import { media } from '@kit.MediaKit'
import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import image from '@ohos.multimedia.image'
import type { SongInfo } from '../model/MusicModel'
import { NotificationHelper } from './NotificationHelper'
import { BackgroundHelper } from './BackgroundHelper'
import { PlayerStore } from './PlayerStore'
import { MusicApi } from './MusicApi'
import { ListeningLevelManager } from './ListeningLevelManager'
import { CompatUtils } from './CompatUtils'
import { TagReader, EmbeddedTags } from './TagReader'

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
        this.playNext()
      },
      onPlayPrevious: () => {
        console.info('[AudioPlayer] Session command: playPrevious')
        this.playPrevious()
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
      AppStorage.setOrCreate('isPlaying', false)
      this.bgHelper.setPlaybackState(false, this._currentTime * 1000, 1.0, this._duration * 1000).catch(() => {
      })
      ListeningLevelManager.getInstance().endSession().catch(() => {
      })
      this.onError?.('播放出错')
    })

    // 监听播放器状态变化 —— 播放结束时触发 onPlayEnd，由上层决定是否继续播放下一首
    this.avPlayer.on('stateChange', (state: string, reason: media.StateChangeReason) => {
      console.info('[AudioPlayer] stateChange: ' + state + ', reason: ' + reason)
      if (state === 'playing') {
        this._isPlaying = true
        this._isPrepared = true
        AppStorage.setOrCreate('isPlaying', true)
        // 同步控制中心/锁屏图标为播放态（官方示例：onPlaying 时同步 setAVPlaybackState）
        this.bgHelper.setPlaybackState(true, this._currentTime * 1000, 1.0, this._duration * 1000).catch(() => {
        })
      } else if (state === 'completed') {
        this._isPlaying = false
        this.stopPositionUpdateTimer()
        AppStorage.setOrCreate('isPlaying', false)
        this.bgHelper.setPlaybackState(false, this._currentTime * 1000, 1.0, this._duration * 1000).catch(() => {
        })
        ListeningLevelManager.getInstance().endSession().catch(() => {
        })
        this.onPlayEnd?.()
      } else if (state === 'paused') {
        // 系统暂停（如音频焦点丢失）或主动暂停，同步状态标记与控制中心图标
        this._isPlaying = false
        this.stopPositionUpdateTimer()
        AppStorage.setOrCreate('isPlaying', false)
        this.bgHelper.setPlaybackState(false, this._currentTime * 1000, 1.0, this._duration * 1000).catch(() => {
        })
      } else if (state === 'stopped' || state === 'idle' || state === 'error') {
        this._isPlaying = false
        this._isPrepared = false
        this.stopPositionUpdateTimer()
        AppStorage.setOrCreate('isPlaying', false)
        if (state !== 'idle') {
          // idle 是播放器创建时的瞬时状态，不覆盖控制中心状态
          this.bgHelper.setPlaybackState(false, this._currentTime * 1000, 1.0, this._duration * 1000).catch(() => {
          })
        }
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

      // 直接使用完整 URI，fileIo.openSync 支持 file:// 协议
      const srcFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
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
      throw new Error('文件复制到沙箱失败: ' + (e instanceof Error ? e.message : String(e)))
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
    // V2.1.2：优先手动解析内嵌标签（系统提取器对 ID3v2.4/部分 FLAC 标签支持不稳定）
    let tags: EmbeddedTags | null = null
    try {
      tags = TagReader.readTags(filePath)
    } catch (_e) {
      tags = null
    }
    if (tags && (tags.title.length > 0 || tags.artist.length > 0)) {
      let durationMs: number = 0
      try {
        durationMs = await AudioPlayer.extractDurationMs(filePath)
      } catch (_e) {
        durationMs = 0
      }
      return {
        title: tags.title,
        artist: tags.artist,
        album: tags.album,
        duration: durationMs
      }
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

  // 仅提取时长（毫秒），失败返回 0
  private static async extractDurationMs(filePath: string): Promise<number> {
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
      if (metadata.duration) {
        return parseInt(metadata.duration as string, 10) || 0
      }
      return 0
    } catch (_e) {
      return 0
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

  static async extractCoverFromAudio(filePath: string, context: Context, originalUri?: string): Promise<string> {
    // V2.1.2：优先手动解析内嵌封面（系统提取器对部分 ID3/FLAC 封面支持不稳定）
    try {
      const tags: EmbeddedTags | null = TagReader.readTags(filePath)
      if (tags && tags.coverBytes !== null && tags.coverBytes.length > 0) {
        const filesDir = context.filesDir
        const coverPath = filesDir + '/music/covers/'
        try {
          fileIo.mkdirSync(coverPath)
        } catch (_e) {
        }
        const hash = AudioPlayer.simpleHash(filePath)
        const mime: string = tags.coverMime || 'image/jpeg'
        const ext: string = mime.includes('png') ? 'png' : (mime.includes('webp') ? 'webp' : 'jpg')
        const destFile = coverPath + hash + '.' + ext
        const fd2 = fileIo.openSync(destFile, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
        try {
          fileIo.writeSync(fd2.fd, tags.coverBytes.slice().buffer as ArrayBuffer)
        } finally {
          fileIo.closeSync(fd2.fd)
        }
        console.info('[AudioPlayer] embedded cover extracted:', destFile)
        return 'file://' + destFile
      }
    } catch (_e) {
      // 手动解析失败，走系统提取
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
      const coverPixelMap: image.PixelMap = await extractor.fetchAlbumCover()
      const imagePacker: image.ImagePacker = await image.createImagePacker()
      const arrayBuffer: ArrayBuffer =
        await imagePacker.packToData(coverPixelMap, { format: 'image/jpeg', quality: 90 })
      const filesDir = context.filesDir
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
      console.error('[AudioPlayer] extractCoverFromAudio embedded failed:', e)
      // 嵌入封面提取失败，尝试从原始文件同目录查找外部封面图
      if (originalUri) {
        const externalCover = await AudioPlayer.findExternalCover(originalUri, filePath, context)
        if (externalCover) {
          return externalCover
        }
      }
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

  // 从原始文件同目录查找外部封面图片（cover.jpg / folder.jpg 等）
  private static async findExternalCover(originalUri: string, sandboxPath: string, context: Context): Promise<string> {
    try {
      let dirPath = originalUri
      if (dirPath.startsWith('file://')) {
        dirPath = dirPath.slice(7)
      }
      const lastSlash = Math.max(dirPath.lastIndexOf('/'), dirPath.lastIndexOf('\\'))
      if (lastSlash < 0) {
        return ''
      }
      const dir = dirPath.substring(0, lastSlash)

      // 获取原始文件名（不含扩展名）用于同名封面匹配
      const origFileName = dirPath.substring(lastSlash + 1)
      const origNameNoExt = origFileName.replace(/\.[^.]+$/, '')

      // 按优先级尝试的封面文件名
      const coverNames = [
        origNameNoExt + '.jpg',
        origNameNoExt + '.png',
        origNameNoExt + '.jpeg',
        'cover.jpg',
        'cover.png',
        'folder.jpg',
        'folder.png',
        'front.jpg',
        'front.png',
        'album.jpg',
        'album.png',
        'AlbumArt.jpg',
        'AlbumArt.png',
      ]

      for (const coverName of coverNames) {
        const coverPath = dir + '/' + coverName
        try {
          if (fileIo.accessSync(coverPath)) {
            console.info('[AudioPlayer] found external cover:', coverPath)
            // 复制到 covers 缓存目录
            const filesDir = context.filesDir
            const coverDir = filesDir + '/music/covers/'
            try {
              fileIo.mkdirSync(coverDir)
            } catch (_e) {
            }
            const hash = AudioPlayer.simpleHash(sandboxPath)
            const destFile = coverDir + hash + '.jpg'

            const srcFile = fileIo.openSync(coverPath, fileIo.OpenMode.READ_ONLY)
            const srcStat = fileIo.statSync(srcFile.fd)
            const buf = new ArrayBuffer(srcStat.size)
            fileIo.readSync(srcFile.fd, buf)
            fileIo.closeSync(srcFile.fd)

            const dstFile = fileIo.openSync(destFile,
              fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
            fileIo.writeSync(dstFile.fd, buf)
            fileIo.closeSync(dstFile.fd)

            return 'file://' + destFile
          }
        } catch (_e) {
          // 该文件不存在或无法访问，继续尝试下一个
        }
      }
      return ''
    } catch (e) {
      console.error('[AudioPlayer] findExternalCover failed:', e)
      return ''
    }
  }

  setCurrentSong(song: SongInfo): void {
    this.currentSong = song
  }

  // 从音频文件中提取内嵌歌词（支持 ID3v2 USLT、FLAC Vorbis Comment、外部 .lrc 文件）
  static async extractLyricFromAudio(filePath: string, originalUri?: string): Promise<string> {
    // V2.1.2：优先手动解析内嵌歌词标签
    try {
      const tags: EmbeddedTags | null = TagReader.readTags(filePath)
      if (tags && tags.lyric && tags.lyric.length > 0) {
        return tags.lyric
      }
    } catch (_e) {
      // 忽略，走原有逻辑
    }
    let fd: number = -1
    try {
      let openUri = filePath
      if (openUri.startsWith('file://')) {
        openUri = openUri.slice(7)
      }

      const file = fileIo.openSync(openUri, fileIo.OpenMode.READ_ONLY)
      fd = file.fd
      const fileSize: number = fileIo.statSync(fd).size

      // 读取文件头判断格式
      const headerBuf = new ArrayBuffer(4)
      fileIo.readSync(fd, headerBuf)
      const header = new Uint8Array(headerBuf)

      let lyric = ''
      if (header[0] === 0x49 && header[1] === 0x44 && header[2] === 0x33) {
        // ID3v2 (MP3)
        lyric = AudioPlayer.parseId3v2Lyrics(fd, fileSize)
      } else if (header[0] === 0x66 && header[1] === 0x4C && header[2] === 0x61 && header[3] === 0x43) {
        // fLaC (FLAC)
        lyric = AudioPlayer.parseFlacLyrics(fd, fileSize)
      }

      if (lyric) {
        return lyric
      }

      // 尝试查找同目录下的 .lrc 文件（优先用原始 URI 的目录，因为沙箱中通常没有外部文件）
      const searchPath = originalUri ? originalUri : openUri
      return await AudioPlayer.findExternalLrc(searchPath)
    } catch (e) {
      console.error('[AudioPlayer] extractLyricFromAudio failed:', e)
      return ''
    } finally {
      if (fd >= 0) {
        try {
          fileIo.closeSync(fd)
        } catch (_e) {
        }
      }
    }
  }

  // 解析 ID3v2 标签中的 USLT（歌词）帧
  private static parseId3v2Lyrics(fd: number, _fileSize: number): string {
    try {
      // 已读取 4 字节标记，读取剩余 6 字节头部（版本2 + 标志1 + 大小4）
      const restHeader = new ArrayBuffer(6)
      fileIo.readSync(fd, restHeader)
      const h = new Uint8Array(restHeader)

      // 同步安全整数：4 字节，每字节只用低 7 位
      const tagSize: number = ((h[2] & 0x7F) << 21) | ((h[3] & 0x7F) << 14) | ((h[4] & 0x7F) << 7) | (h[5] & 0x7F)

      if (tagSize <= 0 || tagSize > 10 * 1024 * 1024) {
        return ''
      }

      const tagData = new ArrayBuffer(tagSize)
      fileIo.readSync(fd, tagData)
      const data = new Uint8Array(tagData)

      let offset = 0
      const flags = h[1]
      const version = h[0]

      // 跳过扩展头部
      if (version >= 3 && (flags & 0x40)) {
        if (offset + 4 <= tagSize) {
          const extSize: number = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3]
          offset = version >= 4 ? extSize : extSize + 4
        }
      }

      while (offset + 10 <= tagSize) {
        // 遇到填充字节（0x00）则停止
        if (data[offset] === 0x00) {
          break
        }

        const frameId = String.fromCharCode(data[offset], data[offset + 1], data[offset + 2], data[offset + 3])

        let frameSize: number
        if (version >= 4) {
          frameSize = ((data[offset + 4] & 0x7F) << 21) | ((data[offset + 5] & 0x7F) << 14) |
          ((data[offset + 6] & 0x7F) << 7) | (data[offset + 7] & 0x7F)
        } else {
          frameSize = (data[offset + 4] << 24) | (data[offset + 5] << 16) | (data[offset + 6] << 8) | data[offset + 7]
        }

        if (frameSize <= 0 || offset + 10 + frameSize > tagSize) {
          break
        }

        if (frameId === 'USLT') {
          const frameData = data.subarray(offset + 10, offset + 10 + frameSize)
          const encoding = frameData[0]
          // 跳过编码(1) + 语言(3) + 内容描述符(null结尾)
          let textStart = 4
          while (textStart < frameData.length && frameData[textStart] !== 0) {
            textStart++
          }
          textStart++

          if (textStart < frameData.length) {
            const textBytes = frameData.subarray(textStart)
            return AudioPlayer.decodeLyricText(textBytes, encoding)
          }
        }

        offset += 10 + frameSize
      }

      return ''
    } catch (e) {
      console.error('[AudioPlayer] parseId3v2Lyrics failed:', e)
      return ''
    }
  }

  // 智能解码歌词文本：支持多编码自动检测，解决中文歌词乱码问题
  private static decodeLyricText(textBytes: Uint8Array, encoding: number): string {
    // ID3v2 编码字节定义：
    // 0x00 = ISO-8859-1（但中文音乐常违规使用 GBK/GB2312/GB18030/BIG5）
    // 0x01 = UTF-16 with BOM
    // 0x02 = UTF-16BE (no BOM)
    // 0x03 = UTF-8

    // 编码 0x00：中文音乐几乎从不使用 ISO-8859-1，优先中文编码
    if (encoding === 0x00) {
      return AudioPlayer.decodeAsChineseEncoding(textBytes)
    }

    const encodingMap: Record<number, string> = {
      1: 'utf-16',
      2: 'utf-16be',
      3: 'utf-8',
    }

    const primaryEncoding = encodingMap[encoding] || 'utf-8'

    try {
      const decoder: util.TextDecoder = util.TextDecoder.create(primaryEncoding)
      const result = decoder.decodeWithStream(textBytes)
      if (AudioPlayer.isValidLyricText(result)) {
        return result
      }
    } catch (_e) {
      // 主编码解码失败，尝试回退
    }

    // 编码 0x01 回退：尝试 UTF-16LE（部分工具不写 BOM）
    if (encoding === 0x01) {
      try {
        const utf16leDecoder: util.TextDecoder = util.TextDecoder.create('utf-16le')
        const utf16leResult = utf16leDecoder.decodeWithStream(textBytes)
        if (AudioPlayer.isValidLyricText(utf16leResult)) {
          return utf16leResult
        }
      } catch (_e) {
        // 回退失败
      }
    }

    // 回退：UTF-8 / 中文编码兜底（部分工具误标编码）
    return AudioPlayer.decodeLrcText(textBytes)
  }

  // 编码 0x00 专用解码：优先中文编码，ISO-8859-1 作为最后兜底
  private static decodeAsChineseEncoding(textBytes: Uint8Array): string {
    // V2.1.0：UTF-8 干净则直接用，否则按 GB18030/GBK 中文编码解码（严格无替换字符判定）
    const primary: string = CompatUtils.decodeResponse(textBytes)
    if (primary.length > 0 && primary.indexOf('\uFFFD') < 0) {
      return primary
    }
    // 兜底：繁体（BIG5）与 UTF-16LE
    const fallbacks: string[] = ['big5', 'utf-16le']
    for (let i = 0; i < fallbacks.length; i++) {
      const s: string = AudioPlayer.tryDecodeLabel(fallbacks[i], textBytes)
      if (s.length > 0 && s.indexOf('\uFFFD') < 0) {
        return s
      }
    }
    // 最后兜底：ISO-8859-1（纯英文歌词场景）
    try {
      const latin1Decoder: util.TextDecoder = util.TextDecoder.create('iso-8859-1')
      const latin1Result = latin1Decoder.decodeWithStream(textBytes)
      return latin1Result
    } catch (_e) {
      // 所有编码都失败
    }
    return primary
  }

  private static tryDecodeLabel(label: string, bytes: Uint8Array): string {
    try {
      const decoder: util.TextDecoder = util.TextDecoder.create(label)
      return decoder.decodeWithStream(bytes)
    } catch (_e) {
      return ''
    }
  }

  // 检查解码后的歌词文本是否有效（严格：无替换字符即视为有效）
  private static isValidLyricText(text: string): boolean {
    if (!text || text.length === 0) {
      return false
    }
    return text.indexOf('\uFFFD') < 0
  }

  // 解析 FLAC 文件中的 Vorbis Comment 歌词（LYRICS 字段）
  private static parseFlacLyrics(fd: number, _fileSize: number): string {
    try {
      // 读取 STREAMINFO 块（一定是第一个元数据块）
      const blockHeader = new ArrayBuffer(4)
      fileIo.readSync(fd, blockHeader)
      const bh = new Uint8Array(blockHeader)

      let isLast: boolean = (bh[0] & 0x80) !== 0
      let blockType: number = bh[0] & 0x7F
      let blockSize: number = (bh[1] << 16) | (bh[2] << 8) | bh[3]

      // 跳过 STREAMINFO 块
      if (blockType === 0 && blockSize > 0) {
        AudioPlayer.skipBytes(fd, blockSize)
      }

      // 遍历后续元数据块
      while (!isLast) {
        const nextHeader = new ArrayBuffer(4)
        const readLen = fileIo.readSync(fd, nextHeader)
        if (readLen < 4) {
          break
        }

        const nh = new Uint8Array(nextHeader)
        isLast = (nh[0] & 0x80) !== 0
        blockType = nh[0] & 0x7F
        blockSize = (nh[1] << 16) | (nh[2] << 8) | nh[3]

        if (blockSize <= 0 || blockSize > 10 * 1024 * 1024) {
          break
        }

        if (blockType === 4) {
          // VORBIS_COMMENT 块
          const commentData = new ArrayBuffer(blockSize)
          fileIo.readSync(fd, commentData)
          const cd = new Uint8Array(commentData)

          // 解析 vendor string
          let offset = 0
          const vendorLen: number = cd[0] | (cd[1] << 8) | (cd[2] << 16) | (cd[3] << 24)
          offset = 4 + vendorLen

          if (offset + 4 > blockSize) {
            return ''
          }

          // 评论数量
          const commentCount: number = cd[offset] | (cd[offset + 1] << 8) | (cd[offset + 2] << 16) |
          (cd[offset + 3] << 24)
          offset += 4

          for (let i = 0; i < commentCount && offset + 4 <= blockSize; i++) {
            const len: number = cd[offset] | (cd[offset + 1] << 8) | (cd[offset + 2] << 16) | (cd[offset + 3] << 24)
            offset += 4

            if (offset + len > blockSize) {
              break
            }

            const commentBytes = cd.subarray(offset, offset + len)
            offset += len

            const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
            const comment = decoder.decodeWithStream(commentBytes)

            const eqIdx = comment.indexOf('=')
            if (eqIdx > 0) {
              const key = comment.substring(0, eqIdx).toUpperCase()
              if (key === 'LYRICS') {
                return comment.substring(eqIdx + 1)
              }
            }
          }

          return ''
        } else {
          // 跳过其他块
          AudioPlayer.skipBytes(fd, blockSize)
        }
      }

      return ''
    } catch (e) {
      console.error('[AudioPlayer] parseFlacLyrics failed:', e)
      return ''
    }
  }

  // 分块跳过字节（避免大块内存分配）
  private static skipBytes(fd: number, totalBytes: number): void {
    let remaining = totalBytes
    const chunkSize = 64 * 1024
    while (remaining > 0) {
      const readSize = Math.min(remaining, chunkSize)
      const buf = new ArrayBuffer(readSize)
      fileIo.readSync(fd, buf)
      remaining -= readSize
    }
  }

  // 查找同目录下的 .lrc 外部歌词文件
  private static async findExternalLrc(audioPath: string): Promise<string> {
    try {
      let searchPath = audioPath
      if (searchPath.startsWith('file://')) {
        searchPath = searchPath.slice(7)
      }
      const lastDot = searchPath.lastIndexOf('.')
      if (lastDot > 0) {
        const lrcPath = searchPath.substring(0, lastDot) + '.lrc'
        // 也尝试 .LRC 大写扩展名
        const lrcPathUpper = searchPath.substring(0, lastDot) + '.LRC'
        let actualPath = ''
        if (fileIo.accessSync(lrcPath)) {
          actualPath = lrcPath
        } else if (fileIo.accessSync(lrcPathUpper)) {
          actualPath = lrcPathUpper
        }
        if (actualPath) {
          const file = fileIo.openSync(actualPath, fileIo.OpenMode.READ_ONLY)
          const stat = fileIo.statSync(file.fd)
          const buf = new ArrayBuffer(stat.size)
          fileIo.readSync(file.fd, buf)
          fileIo.closeSync(file.fd)
          const bytes = new Uint8Array(buf)
          // 先用 UTF-8 解码，如果乱码再尝试 GBK
          return AudioPlayer.decodeLrcText(bytes)
        }
      }
      return ''
    } catch (_e) {
      return ''
    }
  }

  // 解码 LRC 文件内容：UTF-8 优先，乱码时回退多种中文编码
  private static decodeLrcText(bytes: Uint8Array): string {
    // V2.1.0：UTF-8 干净则直接用，否则按 GB18030/GBK 解码（修复本地 .lrc 中文乱码）
    const primary: string = CompatUtils.decodeResponse(bytes)
    if (primary.length > 0 && primary.indexOf('\uFFFD') < 0) {
      return primary
    }
    const fallbacks: string[] = ['big5', 'utf-16le', 'gbk', 'gb2312']
    for (let i = 0; i < fallbacks.length; i++) {
      const s: string = AudioPlayer.tryDecodeLabel(fallbacks[i], bytes)
      if (s.length > 0 && s.indexOf('\uFFFD') < 0) {
        return s
      }
    }
    return primary
  }

  // 控制中心/锁屏上一首命令：真正切到上一首（不依赖页面层 onPlayEnd，该回调常为空或被覆盖）
  async playPrevious(): Promise<void> {
    await this.skipTo(PlayerStore.previous())
  }

  // 控制中心/锁屏下一首命令：真正切到下一首
  async playNext(): Promise<void> {
    await this.skipTo(PlayerStore.next())
  }

  // 统一切歌：更新 AudioPlayer 状态、补齐播放链接后调用 play()
  // 目标歌曲无法获取播放链接（错误歌曲）时自动跳到下一首，避免控制中心上下首"点了没反应"
  private async skipTo(track: SongInfo | undefined, depth: number = 0): Promise<void> {
    if (!track) {
      this.pause()
      return
    }
    if (depth >= 5) {
      // 连续多首都无法获取链接，停止并暂停，防止无限循环
      console.warn('[AudioPlayer] skipTo: too many skips, pausing')
      this.pause()
      return
    }
    this.setCurrentSong(track)
    let url = track.playUrl
    if (!url && track.source !== 'local') {
      try {
        url = await MusicApi.getPlayUrl(track.songId, track.source, track)
      } catch (_e) {
        url = ''
      }
    }
    if (!url) {
      console.warn('[AudioPlayer] skipTo: no playUrl for', track.songName, ', skipping to next')
      await this.skipTo(PlayerStore.next(), depth + 1)
      return
    }
    track.playUrl = url
    await this.play(url)
  }

  // 部分播放入口（XuanchuangTab/Index/FloatingTabBar 等）未调用 setCurrentSong，
  // 若 currentSong 停留在上一首，会导致控制中心/通知栏显示旧歌曲的封面、曲名、歌手。
  // play() 前 PlayerStore.play() 已更新 AppStorage 中的 currentTrack，这里统一同步。
  private syncCurrentSongFromStore(): void {
    const storeTrack = PlayerStore.getCurrentTrack()
    if (storeTrack && (!this.currentSong || storeTrack.songId !== this.currentSong.songId)) {
      this.currentSong = storeTrack
    }
  }

  // 播放 —— 设置 url 后由状态机自动完成 prepare → play
  async play(url: string): Promise<void> {
    if (!url) {
      console.error('[AudioPlayer] play failed: URL is empty')
      this.onError?.('播放链接为空')
      return
    }

    // 进入 play() 时立即锁定本次要上报的歌曲，后续 metadata 不再中途读取 store。
    this.syncCurrentSongFromStore()
    const targetSong: SongInfo | null = this.currentSong

    // 同 URL 恢复播放：无需重新 resolveUrl，直接复用当前播放器
    if (url === this.currentUrl && this.avPlayer) {
      if (this._isPlaying) {
        console.info('[AudioPlayer] same URL, already playing')
        return
      }
      if (this._isPrepared) {
        try {
          await this.avPlayer.play()
          if (!await this.waitForState('playing', 2000)) {
            throw new Error('play did not take effect, state=' + this.avPlayer.state)
          }
          this._isPlaying = true
          AppStorage.setOrCreate('isPlaying', true)
          await ListeningLevelManager.getInstance().startSession()
          console.info('[AudioPlayer] resumed successfully')
          this.startPositionUpdateTimer()
          await this.bgHelper.startBackgroundRunning()
          await this.notificationHelper.updatePlaybackState(true)
          if (targetSong) {
            await this.bgHelper.setSongMetadata(targetSong, this._duration * 1000)
          }
          await this.bgHelper.setPlaybackState(true, this._currentTime * 1000, 1.0, this._duration * 1000)
          return
        } catch (e) {
          console.error('[AudioPlayer] resume failed:', e)
        }
      }
    }

    try {
      // 先释放旧播放器并关闭旧 fd，再打开新文件，避免 fd 被提前关闭
      if (this.avPlayer) {
        if (this._isPlaying) {
          await ListeningLevelManager.getInstance().endSession()
        }
        try {
          await this.avPlayer.release()
          console.info('[AudioPlayer] old player released')
        } catch (e) {
          console.warn('[AudioPlayer] release warning:', e)
        }
        this.avPlayer = null
      }
      this.closeCurrentFd()

      // 关闭旧 fd 后再打开新文件，确保 fd 在 avPlayer 使用期间保持有效
      const resolved = this.resolveUrl(url)
      if (!resolved) {
        this.onError?.('无法打开本地文件')
        return
      }
      console.info('[AudioPlayer] play requested, URL:', resolved.substring(0, 100))

      if (!await this.initPlayer()) {
        console.error('[AudioPlayer] initPlayer failed')
        return
      }

      this.currentUrl = resolved
      this._isPlaying = false
      this._isPrepared = false
      this._currentTime = 0
      this._duration = 0

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
        AppStorage.setOrCreate('isPlaying', true)
        await ListeningLevelManager.getInstance().startSession()
        console.info('[AudioPlayer] playback started')
        this.startPositionUpdateTimer()
        console.info('[AudioPlayer] calling bgHelper.startBackgroundRunning')
        await this.bgHelper.startBackgroundRunning()
        console.info('[AudioPlayer] bgHelper.startBackgroundRunning done')
        if (targetSong) {
          console.info('[AudioPlayer] setting metadata for:', targetSong.songName)
          await this.notificationHelper.updateMusicNotification(targetSong, true)
          await this.bgHelper.setSongMetadata(targetSong, this._duration * 1000)
          await this.bgHelper.setPlaybackState(true, this._currentTime * 1000, 1.0, this._duration * 1000)
          console.info('[AudioPlayer] metadata and playback state set')
        }
      } catch (e) {
        console.error('[AudioPlayer] play error:', e)
        this._isPlaying = false
        await ListeningLevelManager.getInstance().endSession()
        this.onError?.('播放失败')
      }
    } catch (e) {
      console.error('[AudioPlayer] play failed:', e)
      this._isPlaying = false
      this._isPrepared = false
      await ListeningLevelManager.getInstance().endSession()
      this.onError?.('播放失败: ' + (e instanceof Error ? e.message : String(e)))
    }
  }

  // 暂停
  async pause(): Promise<void> {
    if (!this.avPlayer) {
      AppStorage.setOrCreate('isPlaying', false)
      return
    }
    // 直接根据 AVPlayer 实际状态判断是否需要暂停，避免 _isPlaying 标记不同步导致空操作
    const state = this.avPlayer.state
    if (state !== 'playing') {
      console.info('[AudioPlayer] pause: player not playing, state=', state)
      // 播放器已不在播放中，仍同步 UI 与控制中心状态，避免图标/命令卡死在"播放中"
      this._isPlaying = false
      AppStorage.setOrCreate('isPlaying', false)
      await this.bgHelper.setPlaybackState(false, this._currentTime * 1000, 1.0, this._duration * 1000)
      return
    }
    try {
      await this.avPlayer.pause()
      this._isPlaying = false
      this.stopPositionUpdateTimer()
      AppStorage.setOrCreate('isPlaying', false)
      await ListeningLevelManager.getInstance().endSession()
      await this.notificationHelper.updatePlaybackState(false)
      await this.bgHelper.setPlaybackState(false, this._currentTime * 1000, 1.0, this._duration * 1000)
    } catch (e) {
      console.error('[AudioPlayer] pause failed:', e)
      this._isPlaying = false
      AppStorage.setOrCreate('isPlaying', false)
      await this.bgHelper.setPlaybackState(false, this._currentTime * 1000, 1.0, this._duration * 1000)
    }
  }

  // 恢复播放（含后台返回后的状态恢复）
  async resume(): Promise<void> {
    if (!this.avPlayer) {
      console.warn('[AudioPlayer] resume: no player, reinitializing...')
      this._isPrepared = false
      if (this.currentUrl) {
        await this.play(this.currentUrl)
      }
      return
    }
    // 直接根据 AVPlayer 实际状态判断，避免 _isPlaying 标记不同步
    const state = this.avPlayer.state
    console.info('[AudioPlayer] resume: current state=', state)
    if (state === 'playing') {
      // 已经在播放中，只需同步状态（含控制中心图标）
      this._isPlaying = true
      this._isPrepared = true
      AppStorage.setOrCreate('isPlaying', true)
      await this.bgHelper.setPlaybackState(true, this._currentTime * 1000, 1.0, this._duration * 1000)
      return
    }
    if (state === 'paused' || state === 'prepared') {
      try {
        await this.avPlayer.play()
        // play() 是异步的，状态通过 stateChange 事件异步切换；立即读 state 仍是 paused，
        // 必须等待真正进入 playing（2s 超时）才判定成功，超时再走重新初始化兜底
        if (!await this.waitForState('playing', 2000)) {
          throw new Error('play did not take effect, state=' + this.avPlayer.state)
        }
        this._isPlaying = true
        this._isPrepared = true
        AppStorage.setOrCreate('isPlaying', true)
        await ListeningLevelManager.getInstance().startSession()
        console.info('[AudioPlayer] resumed successfully')
        this.startPositionUpdateTimer()
        await this.bgHelper.startBackgroundRunning()
        await this.notificationHelper.updatePlaybackState(true)
        await this.bgHelper.setPlaybackState(true, this._currentTime * 1000, 1.0, this._duration * 1000)
      } catch (e) {
        console.error('[AudioPlayer] resume failed, reinitializing:', e)
        try { await this.avPlayer!.release() } catch (_e) {}
        this.avPlayer = null
        this._isPrepared = false
        if (this.currentUrl) {
          await this.play(this.currentUrl)
        }
      }
      return
    }
    // 其他状态（stopped/idle/error），重新初始化
    console.warn('[AudioPlayer] resume: state not playable (' + state + '), reinitializing...')
    try { await this.avPlayer.release() } catch (_e) {}
    this.avPlayer = null
    this._isPrepared = false
    if (this.currentUrl) {
      await this.play(this.currentUrl)
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
      AppStorage.setOrCreate('isPlaying', false)
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
        AppStorage.setOrCreate('isPlaying', false)
        await ListeningLevelManager.getInstance().endSession()
      } catch (e) {
        console.error('[AudioPlayer] stop failed:', e)
      }
    }
    await this.bgHelper.stopBackgroundRunning()
    await this.notificationHelper.cancelMusicNotification()
    await this.bgHelper.setPlaybackState(false, 0, 1.0, this._duration * 1000)
  }

  // 释放资源
  async release(): Promise<void> {
    if (this._isPlaying) {
      await ListeningLevelManager.getInstance().endSession()
    }
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
    AppStorage.setOrCreate('isPlaying', false)
    await this.bgHelper.stopBackgroundRunning()
    await this.notificationHelper.cancelMusicNotification()
    await this.bgHelper.setPlaybackState(false, 0, 1.0, 0)
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