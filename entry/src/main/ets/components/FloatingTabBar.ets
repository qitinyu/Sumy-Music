import { SongInfo, LyricLine } from '../model/MusicModel'
import { PlayerStore } from '../utils/PlayerStore'
import { AudioPlayer } from '../utils/AudioPlayer'
import { MusicApi } from '../utils/MusicApi'
import { promptAction, uiMaterial } from '@kit.ArkUI'

@Component
export struct FloatingTabBar {
  @Prop activeTab: number = 0
  onTabChange?: (index: number) => void
  onSearch?: () => void

  @StorageProp('currentTrack') @Watch('onTrackChange') currentTrack: SongInfo | null = null
  @StorageProp('isPlaying') isPlaying: boolean = false
  @StorageProp('currentTime') @Watch('onTimeUpdate') currentTime: number = 0
  @StorageProp('duration') duration: number = 0
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'

  @State showPlayer: boolean = true
  @State currentLyric: string = ''

  onTrackChange(): void {
    if (this.currentTrack) {
      this.showPlayer = true
    }
  }

  onTimeUpdate(): void {
    if (this.showPlayer && this.currentTrack) {
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

  private async togglePlay(): Promise<void> {
    if (this.isPlaying) {
      await AudioPlayer.getInstance().pause()
      PlayerStore.pause()
    } else {
      if (this.currentTrack && !this.currentTrack.playUrl && this.currentTrack.source !== 'local') {
        const url = await MusicApi.getPlayUrl(this.currentTrack.songId, this.currentTrack.source, this.currentTrack)
        if (url) {
          this.currentTrack.playUrl = url
          await AudioPlayer.getInstance().play(url)
          PlayerStore.resume()
          return
        }
      }
      await AudioPlayer.getInstance().resume()
      PlayerStore.resume()
    }
  }

  private goToFullPlayer(): void {
    PlayerStore.showFullPlayer()
  }

  private async playTrack(track: SongInfo): Promise<void> {
    let playUrl = track.playUrl
    if (!playUrl && track.source !== 'local') {
      playUrl = await MusicApi.getPlayUrl(track.songId, track.source, track)
    }
    if (!playUrl) {
      PlayerStore.pause()
      promptAction.showToast({ message: '无法获取播放链接', duration: 1500 })
      return
    }
    track.playUrl = playUrl
    PlayerStore.play(track)

    const player = AudioPlayer.getInstance()
    player.onTimeUpdate = (time: number) => { PlayerStore.updateTime(time) }
    player.onDurationUpdate = (dur: number) => { PlayerStore.updateDuration(dur) }
    player.onPlayEnd = () => {
      const nextTrack = PlayerStore.onTrackEnd()
      if (nextTrack) {
        this.playTrack(nextTrack)
      } else {
        PlayerStore.pause()
      }
    }
    player.onError = (_error: string) => { PlayerStore.pause() }

    await player.play(playUrl)
  }

  build() {
    Row() {
      if (this.showPlayer) {
        // Left: collapsed tab bar as new mini bar
        Column() {
          if (this.activeTab === 0) {
            SymbolGlyph($r('sys.symbol.heart_fill')).fontSize(22).fontColor([this.themePrimary])
          } else if (this.activeTab === 1) {
            SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(22).fontColor([this.themePrimary])
          } else {
            SymbolGlyph($r('sys.symbol.gearshape')).fontSize(22).fontColor([this.themePrimary])
          }
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(22)
        .backgroundColor(Color.White)
        .shadow({ radius: 4, color: '#20000000' })
        .margin({ left: 4 })
        .onClick(() => {
          this.showPlayer = false
        })

        Divider()
          .vertical(true)
          .height(32)
          .color('#E0E0E0')
          .margin({ left: 6, right: 6 })

        // Right: expanded player content
        Row({ space: 8 }) {
          if (this.currentTrack) {
            Image(this.currentTrack.coverUrl)
              .width(40).height(40).borderRadius(20)
              .objectFit(ImageFit.Cover)
              .backgroundColor('#E0E0E0')
              .onClick(() => { this.goToFullPlayer() })

            Column({ space: 2 }) {
              Text(this.currentTrack.songName)
                .fontSize(13).fontColor(this.themeTextPrimary)
                .fontWeight(FontWeight.Medium)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 120 })

              Text(this.currentLyric || this.currentTrack.artist)
                .fontSize(10).fontColor(this.themeTextSecondary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .onClick(() => { this.goToFullPlayer() })

            SymbolGlyph($r('sys.symbol.backward_end_fill'))
              .fontSize(18).fontColor([this.themeTextPrimary])
              .onClick(() => {
                const track = PlayerStore.previous()
                if (track) { this.playTrack(track) }
              })

            SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
              .fontSize(22).fontColor([this.themePrimary])
              .onClick(() => { this.togglePlay() })

            SymbolGlyph($r('sys.symbol.forward_end_fill'))
              .fontSize(18).fontColor([this.themeTextPrimary])
              .onClick(() => {
                const track = PlayerStore.next()
                if (track) { this.playTrack(track) }
              })
          } else {
            // 无播放曲目时的占位提示
            Text('暂无播放')
              .fontSize(13)
              .fontColor(this.themeTextSecondary)
              .layoutWeight(1)
              .onClick(() => { this.showPlayer = false })
          }
        }
        .layoutWeight(1)
        .height('100%')
        .padding({ right: 12 })
      } else {
        // Left: independent full tab bar (主页/搜索/设置)
        Row({ space: 0 }) {
          Column() {
            SymbolGlyph($r('sys.symbol.heart_fill'))
              .fontSize(22)
              .fontColor(this.activeTab === 0 ? [this.themePrimary] : [this.themeTextSecondary])
            Text('主页').fontSize(10)
              .fontColor(this.activeTab === 0 ? this.themePrimary : this.themeTextSecondary)
              .margin({ top: 2 })
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center).height('100%')
          .onClick(() => { this.onTabChange?.(0) })

          Column() {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(22)
              .fontColor(this.activeTab === 1 ? [this.themePrimary] : [this.themeTextSecondary])
            Text('搜索').fontSize(10)
              .fontColor(this.activeTab === 1 ? this.themePrimary : this.themeTextSecondary)
              .margin({ top: 2 })
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center).height('100%')
          .onClick(() => { this.onTabChange?.(1) })

          Column() {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(22)
              .fontColor(this.activeTab === 2 ? [this.themePrimary] : [this.themeTextSecondary])
            Text('设置').fontSize(10)
              .fontColor(this.activeTab === 2 ? this.themePrimary : this.themeTextSecondary)
              .margin({ top: 2 })
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center).height('100%')
          .onClick(() => { this.onTabChange?.(2) })
        }
        .layoutWeight(1)
        .height('100%')

        Divider()
          .vertical(true)
          .height(32)
          .color('#E0E0E0')
          .margin({ left: 4, right: 4 })

        // Right: independent circular mini bar
        Column() {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(22)
            .fontColor([Color.White])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.themePrimary)
        .shadow({ radius: 8, color: '#40007DFF', offsetY: 3 })
        .margin({ right: 6 })
        .onClick(() => {
          if (this.currentTrack) {
            this.showPlayer = true
          }
        })
      }
    }
    .width('92%')
    .height(56)
    .borderRadius(36)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
    .animation({ duration: 350, curve: Curve.EaseInOut })
  }
}
