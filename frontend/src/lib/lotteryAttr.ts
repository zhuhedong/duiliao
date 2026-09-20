import type { NumberAttr, DrawSummary, DrawRow, LianxiaoGroup, AdjacentLianxiao } from "./collector";

export const BOSE_COLORS: Record<string, { bg: string; border: string; text: string }> = {
  红: { bg: "#ef4444", border: "#dc2626", text: "#ffffff" },
  蓝: { bg: "#3b82f6", border: "#2563eb", text: "#ffffff" },
  绿: { bg: "#10b981", border: "#059669", text: "#ffffff" },
};

export const WUXING_COLORS: Record<string, string> = {
  金: "#b8860b",
  木: "#10b981",
  水: "#3b82f6",
  火: "#ef4444",
  土: "#a1662f",
};

const RED_NUMS = new Set([1, 2, 7, 8, 12, 13, 18, 19, 23, 24, 29, 30, 34, 35, 40, 45, 46]);
const BLUE_NUMS = new Set([3, 4, 9, 10, 14, 15, 20, 25, 26, 31, 36, 37, 41, 42, 47, 48]);

export const XIAO_LIST = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"] as const;
const JIA_XIAO = new Set(["牛", "马", "羊", "鸡", "狗", "猪"]);

const WUXING_2026: Record<string, Set<number>> = {
  金: new Set([4, 5, 12, 13, 26, 27, 34, 35, 42, 43]),
  木: new Set([8, 9, 16, 17, 24, 25, 38, 39, 46, 47]),
  水: new Set([1, 14, 15, 22, 23, 30, 31, 44, 45]),
  火: new Set([2, 3, 10, 11, 18, 19, 32, 33, 40, 41, 48, 49]),
  土: new Set([6, 7, 20, 21, 28, 29, 36, 37]),
};

export function padNum(num: number | string): string {
  const n = parseInt(String(num).trim(), 10) || 0;
  return n.toString().padStart(2, "0");
}

export function getBose(num: number | string): "红" | "蓝" | "绿" {
  const n = parseInt(String(num), 10);
  if (RED_NUMS.has(n)) return "红";
  if (BLUE_NUMS.has(n)) return "蓝";
  return "绿";
}

export function getXiao(num: number | string, year = 2026): string {
  const n = parseInt(String(num), 10);
  if (n < 1 || n > 49) return "—";
  const yearXiaoIdx = (year - 4) % 12; // 2026 -> 6 -> 马
  const idx = ((yearXiaoIdx - (n - 1)) % 12 + 12) % 12;
  return XIAO_LIST[idx];
}

export function getWuxing(num: number | string): string | null {
  const n = parseInt(String(num), 10);
  for (const [elem, set] of Object.entries(WUXING_2026)) {
    if (set.has(n)) return elem;
  }
  return null;
}

export function getSize(num: number | string): "大" | "小" {
  const n = parseInt(String(num), 10);
  return n >= 25 ? "大" : "小";
}

export function getOdd(num: number | string): "单" | "双" {
  const n = parseInt(String(num), 10);
  return n % 2 !== 0 ? "单" : "双";
}

export function getSumOdd(num: number | string): "单" | "双" {
  const n = parseInt(String(num), 10);
  const sum = Math.floor(n / 10) + (n % 10);
  return sum % 2 !== 0 ? "单" : "双";
}

export function getJiaye(xiao: string): "家" | "野" {
  return JIA_XIAO.has(xiao) ? "家" : "野";
}

export function getHead(num: number | string): string {
  const n = parseInt(String(num), 10);
  return Math.floor(n / 10).toString();
}

export function getWei(num: number | string): string {
  const n = parseInt(String(num), 10);
  return (n % 10).toString();
}

export function computeBallAttr(num: number | string, year = 2026): NumberAttr {
  const p = padNum(num);
  const x = getXiao(p, year);
  const b = getBose(p);
  const s = getSize(p);
  const o = getOdd(p);
  const sum = getSumOdd(p);
  const jy = getJiaye(x);
  const wx = getWuxing(p);
  const h = getHead(p);
  const w = getWei(p);
  return {
    num: p,
    xiao: x,
    bose: b,
    size: s,
    odd: o,
    sum,
    jiaye: jy,
    wuxing: wx,
    head: h,
    wei: w,
  };
}

export function enrichLianxiao(all7: NumberAttr[]): {
  has_lianxiao: boolean;
  has_adjacent_lianxiao: boolean;
  lianxiao_groups: LianxiaoGroup[];
  adjacent_lianxiao: AdjacentLianxiao[];
  lianxiao_text: string;
} {
  const positions = ["正1", "正2", "正3", "正4", "正5", "正6", "特码"];
  const xiaoCounts: Record<string, number> = {};
  for (const b of all7) {
    xiaoCounts[b.xiao] = (xiaoCounts[b.xiao] || 0) + 1;
  }

  const lianxiaoXiaos: Record<string, number> = {};
  for (const [x, cnt] of Object.entries(xiaoCounts)) {
    if (cnt >= 2) lianxiaoXiaos[x] = cnt;
  }

  const adjacent_lianxiao: AdjacentLianxiao[] = [];
  for (let i = 0; i < Math.min(6, all7.length - 1); i++) {
    if (all7[i].xiao === all7[i + 1].xiao) {
      all7[i].is_adjacent_lianxiao = true;
      all7[i + 1].is_adjacent_lianxiao = true;
      adjacent_lianxiao.push({
        xiao: all7[i].xiao,
        pos1: positions[i] || `第${i + 1}码`,
        pos2: positions[i + 1] || `第${i + 2}码`,
        num1: all7[i].num,
        num2: all7[i + 1].num,
      });
    }
  }

  for (const b of all7) {
    b.is_lianxiao = Boolean(lianxiaoXiaos[b.xiao]);
    b.lianxiao_count = lianxiaoXiaos[b.xiao] || 1;
    if (b.is_adjacent_lianxiao === undefined) {
      b.is_adjacent_lianxiao = false;
    }
  }

  const lianxiao_groups: LianxiaoGroup[] = Object.entries(lianxiaoXiaos)
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([xiao, count]) => {
      const nums = all7.filter((b) => b.xiao === xiao).map((b) => b.num);
      const posList = all7
        .map((b, idx) => (b.xiao === xiao ? positions[idx] : null))
        .filter((p): p is string => p !== null);
      return { xiao, count, nums, positions: posList };
    });

  const has_lianxiao = lianxiao_groups.length > 0;
  const lianxiao_text = has_lianxiao
    ? lianxiao_groups.map((g) => `${g.xiao}(${g.count}码)`).join(" · ")
    : "7肖各异";

  return {
    has_lianxiao,
    has_adjacent_lianxiao: adjacent_lianxiao.length > 0,
    lianxiao_groups,
    adjacent_lianxiao,
    lianxiao_text,
  };
}

export function computeDrawSummary(balls: string[], tema: string, year = 2026): DrawSummary {
  const all7Nums = [...balls, tema].map((b) => parseInt(b, 10) || 0);
  const sum7 = all7Nums.reduce((a, b) => a + b, 0);
  const sum7_size = sum7 >= 175 ? "大" : "小";
  const sum7_odd = sum7 % 2 !== 0 ? "单" : "双";

  const temaAttr = computeBallAttr(tema, year);
  const ballsAttr = balls.map((b) => computeBallAttr(b, year));
  const lianxiaoInfo = enrichLianxiao([...ballsAttr, temaAttr]);

  return {
    sum7,
    sum7_size,
    sum7_odd,
    tema_xiao: temaAttr.xiao,
    tema_bose: temaAttr.bose,
    tema_wuxing: temaAttr.wuxing,
    tema_size: temaAttr.size,
    tema_odd: temaAttr.odd,
    tema_sum_odd: temaAttr.sum,
    tema_jiaye: temaAttr.jiaye,
    tema_halfwave: `${temaAttr.bose}${temaAttr.size}`,
    ...lianxiaoInfo,
  };
}

export function ensureDrawDetails(draw: DrawRow): {
  ballsDetail: NumberAttr[];
  temaDetail: NumberAttr;
  summary: DrawSummary;
} {
  const year = draw.draw_date ? parseInt(draw.draw_date.slice(0, 4), 10) : parseInt(draw.period.slice(0, 4), 10) || 2026;
  const ballsDetail = draw.balls_detail && draw.balls_detail.length === 6
    ? draw.balls_detail.map((b) => ({ ...b }))
    : draw.balls.map((b) => computeBallAttr(b, year));
  const temaDetail = draw.tema_detail ? { ...draw.tema_detail } : computeBallAttr(draw.tema, year);
  const all7 = [...ballsDetail, temaDetail];
  const lianxiaoInfo = enrichLianxiao(all7);

  const baseSummary = draw.summary ?? computeDrawSummary(draw.balls, draw.tema, year);
  const summary: DrawSummary = {
    ...baseSummary,
    has_lianxiao: baseSummary.has_lianxiao ?? lianxiaoInfo.has_lianxiao,
    has_adjacent_lianxiao: baseSummary.has_adjacent_lianxiao ?? lianxiaoInfo.has_adjacent_lianxiao,
    lianxiao_groups: baseSummary.lianxiao_groups ?? lianxiaoInfo.lianxiao_groups,
    adjacent_lianxiao: baseSummary.adjacent_lianxiao ?? lianxiaoInfo.adjacent_lianxiao,
    lianxiao_text: baseSummary.lianxiao_text ?? lianxiaoInfo.lianxiao_text,
  };

  return { ballsDetail, temaDetail, summary };
}
