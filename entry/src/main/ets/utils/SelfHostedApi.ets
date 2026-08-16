import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import type { SongInfo } from '../model/MusicModel'
import { SourceInfo } from '../model/MusicModel'
import { CompatUtils } from './CompatUtils'

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

const API_SOURCES: string[] = ['netease', 'qq', 'kugou', 'kuwo', 'migu']

export class SelfHostedApi {
  private static baseUrl: string = ''
  // 存储最后一次错误信息，供 UI 层读取
  static lastError: string = ''

  static setBaseUrl(url: string): void {
    SelfHostedApi.baseUrl = url
  }

  static getBaseUrl(): string {
    return SelfHostedApi.baseUrl
  }

  static getAvailableSources(): string[] {
    return API_SOURCES
  }

  static getDisplayName(source: string): string {
    const info = SourceInfo.MAP[source]
    return info?.name ?? source
  }

  static getColor(source: string): string {
    const info = SourceInfo.MAP[source]
    return info?.color ?? '#999999'
  }

  static async testConnection(url: string): Promise<boolean> {
    try {
      if (!url || url.trim().length === 0) return false
      const testUrl = `${url.replace(/\/+$/, '')}/api/v1/music/search?q=test&source=netease`
      const raw = await SelfHostedApi.httpGet(testUrl)
      if (raw.length === 0) return false
      const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>
      return Number(parsed['code'] ?? 0) === 200
    } catch (_e) {
      return false
    }
  }

  static async search(keyword: string, source: string): Promise<SongInfo[]> {
    if (!keyword || keyword.trim().length === 0) return []
    SelfHostedApi.lastError = ''

    console.info(`[SelfHostedApi] search start: keyword="${keyword}", source=${source}, baseUrl="${SelfHostedApi.baseUrl}"`)

    if (!SelfHostedApi.baseUrl || SelfHostedApi.baseUrl.length === 0) {
      SelfHostedApi.lastError = 'API地址为空，未调用setBaseUrl'
      console.error('[SelfHostedApi] ' + SelfHostedApi.lastError)
      return []
    }

    try {
      if (source === 'all') {
        const allResults: SongInfo[] = []
        const errors: string[] = []
        for (let i = 0; i < API_SOURCES.length; i++) {
          try {
            const songs = await SelfHostedApi.searchSingle(API_SOURCES[i], keyword)
            console.info(`[SelfHostedApi] ${API_SOURCES[i]} => ${songs.length} results`)
            for (let j = 0; j < songs.length; j++) {
              allResults.push(songs[j])
            }
          } catch (_e) {
            console.warn(`[SelfHostedApi] ${API_SOURCES[i]} search error`)
            errors.push(API_SOURCES[i])
            continue
          }
        }
        if (allResults.length === 0) {
          if (errors.length === API_SOURCES.length) {
            SelfHostedApi.lastError = `全部${errors.length}个音源均搜索失败，请检查API服务是否正常`
          } else if (SelfHostedApi.lastError.length > 0) {
            // 保留 searchSingle 已设置的 lastError
          } else {
            SelfHostedApi.lastError = '所有音源均返回0首歌曲，可能是API服务端无匹配或接口路径不正确'
          }
        }
        console.info(`[SelfHostedApi] all sources total => ${allResults.length} results`)
        return allResults
      }
      const singleResults = await SelfHostedApi.searchSingle(source, keyword)
      if (singleResults.length === 0 && !SelfHostedApi.lastError) {
        SelfHostedApi.lastError = `音源 ${source} 返回0首歌曲`
      }
      return singleResults
    } catch (_e) {
      SelfHostedApi.lastError = '搜索异常：' + String(_e)
      console.error('[SelfHostedApi] ' + SelfHostedApi.lastError)
      return []
    }
  }

  private static async searchSingle(source: string, keyword: string): Promise<SongInfo[]> {
    try {
      const url = `${SelfHostedApi.baseUrl}/api/v1/music/search?q=${encodeURIComponent(keyword)}&source=${source}`
      console.info(`[SelfHostedApi] GET ${url}`)
      const raw = await SelfHostedApi.httpGet(url)
      if (raw.length === 0) {
        SelfHostedApi.lastError = `${source}: 网络请求无响应，可能API地址不可达或网络超时`
        console.warn(`[SelfHostedApi] ` + SelfHostedApi.lastError)
        return []
      }

      const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>
      const code = Number(parsed['code'] ?? 0)
      if (code !== 200) {
        const msg = String(parsed['msg'] ?? parsed['message'] ?? '')
        SelfHostedApi.lastError = `${source}: API返回错误码 ${code}${msg.length > 0 ? '，' + msg : ''}，请检查API接口路径`
        console.warn(`[SelfHostedApi] ` + SelfHostedApi.lastError)
        return []
      }

      const data = parsed['data'] as Record<string, Object> | undefined
      if (!data) {
        SelfHostedApi.lastError = `${source}: 返回数据缺少 data 字段，API响应格式可能不兼容`
        return []
      }

      const songs = data['songs'] as Object[] | undefined
      if (!(songs instanceof Array)) {
        SelfHostedApi.lastError = `${source}: 返回数据缺少 data.songs 数组，API响应格式可能不兼容`
        return []
      }

      const results: SongInfo[] = []
      for (let i = 0; i < songs.length; i++) {
        const item = songs[i] as Record<string, Object>
        const id = String(item['id'] ?? '')
        const name = String(item['name'] ?? '')
        if (!id || !name) continue

        const durNum = Number(item['duration'] ?? 0)
        const durSec = Math.floor(durNum)
        const durFormatted = `${Math.floor(durSec / 60)}:${(durSec % 60).toString().padStart(2, '0')}`

        let coverUrl = String(item['cover'] ?? '')
        if (coverUrl.startsWith('//')) {
          coverUrl = 'https:' + coverUrl
        }

        results.push({
          songId: id,
          songName: name,
          artist: String(item['artist'] ?? ''),
          album: String(item['album'] ?? ''),
          coverUrl: coverUrl,
          source: String(item['source'] ?? source),
          playUrl: '',
          quality: durFormatted,
        })
      }
      return results
    } catch (_e) {
      return []
    }
  }

  static async getPlayUrl(songId: string, source: string): Promise<string> {
    try {
      const url = `${SelfHostedApi.baseUrl}/api/v1/music/url?id=${encodeURIComponent(songId)}&source=${source}`
      const raw = await SelfHostedApi.httpGet(url)
      if (raw.length === 0) return ''

      const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>
      const code = Number(parsed['code'] ?? 0)
      if (code !== 200) return ''

      const data = parsed['data'] as Record<string, Object> | undefined
      if (!data) return ''

      return String(data['url'] ?? '')
    } catch (_e) {
      return ''
    }
  }

  static async getLyrics(songId: string, source: string): Promise<string> {
    try {
      const url = `${SelfHostedApi.baseUrl}/api/v1/music/lyric?id=${encodeURIComponent(songId)}&source=${source}`
      const raw = await SelfHostedApi.httpGet(url)
      if (raw.length === 0) return ''

      const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>
      const code = Number(parsed['code'] ?? 0)
      if (code !== 200) return ''

      const data = parsed['data'] as Record<string, Object> | undefined
      if (!data) return ''

      return String(data['lyric'] ?? '')
    } catch (_e) {
      return ''
    }
  }

  private static async httpGet(url: string): Promise<string> {
    try {
      const httpRequest = http.createHttp()
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': UA } as Record<string, string>,
        readTimeout: 15000,
        connectTimeout: 10000,
        // V2.1.0：请求原始字节，避免 http 模块默认按 UTF-8 预解码导致 GBK 歌词乱码
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
      } as http.HttpRequestOptions)
      const code = response.responseCode
      httpRequest.destroy()
      const result = response.result
      if (typeof result === 'string') {
        if (code !== 200) {
          console.warn(`[SelfHostedApi] HTTP ${code}: ${url}`)
        }
        return result
      }
      const bytes: Uint8Array = result instanceof ArrayBuffer ? new Uint8Array(result) : result as Uint8Array
      const contentType: string = String((response.header as Record<string, Object>)['Content-Type'] ?? '')
      const text = CompatUtils.decodeResponse(bytes, contentType)
      if (code !== 200) {
        console.warn(`[SelfHostedApi] HTTP ${code}: ${url}`)
      }
      return text
    } catch (e) {
      console.error(`[SelfHostedApi] httpGet failed: ${url}`, e)
      return ''
    }
  }
}
