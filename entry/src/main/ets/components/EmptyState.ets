// SHMY 空状态占位组件
// EmptyState.ets

@Component
export struct EmptyState {
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'
  icon: ResourceStr = '🔍'
  title: string = '暂无内容'
  subtitle: string = ''

  build() {
    Column({ space: 12 }) {
      // 大图标
      if (typeof this.icon === 'string') {
        Text(this.icon)
          .fontSize(64)
          .opacity(0.4)
      } else {
        Image(this.icon)
          .width(64)
          .height(64)
          .objectFit(ImageFit.Contain)
          .opacity(0.4)
          .fillColor(this.themeTextSecondary)
      }

      // 标题
      Text(this.title)
        .fontSize(16)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Medium)

      // 副标题
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(13)
          .fontColor(this.themeTextSecondary)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(40)
  }
}