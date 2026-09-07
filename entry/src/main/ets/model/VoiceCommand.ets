/**
 * 语音命令解析：把 ASR 识别出的中文文本转为计算器表达式或动作（纯逻辑，可独立单测）
 *
 * 支持：
 *  - 数字：中文数词（"十二"、"一百零五"、小数"三点一四"、负数"负十五"）、阿拉伯数字串
 *  - 运算符：加/加上、减/减去、乘/乘以、除/除以（含常见口语变体）
 *  - 等号：等于/是多少/结果
 *  - 动作：清空/清除/归零；删除/退格
 */
import { parseZhNumber } from './ChineseNumber';

export interface VoiceCommandResult {
  type: 'clear' | 'delete' | 'equals' | 'expression' | 'empty';
  expression?: string;
}

const OP_WORDS: Record<string, string> = {
  '乘以': '*',
  '乘上': '*',
  '乘个': '*',
  '乘': '*',
  '除以': '/',
  '除去': '/',
  '除个': '/',
  '除': '/',
  '加上': '+',
  '加个': '+',
  '加': '+',
  '减去': '-',
  '减掉': '-',
  '减个': '-',
  '减': '-'
};

const EQ_WORDS: string[] = ['等于多少', '结果是多少', '得多少', '是多少', '等于几', '得几', '等于', '多少'];
const CLEAR_WORDS: string[] = ['全部清除', '清空', '清除', '归零', '清零'];
const DELETE_WORDS: string[] = ['删除', '删掉', '删去', '退格', '回退', '删一个'];

const OP_KEYS: string[] = Object.keys(OP_WORDS).sort((a: string, b: string) => b.length - a.length);
const EQ_KEYS: string[] = EQ_WORDS.slice().sort((a: string, b: string) => b.length - a.length);
const CLEAR_KEYS: string[] = CLEAR_WORDS.slice().sort((a: string, b: string) => b.length - a.length);
const DELETE_KEYS: string[] = DELETE_WORDS.slice().sort((a: string, b: string) => b.length - a.length);

const NUM_CHARS: string = '零〇一二两三四五六七八九十百千万亿点负0123456789';

function isNumChar(ch: string): boolean {
  return NUM_CHARS.indexOf(ch) >= 0;
}

function numberToString(v: number): string {
  if (Number.isInteger(v) && Math.abs(v) < 1e15) {
    return Math.trunc(v).toString();
  }
  return v.toString();
}

/**
 * 解析语音文本 → 计算器命令
 * "十二加八" → expression "12+8"
 * "十二加八等于多少" → equals "12+8"
 * "清空" → clear；"删除" → delete；"你好" → empty
 */
export function parseVoiceCommand(text: string): VoiceCommandResult {
  const s = text.replace(/[，。！？、,.;:：；\s]+/g, '');
  if (s.length === 0) {
    return { type: 'empty' };
  }
  for (const w of CLEAR_KEYS) {
    if (s.indexOf(w) >= 0) {
      return { type: 'clear' };
    }
  }
  for (const w of DELETE_KEYS) {
    if (s.indexOf(w) >= 0) {
      return { type: 'delete' };
    }
  }
  const parts: string[] = [];
  let hasEquals = false;
  let i = 0;
  while (i < s.length) {
    let matched = false;
    for (const k of OP_KEYS) {
      if (s.startsWith(k, i)) {
        parts.push(OP_WORDS[k]);
        i += k.length;
        matched = true;
        break;
      }
    }
    if (matched) {
      continue;
    }
    for (const k of EQ_KEYS) {
      if (s.startsWith(k, i)) {
        parts.push('=');
        hasEquals = true;
        i += k.length;
        matched = true;
        break;
      }
    }
    if (matched) {
      // 等号之后的文本是用户口述的答案，不再参与解析
      break;
    }
    if (isNumChar(s.charAt(i))) {
      let j = i;
      while (j < s.length && isNumChar(s.charAt(j))) {
        j++;
      }
      const numText = s.substring(i, j);
      const v = parseZhNumber(numText);
      if (v !== null) {
        parts.push(numberToString(v));
      }
      i = j;
      continue;
    }
    i++;
  }
  let expr = '';
  for (const p of parts) {
    if (p === '=') {
      continue;
    }
    expr += p;
  }
  while (expr.length > 0 && '+-*/'.indexOf(expr.charAt(expr.length - 1)) >= 0) {
    expr = expr.substring(0, expr.length - 1);
  }
  if (expr.length === 0) {
    return { type: 'empty' };
  }
  if (hasEquals) {
    return { type: 'equals', expression: expr };
  }
  return { type: 'expression', expression: expr };
}
