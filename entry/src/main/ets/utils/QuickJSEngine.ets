/**
 * QuickJS 引擎封装：基于 QuickJS 轻量级 JS 引擎执行标准格式 JS 插件
 * - 使用 NAPI 桥接 QuickJS 引擎
 * - 插件全局 API：request / http.get / http.post / log / console / crypto(md5/sha1/sha256/aes/randomBytes)
 * - Node 兼容垫片：Buffer / zlib(stub) / process / setTimeout / setImmediate / atob / btoa / TextEncoder
 * - v3 事件驱动插件（LX Music 规范）：globalThis.lx 完整兼容层
 *   request 支持 body/form/formData/qs/binary，JSON 响应自动解析，回调与 Promise 双模式
 * - 宿主驱动泵：QuickJS 无事件循环，HTTP 由宿主 ArkTS 并行执行，定时器由泵循环驱动，
 *   经 pumpJobs 泵动 Promise 微任务
 * - 详细日志：[QJS引擎] 引擎生命周期/原生请求/任务成败；[QJS插件] 插件内部日志转发
 */
import { JSContext, JSValue } from '@devzeng/quickjs';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import type { BusinessError } from '@kit.BasicServicesKit';
import type { SongInfo } from '../model/MusicModel';
import type { SourceConfig } from './SourceManager';
import { CompatUtils } from './CompatUtils';

/** 插件调用结果 */
export interface QuickJSPluginCallResult {
  ok: boolean;
  data?: Object;
  error?: string;
}

/** 宿主桥返回给 JS 侧的结果结构 */
interface BridgeResponse {
  statusCode: number;
  body: string;
  headers: Record<string, Object>;
  error?: string;
}

/** 宿主待处理 HTTP 请求项 */
interface HostHttpItem {
  id: string;
  url: string;
  method: string;
  data: string;
  headers: string;
  ct: string;
  timeout: number;
  binary: boolean;
}

/** 构造宿主桥成功响应 */
function jsBridgeResp(statusCode: number, body: string, headers: Record<string, Object>): BridgeResponse {
  return { statusCode: statusCode, body: body, headers: headers };
}

/** 插件搜索参数 */
interface SearchInfoArg {
  keyword: string;
  name: string;
  artist: string;
  album: string;
}

/** v3 插件搜索参数 */
interface V3SearchInfo {
  keyword: string;
  page: number;
  pagesize: number;
}

/** v3 插件播放链接参数 */
interface V3PlayInfoArg {
  musicInfo: SongInfo;
  type: string;
}

/** v3 插件歌词参数 */
interface V3LyricInfoArg {
  musicInfo: SongInfo;
}

/** 调用结果中的列表数据包装 */
interface PluginResultListData {
  list: Object;
}

const SEARCH_TIMEOUT: number = 30000;
const PLAY_TIMEOUT: number = 50000;
const LYRIC_TIMEOUT: number = 30000;
const DEFAULT_QUALITY: string = '128k';
const UA: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/** QuickJS shim 第1段：全局状态 / 日志通道 / 字节编解码 */
const SHIM_BOOT: string = '@@SHIM_BOOT@@';

/** QuickJS shim 第2段：MD5 / SHA-1 / SHA-256 / Base64 */
const SHIM_HASH: string = '@@SHIM_HASH@@';

/** QuickJS shim 第3段：AES / crypto / Buffer / 定时器 / 杂项垫片 */
const SHIM_AES: string = '@@SHIM_AES@@';

/** QuickJS shim 第4段：HTTP（LX 规范） / LX v3 兼容层 / 任务调度 */
const SHIM_HTTP: string = '@@SHIM_HTTP@@';

/**
 * QuickJS 插件引擎单例
 * 生命周期：首次调用 init() 创建引擎 → 之后 callPlugin 可用
 */
export class QuickJSEngine {
  private static context: JSContext | null = null;
  private static ready: boolean = false;
  /** 判断事件泵是否已被宿主接管（注入 lx v3 shim 用） */
  private static shimInjected: boolean = false;
  /** 已成功加载（注册了 request 处理器）的 v3 插件名，避免每次调用都传大体积源码 */
  private static loadedPlugins: Set<string> = new Set<string>();

  /** 初始化 QuickJS 引擎 */
  static init(): void {
    if (QuickJSEngine.context) {
      return;
    }
    try {
      QuickJSEngine.context = new JSContext();
      if (!QuickJSEngine.shimInjected) {
        QuickJSEngine.injectHostBridge();
        QuickJSEngine.shimInjected = true;
      }
      QuickJSEngine.ready = true;
      console.info('[QJS引擎] 初始化完成');
    } catch (e) {
      const err = e as BusinessError;
      console.error('[QJS引擎] 初始化失败: ' + (err?.message ?? String(e)));
    }
  }

  /** 确保引擎就绪（惰性初始化） */
  private static ensureCtx(): boolean {
    if (!QuickJSEngine.context) {
      QuickJSEngine.init();
    }
    return QuickJSEngine.context !== null;
  }

  /** 注入宿主桥 + v3 lx shim 到 QuickJS 全局对象 */
  private static injectHostBridge(): void {
    const ctx = QuickJSEngine.context;
    if (!ctx) {
      return;
    }
    try {
      const script: string = SHIM_BOOT + '\n' + SHIM_HASH + '\n' + SHIM_AES + '\n' + SHIM_HTTP;
      const v: JSValue = ctx.evaluateScript(script);
      if (v.isException) {
        const exc: JSValue | null = ctx.exception;
        console.error('[QJS引擎] shim 注入异常: ' + (exc !== null ? exc.toString() : '未知'));
        if (exc !== null) {
          exc.release();
        }
      }
      v.release();
      console.info('[QJS引擎] 宿主桥与 lx 兼容层注入完成 scriptLen=' + script.length.toString());
    } catch (e) {
      console.error('[QJS引擎] shim 注入失败: ' + String(e));
    }
  }

  /** 执行插件方法（同步插件） */
  static async callPlugin(config: SourceConfig, func: string, args: Object[], timeoutMs: number): Promise<QuickJSPluginCallResult> {
    if (!QuickJSEngine.ensureCtx()) {
      return { ok: false, error: '引擎未初始化' };
    }
    const ctx = QuickJSEngine.context!;
    try {
      const src: string = config.jsSource ?? '';
      console.info('[QJS引擎] 标准插件调用 plugin=' + config.name + ' func=' + func + ' len=' + src.length.toString());
      // 设置全局 module/exports（CommonJS 风格插件可用），顶层 eval 让 function 声明落到全局
      const loadVal = ctx.evaluateScript(
        'globalThis.__stdModule = { exports: {} }; globalThis.module = globalThis.__stdModule; globalThis.exports = globalThis.__stdModule.exports; ' +
        '(function() { try { eval(' + JSON.stringify(src) + '); return "ok"; } catch (e) { globalThis.__stdLoadError = String(e && e.message ? e.message : e); return "fail"; } })()');
      const loadFlag: string = loadVal.toString();
      loadVal.release();
      if (loadFlag !== 'ok') {
        let loadErr: string = '插件代码加载失败';
        const eVal = ctx.evaluateScript('globalThis.__stdLoadError || ""');
        const eStr: string = eVal.toString();
        eVal.release();
        if (eStr.length > 0) {
          loadErr = eStr;
        }
        console.warn('[QJS引擎] 标准插件加载失败 plugin=' + config.name + ' err=' + loadErr);
        return { ok: false, error: loadErr };
      }

      // 获取插件函数
      const funcObj = ctx.evaluateScript(
        '(function() { var m = globalThis.__stdModule; ' +
        'if (m && m.exports && typeof m.exports[' + JSON.stringify(func) + '] === "function") { return m.exports[' + JSON.stringify(func) + ']; } ' +
        'if (typeof globalThis[' + JSON.stringify(func) + '] === "function") { return globalThis[' + JSON.stringify(func) + ']; } ' +
        'return null; })()');
      if (funcObj.isNull || funcObj.isUndefined) {
        funcObj.release();
        console.warn('[QJS引擎] 插件方法不存在 plugin=' + config.name + ' func=' + func);
        return { ok: false, error: '插件方法 ' + func + ' 不存在' };
      }

      // 转换参数
      const jsArgs: JSValue[] = [];
      for (let i = 0; i < args.length; i++) {
        const argStr: string = JSON.stringify(args[i]) ?? 'null';
        const jsArg = ctx.evaluateScript('JSON.parse(' + JSON.stringify(argStr) + ')');
        jsArgs.push(jsArg);
      }

      // 调用插件方法
      const result: JSValue = funcObj.callWithArguments(jsArgs);

      // 释放参数与函数
      for (let i = 0; i < jsArgs.length; i++) {
        jsArgs[i].release();
      }
      funcObj.release();

      if (result.isException) {
        const exc: JSValue | null = ctx.exception;
        let errorMsg: string = '未知错误';
        if (exc !== null) {
          errorMsg = exc.errorMessage || exc.toString();
          exc.release();
        }
        result.release();
        console.warn('[QJS引擎] 插件方法执行异常 plugin=' + config.name + ' func=' + func + ' err=' + errorMsg);
        return { ok: false, error: errorMsg };
      }

      // 转换结果：经全局变量暂存后 JSON.stringify（JSValue.toString 对对象只会得到 [object Object]）
      ctx.setObject(result, '__sumyCallResult');
      result.release();
      const jsonVal = ctx.evaluateScript('(function() { try { return JSON.stringify(globalThis.__sumyCallResult); } catch (e) { return ""; } })()');
      const resultStr: string = jsonVal.toString();
      jsonVal.release();
      const clr = ctx.evaluateScript('globalThis.__sumyCallResult = undefined; true');
      clr.release();

      if (!resultStr || resultStr === 'undefined' || resultStr === 'null') {
        return { ok: false, error: '空返回结果' };
      }
      try {
        const obj: QuickJSPluginCallResult = JSON.parse(resultStr) as QuickJSPluginCallResult;
        if (obj && typeof obj === 'object' && obj.ok !== undefined) {
          return obj;
        }
        const listResult: Object = JSON.parse(resultStr);
        const listData: PluginResultListData = { list: listResult };
        return { ok: true, data: listData as Object };
      } catch (_e) {
        return { ok: true, data: resultStr };
      }
    } catch (e) {
      const err = e as BusinessError;
      console.error('[QJS引擎] callPlugin 失败: ' + (err?.message ?? String(e)));
      return { ok: false, error: err?.message ?? String(e) };
    }
  }

  /**
   * 宿主驱动泵：反复泵动 JS Promise 微任务 + 推进定时器 + 并行排空 HTTP 队列，
   * 直到 JS 侧 __getTaskResult(id) 返回 done 或超时。
   */
  private static async pumpTask(taskId: string, timeoutMs: number, actionLabel: string): Promise<QuickJSPluginCallResult> {
    const ctx = QuickJSEngine.context;
    if (!ctx) {
      return { ok: false, error: '引擎未初始化' };
    }
    const startTs: number = Date.now();
    const deadline: number = startTs + timeoutMs;

    while (Date.now() < deadline) {
      // 1) 泵动 JS 微任务，推进 async 插件代码到下一个 await
      ctx.pumpJobs(200);

      // 2) 推进宿主时钟并执行到期定时器（setTimeout/setInterval 由宿主泵驱动）
      try {
        const tVal = ctx.evaluateScript('globalThis.__setHostTime(' + Date.now().toString() + '); globalThis.__runTimers();');
        tVal.release();
      } catch (_e) {
      }
      ctx.pumpJobs(50);

      // 3) 排空 HTTP 队列并并行发送
      await QuickJSEngine.pumpHttpQueue();

      // 4) 读取任务结果
      const rVal = ctx.evaluateScript('globalThis.__getTaskResult(' + JSON.stringify(taskId) + ')');
      const rStr: string = rVal.toString();
      rVal.release();
      if (rStr && rStr.length > 0) {
        try {
          const rec = JSON.parse(rStr) as Record<string, Object>;
          const done: boolean = rec['done'] === true;
          if (done) {
            const elapsed: number = Date.now() - startTs;
            if (rec['ok'] === true) {
              console.info('[QJS引擎] 任务完成 ' + actionLabel + ' 耗时=' + elapsed.toString() + 'ms');
              QuickJSEngine.logDrained(20);
              return { ok: true, data: rec['data'] };
            }
            const errMsg: string = QuickJSEngine.strOf(rec['error']) || '插件执行失败';
            const logs: string[] = QuickJSEngine.drainLogs();
            console.warn('[QJS引擎] 任务失败 ' + actionLabel + ' 耗时=' + elapsed.toString() + 'ms err=' + errMsg);
            if (logs.length > 0) {
              console.warn('[QJS插件] ' + logs.slice(-50).join('\n[QJS插件] '));
              return { ok: false, error: errMsg + ' || ' + logs.slice(-3).join(' | ') };
            }
            return { ok: false, error: errMsg };
          }
        } catch (_e) {
        }
      }

      // 5) 短暂让位，避免忙等
      await QuickJSEngine.sleep(5);
    }

    const timeoutLogs: string[] = QuickJSEngine.drainLogs();
    console.warn('[QJS引擎] 任务超时 ' + actionLabel + ' timeout=' + timeoutMs.toString() + 'ms');
    if (timeoutLogs.length > 0) {
      console.warn('[QJS插件] ' + timeoutLogs.slice(-50).join('\n[QJS插件] '));
      return { ok: false, error: '任务超时 || ' + timeoutLogs.slice(-3).join(' | ') };
    }
    return { ok: false, error: '任务超时' };
  }

  /** 排空 JS 侧 HTTP 队列并并行发送，结果逐个回填 */
  private static async pumpHttpQueue(): Promise<void> {
    const ctx = QuickJSEngine.context;
    if (!ctx) {
      return;
    }
    const qVal = ctx.evaluateScript('JSON.stringify(globalThis.__httpQueue)');
    const qStr: string = qVal.toString();
    qVal.release();
    const clr = ctx.evaluateScript('globalThis.__httpQueue = [];');
    clr.release();
    if (!qStr || qStr.length <= 2) {
      return;
    }
    let items: Object[] = [];
    try {
      items = JSON.parse(qStr) as Object[];
    } catch (_e) {
      return;
    }
    const httpItems: HostHttpItem[] = [];
    for (let i = 0; i < items.length; i++) {
      const rec = items[i] as Record<string, Object>;
      const item: HostHttpItem = {
        id: QuickJSEngine.strOf(rec['id']) || '',
        url: QuickJSEngine.strOf(rec['url']) || '',
        method: QuickJSEngine.strOf(rec['method']) || 'GET',
        data: QuickJSEngine.strOf(rec['data']) || '',
        headers: QuickJSEngine.strOf(rec['headers']) || '{}',
        ct: QuickJSEngine.strOf(rec['ct']) || '',
        timeout: QuickJSEngine.toNum(rec['timeout']),
        binary: rec['binary'] === true,
      };
      if (item.url.length > 0 && item.id.length > 0) {
        httpItems.push(item);
      }
    }
    if (httpItems.length === 0) {
      return;
    }
    const pending: Promise<void>[] = [];
    for (let i = 0; i < httpItems.length; i++) {
      const it: HostHttpItem = httpItems[i];
      const job: Promise<void> = QuickJSEngine.hostHttp(it.url, it.method, it.data, it.headers, it.ct, it.timeout, it.binary)
        .then((resp: BridgeResponse): void => {
          QuickJSEngine.fillHttpResponse(it.id, resp);
        })
        .catch((e: Object): void => {
          const errMsg: string = e instanceof Error ? e.message : String(e);
          const emptyHeaders: Record<string, Object> = {};
          const failResp: BridgeResponse = { statusCode: -1, body: '', headers: emptyHeaders, error: errMsg || '请求异常' };
          QuickJSEngine.fillHttpResponse(it.id, failResp);
        });
      pending.push(job);
    }
    for (let i = 0; i < pending.length; i++) {
      await pending[i];
    }
  }

  /** 将宿主 HTTP 结果回填 JS 侧并 resolve 对应 Promise */
  private static fillHttpResponse(id: string, resp: BridgeResponse): void {
    const ctx = QuickJSEngine.context;
    if (!ctx) {
      return;
    }
    const hostJson: string = '{"id":' + JSON.stringify(id) +
      ',"code":' + String(resp.statusCode) +
      ',"body":' + JSON.stringify(resp.body ?? '') +
      ',"headers":' + JSON.stringify(JSON.stringify(resp.headers ?? {})) +
      ',"error":' + JSON.stringify(resp.error ?? '') + '}';
    const v = ctx.evaluateScript('globalThis.__hostResult = ' + hostJson + '; globalThis.__httpResolve();');
    v.release();
    ctx.pumpJobs(100);
  }

  /** 宿主真实 HTTP 请求（ArkTS http + 按字符集解码，支持 GET/POST/PUT/DELETE/HEAD 与二进制请求体） */
  private static async hostHttp(url: string, method: string, data: string, headersJson: string, contentType: string, timeoutMs: number, binary: boolean): Promise<BridgeResponse> {
    const started: number = Date.now();
    const m: string = method.toUpperCase();
    const showUrl: string = url.length > 400 ? url.substring(0, 400) + '...' : url;
    console.info('[QJS引擎] 原生请求 ' + m + ' ' + showUrl);
    const t: number = timeoutMs > 0 ? timeoutMs : 20000;
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
      const hasBody: boolean = m === 'POST' || m === 'PUT' || m === 'DELETE';
      let hasCt: boolean = false;
      const hkeys: string[] = Object.keys(headers);
      for (let i = 0; i < hkeys.length; i++) {
        if (hkeys[i].toLowerCase() === 'content-type') {
          hasCt = true;
          break;
        }
      }
      if (hasBody && data.length > 0 && !hasCt) {
        headers['Content-Type'] = contentType && contentType.length > 0 ? contentType : 'application/x-www-form-urlencoded';
      }
      let reqMethod: http.RequestMethod = http.RequestMethod.GET;
      if (m === 'POST') {
        reqMethod = http.RequestMethod.POST;
      } else if (m === 'PUT') {
        reqMethod = http.RequestMethod.PUT;
      } else if (m === 'DELETE') {
        reqMethod = http.RequestMethod.DELETE;
      } else if (m === 'HEAD') {
        reqMethod = http.RequestMethod.HEAD;
      }
      const options: http.HttpRequestOptions = {
        method: reqMethod,
        header: headers,
        connectTimeout: connectTimeout,
        readTimeout: readTimeout,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
      };
      if (hasBody && data.length > 0) {
        if (binary) {
          const decoded: Uint8Array = new util.Base64Helper().decodeSync(data);
          if (decoded.length > 0) {
            options.extraData = decoded.buffer as ArrayBuffer;
          }
        } else {
          options.extraData = data;
        }
      }
      const response: http.HttpResponse = await httpRequest.request(url, options);
      let headerObj: Record<string, Object> = {};
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
        const respCt: string = String(headerObj['Content-Type'] ?? '');
        body = CompatUtils.decodeResponse(new Uint8Array(result), respCt);
      }
      console.info('[QJS引擎] 请求完成 code=' + String(response.responseCode) + ' len=' + body.length.toString() + ' 耗时=' + (Date.now() - started).toString() + 'ms');
      return jsBridgeResp(response.responseCode, body, headerObj);
    } catch (e) {
      const err = e as BusinessError;
      const errMsg: string = err?.message ?? String(e);
      console.warn('[QJS引擎] 请求失败 err=' + errMsg + ' 耗时=' + (Date.now() - started).toString() + 'ms url=' + showUrl);
      const emptyHeaders: Record<string, Object> = {};
      const resp: BridgeResponse = { statusCode: -1, body: '', headers: emptyHeaders, error: errMsg };
      return resp;
    } finally {
      httpRequest.destroy();
    }
  }

  /** 解析 v3 插件支持指定 action 的所有音源 id（经 JS __v3Sources 上报的 sources 对象键） */
  static async getV3Sources(config: SourceConfig, action: string): Promise<string[]> {
    if (!QuickJSEngine.ensureCtx()) {
      return [];
    }
    const ctx = QuickJSEngine.context!;
    try {
      let src: string = config.jsSource ?? '';
      if (!QuickJSEngine.loadedPlugins.has(config.name)) {
        const lv = ctx.evaluateScript('globalThis.__v3Loaded(' + JSON.stringify(config.name) + ')');
        const loaded: boolean = lv.toBoolean();
        lv.release();
        if (loaded) {
          QuickJSEngine.loadedPlugins.add(config.name);
        }
      }
      if (QuickJSEngine.loadedPlugins.has(config.name)) {
        src = '';
      }
      if (src.length > 0) {
        console.info('[QJS引擎] 加载脚本 name=' + config.name + ' len=' + src.length.toString() + ' action=' + action);
      }
      const sVal = ctx.evaluateScript('globalThis.__v3Sources(' + JSON.stringify(config.name) + ', ' + JSON.stringify(src) + ')');
      const sStr: string = sVal.toString();
      sVal.release();
      const result: string[] = [];
      if (sStr && sStr.length > 0 && sStr !== '{}') {
        try {
          const obj = JSON.parse(sStr) as Record<string, Object>;
          const keys: string[] = Object.keys(obj);
          for (let i = 0; i < keys.length; i++) {
            result.push(keys[i]);
          }
        } catch (_e) {
        }
      }
      if (result.length > 0) {
        QuickJSEngine.loadedPlugins.add(config.name);
      }
      const iVal = ctx.evaluateScript('globalThis.__v3Info(' + JSON.stringify(config.name) + ')');
      const infoStr: string = iVal.toString();
      iVal.release();
      if (infoStr && infoStr.length > 2 && infoStr !== '{}') {
        console.info('[QJS引擎] 插件就绪 name=' + config.name + ' ' + infoStr + ' action=' + action + ' 可用源=' + result.join(','));
      } else {
        console.warn('[QJS引擎] 插件未就绪 name=' + config.name + ' action=' + action + '（未注册处理器或未上报 sources）');
      }
      // 兜底：action 专用源
      if (result.length === 0 && action === 'musicUrl' && config.name.length > 0) {
        result.push(config.name);
      }
      return result;
    } catch (e) {
      console.warn('[QJS引擎] getV3Sources 失败: ' + String(e));
      return [];
    }
  }

  /** 若插件已注册处理器则记入缓存（后续调用不再传大体积源码） */
  private static markLoaded(name: string): void {
    if (QuickJSEngine.loadedPlugins.has(name)) {
      return;
    }
    const ctx = QuickJSEngine.context;
    if (!ctx) {
      return;
    }
    try {
      const lv = ctx.evaluateScript('globalThis.__v3Loaded(' + JSON.stringify(name) + ')');
      const loaded: boolean = lv.toBoolean();
      lv.release();
      if (loaded) {
        QuickJSEngine.loadedPlugins.add(name);
      }
    } catch (_e) {
    }
  }

  /** 执行 v3 插件动作（单音源，供 V2 引擎分发多音源时调用） */
  static async callV3(config: SourceConfig, action: string, source: string, infoJson: string, timeoutMs: number): Promise<QuickJSPluginCallResult> {
    if (!QuickJSEngine.ensureCtx()) {
      return { ok: false, error: '引擎未初始化' };
    }
    const ctx = QuickJSEngine.context!;
    try {
      let src: string = config.jsSource ?? '';
      if (QuickJSEngine.loadedPlugins.has(config.name)) {
        src = '';
      }
      const idVal = ctx.evaluateScript('globalThis.__startV3Task(' +
        JSON.stringify(config.name) + ', ' +
        JSON.stringify(src) + ', ' +
        JSON.stringify(action) + ', ' +
        JSON.stringify(source) + ', ' +
        JSON.stringify(infoJson) + ')');
      const taskId: string = idVal.toString();
      idVal.release();
      const label: string = 'plugin=' + config.name + ' action=' + action + ' source=' + (source.length > 0 ? source : '(默认)');
      const result: QuickJSPluginCallResult = await QuickJSEngine.pumpTask(taskId, timeoutMs, label);
      QuickJSEngine.markLoaded(config.name);
      return result;
    } catch (e) {
      const err = e as BusinessError;
      console.error('[QJS引擎] callV3 失败: ' + (err?.message ?? String(e)));
      return { ok: false, error: err?.message ?? String(e) };
    }
  }

  /** 执行 v3 插件动作（多音源逐源尝试） */
  private static async callV3Multi(config: SourceConfig, action: string, sources: string[], infoJson: string, timeoutMs: number): Promise<QuickJSPluginCallResult> {
    if (!QuickJSEngine.ensureCtx()) {
      return { ok: false, error: '引擎未初始化' };
    }
    const ctx = QuickJSEngine.context!;
    try {
      let src: string = config.jsSource ?? '';
      if (QuickJSEngine.loadedPlugins.has(config.name)) {
        src = '';
      }
      const idVal = ctx.evaluateScript('globalThis.__startV3TaskMulti(' +
        JSON.stringify(config.name) + ', ' +
        JSON.stringify(src) + ', ' +
        JSON.stringify(action) + ', ' +
        JSON.stringify(JSON.stringify(sources)) + ', ' +
        JSON.stringify(infoJson) + ')');
      const taskId: string = idVal.toString();
      idVal.release();
      const label: string = 'plugin=' + config.name + ' action=' + action + ' sources=' + sources.join(',');
      const result: QuickJSPluginCallResult = await QuickJSEngine.pumpTask(taskId, timeoutMs, label);
      QuickJSEngine.markLoaded(config.name);
      return result;
    } catch (e) {
      const err = e as BusinessError;
      console.error('[QJS引擎] callV3Multi 失败: ' + (err?.message ?? String(e)));
      return { ok: false, error: err?.message ?? String(e) };
    }
  }

  /** 搜索歌曲（v3 走多音源逐源） */
  static async search(config: SourceConfig, keyword: string): Promise<SongInfo[]> {
    QuickJSEngine.init();

    if (config.jsMode === 'v3') {
      return await QuickJSEngine.searchV3(config, keyword);
    }

    const searchNames: string[] = ['search', 'searchMusic'];
    for (let attempt = 0; attempt < searchNames.length; attempt++) {
      const result = await QuickJSEngine.callPlugin(config, searchNames[attempt], [keyword, 1, ''], SEARCH_TIMEOUT);
      if (result.ok) {
        const songs = QuickJSEngine.extractSongs(result.data, config.name);
        if (songs.length > 0) {
          return songs;
        }
      }
    }
    return [];
  }

  /** 搜索 v3 插件（按 sources 逐源尝试） */
  static async searchV3(config: SourceConfig, keyword: string): Promise<SongInfo[]> {
    const sources: string[] = await QuickJSEngine.getV3Sources(config, 'musicSearch');
    const info: V3SearchInfo = { keyword: keyword, page: 1, pagesize: 30 };
    console.info('[QJS引擎] 搜索 plugin=' + config.name + ' keyword=' + keyword + ' sources=' + (sources.length > 0 ? sources.join(',') : '(默认)'));
    let result: QuickJSPluginCallResult;
    if (sources.length === 0) {
      result = await QuickJSEngine.callV3(config, 'musicSearch', '', JSON.stringify(info), SEARCH_TIMEOUT);
    } else {
      result = await QuickJSEngine.callV3Multi(config, 'musicSearch', sources, JSON.stringify(info), SEARCH_TIMEOUT);
    }
    if (result.ok && result.data) {
      const songs: SongInfo[] = QuickJSEngine.extractSongs(result.data, config.name);
      console.info('[QJS引擎] 搜索完成 plugin=' + config.name + ' 结果=' + songs.length.toString() + '首');
      return songs;
    }
    console.warn('[QJS引擎] 搜索失败 plugin=' + config.name + ' err=' + (result.error ?? '未知'));
    return [];
  }

  /** 从插件返回数据中提取歌曲数组 */
  private static extractSongs(data: Object | undefined, platform: string): SongInfo[] {
    if (!data) return [];

    let arr: Object[] | null = null;
    if (data instanceof Array) {
      arr = data as Object[];
    } else if (typeof data === 'object') {
      const rec = data as Record<string, Object>;
      const keys = ['list', 'data', 'result', 'songs'];
      for (const key of keys) {
        if (rec[key] instanceof Array) {
          arr = rec[key] as Object[];
          break;
        }
      }
    }

    if (!arr) return [];

    const songs: SongInfo[] = [];
    for (const item of arr) {
      const song = QuickJSEngine.toSongInfo(item as Record<string, Object>, platform);
      if (song) {
        songs.push(song);
      }
    }
    return songs;
  }

  /** 搜索项 → SongInfo */
  private static toSongInfo(item: Record<string, Object>, platform: string): SongInfo | null {
    const id = QuickJSEngine.strOf(item['id']) || QuickJSEngine.strOf(item['songId']) || QuickJSEngine.strOf(item['hash']) || QuickJSEngine.strOf(item['mid']);
    const name = QuickJSEngine.strOf(item['name']) || QuickJSEngine.strOf(item['title']) || QuickJSEngine.strOf(item['songName']);

    if (id.length === 0 || name.length === 0) return null;

    let artist = QuickJSEngine.strOf(item['singer']) || QuickJSEngine.strOf(item['artist']) || QuickJSEngine.strOf(item['singerName']);
    if (artist.length === 0 && item['singer'] instanceof Array) {
      const names: string[] = [];
      const arr = item['singer'] as Object[];
      for (const s of arr) {
        const singerObj = s as Record<string, Object>;
        const n = QuickJSEngine.strOf(singerObj['name']) || QuickJSEngine.strOf(singerObj['singer']);
        if (n.length > 0) names.push(n);
      }
      artist = names.join('/');
    }

    let cover = QuickJSEngine.strOf(item['pic']) || QuickJSEngine.strOf(item['picUrl']) || QuickJSEngine.strOf(item['albumPic']) || QuickJSEngine.strOf(item['coverUrl']) || QuickJSEngine.strOf(item['artwork']);
    if (cover.startsWith('//')) cover = 'https:' + cover;

    let durNum = 0;
    const durVal = item['duration'] ?? item['interval'] ?? item['durationTime'];
    if (typeof durVal === 'number') {
      durNum = durVal as number;
    } else {
      durNum = Number.parseInt(QuickJSEngine.strOf(durVal)) || 0;
    }
    if (durNum > 3600) durNum = Math.floor(durNum / 1000);
    const durText = `${Math.floor(durNum / 60)}:${(durNum % 60).toString().padStart(2, '0')}`;

    const hash = QuickJSEngine.strOf(item['hash']);
    const mid = QuickJSEngine.strOf(item['mid']);
    const itemSource = QuickJSEngine.strOf(item['source']);

    const song: SongInfo = {
      songId: id,
      songName: name,
      artist: artist,
      album: QuickJSEngine.strOf(item['album']) || QuickJSEngine.strOf(item['albumName']),
      coverUrl: cover,
      source: itemSource.length > 0 ? itemSource : 'custom_' + platform,
      playUrl: QuickJSEngine.strOf(item['url']),
      quality: '128kbps/' + durText,
      hash: hash.length > 0 ? hash : undefined,
      mid: mid.length > 0 ? mid : undefined,
      rawData: JSON.stringify(item),
    };
    return song;
  }

  /** 获取播放链接 */
  static async getPlayUrl(config: SourceConfig, song?: SongInfo): Promise<string> {
    if (!song) return '';

    QuickJSEngine.init();

    if (config.jsMode === 'v3') {
      const sources: string[] = await QuickJSEngine.getV3Sources(config, 'musicUrl');
      const info: V3PlayInfoArg = { musicInfo: song, type: DEFAULT_QUALITY };
      console.info('[QJS引擎] 取链 plugin=' + config.name + ' song=' + song.songName + ' id=' + song.songId + ' sources=' + (sources.length > 0 ? sources.join(',') : '(默认)'));
      const result: QuickJSPluginCallResult = sources.length > 0
        ? await QuickJSEngine.callV3Multi(config, 'musicUrl', sources, JSON.stringify(info), PLAY_TIMEOUT)
        : await QuickJSEngine.callV3(config, 'musicUrl', '', JSON.stringify(info), PLAY_TIMEOUT);
      if (result.ok && result.data) {
        const url: string = QuickJSEngine.extractUrl(result.data);
        console.info('[QJS引擎] 取链完成 plugin=' + config.name + ' song=' + song.songName + ' url=' + (url.length > 0 ? url.substring(0, 150) : '空'));
        return url;
      }
      console.warn('[QJS引擎] 取链失败 plugin=' + config.name + ' song=' + song.songName + ' err=' + (result.error ?? '未知'));
      return '';
    }

    const methodNames: string[] = ['getMusicUrl', 'requestMusicUrl', 'getPlayUrl', 'getMusicInfo', 'getMediaSource'];
    for (const methodName of methodNames) {
      const qualityArg = methodName === 'getMediaSource' ? 'low' : DEFAULT_QUALITY;
      const result = await QuickJSEngine.callPlugin(config, methodName, [song, qualityArg], PLAY_TIMEOUT);
      if (result.ok) {
        const url = QuickJSEngine.extractUrl(result.data);
        if (url.length > 0) return url;
      }
    }
    return '';
  }

  /** 从插件返回数据中提取 http(s) 播放链接 */
  private static extractUrl(data: Object | undefined): string {
    if (!data) return '';

    if (typeof data === 'string') {
      const s = data as string;
      return (s.startsWith('http://') || s.startsWith('https://')) ? s.trim() : '';
    }

    const rec = data as Record<string, Object>;
    const u = (QuickJSEngine.strOf(rec['url']) || QuickJSEngine.strOf(rec['data'])).trim();
    return (u.startsWith('http://') || u.startsWith('https://')) ? u : '';
  }

  /** 获取歌词 */
  static async getLyric(config: SourceConfig, song?: SongInfo): Promise<string> {
    if (!song) return '';

    QuickJSEngine.init();

    if (config.jsMode === 'v3') {
      const sources: string[] = await QuickJSEngine.getV3Sources(config, 'lyric');
      const info: V3LyricInfoArg = { musicInfo: song };
      console.info('[QJS引擎] 歌词 plugin=' + config.name + ' song=' + song.songName + ' sources=' + (sources.length > 0 ? sources.join(',') : '(默认)'));
      const result: QuickJSPluginCallResult = sources.length > 0
        ? await QuickJSEngine.callV3Multi(config, 'lyric', sources, JSON.stringify(info), LYRIC_TIMEOUT)
        : await QuickJSEngine.callV3(config, 'lyric', '', JSON.stringify(info), LYRIC_TIMEOUT);
      if (result.ok && result.data) {
        const rec = result.data as Record<string, Object>;
        const lrc = QuickJSEngine.strOf(rec['lrc']) || QuickJSEngine.strOf(rec['lyric']) || QuickJSEngine.strOf(rec['data']);
        console.info('[QJS引擎] 歌词完成 plugin=' + config.name + ' len=' + lrc.length.toString());
        return lrc.includes('[') ? lrc : '';
      }
      console.warn('[QJS引擎] 歌词失败 plugin=' + config.name + ' song=' + song.songName + ' err=' + (result.error ?? '未知'));
      return '';
    }

    const methodNames: string[] = ['getLyric', 'getLrc', 'getMusicLyric', 'getMediaSource'];
    for (const methodName of methodNames) {
      const lyricArgs: Object[] = methodName === 'getMediaSource' ? [song, 'low'] : [song];
      const result = await QuickJSEngine.callPlugin(config, methodName, lyricArgs, LYRIC_TIMEOUT);
      if (result.ok) {
        const data = result.data;
        if (!data) continue;

        if (typeof data === 'string') {
          const s = data as string;
          if (s.includes('[')) return s;
          continue;
        }

        const rec = data as Record<string, Object>;
        const lrc = QuickJSEngine.strOf(rec['lrc']) || QuickJSEngine.strOf(rec['lyric']) || QuickJSEngine.strOf(rec['rawLrc']) || QuickJSEngine.strOf(rec['data']);
        if (lrc.includes('[')) return lrc;
      }
    }
    return '';
  }

  /** 读取并清空插件日志（JS 侧 __pluginLogs） */
  private static drainLogs(): string[] {
    const ctx = QuickJSEngine.context;
    if (!ctx) {
      return [];
    }
    try {
      const v = ctx.evaluateScript('globalThis.__drainPluginLogs()');
      const s: string = v.toString();
      v.release();
      if (s && s.length > 2) {
        return JSON.parse(s) as string[];
      }
    } catch (_e) {
    }
    return [];
  }

  /** 将插件日志转发到控制台（任务成功时最多 max 条） */
  private static logDrained(max: number): void {
    const logs: string[] = QuickJSEngine.drainLogs();
    const n: number = Math.min(logs.length, max);
    for (let i = 0; i < n; i++) {
      console.info('[QJS插件] ' + logs[i]);
    }
  }

  /** 字符串转换辅助 */
  private static strOf(v: Object | undefined): string {
    if (v === undefined || v === null) return '';
    if (typeof v === 'string') return v as string;
    if (typeof v === 'number' || typeof v === 'boolean') return String(v);
    return '';
  }

  /** 数值转换辅助 */
  private static toNum(v: Object | undefined): number {
    if (v === undefined || v === null) return 0;
    if (typeof v === 'number') return v as number;
    if (typeof v === 'string') return Number.parseInt(v as string) || 0;
    return 0;
  }

  /** 短延时让位（宿主泵循环防忙等） */
  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  /** 释放引擎资源 */
  static release(): void {
    if (QuickJSEngine.context) {
      QuickJSEngine.context.release();
      QuickJSEngine.context = null;
      QuickJSEngine.ready = false;
      QuickJSEngine.shimInjected = false;
      QuickJSEngine.loadedPlugins.clear();
      console.info('[QJS引擎] 已释放');
    }
  }
}
