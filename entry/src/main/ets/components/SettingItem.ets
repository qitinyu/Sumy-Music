// SHMY 设置项组件
// SettingItem.ets

@Component
export struct SettingItem {
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'
  icon: ResourceStr = ''
  iconBgColor: string = '#F0F0F0'
  title: string = ''
  description: string = ''
  switchChecked: boolean = false
  onSwitchChange?: (checked: boolean) => void

  // 是否显示开关
  hasSwitch: boolean = false

  build() {
    Row({ space: 12 }) {
      // 图标
      Row() {
        if (typeof this.icon === 'string') {
          Text(this.icon as string)
            .fontSize(18)
            .fontColor(Color.White)
        } else {
          SymbolGlyph(this.icon as Resource)
            .fontSize(20)
            .fontColor([Color.White])
        }
      }
      .width(40)
      .height(40)
      .borderRadius(10)
      .backgroundColor(this.iconBgColor)
      .justifyContent(FlexAlign.Center)

      // 标题和描述
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(15)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Medium)

        if (this.description.length > 0) {
          Text(this.description)
            .fontSize(12)
            .fontColor(this.themeTextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // Toggle Switch
      if (this.hasSwitch) {
        Toggle({ type: ToggleType.Switch, isOn: this.switchChecked })
          .selectedColor('#007DFF')
          .onChange((isOn: boolean) => {
            if (this.onSwitchChange) {
              this.onSwitchChange(isOn)
            }
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .alignItems(VerticalAlign.Center)
  }
}