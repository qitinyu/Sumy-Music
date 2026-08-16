import avSession from '@ohos.multimedia.avsession'
import { fileIo } from '@kit.CoreFileKit'
import type { SongInfo } from '../model/MusicModel'
import { http } from '@kit.NetworkKit'
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'
import wantAgent, { WantAgent } from '@ohos.app.ability.wantAgent'
import { Want, common } from '@kit.AbilityKit'

const SESSION_TAG: string = 'SHMY_MUSIC'

export interface SessionCommandListener {
  onPlay?: () => void
  onPause?: () => void
  onStop?: () => void
  onPlayNext?: () => void
  onPlayPrevious?: () => void
  onSeek?: (positionMs: number) => void
}

export class BackgroundHelper {
  private static instance: BackgroundHelper | null = null
  private session: avSession.AVSession | null = null
  private context: Context | null = null
  private commandListener: SessionCommandListener | null = null
  private currentPositionMs: number = 0
  private isBackgroundRunning: boolean = false
  private wantAgentObj: WantAgent | null = null
  // 记录最后一次下发的播放状态，供 updatePosition 使用，避免覆盖控制中心图标
  private currentPlaybackState: number = avSession.PlaybackState.PLAYBACK_STATE_STOP

  static getInstance(): BackgroundHelper {
    if (!BackgroundHelper.instance) {
      BackgroundHelper.instance = new BackgroundHelper()
    }
    return BackgroundHelper.instance
  }

  setCommandListener(listener: SessionCommandListener): void {
    this.commandListener = listener
  }

  async init(context: Context): Promise<void> {
    this.context = context
    console.info('[BackgroundHelper] init start')
    await this.createSession()
    await this.createWantAgent()
    console.info('[BackgroundHelper] init done')
  }

  private async createWantAgent(): Promise<void> {
    if (!this.context) return
    try {
      const abilityCtx = this.context as common.UIAbilityContext
      const bundleName: string = abilityCtx.abilityInfo.bundleName
      const abilityName: string = abilityCtx.abilityInfo.name
      const wants: Want[] = [
        {
          bundleName: bundleName,
          abilityName: abilityName
        }
      ]
      const agentInfo: wantAgent.WantAgentInfo = {
        wants: wants,
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      }
      this.wantAgentObj = await wantAgent.getWantAgent(agentInfo)
      console.info('[BackgroundHelper] WantAgent created for', bundleName)
    } catch (e) {
      console.error('[BackgroundHelper] createWantAgent failed:', e)
    }
  }

  private async createSession(): Promise<void> {
    if (!this.context) return
    try {
      this.session = await avSession.createAVSession(this.context, SESSION_TAG, 'audio')
      console.info('[BackgroundHelper] AVSession created')

      this.session.on('play', () => {
        console.info('[BackgroundHelper] AVSession play command')
        this.commandListener?.onPlay?.()
      })

      this.session.on('pause', () => {
        console.info('[BackgroundHelper] AVSession pause command')
        this.commandListener?.onPause?.()
      })

      this.session.on('stop', () => {
        console.info('[BackgroundHelper] AVSession stop command')
        this.commandListener?.onStop?.()
      })

      this.session.on('playNext', () => {
        console.info('[BackgroundHelper] AVSession playNext command')
        this.commandListener?.onPlayNext?.()
      })

      this.session.on('playPrevious', () => {
        console.info('[BackgroundHelper] AVSession playPrevious command')
        this.commandListener?.onPlayPrevious?.()
      })

      this.session.on('seek', (positionMs: number) => {
        console.info('[BackgroundHelper] AVSession seek command:', positionMs)
        this.currentPositionMs = positionMs
        this.commandListener?.onSeek?.(positionMs)
      })

      await this.session.activate()
      console.info('[BackgroundHelper] AVSession activated')
    } catch (e) {
      console.error('[BackgroundHelper] create AVSession failed:', e)
    }
  }

  // 记录最后一次请求的歌曲，供异步封面加载完成后校验，避免慢封面覆盖新歌曲
  private latestSongId: string = ''

  async setSongMetadata(song: SongInfo, durationMs: number = 0): Promise<void> {
    if (!this.session) return
    this.latestSongId = song.songId
    try {
      await this.session.activate()
      // 先立即上报文本信息（标题/歌手/专辑），切歌时控制中心秒级切换，不等封面下载
      await this.session.setAVMetadata({
        assetId: song.songId,
        title: song.songName,
        artist: song.artist || '',
        album: song.album || '',
        duration: durationMs
      })
      console.info('[BackgroundHelper] AVMetadata text set:', song.songName)
      // 封面异步补充上报；加载失败不影响文本，期间若已切歌则丢弃过期封面
      if (song.coverUrl && song.coverUrl.length > 0) {
        try {
          const mediaImage = await this.loadCoverImage(song.coverUrl)
          if (this.latestSongId !== song.songId) return
          if (mediaImage) {
            await this.session.setAVMetadata({
              assetId: song.songId,
              title: song.songName,
              artist: song.artist || '',
              album: song.album || '',
              duration: durationMs,
              mediaImage: mediaImage
            })
            console.info('[BackgroundHelper] AVMetadata cover set:', song.songName)
          }
        } catch (_e) {
          console.error('[BackgroundHelper] cover load failed:', song.songName)
        }
      }
    } catch (e) {
      console.error('[BackgroundHelper] setAVMetadata failed:', e)
    }
  }

  // 下载封面并返回本地 file:// URI（带缓存）。
  // 直接传 PixelMap 需要跨进程共享内存（ashmem），在部分设备上会失败导致控制中心/通知栏封面不显示；
  // 传本地文件 URI 由系统自行读取，更稳定且切歌时无需重复下载。
  private async loadCoverImage(coverUrl: string): Promise<string> {
    if (!coverUrl) return ''
    try {
      // 本地文件封面直接返回原 URI
      if (!coverUrl.startsWith('http://') && !coverUrl.startsWith('https://')) {
        return coverUrl
      }
      if (!this.context) return ''
      // V2.1.3：存 filesDir 防止系统清理 cacheDir 导致封面失效
      const coverDir: string = `${this.context.filesDir}/covers`
      const filePath: string = `${coverDir}/cover_${this.simpleHash(coverUrl)}.jpg`
      // 命中缓存直接返回
      try {
        if (await fileIo.access(filePath)) {
          return `file://${filePath}`
        }
      } catch (_e) {
        // 文件不存在或不可访问，继续下载
      }
      const httpRequest = http.createHttp()
      const response = await httpRequest.request(coverUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      })
      httpRequest.destroy()
      if (response.responseCode === 200 && response.result as ArrayBuffer) {
        try {
          await fileIo.mkdir(coverDir, true)
        } catch (_e) {
          // 目录已存在等情况忽略
        }
        // TRUNC 截断写入，避免覆盖旧文件残留尾部字节导致图片损坏
        const file = await fileIo.open(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
        try {
          await fileIo.write(file.fd, response.result as ArrayBuffer)
        } finally {
          fileIo.close(file)
        }
        return `file://${filePath}`
      }
      return ''
    } catch (e) {
      console.error('[BackgroundHelper] loadCoverImage failed:', e)
      return ''
    }
  }

  private simpleHash(str: string): string {
    let hash: number = 0
    for (let i = 0; i < str.length; i++) {
      const char: number = str.charCodeAt(i)
      hash = ((hash << 5) - hash) + char
      hash = hash & hash
    }
    return Math.abs(hash).toString(16)
  }

  async setPlaybackState(isPlaying: boolean, positionMs: number = 0, speed: number = 1.0, durationMs: number = 0): Promise<void> {
    if (!this.session) return
    try {
      this.currentPositionMs = positionMs
      const newState: number = isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE
      this.currentPlaybackState = newState
      const state: avSession.AVPlaybackState = {
        state: newState,
        position: {
          elapsedTime: positionMs,
          updateTime: Date.now()
        },
        speed: speed,
        duration: durationMs
      }
      await this.session.setAVPlaybackState(state)
      console.info('[BackgroundHelper] Playback state set:', isPlaying, 'position:', positionMs)
    } catch (e) {
      console.error('[BackgroundHelper] setAVPlaybackState failed:', e)
    }
  }

  async updatePosition(positionMs: number): Promise<void> {
    if (!this.session) return
    try {
      this.currentPositionMs = positionMs
      // 保持当前播放状态，不要强制写成 PLAY，否则暂停瞬间会覆盖控制中心图标导致死锁
      const state: avSession.AVPlaybackState = {
        state: this.currentPlaybackState,
        position: {
          elapsedTime: positionMs,
          updateTime: Date.now()
        },
        speed: 1.0
      }
      await this.session.setAVPlaybackState(state)
    } catch (e) {
      console.error('[BackgroundHelper] updatePosition failed:', e)
    }
  }

  async release(): Promise<void> {
    await this.stopBackgroundRunning()
    if (this.session) {
      try {
        this.session.off('play')
        this.session.off('pause')
        this.session.off('stop')
        this.session.off('playNext')
        this.session.off('playPrevious')
        this.session.off('seek')
        await this.session.destroy()
      } catch (_e) {}
      this.session = null
    }
  }

  async startBackgroundRunning(): Promise<void> {
    console.info('[BackgroundHelper] startBackgroundRunning called, isBackgroundRunning:', this.isBackgroundRunning, 'wantAgentObj:', this.wantAgentObj !== null)
    if (!this.context || this.isBackgroundRunning || !this.wantAgentObj) return
    try {
      await backgroundTaskManager.startBackgroundRunning(this.context, backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, this.wantAgentObj)
      this.isBackgroundRunning = true
      console.info('[BackgroundHelper] Background running started for audio playback')
    } catch (e) {
      console.error('[BackgroundHelper] Start background running failed:', e)
    }
  }

  async stopBackgroundRunning(): Promise<void> {
    if (!this.context || !this.isBackgroundRunning) return
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context)
      this.isBackgroundRunning = false
      console.info('[BackgroundHelper] Background running stopped')
    } catch (e) {
      console.error('[BackgroundHelper] Stop background running failed:', e)
    }
  }
}
