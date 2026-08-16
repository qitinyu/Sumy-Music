/**
 * MiniBarPlayer - 底部迷你栏播放器
 * 独立 @Component 直接订阅 AppStorage，切歌/播放状态变化时自身重新渲染，
 * 不受 HdsTabs miniBarBuilder 缓存影响。
 * V2.1.4：封面/歌词全部用组件自身 @State 渲染（不嵌套 CoverImage 子组件），
 * 修复 HdsTabs 迷你栏内子组件 @Prop/@State 更新不生效导致封面不刷新的问题。
 */
import { SongInfo, LyricLine, SourceInfo } from '../model/MusicModel'
import { PlayerStore } from '../utils/PlayerStore'
import { AudioPlayer } from '../utils/AudioPlayer'
import { MusicApi } from '../utils/MusicApi'
import { CoverFetcher } from '../utils/CoverFetcher'

@Component
export struct MiniBarPlayer {
  onExpandRequest?: () => void = undefined
  @StorageProp('currentTrack') @Watch('onTrackOrTimeChange') currentTrack: SongInfo | null = null
  @StorageProp('isPlaying') isPlaying: boolean = false
  @StorageProp('currentTime') @Watch('onTrackOrTimeChange') currentTime: number = 0
  @StorageProp('miniBarStyle') miniBarStyle: number = 1
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'

  @State currentLyric: string = ''
  @State coverDisplay: string = ''
  private lastCoverUrl: string = ''

  aboutToAppear(): void {
    this.updateCurrentLyric()
    this.resolveCover()
  }

  onTrackOrTimeChange(): void {
    this.updateCurrentLyric()
    this.resolveCover()
  }

  private updateCurrentLyric(): void {
    const lyrics = AppStorage.get('lyrics') as LyricLine[] | undefined
    if (!lyrics || lyrics.length === 0) {
      this.currentLyric = ''
      return
    }
    let text: string = ''
    for (let i = lyrics.length - 1; i >= 0; i--) {
      if (lyrics[i].time <= this.currentTime) {
        text = lyrics[i].text
        break
      }
    }
    this.currentLyric = text
  }

  // 切歌时解析封面（与歌词同一 @State 更新管线，确保迷你栏内生效）
  private resolveCover(): void {
    const track: SongInfo | null = this.currentTrack
    const url: string = track ? track.coverUrl : ''
    // 同一封面已成功解析则跳过（时间 tick 每 500ms 触发，避免重复异步解析）
    if (url === this.lastCoverUrl && this.coverDisplay.length > 0) {
      return
    }
    this.lastCoverUrl = url
    if (!url || url.length === 0) {
      this.coverDisplay = ''
      return
    }
    CoverFetcher.resolve(url).then((resolved: string) => {
      const now: SongInfo | null = this.currentTrack
      if (now && now.coverUrl === url && resolved.length > 0) {
        this.coverDisplay = resolved
      }
    }).catch((_e: Error) => {
    })
  }

  private async playTrack(track: SongInfo): Promise<void> {
    let playUrl: string = track.playUrl
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

  private getCoverSource(): ResourceStr {
    if (this.coverDisplay.length > 0) {
      return this.coverDisplay
    }
    if (this.currentTrack && this.currentTrack.coverUrl.length > 0) {
      return this.currentTrack.coverUrl
    }
    return $r('app.media.logo')
  }

  /** 将音源来源码转为中文标签（与搜索卡片一致：SourceInfo 映射） */
  private getSourceLabel(source: string): string {
    return SourceInfo.getName(source)
  }

  build() {
    Row() {
      if (this.miniBarStyle === 1) {
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
      // 左侧：歌曲封面（直接渲染，随 @State 更新）
      Image(this.getCoverSource())
        .width(36)
        .height(36)
        .borderRadius(18)
        .objectFit(ImageFit.Cover)
        .backgroundColor('#E0E0E0')
        .alt($r('app.media.logo'))

      // 中间：歌曲名 + 单行歌词预览（音源标签在歌词行最前面）
      Column({ space: 2 }) {
        Text(this.currentTrack ? this.currentTrack.songName : '暂无播放')
          .fontSize(14)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 6 }) {
          if (this.currentTrack && this.currentTrack.source && this.currentTrack.source.length > 0) {
            Text(SourceInfo.getAbbr(this.currentTrack.source))
              .fontSize(10)
              .fontColor(Color.White)
              .backgroundColor(SourceInfo.getColor(this.currentTrack.source))
              .borderRadius(4)
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .maxLines(1)
              .flexShrink(0)
          }
          Text(this.currentTrack ? this.currentLyric : '轻触开始播放')
            .fontSize(12)
            .fontColor(this.themeTextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
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
      Image(this.getCoverSource())
        .width(40)
        .height(40)
        .borderRadius(20)
        .objectFit(ImageFit.Cover)
        .backgroundColor('#E0E0E0')
        .alt($r('app.media.logo'))
    }
    .width(40)
    .height(40)
    .onClick(() => {
      // 收缩态点击仅展开迷你栏，不打开歌曲详情
      if (this.onExpandRequest) {
        this.onExpandRequest()
      }
    })
  }
}
