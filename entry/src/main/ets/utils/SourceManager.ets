// SourceManager.ets - JS 插件管理器
// 管理标准格式 JS 插件的导入、搜索、播放与歌词

import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import fs from '@ohos.file.fs'
import type { SongInfo } from '../model/MusicModel'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { JsPluginEngine } from './JsPluginEngine'
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
  jsPlatform?: string
  jsVersion?: string
  jsMode?: string
}

const STORAGE_KEY_PREFIX: string = 'plugin_'
const STORAGE_INDEX_KEY: string = 'plugin_index'
const STORAGE_ENABLED_PREFIX: string = 'plugin_enabled_'

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
      const content: string = decoder.decodeWithStream(new Uint8Array(buffer))
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
      // 检测 v3 插件（globalThis.lx 事件驱动，如全豆要）：必须走新引擎 lxSourceManager
      const isV3: boolean = /globalThis\s*\.\s*lx/.test(jsCode) || /EVENT_NAMES/.test(jsCode) ||
        /\blx\.request\b/.test(jsCode) || /EVENT_NAMES\s*\.\s*inited/.test(jsCode)
      if (isV3) {
        try {
          const apiInfo = SourceManager.importLXApi(jsCode)
          // 注册到旧引擎索引，保证音源管理列表可见
          const name: string = apiInfo.name.length > 0 ? apiInfo.name : pluginName
          const config: SourceConfig = {
            name: name,
            type: 'lx_plugin',
            jsSource: jsCode,
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
          console.info(`[SourceManager] Imported V3 plugin (new engine): ${name}, apiId=${apiInfo.id}`)
          return name
        } catch (v3Err) {
          console.error('[SourceManager] import v3 plugin failed:', v3Err)
          return ''
        }
      }
      const config: SourceConfig | null = SourceManager.tryParseJsPlugin(jsCode, pluginName)
      if (!config) return ''
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
            content = dec.decodeWithStream(new Uint8Array(resp.result))
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
    for (let i = 0; i < names.length; i++) {
      const jsonStr = await SourceManager.getSetting(STORAGE_KEY_PREFIX + names[i])
      if (jsonStr.length > 0) {
        try { SourceManager.configs.set(names[i], JSON.parse(jsonStr) as SourceConfig) } catch (_e) {}
      }
    }
    console.info(`[SourceManager] Loaded ${SourceManager.configs.size} JS plugins`)
  }

  static async removeSource(name: string): Promise<void> {
    SourceManager.configs.delete(name)
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

  static async getEnabledSourceNames(): Promise<string[]> {
    const allNames: string[] = SourceManager.getSourceNames()
    const enabled: string[] = []
    for (let i = 0; i < allNames.length; i++) {
      if (await SourceManager.isSourceEnabled(allNames[i])) {
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
    // 并发搜索所有已启用插件（单个插件失败不影响整体），大幅缩短多插件聚合耗时
    const tasks: Promise<SongInfo[]>[] = []
    for (let i = 0; i < names.length; i++) {
      if (!(await SourceManager.isSourceEnabled(names[i]))) continue
      tasks.push(SourceManager.search(names[i], keyword).catch((_e: Error) => {
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
    // v1/v3/MusicFree 插件统一由 JsPluginEngine 执行（内部按 jsMode 分发：
    // v3 走 lx 事件分发 musicSearch，v1/MusicFree 走 search/searchMusic 方法）
    if (config.type === 'lx_plugin' && config.jsSource && config.jsSource.length > 0) {
      return await JsPluginEngine.search(config, keyword)
    }
    return []
  }

  static async getPlayUrl(sourceName: string, _songId: string, song?: SongInfo): Promise<string> {
    const config = SourceManager.configs.get(sourceName)
    if (!config || !(config.type === 'lx_plugin' && config.jsSource && config.jsSource.length > 0)) return ''
    // 平台码：优先按歌曲 source 推断（custom_酷狗→kg），其次按插件名，供 v3 聚合插件按平台取链
    const platform = SourceManager.inferPlatform(song && song.source ? song.source : sourceName)
    // v3 插件走新引擎
    if (config.jsMode === 'v3') {
      if (lxEngineIsReady && song) {
        try {
          const url = await getLXMusicUrl(platform, song.songId, '128k', song.songName, song.artist)
          if (url.length > 0) return url
        } catch (_e) {}
      }
      return ''
    }
    if (lxEngineIsReady && song) {
      try {
        const url = await getLXMusicUrl(platform, song.songId, '128k', song.songName, song.artist)
        if (url.length > 0) return url
      } catch (_e) {}
    }
    return await JsPluginEngine.getPlayUrl(config, song)
  }

  static async getPlayUrlFromAny(songId: string, _songName: string, _artist: string, song?: SongInfo): Promise<string> {
    const names = SourceManager.getSourceNames()
    for (let i = 0; i < names.length; i++) {
      if (!(await SourceManager.isSourceEnabled(names[i]))) continue
      const url = await SourceManager.getPlayUrl(names[i], songId, song)
      if (url.length > 0) return url
    }
    return ''
  }

  static async getLyrics(sourceName: string, _songId: string, _songName?: string, _artist?: string, song?: SongInfo): Promise<string> {
    const config = SourceManager.configs.get(sourceName)
    if (!config || !(config.type === 'lx_plugin' && config.jsSource && config.jsSource.length > 0)) return ''
    // v3 插件走新引擎
    if (config.jsMode === 'v3') {
      if (lxEngineIsReady && song) {
        try {
          const platform = SourceManager.inferPlatform(song.source ? song.source : sourceName)
          const lrc = await getLXLyric(platform, song.songId, song.songName, song.artist)
          if (lrc.length > 0) return lrc
        } catch (_e) {}
      }
      return ''
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
    const isV3 = /globalThis\s*\.\s*lx/.test(jsCode) || /EVENT_NAMES/.test(jsCode) ||
      /\blx\.request\b/.test(jsCode) || /EVENT_NAMES\s*\.\s*inited/.test(jsCode)
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
}
