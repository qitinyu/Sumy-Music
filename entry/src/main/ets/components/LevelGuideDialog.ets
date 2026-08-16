// LevelGuideDialog.ets - 等级明示弹窗：LV1-16 四区段色彩表
import { LevelRangeInfo, buildLevelTable, SEGMENT_NAMES } from '../utils/LevelConfig'

@CustomDialog
export struct LevelGuideDialog {
  controller: CustomDialogController
  currentLevel: number = 1
  themePrimary: string = '#007DFF'
  themeCardBg: string = '#FFFFFF'
  themeTextPrimary: string = '#1A1A1A'
  themeTextSecondary: string = '#999999'
  themeDivider: string = '#EEEEEE'

  private rows: LevelRangeInfo[] = []

  aboutToAppear() {
    this.rows = buildLevelTable()
  }

  @Builder
  LevelRow(row: LevelRangeInfo) {
    Row({ space: 12 }) {
      // 等级徽章（文字镂空，背景填充等级色）
      Stack() {
        Text(`LV${row.level}`)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.themeCardBg)
          .backgroundColor(row.color)
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .borderRadius(8)
      }

      Row({ space: 6 }) {
        Text(`${row.rangeStart}`)
          .fontSize(13)
          .fontColor(this.themeTextPrimary)
        Text('~')
          .fontSize(13)
          .fontColor(this.themeTextSecondary)
        Text(`${row.rangeEnd}`)
          .fontSize(13)
          .fontColor(this.themeTextPrimary)
        Text('分钟')
          .fontSize(11)
          .fontColor(this.themeTextSecondary)
      }
      .layoutWeight(1)

      if (row.level === this.currentLevel) {
        Text('当前')
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor(this.themePrimary)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
      }
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
  }

  @Builder
  SegmentHeader(segment: number) {
    Row({ space: 6 }) {
      Row()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(this.segmentColor(segment))
      Text(SEGMENT_NAMES[segment - 1])
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.themeTextSecondary)
    }
    .width('100%')
    .padding({ top: 8, bottom: 2 })
  }

  private segmentColor(segment: number): string {
    const colors: string[] = ['#2D529F', '#ADD88D', '#C55C10', '#C91D32']
    return colors[Math.max(0, Math.min(3, segment - 1))]
  }

  build() {
    Column({ space: 12 }) {
      Text('等级明示')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.themeTextPrimary)

      Text('等级依据累计听歌时长自动晋升')
        .fontSize(11)
        .fontColor(this.themeTextSecondary)

      List({ space: 2 }) {
        ForEach(this.rows, (row: LevelRangeInfo) => {
          ListItem() {
            Column() {
              if (row.level === 1 || row.level === 5 || row.level === 9 || row.level === 13) {
                this.SegmentHeader(row.segment)
              }
              this.LevelRow(row)
            }
            .width('100%')
          }
        }, (row: LevelRangeInfo) => `${row.level}`)
      }
      .width('100%')
      .height(320)
      .scrollBar(BarState.Off)
      .divider({ strokeWidth: 1, color: this.themeDivider, startMargin: 40, endMargin: 0 })

      Button('我知道了')
        .width('100%')
        .height(40)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(this.themePrimary)
        .borderRadius(20)
        .onClick(() => {
          this.controller.close()
        })
    }
    .padding(16)
    .width('85%')
    .borderRadius(16)
  }
}