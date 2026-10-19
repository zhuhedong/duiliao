import { padNum, XIAO_LIST } from "../../lib/lotteryAttr";

export const XIAO_NUMBERS_2026: Record<string, string[]> = {
  马: ["01", "13", "25", "37", "49"],
  蛇: ["02", "14", "26", "38"],
  龙: ["03", "15", "27", "39"],
  兔: ["04", "16", "28", "40"],
  虎: ["05", "17", "29", "41"],
  牛: ["06", "18", "30", "42"],
  鼠: ["07", "19", "31", "43"],
  猪: ["08", "20", "32", "44"],
  狗: ["09", "21", "33", "45"],
  鸡: ["10", "22", "34", "46"],
  猴: ["11", "23", "35", "47"],
  羊: ["12", "24", "36", "48"],
};

export const DEFAULT_ODDS: Record<string, number> = {
  特码: 47.0,
  正码: 7.0,
  平码: 7.0,
  平特肖: 2.0,
  平特一肖: 2.0,
  特肖: 11.5,
  "2连肖": 4.0,
  "3连肖": 10.0,
  "4连肖": 30.0,
  "5连肖": 100.0,
  "5 不中": 2.0,
  "6 不中": 2.58,
  "7 不中": 3.15,
  "8 不中": 3.85,
  "九不中": 4.70,
  "十不中": 5.80,
  连肖: 4.0,
  不中码: 2.0,
};

export function getDefaultOdds(playType: string, hasMa = false): number {
  if (playType.includes("平特")) {
    return hasMa ? 1.8 : 2.0;
  }
  if (playType.includes("2连肖") || playType.includes("2连")) {
    return hasMa ? 3.8 : 4.0;
  }
  if (playType.includes("3连肖") || playType.includes("3连")) {
    return hasMa ? 9.0 : 10.0;
  }
  if (playType.includes("4连肖") || playType.includes("4连")) {
    return hasMa ? 28.0 : 30.0;
  }
  if (playType.includes("5连肖") || playType.includes("5连")) {
    return hasMa ? 80.0 : 100.0;
  }
  if (playType.includes("5") && playType.includes("不中")) return 2.0;
  if (playType.includes("6") && playType.includes("不中")) return 2.58;
  if (playType.includes("7") && playType.includes("不中")) return 3.15;
  if (playType.includes("8") && playType.includes("不中")) return 3.85;

  return DEFAULT_ODDS[playType] ?? 7.0;
}

function combinations(n: number, k: number): number {
  if (k < 0 || k > n) return 0;
  if (k === 0 || k === n) return 1;
  let c = 1;
  for (let i = 1; i <= k; i++) {
    c = (c * (n - (k - i))) / i;
  }
  return Math.round(c);
}

export interface ParsedSmartInput {
  mode: string;
  numbers: string[];
  xiaos: string[];
  stakePerNote: number | null;
  multiplier: number;
  notesCount: number;
  totalAmount: number;
  fushiLinks: number[];
}

export function parseSmartInput(
  rawInput: string,
  modeHint = "号码单式",
  playTypeHint = "正码"
): ParsedSmartInput {
  const text = (rawInput || "").trim();
  if (!text) {
    return {
      mode: modeHint,
      numbers: [],
      xiaos: [],
      stakePerNote: null,
      multiplier: 1,
      notesCount: 0,
      totalAmount: 0,
      fushiLinks: [],
    };
  }

  // Parse stake: e.g. 个数5, 各数10, 各5, 每码5, 10元, 10块, ×5
  const stakeMatch =
    text.match(/(?:各数|个数|各码|每码|单注|各|每)\s*[:：=＝]?\s*(\d+)/) ||
    text.match(/(\d+)\s*(?:元|块|分|点)/) ||
    text.match(/[×*xX]\s*(\d+)\s*(?:元|块)?$/);
  const parsedStake = stakeMatch ? parseInt(stakeMatch[1], 10) : null;

  // Parse multiplier: e.g. 倍2, 2倍, *2倍
  const multMatch = text.match(/(?:倍\s*(\d+)|(\d+)\s*倍)/);
  const parsedMult = multMatch ? parseInt(multMatch[1] || multMatch[2], 10) : 1;

  // Mode detection
  const isLianxiao =
    modeHint === "连肖复试" ||
    playTypeHint.includes("连肖") ||
    /复[试式]/.test(text) ||
    /[2-5二三四五]连/.test(text);

  const isNbuzhong =
    modeHint === "不中码" ||
    playTypeHint.includes("不中") ||
    /不中/.test(text);

  const isPingte =
    modeHint === "平特肖" ||
    playTypeHint.includes("平特") ||
    /平特/.test(text);

  // Clean text from stake / mult keywords to avoid mistaking digits
  let cleaned = text
    .replace(/(?:各数|个数|各码|每码|单注|各|每)\s*[:：=＝]?\s*\d+/g, "")
    .replace(/\d+\s*(?:元|块|分|点)/g, "")
    .replace(/[×*xX]\s*\d+\s*(?:元|块)?$/g, "")
    .replace(/(?:倍\s*\d+|\d+\s*倍)/g, "")
    .replace(/复[试式]/g, "")
    .replace(/[2-5二三四五]\s*连/g, "")
    .replace(/[·\s]*\d+\s*不中.*$/g, "");

  // Extract explicit numbers (01-49)
  const numbers: string[] = [];
  const numMatches = cleaned.matchAll(/(?<!\d)([0-4]?\d)(?!\d)/g);
  for (const m of numMatches) {
    const val = parseInt(m[1], 10);
    if (val >= 1 && val <= 49) {
      const formatted = padNum(val);
      if (!numbers.includes(formatted)) {
        numbers.push(formatted);
      }
    }
  }

  // Extract zodiacs
  const extractedXiaos: string[] = [];
  for (const char of cleaned) {
    if (XIAO_LIST.includes(char as any) && !extractedXiaos.includes(char)) {
      extractedXiaos.push(char);
    }
  }

  let finalMode = modeHint;
  let finalNumbers = [...numbers];
  let finalXiaos: string[] = [];
  const fushiLinks: number[] = [];

  if (isLianxiao) {
    finalMode = "连肖复试";
    finalXiaos = extractedXiaos;
    finalNumbers = [];

    // Parse ks (e.g. 2, 3, 4, 5)
    const linkMatch = text.match(/([2-5二三四五])连/g);
    if (linkMatch) {
      const map: Record<string, number> = {
        "2": 2, 二: 2, "3": 3, 三: 3, "4": 4, 四: 4, "5": 5, 五: 5,
      };
      for (const lm of linkMatch) {
        const kChar = lm[0];
        const kVal = map[kChar];
        if (kVal && !fushiLinks.includes(kVal)) {
          fushiLinks.push(kVal);
        }
      }
    }
    if (fushiLinks.length === 0) {
      fushiLinks.push(Math.min(4, Math.max(2, finalXiaos.length)));
    }
  } else if (isNbuzhong) {
    finalMode = "不中码";
    // expand any zodiacs into numbers
    for (const x of extractedXiaos) {
      const nums = XIAO_NUMBERS_2026[x] || [];
      for (const n of nums) {
        if (!finalNumbers.includes(n)) {
          finalNumbers.push(n);
        }
      }
    }
  } else if (isPingte) {
    finalMode = "号码单式";
    finalXiaos = extractedXiaos;
  } else {
    // 号码单式
    finalMode = "号码单式";
    // If user entered zodiacs like '龙兔各数5', expand to constituent numbers
    if (extractedXiaos.length > 0 && finalNumbers.length === 0) {
      for (const x of extractedXiaos) {
        const nums = XIAO_NUMBERS_2026[x] || [];
        for (const n of nums) {
          if (!finalNumbers.includes(n)) {
            finalNumbers.push(n);
          }
        }
      }
    }
  }

  // Calculate notes count
  let notesCount = 0;
  if (finalMode === "连肖复试") {
    let sum = 0;
    for (const k of fushiLinks) {
      if (finalXiaos.length >= k) {
        sum += combinations(finalXiaos.length, k);
      }
    }
    notesCount = Math.max(1, sum);
  } else if (finalMode === "不中码") {
    notesCount = 1;
  } else if (finalXiaos.length > 0 && finalNumbers.length === 0) {
    notesCount = finalXiaos.length;
  } else {
    notesCount = Math.max(1, finalNumbers.length);
  }

  const stake = parsedStake || 5;
  const mult = parsedMult || 1;
  const totalAmount = stake * notesCount * mult;

  return {
    mode: finalMode,
    numbers: finalNumbers,
    xiaos: finalXiaos,
    stakePerNote: parsedStake,
    multiplier: mult,
    notesCount,
    totalAmount,
    fushiLinks,
  };
}
