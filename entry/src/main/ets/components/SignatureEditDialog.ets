// SignatureEditDialog.ets - 个性签名编辑弹窗
const MAX_SIGNATURE_LENGTH: number = 30

@CustomDialog
export struct SignatureEditDialog {
  controller: CustomDialogController
  signatureValue: string = ''
  @State inputValue: string = ''
  onSave?: (value: string) => void
  themePrimary: string = '#007DFF'
  themeCardBg: string = '#FFFFFF'
  themeTextPrimary: string = '#1A1A1A'
  themeTextSecondary: string = '#999999'

  aboutToAppear() {
    this.inputValue = this.signatureValue
  }

  build() {
    Column({ space: 16 }) {
      Text('编辑个性签名')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.themeTextPrimary)

      Column({ space: 4 }) {
        TextInput({ placeholder: '编辑后展现更个性的你!', text: this.inputValue })
          .placeholderColor(this.themeTextSecondary)
          .fontColor(this.themeTextPrimary)
          .backgroundColor('#F5F5F7')
          .height(44)
          .borderRadius(8)
          .maxLength(MAX_SIGNATURE_LENGTH)
          .onChange((value: string) => {
            this.inputValue = value
          })

        Text(`${this.inputValue.length}/${MAX_SIGNATURE_LENGTH}`)
          .fontSize(11)
          .fontColor(this.themeTextSecondary)
          .width('100%')
          .textAlign(TextAlign.End)
      }
      .width('100%')

      Row({ space: 12 }) {
        Button('取消')
          .backgroundColor('transparent')
          .fontColor(this.themeTextSecondary)
          .onClick(() => {
            this.controller.close()
          })

        Button('保存')
          .backgroundColor(this.themePrimary)
          .fontColor(Color.White)
          .onClick(() => {
            if (this.onSave) {
              this.onSave(this.inputValue)
            }
            this.controller.close()
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .padding(16)
    .width('80%')
    .borderRadius(6)
  }
}
