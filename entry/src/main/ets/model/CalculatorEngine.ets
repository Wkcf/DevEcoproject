/**
 * 计算器核心：输入状态机 + 中缀表达式求值（纯逻辑，可独立单测）
 *
 * 支持的表达式：数字（含小数）、+ - * /、括号、一元负号（如 -3+5、2*(-3)）
 */

export interface EvaluateResult {
  ok: boolean;
  value: number;
  error: string;
}

const OP_PREC: Record<string, number> = { '+': 1, '-': 1, '*': 2, '/': 2, 'u-': 3 };

function isDigitChar(ch: string): boolean {
  return ch >= '0' && ch <= '9';
}

function isOpChar(ch: string): boolean {
  return ch === '+' || ch === '-' || ch === '*' || ch === '/';
}

function applyOp(a: number, b: number, op: string): number {
  if (op === '+') {
    return a + b;
  }
  if (op === '-') {
    return a - b;
  }
  if (op === '*') {
    return a * b;
  }
  if (op === '/') {
    if (Math.abs(b) < 1e-12) {
      throw new Error('div0');
    }
    return a / b;
  }
  throw new Error('bad-op');
}

function calcOnce(nums: number[], ops: string[]): void {
  const op = ops.pop();
  if (op === undefined) {
    return;
  }
  if (op === 'u-') {
    const v = nums.pop();
    if (v !== undefined) {
      nums.push(-v);
    }
    return;
  }
  const b = nums.pop();
  const a = nums.pop();
  if (a === undefined || b === undefined) {
    throw new Error('bad-expr');
  }
  nums.push(applyOp(a, b, op));
}

function tokenize(expr: string): string[] {
  const tokens: string[] = [];
  let i = 0;
  while (i < expr.length) {
    const ch = expr.charAt(i);
    if (ch === ' ') {
      i++;
      continue;
    }
    if (isOpChar(ch) || ch === '(' || ch === ')') {
      tokens.push(ch);
      i++;
      continue;
    }
    if (isDigitChar(ch) || ch === '.') {
      let j = i;
      while (j < expr.length && (isDigitChar(expr.charAt(j)) || expr.charAt(j) === '.')) {
        j++;
      }
      tokens.push(expr.substring(i, j));
      i = j;
      continue;
    }
    return [];
  }
  return tokens;
}

function isNumberToken(t: string): boolean {
  if (t.length === 0) {
    return false;
  }
  for (let i = 0; i < t.length; i++) {
    const ch = t.charAt(i);
    if (!isDigitChar(ch) && ch !== '.') {
      return false;
    }
  }
  return true;
}

/**
 * 中缀表达式求值（支持 + - * / 括号 一元负号）
 * "12+8" → 20；"-3+5" → 2；"2*(-3)" → -6；"5/0" → 除数为零
 */
export function evaluate(expression: string): EvaluateResult {
  const tokens = tokenize(expression);
  if (tokens.length === 0) {
    return { ok: false, value: 0, error: '表达式为空' };
  }
  const nums: number[] = [];
  const ops: string[] = [];
  let prevToken = '';
  try {
    for (let i = 0; i < tokens.length; i++) {
      const t = tokens[i];
      if (isNumberToken(t)) {
        nums.push(parseFloat(t));
      } else if (t === '(') {
        ops.push(t);
      } else if (t === ')') {
        let closed = false;
        while (ops.length > 0) {
          const top = ops[ops.length - 1];
          if (top === '(') {
            ops.pop();
            closed = true;
            break;
          }
          calcOnce(nums, ops);
        }
        if (!closed) {
          return { ok: false, value: 0, error: '括号不匹配' };
        }
      } else if (isOpChar(t)) {
        let unary = false;
        if (t === '-') {
          if (prevToken === '' || isOpChar(prevToken) || prevToken === '(') {
            unary = true;
          }
        }
        const curPrec = unary ? 3 : (OP_PREC[t] as number);
        while (ops.length > 0 && ops[ops.length - 1] !== '(') {
          const top = ops[ops.length - 1];
          const topPrec = OP_PREC[top];
          if (topPrec === undefined) {
            break;
          }
          if (unary) {
            if (topPrec > curPrec) {
              calcOnce(nums, ops);
            } else {
              break;
            }
          } else {
            if (topPrec >= curPrec) {
              calcOnce(nums, ops);
            } else {
              break;
            }
          }
        }
        ops.push(unary ? 'u-' : t);
      } else {
        return { ok: false, value: 0, error: '非法字符' };
      }
      prevToken = t;
    }
    while (ops.length > 0) {
      const top = ops[ops.length - 1];
      if (top === '(') {
        return { ok: false, value: 0, error: '括号不匹配' };
      }
      calcOnce(nums, ops);
    }
    if (nums.length !== 1) {
      return { ok: false, value: 0, error: '表达式不完整' };
    }
    return { ok: true, value: nums[0], error: '' };
  } catch (e) {
    const msg = (e as Error).message;
    if (msg === 'div0') {
      return { ok: false, value: 0, error: '除数为零' };
    }
    return { ok: false, value: 0, error: '表达式错误' };
  }
}

/**
 * 数值格式化：消除浮点误差，超大/超小用科学计数法
 * 0.30000000000000004 → "0.3"；1/3 → "0.333333333333"；1e21 → "1.000000e+21"
 */
export function formatNumber(n: number): string {
  if (!Number.isFinite(n)) {
    return '错误';
  }
  if (Math.abs(n) < 1e-12) {
    n = 0;
  }
  const precise = parseFloat(n.toPrecision(12));
  if (Math.abs(precise) >= 1e12 || (Math.abs(precise) < 1e-9 && precise !== 0)) {
    return precise.toExponential(6);
  }
  return precise.toString();
}

/**
 * 计算器输入状态机（按键 + 语音共用）
 */
export class CalculatorEngine {
  private expr: string = '';
  private display: string = '0';
  private justEvaluated: boolean = false;
  private lastError: string = '';

  getExpression(): string {
    return this.expr;
  }

  getDisplay(): string {
    return this.display;
  }

  getLastError(): string {
    return this.lastError;
  }

  /** 显示用表达式（把 * / 换成 × ÷） */
  getExpressionLine(): string {
    return this.expr.replace(/\*/g, '×').replace(/\//g, '÷');
  }

  reset(): void {
    this.expr = '';
    this.display = '0';
    this.justEvaluated = false;
    this.lastError = '';
  }

  /** 语音等直接设置完整表达式，返回是否成功 */
  setExpression(e: string): boolean {
    if (!/^[0-9.+\-*/() ]+$/.test(e)) {
      return false;
    }
    const clean = e.replace(/\s+/g, '');
    if (clean.length === 0) {
      return false;
    }
    this.expr = clean;
    this.justEvaluated = false;
    this.lastError = '';
    this.updateDisplayFromTail();
    if (this.display === '') {
      this.display = this.expr;
    }
    return true;
  }

  /** 从表达式尾部截取当前操作数，更新主显示 */
  private updateDisplayFromTail(): void {
    let j = this.expr.length - 1;
    while (j >= 0) {
      const ch = this.expr.charAt(j);
      if (isDigitChar(ch) || ch === '.') {
        j--;
      } else {
        break;
      }
    }
    const tail = this.expr.substring(j + 1);
    if (tail.length > 0) {
      this.display = tail;
    }
  }

  inputDigit(d: string): void {
    if (d.length !== 1 || !isDigitChar(d)) {
      return;
    }
    if (this.justEvaluated) {
      this.expr = '';
      this.justEvaluated = false;
    }
    this.expr += d;
    this.updateDisplayFromTail();
  }

  inputDot(): void {
    if (this.justEvaluated) {
      this.expr = '';
      this.justEvaluated = false;
    }
    let j = this.expr.length - 1;
    while (j >= 0) {
      const ch = this.expr.charAt(j);
      if (isDigitChar(ch) || ch === '.') {
        j--;
      } else {
        break;
      }
    }
    const tail = this.expr.substring(j + 1);
    if (tail.indexOf('.') >= 0) {
      return; // 当前操作数已有点
    }
    if (tail.length === 0) {
      if (this.expr.length > 0 && this.expr.charAt(this.expr.length - 1) === ')') {
        return; // 右括号后不可直接加点
      }
      this.expr += '0.'; // 运算符后直接输入点 → 0.x
    } else {
      this.expr += '.';
    }
    this.updateDisplayFromTail();
  }

  inputOperator(op: string): void {
    if (op !== '+' && op !== '-' && op !== '*' && op !== '/') {
      return;
    }
    if (this.justEvaluated) {
      if (this.display === '错误') {
        this.expr = '';
        this.display = '0';
        this.justEvaluated = false;
        return;
      }
      this.expr = this.display + op; // 用结果继续运算
      this.justEvaluated = false;
      this.display = '';
      return;
    }
    if (this.expr.length === 0) {
      this.expr = '0' + op;
      this.display = '';
      return;
    }
    const last = this.expr.charAt(this.expr.length - 1);
    if (isOpChar(last)) {
      this.expr = this.expr.substring(0, this.expr.length - 1) + op; // 替换末尾运算符
      this.display = '';
    } else if (last === '(') {
      if (op === '-') {
        this.expr += '-';
        this.display = '';
      }
      // '(' 后输入 + * / 忽略
    } else {
      this.expr += op;
      this.display = '';
    }
  }

  inputClear(): void {
    this.reset();
  }

  inputDelete(): void {
    if (this.justEvaluated) {
      this.expr = '';
      this.display = '0';
      this.justEvaluated = false;
      return;
    }
    if (this.expr.length > 0) {
      this.expr = this.expr.substring(0, this.expr.length - 1);
      this.updateDisplayFromTail();
      if (this.display === '') {
        this.display = '0';
      }
    }
  }

  /** 等号：求值并返回结果字符串（失败时 lastError 有原因） */
  inputEquals(): string {
    if (this.expr.length === 0) {
      return this.display;
    }
    const r = evaluate(this.expr);
    if (r.ok) {
      this.display = formatNumber(r.value);
      this.lastError = '';
    } else {
      this.display = '错误';
      this.lastError = r.error;
    }
    this.justEvaluated = true;
    return this.display;
  }
}
