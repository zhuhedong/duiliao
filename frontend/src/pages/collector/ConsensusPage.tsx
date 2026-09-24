import React, { useCallback, useEffect, useMemo, useState } from "react";
import { Badge } from "@appica/ui-react/badge";
import { Alert, AlertDescription } from "@appica/ui-react/alert";
import { ApiError } from "../../lib/api";
import {
  collectorApi,
  LOTTERY_LABEL,
  type ComparisonItem,
  type ConsensusGroup,
  type ConsensusResult,
  type ConsensusTallyItem,
  type DrawRow,
  type Lottery,
  type PeriodComparisonResult,
  type PredAtom,
  type RuleRow,
} from "../../lib/collector";
import {
  LOTTERIES,
  PageWorkspace,
  Select,
  TextInput,
  Toolbar,
  playLabel,
  useCanWrite,
  SegmentedTabs,
} from "./shared";
import {
  BOSE_COLORS,
  WUXING_COLORS,
  XIAO_LIST,
  ensureDrawDetails,
  getBose,
  getJiaye,
  getOdd,
  getSize,
  getWuxing,
  getXiao,
  padNum,
} from "../../lib/lotteryAttr";

function atomsText(list: PredAtom[] | null): string {
  if (!list || !list.length) return "—";
  return list.map((a) => a.value).join(" ");
}

/** Human-readable formatting of judge hit detail (replaces raw JSON) */
function formatHitDetail(item: ComparisonItem, draw?: DrawRow | null): {
  summary: string;
  tag?: string;
  rawJson?: Record<string, unknown> | null;
} {
  if (item.status === "pending") {
    return { summary: "待官方开奖后自动比对", tag: "待对奖" };
  }
  const d = item.hit_detail;
  if (!d) {
    if (item.status === "hit") return { summary: "官方判定命中" };
    return { summary: "官方判定未中" };
  }

  if (d.missing_period) {
    return {
      summary: (d.reason as string) || "已确认缺期，默认按未中计入统计",
      tag: "缺期",
      rawJson: d,
    };
  }

  if (item.status === "hit") {
    if (Array.isArray(d.matched_balls) && d.matched_balls.length > 0) {
      const parts = d.matched_balls.map((b: any) => {
        const posName =
          b.position === "tema"
            ? "特码"
            : b.position
            ? b.position.replace(/^z/, "正") + "码"
            : "";
        return `${b.xiao || ""}${b.num ? " " + b.num : ""}${posName ? ` (${posName})` : ""}`.trim();
      });
      return { summary: `命中落球：${parts.join("、")}`, rawJson: d };
    }
    if (Array.isArray(d.inter) && d.inter.length > 0) {
      return { summary: `命中预测项：${d.inter.join("、")}`, rawJson: d };
    }
    if (d.tema && d.pred) {
      return { summary: `命中特码：${d.tema}`, rawJson: d };
    }
    if (d.explanation) {
      return { summary: String(d.explanation), rawJson: d };
    }
    return { summary: "官方判定命中", rawJson: d };
  }

  if (item.status === "miss") {
    if (d.tema) {
      return {
        summary: `未中（特码开出 ${d.tema}${d.tema_xiao ? "·" + d.tema_xiao : ""}）`,
        rawJson: d,
      };
    }
    if (d.tema_xiao) {
      return { summary: `未中（特肖开出 ${d.tema_xiao}）`, rawJson: d };
    }
    if (d.tema_bose) {
      return { summary: `未中（特波开出 ${d.tema_bose}波）`, rawJson: d };
    }
    if (draw) {
      const t = draw.tema_detail;
      if (item.play_type.startsWith("tema_") && t) {
        return { summary: `未中（特码开出 ${t.num} ${t.xiao}）`, rawJson: d };
      }
    }
    if (d.explanation) {
      return { summary: String(d.explanation), rawJson: d };
    }
    return { summary: "未中", rawJson: d };
  }

  if (item.status === "conflict") {
    return { summary: "来源标榜中奖，但经官方开奖核算判定未命中！", tag: "虚假报喜", rawJson: d };
  }

  return { summary: "—", rawJson: d };
}

/** Render predicted atoms with winning hit highlight */
function PredAtomsBadgeList({ item }: { item: ComparisonItem }) {
  const d = item.hit_detail;
  const hitValues = useMemo(() => {
    const s = new Set<string>();
    if (item.status === "hit" && d) {
      if (Array.isArray(d.inter)) {
        d.inter.forEach((v: any) => s.add(String(v)));
      }
      if (Array.isArray(d.matched_balls)) {
        d.matched_balls.forEach((b: any) => {
          if (b.num) s.add(padNum(b.num));
          if (b.xiao) s.add(String(b.xiao));
        });
      }
      if (d.tema) s.add(padNum(String(d.tema)));
      if (d.tema_xiao) s.add(String(d.tema_xiao));
    }
    return s;
  }, [item.status, d]);

  return (
    <div className="flex gap-1.5 flex-wrap items-center">
      {item.preds.map((p, i) => {
        const val = p.value;
        const isHitVal = hitValues.has(val) || hitValues.has(padNum(val));
        const isNum = /^\d+$/.test(val);
        const bColor = isNum ? BOSE_COLORS[getBose(val)] : undefined;

        return (
          <span
            key={i}
            className={`inline-flex items-center gap-1 px-2.5 py-0.5 rounded-lg text-xs font-semibold transition-all ${
              isHitVal
                ? "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300 border-2 border-emerald-500 shadow-xs ring-2 ring-emerald-500/20"
                : "glass-subtle text-slate-700 dark:text-slate-300"
            }`}
            title={isHitVal ? "🎯 该预测项命中官方开奖！" : undefined}
          >
            {isNum && bColor && (
              <span
                className="w-2 h-2 rounded-full shrink-0"
                style={{ backgroundColor: bColor.bg }}
              />
            )}
            <span>{val}</span>
            {isHitVal && (
              <span className="text-[11px] font-bold text-emerald-600 dark:text-emerald-400">
                ✓
              </span>
            )}
          </span>
        );
      })}
    </div>
  );
}

/** Rich visual rendering of PredAtom list in consensus tables */
function ConsensusAtomDisplay({ atoms }: { atoms: PredAtom[] }) {
  if (!atoms || atoms.length === 0) return <span>—</span>;
  return (
    <div className="flex gap-1.5 flex-wrap items-center">
      {atoms.map((a, i) => {
        const isNum = /^\d+$/.test(a.value);
        const bColor = isNum ? BOSE_COLORS[getBose(a.value)] : undefined;
        return (
          <span
            key={i}
            className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-lg text-xs font-semibold glass-subtle text-slate-800 dark:text-slate-200 shadow-2xs"
          >
            {isNum && bColor && (
              <span
                className="w-2 h-2 rounded-full shrink-0"
                style={{ backgroundColor: bColor.bg }}
              />
            )}
            <span>{a.value}</span>
          </span>
        );
      })}
    </div>
  );
}

/** Collapsible supporters chip list */
function VotersChipList({ sources }: { sources: string[] }) {
  const [expanded, setExpanded] = useState(false);
  const maxShown = 4;
  const visible = expanded ? sources : sources.slice(0, maxShown);
  const hasMore = sources.length > maxShown;

  return (
    <div className="flex gap-1.5 flex-wrap items-center">
      {visible.map((src, i) => (
        <span
          key={i}
          className="inline-flex items-center px-2 py-0.5 rounded-md text-xs glass-subtle text-slate-600 dark:text-slate-300"
        >
          {src}
        </span>
      ))}
      {hasMore && (
        <button
          onClick={() => setExpanded(!expanded)}
          className="px-1.5 py-0.5 text-xs text-primary font-medium hover:underline cursor-pointer transition-colors"
        >
          {expanded ? "收起" : `+${sources.length - maxShown} 更多`}
        </button>
      )}
    </div>
  );
}

export interface FrequencyItem {
  value: string;
  kind: "num" | "xiao";
  count: number;
  percentage: number;
  sources: { id: string; name: string; groupKey?: string }[];
  isHit: boolean;
  bose?: "红" | "蓝" | "绿";
  xiao?: string;
  wuxing?: string | null;
  size?: "大" | "小";
  odd?: "单" | "双";
  jiaye?: "家" | "野";
  sampleNums?: string[];
}

function RankBadge({ rank }: { rank: number }) {
  if (rank === 1) {
    return (
      <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg text-xs font-black bg-gradient-to-r from-amber-400 to-amber-500 text-slate-950 shadow-xs border border-amber-300">
        🥇 1st
      </span>
    );
  }
  if (rank === 2) {
    return (
      <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg text-xs font-extrabold glass-subtle text-slate-700 dark:text-slate-200 shadow-2xs">
        🥈 2nd
      </span>
    );
  }
  if (rank === 3) {
    return (
      <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg text-xs font-extrabold bg-gradient-to-r from-orange-300 to-amber-600 text-slate-950 shadow-2xs border border-orange-400">
        🥉 3rd
      </span>
    );
  }
  return (
    <span className="inline-flex items-center justify-center w-7 h-7 rounded-md font-mono text-xs font-bold text-slate-500 dark:text-slate-400 bg-slate-500/10 dark:bg-white/5">
      #{rank}
    </span>
  );
}

function TemaBall({ num, bose }: { num: string; bose?: "红" | "蓝" | "绿" }) {
  const colorCfg = BOSE_COLORS[bose || "红"] || BOSE_COLORS["红"];
  return (
    <span
      className="inline-grid place-items-center w-8 h-8 rounded-full text-white text-sm font-black font-mono shadow-xs transition-transform hover:scale-110 shrink-0"
      style={{ backgroundColor: colorCfg.bg }}
      title={`${num} (${bose || ""}波)`}
    >
      {num}
    </span>
  );
}

function TexiaoBadge({ xiao, jiaye }: { xiao: string; jiaye?: "家" | "野" }) {
  return (
    <div className="flex items-center gap-2 shrink-0">
      <span
        className="inline-grid place-items-center w-8 h-8 rounded-xl bg-gradient-to-br from-violet-500 to-fuchsia-500 text-white text-base font-black shadow-xs"
        title={`特肖 · ${xiao}`}
      >
        {xiao}
      </span>
      <div className="flex flex-col">
        <span className="font-bold text-sm text-slate-900 dark:text-white leading-tight">
          {xiao}肖
        </span>
        {jiaye && (
          <span className="text-[10px] text-slate-400 font-medium">
            {jiaye === "家" ? "家禽" : "野兽"}
          </span>
        )}
      </div>
    </div>
  );
}

function FrequencyProgressBar({
  count,
  pct,
  isTop,
  isHit,
}: {
  count: number;
  pct: number;
  isTop: boolean;
  isHit: boolean;
}) {
  return (
    <div className="flex flex-col gap-1 w-full min-w-[120px]">
      <div className="flex items-center justify-between text-xs font-medium">
        <span className="font-bold font-mono text-slate-900 dark:text-white flex items-center gap-1">
          <span>{count}</span>
          <span className="text-[11px] text-slate-400 font-normal">次</span>
        </span>
        <span
          className={`font-mono text-xs font-semibold ${
            isHit
              ? "text-emerald-600 dark:text-emerald-400"
              : isTop
              ? "text-amber-600 dark:text-amber-400"
              : "text-slate-500 dark:text-slate-400"
          }`}
        >
          {pct.toFixed(1)}%
        </span>
      </div>
      <div className="w-full bg-slate-500/10 dark:bg-white/5 rounded-full h-2 overflow-hidden shadow-inner">
        <div
          className={`h-full rounded-full transition-all duration-500 ${
            isHit
              ? "bg-gradient-to-r from-emerald-400 to-teal-500"
              : isTop
              ? "bg-gradient-to-r from-amber-400 to-primary"
              : "bg-primary/80"
          }`}
          style={{ width: `${Math.min(pct, 100)}%` }}
        />
      </div>
    </div>
  );
}

function HitStatusBadge({
  isHit,
  hasOfficialDraw,
  kind,
}: {
  isHit: boolean;
  hasOfficialDraw: boolean;
  kind: "tema" | "texiao";
}) {
  if (!hasOfficialDraw) {
    return (
      <Badge size="sm" variant="soft" className="text-[11px]">
        ⏳ 待开奖
      </Badge>
    );
  }
  if (isHit) {
    return (
      <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-bold bg-emerald-500 text-white shadow-xs animate-bounce">
        🎯 命中{kind === "tema" ? "特码" : "特肖"}
      </span>
    );
  }
  return <span className="text-xs text-slate-400">未开出</span>;
}

export function CollectorConsensusPage() {
  const canWrite = useCanWrite();
  const [activeTab, setActiveTab] = useState<"frequency" | "comparison" | "consensus">("frequency");
  const [lottery, setLottery] = useState<Lottery>("macau");
  const [period, setPeriod] = useState("");
  const [loading, setLoading] = useState(false);
  const [rejudging, setRejudging] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Filters
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const [playFilter, setPlayFilter] = useState<string>("");
  const [sourceKeyword, setSourceKeyword] = useState<string>("");
  const [freqKeyword, setFreqKeyword] = useState<string>("");
  const [freqMinVotes, setFreqMinVotes] = useState<number>(0);

  // Data
  const [rules, setRules] = useState<RuleRow[]>([]);
  const [comparison, setComparison] = useState<PeriodComparisonResult | null>(null);
  const [consensusData, setConsensusData] = useState<ConsensusResult | null>(null);
  const [expandedJsonId, setExpandedJsonId] = useState<number | null>(null);

  // Load live play rules catalog
  useEffect(() => {
    collectorApi.rules().then(setRules).catch(() => undefined);
  }, []);

  // Primary query function
  const executeQuery = useCallback(
    async (lot: Lottery, targetPeriod: string) => {
      const p = targetPeriod.trim();
      if (!p) return;
      setLoading(true);
      setError(null);
      try {
        // Query comparison and consensus concurrently to keep both tabs fresh
        const [compRes, consRes] = await Promise.allSettled([
          collectorApi.getComparison(lot, p),
          collectorApi.consensus(lot, p, playFilter || undefined),
        ]);

        if (compRes.status === "fulfilled") {
          setComparison(compRes.value);
        } else {
          setComparison(null);
        }

        if (consRes.status === "fulfilled") {
          setConsensusData(consRes.value);
        } else {
          setConsensusData(null);
        }

        if (compRes.status === "rejected" && consRes.status === "rejected") {
          const err = compRes.reason;
          setError(err instanceof ApiError ? err.message : "数据查询失败");
        }
      } catch (err) {
        setError(err instanceof ApiError ? err.message : "查询失败");
      } finally {
        setLoading(false);
      }
    },
    [playFilter]
  );

  // Initial mount & lottery switch: Auto-fetch latest period for immediate display
  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const latest = await collectorApi.listDraws(lottery, 1, 0);
        if (active && latest.items && latest.items.length > 0) {
          const latestPeriod = latest.items[0].period;
          setPeriod(latestPeriod);
          void executeQuery(lottery, latestPeriod);
        }
      } catch {
        // Ignore fallback
      }
    })();
    return () => {
      active = false;
    };
  }, [lottery, executeQuery]);

  // Stepper: Previous Period
  const handlePrevPeriod = () => {
    if (!period.trim()) return;
    const num = parseInt(period, 10);
    if (!isNaN(num)) {
      const prev = String(num - 1);
      setPeriod(prev);
      void executeQuery(lottery, prev);
    }
  };

  // Stepper: Next Period
  const handleNextPeriod = () => {
    if (!period.trim()) return;
    const num = parseInt(period, 10);
    if (!isNaN(num)) {
      const next = String(num + 1);
      setPeriod(next);
      void executeQuery(lottery, next);
    }
  };

  // Stepper: Latest Period
  const handleLatestPeriod = async () => {
    try {
      const latest = await collectorApi.listDraws(lottery, 1, 0);
      if (latest.items && latest.items.length > 0) {
        const latestPeriod = latest.items[0].period;
        setPeriod(latestPeriod);
        void executeQuery(lottery, latestPeriod);
      }
    } catch {
      // ignore
    }
  };

  const handleRejudge = async () => {
    if (!period.trim()) return;
    setRejudging(true);
    setError(null);
    try {
      const res = await collectorApi.rejudgeComparison(lottery, period.trim());
      setComparison(res);
      // Also refresh consensus to reflect newly judged status
      const cons = await collectorApi.consensus(lottery, period.trim(), playFilter || undefined);
      setConsensusData(cons);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "重新对奖计算失败");
    } finally {
      setRejudging(false);
    }
  };

  const playOptions = useMemo(
    () => [
      { value: "", label: "全部玩法" },
      ...rules.map((r) => ({ value: r.play_type, label: r.name })),
    ],
    [rules]
  );

  // Tab 1 filtered predictions
  const filteredComparisonItems = useMemo(() => {
    return (comparison?.items ?? []).filter((item: ComparisonItem) => {
      if (statusFilter !== "all" && item.status !== statusFilter) return false;
      if (playFilter && item.play_type !== playFilter) return false;
      if (sourceKeyword.trim()) {
        const kw = sourceKeyword.trim().toLowerCase();
        const matchName = item.source_name.toLowerCase().includes(kw);
        const matchId = item.source_id.toLowerCase().includes(kw);
        if (!matchName && !matchId) return false;
      }
      return true;
    });
  }, [comparison, statusFilter, playFilter, sourceKeyword]);

  // Unified official draw row across both tabs
  const officialDraw = comparison?.draw || consensusData?.draw;

  // Frequency aggregation for 特码 (tema_n) and 特肖 (texiao)
  const frequencyStats = useMemo(() => {
    const items = comparison?.items ?? [];

    // --- 1. 特码 (tema_n) ---
    const temaItems = items.filter(
      (it) => (it.play_type === "tema_n" || it.play_type === "特码") && it.claimed_status !== "missing"
    );
    const uniqueTemaSourceKeys = new Set(
      temaItems.map((it) => `${it.source_id}:${it.group_key || ""}`)
    );
    const totalTemaSources = uniqueTemaSourceKeys.size;

    const temaMap = new Map<
      string,
      { count: number; sources: { id: string; name: string; groupKey?: string }[] }
    >();

    for (const it of temaItems) {
      const srcObj = { id: it.source_id, name: it.source_name, groupKey: it.group_key };
      const seenNums = new Set<string>();
      for (const atom of it.preds) {
        if (!atom.value) continue;
        const pNum = padNum(atom.value);
        const nInt = parseInt(pNum, 10);
        if (nInt >= 1 && nInt <= 49) {
          seenNums.add(pNum);
        }
      }
      for (const num of seenNums) {
        let entry = temaMap.get(num);
        if (!entry) {
          entry = { count: 0, sources: [] };
          temaMap.set(num, entry);
        }
        entry.count += 1;
        entry.sources.push(srcObj);
      }
    }

    // --- 2. 特肖 (texiao) ---
    const texiaoItems = items.filter(
      (it) => (it.play_type === "texiao" || it.play_type === "特肖") && it.claimed_status !== "missing"
    );
    const uniqueTexiaoSourceKeys = new Set(
      texiaoItems.map((it) => `${it.source_id}:${it.group_key || ""}`)
    );
    const totalTexiaoSources = uniqueTexiaoSourceKeys.size;

    const texiaoMap = new Map<
      string,
      { count: number; sources: { id: string; name: string; groupKey?: string }[] }
    >();

    for (const it of texiaoItems) {
      const srcObj = { id: it.source_id, name: it.source_name, groupKey: it.group_key };
      const seenXiaos = new Set<string>();
      for (const atom of it.preds) {
        const x = atom.value ? atom.value.trim() : "";
        if (x && (XIAO_LIST as readonly string[]).includes(x)) {
          seenXiaos.add(x);
        }
      }
      for (const x of seenXiaos) {
        let entry = texiaoMap.get(x);
        if (!entry) {
          entry = { count: 0, sources: [] };
          texiaoMap.set(x, entry);
        }
        entry.count += 1;
        entry.sources.push(srcObj);
      }
    }

    // Fallback if comparison has no items but consensusData has atom_tallies
    if (totalTemaSources === 0 && consensusData?.atom_tallies?.tema_n?.length) {
      for (const at of consensusData.atom_tallies.tema_n) {
        const pNum = padNum(at.value);
        temaMap.set(pNum, {
          count: at.votes,
          sources: at.sources.map((s) => ({ id: s, name: s })),
        });
      }
    }
    if (totalTexiaoSources === 0 && consensusData?.atom_tallies?.texiao?.length) {
      for (const at of consensusData.atom_tallies.texiao) {
        texiaoMap.set(at.value, {
          count: at.votes,
          sources: at.sources.map((s) => ({ id: s, name: s })),
        });
      }
    }

    // Official draw target values
    const drawnDetails = officialDraw ? ensureDrawDetails(officialDraw) : null;
    const drawnTemaNum = drawnDetails ? padNum(drawnDetails.temaDetail.num) : null;
    const drawnTemaXiao = drawnDetails ? drawnDetails.temaDetail.xiao : null;

    const resolvedTotalTema =
      totalTemaSources ||
      (consensusData?.atom_tallies?.tema_n && consensusData.atom_tallies.tema_n.length > 0
        ? Math.max(...consensusData.atom_tallies.tema_n.map((t) => t.votes), 1)
        : 1);
    const resolvedTotalTexiao =
      totalTexiaoSources ||
      (consensusData?.atom_tallies?.texiao && consensusData.atom_tallies.texiao.length > 0
        ? Math.max(...consensusData.atom_tallies.texiao.map((t) => t.votes), 1)
        : 1);

    // Build sorted tema list
    const temaList: FrequencyItem[] = Array.from(temaMap.entries())
      .map(([num, data]) => {
        const pct = resolvedTotalTema > 0 ? (data.count / resolvedTotalTema) * 100 : 0;
        return {
          value: num,
          kind: "num" as const,
          count: data.count,
          percentage: pct,
          sources: data.sources,
          isHit: drawnTemaNum !== null && padNum(num) === drawnTemaNum,
          bose: getBose(num),
          xiao: getXiao(num, 2026),
          wuxing: getWuxing(num),
          size: getSize(num),
          odd: getOdd(num),
        };
      })
      .sort((a, b) => {
        if (b.count !== a.count) return b.count - a.count;
        return parseInt(a.value, 10) - parseInt(b.value, 10);
      });

    // Build sorted texiao list
    const texiaoList: FrequencyItem[] = Array.from(texiaoMap.entries())
      .map(([xiao, data]) => {
        const pct = resolvedTotalTexiao > 0 ? (data.count / resolvedTotalTexiao) * 100 : 0;
        const sampleNums: string[] = [];
        for (let n = 1; n <= 49; n++) {
          const p = padNum(n);
          if (getXiao(p, 2026) === xiao) {
            sampleNums.push(p);
          }
        }
        return {
          value: xiao,
          kind: "xiao" as const,
          count: data.count,
          percentage: pct,
          sources: data.sources,
          isHit: drawnTemaXiao !== null && xiao === drawnTemaXiao,
          jiaye: getJiaye(xiao),
          sampleNums,
        };
      })
      .sort((a, b) => {
        if (b.count !== a.count) return b.count - a.count;
        return (XIAO_LIST as readonly string[]).indexOf(a.value) - (XIAO_LIST as readonly string[]).indexOf(b.value);
      });

    return {
      temaList,
      texiaoList,
      totalTemaSources: resolvedTotalTema,
      totalTexiaoSources: resolvedTotalTexiao,
      drawnTemaNum,
      drawnTemaXiao,
    };
  }, [comparison, consensusData, officialDraw]);

  // Filtered tema and texiao lists for search/filter controls
  const filteredTemaList = useMemo(() => {
    return frequencyStats.temaList.filter((item) => {
      if (freqMinVotes > 0 && item.count < freqMinVotes) return false;
      if (freqKeyword.trim()) {
        const kw = freqKeyword.trim().toLowerCase();
        const mVal = item.value.includes(kw);
        const mXiao = item.xiao?.toLowerCase().includes(kw);
        const mBose = item.bose?.includes(kw);
        const mSrc = item.sources.some(
          (s) => s.name.toLowerCase().includes(kw) || s.id.toLowerCase().includes(kw)
        );
        if (!mVal && !mXiao && !mBose && !mSrc) return false;
      }
      return true;
    });
  }, [frequencyStats.temaList, freqMinVotes, freqKeyword]);

  const filteredTexiaoList = useMemo(() => {
    return frequencyStats.texiaoList.filter((item) => {
      if (freqMinVotes > 0 && item.count < freqMinVotes) return false;
      if (freqKeyword.trim()) {
        const kw = freqKeyword.trim().toLowerCase();
        const mVal = item.value.includes(kw);
        const mSrc = item.sources.some(
          (s) => s.name.toLowerCase().includes(kw) || s.id.toLowerCase().includes(kw)
        );
        const mNums = item.sampleNums?.some((n) => n.includes(kw));
        if (!mVal && !mSrc && !mNums) return false;
      }
      return true;
    });
  }, [frequencyStats.texiaoList, freqMinVotes, freqKeyword]);

  // Tab 2 filtered consensus groups
  const filteredConsensusGroups = useMemo(() => {
    if (!consensusData) return [];
    if (!playFilter) return consensusData.groups;
    return consensusData.groups.filter((g) => g.play_type === playFilter);
  }, [consensusData, playFilter]);

  // Tab 2 KPI statistics
  const consensusStats = useMemo(() => {
    if (!consensusData || !consensusData.groups) return null;
    const totalGroups = consensusData.groups.length;
    const totalSources = consensusData.groups.reduce((acc, g) => acc + g.n_sources, 0);
    const totalVotes = consensusData.groups.reduce((acc, g) => acc + g.n_votes, 0);
    const judgedGroups = consensusData.groups.filter((g) => g.leader_hit !== undefined);
    const leaderHits = judgedGroups.filter((g) => g.leader_hit === true).length;
    const leaderHitRate =
      judgedGroups.length > 0 ? Math.round((leaderHits / judgedGroups.length) * 100) : null;

    return {
      totalGroups,
      totalSources,
      totalVotes,
      judgedGroups: judgedGroups.length,
      leaderHits,
      leaderHitRate,
    };
  }, [consensusData]);

  return (
    <PageWorkspace summary="看各来源有没有对上开奖、有没有虚假报喜，以及多个来源去掉重复后的共识排名。">

      {/* 顶部 Tab 切换 */}
      <div className="flex items-center justify-between gap-4 flex-wrap pb-1">
        <SegmentedTabs
          tabs={[
            {
              id: "frequency",
              label: "特码·特肖频次共识榜",
              count:
                frequencyStats &&
                (frequencyStats.temaList.length > 0 || frequencyStats.texiaoList.length > 0)
                  ? `${frequencyStats.temaList.length}特码 · ${frequencyStats.texiaoList.length}特肖`
                  : undefined,
            },
            {
              id: "comparison",
              label: "数据入库与开奖比对",
              count: comparison ? comparison.summary.total : undefined,
            },
            {
              id: "consensus",
              label: "全玩法组合去重对照",
              count: consensusData ? `${consensusData.groups.length} 玩法` : undefined,
            },
          ]}
          activeTab={activeTab}
          onChange={setActiveTab}
        />
      </div>

      {/* 快捷查询与导航工具栏 */}
      <div className="space-y-6">
        <Toolbar>
          <div className="flex items-center gap-2 flex-wrap">
            <Select
              value={lottery}
              onChange={(v) => setLottery(v as Lottery)}
              options={LOTTERIES}
            />

            <div className="flex items-center gap-1">
              <TextInput
                value={period}
                onChange={setPeriod}
                onKeyDown={(e) => {
                  if (e.key === "Enter") executeQuery(lottery, period);
                }}
                placeholder="期号，如 2026262 或 262"
                style={{ width: 170 }}
                className="font-mono text-sm"
              />
              <button
                type="button"
                onClick={handlePrevPeriod}
                title="上一期"
                disabled={loading || !period.trim()}
                className="inline-flex items-center justify-center h-10 px-3 rounded-xl text-sm font-medium border border-slate-200/50 dark:border-white/8 hover:bg-violet-500/5 dark:hover:bg-violet-400/5 text-slate-700 dark:text-slate-300 backdrop-blur-sm transition-colors cursor-pointer disabled:opacity-50"
              >
                ◀
              </button>
              <button
                type="button"
                onClick={handleNextPeriod}
                title="下一期"
                disabled={loading || !period.trim()}
                className="inline-flex items-center justify-center h-10 px-3 rounded-xl text-sm font-medium border border-slate-200/50 dark:border-white/8 hover:bg-violet-500/5 dark:hover:bg-violet-400/5 text-slate-700 dark:text-slate-300 backdrop-blur-sm transition-colors cursor-pointer disabled:opacity-50"
              >
                ▶
              </button>
              <button
                type="button"
                onClick={handleLatestPeriod}
                title="载入最新开奖期号"
                disabled={loading}
                className="inline-flex items-center justify-center h-10 px-3 rounded-xl text-xs font-medium border border-slate-200/50 dark:border-white/8 hover:bg-violet-500/5 dark:hover:bg-violet-400/5 text-slate-700 dark:text-slate-300 backdrop-blur-sm transition-colors cursor-pointer disabled:opacity-50"
              >
                ⚡ 最新期
              </button>
            </div>

            {activeTab !== "frequency" && (
              <Select
                value={playFilter}
                onChange={setPlayFilter}
                options={playOptions}
                style={{ minWidth: 140 }}
              />
            )}

            {activeTab === "frequency" && (
              <>
                <TextInput
                  value={freqKeyword}
                  onChange={setFreqKeyword}
                  placeholder="筛选号码/生肖/来源…"
                  style={{ width: 160 }}
                />
                <Select
                  value={String(freqMinVotes)}
                  onChange={(v) => setFreqMinVotes(Number(v))}
                  options={[
                    { value: "0", label: "全部频次" },
                    { value: "2", label: "≥ 2 票" },
                    { value: "3", label: "≥ 3 票" },
                    { value: "4", label: "≥ 4 票" },
                    { value: "5", label: "≥ 5 票" },
                  ]}
                  style={{ minWidth: 105 }}
                />
              </>
            )}

            {activeTab === "comparison" && (
              <TextInput
                value={sourceKeyword}
                onChange={setSourceKeyword}
                onKeyDown={(e) => {
                  if (e.key === "Enter") executeQuery(lottery, period);
                }}
                placeholder="筛选来源名称/ID…"
                style={{ width: 160 }}
              />
            )}

            <button
              type="button"
              onClick={() => executeQuery(lottery, period)}
              disabled={loading || !period.trim()}
              className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-semibold glow-button border-0 transition-all disabled:opacity-50 cursor-pointer"
            >
              {loading ? "查询中…" : "查询对照"}
            </button>

            {canWrite && comparison && (
              <button
                type="button"
                onClick={handleRejudge}
                disabled={rejudging || !period.trim()}
                className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-semibold border border-slate-200/50 dark:border-white/8 hover:bg-violet-500/5 dark:hover:bg-violet-400/5 text-slate-700 dark:text-slate-300 backdrop-blur-sm transition-all disabled:opacity-50 cursor-pointer"
              >
                {rejudging ? "计算中…" : "🔄 重新触发对奖比对"}
              </button>
            )}
          </div>
        </Toolbar>

        {error ? (
          <Alert variant="error" className="rounded-2xl border border-rose-400/40 dark:border-rose-400/25 bg-rose-500/10 text-rose-700 dark:text-rose-300 backdrop-blur-md">
            <AlertDescription className="text-sm">{error}</AlertDescription>
          </Alert>
        ) : null}

        {/* ========================================================================= */}
        {/* 官方开奖信息看板（Tab 1 & Tab 2 共享，一眼洞悉当期落球与属性）              */}
        {/* ========================================================================= */}
        {officialDraw ? (
          (() => {
            const { ballsDetail, temaDetail, summary } = ensureDrawDetails(officialDraw);
            return (
              <div className="rounded-3xl p-4 sm:p-5 glass-card flex flex-col gap-4">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-slate-200/50 dark:border-white/8 pb-3">
                  <div className="flex items-center gap-2.5">
                    <span className="w-2.5 h-2.5 rounded-full bg-emerald-500 animate-pulse" />
                    <span className="text-sm font-bold text-slate-800 dark:text-slate-200">
                      {LOTTERY_LABEL[officialDraw.lottery as Lottery] || officialDraw.lottery} 第{" "}
                      <span className="font-mono text-primary text-base">{officialDraw.period}</span>{" "}
                      期 官方正式开奖号码
                    </span>
                  </div>
                  <div className="flex items-center gap-3 text-xs text-slate-500 dark:text-slate-400 font-medium">
                    <span>开奖日期：{officialDraw.draw_date || "—"}</span>
                    <span>来源：{officialDraw.source || "official"}</span>
                  </div>
                </div>

                {/* 开奖球号流 */}
                <div className="flex items-center gap-3 sm:gap-4 flex-wrap">
                  <div className="flex gap-2 sm:gap-2.5 flex-wrap">
                    {ballsDetail.map((b, idx) => {
                      const colorCfg = BOSE_COLORS[b.bose] || BOSE_COLORS["红"];
                      const isLianxiao = b.is_lianxiao;
                      const isAdj = b.is_adjacent_lianxiao;
                      let boxShadow = "0 2px 4px rgba(0,0,0,0.18)";
                      if (isLianxiao) {
                        boxShadow = isAdj
                          ? "0 0 0 2.5px #ec4899, 0 0 8px rgba(236,72,153,0.5)"
                          : "0 0 0 2px #8b5cf6, 0 0 6px rgba(139,92,246,0.4)";
                      }
                      return (
                        <div
                          key={idx}
                          className="inline-flex flex-col items-center gap-1"
                        >
                          <span
                            className="inline-grid place-items-center w-8 h-8 sm:w-9 sm:h-9 rounded-full text-white text-xs sm:text-sm font-bold font-mono relative transition-transform hover:scale-105"
                            style={{
                              backgroundColor: colorCfg.bg,
                              boxShadow,
                            }}
                            title={`${b.num} (${b.bose}波 · ${b.xiao})${
                              isLianxiao ? ` [连肖·共${b.lianxiao_count}球]` : ""
                            }`}
                          >
                            {b.num}
                            {isLianxiao && (
                              <span
                                className="absolute -top-1.5 -left-1.5 text-[9px] text-white font-extrabold px-1 rounded-sm leading-tight shadow-2xs"
                                style={{ backgroundColor: isAdj ? "#ec4899" : "#8b5cf6" }}
                              >
                                {isAdj ? "⚡" : "🔗"}
                              </span>
                            )}
                          </span>
                          <span
                            className="text-xs font-bold"
                            style={{
                              color: isAdj ? "#ec4899" : isLianxiao ? "#8b5cf6" : undefined,
                              textDecoration: isLianxiao ? "underline" : undefined,
                            }}
                          >
                            {b.xiao}
                          </span>
                        </div>
                      );
                    })}
                  </div>

                  <span className="text-xl font-bold text-slate-400">+</span>

                  {/* 特码球 */}
                  <div className="inline-flex flex-col items-center gap-1">
                    <span
                      className="inline-grid place-items-center w-9 h-9 sm:w-10 sm:h-10 rounded-full text-white text-sm sm:text-base font-extrabold font-mono relative transition-transform hover:scale-105"
                      style={{
                        backgroundColor: BOSE_COLORS[temaDetail.bose]?.bg || "#ef4444",
                        boxShadow: temaDetail.is_lianxiao
                          ? "0 0 0 2.5px #f59e0b, 0 0 0 4.5px #8b5cf6, 0 3px 10px rgba(139,92,246,0.5)"
                          : "0 0 0 2.5px #f59e0b, 0 3px 8px rgba(245,158,11,0.35)",
                      }}
                      title={`特码 ${temaDetail.num} (${temaDetail.bose}波 · ${temaDetail.xiao} · ${temaDetail.wuxing || ""})${
                        temaDetail.is_lianxiao ? ` [连肖·共${temaDetail.lianxiao_count}球]` : ""
                      }`}
                    >
                      {temaDetail.num}
                      {temaDetail.is_lianxiao && (
                        <span
                          className="absolute -top-1.5 -left-1.5 text-[9px] text-white font-extrabold px-1 rounded-sm leading-tight shadow-2xs"
                          style={{
                            backgroundColor: temaDetail.is_adjacent_lianxiao ? "#ec4899" : "#8b5cf6",
                          }}
                        >
                          {temaDetail.is_adjacent_lianxiao ? "⚡" : "🔗"}
                        </span>
                      )}
                      <span className="absolute -top-1.5 -right-2 text-[9px] bg-amber-400 text-slate-950 font-black px-1 rounded-sm leading-tight shadow-xs">
                        特
                      </span>
                    </span>
                    <span className="text-xs font-extrabold text-primary">
                      {temaDetail.xiao}
                    </span>
                  </div>
                </div>

                {/* 属性形态摘要徽章群 */}
                <div className="flex gap-2 flex-wrap items-center text-xs">
                  {summary.has_lianxiao ? (
                    <Badge size="sm" style={{ backgroundColor: "#8b5cf6", color: "#fff", fontWeight: 700 }}>
                      🔗 连肖: {summary.lianxiao_text}
                    </Badge>
                  ) : (
                    <Badge size="sm" variant="outline">
                      7肖各异
                    </Badge>
                  )}
                  {summary.has_adjacent_lianxiao && (
                    <Badge size="sm" style={{ backgroundColor: "#ec4899", color: "#fff", fontWeight: 700 }}>
                      ⚡ 顺位紧邻连肖
                    </Badge>
                  )}
                  <Badge size="sm" variant="primary">
                    特肖: {temaDetail.xiao} · {temaDetail.jiaye}
                  </Badge>
                  <Badge
                    size="sm"
                    style={{
                      backgroundColor: BOSE_COLORS[temaDetail.bose]?.bg,
                      color: "#fff",
                      border: "none",
                    }}
                  >
                    {temaDetail.bose}波
                  </Badge>
                  {temaDetail.wuxing && (
                    <Badge size="sm" variant="soft" style={{ color: WUXING_COLORS[temaDetail.wuxing] }}>
                      五行{temaDetail.wuxing}
                    </Badge>
                  )}
                  <Badge size="sm" variant="soft">
                    特码: {temaDetail.size} · {temaDetail.odd}
                  </Badge>
                  <Badge size="sm" variant="soft">
                    合{temaDetail.sum}
                  </Badge>
                  <Badge size="sm" variant="outline">
                    半波: {temaDetail.halfwave}
                  </Badge>
                  <Badge size="sm" variant="soft">
                    七球总分: {summary.sum7}（{summary.sum7_size} · {summary.sum7_odd}）
                  </Badge>
                </div>
              </div>
            );
          })()
        ) : (
          <div className="rounded-3xl p-4 bg-amber-500/10 border border-amber-400/40 dark:border-amber-400/25 backdrop-blur-md flex items-center justify-between gap-4">
            <div className="flex items-center gap-3">
              <span className="text-xl">⏳</span>
              <div>
                <div className="text-sm font-bold text-amber-800 dark:text-amber-200">
                  第 {period || "—"} 期 官方尚未开奖
                </div>
                <div className="text-xs text-amber-700/80 dark:text-amber-300/80 mt-0.5">
                  预测已成功采集入库并生成去重共识，待官方开奖后系统将自动完成逐条对奖判定。
                </div>
              </div>
            </div>
            <Badge size="md" variant="warning">
              待开奖
            </Badge>
          </div>
        )}

        {/* ========================================================================= */}
        {/* Tab 0: 特码·特肖频次共识榜（左右独立两列展示）                             */}
        {/* ========================================================================= */}
        {activeTab === "frequency" && (
          <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
            {/* KPI 概览卡片 */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              {/* 领跑特码 */}
              <div className="p-3.5 rounded-2xl glass-subtle flex flex-col gap-1.5">
                <span className="text-xs text-slate-500 dark:text-slate-400 font-medium flex items-center justify-between">
                  <span>🏆 最热特码 (领跑第1)</span>
                  {frequencyStats.temaList[0]?.isHit && (
                    <span className="text-[11px] font-bold text-emerald-600 dark:text-emerald-400 animate-pulse">
                      🎯 已命中
                    </span>
                  )}
                </span>
                {frequencyStats.temaList.length > 0 ? (
                  <div className="flex items-center gap-2 mt-0.5">
                    <TemaBall
                      num={frequencyStats.temaList[0].value}
                      bose={frequencyStats.temaList[0].bose}
                    />
                    <div className="flex flex-col">
                      <span className="text-sm font-bold text-slate-900 dark:text-white">
                        {frequencyStats.temaList[0].value} 号 · {frequencyStats.temaList[0].xiao}肖
                      </span>
                      <span className="text-xs text-slate-500 font-mono">
                        {frequencyStats.temaList[0].count} 票（
                        {frequencyStats.temaList[0].percentage.toFixed(1)}%）
                      </span>
                    </div>
                  </div>
                ) : (
                  <span className="text-sm text-slate-400 font-medium">暂无数据</span>
                )}
              </div>

              {/* 领跑特肖 */}
              <div className="p-3.5 rounded-2xl glass-subtle flex flex-col gap-1.5">
                <span className="text-xs text-slate-500 dark:text-slate-400 font-medium flex items-center justify-between">
                  <span>🏆 最热特肖 (领跑第1)</span>
                  {frequencyStats.texiaoList[0]?.isHit && (
                    <span className="text-[11px] font-bold text-emerald-600 dark:text-emerald-400 animate-pulse">
                      🎯 已命中
                    </span>
                  )}
                </span>
                {frequencyStats.texiaoList.length > 0 ? (
                  <div className="flex items-center gap-2 mt-0.5">
                    <span className="inline-grid place-items-center w-8 h-8 rounded-xl bg-gradient-to-br from-violet-500 to-fuchsia-500 text-white text-base font-black shadow-xs shrink-0">
                      {frequencyStats.texiaoList[0].value}
                    </span>
                    <div className="flex flex-col">
                      <span className="text-sm font-bold text-slate-900 dark:text-white">
                        {frequencyStats.texiaoList[0].value}肖 ·{" "}
                        {frequencyStats.texiaoList[0].jiaye === "家" ? "家禽" : "野兽"}
                      </span>
                      <span className="text-xs text-slate-500 font-mono">
                        {frequencyStats.texiaoList[0].count} 票（
                        {frequencyStats.texiaoList[0].percentage.toFixed(1)}%）
                      </span>
                    </div>
                  </div>
                ) : (
                  <span className="text-sm text-slate-400 font-medium">暂无数据</span>
                )}
              </div>

              {/* 预测覆盖样本 */}
              <div className="p-3.5 rounded-2xl glass-subtle flex flex-col gap-1">
                <span className="text-xs text-primary font-medium">📊 参评预测来源</span>
                <span className="text-xl font-bold font-mono text-primary">
                  {frequencyStats.totalTemaSources} 特码 / {frequencyStats.totalTexiaoSources} 特肖
                </span>
                <span className="text-[11px] text-slate-500 dark:text-slate-400">
                  入选 {frequencyStats.temaList.length} 个特码，{frequencyStats.texiaoList.length} 个生肖
                </span>
              </div>

              {/* 开奖命中核验 */}
              <div
                className={`p-3.5 rounded-2xl border flex flex-col gap-1 ${
                  officialDraw
                    ? "bg-emerald-500/10 border-emerald-400/40 dark:border-emerald-400/25 backdrop-blur-md"
                    : "glass-subtle"
                }`}
              >
                <span
                  className={`text-xs font-medium ${
                    officialDraw
                      ? "text-emerald-700 dark:text-emerald-300"
                      : "text-slate-500 dark:text-slate-400"
                  }`}
                >
                  🎯 官方开奖核验
                </span>
                {officialDraw ? (
                  (() => {
                    const { temaDetail } = ensureDrawDetails(officialDraw);
                    const temaRankIdx = frequencyStats.temaList.findIndex(
                      (t) => padNum(t.value) === padNum(temaDetail.num)
                    );
                    const texiaoRankIdx = frequencyStats.texiaoList.findIndex(
                      (t) => t.value === temaDetail.xiao
                    );
                    return (
                      <div className="flex flex-col gap-0.5">
                        <span className="text-sm font-bold font-mono text-slate-900 dark:text-white">
                          特码 {temaDetail.num}（{temaDetail.xiao}）
                        </span>
                        <span className="text-[11px] text-slate-600 dark:text-slate-400">
                          特码排第 {temaRankIdx >= 0 ? `${temaRankIdx + 1}位` : "未入选"} · 特肖排第{" "}
                          {texiaoRankIdx >= 0 ? `${texiaoRankIdx + 1}位` : "未入选"}
                        </span>
                      </div>
                    );
                  })()
                ) : (
                  <span className="text-sm font-semibold text-slate-500 dark:text-slate-400">
                    ⏳ 待官方开奖后自动核验
                  </span>
                )}
              </div>
            </div>

            {/* 左右独立两列排行榜 */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              {/* ========================================================================= */}
              {/* 左列：特码出现频次排行                                                     */}
              {/* ========================================================================= */}
              <div className="rounded-3xl p-4 sm:p-5 glass-card flex flex-col gap-4">
                <div className="flex items-center justify-between gap-3 border-b border-slate-200/50 dark:border-white/8 pb-3 flex-wrap">
                  <div className="flex items-center gap-2">
                    <span className="text-base font-extrabold text-slate-900 dark:text-white flex items-center gap-1.5">
                      <span>🎯</span>
                      <span>特码出现频次排行</span>
                    </span>
                    <Badge size="sm" variant="soft">
                      共 {filteredTemaList.length} 个号码
                    </Badge>
                    <Badge size="sm" variant="outline">
                      {frequencyStats.totalTemaSources} 来源
                    </Badge>
                  </div>
                  <span className="text-xs text-slate-400 font-medium">按出现次数由高到低排序</span>
                </div>

                {filteredTemaList.length === 0 ? (
                  <div className="text-center py-12 text-slate-400 text-sm">
                    {freqKeyword || freqMinVotes > 0
                      ? "未找到匹配当前筛选条件的特码数据。"
                      : "当期暂无抓取的特码预测数据。"}
                  </div>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full text-left border-collapse text-xs sm:text-sm">
                      <thead>
                        <tr className="glass-subtle text-slate-500 dark:text-slate-400 border-b border-slate-200/50 dark:border-white/8 text-xs">
                          <th style={{ ...th, width: 70 }}>排名</th>
                          <th style={{ ...th, minWidth: 130 }}>特码号码</th>
                          <th style={{ ...th, minWidth: 160 }}>出现频次与支持率</th>
                          <th style={{ ...th, width: 95 }}>开奖核验</th>
                          <th style={{ ...th, minWidth: 140 }}>支持来源</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-200/40 dark:divide-white/5">
                        {filteredTemaList.map((item, i) => (
                          <tr
                            key={item.value}
                            className={`transition-colors ${
                              item.isHit
                                ? "bg-emerald-500/10 dark:bg-emerald-950/20 font-medium"
                                : i === 0
                                ? "bg-amber-500/5 dark:bg-amber-950/10"
                                : "hover:bg-violet-500/5 dark:hover:bg-violet-400/5"
                            }`}
                          >
                            <td style={td}>
                              <RankBadge rank={i + 1} />
                            </td>
                            <td style={td}>
                              <div className="flex items-center gap-2">
                                <TemaBall num={item.value} bose={item.bose} />
                                <div className="flex flex-col">
                                  <div className="flex items-center gap-1">
                                    <span className="font-bold text-xs text-slate-800 dark:text-slate-200">
                                      {item.xiao}肖
                                    </span>
                                    <span
                                      className="text-[10px] font-semibold px-1 rounded"
                                      style={{
                                        color: BOSE_COLORS[item.bose || "红"].bg,
                                      }}
                                    >
                                      {item.bose}波
                                    </span>
                                  </div>
                                  <div className="flex items-center gap-1 text-[10px] text-slate-400 font-mono">
                                    <span>{item.size}</span>
                                    <span>·</span>
                                    <span>{item.odd}</span>
                                    {item.wuxing && (
                                      <>
                                        <span>·</span>
                                        <span style={{ color: WUXING_COLORS[item.wuxing] }}>
                                          {item.wuxing}
                                        </span>
                                      </>
                                    )}
                                  </div>
                                </div>
                              </div>
                            </td>
                            <td style={td}>
                              <FrequencyProgressBar
                                count={item.count}
                                pct={item.percentage}
                                isTop={i === 0}
                                isHit={item.isHit}
                              />
                            </td>
                            <td style={td}>
                              <HitStatusBadge
                                isHit={item.isHit}
                                hasOfficialDraw={!!officialDraw}
                                kind="tema"
                              />
                            </td>
                            <td style={td}>
                              <VotersChipList sources={item.sources.map((s) => s.name)} />
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>

              {/* ========================================================================= */}
              {/* 右列：特肖出现频次排行                                                     */}
              {/* ========================================================================= */}
              <div className="rounded-3xl p-4 sm:p-5 glass-card flex flex-col gap-4">
                <div className="flex items-center justify-between gap-3 border-b border-slate-200/50 dark:border-white/8 pb-3 flex-wrap">
                  <div className="flex items-center gap-2">
                    <span className="text-base font-extrabold text-slate-900 dark:text-white flex items-center gap-1.5">
                      <span>🐾</span>
                      <span>特肖出现频次排行</span>
                    </span>
                    <Badge size="sm" variant="soft">
                      共 {filteredTexiaoList.length} 个生肖
                    </Badge>
                    <Badge size="sm" variant="outline">
                      {frequencyStats.totalTexiaoSources} 来源
                    </Badge>
                  </div>
                  <span className="text-xs text-slate-400 font-medium">按出现次数由高到低排序</span>
                </div>

                {filteredTexiaoList.length === 0 ? (
                  <div className="text-center py-12 text-slate-400 text-sm">
                    {freqKeyword || freqMinVotes > 0
                      ? "未找到匹配当前筛选条件的特肖数据。"
                      : "当期暂无抓取的特肖预测数据。"}
                  </div>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full text-left border-collapse text-xs sm:text-sm">
                      <thead>
                        <tr className="glass-subtle text-slate-500 dark:text-slate-400 border-b border-slate-200/50 dark:border-white/8 text-xs">
                          <th style={{ ...th, width: 70 }}>排名</th>
                          <th style={{ ...th, minWidth: 130 }}>特肖生肖</th>
                          <th style={{ ...th, minWidth: 160 }}>出现频次与支持率</th>
                          <th style={{ ...th, width: 95 }}>开奖核验</th>
                          <th style={{ ...th, minWidth: 140 }}>支持来源</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-200/40 dark:divide-white/5">
                        {filteredTexiaoList.map((item, i) => (
                          <tr
                            key={item.value}
                            className={`transition-colors ${
                              item.isHit
                                ? "bg-emerald-500/10 dark:bg-emerald-950/20 font-medium"
                                : i === 0
                                ? "bg-amber-500/5 dark:bg-amber-950/10"
                                : "hover:bg-violet-500/5 dark:hover:bg-violet-400/5"
                            }`}
                          >
                            <td style={td}>
                              <RankBadge rank={i + 1} />
                            </td>
                            <td style={td}>
                              <div className="flex items-center gap-2">
                                <TexiaoBadge xiao={item.value} jiaye={item.jiaye} />
                                {item.sampleNums && item.sampleNums.length > 0 && (
                                  <div className="hidden sm:flex flex-wrap gap-1 max-w-[90px]">
                                    {item.sampleNums.map((num) => (
                                      <span
                                        key={num}
                                        className="text-[10px] font-mono px-1 py-0.5 rounded glass-subtle text-slate-500 dark:text-slate-400"
                                      >
                                        {num}
                                      </span>
                                    ))}
                                  </div>
                                )}
                              </div>
                            </td>
                            <td style={td}>
                              <FrequencyProgressBar
                                count={item.count}
                                pct={item.percentage}
                                isTop={i === 0}
                                isHit={item.isHit}
                              />
                            </td>
                            <td style={td}>
                              <HitStatusBadge
                                isHit={item.isHit}
                                hasOfficialDraw={!!officialDraw}
                                kind="texiao"
                              />
                            </td>
                            <td style={td}>
                              <VotersChipList sources={item.sources.map((s) => s.name)} />
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            </div>
          </div>
        )}

        {/* ========================================================================= */}
        {/* Tab 1: 数据入库与开奖比对                                                 */}
        {/* ========================================================================= */}
        {activeTab === "comparison" && comparison && (
          <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
            {/* 统计指标卡片网格 */}
            <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
              <div className="p-3.5 rounded-2xl glass-subtle flex flex-col gap-1">
                <span className="text-xs text-slate-500 dark:text-slate-400">已入库预测</span>
                <span className="text-xl font-bold font-mono text-slate-900 dark:text-white">
                  {comparison.summary.total}
                </span>
              </div>
              <div className="p-3.5 rounded-2xl glass-subtle flex flex-col gap-1">
                <span className="text-xs text-slate-500 dark:text-slate-400">已完成对奖</span>
                <span className="text-xl font-bold font-mono text-slate-900 dark:text-white">
                  {comparison.summary.judged}
                </span>
              </div>
              <div className="p-3.5 rounded-2xl bg-emerald-500/10 border border-emerald-400/40 dark:border-emerald-400/25 backdrop-blur-md flex flex-col gap-1">
                <span className="text-xs text-emerald-700 dark:text-emerald-300 font-medium">
                  🎯 官方命中数
                </span>
                <span className="text-xl font-bold font-mono text-emerald-600 dark:text-emerald-400">
                  {comparison.summary.hits}
                </span>
              </div>
              <div className="p-3.5 rounded-2xl glass-subtle flex flex-col gap-1">
                <span className="text-xs text-primary font-medium">📈 综合命中率</span>
                <span className="text-xl font-bold font-mono text-primary">
                  {comparison.summary.hit_rate}%
                </span>
              </div>
              <div
                className={`p-3.5 rounded-2xl border flex flex-col gap-1 ${
                  comparison.summary.conflicts > 0
                    ? "bg-rose-500/10 border-rose-400/40 dark:border-rose-400/25 backdrop-blur-md"
                    : "glass-subtle"
                }`}
              >
                <span
                  className={`text-xs font-medium ${
                    comparison.summary.conflicts > 0
                      ? "text-rose-600 dark:text-rose-400"
                      : "text-slate-500 dark:text-slate-400"
                  }`}
                >
                  ⚠️ 自称存疑 (虚假报喜)
                </span>
                <span
                  className={`text-xl font-bold font-mono ${
                    comparison.summary.conflicts > 0
                      ? "text-rose-600 dark:text-rose-400"
                      : "text-slate-800 dark:text-slate-200"
                  }`}
                >
                  {comparison.summary.conflicts}
                </span>
              </div>
            </div>

            {/* 状态筛选切换条 */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pt-1">
              <div className="flex gap-2 items-center flex-wrap">
                <span className="text-xs text-slate-500 dark:text-slate-400 font-medium">
                  状态筛选:
                </span>
                {[
                  { key: "all", label: `全部 (${comparison.items.length})` },
                  { key: "hit", label: `🎯 官方命中 (${comparison.summary.hits})` },
                  { key: "miss", label: `❌ 官方未中 (${comparison.summary.misses})` },
                  { key: "pending", label: `⏳ 待开奖 (${comparison.summary.pending})` },
                  { key: "conflict", label: `⚠️ 自称不符 (${comparison.summary.conflicts})` },
                ].map((f) => (
                  <button
                    key={f.key}
                    onClick={() => setStatusFilter(f.key)}
                    className={`px-3 py-1.5 rounded-xl text-xs font-medium cursor-pointer transition-all ${
                      statusFilter === f.key
                        ? "glow-button border-0"
                        : "glass-subtle text-slate-700 dark:text-slate-300 hover:border-violet-400/40"
                    }`}
                  >
                    {f.label}
                  </button>
                ))}
              </div>
              <div className="text-xs text-slate-400">
                显示 {filteredComparisonItems.length} / {comparison.items.length} 条记录
              </div>
            </div>

            {/* 比对明细表格 */}
            {filteredComparisonItems.length === 0 ? (
              <div className="text-center py-12 text-slate-400 text-sm">
                当前筛选条件下暂无预测比对记录。
              </div>
            ) : (
              <div className="overflow-x-auto rounded-3xl glass-card">
                <table className="w-full text-left border-collapse text-xs sm:text-sm">
                  <thead>
                    <tr className="glass-subtle text-slate-500 dark:text-slate-400 border-b border-slate-200/50 dark:border-white/8">
                      <th style={th}>预测来源</th>
                      <th style={th}>玩法</th>
                      <th style={th}>预测内容（命中高亮）</th>
                      <th style={th}>官方对奖结果</th>
                      <th style={th}>命中详情说明</th>
                      <th style={th}>自称核验</th>
                      <th style={th}>抓取时间</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-200/40 dark:divide-white/5">
                    {filteredComparisonItems.map((item) => {
                      const detail = formatHitDetail(item, officialDraw);
                      const isJsonOpen = expandedJsonId === item.id;
                      return (
                        <tr
                          key={item.id}
                          className="hover:bg-violet-500/5 dark:hover:bg-violet-400/5 transition-colors"
                        >
                          <td style={td}>
                            <div className="font-semibold text-slate-900 dark:text-white">
                              {item.source_name}
                            </div>
                            <div className="text-[11px] text-slate-400 font-mono mt-0.5">
                              {item.source_id}
                              {item.group_key ? ` · 第${item.group_key}组` : ""}
                            </div>
                          </td>
                          <td style={td}>
                            <Badge size="sm" variant="soft">
                              {playLabel(item.play_type)}
                            </Badge>
                          </td>
                          <td style={{ ...td, minWidth: 160 }}>
                            <PredAtomsBadgeList item={item} />
                          </td>
                          <td style={td}>
                            {item.status === "hit" ? (
                              <Badge size="sm" variant="success">
                                🎯 官方命中
                              </Badge>
                            ) : item.status === "miss" ? (
                              <Badge size="sm" variant="error">
                                ❌ 官方未中
                              </Badge>
                            ) : item.status === "conflict" ? (
                              <Badge size="sm" variant="error">
                                ⚠️ 假报中奖
                              </Badge>
                            ) : (
                              <Badge size="sm" variant="soft">
                                ⏳ 待开奖对奖
                              </Badge>
                            )}
                          </td>
                          <td style={{ ...td, minWidth: 200, maxWidth: 300 }}>
                            <div className="flex flex-col gap-1">
                              <span className="text-xs text-slate-700 dark:text-slate-300 leading-relaxed font-medium">
                                {detail.summary}
                              </span>
                              {detail.rawJson && (
                                <div>
                                  <button
                                    onClick={() =>
                                      setExpandedJsonId(isJsonOpen ? null : item.id)
                                    }
                                    className="text-[11px] text-primary hover:underline cursor-pointer transition-colors"
                                  >
                                    {isJsonOpen ? "收起参数" : "查看参数"}
                                  </button>
                                  {isJsonOpen && (
                                    <pre className="mt-1 p-2 rounded-xl bg-slate-950/90 backdrop-blur-md text-emerald-300 border border-white/10 font-mono text-[10px] overflow-x-auto max-h-32 shadow-inner">
                                      {JSON.stringify(detail.rawJson, null, 2)}
                                    </pre>
                                  )}
                                </div>
                              )}
                            </div>
                          </td>
                          <td style={td}>
                            {item.claimed_status === "hit" && item.official_hit === 0 ? (
                              <Badge size="sm" variant="error">
                                ⚠️ 虚假报中
                              </Badge>
                            ) : item.claimed_status === "hit" ? (
                              <span className="text-xs text-emerald-600 dark:text-emerald-400 font-semibold">
                                标榜已中
                              </span>
                            ) : item.claimed_status === "miss" ? (
                              <span className="text-xs text-slate-400">标榜未中</span>
                            ) : (
                              <span className="text-xs text-slate-400">未标明</span>
                            )}
                          </td>
                          <td style={{ ...td, fontSize: 11, color: "var(--color-foreground-muted)" }}>
                            {item.fetched_at?.replace("T", " ").slice(0, 16) || "—"}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}

        {/* ========================================================================= */}
        {/* Tab 2: 多源预测共识对照                                                   */}
        {/* ========================================================================= */}
        {activeTab === "consensus" && consensusData && (
          <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
            {/* 共识概览 KPI */}
            {consensusStats && (
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                <div className="p-3.5 rounded-2xl glass-subtle flex flex-col gap-1">
                  <span className="text-xs text-slate-500 dark:text-slate-400">共识涵盖玩法</span>
                  <span className="text-xl font-bold font-mono text-slate-900 dark:text-white">
                    {consensusStats.totalGroups} 类
                  </span>
                </div>
                <div className="p-3.5 rounded-2xl glass-subtle flex flex-col gap-1">
                  <span className="text-xs text-slate-500 dark:text-slate-400">参评来源总数</span>
                  <span className="text-xl font-bold font-mono text-slate-900 dark:text-white">
                    {consensusStats.totalSources} 条预测
                  </span>
                </div>
                <div className="p-3.5 rounded-2xl glass-subtle flex flex-col gap-1">
                  <span className="text-xs text-primary font-medium">有效去重选票</span>
                  <span className="text-xl font-bold font-mono text-primary">
                    {consensusStats.totalVotes} 票
                  </span>
                </div>
                <div className="p-3.5 rounded-2xl bg-emerald-500/10 border border-emerald-400/40 dark:border-emerald-400/25 backdrop-blur-md flex flex-col gap-1">
                  <span className="text-xs text-emerald-700 dark:text-emerald-300 font-medium">
                    🏆 领跑项开奖命中率
                  </span>
                  <span className="text-xl font-bold font-mono text-emerald-600 dark:text-emerald-400">
                    {consensusStats.leaderHitRate !== null
                      ? `${consensusStats.leaderHitRate}% (${consensusStats.leaderHits}/${consensusStats.judgedGroups})`
                      : "待开奖"}
                  </span>
                </div>
              </div>
            )}

            {filteredConsensusGroups.length === 0 ? (
              <div className="text-center py-12 text-slate-400 text-sm">
                该期暂无多源预测共识数据。
              </div>
            ) : (
              <div className="flex flex-col gap-6">
                {filteredConsensusGroups.map((g: ConsensusGroup) => {
                  const totalVotes = g.n_votes || 1;
                  return (
                    <div
                      key={g.play_type}
                      className="rounded-3xl p-4 sm:p-5 glass-card flex flex-col gap-4"
                    >
                      {/* 分组头部 */}
                      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-slate-200/50 dark:border-white/8 pb-3">
                        <div className="flex items-center gap-2.5 flex-wrap">
                          <span className="text-base font-bold text-slate-900 dark:text-white">
                            {playLabel(g.play_type)}
                          </span>
                          <Badge size="sm" variant="soft">
                            {g.n_sources} 来源样本
                          </Badge>
                          <Badge size="sm" variant="soft">
                            {g.n_votes} 有效票
                          </Badge>
                        </div>

                        {/* 领跑者突出显示 */}
                        {g.leader && (
                          <div className="flex items-center gap-2 flex-wrap">
                            <span className="text-xs text-slate-400 font-medium">
                              共识第一名：
                            </span>
                            <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-xl text-xs font-bold bg-amber-500/10 text-amber-800 dark:text-amber-200 border border-amber-500/20">
                              <span>🏆</span>
                              <span>{atomsText(g.leader)}</span>
                              <span className="font-mono text-amber-600 dark:text-amber-400">
                                （{g.leader_votes} 票 ·{" "}
                                {((g.leader_votes / totalVotes) * 100).toFixed(1)}%）
                              </span>
                            </span>

                            {g.leader_hit !== undefined && (
                              <Badge
                                size="sm"
                                variant={g.leader_hit ? "success" : "error"}
                              >
                                {g.leader_hit ? "🎯 领跑命中" : "❌ 领跑未中"}
                              </Badge>
                            )}
                          </div>
                        )}
                      </div>

                      {/* 投票排行榜表格 */}
                      <div className="overflow-x-auto">
                        <table className="w-full text-left border-collapse text-xs sm:text-sm">
                          <thead>
                            <tr className="glass-subtle text-slate-500 dark:text-slate-400 border-b border-slate-200/50 dark:border-white/8 text-xs">
                              <th style={{ ...th, width: 80 }}>排名</th>
                              <th style={th}>预测内容</th>
                              <th style={{ ...th, minWidth: 180 }}>得票与支持率</th>
                              {officialDraw && <th style={{ ...th, width: 110 }}>开奖核验</th>}
                              <th style={th}>支持来源</th>
                            </tr>
                          </thead>
                          <tbody className="divide-y divide-slate-200/40 dark:divide-white/5">
                            {g.tally.map((t: ConsensusTallyItem, i: number) => {
                              const pct = Math.round((t.votes / totalVotes) * 100);
                              return (
                                <tr
                                  key={i}
                                  className="hover:bg-violet-500/5 dark:hover:bg-violet-400/5 transition-colors"
                                >
                                  {/* 排名奖章 */}
                                  <td style={td}>
                                    {i === 0 ? (
                                      <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-xs font-bold bg-amber-500/15 text-amber-700 dark:text-amber-300 border border-amber-500/30">
                                        🥇 1st
                                      </span>
                                    ) : i === 1 ? (
                                      <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-xs font-bold glass-subtle text-slate-700 dark:text-slate-200">
                                        🥈 2nd
                                      </span>
                                    ) : i === 2 ? (
                                      <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-xs font-bold bg-orange-500/15 text-orange-700 dark:text-orange-300 border border-orange-500/30">
                                        🥉 3rd
                                      </span>
                                    ) : (
                                      <span className="text-xs text-slate-400 font-mono px-2">
                                        #{i + 1}
                                      </span>
                                    )}
                                  </td>

                                  {/* 预测号码/生肖 */}
                                  <td style={td}>
                                    <ConsensusAtomDisplay atoms={t.preds} />
                                  </td>

                                  {/* 得票与进度条 */}
                                  <td style={td}>
                                    <div className="flex flex-col gap-1.5">
                                      <div className="flex items-center justify-between text-xs font-medium">
                                        <span className="font-bold font-mono text-slate-800 dark:text-slate-200">
                                          {t.votes} 票
                                        </span>
                                        <span className="font-mono text-slate-500 dark:text-slate-400">
                                          {pct}%
                                        </span>
                                      </div>
                                      <div className="w-full bg-slate-500/10 dark:bg-white/5 rounded-full h-2 overflow-hidden">
                                        <div
                                          className={`h-full rounded-full transition-all ${
                                            i === 0
                                              ? "bg-gradient-to-r from-amber-500 to-primary"
                                              : "bg-primary/70"
                                          }`}
                                          style={{ width: `${pct}%` }}
                                        />
                                      </div>
                                    </div>
                                  </td>

                                  {/* 官方开奖核验（若当期已开奖） */}
                                  {officialDraw && (
                                    <td style={td}>
                                      {t.hit === true ? (
                                        <Badge size="sm" variant="success">
                                          🎯 官方命中
                                        </Badge>
                                      ) : t.hit === false ? (
                                        <span className="text-xs text-slate-400">未命中</span>
                                      ) : (
                                        <span className="text-xs text-slate-400">待对奖</span>
                                      )}
                                    </td>
                                  )}

                                  {/* 支持来源 Chip 列表 */}
                                  <td style={{ ...td, minWidth: 160 }}>
                                    <VotersChipList sources={t.sources} />
                                  </td>
                                </tr>
                              );
                            })}
                          </tbody>
                        </table>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        )}
      </div>
    </PageWorkspace>
  );
}

const th: React.CSSProperties = { padding: "10px 12px", fontWeight: 600, fontSize: 13 };
const td: React.CSSProperties = { padding: "12px 12px", verticalAlign: "middle" };
