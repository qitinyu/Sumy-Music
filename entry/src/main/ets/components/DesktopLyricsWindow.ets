import { LyricLine } from '../model/MusicModel'
import window from '@ohos.window'

@Component
export struct DesktopLyricsWindow {
  @StorageProp('currentTime') currentTime: number = 0
  @StorageProp('lyrics') lyrics: LyricLine[] = []
  @StorageProp('isPlaying') isPlaying: boolean = false
  @StorageProp('desktopLyrics') @Watch('onDesktopLyricsChange') desktopLyrics: boolean = false
  @StorageProp('lockDesktopLyrics') locked: boolean = false
  @StorageProp('multiLineLyrics') multiLine: boolean = false
  @StorageProp('lyricsSize') lyricsSize: string = 'standard'
  @StorageProp('lyricsColor') lyricsColor: string = '#FFFFFF'
  @StorageProp('lyricsBgOpacity') bgOpacity: number = 50
  @State currentLine: string = ''

  private ctx: Context | null = null
  private win: window.Window | null = null
  private timer: number = -1

  aboutToAppear(): void {
    this.ctx = this.getUIContext().getHostContext() as Context
  }

  aboutToDisappear(): void {
    this.stopWindow()
  }

  private onDesktopLyricsChange(enabled: boolean): void {
    setTimeout(() => {
      if (enabled) {
        this.startWindow()
      } else {
        this.stopWindow()
      }
    }, 200)
  }

  private async startWindow(): Promise<void> {
    if (this.win || !this.ctx) return
    try {
      const mainWin = await window.getLastWindow(this.ctx!)
      this.win = await window.createWindow({
        name: 'shmy_desktop_lyrics',
        windowType: 0,
      })
      this.win!.setWindowLayoutFullScreen(false)
      this.win!.setWindowSystemBarEnable([])
      this.win!.setWindowBackgroundColor('#00000000')
      this.win!.resize(800, 100)
      const mainRect = mainWin.getWindowProperties().windowRect
      this.win!.moveTo(mainRect.left, mainRect.top + mainRect.height - 200)
      this.win!.showWindow()
      this.timer = setInterval(() => {
        this.tick()
      }, 300)
    } catch (e) {
      console.error('[DesktopLyrics] start failed:', e)
    }
  }

  private async stopWindow(): Promise<void> {
    if (this.timer >= 0) {
      clearInterval(this.timer)
      this.timer = -1
    }
    if (this.win) {
      try { await this.win.destroyWindow() } catch (_e) {}
      this.win = null
    }
  }

  private tick(): void {
    if (this.lyrics.length === 0) {
      this.currentLine = ''
      return
    }
    const ct = this.currentTime
    let line = ''
    for (let i = this.lyrics.length - 1; i >= 0; i--) {
      if (ct >= this.lyrics[i].time) {
        line = this.lyrics[i].text
        if (this.multiLine && i > 0) {
          line = this.lyrics[i - 1].text + '  ' + line
        }
        break
      }
    }
    this.currentLine = line
    if (this.win && this.isPlaying) {
      try {
        const alpha = Math.round(this.bgOpacity * 2.55)
        const hex = alpha.toString(16).padStart(2, '0')
        this.win.setWindowBackgroundColor('#000000' + hex)
      } catch (_e) {}
    }
  }

  build() {
    Column().width(0).height(0)
  }
}
