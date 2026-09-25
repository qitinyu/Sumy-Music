// SourceManager.ets - JS 插件管理器
// 管理标准格式 JS 插件的导入、搜索、播放与歌词

import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import fs from '@ohos.file.fs'
import type { SongInfo } from '../model/MusicModel'
import { SourceStatus } from '../model/MusicModel'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { JsPluginEngine } from './JsPluginEngine'
import { JsPluginEngine as JsPluginEngineV2 } from './JsPluginEngineV2'
import { MFEngine } from './MFEngine'
import { getLXMusicUrl, getLXLyric, getLXPic } from '../source/LXPlayHelper'
import { lxEngineIsReady } from '../source/LXSourceEngine'
import { lxSourceManager } from '../source/LXSourceManager'
import type { LXUserApiInfo } from '../source/Interface'

export interface ImportResult {
  name: string
  success: boolean
  error?: string
}

export interface SourceConfig {
  name: string
  type: string
  jsSource?: string
  jsSourceHash?: string
  jsPlatform?: string
  jsVersion?: string
  jsMode?: string
}

const STORAGE_KEY_PREFIX: string = 'plugin_'
const STORAGE_INDEX_KEY: string = 'plugin_index'
const STORAGE_ENABLED_PREFIX: string = 'plugin_enabled_'
const PLAY_URL_TIMEOUT: number = 4000
// v3 插件内部搜索超时 15s + 多链路回退，需留足余量，否则插件未返回就被软超时掐断
const SEARCH_SOURCE_TIMEOUT: number = 12000
const FALLBACK_SEARCH_LIMIT: number = 8

type GetSettingFn = (key: string) => Promise<string>
type SetSettingFn = (key: string, value: string) => Promise<void>

export class SourceManager {
  private static configs: Map<string, SourceConfig> = new Map()
  private static getSettingFn: GetSettingFn | null = null
  private static setSettingFn: SetSettingFn | null = null
  private static loaded: boolean = false

  static setDatabaseOps(getFn: GetSettingFn, setFn: SetSettingFn): void {
    SourceManager.getSettingFn = getFn
    SourceManager.setSettingFn = setFn
  }

  private static registerV3PluginName(name: string): void {
    const raw: string = AppStorage.get<string>('v3PluginNames') || '[]'
    try {
      const arr: string[] = JSON.parse(raw) as string[]
      if (arr.indexOf(name) < 0) {
        arr.push(name)
        AppStorage.setOrCreate('v3PluginNames', JSON.stringify(arr))
      }
    } catch (_e) {}
  }

  static isV3PluginName(name: string): boolean {
    const raw: string = AppStorage.get<string>('v3PluginNames') || '[]'
    try {
      const arr: string[] = JSON.parse(raw) as string[]
      return arr.indexOf(name) >= 0
    } catch (_e) { return false }
  }

  static async ensureLoaded(): Promise<void> {
    if (SourceManager.loaded) return
    SourceManager.loaded = true
    await SourceManager.loadAll()
  }

  private static async getSetting(key: string): Promise<string> {
    if (SourceManager.getSettingFn) return await SourceManager.getSettingFn(key)
    return await DatabaseHelper.getInstance().getSetting(key)
  }

  private static async setSetting(key: string, value: string): Promise<void> {
    if (SourceManager.setSettingFn) {
      await SourceManager.setSettingFn(key, value)
      return
    }
    await DatabaseHelper.getInstance().setSetting(key, value)
  }

  static async importFromFile(fileUri: string): Promise<string> {
    try {
      const file: fs.File = fs.openSync(fileUri, fs.OpenMode.READ_ONLY)
      const stat: fs.Stat = fs.statSync(file.fd)
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size)
      fs.readSync(file.fd, buffer)
      fs.closeSync(file)
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
      const content: string = decoder.decodeToString(new Uint8Array(buffer))
      const fileName: string = fileUri.substring(fileUri.lastIndexOf('/') + 1)
      const pluginName: string = fileName.replace(/\.(json|js)$/i, '')
      const name: string = await SourceManager.importJsConfig(content, pluginName)
      if (name.length > 0) console.info(`[SourceManager] Imported JS plugin: ${name}`)
      return name
    } catch (e) {
      console.error('[SourceManager] importFromFile failed:', e)
      return ''
    }
  }

  static async importJsConfig(jsCode: string, pluginName: string): Promise<string> {
    try {
      const sourceHash = SourceManager.hashSource(jsCode)
      const isV3: boolean = SourceManager.detectV3Plugin(jsCode)
      if (isV3) {
        try {
          const apiInfo = SourceManager.importLXApi(jsCode)
          const name: string = apiInfo.name.length > 0 ? apiInfo.name : pluginName
          const config: SourceConfig = {
            name: name,
            type: 'lx_plugin',
            jsSource: jsCode,
            jsSourceHash: sourceHash,
            jsPlatform: name,
            jsMode: 'v3'
          }
          await SourceManager.setSetting(STORAGE_KEY_PREFIX + name, JSON.stringify(config))
          let indexStr: string = await SourceManager.getSetting(STORAGE_INDEX_KEY)
          let names: string[] = []
          if (indexStr.length > 0) names = JSON.parse(indexStr) as string[]
          if (names.indexOf(name) < 0) names.push(name)
          await SourceManager.setSetting(STORAGE_INDEX_KEY, JSON.stringify(names))
          SourceManager.configs.set(name, config)
          JsPluginEngine.clearV3SourcesCache(name)
          JsPluginEngineV2.clearV3SourcesCache(name)
          SourceManager.registerV3PluginName(name)
          console.info(`[SourceManager] Imported V3 plugin (new engine): ${name}, apiId=${apiInfo.id}`)
          return name
        } catch (v3Err) {
          console.error('[SourceManager] import v3 plugin failed:', v3Err)
          return ''
        }
      }
      const jsonConfig: SourceConfig | null = SourceManager.tryParseJsonSource(jsCode, pluginName)
      if (jsonConfig) {
        jsonConfig.jsSourceHash = sourceHash
        const configJson: string = JSON.stringify(jsonConfig)
        await SourceManager.setSetting(STORAGE_KEY_PREFIX + jsonConfig.name, configJson)
        let indexStr: string = await SourceManager.getSetting(STORAGE_INDEX_KEY)
        let names: string[] = []
        if (indexStr.length > 0) names = JSON.parse(indexStr) as string[]
        let found: boolean = false
        for (let i = 0; i < names.length; i++) {
          if (names[i] === jsonConfig.name) { found = true; break }
        }
        if (!found) names.push(jsonConfig.name)
        await SourceManager.setSetting(STORAGE_INDEX_KEY, JSON.stringify(names))
        SourceManager.configs.set(jsonConfig.name, jsonConfig)
        console.info(`[SourceManager] Imported JSON source: ${jsonConfig.name}`)
        return jsonConfig.name
      }
      const config: SourceConfig | null = SourceManager.tryParseJsPlugin(jsCode, pluginName)
      if (!config) return ''
      config.jsSourceHash = sourceHash
      const previous = SourceManager.configs.get(config.name)
      const configJson: string = JSON.stringify(config)
      await SourceManager.setSetting(STORAGE_KEY_PREFIX + config.name, configJson)
      let indexStr: string = await SourceManager.getSetting(STORAGE_INDEX_KEY)
      let names: string[] = []
      if (indexStr.length > 0) names = JSON.parse(indexStr) as string[]
      let found: boolean = false
      for (let i = 0; i < names.length; i++) {
        if (names[i] === config.name) { found = true; break }
      }
      if (!found) names.push(config.name)
      await SourceManager.setSetting(STORAGE_INDEX_KEY, JSON.stringify(names))
      SourceManager.configs.set(config.name, config)
      if (!previous || previous.jsSourceHash !== config.jsSourceHash) {
        JsPluginEngine.clearV3SourcesCache(config.name)
        JsPluginEngineV2.clearV3SourcesCache(config.name)
      }
      console.info(`[SourceManager] Imported JS plugin: ${config.name}`)
      return config.name
    } catch (e) {
      console.error('[SourceManager] importJsConfig failed:', e)
      return ''
    }
  }

  static async importFromSubscriptionJson(jsonStr: string): Promise<ImportResult[]> {
    const results: ImportResult[] = []
    try {
      const parsed: Record<string, Object> = JSON.parse(jsonStr) as Record<string, Object>
      const plugins: Object | undefined = parsed['plugins']
      if (!(plugins instanceof Array)) return [{ name: '', success: false, error: '缺少 plugins 数组' }]
      const pluginList: Object[] = plugins as Object[]
      for (let i = 0; i < pluginList.length; i++) {
        const plugin: Record<string, Object> = pluginList[i] as Record<string, Object>
        const url: string = String(plugin['url'] ?? '')
        const name: string = String(plugin['name'] ?? '')
        if (url.length === 0) { results.push({ name: name || 'unknown', success: false, error: '缺少 url' }); continue }
        try {
          const httpReq = http.createHttp()
          const resp = await httpReq.request(url, { method: http.RequestMethod.GET, readTimeout: 15000, connectTimeout: 15000 })
          httpReq.destroy()
          let content: string = ''
          if (typeof resp.result === 'string') content = resp.result as string
          else if (resp.result instanceof ArrayBuffer) {
            const dec = util.TextDecoder.create('utf-8')
            content = dec.decodeToString(new Uint8Array(resp.result))
          }
          if (content.length === 0) { results.push({ name, success: false, error: '下载内容为空' }); continue }
          const importedName = await SourceManager.importJsConfig(content, name)
          results.push(importedName.length > 0 ? { name: importedName, success: true } : { name, success: false, error: '插件解析失败' })
        } catch (err) {
          results.push({ name, success: false, error: `下载失败: ${(err as Error).message}` })
        }
      }
      return results
    } catch (e) {
      return [{ name: '', success: false, error: `订阅解析失败: ${(e as Error).message}` }]
    }
  }

  static importLXApi(scriptRaw: string): LXUserApiInfo {
    return lxSourceManager.importApi(scriptRaw)
  }
  static getLXApiList(): LXUserApiInfo[] { return lxSourceManager.getApiList() }
  static removeLXApi(apiId: string): void { lxSourceManager.removeApi(apiId) }

  static async loadAll(): Promise<void> {
    const indexStr: string = await SourceManager.getSetting(STORAGE_INDEX_KEY)
    if (indexStr.length === 0) return
    const names: string[] = JSON.parse(indexStr) as string[]
    const v3Names: string[] = []
    for (let i = 0; i < names.length; i++) {
      const jsonStr = await SourceManager.getSetting(STORAGE_KEY_PREFIX + names[i])
      if (jsonStr.length > 0) {
        try {
          const cfg: SourceConfig = JSON.parse(jsonStr) as SourceConfig
          SourceManager.configs.set(names[i], cfg)
          if (cfg.jsMode === 'v3') v3Names.push(names[i])
        } catch (_e) {}
      }
    }
    if (v3Names.length > 0) {
      AppStorage.setOrCreate('v3PluginNames', JSON.stringify(v3Names))
    }
    console.info(`[SourceManager] Loaded ${SourceManager.configs.size} JS plugins`)
  }

  static async removeSource(name: string): Promise<void> {
    SourceManager.configs.delete(name)
    JsPluginEngine.clearV3SourcesCache(name)
    JsPluginEngineV2.clearV3SourcesCache(name)
    MFEngine.getInstance().forget(name)
    const v3Raw: string = AppStorage.get<string>('v3PluginNames') || '[]'
    try {
      const v3Arr: string[] = JSON.parse(v3Raw) as string[]
      const filtered: string[] = v3Arr.filter((n: string) => n !== name)
      AppStorage.setOrCreate('v3PluginNames', JSON.stringify(filtered))
    } catch (_e) {}
    await SourceManager.setSetting(STORAGE_KEY_PREFIX + name, '')
    const indexStr = await SourceManager.getSetting(STORAGE_INDEX_KEY)
    if (indexStr.length > 0) {
      const allNames = JSON.parse(indexStr) as string[]
      await SourceManager.setSetting(STORAGE_INDEX_KEY, JSON.stringify(allNames.filter((n: string) => n !== name)))
    }
  }

  static async autoDetectAndImport(content: string, fallbackName: string = 'custom'): Promise<string> {
    return await SourceManager.importJsConfig(content, fallbackName)
  }

  /**
   * 导入 MusicFree 插件（双协议支持）：
   * 先在 MF 沙箱挂载验证 → 取插件声明的 platform 作为音源名 → 以 jsMode='mf' 注册。
   * 已存在相同源码哈希时跳过（幂等）；源码更新时覆盖重挂载。
   * 成功返回音源名，失败返回空串（错误见 MFEngine.lastError）。
   */
  static async importMusicFreePlugin(jsCode: string, fallbackName: string): Promise<string> {
    try {
      if (!jsCode || jsCode.length === 0) {
        MFEngine.lastError = '插件源码为空'
        return ''
      }
      const sourceHash: string = SourceManager.hashSource(jsCode)
      // 哈希去重：已安装相同源码 → 确保沙箱已挂载后直接返回
      const existingNames: string[] = SourceManager.getSourceNames()
      for (let i = 0; i < existingNames.length; i++) {
        const existing: SourceConfig | undefined = SourceManager.configs.get(existingNames[i])
        if (existing && existing.jsMode === 'mf' && existing.jsSourceHash === sourceHash) {
          if (!MFEngine.getInstance().isMounted(existing.name) && existing.jsSource) {
            await MFEngine.getInstance().mountPlugin(existing.name, existing.jsSource)
          }
          return existing.name
        }
      }
      // 沙箱挂载验证（临时名 → 挂载后按 platform 重命名）
      const mountKey: string = fallbackName.length > 0 ? fallbackName : 'mf_plugin'
      const info = await MFEngine.getInstance().mountPlugin(mountKey, jsCode)
      const name: string = info.platform.length > 0 ? info.platform : mountKey
      if (name !== mountKey) {
        MFEngine.getInstance().rename(mountKey, name)
      }
      const config: SourceConfig = {
        name: name,
        type: 'lx_plugin',
        jsSource: jsCode,
        jsSourceHash: sourceHash,
        jsPlatform: name,
        jsVersion: info.version,
        jsMode: 'mf',
      }
      await SourceManager.setSetting(STORAGE_KEY_PREFIX + name, JSON.stringify(config))
      let indexStr: string = await SourceManager.getSetting(STORAGE_INDEX_KEY)
      let names: string[] = []
      if (indexStr.length > 0) names = JSON.parse(indexStr) as string[]
      if (names.indexOf(name) < 0) names.push(name)
      await SourceManager.setSetting(STORAGE_INDEX_KEY, JSON.stringify(names))
      SourceManager.configs.set(name, config)
      console.info(`[SourceManager] Imported MusicFree plugin: ${name} v${info.version}`)
      return name
    } catch (e) {
      // 把真实失败原因暴露给自检日志（挂载失败/依赖缺失等）
      const message: string = e instanceof Error ? e.message : String(e)
      MFEngine.lastError = message
      console.error(`[SourceManager] importMusicFreePlugin failed: ${message}`)
      return ''
    }
  }

  static async getEnabledSourceNames(): Promise<string[]> {
    const allNames: string[] = SourceManager.getSourceNames()
    // 并行读取启用状态，避免逐个 await getSetting 造成串行 I/O
    const flags: Promise<boolean>[] = []
    for (let i = 0; i < allNames.length; i++) {
      flags.push(SourceManager.isSourceEnabled(allNames[i]))
    }
    const settled: boolean[] = await Promise.all(flags)
    const enabled: string[] = []
    for (let i = 0; i < allNames.length; i++) {
      if (settled[i]) {
        enabled.push(allNames[i])
      }
    }
    return enabled
  }

  static getSourceNames(): string[] {
    const names: string[] = []
    SourceManager.configs.forEach((_: SourceConfig, key: string) => names.push(key))
    return names
  }

  static async isSourceEnabled(name: string): Promise<boolean> {
    return (await SourceManager.getSetting(STORAGE_ENABLED_PREFIX + name)) !== 'false'
  }

  static async setSourceEnabled(name: string, enabled: boolean): Promise<void> {
    await SourceManager.setSetting(STORAGE_ENABLED_PREFIX + name, enabled ? 'true' : 'false')
  }

  static getConfig(name: string): SourceConfig | undefined {
    return SourceManager.configs.get(name)
  }

  private static hashSource(source: string): string {
    let hash = 2166136261
    for (let i = 0; i < source.length; i++) {
      hash ^= source.charCodeAt(i)
      hash = Math.imul(hash, 16777619)
    }
    return (hash >>> 0).toString(16)
  }

  /** 引擎 init 上报的源列表（v3 插件声明的自定义源，如全豆要的 qsvip） */
  static declaredEngineSources(): string[] {
    try {
      const json: string = AppStorage.get<string>('lxEngineSources') || ''
      if (json.length === 0) return []
      const srcs: Record<string, Object> = JSON.parse(json) as Record<string, Object>
      return Object.keys(srcs)
    } catch (_e) {
      return []
    }
  }

  /**
   * 插件搜索结果可能出现的 source 标识集合，供 UI 防御性过滤。
   * v1/MusicFree 插件结果带 custom_ 前缀；v3 插件结果是引擎声明的源（如 qsvip）。
   */
  static getSourceAliases(sourceName: string): string[] {
    const config: SourceConfig | undefined = SourceManager.configs.get(sourceName)
    if (!config) return [sourceName]
    if (config.jsMode === 'v3') {
      const declared: string[] = SourceManager.declaredEngineSources()
      return declared.length > 0 ? declared : [sourceName]
    }
    return ['custom_' + sourceName, sourceName]
  }

  /** 校验 url 是否可直接播放（http(s) 且可 Range 探通），供外部在已取得链接时避免重复取链 */
  static async checkUrlPlayable(url: string): Promise<boolean> {
    return await SourceManager.isPlayableUrl(url)
  }

  /** 从插件名/源名推断平台码（kw/kg/tx/wy/mg），供 v3 聚合插件按平台取链 */
  static inferPlatform(source: string): string {
    let s = source
    if (s.startsWith('custom_')) {
      s = s.substring(7)
    }
    const exact: Record<string, string> = {
      'kw': 'kw', 'kuwo': 'kw', '酷我': 'kw',
      'kg': 'kg', 'kugou': 'kg', '酷狗': 'kg',
      'tx': 'tx', 'qq': 'tx', 'QQ': 'tx',
      'wy': 'wy', 'netease': 'wy', '网易': 'wy', '163': 'wy',
      'mg': 'mg', 'migu': 'mg', '咪咕': 'mg',
    }
    const hit: string | undefined = exact[s]
    if (hit !== undefined) {
      return hit
    }
    if (s.indexOf('酷狗') >= 0 || s.indexOf('kugou') >= 0) return 'kg'
    if (s.indexOf('酷我') >= 0 || s.indexOf('kuwo') >= 0) return 'kw'
    if (s.indexOf('腾讯') >= 0 || s.indexOf('qq') >= 0) return 'tx'
    if (s.indexOf('网易') >= 0 || s.indexOf('netease') >= 0 || s.indexOf('163') >= 0) return 'wy'
    if (s.indexOf('咪咕') >= 0 || s.indexOf('migu') >= 0) return 'mg'
    return s
  }

  static async searchAll(keyword: string): Promise<SongInfo[]> {
    const names = SourceManager.getSourceNames()
    // 并行判断各音源是否启用，避免逐个 await getSetting 拖慢搜索
    const flags: Promise<boolean>[] = []
    for (let i = 0; i < names.length; i++) {
      flags.push(SourceManager.isSourceEnabled(names[i]))
    }
    const enabledFlags: boolean[] = await Promise.all(flags)
    const tasks: Promise<SongInfo[]>[] = []
    for (let i = 0; i < names.length; i++) {
      if (!enabledFlags[i]) continue
      const sourceName = names[i]
      tasks.push(SourceManager.withTimeout(SourceManager.search(sourceName, keyword), SEARCH_SOURCE_TIMEOUT, sourceName)
        .catch((e: Error) => {
          console.warn(`[SourceManager] search skip source=${sourceName}: ${e.message}`)
          return [] as SongInfo[]
        }))
    }
    const settled: SongInfo[][] = await Promise.all(tasks)
    const allResults: SongInfo[] = []
    const seenKeys = new Set<string>()
    for (let i = 0; i < settled.length; i++) {
      const results = settled[i]
      for (let j = 0; j < results.length; j++) {
        const key = results[j].source + '|' + results[j].songId
        if (seenKeys.has(key)) continue
        seenKeys.add(key)
        allResults.push(results[j])
      }
    }
    return allResults
  }

  static async search(sourceName: string, keyword: string): Promise<SongInfo[]> {
    const config = SourceManager.configs.get(sourceName)
    if (!config) return []
    if (config.jsMode === 'v3') {
      const configForEngine: SourceConfig = {
        name: config.name,
        type: config.type,
        jsSource: config.jsSource,
        jsSourceHash: config.jsSourceHash,
        jsPlatform: config.jsPlatform,
        jsVersion: config.jsVersion,
        jsMode: 'v3'
      }
      const results: SongInfo[] = await JsPluginEngineV2.search(configForEngine, keyword)
      if (results.length === 0 && JsPluginEngineV2.lastError.length > 0) {
        SourceManager.lastSearchError = JsPluginEngineV2.lastError
      }
      if (results.length > 0) return results
      return await SourceManager.builtInPlatformSearch(config, keyword)
    }
    if (config.jsMode === 'mf' && config.jsSource && config.jsSource.length > 0) {
      const results: SongInfo[] = await MFEngine.getInstance().search(config.name, config.jsSource, keyword)
      if (results.length === 0 && MFEngine.lastError.length > 0) {
        SourceManager.lastSearchError = MFEngine.lastError
      }
      return results
    }
    if (config.type === 'lx_plugin' && config.jsSource && config.jsSource.length > 0) {
      return await JsPluginEngine.search(config, keyword)
    }
    if (config.type === 'json_source') {
      return await SourceManager.jsonSourceSearch(config, keyword)
    }
    return []
  }

  /** 最近一次搜索失败原因（供上层展示） */
  static lastSearchError: string = ''

  /**
   * 解析 v3 插件用于搜索的源：读取引擎 init 上报的 sources（lxEngineSources），
   * 优先取声明了 musicSearch 的源（含聚合插件的自定义源），否则回退平台码。
   * 注意：调用前必须已通过 withLxPlugin 切到目标插件，否则读到的是别的插件的声明。
   */
  private static resolveV3SearchSource(sourceName: string): string {
    const declared = SourceManager.findDeclaredSearchSource()
    if (declared.length > 0) return declared
    // 插件名本身就是平台码（kw/kg/tx/wy/mg）的极简插件：直接用平台码
    const platform = SourceManager.inferPlatform(sourceName)
    if (platform === 'kw' || platform === 'kg' || platform === 'tx' || platform === 'wy' || platform === 'mg') {
      return platform
    }
    // 引擎未上报任何可搜索源，且插件名不是平台码：
    // 不能把插件名当源 id 发出去（插件的请求处理函数不认识该 source，会返回空），
    // 交由上层报"未声明支持搜索的源"。
    return ''
  }

  /** 从引擎上报的 sources 中找到第一个支持 musicSearch 的源 */
  private static findDeclaredSearchSource(): string {
    try {
      const json: string = AppStorage.get<string>('lxEngineSources') || ''
      if (json.length === 0) return ''
      const srcs: Record<string, Object> = JSON.parse(json) as Record<string, Object>
      const keys: string[] = Object.keys(srcs)
      for (let i = 0; i < keys.length; i++) {
        const info: Record<string, Object> = srcs[keys[i]] as Record<string, Object>
        const actions: Object | undefined = info['actions']
        if (actions instanceof Array) {
          const arr: string[] = actions as string[]
          if (arr.indexOf('musicSearch') >= 0) return keys[i]
        }
      }
    } catch (_e) {
      // 解析失败时回退到插件名
    }
    return ''
  }

  private static async withTimeout<T>(task: Promise<T>, timeoutMs: number, label: string): Promise<T> {
    let timer: number | undefined = undefined
    const timeout = new Promise<T>((_resolve, reject) => {
      timer = setTimeout(() => {
        reject(new Error(`source timeout: ${label}`))
      }, timeoutMs)
    })
    try {
      return await Promise.race([task, timeout])
    } finally {
      if (timer !== undefined) {
        clearTimeout(timer)
      }
    }
  }

  /** v3 引擎切换串行锁：同一时刻引擎只托管一个 v3 插件，
   *  多插件并发搜索时必须排队切换，否则后切到的插件会覆盖前一个的运行环境 */
  private static lxLock: Promise<void> = Promise.resolve()

  /** 等待 LX 引擎就绪（轮询 lxEngineReady，供切插件后确认新环境已初始化） */
  private static async waitForLxEngine(timeoutMs: number): Promise<boolean> {
    const start: number = Date.now()
    while (Date.now() - start < timeoutMs) {
      if (AppStorage.get<boolean>('lxEngineReady') || false) {
        return true
      }
      await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 200) })
    }
    return AppStorage.get<boolean>('lxEngineReady') || false
  }

  /** 确保引擎当前加载的是指定 v3 插件；未加载则切换并等待就绪 */
  private static async ensureLxPlugin(sourceName: string): Promise<boolean> {
    const active: string = AppStorage.get<string>('lxActiveSource') || ''
    if (active === sourceName) {
      if (lxEngineIsReady) return true
      return await SourceManager.waitForLxEngine(10000)
    }
    AppStorage.setOrCreate('lxActiveSource', sourceName)
    // onActiveSourceChanged 会先把 lxEngineReady 置 false 再重载插件，这里等到重新就绪
    return await SourceManager.waitForLxEngine(12000)
  }

  /** 串行执行"切到目标插件 → 跑任务"，保证并发调用不互相覆盖引擎环境。
   *  实现：把本次任务挂到上一把锁之后，并把"本任务结束"作为新锁，
   *  同步完成读旧锁/挂任务/写新锁，后到的调用自然排队。 */
  private static async withLxPlugin<T>(sourceName: string, task: () => Promise<T>): Promise<T> {
    const prev: Promise<void> = SourceManager.lxLock
    const next: Promise<T> = prev.then(async (): Promise<T> => {
      await SourceManager.ensureLxPlugin(sourceName)
      return await task()
    })
    // 新锁在本任务结束后（无论成败）才 resolve，失败也吞掉以免锁卡在 rejected
    SourceManager.lxLock = next.then((): void => {}, (): void => {})
    return await next
  }

  static async getPlayUrl(sourceName: string, _songId: string, song?: SongInfo): Promise<string> {
    const config = SourceManager.configs.get(sourceName)
    if (!config || !((config.type === 'lx_plugin' && config.jsSource && config.jsSource.length > 0) ||
      config.type === 'json_source')) return ''
    const platform = SourceManager.inferPlatform(song && song.source ? song.source : sourceName)
    if (config.jsMode === 'v3') {
      if (!song) return ''
      const configForEngine: SourceConfig = {
        name: config.name, type: config.type, jsSource: config.jsSource,
        jsSourceHash: config.jsSourceHash, jsPlatform: config.jsPlatform,
        jsVersion: config.jsVersion, jsMode: 'v3'
      }
      const url: string = await JsPluginEngineV2.getPlayUrl(configForEngine, song)
      if (url.length > 0) return url
      return ''
    }
    if (config.jsMode === 'mf') {
      if (!song || !config.jsSource) return ''
      return await MFEngine.getInstance().getPlayUrl(config.name, config.jsSource, song)
    }
    if (config.type === 'json_source') {
      if (!song) return ''
      return await SourceManager.jsonSourceGetPlayUrl(config, song)
    }
    if (lxEngineIsReady && song) {
      try {
        const url = await getLXMusicUrl(platform, song.songId, '128k', song.songName, song.artist)
        if (url.length > 0) return url
      } catch (_e) {}
    }
    return await JsPluginEngine.getPlayUrl(config, song)
  }

  static async getPlayableUrl(song: SongInfo): Promise<string> {
    const preferredSource = song.source && song.source.length > 0 ? song.source : ''
    if (preferredSource.length > 0 && await SourceManager.isSourceEnabled(preferredSource)) {
      const preferredUrl = await SourceManager.getValidPlayUrl(preferredSource, song)
      if (preferredUrl.length > 0) return preferredUrl
    }

    const names = SourceManager.getSourceNames()
    for (let i = 0; i < names.length; i++) {
      if (names[i] === preferredSource) continue
      if (!(await SourceManager.isSourceEnabled(names[i]))) continue
      const directUrl = await SourceManager.getValidPlayUrl(names[i], song)
      if (directUrl.length > 0) return directUrl
    }

    return await SourceManager.searchAndGetFallbackUrl(song)
  }

  static async getPlayUrlFromAny(songId: string, songName: string, artist: string, song?: SongInfo): Promise<string> {
    if (song) {
      const playableUrl = await SourceManager.getPlayableUrl(song)
      if (playableUrl.length > 0) return playableUrl
    }

    const seedSong: SongInfo = {
      songId: songId,
      songName: songName,
      artist: artist,
      source: ''
    } as SongInfo
    const fallbackUrl = await SourceManager.searchAndGetFallbackUrl(seedSong)
    if (fallbackUrl.length > 0) return fallbackUrl

    const names = SourceManager.getSourceNames()
    for (let i = 0; i < names.length; i++) {
      if (!(await SourceManager.isSourceEnabled(names[i]))) continue
      const url = await SourceManager.getValidPlayUrl(names[i], seedSong)
      if (url.length > 0) return url
    }
    return ''
  }

  private static async getValidPlayUrl(sourceName: string, song: SongInfo): Promise<string> {
    const config: SourceConfig | undefined = SourceManager.getConfig(sourceName)
    if (!config) {
      // 非插件源（如 v3 引擎声明的自定义源 qsvip）：无法按插件名取链，不标记可用性
      return ''
    }
    try {
      const url = await SourceManager.getPlayUrl(sourceName, song.songId, song)
      if (await SourceManager.isPlayableUrl(url)) {
        SourceStatus.markPlayable(sourceName)
        return url
      }
      // v3 聚合插件按歌按平台取链，单曲失败属常态，不因此标记整个插件不可用
      if (config.jsMode !== 'v3') {
        SourceStatus.markUnplayable(sourceName)
      }
    } catch (_e) {
      if (config.jsMode !== 'v3') {
        SourceStatus.markUnplayable(sourceName)
      }
    }
    return ''
  }

  private static async searchAndGetFallbackUrl(song: SongInfo): Promise<string> {
    const keyword = SourceManager.buildFallbackKeyword(song.songName, song.artist)
    if (keyword.length === 0) return ''

    const names = SourceManager.getSourceNames()
    for (let i = 0; i < names.length; i++) {
      if (names[i] === song.source) continue
      if (!(await SourceManager.isSourceEnabled(names[i]))) continue
      let results: SongInfo[] = []
      try {
        results = await SourceManager.search(names[i], keyword)
      } catch (_e) {
        results = []
      }
      const limit = Math.min(results.length, FALLBACK_SEARCH_LIMIT)
      for (let j = 0; j < limit; j++) {
        const candidate = results[j]
        if (!SourceManager.isLikelySameSong(song, candidate)) continue
        const candidateUrl = await SourceManager.getValidPlayUrl(names[i], candidate)
        if (candidateUrl.length > 0) {
          SourceStatus.markPlayable(names[i])
          return candidateUrl
        }
      }
    }
    return ''
  }

  private static buildFallbackKeyword(songName: string, artist: string): string {
    const cleanName = SourceManager.normalizeSearchText(songName)
    const cleanArtist = SourceManager.normalizeSearchText(artist)
    if (cleanName.length === 0) return ''
    if (cleanArtist.length === 0 || cleanName.indexOf(cleanArtist) >= 0) return cleanName
    return cleanName + ' ' + cleanArtist
  }

  private static isLikelySameSong(target: SongInfo, candidate: SongInfo): boolean {
    const targetName = SourceManager.normalizeTitle(target.songName)
    const candidateName = SourceManager.normalizeTitle(candidate.songName)
    if (targetName.length === 0 || candidateName.length === 0) return false
    if (targetName !== candidateName && targetName.indexOf(candidateName) < 0 && candidateName.indexOf(targetName) < 0) {
      return false
    }

    const targetArtist = SourceManager.normalizeSearchText(target.artist)
    const candidateArtist = SourceManager.normalizeSearchText(candidate.artist)
    if (targetArtist.length === 0 || candidateArtist.length === 0) return true
    return targetArtist.indexOf(candidateArtist) >= 0 || candidateArtist.indexOf(targetArtist) >= 0
  }

  private static normalizeTitle(value: string): string {
    return SourceManager.normalizeSearchText(value)
      .replace(/\([^)]*\)/g, '')
      .replace(/（[^）]*）/g, '')
      .replace(/\[[^\]]*\]/g, '')
      .replace(/【[^】]*】/g, '')
      .replace(/\s+/g, '')
  }

  private static normalizeSearchText(value: string): string {
    return value
      .toLowerCase()
      .replace(/\s+/g, ' ')
      .replace(/^\s+|\s+$/g, '')
  }

  private static async isPlayableUrl(url: string): Promise<boolean> {
    if (url.length === 0) return false
    if (url.indexOf('http://') !== 0 && url.indexOf('https://') !== 0) return false

    const req = http.createHttp()
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Range': 'bytes=0-1',
          'User-Agent': 'Mozilla/5.0',
          'Accept': '*/*'
        },
        readTimeout: PLAY_URL_TIMEOUT,
        connectTimeout: PLAY_URL_TIMEOUT
      })
      const code = resp.responseCode
      return code >= 200 && code < 400
    } catch (_e) {
      return false
    } finally {
      req.destroy()
    }
  }

  static async getLyrics(sourceName: string, _songId: string, _songName?: string, _artist?: string, song?: SongInfo): Promise<string> {
    const config = SourceManager.configs.get(sourceName)
    if (!config || !((config.type === 'lx_plugin' && config.jsSource && config.jsSource.length > 0) ||
      config.type === 'json_source')) return ''
    if (config.jsMode === 'v3') {
      if (!song) return ''
      const configForEngine: SourceConfig = {
        name: config.name, type: config.type, jsSource: config.jsSource,
        jsSourceHash: config.jsSourceHash, jsPlatform: config.jsPlatform,
        jsVersion: config.jsVersion, jsMode: 'v3'
      }
      return await JsPluginEngineV2.getLyric(configForEngine, song)
    }
    if (config.jsMode === 'mf') {
      if (!song || !config.jsSource) return ''
      return await MFEngine.getInstance().getLyric(config.name, config.jsSource, song)
    }
    if (config.type === 'json_source') {
      if (!song) return ''
      return await SourceManager.jsonSourceGetLyric(config, song)
    }
    if (lxEngineIsReady && song) {
      try {
        const platform = SourceManager.inferPlatform(song.source ? song.source : sourceName)
        const lrc = await getLXLyric(platform, song.songId, song.songName, song.artist)
        if (lrc.length > 0) return lrc
      } catch (_e) {}
    }
    return await JsPluginEngine.getLyric(config, song)
  }

  static async getPic(sourceName: string, songId: string, songName?: string, artist?: string): Promise<string> {
    if (lxEngineIsReady) {
      try { return await getLXPic(sourceName, songId, songName, artist) } catch (_e) {}
    }
    return ''
  }

  static tryParseJsPlugin(jsCode: string, pluginName: string): SourceConfig | null {
    try {
      return SourceManager.parseFullJsPlugin(jsCode, pluginName)
    } catch (e) {
      console.error(`[SourceManager] tryParseJsPlugin failed for ${pluginName}:`, e)
      return null
    }
  }

  private static parseFullJsPlugin(jsCode: string, fallbackName: string): SourceConfig | null {
    const exportMatch = jsCode.match(/module\s*\.\s*exports\s*=\s*\{/)
    if (exportMatch) {
      const hasSearch = /(?:^|\n|\s|;|})\s*(?:async\s+)?function\s+search\b/.test(jsCode) ||
        /search\s*:\s*(?:async\s+)?function/.test(jsCode) || /search\s*:\s*\(/.test(jsCode) || /\bsearch\s*,/.test(jsCode) ||
        /\bsearch\s*\(/.test(jsCode)
      if (hasSearch) {
        let platform = ''
        const pm = jsCode.match(/platform\s*:\s*['"]([^'"]+)['"]/)
        if (pm) platform = pm[1]
        let version = ''
        const vm = jsCode.match(/version\s*:\s*['"](\d[^'"]*)['"]/)
        if (vm) version = vm[1]
        const name = platform.length > 0 ? platform : fallbackName
        return { name, type: 'lx_plugin', jsSource: jsCode, jsPlatform: name, jsVersion: version, jsMode: 'v1' }
      }
      return null
    }
    const isV3 = SourceManager.detectV3Plugin(jsCode)
    if (!isV3) return null
    let v3Name = ''
    const nm = jsCode.match(/@name\s+([^\n\r]+)/)
    if (nm) {
      v3Name = nm[1].trim()
      const bi = v3Name.search(/[\[（(]/)
      if (bi > 0) v3Name = v3Name.substring(0, bi).trim()
    }
    if (v3Name.length === 0) v3Name = fallbackName
    let v3Version = ''
    const vvm = jsCode.match(/@version\s+([^\n\r]+)/)
    if (vvm) v3Version = vvm[1].trim()
    console.info(`[SourceManager] Parsed v3 plugin: ${v3Name} v${v3Version}`)
    return { name: v3Name, type: 'lx_plugin', jsSource: jsCode, jsPlatform: v3Name, jsVersion: v3Version, jsMode: 'v3' }
  }

  private static detectV3Plugin(jsCode: string): boolean {
    if (new RegExp('globalThis\\s*\\.\\s*lx').test(jsCode)) return true
    if (new RegExp('EVENT_NAMES').test(jsCode)) return true
    if (new RegExp('\\blx\\.request\\b').test(jsCode)) return true
    if (new RegExp('EVENT_NAMES\\s*\\.\\s*inited').test(jsCode)) return true
    if (new RegExp('globalThis\\s*\\[\\s*[\'"]').test(jsCode)) {
      const hexLx = new RegExp('\\\\x6c\\\\x78')
      const uniLx = new RegExp('\\\\u006c\\\\u0078')
      if (hexLx.test(jsCode) || uniLx.test(jsCode)) return true
      const bracketMatch = jsCode.match(new RegExp('globalThis\\s*\\[\\s*[\'"]([^\'"]+)[\'"]\\s*\\]'))
      if (bracketMatch && bracketMatch[1] === 'lx') return true
    }
    if (new RegExp('@name\\s+').test(jsCode) && !new RegExp('module\\s*\\.\\s*exports').test(jsCode)) {
      if (new RegExp('\\blx\\s*\\.\\s*(request|on|send|env)\\b').test(jsCode)) return true
      if (new RegExp('\\\\x6c\\\\x78').test(jsCode) || new RegExp('\\\\u006c\\\\u0078').test(jsCode)) return true
    }
    if (new RegExp('jsjiami\\.com').test(jsCode) && new RegExp('@name\\s+').test(jsCode)) {
      if (!new RegExp('module\\s*\\.\\s*exports').test(jsCode)) return true
    }
    return false
  }

  static tryParseJsonSource(content: string, fallbackName: string): SourceConfig | null {
    const trimmed: string = content.replace(/^\s+/, '').replace(/\s+$/, '')
    if (trimmed.length < 2 || trimmed.charAt(0) !== '{') return null
    try {
      const parsed: Record<string, Object> = JSON.parse(trimmed) as Record<string, Object>
      const nameVal: Object | undefined = parsed['name']
      if (nameVal === undefined || nameVal === null) return null
      const name: string = String(nameVal)
      if (name.length === 0) return null
      const searchVal: Object | undefined = parsed['search']
      if (searchVal === undefined || searchVal === null) return null
      let version: string = ''
      const verVal: Object | undefined = parsed['version']
      if (verVal !== undefined && verVal !== null) version = String(verVal)
      return {
        name: name,
        type: 'json_source',
        jsSource: trimmed,
        jsSourceHash: '',
        jsPlatform: name,
        jsVersion: version,
        jsMode: 'json'
      }
    } catch (_e) {
      return null
    }
  }

  private static jsonSourceSearch(config: SourceConfig, keyword: string): Promise<SongInfo[]> {
    return new Promise<SongInfo[]>((resolve: (songs: SongInfo[]) => void) => {
      try {
        const parsed: Record<string, Object> = JSON.parse(config.jsSource ?? '') as Record<string, Object>
        const searchConf: Record<string, Object> = parsed['search'] as Record<string, Object>
        const url: string = String(searchConf['url'] ?? '')
        if (url.length === 0) { resolve([]); return }
        const method: string = String(searchConf['method'] ?? 'GET')
        const headers: Record<string, Object> = (searchConf['headers'] ?? new Object()) as Record<string, Object>
        const params: Record<string, Object> = (searchConf['params'] ?? new Object()) as Record<string, Object>
        const respConf: Record<string, Object> = (searchConf['response'] ?? new Object()) as Record<string, Object>
        let finalUrl: string = url
        const queryParts: string[] = []
        const paramKeys: string[] = Object.keys(params)
        for (let i = 0; i < paramKeys.length; i++) {
          const val: string = String(params[paramKeys[i]])
          const replaced: string = SourceManager.replacePlaceholders(val, keyword, '', '')
          queryParts.push(encodeURIComponent(paramKeys[i]) + '=' + encodeURIComponent(replaced))
        }
        if (method === 'GET' && queryParts.length > 0) {
          finalUrl = url + (url.indexOf('?') >= 0 ? '&' : '?') + queryParts.join('&')
        }
        const httpRequest = http.createHttp()
        const reqHeaders: Record<string, string> = {}
        const hKeys: string[] = Object.keys(headers)
        for (let i = 0; i < hKeys.length; i++) {
          reqHeaders[hKeys[i]] = String(headers[hKeys[i]])
        }
        reqHeaders['User-Agent'] = reqHeaders['User-Agent'] ?? 'Mozilla/5.0'
        const options: http.HttpRequestOptions = {
          method: method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
          header: reqHeaders,
          readTimeout: 15000,
          connectTimeout: 10000,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
        }
        if (method === 'POST' && queryParts.length > 0) {
          options.extraData = queryParts.join('&')
        }
        httpRequest.request(finalUrl, options).then((response: http.HttpResponse) => {
          httpRequest.destroy()
          let body: string = ''
          const result: Object | ArrayBuffer | string = response.result
          if (typeof result === 'string') {
            body = result as string
          } else if (result instanceof ArrayBuffer) {
            const dec: util.TextDecoder = util.TextDecoder.create('utf-8')
            body = dec.decodeToString(new Uint8Array(result))
          }
          if (body.length === 0) { resolve([]); return }
          const songs: SongInfo[] = SourceManager.parseJsonSearchResponse(body, respConf, config.name)
          resolve(songs)
        }).catch((_err: Object) => {
          httpRequest.destroy()
          resolve([])
        })
      } catch (_e) {
        resolve([])
      }
    })
  }

  private static replacePlaceholders(template: string, keyword: string, songId: string, songName: string): string {
    return template
      .replace(new RegExp('\\{keyword\\}', 'g'), keyword)
      .replace(new RegExp('\\{songId\\}', 'g'), songId)
      .replace(new RegExp('\\{songName\\}', 'g'), songName)
  }

  private static parseJsonSearchResponse(body: string, respConf: Record<string, Object>, platform: string): SongInfo[] {
    try {
      const root: Record<string, Object> = JSON.parse(body) as Record<string, Object>
      const listPath: string = String(respConf['listPath'] ?? '')
      if (listPath.length === 0) return []
      const list: Object[] | null = SourceManager.resolveJsonPath(root, listPath)
      if (list === null) return []
      const songs: SongInfo[] = []
      const limit: number = Math.min(list.length, 50)
      for (let i = 0; i < limit; i++) {
        const item: Record<string, Object> = list[i] as Record<string, Object>
        const songIdPath: string = String(respConf['songId'] ?? 'id')
        const songNamePath: string = String(respConf['songName'] ?? 'name')
        const artistPath: string = String(respConf['artist'] ?? 'artist')
        const albumPath: string = String(respConf['album'] ?? 'album')
        const coverUrlPath: string = String(respConf['coverUrl'] ?? '')
        const durationPath: string = String(respConf['duration'] ?? '')
        const id: string = SourceManager.resolveJsonPathString(item, songIdPath)
        const name: string = SourceManager.resolveJsonPathString(item, songNamePath)
        const artist: string = SourceManager.resolveJsonPathString(item, artistPath)
        if (id.length === 0 || name.length === 0) continue
        const album: string = SourceManager.resolveJsonPathString(item, albumPath)
        let cover: string = SourceManager.resolveJsonPathString(item, coverUrlPath)
        const coverPrefix: string = String(respConf['coverPrefix'] ?? '')
        const coverSuffix: string = String(respConf['coverSuffix'] ?? '')
        if (cover.length > 0 && coverPrefix.length > 0) cover = coverPrefix + cover + coverSuffix
        let durNum: number = 0
        if (durationPath.length > 0) {
          const durVal: string = SourceManager.resolveJsonPathString(item, durationPath)
          durNum = Number.parseInt(durVal) || 0
          if (durNum > 3600) durNum = Math.floor(durNum / 1000)
        }
        const durText: string = durNum > 0 ? `${Math.floor(durNum / 60)}:${(durNum % 60).toString().padStart(2, '0')}` : ''
        const song: SongInfo = {
          songId: id,
          songName: name,
          artist: artist,
          album: album,
          coverUrl: cover,
          source: 'custom_' + platform,
          playUrl: '',
          quality: durText.length > 0 ? '128kbps/' + durText : '128kbps',
          rawData: JSON.stringify(item),
        }
        songs.push(song)
      }
      return songs
    } catch (_e) {
      return []
    }
  }

  private static resolveJsonPath(root: Record<string, Object>, path: string): Object[] | null {
    const parts: string[] = path.split('.')
    let current: Object = root
    for (let i = 0; i < parts.length; i++) {
      if (current instanceof Array) {
        const idx: number = Number.parseInt(parts[i])
        if (isNaN(idx) || idx < 0 || idx >= (current as Object[]).length) return null
        current = (current as Object[])[idx]
      } else {
        const rec: Record<string, Object> = current as Record<string, Object>
        const val: Object | undefined = rec[parts[i]]
        if (val === undefined || val === null) return null
        current = val
      }
    }
    if (current instanceof Array) return current as Object[]
    return null
  }

  private static resolveJsonPathString(item: Record<string, Object>, path: string): string {
    if (path.length === 0) return ''
    const parts: string[] = path.split('.')
    let current: Object = item
    for (let i = 0; i < parts.length; i++) {
      if (current instanceof Array) {
        const idx: number = Number.parseInt(parts[i])
        if (isNaN(idx) || idx < 0 || idx >= (current as Object[]).length) return ''
        current = (current as Object[])[idx]
      } else {
        const rec: Record<string, Object> = current as Record<string, Object>
        const val: Object | undefined = rec[parts[i]]
        if (val === undefined || val === null) return ''
        current = val
      }
    }
    return String(current)
  }

  private static jsonSourceGetPlayUrl(config: SourceConfig, song: SongInfo): Promise<string> {
    return new Promise<string>((resolve: (url: string) => void) => {
      try {
        const parsed: Record<string, Object> = JSON.parse(config.jsSource ?? '') as Record<string, Object>
        const playConf: Record<string, Object> | undefined = parsed['play'] as Record<string, Object> | undefined
        if (playConf === undefined || playConf === null) { resolve(''); return }
        const fallbacks: Object | undefined = parsed['playFallback']
        const attempts: Record<string, Object>[] = [playConf]
        if (fallbacks instanceof Array) {
          const fbArr: Object[] = fallbacks as Object[]
          for (let i = 0; i < fbArr.length; i++) {
            attempts.push(fbArr[i] as Record<string, Object>)
          }
        }
        SourceManager.tryJsonPlayAttempts(attempts, song, 0, resolve)
      } catch (_e) {
        resolve('')
      }
    })
  }

  private static tryJsonPlayAttempts(attempts: Record<string, Object>[], song: SongInfo, index: number, resolve: (url: string) => void): void {
    if (index >= attempts.length) { resolve(''); return }
    const playConf: Record<string, Object> = attempts[index]
    SourceManager.doJsonPlayRequest(playConf, song).then((url: string) => {
      if (url.length > 0) { resolve(url); return }
      SourceManager.tryJsonPlayAttempts(attempts, song, index + 1, resolve)
    }).catch((_err: Object) => {
      SourceManager.tryJsonPlayAttempts(attempts, song, index + 1, resolve)
    })
  }

  private static doJsonPlayRequest(playConf: Record<string, Object>, song: SongInfo): Promise<string> {
    return new Promise<string>((resolve: (url: string) => void) => {
      const url: string = String(playConf['url'] ?? '')
      if (url.length === 0) { resolve(''); return }
      const method: string = String(playConf['method'] ?? 'GET')
      const headers: Record<string, Object> = (playConf['headers'] ?? new Object()) as Record<string, Object>
      const params: Record<string, Object> = (playConf['params'] ?? new Object()) as Record<string, Object>
      const respConf: Record<string, Object> = (playConf['response'] ?? new Object()) as Record<string, Object>
      let songId: string = song.songId
      const rawData: string = song.rawData ?? ''
      if (rawData.length > 0) {
        try {
          const rawObj: Record<string, Object> = JSON.parse(rawData) as Record<string, Object>
          songId = String(rawObj['id'] ?? rawObj['songId'] ?? rawObj['hash'] ?? rawObj['mid'] ?? songId)
        } catch (_e) {}
      }
      let finalUrl: string = SourceManager.replacePlaceholders(url, '', songId, song.songName)
      const queryParts: string[] = []
      const paramKeys: string[] = Object.keys(params)
      for (let i = 0; i < paramKeys.length; i++) {
        const val: string = SourceManager.replacePlaceholders(String(params[paramKeys[i]]), '', songId, song.songName)
        queryParts.push(encodeURIComponent(paramKeys[i]) + '=' + encodeURIComponent(val))
      }
      if (method === 'GET' && queryParts.length > 0) {
        finalUrl = finalUrl + (finalUrl.indexOf('?') >= 0 ? '&' : '?') + queryParts.join('&')
      }
      const httpRequest = http.createHttp()
      const reqHeaders: Record<string, string> = {}
      const hKeys: string[] = Object.keys(headers)
      for (let i = 0; i < hKeys.length; i++) {
        reqHeaders[hKeys[i]] = String(headers[hKeys[i]])
      }
      reqHeaders['User-Agent'] = reqHeaders['User-Agent'] ?? 'Mozilla/5.0'
      const options: http.HttpRequestOptions = {
        method: method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: reqHeaders,
        readTimeout: 15000,
        connectTimeout: 10000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
      }
      if (method === 'POST' && queryParts.length > 0) {
        options.extraData = queryParts.join('&')
      }
      httpRequest.request(finalUrl, options).then((response: http.HttpResponse) => {
        httpRequest.destroy()
        let body: string = ''
        const result: Object | ArrayBuffer | string = response.result
        if (typeof result === 'string') {
          body = result as string
        } else if (result instanceof ArrayBuffer) {
          const dec: util.TextDecoder = util.TextDecoder.create('utf-8')
          body = dec.decodeToString(new Uint8Array(result))
        }
        if (body.length === 0) { resolve(''); return }
        const playUrl: string = SourceManager.extractJsonPlayUrl(body, respConf)
        resolve(playUrl)
      }).catch((_err: Object) => {
        httpRequest.destroy()
        resolve('')
      })
    })
  }

  private static extractJsonPlayUrl(body: string, respConf: Record<string, Object>): string {
    try {
      const root: Record<string, Object> = JSON.parse(body) as Record<string, Object>
      const codePath: string = String(respConf['codePath'] ?? '')
      const successCode: string = String(respConf['successCode'] ?? '')
      if (codePath.length > 0 && successCode.length > 0) {
        const codeVal: string = SourceManager.resolveJsonPathString(root, codePath)
        if (codeVal !== successCode) return ''
      }
      const urlPath: string = String(respConf['urlPath'] ?? '')
      if (urlPath.length === 0) return ''
      let playUrl: string = SourceManager.resolveJsonPathString(root, urlPath)
      const urlPrefix: string = String(respConf['urlPrefix'] ?? '')
      if (playUrl.length > 0 && urlPrefix.length > 0) playUrl = urlPrefix + playUrl
      if (playUrl.indexOf('http://') === 0 || playUrl.indexOf('https://') === 0) return playUrl
      return ''
    } catch (_e) {
      return ''
    }
  }

  private static jsonSourceGetLyric(config: SourceConfig, song: SongInfo): Promise<string> {
    return new Promise<string>((resolve: (lrc: string) => void) => {
      try {
        const parsed: Record<string, Object> = JSON.parse(config.jsSource ?? '') as Record<string, Object>
        const lyricConf: Record<string, Object> | undefined = parsed['lyric'] as Record<string, Object> | undefined
        if (lyricConf === undefined || lyricConf === null) { resolve(''); return }
        const fallbacks: Object | undefined = parsed['lyricFallback']
        const attempts: Record<string, Object>[] = [lyricConf]
        if (fallbacks instanceof Array) {
          const fbArr: Object[] = fallbacks as Object[]
          for (let i = 0; i < fbArr.length; i++) {
            attempts.push(fbArr[i] as Record<string, Object>)
          }
        }
        SourceManager.tryJsonLyricAttempts(attempts, song, 0, resolve)
      } catch (_e) {
        resolve('')
      }
    })
  }

  private static tryJsonLyricAttempts(attempts: Record<string, Object>[], song: SongInfo, index: number, resolve: (lrc: string) => void): void {
    if (index >= attempts.length) { resolve(''); return }
    const lyricConf: Record<string, Object> = attempts[index]
    SourceManager.doJsonLyricRequest(lyricConf, song).then((lrc: string) => {
      if (lrc.length > 0) { resolve(lrc); return }
      SourceManager.tryJsonLyricAttempts(attempts, song, index + 1, resolve)
    }).catch((_err: Object) => {
      SourceManager.tryJsonLyricAttempts(attempts, song, index + 1, resolve)
    })
  }

  private static doJsonLyricRequest(lyricConf: Record<string, Object>, song: SongInfo): Promise<string> {
    return new Promise<string>((resolve: (lrc: string) => void) => {
      const url: string = String(lyricConf['url'] ?? '')
      if (url.length === 0) { resolve(''); return }
      const method: string = String(lyricConf['method'] ?? 'GET')
      const headers: Record<string, Object> = (lyricConf['headers'] ?? new Object()) as Record<string, Object>
      const params: Record<string, Object> = (lyricConf['params'] ?? new Object()) as Record<string, Object>
      const respConf: Record<string, Object> = (lyricConf['response'] ?? new Object()) as Record<string, Object>
      let songId: string = song.songId
      let finalUrl: string = SourceManager.replacePlaceholders(url, '', songId, song.songName)
      const queryParts: string[] = []
      const paramKeys: string[] = Object.keys(params)
      for (let i = 0; i < paramKeys.length; i++) {
        const val: string = SourceManager.replacePlaceholders(String(params[paramKeys[i]]), '', songId, song.songName)
        queryParts.push(encodeURIComponent(paramKeys[i]) + '=' + encodeURIComponent(val))
      }
      if (method === 'GET' && queryParts.length > 0) {
        finalUrl = finalUrl + (finalUrl.indexOf('?') >= 0 ? '&' : '?') + queryParts.join('&')
      }
      const httpRequest = http.createHttp()
      const reqHeaders: Record<string, string> = {}
      const hKeys: string[] = Object.keys(headers)
      for (let i = 0; i < hKeys.length; i++) {
        reqHeaders[hKeys[i]] = String(headers[hKeys[i]])
      }
      reqHeaders['User-Agent'] = reqHeaders['User-Agent'] ?? 'Mozilla/5.0'
      const options: http.HttpRequestOptions = {
        method: method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: reqHeaders,
        readTimeout: 15000,
        connectTimeout: 10000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
      }
      if (method === 'POST' && queryParts.length > 0) {
        options.extraData = queryParts.join('&')
      }
      httpRequest.request(finalUrl, options).then((response: http.HttpResponse) => {
        httpRequest.destroy()
        let body: string = ''
        const result: Object | ArrayBuffer | string = response.result
        if (typeof result === 'string') {
          body = result as string
        } else if (result instanceof ArrayBuffer) {
          const dec: util.TextDecoder = util.TextDecoder.create('utf-8')
          body = dec.decodeToString(new Uint8Array(result))
        }
        if (body.length === 0) { resolve(''); return }
        const lrc: string = SourceManager.extractJsonLyric(body, respConf)
        resolve(lrc)
      }).catch((_err: Object) => {
        httpRequest.destroy()
        resolve('')
      })
    })
  }

  private static extractJsonLyric(body: string, respConf: Record<string, Object>): string {
    try {
      const respType: string = String(respConf['type'] ?? '')
      if (respType === 'plain_text') {
        return body.indexOf('[') >= 0 ? body : ''
      }
      const root: Record<string, Object> = JSON.parse(body) as Record<string, Object>
      const isBase64: boolean = String(respConf['base64'] ?? '') === 'true'
      const lrcPath: string = String(respConf['lrcPath'] ?? '')
      if (lrcPath.length === 0) return ''
      let lrc: string = SourceManager.resolveJsonPathString(root, lrcPath)
      if (isBase64 && lrc.length > 0) {
        try {
          const bytes: Uint8Array = SourceManager.base64ToBytes(lrc)
          const dec: util.TextDecoder = util.TextDecoder.create('utf-8')
          lrc = dec.decodeToString(bytes)
        } catch (_e) {
          return ''
        }
      }
      return lrc.indexOf('[') >= 0 ? lrc : ''
    } catch (_e) {
      if (body.indexOf('[') >= 0) return body
      return ''
    }
  }

  private static base64ToBytes(base64: string): Uint8Array {
    const chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    const lookup: number[] = new Array(128)
    for (let i = 0; i < 128; i++) { lookup[i] = -1 }
    for (let i = 0; i < 64; i++) { lookup[chars.charCodeAt(i)] = i }
    let byteLen: number = Math.floor(base64.length * 3 / 4)
    if (base64.length > 0 && base64.charAt(base64.length - 1) === '=') byteLen--
    if (base64.length > 1 && base64.charAt(base64.length - 2) === '=') byteLen--
    const bytes: Uint8Array = new Uint8Array(byteLen)
    let byteIdx: number = 0
    for (let i = 0; i < base64.length; i += 4) {
      const a: number = lookup[base64.charCodeAt(i)] ?? 0
      const b: number = i + 1 < base64.length ? (lookup[base64.charCodeAt(i + 1)] ?? 0) : 0
      const c: number = i + 2 < base64.length ? (lookup[base64.charCodeAt(i + 2)] ?? 0) : 0
      const d: number = i + 3 < base64.length ? (lookup[base64.charCodeAt(i + 3)] ?? 0) : 0
      bytes[byteIdx++] = (a << 2) | (b >> 4)
      if (byteIdx < byteLen) bytes[byteIdx++] = ((b & 0x0F) << 4) | (c >> 2)
      if (byteIdx < byteLen) bytes[byteIdx++] = ((c & 0x03) << 6) | d
    }
    return bytes
  }

  static async builtInPlatformSearch(config: SourceConfig, keyword: string): Promise<SongInfo[]> {
    const platform: string = SourceManager.inferPlatform(config.name)
    const isSinglePlatform: boolean = platform === 'kw' || platform === 'kg' || platform === 'tx' || platform === 'wy' || platform === 'mg'
    const platforms: string[] = isSinglePlatform ? [platform] : ['kw', 'kg', 'tx', 'wy', 'mg']
    const allResults: SongInfo[] = []
    const seenKeys: Set<string> = new Set()
    const tasks: Promise<SongInfo[]>[] = []
    for (let i = 0; i < platforms.length; i++) {
      tasks.push(SourceManager.doBuiltInSearch(platforms[i], keyword, config.name))
    }
    const settled: SongInfo[][] = await Promise.all(tasks)
    for (let i = 0; i < settled.length; i++) {
      const results: SongInfo[] = settled[i]
      for (let j = 0; j < results.length; j++) {
        const key: string = results[j].source + '|' + results[j].songId
        if (!seenKeys.has(key)) {
          seenKeys.add(key)
          allResults.push(results[j])
        }
      }
    }
    if (allResults.length === 0) {
      SourceManager.lastSearchError = `内置平台搜索无结果`
    }
    return allResults
  }

  private static async doBuiltInSearch(platform: string, keyword: string, pluginName: string): Promise<SongInfo[]> {
    const encodedKeyword: string = encodeURIComponent(keyword)
    let searchUrl: string = ''
    let reqHeaders: Record<string, string> = {}
    if (platform === 'kw') {
      searchUrl = `http://www.kuwo.cn/api/www/search/searchMusicBykeyWord?key=${encodedKeyword}&pn=1&rn=30`
      reqHeaders = { 'User-Agent': 'Mozilla/5.0', 'Referer': 'http://www.kuwo.cn/search/list?key=' + encodedKeyword, 'Cookie': 'kw_token=SUMYAPP' }
    } else if (platform === 'kg') {
      searchUrl = `http://mobilecdn.kugou.com/api/v3/search/song?keyword=${encodedKeyword}&page=1&pagesize=30`
      reqHeaders = { 'User-Agent': 'Mozilla/5.0' }
    } else if (platform === 'tx') {
      searchUrl = `https://c.y.qq.com/soso/fcgi-bin/client_search_cp?format=json&w=${encodedKeyword}&n=30&p=1`
      reqHeaders = { 'User-Agent': 'Mozilla/5.0', 'Referer': 'https://y.qq.com' }
    } else if (platform === 'wy') {
      searchUrl = `https://music.163.com/api/cloudsearch/pc?s=${encodedKeyword}&type=1&offset=0&limit=30`
      reqHeaders = { 'User-Agent': 'Mozilla/5.0', 'Referer': 'https://music.163.com' }
    } else if (platform === 'mg') {
      searchUrl = `https://m.music.migu.cn/migu/remoting/scr_search_tag?keyword=${encodedKeyword}&type=2&pg=1&pz=30`
      reqHeaders = { 'User-Agent': 'Mozilla/5.0', 'Referer': 'https://m.music.migu.cn' }
    }
    if (searchUrl.length === 0) return []
    const httpRequest = http.createHttp()
    try {
      const resp = await httpRequest.request(searchUrl, {
        method: http.RequestMethod.GET,
        header: reqHeaders,
        readTimeout: 15000,
        connectTimeout: 10000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
      })
      httpRequest.destroy()
      let body: string = ''
      const result: Object | ArrayBuffer | string = resp.result
      if (typeof result === 'string') {
        body = result as string
      } else if (result instanceof ArrayBuffer) {
        const dec: util.TextDecoder = util.TextDecoder.create('utf-8')
        body = dec.decodeToString(new Uint8Array(result))
      }
      if (body.length === 0) return []
      return SourceManager.parseBuiltInSearchResult(platform, body, pluginName)
    } catch (_e) {
      httpRequest.destroy()
      return []
    }
  }

  private static parseBuiltInSearchResult(platform: string, body: string, pluginName: string): SongInfo[] {
    try {
      const root: Record<string, Object> = JSON.parse(body) as Record<string, Object>
      const songs: SongInfo[] = []
      if (platform === 'kw') {
        const data: Object | undefined = root['data']
        if (data === undefined || data === null) return []
        const dataRec: Record<string, Object> = data as Record<string, Object>
        const list: Object | undefined = dataRec['list']
        if (!(list instanceof Array)) return []
        const arr: Object[] = list as Object[]
        for (let i = 0; i < arr.length; i++) {
          const item: Record<string, Object> = arr[i] as Record<string, Object>
          const rid: string = String(item['rid'] ?? '')
          const name: string = String(item['name'] ?? '')
          const artist: string = String(item['artist'] ?? '')
          if (rid.length === 0 || name.length === 0) continue
          const album: string = String(item['album'] ?? '')
          const durNum: number = Number(item['duration'] ?? 0) || 0
          const durText: string = durNum > 0 ? `${Math.floor(durNum / 60)}:${(durNum % 60).toString().padStart(2, '0')}` : ''
          const rawObj: Record<string, Object> = item
          rawObj['__platform'] = platform
          songs.push({
            songId: rid, songName: name, artist: artist, album: album,
            coverUrl: String(item['albPic'] ?? ''), source: 'custom_' + pluginName,
            playUrl: '', quality: durText.length > 0 ? '128kbps/' + durText : '128kbps',
            rawData: JSON.stringify(rawObj),
          })
        }
      } else if (platform === 'kg') {
        const data: Object | undefined = root['data']
        if (data === undefined || data === null) return []
        const dataRec: Record<string, Object> = data as Record<string, Object>
        const info: Object | undefined = dataRec['info']
        if (!(info instanceof Array)) return []
        const arr: Object[] = info as Object[]
        for (let i = 0; i < arr.length; i++) {
          const item: Record<string, Object> = arr[i] as Record<string, Object>
          const hash: string = String(item['hash'] ?? '')
          const name: string = String(item['songname'] ?? '')
          const artist: string = String(item['singername'] ?? '')
          if (hash.length === 0 || name.length === 0) continue
          const rawObj: Record<string, Object> = item
          rawObj['__platform'] = platform
          songs.push({
            songId: hash, songName: name, artist: artist,
            album: String(item['album_name'] ?? ''),
            coverUrl: String(item['imgUrl'] ?? '').replace('{size}', '400'),
            source: 'custom_' + pluginName, playUrl: '', quality: '128kbps',
            rawData: JSON.stringify(rawObj),
          })
        }
      } else if (platform === 'tx') {
        const data: Object | undefined = root['data']
        if (data === undefined || data === null) return []
        const dataRec: Record<string, Object> = data as Record<string, Object>
        const song: Object | undefined = dataRec['song']
        if (song === undefined || song === null) return []
        const songRec: Record<string, Object> = song as Record<string, Object>
        const list: Object | undefined = songRec['list']
        if (!(list instanceof Array)) return []
        const arr: Object[] = list as Object[]
        for (let i = 0; i < arr.length; i++) {
          const item: Record<string, Object> = arr[i] as Record<string, Object>
          const mid: string = String(item['songmid'] ?? '')
          const name: string = String(item['songname'] ?? '')
          if (mid.length === 0 || name.length === 0) continue
          let artist: string = ''
          const singer: Object | undefined = item['singer']
          if (singer instanceof Array) {
            const names: string[] = []
            const sArr: Object[] = singer as Object[]
            for (let j = 0; j < sArr.length; j++) {
              const s: Record<string, Object> = sArr[j] as Record<string, Object>
              const n: string = String(s['name'] ?? '')
              if (n.length > 0) names.push(n)
            }
            artist = names.join('/')
          }
          const albummid: string = String(item['albummid'] ?? '')
          const coverUrl: string = albummid.length > 0 ?
            `https://y.qq.com/music/photo_new/T002R300x300M000${albummid}.jpg` : ''
          const rawObj: Record<string, Object> = item
          rawObj['__platform'] = platform
          songs.push({
            songId: mid, songName: name, artist: artist,
            album: String(item['albumname'] ?? ''),
            coverUrl: coverUrl, source: 'custom_' + pluginName, playUrl: '', quality: '128kbps',
            mid: mid, rawData: JSON.stringify(rawObj),
          })
        }
      } else if (platform === 'wy') {
        const result: Object | undefined = root['result']
        if (result === undefined || result === null) return []
        const resultRec: Record<string, Object> = result as Record<string, Object>
        const songsList: Object | undefined = resultRec['songs']
        if (!(songsList instanceof Array)) return []
        const arr: Object[] = songsList as Object[]
        for (let i = 0; i < arr.length; i++) {
          const item: Record<string, Object> = arr[i] as Record<string, Object>
          const id: string = String(item['id'] ?? '')
          const name: string = String(item['name'] ?? '')
          if (id.length === 0 || name.length === 0) continue
          let artist: string = ''
          const ar: Object | undefined = item['ar']
          if (ar instanceof Array) {
            const names: string[] = []
            const arArr: Object[] = ar as Object[]
            for (let j = 0; j < arArr.length; j++) {
              const s: Record<string, Object> = arArr[j] as Record<string, Object>
              const n: string = String(s['name'] ?? '')
              if (n.length > 0) names.push(n)
            }
            artist = names.join('/')
          }
          const al: Object | undefined = item['al']
          const alRec: Record<string, Object> = (al instanceof Object ? al : new Object()) as Record<string, Object>
          const durNum: number = Number(item['dt'] ?? 0) || 0
          const durSec: number = Math.floor(durNum / 1000)
          const durText: string = durSec > 0 ? `${Math.floor(durSec / 60)}:${(durSec % 60).toString().padStart(2, '0')}` : ''
          const rawObj: Record<string, Object> = item
          rawObj['__platform'] = platform
          songs.push({
            songId: id, songName: name, artist: artist,
            album: String(alRec['name'] ?? ''),
            coverUrl: String(alRec['picUrl'] ?? ''),
            source: 'custom_' + pluginName, playUrl: '',
            quality: durText.length > 0 ? '128kbps/' + durText : '128kbps',
            rawData: JSON.stringify(rawObj),
          })
        }
      } else if (platform === 'mg') {
        const musics: Object | undefined = root['musics']
        if (!(musics instanceof Array)) return []
        const arr: Object[] = musics as Object[]
        for (let i = 0; i < arr.length; i++) {
          const item: Record<string, Object> = arr[i] as Record<string, Object>
          const id: string = String(item['id'] ?? '')
          const name: string = String(item['songName'] ?? String(item['title'] ?? ''))
          const artist: string = String(item['singerName'] ?? '')
          if (id.length === 0 || name.length === 0) continue
          const rawObj: Record<string, Object> = item
          rawObj['__platform'] = platform
          songs.push({
            songId: id, songName: name, artist: artist,
            album: String(item['albumName'] ?? ''),
            coverUrl: String(item['cover'] ?? ''),
            source: 'custom_' + pluginName, playUrl: '', quality: '128kbps',
            rawData: JSON.stringify(rawObj),
          })
        }
      }
      return songs
    } catch (_e) {
      return []
    }
  }
}
