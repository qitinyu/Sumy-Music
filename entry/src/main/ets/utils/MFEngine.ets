// MFEngine.ets - MusicFree 插件引擎（WebView 沙箱执行器）
// 移植自 MusicFreeOH 的 WebPluginExecutor：
//   - 沙箱页面：resources/rawfile/mf_host.html（XHR/fetch 桥 + require 环境 + __mf 协议）
//   - 宿主桥：javaScriptProxy 注入为 window.mfNative
//   - HTTP 桥：mfNative.httpRequest → 原生 http → __mf.onHttpResult（body 走 base64）
//   - 结果回传：mfNative.onPluginResult(callId, ok, json)
// 协议说明：MusicFree 插件为 CommonJS 模块，导出 {platform, version, search, getMediaSource, getLyric, ...}

import { webview } from '@kit.ArkWeb'
import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import type { SongInfo } from '../model/MusicModel'
import { playLog } from './PlayLog'

/** MusicFree 插件实例信息（沙箱 __mf.load 回传） */
export interface MFPluginInfo {
  platform: string
  version: string
  srcUrl: string
  author: string
  methods: string[]
}

/** 挂载/调用挂起项 */
class MFPending {
  resolve: (value: string) => void = (_value: string): void => {}
  reject: (reason: Error) => void = (_reason: Error): void => {}
  timer: number = -1
}

/**
 * 沙箱宿主桥（通过 javaScriptProxy 注入为 window.mfNative）
 * 方法名与方法列表必须与 MFEngineHost 中 methodList 一致
 */
export class MFNativeBridge {
  onPluginResult(callId: string, ok: boolean, json: string): void {
    MFEngine.getInstance().handlePluginResult(callId, ok, json)
  }

  /** 沙箱页面加载完成信号（mf_host.html 末尾调用） */
  markReady(): void {
    MFEngine.getInstance().markReady()
  }

  /** 取插件用户变量（JSON 字符串）；当前不支持用户变量，返回空对象保持协议完整 */
  getUserVariables(_pluginName: string): string {
    return '{}'
  }

  /** HTTP 桥：沙箱内网络请求转发到原生 */
  httpRequest(callId: string, url: string, method: string, headersJson: string,
    bodyBase64: string, timeoutMs: number): void {
    MFEngine.getInstance().handleHttp(callId, url, method, headersJson, bodyBase64, timeoutMs)
  }

  /** 沙箱 console */
  log(level: string, message: string): void {
    if (level === 'error') {
      console.error('[MF插件] ' + message)
      playLog('MF插件', message)
    } else if (level === 'warn') {
      console.warn('[MF插件] ' + message)
    } else {
      console.info('[MF插件] ' + message)
    }
  }
}

export class MFEngine {
  private static inst: MFEngine | null = null

  static getInstance(): MFEngine {
    if (MFEngine.inst === null) {
      MFEngine.inst = new MFEngine()
    }
    return MFEngine.inst
  }

  /** 暴露给 javaScriptProxy 的桥对象 */
  readonly bridge: MFNativeBridge = new MFNativeBridge()

  private controller: webview.WebviewController | null = null
  private ready: boolean = false
  private readyResolvers: Array<() => void> = []
  /** 已挂载插件名集合（key = 插件名，与 SourceManager 配置名一致） */
  private mounted: Set<string> = new Set<string>()
  /** 插件名 → 实例信息 */
  private infoMap: Map<string, MFPluginInfo> = new Map<string, MFPluginInfo>()
  private pending: Map<string, MFPending> = new Map<string, MFPending>()
  private callSeq: number = 0
  /** 最近一次错误（供自检/诊断展示） */
  static lastError: string = ''

  private constructor() {}

  /** MFEngineHost 在 Web 组件创建后绑定 controller */
  attachController(controller: webview.WebviewController): void {
    this.controller = controller
  }

  isReady(): boolean {
    return this.ready
  }

  markReady(): void {
    if (this.ready) {
      return
    }
    this.ready = true
    console.info('[MF引擎] 沙箱就绪')
    const resolvers = this.readyResolvers.slice()
    this.readyResolvers = []
    for (const r of resolvers) {
      r()
    }
  }

  private async waitReady(timeoutMs: number): Promise<void> {
    if (this.ready) {
      return
    }
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        reject(new Error('MF 插件沙箱未就绪'))
      }, timeoutMs)
      this.readyResolvers.push(() => {
        clearTimeout(timer)
        resolve()
      })
    })
  }

  /** 是否已挂载 */
  isMounted(name: string): boolean {
    return this.mounted.has(name)
  }

  /**
   * 沙箱环境自检：返回各依赖库加载状态 JSON
   * {"native":true,"libs":8,"total":8,"missing":[]}
   */
  async probeEnvironment(): Promise<string> {
    return await this.runCall((callId: string): string => {
      return 'window.__mf.probe(' + JSON.stringify(callId) + ')'
    }, 10000)
  }

  /** 获取已挂载插件的方法列表 */
  getMethods(name: string): string[] {
    const info: MFPluginInfo | undefined = this.infoMap.get(name)
    return info !== undefined ? info.methods : []
  }

  /** 卸载记录（沙箱实例仍保留，重挂载时覆盖同名 key） */
  forget(name: string): void {
    this.mounted.delete(name)
    this.infoMap.delete(name)
  }

  /**
   * 实例重命名：挂载时用临时名，挂载成功后改用插件声明的 platform 名。
   * 同步移动沙箱实例与宿主侧记录。
   */
  rename(oldName: string, newName: string): void {
    if (oldName === newName) {
      return
    }
    const controller: webview.WebviewController | null = this.controller
    if (controller !== null) {
      const script: string = 'window.__mf.rename(' + JSON.stringify(oldName) + ', ' + JSON.stringify(newName) + ')'
      controller.runJavaScript(script).catch((): void => {
      })
    }
    if (this.mounted.has(oldName)) {
      this.mounted.delete(oldName)
      this.mounted.add(newName)
    }
    const info: MFPluginInfo | undefined = this.infoMap.get(oldName)
    if (info !== undefined) {
      this.infoMap.delete(oldName)
      this.infoMap.set(newName, info)
    }
  }

  /**
   * 挂载插件源码并返回实例信息；失败抛错。
   * 宿主经 runJavaScript 以脚本字面量传参：funcCode 为 JSON 字符串化后的源码
   */
  async mountPlugin(name: string, funcCode: string): Promise<MFPluginInfo> {
    const started: number = Date.now()
    await this.waitReady(30000)
    const env: Record<string, string> = {
      'appVersion': '2.0.6',
      'os': 'harmony',
      'lang': 'zh-CN',
    }
    const envText: string = JSON.stringify(env)
    const raw: string = await this.runCall((callId: string): string => {
      return 'window.__mf.load(' + JSON.stringify(name) + ', ' + JSON.stringify(funcCode) +
        ', ' + envText + ', ' + JSON.stringify(callId) + ')'
    }, 30000)
    const rec: Record<string, Object> = JSON.parse(raw) as Record<string, Object>
    const infoRec: Object | undefined = rec['info']
    if (infoRec === undefined || infoRec === null) {
      let message: string = '插件无法解析'
      const errRec: Record<string, Object> = rec as Record<string, Object>
      const msgVal: Object | undefined = errRec['message']
      if (msgVal !== undefined && msgVal !== null) {
        message = String(msgVal)
      }
      throw new Error(message)
    }
    const info: MFPluginInfo = MFEngine.parseInfo(infoRec)
    if (info.platform.length === 0) {
      throw new Error('插件缺少 platform 声明')
    }
    this.mounted.add(name)
    this.infoMap.set(name, info)
    playLog('MF引擎', `插件挂载成功: ${info.platform} v${info.version} 方法=${info.methods.length}个 耗时=${Date.now() - started}ms`)
    return info
  }

  private static parseInfo(v: Object): MFPluginInfo {
    const rec: Record<string, Object> = v as Record<string, Object>
    const info: MFPluginInfo = {
      platform: rec['platform'] !== undefined && rec['platform'] !== null ? String(rec['platform']) : '',
      version: rec['version'] !== undefined && rec['version'] !== null ? String(rec['version']) : '',
      srcUrl: rec['srcUrl'] !== undefined && rec['srcUrl'] !== null ? String(rec['srcUrl']) : '',
      author: rec['author'] !== undefined && rec['author'] !== null ? String(rec['author']) : '',
      methods: [],
    }
    const methodsVal: Object | undefined = rec['supportedMethods']
    if (methodsVal instanceof Array) {
      const arr: Object[] = methodsVal as Object[]
      for (let i = 0; i < arr.length; i++) {
        if (typeof arr[i] === 'string') {
          info.methods.push(arr[i] as string)
        }
      }
    }
    return info
  }

  /** 确保插件已挂载（未挂载时用配置源码挂载） */
  private async ensureMounted(name: string, funcCode: string): Promise<void> {
    if (this.mounted.has(name)) {
      return
    }
    await this.mountPlugin(name, funcCode)
  }

  /** 调用插件方法，返回结果 JSON 字符串 */
  private async callMethod(name: string, method: string, args: Object[]): Promise<string> {
    if (!this.mounted.has(name)) {
      throw new Error('插件未挂载: ' + name)
    }
    const argsText: string = JSON.stringify(args)
    return await this.runCall((callId: string): string => {
      return 'window.__mf.call(' + JSON.stringify(name) + ', ' + JSON.stringify(method) +
        ', ' + argsText + ', ' + JSON.stringify(callId) + ')'
    }, 60000)
  }

  /**
   * 搜索：调用插件 search(keyword, page, type)
   * MusicFree 结果字段：{id, title, artist, album, artwork, duration(ms), ...}
   */
  async search(name: string, funcCode: string, keyword: string): Promise<SongInfo[]> {
    await this.ensureMounted(name, funcCode)
    const methods: string[] = this.getMethods(name)
    if (methods.indexOf('search') < 0) {
      MFEngine.lastError = '插件未实现 search'
      return []
    }
    try {
      const raw: string = await this.callMethod(name, 'search', [keyword, 1, 'music'])
      const songs: SongInfo[] = []
      const rec: Record<string, Object> = JSON.parse(raw) as Record<string, Object>
      const dataVal: Object | undefined = rec['data']
      if (dataVal instanceof Array) {
        const arr: Object[] = dataVal as Object[]
        for (let i = 0; i < arr.length; i++) {
          const item: Record<string, Object> = arr[i] as Record<string, Object>
          const song: SongInfo | null = MFEngine.mfItemToSong(item, name)
          if (song !== null) {
            songs.push(song)
          }
        }
      }
      return songs
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e)
      MFEngine.lastError = message
      playLog('MF引擎', `搜索失败 插件=${name}: ${message}`)
      return []
    }
  }

  /** MusicFree 搜索条目 → SongInfo */
  private static mfItemToSong(item: Record<string, Object>, pluginName: string): SongInfo | null {
    const strOf = (v: Object | undefined): string => {
      if (v === undefined || v === null) return ''
      return String(v)
    }
    const id: string = strOf(item['id'])
    const title: string = strOf(item['title']) || strOf(item['name'])
    if (id.length === 0 || title.length === 0) {
      return null
    }
    // artist 可能为字符串或数组
    let artist: string = ''
    const artistVal: Object | undefined = item['artist']
    if (artistVal instanceof Array) {
      const parts: string[] = []
      const arr: Object[] = artistVal as Object[]
      for (let i = 0; i < arr.length; i++) {
        const it: Object = arr[i]
        if (typeof it === 'string') {
          parts.push(it as string)
        } else {
          const rec: Record<string, Object> = it as Record<string, Object>
          const n: string = strOf(rec['name'])
          if (n.length > 0) parts.push(n)
        }
      }
      artist = parts.join('、')
    } else {
      artist = strOf(artistVal)
    }
    // album 可能为字符串或 {title}
    let album: string = ''
    const albumVal: Object | undefined = item['album']
    if (albumVal instanceof Array || typeof albumVal === 'string' || typeof albumVal === 'number') {
      album = strOf(albumVal)
    } else if (albumVal !== undefined && albumVal !== null) {
      const rec: Record<string, Object> = albumVal as Record<string, Object>
      album = strOf(rec['title'])
    }
    let cover: string = strOf(item['artwork']) || strOf(item['pic']) || strOf(item['img'])
    if (cover.startsWith('//')) cover = 'https:' + cover
    // duration 单位毫秒 → mm:ss
    let durNum: number = 0
    const durVal: Object | undefined = item['duration']
    if (typeof durVal === 'number') {
      durNum = durVal as number
    } else if (durVal !== undefined && durVal !== null) {
      durNum = Number.parseInt(String(durVal)) || 0
    }
    if (durNum > 3600) durNum = Math.floor(durNum / 1000)
    const durText: string = `${Math.floor(durNum / 60)}:${(durNum % 60).toString().padStart(2, '0')}`
    const song: SongInfo = {
      songId: id,
      songName: title,
      artist: artist,
      album: album,
      coverUrl: cover,
      source: 'custom_' + pluginName,
      playUrl: '',
      quality: '128kbps/' + durText,
      rawData: JSON.stringify(item),
    }
    return song
  }

  /** SongInfo → MusicFree musicItem（优先回传搜索时的原始条目） */
  private static songToMfItem(song: SongInfo, pluginName: string): Record<string, Object> {
    let item: Record<string, Object> = {}
    if (song.rawData && song.rawData.length > 0) {
      try {
        const parsed: Record<string, Object> = JSON.parse(song.rawData) as Record<string, Object>
        item = parsed
      } catch (_e) {
        item = {}
      }
    }
    item['id'] = song.songId
    item['platform'] = pluginName
    if (item['title'] === undefined || item['title'] === null || String(item['title']).length === 0) {
      item['title'] = song.songName
    }
    if (item['artist'] === undefined || item['artist'] === null || String(item['artist']).length === 0) {
      item['artist'] = song.artist
    }
    return item
  }

  /**
   * 取播放链接：调用插件 getMediaSource(musicItem, quality)
   * 返回 {url, headers?}；仅返回 url（headers 需求记入日志）
   */
  async getPlayUrl(name: string, funcCode: string, song: SongInfo): Promise<string> {
    await this.ensureMounted(name, funcCode)
    const methods: string[] = this.getMethods(name)
    if (methods.indexOf('getMediaSource') < 0) {
      MFEngine.lastError = '插件未实现 getMediaSource'
      return ''
    }
    const started: number = Date.now()
    try {
      const item: Record<string, Object> = MFEngine.songToMfItem(song, name)
      const raw: string = await this.callMethod(name, 'getMediaSource', [item, 'standard'])
      const rec: Record<string, Object> = JSON.parse(raw) as Record<string, Object>
      const url: string = rec['url'] !== undefined && rec['url'] !== null ? String(rec['url']) : ''
      if (url.length === 0) {
        MFEngine.lastError = '取链返回空'
        playLog('MF引擎', `[取链] 返回空 url 插件=${name} 歌曲=${song.songName}-${song.artist} 耗时=${Date.now() - started}ms`)
        return ''
      }
      const headersVal: Object | undefined = rec['headers']
      if (headersVal !== undefined && headersVal !== null) {
        playLog('MF引擎', `[取链] 成功 url=${url.substring(0, 80)}（含播放 headers，当前播放器未设置，如无法播放请反馈）`)
      } else {
        playLog('MF引擎', `[取链] 成功 url=${url.substring(0, 80)} 耗时=${Date.now() - started}ms`)
      }
      return url
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e)
      MFEngine.lastError = message
      playLog('MF引擎', `[取链] 失败 插件=${name}: ${message}`)
      return ''
    }
  }

  /** 取歌词：调用插件 getLyric(musicItem)，返回 {rawLrc, translation?} */
  async getLyric(name: string, funcCode: string, song: SongInfo): Promise<string> {
    await this.ensureMounted(name, funcCode)
    const methods: string[] = this.getMethods(name)
    if (methods.indexOf('getLyric') < 0) {
      return ''
    }
    try {
      const item: Record<string, Object> = MFEngine.songToMfItem(song, name)
      const raw: string = await this.callMethod(name, 'getLyric', [item])
      const rec: Record<string, Object> = JSON.parse(raw) as Record<string, Object>
      const rawLrcVal: Object | undefined = rec['rawLrc']
      if (rawLrcVal !== undefined && rawLrcVal !== null && String(rawLrcVal).length > 0) {
        return String(rawLrcVal)
      }
      const lrcVal: Object | undefined = rec['lrc']
      if (lrcVal !== undefined && lrcVal !== null && String(lrcVal).length > 0) {
        return String(lrcVal)
      }
      const lyricVal: Object | undefined = rec['lyric']
      if (lyricVal !== undefined && lyricVal !== null && String(lyricVal).length > 0) {
        return String(lyricVal)
      }
      return ''
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e)
      playLog('MF引擎', `[歌词] 失败 插件=${name}: ${message}`)
      return ''
    }
  }

  handlePluginResult(callId: string, ok: boolean, json: string): void {
    const p: MFPending | undefined = this.pending.get(callId)
    if (p === undefined) {
      return
    }
    this.pending.delete(callId)
    if (p.timer >= 0) {
      clearTimeout(p.timer)
    }
    if (ok) {
      p.resolve(json)
    } else {
      let message: string = '插件调用失败'
      try {
        const rec: Record<string, Object> = JSON.parse(json) as Record<string, Object>
        const msgVal: Object | undefined = rec['message']
        if (msgVal !== undefined && msgVal !== null) {
          message = String(msgVal)
        }
      } catch (_e) {
      }
      p.reject(new Error(message))
    }
  }

  handleHttp(callId: string, url: string, method: string, headersJson: string,
    bodyBase64: string, timeoutMs: number): void {
    this.doHttp(callId, url, method, headersJson, bodyBase64, timeoutMs)
  }

  private async doHttp(callId: string, url: string, method: string, headersJson: string,
    bodyBase64: string, timeoutMs: number): Promise<void> {
    let status: number = 0
    let headersJsonOut: string = '{}'
    let bodyB64: string = ''
    const req: http.HttpRequest = http.createHttp()
    try {
      const headers: Record<string, string> = {}
      try {
        const rec: Record<string, Object> = JSON.parse(headersJson) as Record<string, Object>
        const keys: string[] = Object.keys(rec)
        for (let i = 0; i < keys.length; i++) {
          const v: Object | undefined = rec[keys[i]]
          if (typeof v === 'string') {
            headers[keys[i]] = v as string
          }
        }
      } catch (_e) {
      }
      const options: http.HttpRequestOptions = {
        method: MFEngine.methodOf(method),
        header: headers,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
      }
      if (bodyBase64.length > 0) {
        const helper: util.Base64Helper = new util.Base64Helper()
        const decoded: Uint8Array = helper.decodeSync(bodyBase64)
        const buf: ArrayBuffer = new ArrayBuffer(decoded.length)
        const view: Uint8Array = new Uint8Array(buf)
        for (let i = 0; i < decoded.length; i++) {
          view[i] = decoded[i]
        }
        options.extraData = buf
      }
      const resp: http.HttpResponse = await req.request(url, options)
      status = resp.responseCode
      headersJsonOut = MFEngine.normalizeHeaders(resp.header)
      const result: Object = resp.result
      if (result instanceof ArrayBuffer) {
        const helper: util.Base64Helper = new util.Base64Helper()
        bodyB64 = helper.encodeToStringSync(new Uint8Array(result as ArrayBuffer))
      }
    } catch (e) {
      status = 0
      headersJsonOut = '{}'
      bodyB64 = ''
    } finally {
      req.destroy()
    }
    this.respondHttp(callId, status, headersJsonOut, bodyB64)
  }

  /** 响应头归一化：key 小写；数组值原样保留（set-cookie），沙箱侧会处理 */
  private static normalizeHeaders(header: Object): string {
    const out: Record<string, Object> = {}
    try {
      const rec: Record<string, Object> = header as Record<string, Object>
      const keys: string[] = Object.keys(rec)
      for (let i = 0; i < keys.length; i++) {
        const k: string = keys[i]
        const lower: string = k.toLowerCase()
        const v: Object | undefined = rec[k]
        if (v === undefined || v === null) {
          continue
        }
        if (v instanceof Array) {
          out[lower] = v
        } else if (typeof v === 'string') {
          out[lower] = v
        } else {
          out[lower] = String(v)
        }
      }
    } catch (_e) {
    }
    return JSON.stringify(out)
  }

  private static methodOf(method: string): http.RequestMethod {
    const m: string = method.toUpperCase()
    if (m === 'POST') return http.RequestMethod.POST
    if (m === 'PUT') return http.RequestMethod.PUT
    if (m === 'DELETE') return http.RequestMethod.DELETE
    if (m === 'HEAD') return http.RequestMethod.HEAD
    if (m === 'OPTIONS') return http.RequestMethod.OPTIONS
    if (m === 'PATCH') return http.RequestMethod.PATCH
    return http.RequestMethod.GET
  }

  private respondHttp(callId: string, status: number, headersJson: string, bodyB64: string): void {
    const controller: webview.WebviewController | null = this.controller
    if (controller === null) {
      return
    }
    const script: string = 'window.__mf.onHttpResult(' + JSON.stringify(callId) + ', ' + status.toString() +
      ', ' + headersJson + ', ' + JSON.stringify(bodyB64) + ')'
    controller.runJavaScript(script).catch((): void => {
    })
  }

  private async runCall(scriptFactory: (callId: string) => string, timeoutMs: number): Promise<string> {
    const controller: webview.WebviewController | null = this.controller
    if (controller === null) {
      throw new Error('MF 插件沙箱未初始化')
    }
    this.callSeq += 1
    const callId: string = 'mf' + Date.now().toString() + '-' + this.callSeq.toString()
    const pendingCall: MFPending = new MFPending()
    const promise: Promise<string> = new Promise<string>((resolve, reject) => {
      pendingCall.resolve = resolve
      pendingCall.reject = reject
    })
    this.pending.set(callId, pendingCall)
    const timer: number = setTimeout(() => {
      const p: MFPending | undefined = this.pending.get(callId)
      if (p !== undefined) {
        this.pending.delete(callId)
        p.reject(new Error('MF 插件调用超时'))
      }
    }, timeoutMs)
    pendingCall.timer = timer
    try {
      await controller.runJavaScript(scriptFactory(callId))
    } catch (e) {
      clearTimeout(timer)
      this.pending.delete(callId)
      throw new Error('MF 沙箱脚本执行失败')
    }
    return promise
  }
}
