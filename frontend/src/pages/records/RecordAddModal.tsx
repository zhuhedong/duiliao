import { useState, useMemo, useEffect } from "react";
import { Portal } from "../../components/Portal";
import { Button } from "../../components/ui/button";
import { Spinner } from "../../components/ui/spinner";
import { Alert, AlertDescription } from "../../components/ui/alert";
import { CloseIcon, SparklesIcon, CheckIcon } from "../../components/icons";
import { LOTTERIES } from "../collector/shared";
import { BOSE_COLORS, getBose, getXiao, padNum, XIAO_LIST } from "../../lib/lotteryAttr";
import {
  recordsApi,
  type BettingRecord,
  type CreateRecordPayload,
} from "../../lib/records";
import {
  parseSmartInput,
  getDefaultOdds,
  XIAO_NUMBERS_2026,
} from "./recordsUtils";

interface RecordAddModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: (newRecord: BettingRecord) => void;
  defaultLottery?: string;
  defaultPeriod?: string;
}

const PLAY_TYPES = [
  "正码",
  "特码",
  "平特肖",
  "特肖",
  "2连肖",
  "3连肖",
  "4连肖",
  "5连肖",
  "5 不中",
  "6 不中",
  "7 不中",
  "8 不中",
  "特尾",
  "合肖",
  "二中二",
  "三中三",
];

const PRESETS = [
  { label: "10码正码", text: "18.42.39.27.28.14.32.11.26.16个数5" },
  { label: "特码3码", text: "03 14 26 20元" },
  { label: "生肖包码", text: "龙兔各数5" },
  { label: "连肖复试", text: "龙牛猴鸡兔复试4连个数10" },
  { label: "六不中", text: "02.04.06.08.10.12·6不中个数10" },
];

export function RecordAddModal({
  isOpen,
  onClose,
  onSuccess,
  defaultLottery = "macau",
  defaultPeriod = "",
}: RecordAddModalProps) {
  const [lottery, setLottery] = useState(defaultLottery);
  const [period, setPeriod] = useState(defaultPeriod);
  const [mode, setMode] = useState<"号码单式" | "连肖复试" | "不中码" | "平特肖">("号码单式");
  const [playType, setPlayType] = useState("正码");
  const [rawInput, setRawInput] = useState("");
  const [selectedNumbers, setSelectedNumbers] = useState<string[]>([]);
  const [selectedXiaos, setSelectedXiaos] = useState<string[]>([]);
  const [stakePerNote, setStakePerNote] = useState<number>(5);
  const [multiplier, setMultiplier] = useState<number>(1);
  const [odds, setOdds] = useState<number>(7.0);
  const [note, setNote] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Sync default period
  useEffect(() => {
    if (defaultPeriod && !period) {
      setPeriod(defaultPeriod);
    }
  }, [defaultPeriod, period]);

  // When mode changes, adapt playType and odds
  const handleModeChange = (newMode: "号码单式" | "连肖复试" | "不中码" | "平特肖") => {
    setMode(newMode);
    if (newMode === "连肖复试") {
      setPlayType("3连肖");
      setOdds(getDefaultOdds("3连肖"));
    } else if (newMode === "不中码") {
      setPlayType("5 不中");
      setOdds(getDefaultOdds("5 不中"));
    } else if (newMode === "平特肖") {
      setPlayType("平特肖");
      setOdds(getDefaultOdds("平特肖"));
    } else {
      setPlayType("正码");
      setOdds(getDefaultOdds("正码"));
    }
  };

  // Parse rawInput live
  const parsed = useMemo(() => {
    return parseSmartInput(rawInput, mode, playType);
  }, [rawInput, mode, playType]);

  // When raw input changes, auto-populate stake, multiplier, and selections if parsed
  useEffect(() => {
    if (parsed.stakePerNote !== null && parsed.stakePerNote > 0) {
      setStakePerNote(parsed.stakePerNote);
    }
    if (parsed.multiplier > 0) {
      setMultiplier(parsed.multiplier);
    }
    if (parsed.numbers.length > 0) {
      setSelectedNumbers(parsed.numbers);
    }
    if (parsed.xiaos.length > 0) {
      setSelectedXiaos(parsed.xiaos);
    }
    if (parsed.mode && parsed.mode !== mode) {
      if (
        parsed.mode === "连肖复试" ||
        parsed.mode === "不中码" ||
        parsed.mode === "平特肖" ||
        parsed.mode === "号码单式"
      ) {
        setMode(parsed.mode as any);
      }
    }
  }, [parsed]);

  // Keep odds in sync when playType changes
  const handlePlayTypeChange = (pt: string) => {
    setPlayType(pt);
    const hasMa = selectedXiaos.includes("马") || selectedNumbers.some((n) => getXiao(n) === "马");
    setOdds(getDefaultOdds(pt, hasMa));
  };

  // Toggle single ball in picker
  const toggleNumber = (numStr: string) => {
    setSelectedNumbers((prev) =>
      prev.includes(numStr) ? prev.filter((n) => n !== numStr) : [...prev, numStr].sort()
    );
  };

  // Toggle single zodiac
  const toggleXiao = (x: string) => {
    setSelectedXiaos((prev) =>
      prev.includes(x) ? prev.filter((item) => item !== x) : [...prev, x]
    );
  };

  // Quick number selectors
  const selectByFilter = (filterType: "all" | "clear" | "red" | "blue" | "green" | "big" | "small" | "odd" | "even") => {
    if (filterType === "clear") {
      setSelectedNumbers([]);
      return;
    }
    const all49 = Array.from({ length: 49 }, (_, i) => padNum(i + 1));
    if (filterType === "all") {
      setSelectedNumbers(all49);
      return;
    }
    if (filterType === "red") {
      setSelectedNumbers(all49.filter((n) => getBose(n) === "红"));
      return;
    }
    if (filterType === "blue") {
      setSelectedNumbers(all49.filter((n) => getBose(n) === "蓝"));
      return;
    }
    if (filterType === "green") {
      setSelectedNumbers(all49.filter((n) => getBose(n) === "绿"));
      return;
    }
    if (filterType === "big") {
      setSelectedNumbers(all49.filter((n) => parseInt(n, 10) >= 25));
      return;
    }
    if (filterType === "small") {
      setSelectedNumbers(all49.filter((n) => parseInt(n, 10) < 25));
      return;
    }
    if (filterType === "odd") {
      setSelectedNumbers(all49.filter((n) => parseInt(n, 10) % 2 !== 0));
      return;
    }
    if (filterType === "even") {
      setSelectedNumbers(all49.filter((n) => parseInt(n, 10) % 2 === 0));
      return;
    }
  };

  // Calculate notes count and total amount
  const computedNotesCount = useMemo(() => {
    if (mode === "连肖复试") {
      const kMatch = playType.match(/([2-5])连/);
      const k = kMatch ? parseInt(kMatch[1], 10) : 3;
      const n = selectedXiaos.length;
      if (n < k) return 0;
      let c = 1;
      for (let i = 1; i <= k; i++) c = (c * (n - (k - i))) / i;
      return Math.round(c);
    }
    if (mode === "不中码") {
      return selectedNumbers.length > 0 ? 1 : 0;
    }
    if (mode === "平特肖" || (selectedXiaos.length > 0 && selectedNumbers.length === 0)) {
      return selectedXiaos.length;
    }
    return selectedNumbers.length;
  }, [mode, playType, selectedNumbers, selectedXiaos]);

  const computedTotalAmount = computedNotesCount * stakePerNote * multiplier;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    const periodTrimmed = period.trim();
    if (!periodTrimmed) {
      setError("请填写或选择期号");
      return;
    }

    if (computedNotesCount <= 0) {
      setError("请至少选择或识别 1 个有效号码/生肖");
      return;
    }

    setLoading(true);
    try {
      const payload: CreateRecordPayload = {
        lottery,
        period: periodTrimmed,
        mode,
        play_type: playType,
        numbers: selectedNumbers,
        xiaos: selectedXiaos,
        stake_per_note: stakePerNote,
        multiplier,
        notes_count: computedNotesCount,
        total_amount: computedTotalAmount,
        odds,
        raw_input: rawInput,
        note: note.trim() || undefined,
        source_badge: rawInput ? "智能识别录入" : "手工录入",
      };

      const res = await recordsApi.create(payload);
      if (res.ok && res.record) {
        onSuccess(res.record);
        onClose();
      } else {
        setError("录入失败，请检查参数");
      }
    } catch (err: any) {
      setError(err?.message || "录入记录失败，请重试");
    } finally {
      setLoading(false);
    }
  };

  if (!isOpen) return null;

  return (
    <Portal onClose={onClose}>
      <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-6 bg-slate-900/50 dark:bg-black/70 animate-fadeIn backdrop-blur-sm">
        <div className="w-full max-w-3xl max-h-[92vh] glass-card rounded-3xl animate-fadeIn flex flex-col overflow-hidden shadow-2xl border border-slate-200/50 dark:border-white/10 bg-white dark:bg-slate-900">
          {/* Header */}
          <div className="flex items-center justify-between border-b border-slate-200/50 dark:border-white/10 px-6 py-4 shrink-0">
            <div>
              <h3 className="text-lg font-bold text-slate-900 dark:text-white flex items-center gap-2">
                <SparklesIcon size={20} className="text-primary" />
                <span>新增投注记录</span>
              </h3>
              <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
                支持智能文本识别、一键生肖包码与盘口注数自动测算
              </p>
            </div>
            <button
              onClick={onClose}
              className="p-2 rounded-xl text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 hover:bg-slate-100 dark:hover:bg-white/5 transition-colors"
            >
              <CloseIcon size={20} />
            </button>
          </div>

          {/* Body */}
          <div className="overflow-y-auto px-6 py-5 space-y-6 flex-1">
            {error && (
              <Alert variant="error">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {/* Mode Switcher */}
            <div>
              <label className="block text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider mb-2">
                录入模式
              </label>
              <div className="grid grid-cols-4 gap-2 p-1 rounded-2xl bg-slate-100 dark:bg-white/5">
                {(["号码单式", "连肖复试", "不中码", "平特肖"] as const).map((m) => (
                  <button
                    key={m}
                    type="button"
                    onClick={() => handleModeChange(m)}
                    className={`py-2 px-3 text-xs font-semibold rounded-xl transition-all cursor-pointer ${
                      mode === m
                        ? "bg-white dark:bg-primary text-slate-900 dark:text-white shadow-sm"
                        : "text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white"
                    }`}
                  >
                    {m}
                  </button>
                ))}
              </div>
            </div>

            {/* Lottery & Period */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider mb-2">
                  彩种
                </label>
                <div className="flex gap-2 flex-wrap">
                  {LOTTERIES.map((l) => (
                    <button
                      key={l.value}
                      type="button"
                      onClick={() => setLottery(l.value)}
                      className={`px-3.5 py-1.5 text-xs font-medium rounded-xl transition-all ${
                        lottery === l.value
                          ? "bg-primary text-white shadow-md shadow-primary/25"
                          : "glass-subtle text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-white/10"
                      }`}
                    >
                      {l.label}
                    </button>
                  ))}
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider mb-2">
                  期号
                </label>
                <div className="flex items-center gap-2">
                  <input
                    type="text"
                    value={period}
                    onChange={(e) => setPeriod(e.target.value)}
                    placeholder="如 2026277"
                    className="flex-1 px-3.5 py-2 text-sm rounded-xl border border-slate-200 dark:border-white/10 bg-slate-50/50 dark:bg-white/5 focus:outline-none focus:ring-2 focus:ring-primary/50 text-slate-900 dark:text-white font-mono"
                  />
                  {period && (
                    <button
                      type="button"
                      onClick={() => {
                        const num = parseInt(period, 10);
                        if (!isNaN(num)) setPeriod(String(num + 1));
                      }}
                      className="px-2.5 py-2 text-xs rounded-xl glass-subtle text-slate-600 dark:text-slate-300 hover:bg-primary/10 hover:text-primary transition-colors"
                      title="下期 (+1)"
                    >
                      +1期
                    </button>
                  )}
                </div>
              </div>
            </div>

            {/* Smart Text Entry */}
            <div>
              <div className="flex items-center justify-between mb-2">
                <label className="text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider flex items-center gap-1.5">
                  <SparklesIcon size={14} className="text-primary" />
                  智能文本录入（支持空格/逗号/点号分隔、自动识别金额）
                </label>
                <div className="text-[11px] text-slate-400 dark:text-slate-500">
                  例：18.42.39个数5 · 龙兔各数5 · 龙牛猴鸡兔复试4连个数10
                </div>
              </div>

              <textarea
                rows={2}
                value={rawInput}
                onChange={(e) => setRawInput(e.target.value)}
                placeholder="粘贴或输入号码文本，例如：18.42.39.27.28.14.32.11.26.16个数5"
                className="w-full px-4 py-3 text-sm rounded-2xl border border-slate-200 dark:border-white/10 bg-slate-50/50 dark:bg-white/5 focus:outline-none focus:ring-2 focus:ring-primary/50 text-slate-900 dark:text-white font-mono placeholder:text-slate-400 leading-relaxed resize-none"
              />

              {/* Sample Quick Chips */}
              <div className="flex items-center gap-2 mt-2 flex-wrap">
                <span className="text-[11px] text-slate-400">快速填入示例:</span>
                {PRESETS.map((p) => (
                  <button
                    key={p.label}
                    type="button"
                    onClick={() => setRawInput(p.text)}
                    className="px-2.5 py-1 text-[11px] rounded-lg bg-slate-100 dark:bg-white/5 text-slate-600 dark:text-slate-400 hover:text-primary hover:bg-primary/10 transition-colors"
                  >
                    {p.label}
                  </button>
                ))}
              </div>
            </div>

            {/* Live Recognition Preview */}
            <div className="p-4 rounded-2xl glass-panel border border-slate-200/60 dark:border-white/10 space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-slate-900 dark:text-white flex items-center gap-1.5">
                  <CheckIcon size={14} className="text-emerald-500" />
                  当前识别内容与注单预览
                </span>
                <span className="text-xs px-2.5 py-0.5 rounded-full bg-emerald-500/15 text-emerald-600 dark:text-emerald-400 font-medium">
                  已识别 {selectedNumbers.length > 0 ? `${selectedNumbers.length} 个号码` : `${selectedXiaos.length} 个生肖`}
                </span>
              </div>

              {/* Numbers Balls */}
              {selectedNumbers.length > 0 && (
                <div className="flex flex-wrap gap-2 pt-1">
                  {selectedNumbers.map((n) => {
                    const bColor = BOSE_COLORS[getBose(n)] || { bg: "#64748b" };
                    return (
                      <span
                        key={n}
                        className="inline-flex items-center justify-center w-8 h-8 rounded-full text-xs font-bold text-white shadow-sm ring-2 ring-white/20 select-none"
                        style={{ backgroundColor: bColor.bg }}
                        title={`${n} (${getBose(n)}波 · ${getXiao(n)})`}
                      >
                        {n}
                      </span>
                    );
                  })}
                </div>
              )}

              {/* Zodiacs Chips */}
              {selectedXiaos.length > 0 && (
                <div className="flex flex-wrap gap-2 pt-1">
                  {selectedXiaos.map((x) => (
                    <span
                      key={x}
                      className="px-3 py-1 rounded-xl text-xs font-bold bg-primary/15 text-primary border border-primary/30"
                    >
                      {x}
                    </span>
                  ))}
                </div>
              )}

              {/* Financial Calculation Bar */}
              <div className="pt-2 border-t border-slate-200/50 dark:border-white/10 flex items-center justify-between text-xs">
                <div className="text-slate-600 dark:text-slate-300">
                  共 <b className="text-slate-900 dark:text-white font-mono text-sm">{computedNotesCount}</b> 注 ×
                  单注 <b className="text-slate-900 dark:text-white font-mono text-sm">¥{stakePerNote}</b> ×
                  <b className="text-slate-900 dark:text-white font-mono text-sm">{multiplier}</b> 倍
                </div>
                <div className="text-slate-500 dark:text-slate-400">
                  合计：
                  <span className="text-lg font-bold text-primary font-mono ml-1">
                    ¥{computedTotalAmount}
                  </span>
                </div>
              </div>
            </div>

            {/* Play Type, Stake, Multiplier & Odds Settings */}
            <div className="grid grid-cols-1 sm:grid-cols-4 gap-4">
              <div>
                <label className="block text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider mb-2">
                  玩法
                </label>
                <select
                  value={playType}
                  onChange={(e) => handlePlayTypeChange(e.target.value)}
                  className="w-full px-3 py-2 text-xs rounded-xl border border-slate-200 dark:border-white/10 bg-slate-50/50 dark:bg-white/5 focus:outline-none focus:ring-2 focus:ring-primary/50 text-slate-900 dark:text-white font-medium"
                >
                  {PLAY_TYPES.map((pt) => (
                    <option key={pt} value={pt} className="bg-white dark:bg-slate-800 text-slate-900 dark:text-white">
                      {pt}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider mb-2">
                  单注金额 (¥)
                </label>
                <div className="flex items-center gap-1">
                  {[2, 5, 10, 20].map((v) => (
                    <button
                      key={v}
                      type="button"
                      onClick={() => setStakePerNote(v)}
                      className={`px-2 py-1 text-xs rounded-lg ${
                        stakePerNote === v
                          ? "bg-primary text-white font-bold"
                          : "bg-slate-100 dark:bg-white/5 text-slate-600 dark:text-slate-400"
                      }`}
                    >
                      {v}
                    </button>
                  ))}
                  <input
                    type="number"
                    min={1}
                    value={stakePerNote}
                    onChange={(e) => setStakePerNote(Math.max(1, parseInt(e.target.value, 10) || 1))}
                    className="w-16 px-2 py-1 text-xs rounded-lg border border-slate-200 dark:border-white/10 bg-slate-50/50 dark:bg-white/5 text-slate-900 dark:text-white font-mono text-center"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider mb-2">
                  倍数
                </label>
                <div className="flex items-center gap-1">
                  {[1, 2, 5].map((m) => (
                    <button
                      key={m}
                      type="button"
                      onClick={() => setMultiplier(m)}
                      className={`px-2.5 py-1 text-xs rounded-lg ${
                        multiplier === m
                          ? "bg-primary text-white font-bold"
                          : "bg-slate-100 dark:bg-white/5 text-slate-600 dark:text-slate-400"
                      }`}
                    >
                      {m}倍
                    </button>
                  ))}
                  <input
                    type="number"
                    min={1}
                    value={multiplier}
                    onChange={(e) => setMultiplier(Math.max(1, parseInt(e.target.value, 10) || 1))}
                    className="w-14 px-2 py-1 text-xs rounded-lg border border-slate-200 dark:border-white/10 bg-slate-50/50 dark:bg-white/5 text-slate-900 dark:text-white font-mono text-center"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider mb-2">
                  结算赔率 (1:x)
                </label>
                <input
                  type="number"
                  step="0.1"
                  min="0.1"
                  value={odds}
                  onChange={(e) => setOdds(parseFloat(e.target.value) || 1.0)}
                  className="w-full px-3 py-2 text-xs rounded-xl border border-slate-200 dark:border-white/10 bg-slate-50/50 dark:bg-white/5 focus:outline-none focus:ring-2 focus:ring-primary/50 text-slate-900 dark:text-white font-mono"
                />
              </div>
            </div>

            {/* Interactive Number Picker (01-49) */}
            <div className="space-y-2">
              <div className="flex items-center justify-between flex-wrap gap-2">
                <label className="text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider">
                  手动选码 (49码网格 · 已选 {selectedNumbers.length} 码)
                </label>
                <div className="flex items-center gap-1.5 flex-wrap">
                  {(
                    [
                      { id: "all", label: "全选" },
                      { id: "clear", label: "清空" },
                      { id: "red", label: "红波" },
                      { id: "blue", label: "蓝波" },
                      { id: "green", label: "绿波" },
                      { id: "big", label: "大号" },
                      { id: "small", label: "小号" },
                      { id: "odd", label: "单数" },
                      { id: "even", label: "双数" },
                    ] as const
                  ).map((btn) => (
                    <button
                      key={btn.id}
                      type="button"
                      onClick={() => selectByFilter(btn.id)}
                      className="px-2 py-0.5 text-[11px] rounded-md bg-slate-100 dark:bg-white/5 hover:bg-slate-200 dark:hover:bg-white/10 text-slate-600 dark:text-slate-400 transition-colors"
                    >
                      {btn.label}
                    </button>
                  ))}
                </div>
              </div>

              <div className="grid grid-cols-7 sm:grid-cols-10 gap-1.5 p-3 rounded-2xl bg-slate-50/70 dark:bg-white/[0.03] border border-slate-200/50 dark:border-white/5">
                {Array.from({ length: 49 }, (_, i) => padNum(i + 1)).map((numStr) => {
                  const isSelected = selectedNumbers.includes(numStr);
                  const bColor = BOSE_COLORS[getBose(numStr)];
                  return (
                    <button
                      key={numStr}
                      type="button"
                      onClick={() => toggleNumber(numStr)}
                      className={`h-8 rounded-lg text-xs font-mono font-bold flex items-center justify-center transition-all ${
                        isSelected
                          ? "text-white shadow-md ring-2 ring-white/50 scale-105"
                          : "text-slate-700 dark:text-slate-300 hover:bg-slate-200/60 dark:hover:bg-white/10"
                      }`}
                      style={{
                        backgroundColor: isSelected ? bColor?.bg : undefined,
                        borderColor: !isSelected ? bColor?.border : undefined,
                      }}
                    >
                      {numStr}
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Interactive Zodiac Picker (12肖) */}
            <div className="space-y-2">
              <label className="text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider">
                生肖速选 (12生肖 · 2026丙午年)
              </label>
              <div className="grid grid-cols-6 sm:grid-cols-12 gap-1.5">
                {XIAO_LIST.map((x) => {
                  const isSelected = selectedXiaos.includes(x);
                  return (
                    <button
                      key={x}
                      type="button"
                      onClick={() => toggleXiao(x)}
                      className={`py-2 px-1 text-xs font-bold rounded-xl transition-all flex flex-col items-center gap-0.5 ${
                        isSelected
                          ? "bg-primary text-white shadow-md shadow-primary/25 ring-2 ring-primary/40"
                          : "bg-slate-100 dark:bg-white/5 text-slate-700 dark:text-slate-300 hover:bg-slate-200/70 dark:hover:bg-white/10"
                      }`}
                    >
                      <span>{x}</span>
                      <span className="text-[9px] opacity-70">
                        {XIAO_NUMBERS_2026[x]?.[0]}..
                      </span>
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Note & Remarks */}
            <div>
              <label className="block text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider mb-2">
                备注说明（可选）
              </label>
              <input
                type="text"
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder="例如：AI共识TOP3号码、平特冷热组合等"
                className="w-full px-3.5 py-2 text-xs rounded-xl border border-slate-200 dark:border-white/10 bg-slate-50/50 dark:bg-white/5 focus:outline-none focus:ring-2 focus:ring-primary/50 text-slate-900 dark:text-white"
              />
            </div>
          </div>

          {/* Footer */}
          <div className="flex items-center justify-between border-t border-slate-200/50 dark:border-white/10 px-6 py-4 bg-slate-50/50 dark:bg-white/[0.02] shrink-0">
            <div className="text-xs text-slate-500 dark:text-slate-400">
              总计：
              <span className="text-base font-bold text-slate-900 dark:text-white font-mono ml-1">
                {computedNotesCount} 注 · ¥{computedTotalAmount}
              </span>
            </div>
            <div className="flex items-center gap-3">
              <Button type="button" variant="outline" onClick={onClose} disabled={loading}>
                取消
              </Button>
              <Button type="button" onClick={handleSubmit} disabled={loading} className="gap-2">
                {loading && <Spinner className="size-4" />}
                <span>确认录入</span>
              </Button>
            </div>
          </div>
        </div>
      </div>
    </Portal>
  );
}
