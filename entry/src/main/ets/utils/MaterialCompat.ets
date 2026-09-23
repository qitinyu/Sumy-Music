// MaterialCompat.ets - 沉浸式材质兼容层（V1.1.0）
// API 26+ 使用真正的 uiMaterial.ImmersiveMaterial + systemMaterial
// API 24-25 使用 backgroundEffect 模拟沉浸光感
// V2.1.6：immersiveMaterial 内部加版本守卫——API 26 以下 uiMaterial.ImmersiveStyle
// 运行时不存在，直接访问 .THICK 等成员会抛 TypeError 导致低版本设备启动崩溃，
// 统一返回 undefined（systemMaterial 参数接受 undefined，走默认弹窗背景）。

import { uiMaterial } from '@kit.ArkUI'
import { CompatUtils } from './CompatUtils'

// 材质分档，对应 uiMaterial.ImmersiveStyle（从薄到厚）
export enum MaterialCompatStyle {
  ULTRA_THIN = 0,
  THIN = 1,
  REGULAR = 2,
  THICK = 3,
  ULTRA_THICK = 4
}

// 模拟材质参数，结构兼容 backgroundEffect 的 BackgroundEffectOptions
export interface MaterialEffectOptions {
  radius: number
  saturation: number
  brightness: number
  color: string
}

export interface MaterialImmersiveOptions {
  interactive?: boolean
  lightEffect?: boolean
}

export class MaterialCompat {
  /**
   * 生成模拟沉浸式材质的 backgroundEffect 参数
   * @param isDark 是否深色模式
   * @param cardBg 主题卡片底色（用于深色模式蒙版）
   * @param style 材质分档，默认 REGULAR
   */
  static effect(isDark: boolean, cardBg: string, style?: MaterialCompatStyle): MaterialEffectOptions {
    const s: MaterialCompatStyle = style !== undefined ? style : MaterialCompatStyle.REGULAR
    let radius: number = 20
    // 沉浸光感程度加深：各档 alpha 上调 ~0.06~0.08，材质更厚重明显
    let lightAlpha: number = 0.52 // 原 0.45
    let darkAlpha: number = 0.80 // 原 0.72
    switch (s) {
      case MaterialCompatStyle.ULTRA_THIN:
        radius = 12
        lightAlpha = 0.36 // 原 0.30
        darkAlpha = 0.65 // 原 0.58
        break
      case MaterialCompatStyle.THIN:
        radius = 16
        lightAlpha = 0.44 // 原 0.38
        darkAlpha = 0.72 // 原 0.65
        break
      case MaterialCompatStyle.REGULAR:
        radius = 20
        lightAlpha = 0.52 // 原 0.45
        darkAlpha = 0.80 // 原 0.72
        break
      case MaterialCompatStyle.THICK:
        radius = 28
        lightAlpha = 0.64 // 原 0.58
        darkAlpha = 0.86 // 原 0.80
        break
      case MaterialCompatStyle.ULTRA_THICK:
        radius = 36
        lightAlpha = 0.78 // 原 0.72
        darkAlpha = 0.92 // 原 0.88
        break
      default:
        break
    }
    const color: string = isDark
      ? MaterialCompat.withAlpha(cardBg, darkAlpha)
      : MaterialCompat.withAlpha('#FFFFFF', lightAlpha)
    return {
      radius: radius,
      saturation: 1.2,
      brightness: 1.0,
      color: color
    }
  }

  /**
   * API 26+ 使用真正的沉浸式材质对象，配合 .systemMaterial() 使用；
   * API 26 以下返回 undefined（调用方传给 systemMaterial 即走默认样式）
   * @param style 材质分档
   * @param options interactive 是否启用按压形变；lightEffect 是否启用光感交互反馈
   */
  static immersiveMaterial(
    style?: MaterialCompatStyle,
    options?: MaterialImmersiveOptions
  ): uiMaterial.Material | undefined {
    if (!CompatUtils.isImmersiveSupported()) {
      return undefined
    }
    try {
      const s: MaterialCompatStyle = style !== undefined ? style : MaterialCompatStyle.REGULAR
      let immersiveStyle: uiMaterial.ImmersiveStyle
      switch (s) {
        case MaterialCompatStyle.ULTRA_THIN:
          immersiveStyle = uiMaterial.ImmersiveStyle.ULTRA_THIN
          break
        case MaterialCompatStyle.THIN:
          immersiveStyle = uiMaterial.ImmersiveStyle.THIN
          break
        case MaterialCompatStyle.THICK:
          immersiveStyle = uiMaterial.ImmersiveStyle.THICK
          break
        case MaterialCompatStyle.ULTRA_THICK:
          immersiveStyle = uiMaterial.ImmersiveStyle.ULTRA_THICK
          break
        case MaterialCompatStyle.REGULAR:
        default:
          immersiveStyle = uiMaterial.ImmersiveStyle.REGULAR
          break
      }
      const opts: uiMaterial.ImmersiveOptions = { style: immersiveStyle }
      if (options !== undefined && options.interactive === true) {
        opts.interactive = true
      }
      if (options !== undefined && options.lightEffect === true) {
        opts.lightEffect = { color: Color.White }
      }
      return new uiMaterial.ImmersiveMaterial(opts)
    } catch (_e) {
      // 兜底：个别设备 API 版本达标但材质接口异常时降级为默认样式，不崩溃
      return undefined
    }
  }

  /** 将 #RRGGBB 颜色转换为 #AARRGGBB（追加/替换 alpha 通道） */
  static withAlpha(hexColor: string, alpha: number): string {
    let hex: string = hexColor.replace('#', '')
    if (hex.length === 8) {
      hex = hex.substring(2)
    }
    hex = hex.substring(0, 6)
    const a: number = Math.round(Math.max(0, Math.min(1, alpha)) * 255)
    return `#${a.toString(16).padStart(2, '0')}${hex}`
  }
}
