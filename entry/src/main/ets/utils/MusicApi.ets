// MusicApi.ets - V3.0 纯插件引擎音源接口（上架合规：无任何内置平台直连）
// 搜索/播放/歌词/封面全部由用户导入的 JS 插件提供（v1 / v3 / MusicFree 格式），
// 或走用户自建 API 模式。应用本体不内置任何音乐平台接口。

import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import type { SongInfo } from '../model/MusicModel'
import { SourceManager } from './SourceManager'
import { SelfHostedApi } from './SelfHostedApi'
import { JsPluginEngine } from './JsPluginEngine'
import { CompatUtils } from './CompatUtils'
import { CoverFetcher } from './CoverFetcher'
import { CloudTagEnricher } from './CloudTagEnricher'

// ===== 导入新引擎 (123 引擎) =====
import { lxEngineIsReady } from '../source/LXSourceEngine';
import { getLXMusicUrl } from '../source/LXPlayHelper';

// ==================== HTTP 工具函数 ====================

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

async function fetchUrlTextWithAuth(rawUrl: string): Promise<string> {
  let url: string = rawUrl
  let authHeader: string = ''
  const uiMatch: RegExpMatchArray | null = url.match(/^(https?:\/\/)([^/@]+)@/)
  if (uiMatch) {
    const ui: string = uiMatch[2]
    const idx: number = ui.indexOf(':')
    let user: string = idx >= 0 ? ui.substring(0, idx) : ui
    let pass: string = idx >= 0 ? ui.substring(idx + 1) : ''
    try {
      user = decodeURIComponent(user)
    } catch (_e) {}
    try {
      pass = decodeURIComponent(pass)
    } catch (_e) {}
    const encoder: util.TextEncoder = new util.TextEncoder()
    const helper: util.Base64Helper = new util.Base64Helper()
    authHeader = 'Basic ' + helper.encodeToStringSync(encoder.encodeInto(user + ':' + pass))
    url = url.replace(/^(https?:\/\/)([^/@]+)@/, '$1')
  }
  const headerObj: Record<string, string> = { 'User-Agent': UA } as Record<string, string>
  if (authHeader.length > 0) {
    headerObj['Authorization'] = authHeader
  }
  const httpRequest = http.createHttp()
  try {
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: headerObj,
      readTimeout: 10000,
      connectTimeout: 10000,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
    } as http.HttpRequestOptions)
    const result = response.result
    if (typeof result === 'string') {
      return result
    }
    if (result instanceof ArrayBuffer) {
      const contentType: string = String((response.header as Record<string, Object>)['Content-Type'] ?? '')
      return CompatUtils.decodeResponse(new Uint8Array(result), contentType)
    }
    return ''
  } catch (_e) {
    return ''
  } finally {
    httpRequest.destroy()
  }
}

// ==================== MusicApi（纯插件引擎：新引擎 v3 + 旧引擎 v1/MusicFree + 自建API） ====================

export class MusicApi {

  static lastError: string = ''

  static clearError(): void {
    MusicApi.lastError = ''
  }

  /** 将插件名/平台码解析为已导入的插件名 */
  private static resolvePluginName(source: string): string {
    const names: string[] = SourceManager.getSourceNames()
    const kwMap: Record<string, string[]> = {
      'kw': ['kuwo', '酷我'],
      'kg': ['kugou', '酷狗'],
      'tx': ['qq', 'QQ', '腾讯'],
      'wy': ['netease', '网易', '163'],
      'mg': ['migu', '咪咕'],
    }
    const keywords: string[] = kwMap[source] || [source]
    for (let i = 0; i < names.length; i++) {
      const n: string = names[i]
      for (let j = 0; j < keywords.length; j++) {
        if (n.indexOf(keywords[j]) >= 0) {
          return n
        }
      }
    }
    return source
  }

  static async search(keyword: string, source: string = 'all'): Promise<SongInfo[]> {
    if (!keyword || keyword.trim().length === 0) return []
    MusicApi.clearError()

    if (MusicApi.isSelfHostedMode()) {
      const url = MusicApi._selfHostedUrl
      if (!url || url.length === 0) {
        MusicApi.lastError = '自建API地址为空，请在设置中填写API地址'
        console.error('[MusicApi] ' + MusicApi.lastError)
        return []
      }
      try {
        const results = await SelfHostedApi.search(keyword, source)
        if (results.length === 0) {
          MusicApi.lastError = SelfHostedApi.lastError || '自建API返回0首歌曲'
        }
        console.info(`[MusicApi] Search "${keyword}" via self-hosted API => ${results.length} results`)
        return results
      } catch (_e) {
        MusicApi.lastError = '自建API搜索异常：' + String(_e)
        console.error('[MusicApi] ' + MusicApi.lastError)
        return []
      }
    }

    // ---- 插件引擎搜索（v1/MusicFree 插件经 JsPluginEngine，v3 插件无 musicSearch 自动跳过） ----
    await SourceManager.ensureLoaded()
    try {
      if (source === 'all' || source === '') {
        const results = await SourceManager.searchAll(keyword)
        if (results.length === 0) {
          if (JsPluginEngine.lastError.length > 0) {
            MusicApi.lastError = JsPluginEngine.lastError
          } else if (!lxEngineIsReady) {
            MusicApi.lastError = '音源引擎未就绪，请检查是否已导入音源插件'
          } else {
            MusicApi.lastError = '未找到歌曲：请先导入并启用音源插件'
          }
        }
        console.info(`[MusicApi] Search "${keyword}" via plugins => ${results.length} results`)
        return results
      }
      const sourceName = MusicApi.resolvePluginName(source)
      const results = await SourceManager.search(sourceName, keyword)
      if (results.length === 0) {
        if (JsPluginEngine.lastError.length > 0) {
          MusicApi.lastError = JsPluginEngine.lastError
        } else {
          MusicApi.lastError = `音源 "${source}" 未返回结果`
        }
      }
      console.info(`[MusicApi] Search "${keyword}" via "${sourceName}" => ${results.length} results`)
      return results
    } catch (_e) {
      MusicApi.lastError = '搜索失败：' + String(_e)
      console.error('[MusicApi] ' + MusicApi.lastError)
      return []
    }
  }

  /** 归一化播放源名：custom_ 前缀剥离 + 平台码映射插件名（兼容旧收藏数据） */
  private static normalizeSourceForPlugin(source: string): string {
    if (source.startsWith('custom_')) {
      return source.substring(7)
    }
    // 平台码（旧收藏/歌单数据）映射到对应插件名
    if (['kw', 'kg', 'tx', 'wy', 'mg'].indexOf(source) >= 0) {
      return MusicApi.resolvePluginName(source)
    }
    return source
  }

  static async getPlayUrl(songId: string, source: string, song?: SongInfo): Promise<string> {
    if (source === 'local' || source === 'webdav') {
      return song?.playUrl ?? ''
    }

    if (MusicApi.isSelfHostedMode()) {
      try {
        return await SelfHostedApi.getPlayUrl(songId, source)
      } catch (_e) {
        console.error('[MusicApi] self-hosted getPlayUrl failed')
        return ''
      }
    }

    // 平台码归一化（供新引擎按平台取链；inferPlatform 支持中文别名：酷狗→kg 等）
    const platform = SourceManager.inferPlatform(source)
    const name = song?.songName || ''
    const singer = song?.artist || ''

    // ---- 新引擎优先（v3 插件，如全豆要；平台码 kw/kg/tx/wy/mg 直接命中） ----
    if (lxEngineIsReady) {
      try {
        const quality = '128k'
        console.info(`[MusicApi] 新引擎获取链接: platform=${platform}, songId=${songId}`)
        const url = await getLXMusicUrl(platform, songId, quality, name, singer)
        if (url && url.length > 0) {
          console.info(`[MusicApi] 新引擎返回链接: ${url.substring(0, 80)}`)
          return url
        }
      } catch (e) {
        console.warn('[MusicApi] 新引擎获取链接失败，回退旧引擎:', e)
        MusicApi.lastError = '新引擎失败：' + String(e)
      }
    }

    // ---- 插件自身取链（v1/MusicFree 经 JsPluginEngine，v3 经引擎按插件名分发） ----
    await SourceManager.ensureLoaded()
    try {
      let sourceName = MusicApi.normalizeSourceForPlugin(source)
      const url = await SourceManager.getPlayUrl(sourceName, songId, song)
      if (url.length > 0) return url

      if (song) {
        const fallbackUrl = await SourceManager.getPlayUrlFromAny(songId, song.songName, song.artist, song)
        if (fallbackUrl.length > 0) return fallbackUrl
      }
      return ''
    } catch (_e) {
      console.error('[MusicApi] 旧引擎 getPlayUrl 失败')
      return ''
    }
  }

  static async getLyrics(songId: string, source: string, song?: SongInfo): Promise<string> {
    if (source === 'webdav') {
      const embedded: string = CloudTagEnricher.getEmbeddedLyric(songId)
      if (embedded.length > 0) return embedded
      if (song && !CloudTagEnricher.isAttempted(songId)) {
        await CloudTagEnricher.ensureEnriched(song)
        const embedded2: string = CloudTagEnricher.getEmbeddedLyric(songId)
        if (embedded2.length > 0) return embedded2
      }
      if (song && song.lyricUrl && song.lyricUrl.length > 0) {
        const lrc = await MusicApi.fetchUrlText(song.lyricUrl)
        if (lrc.length > 0) return lrc
      }
      return ''
    }

    if (source === 'local') {
      return song?.lyric ?? ''
    }

    if (MusicApi.isSelfHostedMode()) {
      try {
        return await SelfHostedApi.getLyrics(songId, source)
      } catch (_e) {
        console.error('[MusicApi] self-hosted getLyrics failed')
        return ''
      }
    }

    // ---- 插件歌词（v1/MusicFree 经 JsPluginEngine，v3 经引擎按插件名分发） ----
    await SourceManager.ensureLoaded()
    try {
      let sourceName = MusicApi.normalizeSourceForPlugin(source)
      const lrc = await SourceManager.getLyrics(sourceName, songId, song?.songName, song?.artist, song)
      if (lrc.length > 0) return lrc

      const otherNames: string[] = await SourceManager.getEnabledSourceNames()
      for (let i = 0; i < otherNames.length; i++) {
        if (otherNames[i] === sourceName) continue
        const fallbackLrc = await SourceManager.getLyrics(otherNames[i], songId, song?.songName, song?.artist, song)
        if (fallbackLrc.length > 0) {
          console.info(`[MusicApi] lyrics fallback: ${sourceName} -> ${otherNames[i]}`)
          return fallbackLrc
        }
      }
      return ''
    } catch (_e) {
      console.error('[MusicApi] 插件 getLyrics 失败')
      return ''
    }
  }

  // ==================== 自建 API 模式 ====================
  private static _isSelfHostedMode: boolean = false
  private static _selfHostedUrl: string = ''

  static isSelfHostedMode(): boolean {
    return MusicApi._isSelfHostedMode
  }

  static setSelfHostedMode(enabled: boolean, url: string): void {
    MusicApi._isSelfHostedMode = enabled
    MusicApi._selfHostedUrl = url
    SelfHostedApi.setBaseUrl(url)
  }

  static async fetchCoverFromOnline(song: SongInfo): Promise<string> {
    if (!song.coverUrl || song.coverUrl.length === 0) {
      return ''
    }
    // 仅做 URL 解析（WebDAV 内嵌账号的封面下载为本地文件），不涉及任何平台直连
    return await CoverFetcher.resolve(song.coverUrl)
  }

  static async fetchUrlText(url: string): Promise<string> {
    return await fetchUrlTextWithAuth(url)
  }
}
