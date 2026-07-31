// SHMY 浮动操作弹窗 - V1.0.8.5 卡片式悬浮风格
import { SongInfo } from '../model/MusicModel'
import { uiMaterial } from '@kit.ArkUI'

export interface FloatingAction {
  icon: Resource
  label: string
  action: string
  isDanger?: boolean
}

const DEFAULT_ACTIONS: FloatingAction[] = [
  { icon: $r('sys.symbol.forward_end_fill'), label: '下首播放', action: 'play_next' },
  { icon: $r('sys.symbol.list_bullet'), label: '移动歌单', action: 'move_playlist' },
  { icon: $r('sys.symbol.chevron_up'), label: '调整位置', action: 'reorder' },
  { icon: $r('sys.symbol.share'), label: '分享歌曲', action: 'share_song' },
  { icon: $r('sys.symbol.trash'), label: '删除歌曲', action: 'delete_song', isDanger: true },
]

@Component
export struct FloatingActionPopup {
  song: SongInfo | null = null
  visible: boolean = false
  actions: FloatingAction[] = DEFAULT_ACTIONS
  onAction?: (action: string, song: SongInfo) => void
  onDismiss?: () => void
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_danger') themeDanger: string = '#F44336'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'

  build() {
    Stack() {
      if (this.visible && this.song) {
        // 全屏高斯模糊背景（半透明黑色蒙版）
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#00000040')
          .onClick(() => {
            this.onDismiss?.()
          })

        // 弹窗主体（Stack 默认居中）
        Column({ space: 12 }) {
          // 顶部歌曲信息条
          Row({ space: 12 }) {
            if (this.song.coverUrl && this.song.coverUrl.length > 0) {
              Image(this.song.coverUrl)
                .width(44)
                .height(44)
                .borderRadius(10)
                .objectFit(ImageFit.Cover)
            } else {
              Row() {
                Image($r('app.media.music_note'))
                  .width(20)
                  .height(20)
              }
              .width(44)
              .height(44)
              .borderRadius(10)
              .backgroundColor(this.themePrimary)
              .justifyContent(FlexAlign.Center)
            }

            Column({ space: 2 }) {
              Text(this.song.songName)
                .fontSize(15)
                .fontColor(this.themeTextPrimary)
                .fontWeight(FontWeight.Medium)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')

              Text(this.song.artist)
                .fontSize(12)
                .fontColor(this.themeTextSecondary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding({ left: 12, right: 16, top: 8, bottom: 8 })
          .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
          .borderRadius(22)

          // 操作列表
          Column({ space: 0 }) {
            ForEach(this.actions, (item: FloatingAction, index?: number) => {
              Row({ space: 12 }) {
                SymbolGlyph(item.icon)
                  .fontSize(18)
                  .fontColor([item.isDanger ? this.themeDanger : this.themePrimary])

                Text(item.label)
                  .fontSize(16)
                  .fontColor(item.isDanger ? this.themeDanger : this.themeTextPrimary)
                  .fontWeight(item.isDanger ? FontWeight.Medium : FontWeight.Normal)
                  .layoutWeight(1)
              }
              .width('100%')
              .height(48)
              .padding({ left: 20, right: 20 })
              .onClick(() => {
                this.onAction?.(item.action, this.song!)
              })

              if ((index ?? 0) < this.actions.length - 1) {
                Divider()
                  .color('#E8E8E8')
                  .margin({ left: 50, right: 20 })
              }
            })
          }
          .width('100%')
          .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
          .borderRadius(20)
        }
        .width('82%')
      }
    }
    .width('100%')
    .height('100%')
  }
}
