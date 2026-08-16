// Sumy Music 播放详情页 - Overlay 版 (已修复进度条问题)
import { SongInfo, LyricLine, Playlist, SourceInfo } from '../model/MusicModel'
import { AudioPlayer } from '../utils/AudioPlayer'
import { MusicApi } from '../utils/MusicApi'
import { PlayerStore, PlayerKeys } from '../utils/PlayerStore'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { promptAction } from '@kit.ArkUI'
import { CompatUtils } from '../utils/CompatUtils'
import { MaterialCompat, MaterialCompatStyle } from '../utils/MaterialCompat'
import { pasteboard } from '@kit.BasicServicesKit'
import { systemShare } from '@kit.ShareKit'
import { uniformTypeDescriptor as utd } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { CoverImage } from '../components/CoverImage'

@Entry
@Component
export struct FullPlayerPage {
  onClose?: () => void
  @StorageProp('currentTrack') @Watch('onTrackChanged') currentTrack: SongInfo | null = null
  @StorageProp('isPlaying') isPlaying: boolean = false
  @StorageProp('currentTime') currentTime: number = 0
  @StorageProp('duration') duration: number = 0
  @StorageProp('lyrics') lyrics: LyricLine[] = []
  @StorageProp('playMode') playMode: number = 0
  @StorageProp('queue') queue: SongInfo[] = []
  @StorageProp('queueIndex') queueIndex: number = 0
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_bg') themeBg: string = '#F8F8FA'
  @StorageProp('theme_cardBg') themeCardBg: string = '#FFFFFF'
  @StorageProp('theme_surface') themeSurface: string = '#FFFFFF'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'
  @StorageProp('theme_divider') themeDivider: string = '#E8E8E8'
  @StorageProp('theme_placeholder') themePlaceholder: string = '#E0E0E0'
  @StorageProp('theme_primaryLight') themePrimaryLight: string = '#E0F0FF'
  @StorageProp('theme_bgImageName') themeBgImageName: string = ''
  @StorageProp('isDarkMode') isDarkMode: boolean = false
  @State progress: number = 0
  @State currentLyricIndex: number = 0
  @State isSeeking: boolean = false
  @State showListSheet: boolean = false
  @State showMoreSheet: boolean = false
  @State dragOffset: number = 0
  @State swiperIndex: number = 0
  @State showControls: boolean = true
  @State playModeLocal: number = 0
  @State bgColorEnabled: boolean = false
  @State lyricsAlign: string = 'center'
  @State showPlaylistPicker: boolean = false
  @State playlists: Playlist[] = []
  @State showLyricsAlignPicker: boolean = false
  @State autoHideControls: boolean = false
  @State showQueuePopup: boolean = false
  @State lyricPullOffset: number = 0
  @State lyricPullHint: string = ''
  @State lyricsViewHeight: number = 600
  private lyricsScroller: Scroller = new Scroller()
  private progressTimer: number = -1
  private controlsTimer: number = -1
  private db: DatabaseHelper = DatabaseHelper.getInstance()
  // 🆕 拖动中：记录预览时间，不污染全局 currentTime
  private dragTime: number = 0
  private supportImmersive: boolean = CompatUtils.isImmersiveSupported()

  aboutToAppear(): void {
    this.playModeLocal = this.playMode
    this.loadSettings()
    if (this.currentTrack) {
      this.loadLyrics()
    }
    this.startProgressTimer()
    this.setupPlayerCallbacks()
    if (this.autoHideControls && this.swiperIndex === 1) {
      this.resetControlsTimer()
    }
  }

  // 切歌（含控制中心上一首/下一首命令）时联动：重载歌词、重置进度与歌词滚动
  onTrackChanged(): void {
    if (!this.currentTrack) {
      return
    }
    this.loadLyrics()
    this.progress = 0
    this.currentLyricIndex = 0
    this.lyricsScroller.scrollToIndex(0)
  }

  aboutToDisappear(): void {
    if (this.progressTimer !== -1) {
      clearInterval(this.progressTimer)
    }
    if (this.controlsTimer !== -1) {
      clearTimeout(this.controlsTimer)
    }
  }

  private async loadSettings(): Promise<void> {
    const align = await this.db.getSetting('lyricsAlign')
    if (align) {
      this.lyricsAlign = align
    }
    const bgColor = await this.db.getSetting('bgColorEnabled')
    if (bgColor === 'true') {
      this.bgColorEnabled = true
    }
    const autoHide = await this.db.getSetting('autoHideControls')
    if (autoHide === 'true') {
      this.autoHideControls = true
    }
  }

  private resetControlsTimer(): void {
    if (this.controlsTimer !== -1) {
      clearTimeout(this.controlsTimer)
    }
    this.showControls = true
    this.controlsTimer = setTimeout(() => {
      this.showControls = false
    }, 3000)
  }

  private toggleControls(): void {
    if (this.showControls) {
      this.showControls = false
      if (this.controlsTimer !== -1) {
        clearTimeout(this.controlsTimer)
      }
    } else {
      this.resetControlsTimer()
    }
  }

  // ======================== 修复①：加 seekDone 回调 ========================
  private setupPlayerCallbacks(): void {
    const player = AudioPlayer.getInstance()

    player.onTimeUpdate = (time: number) => {
      if (!this.isSeeking) {
        PlayerStore.updateTime(time)
      }
    }

    player.onDurationUpdate = (dur: number) => {
      PlayerStore.updateDuration(dur)
    }

    // 🆕 seekDone：seek 完成后自动解锁，更新进度
    player.onSeekDone = (seekTime: number) => {
      this.isSeeking = false
      const dur = this.duration > 0 ? this.duration : player.duration
      if (dur > 0) {
        this.progress = Math.min(seekTime, dur) / dur
      }
    }

    player.onPlayEnd = () => {
      const nextTrack = PlayerStore.onTrackEnd()
      if (nextTrack) {
        this.playNewTrack(nextTrack)
      } else {
        PlayerStore.pause()
      }
    }

    player.onError = (error: string) => {
      PlayerStore.pause()
      promptAction.showToast({
        message: error || '播放失败，3秒后自动播放下一首',
        duration: 3000,
        bottom: '120vp'
      })
      setTimeout(() => {
        const nextTrack = PlayerStore.next()
        if (nextTrack) {
          this.playNewTrack(nextTrack)
        }
      }, 3000)
    }
  }

  private async playNewTrack(track: SongInfo): Promise<void> {
    let playUrl = track.playUrl
    if (!playUrl && track.source !== 'local') {
      playUrl = await MusicApi.getPlayUrl(track.songId, track.source, track)
    }
    if (!playUrl) {
      PlayerStore.pause()
      return
    }
    track.playUrl = playUrl
    PlayerStore.play(track)
    AudioPlayer.getInstance().setCurrentSong(track)
    // 歌词加载与进度重置由 onTrackChanged（@Watch currentTrack）统一处理
    await AudioPlayer.getInstance().play(playUrl)
  }

  private async loadLyrics(): Promise<void> {
    if (!this.currentTrack) {
      return
    }
    // 优先使用本地音乐内嵌歌词
    if (this.currentTrack.lyric && this.currentTrack.lyric.length > 0) {
      console.info('[FullPlayerPage] using local embedded lyric, length:', this.currentTrack.lyric.length)
      const parsed = PlayerStore.parseLrc(this.currentTrack.lyric)
      if (parsed.length > 0) {
        const deduped: LyricLine[] = []
        for (let i = 0; i < parsed.length; i++) {
          if (i === 0 || parsed[i].text !== parsed[i - 1].text) {
            deduped.push(parsed[i])
          }
        }
        PlayerStore.setLyrics(deduped, this.currentTrack.lyric)
        this.currentLyricIndex = 0
        return
      }
    }
    // 否则走在线获取
    try {
      const raw = await MusicApi.getLyrics(this.currentTrack.songId, this.currentTrack.source, this.currentTrack)
      if (raw && raw.length > 0) {
        const parsed = PlayerStore.parseLrc(raw)
        const deduped: LyricLine[] = []
        for (let i = 0; i < parsed.length; i++) {
          if (i === 0 || parsed[i].text !== parsed[i - 1].text) {
            deduped.push(parsed[i])
          }
        }
        PlayerStore.setLyrics(deduped, raw)
        this.currentLyricIndex = 0
      }
    } catch (_e) {
      console.error('[FullPlayerPage] loadLyrics failed')
    }
  }

  private startProgressTimer(): void {
    this.progressTimer = setInterval(() => {
      if (!this.isSeeking) {
        if (this.duration > 0) {
          this.progress = this.currentTime / this.duration
        } else {
          this.progress = 0
        }
      }
      this.updateCurrentLyricIndex()
    }, 500)
  }

  private updateCurrentLyricIndex(): void {
    if (this.lyrics.length === 0) {
      this.currentLyricIndex = 0
      return
    }
    for (let i = this.lyrics.length - 1; i >= 0; i--) {
      if (this.currentTime >= this.lyrics[i].time) {
        if (i !== this.currentLyricIndex) {
          this.currentLyricIndex = i
          const midIndex = Math.max(0, i - 4)
          this.lyricsScroller.scrollToIndex(midIndex)
        }
        break
      }
    }
  }

  private formatTime(seconds: number): string {
    const min = Math.floor(seconds / 60)
    const sec = Math.floor(seconds % 60)
    return `${min.toString().padStart(2, '0')}:${sec.toString().padStart(2, '0')}`
  }

  /** 将音源来源码转为中文标签（与搜索卡片一致：SourceInfo 映射） */
  private getSourceLabel(source: string): string {
    return SourceInfo.getName(source)
  }

  private async togglePlayPause(): Promise<void> {
    if (!this.currentTrack) {
      return
    }
    if (this.isPlaying) {
      await AudioPlayer.getInstance().pause()
      PlayerStore.pause()
    } else {
      await AudioPlayer.getInstance().resume()
      PlayerStore.resume()
    }
  }

  // ======================== 修复②：doSeek 去掉 setTimeout ========================
  private doSeek(position: number): void {
    if (position <= 0.001) {
      return
    }
    const player = AudioPlayer.getInstance()
    const dur = this.duration > 0 ? this.duration : player.duration
    if (dur <= 0) {
      return
    }

    const time = position * dur
    this.isSeeking = true
    this.progress = position
    this.dragTime = time
    // ✅ seekDone 回调会自动解锁 isSeeking，不需要 setTimeout
    player.seekTo(time)
    this.updateCurrentLyricIndex()
  }

  private async handlePrevious(): Promise<void> {
    const track = PlayerStore.previous()
    if (track) {
      await this.playNewTrack(track)
    }
  }

  private async handleNext(): Promise<void> {
    const track = PlayerStore.next()
    if (track) {
      await this.playNewTrack(track)
    }
  }

  private async saveProgress(): Promise<void> {
    // 进度保存已移至 EntryAbility.onBackground（按会话保存 lastTrack/lastPosition）
    // 此方法保留为空，避免影响 doBack 调用链
  }

  private togglePlayMode(): void {
    this.playModeLocal = PlayerStore.togglePlayMode()
  }

  private getPlayModeIconLocal(): Resource {
    switch (this.playModeLocal) {
      case 0:
        return $r('sys.symbol.repeat')
      case 1:
        return $r('sys.symbol.shuffle')
      case 2:
        return $r('sys.symbol.repeat_1')
      default:
        return $r('sys.symbol.repeat')
    }
  }

  private getPlayModeLabelLocal(): string {
    switch (this.playModeLocal) {
      case 0:
        return '顺序播放'
      case 1:
        return '随机播放'
      case 2:
        return '单曲循环'
      default:
        return '列表循环'
    }
  }

  private async handleLyricClick(line: LyricLine): Promise<void> {
    const player = AudioPlayer.getInstance()
    await player.seekTo(line.time)
    PlayerStore.updateTime(line.time)
    this.currentLyricIndex = this.lyrics.indexOf(line)
    this.progress = this.duration > 0 ? line.time / this.duration : 0
    if (!this.isPlaying) {
      await player.resume()
      PlayerStore.resume()
    }
  }

  private async showPlaylistSheet(): Promise<void> {
    this.playlists = await this.db.getPlaylists()
    this.showPlaylistPicker = true
    this.showMoreSheet = false
  }

  private async addToPlaylist(playlist: Playlist): Promise<void> {
    if (!this.currentTrack) {
      return
    }
    const result = await this.db.addSongToPlaylist(playlist.id, this.currentTrack)
    if (result) {
      promptAction.showToast({ message: `已添加到「${playlist.name}」`, duration: 2000 })
    } else {
      promptAction.showToast({ message: '添加失败，请重试', duration: 2000 })
    }
    this.showPlaylistPicker = false
  }

  private async setLyricsAlign(align: string): Promise<void> {
    this.lyricsAlign = align
    await this.db.setSetting('lyricsAlign', align)
    this.showLyricsAlignPicker = false
    promptAction.showToast(
      { message: `歌词对齐：${align === 'left' ? '左对齐' : align === 'right' ? '右对齐' : '居中'}`, duration: 1500 })
  }

  private async toggleBgColor(): Promise<void> {
    this.bgColorEnabled = !this.bgColorEnabled
    await this.db.setSetting('bgColorEnabled', this.bgColorEnabled ? 'true' : 'false')
    this.showMoreSheet = false
    promptAction.showToast({ message: this.bgColorEnabled ? '背景取色已开启' : '背景取色已关闭', duration: 1500 })
  }

  private async toggleAutoHideControls(): Promise<void> {
    this.autoHideControls = !this.autoHideControls
    await this.db.setSetting('autoHideControls', this.autoHideControls ? 'true' : 'false')
    this.showMoreSheet = false
    if (this.autoHideControls && this.swiperIndex === 1) {
      this.resetControlsTimer()
    } else {
      this.showControls = true
      if (this.controlsTimer !== -1) {
        clearTimeout(this.controlsTimer)
      }
    }
    promptAction.showToast({ message: this.autoHideControls ? '组件隐藏已开启' : '组件隐藏已关闭', duration: 1500 })
  }

  private async shareSong(): Promise<void> {
    if (!this.currentTrack) {
      return
    }
    try {
      // 与歌曲弹窗/歌单内分享一致：调用系统分享面板
      const shareText = this.buildShareText(this.currentTrack)
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: shareText,
        title: `分享歌曲：${this.currentTrack.songName}`,
        description: `${this.currentTrack.songName} - ${this.currentTrack.artist}`,
      })
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData)
      const context = getContext(this) as common.UIAbilityContext
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL,
      })
    } catch (e) {
      console.error('[FullPlayerPage] share failed:', e)
      // 降级：复制到剪贴板
      try {
        const shareText = this.buildShareText(this.currentTrack)
        const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, shareText)
        const systemPasteboard = pasteboard.getSystemPasteboard()
        await systemPasteboard.setDataSync(pasteData)
        promptAction.showToast({ message: '分享面板拉起失败，已复制到剪贴板', duration: 2000 })
      } catch (_e) {
        promptAction.showToast({ message: '分享失败', duration: 2000 })
      }
    }
    this.showMoreSheet = false
  }

  // 分享文本与歌曲弹窗/歌单内分享一致
  private buildShareText(song: SongInfo): string {
    const url = this.getShareUrl(song)
    if (url) {
      return `♫ ${song.songName} - ${song.artist}\n${url}`
    }
    return `♫ ${song.songName} - ${song.artist}\n快来听这首歌吧！`
  }

  // 根据音源生成原平台详情页链接（与歌曲弹窗/歌单分享一致）
  private getShareUrl(song: SongInfo): string {
    const id = song.songId
    switch (song.source) {
      case 'wy':
      case 'netease':
      case 'WY':
        return `https://music.163.com/#/song?id=${id}`
      case 'tx':
      case 'qq':
      case 'TX':
        return `https://y.qq.com/n/ryqq/songDetail/${id}`
      case 'kw':
      case 'kuwo':
      case 'KW':
        return `https://www.kuwo.cn/play_detail/${id}`
      case 'kg':
      case 'kugou':
      case 'KG':
        return `https://www.kugou.com/song/#hash=${id}`
      case 'mg':
      case 'migu':
      case 'MG':
        return `https://music.migu.cn/v3/music/song/${id}`
      default:
        // local、webdav 等无原平台链接
        return ''
    }
  }

  private doBack(): void {
    this.saveProgress()
    PlayerStore.hideFullPlayer()
    this.onClose?.()
  }

  private removeFromQueue(index: number): void {
    const queue = PlayerStore.getQueue()
    const currentIndex = PlayerStore.getQueueIndex()
    if (index < 0 || index >= queue.length) {
      return
    }

    const newQueue = queue.slice()
    newQueue.splice(index, 1)

    if (newQueue.length === 0) {
      PlayerStore.setQueue([])
      PlayerStore.pause()
      AppStorage.setOrCreate(PlayerKeys.CURRENT_TRACK, null)
      this.showQueuePopup = false
      return
    }

    let newIndex = currentIndex
    if (index < currentIndex) {
      newIndex = currentIndex - 1
    } else if (index === currentIndex) {
      if (newIndex >= newQueue.length) {
        newIndex = newQueue.length - 1
      }
      AppStorage.setOrCreate(PlayerKeys.QUEUE, newQueue)
      AppStorage.setOrCreate(PlayerKeys.QUEUE_INDEX, newIndex)
      const track = newQueue[newIndex]
      if (track) {
        this.playNewTrack(track)
      }
      return
    }

    AppStorage.setOrCreate(PlayerKeys.QUEUE, newQueue)
    AppStorage.setOrCreate(PlayerKeys.QUEUE_INDEX, newIndex)
  }

  // 🆕 获取显示时间：拖动时显示预览时间，释放后显示实际时间
  private getDisplayTime(): number {
    if (this.isSeeking) {
      return this.dragTime
    }
    return this.currentTime
  }

  @Builder
  ThemeBackgroundImage() {
    if (this.themeBgImageName === 'lxtx') {
      Image($rawfile('theme-lxtx.jpg'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else if (this.themeBgImageName === 'xrhf') {
      Image($rawfile('theme-xrhf.jpg'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else if (this.themeBgImageName === 'nyqf') {
      Image($rawfile('theme-nyqf.jpg'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else if (this.themeBgImageName === 'nyha') {
      Image($rawfile('theme-nyha.jpg'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else if (this.themeBgImageName === 'xcwh') {
      Image($rawfile('theme-xcwh.jpg'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [[this.themeBg, 0], [this.themeSurface, 1]],
        })
    }
  }

  build() {
    Stack() {
      // Background
      this.ThemeBackgroundImage()

      if (this.bgColorEnabled && this.currentTrack?.coverUrl) {
        Image(this.currentTrack.coverUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(50)
          .opacity(0.6)
      }

      Column() {
        Row() {
          if (this.supportImmersive) {
            Row() {
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(18)
                .fontColor([this.themeTextPrimary])
            }
            .width(32).height(32)
            .borderRadius(16)
            .border({ width: 1, color: this.themeTextPrimary })
            .backgroundColor(this.themeCardBg)
            .systemMaterial(MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN))
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.doBack()
            })
          } else {
            Row() {
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(18)
                .fontColor([this.themeTextPrimary])
            }
            .width(32).height(32)
            .borderRadius(16)
            .border({ width: 1, color: this.themeTextPrimary })
            .backgroundColor(this.themeCardBg)
            .blur(8)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.doBack()
            })
          }

          Blank().layoutWeight(1)

          if (this.supportImmersive) {
            Row() {
              SymbolGlyph($r('sys.symbol.list_bullet'))
                .fontSize(18)
                .fontColor([this.themeTextPrimary])
            }
            .width(32)
            .height(32)
            .borderRadius(16)
            .border({ width: 1, color: this.themeTextPrimary })
            .backgroundColor(this.themeCardBg)
            .systemMaterial(MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN))
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.showQueuePopup = true
            })
            .bindPopup(this.showQueuePopup, {
              builder: this.QueuePopupBuilder(),
              placement: Placement.Bottom,
              width: '85%',
              systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN),
              onStateChange: (e: PopupStateChangeParam) => {
                if (!e.isVisible) {
                  this.showQueuePopup = false
                }
              }
            })
          } else {
            Row() {
              SymbolGlyph($r('sys.symbol.list_bullet'))
                .fontSize(18)
                .fontColor([this.themeTextPrimary])
            }
            .width(32)
            .height(32)
            .borderRadius(16)
            .border({ width: 1, color: this.themeTextPrimary })
            .backgroundColor(this.themeCardBg)
            .blur(8)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.showQueuePopup = true
            })
            .bindPopup(this.showQueuePopup, {
              builder: this.QueuePopupBuilder(),
              placement: Placement.Bottom,
              width: '85%',
              systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN),
              onStateChange: (e: PopupStateChangeParam) => {
                if (!e.isVisible) {
                  this.showQueuePopup = false
                }
              }
            })
          }
        }
        .width('100%')
        .padding({
          left: 8,
          right: 8,
          top: 42,
          bottom: 4
        })

        Column() {
          Swiper() {
            this.CoverView()
            this.LyricsView()
          }
          .index(this.swiperIndex)
          .vertical(false)
          .autoPlay(false)
          .displayArrow(false)
          .effectMode(EdgeEffect.Spring)
          .indicator(new DotIndicator()
            .itemWidth(6)
            .itemHeight(6)
            .selectedItemWidth(12)
            .selectedItemHeight(6)
            .color((this.autoHideControls && this.swiperIndex === 1 && !this.showControls) ? '#00000000' :
              this.themeDivider)
            .selectedColor((this.autoHideControls && this.swiperIndex === 1 && !this.showControls) ? '#00000000' :
              this.themePrimary)
          )
          .cachedCount(2)
          .onChange((index: number) => {
            this.swiperIndex = index
            if (index === 1 && this.autoHideControls) {
              this.resetControlsTimer()
            } else {
              this.showControls = true
              if (this.controlsTimer !== -1) {
                clearTimeout(this.controlsTimer)
              }
            }
          })
          .layoutWeight(1)
        }
        .width('100%')
        .layoutWeight(1)
        .gesture(
          PanGesture({ direction: PanDirection.Down })
            .onActionUpdate((event) => {
              this.dragOffset = event.offsetY * 0.4
            })
            .onActionEnd((event) => {
              if (event.offsetY > 150) {
                this.doBack()
              }
              animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                this.dragOffset = 0
              })
            })
        )

        // ======================== 修复③：Slider ========================
        Column() {
          Column({ space: 4 }) {
            Slider({
              value: this.progress,
              min: 0,
              max: 1,
              step: 0.001,
            })
              .width('100%')
              .blockColor(this.themePrimary)
              .selectedColor(this.themePrimary)
              .trackColor(this.themePlaceholder)
              .showSteps(false)
              .enabled(!!this.currentTrack)
              .onChange((value: number, mode: SliderChangeMode) => {
                switch (mode) {
                  case SliderChangeMode.Begin:
                    this.isSeeking = true
                    this.dragTime = this.currentTime // 锁定当前时间
                    break
                  case SliderChangeMode.Moving:
                    // ✅ 只更新 UI，不写全局状态
                    this.progress = value
                    const dur = this.duration > 0 ? this.duration : AudioPlayer.getInstance().duration
                    this.dragTime = value * dur
                    break
                  case SliderChangeMode.Click:
                  case SliderChangeMode.End:
                    this.doSeek(value)
                    break
                }
              })

            // ✅ 时间显示：拖动时用 dragTime，释放后用 currentTime
            Row() {
              Text(this.formatTime(this.getDisplayTime()))
                .fontSize(11)
                .fontColor(this.themeTextSecondary)
              Blank().layoutWeight(1)
              Text(this.formatTime(this.duration))
                .fontSize(11)
                .fontColor(this.themeTextSecondary)
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 24, right: 24 })

          this.ControlBar()
        }
        .width('100%')
        .opacity(this.showControls ? 1 : 0)
        .animation({ duration: 300, curve: Curve.EaseInOut })
        .translate({ y: this.showControls ? 0 : 20 })
        .hitTestBehavior(this.showControls ? HitTestMode.Default : HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .translate({ y: Math.max(0, this.dragOffset) })

      Row().width(1).height(1)
        .bindSheet($$this.showListSheet, this.PlaylistSheetContent(), {
          height: SheetSize.MEDIUM,
          dragBar: true,
          showClose: true,
          systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK)
        })
      Row().width(1).height(1)
        .bindSheet($$this.showMoreSheet, this.MoreSheetContent(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: true,
          systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK)
        })
      Row().width(1).height(1)
        .bindSheet($$this.showPlaylistPicker, this.PlaylistPickerContent(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: true,
          systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK)
        })
      Row().width(1).height(1)
        .bindSheet($$this.showLyricsAlignPicker, this.LyricsAlignPickerContent(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: true,
          systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK)
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  CoverView() {
    Column() {
      CoverImage({
        url: this.currentTrack ? this.currentTrack.coverUrl : '',
        coverWidth: 280,
        coverHeight: 280,
        radius: 16
      })
      .shadow({ radius: 30, color: '#007DFF30', offsetY: 8 })

      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(this.currentTrack?.songName ?? '暂无播放内容')
            .fontSize(20)
            .fontColor(this.themeTextPrimary)
            .fontWeight(FontWeight.Bold)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.currentTrack && this.currentTrack.source && this.currentTrack.source.length > 0) {
            Text(SourceInfo.getAbbr(this.currentTrack.source))
              .fontSize(11)
              .fontColor(Color.White)
              .backgroundColor(SourceInfo.getColor(this.currentTrack.source))
              .borderRadius(4)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .maxLines(1)
              .flexShrink(0)
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .margin({ top: 20 })

        if (this.currentTrack) {
          Text(this.currentTrack.artist)
            .fontSize(15)
            .fontColor(this.themeTextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      .padding({ left: 32, right: 32 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  LyricsView() {
    Column() {
      Stack() {
        if (this.lyricPullOffset > 0) {
          Column() {
            SymbolGlyph($r('sys.symbol.arrow_down'))
              .fontSize(16)
              .fontColor([this.themePrimary])
              .opacity(Math.min(1, this.lyricPullOffset / 60))
            Text(this.lyricPullHint)
              .fontSize(12)
              .fontColor(this.themePrimary)
              .margin({ top: 4 })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%')
      .height(Math.max(0, this.lyricPullOffset))
      .clip(true)

      Text(this.currentTrack?.songName ?? '')
        .fontSize(16)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({
          left: 32,
          right: 32,
          top: 16,
          bottom: 8
        })

      if (this.lyrics.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.mic')).fontSize(48).fontColor([this.themeTextSecondary]).opacity(0.3)
          Text('暂无歌词').fontSize(15).fontColor(this.themeTextSecondary).margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ scroller: this.lyricsScroller }) {
          ListItem() {
            Row().height('40%').width('100%')
          }

          ForEach(this.lyrics, (line: LyricLine, index?: number) => {
            ListItem() {
              Text(line.text)
                .fontSize(this.getLyricFontSize(index ?? 0))
                .fontColor(this.getLyricColor(index ?? 0))
                .fontWeight(this.getLyricFontWeight(index ?? 0))
                .opacity(this.getLyricOpacity(index ?? 0))
                .width('100%')
                .padding({
                  left: 32,
                  right: 32,
                  top: 10,
                  bottom: 10
                })
                .textAlign(this.getLyricsTextAlign())
                .animation({ duration: 300, curve: Curve.EaseInOut })
                .onClick(() => {
                  this.handleLyricClick(line)
                })
            }
          })
          ListItem() {
            Row().height('40%').width('100%')
          }
        }
        .width('100%')
        .layoutWeight(1)
        .alignListItem(ListItemAlign.Center)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(10)
        .onClick(() => {
          if (this.autoHideControls) {
            this.toggleControls()
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_, newArea) => {
      this.lyricsViewHeight = newArea.height as number
    })
    .gesture(
      PanGesture({ direction: PanDirection.Down })
        .onActionUpdate((event) => {
          this.lyricPullOffset = event.offsetY
          const center = this.lyricsViewHeight / 2
          this.lyricPullHint = this.lyricPullOffset > center ? '松开关闭详情页'
            : this.lyricPullOffset > 40 ? '松开刷新歌词'
              : '轻拉刷新 / 拖底关闭'
        })
        .onActionEnd(() => {
          const center = this.lyricsViewHeight / 2
          if (this.lyricPullOffset > center) {
            this.doBack()
            animateTo({ duration: 200 }, () => {
              this.lyricPullOffset = 0
            })
            setTimeout(() => {
              this.lyricPullHint = ''
            }, 300)
            return
          }
          if (this.lyricPullOffset > 40) {
            this.lyricPullHint = '刷新中...'
            this.loadLyrics()
          }
          animateTo({ duration: 200 }, () => {
            this.lyricPullOffset = 0
          })
          setTimeout(() => {
            this.lyricPullHint = ''
          }, 300)
        })
    )
  }

  private getLyricsTextAlign(): TextAlign {
    switch (this.lyricsAlign) {
      case 'left':
        return TextAlign.Start
      case 'right':
        return TextAlign.End
      default:
        return TextAlign.Center
    }
  }

  private getLyricFontSize(index: number): number {
    const diff = Math.abs(index - this.currentLyricIndex)
    return diff === 0 ? 20 : diff === 1 ? 16 : 14
  }

  private getLyricColor(index: number): ResourceColor {
    const diff = Math.abs(index - this.currentLyricIndex)
    return diff === 0 ? this.themeTextPrimary : this.themeTextSecondary
  }

  private getLyricFontWeight(index: number): FontWeight {
    return Math.abs(index - this.currentLyricIndex) === 0 ? FontWeight.Bold : FontWeight.Normal
  }

  private getLyricOpacity(index: number): number {
    const diff = Math.abs(index - this.currentLyricIndex)
    return diff === 0 ? 1.0 : diff === 1 ? 0.7 : 0.4
  }

  @Builder
  ControlBar() {
    Column() {
      Divider().width('90%').height(0.5).color(this.themeDivider).margin({ bottom: 12 })

      Row() {
        // 播放模式
        if (this.supportImmersive) {
          Row() {
            SymbolGlyph(this.getPlayModeIconLocal()).fontSize(16).fontColor([this.themeTextPrimary])
          }
          .width(36).height(36)
          .borderRadius(18)
          .border({ width: 1, color: this.themeTextPrimary })
          .backgroundColor(this.themeCardBg)
          .systemMaterial(MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN))
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.togglePlayMode()
            promptAction.showToast({ message: this.getPlayModeLabelLocal(), duration: 1500 })
          })
        } else {
          Row() {
            SymbolGlyph(this.getPlayModeIconLocal()).fontSize(16).fontColor([this.themeTextPrimary])
          }
          .width(36).height(36)
          .borderRadius(18)
          .border({ width: 1, color: this.themeTextPrimary })
          .backgroundColor(this.themeCardBg)
          .blur(8)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.togglePlayMode()
            promptAction.showToast({ message: this.getPlayModeLabelLocal(), duration: 1500 })
          })
        }

        // 上一首
        if (this.supportImmersive) {
          Row() {
            SymbolGlyph($r('sys.symbol.backward_end_fill')).fontSize(18).fontColor([this.themeTextPrimary])
          }
          .width(36).height(36)
          .borderRadius(18)
          .border({ width: 1, color: this.themeTextPrimary })
          .backgroundColor(this.themeCardBg)
          .systemMaterial(MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN))
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.handlePrevious()
          })
        } else {
          Row() {
            SymbolGlyph($r('sys.symbol.backward_end_fill')).fontSize(18).fontColor([this.themeTextPrimary])
          }
          .width(36).height(36)
          .borderRadius(18)
          .border({ width: 1, color: this.themeTextPrimary })
          .backgroundColor(this.themeCardBg)
          .blur(8)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.handlePrevious()
          })
        }

        // 播放/暂停（中间，更大）
        if (this.supportImmersive) {
          Row() {
            SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
              .fontSize(24).fontColor([this.themeTextPrimary])
          }
          .width(52)
          .height(52)
          .borderRadius(26)
          .border({ width: 1, color: this.themeTextPrimary })
          .backgroundColor(this.themeCardBg)
          .systemMaterial(MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN))
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.togglePlayPause()
          })
        } else {
          Row() {
            SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
              .fontSize(24).fontColor([this.themeTextPrimary])
          }
          .width(52)
          .height(52)
          .borderRadius(26)
          .border({ width: 1, color: this.themeTextPrimary })
          .backgroundColor(this.themeCardBg)
          .blur(8)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.togglePlayPause()
          })
        }

        // 下一首
        if (this.supportImmersive) {
          Row() {
            SymbolGlyph($r('sys.symbol.forward_end_fill')).fontSize(18).fontColor([this.themeTextPrimary])
          }
          .width(36).height(36)
          .borderRadius(18)
          .border({ width: 1, color: this.themeTextPrimary })
          .backgroundColor(this.themeCardBg)
          .systemMaterial(MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN))
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.handleNext()
          })
        } else {
          Row() {
            SymbolGlyph($r('sys.symbol.forward_end_fill')).fontSize(18).fontColor([this.themeTextPrimary])
          }
          .width(36).height(36)
          .borderRadius(18)
          .border({ width: 1, color: this.themeTextPrimary })
          .backgroundColor(this.themeCardBg)
          .blur(8)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.handleNext()
          })
        }

        // 更多
        if (this.supportImmersive) {
          Row() {
            SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(16).fontColor([this.themeTextPrimary])
          }
          .width(36).height(36)
          .borderRadius(18)
          .border({ width: 1, color: this.themeTextPrimary })
          .backgroundColor(this.themeCardBg)
          .systemMaterial(MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN))
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.showMoreSheet = true
          })
        } else {
          Row() {
            SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(16).fontColor([this.themeTextPrimary])
          }
          .width(36).height(36)
          .borderRadius(18)
          .border({ width: 1, color: this.themeTextPrimary })
          .backgroundColor(this.themeCardBg)
          .blur(8)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.showMoreSheet = true
          })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, bottom: 8 })
    }
    .width('100%')
    .padding({ bottom: 36 })
  }

  @Builder
  PlaylistSheetContent() {
    Column() {
      Row() {
        Text('播放列表').fontSize(18).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Bold)
        Blank().layoutWeight(1)
        Text(this.getPlayModeLabelLocal())
          .fontSize(12)
          .fontColor(this.themePrimary)
          .padding({
            left: 12,
            right: 12,
            top: 4,
            bottom: 4
          })
          .backgroundColor(this.themePrimaryLight)
          .borderRadius(12)
          .onClick(() => {
            this.togglePlayMode();
            promptAction.showToast({ message: this.getPlayModeLabelLocal(), duration: 1500 })
          })
      }
      .width('100%')
      .padding({
        left: 24,
        right: 24,
        top: 16,
        bottom: 12
      })

      Scroll() {
        Column({ space: 0 }) {
          ForEach(PlayerStore.getQueue(), (track: SongInfo, index?: number) => {
            Row({ space: 10 }) {
              Text(`${(index ?? 0) + 1}`)
                .fontSize(13)
                .fontColor(this.themeTextSecondary)
                .width(24)
                .textAlign(TextAlign.Center)
              CoverImage({
                url: track.coverUrl,
                coverWidth: 40,
                coverHeight: 40,
                radius: 6
              })
              Column({ space: 2 }) {
                Text(track.songName)
                  .fontSize(14)
                  .fontColor(this.themeTextPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(track.artist)
                  .fontSize(11)
                  .fontColor(this.themeTextSecondary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({
              left: 24,
              right: 24,
              top: 8,
              bottom: 8
            })
          })
        }
        .width('100%')
      }.layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring)
    }.width('100%').height('100%')
  }

  @Builder
  MoreSheetContent() {
    Column({ space: 0 }) {
      MoreSheetRow($r('sys.symbol.plus'), '添至歌单', () => {
        this.showPlaylistSheet()
      })
      Divider().width('100%').color(this.themeDivider).margin({ left: 24, right: 24 })
      MoreSheetRow($r('sys.symbol.text_alignleft'), '歌词排列', () => {
        this.showMoreSheet = false;
        this.showLyricsAlignPicker = true
      })
      Divider().width('100%').color(this.themeDivider).margin({ left: 24, right: 24 })
      MoreSheetToggleRow('组件隐藏', this.autoHideControls, (v) => {
        if (v !== this.autoHideControls) {
          this.toggleAutoHideControls()
        }
      })
      Divider().width('100%').color(this.themeDivider).margin({ left: 24, right: 24 })
      MoreSheetToggleRow('背景取色', this.bgColorEnabled, (v) => {
        if (v !== this.bgColorEnabled) {
          this.toggleBgColor()
        }
      })
      Divider().width('100%').color(this.themeDivider).margin({ left: 24, right: 24 })
      MoreSheetRow($r('sys.symbol.share'), '分享歌曲', () => {
        this.shareSong()
      }, true)
    }.width('100%')
  }

  @Builder
  PlaylistPickerContent() {
    Column() {
      Text('选择歌单')
        .fontSize(17)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({
          left: 24,
          right: 24,
          top: 16,
          bottom: 12
        })
      if (this.playlists.length === 0) {
        Column({ space: 12 }) {
          Text('暂无歌单').fontSize(14).fontColor(this.themeTextSecondary)
        }.width('100%').padding(24)
      } else {
        ForEach(this.playlists, (playlist: Playlist) => {
          Row({ space: 12 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(18).fontColor([this.themePrimary])
            }
            .width(36)
            .height(36)
            .borderRadius(8)
            .backgroundColor(this.themePlaceholder)
            .justifyContent(FlexAlign.Center)

            Column({ space: 2 }) {
              Text(playlist.name).fontSize(15).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium)
              Text(`${playlist.songCount} 首`).fontSize(12).fontColor(this.themeTextSecondary)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }
          .width('100%')
          .padding({
            left: 24,
            right: 24,
            top: 12,
            bottom: 12
          })
          .onClick(() => {
            this.addToPlaylist(playlist)
          })
        })
      }
      Column().height(16)
    }
  }

  @Builder
  LyricsAlignPickerContent() {
    Column() {
      Text('歌词排列')
        .fontSize(17)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({
          left: 24,
          right: 24,
          top: 16,
          bottom: 12
        })
      AlignRow('左对齐', $r('sys.symbol.text_alignleft'), this.lyricsAlign === 'left', () => {
        this.setLyricsAlign('left')
      })
      Divider().width('100%').color(this.themeDivider).margin({ left: 24, right: 24 })
      AlignRow('居中（默认）', $r('sys.symbol.text_aligncenter'), this.lyricsAlign === 'center', () => {
        this.setLyricsAlign('center')
      })
      Divider().width('100%').color(this.themeDivider).margin({ left: 24, right: 24 })
      AlignRow('右对齐', $r('sys.symbol.text_alignright'), this.lyricsAlign === 'right', () => {
        this.setLyricsAlign('right')
      })
      Column().height(16)
    }
  }

  @Builder
  QueuePopupBuilder() {
    Column() {
      Row() {
        Text('播放列表').fontSize(16).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Bold)
        Blank().layoutWeight(1)
        Row() {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([this.themeTextSecondary])
        }.width(32).height(32).justifyContent(FlexAlign.Center).onClick(() => {
          this.showQueuePopup = false
        })
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 12,
        bottom: 12
      })

      Divider().width('100%').color(this.themeDivider)

      if (this.queue.length === 0) {
        Column() {
          Text('暂无歌曲').fontSize(14).fontColor(this.themeTextSecondary)
        }
        .width('100%').height(120).justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.queue, (track: SongInfo, index?: number) => {
            ListItem() {
              Row({ space: 10 }) {
                if ((index ?? 0) === this.queueIndex) {
                  SymbolGlyph($r('sys.symbol.waveform')).fontSize(18).fontColor([this.themePrimary]).width(24)
                } else {
                  Text(`${(index ?? 0) + 1}`)
                    .fontSize(13)
                    .fontColor(this.themeTextSecondary)
                    .width(24)
                    .textAlign(TextAlign.Center)
                }
                CoverImage({
                  url: track.coverUrl,
                  coverWidth: 40,
                  coverHeight: 40,
                  radius: 6
                })
                Column({ space: 2 }) {
                  Text(track.songName)
                    .fontSize(14)
                    .fontColor((index ?? 0) === this.queueIndex ? this.themePrimary : this.themeTextPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(track.artist)
                    .fontSize(11)
                    .fontColor(this.themeTextSecondary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)

                Row() {
                  SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([this.themeTextSecondary])
                }.width(32).height(32).justifyContent(FlexAlign.Center).onClick(() => {
                  this.removeFromQueue(index ?? 0)
                })
              }
              .width('100%')
              .padding({
                left: 16,
                right: 8,
                top: 8,
                bottom: 8
              })
            }.onClick(() => {
              const idx = index ?? 0
              if (idx !== this.queueIndex) {
                AppStorage.setOrCreate(PlayerKeys.QUEUE_INDEX, idx)
                const track = this.queue[idx]
                if (track) {
                  this.playNewTrack(track)
                }
              }
            })
          })
        }.width('100%').height(320).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring)
      }
    }.width('100%').backgroundColor(this.themeCardBg).borderRadius(12).shadow({ radius: 16, color: '#00000020', offsetY: 4 })
  }
}

// ================== 通用 Builder 函数（复用 MoreSheet 里的行） ==================

@Builder
function MoreSheetRow(icon: Resource, text: string, onClick: () => void, last?: boolean) {
  Row({ space: 12 }) {
    SymbolGlyph(icon).fontSize(20).fontColor([$r('sys.color.ohos_id_color_primary')])
    Text(text).fontSize(16).fontColor($r('sys.color.ohos_id_color_text_primary')).layoutWeight(1)
  }
  .width('100%')
  .padding({
    left: 24,
    right: 24,
    top: 16,
    bottom: last ? 24 : 16
  })
  .onClick(() => {
    onClick()
  })
}

@Builder
function MoreSheetToggleRow(text: string, isOn: boolean, onChange: (v: boolean) => void) {
  Row({ space: 12 }) {
    SymbolGlyph($r('sys.symbol.eye')).fontSize(20).fontColor([$r('sys.color.ohos_id_color_primary')])
    Text(text).fontSize(16).fontColor($r('sys.color.ohos_id_color_text_primary')).layoutWeight(1)
    Toggle({ type: ToggleType.Switch, isOn: isOn })
      .selectedColor($r('sys.color.ohos_id_color_primary'))
      .onChange((v: boolean) => {
        onChange(v)
      })
  }
  .width('100%')
  .padding({
    left: 24,
    right: 24,
    top: 16,
    bottom: 16
  })
}

@Builder
function AlignRow(text: string, icon: Resource, selected: boolean, onClick: () => void) {
  Row({ space: 12 }) {
    SymbolGlyph(icon)
      .fontSize(20)
      .fontColor([selected ? $r('sys.color.ohos_id_color_primary') : $r('sys.color.ohos_id_color_text_secondary')])
    Text(text)
      .fontSize(15)
      .fontColor(selected ? $r('sys.color.ohos_id_color_primary') : $r('sys.color.ohos_id_color_text_primary'))
      .fontWeight(selected ? FontWeight.Bold : FontWeight.Normal)
      .layoutWeight(1)
    if (selected) {
      SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([$r('sys.color.ohos_id_color_primary')])
    }
  }
  .width('100%')
  .padding({
    left: 24,
    right: 24,
    top: 14,
    bottom: 14
  })
  .onClick(() => {
    onClick()
  })
}