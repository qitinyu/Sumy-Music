// Sumy Music 开屏动画组件
// StartupDialog.ets - V1.0.9

@Component
export struct StartupDialog {
  @StorageProp('theme_bg') themeBg: string = '#F5F5FA'
  @StorageProp('showStartup') showStartup: boolean = true
  onDismiss?: (dontShowToday: boolean) => void

  @State opacityValue: number = 0
  @State scaleValue: number = 0.8
  private autoDismissTimer: number | null = null

  aboutToAppear(): void {
    setTimeout(() => {
      this.opacityValue = 1
      this.scaleValue = 1
    }, 150)
    this.autoDismissTimer = setTimeout(() => {
      this.doDismiss()
    }, 3000)
  }

  aboutToDisappear(): void {
    if (this.autoDismissTimer) {
      clearTimeout(this.autoDismissTimer)
      this.autoDismissTimer = null
    }
  }

  build() {
    if (!this.showStartup) {
      Column().height(0).width(0)
    } else {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.themeBg)

        Column({ space: 0 }) {
          Column({ space: 20 }) {
            Image($r('app.media.logo'))
              .width(96)
              .height(96)
              .borderRadius(24)
              .objectFit(ImageFit.Cover)
              .shadow({ radius: 20, color: '#00000040', offsetY: 8 })

            Text('Sumy Music')
              .fontSize(28)
              .fontColor(Color.Black)
              .fontWeight(FontWeight.Normal)
              .letterSpacing(4)

            Text('听你想听 · 回归音乐本质')
              .fontSize(14)
              .fontColor('#666666')
              .letterSpacing(1)

            LoadingProgress()
              .width(32)
              .height(32)
              .color('#999999')
              .margin({ top: 20 })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .layoutWeight(1)

          Text('Sumy By YuQi')
            .fontSize(12)
            .fontColor('#999999')
            .letterSpacing(2)
            .padding({ bottom: 48 })
        }
        .width('100%')
        .height('100%')
        .opacity(this.opacityValue)
        .scale({ x: this.scaleValue, y: this.scaleValue })
        .animation({ duration: 1500, curve: Curve.EaseOut })
      }
      .width('100%')
      .height('100%')
    }
  }

  private doDismiss(): void {
    AppStorage.setOrCreate('showStartup', false)
    this.showStartup = false
    if (this.onDismiss) {
      this.onDismiss(false)
    }
  }
}
