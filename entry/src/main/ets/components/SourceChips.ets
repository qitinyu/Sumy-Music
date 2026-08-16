// SHMY 音源选择 Chips 组件 - V1.0.9 插件化
// SourceChips.ets - 动态渲染已安装插件
import { SourceManager } from '../utils/SourceManager'

@Component
export struct SourceChips {
  @Prop selected: string = 'all'
  @State sourceNames: string[] = []
  onSelect?: (source: string) => void
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_placeholder') themePlaceholder: string = '#E0E0E0'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'

  async aboutToAppear() {
    await SourceManager.ensureLoaded()
    this.sourceNames = SourceManager.getSourceNames()
  }

  build() {
    Scroll() {
      Row({ space: 8 }) {
        Text('全网搜索')
          .fontSize(13)
          .fontColor(this.selected === 'all' ? Color.White : this.themeTextSecondary)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor(this.selected === 'all' ? this.themePrimary : this.themePlaceholder)
          .flexShrink(0)
          .onClick(() => { if (this.onSelect) { this.onSelect('all') } })

        ForEach(this.sourceNames, (name: string) => {
          Text(name)
            .fontSize(13)
            .fontColor(this.selected === name ? Color.White : this.themeTextSecondary)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(this.selected === name ? this.themePrimary : this.themePlaceholder)
            .flexShrink(0)
            .onClick(() => { if (this.onSelect) { this.onSelect(name) } })
        })
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
  }
}