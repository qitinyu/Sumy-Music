// SHMY 主题管理器 - V1.0.5 暗夜模式
// ThemeManager.ets
import { DatabaseHelper } from '../database/DatabaseHelper'
import { ConfigurationConstant } from '@kit.AbilityKit'

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

// ===== 亮色主题 =====
const THEMES_LIGHT: Map<string, ThemePalette> = new Map()
THEMES_LIGHT.set('jianbai', {
  primary: '#007DFF',
  primaryLight: '#E0F0FF',
  bg: '#F5F5FA',
  cardBg: '#FFFFFF',
  surface: '#FFFFFF',
  textPrimary: '#1A1A1A',
  textSecondary: '#4A4A4A',
  divider: '#E8E8E8',
  danger: '#F44336',
  placeholder: '#E0E0E0',
} as ThemePalette)
THEMES_LIGHT.set('sea_breeze', {
  primary: '#7BA7C4',
  primaryLight: '#D6E6F0',
  bg: '#F5F2ED',
  cardBg: '#FFFFFF',
  surface: '#FAF9F7',
  textPrimary: '#3A3A3A',
  textSecondary: '#4A4A4A',
  divider: '#EBE7E2',
  danger: '#D4958A',
  placeholder: '#E5E0DB',
} as ThemePalette)
THEMES_LIGHT.set('sunset_sweet', {
  primary: '#EFCACA',
  primaryLight: '#F1D6D6',
  bg: '#F3E5E8',
  cardBg: '#FFFFFF',
  surface: '#F1DADD',
  textPrimary: '#4A3538',
  textSecondary: '#4A4A4A',
  divider: '#EFCDCF',
  danger: '#D4958A',
  placeholder: '#F1D6D6',
} as ThemePalette)
THEMES_LIGHT.set('nyqf', {
  primary: '#B2BF96',
  primaryLight: '#C6CFB0',
  bg: '#F0EFE8',
  cardBg: '#FFFFFF',
  surface: '#DDE3C9',
  textPrimary: '#4A4A3A',
  textSecondary: '#4A4A4A',
  divider: '#DDE3C9',
  danger: '#D4958A',
  placeholder: '#DDE3C9',
} as ThemePalette)
THEMES_LIGHT.set('nyha', {
  primary: '#ECF1D4',
  primaryLight: '#ECE0C7',
  bg: '#F5F1DC',
  cardBg: '#FFFFFF',
  surface: '#F2EAD7',
  textPrimary: '#4A453A',
  textSecondary: '#4A4A4A',
  divider: '#F2EAD7',
  danger: '#D4958A',
  placeholder: '#F2EAD7',
} as ThemePalette)
THEMES_LIGHT.set('xcwh', {
  primary: '#D0DCF3',
  primaryLight: '#D4DDEF',
  bg: '#D9E1F1',
  cardBg: '#FFFFFF',
  surface: '#DEE4EF',
  textPrimary: '#3A3A4A',
  textSecondary: '#4A4A4A',
  divider: '#DEE4EF',
  danger: '#D4958A',
  placeholder: '#DEE4EF',
} as ThemePalette)

// ===== 暗色主题 =====
const THEMES_DARK: Map<string, ThemePalette> = new Map()
THEMES_DARK.set('jianbai', {
  primary: '#3399FF',
  primaryLight: '#1A3350',
  bg: '#1A1A1E',
  cardBg: '#2C2C32',
  surface: '#2C2C32',
  textPrimary: '#E0E0E0',
  textSecondary: '#888888',
  divider: '#3A3A3E',
  danger: '#FF6B6B',
  placeholder: '#3A3A3E',
} as ThemePalette)
THEMES_DARK.set('sea_breeze', {
  primary: '#8DB8D0',
  primaryLight: '#2A3A44',
  bg: '#1A1D1E',
  cardBg: '#2C2C32',
  surface: '#2A2D2E',
  textPrimary: '#E0E0E0',
  textSecondary: '#8A8A8A',
  divider: '#3A3A3E',
  danger: '#E89090',
  placeholder: '#3A3A3E',
} as ThemePalette)
THEMES_DARK.set('sunset_sweet', {
  primary: '#F0D0D0',
  primaryLight: '#3A2828',
  bg: '#1E1A1C',
  cardBg: '#2C282A',
  surface: '#2A1E20',
  textPrimary: '#E0D8D8',
  textSecondary: '#9A8A8A',
  divider: '#3A2E32',
  danger: '#E89090',
  placeholder: '#3A2E32',
} as ThemePalette)
THEMES_DARK.set('nyqf', {
  primary: '#C6D0A8',
  primaryLight: '#3A3E30',
  bg: '#1A1A18',
  cardBg: '#2C2C2A',
  surface: '#2A2A26',
  textPrimary: '#E0E0D8',
  textSecondary: '#9DA97C',
  divider: '#3A3A36',
  danger: '#E89090',
  placeholder: '#3A3A36',
} as ThemePalette)
THEMES_DARK.set('nyha', {
  primary: '#F0E9CE',
  primaryLight: '#4A4638',
  bg: '#1A1916',
  cardBg: '#2C2C28',
  surface: '#2A2922',
  textPrimary: '#E0DED0',
  textSecondary: '#A89A7A',
  divider: '#3A3932',
  danger: '#E89090',
  placeholder: '#3A3932',
} as ThemePalette)
THEMES_DARK.set('xcwh', {
  primary: '#D0DCF3',
  primaryLight: '#3A3E4E',
  bg: '#1A1A24',
  cardBg: '#2C2C34',
  surface: '#2A2A32',
  textPrimary: '#E0E0E8',
  textSecondary: '#8A9ABA',
  divider: '#3A3A42',
  danger: '#E89090',
  placeholder: '#3A3A42',
} as ThemePalette)

// 主题背景图映射（key：主题名，value：rawfile 背景图短名）
const THEME_BG_RESOURCES: Record<string, string> = {
  'sunset_sweet': 'lxtx',
  'sea_breeze': 'xrhf',
  'nyqf': 'nyqf',
  'nyha': 'nyha',
  'xcwh': 'xcwh',
}

export class ThemeManager {
  private static db: DatabaseHelper = DatabaseHelper.getInstance()
  private static currentTheme: string = 'jianbai'
  private static isDark: boolean = false

  // 获取所有主题名列表
  static getThemeNames(): string[] {
    return Array.from(THEMES_LIGHT.keys())
  }

  // 获取主题的中文名
  static getThemeLabel(name: string): string {
    const labels: Record<string, string> = {}
    labels['jianbai'] = '简白'
    labels['sea_breeze'] = '夏日海风'
    labels['sunset_sweet'] = '落霞甜夏'
    labels['nyqf'] = '暖野清风'
    labels['nyha'] = '暖阳海岸'
    labels['xcwh'] = '香草午后'
    return labels[name] || name
  }

  // 获取当前是否暗色模式
  static getIsDark(): boolean {
    return ThemeManager.isDark
  }

  // 获取当前主题名
  static getCurrentTheme(): string {
    return ThemeManager.currentTheme
  }

  // 初始化主题（应用启动时调用）
  static async initTheme(colorMode: number): Promise<void> {
    const saved = await ThemeManager.db.getSetting('theme')
    const themeName = saved || 'jianbai'
    ThemeManager.currentTheme = themeName

    const dark = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    ThemeManager.isDark = dark
    ThemeManager.applyTheme(themeName, dark)
  }

  // 系统暗色模式变更时调用
  static async onSystemDarkModeChange(colorMode: number): Promise<void> {
    const dark = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    if (dark !== ThemeManager.isDark) {
      ThemeManager.isDark = dark
      ThemeManager.applyTheme(ThemeManager.currentTheme, dark)
    }
  }

  // 注册默认值到 AppStorage（防止首次启动时 @StorageProp 读取 undefined）
  static registerDefaults() {
    const defaultTheme = THEMES_LIGHT.get('jianbai')!
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
    AppStorage.setOrCreate('isDarkMode', false)
    AppStorage.setOrCreate('theme_bgImageName', '')
  }

  // 应用主题（用户选择时调用，isDark 可选，不传则保持当前暗色模式状态）
  static applyTheme(name: string, isDark?: boolean) {
    const dark = isDark !== undefined ? isDark : ThemeManager.isDark
    ThemeManager.currentTheme = name
    ThemeManager.isDark = dark

    // 深色模式下强制使用简白深色样式，不受主题影响（无论手动开关还是系统触发）
    const effectiveName = dark ? 'jianbai' : name
    const themes = dark ? THEMES_DARK : THEMES_LIGHT
    const palette = themes.get(effectiveName) ?? themes.get('jianbai')!
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
    AppStorage.setOrCreate('isDarkMode', dark)

    // 深色模式下不显示主题背景图
    const bgName = dark ? '' : THEME_BG_RESOURCES[name]
    AppStorage.setOrCreate('theme_bgImageName', bgName ?? '')
  }
}

// 模块加载时同步注册默认值，确保 AppStorage 在任何组件创建前就有值
ThemeManager.registerDefaults()