import avSession from '@ohos.multimedia.avsession'
import image from '@ohos.multimedia.image'
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

  async setSongMetadata(song: SongInfo, durationMs: number = 0): Promise<void> {
    if (!this.session) return
    try {
      await this.session.activate()
      let mediaImage: image.PixelMap | string = ''
      if (song.coverUrl && song.coverUrl.length > 0) {
        try {
          mediaImage = await this.loadCoverImage(song.coverUrl)
        } catch (_e) {
          mediaImage = ''
        }
      }
      const metadata: avSession.AVMetadata = {
        assetId: song.songId,
        title: song.songName,
        artist: song.artist || '',
        album: song.album || '',
        duration: durationMs,
        mediaImage: mediaImage
      }
      await this.session.setAVMetadata(metadata)
      console.info('[BackgroundHelper] AVMetadata set:', song.songName)
    } catch (e) {
      console.error('[BackgroundHelper] setAVMetadata failed:', e)
    }
  }

  private async loadCoverImage(coverUrl: string): Promise<image.PixelMap | string> {
    if (!coverUrl) return ''
    try {
      if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://')) {
        const httpRequest = http.createHttp()
        const response = await httpRequest.request(coverUrl, { method: http.RequestMethod.GET, expectDataType: http.HttpDataType.ARRAY_BUFFER })
        httpRequest.destroy()
        if (response.responseCode === 200 && response.result as ArrayBuffer) {
          const imageSource = image.createImageSource(response.result as ArrayBuffer)
          const pixelMap = await imageSource.createPixelMap()
          imageSource.release()
          return pixelMap
        }
      }
      return coverUrl
    } catch (e) {
      console.error('[BackgroundHelper] loadCoverImage failed:', e)
      return ''
    }
  }

  async setPlaybackState(isPlaying: boolean, positionMs: number = 0, speed: number = 1.0, durationMs: number = 0): Promise<void> {
    if (!this.session) return
    try {
      this.currentPositionMs = positionMs
      const state: avSession.AVPlaybackState = {
        state: isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
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
      const state: avSession.AVPlaybackState = {
        state: avSession.PlaybackState.PLAYBACK_STATE_PLAY,
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
