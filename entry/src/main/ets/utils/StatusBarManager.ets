import { window } from '@kit.ArkUI'

interface RgbColor {
  r: number
  g: number
  b: number
}

export class StatusBarManager {
  private static mainWindow: window.Window | null = null
  private static isDarkBg: boolean = true

  static setMainWindow(win: window.Window): void {
    StatusBarManager.mainWindow = win
  }

  private static hexToRgb(hex: string): RgbColor | null {
    const h = hex.replace('#', '')
    let color = h
    if (h.length === 8) {
      color = h.substring(2)
    } else if (h.length !== 6) {
      return null
    }
    const r = parseInt(color.substring(0, 2), 16)
    const g = parseInt(color.substring(2, 4), 16)
    const b = parseInt(color.substring(4, 6), 16)
    return { r: r, g: g, b: b }
  }

  static isDarkColor(bgColor: string): boolean {
    const rgb = StatusBarManager.hexToRgb(bgColor)
    if (!rgb) return true
    const luminance = (0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b) / 255
    return luminance < 0.5
  }

  static async applyForBackground(bgColor: string): Promise<void> {
    if (!StatusBarManager.mainWindow) return
    const dark = StatusBarManager.isDarkColor(bgColor)
    StatusBarManager.isDarkBg = dark
    const contentColor = dark ? '#FFFFFF' : '#000000'
    const props: window.SystemBarProperties = {
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      statusBarContentColor: contentColor,
      navigationBarContentColor: contentColor,
    }
    try {
      await StatusBarManager.mainWindow.setWindowSystemBarProperties(props)
    } catch (e) {
      console.error('[StatusBarManager] apply failed:', e)
    }
  }

  static getIsDarkBg(): boolean {
    return StatusBarManager.isDarkBg
  }
}
