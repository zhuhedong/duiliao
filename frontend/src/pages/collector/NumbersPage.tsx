import { useCallback, useEffect, useMemo, useState } from "react";
import { Spinner } from "@appica/ui-react/spinner";
import { Alert, AlertDescription } from "@appica/ui-react/alert";
import { ApiError } from "../../lib/api";
import { collectorApi, type NumberAttr } from "../../lib/collector";
import {
  PageHeader,
  SectionCard,
  TableContainer,
  tableThClass,
  tableTdClass,
  tableRowClass,
} from "./shared";
import { CalendarIcon } from "../../components/icons";

const BOSE_STYLES: Record<string, { bg: string; text: string }> = {
  红: { bg: "#e5484d", text: "#ffffff" },
  蓝: { bg: "#3b82f6", text: "#ffffff" },
  绿: { bg: "#22a06b", text: "#ffffff" },
};

const WUXING_COLORS: Record<string, string> = {
  金: "#b8860b",
  木: "#22a06b",
  水: "#3b82f6",
  火: "#e5484d",
  土: "#a1662f",
};

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

function NumberBall({ num, bose }: { num: string; bose: string }) {
  const cfg = BOSE_STYLES[bose] || { bg: "#64748b", text: "#ffffff" };
  return (
    <div
      className="w-8 h-8 rounded-full flex items-center justify-center font-bold font-mono text-xs shadow-xs text-white select-none transition-transform hover:scale-110"
      style={{ backgroundColor: cfg.bg }}
    >
      {num}
    </div>
  );
}

export function CollectorNumbersPage() {
  const [date, setDate] = useState(today());
  const [items, setItems] = useState<NumberAttr[]>([]);
  const [wuxingAvailable, setWuxingAvailable] = useState(true);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Filter state
  const [boseFilter, setBoseFilter] = useState<string>("all");
  const [genderFilter, setGenderFilter] = useState<string>("all");
  const [keyword, setKeyword] = useState<string>("");

  const load = useCallback(async (d: string) => {
    setLoading(true);
    setError(null);
    try {
      const res = await collectorApi.numbers(d);
      setItems(res.items);
      setWuxingAvailable(res.wuxing_available);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "加载号码资料失败");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load(date);
  }, [date, load]);

  const filteredItems = useMemo(() => {
    return items.filter((item) => {
      if (boseFilter !== "all" && item.bose !== boseFilter) return false;
      if (genderFilter !== "all" && item.gender !== genderFilter) return false;
      if (keyword.trim()) {
        const kw = keyword.trim().toLowerCase();
        const mNum = item.num.includes(kw);
        const mXiao = item.xiao.toLowerCase().includes(kw);
        const mWuxing = item.wuxing?.toLowerCase().includes(kw);
        const mJiaye = item.jiaye.includes(kw);
        const mGender = item.gender?.toLowerCase().includes(kw);
        const mTianDi = item.tian_di?.toLowerCase().includes(kw);
        if (!mNum && !mXiao && !mWuxing && !mJiaye && !mGender && !mTianDi) return false;
      }
      return true;
    });
  }, [items, boseFilter, genderFilter, keyword]);

  return (
    <div className="space-y-6">
      <PageHeader
        title="号码资料属性字典"
        desc="01–49 号码全属性划分字典。生肖与家野按所选参考日期计算（农历春节自动切换），波色、大小、单双、头尾、合数为数学固定属性。"
      />

      {error && (
        <Alert variant="error" className="rounded-2xl border border-rose-400/40 dark:border-rose-400/25 bg-rose-500/10 text-rose-700 dark:text-rose-300 backdrop-blur-md">
          <AlertDescription className="text-sm">{error}</AlertDescription>
        </Alert>
      )}

      {/* 控制与过滤面板 */}
      <SectionCard
        title={
          <div className="flex items-center gap-2">
            <CalendarIcon size={18} className="text-primary" />
            <span>查询参考日期与号码属性过滤</span>
          </div>
        }
        subtitle="切换年份或输入生肖、号码快速定位对应属性"
      >
        <div className="flex items-center gap-3 flex-wrap">
          <div className="flex items-center gap-2">
            <span className="text-xs font-semibold text-slate-600 dark:text-slate-400">参考日期:</span>
            <input
              type="date"
              value={date}
              min="2000-01-01"
              max="2040-12-31"
              onChange={(e) => setDate(e.target.value)}
              className="h-10 px-3.5 rounded-xl glass-input text-sm font-medium text-slate-800 dark:text-slate-200 cursor-pointer"
            />
            <button
              type="button"
              onClick={() => setDate(today())}
              className="px-3 py-2 rounded-xl text-xs font-medium glass-subtle hover:bg-violet-500/5 dark:hover:bg-violet-400/5 text-slate-700 dark:text-slate-300 transition-colors cursor-pointer"
            >
              设为今天
            </button>
          </div>

          <div className="flex items-center gap-2">
            <span className="text-xs font-semibold text-slate-600 dark:text-slate-400">波色:</span>
            <select
              value={boseFilter}
              onChange={(e) => setBoseFilter(e.target.value)}
              className="h-10 px-3 rounded-xl glass-input text-sm font-medium text-slate-800 dark:text-slate-200 cursor-pointer"
            >
              <option value="all">全部波色</option>
              <option value="红">红波 (17码)</option>
              <option value="蓝">蓝波 (16码)</option>
              <option value="绿">绿波 (16码)</option>
            </select>
          </div>

          <div className="flex items-center gap-2">
            <span className="text-xs font-semibold text-slate-600 dark:text-slate-400">男女肖:</span>
            <select
              value={genderFilter}
              onChange={(e) => setGenderFilter(e.target.value)}
              className="h-10 px-3 rounded-xl glass-input text-sm font-medium text-slate-800 dark:text-slate-200 cursor-pointer"
            >
              <option value="all">全部生肖</option>
              <option value="男肖">男肖 (7肖)</option>
              <option value="女肖">女肖 (5肖)</option>
            </select>
          </div>

          <div className="flex-1 min-w-[180px]">
            <input
              type="text"
              value={keyword}
              onChange={(e) => setKeyword(e.target.value)}
              placeholder="搜索号码 / 生肖 / 男女肖 / 天地肖 / 五行 / 家野..."
              className="w-full h-10 px-3.5 rounded-xl glass-input text-sm text-slate-800 dark:text-slate-200 placeholder:text-slate-400 dark:placeholder:text-slate-500"
            />
          </div>

          <span className="text-xs text-slate-400 dark:text-slate-500">
            显示 {filteredItems.length} / {items.length} 个号码
          </span>
        </div>
      </SectionCard>

      {/* 49 号码属性大表 */}
      <SectionCard
        title={
          <div className="flex items-center gap-3">
            <span>01–49 属性字典明细</span>
            <span className="text-xs font-mono px-2.5 py-0.5 rounded-full glass-subtle text-slate-600 dark:text-slate-400">
              农历基准: {date}
            </span>
          </div>
        }
      >
        {loading ? (
          <div className="p-12 flex justify-center">
            <Spinner aria-label="加载中" />
          </div>
        ) : (
          <div className="space-y-4">
            <TableContainer>
              <thead>
                <tr>
                  <th className={`${tableThClass} w-20`}>号码</th>
                  <th className={tableThClass}>生肖</th>
                  <th className={tableThClass}>生肖分类</th>
                  <th className={tableThClass}>五行属性</th>
                  <th className={tableThClass}>家野</th>
                  <th className={tableThClass}>波色</th>
                  <th className={tableThClass}>大小</th>
                  <th className={tableThClass}>单双</th>
                  <th className={tableThClass}>头数</th>
                  <th className={tableThClass}>尾数</th>
                  <th className={tableThClass}>合数</th>
                </tr>
              </thead>
              <tbody>
                {filteredItems.map((n) => (
                  <tr key={n.num} className={tableRowClass}>
                    <td className={tableTdClass}>
                      <NumberBall num={n.num} bose={n.bose} />
                    </td>
                    <td className={tableTdClass}>
                      <span className="font-bold text-slate-900 dark:text-white text-base">
                        {n.xiao}
                      </span>
                    </td>
                    <td className={tableTdClass}>
                      {n.gender ? (
                        <span
                          className={`px-2 py-0.5 rounded-md text-xs font-semibold ${
                            n.gender === "男肖"
                              ? "bg-sky-500/10 text-sky-600 dark:text-sky-400"
                              : "bg-rose-500/10 text-rose-600 dark:text-rose-400"
                          }`}
                        >
                          {n.gender}
                          {n.tian_di ? ` · ${n.tian_di}` : ""}
                        </span>
                      ) : (
                        <span className="text-slate-400">—</span>
                      )}
                    </td>
                    <td className={tableTdClass}>
                      {n.wuxing ? (
                        <span
                          className="font-bold px-2 py-0.5 rounded-md glass-subtle text-xs"
                          style={{ color: WUXING_COLORS[n.wuxing] ?? "inherit" }}
                        >
                          {n.wuxing}
                        </span>
                      ) : (
                        <span className="text-slate-400">—</span>
                      )}
                    </td>
                    <td className={tableTdClass}>
                      <span className={`px-2 py-0.5 rounded-md text-xs font-semibold ${
                        n.jiaye === "家"
                          ? "bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
                          : "glass-subtle text-slate-600 dark:text-slate-400"
                      }`}>
                        {n.jiaye === "家" ? "家禽" : "野兽"}
                      </span>
                    </td>
                    <td className={tableTdClass}>
                      <span
                        className="font-bold px-2.5 py-0.5 rounded-md text-xs text-white"
                        style={{ backgroundColor: BOSE_STYLES[n.bose]?.bg }}
                      >
                        {n.bose}波
                      </span>
                    </td>
                    <td className={tableTdClass}>
                      <span className="text-xs font-medium text-slate-700 dark:text-slate-300">
                        {n.size}
                      </span>
                    </td>
                    <td className={tableTdClass}>
                      <span className="text-xs font-medium text-slate-700 dark:text-slate-300">
                        {n.odd}
                      </span>
                    </td>
                    <td className={tableTdClass}>
                      <span className="text-xs font-mono text-slate-500 dark:text-slate-400">
                        {n.head}头
                      </span>
                    </td>
                    <td className={tableTdClass}>
                      <span className="text-xs font-mono text-slate-500 dark:text-slate-400">
                        {n.wei}尾
                      </span>
                    </td>
                    <td className={tableTdClass}>
                      <span className="text-xs font-mono font-bold text-slate-700 dark:text-slate-300">
                        合{n.sum}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </TableContainer>

            {!wuxingAvailable && (
              <div className="p-3.5 rounded-xl bg-amber-500/10 border border-amber-400/40 dark:border-amber-400/25 text-amber-700 dark:text-amber-300 text-xs backdrop-blur-md">
                ⚠️ 当前所选日期对应的农历年暂无五行对照表（只录入了有官方资料的年份）。切换到已录入年份即可显示五行。
              </div>
            )}

            <div className="text-xs text-slate-400 dark:text-slate-500">
              💡 注：五行按农历年（春节切换）轮换，依据当年官方生肖灵码表逐年录入；未录入的年份显示为「—」。
            </div>
          </div>
        )}
      </SectionCard>
    </div>
  );
}
