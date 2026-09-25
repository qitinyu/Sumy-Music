// Sumy Music 播放详情页 - Overlay 版 (已修复进度条问题)
import { SongInfo, LyricLine, Playlist, SourceInfo } from '../model/MusicModel'
import { AudioPlayer } from '../utils/AudioPlayer'
import { MusicApi } from '../utils/MusicApi'
import { PlayerStore, PlayerKeys } from '../utils/PlayerStore'
import { DatabaseHelper } from '../database/DatabaseHelper'

import { CompatUtils } from '../utils/CompatUtils'
import { MaterialCompat, MaterialCompatStyle } from '../utils/MaterialCompat'
import { hdsEffect } from '@kit.UIDesignKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { systemShare } from '@kit.ShareKit'
import { uniformTypeDescriptor as utd } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { CoverImage } from '../components/CoverImage'
import { LocalTagEnricher } from '../utils/LocalTagEnricher'
import { playLog } from '../utils/PlayLog'
import { StatusBarManager } from '../utils/StatusBarManager'

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
  @State sliderValue: number = 0
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
  @State lyricPullOffset: number = 0
  @State lyricPullHint: string = ''
  @State lyricsViewHeight: number = 600
  private lyricsScroller: Scroller = new Scroller()
  // 版块设置-主页-播放列表设置：定位播放歌曲（默认关闭）
  @StorageProp('queueLocatePlaying') queueLocatePlaying: boolean = false
  // 播放列表弹窗滚动器（打开弹窗时定位播放中歌曲）
  private queueSheetScroller: Scroller = new Scroller()
  private progressTimer: number = -1
  private controlsTimer: number = -1
  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private dragTime: number = 0
  private supportImmersive: boolean = CompatUtils.isImmersiveSupported()
  private onSeekDoneBound: (time: number) => void = (_t: number) => {}
  // V2.1.6：同曲守卫（source+songId），区分真切歌与封面等字段异步补全触发的同曲刷新
  private lastTrackKey: string = ''

  aboutToAppear(): void {
    this.playModeLocal = this.playMode
    this.loadSettings()
    if (this.currentTrack) {
      this.loadLyrics()
      this.lastTrackKey = this.currentTrack.source + '|' + this.currentTrack.songId
    }
    this.startProgressTimer()
    this.setupPlayerCallbacks()
    if (this.autoHideControls && this.swiperIndex === 1) {
      this.resetControlsTimer()
    }
  }

  // 切歌（含控制中心上一首/下一首命令）时联动：重载歌词、重置进度与歌词滚动
  onTrackChanged(): void {
    // V2.1.7：切歌/封面异步补全后背景可能变化，同步校正状态栏文字色
    this.applyPlayerStatusBar()
    if (!this.currentTrack) {
      this.lastTrackKey = ''
      return
    }
    // V2.1.6：同曲刷新（封面异步补全触发 refreshCurrentTrack）不重置进度/歌词
    const trackKey: string = this.currentTrack.source + '|' + this.currentTrack.songId
    if (trackKey === this.lastTrackKey) {
      return
    }
    this.lastTrackKey = trackKey
    this.loadLyrics()
    this.progress = 0
    this.sliderValue = 0
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
    const player = AudioPlayer.getInstance()
    player.removeSeekDoneListener(this.onSeekDoneBound)
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
    // V2.1.7：按实际背景校正状态栏文字色（背景取色且有封面→白字，否则跟随主题背景）
    this.applyPlayerStatusBar()
    const autoHide = await this.db.getSetting('autoHideControls')
    if (autoHide === 'true') {
      this.autoHideControls = true
    }
  }

  // V2.1.7：播放页状态栏文字色跟随实际背景——背景取色且有封面为模糊深底（白字），否则按主题背景判定
  private applyPlayerStatusBar(): void {
    const hasCover: boolean = this.bgColorEnabled && this.currentTrack !== null && this.currentTrack.coverUrl.length > 0
    StatusBarManager.applyForBackground(hasCover ? '#1A1A1A' : this.themeBg)
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

  // seekDone 回调：进度/时间推进、播放结束自动切歌、错误处理均由 AudioPlayer 中央化处理，
  // 这里仅负责拖动释放后把实际落点写回进度条并解锁 isSeeking
  private setupPlayerCallbacks(): void {
    const player = AudioPlayer.getInstance()

    this.onSeekDoneBound = (seekTime: number) => {
      PlayerStore.updateTime(seekTime)
      const dur = this.duration > 0 ? this.duration : player.duration
      if (dur > 0) {
        this.progress = Math.min(seekTime, dur) / dur
        // 拖动释放后 seekDone 回写实际位置到滑块，避免与拖动值打架
        this.sliderValue = this.progress
      }
      this.isSeeking = false
    }

    player.addSeekDoneListener(this.onSeekDoneBound)
  }

  private async playNewTrack(track: SongInfo): Promise<void> {
    playLog('播放', `开始播放: ${track.songName} - ${track.artist} source=${track.source}`)
    let playUrl = track.playUrl
    if (!playUrl && track.source !== 'local') {
      playLog('播放', `开始在线取链 source=${track.source} songId=${track.songId}`)
      const urlStart: number = Date.now()
      playUrl = await MusicApi.getPlayUrl(track.songId, track.source, track)
      const urlCost: number = Date.now() - urlStart
      playLog('播放', `取链完成 source=${track.source} 耗时=${urlCost}ms ${playUrl.length > 0 ? `url=${playUrl.substring(0, 80)}` : '链接为空'}`)
    }
    if (!playUrl) {
      const err: string = MusicApi.lastError.length > 0 ? MusicApi.lastError : '未获取到播放链接'
      playLog('播放', `取链失败，无法播放: ${err}`)
      // 真正停掉 AVPlayer（PlayerStore.pause 只改 AppStorage 标记，旧歌会继续响）
      await AudioPlayer.getInstance().pause()
      this.getUIContext().getPromptAction().showToast({ message: `无法播放: ${track.songName}`, duration: 1500 })
      return
    }
    track.playUrl = playUrl
    PlayerStore.play(track)
    AudioPlayer.getInstance().setCurrentSong(track)
    // 歌词加载与进度重置由 onTrackChanged（@Watch currentTrack）统一处理
    await AudioPlayer.getInstance().play(playUrl)
    playLog('播放', `播放器已提交 URL，等待就绪 source=${track.source}`)
  }

  private async loadLyrics(): Promise<void> {
    if (!this.currentTrack) {
      return
    }
    const cur: SongInfo = this.currentTrack
    playLog('歌词', `开始获取歌词 songName=${cur.songName} source=${cur.source}`)
    // 本地音乐：内嵌歌词优先，缺失时按歌名+歌手联网补全（LocalTagEnricher）
    if (cur.source === 'local') {
      const localLrc: string = await LocalTagEnricher.ensureLyric(cur)
      if (localLrc.length > 0) {
        playLog('歌词', `本地内嵌歌词成功 len=${localLrc.length}`)
        this.setLyricsFromRaw(localLrc)
        return
      }
    }
    // 非本地或联网补全仍无歌词：走插件获取
    try {
      const raw = await MusicApi.getLyrics(cur.songId, cur.source, cur)
      if (raw && raw.length > 0) {
        playLog('歌词', `插件歌词成功 len=${raw.length}`)
        this.setLyricsFromRaw(raw)
      } else {
        playLog('歌词', '歌词为空（该源可能无歌词数据）')
      }
    } catch (e) {
      console.error('[FullPlayerPage] loadLyrics failed', e)
      playLog('歌词', `歌词获取异常: ${String(e)}`)
    }
  }

  /** 解析 LRC 原文并写入播放状态（去重相邻相同行） */
  private setLyricsFromRaw(raw: string): void {
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

  private startProgressTimer(): void {
    this.progressTimer = setInterval(() => {
      if (!this.isSeeking) {
        if (this.duration > 0) {
          this.progress = this.currentTime / this.duration
          this.sliderValue = this.progress
        } else {
          this.progress = 0
          this.sliderValue = 0
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
    // 拖动进度条时按预览时间（dragTime）定位歌词，释放后由 seekDone 回到真实时间
    const t: number = this.getDisplayTime()
    for (let i = this.lyrics.length - 1; i >= 0; i--) {
      if (t >= this.lyrics[i].time) {
        if (i !== this.currentLyricIndex) {
          this.currentLyricIndex = i
          const midIndex = Math.max(0, i - 4)
          this.lyricsScroller.scrollToIndex(midIndex)
        }
        break
      }
    }
  }

  private resolveDisplaySource(track: SongInfo): string {
    if (track.rawData) {
      try {
        const obj: Record<string, Object> = JSON.parse(track.rawData) as Record<string, Object>
        const platform = obj['__platform']
        if (typeof platform === 'string' && platform.length > 0) {
          return platform
        }
      } catch (_e) {}
    }
    return track.source
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
    // 允许拖到开头（position 接近 0 也要能 seek），并钳制到 [0,1]
    const pos = Math.max(0, Math.min(1, position))
    const player = AudioPlayer.getInstance()
    const dur = this.duration > 0 ? this.duration : player.duration
    if (dur <= 0) {
      // 无时长信息：仍把界面进度同步到拖动位置并解锁，避免「拖了没反应」；
      // 播放器侧无时长时 seek 也无法定位，属预期，但要让进度条跟手。
      console.warn('[doSeek] duration<=0，仅同步进度不 seek, dur=' + dur)
      this.progress = pos
      this.isSeeking = false
      return
    }

    const time = pos * dur
    this.isSeeking = true
    this.progress = pos
    this.sliderValue = pos
    this.dragTime = time
    // seekDone 回调会自动解锁 isSeeking；但播放器未 prepared 时 seekDone 不会触发，
    // 加超时兜底防止进度条永久锁定
    player.seekTo(time).catch(() => {
    })
    this.updateCurrentLyricIndex()
    setTimeout(() => {
      if (this.isSeeking) {
        PlayerStore.updateTime(time)
        this.sliderValue = pos
        this.progress = pos
        this.isSeeking = false
      }
    }, 1500)
  }

  private async handlePrevious(): Promise<void> {
    // 统一走 AudioPlayer 切歌：带取链失败自动跳下一首、防抖（代际）与真实暂停
    await AudioPlayer.getInstance().playPrevious()
  }

  private async handleNext(): Promise<void> {
    await AudioPlayer.getInstance().playNext()
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
    this.sliderValue = this.progress
    if (!this.isPlaying) {
      await player.resume()
      PlayerStore.resume()
    }
  }

  private async showPlaylistSheet(): Promise<void> {
    const list: Playlist[] = await this.db.getPlaylists()
    // 歌单自身未设封面时回退取第一首歌的封面（与歌曲弹窗/轩窗歌单列表一致）
    for (let i = 0; i < list.length; i++) {
      const p: Playlist = list[i]
      if (!p.coverUrl || p.coverUrl.length === 0) {
        const songs: SongInfo[] = await this.db.getPlaylistSongs(p.id)
        if (songs.length > 0 && songs[0].coverUrl.length > 0) {
          p.coverUrl = songs[0].coverUrl
        }
      }
    }
    this.playlists = list
    this.showPlaylistPicker = true
    this.showMoreSheet = false
  }

  private async addToPlaylist(playlist: Playlist): Promise<void> {
    if (!this.currentTrack) {
      return
    }
    const result = await this.db.addSongToPlaylist(playlist.id, this.currentTrack)
    if (result) {
      this.getUIContext().getPromptAction().showToast({ message: `已添加到「${playlist.name}」`, duration: 2000 })
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '添加失败，请重试', duration: 2000 })
    }
    this.showPlaylistPicker = false
  }

  private async setLyricsAlign(align: string): Promise<void> {
    this.lyricsAlign = align
    await this.db.setSetting('lyricsAlign', align)
    this.showLyricsAlignPicker = false
    this.getUIContext().getPromptAction().showToast(
      { message: `歌词对齐：${align === 'left' ? '左对齐' : align === 'right' ? '右对齐' : '居中'}`, duration: 1500 })
  }

  private async toggleBgColor(): Promise<void> {
    this.bgColorEnabled = !this.bgColorEnabled
    await this.db.setSetting('bgColorEnabled', this.bgColorEnabled ? 'true' : 'false')
    this.applyPlayerStatusBar()
    this.showMoreSheet = false
    this.getUIContext().getPromptAction().showToast({ message: this.bgColorEnabled ? '背景取色已开启' : '背景取色已关闭', duration: 1500 })
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
    this.getUIContext().getPromptAction().showToast({ message: this.autoHideControls ? '组件隐藏已开启' : '组件隐藏已关闭', duration: 1500 })
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
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
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
        this.getUIContext().getPromptAction().showToast({ message: '分享面板拉起失败，已复制到剪贴板', duration: 2000 })
      } catch (_e) {
        this.getUIContext().getPromptAction().showToast({ message: '分享失败', duration: 2000 })
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
      this.showListSheet = false
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

  // 播放列表弹窗内点击歌曲：切到该队列位置并播放
  private playTrackInQueue(index: number): void {
    if (index < 0 || index >= this.queue.length) {
      return
    }
    AppStorage.setOrCreate(PlayerKeys.QUEUE_INDEX, index)
    const track = this.queue[index]
    if (track) {
      this.playNewTrack(track)
    }
  }

  // 🆕 获取显示时间：拖动时显示预览时间，释放后显示实际时间
  private getDisplayTime(): number {
    if (this.isSeeking) {
      return this.dragTime
    }
    return this.currentTime
  }

  /**
   * 播放页圆形图标按钮（统一沉浸光感）：
   * 去掉原 1px themeTextPrimary 黑色描边与不透明卡片底（沉浸材质被不透明底盖住等于白涂），
   * 改为透明底 + 系统沉浸材质（API 26+），低版本用 backgroundEffect 模拟沉浸光感。
   */
  @Builder
  PlayerIconButton(icon: Resource, iconSize: number, btnSize: number, click: () => void) {
    Row() {
      SymbolGlyph(icon).fontSize(iconSize).fontColor([this.themeTextPrimary])
    }
    .width(btnSize)
    .height(btnSize)
    .borderRadius(btnSize / 2)
    .backgroundColor(Color.Transparent)
    .systemMaterial(this.supportImmersive ? MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN) : undefined)
    .backgroundEffect(this.supportImmersive ? undefined : MaterialCompat.effect(this.isDarkMode, this.themeCardBg, MaterialCompatStyle.THIN))
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pressShadow(hdsEffect.PressShadowType.BLEND_WHITE)
      .pointLight({
        sourceType: hdsEffect.PointLightSourceType.SOFT,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        options: {
          color: this.themePrimary,
          intensity: 0.6,
          height: 60,
          bloom: 0.3
        }
      })
      .buildEffect())
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      click()
    })
  }

  // V2.0.8：rawfile 图标版圆形图标按钮（down/more 等自定义 svg），样式与 PlayerIconButton 一致
  @Builder
  PlayerRawIconButton(icon: Resource, iconSize: number, btnSize: number, click: () => void) {
    Row() {
      Image(icon)
        .width(iconSize)
        .height(iconSize)
        .objectFit(ImageFit.Contain)
        .fillColor(this.themeTextPrimary)
    }
    .width(btnSize)
    .height(btnSize)
    .borderRadius(btnSize / 2)
    .backgroundColor(Color.Transparent)
    .systemMaterial(this.supportImmersive ? MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN) : undefined)
    .backgroundEffect(this.supportImmersive ? undefined : MaterialCompat.effect(this.isDarkMode, this.themeCardBg, MaterialCompatStyle.THIN))
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pressShadow(hdsEffect.PressShadowType.BLEND_WHITE)
      .pointLight({
        sourceType: hdsEffect.PointLightSourceType.SOFT,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        options: {
          color: this.themePrimary,
          intensity: 0.6,
          height: 60,
          bloom: 0.3
        }
      })
      .buildEffect())
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      click()
    })
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
          this.PlayerRawIconButton($rawfile('down.svg'), 18, 32, () => {
            this.doBack()
          })

          Blank().layoutWeight(1)

          // 右上角：更多（从底部弹窗，复用统一沉浸光感图标按钮）
          this.PlayerRawIconButton($rawfile('more.svg'), 18, 32, () => {
            this.showMoreSheet = true
          })
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
              this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                this.dragOffset = 0
              })
            })
        )

        // ======================== 修复③：Slider ========================
        Column() {
          Column({ space: 4 }) {
            Slider({
              value: this.sliderValue,
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
                    this.dragTime = this.currentTime
                    break
                  case SliderChangeMode.Moving: {
                    this.isSeeking = true
                    const dur = this.duration > 0 ? this.duration : AudioPlayer.getInstance().duration
                    // 拖动时只更新滑块位置，不写 progress，避免与 playback 定时器互相覆盖
                    this.sliderValue = value
                    this.progress = value
                    this.dragTime = value * dur
                    this.updateCurrentLyricIndex()
                    break
                  }
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
          showClose: false,
          systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK)
        })
      Row().width(1).height(1)
        .bindSheet($$this.showMoreSheet, this.MoreSheetContent(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
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
            .textOverflow({ overflow: TextOverflow.MARQUEE })
          if (this.currentTrack && this.currentTrack.source && this.currentTrack.source.length > 0) {
            Text(SourceInfo.getAbbr(this.resolveDisplaySource(this.currentTrack)))
              .fontSize(11)
              .fontColor(Color.White)
              .backgroundColor(SourceInfo.getColor(this.resolveDisplaySource(this.currentTrack)))
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
        .textOverflow({ overflow: TextOverflow.MARQUEE })
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
            this.getUIContext().animateTo({ duration: 200 }, () => {
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
          this.getUIContext().animateTo({ duration: 200 }, () => {
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
      Row() {
        // 播放模式（直接内联构建：@Builder 参数不响应 @State 变化，会导致图标不更新）
        this.PlayModeButton()

        // 上一首
        this.PlayerIconButton($r('sys.symbol.backward_end_fill'), 18, 36, () => {
          this.handlePrevious()
        })

        // 播放/暂停（中间，更大，图标在 @Builder 内部读取 isPlaying）
        this.PlayPauseButton()

        // 下一首
        this.PlayerIconButton($r('sys.symbol.forward_end_fill'), 18, 36, () => {
          this.handleNext()
        })

        // 播放列表（右下角，yylb 图标，从底部弹窗弹出，沉浸光感）
        this.QueueIconButton()
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
  PlayPauseButton() {
    Row() {
      // 图标选择写在 @Builder 内部，确保 isPlaying 变化时重新渲染（参数传入不响应 @State）
      SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
        .fontSize(24)
        .fontColor([this.themeTextPrimary])
    }
    .width(52)
    .height(52)
    .borderRadius(26)
    .backgroundColor(Color.Transparent)
    .systemMaterial(this.supportImmersive ? MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN) : undefined)
    .backgroundEffect(this.supportImmersive ? undefined : MaterialCompat.effect(this.isDarkMode, this.themeCardBg, MaterialCompatStyle.THIN))
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pressShadow(hdsEffect.PressShadowType.BLEND_WHITE)
      .pointLight({
        sourceType: hdsEffect.PointLightSourceType.SOFT,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        options: {
          color: this.themePrimary,
          intensity: 0.6,
          height: 60,
          bloom: 0.3
        }
      })
      .buildEffect())
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.togglePlayPause()
    })
  }

  // 播放模式按钮：图标/状态读取写在 @Builder 内部，确保 @State 变化时重新渲染
  @Builder
  PlayModeButton() {
    Row() {
      SymbolGlyph(this.getPlayModeIconLocal())
        .fontSize(16)
        .fontColor([this.themeTextPrimary])
    }
    .width(36)
    .height(36)
    .borderRadius(18)
    .backgroundColor(Color.Transparent)
    .systemMaterial(this.supportImmersive ? MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN) : undefined)
    .backgroundEffect(this.supportImmersive ? undefined : MaterialCompat.effect(this.isDarkMode, this.themeCardBg, MaterialCompatStyle.THIN))
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pressShadow(hdsEffect.PressShadowType.BLEND_WHITE)
      .pointLight({
        sourceType: hdsEffect.PointLightSourceType.SOFT,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        options: {
          color: this.themePrimary,
          intensity: 0.6,
          height: 60,
          bloom: 0.3
        }
      })
      .buildEffect())
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.togglePlayMode()
      this.getUIContext().getPromptAction().showToast({ message: this.getPlayModeLabelLocal(), duration: 1500 })
    })
  }

  // 播放列表按钮（yylb 图标，与其它控制按钮统一沉浸光感）
  @Builder
  QueueIconButton() {
    Row() {
      Image($rawfile('yylb.svg'))
        .width(18)
        .height(18)
        .objectFit(ImageFit.Contain)
        .fillColor(this.themeTextPrimary)
    }
    .width(36)
    .height(36)
    .borderRadius(18)
    .backgroundColor(Color.Transparent)
    .systemMaterial(this.supportImmersive ? MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN) : undefined)
    .backgroundEffect(this.supportImmersive ? undefined : MaterialCompat.effect(this.isDarkMode, this.themeCardBg, MaterialCompatStyle.THIN))
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pressShadow(hdsEffect.PressShadowType.BLEND_WHITE)
      .pointLight({
        sourceType: hdsEffect.PointLightSourceType.SOFT,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        options: {
          color: this.themePrimary,
          intensity: 0.6,
          height: 60,
          bloom: 0.3
        }
      })
      .buildEffect())
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showListSheet = true
      // 播放列表设置-定位播放歌曲开启时，弹窗打开自动定位到播放中的歌曲
      if (this.queueLocatePlaying) {
        this.locateQueuePlaying()
      }
    })
  }

  // 打开播放列表弹窗时自动定位/跳转正在播放的歌曲（行高：封面40 + 上下内边距8×2 = 56）
  private locateQueuePlaying(): void {
    const idx: number = this.queueIndex
    if (idx <= 0 || idx >= this.queue.length) {
      return
    }
    const scroller: Scroller = this.queueSheetScroller
    setTimeout(() => {
      scroller.scrollTo({ xOffset: 0, yOffset: idx * 56, animation: { duration: 300, curve: Curve.EaseOut } })
    }, 250)
  }

  @Builder
  PlaylistSheetContent() {
    Column() {
      Row() {
        Text(`播放列表(${this.queue.length})`)
          .fontSize(18)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Bold)
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
            this.getUIContext().getPromptAction().showToast({ message: this.getPlayModeLabelLocal(), duration: 1500 })
          })
      }
      .width('100%')
      .padding({
        left: 24,
        right: 24,
        top: 16,
        bottom: 12
      })

      Scroll(this.queueSheetScroller) {
        Column({ space: 0 }) {
          ForEach(this.queue, (track: SongInfo, index?: number) => {
            Row({ space: 10 }) {
              if ((index ?? 0) === this.queueIndex) {
                SymbolGlyph($r('sys.symbol.waveform'))
                  .fontSize(16)
                  .fontColor([this.themePrimary])
                  .width(24)
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
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(14)
                  .fontColor([this.themeTextSecondary])
              }
              .width(28)
              .height(28)
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                this.removeFromQueue(index ?? 0)
              })
            }
            .width('100%')
            .padding({
              left: 24,
              right: 12,
              top: 8,
              bottom: 8
            })
            .onClick(() => {
              const idx = index ?? 0
              if (idx !== this.queueIndex) {
                this.playTrackInQueue(idx)
              }
            })
          }, (track: SongInfo, index?: number) => `${track.songId}_${track.source}_${index ?? 0}`)
        }
        .width('100%')
      }.layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring)
    }.width('100%').height('100%')
  }

  @Builder
  MoreSheetContent() {
    Column({ space: 0 }) {
      this.MoreSheetRow($r('sys.symbol.plus'), '添至歌单', () => {
        this.showPlaylistSheet()
      })
      Divider().width('100%').color(this.themeDivider).margin({ left: 24, right: 24 })
      this.MoreSheetRow($r('sys.symbol.text_alignleft'), '歌词排列', () => {
        this.showMoreSheet = false;
        this.showLyricsAlignPicker = true
      })
      Divider().width('100%').color(this.themeDivider).margin({ left: 24, right: 24 })
      this.MoreSheetToggleRow('组件隐藏', this.autoHideControls, (v: boolean) => {
        if (v !== this.autoHideControls) {
          this.toggleAutoHideControls()
        }
      })
      Divider().width('100%').color(this.themeDivider).margin({ left: 24, right: 24 })
      this.MoreSheetToggleRow('背景取色', this.bgColorEnabled, (v: boolean) => {
        if (v !== this.bgColorEnabled) {
          this.toggleBgColor()
        }
      })
      Divider().width('100%').color(this.themeDivider).margin({ left: 24, right: 24 })
      this.MoreSheetRow($r('sys.symbol.share'), '分享歌曲', () => {
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
            if (playlist.coverUrl && playlist.coverUrl.length > 0) {
              CoverImage({
                url: playlist.coverUrl,
                coverWidth: 36,
                coverHeight: 36,
                radius: 8
              })
              .flexShrink(0)
            } else {
              Row() {
                SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(18).fontColor([this.themePrimary])
              }
              .width(36)
              .height(36)
              .borderRadius(8)
              .backgroundColor(this.themePlaceholder)
              .justifyContent(FlexAlign.Center)
              .flexShrink(0)
            }

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
      this.AlignRow('左对齐', $r('sys.symbol.text_alignleft'), this.lyricsAlign === 'left', () => {
        this.setLyricsAlign('left')
      })
      Divider().width('100%').color(this.themeDivider).margin({ left: 24, right: 24 })
      this.AlignRow('居中（默认）', $r('sys.symbol.text_aligncenter'), this.lyricsAlign === 'center', () => {
        this.setLyricsAlign('center')
      })
      Divider().width('100%').color(this.themeDivider).margin({ left: 24, right: 24 })
      this.AlignRow('右对齐', $r('sys.symbol.text_alignright'), this.lyricsAlign === 'right', () => {
        this.setLyricsAlign('right')
      })
      Column().height(16)
    }
  }

// ================== 通用 Builder 函数（复用 MoreSheet 里的行） ==================

@Builder
MoreSheetRow(icon: Resource, text: string, onClick: () => void, last?: boolean) {
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
MoreSheetToggleRow(text: string, isOn: boolean, onChange: (v: boolean) => void) {
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
AlignRow(text: string, icon: Resource, selected: boolean, onClick: () => void) {
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
}