// Sumy - 设置
// LoushiTab.ets - V1.0.3 分区卡片式布局
import { DEFAULT_SETTINGS } from '../model/MusicModel'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { PluginManagerPage } from '../components/PluginManagerPage'

import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { common, Want, bundleManager } from '@kit.AbilityKit'
import { ThemeManager } from '../utils/ThemeManager'
import { WebDavSync } from '../utils/WebDavSync'
import { MusicApi } from '../utils/MusicApi'
import { SelfHostedApi } from '../utils/SelfHostedApi'
import { AccountManager } from '../utils/AccountManager'
import { SourceManager } from '../utils/SourceManager'
import { CacheManager, CacheInfo } from '../utils/CacheManager'
import { ListeningLevelManager, LevelInfo } from '../utils/ListeningLevelManager'
import { getLevelColor, LEVEL_TEXT_COLOR } from '../utils/LevelConfig'
import { MaterialCompat, MaterialCompatStyle } from '../utils/MaterialCompat'
import {
  HdsNavigation,
  HdsNavDestination,
  HdsNavigationTitleBarOptions,
  ScrollEffectType,
  hdsMaterial
} from '@kit.UIDesignKit'

// 自建 API 访问密码（仅开发者本人可启用）
const SELF_HOSTED_API_PASSWORD: string = '0723'

// 选择项
interface PickerOption {
  label: string
  value: string
}

const THEME_OPTIONS: PickerOption[] = [
  { label: '\u7B80\u767D', value: 'jianbai' },
  { label: '\u590F\u65E5\u6D77\u98CE', value: 'sea_breeze' },
  { label: '\u843D\u971E\u751C\u590F', value: 'sunset_sweet' },
  { label: '\u6696\u91CE\u6E05\u98CE', value: 'nyqf' },
  { label: '\u6696\u9633\u6D77\u5CB8', value: 'nyha' },
  { label: '\u9999\u8349\u5348\u540E', value: 'xcwh' },
]

// 关于页面项
interface LinkOption {
  label: string
  url: string
}

interface AboutItem {
  label: string
  type: 'text' | 'link' | 'feedback' | 'links'
  content?: string
  url?: string
  urls?: LinkOption[]
}

const aboutItems: AboutItem[] = [
  {
    label: '软件说明',
    type: 'text',
    content: '1. Sumy Music 是一款简洁优雅的音乐播放器应用\n\n' +
      '2. 本应用支持本地音乐播放/在线音乐搜索/WebDAV网盘曲库播放 \n\n' +
      '3. 无广告/无弹窗/无会员 \n\n' +
      '4. 致力于为用户带来纯粹的音乐体验',
  },
  {
    label: '隐私政策',
    type: 'link',
    url: 'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2008081676026026304',
  },
  {
    label: '软件协议',
    type: 'text',
    content: '本软件采用 MIT 开源协议：\n\n' +
      '1. MIT License\n' +
      '2. Copyright (c) 2026 Sumy Music\n' +
      '3. Permission is hereby granted, free of charge, to any person obtaining a copy ' +
      'of this software and associated documentation files...',
  },
  {
    label: '版本日志',
    type: 'text',
    content: 'v2.0.9.6\n' +
      '1. 搜索页/推荐页搜索栏迁入系统沉浸标题栏，推荐页分类标签对齐\n' +
      '2. 修复歌单播放大量自动跳过：播放时强制重新取链，不再使用过期链接\n' +
      '3. 歌单/收藏播放支持自动换源（全网兜底），失败自动跳下一首\n' +
      '4. 播放设置新增「自动换源」开关，默认开启\n' +
      '5. 歌单添加同曲同源自动替换不再重复；删除改单条精确删除\n' +
      '6. APP 图标真实热更换（默认/备选即点即换），旧系统自动提示\n' +
      '7. 个性化去除沉浸光感卡片；音源管理「订阅导入」长按彩蛋跳转帮助文档\n' +
      '8. 完整更新日志(----------https://github.com/qitinyu/Sumy-Music/wiki/)',
  },

  {
  label: '用户反馈',
  type: 'feedback',
  },

  {
    label: '开源链接',
    type: 'link',
    url: 'https://github.com/qitinyu/Sumy-Music/',
  },

  {
    label: '软件更新',
    type: 'links',
    urls: [
      { label: 'GitHub Release', url: 'https://github.com/qitinyu/SHMY/releases/' },
      { label: 'GitCode Release', url: 'https://gitcode.com/YQAMM/Sumy-Music/releases/' },
    ],
  },

  {
    label: '帮助鸣谢',
    type: 'link',
    url: 'https://github.com/qitinyu/Sumy-Music/blob/main/%E5%B8%AE%E5%8A%A9%E9%B8%A3%E8%B0%A2.md',
  },
]

type SubPage = 'main'
  | 'personalization'
  | 'player'
  | 'webdev_config'
  | 'self_hosted_api'
  | 'plugin_manager'
  | 'about'
  | 'xuanchuang_settings'
  | 'qinse_settings'
  | 'cache_settings'

interface SettingItem {
  icon: Resource
  label: string
  target: SubPage
  requireLogin?: boolean
  locked?: boolean
}

@Component
export struct LoushiTab {
  // V2.1.9：loushi_subPage 不再驱动 build 分支，仅作为「当前是否在设置子页」的 AppStorage 标志，
  // 供 Index.onBackPress 判断：子页内按返回 → 发信号 pop 路由栈；主页按返回 → 关闭侧边栏
  @StorageLink('loushi_subPage') subPage: SubPage = 'main'
  // V2.1.9：设置子页路由栈（HdsNavDestination 由 SubPageMap 按路由名构造）
  private loushiStack: NavPathStack = new NavPathStack()
  // Index 返回键信号（时间戳）：设置子页内按返回 → pop 路由栈
  @StorageProp('loushiNavBackSignal') @Watch('onNavBackSignal') navBackSignal: number = 0
  @State theme: string = DEFAULT_SETTINGS.theme
  @State autoPlay: boolean = DEFAULT_SETTINGS.autoPlay
  @State autoJumpDetail: boolean = DEFAULT_SETTINGS.autoJumpDetail
  @State rememberProgress: boolean = DEFAULT_SETTINGS.rememberProgress
  // 封面/歌词自动补全，默认关闭（开启后缺失封面/歌词时联网补全）
  @State autoEnrichTags: boolean = false
  // 自动换源，默认开启（关闭后歌曲播放失败自动跳过不再换源）
  @State autoSourceSwitch: boolean = true
  // 迷你栏歌曲来源徽章，默认开启
  @State miniBarShowSource: boolean = true
  @State searchMemory: boolean = true // 默认开启
  @State searchPersist: boolean = false // 搜索常驻，默认关闭
  @State searchSuggest: boolean = true // 搜索联想词，默认开启
  @State showHomeStats: boolean = true // 默认开启
  // 筛选源规定-自动定位跳转（默认开启）：自动记忆、定位、跳转上次的音源位置
  @State searchSourceLocate: boolean = true
  // 歌单内设置-定位播放歌曲（默认关闭）：开启后进入歌单自动定位并跳转播放中歌曲
  @State playlistLocatePlaying: boolean = false
  // 播放列表设置-定位播放歌曲（默认关闭）：开启后进入歌单自动定位并跳转播放中歌曲
  @State queueLocatePlaying: boolean = false
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_bg') themeBg: string = '#F8F8FA'
  @StorageProp('theme_cardBg') themeCardBg: string = '#FFFFFF'
  @StorageProp('theme_primaryLight') themePrimaryLight: string = '#E0F0FF'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'
  @StorageProp('theme_divider') themeDivider: string = '#E8E8E8'
  @StorageProp('theme_placeholder') themePlaceholder: string = '#E0E0E0'
  @StorageProp('theme_bgImageName') themeBgImageName: string = ''

  // WebDAV 配置
  @State webdavUrl: string = ''
  @State webdavUser: string = ''
  @State webdavPass: string = ''
  @State webdavPath: string = ''
  @State webdavShowPass: boolean = false
  @State webdavTesting: boolean = false
  @State webdavParseMode: string = 'song-artist'

  // 数据同步
  @State syncing: boolean = false
  @State lastSyncTime: number = 0
  @State syncMessage: string = ''

  @State showAboutDialog: boolean = false
  @State aboutDialogTitle: string = ''
  @State aboutDialogContent: string = ''

  // 自建 API 配置
  @StorageProp('useSelfHostedApi') useSelfHostedApi: boolean = false // 默认关闭，填写地址后手动开启
  @StorageProp('selfHostedApiUrl') selfHostedApiUrl: string = ''
  @State selfHostedApiTesting: boolean = false

  // APP 图标
  @State appIcon: string = 'default'
  @State cacheInfo: CacheInfo = { bytes: 0, files: 0 }
  @State clearingCache: boolean = false

  // 账号设置（复用我的页个人信息区）
  @State accountUserName: string = '点击登录'
  @State accountAvatarUrl: string = ''
  @State accountIsLoggedIn: boolean = false
  @State accountLoggingIn: boolean = false
  @State accountLevelInfo: LevelInfo = { level: 1, current: 0, need: 1000, totalSeconds: 0, percent: 0 }
  @State accountSignature: string = ''
  @State accountShowMenu: boolean = false

  private db: DatabaseHelper = DatabaseHelper.getInstance()

  async aboutToAppear() {
    await this.loadSettings()
    await this.refreshCacheInfo()
    await this.loadAccountInfo()
  }

  private async loadAccountInfo(): Promise<void> {
    const savedUser = await AccountManager.loadSavedUserInfo()
    if (savedUser) {
      this.accountUserName = savedUser.displayName
      this.accountAvatarUrl = savedUser.avatarUri
      this.accountIsLoggedIn = true
      const manager = ListeningLevelManager.getInstance()
      await manager.init()
      this.accountLevelInfo = manager.getLevelInfo()
      this.accountSignature = manager.getSignature()
    } else {
      this.accountUserName = '点击登录'
      this.accountAvatarUrl = ''
      this.accountIsLoggedIn = false
      this.accountLevelInfo = { level: 1, current: 0, need: 1000, totalSeconds: 0, percent: 0 }
      this.accountSignature = ''
    }
  }

  private async accountDoLogin(): Promise<void> {
    this.accountLoggingIn = true
    try {
      const context = this.getUIContext().getHostContext() as common.Context
      const result = await AccountManager.login(context)
      if (result.success && result.userInfo) {
        this.accountUserName = result.userInfo.displayName
        this.accountAvatarUrl = result.userInfo.avatarUri
        this.accountIsLoggedIn = true
        await this.loadAccountInfo()
        this.showToastMsg('登录成功')
      } else {
        this.showToastMsg(result.error || '登录失败')
      }
    } finally {
      this.accountLoggingIn = false
    }
  }

  private async accountDoLogout(): Promise<void> {
    await AccountManager.logout()
    ListeningLevelManager.getInstance().reset()
    this.accountUserName = '点击登录'
    this.accountAvatarUrl = ''
    this.accountIsLoggedIn = false
    this.accountLevelInfo = { level: 1, current: 0, need: 1000, totalSeconds: 0, percent: 0 }
    this.accountSignature = ''
    this.accountShowMenu = false
    this.showToastMsg('已退出登录')
  }

  // 彻底退出应用
  private accountExitApp(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      ctx.terminateSelf()
    } catch (e) {
      console.error('[LoushiTab] exit app failed:', e)
      this.showToastMsg('退出失败')
    }
  }

  // 重启应用
  private accountRestartApp(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      ctx.startAbility({
        bundleName: ctx.abilityInfo.bundleName,
        abilityName: ctx.abilityInfo.name
      })
      ctx.terminateSelf()
    } catch (e) {
      console.error('[LoushiTab] restart app failed:', e)
      this.showToastMsg('重启失败')
    }
  }

  private async refreshCacheInfo(): Promise<void> {
    this.cacheInfo = await CacheManager.getInfo()
  }

  private async clearAppCache(): Promise<void> {
    if (this.clearingCache) return
    this.clearingCache = true
    try {
      await CacheManager.clear()
      await this.refreshCacheInfo()
      this.showToastMsg('缓存清理完成')
    } catch (e) {
      console.error('[LoushiTab] clear cache failed:', e)
      this.showToastMsg('缓存清理失败')
    } finally {
      this.clearingCache = false
    }
  }

  private async loadSettings() {
    this.theme = (await this.db.getSetting('theme')) || DEFAULT_SETTINGS.theme
    this.autoPlay = (await this.db.getSetting('autoPlay')) === 'true'
    this.autoJumpDetail = (await this.db.getSetting('autoJumpDetail')) === 'true'
    this.rememberProgress = (await this.db.getSetting('rememberProgress')) !== 'false' // 默认开启
    // 封面/歌词自动补全：默认关闭，仅在用户开启时联网补全
    this.autoEnrichTags = (await this.db.getSetting('autoEnrichTags')) === 'true'
    AppStorage.setOrCreate('autoEnrichTags', this.autoEnrichTags)
    // 自动换源：默认开启（关闭后歌曲播放失败自动跳过不再换源）
    const autoSwitch = await this.db.getSetting('autoSourceSwitch')
    this.autoSourceSwitch = autoSwitch !== 'false'
    AppStorage.setOrCreate('autoSourceSwitch', this.autoSourceSwitch)
    // 迷你栏来源徽章：默认开启
    const showSource = await this.db.getSetting('miniBarShowSource')
    this.miniBarShowSource = showSource !== 'false'
    AppStorage.setOrCreate('miniBarShowSource', this.miniBarShowSource)
    const searchMem = await this.db.getSetting('searchMemory')
    this.searchMemory = searchMem !== 'false' // 默认开启
    const searchPersist = await this.db.getSetting('searchPersist')
    this.searchPersist = searchPersist === 'true'
    const searchSuggest = await this.db.getSetting('searchSuggest')
    this.searchSuggest = searchSuggest !== 'false' // 默认开启
    const homeStats = await this.db.getSetting('showHomeStats')
    this.showHomeStats = homeStats !== 'false' // 默认开启
    // 筛选源规定-自动定位跳转（默认开启）
    const sourceLocate = await this.db.getSetting('searchSourceLocate')
    this.searchSourceLocate = sourceLocate !== 'false'
    AppStorage.setOrCreate('searchSourceLocate', this.searchSourceLocate)
    // 歌单内设置-定位播放歌曲（默认关闭）
    const playlistLocate = await this.db.getSetting('playlistLocatePlaying')
    this.playlistLocatePlaying = playlistLocate === 'true'
    AppStorage.setOrCreate('playlistLocatePlaying', this.playlistLocatePlaying)
    // 播放列表设置-定位播放歌曲（默认关闭）
    const queueLocate = await this.db.getSetting('queueLocatePlaying')
    this.queueLocatePlaying = queueLocate === 'true'
    AppStorage.setOrCreate('queueLocatePlaying', this.queueLocatePlaying)

    // WebDAV
    this.webdavUrl = (await this.db.getSetting('webdav_url')) || ''
    this.webdavUser = (await this.db.getSetting('webdav_user')) || ''
    this.webdavPass = (await this.db.getSetting('webdav_pass')) || ''
    this.webdavPath = (await this.db.getSetting('webdav_path')) || ''
    this.webdavParseMode = (await this.db.getSetting('webdav_parse_mode')) || 'song-artist'

    // 上次同步时间
    this.lastSyncTime = await WebDavSync.getLastSyncTime()

    // 自建 API（默认关闭，需手动开启）
    this.useSelfHostedApi = (await this.db.getSetting('useSelfHostedApi')) === 'true'
    this.selfHostedApiUrl = (await this.db.getSetting('selfHostedApiUrl')) || ''
    MusicApi.setSelfHostedMode(this.useSelfHostedApi, this.selfHostedApiUrl)

    // APP 图标
    this.appIcon = (await this.db.getSetting('appIcon')) || 'default'
  }

  private saveSetting(key: string, value: string) {
    this.db.setSetting(key, value)
  }

  private showToastMsg(msg: string) {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 })
  }

  // 保存自建 API 设置
  private saveSelfHostedApiSettings(): void {
    const url = this.selfHostedApiUrl.trim()
    if (this.useSelfHostedApi && url.length === 0) {
      this.showToastMsg('请先填写 API 地址')
      return
    }
    this.selfHostedApiUrl = url
    this.saveSetting('useSelfHostedApi', String(this.useSelfHostedApi))
    this.saveSetting('selfHostedApiUrl', url)
    MusicApi.setSelfHostedMode(this.useSelfHostedApi, url)
    this.showToastMsg('保存成功')
  }

  // 启用自建 API 时自动关闭所有插件音源（互斥，避免搜索源混乱）
  private async disableAllPluginSources(): Promise<void> {
    try {
      await SourceManager.ensureLoaded()
      const names = SourceManager.getSourceNames()
      for (let i = 0; i < names.length; i++) {
        await SourceManager.setSourceEnabled(names[i], false)
      }
      console.info('[LoushiTab] All plugin sources disabled for self-hosted API mode')
    } catch (e) {
      console.error('[LoushiTab] disableAllPluginSources failed:', e)
    }
  }

  // 测试自建 API 连接
  private async testSelfHostedApiConnection(): Promise<void> {
    const url = this.selfHostedApiUrl.trim()
    if (url.length === 0) {
      this.showToastMsg('请先填写 API 地址')
      return
    }
    this.selfHostedApiTesting = true
    const ok = await SelfHostedApi.testConnection(url)
    this.selfHostedApiTesting = false
    if (ok) {
      this.showToastMsg('连接成功')
    } else {
      this.showToastMsg('连接失败，请检查地址或网络')
    }
  }

  private openUrl(url: string) {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url,
      }
      ctx.startAbility(want)
    } catch {
      this.showToastMsg('无法打开链接')
    }
  }

  private showFeedback() {
    this.getUIContext().getPromptAction().showActionMenu({
      title: '选择反馈方式',
      buttons: [
        { text: 'QQ群聊', color: this.themePrimary },
        { text: 'GitHub Discussion', color: this.themePrimary },
        { text: 'Git Code', color: this.themePrimary },
      ],
    }).then((res) => {
      if (res.index === 0) {
        this.showToastMsg('QQ群: 985641970')
      } else if (res.index === 1) {
        this.openUrl('https://github.com/qitinyu/SHMY/discussions/')
      } else if (res.index ===2) {
        this.openUrl('https://gitcode.com/YQAMM/Sumy-Music/discussions/2')
      }
    })
  }

  private showLinks(links: LinkOption[]) {
    this.getUIContext().getPromptAction().showActionMenu({
      title: '选择下载渠道',
      buttons: [
        { text: links[0].label, color: this.themePrimary },
        { text: links[1].label, color: this.themePrimary },
      ],
    }).then((res) => {
      if (res.index !== undefined && res.index < links.length) {
        this.openUrl(links[res.index].url)
      }
    })
  }

  build() {
    Column() {
      // V2.1.9：设置子页改走 HdsNavigation 路由栈 —— 子页获得系统 MINI 标题栏（返回键自动 pop、沉浸材质、转场动画）
      HdsNavigation(this.loushiStack) {
        Column() {
          this.MainPage()
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Start)
      }
      .mode(NavigationMode.Stack)
      .hideTitleBar(true)
      .navDestination(this.SubPageMap)
      .width('100%')
      .height('100%')
    }
    .width('100%').height('100%')
      .padding({ top: 44 })
      .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
      .justifyContent(FlexAlign.Start)
      .bindSheet($$this.showLockDialog, this.LockPasswordSheet(), {
        height: 260,
        showClose: true,
        dragBar: false,
        backgroundColor: this.themeCardBg
      })
  }

  // ======================== V2.1.9 子页路由 ========================

  /** 子页沉浸标题栏（MINI 模式，返回键默认 pop）——静止时背景板透明；滚动后浮出浅灰模糊板（API23 规则） */
  private getDestTitleBar(title: string): HdsNavigationTitleBarOptions {
    return {
      content: {
        title: { mainTitle: title },
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
        },
        // 不配 systemMaterialEffect 时滚动板为 #99000000 黑板（API23 规则），与浅色状态栏割裂
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
        },
      },
      // 官方样例必配：禁用标题栏内部安全区避让，防止贴边时 56vp 高度被压缩
      avoidLayoutSafeArea: false,
      enableComponentSafeArea: false,
    }
  }

  /** 进入设置子页：压入路由栈并同步 AppStorage 标志（供 Index 返回键判断） */
  private goSubPage(target: SubPage): void {
    this.subPage = target
    this.loushiStack.pushPathByName(target, '')
  }

  /** 返回设置主页（代码调用；子页标题栏返回键由系统自动 pop） */
  private popSubPage(): void {
    this.loushiStack.pop()
    this.subPage = 'main'
  }

  /** 子页隐藏时同步标志（覆盖标题栏返回键自动 pop 的场景） */
  private onDestHidden(): void {
    if (this.loushiStack.size() === 0) {
      this.subPage = 'main'
    }
  }

  private onNavBackSignal(): void {
    if (this.loushiStack.size() > 0) {
      this.popSubPage()
    }
  }

  /** 子页路由表：按路由名构造 HdsNavDestination（内容让出 56vp 标题栏高度） */
  @Builder
  SubPageMap(name: string) {
    if (name === 'personalization') {
      HdsNavDestination() {
        Column() {
          this.PersonalizationPage()
        }
        .width('100%').height('100%')
        .padding({ top: 56 })
      }
      .titleBar(this.getDestTitleBar('个性化'))
      .onHidden(() => { this.onDestHidden() })
    } else if (name === 'player') {
      HdsNavDestination() {
        Column() {
          this.PlayerSettingsPage()
        }
        .width('100%').height('100%')
        .padding({ top: 56 })
      }
      .titleBar(this.getDestTitleBar('播放器'))
      .onHidden(() => { this.onDestHidden() })
    } else if (name === 'webdev_config') {
      HdsNavDestination() {
        Column() {
          this.WebdevConfigPage()
        }
        .width('100%').height('100%')
        .padding({ top: 56 })
      }
      .titleBar(this.getDestTitleBar('WebDAV'))
      .onHidden(() => { this.onDestHidden() })
    } else if (name === 'self_hosted_api') {
      HdsNavDestination() {
        Column() {
          this.SelfHostedApiPage()
        }
        .width('100%').height('100%')
        .padding({ top: 56 })
      }
      .titleBar(this.getDestTitleBar('自建 API'))
      .onHidden(() => { this.onDestHidden() })
    } else if (name === 'plugin_manager') {
      // 音源管理为外部组件，自带头部（含返回键），隐藏系统标题栏避免重复
      HdsNavDestination() {
        PluginManagerPage({ onBack: () => { this.popSubPage() } })
      }
      .hideTitleBar(true)
      .onHidden(() => { this.onDestHidden() })
    } else if (name === 'about') {
      HdsNavDestination() {
        Column() {
          this.AboutPage()
        }
        .width('100%').height('100%')
        .padding({ top: 56 })
      }
      .titleBar(this.getDestTitleBar('关于 Sumy Music'))
      .onHidden(() => { this.onDestHidden() })
    } else if (name === 'xuanchuang_settings') {
      HdsNavDestination() {
        Column() {
          this.XuanchuangSettingsPage()
        }
        .width('100%').height('100%')
        .padding({ top: 56 })
      }
      .titleBar(this.getDestTitleBar('主页设置'))
      .onHidden(() => { this.onDestHidden() })
    } else if (name === 'qinse_settings') {
      HdsNavDestination() {
        Column() {
          this.QinseSettingsPage()
        }
        .width('100%').height('100%')
        .padding({ top: 56 })
      }
      .titleBar(this.getDestTitleBar('搜索设置'))
      .onHidden(() => { this.onDestHidden() })
    } else if (name === 'cache_settings') {
      HdsNavDestination() {
        Column() {
          this.CacheSettingsPage()
        }
        .width('100%').height('100%')
        .padding({ top: 56 })
      }
      .titleBar(this.getDestTitleBar('缓存清理'))
      .onHidden(() => { this.onDestHidden() })
    }
  }

  // ===== 密码锁弹窗 =====
  @State showLockDialog: boolean = false
  @State lockTarget: SubPage = 'main'
  @State lockInput: string = ''

  @Builder
  LockPasswordSheet() {
    Column({ space: 12 }) {
      Text('访问受限')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.themeTextPrimary)
      Text('请输入密码以继续')
        .fontSize(13)
        .fontColor(this.themeTextSecondary)
      TextInput({ placeholder: '请输入密码', text: this.lockInput })
        .type(InputType.Password)
        .height(44)
        .borderRadius(12)
        .backgroundColor(this.themePlaceholder)
        .fontColor(this.themeTextPrimary)
        .margin({ top: 8 })
        .onChange((value: string) => {
          this.lockInput = value
        })
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .backgroundColor(this.themePlaceholder)
          .fontColor(this.themeTextPrimary)
          .onClick(() => {
            this.showLockDialog = false
            this.lockInput = ''
          })
        Button('确定')
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .backgroundColor(this.themePrimary)
          .fontColor(Color.White)
          .onClick(() => {
            if (this.lockInput.trim() === SELF_HOSTED_API_PASSWORD) {
              const target = this.lockTarget
              this.showLockDialog = false
              this.lockInput = ''
              this.goSubPage(target)
            } else {
              this.showToastMsg('密码错误')
              this.lockInput = ''
            }
          })
      }
      .margin({ top: 4 })
    }
    .width('100%')
    .padding(20)
  }

  // ===== 卡片行 =====
  @Builder
  CardRow(icon: Resource, title: string, target: SubPage, requireLogin: boolean = false) {
    Row() {
      SymbolGlyph(icon).fontSize(26).fontColor([this.themeTextPrimary])
      Text(title).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.themeTextPrimary).layoutWeight(1).margin({ left: 12 })
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor([this.themeTextSecondary])
    }
    .width('100%').height(56).padding({ left: 16, right: 16 }).backgroundColor(this.themeCardBg).borderRadius(12)
    .onClick(() => {
      if (requireLogin) {
        this.navigateWithLoginCheck(target)
      } else {
        this.goSubPage(target)
      }
    })
  }

  private async navigateWithLoginCheck(target: SubPage, locked: boolean = false): Promise<void> {
    const loggedIn = await AccountManager.isLoggedIn()
    if (loggedIn) {
      if (locked) {
        this.verifyLock(target)
      } else {
        this.goSubPage(target)
      }
    } else {
      this.showToastMsg('请先在主页登录华为账号')
    }
  }

  // ===== 简易开关行 =====
  @Builder
  ToggleRow(title: string, desc: string, checked: boolean, onChange: (v: boolean) => void) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(15).fontColor(this.themeTextPrimary).width('100%')
        Text(desc).fontSize(12).fontColor(this.themeTextSecondary).width('100%')
      }
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: checked })
        .selectedColor(this.themePrimary)
        .onChange((v: boolean) => { onChange(v) })
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  // ===== 主题卡片（含缩略图） =====
  @Builder
  ThemeCard() {
    Column() {
      Text('主题')
        .fontSize(15)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 12 })

      Row({ space: 8 }) {
        this.ThemeOption('jianbai', '简白', '#F5F5FA', '#1A1A1A')
        this.ThemeOption('sea_breeze', '夏日海风', '#D6E6F0', '#3A3A3A', $r('app.media.slt_xrhf'))
        this.ThemeOption('sunset_sweet', '落霞甜夏', '#F3E5E8', '#4A3538', $r('app.media.slt_lxtx'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      Row({ space: 8 }) {
        this.ThemeOption('nyqf', '暖野清风', '#DDE3C9', '#4A4A3A', $r('app.media.slt_nyqf'))
        this.ThemeOption('nyha', '暖阳海岸', '#F2EAD7', '#4A453A', $r('app.media.slt_nyha'))
        this.ThemeOption('xcwh', '香草午后', '#DEE4EF', '#3A3A4A', $r('app.media.slt_xcwh'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
    }
    .width('100%')
    .backgroundColor(this.themeCardBg)
    .borderRadius(12)
  }

  @Builder
  ThemeOption(value: string, label: string, placeholderColor: string, textColor: string, thumbnailRes?: Resource) {
    Column({ space: 6 }) {
      if (thumbnailRes) {
        Image(thumbnailRes)
          .width('100%')
          .height(64)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          Text(label.charAt(0))
            .fontSize(16)
            .fontColor(textColor)
            .fontWeight(FontWeight.Bold)
        }
        .width('100%')
        .height(64)
        .borderRadius(8)
        .backgroundColor(placeholderColor)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      Text(label)
        .fontSize(11)
        .fontColor(this.theme === value ? this.themePrimary : this.themeTextSecondary)
        .fontWeight(this.theme === value ? FontWeight.Medium : FontWeight.Normal)
    }
    .layoutWeight(1)
    .border({ width: this.theme === value ? 2 : 0, color: this.themePrimary })
    .borderRadius(10)
    .padding(this.theme === value ? 6 : 8)
    .onClick(() => {
      this.theme = value
      this.saveSetting('theme', value)
      ThemeManager.applyTheme(value)
    })
  }

  // ===== APP 图标卡片 =====
  @Builder
  AppIconCard() {
    Column() {
      Text('APP 图标')
        .fontSize(15)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 12 })

      Row({ space: 8 }) {
        this.AppIconOption('default', '默认', $r('app.media.app_icon'))
        this.AppIconOption('alternative', '备选', $r('app.media.backapp_icon'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
    }
    .width('100%')
    .backgroundColor(this.themeCardBg)
    .borderRadius(12)
  }

  @Builder
  AppIconOption(value: string, label: string, iconRes: Resource) {
    Column({ space: 8 }) {
      Image(iconRes)
        .width(56)
        .height(56)
        .borderRadius(12)
        .objectFit(ImageFit.Cover)

      Text(label)
        .fontSize(12)
        .fontColor(this.appIcon === value ? this.themePrimary : this.themeTextSecondary)
        .fontWeight(this.appIcon === value ? FontWeight.Medium : FontWeight.Normal)
    }
    .layoutWeight(1)
    .padding({ top: 8, bottom: 8 })
    .border({ width: this.appIcon === value ? 2 : 0, color: this.themePrimary })
    .borderRadius(10)
    .backgroundColor(this.appIcon === value ? this.themePrimaryLight : this.themePlaceholder)
    .onClick(() => {
      if (this.appIcon !== value) {
        this.appIcon = value
        this.saveSetting('appIcon', value)
        this.switchAppIcon(value)
      }
    })
  }

  private async switchAppIcon(iconType: string): Promise<void> {
    // V2.1.9 bundleManager.setAlternateIcon 为 API26（HarmonyOS 7.0）新增接口，
    // 旧系统设备上该方法不存在，typeof 兜底避免崩溃
    if (typeof bundleManager.setAlternateIcon !== 'function') {
      this.showToastMsg('当前系统版本过低，暂不支持切换应用图标')
      return
    }
    try {
      // 传空字符串取消备选图标，恢复默认；备选项 name 须与 app.json5 alternateIcons.name 一致
      await bundleManager.setAlternateIcon(iconType === 'alternative' ? 'alternative' : '')
      this.showToastMsg(iconType === 'alternative' ? '应用图标已切换' : '已恢复默认图标')
    } catch (e) {
      console.error('[LoushiTab] setAlternateIcon failed:', e)
      this.showToastMsg('切换应用图标失败')
    }
  }

  // ===== 子页面通用导航栏 =====
  @Builder
  SubPageHeader(title: string) {
    Row({ space: 12 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([this.themeTextPrimary])
      }
      .width(36).height(36).justifyContent(FlexAlign.Center)
      .onClick(() => { this.subPage = 'main' })
      Text(title).fontSize(17).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Bold).layoutWeight(1)
    }
    .width('100%').height(56).padding({ left: 8, right: 16 }).alignItems(VerticalAlign.Center)
  }

  // ======================== 主页面 ========================
  @Builder
  SettingGroup(title: string, items: SettingItem[]) {
    Column({ space: 0 }) {
      Text(title)
        .fontSize(13)
        .fontColor(this.themeTextSecondary)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .padding({ left: 4, bottom: 8 })

      Column() {
        ForEach(items, (item: SettingItem, index: number) => {
          this.SettingInnerRow(item.icon, item.label, item.target, item.requireLogin === true, item.locked === true)
          if (index < items.length - 1) {
            Divider()
              .height(1)
              .color(this.themeDivider)
              .width('100%')
              .margin({ left: 56 })
          }
        })
      }
      .width('100%')
      .backgroundColor(this.themeCardBg)
      .borderRadius(12)
    }
    .width('100%')
  }

  @Builder
  SettingInnerRow(icon: Resource, label: string, target: SubPage, requireLogin: boolean = false, locked: boolean = false) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontColor([this.themeTextPrimary])
      Text(label)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.themeTextPrimary)
        .layoutWeight(1)
        .margin({ left: 12 })
      if (locked) {
        SymbolGlyph($r('sys.symbol.lock_fill'))
          .fontSize(14)
          .fontColor([this.themeTextSecondary])
      }
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.themeTextSecondary])
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      if (requireLogin) {
        this.navigateWithLoginCheck(target, locked)
      } else if (locked) {
        this.verifyLock(target)
      } else {
        this.goSubPage(target)
      }
    })
  }

  private verifyLock(target: SubPage): void {
    this.lockTarget = target
    this.lockInput = ''
    this.showLockDialog = true
  }

  @Builder
  MainPage() {
    Scroll() {
      Column({ space: 20 }) {
        // 顶部：账号设置（复用我的页个人信息区，右侧保留电源图标与原弹出菜单）
        this.AccountSettingCard()

        this.SettingGroup('显示与播放', [
          { icon: $r('sys.symbol.paintbrush'), label: '\u4E2A\u6027\u5316', target: 'personalization' },
          { icon: $r('sys.symbol.play_circle'), label: '\u64AD\u653E\u5668', target: 'player' }
        ])

        this.SettingGroup('音源', [
          { icon: $r('sys.symbol.gearshape'), label: '\u97F3\u6E90\u7BA1\u7406', target: 'plugin_manager' },
          { icon: $r('sys.symbol.link'), label: '自建API', target: 'self_hosted_api', requireLogin: true, locked: true },
          { icon: $r('sys.symbol.cloud'), label: 'WebDAV', target: 'webdev_config', requireLogin: true }
        ])

        this.SettingGroup('版块设置', [
          { icon: $r('sys.symbol.heart_fill'), label: '\u4E3B\u9875', target: 'xuanchuang_settings' },
          { icon: $r('sys.symbol.magnifyingglass'), label: '\u641C\u7D22', target: 'qinse_settings' },
          { icon: $r('sys.symbol.trash'), label: '缓存清理', target: 'cache_settings' }
        ])

        // 关于软件 独立分组
        this.SettingGroup('关于软件', [
          { icon: $r('sys.symbol.info_circle_fill'), label: '\u5173\u4E8E\u8F6F\u4EF6', target: 'about' }
        ])

        Column().height(168)
      }
      .width('100%').padding({ top: 28, left: 16, right: 16 })
    }
    .width('100%').layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring).align(Alignment.Top)
  }

  // ======================== 账号设置卡片 ========================
  @Builder
  AccountSettingCard() {
    Row({ space: 16 }) {
      // 左侧：头像 + 用户信息（点击登录）
      Row({ space: 16 }) {
        Stack() {
          // 头像：已登录且有头像用网络图片，否则用默认图标
          if (this.accountIsLoggedIn && this.accountAvatarUrl.length > 0) {
            Image(this.accountAvatarUrl)
              .width(72).height(72).borderRadius(36)
              .objectFit(ImageFit.Cover)
          } else {
            Row() {
              SymbolGlyph($r('sys.symbol.person'))
                .fontSize(48)
                .fontColor([this.themeTextSecondary])
            }
            .width(72)
            .height(72)
            .borderRadius(36)
            .backgroundColor(this.themeCardBg)
            .justifyContent(FlexAlign.Center)
          }

          if (!this.accountIsLoggedIn) {
            Row() {
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(14)
                .fontColor([Color.White])
            }
            .width(20)
            .height(20)
            .borderRadius(10)
            .backgroundColor(this.themePrimary)
            .justifyContent(FlexAlign.Center)
            .position({ x: 52, y: 52 })
          }
        }
        .flexShrink(0)

        Column({ space: 6 }) {
          if (this.accountLoggingIn) {
            Row({ space: 6 }) {
              LoadingProgress().width(16).height(16).color(this.themePrimary)
              Text('登录中...')
                .fontSize(16)
                .fontColor(this.themeTextSecondary)
            }
          } else {
            Row({ space: 8 }) {
              Text(this.accountUserName)
                .fontSize(18)
                .fontColor(this.themeTextPrimary)
                .fontWeight(FontWeight.Bold)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .flexShrink(1)

              if (this.accountIsLoggedIn) {
                Stack() {
                  Text(`LV${this.accountLevelInfo.level}`)
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(LEVEL_TEXT_COLOR)
                }
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor(getLevelColor(this.accountLevelInfo.level))
                .borderRadius(10)
              }
            }
            .width('100%')

            if (this.accountIsLoggedIn) {
              // 等级进度条
              Row({ space: 8 }) {
                Stack({ alignContent: Alignment.Start }) {
                  Row()
                    .width('100%')
                    .height(5)
                    .borderRadius(2.5)
                    .backgroundColor(this.themeDivider)
                  Row()
                    .width(`${this.accountLevelInfo.percent}%`)
                    .height(5)
                    .borderRadius(2.5)
                    .backgroundColor(this.themePrimary)
                    .constraintSize({ minWidth: this.accountLevelInfo.percent > 0 ? 3 : 0 })
                }
                .layoutWeight(1)
                .height(8)
                .constraintSize({ maxWidth: 120 })

                Text(`${this.accountLevelInfo.current}/${this.accountLevelInfo.need}`)
                  .fontSize(11)
                  .fontColor(this.themeTextSecondary)
              }
              .width('100%')

              // 个性签名
              Text(this.accountSignature.length > 0 ? this.accountSignature : '个性签名：编辑后展现更个性的你!')
                .fontSize(13)
                .fontColor(this.themeTextSecondary)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .layoutWeight(1)
      .onClick(() => {
        if (!this.accountIsLoggedIn && !this.accountLoggingIn) {
          this.accountDoLogin()
        }
      })

      // 右侧：电源图标，未登录点击退出软件，登录后弹出菜单选择
      Row() {
        SymbolGlyph($r('sys.symbol.power'))
          .fontSize(18)
          .fontColor([this.themeTextPrimary])
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (!this.accountIsLoggedIn) {
          this.accountExitApp()
        } else {
          this.accountShowMenu = !this.accountShowMenu
        }
      })
      .bindPopup(this.accountShowMenu, {
        builder: this.AccountMenuBuilder,
        placement: Placement.Bottom,
        systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN),
        autoCancel: true,
        onStateChange: (e: PopupStateChangeParam) => {
          if (!e.isVisible) {
            this.accountShowMenu = false
          }
        }
      })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.themeCardBg)
    .borderRadius(16)
    .shadow({ radius: 4, color: '#00000008', offsetY: 2 })
  }

  @Builder
  AccountMenuBuilder() {
    Column({ space: 0 }) {
      Text('退出软件')
        .fontSize(15)
        .fontColor(this.themeTextPrimary)
        .width('100%')
        .height(44)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.accountShowMenu = false
          this.accountExitApp()
        })

      Divider().color(this.themeDivider).strokeWidth(0.5)

      Text('重启软件')
        .fontSize(15)
        .fontColor(this.themeTextPrimary)
        .width('100%')
        .height(44)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.accountShowMenu = false
          this.accountRestartApp()
        })

      Divider().color(this.themeDivider).strokeWidth(0.5)

      Text('退出登录')
        .fontSize(15)
        .fontColor('#FF6B6B')
        .width('100%')
        .height(44)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.accountDoLogout()
        })
    }
    .width(120)
    .borderRadius(10)
    .padding({ top: 4, bottom: 4 })
  }

  // ======================== 个性化 ========================
  @Builder
  PersonalizationPage() {
    Column() {
      // V2.1.9：页头由 HdsNavDestination 系统标题栏提供（返回键自动 pop + 沉浸材质）
      Scroll() {
        Column({ space: 12 }) {
          // 主题卡片（含缩略图）——上架审核 UX 不过关，先隐藏（不删除代码）
          // this.ThemeCard()

          // APP 图标（V2.1.9 设备实测 HarmonyOS 7.0 / API26，setAlternateIcon 已可用，恢复真实换图标）
          this.AppIconCard()

          // V2.1.9 沉浸光感卡片去除
          Column().height(168)
        }
        .width('100%').padding({ top: 12, left: 16, right: 16 })
      }
      .layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring).align(Alignment.Top)
    }
    .width('100%').height('100%')
      .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
      .justifyContent(FlexAlign.Start)
  }

  // ======================== 播放器 ========================
  @Builder
  PlayerSettingsPage() {
    Column() {
      // V2.1.9：页头由 HdsNavDestination 系统标题栏提供（返回键自动 pop + 沉浸材质）
      Scroll() {
        Column({ space: 12 }) {
          // 播放设置卡片
          this.PlayerSettingsCard()

          // Minibar 设置卡片
          this.MiniBarSettingsCard()

          Column().height(168)
        }
        .width('100%').padding({ top: 12, left: 16, right: 16 })
      }
      .layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring).align(Alignment.Top)
    }
    .width('100%').height('100%')
      .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
      .justifyContent(FlexAlign.Start)
  }

  @Builder
  PlayerSettingsCard() {
    Column() {
      Text('播放设置')
        .fontSize(15)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 8 })

      this.PlayerToggleItem('自动记忆', '开启后自动记忆退出软件时播放的曲目和进度',
        this.rememberProgress, (v) => { this.rememberProgress = v; this.saveSetting('rememberProgress', String(v)) })

      Divider().height(1).color(this.themeDivider).width('100%').margin({ left: 16, right: 16 })

      this.PlayerToggleItem('自动播放', '开启后每次进入软件都从上次播放的曲目和进度开始播放',
        this.autoPlay, (v) => { this.autoPlay = v; this.saveSetting('autoPlay', String(v)) })

      Divider().height(1).color(this.themeDivider).width('100%').margin({ left: 16, right: 16 })

      this.PlayerToggleItem('自动详情', '开启后点击搜索/歌单内的歌曲，底部栏开始播放和打开详情页同步进行',
        this.autoJumpDetail, (v) => {
          this.autoJumpDetail = v
          this.saveSetting('autoJumpDetail', String(v))
          AppStorage.setOrCreate('autoJumpDetail', v)
        })

      Divider().height(1).color(this.themeDivider).width('100%').margin({ left: 16, right: 16 })

      this.PlayerToggleItem('封面/歌词自动补全', '开启后，在封面/歌词缺失时将尝试自动补全',
        this.autoEnrichTags, (v) => {
          this.autoEnrichTags = v
          this.saveSetting('autoEnrichTags', String(v))
          AppStorage.setOrCreate('autoEnrichTags', v)
        })

      Divider().height(1).color(this.themeDivider).width('100%').margin({ left: 16, right: 16 })

      this.PlayerToggleItem('自动换源', '关闭后歌曲播放失败自动跳过不再换源',
        this.autoSourceSwitch, (v) => {
          this.autoSourceSwitch = v
          this.saveSetting('autoSourceSwitch', String(v))
          AppStorage.setOrCreate('autoSourceSwitch', v)
        })
    }
    .width('100%')
    .backgroundColor(this.themeCardBg)
    .borderRadius(12)
  }

  @Builder
  PlayerToggleItem(title: string, desc: string, checked: boolean, onChange: (v: boolean) => void) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(15).fontColor(this.themeTextPrimary).width('100%')
        Text(desc).fontSize(12).fontColor(this.themeTextSecondary).width('100%')
      }
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: checked })
        .selectedColor(this.themePrimary)
        .onChange((v: boolean) => { onChange(v) })
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  // ===== Minibar 设置 =====
  @Builder
  MiniBarSettingsCard() {
    Column() {
      Text('Minibar 设置')
        .fontSize(15)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 8 })

      this.PlayerToggleItem('歌曲来源展示', '关闭后迷你栏不再显示歌曲来源徽章',
        this.miniBarShowSource, (v) => {
          this.miniBarShowSource = v
          this.saveSetting('miniBarShowSource', String(v))
          AppStorage.setOrCreate('miniBarShowSource', v)
        })
    }
    .width('100%')
    .backgroundColor(this.themeCardBg)
    .borderRadius(12)
  }

  // ======================== WebDAV ========================
  @Builder
  WebdevConfigPage() {
    Column() {
      // V2.1.9：页头由 HdsNavDestination 系统标题栏提供（返回键自动 pop + 沉浸材质）
      Scroll() {
        Column({ space: 12 }) {
          // 说明卡片
          Column({ space: 8 }) {
            Text('配置 WebDAV 网盘曲库')
              .fontSize(16).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium).width('100%')
            Text('支持坚果云等 WebDAV 服务，将音乐上传至网盘后即可在线播放，目前仅支持坚果云的单一路径')
              .fontSize(13).fontColor(this.themeTextSecondary).width('100%')
          }
          .width('100%').padding(16)
          .backgroundColor(this.themeCardBg).borderRadius(12)

          // 服务器地址
          Column({ space: 8 }) {
            Text('服务器地址').fontSize(14).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium).width('100%')
            TextInput({ placeholder: 'https://dav.jianguoyun.com/dav/', text: this.webdavUrl })
              .width('100%').height(44).fontSize(14)
              .backgroundColor(this.themePlaceholder).borderRadius(10)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => { this.webdavUrl = value })
          }
          .width('100%').padding(16)
          .backgroundColor(this.themeCardBg).borderRadius(12)

          // 用户名
          Column({ space: 8 }) {
            Text('用户名').fontSize(14).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium).width('100%')
            TextInput({ placeholder: '输入 WebDAV 用户名', text: this.webdavUser })
              .width('100%').height(44).fontSize(14)
              .backgroundColor(this.themePlaceholder).borderRadius(10)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => { this.webdavUser = value })
          }
          .width('100%').padding(16)
          .backgroundColor(this.themeCardBg).borderRadius(12)

          // 密码
          Column({ space: 8 }) {
            Text('密码').fontSize(14).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium).width('100%')
            Row({ space: 8 }) {
              TextInput({ placeholder: '输入 WebDAV 密码（应用密码）', text: this.webdavPass })
                .layoutWeight(1).height(44).fontSize(14)
                .backgroundColor(this.themePlaceholder).borderRadius(10)
                .padding({ left: 12, right: 12 })
                .type(this.webdavShowPass ? InputType.Normal : InputType.Password)
                .onChange((value: string) => { this.webdavPass = value })
              Row() {
                SymbolGlyph(this.webdavShowPass ? $r('sys.symbol.eye') : $r('sys.symbol.eye_slash'))
                  .fontSize(18)
                  .fontColor([this.themeTextSecondary])
              }
              .width(36).height(36)
              .justifyContent(FlexAlign.Center)
              .onClick(() => { this.webdavShowPass = !this.webdavShowPass })
            }
            .width('100%')
          }
          .width('100%').padding(16)
          .backgroundColor(this.themeCardBg).borderRadius(12)

          // 音乐路径
          Column({ space: 8 }) {
            Text('音乐路径').fontSize(14).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium).width('100%')
            Text('指定网盘中存放音乐的文件夹路径，如 /music或/').fontSize(12).fontColor(this.themeTextSecondary).width('100%')
            TextInput({ placeholder: '/music/', text: this.webdavPath })
              .width('100%').height(44).fontSize(14)
              .backgroundColor(this.themePlaceholder).borderRadius(10)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => { this.webdavPath = value })
          }
          .width('100%').padding(16)
          .backgroundColor(this.themeCardBg).borderRadius(12)

          // 文件名解析方式
          Column({ space: 8 }) {
            Text('文件名解析方式').fontSize(14).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium).width('100%')
            Text('根据文件名格式解析歌手和歌曲名').fontSize(12).fontColor(this.themeTextSecondary).width('100%')
            Row({ space: 8 }) {
              this.ParseModeButton('song-artist', '歌曲名 - 歌手')
              this.ParseModeButton('artist-song', '歌手 - 歌曲名')
              this.ParseModeButton('auto', '自动识别')
            }
            .width('100%')
          }
          .width('100%').padding(16)
          .backgroundColor(this.themeCardBg).borderRadius(12)

          // 测试连接 + 保存按钮
          Row({ space: 12 }) {
            Button('测试连接')
              .layoutWeight(1).height(48).fontSize(15)
              .fontColor(this.themePrimary)
              .backgroundColor(this.themeCardBg)
              .border({ width: 1, color: this.themePrimary })
              .borderRadius(12)
              .enabled(!this.webdavTesting)
              .onClick(() => { this.testWebdavConnection() })

            Button('保存配置')
              .layoutWeight(1).height(48).fontSize(15)
              .fontColor(Color.White)
              .backgroundColor(this.themePrimary)
              .borderRadius(12)
              .onClick(() => {
                this.saveSetting('webdav_url', this.webdavUrl)
                this.saveSetting('webdav_user', this.webdavUser)
                this.saveSetting('webdav_pass', this.webdavPass)
                this.saveSetting('webdav_path', this.webdavPath)
                this.saveSetting('webdav_parse_mode', this.webdavParseMode)
                this.showToastMsg('WebDAV 配置已保存')
              })
          }
          .width('100%').margin({ top: 8 })

          // ===== 数据同步区域 =====
          Column({ space: 12 }) {
            Text('数据同步')
              .fontSize(16).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium).width('100%')
            Text('将歌单、收藏、搜索记录、音源配置、主题设置等数据备份到 WebDAV 网盘，换设备可恢复')
              .fontSize(13).fontColor(this.themeTextSecondary).width('100%')

            // 上次同步时间
            if (this.lastSyncTime > 0) {
              Text(`上次同步: ${this.formatTime(this.lastSyncTime)}`)
                .fontSize(12).fontColor(this.themeTextSecondary).width('100%')
            }

            // 同步状态提示
            if (this.syncMessage.length > 0) {
              Text(this.syncMessage)
                .fontSize(12)
                .fontColor(this.syncMessage.includes('成功') ? '#4CAF50' : '#FF6B6B')
                .width('100%')
            }

            // 上传 / 恢复 按钮
            Row({ space: 12 }) {
              Button('上传备份')
                .layoutWeight(1).height(44).fontSize(14)
                .fontColor(this.themePrimary)
                .backgroundColor(this.themeCardBg)
                .border({ width: 1, color: this.themePrimary })
                .borderRadius(12)
                .enabled(!this.syncing)
                .onClick(() => { this.uploadBackup() })

              Button('恢复备份')
                .layoutWeight(1).height(44).fontSize(14)
                .fontColor(Color.White)
                .backgroundColor(this.themePrimary)
                .borderRadius(12)
                .enabled(!this.syncing)
                .onClick(() => { this.restoreBackup() })
            }
            .width('100%')

            if (this.syncing) {
              Row({ space: 8 }) {
                LoadingProgress().width(16).height(16).color(this.themePrimary)
                Text('正在同步...')
                  .fontSize(13).fontColor(this.themeTextSecondary)
              }
            }
          }
          .width('100%').padding(16)
          .backgroundColor(this.themeCardBg).borderRadius(12)
          .margin({ top: 12 })

          Column().height(168)
        }
        .width('100%').padding({ top: 12, left: 16, right: 16 })
      }
      .layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring).align(Alignment.Top)
    }
    .width('100%').height('100%')
      .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
      .justifyContent(FlexAlign.Start)
  }

  private async uploadBackup() {
    this.syncing = true
    this.syncMessage = ''
    try {
      const result = await WebDavSync.uploadBackup()
      this.syncMessage = result.message
      if (result.success && result.syncTime) {
        this.lastSyncTime = result.syncTime
      }
    } finally {
      this.syncing = false
    }
  }

  private async restoreBackup() {
    this.syncing = true
    this.syncMessage = ''
    try {
      const result = await WebDavSync.downloadBackup()
      this.syncMessage = result.message
      if (result.success && result.syncTime) {
        this.lastSyncTime = result.syncTime
        // 重新加载设置以应用导入的数据
        await this.loadSettings()
      }
    } finally {
      this.syncing = false
    }
  }

  private formatTime(timestamp: number): string {
    const d = new Date(timestamp)
    const month = String(d.getMonth() + 1).padStart(2, '0')
    const day = String(d.getDate()).padStart(2, '0')
    const hour = String(d.getHours()).padStart(2, '0')
    const minute = String(d.getMinutes()).padStart(2, '0')
    return `${month}-${day} ${hour}:${minute}`
  }

  private async testWebdavConnection() {
    if (!this.webdavUrl) {
      this.showToastMsg('请先填写服务器地址')
      return
    }
    this.webdavTesting = true
    try {
      const auth = this.base64Encode(`${this.webdavUser}:${this.webdavPass}`)
      let testUrl = this.webdavUrl.endsWith('/') ? this.webdavUrl : this.webdavUrl + '/'
      if (this.webdavPath.length > 0) {
        const path = this.webdavPath.startsWith('/') ? this.webdavPath.substring(1) : this.webdavPath
        const cleanPath = path.endsWith('/') ? path : path + '/'
        testUrl += encodeURI(cleanPath)
      }
      // WebDAV 规范（RFC 4918）要求 PROPFIND 携带 XML body，否则部分服务器（如坚果云）会返回 503
      const propfindBody = '<?xml version="1.0" encoding="utf-8"?>' +
        '<D:propfind xmlns:D="DAV:"><D:prop><D:resourcetype/></D:prop></D:propfind>'
      const httpRequest = http.createHttp()
      const response = await httpRequest.request(testUrl, {
        method: 'PROPFIND' as http.RequestMethod,
        header: {
          'Authorization': `Basic ${auth}`,
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
          'User-Agent': 'Sumy/1.0',
        },
        extraData: propfindBody,
        readTimeout: 10000,
        connectTimeout: 10000,
      } as http.HttpRequestOptions)
      httpRequest.destroy()

      const code = response.responseCode
      if (code === 207 || code === 200) {
        this.showToastMsg('连接成功！WebDAV 可正常访问')
      } else if (code === 401 || code === 403) {
        this.showToastMsg('认证失败，请使用坚果云「应用密码」而非登录密码')
      } else if (code === 503) {
        this.showToastMsg('服务暂不可用（503），可能被限流，请稍后重试')
      } else if (code === 404) {
        this.showToastMsg('路径不存在（404），请检查服务器地址和路径')
      } else {
        this.showToastMsg(`连接失败，响应码: ${code}`)
      }
    } catch (e) {
      console.error('[Loushi] testWebdavConnection:', e)
      this.showToastMsg('连接失败，请检查地址和账号密码')
    }
    this.webdavTesting = false
  }

  private base64Encode(str: string): string {
    const helper = new util.Base64Helper()
    const uint8Array = new Uint8Array(str.split('').map(c => c.charCodeAt(0)))
    return helper.encodeToStringSync(uint8Array)
  }

  @Builder
  ParseModeButton(value: string, label: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.webdavParseMode === value ? Color.White : this.themeTextPrimary)
    }
    .layoutWeight(1).height(32).justifyContent(FlexAlign.Center).borderRadius(8)
    .backgroundColor(this.webdavParseMode === value ? this.themePrimary : this.themePlaceholder)
    .onClick(() => { this.webdavParseMode = value })
  }

  // ======================== 关于软件 ========================
  @Builder
  AboutPage() {
    Stack() {
      Column() {
        // V2.1.9：页头由 HdsNavDestination 系统标题栏提供（返回键自动 pop + 沉浸材质）
        Scroll() {
          Column({ space: 12 }) {
            // Logo + 版本
            Column({ space: 8 }) {
              Image($r('app.media.logo'))
                .width(72)
                .height(72)
                .borderRadius(18)
                .objectFit(ImageFit.Cover)
              Text('Sumy Music')
                .fontSize(22)
                .fontColor(this.themeTextPrimary)
                .fontWeight(FontWeight.Bold)
              Text('Version 2.0.9.6')
                .fontSize(13)
                .fontColor(this.themeTextSecondary)
            }
            .width('100%')
            .padding({ top: 36, bottom: 16 })
            .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)

            // 2x2 方形卡片（前4项：说明/权限/协议/日志）
            Column() {
              GridRow({ columns: 2, gutter: { x: 8, y: 8 } }) {
                ForEach(aboutItems.slice(0, 4), (item: AboutItem) => {
                  GridCol() {
                    Row() {
                      Text(item.label)
                        .fontSize(16)
                        .fontColor(this.themeTextPrimary)
                        .fontWeight(FontWeight.Medium)
                        .layoutWeight(1)
                      SymbolGlyph($r('sys.symbol.chevron_right'))
                        .fontSize(14)
                        .fontColor([this.themeTextSecondary])
                    }
                    .width('100%')
                    .height(52)
                    .padding({ left: 16, right: 16 })
                    .backgroundColor(this.themeCardBg)
                    .borderRadius(12)
                    .onClick(() => {
                      if (item.type === 'text') {
                        this.aboutDialogTitle = item.label
                        this.aboutDialogContent = item.content || ''
                        this.showAboutDialog = true
                      } else if (item.type === 'link') {
                        this.openUrl(item.url || '')
                      }
                    })
                  }
                }, (item: AboutItem) => item.label)
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16 })

            // 其余项（链接/反馈/更新）
            Column({ space: 8 }) {
              ForEach(aboutItems.slice(4), (item: AboutItem) => {
                Row() {
                  Text(item.label)
                    .fontSize(16)
                    .fontColor(this.themeTextPrimary)
                    .flexShrink(0)
                  Blank()
                  Text('\u8BF7\u6CE8\u610F\uFF1A\u6B64\u4E3A\u5916\u94FE\u6253\u5F00')
                    .fontSize(11)
                    .fontColor(this.themeTextSecondary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                    .textAlign(TextAlign.Center)
                  Blank()
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([this.themeTextSecondary])
                    .flexShrink(0)
                }
                .width('100%')
                .height(52)
                .padding({ left: 16, right: 16 })
                .backgroundColor(this.themeCardBg)
                .borderRadius(12)
                .onClick(() => {
                  if (item.type === 'link') {
                    this.openUrl(item.url || '')
                  } else if (item.type === 'links') {
                    this.showLinks(item.urls || [])
                  } else if (item.type === 'feedback') {
                    this.showFeedback()
                  }
                })
              }, (item: AboutItem) => item.label)
            }
            .width('100%')
            .padding({ left: 16, right: 16 })

            Column().height(168)
          }
          .width('100%').padding({ top: 12, left: 16, right: 16 })
        }
        .layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring).align(Alignment.Top)
      }
      .width('100%').height('100%')
      .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
      .justifyContent(FlexAlign.Start)

      // 详情弹窗
      if (this.showAboutDialog) {
        Column() {
          Column() {
            Text(this.aboutDialogTitle)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.themeTextPrimary)
              .margin({ bottom: 16 })

            Text(this.aboutDialogContent)
              .fontSize(14)
              .fontColor(this.themeTextPrimary)
              .width('100%')

            Button('\u5173\u95ED')
              .width('100%')
              .margin({ top: 16 })
              .backgroundColor(this.themePrimary)
              .fontColor(Color.White)
              .onClick(() => {
                this.showAboutDialog = false
              })
          }
          .width('80%')
          .padding(24)
          .backgroundColor(this.themeCardBg)
          .borderRadius(16)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.4)')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.showAboutDialog = false
        })
      }
    }
    .width('100%').height('100%')
  }

  // ======================== 自建 API ========================
  @Builder
  SelfHostedApiPage() {
    Column() {
      // V2.1.9：页头由 HdsNavDestination 系统标题栏提供（返回键自动 pop + 沉浸材质）
      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 8 }) {
            Text('自建 API 模式')
              .fontSize(16).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium).width('100%')
            Text('开启后所有搜索/播放/歌词请求走自建后端 API；关闭则使用 JSON 源配置')
              .fontSize(13).fontColor(this.themeTextSecondary).width('100%')
          }
          .width('100%').padding(16)
          .backgroundColor(this.themeCardBg).borderRadius(12)

          Column({ space: 12 }) {
            this.ToggleRow('启用自建 API', '开启后所有搜索/播放/歌词请求走自建后端 API',
              this.useSelfHostedApi, (v) => {
                this.useSelfHostedApi = v
                if (v) {
                  // 互斥：启用自建 API 时自动关闭所有插件音源，避免搜索源混乱
                  this.disableAllPluginSources()
                }
              })

            if (this.useSelfHostedApi) {
              Divider().height(1).color(this.themeDivider).width('100%')

              Column({ space: 8 }) {
                Text('API 地址').fontSize(14).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium).width('100%')
                TextInput({ placeholder: '请输入 API 地址', text: this.selfHostedApiUrl })
                  .width('100%').height(44).fontSize(14)
                  .backgroundColor(this.themePlaceholder).borderRadius(10)
                  .padding({ left: 12, right: 12 })
                  .onChange((value: string) => {
                    this.selfHostedApiUrl = value
                  })
              }
              .width('100%')

              Row({ space: 12 }) {
                Button('保存')
                  .fontSize(14)
                  .fontColor(Color.White)
                  .backgroundColor(this.themePrimary)
                  .layoutWeight(1)
                  .height(40)
                  .onClick(() => {
                    this.saveSelfHostedApiSettings()
                  })

                Button(this.selfHostedApiTesting ? '测试中...' : '测试连接')
                  .fontSize(14)
                  .fontColor(this.themeTextPrimary)
                  .backgroundColor(this.themePlaceholder)
                  .layoutWeight(1)
                  .height(40)
                  .enabled(!this.selfHostedApiTesting)
                  .onClick(() => {
                    this.testSelfHostedApiConnection()
                  })
              }
              .width('100%')
            }
          }
          .width('100%').padding(16)
          .backgroundColor(this.themeCardBg).borderRadius(12)

          Column({ space: 8 }) {
            Text('支持源').fontSize(14).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium).width('100%')
            Text('wy(小云)/qe(小鹅)/xg(小狗)/kw(小我)/mg(小咕)')
              .fontSize(13).fontColor(this.themeTextSecondary).width('100%')
          }
          .width('100%').padding(16)
          .backgroundColor(this.themeCardBg).borderRadius(12)

          Column().height(168)
        }
        .width('100%').padding({ top: 12, left: 16, right: 16 })
      }
      .layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring).align(Alignment.Top)
    }
    .width('100%').height('100%')
      .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
      .justifyContent(FlexAlign.Start)
  }

  // ======================== 版块设置 ========================
  @Builder
  SectionSettingsPage() {
    Column() {
      this.SubPageHeader('\u677F\u5757\u8BBE\u7F6E')
      Scroll() {
        Column({ space: 12 }) {
          this.CardRow($r('sys.symbol.magnifyingglass'), '\u641C\u7D22', 'qinse_settings')
          Column().height(168)
        }
        .width('100%').padding({ top: 12, left: 16, right: 16 })
      }
      .layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring).align(Alignment.Top)
    }
    .width('100%').height('100%')
      .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  CacheSettingsPage() {
    Column() {
      // V2.1.9：页头由 HdsNavDestination 系统标题栏提供（返回键自动 pop + 沉浸材质）
      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 8 }) {
            Text('缓存清理')
              .fontSize(16).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium).width('100%')
            Text('点击清理应用缓存')
              .fontSize(13).fontColor(this.themeTextSecondary).width('100%')
            Text(`当前缓存 ${CacheManager.formatBytes(this.cacheInfo.bytes)} · ${this.cacheInfo.files} 个文件`)
              .fontSize(13).fontColor(this.themeTextSecondary).width('100%')
            Button(this.clearingCache ? '清理中...' : '清理缓存')
              .width('100%')
              .height(44)
              .fontSize(15)
              .backgroundColor(this.themePrimary)
              .fontColor(Color.White)
              .enabled(!this.clearingCache)
              .onClick(() => { this.clearAppCache() })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.themeCardBg)
          .borderRadius(12)

          Column().height(168)
        }
        .width('100%').padding({ top: 12, left: 16, right: 16 })
      }
      .layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring).align(Alignment.Top)
    }
    .width('100%').height('100%')
    .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
    .justifyContent(FlexAlign.Start)
  }

  // V2.1.0 精简版块设置：单行开关条目（可选小字 subTitle，一行一个功能）
  @Builder
  SettingToggleRow(title: string, subTitle: string, isOn: boolean, onChanged: (v: boolean) => void) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontColor(this.themeTextPrimary)
          .width('100%')
        if (subTitle.length > 0) {
          Text(subTitle)
            .fontSize(12)
            .fontColor(this.themeTextSecondary)
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(this.themePrimary)
        .onChange((v: boolean) => {
          onChanged(v)
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  // ======================== 主页设置 ========================
  @Builder
  XuanchuangSettingsPage() {
    Column() {
      // V2.1.9：页头由 HdsNavDestination 系统标题栏提供（返回键自动 pop + 沉浸材质）
      Scroll() {
        Column({ space: 12 }) {
          // V2.1.0 精简：主页统计单行开关
          Column() {
            this.SettingToggleRow('主页统计', '', this.showHomeStats, (v: boolean) => {
              this.showHomeStats = v
              this.saveSetting('showHomeStats', String(v))
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.themeCardBg)
          .borderRadius(12)

          // 歌单内设置：定位播放歌曲（默认关闭）
          Column() {
            Text('歌单内设置')
              .fontSize(13)
              .fontColor(this.themeTextSecondary)
              .width('100%')
              .padding({ top: 12 })
            this.SettingToggleRow('定位播放歌曲', '开启后进入歌单自动定位并跳转播放中歌曲', this.playlistLocatePlaying, (v: boolean) => {
              this.playlistLocatePlaying = v
              this.saveSetting('playlistLocatePlaying', String(v))
              AppStorage.setOrCreate('playlistLocatePlaying', v)
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.themeCardBg)
          .borderRadius(12)

          // 播放列表设置：定位播放歌曲（默认关闭）
          Column() {
            Text('播放列表设置')
              .fontSize(13)
              .fontColor(this.themeTextSecondary)
              .width('100%')
              .padding({ top: 12 })
            this.SettingToggleRow('定位播放歌曲', '开启后进入歌单自动定位并跳转播放中歌曲', this.queueLocatePlaying, (v: boolean) => {
              this.queueLocatePlaying = v
              this.saveSetting('queueLocatePlaying', String(v))
              AppStorage.setOrCreate('queueLocatePlaying', v)
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.themeCardBg)
          .borderRadius(12)

          Column().height(168)
        }
        .width('100%').padding({ top: 12, left: 16, right: 16 })
      }
      .layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring).align(Alignment.Top)
    }
    .width('100%').height('100%')
      .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
      .justifyContent(FlexAlign.Start)
  }

  // ======================== 搜索设置 ========================
  @Builder
  QinseSettingsPage() {
    Column() {
      // V2.1.9：页头由 HdsNavDestination 系统标题栏提供（返回键自动 pop + 沉浸材质）
      Scroll() {
        Column({ space: 12 }) {
          // V2.1.0 精简：一区块一行功能
          Column() {
            this.SettingToggleRow('搜索记忆', '', this.searchMemory, (v: boolean) => {
              this.searchMemory = v
              this.saveSetting('searchMemory', String(v))
            })
            Divider().width('100%').color(this.themeDivider)
            this.SettingToggleRow('搜索常驻', '', this.searchPersist, (v: boolean) => {
              this.searchPersist = v
              this.saveSetting('searchPersist', String(v))
            })
            Divider().width('100%').color(this.themeDivider)
            this.SettingToggleRow('搜索联想词', '', this.searchSuggest, (v: boolean) => {
              this.searchSuggest = v
              this.saveSetting('searchSuggest', String(v))
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.themeCardBg)
          .borderRadius(12)

          // 筛选源规定：自动定位跳转（默认开启）
          Column() {
            Text('筛选源规定')
              .fontSize(13)
              .fontColor(this.themeTextSecondary)
              .width('100%')
              .padding({ top: 12 })
            this.SettingToggleRow('自动定位跳转', '自动记忆、定位、跳转上次的音源位置', this.searchSourceLocate, (v: boolean) => {
              this.searchSourceLocate = v
              this.saveSetting('searchSourceLocate', String(v))
              AppStorage.setOrCreate('searchSourceLocate', v)
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.themeCardBg)
          .borderRadius(12)

          Column().height(168)
        }
        .width('100%').padding({ top: 12, left: 16, right: 16 })
      }
      .layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring).align(Alignment.Top)
    }
    .width('100%').height('100%')
      .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
      .justifyContent(FlexAlign.Start)
  }
}
