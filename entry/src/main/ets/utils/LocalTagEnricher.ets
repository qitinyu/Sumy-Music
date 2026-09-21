/**
 * LocalTagEnricher - 本地音乐网络补全器
 * 本地歌曲只有内嵌标签（部分歌曲连标签都没有，封面/歌词全空）。
 * 当封面或歌词缺失时，用已导入音源/自建API按「歌名+歌手」联网搜索匹配曲目，
 * 把网络封面下载到本地缓存、网络歌词补到歌曲对象并持久化到本地音乐表。
 * - 全程异步、不阻塞播放；会话内每首歌仅尝试一次，失败不重试。
 * - 绝不改动本地歌曲的播放路径与来源标记。
 */
import type { SongInfo } from '../model/MusicModel'
import { MusicApi } from './MusicApi'
import { CoverFetcher } from './CoverFetcher'
import { DatabaseHelper } from '../database/DatabaseHelper'

const SEARCH_LIMIT: number = 10

export class LocalTagEnricher {
  private static attempted: Set<string> = new Set()
  private static lyricCache: Map<string, string> = new Map()
  private static coverCache: Map<string, string> = new Map()

  /** 「封面/歌词自动补全」开关（设置-播放器，默认关闭）。关闭时不做任何联网补全。 */
  static isAutoEnrichEnabled(): boolean {
    const val: Object | undefined = AppStorage.get('autoEnrichTags')
    return typeof val === 'boolean' ? val : false
  }

  /** 会话内是否已尝试过该歌曲（无论成败，避免重复联网） */
  static isAttempted(playUrl: string): boolean {
    return LocalTagEnricher.attempted.has(playUrl)
  }

  /** 取已补全的网络歌词（未尝试过则返回空） */
  static getOnlineLyric(playUrl: string): string {
    const lrc: string | undefined = LocalTagEnricher.lyricCache.get(playUrl)
    return lrc === undefined ? '' : lrc
  }

  /** 取已补全的网络封面（未尝试过则返回空） */
  static getOnlineCover(playUrl: string): string {
    const cover: string | undefined = LocalTagEnricher.coverCache.get(playUrl)
    return cover === undefined ? '' : cover
  }

  static clearMemoryCache(): void {
    LocalTagEnricher.attempted.clear()
    LocalTagEnricher.lyricCache.clear()
    LocalTagEnricher.coverCache.clear()
  }

  /**
   * 补全本地歌曲缺失的封面与歌词（会话内仅一次）。
   * 直接写回 song 对象（coverUrl/lyric），并持久化到本地音乐表。
   */
  static async ensureEnriched(song: SongInfo): Promise<void> {
    if (!song || song.source !== 'local' || !song.playUrl || song.playUrl.length === 0) {
      return
    }
    // 用户未在「设置-播放器」开启自动补全时，不联网（内嵌标签仍可用）
    if (!LocalTagEnricher.isAutoEnrichEnabled()) {
      return
    }
    const key: string = song.playUrl
    const needLyric: boolean = !song.lyric || song.lyric.length === 0
    const needCover: boolean = !song.coverUrl || song.coverUrl.length === 0
    if (!needLyric && !needCover) {
      return
    }
    if (LocalTagEnricher.attempted.has(key)) {
      // 之前已搜过：把缓存结果补回歌曲对象（例如列表页先搜过、播放页再打开）
      if (needLyric) {
        const lrc: string = LocalTagEnricher.getOnlineLyric(key)
        if (lrc.length > 0) song.lyric = lrc
      }
      if (needCover) {
        const cover: string = LocalTagEnricher.getOnlineCover(key)
        if (cover.length > 0) song.coverUrl = cover
      }
      return
    }
    LocalTagEnricher.attempted.add(key)
    if (!song.songName || song.songName.trim().length === 0) {
      return
    }
    const keyword: string = LocalTagEnricher.buildKeyword(song.songName, song.artist)
    if (keyword.length === 0) {
      return
    }
    let candidates: SongInfo[] = []
    try {
      candidates = await MusicApi.search(keyword, 'all')
    } catch (_e) {
      candidates = []
    }
    const match: SongInfo | null = LocalTagEnricher.findBestMatch(song, candidates)
    if (match === null) {
      return
    }
    let changed: boolean = false
    if (needLyric) {
      try {
        const lrc: string = await MusicApi.getLyrics(match.songId, match.source, match)
        if (lrc.length > 0) {
          LocalTagEnricher.lyricCache.set(key, lrc)
          song.lyric = lrc
          changed = true
        }
      } catch (_e) {
        // 单项失败不影响封面补全
      }
    }
    if (needCover && match.coverUrl && match.coverUrl.length > 0) {
      try {
        const localPath: string = await CoverFetcher.downloadToCache(match.coverUrl)
        if (localPath.length > 0) {
          LocalTagEnricher.coverCache.set(key, localPath)
          song.coverUrl = localPath
          changed = true
        }
      } catch (_e) {
      }
    }
    if (changed) {
      LocalTagEnricher.persist(song)
      // 强制刷新播放页封面（@StorageProp 对象属性变更不会自动触发重渲染）
      const playing: SongInfo | undefined = AppStorage.get<SongInfo>('currentTrack')
      if (playing && playing.playUrl === key) {
        AppStorage.setOrCreate<SongInfo>('currentTrack', song)
      }
    }
  }

  /**
   * 仅补歌词，返回可用歌词（内嵌优先，网络补全其次）。
   * 注意：即使内嵌歌词已存在，仍需走 ensureEnriched —— 封面可能缺失，
   * 提前 return 会导致「有歌词但无封面」的歌曲永远不补封面。
   */
  static async ensureLyric(song: SongInfo): Promise<string> {
    if (!song || song.source !== 'local') {
      return song?.lyric ?? ''
    }
    await LocalTagEnricher.ensureEnriched(song)
    return song.lyric ?? ''
  }

  /** 搜索关键词：歌名为主，歌手为辅（歌手与歌名重复时只取歌名） */
  private static buildKeyword(songName: string, artist?: string): string {
    const name: string = (songName ?? '').replace(/\s+/g, ' ').trim()
    if (name.length === 0) {
      return ''
    }
    const singer: string = (artist ?? '').replace(/\s+/g, ' ').trim()
    if (singer.length === 0 || name.indexOf(singer) >= 0 || singer.indexOf(name) >= 0) {
      return name
    }
    return name + ' ' + singer
  }

  /** 从搜索结果中找最可能是同一首歌的候选（标题归一化后一致，且歌手能对上） */
  private static findBestMatch(target: SongInfo, candidates: SongInfo[]): SongInfo | null {
    const tName: string = LocalTagEnricher.normalizeTitle(target.songName)
    const tArtist: string = LocalTagEnricher.normalizeText(target.artist)
    if (tName.length === 0) {
      return null
    }
    const limit: number = Math.min(candidates.length, SEARCH_LIMIT)
    for (let i = 0; i < limit; i++) {
      const c: SongInfo = candidates[i]
      const cName: string = LocalTagEnricher.normalizeTitle(c.songName)
      if (cName.length === 0) {
        continue
      }
      const nameMatch: boolean = tName === cName || tName.indexOf(cName) >= 0 || cName.indexOf(tName) >= 0
      if (!nameMatch) {
        continue
      }
      const cArtist: string = LocalTagEnricher.normalizeText(c.artist)
      if (tArtist.length === 0 || cArtist.length === 0) {
        return c
      }
      if (tArtist.indexOf(cArtist) >= 0 || cArtist.indexOf(tArtist) >= 0) {
        return c
      }
    }
    return null
  }

  private static normalizeTitle(value: string): string {
    return LocalTagEnricher.normalizeText(value)
      .replace(/\([^)]*\)/g, '')
      .replace(/（[^）]*）/g, '')
      .replace(/\[[^\]]*\]/g, '')
      .replace(/【[^】]*】/g, '')
      .replace(/\s+/g, '')
  }

  private static normalizeText(value: string): string {
    return (value ?? '')
      .toLowerCase()
      .replace(/\s+/g, ' ')
      .replace(/^\s+|\s+$/g, '')
  }

  /** 异步落库：只更新封面与歌词两列，不动歌名/歌手/播放路径 */
  private static persist(song: SongInfo): void {
    const filePath: string = song.playUrl
    const coverUrl: string = song.coverUrl ?? ''
    const lyric: string = song.lyric ?? ''
    DatabaseHelper.getInstance().updateLocalMusicMeta(filePath, coverUrl, lyric).catch((_e: Object) => {
      console.warn('[LocalTagEnricher] persist failed')
    })
  }
}
