import { SongInfo, LyricLine } from '../model/MusicModel'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { FullPlayerPage } from './FullPlayerPage'
import { StartupDialog } from '../components/StartupDialog'
import { DesktopLyricsWindow } from '../components/DesktopLyricsWindow'
import { PlayerStore } from '../utils/PlayerStore'
import { AudioPlayer } from '../utils/AudioPlayer'
import { MusicApi } from '../utils/MusicApi'
import {
  HdsTabs,
  HdsTabsController,
  hdsMaterial,
  HdsTabsFloatingStyle,
  HdsBarStyle,
  HdsTabsBarChangeMode
} from '@kit.UIDesignKit'

import { XuanchuangTab } from './XuanchuangTab'
import { QinseTab } from './QinseTab'
import { LoushiTab } from './LoushiTab'

@Entry
@Component
struct Index {
  @State activeTab: number = 0
  @StorageProp('currentTrack') @Watch('onTrackChange') currentTrack: SongInfo | null = null
  @StorageProp('isPlaying') isPlaying: boolean = false
  @StorageProp('currentTime') @Watch('onTimeUpdate') currentTime: number = 0
  @StorageProp('showFullPlayer') @Watch('onShowFullPlayerChange') showFullPlayer: boolean = false
  @StorageProp('fullPlayerPage') fullPlayerPage: string = 'cover'
  @StorageProp('autoJumpDetail') autoJumpDetail: boolean = false
  @StorageProp('theme_bg') themeBg: string = '#F5F5F7'
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'
  @State showPlayerOverlay: boolean = false
  @State miniBarStyle: HdsBarStyle = HdsBarStyle.EXPAND
  @State currentLyric: string = ''

  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private controller: HdsTabsController = new HdsTabsController()
  @State private miniBarApplied: boolean = false

  aboutToAppear(): void {
    // 主题初始化已移至 EntryAbility.onCreate，在 UI 创建前完成
    AppStorage.setOrCreate('desktopLyrics', false)
    AppStorage.setOrCreate('lockDesktopLyrics', false)
    AppStorage.setOrCreate('multiLineLyrics', false)
    AppStorage.setOrCreate('lyricsSize', 'standard')
    AppStorage.setOrCreate('lyricsColor', '#FFFFFF')
    AppStorage.setOrCreate('lyricsBgOpacity', 50)
    AppStorage.setOrCreate('playMode', 0)
    this.checkAnnouncementDate()
    this.loadAutoJumpSetting()
    // 默认展示展开的迷你栏
    setTimeout(() => {
      if (!this.miniBarApplied) {
        this.miniBarApplied = true
        this.controller.applyMiniBarStyle(HdsBarStyle.EXPAND)
      }
    }, 100)
  }

  private async checkAnnouncementDate(): Promise<void> {
    const lastDate: string = await this.db.getSetting('announcementDismissedDate')
    if (lastDate === this.getTodayStr()) {
      AppStorage.setOrCreate('showStartup', false)
    }
  }

  private async loadAutoJumpSetting(): Promise<void> {
    const val = await this.db.getSetting('autoJumpDetail')
    if (val === 'true') {
      AppStorage.setOrCreate('autoJumpDetail', true)
    }
  }

  private getTodayStr(): string {
    const d = new Date()
    const year: number = d.getFullYear()
    const month: string = (d.getMonth() + 1).toString().padStart(2, '0')
    const day: string = d.getDate().toString().padStart(2, '0')
    return year + '-' + month + '-' + day
  }

  private onTabChange(index: number): void {
    this.activeTab = index
  }

  private async handleStartupDismiss(dontShowToday: boolean): Promise<void> {
    if (dontShowToday) {
      await this.db.setSetting('announcementDismissedDate', this.getTodayStr())
    }
  }

  private onShowFullPlayerChange(): void {
    if (this.showFullPlayer) {
      this.showPlayerOverlay = true
    }
  }

  private onTrackChange(): void {
    if (this.currentTrack) {
      this.updateCurrentLyric()
    } else {
      this.currentLyric = ''
    }
  }

  private onTimeUpdate(): void {
    if (this.currentTrack) {
      this.updateCurrentLyric()
    }
  }

  private updateCurrentLyric(): void {
    const lyrics = AppStorage.get('lyrics') as LyricLine[] | undefined
    if (!lyrics || lyrics.length === 0) {
      this.currentLyric = ''
      return
    }
    let text = ''
    for (let i = lyrics.length - 1; i >= 0; i--) {
      if (lyrics[i].time <= this.currentTime) {
        text = lyrics[i].text
        break
      }
    }
    this.currentLyric = text
  }

  private closePlayerOverlay(): void {
    this.showPlayerOverlay = false
    AppStorage.setOrCreate('showFullPlayer', false)
  }

  onBackPress(): boolean {
    if (this.showPlayerOverlay) {
      this.closePlayerOverlay()
      return true
    }
    return false
  }

  private getBarFloatingStyle(): HdsTabsFloatingStyle {
    return {
      barBottomMargin: 20,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      miniBar: {
        miniBarBuilder: () => this.MiniBarBuilder(),
        onBarStyleChange: (style: HdsBarStyle, _tabBarStyle: HdsBarStyle, _miniBarWidth: number, _tabBarWidth: number, _mode: HdsTabsBarChangeMode) => {
          this.miniBarStyle = style
        }
      }
    }
  }

  build() {
    Stack() {
      // 顶部留出 44px 状态栏高度，HdsTabs 内容从此处开始
      Column() {
        HdsTabs({ controller: this.controller }) {
          TabContent() {
            XuanchuangTab()
          }
          .tabBar(this.buildTabBarBuilder(0, '主页', $r('sys.symbol.heart_fill')))

          TabContent() {
            QinseTab()
          }
          .tabBar(this.buildTabBarBuilder(1, '搜索', $r('sys.symbol.magnifyingglass')))

          TabContent() {
            LoushiTab()
          }
          .tabBar(this.buildTabBarBuilder(2, '设置', $r('sys.symbol.gearshape')))
        }
        .vertical(false)
        .barPosition(BarPosition.End)
        .barMode(BarMode.Fixed)
        .scrollable(false)
        .barOverlap(true)
        .onChange((index: number) => {
          this.onTabChange(index)
        })
        .barFloatingStyle(this.getBarFloatingStyle())
      }
      .width('100%')
      .height('100%')
      .padding({ top: 44 })

      StartupDialog({
        onDismiss: (dontShowToday: boolean) => {
          this.handleStartupDismiss(dontShowToday)
        },
      })

      DesktopLyricsWindow()

      // 全屏播放器 Overlay（底部上滑，渐缓动画）
      if (this.showPlayerOverlay) {
        Column() {
          FullPlayerPage({
            onClose: () => this.closePlayerOverlay()
          })
        }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.translate({ y: '100%' }).animation({ duration: 400, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBg)
  }

  @Builder
  MiniBarBuilder() {
    Row() {
      if (this.miniBarStyle === HdsBarStyle.EXPAND) {
        this.ExpandedMiniPlayer()
      } else {
        this.CollapsedMiniPlayer()
      }
    }
    .height(40)
    .padding({ left: 8, right: 8 })
  }

  @Builder
  ExpandedMiniPlayer() {
    Row({ space: 10 }) {
      // 左侧：歌曲封面
      if (this.currentTrack && this.currentTrack.coverUrl) {
        Image(this.currentTrack.coverUrl)
          .width(36)
          .height(36)
          .borderRadius(18)
          .objectFit(ImageFit.Cover)
      } else {
        Image($r('app.media.logo'))
          .width(36)
          .height(36)
          .borderRadius(18)
          .objectFit(ImageFit.Cover)
      }

      // 中间：歌曲名 + 单行歌词预览
      Column({ space: 2 }) {
        Text(this.currentTrack ? this.currentTrack.songName : '暂无播放')
          .fontSize(12)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.currentTrack ? this.currentLyric : '轻触开始播放')
          .fontSize(10)
          .fontColor(this.themeTextSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 右侧：上一首 / 播放暂停 / 下一首
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.backward_end_fill'))
          .fontSize(16)
          .fontColor([this.themeTextPrimary])
          .onClick(() => {
            this.handlePrevious()
          })

        SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
          .fontSize(20)
          .fontColor([this.themePrimary])
          .onClick(() => {
            this.togglePlay()
          })

        SymbolGlyph($r('sys.symbol.forward_end_fill'))
          .fontSize(16)
          .fontColor([this.themeTextPrimary])
          .onClick(() => {
            this.handleNext()
          })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 4, right: 4 })
    .onClick(() => {
      PlayerStore.showFullPlayer()
    })
  }

  @Builder
  CollapsedMiniPlayer() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.currentTrack && this.currentTrack.coverUrl) {
        Image(this.currentTrack.coverUrl)
          .width(40)
          .height(40)
          .borderRadius(20)
          .objectFit(ImageFit.Cover)
      } else {
        Image($r('app.media.logo'))
          .width(40)
          .height(40)
          .borderRadius(20)
          .objectFit(ImageFit.Cover)
      }
    }
    .width(40)
    .height(40)
    .onClick(() => {
      // 收缩态点击仅展开迷你栏，不打开歌曲详情
      this.controller.applyMiniBarStyle(HdsBarStyle.EXPAND)
    })
  }

  private async handlePrevious(): Promise<void> {
    const track = PlayerStore.previous()
    if (track) {
      await this.playTrack(track)
    }
  }

  private async handleNext(): Promise<void> {
    const track = PlayerStore.next()
    if (track) {
      await this.playTrack(track)
    }
  }

  private async playTrack(track: SongInfo): Promise<void> {
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
    await AudioPlayer.getInstance().play(playUrl)
  }

  @Builder
  buildTabBarBuilder(index: number, label: string, icon: Resource) {
    Column({ space: 2 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor(this.activeTab === index ? [this.themePrimary] : [this.themeTextSecondary])
      Text(label)
        .fontSize(10)
        .fontColor(this.activeTab === index ? this.themePrimary : this.themeTextSecondary)
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .height('100%')
  }

  private async togglePlay(): Promise<void> {
    if (this.isPlaying) {
      await AudioPlayer.getInstance().pause()
      PlayerStore.pause()
    } else {
      if (this.currentTrack && !this.currentTrack.playUrl && this.currentTrack.source !== 'local') {
        const url = await MusicApi.getPlayUrl(this.currentTrack!.songId, this.currentTrack!.source, this.currentTrack!)
        if (url) {
          this.currentTrack!.playUrl = url
          await AudioPlayer.getInstance().play(url)
          PlayerStore.resume()
          return
        }
      }
      await AudioPlayer.getInstance().resume()
      PlayerStore.resume()
    }
  }
}
