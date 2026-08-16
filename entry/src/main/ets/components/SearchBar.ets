// SHMY 搜索栏组件
// SearchBar.ets

@Component
export struct SearchBar {
  @Prop keyword: string = ''
  onKeywordChange?: (keyword: string) => void
  onSearch?: (keyword: string) => void
  onClear?: () => void
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'
  @StorageProp('theme_placeholder') themePlaceholder: string = '#E0E0E0'

  build() {
    Row({ space: 8 }) {
      // 搜索图标
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(16)
        .fontColor([this.themeTextSecondary])
        .margin({ left: 12 })

      // 搜索输入框
      TextInput({ placeholder: '\u641C\u7D22\u6B4C\u66F2\u3001\u6B4C\u624B', text: this.keyword })
        .layoutWeight(1)
        .height(36)
        .backgroundColor(Color.Transparent)
        .fontSize(14)
        .fontColor(this.themeTextPrimary)
        .placeholderColor(this.themeTextSecondary)
        .placeholderFont({ size: 14 })
        .onChange((value: string) => {
          if (this.onKeywordChange) {
            this.onKeywordChange(value)
          }
        })
        .onSubmit(() => {
          if (this.onSearch && this.keyword.trim().length > 0) {
            this.onSearch(this.keyword.trim())
          }
        })

      // 清除按钮
      if (this.keyword.length > 0) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(14)
          .fontColor([this.themeTextSecondary])
          .margin({ right: 4 })
          .onClick(() => {
            if (this.onClear) {
              this.onClear()
            }
          })
      }

      // 搜索按钮
      Button('\u641C\u7D22')
        .height(32)
        .padding({ left: 14, right: 14 })
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor(this.themePrimary)
        .borderRadius(16)
        .margin({ right: 4 })
        .onClick(() => {
          if (this.onSearch && this.keyword.trim().length > 0) {
            this.onSearch(this.keyword.trim())
          }
        })
    }
    .height(40)
    .backgroundColor(this.themePlaceholder)
    .borderRadius(20)
    .padding({ left: 4, right: 4 })
  }
}