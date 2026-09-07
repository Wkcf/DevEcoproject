/**
 * 中文数字与阿拉伯数字互转模块（纯逻辑，无鸿蒙系统依赖，可独立单测）
 *
 * 能力：
 *  - parseZhNumber：中文数字（含"点"小数、"负"、两、〇、数字式读法）→ number
 *  - numberToZh：number → 中文口播文本（语音播报用）
 *  - parseZhInt / numberToZhInt：整数子集
 */

const ZHU_DIGITS: string[] = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
const SMALL_UNITS: string[] = ['', '十', '百', '千'];

function zhDigitToNumber(ch: string): number {
  switch (ch) {
    case '零':
    case '〇':
      return 0;
    case '一':
      return 1;
    case '二':
    case '两':
      return 2;
    case '三':
      return 3;
    case '四':
      return 4;
    case '五':
      return 5;
    case '六':
      return 6;
    case '七':
      return 7;
    case '八':
      return 8;
    case '九':
      return 9;
    default:
      return -1;
  }
}

function isZhUnit(ch: string): boolean {
  return '十百千万亿'.indexOf(ch) >= 0;
}

function findDot(text: string): number {
  const idxZh = text.indexOf('点');
  if (idxZh >= 0) {
    return idxZh;
  }
  return text.indexOf('.');
}

/**
 * 中文整数 → number
 * 标准数词："十二"=12、"一百零五"=105、"两千零二十三"=2023、"十二万三千"=123000、"一亿零五"=100000005
 * 数字式读法（不含单位词）："二零二四"=2024、"一零"=10
 * 失败返回 null
 */
export function parseZhInt(text: string): number | null {
  const s = text.trim();
  if (s.length === 0) {
    return null;
  }
  let hasUnit = false;
  for (let i = 0; i < s.length; i++) {
    if (isZhUnit(s.charAt(i))) {
      hasUnit = true;
      break;
    }
  }
  if (!hasUnit && s.length > 1) {
    // 数字式读法（逐位拼接）："二零二四" → 2024
    let v = 0;
    let ok = true;
    for (let i = 0; i < s.length; i++) {
      const d = zhDigitToNumber(s.charAt(i));
      if (d < 0) {
        ok = false;
        break;
      }
      v = v * 10 + d;
    }
    if (ok) {
      return v;
    }
    return null;
  }
  let total = 0;
  let section = 0;
  let num = 0;
  for (let i = 0; i < s.length; i++) {
    const ch = s.charAt(i);
    const d = zhDigitToNumber(ch);
    if (d >= 0) {
      num = d;
    } else if (ch === '十') {
      section += (num === 0 ? 1 : num) * 10;
      num = 0;
    } else if (ch === '百') {
      section += num * 100;
      num = 0;
    } else if (ch === '千') {
      section += num * 1000;
      num = 0;
    } else if (ch === '万') {
      total += (section + num) * 10000;
      section = 0;
      num = 0;
    } else if (ch === '亿') {
      total += (section + num) * 100000000;
      section = 0;
      num = 0;
    } else {
      return null;
    }
  }
  total += section + num;
  return total;
}

/**
 * 中文数字（可含小数点）→ number
 * "十二"=12、"三点一四"=3.14、"点五"=0.5、"负十五"=-15
 * 失败返回 null
 */
export function parseZhNumber(text: string): number | null {
  const s = text.trim();
  if (s.length === 0) {
    return null;
  }
  let neg = false;
  let body = s;
  if (body.startsWith('负')) {
    neg = true;
    body = body.substring(1);
  }
  const dotIdx = findDot(body);
  const intPart = dotIdx >= 0 ? body.substring(0, dotIdx) : body;
  const fracPart = dotIdx >= 0 ? body.substring(dotIdx + 1) : '';
  let intVal = 0;
  if (intPart.length > 0) {
    const r = parseZhInt(intPart);
    if (r === null) {
      return null;
    }
    intVal = r;
  }
  let fracVal = 0;
  if (fracPart.length > 0) {
    for (let i = 0; i < fracPart.length; i++) {
      const d = zhDigitToNumber(fracPart.charAt(i));
      if (d < 0) {
        return null;
      }
      fracVal = fracVal * 10 + d;
    }
    fracVal = fracVal / Math.pow(10, fracPart.length);
  }
  let result = intVal + fracVal;
  if (neg) {
    result = -result;
  }
  return result;
}

/**
 * 0 < n <= 9999 的整数 → 中文（节内读法）
 * 规则：开头的 0 不读；非零数字之间的 0 读一次"零"；千位为 2 读"两"（两千）
 */
function sectionToZh(n: number): string {
  const d1 = Math.floor(n / 1000) % 10;
  const d2 = Math.floor(n / 100) % 10;
  const d3 = Math.floor(n / 10) % 10;
  const d4 = n % 10;
  const digits: number[] = [d1, d2, d3, d4];
  let s = '';
  let zeroPending = false;
  for (let i = 0; i < 4; i++) {
    const d = digits[i];
    if (d > 0) {
      if (zeroPending) {
        s += '零';
        zeroPending = false;
      }
      if (i === 0 && d === 2) {
        s += '两'; // 千位："两千"
      } else {
        s += ZHU_DIGITS[d];
      }
      if (i < 3) {
        s += SMALL_UNITS[3 - i];
      }
    } else if (s.length > 0) {
      // 只有已经输出非零数字后，零才需要被记录
      zeroPending = true;
    }
  }
  // 10~19 读"十X"而非"一十X"
  if (n >= 10 && n < 20 && s.startsWith('一十')) {
    s = s.substring(1);
  }
  return s;
}

/**
 * 整数 → 中文（含"负"，支持到亿以上）
 * 12="十二" 105="一百零五" 10500="一万零五百" 100000123="一亿零一百二十三"
 */
export function numberToZhInt(n: number): string {
  if (!Number.isFinite(n)) {
    return '';
  }
  if (n === 0) {
    return '零';
  }
  const neg = n < 0;
  let x = Math.abs(Math.floor(n));
  const yi = Math.floor(x / 100000000);
  x = x % 100000000;
  const wan = Math.floor(x / 10000);
  const ge = x % 10000;
  const sections: number[] = [yi, wan, ge];
  const names: string[] = ['亿', '万', ''];
  let s = '';
  let prevNonZero = -1;
  for (let i = 0; i < 3; i++) {
    const sec = sections[i];
    if (sec > 0) {
      if (s.length > 0 && prevNonZero >= 0) {
        const prevSec = sections[prevNonZero];
        // 低节最高位不是"千"（<1000）或上一节个位为 0 时，节间补零
        if (sec < 1000 || prevSec % 10 === 0) {
          s += '零';
        }
      }
      s += sectionToZh(sec) + names[i];
      prevNonZero = i;
    }
  }
  return (neg ? '负' : '') + s;
}

/**
 * number → 中文口播文本（支持小数与负数，播报用）
 * 12="十二" 105="一百零五" 3.14="三点一四" 0.5="零点五" -8="负八"
 */
export function numberToZh(num: number): string {
  if (!Number.isFinite(num)) {
    return '无效数字';
  }
  if (num === 0) {
    return '零';
  }
  const neg = num < 0;
  const abs = Math.abs(num);
  const intPart = Math.floor(abs);
  const frac = abs - intPart;
  let s = '';
  if (frac > 1e-12) {
    s = intPart === 0 ? '零' : numberToZhInt(intPart);
    let fracStr = frac.toFixed(10);
    while (fracStr.length > 0 && fracStr.charAt(fracStr.length - 1) === '0') {
      fracStr = fracStr.substring(0, fracStr.length - 1);
    }
    if (fracStr.startsWith('0.')) {
      fracStr = fracStr.substring(2);
    }
    s += '点';
    for (let i = 0; i < fracStr.length; i++) {
      const d = parseInt(fracStr.charAt(i), 10);
      s += ZHU_DIGITS[d];
    }
  } else {
    s = numberToZhInt(intPart);
  }
  return (neg ? '负' : '') + s;
}
