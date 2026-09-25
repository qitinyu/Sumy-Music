/**
 * MiniBarPlayer - 底部迷你栏播放器
 * 独立 @Component 直接订阅 AppStorage，切歌/播放状态变化时自身重新渲染，
 * 不受 HdsTabs miniBarBuilder 缓存影响。
 * V2.1.5：迷你栏不再显示歌词。
 * - 第一行：歌曲名 + 音源徽章（徽章缩小）
 * - 第二行：歌手 + 专辑（有专辑才显示），多余文本省略
 * - 右侧：上一首/播放暂停/下一首 整体左移，最右侧新增「播放列表」图标，
 *   点击从底部弹出当前播放列表（样式参考播放页右上角播放列表）。
 * 封面/歌词仍由组件自身 @State 渲染（不嵌套 CoverImage 子组件），
 * 修复 HdsTabs 迷你栏内子组件 @Prop/@State 更新不生效导致封面不刷新的问题。
 */
import { SongInfo, SourceInfo } from '../model/MusicModel'
import { PlayerStore, PlayerKeys } from '../utils/PlayerStore'
import { AudioPlayer } from '../utils/AudioPlayer'
import { MusicApi } from '../utils/MusicApi'
import { CoverFetcher } from '../utils/CoverFetcher'

import { CoverImage } from './CoverImage'
import { CompatUtils } from '../utils/CompatUtils'
import { MaterialCompat, MaterialCompatStyle } from '../utils/MaterialCompat'

@Component
export struct MiniBarPlayer {
  onExpandRequest?: () => void = undefined
  @StorageProp('currentTrack') @Watch('onTrackOrTimeChange') currentTrack: SongInfo | null = null
  @StorageProp('isPlaying') isPlaying: boolean = false
  @StorageProp('currentTime') @Watch('onTrackOrTimeChange') currentTime: number = 0
  @StorageProp('miniBarStyle') miniBarStyle: number = 1
  @StorageProp('miniBarShowSource') miniBarShowSource: boolean = true
  @StorageProp('queue') queue: SongInfo[] = []
  @StorageProp('queueIndex') queueIndex: number = 0
  @StorageProp('playMode') playMode: number = 0
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_primaryLight') themePrimaryLight: string = '#E0F0FF'
  @StorageProp('theme_cardBg') themeCardBg: string = '#FFFFFF'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'
  @StorageProp('theme_divider') themeDivider: string = '#E8E8E8'

  @State coverDisplay: string = ''
  @State showQueueSheet: boolean = false
  private lastCoverUrl: string = ''
  // V2.1.6：解析中封面 URL，防止 500ms tick 在解析窗口内重复发起
  private pendingCoverUrl: string = ''
  private supportImmersive: boolean = CompatUtils.isImmersiveSupported()
  // 版块设置-主页-播放列表设置：定位播放歌曲（默认关闭）
  @StorageProp('queueLocatePlaying') queueLocatePlaying: boolean = false
  // 播放列表弹窗滚动器（打开弹窗时定位播放中歌曲）
  private queueSheetScroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.resolveCover()
  }

  onTrackOrTimeChange(): void {
    this.resolveCover()
  }

  // 切歌时解析封面（与播放状态同一 @State 更新管线，确保迷你栏内生效）
  private resolveCover(): void {
    const track: SongInfo | null = this.currentTrack
    const url: string = track ? track.coverUrl : ''
    // 同一封面已成功解析则跳过（时间 tick 每 500ms 触发，避免重复异步解析）
    if (url === this.lastCoverUrl && this.coverDisplay.length > 0) {
      return
    }
    // 同一封面解析中：跳过，避免 tick 在解析窗口内重复发起
    if (url === this.lastCoverUrl && url === this.pendingCoverUrl) {
      return
    }
    this.lastCoverUrl = url
    // V2.1.6：切歌即时切换封面源——清掉旧封面，回退显示新 URL（普通 http 直接可加载）或占位图
    this.coverDisplay = ''
    if (!url || url.length === 0) {
      this.pendingCoverUrl = ''
      return
    }
    this.pendingCoverUrl = url
    CoverFetcher.resolve(url).then((resolved: string) => {
      // 期间已切歌：丢弃旧结果
      if (this.pendingCoverUrl !== url) {
        return
      }
      this.pendingCoverUrl = ''
      const now: SongInfo | null = this.currentTrack
      if (now && now.coverUrl === url && resolved.length > 0) {
        this.coverDisplay = resolved
      }
    }).catch((_e: Error) => {
      if (this.pendingCoverUrl === url) {
        this.pendingCoverUrl = ''
      }
    })
  }

  private async playTrack(track: SongInfo): Promise<void> {
    let playUrl: string = track.playUrl
    if (!playUrl && track.source !== 'local') {
      playUrl = await MusicApi.getPlayUrl(track.songId, track.source, track)
    }
    if (!playUrl) {
      // 真正停掉 AVPlayer（PlayerStore.pause 只改 AppStorage 标记，旧歌会继续响）
      await AudioPlayer.getInstance().pause()
      this.getUIContext().getPromptAction().showToast({ message: '无法获取播放链接', duration: 1500 })
      return
    }
    track.playUrl = playUrl
    PlayerStore.play(track)
    AudioPlayer.getInstance().setCurrentSong(track)
    await AudioPlayer.getInstance().play(playUrl)
  }

  private async handlePrevious(): Promise<void> {
    // 统一走 AudioPlayer 切歌：带取链失败自动跳下一首、防抖（代际）与真实暂停
    await AudioPlayer.getInstance().playPrevious()
  }

  private async handleNext(): Promise<void> {
    await AudioPlayer.getInstance().playNext()
  }

  // 点击播放列表内的歌曲：切到该队列位置并播放
  private async playTrackAt(index: number): Promise<void> {
    const queue = PlayerStore.getQueue()
    const track = queue[index]
    if (!track) {
      return
    }
    AppStorage.setOrCreate(PlayerKeys.QUEUE_INDEX, index)
    this.showQueueSheet = false
    await this.playTrack(track)
  }

  // 从播放列表移除（参考播放页右上角播放列表的移除逻辑）
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
      this.showQueueSheet = false
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
        this.playTrack(track)
      }
      return
    }

    AppStorage.setOrCreate(PlayerKeys.QUEUE, newQueue)
    AppStorage.setOrCreate(PlayerKeys.QUEUE_INDEX, newIndex)
  }

  // 打开播放列表弹窗时自动定位/跳转正在播放的歌曲（受"播放列表设置-定位播放歌曲"开关控制）
  private locateQueuePlaying(): void {
    const idx: number = this.queueIndex
    if (idx <= 0 || idx >= this.queue.length) {
      return
    }
    const scroller: Scroller = this.queueSheetScroller
    setTimeout(() => {
      scroller.scrollToIndex(idx, true, ScrollAlign.CENTER)
    }, 250)
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

  // 第二行：歌手 + 专辑（有专辑才拼接）
  private getArtistAlbum(): string {
    const track = this.currentTrack
    if (!track) {
      return '轻触开始播放'
    }
    const artist: string = track.artist ?? ''
    const album: string = track.album ?? ''
    if (album.length > 0) {
      return artist.length > 0 ? `${artist} - ${album}` : album
    }
    return artist.length > 0 ? artist : '轻触开始播放'
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

  private getPlayModeLabel(): string {
    switch (this.playMode) {
      case 0: return '顺序播放'
      case 1: return '随机播放'
      case 2: return '单曲循环'
      default: return '列表循环'
    }
  }

  private togglePlayMode(): void {
    PlayerStore.togglePlayMode()
    this.getUIContext().getPromptAction().showToast({ message: PlayerStore.getPlayModeLabel(), duration: 1500 })
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
    .bindSheet($$this.showQueueSheet, this.QueueSheetContent(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: false,
      backgroundColor: Color.Transparent,
      systemMaterial: this.supportImmersive ? MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK) : undefined,
    })
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

      // 中间：第一行 歌曲名；第二行 歌手+专辑 + 音源徽章（徽章在歌手右侧）
      Column({ space: 2 }) {
        Text(this.currentTrack ? this.currentTrack.songName : '暂无播放')
          .fontSize(14)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.MARQUEE })
          .width('100%')

        Row({ space: 5 }) {
          Text(this.getArtistAlbum())
            .fontSize(12)
            .fontColor(this.themeTextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (this.miniBarShowSource && this.currentTrack && this.currentTrack.source &&
            this.currentTrack.source.length > 0) {
            Text(SourceInfo.getAbbr(this.resolveDisplaySource(this.currentTrack)))
              .fontSize(9)
              .fontColor(Color.White)
              .backgroundColor(SourceInfo.getColor(this.resolveDisplaySource(this.currentTrack)))
              .borderRadius(3)
              .padding({ left: 3, right: 3, top: 1, bottom: 1 })
              .maxLines(1)
              .flexShrink(0)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 右侧：上一首 / 播放暂停 / 下一首（整体左移，为最右侧播放列表图标腾出位置）
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
      .alignItems(VerticalAlign.Center)

      // 最右侧：播放列表图标（与下一首图标同等大小）
      Image($rawfile('yylb.svg'))
        .width(16)
        .height(16)
        .objectFit(ImageFit.Contain)
        .onClick(() => {
          this.showQueueSheet = true
          // 播放列表设置-定位播放歌曲开启时，弹窗打开自动定位到播放中的歌曲
          if (this.queueLocatePlaying) {
            this.locateQueuePlaying()
          }
        })
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

  // 底部播放列表弹窗（样式参考播放页右上角播放列表）
  @Builder
  QueueSheetContent() {
    Column() {
      // 头部：标题 + 播放模式 + 关闭
      Row() {
        Text(`播放列表(${this.queue.length})`)
          .fontSize(16)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Bold)

        Blank().layoutWeight(1)

        Text(this.getPlayModeLabel())
          .fontSize(12)
          .fontColor(this.themePrimary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(this.themePrimaryLight)
          .borderRadius(10)
          .onClick(() => {
            this.togglePlayMode()
          })
      }
      .width('100%')
      .padding({ left: 16, right: 8, top: 12, bottom: 8 })

      Divider().width('100%').color(this.themeDivider)

      if (this.queue.length === 0) {
        Column() {
          Text('暂无歌曲')
            .fontSize(14)
            .fontColor(this.themeTextSecondary)
        }
        .width('100%')
        .height(120)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ scroller: this.queueSheetScroller }) {
          ForEach(this.queue, (track: SongInfo, index?: number) => {
            ListItem() {
              Row({ space: 10 }) {
                if ((index ?? 0) === this.queueIndex) {
                  SymbolGlyph($r('sys.symbol.waveform'))
                    .fontSize(16)
                    .fontColor([this.themePrimary])
                    .width(20)
                } else {
                  Text(`${(index ?? 0) + 1}`)
                    .fontSize(13)
                    .fontColor(this.themeTextSecondary)
                    .width(20)
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
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

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
              .padding({ left: 16, right: 4, top: 8, bottom: 8 })
            }
            .onClick(() => {
              this.playTrackAt(index ?? 0)
            })
          }, (track: SongInfo) => `${track.songId}_${track.source}_${track.playUrl}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
  }
}
