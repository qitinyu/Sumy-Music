// PlayerStore.ets - 全局播放器状态管理
// 使用 AppStorage 实现跨组件状态共享
import type { SongInfo, LyricLine } from '../model/MusicModel'
import { MusicApi } from './MusicApi'
import { LocalTagEnricher } from './LocalTagEnricher'

// 播放器状态 Key 常量
export class PlayerKeys {
  static readonly CURRENT_TRACK: string = 'currentTrack'
  static readonly IS_PLAYING: string = 'isPlaying'
  static readonly CURRENT_TIME: string = 'currentTime'
  static readonly DURATION: string = 'duration'
  static readonly VOLUME: string = 'volume'
  static readonly QUEUE: string = 'queue'
  static readonly QUEUE_INDEX: string = 'queueIndex'
  static readonly LYRICS: string = 'lyrics'
  static readonly LYRICS_RAW: string = 'lyricsRaw'
  static readonly SHOW_FULL_PLAYER: string = 'showFullPlayer'
  static readonly FULL_PLAYER_PAGE: string = 'fullPlayerPage'
  static readonly PLAY_MODE: string = 'playMode'
  // playMode: 0 = 列表循环, 1 = 随机播放, 2 = 单曲循环
}

// 安全获取 AppStorage 中的 boolean 值
function getStorageBool(key: string): boolean {
  const val: Object | undefined = AppStorage.get(key)
  if (typeof val === 'boolean') {
    return val
  }
  return false
}

// 安全获取 AppStorage 中的 number 值
function getStorageNum(key: string): number {
  const val: Object | undefined = AppStorage.get(key)
  if (typeof val === 'number') {
    return val
  }
  return 0
}

export class PlayerStore {

  // 播放指定曲目并设置队列
  static play(track: SongInfo, queue?: SongInfo[], queueIndex?: number): void {
    AppStorage.setOrCreate(PlayerKeys.CURRENT_TRACK, track)
    AppStorage.setOrCreate(PlayerKeys.IS_PLAYING, true)
    if (queue !== undefined) {
      AppStorage.setOrCreate(PlayerKeys.QUEUE, queue)
      AppStorage.setOrCreate(PlayerKeys.QUEUE_INDEX, queueIndex ?? 0)
    }
    // V2.1.1：切歌即清空旧歌词并异步加载新歌词（迷你栏/桌面歌词实时跟随）
    AppStorage.setOrCreate(PlayerKeys.LYRICS, [])
    AppStorage.setOrCreate(PlayerKeys.LYRICS_RAW, '')
    PlayerStore.loadLyricsAsync(track)
    // V2.1.6：切歌统一补全 WebDAV 授权封面（所有切歌路径生效：搜索页/迷你栏/播放页/自动下一首）
    PlayerStore.ensureCoverAsync(track)
  }

  // 异步加载当前曲目歌词（带切歌竞态保护）
  static async loadLyricsAsync(track: SongInfo): Promise<void> {
    if (!track) {
      return
    }
    let raw: string = ''
    // 本地音乐：内嵌歌词优先，缺失时按歌名+歌手联网补全（迷你栏/桌面歌词同样受益）
    if (track.source === 'local') {
      try {
        raw = await LocalTagEnricher.ensureLyric(track)
      } catch (_e) {
        raw = ''
      }
    } else if (track.lyric && track.lyric.length > 0) {
      raw = track.lyric
    } else {
      try {
        raw = await MusicApi.getLyrics(track.songId, track.source, track)
      } catch (_e) {
        raw = ''
      }
    }
    // 竞态保护：期间已切歌则丢弃结果
    const now: SongInfo | undefined = PlayerStore.getCurrentTrack()
    if (!now || now.songId !== track.songId || now.source !== track.source) {
      return
    }
    if (raw && raw.length > 0) {
      const parsed: LyricLine[] = PlayerStore.parseLrc(raw)
      if (parsed.length > 0) {
        PlayerStore.setLyrics(parsed, raw)
      }
    }
  }

  // V2.1.6：切歌统一补全 WebDAV 授权封面（user:pass@ 的 http URL 系统组件无法直显），
  // 解析为本地 file:// 后刷新当前曲目，背景取色/列表封面同步受益
  static ensureCoverAsync(track: SongInfo): void {
    const cover: string = track.coverUrl
    if (cover.length === 0 || cover.indexOf('@') < 0 || cover.indexOf('://') < 0) {
      return
    }
    if (!cover.startsWith('http://') && !cover.startsWith('https://')) {
      return
    }
    MusicApi.fetchCoverFromOnline(track).then((resolved: string) => {
      if (resolved.length === 0 || resolved === cover) {
        return
      }
      // 期间已切歌则丢弃，避免污染新歌封面
      const now: SongInfo | undefined = PlayerStore.getCurrentTrack()
      if (now && now.songId === track.songId && now.source === track.source) {
        track.coverUrl = resolved
        PlayerStore.refreshCurrentTrack(track)
      }
    }).catch((_e: Error) => {
    })
  }

  // 暂停
  static pause(): void {
    AppStorage.setOrCreate(PlayerKeys.IS_PLAYING, false)
  }

  // 恢复
  static resume(): void {
    AppStorage.setOrCreate(PlayerKeys.IS_PLAYING, true)
  }

  // 切换播放/暂停
  static togglePlay(): void {
    const playing = getStorageBool(PlayerKeys.IS_PLAYING)
    AppStorage.setOrCreate(PlayerKeys.IS_PLAYING, !playing)
  }

  // 下一首 - 返回新曲目以便调用方播放
  static next(): SongInfo | undefined {
    const queue = AppStorage.get(PlayerKeys.QUEUE) as SongInfo[]
    const index = getStorageNum(PlayerKeys.QUEUE_INDEX)
    if (!queue || queue.length === 0) return undefined
    const playMode = PlayerStore.getPlayMode()
    let nextIndex = index
    if (playMode === 2) {
      // 单曲循环：保持当前索引
      nextIndex = index
    } else if (playMode === 1) {
      // 随机播放
      if (queue.length === 1) {
        nextIndex = 0
      } else {
        do {
          nextIndex = Math.floor(Math.random() * queue.length)
        } while (nextIndex === index)
      }
    } else {
      // 列表循环
      nextIndex = index + 1
      if (nextIndex >= queue.length) {
        nextIndex = 0
      }
    }
    AppStorage.setOrCreate(PlayerKeys.QUEUE_INDEX, nextIndex)
    const track = queue[nextIndex]
    if (track) {
      AppStorage.setOrCreate(PlayerKeys.CURRENT_TRACK, track)
      AppStorage.setOrCreate(PlayerKeys.IS_PLAYING, true)
    }
    return track
  }

  // 上一首 - 返回新曲目以便调用方播放
  static previous(): SongInfo | undefined {
    const queue = AppStorage.get(PlayerKeys.QUEUE) as SongInfo[]
    const index = getStorageNum(PlayerKeys.QUEUE_INDEX)
    if (!queue || queue.length === 0) return undefined
    // 直接切到列表上一首（循环到末尾）
    let prevIndex = index - 1
    if (prevIndex < 0) {
      prevIndex = queue.length - 1
    }
    AppStorage.setOrCreate(PlayerKeys.QUEUE_INDEX, prevIndex)
    const track = queue[prevIndex]
    if (track) {
      AppStorage.setOrCreate(PlayerKeys.CURRENT_TRACK, track)
      AppStorage.setOrCreate(PlayerKeys.IS_PLAYING, true)
    }
    return track
  }

  // 更新当前时间
  static updateTime(time: number): void {
    AppStorage.setOrCreate(PlayerKeys.CURRENT_TIME, time)
  }

  // 更新总时长
  static updateDuration(duration: number): void {
    AppStorage.setOrCreate(PlayerKeys.DURATION, duration)
  }

  // 设置队列
  static setQueue(tracks: SongInfo[]): void {
    AppStorage.setOrCreate(PlayerKeys.QUEUE, tracks)
    AppStorage.setOrCreate(PlayerKeys.QUEUE_INDEX, 0)
  }

  // 添加到队列末尾（稍后播放）
  static addToQueue(track: SongInfo): void {
    const queue = AppStorage.get(PlayerKeys.QUEUE) as SongInfo[]
    if (queue) {
      const newQueue: SongInfo[] = queue.slice()
      newQueue.push(track)
      AppStorage.setOrCreate(PlayerKeys.QUEUE, newQueue)
    } else {
      // 队列为空，创建新队列并设为当前播放
      AppStorage.setOrCreate(PlayerKeys.QUEUE, [track])
    }
  }

  // 插入到下一首播放（当前曲目之后）
  static insertNext(track: SongInfo): void {
    const queue = AppStorage.get(PlayerKeys.QUEUE) as SongInfo[]
    const index = getStorageNum(PlayerKeys.QUEUE_INDEX)
    if (queue && queue.length > 0) {
      const newQueue: SongInfo[] = queue.slice()
      newQueue.splice(index + 1, 0, track)
      AppStorage.setOrCreate(PlayerKeys.QUEUE, newQueue)
    } else {
      // 队列为空，创建新队列
      AppStorage.setOrCreate(PlayerKeys.QUEUE, [track])
    }
  }

  // 设置歌词
  static setLyrics(lyrics: LyricLine[], raw: string): void {
    AppStorage.setOrCreate(PlayerKeys.LYRICS, lyrics)
    AppStorage.setOrCreate(PlayerKeys.LYRICS_RAW, raw)
  }

  // 显示完整播放器
  static showFullPlayer(): void {
    AppStorage.setOrCreate(PlayerKeys.SHOW_FULL_PLAYER, true)
  }

  // 隐藏完整播放器
  static hideFullPlayer(): void {
    AppStorage.setOrCreate(PlayerKeys.SHOW_FULL_PLAYER, false)
  }

  // 切换播放器页面
  static setFullPlayerPage(page: string): void {
    AppStorage.setOrCreate(PlayerKeys.FULL_PLAYER_PAGE, page)
  }

  // 获取当前曲目
  static getCurrentTrack(): SongInfo | undefined {
    return AppStorage.get(PlayerKeys.CURRENT_TRACK) as SongInfo | undefined
  }

  // 刷新当前曲目（用于封面等字段异步更新后通知 UI）
  static refreshCurrentTrack(track: SongInfo): void {
    const current = AppStorage.get(PlayerKeys.CURRENT_TRACK) as SongInfo | undefined
    // 仅当传入的还是当前曲目时才刷新，避免切歌后旧回调污染
    if (current && current.songId === track.songId && current.source === track.source) {
      // 复制为新对象引用，确保 AppStorage 观察者收到变更（否则原地改字段不会触发 UI 刷新）
      try {
        const clone: SongInfo = JSON.parse(JSON.stringify(track)) as SongInfo
        AppStorage.setOrCreate(PlayerKeys.CURRENT_TRACK, clone)
      } catch (_e) {
        AppStorage.setOrCreate(PlayerKeys.CURRENT_TRACK, track)
      }
    }
  }

  // 获取队列
  static getQueue(): SongInfo[] {
    const queue = AppStorage.get(PlayerKeys.QUEUE) as SongInfo[]
    return queue ?? []
  }

  // 获取当前队列索引
  static getQueueIndex(): number {
    return getStorageNum(PlayerKeys.QUEUE_INDEX)
  }

  // 获取歌词
  static getLyrics(): LyricLine[] {
    const lyrics = AppStorage.get(PlayerKeys.LYRICS) as LyricLine[]
    return lyrics ?? []
  }

  // 播放模式
  static getPlayMode(): number {
    return getStorageNum(PlayerKeys.PLAY_MODE)
  }

  static setPlayMode(mode: number): void {
    AppStorage.setOrCreate(PlayerKeys.PLAY_MODE, mode)
  }

  static togglePlayMode(): number {
    const mode = PlayerStore.getPlayMode()
    const nextMode = (mode + 1) % 3
    AppStorage.setOrCreate(PlayerKeys.PLAY_MODE, nextMode)
    return nextMode
  }

  static getPlayModeLabel(): string {
    const mode = PlayerStore.getPlayMode()
    switch (mode) {
      case 0: return '顺序播放'
      case 1: return '随机播放'
      case 2: return '单曲循环'
      default: return '列表循环'
    }
  }

  static getPlayModeIcon(): Resource {
    const mode = PlayerStore.getPlayMode()
    switch (mode) {
      case 0: return $r('sys.symbol.repeat')
      case 1: return $r('sys.symbol.shuffle')
      case 2: return $r('sys.symbol.repeat_1')
      default: return $r('sys.symbol.repeat')
    }
  }

  // 歌曲播放结束 - 自动播下一首
  static onTrackEnd(): SongInfo | undefined {
    return PlayerStore.next()
  }

  // 解析 LRC 歌词
  static parseLrc(raw: string): LyricLine[] {
    if (!raw || raw.length === 0) return []
    const lines = raw.split('\n')
    const result: LyricLine[] = []

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i]
      // 支持多时间标签格式: [00:12.34][00:12.345]歌词
      const timeRegex = /\[(\d{1,2}):(\d{2})\.(\d{2,3})\]/g
      const timeMatches: number[] = []
      let match: RegExpExecArray | null = null
      while ((match = timeRegex.exec(line)) !== null) {
        const min = parseInt(match[1])
        const sec = parseInt(match[2])
        const ms = parseInt(match[3].padEnd(3, '0'))
        const time = min * 60 + sec + ms / 1000
        timeMatches.push(time)
      }
      // 提取歌词文本（去掉所有时间标签）
      const text = line.replace(/\[\d{1,2}:\d{2}\.\d{2,3}\]/g, '').trim()
      if (text.length > 0 && timeMatches.length > 0) {
        for (let j = 0; j < timeMatches.length; j++) {
          result.push({ time: timeMatches[j], text: text })
        }
      }
    }
    result.sort((a: LyricLine, b: LyricLine) => a.time - b.time)
    return result
  }
}