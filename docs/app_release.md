# Duiliao APP 内部分发

Flutter 工程在 `duiliao_app/`。正式构建必须通过 `--dart-define` 注入
`API_BASE_URL`、`APP_SIGNING_SECRET` 和 `APP_ID`，不能使用默认占位密钥。

Android release 使用 `duiliao_app/android/key.properties` 指定签名文件；该文件和
keystore 不提交到仓库。没有 `key.properties` 时仅允许本地调试构建使用 debug key。

```bash
cd duiliao_app
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi \
  --dart-define=API_BASE_URL=https://example.com/api/v1 \
  --dart-define=APP_SIGNING_SECRET="$APP_SIGNING_SECRET" \
  --dart-define=APP_ID=android-internal
```

服务端提高 `app_android_min_version` 或 `app_ios_min_version` 后，旧版本会在启动时
停留在强制更新页。轮换 `APP_SIGNING_SECRET` 时必须同时发布新包并提高最低版本，
否则旧包会因 `bad_signature` 无法通信。

通知在前台由一分钟轮询驱动，Android 后台任务的最小周期为 15 分钟；iOS 后台执行由
系统调度，打开 APP 时会立即补拉。通知点击使用事件中的深链跳转到对应详情页。
