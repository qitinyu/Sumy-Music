/**
 * CloudTagEnricher - 云端（WebDAV）歌曲内嵌标签增强器
 * 云端歌单只按文件名解析，从不读取音频文件的内嵌标签（歌名/歌手/封面/歌词）。
 * 此工具通过 HTTP Range 请求只下载文件头（512KB），手动解析 ID3v2/FLAC 标签，
 * 将内嵌的歌名/歌手/封面/歌词补全到歌曲对象上。
 */
import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import type { SongInfo } from '../model/MusicModel'
import { TagReader, EmbeddedTags } from './TagReader'
import { CoverFetcher } from './CoverFetcher'

const UA: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
const HEADER_BYTES: number = 512 * 1024

export class CloudTagEnricher {
  private static attempted: Set<string> = new Set()
  private static lyricCache: Map<string, string> = new Map()

  /** 会话内是否已尝试解析过该歌曲（无论成败，避免重复请求） */
  static isAttempted(songId: string): boolean {
    return CloudTagEnricher.attempted.has(songId)
  }

  /** 获取已解析的内嵌歌词（未解析过则返回空） */
  static getEmbeddedLyric(songId: string): string {
    const lrc: string | undefined = CloudTagEnricher.lyricCache.get(songId)
    return lrc === undefined ? '' : lrc
  }

  static clearMemoryCache(): void {
    CloudTagEnricher.attempted.clear()
    CloudTagEnricher.lyricCache.clear()
  }

  /** 确保尝试过内嵌标签解析（会话内仅一次），解析结果直接写回 song 对象 */
  static async ensureEnriched(song: SongInfo): Promise<void> {
    if (!song || song.source !== 'webdav' || !song.playUrl || song.playUrl.length === 0) {
      return
    }
    if (CloudTagEnricher.attempted.has(song.songId)) {
      return
    }
    CloudTagEnricher.attempted.add(song.songId)
    try {
      const bytes: Uint8Array | null = await CloudTagEnricher.fetchHeaderBytes(song.playUrl)
      if (!bytes) {
        return
      }
      const tags: EmbeddedTags | null = TagReader.readTagsFromBytes(bytes)
      if (!tags) {
        return
      }
      if (tags.title.length > 0) {
        song.songName = tags.title
      }
      if (tags.artist.length > 0) {
        song.artist = tags.artist
      }
      if (tags.coverBytes !== null && tags.coverBytes.length > 0) {
        const ext: string = tags.coverMime.includes('png') ? 'png' :
          (tags.coverMime.includes('webp') ? 'webp' : 'jpg')
        const path: string = await CoverFetcher.saveBytes('cloud_' + CloudTagEnricher.simpleHash(song.songId),
          tags.coverBytes, ext)
        if (path.length > 0) {
          song.coverUrl = path
        }
      }
      if (tags.lyric.length > 0) {
        CloudTagEnricher.lyricCache.set(song.songId, tags.lyric)
      }
      console.info(`[CloudTagEnricher] enriched: ${song.songName} (cover=${song.coverUrl.length > 0}, lyric=${tags.lyric.length > 0})`)
    } catch (_e) {
      // 单曲失败不影响其他歌曲
    }
  }

  /** Range 请求下载文件头（带 Basic Auth） */
  private static async fetchHeaderBytes(rawUrl: string): Promise<Uint8Array | null> {
    let url: string = rawUrl
    const headerObj: Record<string, string> = {
      'User-Agent': UA,
      'Range': `bytes=0-${HEADER_BYTES - 1}`,
    } as Record<string, string>
    const uiMatch: RegExpMatchArray | null = url.match(/^(https?:\/\/)([^/@]+)@/)
    if (uiMatch) {
      const ui: string = uiMatch[2]
      const idx: number = ui.indexOf(':')
      let user: string = idx >= 0 ? ui.substring(0, idx) : ui
      let pass: string = idx >= 0 ? ui.substring(idx + 1) : ''
      try {
        user = decodeURIComponent(user)
      } catch (_e) {
      }
      try {
        pass = decodeURIComponent(pass)
      } catch (_e) {
      }
      const encoder: util.TextEncoder = new util.TextEncoder()
      const helper: util.Base64Helper = new util.Base64Helper()
      headerObj['Authorization'] = 'Basic ' + helper.encodeToStringSync(encoder.encodeInto(user + ':' + pass))
      url = url.replace(/^(https?:\/\/)([^/@]+)@/, '$1')
    }
    const httpRequest = http.createHttp()
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: headerObj,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        readTimeout: 15000,
        connectTimeout: 15000,
      } as http.HttpRequestOptions)
      if (response.responseCode !== 200 && response.responseCode !== 206) {
        return null
      }
      const result = response.result
      if (result instanceof ArrayBuffer) {
        return new Uint8Array(result)
      }
      return null
    } catch (_e) {
      return null
    } finally {
      httpRequest.destroy()
    }
  }

  private static simpleHash(str: string): string {
    let hash: number = 0
    for (let i = 0; i < str.length; i++) {
      const char: number = str.charCodeAt(i)
      hash = ((hash << 5) - hash) + char
      hash = hash & hash
    }
    return Math.abs(hash).toString(16)
  }
}
