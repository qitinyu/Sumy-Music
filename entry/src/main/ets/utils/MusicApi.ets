// MusicApi.ets - V1.0.9 鎻掍欢鍖栭煶婧愬紩鎿?// 鎵€鏈夐煶婧愰€氳繃 SourceManager 鎻掍欢绯荤粺鍔犺浇锛屼笉鍐嶅唴缃换浣曢煶婧?// 浠呬繚鐣欑綉鏄撲簯姝屽崟瀵煎叆浣滀负鐙珛鍔熻兘

import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import type { SongInfo } from '../model/MusicModel'
import { SourceManager } from './SourceManager'
import { SelfHostedApi } from './SelfHostedApi'

// ==================== HTTP 宸ュ叿鍑芥暟 ====================

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

async function httpGet(url: string, extraHeaders?: Record<string, string>, timeout?: number): Promise<string> {
  const t = timeout ?? 10000
  try {
    const headerObj: Record<string, string> = { 'User-Agent': UA }
    if (extraHeaders) {
      const keys = Object.keys(extraHeaders)
      for (let i = 0; i < keys.length; i++) {
        headerObj[keys[i]] = extraHeaders[keys[i]]
      }
    }
    const httpRequest = http.createHttp()
    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: headerObj,
      readTimeout: t,
      connectTimeout: t,
    } as http.HttpRequestOptions)
    httpRequest.destroy()
    const result = response.result
    if (typeof result === 'string') {
      return result
    }
    if (result instanceof ArrayBuffer) {
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
      return decoder.decodeWithStream(new Uint8Array(result))
    }
    return ''
  } catch (_e) {
    return ''
  }
}

function base64Decode(encoded: string): string {
  try {
    const helper = new util.Base64Helper()
    const uint8Array = helper.decodeSync(encoded)
    let result = ''
    for (let i = 0; i < uint8Array.length; i++) {
      result += String.fromCharCode(uint8Array[i])
    }
    return result
  } catch (_e) {
    return ''
  }
}

// ==================== 缃戞槗浜戞瓕鍗曞鍏ワ紙鐙珛鍔熻兘锛?====================

const WY_PLAYLIST_URL = 'https://music.163.com/api/v3/playlist/detail'

async function getWyPlaylistById(playlistId: string): Promise<SongInfo[]> {
  if (!playlistId || playlistId.length === 0) return []
  const url = `${WY_PLAYLIST_URL}?id=${playlistId}`
  const raw = await httpGet(url, {
    'Referer': 'https://music.163.com/',
    'Cookie': 'appver=2.0.0; os=pc; osver=windows',
  }, 10000)
  if (raw.length === 0) return []
  try {
    const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>
    const code = Number(parsed['code'] ?? -1)
    if (code !== 200) return []
    const playlistObj = parsed['playlist'] as Record<string, Object> | undefined
    if (!playlistObj) return []
    const trackIds = playlistObj['trackIds'] as Object[] | undefined
    if (!(trackIds instanceof Array) || trackIds.length === 0) return []
    const tracks = playlistObj['tracks'] as Object[] | undefined
    if (tracks instanceof Array && tracks.length > 0) {
      return parseWyTracks(tracks)
    }
    const results: SongInfo[] = []
    const batchSize = 100
    for (let i = 0; i < trackIds.length; i += batchSize) {
      const batch = trackIds.slice(i, i + batchSize)
      const ids = batch.map((t: Object) => String((t as Record<string, Object>)['id'] ?? '')).join(',')
      if (ids.length === 0) continue
      const detailUrl = `https://music.163.com/api/song/detail?ids=[${ids}]`
      const detailRaw = await httpGet(detailUrl, {
        'Referer': 'https://music.163.com/',
        'Cookie': 'appver=2.0.0',
      }, 10000)
      if (detailRaw.length > 0) {
        try {
          const detailParsed: Record<string, Object> = JSON.parse(detailRaw) as Record<string, Object>
          const songs = detailParsed['songs'] as Object[] | undefined
          if (songs instanceof Array) {
            for (let j = 0; j < songs.length; j++) {
              const song = parseWyTrackItem(songs[j] as Record<string, Object>)
              if (song) results.push(song)
            }
          }
        } catch (_e) {}
      }
    }
    return results
  } catch (_e) {
    return []
  }
}

function parseWyTrackItem(item: Record<string, Object>): SongInfo | null {
  const songId = String(item['id'] ?? '')
  const songName = String(item['name'] ?? '')
  if (!songId || !songName) return null
  const artists = item['artists'] as Object[] | undefined
  let artistName = ''
  if (artists instanceof Array) {
    const names: string[] = []
    for (let i = 0; i < artists.length; i++) {
      names.push(String((artists[i] as Record<string, Object>)['name'] ?? ''))
    }
    artistName = names.join('/')
  }
  const album = item['album'] as Record<string, Object> | undefined
  const albumName = album ? String(album['name'] ?? '') : ''
  let coverUrl = ''
  if (album) {
    const picUrl = album['picUrl'] as string | undefined
    if (picUrl && picUrl.length > 0) {
      coverUrl = picUrl
    }
  }
  const duration = Number(item['duration'] ?? 0) || 0
  const durSec = Math.floor(duration / 1000)
  return {
    songId: songId,
    songName: songName,
    artist: artistName,
    album: albumName,
    coverUrl: coverUrl,
    source: 'wy',
    playUrl: '',
    quality: `${Math.floor(durSec / 60)}:${Math.floor(durSec % 60)}`,
  }
}

function parseWyTracks(tracks: Object[]): SongInfo[] {
  const results: SongInfo[] = []
  for (let i = 0; i < tracks.length; i++) {
    const song = parseWyTrackItem(tracks[i] as Record<string, Object>)
    if (song) results.push(song)
  }
  return results
}

// ==================== MusicApi锛堟彃浠跺寲锛?====================

export class MusicApi {

  // 存储最后一次操作的错误信息，供 UI 层读取展示
  static lastError: string = ''

  static clearError(): void {
    MusicApi.lastError = ''
  }

  static async search(keyword: string, source: string = 'all'): Promise<SongInfo[]> {
    if (!keyword || keyword.trim().length === 0) return []
    MusicApi.clearError()

    // 自建API模式：优先使用 SelfHostedApi
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
          MusicApi.lastError = SelfHostedApi.lastError || '自建API返回0首歌曲，可能是服务端无匹配结果或接口路径不对'
        }
        console.info(`[MusicApi] Search "${keyword}" via self-hosted API => ${results.length} results`)
        return results
      } catch (_e) {
        MusicApi.lastError = '自建API搜索异常：' + String(_e)
        console.error('[MusicApi] ' + MusicApi.lastError)
        return []
      }
    }

    await SourceManager.ensureLoaded()

    try {
      if (source === 'all') {
        const results = await SourceManager.searchAll(keyword)
        if (results.length === 0) {
          MusicApi.lastError = '未找到歌曲：JSON源没有返回结果，请检查是否已导入音源插件'
        }
        console.info(`[MusicApi] Search "${keyword}" via plugins => ${results.length} results`)
        return results
      }
      const results = await SourceManager.search(source, keyword)
      if (results.length === 0) {
        MusicApi.lastError = `音源 "${source}" 未返回结果`
      }
      console.info(`[MusicApi] Search "${keyword}" via "${source}" => ${results.length} results`)
      return results
    } catch (_e) {
      MusicApi.lastError = '搜索失败：' + String(_e)
      console.error('[MusicApi] ' + MusicApi.lastError)
      return []
    }
  }

  static async getPlayUrl(songId: string, source: string, song?: SongInfo): Promise<string> {
    if (source === 'local') {
      return song?.playUrl ?? ''
    }

    // 自建API模式
    if (MusicApi.isSelfHostedMode()) {
      try {
        return await SelfHostedApi.getPlayUrl(songId, source)
      } catch (_e) {
        console.error('[MusicApi] self-hosted getPlayUrl failed')
        return ''
      }
    }

    await SourceManager.ensureLoaded()

    try {
      let sourceName = source
      if (source.startsWith('custom_')) {
        sourceName = source.substring(7)
      }

      const url = await SourceManager.getPlayUrl(sourceName, songId)
      if (url.length > 0) return url

      if (song) {
        const fallbackUrl = await SourceManager.getPlayUrlFromAny(songId, song.songName, song.artist)
        if (fallbackUrl.length > 0) return fallbackUrl
      }

      return ''
    } catch (_e) {
      console.error('[MusicApi] getPlayUrl failed')
      return ''
    }
  }

  static async getLyrics(songId: string, source: string, _song?: SongInfo): Promise<string> {
    // 自建API模式
    if (MusicApi.isSelfHostedMode()) {
      try {
        return await SelfHostedApi.getLyrics(songId, source)
      } catch (_e) {
        console.error('[MusicApi] self-hosted getLyrics failed')
        return ''
      }
    }

    await SourceManager.ensureLoaded()

    try {
      let sourceName = source
      if (source.startsWith('custom_')) {
        sourceName = source.substring(7)
      }
      return await SourceManager.getLyrics(sourceName, songId)
    } catch (_e) {
      console.error('[MusicApi] getLyrics failed')
      return ''
    }
  }

  static async getWyPlaylist(playlistId: string): Promise<SongInfo[]> {
    return await getWyPlaylistById(playlistId)
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
    // 尝试从 SourceManager 获取封面
    await SourceManager.ensureLoaded()
    try {
      // 如果歌曲有 coverUrl 但不是完整 URL，尝试补全
      if (song.coverUrl && song.coverUrl.length > 0) {
        return song.coverUrl
      }
      // 否则返回空，由调用方处理
      return ''
    } catch (_e) {
      return ''
    }
  }
}