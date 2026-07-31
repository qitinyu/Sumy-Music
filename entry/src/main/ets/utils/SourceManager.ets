// SourceManager.ets - 自定义音源管理器
// 支持导入 JSON 格式的音源配置文件，动态加载搜索/播放/歌词接口

import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import fs from '@ohos.file.fs'
import type { SongInfo } from '../model/MusicModel'
import { DatabaseHelper } from '../database/DatabaseHelper'

// ==================== 类型定义 ====================

export interface ParamPair {
  key: string
  value: string
}

export interface UrlParseResult {
  baseUrl: string
  params: ParamPair[]
}

export interface ImportResult {
  name: string
  success: boolean
  error?: string
}

export interface SourceConfig {
  name: string
  type: string
  search: SearchConfig
  play: PlayConfig
  lyric?: LyricConfig
}

export interface SearchConfig {
  url: string
  method: string
  params: Record<string, string>
  headers?: Record<string, string>
  response: SearchResponseConfig
}

export interface SearchResponseConfig {
  listPath: string
  songId: string
  songIdStrip: string
  songName: string
  artist: string
  album: string
  duration: string
  coverUrl: string
  coverPrefix: string
  coverSuffix: string
  isPay: string
}

export interface PlayConfig {
  url: string
  method: string
  params: Record<string, string>
  headers?: Record<string, string>
  response: PlayResponseConfig
}

export interface PlayResponseConfig {
  type: string
  urlPath: string
  codePath: string
  successCode: string
  urlPrefix: string
}

export interface LyricConfig {
  url: string
  method: string
  params: Record<string, string>
  headers?: Record<string, string>
  response: LyricResponseConfig
}

export interface LyricResponseConfig {
  type: string
  listPath: string
  lrcPath: string
  tlyricPath: string
  timeField: string
  textField: string
}

// ==================== SourceManager ====================

const STORAGE_KEY_PREFIX: string = 'custom_source_'
const STORAGE_INDEX_KEY: string = 'custom_source_index'
const STORAGE_ENABLED_PREFIX: string = 'source_enabled_'
const UA: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

// 数据库操作函数类型
type GetSettingFn = (key: string) => Promise<string>
type SetSettingFn = (key: string, value: string) => Promise<void>

export class SourceManager {
  private static configs: Map<string, SourceConfig> = new Map()
  private static getSettingFn: GetSettingFn | null = null
  private static setSettingFn: SetSettingFn | null = null
  private static loaded: boolean = false

  // 注入数据库操作函数（可选，默认使用 DatabaseHelper）
  static setDatabaseOps(getFn: GetSettingFn, setFn: SetSettingFn): void {
    SourceManager.getSettingFn = getFn
    SourceManager.setSettingFn = setFn
  }

  // 确保已从数据库加载所有音源（幂等，首次调用生效）
  static async ensureLoaded(): Promise<void> {
    if (SourceManager.loaded) return
    SourceManager.loaded = true
    await SourceManager.loadAll()
  }

  private static async getSetting(key: string): Promise<string> {
    if (SourceManager.getSettingFn) {
      return await SourceManager.getSettingFn(key)
    }
    return await DatabaseHelper.getInstance().getSetting(key)
  }

  private static async setSetting(key: string, value: string): Promise<void> {
    if (SourceManager.setSettingFn) {
      await SourceManager.setSettingFn(key, value)
      return
    }
    await DatabaseHelper.getInstance().setSetting(key, value)
  }

  // 从文件导入音源配置（自动检测 JSON 或 JS 插件）
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
      const name: string = await SourceManager.autoDetectAndImport(content, pluginName)
      if (name.length > 0) {
        console.info(`[SourceManager] Imported source from file: ${name}`)
      }
      return name
    } catch (e) {
      console.error('[SourceManager] importFromFile failed:', e)
      return ''
    }
  }

  // 从 JS 插件代码导入音源配置
  static async importJsConfig(jsCode: string, pluginName: string): Promise<string> {
    try {
      const config: SourceConfig | null = SourceManager.tryParseJsPlugin(jsCode, pluginName)
      if (!config) return ''

      const configJson: string = JSON.stringify(config)
      await SourceManager.setSetting(STORAGE_KEY_PREFIX + config.name, configJson)

      let indexStr: string = await SourceManager.getSetting(STORAGE_INDEX_KEY)
      let names: string[] = []
      if (indexStr.length > 0) {
        names = JSON.parse(indexStr) as string[]
      }
      let found: boolean = false
      for (let i = 0; i < names.length; i++) {
        if (names[i] === config.name) {
          found = true
          break
        }
      }
      if (!found) {
        names.push(config.name)
      }
      await SourceManager.setSetting(STORAGE_INDEX_KEY, JSON.stringify(names))

      SourceManager.configs.set(config.name, config)

      console.info(`[SourceManager] Imported JS plugin: ${config.name}`)
      return config.name
    } catch (e) {
      console.error('[SourceManager] importJsConfig failed:', e)
      return ''
    }
  }

  // 自动检测内容格式并导入：先尝试 JSON，失败则尝试 JS 插件
  static async autoDetectAndImport(content: string, fallbackName: string = 'custom'): Promise<string> {
    // 先尝试 JSON 解析
    try {
      const parsed = JSON.parse(content) as Record<string, Object>
      if (parsed['name'] !== undefined && parsed['search'] !== undefined && parsed['play'] !== undefined) {
        return await SourceManager.importConfig(content)
      }
    } catch (_e) {
      // JSON 解析失败，尝试 JS 插件
    }
    // 尝试 JS 插件解析
    const result = await SourceManager.importJsConfig(content, fallbackName)
    return result
  }

  // 从 JSON 字符串导入音源配置
  static async importConfig(jsonStr: string): Promise<string> {
    try {
      const config: SourceConfig = SourceManager.parseConfig(jsonStr)
      if (config.name.length === 0 || !config.search || !config.play) {
        return ''
      }

      const configJson: string = JSON.stringify(config)
      await SourceManager.setSetting(STORAGE_KEY_PREFIX + config.name, configJson)

      let indexStr: string = await SourceManager.getSetting(STORAGE_INDEX_KEY)
      let names: string[] = []
      if (indexStr.length > 0) {
        names = JSON.parse(indexStr) as string[]
      }
      let found: boolean = false
      for (let i = 0; i < names.length; i++) {
        if (names[i] === config.name) {
          found = true
          break
        }
      }
      if (!found) {
        names.push(config.name)
      }
      await SourceManager.setSetting(STORAGE_INDEX_KEY, JSON.stringify(names))

      SourceManager.configs.set(config.name, config)

      console.info(`[SourceManager] Imported source from config: ${config.name}`)
      return config.name
    } catch (e) {
      console.error('[SourceManager] importConfig failed:', e)
      return ''
    }
  }

  // 从数据库加载所有已导入的音源
  static async loadAll(): Promise<void> {
    const indexStr: string = await SourceManager.getSetting(STORAGE_INDEX_KEY)
    if (indexStr.length === 0) return

    const names: string[] = JSON.parse(indexStr) as string[]
    for (let i = 0; i < names.length; i++) {
      const jsonStr: string = await SourceManager.getSetting(STORAGE_KEY_PREFIX + names[i])
      if (jsonStr.length > 0) {
        try {
          const config: SourceConfig = SourceManager.parseConfig(jsonStr)
          SourceManager.configs.set(config.name, config)
        } catch (_e) {
          // 跳过损坏的配置
        }
      }
    }

    console.info(`[SourceManager] Loaded ${SourceManager.configs.size} custom sources`)
  }

  // 删除音源
  static async removeSource(name: string): Promise<void> {
    SourceManager.configs.delete(name)
    await SourceManager.setSetting(STORAGE_KEY_PREFIX + name, '')

    const indexStr: string = await SourceManager.getSetting(STORAGE_INDEX_KEY)
    if (indexStr.length > 0) {
      const names: string[] = JSON.parse(indexStr) as string[]
      const newNames: string[] = []
      for (let i = 0; i < names.length; i++) {
        if (names[i] !== name) {
          newNames.push(names[i])
        }
      }
      await SourceManager.setSetting(STORAGE_INDEX_KEY, JSON.stringify(newNames))
    }
  }

  // 获取所有已加载的音源名
  static getSourceNames(): string[] {
    const names: string[] = []
    SourceManager.configs.forEach((config: SourceConfig) => {
      names.push(config.name)
    })
    return names
  }

  // 获取已启用的音源名
  static async getEnabledSourceNames(): Promise<string[]> {
    const allNames: string[] = SourceManager.getSourceNames()
    const enabledNames: string[] = []
    for (let i = 0; i < allNames.length; i++) {
      const enabled: boolean = await SourceManager.isSourceEnabled(allNames[i])
      if (enabled) {
        enabledNames.push(allNames[i])
      }
    }
    return enabledNames
  }

  // 获取同步的已启用音源名（从缓存读取，避免异步）
  static getEnabledSourceNamesSync(): string[] {
    // 返回所有音源名，同步模式下默认全部启用
    // 实际启用状态由外部调用 isSourceEnabled 检查
    return SourceManager.getSourceNames()
  }

  // 检查音源是否启用
  static async isSourceEnabled(name: string): Promise<boolean> {
    const val: string = await SourceManager.getSetting(STORAGE_ENABLED_PREFIX + name)
    // 默认启用
    return val !== 'false'
  }

  // 设置音源启用状态
  static async setSourceEnabled(name: string, enabled: boolean): Promise<void> {
    await SourceManager.setSetting(STORAGE_ENABLED_PREFIX + name, enabled ? 'true' : 'false')
  }

  // 获取音源配置
  static getConfig(name: string): SourceConfig | undefined {
    return SourceManager.configs.get(name)
  }

  // 搜索所有自定义音源（仅搜索已启用的）
  static async searchAll(keyword: string): Promise<SongInfo[]> {
    const names: string[] = SourceManager.getSourceNames()
    let allResults: SongInfo[] = []
    for (let i = 0; i < names.length; i++) {
      const enabled: boolean = await SourceManager.isSourceEnabled(names[i])
      if (!enabled) continue
      const results: SongInfo[] = await SourceManager.search(names[i], keyword)
      allResults = allResults.concat(results)
    }
    return allResults
  }

  // 使用自定义音源搜索
  static async search(sourceName: string, keyword: string): Promise<SongInfo[]> {
    const config: SourceConfig | undefined = SourceManager.configs.get(sourceName)
    if (!config) return []

    try {
      const method: string = config.search.method || 'GET'
      const headers: Record<string, string> = config.search.headers ?? (new Object() as Record<string, string>)
      let raw: string = ''

      if (method === 'POST') {
        const body: string = SourceManager.buildFormBody(config.search.params, keyword, '0')
        raw = await SourceManager.httpRequest(config.search.url, 'POST', body, headers)
      } else {
        const url: string = SourceManager.buildUrl(config.search.url, config.search.params, keyword, '0')
        raw = await SourceManager.httpGet(url, headers)
      }

      if (raw.length === 0) return []

      const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>
      const list: Object = SourceManager.getNestedValue(parsed, config.search.response.listPath)
      if (!(list instanceof Array)) return []

      const results: SongInfo[] = []
      const arr: Object[] = list as Object[]

      for (let i = 0; i < arr.length; i++) {
        const item: Record<string, Object> = arr[i] as Record<string, Object>
        let songId: string = String(item[config.search.response.songId] ?? '')
        const strip: string = config.search.response.songIdStrip
        if (strip.length > 0 && songId.startsWith(strip)) {
          songId = songId.substring(strip.length)
        }

        const songName: string = String(item[config.search.response.songName] ?? '')
        const artist: string = String(item[config.search.response.artist] ?? '')
        const album: string = config.search.response.album.length > 0 ? String(item[config.search.response.album] ?? '') : ''

        let coverUrl: string = ''
        if (config.search.response.coverUrl.length > 0) {
          const coverPart: string = String(item[config.search.response.coverUrl] ?? '')
          if (coverPart.length > 0) {
            let rawCover: string = coverPart
            if (rawCover.startsWith('//')) {
              rawCover = 'https:' + rawCover
            }
            coverUrl = config.search.response.coverPrefix + rawCover + config.search.response.coverSuffix
          }
        }

        let durStr: string = '0'
        if (config.search.response.duration.length > 0) {
          durStr = String(item[config.search.response.duration] ?? '0')
        }
        const durSec: number = parseInt(durStr) || 0
        const durFormatted: string = `${Math.floor(durSec / 60)}:${(durSec % 60).toString().padStart(2, '0')}`

        if (songId.length === 0 || songName.length === 0) continue

        let isPay: boolean = false
        if (config.search.response.isPay.length > 0) {
          isPay = String(item[config.search.response.isPay] ?? '0') === '1'
        }

        const song: SongInfo = {
          songId: songId,
          songName: songName,
          artist: artist,
          album: album,
          coverUrl: coverUrl,
          source: 'custom_' + config.name,
          playUrl: '',
          quality: isPay ? `VIP/${durFormatted}` : `128kbps/${durFormatted}`,
        }
        results.push(song)
      }

      console.info(`[SourceManager] Search "${keyword}" via ${sourceName} => ${results.length} results`)
      return results
    } catch (e) {
      console.error(`[SourceManager] search failed for ${sourceName}:`, e)
      return []
    }
  }

  // 使用自定义音源获取播放 URL
  static async getPlayUrl(sourceName: string, songId: string): Promise<string> {
    const config: SourceConfig | undefined = SourceManager.configs.get(sourceName)
    if (!config) return ''

    try {
      const method: string = config.play.method || 'GET'
      const headers: Record<string, string> = config.play.headers ?? (new Object() as Record<string, string>)
      const respType: string = config.play.response.type || 'json'
      let raw: string = ''

      if (method === 'POST') {
        const body: string = SourceManager.buildFormBody(config.play.params, songId, '')
        raw = await SourceManager.httpRequest(config.play.url, 'POST', body, headers)
      } else {
        const url: string = SourceManager.buildUrl(config.play.url, config.play.params, songId, '')
        raw = await SourceManager.httpGet(url, headers)
      }
      if (raw.length === 0) return ''

      // 纯文本模式：直接返回响应体作为播放 URL
      if (respType === 'plain_text') {
        const trimmed: string = raw.trim()
        if (trimmed.length > 0 && (trimmed.startsWith('http://') || trimmed.startsWith('https://'))) {
          return trimmed
        }
        return ''
      }

      const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>

      // 检查成功码
      if (config.play.response.codePath.length > 0) {
        const code: string = String(SourceManager.getNestedValue(parsed, config.play.response.codePath) ?? '')
        const successCode: string = config.play.response.successCode
        if (code !== successCode) {
          console.warn(`[SourceManager] Play URL failed: code=${code}`)
          return ''
        }
      }

      const playUrl: string = String(SourceManager.getNestedValue(parsed, config.play.response.urlPath) ?? '')
      if (playUrl.length > 0 && (playUrl.startsWith('http://') || playUrl.startsWith('https://'))) {
        return config.play.response.urlPrefix + playUrl
      }

      return ''
    } catch (e) {
      console.error(`[SourceManager] getPlayUrl failed for ${sourceName}:`, e)
      return ''
    }
  }

  // 尝试所有自定义音源获取播放 URL（仅已启用的）
  static async getPlayUrlFromAny(songId: string, songName: string, artist: string): Promise<string> {
    const names: string[] = SourceManager.getSourceNames()
    for (let i = 0; i < names.length; i++) {
      const enabled: boolean = await SourceManager.isSourceEnabled(names[i])
      if (!enabled) continue
      const url: string = await SourceManager.getPlayUrl(names[i], songId)
      if (url.length > 0) return url
    }
    return ''
  }

  // 使用自定义音源获取歌词
  static async getLyrics(sourceName: string, songId: string, songName?: string, artist?: string): Promise<string> {
    const config: SourceConfig | undefined = SourceManager.configs.get(sourceName)
    if (!config || !config.lyric) return ''

    try {
      const method: string = config.lyric.method || 'GET'
      const headers: Record<string, string> = config.lyric.headers ?? (new Object() as Record<string, string>)
      const respType: string = config.lyric.response.type || 'json'
      let raw: string = ''

      if (method === 'POST') {
        const body: string = SourceManager.buildFormBody(config.lyric.params, songId, '')
        raw = await SourceManager.httpRequest(config.lyric.url, 'POST', body, headers)
      } else {
        const url: string = SourceManager.buildUrl(config.lyric.url, config.lyric.params, songId, '', songName, artist)
        raw = await SourceManager.httpGet(url, headers)
      }
      if (raw.length === 0) return ''

      // 纯文本模式：直接返回响应体作为 LRC 文本
      if (respType === 'plain_text') {
        return raw
      }

      const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>

      // JSON 文本提取模式：通过 lrcPath 获取歌词文本
      if (config.lyric.response.lrcPath.length > 0) {
        let lrcText: string = String(SourceManager.getNestedValue(parsed, config.lyric.response.lrcPath) ?? '')
        if (lrcText.length > 0) {
          // 尝试拼接翻译歌词
          if (config.lyric.response.tlyricPath.length > 0) {
            const tlText: string = String(SourceManager.getNestedValue(parsed, config.lyric.response.tlyricPath) ?? '')
            if (tlText.length > 0) {
              lrcText += '\n' + tlText
            }
          }
          return lrcText
        }
      }

      // JSON 数组模式：通过 listPath + timeField + textField 解析
      const list: Object = SourceManager.getNestedValue(parsed, config.lyric.response.listPath)
      if (!(list instanceof Array)) return ''

      let lrc: string = ''
      const arr: Object[] = list as Object[]
      for (let i = 0; i < arr.length; i++) {
        const item: Record<string, Object> = arr[i] as Record<string, Object>
        const time: string = String(item[config.lyric.response.timeField] ?? '0:00.00')
        const text: string = String(item[config.lyric.response.textField] ?? '')
        lrc += `[${time}]${text}\n`
      }

      return lrc
    } catch (e) {
      console.error(`[SourceManager] getLyrics failed for ${sourceName}:`, e)
      return ''
    }
  }

  // ==================== 内部工具函数 ====================

  private static parseConfig(jsonStr: string): SourceConfig {
    const raw: Record<string, Object> = JSON.parse(jsonStr) as Record<string, Object>
    const searchRaw: Object | undefined = raw['search']
    const playRaw: Object | undefined = raw['play']
    const lyricRaw: Object | undefined = raw['lyric']

    const config: SourceConfig = {
      name: String(raw['name'] ?? ''),
      type: String(raw['type'] ?? 'custom'),
      search: searchRaw ? SourceManager.parseSearchConfig(searchRaw) : SourceManager.emptySearchConfig(),
      play: playRaw ? SourceManager.parsePlayConfig(playRaw) : SourceManager.emptyPlayConfig(),
      lyric: lyricRaw ? SourceManager.parseLyricConfig(lyricRaw) : undefined,
    }
    return config
  }

  private static emptySearchConfig(): SearchConfig {
    const emptyParams: Record<string, string> = new Object() as Record<string, string>
    return {
      url: '',
      method: 'GET',
      params: emptyParams,
      response: {
        listPath: '',
        songId: 'songId',
        songIdStrip: '',
        songName: 'songName',
        artist: 'artist',
        album: '',
        duration: '',
        coverUrl: '',
        coverPrefix: '',
        coverSuffix: '',
        isPay: '',
      },
    }
  }

  private static emptyPlayConfig(): PlayConfig {
    const emptyParams: Record<string, string> = new Object() as Record<string, string>
    return {
      url: '',
      method: 'GET',
      params: emptyParams,
      response: {
        type: 'json',
        urlPath: 'url',
        codePath: '',
        successCode: '200',
        urlPrefix: '',
      },
    }
  }

  private static parseSearchConfig(raw: Object): SearchConfig {
    const obj: Record<string, Object> = raw as Record<string, Object>
    const respRaw: Object | undefined = obj['response']
    const resp: Record<string, Object> = (respRaw !== undefined && respRaw !== null) ? respRaw as Record<string, Object> : new Object() as Record<string, Object>
    const result: SearchConfig = {
      url: String(obj['url'] ?? ''),
      method: String(obj['method'] ?? 'GET'),
      params: SourceManager.toStringMap(obj['params']),
      headers: obj['headers'] ? SourceManager.toStringMap(obj['headers']) : undefined,
      response: {
        listPath: String(resp['listPath'] ?? ''),
        songId: String(resp['songId'] ?? 'songId'),
        songIdStrip: resp['songIdStrip'] ? String(resp['songIdStrip']) : '',
        songName: String(resp['songName'] ?? 'songName'),
        artist: String(resp['artist'] ?? 'artist'),
        album: resp['album'] ? String(resp['album']) : '',
        duration: resp['duration'] ? String(resp['duration']) : '',
        coverUrl: resp['coverUrl'] ? String(resp['coverUrl']) : '',
        coverPrefix: resp['coverPrefix'] ? String(resp['coverPrefix']) : '',
        coverSuffix: resp['coverSuffix'] ? String(resp['coverSuffix']) : '',
        isPay: resp['isPay'] ? String(resp['isPay']) : '',
      },
    }
    return result
  }

  private static parsePlayConfig(raw: Object): PlayConfig {
    const obj: Record<string, Object> = raw as Record<string, Object>
    const respRaw: Object | undefined = obj['response']
    const resp: Record<string, Object> = (respRaw !== undefined && respRaw !== null) ? respRaw as Record<string, Object> : new Object() as Record<string, Object>
    const result: PlayConfig = {
      url: String(obj['url'] ?? ''),
      method: String(obj['method'] ?? 'GET'),
      params: SourceManager.toStringMap(obj['params']),
      headers: obj['headers'] ? SourceManager.toStringMap(obj['headers']) : undefined,
      response: {
        type: resp['type'] ? String(resp['type']) : 'json',
        urlPath: String(resp['urlPath'] ?? 'url'),
        codePath: resp['codePath'] ? String(resp['codePath']) : '',
        successCode: resp['successCode'] ? String(resp['successCode']) : '200',
        urlPrefix: resp['urlPrefix'] ? String(resp['urlPrefix']) : '',
      },
    }
    return result
  }

  private static parseLyricConfig(raw: Object): LyricConfig {
    const obj: Record<string, Object> = raw as Record<string, Object>
    const respRaw: Object | undefined = obj['response']
    const resp: Record<string, Object> = (respRaw !== undefined && respRaw !== null) ? respRaw as Record<string, Object> : new Object() as Record<string, Object>
    const result: LyricConfig = {
      url: String(obj['url'] ?? ''),
      method: String(obj['method'] ?? 'GET'),
      params: SourceManager.toStringMap(obj['params']),
      headers: obj['headers'] ? SourceManager.toStringMap(obj['headers']) : undefined,
      response: {
        type: resp['type'] ? String(resp['type']) : 'json',
        listPath: String(resp['listPath'] ?? 'data.lrclist'),
        lrcPath: resp['lrcPath'] ? String(resp['lrcPath']) : '',
        tlyricPath: resp['tlyricPath'] ? String(resp['tlyricPath']) : '',
        timeField: String(resp['timeField'] ?? 'time'),
        textField: String(resp['textField'] ?? 'lineLyric'),
      },
    }
    return result
  }

  private static toStringMap(raw: Object): Record<string, string> {
    const result: Record<string, string> = new Object() as Record<string, string>
    if (raw && typeof raw === 'object') {
      const obj: Record<string, Object> = raw as Record<string, Object>
      const keys: string[] = Object.keys(obj)
      for (let i = 0; i < keys.length; i++) {
        result[keys[i]] = String(obj[keys[i]])
      }
    }
    return result
  }

  // 构建 URL：替换 params 中的 {keyword}、{songId}、{songName}、{artist}、{page} 等占位符
  // primaryValue: 当搜索时是 keyword，当播放时是 songId
  static buildUrl(baseUrl: string, params: Record<string, string>, primaryValue: string, page: string, songName?: string, artist?: string): string {
    const parts: string[] = []
    const keys: string[] = Object.keys(params)
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i]
      let val: string = params[key]
      // 替换占位符 — primaryValue 用于 {keyword} 或 {songId}
      val = val.replace('{keyword}', encodeURIComponent(primaryValue))
      val = val.replace('{songId}', encodeURIComponent(primaryValue))
      val = val.replace('{songName}', songName ? encodeURIComponent(songName) : '')
      val = val.replace('{artist}', artist ? encodeURIComponent(artist) : '')
      val = val.replace('{page}', page)
      parts.push(`${key}=${val}`)
    }

    if (parts.length === 0) return baseUrl
    const separator: string = baseUrl.indexOf('?') >= 0 ? '&' : '?'
    return baseUrl + separator + parts.join('&')
  }

  // 构建 POST form body：将 params 中的占位符替换后拼接为 key=value&key2=value2
  static buildFormBody(params: Record<string, string>, primaryValue: string, page: string, songName?: string, artist?: string): string {
    const parts: string[] = []
    const keys: string[] = Object.keys(params)
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i]
      let val: string = params[key]
      val = val.replace('{keyword}', encodeURIComponent(primaryValue))
      val = val.replace('{songId}', encodeURIComponent(primaryValue))
      val = val.replace('{songName}', songName ? encodeURIComponent(songName) : '')
      val = val.replace('{artist}', artist ? encodeURIComponent(artist) : '')
      val = val.replace('{page}', page)
      parts.push(`${key}=${val}`)
    }
    return parts.join('&')
  }

  // 从嵌套路径获取值：如 "data.lrclist" 或 "singer[0].name"
  private static getNestedValue(obj: Record<string, Object>, path: string): Object {
    const parts: string[] = path.split('.')
    let current: Object = obj
    for (let i = 0; i < parts.length; i++) {
      if (current === null || current === undefined || typeof current !== 'object') {
        return ''
      }
      const part = parts[i]
      // 支持数组索引: singer[0]
      const arrMatch = part.match(/^(\w+)\[(\d+)\]$/)
      if (arrMatch) {
        const record: Record<string, Object> = current as Record<string, Object>
        const arr = record[arrMatch[1]]
        if (arr instanceof Array) {
          const idx = parseInt(arrMatch[2])
          current = (idx < arr.length) ? (arr[idx] as Object) : ''
        } else {
          current = ''
        }
      } else {
        const record: Record<string, Object> = current as Record<string, Object>
        current = record[part] ?? ''
      }
    }
    return current
  }

  private static async httpRequest(url: string, method: string, body?: string, extraHeaders?: Record<string, string>): Promise<string> {
    try {
      const headerObj: Record<string, string> = { 'User-Agent': UA } as Record<string, string>
      if (extraHeaders) {
        const keys: string[] = Object.keys(extraHeaders)
        for (let i = 0; i < keys.length; i++) {
          headerObj[keys[i]] = extraHeaders[keys[i]]
        }
      }
      const httpRequest = http.createHttp()
      const options: http.HttpRequestOptions = {
        method: method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: headerObj,
        readTimeout: 10000,
        connectTimeout: 10000,
      } as http.HttpRequestOptions
      if (method === 'POST' && !headerObj['Content-Type']) {
        headerObj['Content-Type'] = 'application/x-www-form-urlencoded'
      }
      if (body !== undefined && body.length > 0) {
        (options as Record<string, Object>)['extraData'] = body
      }
      const response = await httpRequest.request(url, options)
      httpRequest.destroy()
      const result = response.result
      if (typeof result === 'string') {
        return result
      }
      const bytes: Uint8Array = result as Uint8Array
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
      return decoder.decodeWithStream(bytes)
    } catch (e) {
      console.error('[SourceManager] httpRequest failed:', e)
      return ''
    }
  }

  // 兼容旧调用
  private static async httpGet(url: string, extraHeaders?: Record<string, string>): Promise<string> {
    return SourceManager.httpRequest(url, 'GET', undefined, extraHeaders)
  }

  // ==================== JS 插件解析 (LX Music 格式) ====================

  // 从 LX Music JS 插件代码中提取音源配置
  static tryParseJsPlugin(jsCode: string, pluginName: string): SourceConfig | null {
    try {
      // 1. 提取 requestMusicUrl 中的播放 URL
      const playUrl = SourceManager.extractPlayUrl(jsCode)
      if (!playUrl || playUrl.length === 0) {
        console.warn(`[SourceManager] Cannot extract play URL from ${pluginName}`)
        return null
      }

      // 2. 尝试提取搜索 URL
      const searchInfo = SourceManager.extractSearchInfo(jsCode)
      if (!searchInfo) {
        console.warn(`[SourceManager] Cannot extract search URL from ${pluginName}`)
        return null
      }

      // 3. 构建 SourceConfig
      const config: SourceConfig = {
        name: pluginName,
        type: 'lx_plugin',
        search: searchInfo,
        play: SourceManager.buildPlayConfig(playUrl),
      }

      console.info(`[SourceManager] Parsed JS plugin: ${pluginName}`)
      return config
    } catch (e) {
      console.error(`[SourceManager] tryParseJsPlugin failed for ${pluginName}:`, e)
      return null
    }
  }

  // 提取播放 URL
  private static extractPlayUrl(jsCode: string): string {
    // 匹配 requestMusicUrl 函数体中的 URL
    const funcMatch = jsCode.match(/async\s+function\s+requestMusicUrl[\s\S]*?^}/m)
    const funcBody = funcMatch ? funcMatch[0] : ''

    // 模式1: 完整的 URL 模板字符串 "https://...{songId}..."
    if (funcBody.length > 0) {
      const templateMatch = funcBody.match(/["'`](https?:\/\/[^"'`]*?\{songId\}[^"'`]*)["'`]/)
      if (templateMatch) {
        return templateMatch[1]
      }
    }

    // 模式2: url: "https://..." 或 return { url: "https://..." } (在函数体内)
    if (funcBody.length > 0) {
      const urlMatch = funcBody.match(/url\s*:\s*["'`](https?:\/\/[^"'`]+)["'`]/)
      if (urlMatch) {
        return urlMatch[1]
      }
    }

    // 模式3: 拼接形式 "https://...?id=" + encodeURIComponent(songId) + "&level=..."
    // 尝试重建完整 URL 模板
    if (funcBody.length > 0) {
      const rebuilt = SourceManager.rebuildConcatUrl(funcBody)
      if (rebuilt.length > 0) return rebuilt
    }

    // 模式4: 全局搜索 url: "https://..." (兜底)
    const urlMatch = jsCode.match(/url\s*:\s*["'`](https?:\/\/[^"'`]+)["'`]/)
    if (urlMatch) {
      return urlMatch[1]
    }

    return ''
  }

  // 从字符串拼接重建 URL 模板
  private static rebuildConcatUrl(funcBody: string): string {
    // 匹配 "https://...?id=" + encodeURIComponent(songId) + "&level=" + encodeURIComponent(level)
    // 提取所有字符串片段
    const parts: string[] = []
    const regex = /["'`]([^"'`]*)["'`]\s*\+/g
    let match = regex.exec(funcBody)
    while (match !== null) {
      parts.push(match[1])
      match = regex.exec(funcBody)
    }
    // 也匹配最后一个不带 + 的片段
    const lastMatch = funcBody.match(/["'`]([^"'`]*)["'`]\s*[;}\)]/)
    if (lastMatch && parts.length > 0) {
      parts.push(lastMatch[1])
    }

    if (parts.length >= 2) {
      let url = parts[0]
      if (url.startsWith('http')) {
        // 将中间的 encodeURIComponent 参数替换为占位符
        for (let i = 1; i < parts.length; i++) {
          // 检测下一个片段是否以 & 或 ? 开头，说明是 URL 参数延续
          if (parts[i].startsWith('&') || parts[i].startsWith('?') || parts[i].startsWith('/')) {
            url += `{songId}` + parts[i]
          } else {
            url += parts[i]
          }
        }
        // 如果只有一个参数插入点，添加 {songId}
        if (url.indexOf('{songId}') < 0) {
          url = url.replace(/\?([^=]+)=$/, '?$1={songId}')
        }
        return url
      }
    }
    return ''
  }

  // 提取搜索信息
  private static extractSearchInfo(jsCode: string): SearchConfig | null {
    // 策略1: 查找 getMusicInfo 或 searchMusic 函数
    const searchFunc = jsCode.match(/(?:async\s+function\s+(?:getMusicInfo|searchMusic)|function\s+(?:getMusicInfo|searchMusic))[\s\S]*?^}/m)
    if (!searchFunc) {
      // 策略2: 查找 axios.get 或 axios_1.default.get 调用中的 URL
      const axiosCalls = SourceManager.extractAxiosUrls(jsCode)
      if (axiosCalls.length > 0) {
        // 优先找包含 search 关键字的 URL
        for (let i = 0; i < axiosCalls.length; i++) {
          const url = axiosCalls[i]
          if (url.indexOf('search') >= 0 || url.indexOf('query') >= 0 || url.indexOf('soso') >= 0) {
            return SourceManager.guessSearchConfig(url, jsCode)
          }
        }
        // 没有 search 关键字，用第一个 URL
        return SourceManager.guessSearchConfig(axiosCalls[0], jsCode)
      }
      return null
    }

    const funcBody = searchFunc[0]
    const urls = SourceManager.extractAxiosUrls(funcBody)
    if (urls.length === 0) return null

    return SourceManager.guessSearchConfig(urls[0], jsCode)
  }

  // 提取 axios 调用中的 URL
  private static extractAxiosUrls(code: string): string[] {
    const urls: string[] = []
    const seen: Set<string> = new Set()

    // 匹配 axios.get("url") 或 axios_1.default.get("url")
    const getRegex = /(?:axios|axios_1\.default)\s*\.\s*get\s*\(\s*["'`](https?:\/\/[^"'`]+)["'`]/g
    let match = getRegex.exec(code)
    while (match !== null) {
      const url = match[1]
      if (!seen.has(url)) {
        seen.add(url)
        urls.push(url)
      }
      match = getRegex.exec(code)
    }

    // 匹配 axios({ method: "post", url: "..." })
    const postRegex = /(?:axios|axios_1\.default)\s*\(\s*\{[\s\S]*?url\s*:\s*["'`](https?:\/\/[^"'`]+)["'`]/g
    match = postRegex.exec(code)
    while (match !== null) {
      const url = match[1]
      if (!seen.has(url)) {
        seen.add(url)
        urls.push(url)
      }
      match = postRegex.exec(code)
    }

    return urls
  }

  // 根据搜索 URL 猜测搜索配置
  private static guessSearchConfig(url: string, jsCode: string): SearchConfig {
    // 判断是 GET 还是 POST
    const isPost = jsCode.indexOf(`"${url}"`) >= 0 &&
      jsCode.substring(0, jsCode.indexOf(`"${url}"`)).indexOf('method: "post"') >= 0

    const method = isPost ? 'POST' : 'GET'

    // 提取参数
    const params: Record<string, string> = new Object() as Record<string, string>
    const urlObj = SourceManager.parseUrlParams(url)

    if (urlObj.params.length > 0) {
      // URL 已有参数，提取并添加 keyword 占位符
      for (let i = 0; i < urlObj.params.length; i++) {
        const p = urlObj.params[i]
        if (p.key === 'keyword' || p.key === 'key' || p.key === 's' || p.key === 'q' || p.key === 'query' || p.key === 'keywords' || p.key === 'wd' || p.key === 'w') {
          params[p.key] = '{keyword}'
        } else {
          params[p.key] = p.value
        }
      }
      // 确保有 keyword 参数
      if (Object.keys(params).length === 0) {
        params['keyword'] = '{keyword}'
      }
    } else {
      // URL 无参数，添加默认参数
      params['keyword'] = '{keyword}'
    }

    // 判断响应格式
    const response: SearchResponseConfig = {
      listPath: SourceManager.guessListPath(jsCode),
      songId: 'id',
      songIdStrip: '',
      songName: 'title',
      artist: 'artist',
      album: 'album',
      duration: 'duration',
      coverUrl: 'artwork',
      coverPrefix: '',
      coverSuffix: '',
      isPay: '',
    }

    return {
      url: urlObj.baseUrl,
      method: method,
      params: params,
      response: response,
    }
  }

  // 解析 URL 中的参数
  private static parseUrlParams(url: string): UrlParseResult {
    const qIndex = url.indexOf('?')
    if (qIndex < 0) {
      return { baseUrl: url, params: [] } as UrlParseResult
    }
    const baseUrl = url.substring(0, qIndex)
    const queryStr = url.substring(qIndex + 1)
    const params: ParamPair[] = []
    const pairs = queryStr.split('&')
    for (let i = 0; i < pairs.length; i++) {
      const eqIndex = pairs[i].indexOf('=')
      if (eqIndex > 0) {
        params.push({
          key: pairs[i].substring(0, eqIndex),
          value: pairs[i].substring(eqIndex + 1),
        } as ParamPair)
      }
    }
    return { baseUrl: baseUrl, params: params } as UrlParseResult
  }

  // 猜测响应数据的列表路径
  private static guessListPath(jsCode: string): string {
    // 常见路径模式
    const patterns = [
      'data.list', 'result.songs', 'data.songs', 'data.data',
      'data.result', 'result.data', 'data', 'result',
    ]
    for (let i = 0; i < patterns.length; i++) {
      const p = patterns[i]
      if (jsCode.indexOf(p) >= 0) {
        return p
      }
    }
    return 'data'
  }

  // 构建播放配置
  private static buildPlayConfig(playUrl: string): PlayConfig {
    const urlObj = SourceManager.parseUrlParams(playUrl)
    const params: Record<string, string> = new Object() as Record<string, string>

    if (urlObj.params.length > 0) {
      for (let i = 0; i < urlObj.params.length; i++) {
        const p = urlObj.params[i]
        if (p.key === 'id' || p.key === 'songId' || p.key === 'ids' || p.key === 'songid' || p.key === 'copyrightId' ||
            p.key === 'hash' || p.key === 'mid' || p.key === 'songmid' || p.key === 'sid') {
          params[p.key] = '{songId}'
        } else if (p.key === 'level' || p.key === 'quality' || p.key === 'type' || p.key === 'br' || p.key === 'format') {
          // 保留质量/格式参数的原值
          params[p.key] = p.value.length > 0 ? p.value : 'standard'
        } else {
          params[p.key] = p.value
        }
      }
    } else {
      params['id'] = '{songId}'
    }

    const response: PlayResponseConfig = {
      type: 'json',
      urlPath: 'url',
      codePath: 'code',
      successCode: '200',
      urlPrefix: '',
    }

    return {
      url: urlObj.baseUrl,
      method: 'GET',
      params: params,
      response: response,
    }
  }

  // 从订阅 URL 导入所有插件
  static async importFromSubscription(subscriptionUrl: string): Promise<ImportResult[]> {
    try {
      const subJson = await SourceManager.httpGet(subscriptionUrl)
      if (subJson.length === 0) {
        return [{ name: '订阅', success: false, error: '无法下载订阅文件' }] as ImportResult[]
      }
      return SourceManager.importFromSubscriptionJson(subJson)
    } catch (e) {
      console.error('[SourceManager] importFromSubscription failed:', e)
      return [{ name: '订阅', success: false, error: '订阅格式无效' }] as ImportResult[]
    }
  }

  // 从已下载的订阅 JSON 字符串导入
  static async importFromSubscriptionJson(subJson: string): Promise<ImportResult[]> {
    const results: ImportResult[] = []

    try {
      const sub = JSON.parse(subJson) as Record<string, Object>
      const plugins = sub['plugins'] as Object[] | undefined
      if (!(plugins instanceof Array) || plugins.length === 0) {
        return [{ name: '订阅', success: false, error: '订阅中没有找到插件' }] as ImportResult[]
      }

      // 遍历每个插件
      for (let i = 0; i < plugins.length; i++) {
        const plugin = plugins[i] as Record<string, Object>
        const name = String(plugin['name'] ?? '')
        const url = String(plugin['url'] ?? '')

        if (name.length === 0 || url.length === 0) continue

        try {
          console.info(`[SourceManager] Downloading plugin: ${name} from ${url}`)
          const content = await SourceManager.httpGet(url)
          if (content.length === 0) {
            results.push({ name: name, success: false, error: '下载失败' } as ImportResult)
            continue
          }

          const importedName = await SourceManager.autoDetectAndImport(content, name)
          if (importedName.length > 0) {
            results.push({ name: name, success: true } as ImportResult)
          } else {
            results.push({ name: name, success: false, error: '无法解析（加密API不支持自动转换）' } as ImportResult)
          }
        } catch (e) {
          results.push({ name: name, success: false, error: '解析异常' } as ImportResult)
        }
      }

      return results
    } catch (e) {
      console.error('[SourceManager] importFromSubscriptionJson failed:', e)
      return [{ name: '订阅', success: false, error: '订阅格式无效' }]
    }
  }
}
