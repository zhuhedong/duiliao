/// SSE client for `/ai/analyze-stream`.
///
/// That endpoint is **exempt from the encryption middleware** (see the exempt
/// path list in `app/middleware/encryption.py`), so it is plain JSON over a
/// bearer token — no handshake, no envelope, no request signature. It therefore
/// cannot go through [ApiClient], which would wrap the body and add signature
/// headers the endpoint does not expect.
///
/// Wire format, from `app/api/v1/ai.py`:
/// * Frames are `data: {json}` followed by a blank line. There is no `event:`,
///   no `id:` and no retry directive.
/// * The final frame is the literal `data: [DONE]`, which is **not** JSON and has
///   to be special-cased before decoding.
/// * `stage` takes five values, not three: `status`, `started`, `delta`, `done`
///   and `error`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'api_exception.dart';

/// One decoded SSE event.
class StreamEvent {
  const StreamEvent({required this.stage, required this.data});

  /// `status` | `started` | `delta` | `done` | `error`.
  final String stage;

  final Map<String, dynamic> data;

  /// Token text for a `delta` frame.
  String get delta => (data['delta'] as String?) ?? '';

  String? get message => data['message'] as String?;
  String? get error => data['error'] as String?;

  bool get isDelta => stage == 'delta';
  bool get isDone => stage == 'done';
  bool get isError => stage == 'error';
}

class StreamClient {
  StreamClient({required this.config, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final AppConfig config;
  final http.Client _http;

  /// Stream an AI analysis.
  ///
  /// [accessToken] is required: JWT is the only protection on this route.
  Stream<StreamEvent> analyze({
    required String accessToken,
    String promptId = 'macau_analyst_expert',
    String? period,
    String? provider,
    String? model,
    double temperature = 0.7,
  }) async* {
    final uri = Uri.parse('${config.apiBaseUrl}/ai/analyze-stream');
    final request = http.Request('POST', uri)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Authorization': 'Bearer $accessToken',
      })
      // Plain JSON: this endpoint is not encrypted.
      ..body = jsonEncode({
        'prompt_id': promptId,
        'period': ?period,
        'provider': ?provider,
        'model': ?model,
        'temperature': temperature,
        'fetch_fresh': true,
      });

    final http.StreamedResponse response;
    try {
      response = await _http.send(request);
    } on SocketException catch (e) {
      throw NetworkException('could not reach $uri', cause: e);
    } on http.ClientException catch (e) {
      throw NetworkException(e.message, cause: e);
    }

    if (response.statusCode >= 400) {
      final body = await response.stream.bytesToString();
      Object? decoded;
      try {
        decoded = jsonDecode(body);
      } on FormatException {
        decoded = body;
      }
      throw ApiException(
        extractApiErrorMessage(decoded, 'HTTP ${response.statusCode}'),
        statusCode: response.statusCode,
        code: extractApiErrorCode(decoded),
        payload: decoded,
      );
    }

    // A single `data:` line can be split across network chunks, so the byte
    // stream is decoded and re-split on line boundaries rather than parsed
    // per chunk.
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (line.isEmpty) continue;
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;
      // The terminator is not JSON.
      if (payload == '[DONE]') return;

      Map<String, dynamic> decoded;
      try {
        final value = jsonDecode(payload);
        if (value is! Map<String, dynamic>) continue;
        decoded = value;
      } on FormatException {
        // A malformed frame is skipped rather than aborting a generation that
        // is otherwise progressing.
        continue;
      }
      final stage = (decoded['stage'] as String?) ?? 'delta';
      yield StreamEvent(stage: stage, data: decoded);
      if (stage == 'error') return;
    }
  }

  void dispose() => _http.close();
}
