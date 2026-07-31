// SHMY 歌曲卡片组件
// SongCard.ets
import { SongInfo, SourceInfo, createEmptySongInfo } from '../model/MusicModel'

@Component
export struct SongCard {
  song: SongInfo = createEmptySongInfo()
  onPlay?: (song: SongInfo) => void
  onMore?: (song: SongInfo) => void

  // 模式：true = 双击播放（搜索结果），false = 单击播放（轩窗收藏/歌单）
  doubleTapToPlay: boolean = false

  @State private isPressed: boolean = false
  @StorageProp('theme_cardBg') themeCardBg: string = '#F5F5F5'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'

  build() {
    Row({ space: 10 }) {
      // 左侧封面图片 48x48
      Image(this.song.coverUrl)
        .width(48)
        .height(48)
        .borderRadius(8)
        .objectFit(ImageFit.Cover)
        .backgroundColor('#E0E0E0')
        .flexShrink(0)

      // 右侧信息区
      Column() {
        // 右侧上方：歌曲名（15sp，粗体，单行省略）
        Text(this.song.songName)
          .fontSize(15)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 右侧下方：音源标签 + 演唱者 + 更多按钮
        Row({ space: 6 }) {
          // 音源小标签（彩色背景白色文字）
          Text(SourceInfo.getName(this.song.source))
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor(SourceInfo.getColor(this.song.source))
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .borderRadius(3)
            .flexShrink(0)

          // 演唱者（灰色，单行省略）
          Text(this.song.artist)
            .fontSize(12)
            .fontColor(this.themeTextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          // 更多按钮（三点）
          SymbolGlyph($r('sys.symbol.ellipsis_circle'))
            .fontSize(20)
            .fontColor([this.themeTextSecondary])
            .width(28)
            .height(28)
            .flexShrink(0)
            .onClick(() => {
              if (this.onMore) {
                this.onMore(this.song)
              }
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 10, bottom: 10 })
    .backgroundColor(this.themeCardBg)
    .borderRadius(12)
    .scale({ x: this.isPressed ? 0.97 : 1, y: this.isPressed ? 0.97 : 1 })
    .animation({ duration: 150 })
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        // 长按 → 打开操作菜单
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction(() => {
            if (this.onMore) {
              this.onMore(this.song)
            }
          }),
        // 双击 → 播放（搜索模式）
        TapGesture({ count: 2 })
          .onAction(() => {
            if (this.onPlay) {
              this.onPlay(this.song)
            }
          }),
        // 单击 → 播放（轩窗收藏/歌单模式）
        TapGesture({ count: 1 })
          .onAction(() => {
            if (!this.doubleTapToPlay) {
              if (this.onPlay) {
                this.onPlay(this.song)
              }
            }
          }),
      )
    )
  }
}