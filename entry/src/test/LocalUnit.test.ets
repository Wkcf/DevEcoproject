/**
 * 核心逻辑单元测试（在 DevEco Studio 中运行：entry/src/test → LocalUnit）
 * 覆盖：中文数字转换、表达式求值、数值格式化、语音命令解析、计算器状态机
 */
import { describe, it, expect } from '@ohos/hypium';
import { parseZhNumber, numberToZh } from '../main/ets/model/ChineseNumber';
import { evaluate, formatNumber, CalculatorEngine } from '../main/ets/model/CalculatorEngine';
import { parseVoiceCommand } from '../main/ets/model/VoiceCommand';

export default function localUnitTest() {
  describe('ChineseNumber', () => {
    it('parseZhNumber_basic', 0, () => {
      expect(parseZhNumber('十二')).assertEqual(12);
      expect(parseZhNumber('一百零五')).assertEqual(105);
      expect(parseZhNumber('两千零二十三')).assertEqual(2023);
      expect(parseZhNumber('十二万三千')).assertEqual(123000);
      expect(parseZhNumber('一亿零五')).assertEqual(100000005);
    });
    it('parseZhNumber_decimal_negative', 0, () => {
      expect(parseZhNumber('三点一四')).assertEqual(3.14);
      expect(parseZhNumber('点五')).assertEqual(0.5);
      expect(parseZhNumber('负十五')).assertEqual(-15);
    });
    it('parseZhNumber_digit_style', 0, () => {
      expect(parseZhNumber('二零二四')).assertEqual(2024);
      expect(parseZhNumber('两')).assertEqual(2);
      expect(parseZhNumber('十')).assertEqual(10);
      expect(parseZhNumber('零')).assertEqual(0);
    });
    it('parseZhNumber_invalid', 0, () => {
      expect(parseZhNumber('abc')).assertNull();
    });
    it('numberToZh_int', 0, () => {
      expect(numberToZh(12)).assertEqual('十二');
      expect(numberToZh(20)).assertEqual('二十');
      expect(numberToZh(105)).assertEqual('一百零五');
      expect(numberToZh(2023)).assertEqual('两千零二十三');
      expect(numberToZh(10500)).assertEqual('一万零五百');
      expect(numberToZh(105000)).assertEqual('十万零五千');
      expect(numberToZh(100500)).assertEqual('十万零五百');
      expect(numberToZh(12000)).assertEqual('一万两千');
      expect(numberToZh(100000123)).assertEqual('一亿零一百二十三');
      expect(numberToZh(123456789)).assertEqual('一亿两千三百四十五万六千七百八十九');
      expect(numberToZh(0)).assertEqual('零');
      expect(numberToZh(10)).assertEqual('十');
      expect(numberToZh(1001)).assertEqual('一千零一');
    });
    it('numberToZh_decimal_negative', 0, () => {
      expect(numberToZh(3.14)).assertEqual('三点一四');
      expect(numberToZh(0.5)).assertEqual('零点五');
      expect(numberToZh(-8)).assertEqual('负八');
      expect(numberToZh(-0.25)).assertEqual('负零点二五');
    });
  });

  describe('CalculatorEngine.evaluate', () => {
    it('basic_arith', 0, () => {
      expect(evaluate('12+8').value).assertEqual(20);
      expect(evaluate('2*3+4').value).assertEqual(10);
      expect(evaluate('2+3*4').value).assertEqual(14);
      expect(evaluate('10/4').value).assertEqual(2.5);
      expect(evaluate('1.5*2').value).assertEqual(3);
    });
    it('parenthesis_and_unary', 0, () => {
      expect(evaluate('(2+3)*4').value).assertEqual(20);
      expect(evaluate('-3+5').value).assertEqual(2);
      expect(evaluate('2*-3').value).assertEqual(-6);
      expect(evaluate('3*(2+4)').value).assertEqual(18);
      expect(evaluate('2*(3+4)-1').value).assertEqual(13);
      expect(evaluate('7-(-3)').value).assertEqual(10);
    });
    it('error_cases', 0, () => {
      expect(evaluate('5/0').ok).assertFalse();
      expect(evaluate('(1+2').ok).assertFalse();
      expect(evaluate('').ok).assertFalse();
    });
    it('formatNumber', 0, () => {
      expect(formatNumber(0.1 + 0.2)).assertEqual('0.3');
      expect(formatNumber(1 / 3)).assertEqual('0.333333333333');
      expect(formatNumber(20)).assertEqual('20');
    });
  });

  describe('VoiceCommand', () => {
    it('expression_commands', 0, () => {
      expect(parseVoiceCommand('十二加八').expression).assertEqual('12+8');
      expect(parseVoiceCommand('一百二十三乘以四十五').expression).assertEqual('123*45');
      expect(parseVoiceCommand('负三加五').expression).assertEqual('-3+5');
      expect(parseVoiceCommand('三点一四加二').expression).assertEqual('3.14+2');
    });
    it('equals_commands', 0, () => {
      const r = parseVoiceCommand('十二加八等于多少');
      expect(r.type).assertEqual('equals');
      expect(r.expression).assertEqual('12+8');
      const r2 = parseVoiceCommand('八除以二等于四');
      expect(r2.type).assertEqual('equals');
      expect(r2.expression).assertEqual('8/2');
    });
    it('action_commands', 0, () => {
      expect(parseVoiceCommand('请清空一下').type).assertEqual('clear');
      expect(parseVoiceCommand('删掉一位').type).assertEqual('delete');
      expect(parseVoiceCommand('你好呀').type).assertEqual('empty');
    });
  });

  describe('CalculatorEngine state machine', () => {
    it('digit_operator_equals', 0, () => {
      const eng = new CalculatorEngine();
      eng.inputDigit('1');
      eng.inputDigit('2');
      expect(eng.getDisplay()).assertEqual('12');
      eng.inputOperator('+');
      eng.inputDigit('3');
      expect(eng.getExpression()).assertEqual('12+3');
      eng.inputEquals();
      expect(eng.getDisplay()).assertEqual('15');
      expect(eng.getExpressionLine()).assertEqual('12+3');
    });
    it('continue_calc_and_clear', 0, () => {
      const eng = new CalculatorEngine();
      eng.inputDigit('1');
      eng.inputDigit('2');
      eng.inputOperator('+');
      eng.inputDigit('3');
      eng.inputEquals();
      eng.inputOperator('*');
      eng.inputDigit('2');
      eng.inputEquals();
      expect(eng.getDisplay()).assertEqual('30');
      eng.inputClear();
      expect(eng.getDisplay()).assertEqual('0');
    });
    it('div0_and_float', 0, () => {
      const eng = new CalculatorEngine();
      eng.setExpression('5/0');
      eng.inputEquals();
      expect(eng.getDisplay()).assertEqual('错误');
      expect(eng.getLastError()).assertEqual('除数为零');
      eng.setExpression('0.1+0.2');
      eng.inputEquals();
      expect(eng.getDisplay()).assertEqual('0.3');
    });
    it('delete_and_voice_equals', 0, () => {
      const eng = new CalculatorEngine();
      eng.inputDigit('1');
      eng.inputDigit('2');
      eng.inputDigit('3');
      eng.inputDelete();
      expect(eng.getDisplay()).assertEqual('12');
      eng.setExpression('-3+5');
      eng.inputEquals();
      expect(eng.getDisplay()).assertEqual('2');
      eng.setExpression('8/2');
      eng.inputEquals();
      expect(eng.getDisplay()).assertEqual('4');
    });
  });
}
