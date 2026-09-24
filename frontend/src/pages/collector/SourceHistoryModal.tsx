import { useEffect, useState, useCallback } from "react";
import { Spinner } from "@appica/ui-react/spinner";
import { Alert, AlertDescription } from "@appica/ui-react/alert";
import { ApiError } from "../../lib/api";
import {
  collectorApi,
  LOTTERY_LABEL,
  type Lottery,
  type SourceHistoryResult,
} from "../../lib/collector";
import {
  BOSE_COLORS,
  getBose,
  getXiao,
} from "../../lib/lotteryAttr";
import {
  playLabel,
  StatusPill,
  TableContainer,
  tableThClass,
  tableTdClass,
  tableRowClass,
} from "./shared";
import {
  CalendarIcon,
  ClockIcon,
  CloseIcon,
  RefreshIcon,
  ChevronDownIcon,
} from "../../components/icons";

interface SourceHistoryModalProps {
  sourceId: string | null;
  lottery?: Lottery;
  isOpen: boolean;
  onClose: () => void;
}

export function SourceHistoryModal({
  sourceId,
  lottery,
  isOpen,
  onClose,
}: SourceHistoryModalProps) {
  const [data, setData] = useState<SourceHistoryResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Filters & Pagination
  const [statusFilter, setStatusFilter] = useState<string>("");
  const [periodSearch, setPeriodSearch] = useState("");
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(50);
  const [expandedRowId, setExpandedRowId] = useState<number | null>(null);

  const fetchHistory = useCallback(async () => {
    if (!sourceId) return;
    setLoading(true);
    setError(null);
    try {
      const res = await collectorApi.getSourceHistory(sourceId, {
        lottery,
        status: statusFilter || undefined,
        limit: pageSize,
        offset: (page - 1) * pageSize,
      });
      setData(res);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "加载历史数据失败");
    } finally {
      setLoading(false);
    }
  }, [sourceId, lottery, statusFilter, page, pageSize]);

  useEffect(() => {
    if (isOpen && sourceId) {
      setPage(1);
      setExpandedRowId(null);
      void fetchHistory();
    } else {
      setData(null);
      setError(null);
    }
  }, [isOpen, sourceId, statusFilter, pageSize]);

  useEffect(() => {
    if (isOpen && sourceId && page > 1) {
      void fetchHistory();
    }
  }, [page]);

  if (!isOpen || !sourceId) return null;

  const stats = data?.stats;
  const source = data?.source;
  const items = data?.items ?? [];

  // Filter items by client search if typed
  const displayedItems = periodSearch.trim()
    ? items.filter((it) => it.period.includes(periodSearch.trim()))
    : items;

  const totalPages = data ? Math.max(1, Math.ceil(data.total / pageSize)) : 1;

  const renderAtom = (atom: { kind: string; value: string; text?: string | null }, idx: number) => {
    if (atom.kind === "num") {
      const bose = getBose(atom.value);
      const xiao = getXiao(atom.value);
      const bg = BOSE_COLORS[bose]?.bg || "#475569";
      return (
        <span
          key={idx}
          className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-white text-xs font-mono font-bold shadow-2xs"
          style={{ backgroundColor: bg }}
        >
          <span>{atom.value}</span>
          <span className="text-2xs font-normal opacity-90">({xiao})</span>
        </span>
      );
    }
    if (atom.kind === "xiao") {
      return (
        <span
          key={idx}
          className="inline-flex items-center px-2.5 py-0.5 rounded-lg text-xs font-bold bg-violet-500/10 text-violet-700 dark:text-violet-300 border border-violet-400/40 dark:border-violet-400/25 backdrop-blur-md"
        >
          {atom.value}
        </span>
      );
    }
    return (
      <span
        key={idx}
        className="inline-flex items-center px-2 py-0.5 rounded-lg text-xs font-medium glass-subtle text-slate-700 dark:text-slate-300 font-mono"
      >
        {atom.value}
      </span>
    );
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-6 bg-slate-900/40 dark:bg-black/60 backdrop-blur-sm animate-fadeIn">
      <div className="w-full max-w-6xl max-h-[92vh] glass-panel rounded-3xl animate-glassPop flex flex-col overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-slate-200/50 dark:border-white/8 px-6 py-4">
          <div className="space-y-1">
            <div className="flex items-center gap-2.5 flex-wrap">
              <h3 className="text-lg font-bold text-slate-900 dark:text-white flex items-center gap-2">
                <CalendarIcon size={20} className="text-primary" />
                <span>{source?.source_name || sourceId} · 全量历史对奖流水</span>
              </h3>
              <span className="text-xs font-mono px-2 py-0.5 rounded-md glass-subtle text-slate-600 dark:text-slate-400">
                ID: {sourceId}
              </span>
              {source && (
                <>
                  <span className="text-xs px-2 py-0.5 rounded-md bg-primary/10 text-primary font-medium">
                    {LOTTERY_LABEL[source.lottery] || source.lottery}
                  </span>
                  <span className="text-xs px-2 py-0.5 rounded-md glass-subtle text-slate-700 dark:text-slate-300">
                    {playLabel(source.play_type)}
                  </span>
                  <span className="text-xs font-mono px-2 py-0.5 rounded-md glass-subtle text-slate-500 dark:text-slate-400">
                    {source.hit_mode.toUpperCase()}
                  </span>
                </>
              )}
            </div>
            <p className="text-xs text-slate-500 dark:text-slate-400">
              展示该数据源抓取入库的全部历史期数、开奖号码、预测内容、判定结果及虚假自称核验。
            </p>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => void fetchHistory()}
              disabled={loading}
              className="p-2 rounded-xl text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 hover:bg-violet-500/5 dark:hover:bg-violet-400/5 transition-colors cursor-pointer"
              title="刷新数据"
            >
              <RefreshIcon size={18} className={loading ? "animate-spin" : ""} />
            </button>
            <button
              type="button"
              onClick={onClose}
              className="p-2 rounded-xl text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 hover:bg-violet-500/5 dark:hover:bg-violet-400/5 transition-colors cursor-pointer"
              title="关闭窗口"
            >
              <CloseIcon size={20} />
            </button>
          </div>
        </div>

        {/* Content Body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-5">
          {error && (
            <Alert variant="error" className="rounded-2xl border border-rose-400/40 dark:border-rose-400/25 bg-rose-500/10 backdrop-blur-md text-rose-700 dark:text-rose-300">
              <AlertDescription className="text-sm">{error}</AlertDescription>
            </Alert>
          )}

          {/* Aggregate Stats Bar */}
          {stats && (
            <div className="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-7 gap-3">
              <div className="p-3 rounded-2xl glass-subtle">
                <span className="text-2xs font-semibold text-slate-400 uppercase block">历史总期数</span>
                <span className="text-lg font-bold font-mono text-slate-900 dark:text-white mt-1 block">
                  {stats.total} 期
                </span>
              </div>

              <div className="p-3 rounded-2xl glass-subtle">
                <span className="text-2xs font-semibold text-slate-400 uppercase block">官方判定命中率</span>
                <div className="flex items-baseline gap-1 mt-1">
                  <span className={`text-lg font-bold font-mono ${stats.hit_rate >= 50 ? "text-emerald-600 dark:text-emerald-400" : "text-slate-700 dark:text-slate-300"}`}>
                    {stats.hit_rate.toFixed(1)}%
                  </span>
                  <span className="text-xs text-slate-400">({stats.judged}期已判)</span>
                </div>
              </div>

              <div className="p-3 rounded-2xl bg-emerald-500/10 border border-emerald-400/40 dark:border-emerald-400/25 backdrop-blur-md">
                <span className="text-2xs font-semibold text-emerald-600 dark:text-emerald-400 uppercase block">命中次数</span>
                <span className="text-lg font-bold font-mono text-emerald-600 dark:text-emerald-400 mt-1 block">
                  {stats.hits} 次
                </span>
              </div>

              <div className="p-3 rounded-2xl bg-rose-500/10 border border-rose-400/40 dark:border-rose-400/25 backdrop-blur-md">
                <span className="text-2xs font-semibold text-rose-600 dark:text-rose-400 uppercase block">未中(挂)次数</span>
                <span className="text-lg font-bold font-mono text-rose-600 dark:text-rose-400 mt-1 block">
                  {stats.misses} 次
                </span>
              </div>

              <div className="p-3 rounded-2xl glass-subtle">
                <span className="text-2xs font-semibold text-slate-400 uppercase block">待对奖 / 缺期</span>
                <span className="text-lg font-bold font-mono text-slate-700 dark:text-slate-300 mt-1 block">
                  {stats.pending} 待 / {stats.missing} 缺
                </span>
              </div>

              <div className="p-3 rounded-2xl glass-subtle">
                <span className="text-2xs font-semibold text-slate-400 uppercase block">连中 / 连挂极限</span>
                <div className="text-xs font-mono font-bold mt-1.5 space-x-2">
                  <span className="text-emerald-600 dark:text-emerald-400">连中 {stats.longest_hit}</span>
                  <span className="text-slate-400">/</span>
                  <span className="text-rose-600 dark:text-rose-400">连挂 {stats.longest_miss}</span>
                </div>
              </div>

              <div className={`p-3 rounded-2xl border backdrop-blur-md ${
                stats.conflicts > 0
                  ? "bg-amber-500/10 border-amber-400/40 dark:border-amber-400/25"
                  : "bg-slate-500/5 border-slate-400/30 dark:border-slate-400/20"
              }`}>
                <span className="text-2xs font-semibold text-slate-400 uppercase block">虚假自称(冲突)</span>
                <span className={`text-lg font-bold font-mono mt-1 block ${stats.conflicts > 0 ? "text-amber-600 dark:text-amber-400 font-black" : "text-slate-400"}`}>
                  {stats.conflicts > 0 ? `⚠️ ${stats.conflicts} 次不符` : "0 异常"}
                </span>
              </div>
            </div>
          )}

          {/* Filter & Toolbar */}
          <div className="flex items-center justify-between gap-3 flex-wrap glass-subtle p-3 rounded-2xl">
            {/* Status Pills */}
            <div className="flex items-center gap-1.5 flex-wrap">
              {[
                { id: "", label: "全部记录" },
                { id: "hit", label: "已命中" },
                { id: "miss", label: "未命中" },
                { id: "pending", label: "待对奖" },
                { id: "conflict", label: "虚假自称(冲突)" },
                { id: "missing", label: "人工确认缺期" },
              ].map((tab) => {
                const isSelected = statusFilter === tab.id;
                return (
                  <button
                    key={tab.id}
                    type="button"
                    onClick={() => {
                      setStatusFilter(tab.id);
                      setPage(1);
                    }}
                    className={`px-3 py-1 rounded-xl text-xs font-semibold transition-all cursor-pointer ${
                      isSelected
                        ? "glow-button border-0 text-white"
                        : "glass-subtle text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white"
                    }`}
                  >
                    {tab.label}
                  </button>
                );
              })}
            </div>

            {/* Search & Page Size */}
            <div className="flex items-center gap-2.5">
              <input
                type="text"
                value={periodSearch}
                onChange={(e) => setPeriodSearch(e.target.value)}
                placeholder="搜索期号 (如 260)"
                className="w-36 text-xs px-3 py-1.5 rounded-xl glass-input text-slate-800 dark:text-slate-200 placeholder:text-slate-400 dark:placeholder:text-slate-500"
              />

              <select
                value={pageSize}
                onChange={(e) => {
                  setPageSize(Number(e.target.value));
                  setPage(1);
                }}
                className="text-xs px-2.5 py-1.5 rounded-xl glass-input text-slate-700 dark:text-slate-300 cursor-pointer"
              >
                <option value={20}>20 条/页</option>
                <option value={50}>50 条/页</option>
                <option value={100}>100 条/页</option>
                <option value={200}>200 条/页</option>
              </select>
            </div>
          </div>

          {/* Historical Records Table */}
          {loading ? (
            <div className="py-20 flex justify-center items-center gap-3 text-slate-400 text-sm">
              <Spinner aria-label="加载历史数据中" />
              <span>正在获取该数据源历史流水…</span>
            </div>
          ) : displayedItems.length === 0 ? (
            <div className="py-16 text-center text-sm text-slate-400">
              暂未检索到符合条件的该源历史预测记录。
            </div>
          ) : (
            <TableContainer>
              <thead>
                <tr>
                  <th className={tableThClass}>期号 / 开奖日</th>
                  <th className={tableThClass}>官方开奖号码</th>
                  <th className={tableThClass}>预测内容</th>
                  <th className={tableThClass}>对奖判定</th>
                  <th className={tableThClass}>来源自称</th>
                  <th className={`${tableThClass} text-right`}>明细</th>
                </tr>
              </thead>
              <tbody>
                {displayedItems.map((item) => {
                  const isExpanded = expandedRowId === item.id;
                  const draw = item.draw;
                  const tema = draw?.tema;
                  const temaDetail = draw?.tema_detail;

                  return (
                    <div key={item.id} style={{ display: "contents" }}>
                      <tr className={`${tableRowClass} ${item.is_conflict ? "bg-amber-500/5 dark:bg-amber-400/5" : ""}`}>
                        {/* Period / Date */}
                        <td className={tableTdClass}>
                          <div className="font-mono font-bold text-slate-900 dark:text-white flex items-center gap-1.5">
                            <span>{item.period}</span>
                            {item.group_key && item.group_key !== "default" && item.group_key !== "0" && (
                              <span className="text-2xs font-normal px-1.5 py-0.5 rounded bg-slate-500/10 text-slate-500 dark:text-slate-400">
                                /{item.group_key}
                              </span>
                            )}
                          </div>
                          <div className="text-2xs text-slate-400 mt-0.5 flex items-center gap-1">
                            <ClockIcon size={11} />
                            <span>{draw?.draw_date || (item.fetched_at ? item.fetched_at.slice(0, 10) : "—")}</span>
                          </div>
                        </td>

                        {/* Official Draw Balls */}
                        <td className={tableTdClass}>
                          {draw && tema ? (
                            <div className="flex items-center gap-2 flex-wrap">
                              {/* Balls 1-6 */}
                              <div className="flex items-center gap-1">
                                {draw.balls.map((ballNum, bIdx) => {
                                  const ballBose = getBose(ballNum);
                                  const bBg = BOSE_COLORS[ballBose]?.bg || "#475569";
                                  return (
                                    <span
                                      key={bIdx}
                                      className="inline-flex items-center justify-center w-5.5 h-5.5 rounded-full text-2xs font-mono font-bold text-white shadow-2xs"
                                      style={{ backgroundColor: bBg }}
                                      title={`正码 ${bIdx + 1}: ${ballNum} (${ballBose}波)`}
                                    >
                                      {ballNum}
                                    </span>
                                  );
                                })}
                              </div>

                              <span className="text-slate-300 dark:text-slate-600 font-bold">+</span>

                              {/* Special Tema Ball */}
                              <div className="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full glass-subtle">
                                <span
                                  className="inline-flex items-center justify-center w-5.5 h-5.5 rounded-full text-2xs font-mono font-bold text-white shadow-2xs"
                                  style={{ backgroundColor: BOSE_COLORS[temaDetail?.bose || getBose(tema)]?.bg || "#ef4444" }}
                                >
                                  {tema}
                                </span>
                                <span className="text-xs font-semibold text-slate-700 dark:text-slate-300">
                                  {temaDetail?.xiao || getXiao(tema)}
                                </span>
                                <span className="text-2xs text-slate-400 font-mono">
                                  {temaDetail?.size}{temaDetail?.odd}
                                </span>
                              </div>
                            </div>
                          ) : (
                            <span className="text-xs text-slate-400 italic">待开奖 / 暂无开奖数据</span>
                          )}
                        </td>

                        {/* Prediction Atoms */}
                        <td className={tableTdClass}>
                          {item.is_missing ? (
                            <span className="text-xs text-slate-400 italic">【确认缺期，未发表】</span>
                          ) : (
                            <div className="flex items-center gap-1.5 flex-wrap">
                              {item.preds.map((atom, aIdx) => renderAtom(atom, aIdx))}
                            </div>
                          )}
                        </td>

                        {/* Official Verification Status */}
                        <td className={tableTdClass}>
                          {item.official_hit === 1 ? (
                            <StatusPill variant="success">已命中</StatusPill>
                          ) : item.official_hit === 0 ? (
                            item.is_missing ? (
                              <StatusPill variant="neutral">缺期(按挂)</StatusPill>
                            ) : (
                              <StatusPill variant="danger">未中(挂)</StatusPill>
                            )
                          ) : (
                            <StatusPill variant="neutral">待对奖</StatusPill>
                          )}
                        </td>

                        {/* Claimed Status & Conflict check */}
                        <td className={tableTdClass}>
                          {item.is_conflict ? (
                            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-lg text-xs font-bold bg-rose-500/10 text-rose-700 dark:text-rose-300 border border-rose-400/40 dark:border-rose-400/25 backdrop-blur-md">
                              <span>⚠️ 自称中 (实测挂)</span>
                            </span>
                          ) : (
                            <span className="text-xs font-mono text-slate-500 dark:text-slate-400">
                              {item.claimed_status === "hit"
                                ? "自称: 命中"
                                : item.claimed_status === "miss"
                                ? "自称: 未中"
                                : item.claimed_status === "missing"
                                ? "自称: 缺期"
                                : `自称: ${item.claimed_status || "未知"}`}
                            </span>
                          )}
                        </td>

                        {/* Action Details toggle */}
                        <td className={`${tableTdClass} text-right`}>
                          <button
                            type="button"
                            onClick={() => setExpandedRowId(isExpanded ? null : item.id)}
                            className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg text-xs font-medium border border-slate-200/50 dark:border-white/8 hover:bg-violet-500/5 dark:hover:bg-violet-400/5 text-slate-700 dark:text-slate-300 transition-colors cursor-pointer"
                          >
                            <span>{isExpanded ? "收起" : "依据"}</span>
                            <ChevronDownIcon size={12} className={`transition-transform duration-200 ${isExpanded ? "rotate-180" : ""}`} />
                          </button>
                        </td>
                      </tr>

                      {/* Expanded Evidence Drawer */}
                      {isExpanded && (
                        <tr className="bg-slate-500/5 dark:bg-white/[0.03]">
                          <td colSpan={6} className="p-4 sm:p-5 border-b border-slate-200/50 dark:border-white/8">
                            <div className="space-y-3">
                              <div className="flex items-center justify-between text-xs text-slate-500 dark:text-slate-400">
                                <span className="font-semibold text-slate-800 dark:text-slate-200">
                                  第 {item.period} 期 抓取证据与对奖详细判定报告
                                </span>
                                <span>抓取时间: {item.fetched_at || "—"}</span>
                              </div>

                              {/* Explanation */}
                              {item.hit_detail && (
                                <div className="p-3 rounded-xl glass-subtle space-y-1.5 text-xs">
                                  <div className="flex items-center gap-2">
                                    <span className="font-bold text-slate-700 dark:text-slate-300">对奖结论说明：</span>
                                    <span className="text-slate-600 dark:text-slate-300">
                                      {typeof item.hit_detail === "object" && (item.hit_detail as any).explanation
                                        ? String((item.hit_detail as any).explanation)
                                        : "已按规则标准逻辑对奖"}
                                    </span>
                                  </div>
                                  {typeof item.hit_detail === "object" && (item.hit_detail as any).rule && (
                                    <div className="text-slate-400 text-2xs">
                                      适用判定规则: {String((item.hit_detail as any).rule)} (版本: {String((item.hit_detail as any).rule_version || "—")})
                                    </div>
                                  )}
                                </div>
                              )}

                              {/* Raw Scraped Text */}
                              <div>
                                <span className="text-2xs font-semibold text-slate-400 uppercase mb-1 block">
                                  网页爬虫原始解析文本 (Scraped Raw Text):
                                </span>
                                <pre className="p-3 rounded-xl bg-slate-950/90 backdrop-blur-md text-emerald-400 font-mono text-xs overflow-x-auto whitespace-pre-wrap leading-relaxed shadow-inner border border-white/10">
                                  {item.raw_text || "无原始文本内容"}
                                </pre>
                              </div>

                              {item.final_url && (
                                <div className="text-2xs text-slate-400 truncate">
                                  抓取地址:{" "}
                                  <a
                                    href={item.final_url}
                                    target="_blank"
                                    rel="noreferrer"
                                    className="text-primary hover:underline"
                                  >
                                    {item.final_url}
                                  </a>
                                </div>
                              )}
                            </div>
                          </td>
                        </tr>
                      )}
                    </div>
                  );
                })}
              </tbody>
            </TableContainer>
          )}

          {/* Pagination Footer */}
          {data && data.total > 0 && (
            <div className="flex items-center justify-between pt-3 border-t border-slate-200/50 dark:border-white/8 flex-wrap gap-2">
              <span className="text-xs text-slate-500 dark:text-slate-400">
                显示第 {(page - 1) * pageSize + 1} - {Math.min(page * pageSize, data.total)} 条，共 {data.total} 期历史数据
              </span>

              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                  disabled={page === 1 || loading}
                  className="px-3.5 py-1.5 rounded-xl text-xs font-medium border border-slate-200/50 dark:border-white/8 hover:bg-violet-500/5 dark:hover:bg-violet-400/5 text-slate-700 dark:text-slate-300 disabled:opacity-40 transition-colors cursor-pointer"
                >
                  上一页
                </button>
                <span className="text-xs font-mono font-medium text-slate-600 dark:text-slate-400 px-1">
                  {page} / {totalPages}
                </span>
                <button
                  type="button"
                  onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                  disabled={page >= totalPages || loading}
                  className="px-3.5 py-1.5 rounded-xl text-xs font-medium border border-slate-200/50 dark:border-white/8 hover:bg-violet-500/5 dark:hover:bg-violet-400/5 text-slate-700 dark:text-slate-300 disabled:opacity-40 transition-colors cursor-pointer"
                >
                  下一页
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
