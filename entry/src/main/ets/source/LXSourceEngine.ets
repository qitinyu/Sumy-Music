/**
 * 音源引擎核心
 * 基于隐藏 WebView + javaScriptProxy 实现 JS 插件沙箱
 * 通过 lx_bridge.html 与 JS 插件进行事件驱动通信
 * 适配自 123 项目 LXSourceEngine
 */
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { LXUserApiInfoFull, LXUserApiSourceInfo, LXSourceRequestData } from './Interface';
import { lxSourceManager } from './LXSourceManager';
import { CompatUtils } from '../utils/CompatUtils';

export let lxEngineSendRequest: ((key: string, data: LXSourceRequestData) => void) | null = null;
export let lxEngineRegisterPromise: ((key: string,
  resolve: (result: object) => void, reject: (reason: Error) => void) => void) | null = null;
export let lxEngineIsReady: boolean = false;

interface LXProxyInfo {
  host: string;
  port: string;
}

class LXBridgeProxy {
  onMessageCallback: (message: string) => void = (): void => {};

  onMessage(message: string): void {
    this.onMessageCallback(message);
  }
}

interface PendingRequest {
  resolve: (result: object) => void;
  reject: (reason: Error) => void;
  timeoutId: number;
}

interface LXInitData {
  name: string;
  description: string;
  version: string;
  author: string;
  homepage: string;
  script: string;
  proxy: LXProxyInfo;
}

@Component
export struct LXSourceEngine {
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridgeProxy: LXBridgeProxy = new LXBridgeProxy();
  private methodList: string[] = ['onMessage'];
  private pendingRequests: Map<string, PendingRequest> = new Map();
  private webviewReady: boolean = false;
  private pendingInitData: string = '';
  private reloaded: boolean = false;
  @State isReady: boolean = false;
  @State sources: Record<string, LXUserApiSourceInfo> = {};
  @StorageLink('lxActiveSource') @Watch('onActiveSourceChanged') lxActiveSource: string = '';
  private currentApiInfo: LXUserApiInfoFull | null = null;
  onUpdateAlert: ((log: string, updateUrl: string) => void) | null = null;

  onActiveSourceChanged(): void {
    LXSourceEngine.appendLog('引擎 active 变化 → ' + this.lxActiveSource);
    if (this.lxActiveSource.length > 0) {
      // 切换插件：桥的 inited 事件单次注册，必须强制刷新 WebView 重置插件环境，
      // 否则旧插件（如全豆要）残留，新插件请求被旧插件拦截（"无效的平台参数"）
      this.webviewReady = false;
      this.isReady = false;
      this.reloaded = false;
      lxEngineIsReady = false;
      AppStorage.setOrCreate('lxEngineReady', false);
      try {
        this.controller.refresh();
      } catch (e) {
        LXSourceEngine.appendLog('引擎 refresh 失败: ' + JSON.stringify(e).substring(0, 100));
      }
      this.loadSourceById(this.lxActiveSource);
    } else {
      this.destroy();
    }
  }

  async loadSourceById(sourceId: string): Promise<void> {
    LXSourceEngine.appendLog('引擎 加载源 id=' + sourceId);
    let fullInfo: LXUserApiInfoFull | null = await lxSourceManager.getFullApiInfo(sourceId);
    if (fullInfo !== null) {
      LXSourceEngine.appendLog('引擎 读取脚本成功 name=' + fullInfo.name + ' len=' + fullInfo.script.length);
      this.initScript(fullInfo);
    } else {
      LXSourceEngine.appendLog('引擎 读取脚本失败（源不存在）');
    }
  }

  aboutToAppear(): void {
    LXSourceEngine.appendLog('引擎 aboutToAppear active=' + this.lxActiveSource);
    lxEngineSendRequest = (key: string, data: LXSourceRequestData): void => {
      this.sendRequest(key, data);
    };
    lxEngineRegisterPromise = (key: string,
      resolve: (result: object) => void, reject: (reason: Error) => void): void => {
      this.registerRequestPromise(key, resolve, reject);
    };
    this.bridgeProxy.onMessageCallback = (message: string): void => {
      this.handleJsMessage(message);
    };
    if (this.lxActiveSource.length > 0) {
      this.loadSourceById(this.lxActiveSource);
    }
  }

  aboutToDisappear(): void {
    lxEngineSendRequest = null;
    lxEngineRegisterPromise = null;
    lxEngineIsReady = false;
    this.clearAllRequests();
  }

  private clearAllRequests(): void {
    this.pendingRequests.forEach((req: PendingRequest, _key: string): void => {
      clearTimeout(req.timeoutId);
      req.reject(new Error('Engine destroyed'));
    });
    this.pendingRequests.clear();
  }

  initScript(apiInfo: LXUserApiInfoFull): void {
    LXSourceEngine.appendLog('引擎 initScript name=' + apiInfo.name + ' webviewReady=' + this.webviewReady);
    this.currentApiInfo = apiInfo;
    let proxyInfo: LXProxyInfo = { host: '', port: '' };
    let initData: LXInitData = {
      name: apiInfo.name,
      description: apiInfo.description,
      version: apiInfo.version,
      author: apiInfo.author,
      homepage: apiInfo.homepage,
      script: apiInfo.script,
      proxy: proxyInfo
    };
    let initDataJson: string = JSON.stringify(initData) || '';
    this.pendingInitData = initDataJson;
    if (this.webviewReady) {
      this.injectScript(initDataJson);
    }
  }

  sendRequest(requestKey: string, data: LXSourceRequestData): void {
    let reqJson: string = JSON.stringify(data) || '';
    let b64: string = this.toBase64(reqJson);
    this.runJs(`window._lx_handleRequest('${requestKey}', atob('${b64}'))`);
  }

  private toBase64(str: string): string {
    let encoder: util.TextEncoder = new util.TextEncoder();
    let data: Uint8Array = encoder.encodeInto(str);
    let base64Helper: util.Base64Helper = new util.Base64Helper();
    return base64Helper.encodeToStringSync(data);
  }

  registerRequestPromise(requestKey: string, resolve: (result: object) => void, reject: (reason: Error) => void): void {
    let existing: PendingRequest | undefined = this.pendingRequests.get(requestKey);
    if (existing !== undefined) {
      clearTimeout(existing.timeoutId);
    }
    let timeoutId: number = setTimeout((): void => {
      this.pendingRequests.delete(requestKey);
      reject(new Error('Request timeout'));
    }, 12000);
    this.pendingRequests.set(requestKey, {
      resolve: resolve,
      reject: reject,
      timeoutId: timeoutId
    });
  }

  cancelRequest(requestKey: string): void {
    let req: PendingRequest | undefined = this.pendingRequests.get(requestKey);
    if (req !== undefined) {
      clearTimeout(req.timeoutId);
      req.reject(new Error('Request cancelled'));
      this.pendingRequests.delete(requestKey);
    }
  }

  destroy(): void {
    this.clearAllRequests();
    this.isReady = false;
    this.sources = {};
    this.currentApiInfo = null;
    lxEngineIsReady = false;
    AppStorage.setOrCreate('lxEngineReady', false);
    AppStorage.setOrCreate('lxEngineSources', '{}');
  }

  private escapeJsString(s: string): string {
    return s.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/"/g, '\\"')
      .replace(/\n/g, '\\n').replace(/\r/g, '\\r');
  }

  private runJs(code: string): void {
    try {
      this.controller.runJavaScript(code).then((_v: string): void => {
        // executed
      }).catch((e: Object): void => {
        LXSourceEngine.appendLog('引擎 runJs 执行失败: ' + JSON.stringify(e).substring(0, 120));
      });
    } catch (e) {
      LXSourceEngine.appendLog('引擎 runJs 同步异常: ' + JSON.stringify(e).substring(0, 120));
    }
  }

  /** Appends a line to the shared lx play log (visible in the settings page). */
  private static appendLog(msg: string): void {
    let prev: string = AppStorage.get<string>('lxPlayLog') || '';
    let now: Date = new Date();
    let time: string = now.getHours().toString().padStart(2, '0') + ':' +
      now.getMinutes().toString().padStart(2, '0') + ':' +
      now.getSeconds().toString().padStart(2, '0');
    let log: string = prev + '[' + time + '] ' + msg + '\n';
    if (log.length > 20000) {
      log = log.substring(log.length - 20000);
    }
    AppStorage.setOrCreate('lxPlayLog', log);
  }

  private injectScript(initDataJson: string): void {
    LXSourceEngine.appendLog('引擎 注入脚本（webviewReady=' + this.webviewReady + '）');
    let b64: string = this.toBase64(initDataJson);
    this.runJs(`window._lx_init(JSON.parse(atob('${b64}')))`);
    const retryJson: string = initDataJson;
    const engineRef: LXSourceEngine = this;
    setTimeout((): void => {
      if (engineRef.isReady) {
        return;
      }
      if (!engineRef.reloaded) {
        // Not ready after 5s: refresh the webview page to revive its JS environment, then re-inject.
        engineRef.reloaded = true;
        engineRef.webviewReady = false;
        engineRef.pendingInitData = retryJson;
        LXSourceEngine.appendLog('引擎 注入后未就绪，刷新 WebView');
        try {
          engineRef.controller.refresh();
        } catch (e) {
          LXSourceEngine.appendLog('引擎 refresh 失败: ' + JSON.stringify(e).substring(0, 100));
        }
      } else {
        LXSourceEngine.appendLog('引擎 刷新后仍未就绪，请重启应用');
      }
    }, 5000);
  }

  private handleNativeFetch(data: Record<string, Object>): void {
    let requestId: number = data.requestId as number;
    let url: string = data.url as string;
    let method: string = (data.method as string) || 'GET';
    let headers: Record<string, string> = data.headers as Record<string, string>;
    let body: string = data.body as string;
    let timeout: number = (data.timeout as number) || 15000;
    console.info('[TRACE:nativeFetch] req start id=' + requestId + ' url=' + url.substring(0, 100));

    let httpRequest = http.createHttp();
    let reqHeaders: Record<string, string> = {};
    if (headers !== undefined && headers !== null) {
      let keys: string[] = Object.keys(headers);
      for (let i: number = 0; i < keys.length; i++) {
        reqHeaders[keys[i]] = headers[keys[i]] as string;
      }
    }

    let reqMethod: http.RequestMethod = http.RequestMethod.GET;
    let m: string = method.toUpperCase();
    if (m === 'POST') {
      reqMethod = http.RequestMethod.POST;
    } else if (m === 'PUT') {
      reqMethod = http.RequestMethod.PUT;
    } else if (m === 'DELETE') {
      reqMethod = http.RequestMethod.DELETE;
    } else if (m === 'OPTIONS') {
      reqMethod = http.RequestMethod.OPTIONS;
    } else if (m === 'HEAD') {
      reqMethod = http.RequestMethod.HEAD;
    }

    let extraData: string | ArrayBuffer | Object = '';
    if (body !== undefined && body !== null && body.length > 0) {
      extraData = body;
    }

    httpRequest.request(url, {
      method: reqMethod,
      header: reqHeaders,
      extraData: extraData,
      connectTimeout: timeout,
      readTimeout: timeout,
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    }).then((resp: http.HttpResponse): void => {
      let respBody: string = '';
      if (typeof resp.result === 'string') {
        respBody = resp.result as string;
      } else if (resp.result !== undefined && resp.result !== null) {
        // V1.2.3：按响应字符集解码，修复 GBK 歌词乱码
        const contentType: string = String((resp.header as Record<string, Object>)['Content-Type'] ?? '');
        const bytes: Uint8Array = resp.result instanceof ArrayBuffer ? new Uint8Array(resp.result) : resp.result as Uint8Array;
        respBody = CompatUtils.decodeResponse(bytes, contentType);
      }
      console.info('[TRACE:nativeFetch] req ok id=' + requestId + ' code=' + resp.responseCode + ' bodyLen=' + respBody.length);
      let headersJson: string = JSON.stringify(resp.header) || '{}';
      let escHeaders: string = this.escapeJsString(headersJson);
      let escBody: string = this.escapeJsString(respBody);
      this.runJs(`window._lx_handleFetchResponse(${requestId}, null, ${resp.responseCode}, '${escHeaders}', '${escBody}')`);
      console.info('[TRACE:nativeFetch] js callback sent id=' + requestId);
    }).catch((err: Object): void => {
      let errMsg: string = JSON.stringify(err);
      console.error('[TRACE:nativeFetch] req fail id=' + requestId + ' err=' + errMsg);
      let escErr: string = this.escapeJsString(errMsg);
      this.runJs(`window._lx_handleFetchResponse(${requestId}, '${escErr}', 0, '{}', '')`);
    });
  }

  private handleJsMessage(message: string): void {
    try {
      let msg: Record<string, Object> = JSON.parse(message) as Record<string, Object>;
      let event: string = msg.event as string;
      let data: Record<string, Object> = msg.data as Record<string, Object>;

      switch (event) {
        case 'nativeFetch': {
          this.handleNativeFetch(data);
          break;
        }
        case 'init': {
          let status: boolean = data.status as boolean;
          let errorMsg: string = (data.message as string) || '';
          let srcs: Record<string, LXUserApiSourceInfo> =
            data.sources as Record<string, LXUserApiSourceInfo>;
          LXSourceEngine.appendLog('引擎 init 事件 status=' + status +
            (errorMsg.length > 0 ? ' msg=' + errorMsg.substring(0, 80) : ''));
          if (status && srcs !== undefined) {
            this.isReady = true;
            this.sources = srcs;
            lxEngineIsReady = true;
            AppStorage.setOrCreate('lxEngineReady', true);
            AppStorage.setOrCreate('lxEngineSources', JSON.stringify(srcs) || '{}');
            LXSourceEngine.appendLog('引擎 就绪 ' + Object.keys(srcs).length);
          } else {
            this.isReady = false;
            this.sources = {};
            AppStorage.setOrCreate('lxEngineReady', false);
            AppStorage.setOrCreate('lxEngineSources', '{}');
          }
          break;
        }
        case 'response': {
          let requestKey: string = data.requestKey as string;
          let status: boolean = data.status as boolean;
          let message: string = (data.message as string) || '';
          let result: object = data.result as object;
          let pending: PendingRequest | undefined = this.pendingRequests.get(requestKey);
          if (pending !== undefined) {
            clearTimeout(pending.timeoutId);
            this.pendingRequests.delete(requestKey);
            if (status && result !== undefined) {
              pending.resolve(result);
            } else {
              pending.reject(new Error(message || 'Request failed'));
            }
          }
          break;
        }
        case 'updateAlert': {
          let log: string = data.log as string;
          let updateUrl: string = (data.updateUrl as string) || '';
          if (this.onUpdateAlert !== null) {
            this.onUpdateAlert(log, updateUrl);
          }
          break;
        }
        case 'log': {
          let dataObj: Record<string, Object> = data as Record<string, Object>;
          let msg: string = (dataObj.message as string) || '';
          let prev: string = AppStorage.get<string>('lxPlayLog') || '';
          let now: Date = new Date();
          let time: string = now.getHours().toString().padStart(2, '0') + ':' +
            now.getMinutes().toString().padStart(2, '0') + ':' +
            now.getSeconds().toString().padStart(2, '0');
          AppStorage.setOrCreate('lxPlayLog', prev + '[' + time + '] ' + msg + '\n');
          break;
        }
      }
    } catch (e) {
      console.error('LXSourceEngine handleJsMessage error:', JSON.stringify(e));
    }
  }

  build(): void {
    Web({ src: $rawfile('lx_bridge.html'), controller: this.controller })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(true)
      .onlineImageAccess(true)
      .mixedMode(MixedMode.All)
      .javaScriptProxy({
        object: this.bridgeProxy,
        name: 'ohos_bridge',
        methodList: this.methodList,
        controller: this.controller
      })
      .onPageEnd((): void => {
        this.webviewReady = true;
        LXSourceEngine.appendLog('引擎 webview onPageEnd，待注入=' + (this.pendingInitData.length > 0));
        if (this.pendingInitData.length > 0) {
          this.injectScript(this.pendingInitData);
          this.pendingInitData = '';
        }
      })
      .width(1)
      .height(1)
      .opacity(0)
  }
}