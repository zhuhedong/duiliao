import { useCallback, useEffect, useMemo, useState } from "react";
import { Alert, AlertDescription } from "../../components/ui/alert";
import { Spinner } from "../../components/ui/spinner";
import { RefreshIcon } from "../../components/icons";
import { ApiError } from "../../lib/api";
import {
  collectorApi,
  LOTTERY_LABEL,
  type Lottery,
  type TrendItem,
} from "../../lib/collector";
import {
  BOSE_COLORS,
  computeBallAttr,
  getBose,
  getXiao,
  padNum,
} from "../../lib/lotteryAttr";
import { LOTTERIES, PageWorkspace } from "./shared";

type TrendTab = "draw" | "wei" | "tou" | "bose" | "wuxing" | "shengxiao";

interface CellValue {
  value?: string; // ball number if hit
  index?: number; // omission if miss
  color?: "red" | "blue" | "green";
  allValues?: Array<{ num: string; color: "red" | "blue" | "green" }>;
}

const WEI_COLS = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"];
const TOU_COLS = ["0", "1", "2", "3", "4"];
const BOSE_COLS = ["红波", "蓝波", "绿波"];
const WUXING_COLS = ["金", "木", "水", "火", "土"];
const SHENGXIAO_COLS = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"];

const BOSE_MAP: Record<string, "red" | "blue" | "green"> = {
  红: "red",
  蓝: "blue",
  绿: "green",
};

export function TrendPage() {
  const [lottery, setLottery] = useState<Lottery>("macau");
  const [limit, setLimit] = useState<number>(100);
  const [activeTab, setActiveTab] = useState<TrendTab>("draw");
  const [mode, setMode] = useState<"tema" | "pingte">("tema"); // tema matches djds-129 exactly
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [trendList, setTrendList] = useState<TrendItem[]>([]);

  const loadData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await collectorApi.getTrend(lottery, limit);
      if (res && Array.isArray(res.data)) {
        setTrendList(res.data);
      } else {
        setTrendList([]);
      }
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "获取走势数据失败");
    } finally {
      setLoading(false);
    }
  }, [lottery, limit]);

  useEffect(() => {
    void loadData();
  }, [loadData]);

  // Compute table matrices matching djds-129 algorithm
  const { weiRows, touRows, boseRows, wuxingRows, shengxiaoRows } = useMemo(() => {
    if (!trendList.length) {
      return {
        weiRows: [],
        touRows: [],
        boseRows: [],
        wuxingRows: [],
        shengxiaoRows: [],
      };
    }

    // Process chronological (from oldest to newest)
    const reversed = [...trendList].reverse();

    // 1. Weihao (尾号)
    const weiRowsAcc: Array<{ period: string; cells: CellValue[] }> = [];
    let prevWeiOmission: number[] = new Array(WEI_COLS.length).fill(0);

    for (const item of reversed) {
      const balls = item.code.map((b) => padNum(b));
      const targetBalls = mode === "tema" ? [balls[6]] : balls;
      const hitMap: Record<number, Array<{ num: string; color: "red" | "blue" | "green" }>> = {};

      for (const b of targetBalls) {
        if (!b) continue;
        const tail = parseInt(b[1] ?? b[0], 10);
        const colIdx = tail;
        const c = BOSE_MAP[getBose(b)] || "red";
        if (!hitMap[colIdx]) hitMap[colIdx] = [];
        hitMap[colIdx].push({ num: b, color: c });
      }

      const cells: CellValue[] = [];
      const currentOmission: number[] = [];
      for (let c = 0; c < WEI_COLS.length; c++) {
        if (hitMap[c] && hitMap[c].length > 0) {
          cells.push({
            value: hitMap[c][0].num,
            color: hitMap[c][0].color,
            allValues: hitMap[c],
          });
          currentOmission.push(0);
        } else {
          const om = (prevWeiOmission[c] || 0) + 1;
          cells.push({ index: om });
          currentOmission.push(om);
        }
      }
      prevWeiOmission = currentOmission;
      weiRowsAcc.unshift({ period: item.period, cells });
    }

    // 2. Touhao (头号 0-4)
    const touRowsAcc: Array<{ period: string; cells: CellValue[] }> = [];
    let prevTouOmission: number[] = new Array(TOU_COLS.length).fill(0);

    for (const item of reversed) {
      const balls = item.code.map((b) => padNum(b));
      const targetBalls = mode === "tema" ? [balls[6]] : balls;
      const hitMap: Record<number, Array<{ num: string; color: "red" | "blue" | "green" }>> = {};

      for (const b of targetBalls) {
        if (!b) continue;
        const head = parseInt(b[0], 10);
        const colIdx = head;
        if (colIdx >= 0 && colIdx < TOU_COLS.length) {
          const c = BOSE_MAP[getBose(b)] || "red";
          if (!hitMap[colIdx]) hitMap[colIdx] = [];
          hitMap[colIdx].push({ num: b, color: c });
        }
      }

      const cells: CellValue[] = [];
      const currentOmission: number[] = [];
      for (let c = 0; c < TOU_COLS.length; c++) {
        if (hitMap[c] && hitMap[c].length > 0) {
          cells.push({
            value: hitMap[c][0].num,
            color: hitMap[c][0].color,
            allValues: hitMap[c],
          });
          currentOmission.push(0);
        } else {
          const om = (prevTouOmission[c] || 0) + 1;
          cells.push({ index: om });
          currentOmission.push(om);
        }
      }
      prevTouOmission = currentOmission;
      touRowsAcc.unshift({ period: item.period, cells });
    }

    // 3. Bose (波色: 红波, 蓝波, 绿波)
    const boseRowsAcc: Array<{ period: string; cells: CellValue[] }> = [];
    let prevBoseOmission: number[] = new Array(BOSE_COLS.length).fill(0);

    for (const item of reversed) {
      const balls = item.code.map((b) => padNum(b));
      const targetBalls = mode === "tema" ? [balls[6]] : balls;
      const hitMap: Record<number, Array<{ num: string; color: "red" | "blue" | "green" }>> = {};

      for (const b of targetBalls) {
        if (!b) continue;
        const bs = getBose(b);
        const colIdx = bs === "红" ? 0 : bs === "蓝" ? 1 : 2;
        const c = BOSE_MAP[bs] || "red";
        if (!hitMap[colIdx]) hitMap[colIdx] = [];
        hitMap[colIdx].push({ num: b, color: c });
      }

      const cells: CellValue[] = [];
      const currentOmission: number[] = [];
      for (let c = 0; c < BOSE_COLS.length; c++) {
        if (hitMap[c] && hitMap[c].length > 0) {
          cells.push({
            value: hitMap[c][0].num,
            color: hitMap[c][0].color,
            allValues: hitMap[c],
          });
          currentOmission.push(0);
        } else {
          const om = (prevBoseOmission[c] || 0) + 1;
          cells.push({ index: om });
          currentOmission.push(om);
        }
      }
      prevBoseOmission = currentOmission;
      boseRowsAcc.unshift({ period: item.period, cells });
    }

    // 4. Wuxing (五行: 金, 木, 水, 火, 土)
    const wuxingRowsAcc: Array<{ period: string; cells: CellValue[] }> = [];
    let prevWuxingOmission: number[] = new Array(WUXING_COLS.length).fill(0);

    for (const item of reversed) {
      const balls = item.code.map((b) => padNum(b));
      const targetBalls = mode === "tema" ? [balls[6]] : balls;
      const hitMap: Record<number, Array<{ num: string; color: "red" | "blue" | "green" }>> = {};

      for (const b of targetBalls) {
        if (!b) continue;
        const attr = computeBallAttr(b);
        const wx = attr.wuxing || "";
        const colIdx = WUXING_COLS.indexOf(wx);
        if (colIdx >= 0) {
          const c = BOSE_MAP[getBose(b)] || "red";
          if (!hitMap[colIdx]) hitMap[colIdx] = [];
          hitMap[colIdx].push({ num: b, color: c });
        }
      }

      const cells: CellValue[] = [];
      const currentOmission: number[] = [];
      for (let c = 0; c < WUXING_COLS.length; c++) {
        if (hitMap[c] && hitMap[c].length > 0) {
          cells.push({
            value: hitMap[c][0].num,
            color: hitMap[c][0].color,
            allValues: hitMap[c],
          });
          currentOmission.push(0);
        } else {
          const om = (prevWuxingOmission[c] || 0) + 1;
          cells.push({ index: om });
          currentOmission.push(om);
        }
      }
      prevWuxingOmission = currentOmission;
      wuxingRowsAcc.unshift({ period: item.period, cells });
    }

    // 5. Shengxiao (生肖: 12生肖)
    const shengxiaoRowsAcc: Array<{ period: string; cells: CellValue[] }> = [];
    let prevShengxiaoOmission: number[] = new Array(SHENGXIAO_COLS.length).fill(0);

    for (const item of reversed) {
      const balls = item.code.map((b) => padNum(b));
      const targetBalls = mode === "tema" ? [balls[6]] : balls;
      const hitMap: Record<number, Array<{ num: string; color: "red" | "blue" | "green" }>> = {};

      for (const b of targetBalls) {
        if (!b) continue;
        const xiao = getXiao(b);
        const colIdx = SHENGXIAO_COLS.indexOf(xiao);
        if (colIdx >= 0) {
          const c = BOSE_MAP[getBose(b)] || "red";
          if (!hitMap[colIdx]) hitMap[colIdx] = [];
          hitMap[colIdx].push({ num: b, color: c });
        }
      }

      const cells: CellValue[] = [];
      const currentOmission: number[] = [];
      for (let c = 0; c < SHENGXIAO_COLS.length; c++) {
        if (hitMap[c] && hitMap[c].length > 0) {
          cells.push({
            value: hitMap[c][0].num,
            color: hitMap[c][0].color,
            allValues: hitMap[c],
          });
          currentOmission.push(0);
        } else {
          const om = (prevShengxiaoOmission[c] || 0) + 1;
          cells.push({ index: om });
          currentOmission.push(om);
        }
      }
      prevShengxiaoOmission = currentOmission;
      shengxiaoRowsAcc.unshift({ period: item.period, cells });
    }

    return {
      weiRows: weiRowsAcc,
      touRows: touRowsAcc,
      boseRows: boseRowsAcc,
      wuxingRows: wuxingRowsAcc,
      shengxiaoRows: shengxiaoRowsAcc,
    };
  }, [trendList, mode]);

  // Compute column statistics for summary row
  const computeStats = (
    rows: Array<{ period: string; cells: CellValue[] }>,
    colCount: number
  ) => {
    const hits = new Array(colCount).fill(0);
    const maxOmission = new Array(colCount).fill(0);
    const curOmission = new Array(colCount).fill(0);

    for (let c = 0; c < colCount; c++) {
      let maxOm = 0;
      let count = 0;
      for (const r of rows) {
        if (r.cells[c]?.value) {
          count++;
        } else if (r.cells[c]?.index) {
          if (r.cells[c].index! > maxOm) maxOm = r.cells[c].index!;
        }
      }
      hits[c] = count;
      maxOmission[c] = maxOm;
      curOmission[c] = rows[0]?.cells[c]?.index ?? 0;
    }
    return { hits, maxOmission, curOmission };
  };

  return (
    <PageWorkspace
      summary="官方开奖落球走势分析，支持尾号、头号、波色、五行、生肖及特码/平特多维走势与遗漏统计（兼容 djds-129.dhd1k5.com）"
    >
      {/* Top Controls Card */}
      <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl p-4 shadow-xs mb-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex flex-wrap items-center gap-2">
            {/* Lottery Selector */}
            <div className="flex items-center gap-1 bg-slate-100 dark:bg-slate-800/80 p-1 rounded-xl text-xs font-medium">
              {LOTTERIES.map((l) => (
                <button
                  key={l.value}
                  type="button"
                  onClick={() => setLottery(l.value)}
                  className={`px-3 py-1.5 rounded-lg transition-all ${
                    lottery === l.value
                      ? "bg-white dark:bg-slate-700 text-sky-600 dark:text-sky-400 font-semibold shadow-xs"
                      : "text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200"
                  }`}
                >
                  {l.label}
                </button>
              ))}
            </div>

            {/* Limit Selector */}
            <div className="flex items-center gap-1 bg-slate-100 dark:bg-slate-800/80 p-1 rounded-xl text-xs">
              {[30, 50, 100, 200].map((lim) => (
                <button
                  key={lim}
                  type="button"
                  onClick={() => setLimit(lim)}
                  className={`px-2.5 py-1.5 rounded-lg transition-all ${
                    limit === lim
                      ? "bg-white dark:bg-slate-700 text-slate-900 dark:text-white font-semibold shadow-xs"
                      : "text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200"
                  }`}
                >
                  {lim}期
                </button>
              ))}
            </div>

            {/* Mode Selector */}
            <div className="flex items-center gap-1 bg-slate-100 dark:bg-slate-800/80 p-1 rounded-xl text-xs">
              <button
                type="button"
                onClick={() => setMode("tema")}
                className={`px-3 py-1.5 rounded-lg transition-all ${
                  mode === "tema"
                    ? "bg-sky-500 text-white font-semibold shadow-xs"
                    : "text-slate-600 dark:text-slate-400 hover:text-slate-900"
                }`}
              >
                特码走势
              </button>
              <button
                type="button"
                onClick={() => setMode("pingte")}
                className={`px-3 py-1.5 rounded-lg transition-all ${
                  mode === "pingte"
                    ? "bg-sky-500 text-white font-semibold shadow-xs"
                    : "text-slate-600 dark:text-slate-400 hover:text-slate-900"
                }`}
              >
                平特走势(7码)
              </button>
            </div>
          </div>

          {/* Refresh Button */}
          <button
            type="button"
            onClick={() => void loadData()}
            disabled={loading}
            className="flex items-center gap-1.5 px-3.5 py-2 rounded-xl text-xs font-semibold bg-sky-500 hover:bg-sky-600 text-white transition-colors disabled:opacity-50 cursor-pointer shadow-xs"
          >
            <RefreshIcon size={14} className={loading ? "animate-spin" : ""} />
            <span>刷新走势</span>
          </button>
        </div>

        {/* Tab Bar */}
        <div className="flex items-center gap-2 mt-4 border-t border-slate-100 dark:border-slate-800/80 pt-3 overflow-x-auto">
          {[
            { key: "draw", label: "开奖" },
            { key: "wei", label: "尾号" },
            { key: "tou", label: "头号" },
            { key: "bose", label: "波色" },
            { key: "wuxing", label: "五行" },
            { key: "shengxiao", label: "生肖" },
          ].map((tab) => (
            <button
              key={tab.key}
              type="button"
              onClick={() => setActiveTab(tab.key as TrendTab)}
              className={`px-4 py-2 rounded-xl text-xs font-medium transition-all ${
                activeTab === tab.key
                  ? "bg-slate-900 text-white dark:bg-white dark:text-slate-900 font-bold shadow-xs"
                  : "bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 hover:bg-slate-200 dark:hover:bg-slate-700"
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {error && (
        <Alert variant="error" className="mb-4">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      {loading && trendList.length === 0 ? (
        <div className="flex items-center justify-center p-16">
          <Spinner className="w-8 h-8 text-sky-500" />
        </div>
      ) : (
        <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl overflow-hidden shadow-xs">
          {/* TAB 1: 开奖 (Draws history list matching target site) */}
          {activeTab === "draw" && (
            <div className="divide-y divide-slate-100 dark:divide-slate-800">
              {trendList.map((item) => {
                const balls = item.code.map((b) => padNum(b));
                const zBalls = balls.slice(0, 6);
                const temaBall = balls[6];

                return (
                  <div key={item.id} className="p-4 transition-colors hover:bg-slate-50/50 dark:hover:bg-slate-800/20">
                    <div className="text-xs font-semibold text-slate-500 dark:text-slate-400 mb-3 flex items-center justify-between">
                      <div>
                        <span className="font-bold text-slate-700 dark:text-slate-200">
                          {LOTTERY_LABEL[lottery] || lottery}六合彩
                        </span>{" "}
                        · 第 <span className="font-mono text-sky-600 dark:text-sky-400">{item.period}</span> 期
                      </div>
                      <div className="text-slate-400 font-mono text-[11px]">{item.date}</div>
                    </div>

                    <div className="flex flex-wrap items-center gap-3">
                      {/* Normal 6 balls */}
                      <div className="flex items-center gap-2">
                        {zBalls.map((b, idx) => {
                          const attr = computeBallAttr(b);
                          const boseCol = BOSE_COLORS[attr.bose] || { bg: "#64748b" };
                          return (
                            <div key={idx} className="flex flex-col items-center">
                              <div
                                className="w-8 h-8 rounded-full flex items-center justify-center font-bold font-mono text-xs text-white shadow-xs"
                                style={{ backgroundColor: boseCol.bg }}
                              >
                                {b}
                              </div>
                              <span className="text-[10px] text-slate-500 dark:text-slate-400 mt-1">
                                {attr.xiao} / {attr.wuxing || "—"}
                              </span>
                            </div>
                          );
                        })}
                      </div>

                      <div className="text-slate-400 font-bold text-lg px-1">+</div>

                      {/* Special ball (特码) */}
                      {temaBall && (
                        <div className="flex flex-col items-center">
                          <div
                            className="w-8 h-8 rounded-full flex items-center justify-center font-bold font-mono text-xs text-white ring-2 ring-amber-400 shadow-md"
                            style={{
                              backgroundColor: BOSE_COLORS[getBose(temaBall)]?.bg || "#e5484d",
                            }}
                          >
                            {temaBall}
                          </div>
                          <span className="text-[10px] font-semibold text-amber-600 dark:text-amber-400 mt-1">
                            {getXiao(temaBall)} / {computeBallAttr(temaBall).wuxing || "—"}
                          </span>
                        </div>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          )}

          {/* TAB 2: 尾号 (Tail 0-9) */}
          {activeTab === "wei" && (
            <TrendTable
              columns={WEI_COLS}
              rows={weiRows}
              stats={computeStats(weiRows, WEI_COLS.length)}
            />
          )}

          {/* TAB 3: 头号 (Head 0-4) */}
          {activeTab === "tou" && (
            <TrendTable
              columns={TOU_COLS}
              rows={touRows}
              stats={computeStats(touRows, TOU_COLS.length)}
            />
          )}

          {/* TAB 4: 波色 (红波, 蓝波, 绿波) */}
          {activeTab === "bose" && (
            <TrendTable
              columns={BOSE_COLS}
              rows={boseRows}
              stats={computeStats(boseRows, BOSE_COLS.length)}
            />
          )}

          {/* TAB 5: 五行 (金, 木, 水, 火, 土) */}
          {activeTab === "wuxing" && (
            <TrendTable
              columns={WUXING_COLS}
              rows={wuxingRows}
              stats={computeStats(wuxingRows, WUXING_COLS.length)}
            />
          )}

          {/* TAB 6: 生肖 (12生肖) */}
          {activeTab === "shengxiao" && (
            <TrendTable
              columns={SHENGXIAO_COLS}
              rows={shengxiaoRows}
              stats={computeStats(shengxiaoRows, SHENGXIAO_COLS.length)}
            />
          )}
        </div>
      )}
    </PageWorkspace>
  );
}

interface TrendTableProps {
  columns: string[];
  rows: Array<{ period: string; cells: CellValue[] }>;
  stats: {
    hits: number[];
    maxOmission: number[];
    curOmission: number[];
  };
}

function TrendTable({ columns, rows, stats }: TrendTableProps) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-center border-collapse text-xs select-none">
        <thead>
          <tr className="bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-200 font-semibold border-b border-slate-200 dark:border-slate-700">
            <th className="py-2.5 px-3 border-r border-slate-200 dark:border-slate-700 w-20 sticky left-0 bg-slate-100 dark:bg-slate-800 z-10">
              期号
            </th>
            {columns.map((col) => (
              <th key={col} className="py-2.5 px-2 border-r border-slate-200 dark:border-slate-700 min-w-[38px]">
                {col}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-100 dark:divide-slate-800 font-mono">
          {rows.map((row) => (
            <tr key={row.period} className="hover:bg-slate-50/70 dark:hover:bg-slate-800/40">
              <td className="py-2 px-3 border-r border-slate-100 dark:border-slate-800 text-slate-500 dark:text-slate-400 font-medium sticky left-0 bg-white dark:bg-slate-900 z-10 text-[11px]">
                {row.period}
              </td>
              {row.cells.map((cell, idx) => {
                if (cell.value) {
                  const bgClass =
                    cell.color === "green"
                      ? "bg-emerald-500 text-white font-bold"
                      : cell.color === "blue"
                      ? "bg-blue-600 text-white font-bold"
                      : "bg-rose-500 text-white font-bold";

                  return (
                    <td
                      key={idx}
                      className={`py-1.5 px-1 border-r border-slate-100 dark:border-slate-800 ${bgClass}`}
                      title={
                        cell.allValues && cell.allValues.length > 1
                          ? `开出: ${cell.allValues.map((v) => v.num).join(", ")}`
                          : undefined
                      }
                    >
                      <span className="inline-block">{cell.value}</span>
                      {cell.allValues && cell.allValues.length > 1 && (
                        <span className="text-[9px] block opacity-80">({cell.allValues.length}码)</span>
                      )}
                    </td>
                  );
                }

                return (
                  <td
                    key={idx}
                    className="py-1.5 px-1 border-r border-slate-100 dark:border-slate-800 text-slate-400 dark:text-slate-500 text-[11px]"
                  >
                    {cell.index || 1}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
        {/* Summary Footer */}
        <tfoot>
          <tr className="bg-slate-50 dark:bg-slate-800/60 font-semibold text-slate-700 dark:text-slate-200 border-t border-slate-200 dark:border-slate-700">
            <td className="py-2 px-3 border-r border-slate-200 dark:border-slate-700 sticky left-0 bg-slate-50 dark:bg-slate-800/60 z-10 text-[11px]">
              出现次数
            </td>
            {stats.hits.map((h, idx) => (
              <td key={idx} className="py-2 px-1 border-r border-slate-200 dark:border-slate-700 text-sky-600 dark:text-sky-400 font-bold">
                {h}
              </td>
            ))}
          </tr>
          <tr className="bg-slate-50 dark:bg-slate-800/60 text-slate-500 dark:text-slate-400">
            <td className="py-2 px-3 border-r border-slate-200 dark:border-slate-700 sticky left-0 bg-slate-50 dark:bg-slate-800/60 z-10 text-[11px]">
              当前遗漏
            </td>
            {stats.curOmission.map((om, idx) => (
              <td key={idx} className="py-2 px-1 border-r border-slate-200 dark:border-slate-700">
                {om}
              </td>
            ))}
          </tr>
          <tr className="bg-slate-50 dark:bg-slate-800/60 text-slate-500 dark:text-slate-400">
            <td className="py-2 px-3 border-r border-slate-200 dark:border-slate-700 sticky left-0 bg-slate-50 dark:bg-slate-800/60 z-10 text-[11px]">
              最大遗漏
            </td>
            {stats.maxOmission.map((om, idx) => (
              <td key={idx} className="py-2 px-1 border-r border-slate-200 dark:border-slate-700">
                {om}
              </td>
            ))}
          </tr>
        </tfoot>
      </table>
    </div>
  );
}
