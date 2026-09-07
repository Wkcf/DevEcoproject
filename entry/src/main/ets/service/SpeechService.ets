/**
 * 语音服务封装：华为 Core Speech Kit（语音识别 speechRecognizer + 语音合成 textToSpeech）
 * 麦克风录音使用 @kit.AudioKit 的 AudioCapturer，把 16k/单声道/16bit PCM 流喂给识别引擎
 *
 * 设计要点（依据华为官方文档）：
 *  - 引擎懒加载，创建失败不影响计算器基础功能
 *  - writeAudio 每次只能写 640 或 1280 字节，录音数据按 1280 分包
 *  - 识别为短语音模式（≤60s），VAD 静音 3s 自动结束
 *  - TTS requestId 在同一引擎实例内只能用一次，每次播报生成新 ID
 */
import { speechRecognizer, textToSpeech } from '@kit.CoreSpeechKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

const TAG = 'SpeechService';
const WRITE_CHUNK = 1280;

export class SpeechService {
  private context: common.UIAbilityContext;
  private asrEngine: speechRecognizer.SpeechRecognitionEngine | undefined = undefined;
  private ttsEngine: textToSpeech.TextToSpeechEngine | undefined = undefined;
  private capturer: audio.AudioCapturer | undefined = undefined;
  private sessionId: string = '';
  private pending: number[] = [];
  private listening: boolean = false;
  private finalDelivered: boolean = false;
  private lastResult: string = '';
  private asrInitPromise: Promise<boolean> | undefined = undefined;
  private ttsInitPromise: Promise<boolean> | undefined = undefined;
  private ttsSeq: number = 0;

  private onPartialCb: (text: string) => void = () => { };
  private onFinalCb: (text: string) => void = () => { };
  private onErrorCb: (message: string) => void = () => { };

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  setCallbacks(onPartial: (text: string) => void, onFinal: (text: string) => void,
    onError: (message: string) => void): void {
    this.onPartialCb = onPartial;
    this.onFinalCb = onFinal;
    this.onErrorCb = onError;
  }

  // ---------------- 语音识别 ASR ----------------

  private ensureAsr(): Promise<boolean> {
    if (this.asrEngine !== undefined) {
      return Promise.resolve(true);
    }
    if (this.asrInitPromise === undefined) {
      this.asrInitPromise = new Promise<boolean>((resolve) => {
        const extra: Record<string, Object> = { 'locate': 'CN', 'recognizerMode': 'short' };
        const params: speechRecognizer.CreateEngineParams = {
          language: 'zh-CN',
          online: 1,
          extraParams: extra
        };
        speechRecognizer.createEngine(params,
          (err: BusinessError, engine: speechRecognizer.SpeechRecognitionEngine) => {
            if (!err) {
              this.asrEngine = engine;
              this.asrEngine?.setListener(this.buildAsrListener());
              resolve(true);
            } else {
              console.error(`${TAG} create asr engine failed: code=${err.code} msg=${err.message}`);
              resolve(false);
            }
          });
      });
    }
    return this.asrInitPromise;
  }

  private buildAsrListener(): speechRecognizer.RecognitionListener {
    return {
      onStart: (sessionId: string, eventMessage: string) => {
        console.info(`${TAG} asr onStart: ${eventMessage}`);
      },
      onEvent: (sessionId: string, eventCode: number, eventMessage: string) => {
        console.info(`${TAG} asr onEvent code=${eventCode}`);
      },
      onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
        if (result !== undefined && result.result !== undefined && result.result.length > 0) {
          this.lastResult = result.result;
          this.onPartialCb(result.result);
        }
      },
      onComplete: (sessionId: string, eventMessage: string) => {
        console.info(`${TAG} asr onComplete`);
        this.deliverFinal();
      },
      onError: (sessionId: string, errorCode: number, errorMessage: string) => {
        console.error(`${TAG} asr onError code=${errorCode} msg=${errorMessage}`);
        if (this.lastResult.length > 0) {
          this.deliverFinal();
        } else {
          this.finishCapture();
          this.onErrorCb('识别失败，请重试');
        }
      }
    };
  }

  /** 交付最终识别文本（幂等） */
  private deliverFinal(): void {
    this.finishCapture();
    if (this.finalDelivered) {
      return;
    }
    this.finalDelivered = true;
    if (this.lastResult.length > 0) {
      this.onFinalCb(this.lastResult);
    } else {
      this.onErrorCb('未识别到语音');
    }
  }

  async startListening(): Promise<boolean> {
    if (this.listening) {
      return true;
    }
    const ok = await this.ensureAsr();
    if (!ok) {
      this.onErrorCb('语音引擎初始化失败');
      return false;
    }
    this.sessionId = 'vc_' + Date.now().toString();
    this.pending = [];
    this.lastResult = '';
    this.finalDelivered = false;
    this.listening = true;
    const audioInfo: speechRecognizer.AudioInfo = {
      audioType: 'pcm',
      sampleRate: 16000,
      soundChannel: 1,
      sampleBit: 16
    };
    const extra: Record<string, Object> = {
      'recognitionMode': 0,
      'vadBegin': 2000,
      'vadEnd': 3000,
      'maxAudioDuration': 20000
    };
    const params: speechRecognizer.StartParams = {
      sessionId: this.sessionId,
      audioInfo: audioInfo,
      extraParams: extra
    };
    try {
      this.asrEngine?.startListening(params);
    } catch (e) {
      this.listening = false;
      this.onErrorCb('启动识别失败');
      return false;
    }
    const capOk = await this.startCapture();
    if (!capOk) {
      this.listening = false;
      try {
        this.asrEngine?.cancel(this.sessionId);
      } catch (e) {
        console.error(`${TAG} cancel failed`);
      }
      this.onErrorCb('麦克风启动失败，请检查权限');
      return false;
    }
    return true;
  }

  stopListening(): void {
    if (!this.listening) {
      return;
    }
    this.listening = false;
    this.finishCapture();
    try {
      this.asrEngine?.finish(this.sessionId);
    } catch (e) {
      console.error(`${TAG} finish failed`);
    }
    // 兜底：若引擎未回调 onComplete，1.2s 后强制交付最终结果
    setTimeout(() => {
      if (!this.finalDelivered) {
        this.deliverFinal();
      }
    }, 1200);
  }

  // ---------------- 麦克风录音 ----------------

  private async startCapture(): Promise<boolean> {
    try {
      const options: audio.AudioCapturerOptions = {
        streamInfo: {
          samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
          channels: audio.AudioChannel.CHANNEL_1,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
        },
        capturerInfo: {
          source: audio.SourceType.SOURCE_TYPE_MIC,
          capturerFlags: 0
        }
      };
      const cap = await audio.createAudioCapturer(options);
      cap.on('readData', (data: ArrayBuffer) => {
        this.onAudioData(data);
      });
      await cap.start();
      this.capturer = cap;
      return true;
    } catch (e) {
      console.error(`${TAG} start capture failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  private onAudioData(data: ArrayBuffer): void {
    const u8 = new Uint8Array(data);
    for (let i = 0; i < u8.length; i++) {
      this.pending.push(u8[i]);
    }
    this.flushAudio();
  }

  private flushAudio(): void {
    while (this.pending.length >= WRITE_CHUNK) {
      const chunk = new Uint8Array(WRITE_CHUNK);
      for (let i = 0; i < WRITE_CHUNK; i++) {
        chunk[i] = this.pending[i];
      }
      this.pending.splice(0, WRITE_CHUNK);
      try {
        this.asrEngine?.writeAudio(this.sessionId, chunk);
      } catch (e) {
        console.error(`${TAG} writeAudio failed: ${JSON.stringify(e)}`);
      }
    }
  }

  private finishCapture(): void {
    if (this.capturer !== undefined) {
      try {
        this.capturer.stop();
      } catch (e) {
        console.error(`${TAG} capturer stop failed`);
      }
      try {
        this.capturer.release();
      } catch (e) {
        console.error(`${TAG} capturer release failed`);
      }
      this.capturer = undefined;
    }
    this.pending = [];
  }

  // ---------------- 语音合成 TTS ----------------

  private ensureTts(): Promise<boolean> {
    if (this.ttsEngine !== undefined) {
      return Promise.resolve(true);
    }
    if (this.ttsInitPromise === undefined) {
      this.ttsInitPromise = new Promise<boolean>((resolve) => {
        const extra: Record<string, Object> = {
          'style': 'interaction-broadcast',
          'locate': 'CN',
          'name': 'VoiceCalculator'
        };
        const params: textToSpeech.CreateEngineParams = {
          language: 'zh-CN',
          person: 13, // 聆小珊女声音色（推荐 13）
          online: 1,
          extraParams: extra
        };
        textToSpeech.createEngine(params,
          (err: BusinessError, engine: textToSpeech.TextToSpeechEngine) => {
            if (!err) {
              this.ttsEngine = engine;
              this.ttsEngine?.setListener(this.buildTtsListener());
              resolve(true);
            } else {
              console.error(`${TAG} create tts engine failed: code=${err.code} msg=${err.message}`);
              resolve(false);
            }
          });
      });
    }
    return this.ttsInitPromise;
  }

  private buildTtsListener(): textToSpeech.SpeakListener {
    return {
      onStart: (requestId: string, response: textToSpeech.StartResponse) => {
        console.info(`${TAG} tts onStart ${requestId}`);
      },
      onComplete: (requestId: string, response: textToSpeech.CompleteResponse) => {
        console.info(`${TAG} tts onComplete ${requestId}`);
      },
      onStop: (requestId: string, response: textToSpeech.StopResponse) => {
        console.info(`${TAG} tts onStop ${requestId}`);
      },
      onError: (requestId: string, errorCode: number, errorMessage: string) => {
        console.error(`${TAG} tts onError code=${errorCode} msg=${errorMessage}`);
      }
    };
  }

  /** 播报文本（自动初始化引擎；requestId 每次唯一） */
  speak(text: string): void {
    if (text.length === 0) {
      return;
    }
    this.ensureTts().then((ok: boolean) => {
      if (!ok || this.ttsEngine === undefined) {
        this.onErrorCb('语音合成引擎初始化失败');
        return;
      }
      try {
        if (this.ttsEngine.isBusy()) {
          this.ttsEngine.stop();
        }
      } catch (e) {
        console.error(`${TAG} tts stop failed`);
      }
      this.ttsSeq++;
      const requestId = 'vc_' + Date.now().toString() + '_' + this.ttsSeq.toString();
      const extra: Record<string, Object> = {
        'speed': 1,
        'volume': 1,
        'pitch': 1,
        'languageContext': 'zh-CN',
        'audioType': 'pcm'
      };
      const params: textToSpeech.SpeakParams = {
        requestId: requestId,
        extraParams: extra
      };
      this.ttsEngine.speak(text, params);
    });
  }

  stopSpeaking(): void {
    try {
      this.ttsEngine?.stop();
    } catch (e) {
      console.error(`${TAG} tts stop failed`);
    }
  }

  /** 释放全部引擎资源（页面销毁时调用） */
  release(): void {
    this.stopListening();
    this.finishCapture();
    try {
      this.asrEngine?.shutdown();
    } catch (e) {
      console.error(`${TAG} asr shutdown failed`);
    }
    try {
      this.ttsEngine?.shutdown();
    } catch (e) {
      console.error(`${TAG} tts shutdown failed`);
    }
    this.asrEngine = undefined;
    this.ttsEngine = undefined;
    this.asrInitPromise = undefined;
    this.ttsInitPromise = undefined;
  }
}
