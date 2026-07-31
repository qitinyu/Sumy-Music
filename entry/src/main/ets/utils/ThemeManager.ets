// SHMY 主题管理器 - V1.0.4
// ThemeManager.ets
import { DatabaseHelper } from '../database/DatabaseHelper'

// 主题色板
export interface ThemePalette {
  primary: string
  primaryLight: string
  bg: string
  cardBg: string
  surface: string
  textPrimary: string
  textSecondary: string
  divider: string
  danger: string
  placeholder: string
}

// 主题定义
const THEMES: Map<string, ThemePalette> = new Map()
THEMES.set('jianbai', {
  primary: '#007DFF',
  primaryLight: '#E0F0FF',
  bg: '#F5F5FA',
  cardBg: '#FFFFFF',
  surface: '#FFFFFF',
  textPrimary: '#1A1A1A',
  textSecondary: '#999999',
  divider: '#E8E8E8',
  danger: '#F44336',
  placeholder: '#E0E0E0',
} as ThemePalette)
THEMES.set('sea_breeze', {
  primary: '#7BA7C4',
  primaryLight: '#D6E6F0',
  bg: '#F5F2ED',
  cardBg: '#FFFFFF',
  surface: '#FAF9F7',
  textPrimary: '#3A3A3A',
  textSecondary: '#A8A09A',
  divider: '#EBE7E2',
  danger: '#D4958A',
  placeholder: '#E5E0DB',
} as ThemePalette)
THEMES.set('sunset_sweet', {
  primary: '#EFCACA',
  primaryLight: '#F1D6D6',
  bg: '#F3E5E8',
  cardBg: '#FFFFFF',
  surface: '#F1DADD',
  textPrimary: '#4A3538',
  textSecondary: '#B89EA2',
  divider: '#EFCDCF',
  danger: '#D4958A',
  placeholder: '#F1D6D6',
} as ThemePalette)

// AppStorage 键名
const KEYS = [
  'theme_primary', 'theme_primaryLight', 'theme_bg', 'theme_cardBg',
  'theme_surface', 'theme_textPrimary', 'theme_textSecondary',
  'theme_divider', 'theme_danger', 'theme_placeholder',
]

export class ThemeManager {
  private static db: DatabaseHelper = DatabaseHelper.getInstance()

  // 获取所有主题名列表
  static getThemeNames(): string[] {
    return Array.from(THEMES.keys())
  }

  // 获取主题的中文名
  static getThemeLabel(name: string): string {
    const labels: Record<string, string> = {}
    labels['jianbai'] = '简约'
    labels['sea_breeze'] = '夏日海风'
    labels['sunset_sweet'] = '落霞甜夏'
    return labels[name] || name
  }

  // 获取主题色板
  static getTheme(name: string): ThemePalette {
    return THEMES.get(name) ?? THEMES.get('jianbai')!
  }

  // 初始化主题（应用启动时调用）
  static async initTheme() {
    // 默认值已在模块加载时同步注册，这里只需读取数据库并应用保存的主题
    const saved = await ThemeManager.db.getSetting('theme')
    const themeName = saved || 'jianbai'
    ThemeManager.applyTheme(themeName)
  }

  // 注册默认值到 AppStorage（防止首次启动时 @StorageProp 读取 undefined）
  // 公开方法，允许模块加载时同步调用
  static registerDefaults() {
    const defaultTheme = THEMES.get('jianbai')!
    const palette: ThemePalette = defaultTheme
    AppStorage.setOrCreate('theme_primary', palette.primary)
    AppStorage.setOrCreate('theme_primaryLight', palette.primaryLight)
    AppStorage.setOrCreate('theme_bg', palette.bg)
    AppStorage.setOrCreate('theme_cardBg', palette.cardBg)
    AppStorage.setOrCreate('theme_surface', palette.surface)
    AppStorage.setOrCreate('theme_textPrimary', palette.textPrimary)
    AppStorage.setOrCreate('theme_textSecondary', palette.textSecondary)
    AppStorage.setOrCreate('theme_divider', palette.divider)
    AppStorage.setOrCreate('theme_danger', palette.danger)
    AppStorage.setOrCreate('theme_placeholder', palette.placeholder)
  }

  // 应用主题（用户选择时调用）
  static applyTheme(name: string) {
    const palette = THEMES.get(name) ?? THEMES.get('jianbai')!
    AppStorage.setOrCreate('theme_primary', palette.primary)
    AppStorage.setOrCreate('theme_primaryLight', palette.primaryLight)
    AppStorage.setOrCreate('theme_bg', palette.bg)
    AppStorage.setOrCreate('theme_cardBg', palette.cardBg)
    AppStorage.setOrCreate('theme_surface', palette.surface)
    AppStorage.setOrCreate('theme_textPrimary', palette.textPrimary)
    AppStorage.setOrCreate('theme_textSecondary', palette.textSecondary)
    AppStorage.setOrCreate('theme_divider', palette.divider)
    AppStorage.setOrCreate('theme_danger', palette.danger)
    AppStorage.setOrCreate('theme_placeholder', palette.placeholder)
  }
}

// 模块加载时同步注册默认值，确保 AppStorage 在任何组件创建前就有值
// 这样 @StorageProp 才能正确订阅后续的主题变更
ThemeManager.registerDefaults()