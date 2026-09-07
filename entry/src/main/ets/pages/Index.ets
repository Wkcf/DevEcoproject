/**
 * 语音计算器主页面（无障碍设计）
 * 功能：界面（显示区/数字键/运算符键/语音输入键）、逻辑（加减乘除/清空/删除/等号）、
 *       AI（华为语音识别把"十二加八"转为 12+8）、播报（计算结果朗读）
 */
import { common } from '@kit.AbilityKit';
import { CalculatorEngine } from '../model/CalculatorEngine';
import { numberToZh } from '../model/ChineseNumber';
import { parseVoiceCommand } from '../model/VoiceCommand';
import { SpeechService } from '../service/SpeechService';

const TAG = 'VoiceCalculator';

function isDigitCh(ch: string): boolean {
  return ch >= '0' && ch <= '9';
}

/** 表达式 → 中文口播（"12+8" → "十二加八"，"-3" → "负三"） */
function exprToZh(expr: string): string {
  let s = '';
  let i = 0;
  while (i < expr.length) {
    const ch = expr.charAt(i);
    if (isDigitCh(ch) || ch === '.') {
      let j = i;
      while (j < expr.length && (isDigitCh(expr.charAt(j)) || expr.charAt(j) === '.')) {
        j++;
      }
      const num = parseFloat(expr.substring(i, j));
      s += numberToZh(num);
      i = j;
    } else if (ch === '+') {
      s += '加';
      i++;
    } else if (ch === '-') {
      const prev = i > 0 ? expr.charAt(i - 1) : '';
      if (prev === '' || prev === '(' || '+-*/'.indexOf(prev) >= 0) {
        // 一元负号：与后续数字合并读"负X"
        let j = i + 1;
        while (j < expr.length && (isDigitCh(expr.charAt(j)) || expr.charAt(j) === '.')) {
          j++;
        }
        const num = parseFloat(expr.substring(i + 1, j));
        s += '负' + numberToZh(num);
        i = j;
      } else {
        s += '减';
        i++;
      }
    } else if (ch === '*') {
      s += '乘';
      i++;
    } else if (ch === '/') {
      s += '除以';
      i++;
    } else if (ch === '(') {
      s += '左括号';
      i++;
    } else if (ch === ')') {
      s += '右括号';
      i++;
    } else {
      i++;
    }
  }
  return s;
}

@Entry
@Component
struct Index {
  private engine: CalculatorEngine = new CalculatorEngine();
  private speech: SpeechService | undefined = undefined;
  @State displayText: string = '0';
  @State exprLine: string = '';
  @State voiceHint: string = '点击麦克风，语音输入算式';
  @State listening: boolean = false;

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.speech = new SpeechService(ctx);
    this.speech.setCallbacks(
      (partial: string) => {
        this.voiceHint = '聆听中：' + partial;
      },
      (finalText: string) => {
        this.handleVoiceText(finalText);
      },
      (msg: string) => {
        this.listening = false;
        this.voiceHint = msg;
      }
    );
    this.refresh();
  }

  aboutToDisappear(): void {
    this.speech?.release();
  }

  private refresh(): void {
    this.displayText = this.engine.getDisplay();
    this.exprLine = this.engine.getExpressionLine();
  }

  /** 等号：计算 → 显示 → 语音播报结果 */
  private onEquals(): void {
    this.engine.inputEquals();
    this.refresh();
    this.speakResult();
  }

  /** 播报："十二加八等于二十" */
  private speakResult(): void {
    if (this.displayText === '错误') {
      this.speech?.speak('计算错误');
      return;
    }
    const expr = this.engine.getExpression();
    const res = this.displayText;
    const zhExpr = exprToZh(expr);
    let zhRes = '';
    const v = parseFloat(res);
    if (Number.isFinite(v) && Math.abs(v) < 1e12) {
      zhRes = numberToZh(v);
    } else {
      zhRes = res; // 超大/科学计数直接读原文
    }
    this.speech?.speak(zhExpr + '等于' + zhRes);
  }

  /** 处理语音最终识别文本 */
  private handleVoiceText(text: string): void {
    this.listening = false;
    const r = parseVoiceCommand(text);
    if (r.type === 'clear') {
      this.engine.inputClear();
      this.voiceHint = '已清空';
    } else if (r.type === 'delete') {
      this.engine.inputDelete();
      this.voiceHint = '已删除';
    } else if (r.type === 'empty') {
      this.voiceHint = '没听清算式，请再说一次';
    } else if (r.type === 'expression') {
      const ok = this.engine.setExpression(r.expression as string);
      this.voiceHint = ok ? '语音输入：' + r.expression : '算式无效，请重试';
    } else if (r.type === 'equals') {
      const ok = this.engine.setExpression(r.expression as string);
      if (ok) {
        this.engine.inputEquals();
        this.voiceHint = '语音输入：' + r.expression + '=';
        this.speakResult();
      } else {
        this.voiceHint = '算式无效，请重试';
      }
    }
    this.refresh();
  }

  /** 麦克风键：开始/停止识别 */
  private onVoice(): void {
    if (this.listening) {
      this.speech?.stopListening();
      this.listening = false;
      this.voiceHint = '已停止聆听';
      return;
    }
    this.listening = true;
    this.voiceHint = '正在聆听，请说出算式…';
    this.speech?.startListening().then((ok: boolean) => {
      if (!ok) {
        this.listening = false;
      }
    });
  }

  private onKey(k: string): void {
    if (this.listening) {
      return; // 识别中忽略按键，避免状态冲突
    }
    if (k === 'C') {
      this.engine.inputClear();
    } else if (k === '⌫') {
      this.engine.inputDelete();
    } else if (k === '÷') {
      this.engine.inputOperator('/');
    } else if (k === '×') {
      this.engine.inputOperator('*');
    } else if (k === '−') {
      this.engine.inputOperator('-');
    } else if (k === '+') {
      this.engine.inputOperator('+');
    } else if (k === '=') {
      this.onEquals();
      return;
    } else if (k === '.') {
      this.engine.inputDot();
    } else {
      this.engine.inputDigit(k);
    }
    this.refresh();
  }

  private keyColor(k: string): string {
    if (k === '=' || k === '🎤 语音') {
      return '#FFFFFF';
    }
    return '#1A1B1C';
  }

  private keyBg(k: string): string {
    if (k === '=') {
      return '#2F6FED';
    }
    if (k === 'C' || k === '⌫') {
      return '#FDECEC';
    }
    if ('÷×−+'.indexOf(k) >= 0) {
      return '#E8F0FE';
    }
    if (k === '🎤 语音') {
      return this.listening ? '#FDECEC' : '#E6F4EA';
    }
    return '#FFFFFF';
  }

  @Builder
  keyRow(keys: string[]) {
    Row() {
      ForEach(keys, (k: string) => {
        this.keyButton(k)
      }, (k: string) => k)
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .margin({ bottom: 10 })
  }

  @Builder
  keyButton(k: string, isVoice: boolean = false) {
    Button(k)
      .width(isVoice ? '51%' : '24%')
      .height(64)
      .fontSize(isVoice ? 15 : 22)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.keyColor(k))
      .backgroundColor(this.keyBg(k))
      .borderRadius(12)
      .border({ width: 0.5, color: '#E4E3DD' })
      .onClick(() => {
        if (k === '🎤 语音') {
          this.onVoice();
        } else {
          this.onKey(k);
        }
      })
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Text('语音计算器')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1B1C')
        Blank()
        Text('无障碍语音')
          .fontSize(11)
          .fontColor('#6B7280')
      }
      .width('100%')
      .padding({ left: 4, right: 4, bottom: 12 })

      // 显示区：表达式行 + 结果行
      Column() {
        Text(this.exprLine)
          .fontSize(16)
          .fontColor('#6B7280')
          .width('100%')
          .textAlign(TextAlign.End)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.displayText)
          .fontSize(42)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1A1B1C')
          .width('100%')
          .textAlign(TextAlign.End)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#F2F3F5')
      .borderRadius(12)
      .alignItems(HorizontalAlign.End)

      // 语音状态提示
      Row() {
        Text(this.listening ? '● ' : '')
          .fontColor('#EA6668')
          .fontSize(12)
        Text(this.voiceHint)
          .fontSize(12)
          .fontColor('#6B7280')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      // 按键区
      this.keyRow(['C', '⌫', '÷', '×'])
      this.keyRow(['7', '8', '9', '−'])
      this.keyRow(['4', '5', '6', '+'])
      this.keyRow(['1', '2', '3', '='])
      Row() {
        this.keyButton('0')
        this.keyButton('.')
        this.keyButton('🎤 语音', true)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Blank()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor('#FFFFFF')
  }
}
