/**
 * JS 音源引擎：基于隐藏 WebView(ArkWeb) 执行标准格式 JS 插件
 * - registerJavaScriptProxy 注入宿主桥 window.__host（同步方法 httpStart/httpPoll/httpDone/log）
 * - runJavaScript 启动插件任务并轮询结果（__startTask / __getTaskResult）
 * - 支持插件全局 API：request / http.get / http.post / log / crypto(md5/sha1/sha256/aes/randomBytes)
 * - v3 事件驱动插件（全豆要等）：globalThis.lx 兼容层 + __startV3Task 动作分发（musicSearch/musicUrl/lyric）
 */
import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import type { BusinessError } from '@kit.BasicServicesKit';
import type { SongInfo } from '../model/MusicModel';
import type { SourceConfig } from './SourceManager';
import { CompatUtils } from './CompatUtils';

/** 插件调用结果 */
export interface PluginCallResult {
  ok: boolean;
  data?: Object;
  error?: string;
}

/** 插件 search(info, page, type) 兼容参数（信息对象形式） */
interface SearchInfoArg {
  keyword: string;
  name: string;
  artist: string;
  album: string;
}

/** 插件歌曲参数回退结构（rawData 缺失时由 SongInfo 字段拼装）
 *  v3 插件（如全豆要）的 getSongId/getPlatformSongId 依赖 songmid/hash 字段，
 *  回退结构必须包含这些字段以避免歌曲 ID 解析失败。 */
interface FallbackSongPayload {
  id: string;
  songId: string;
  songmid: string;
  hash: string;
  name: string;
  title: string;
  singer: string;
  artist: string;
  album: string;
}

/** v3 插件 musicSearch 参数（标准：keyword/page/pagesize） */
interface V3SearchInfo {
  keyword: string;
  page: number;
  pagesize: number;
}

/** v3 插件 musicUrl 参数 */
interface V3MusicInfo {
  musicInfo: Object;
  type: string;
}

/** v3 插件 lyric 参数 */
interface V3LyricInfo {
  musicInfo: Object;
}

const SEARCH_TIMEOUT: number = 30000;
const PLAY_TIMEOUT: number = 50000;
const LYRIC_TIMEOUT: number = 30000;
const POLL_INTERVAL: number = 120;
const READY_WAIT: number = 2000;
const DEFAULT_QUALITY: string = '128k';
const UA: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/** 注入到 JS 侧的宿主桥对象（方法经 registerJavaScriptProxy 暴露为 window.__host） */
class JsHostBridge {
  private static pending: Map<string, string> = new Map();
  private static seq: number = 0;

  /** 同步方法：启动一次宿主 HTTP 请求并立即返回 token，结果经 httpPoll 轮询取得 */
  httpStart(url: string, method: string, data: string, headersJson: string, contentType: string, timeoutMs: number): string {
    const token: string = 'r' + (++JsHostBridge.seq);
    JsHostBridge.pending.set(token, '');
    JsHostBridge.doRequest(url, method, data, headersJson, contentType, timeoutMs).then((res: string) => {
      JsHostBridge.pending.set(token, res);
    });
    return token;
  }

  /** 同步方法：取 token 对应请求结果，未完成返回 '' */
  httpPoll(token: string): string {
    const res: string | undefined = JsHostBridge.pending.get(token);
    return res === undefined ? '' : res;
  }

  /** 同步方法：清理已完成请求 */
  httpDone(token: string): void {
    JsHostBridge.pending.delete(token);
  }

  log(msg: string): void {
    console.info('[JsPlugin] ' + msg);
  }

  private static async doRequest(url: string, method: string, data: string, headersJson: string, contentType: string, timeoutMs: number): Promise<string> {
    const t: number = timeoutMs > 0 ? timeoutMs : 20000;
    // V1.2.2：提高 readTimeout 上限至 20s，匹配插件（如全豆要）getUrl 20s/search 15s 超时需求，
    // 避免 HTTP 请求还在传输数据时就被宿主层截断，导致轮询拿到空结果。
    const connectTimeout: number = t < 5000 ? t : 5000;
    const readTimeout: number = t > 20000 ? 20000 : t;
    const httpRequest = http.createHttp();
    try {
      const headers: Record<string, string> = { 'User-Agent': UA };
      if (headersJson && headersJson.length > 0) {
        try {
          const extra: Record<string, Object> = JSON.parse(headersJson) as Record<string, Object>;
          const keys: string[] = Object.keys(extra);
          for (let i = 0; i < keys.length; i++) {
            const key = keys[i];
            const val = extra[key];
            if (val !== undefined && val !== null) {
              headers[key] = String(val);
            }
          }
        } catch (_e) {
        }
      }
      if (method === 'POST') {
        const ct: string = contentType && contentType.length > 0 ? contentType : 'application/x-www-form-urlencoded';
        if (!headers['Content-Type']) {
          headers['Content-Type'] = ct;
        }
      }
      const options: http.HttpRequestOptions = {
        method: method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: headers,
        connectTimeout: connectTimeout,
        readTimeout: readTimeout,
        // V2.1.0：请求原始字节，避免 http 模块默认按 UTF-8 预解码导致 GBK 歌词乱码
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
      };
      if (method === 'POST' && data.length > 0) {
        options.extraData = data;
      }
      const response: http.HttpResponse = await httpRequest.request(url, options);
      let headerObj: Record<string, Object> = new Object() as Record<string, Object>;
      try {
        if (response.header) {
          headerObj = JSON.parse(JSON.stringify(response.header)) as Record<string, Object>;
        }
      } catch (_e) {
      }
      let body: string = '';
      const result: Object | ArrayBuffer | string = response.result;
      if (typeof result === 'string') {
        body = result as string;
      } else if (result instanceof ArrayBuffer) {
        // V1.2.3：按响应字符集解码（GBK/GB18030 歌词乱码修复）
        const contentType: string = String(headerObj['Content-Type'] ?? '');
        body = CompatUtils.decodeResponse(new Uint8Array(result), contentType);
      }
      return JSON.stringify(jsBridgeResp(response.responseCode, body, headerObj));
    } catch (e) {
      const err = e as BusinessError;
      // 输出具体失败原因（DNS/连接/超时/权限等），便于设备端日志定位挂起来源
      console.warn('[JsPlugin] http fail: ' + (err?.message ?? String(e)) + ' | ' + url);
      const emptyHeaders: Record<string, Object> = new Object() as Record<string, Object>;
      const resp: BridgeResponse = { statusCode: -1, body: '', headers: emptyHeaders, error: err?.message ?? String(e) };
      return JSON.stringify(resp);
    } finally {
      httpRequest.destroy();
    }
  }

  /** 桥诊断：当前挂起请求数与序号（配合任务超时定位） */
  diag(): string {
    const d: BridgeDiag = { pending: JsHostBridge.pending.size, seq: JsHostBridge.seq };
    return JSON.stringify(d);
  }
}

/** 宿主桥返回给 JS 侧的结果结构（经 JSON.stringify 序列化） */
interface BridgeResponse {
  statusCode: number;
  body: string;
  headers: Record<string, Object>;
  error?: string;
}

/** 桥诊断返回结构 */
interface BridgeDiag {
  pending: number;
  seq: number;
}

/** 构造宿主桥成功响应 */
function jsBridgeResp(statusCode: number, body: string, headers: Record<string, Object>): BridgeResponse {
  return { statusCode: statusCode, body: body, headers: headers };
}

/**
 * JS 插件引擎单例
 * 生命周期：Index 挂载 JsEngineHost → 首次 onPageEnd 调 init()（注册桥+refresh）
 *          → 二次 onPageEnd 调 markReady() → 之后 callPlugin 可用
 */
export class JsPluginEngine {
  static controller: webview.WebviewController | null = null;
  static ready: boolean = false;
  /** 最近一次插件调用失败原因（供上层展示真实错误，替代笼统的"未返回结果"） */
  static lastError: string = '';
  private static bridge: JsHostBridge = new JsHostBridge();
  private static proxyRegistered: boolean = false;

  /** 由 JsEngineHost 在页面首次加载完成后调用 */
  static init(controller: webview.WebviewController): void {
    JsPluginEngine.controller = controller;
    if (!JsPluginEngine.proxyRegistered) {
      JsPluginEngine.proxyRegistered = true;
      try {
        // 同步方法桥（httpStart/httpPoll/httpDone）：async 代理方法在部分设备上 Promise 无法被 JS await，
        // 改为同步启动 + 轮询，彻底规避挂起导致的 0 结果问题
        controller.registerJavaScriptProxy(JsPluginEngine.bridge, '__host', ['log', 'httpStart', 'httpPoll', 'httpDone']);
        controller.refresh();
        // V1.2.1：兜底定时器 — WebView refresh 后依赖二次 onPageEnd 触发 markReady，
        // 部分设备/场景下二次加载可能不触发（缓存/时序），超时后强制就绪避免永久不可用
        setTimeout(() => {
          if (!JsPluginEngine.ready) {
            console.warn('[JsPluginEngine] refresh 后 markReady 未触发，强制就绪');
            JsPluginEngine.markReady();
          }
        }, 5000);
      } catch (e) {
        const errMsg = e && (e as Error).message ? (e as Error).message : String(e);
        JsPluginEngine.lastError = `引擎初始化失败：${errMsg}`;
        console.error('[JsPluginEngine] init failed:', e);
      }
    }
  }

  /** refresh 之后的二次 onPageEnd 触发，标记引擎就绪 */
  static markReady(): void {
    JsPluginEngine.ready = true;
    console.info('[JsPluginEngine] ready');
    JsPluginEngine.probe();
  }

  /** 探测引擎内部状态（宿主桥是否注入、任务函数是否就绪），用于诊断 */
  private static async probe(): Promise<void> {
    const controller = JsPluginEngine.controller;
    if (!controller) return;
    try {
      const raw: string = await controller.runJavaScript('window.__probe ? window.__probe() : "no-probe"');
      console.info('[JsPluginEngine] probe: ' + JsPluginEngine.unwrap(raw));
    } catch (e) {
      console.warn('[JsPluginEngine] probe failed:', e);
    }
  }

  public static async ensureReady(): Promise<boolean> {
    if (JsPluginEngine.ready) {
      return true;
    }
    const deadline: number = Date.now() + READY_WAIT;
    while (!JsPluginEngine.ready) {
      if (Date.now() > deadline) {
        return false;
      }
      await JsPluginEngine.sleep(50);
    }
    return true;
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  /** 去除 runJavaScript 对 JS 字符串返回值的 JSON 包装
   *  ArkWeb 对 JS 表达式返回的字符串值会做 JSON 序列化（加双引号+转义），
   *  导致 "t3" 变为 "\"t3\""、JSON 字符串变为 "\"{\\\"done\\\":true...}\""。
   *  此方法检测并去除该包装，使后续 JSON.parse 能正确解析。 */
  private static unwrap(raw: string): string {
    if (raw.length > 0 && raw.charAt(0) === '"') {
      try {
        const s: Object = JSON.parse(raw);
        if (typeof s === 'string') {
          return s as string;
        }
      } catch (_e) {
      }
    }
    return raw;
  }

  private static isHttpUrl(url: string): boolean {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /** 执行插件方法（v1：module.exports 具名导出；启动任务 + 轮询结果，超时返回失败） */
  static async callPlugin(config: SourceConfig, func: string, args: Object[], timeoutMs: number): Promise<PluginCallResult> {
    const src: string = config.jsSource ?? '';
    // args 需双重 stringify：JSON.stringify(args) 生成 JSON 字符串，嵌入 script 后若不二次包装，
    // JS 引擎会将其解析为数组字面量而非字符串，导致 __startTask 中 JSON.parse(argsJson) 收到
    // 数组 toString() 结果（如 "关键词,1,"）而非 JSON 字符串
    const script: string =
      `window.__startTask(${JSON.stringify(config.name)}, ${JSON.stringify(src)}, ${JSON.stringify(func)}, ${JSON.stringify(JSON.stringify(args))})`;
    return JsPluginEngine.runScriptTask(script, timeoutMs);
  }

  /*   * 执行 v3 插件动作（事件驱动：musicSearch/musicUrl/lyric） */
  private static async callV3(config: SourceConfig, action: string, source: string, infoJson: string, timeoutMs: number): Promise<PluginCallResult> {
    const src: string = config.jsSource ?? '';
    const script: string =
      `window.__startV3Task(${JSON.stringify(config.name)}, ${JSON.stringify(src)}, ${JSON.stringify(action)}, ${JSON.stringify(source)}, ${JSON.stringify(infoJson)})`;
    return JsPluginEngine.runScriptTask(script, timeoutMs);
  }

  /** 执行 v3 插件动作（多音源分发：依次尝试，取第一个成功结果） */
  private static async callV3Multi(config: SourceConfig, action: string, sources: string[], infoJson: string, timeoutMs: number): Promise<PluginCallResult> {
    const src: string = config.jsSource ?? '';
    // sources 需双重 stringify：脚本参数应为 JSON 字符串（桥接端 JSON.parse(sourcesJson)），
    // 单次 stringify 生成数组字面量会被 JSON.parse 强制转字符串后解析失败（"未找到支持该操作的音源"）
    const script: string =
      `window.__startV3TaskMulti(${JSON.stringify(config.name)}, ${JSON.stringify(src)}, ${JSON.stringify(action)}, ${JSON.stringify(JSON.stringify(sources))}, ${JSON.stringify(infoJson)})`;
    return JsPluginEngine.runScriptTask(script, timeoutMs);
  }

  /** 启动任务脚本并轮询结果 */
  private static async runScriptTask(script: string, timeoutMs: number): Promise<PluginCallResult> {
    const controller = JsPluginEngine.controller;
    if (!controller) {
      return { ok: false, error: '引擎未初始化' };
    }
    if (!await JsPluginEngine.ensureReady()) {
      return { ok: false, error: '引擎初始化超时' };
    }
    try {
      // runJavaScript 对 JS 字符串返回值会做 JSON 序列化（加双引号转义），
      // __startTask/__startV3Task 返回 id 字符串，需 unwrap 去除外层引号
      const rawTaskId: string = await controller.runJavaScript(script);
      const taskId: string = JsPluginEngine.unwrap(rawTaskId);
      if (!taskId || taskId.length === 0) {
        JsPluginEngine.lastError = '任务启动失败（返回空 ID）';
        return { ok: false, error: '任务启动失败' };
      }
      const end: number = Date.now() + timeoutMs;
      while (Date.now() < end) {
        const raw: string = await controller.runJavaScript(`window.__getTaskResult(${JSON.stringify(taskId)})`);
        const unwrapped: string = JsPluginEngine.unwrap(raw);
        if (unwrapped && unwrapped.length > 0) {
          try {
            const parsed: Record<string, Object> = JSON.parse(unwrapped) as Record<string, Object>;
            const done: string = String(parsed['done'] ?? '');
            if (done === 'true') {
              const ok: string = String(parsed['ok'] ?? '');
              const err: string = String(parsed['error'] ?? '');
              return { ok: ok === 'true', data: parsed['data'], error: err };
            }
          } catch (_e) {
          }
        }
        await JsPluginEngine.sleep(POLL_INTERVAL);
      }
      // 超时：输出任务/桥/插件三方诊断，定位挂起点
      try {
        const diagRaw: string = await controller.runJavaScript(
          `window.__taskDiag ? window.__taskDiag(${JSON.stringify(taskId)}) : 'no-diag'`);
        console.warn('[JsPluginEngine] task timeout diag: ' + JsPluginEngine.unwrap(diagRaw) + ' | bridge=' + JsPluginEngine.bridge.diag());
      } catch (e) {
        console.warn('[JsPluginEngine] task timeout diag failed:', e);
      }
      return { ok: false, error: '插件执行超时' };
    } catch (e) {
      console.error('[JsPluginEngine] task failed:', e);
      return { ok: false, error: '引擎调用异常' };
    }
  }

  /** v3 插件已解析的音源 id 缓存（key 为 "插件名|action"，值为 JSON 数组字符串） */
  private static v3SourcesCache: Map<string, string> = new Map();

  /** 按 action 解析 v3 插件中支持该 action 的所有音源 id；无匹配时返回空数组 */
  private static async resolveV3SourcesForAction(config: SourceConfig, action: string): Promise<string[]> {
    const cacheKey: string = config.name + '|' + action;
    const cached: string | undefined = JsPluginEngine.v3SourcesCache.get(cacheKey);
    if (cached !== undefined && cached.length > 0) {
      try {
        return JSON.parse(cached) as string[];
      } catch (_e) {
      }
    }
    const controller = JsPluginEngine.controller;
    if (!controller) return [];
    if (!await JsPluginEngine.ensureReady()) return [];
    try {
      const raw: string = await controller.runJavaScript(
        `window.__v3Sources(${JSON.stringify(config.name)}, ${JSON.stringify(config.jsSource ?? '')})`);
      const unwrapped: string = JsPluginEngine.unwrap(raw);
      const srcs: string[] = [];
      if (unwrapped && unwrapped.length > 0 && unwrapped !== '{}') {
        const parsed: Record<string, Object> = JSON.parse(unwrapped) as Record<string, Object>;
        const keys: string[] = Object.keys(parsed);
        for (let i = 0; i < keys.length; i++) {
          const srcConf: Record<string, Object> = parsed[keys[i]] as Record<string, Object>;
          const actions: Object | undefined = srcConf['actions'];
          if (actions instanceof Array) {
            const acts: Object[] = actions as Object[];
            for (let j = 0; j < acts.length; j++) {
              if (String(acts[j]) === action) {
                srcs.push(keys[i]);
                break;
              }
            }
          }
        }
        if (srcs.length > 0) {
          JsPluginEngine.v3SourcesCache.set(cacheKey, JSON.stringify(srcs));
        } else {
          console.warn(`[JsPluginEngine] v3(${config.name}) 无音源支持 ${action}`);
        }
      }
      return srcs;
    } catch (e) {
      console.error('[JsPluginEngine] resolveV3SourcesForAction failed:', e);
      return [];
    }
  }

  /** 解析 v3 插件中支持 musicSearch 的所有音源 id */
  private static async resolveV3SearchSources(config: SourceConfig): Promise<string[]> {
    return await JsPluginEngine.resolveV3SourcesForAction(config, 'musicSearch');
  }

  /** v3 插件搜索：keyword → SongInfo[]（依次尝试支持 musicSearch 的每个音源） */
  private static async searchV3(config: SourceConfig, keyword: string): Promise<SongInfo[]> {
    const sources: string[] = await JsPluginEngine.resolveV3SearchSources(config);
    if (sources.length === 0) {
      JsPluginEngine.lastError = `插件 ${config.name} 未声明支持搜索动作(musicSearch)`;
      console.warn('[JsPluginEngine] v3 search: ' + JsPluginEngine.lastError);
      return [];
    }
    const info: V3SearchInfo = { keyword: keyword, page: 1, pagesize: 30 };
    const result: PluginCallResult = await JsPluginEngine.callV3Multi(config, 'musicSearch', sources, JSON.stringify(info), SEARCH_TIMEOUT);
    if (!result.ok || result.data === undefined || result.data === null) {
      JsPluginEngine.lastError = `插件 ${config.name} 搜索失败：${result.error ?? '无返回数据'}`;
      console.warn('[JsPluginEngine] v3 search failed:', JsPluginEngine.lastError);
      return [];
    }
    const rec: Record<string, Object> = result.data as Record<string, Object>;
    const list: Object | undefined = rec['list'];
    if (!(list instanceof Array)) {
      JsPluginEngine.lastError = `插件 ${config.name} 搜索返回数据格式异常`;
      return [];
    }
    const arr: Object[] = list as Object[];
    const songs: SongInfo[] = [];
    for (let i = 0; i < arr.length; i++) {
      const item: Record<string, Object> = arr[i] as Record<string, Object>;
      const song: SongInfo | null = JsPluginEngine.toSongInfo(item, config.name);
      if (song) {
        songs.push(song);
      }
    }
    JsPluginEngine.lastError = '';
    return songs;
  }

  /** 插件搜索：keyword → SongInfo[] */
  static async search(config: SourceConfig, keyword: string): Promise<SongInfo[]> {
    JsPluginEngine.lastError = '';
    // v3 事件驱动插件：走 lx 事件分发。若无 musicSearch 源则 fallback V1 搜索
    if (config.jsMode === 'v3') {
      const v3Results: SongInfo[] = await JsPluginEngine.searchV3(config, keyword);
      if (v3Results.length > 0 || JsPluginEngine.lastError === '') {
        return v3Results;
      }
      // v3 插件未声明 musicSearch（如全豆要只提供 musicUrl）→ 直接返回，避免走 V1 方法白白超时
      if (JsPluginEngine.lastError.indexOf('musicSearch') >= 0) {
        return [];
      }
      // V3 路径未声明 musicSearch —— 兜底走 V1 搜索
      JsPluginEngine.lastError = '';
    }
    // 兼容两种插件签名：search(keyword, page, type) 与 search(info, page, type)
    // 仅在快速返回空结果时重试对象形式，避免超时场景重复等待
    let data: Object | undefined;
    const start: number = Date.now();
    // V1.2.1：优先尝试 'search'，失败时尝试 'searchMusic'（部分插件用此方法名）
    const searchNames: string[] = ['search', 'searchMusic'];
    for (let attempt = 0; attempt < searchNames.length; attempt++) {
      const first = await JsPluginEngine.callPlugin(config, searchNames[attempt], [keyword, 1, ''], SEARCH_TIMEOUT);
      if (!first.ok) {
        if (attempt === 0) {
          console.warn(`[JsPluginEngine] search "${keyword}" failed with 'search', trying 'searchMusic': ${first.error}`);
        } else {
          console.warn(`[JsPluginEngine] search "${keyword}" failed: ${first.error}`);
        }
        continue;
      }
      const arr: Object[] | null = JsPluginEngine.extractSongArray(first.data);
      if (arr !== null) {
        data = arr;
        break;
      } else if (first.ok && (Date.now() - start) < 5000) {
        const info: SearchInfoArg = { keyword: keyword, name: keyword, artist: '', album: '' };
        const retry = await JsPluginEngine.callPlugin(config, searchNames[attempt],
          [info as Object, 1, ''], SEARCH_TIMEOUT);
        if (retry.ok) {
          const arr2: Object[] | null = JsPluginEngine.extractSongArray(retry.data);
          if (arr2 !== null) {
            data = arr2;
            break;
          }
        }
      }
    }
    if (data === undefined || !(data instanceof Array)) {
      JsPluginEngine.lastError = `插件 ${config.name} 搜索无返回结果`;
      return [];
    }
    const arr3: Object[] = data as Object[];
    const songs: SongInfo[] = [];
    for (let i = 0; i < arr3.length; i++) {
      const item = arr3[i] as Record<string, Object>;
      const song: SongInfo | null = JsPluginEngine.toSongInfo(item, config.name);
      if (song) {
        songs.push(song);
      }
    }
    return songs;
  }

  /** 从插件返回数据中提取歌曲数组（兼容裸数组 / {list} / {data} / {result} / {songs} 结构） */
  private static extractSongArray(data: Object | undefined): Object[] | null {
    if (data === undefined || data === null) {
      return null;
    }
    if (data instanceof Array) {
      return data as Object[];
    }
    if (typeof data === 'object') {
      const rec: Record<string, Object> = data as Record<string, Object>;
      const keys: string[] = ['list', 'data', 'result', 'songs'];
      for (let i = 0; i < keys.length; i++) {
        const val: Object | undefined = rec[keys[i]];
        if (val instanceof Array) {
          return val as Object[];
        }
      }
    }
    return null;
  }

  /** 插件取播放链接（V1.2.1：兼容多种方法名） */
  static async getPlayUrl(config: SourceConfig, song?: SongInfo): Promise<string> {
    if (!song) {
      return '';
    }
    if (JsPluginEngine.isHttpUrl(song.playUrl)) {
      return song.playUrl;
    }
    // v3 事件驱动插件：musicUrl 动作（多音源依次尝试）
    if (config.jsMode === 'v3') {
      const sources: string[] = await JsPluginEngine.resolveV3SourcesForAction(config, 'musicUrl');
      if (sources.length === 0) {
        JsPluginEngine.lastError = `插件 ${config.name} 未声明支持播放动作(musicUrl)`;
        return '';
      }
      const musicInfo: Object = JSON.parse(JsPluginEngine.buildSongInfoJson(song)) as Object;
      const info: V3MusicInfo = { musicInfo: musicInfo, type: DEFAULT_QUALITY };
      const result = await JsPluginEngine.callV3Multi(config, 'musicUrl', sources, JSON.stringify(info), PLAY_TIMEOUT);
      if (!result.ok) {
        JsPluginEngine.lastError = `插件 ${config.name} 获取播放链接失败：${result.error ?? ''}`;
        return '';
      }
      const url: string = JsPluginEngine.extractUrl(result.data);
      if (url.length === 0) {
        JsPluginEngine.lastError = `插件 ${config.name} 播放链接为空`;
      }
      return url;
    }
    const songInfoJson: string = JsPluginEngine.buildSongInfoJson(song);
    const songInfoObj: Object = JSON.parse(songInfoJson) as Object;
    // V1.2.1：按优先级尝试多种播放方法名（getMediaSource 兼容 MusicFree 格式插件）
    const methodNames: string[] = ['getMusicUrl', 'requestMusicUrl', 'getPlayUrl', 'getMusicInfo', 'getMediaSource'];
    for (let i = 0; i < methodNames.length; i++) {
      // MusicFree 插件（getMediaSource）用 quality 名称 'low/standard/high'，LX 插件用 '128k/320k'
      const qualityArg: string = methodNames[i] === 'getMediaSource' ? 'low' : DEFAULT_QUALITY;
      const result = await JsPluginEngine.callPlugin(config, methodNames[i], [songInfoObj, qualityArg], PLAY_TIMEOUT);
      if (result.ok) {
        const url: string = JsPluginEngine.extractUrl(result.data);
        if (url.length > 0) {
          if (i > 0) {
            console.info(`[JsPluginEngine] 播放方法名兼容: ${methodNames[i]} (非首选)`);
          }
          return url;
        }
      }
    }
    return '';
  }

  /** 从插件返回数据中提取 http(s) 播放链接 */
  private static extractUrl(data: Object | undefined): string {
    if (data === undefined || data === null) {
      return '';
    }
    if (typeof data === 'string') {
      const s = data as string;
      return JsPluginEngine.isHttpUrl(s.trim()) ? s.trim() : '';
    }
    const rec = data as Record<string, Object>;
    const u: string = (JsPluginEngine.strOf(rec['url']) || JsPluginEngine.strOf(rec['data'])).trim();
    return JsPluginEngine.isHttpUrl(u) ? u : '';
  }

  /** 插件取歌词（LRC 文本，V1.2.1：兼容多种方法名） */
  static async getLyric(config: SourceConfig, song?: SongInfo): Promise<string> {
    if (!song) {
      return '';
    }
    // v3 事件驱动插件：lyric 动作（多音源依次尝试）
    if (config.jsMode === 'v3') {
      const sources: string[] = await JsPluginEngine.resolveV3SourcesForAction(config, 'lyric');
      if (sources.length === 0) {
        JsPluginEngine.lastError = `插件 ${config.name} 未声明支持歌词动作(lyric)`;
        return '';
      }
      const musicInfo: Object = JSON.parse(JsPluginEngine.buildSongInfoJson(song)) as Object;
      const info: V3LyricInfo = { musicInfo: musicInfo };
      const result = await JsPluginEngine.callV3Multi(config, 'lyric', sources, JSON.stringify(info), LYRIC_TIMEOUT);
      if (!result.ok) {
        JsPluginEngine.lastError = `插件 ${config.name} 获取歌词失败：${result.error ?? ''}`;
        return '';
      }
      const data: Object | undefined = result.data;
      if (data === undefined || data === null) {
        JsPluginEngine.lastError = `插件 ${config.name} 歌词为空`;
        return '';
      }
      const rec = data as Record<string, Object>;
      const lrc: string = JsPluginEngine.strOf(rec['lrc']) || JsPluginEngine.strOf(rec['lyric']) || JsPluginEngine.strOf(rec['data']);
      return lrc.includes('[') ? lrc : '';
    }
    const songInfoJson: string = JsPluginEngine.buildSongInfoJson(song);
    const songInfoObj: Object = JSON.parse(songInfoJson) as Object;
    // V1.2.1：按优先级尝试多种歌词方法名（getMediaSource 兼容 MusicFree 格式插件，返回 rawLrc）
    const methodNames: string[] = ['getLyric', 'getLrc', 'getMusicLyric', 'getMediaSource'];
    for (let i = 0; i < methodNames.length; i++) {
      // MusicFree getMediaSource 需要 quality 参数（'low' 对应 128k）
      const lyricArgs: Object[] = methodNames[i] === 'getMediaSource' ?
        ([songInfoObj, 'low'] as Object[]) : [songInfoObj];
      const result = await JsPluginEngine.callPlugin(config, methodNames[i], lyricArgs, LYRIC_TIMEOUT);
      if (result.ok) {
        const data: Object | undefined = result.data;
        if (data === undefined || data === null) {
          continue;
        }
        if (typeof data === 'string') {
          const s = data as string;
          if (s.includes('[')) {
            if (i > 0) {
              console.info(`[JsPluginEngine] 歌词方法名兼容: ${methodNames[i]} (非首选)`);
            }
            return s;
          }
          continue;
        }
        const rec = data as Record<string, Object>;
        const lrc: string = JsPluginEngine.strOf(rec['lrc']) || JsPluginEngine.strOf(rec['lyric']) ||
          JsPluginEngine.strOf(rec['rawLrc']) || JsPluginEngine.strOf(rec['data']);
        if (lrc.includes('[')) {
          if (i > 0) {
            console.info(`[JsPluginEngine] 歌词方法名兼容: ${methodNames[i]} (非首选)`);
          }
          return lrc;
        }
      }
    }
    return '';
  }

  /** 将 SongInfo 还原为插件可识别的歌曲对象（优先用搜索时的原始数据） */
  private static buildSongInfoJson(song: SongInfo): string {
    if (song.rawData && song.rawData.length > 0) {
      try {
        const parsed: Record<string, Object> = JSON.parse(song.rawData) as Record<string, Object>;
        if (Object.keys(parsed).length > 0) {
          return song.rawData;
        }
      } catch (_e) {
      }
    }
    const fb: FallbackSongPayload = {
      id: song.songId,
      songId: song.songId,
      songmid: song.mid || song.hash || song.songId,
      hash: song.hash || song.mid || song.songId,
      name: song.songName,
      title: song.songName,
      singer: song.artist,
      artist: song.artist,
      album: song.album,
    };
    return JSON.stringify(fb);
  }

  private static strOf(v: Object | undefined): string {
    if (v === undefined || v === null) {
      return '';
    }
    if (typeof v === 'string') {
      return v as string;
    }
    if (typeof v === 'number' || typeof v === 'boolean') {
      return String(v);
    }
    return '';
  }

  /** 搜索项 → SongInfo（保留原始字段到 rawData 供后续 getMusicUrl/getLyric 使用） */
  private static toSongInfo(item: Record<string, Object>, platform: string): SongInfo | null {
    const id: string = JsPluginEngine.strOf(item['id']) || JsPluginEngine.strOf(item['songId']) ||
      JsPluginEngine.strOf(item['hash']) || JsPluginEngine.strOf(item['mid']);
    const name: string = JsPluginEngine.strOf(item['name']) || JsPluginEngine.strOf(item['title']) ||
      JsPluginEngine.strOf(item['songName']);
    if (id.length === 0 || name.length === 0) {
      return null;
    }
    let artist: string = JsPluginEngine.strOf(item['singer']) || JsPluginEngine.strOf(item['artist']) ||
      JsPluginEngine.strOf(item['singerName']);
    if (artist.length === 0 && item['singer'] instanceof Array) {
      const names: string[] = [];
      const arr = item['singer'] as Object[];
      for (let j = 0; j < arr.length; j++) {
        const s = arr[j] as Record<string, Object>;
        const n: string = JsPluginEngine.strOf(s['name']) || JsPluginEngine.strOf(s['singer']);
        if (n.length > 0) {
          names.push(n);
        }
      }
      artist = names.join('/');
    }
    let cover: string = JsPluginEngine.strOf(item['pic']) || JsPluginEngine.strOf(item['picUrl']) ||
      JsPluginEngine.strOf(item['albumPic']) || JsPluginEngine.strOf(item['coverUrl']) || JsPluginEngine.strOf(item['artwork']);
    if (cover.startsWith('//')) {
      cover = 'https:' + cover;
    }
    let durNum: number = 0;
    const durVal: Object | undefined = item['duration'] ?? item['interval'] ?? item['durationTime'];
    if (typeof durVal === 'number') {
      durNum = durVal as number;
    } else {
      durNum = Number.parseInt(JsPluginEngine.strOf(durVal)) || 0;
    }
    if (durNum > 3600) {
      durNum = Math.floor(durNum / 1000);
    }
    const durText: string = `${Math.floor(durNum / 60)}:${(durNum % 60).toString().padStart(2, '0')}`;
    const hash: string = JsPluginEngine.strOf(item['hash']);
    const mid: string = JsPluginEngine.strOf(item['mid']);
    // 平台标记：插件可在搜索项里带 source 字段（如聚合源的 kg/kw/tx/mg/wy），
    // 用于展示真实音源徽章（酷狗/酷我等）并直接按平台路由取链；缺省回退插件名
    const itemSource: string = JsPluginEngine.strOf(item['source']);
    const song: SongInfo = {
      songId: id,
      songName: name,
      artist: artist,
      album: JsPluginEngine.strOf(item['album']) || JsPluginEngine.strOf(item['albumName']),
      coverUrl: cover,
      source: itemSource.length > 0 ? itemSource : 'custom_' + platform,
      playUrl: JsPluginEngine.strOf(item['url']),
      quality: '128kbps/' + durText,
      hash: hash.length > 0 ? hash : undefined,
      mid: mid.length > 0 ? mid : undefined,
      rawData: JSON.stringify(item),
    };
    return song;
  }
}
