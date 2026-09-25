// LevelGuideDialog.ets - 等级明示弹窗：LV1-8 八区段色彩表
import { LevelRangeInfo, buildLevelTable, LEVEL_TEXT_COLOR } from '../utils/LevelConfig'

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

  // 千分位格式化（区间最大 160000）
  private formatNum(n: number): string {
    const s: string = String(n)
    if (s.length <= 3) {
      return s
    }
    return s.substring(0, s.length - 3) + ',' + s.substring(s.length - 3)
  }

  @Builder
  LevelRow(row: LevelRangeInfo) {
    Row({ space: 12 }) {
      // 等级徽章（区段色均为浅/中亮度，黑色文字保证对比度）
      Stack() {
        Text(`LV${row.level}`)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(LEVEL_TEXT_COLOR)
          .backgroundColor(row.color)
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .borderRadius(8)
      }

      Row({ space: 6 }) {
        Text(this.formatNum(row.rangeStart))
          .fontSize(13)
          .fontColor(this.themeTextPrimary)
        Text('~')
          .fontSize(13)
          .fontColor(this.themeTextSecondary)
        Text(this.formatNum(row.rangeEnd))
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
            this.LevelRow(row)
          }
        }, (row: LevelRangeInfo) => `${row.level}`)
      }
      .width('100%')
      .height(280)
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
