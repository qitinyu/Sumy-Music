// MusicApi.ets - V1.0.9 鎻掍欢鍖栭煶婧愬紩鎿?// 鎵€鏈夐煶婧愰€氳繃 SourceManager 鎻掍欢绯荤粺鍔犺浇锛屼笉鍐嶅唴缃换浣曢煶婧?// 浠呬繚鐣欑綉鏄撲簯姝屽崟瀵煎叆浣滀负鐙珛鍔熻兘

import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import type { SongInfo } from '../model/MusicModel'
import { SourceManager } from './SourceManager'
import { SelfHostedApi } from './SelfHostedApi'
import { CoverFetcher } from './CoverFetcher'

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
      return decoder.decodeToString(new Uint8Array(result))
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
    quality: `${Math.floor(durSec / 60)}:${(durSec % 60).toString().padStart(2, '0')}`,
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

  /** 最近一次操作的错误信息（搜索/取链/歌词失败时记录，供诊断） */
  static lastError: string = ''

  /**
   * 搜索串行链：同一时刻只允许一个搜索在插件引擎上执行。
   * 联想词搜索与正式搜索（或下拉刷新）并发跑在同一个引擎上会互相干扰，
   * 导致插件超时、主线程冻结（THREAD_BLOCK_6S）后被系统杀死。
   */
  private static searchQueue: Promise<void> = Promise.resolve()

  static search(keyword: string, source: string = 'all'): Promise<SongInfo[]> {
    if (!keyword || keyword.trim().length === 0) {
      return Promise.resolve([])
    }
    // 排队等待上一个搜索结束后再执行
    const task: Promise<SongInfo[]> = MusicApi.searchQueue.then(
      (): Promise<SongInfo[]> => MusicApi.runSearch(keyword, source)
    )
    MusicApi.searchQueue = task.then((): void => {}, (): void => {})
    return task
  }

  private static async runSearch(keyword: string, source: string): Promise<SongInfo[]> {
    await SourceManager.ensureLoaded()

    try {
      if (source === 'all') {
        const results = await SourceManager.searchAll(keyword)
        console.info(`[MusicApi] Search "${keyword}" via plugins => ${results.length} results`)
        if (results.length === 0) {
          MusicApi.lastError = `搜索无结果(${keyword})`
        }
        return results
      }
      const results = await SourceManager.search(source, keyword)
      console.info(`[MusicApi] Search "${keyword}" via "${source}" => ${results.length} results`)
      if (results.length === 0) {
        MusicApi.lastError = `搜索无结果(${keyword}) source=${source}`
      }
      return results
    } catch (_e) {
      console.error('[MusicApi] search failed', _e)
      MusicApi.lastError = `搜索异常: ${String(_e)}`
      return []
    }
  }

  /** 取链总超时兜底标记（真实 URL 不会包含 NUL 字符，不会误判） */
  private static readonly URL_TIMEOUT_SENTINEL: string = String.fromCharCode(0) + 'URL_TIMEOUT'

  /**
   * 取链总超时：直接取链失败后的全网回退（逐源搜索+验证）最坏可达数分钟，
   * 期间界面无任何反馈，表现为“点了没反应”。超过 20s 按取链失败处理。
   */
  static async getPlayUrl(songId: string, source: string, song?: SongInfo, fastTest?: boolean): Promise<string> {
    if (source === 'local') {
      return song?.playUrl ?? ''
    }
    const result: string = await Promise.race([
      MusicApi.runGetPlayUrl(songId, source, song),
      new Promise<string>((resolve) => {
        setTimeout((): void => {
          resolve(MusicApi.URL_TIMEOUT_SENTINEL)
        }, 20000)
      })
    ])
    if (result === MusicApi.URL_TIMEOUT_SENTINEL) {
      MusicApi.lastError = '取链超时(20s)，已放弃等待'
      console.warn('[MusicApi] getPlayUrl total timeout: songId=' + songId + ' source=' + source)
      return ''
    }
    return result
  }

  private static async runGetPlayUrl(songId: string, source: string, song?: SongInfo): Promise<string> {
    await SourceManager.ensureLoaded()

    try {
      let sourceName = source
      if (source.startsWith('custom_')) {
        sourceName = source.substring(7)
      }

      // 必须携带 song：v3/MF/json_source 引擎取链都依赖歌曲信息，缺参会直接返回 ''，
      // 导致每次播放都落入耗时的全网回退（逐源搜索+验证），期间界面无任何反馈
      const url = await SourceManager.getPlayUrl(sourceName, songId, song)
      if (url.length > 0) {
        MusicApi.lastError = ''
        return url
      }

      // V2.1.9 自动换源开关（设置-播放器-播放设置，默认开启）：
      // 关闭后不再全网换源取链，原源取链失败直接返回空，由上层"自动跳过"处理
      if (song && AppStorage.get<boolean>('autoSourceSwitch') !== false) {
        const fallbackUrl = await SourceManager.getPlayUrlFromAny(songId, song.songName, song.artist)
        if (fallbackUrl.length > 0) {
          MusicApi.lastError = ''
          return fallbackUrl
        }
      }

      MusicApi.lastError = '取链失败无可用链接'
      return ''
    } catch (_e) {
      console.error('[MusicApi] getPlayUrl failed', _e)
      MusicApi.lastError = `取链异常: ${String(_e)}`
      return ''
    }
  }

  static async getLyrics(songId: string, source: string, _song?: SongInfo, fastTest?: boolean): Promise<string> {
    await SourceManager.ensureLoaded()

    try {
      let sourceName = source
      if (source.startsWith('custom_')) {
        sourceName = source.substring(7)
      }
      const raw = await SourceManager.getLyrics(sourceName, songId, _song?.songName, _song?.artist, _song)
      MusicApi.lastError = ''
      return raw
    } catch (_e) {
      console.error('[MusicApi] getLyrics failed', _e)
      MusicApi.lastError = `歌词获取异常: ${String(_e)}`
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
    if (!song.coverUrl || song.coverUrl.length === 0) {
      return ''
    }
    return await CoverFetcher.resolve(song.coverUrl)
  }
}