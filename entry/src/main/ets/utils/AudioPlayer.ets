import { media } from '@kit.MediaKit'
import { fileIo } from '@kit.CoreFileKit'
import image from '@ohos.multimedia.image'
import type { SongInfo } from '../model/MusicModel'
import { NotificationHelper } from './NotificationHelper'
import { BackgroundHelper } from './BackgroundHelper'
import { PlayerStore } from './PlayerStore'

export interface AudioMetadata {
  title: string
  artist: string
  album: string
  duration: number
}

export class AudioPlayer {
  private static instance: AudioPlayer | null = null
  private avPlayer: media.AVPlayer | null = null
  private currentUrl: string = ''
  private currentFd: number = -1
  private _isPlaying: boolean = false
  private _isPrepared: boolean = false
  private currentSong: SongInfo | null = null
  private notificationHelper: NotificationHelper = NotificationHelper.getInstance()
  private bgHelper: BackgroundHelper = BackgroundHelper.getInstance()
  private _duration: number = 0
  private _currentTime: number = 0
  private _positionUpdateTimer: number = -1
  onTimeUpdate?: (time: number) => void
  onDurationUpdate?: (duration: number) => void
  onPlayEnd?: () => void
  onError?: (error: string) => void
  // 🆕 seek 完成回调
  onSeekDone?: (time: number) => void

  static getInstance(): AudioPlayer {
    if (!AudioPlayer.instance) {
      AudioPlayer.instance = new AudioPlayer()
    }
    return AudioPlayer.instance
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

  // 初始化播放器
  private async initPlayer(): Promise<boolean> {
    try {
      this.avPlayer = await media.createAVPlayer()
      this._isPrepared = false
      this.setupListeners()
      this.setupSessionCommands()
      console.info('[AudioPlayer] AVPlayer created')
      return true
    } catch (e) {
      console.error('[AudioPlayer] create failed:', e)
      this.onError?.('播放器初始化失败')
      return false
    }
  }

  // 注册播控中心命令监听
  private setupSessionCommands(): void {
    this.bgHelper.setCommandListener({
      onPlay: () => {
        console.info('[AudioPlayer] Session command: play')
        this.resume()
      },
      onPause: () => {
        console.info('[AudioPlayer] Session command: pause')
        this.pause()
      },
      onStop: () => {
        console.info('[AudioPlayer] Session command: stop')
        this.stop()
      },
      onPlayNext: () => {
        console.info('[AudioPlayer] Session command: playNext')
        this.onPlayEnd?.()
      },
      onPlayPrevious: () => {
        console.info('[AudioPlayer] Session command: playPrevious')
        this.onPlayEnd?.()
      },
      onSeek: (positionMs: number) => {
        console.info('[AudioPlayer] Session command: seek', positionMs)
        this.seekTo(positionMs / 1000)
      }
    })
  }

  // 等待播放器进入指定状态
  private async waitForState(targetState: string, timeoutMs: number = 8000): Promise<boolean> {
    if (!this.avPlayer) {
      return false
    }
    const start = Date.now()
    while (Date.now() - start < timeoutMs) {
      if (this.avPlayer.state === targetState) {
        return true
      }
      await new Promise<void>(resolve => setTimeout(resolve, 50))
    }
    console.warn(`[AudioPlayer] waitForState('${targetState}') timed out, current state: ${this.avPlayer.state}`)
    return false
  }

  // 设置事件监听
  private setupListeners(): void {
    if (!this.avPlayer) {
      return
    }

    this.avPlayer.on('timeUpdate', (time: number) => {
      this._currentTime = time / 1000
      this.onTimeUpdate?.(this._currentTime)
    })

    this.avPlayer.on('durationUpdate', (duration: number) => {
      this._duration = duration / 1000
      this.onDurationUpdate?.(this._duration)
    })

    this.avPlayer.on('error', (err) => {
      console.error('[AudioPlayer] error event:', JSON.stringify(err))
      this._isPlaying = false
      this._isPrepared = false
      this.stopPositionUpdateTimer()
      this.onError?.('播放出错')
    })

    // 监听播放器状态变化 —— 播放结束时触发 onPlayEnd，由上层决定是否继续播放下一首
    this.avPlayer.on('stateChange', (state: string, reason: media.StateChangeReason) => {
      console.info('[AudioPlayer] stateChange: ' + state + ', reason: ' + reason)
      if (state === 'completed') {
        this._isPlaying = false
        this.stopPositionUpdateTimer()
        this.onPlayEnd?.()
      }
    })

    // 🆕 监听 seekDone，seek 完成后通知 UI 解锁进度条
    this.avPlayer.on('seekDone', (seekDoneTime: number) => {
      const seekTimeSec = seekDoneTime / 1000
      console.info(`[AudioPlayer] seekDone: ${seekDoneTime}ms → ${seekTimeSec}s`)
      this._currentTime = seekTimeSec
      this.onSeekDone?.(seekTimeSec)
    })
  }

  // 启动进度更新定时器
  private startPositionUpdateTimer(): void {
    this.stopPositionUpdateTimer()
    this._positionUpdateTimer = setInterval(() => {
      if (this._isPlaying && this._currentTime > 0) {
        this.bgHelper.updatePosition(this._currentTime * 1000).catch(() => {
        })
      }
    }, 5000)
  }

  // 停止进度更新定时器
  private stopPositionUpdateTimer(): void {
    if (this._positionUpdateTimer >= 0) {
      clearInterval(this._positionUpdateTimer)
      this._positionUpdateTimer = -1
    }
  }

  // 关闭已打开的本地文件 fd
  private closeCurrentFd(): void {
    if (this.currentFd >= 0) {
      try {
        fileIo.closeSync(this.currentFd)
      } catch (_e) {
        // ignore
      }
      this.currentFd = -1
    }
  }

  private resolveUrl(url: string): string {
    if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('fd://')) {
      return url
    }
    let openUri = url
    if (openUri.startsWith('file://')) {
      openUri = openUri.slice(7)
    }
    if (!openUri.startsWith('/') && !openUri.startsWith('content://')) {
      openUri = '/' + openUri
    }
    console.info('[AudioPlayer] resolveUrl: trying to open:', openUri)
    try {
      const file = fileIo.openSync(openUri, fileIo.OpenMode.READ_ONLY)
      this.currentFd = file.fd
      console.info('[AudioPlayer] local file opened successfully, fd:', file.fd)
      return `fd://${file.fd}`
    } catch (e) {
      console.error('[AudioPlayer] open local file failed:', openUri, e)
      return ''
    }
  }

  static async copyToSandbox(uri: string, context: Context): Promise<string> {
    let srcFd: number = -1
    let dstFd: number = -1
    try {
      const filesDir = context.filesDir
      const musicDir: string = filesDir + '/music/'
      try {
        fileIo.mkdirSync(musicDir)
      } catch (_e) {
      }

      const hash: string = AudioPlayer.simpleHash(uri)
      let extMatch: RegExpMatchArray | null = uri.match(/\.(\w+)(?:\?|$)/)
      if (!extMatch) {
        extMatch = uri.match(/\.(\w+)$/)
      }
      const ext: string = extMatch ? '.' + extMatch[1].toLowerCase() : '.mp3'
      const destPath: string = musicDir + hash + ext

      if (fileIo.accessSync(destPath)) {
        console.info('[AudioPlayer] copyToSandbox: file already exists:', destPath)
        return 'file://' + destPath
      }

      let openUri = uri
      if (openUri.startsWith('file://')) {
        openUri = openUri.slice(7)
      }

      const srcFile = fileIo.openSync(openUri, fileIo.OpenMode.READ_ONLY)
      srcFd = srcFile.fd
      const stat: fileIo.Stat = fileIo.statSync(srcFd)
      const buf: ArrayBuffer = new ArrayBuffer(stat.size)
      fileIo.readSync(srcFd, buf)

      const dstFile =
        fileIo.openSync(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
      dstFd = dstFile.fd
      fileIo.writeSync(dstFd, buf)

      console.info('[AudioPlayer] copyToSandbox: copied to:', destPath)
      return 'file://' + destPath
    } catch (e) {
      console.error('[AudioPlayer] copyToSandbox failed:', uri, e)
      return uri
    } finally {
      if (srcFd >= 0) {
        try {
          fileIo.closeSync(srcFd)
        } catch (_e) {
        }
      }
      if (dstFd >= 0) {
        try {
          fileIo.closeSync(dstFd)
        } catch (_e) {
        }
      }
    }
  }

  static async extractMetadata(filePath: string): Promise<AudioMetadata> {
    const defaultResult: AudioMetadata = {
      title: '',
      artist: '',
      album: '',
      duration: 0
    }
    let extractor: media.AVMetadataExtractor | null = null
    let fd: number = -1
    try {
      let openUri = filePath
      if (openUri.startsWith('file://')) {
        openUri = openUri.slice(7)
      }
      const file = fileIo.openSync(openUri, fileIo.OpenMode.READ_ONLY)
      fd = file.fd
      const stat: fileIo.Stat = fileIo.statSync(fd)
      extractor = await media.createAVMetadataExtractor()
      extractor.fdSrc = { fd: fd, offset: 0, length: stat.size }
      const metadata: media.AVMetadata = await extractor.fetchMetadata()
      let durationMs = 0
      if (metadata.duration) {
        durationMs = parseInt(metadata.duration as string, 10) || 0
      }
      const result: AudioMetadata = {
        title: (metadata.title as string) || '',
        artist: (metadata.artist as string) || '',
        album: (metadata.album as string) || '',
        duration: durationMs
      }
      return result
    } catch (e) {
      console.error('[AudioPlayer] extractMetadata failed:', e)
      return defaultResult
    } finally {
      if (fd >= 0) {
        try {
          fileIo.closeSync(fd)
        } catch (_e) {
        }
      }
      if (extractor) {
        try {
          await extractor.release()
        } catch (_e) {
        }
      }
    }
  }

  static async extractCoverFromAudio(filePath: string): Promise<string> {
    let extractor: media.AVMetadataExtractor | null = null
    let fd: number = -1
    try {
      let openUri = filePath
      if (openUri.startsWith('file://')) {
        openUri = openUri.slice(7)
      }
      const file = fileIo.openSync(openUri, fileIo.OpenMode.READ_ONLY)
      fd = file.fd
      const stat: fileIo.Stat = fileIo.statSync(fd)
      extractor = await media.createAVMetadataExtractor()
      extractor.fdSrc = { fd: fd, offset: 0, length: stat.size }
      const coverPixelMap: image.PixelMap = await extractor.fetchAlbumCover()
      fileIo.closeSync(fd)
      fd = -1
      const imagePacker: image.ImagePacker = await image.createImagePacker()
      const arrayBuffer: ArrayBuffer =
        await imagePacker.packToData(coverPixelMap, { format: 'image/jpeg', quality: 90 })
      const filesDir = getContext().filesDir
      const coverPath = filesDir + '/music/covers/'
      try {
        fileIo.mkdirSync(coverPath)
      } catch (_e) {
      }
      const hash = AudioPlayer.simpleHash(filePath)
      const destFile = coverPath + hash + '.jpg'
      const fd2 = fileIo.openSync(destFile, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(fd2.fd, arrayBuffer)
      fileIo.closeSync(fd2.fd)
      coverPixelMap.release()
      await imagePacker.release()
      return 'file://' + destFile
    } catch (e) {
      console.error('[AudioPlayer] extractCoverFromAudio failed:', e)
      return ''
    } finally {
      if (fd >= 0) {
        try {
          fileIo.closeSync(fd)
        } catch (_e) {
        }
      }
      if (extractor) {
        try {
          await extractor.release()
        } catch (_e) {
        }
      }
    }
  }

  setCurrentSong(song: SongInfo): void {
    this.currentSong = song
  }

  // 播放 —— 设置 url 后由状态机自动完成 prepare → play
  async play(url: string): Promise<void> {
    if (!url) {
      console.error('[AudioPlayer] play failed: URL is empty')
      this.onError?.('播放链接为空')
      return
    }

    const resolved = this.resolveUrl(url)
    if (!resolved) {
      this.onError?.('无法打开本地文件')
      return
    }

    console.info('[AudioPlayer] play requested, URL:', resolved.substring(0, 100))

    if (resolved === this.currentUrl && this.avPlayer) {
      if (this._isPlaying) {
        console.info('[AudioPlayer] same URL, already playing')
        return
      }
      if (this._isPrepared) {
        try {
          await this.avPlayer.play()
          this._isPlaying = true
          console.info('[AudioPlayer] resumed successfully')
          await this.notificationHelper.updatePlaybackState(true)
          return
        } catch (e) {
          console.error('[AudioPlayer] resume failed:', e)
        }
      }
    }

    try {
      if (this.avPlayer) {
        try {
          await this.avPlayer.release()
          console.info('[AudioPlayer] old player released')
        } catch (e) {
          console.warn('[AudioPlayer] release warning:', e)
        }
        this.avPlayer = null
      }
      this.closeCurrentFd()

      if (!await this.initPlayer()) {
        console.error('[AudioPlayer] initPlayer failed')
        return
      }

      this.currentUrl = resolved
      this._isPlaying = false
      this._isPrepared = false

      this.avPlayer!.url = resolved
      console.info('[AudioPlayer] URL set, waiting for initialization...')
      if (!await this.waitForState('initialized')) {
        this.onError?.('播放器初始化超时')
        return
      }
      console.info('[AudioPlayer] player initialized, preparing...')
      try {
        await this.avPlayer!.prepare()
      } catch (e) {
        console.error('[AudioPlayer] prepare error:', e)
        this._isPrepared = false
        this.onError?.('播放准备失败')
        return
      }
      console.info('[AudioPlayer] waiting for prepared state...')
      if (!await this.waitForState('prepared')) {
        this.onError?.('播放准备超时')
        return
      }
      this._isPrepared = true
      try {
        await this.avPlayer!.play()
        this._isPlaying = true
        console.info('[AudioPlayer] playback started')
        this.startPositionUpdateTimer()
        console.info('[AudioPlayer] calling bgHelper.startBackgroundRunning')
        await this.bgHelper.startBackgroundRunning()
        console.info('[AudioPlayer] bgHelper.startBackgroundRunning done')
        if (this.currentSong) {
          console.info('[AudioPlayer] setting metadata for:', this.currentSong.songName)
          await this.notificationHelper.updateMusicNotification(this.currentSong, true)
          await this.bgHelper.setSongMetadata(this.currentSong, this._duration * 1000)
          await this.bgHelper.setPlaybackState(true, this._currentTime * 1000, 1.0, this._duration * 1000)
          console.info('[AudioPlayer] metadata and playback state set')
        }
      } catch (e) {
        console.error('[AudioPlayer] play error:', e)
        this._isPlaying = false
        this.onError?.('播放失败')
      }
    } catch (e) {
      console.error('[AudioPlayer] play failed:', e)
      this._isPlaying = false
      this._isPrepared = false
      this.onError?.('播放失败: ' + (e instanceof Error ? e.message : String(e)))
    }
  }

  // 暂停
  async pause(): Promise<void> {
    if (this.avPlayer && this._isPlaying) {
      try {
        await this.avPlayer.pause()
        this._isPlaying = false
        this.stopPositionUpdateTimer()
        await this.notificationHelper.updatePlaybackState(false)
        await this.bgHelper.setPlaybackState(false, this._currentTime * 1000, 0, this._duration * 1000)
      } catch (e) {
        console.error('[AudioPlayer] pause failed:', e)
      }
    }
  }

  // 恢复播放（含后台返回后的状态恢复）
  async resume(): Promise<void> {
    if (!this.avPlayer) {
      console.warn('[AudioPlayer] resume called but player is null, reinitializing...')
      if (this.currentUrl) {
        await this.play(this.currentUrl)
      }
      return
    }
    if (!this._isPlaying) {
      try {
        await this.avPlayer.play()
        this._isPlaying = true
        console.info('[AudioPlayer] resumed successfully')
        this.startPositionUpdateTimer()
        await this.bgHelper.startBackgroundRunning()
        await this.notificationHelper.updatePlaybackState(true)
        await this.bgHelper.setPlaybackState(true, this._currentTime * 1000, 1.0, this._duration * 1000)
      } catch (e) {
        console.error('[AudioPlayer] resume failed, reinitializing:', e)
        if (this.currentUrl) {
          await this.play(this.currentUrl)
        }
      }
    }
  }

  // 跳转
  async seekTo(timeSeconds: number): Promise<void> {
    if (this.avPlayer && this._isPrepared) {
      try {
        await this.avPlayer.seek(timeSeconds * 1000)
      } catch (e) {
        console.error('[AudioPlayer] seek failed:', e)
      }
    }
  }

  // 设置音量 0~1
  async setVolume(volume: number): Promise<void> {
    if (this.avPlayer) {
      try {
        await this.avPlayer.setVolume(Math.max(0, Math.min(1, volume)))
      } catch (e) {
        console.error('[AudioPlayer] setVolume failed:', e)
      }
    }
  }

  // 从后台返回后同步播放器状态
  async syncStateAfterForeground(): Promise<void> {
    if (!this.avPlayer) {
      return
    }
    try {
      const state: string = this.avPlayer.state
      console.info('[AudioPlayer] syncStateAfterForeground, current state:', state)
      if (state === 'playing') {
        this._isPlaying = true
        this._isPrepared = true
      } else if (state === 'paused') {
        this._isPlaying = false
        this._isPrepared = true
      } else if (state === 'prepared') {
        this._isPrepared = true
        this._isPlaying = false
      } else {
        this._isPlaying = false
        this._isPrepared = false
      }
      // 同步到 AppStorage 以更新 UI
      AppStorage.setOrCreate('isPlaying', this._isPlaying)
    } catch (e) {
      console.error('[AudioPlayer] syncStateAfterForeground failed:', e)
      this._isPlaying = false
      this._isPrepared = false
    }
  }

  // 停止
  async stop(): Promise<void> {
    if (this.avPlayer) {
      try {
        await this.avPlayer.stop()
        this._isPlaying = false
        this._isPrepared = false
        this.stopPositionUpdateTimer()
      } catch (e) {
        console.error('[AudioPlayer] stop failed:', e)
      }
    }
    await this.bgHelper.stopBackgroundRunning()
    await this.notificationHelper.cancelMusicNotification()
    await this.bgHelper.setPlaybackState(false, 0, 0, this._duration * 1000)
  }

  // 释放资源
  async release(): Promise<void> {
    if (this.avPlayer) {
      try {
        await this.avPlayer.release()
      } catch (_ignore) {
        // ignore
      }
      this.avPlayer = null
    }
    this.closeCurrentFd()
    this.stopPositionUpdateTimer()
    this._isPlaying = false
    this._isPrepared = false
    this._currentTime = 0
    this._duration = 0
    this.currentUrl = ''
    this.currentSong = null
    await this.bgHelper.stopBackgroundRunning()
    await this.notificationHelper.cancelMusicNotification()
    await this.bgHelper.setPlaybackState(false, 0, 0, 0)
  }

  get isPlaying(): boolean {
    return this._isPlaying
  }

  get playingUrl(): string {
    return this.currentUrl
  }

  get duration(): number {
    return this._duration
  }

  get currentTime(): number {
    return this._currentTime
  }
}