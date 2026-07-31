// SHMY 音源选择 Chips 组件 - V1.0.9 插件化
// SourceChips.ets - 动态渲染已安装插件
import { SourceManager } from '../utils/SourceManager'

@Component
export struct SourceChips {
  @Prop selected: string = 'all'
  @State sourceNames: string[] = []
  onSelect?: (source: string) => void

  async aboutToAppear() {
    await SourceManager.ensureLoaded()
    this.sourceNames = SourceManager.getSourceNames()
  }

  build() {
    Scroll() {
      Row({ space: 8 }) {
        Text('全网搜索')
          .fontSize(13)
          .fontColor(this.selected === 'all' ? Color.White : '#666666')
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor(this.selected === 'all' ? '#007DFF' : '#F0F0F0')
          .flexShrink(0)
          .onClick(() => { if (this.onSelect) { this.onSelect('all') } })

        ForEach(this.sourceNames, (name: string) => {
          Text(name)
            .fontSize(13)
            .fontColor(this.selected === name ? Color.White : '#666666')
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(this.selected === name ? '#007DFF' : '#F0F0F0')
            .flexShrink(0)
            .onClick(() => { if (this.onSelect) { this.onSelect(name) } })
        })
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }
}