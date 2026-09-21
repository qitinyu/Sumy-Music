// SHMY 底部播放器组件 - V1.0.3
// BottomPlayer.ets - 修复上一首/下一首实际播放
import { SongInfo } from '../model/MusicModel'
import { PlayerStore } from '../utils/PlayerStore'
import { AudioPlayer } from '../utils/AudioPlayer'
import { MusicApi } from '../utils/MusicApi'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { CompatUtils } from '../utils/CompatUtils'
import { MaterialCompat, MaterialCompatStyle } from '../utils/MaterialCompat'

@Component
export struct BottomPlayer {
  @StorageProp('currentTrack') currentTrack: SongInfo | null = null
  @StorageProp('isPlaying') isPlaying: boolean = false
  @StorageProp('currentTime') currentTime: number = 0
  @StorageProp('duration') duration: number = 0
  @StorageProp('autoJumpDetail') autoJumpDetail: boolean = false
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_cardBg') themeCardBg: string = '#FFFFFF'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'
  @StorageProp('theme_divider') themeDivider: string = '#E8E8E8'
  @StorageProp('theme_placeholder') themePlaceholder: string = '#E0E0E0'
  @StorageProp('isDarkMode') isDarkMode: boolean = false

  onClose?: () => void

  private progress: number = 0
  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private supportImmersive: boolean = CompatUtils.isImmersiveSupported()

  aboutToAppear(): void {
    this.updateProgress()
    this.loadAutoJumpSetting()
  }

  private updateProgress(): void {
    if (this.duration > 0) {
      this.progress = this.currentTime / this.duration
    } else {
      this.progress = 0
    }
  }

  private async loadAutoJumpSetting(): Promise<void> {
    const val = await this.db.getSetting('autoJumpDetail')
    if (val === 'true') {
      AppStorage.setOrCreate('autoJumpDetail', true)
    } else {
      AppStorage.setOrCreate('autoJumpDetail', false)
    }
  }

  // 切换播放/暂停（实际控制播放器）
  private async togglePlay(): Promise<void> {
    if (this.isPlaying) {
      await AudioPlayer.getInstance().pause()
      PlayerStore.pause()
    } else {
      // 如果有当前曲目但没有URL，重新获取
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

  // 上一首（实际播放）
  private async handlePrevious(): Promise<void> {
    // 统一走 AudioPlayer 切歌：带取链失败自动跳下一首、防抖（代际）与真实暂停
    await AudioPlayer.getInstance().playPrevious()
  }

  // 下一首（实际播放）
  private async handleNext(): Promise<void> {
    await AudioPlayer.getInstance().playNext()
  }

  // 播放指定曲目
  // 统一跳转到完整播放器
  private goToFullPlayer(): void {
    PlayerStore.showFullPlayer()
  }

  @Builder
  PlayerContent() {
    // 顶部进度条
    Row()
      .width('100%')
      .height(2)
      .backgroundColor(this.themeDivider)
      .borderRadius({ topLeft: 28, topRight: 28 })
    Row()
      .width(`${Math.min(this.progress * 100, 100)}%`)
      .height(2)
      .backgroundColor(this.themePrimary)
      .position({ x: 0, y: 0 })

    // 播放器内容行
    Row({ space: 12 }) {
      // 封面图
      Image(this.currentTrack!.coverUrl)
        .width(44)
        .height(44)
        .borderRadius(10)
        .objectFit(ImageFit.Cover)
        .backgroundColor(this.themePlaceholder)

      // 歌曲信息
      Column({ space: 2 }) {
        Text(this.currentTrack!.songName)
          .fontSize(15)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '60%' })

        Text(this.currentTrack!.artist)
          .fontSize(13)
          .fontColor(this.themeTextSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 上一首按钮
      Row() {
        SymbolGlyph($r('sys.symbol.backward_end_fill'))
          .fontSize(20)
          .fontColor([this.themeTextPrimary])
      }
      .width(32)
      .height(32)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.handlePrevious()
      })

      // 播放/暂停按钮
      Row() {
        SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
          .fontSize(16)
          .fontColor([Color.White])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(this.themePrimary)
      .justifyContent(FlexAlign.Center)
      .shadow({ radius: 8, color: '#1A80FF40', offsetY: 2 })
      .onClick(() => {
        this.togglePlay()
      })

      // 下一首按钮
      Row() {
        SymbolGlyph($r('sys.symbol.forward_end_fill'))
          .fontSize(20)
          .fontColor([this.themeTextPrimary])
      }
      .width(32)
      .height(32)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.handleNext()
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  build() {
    if (!this.currentTrack) {
      Column()
        .height(0)
    } else if (this.supportImmersive) {
      Column() {
        this.PlayerContent()
      }
      .width('100%')
      .borderRadius({ topLeft: 28, topRight: 28 })
      .systemMaterial(MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN))
      .onClick(() => {
        this.goToFullPlayer()
      })
    } else {
      Column() {
        this.PlayerContent()
      }
      .width('100%')
      .borderRadius({ topLeft: 28, topRight: 28 })
      .backgroundColor(this.themeCardBg)
      .onClick(() => {
        this.goToFullPlayer()
      })
    }
  }
}
