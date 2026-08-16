// SHMY 陋室 Tab - 设置
// LoushiTab.ets - V1.0.3 分区卡片式布局
import { DEFAULT_SETTINGS } from '../model/MusicModel'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { PluginManagerPage } from '../components/PluginManagerPage'
import { promptAction } from '@kit.ArkUI'
import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { common, Want, bundleManager } from '@kit.AbilityKit'
import { ThemeManager } from '../utils/ThemeManager'
import { WebDavSync } from '../utils/WebDavSync'
import { MusicApi } from '../utils/MusicApi'
import { SelfHostedApi } from '../utils/SelfHostedApi'
import { AccountManager } from '../utils/AccountManager'
import { SourceManager } from '../utils/SourceManager'

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
      '2. Copyright (c) 2025 Sumy Music\n' +
      '3. Permission is hereby granted, free of charge, to any person obtaining a copy ' +
      'of this software and associated documentation files...',
  },
  {
    label: '版本日志',
    type: 'text',
    content: 'v2.0.5.7\n' +
      '1. 补充未适配组件的深色模式\n' +
      '2. 自建API与导入源隔离\n' +
      '3. 修复控制中心对歌曲的控制\n' +
      '4. 修复音源相关问题\n' +
      '5. 完整更新日志(----------https://github.com/qitinyu/Sumy-Music/wiki/)',
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

interface SettingItem {
  icon: Resource
  label: string
  target: SubPage
  requireLogin?: boolean
  locked?: boolean
}

@Component
export struct LoushiTab {
  @StorageLink('loushi_subPage') subPage: SubPage = 'main'
  @State theme: string = DEFAULT_SETTINGS.theme
  @State autoPlay: boolean = DEFAULT_SETTINGS.autoPlay
  @State autoJumpDetail: boolean = DEFAULT_SETTINGS.autoJumpDetail
  @State rememberProgress: boolean = DEFAULT_SETTINGS.rememberProgress
  @State searchMemory: boolean = true // 默认开启
  @State searchPersist: boolean = false // 搜索常驻，默认关闭
  @State searchFloatingBall: boolean = true // 搜索页悬浮球，默认开启
  @State searchFloatingBallLeft: boolean = false // 悬浮球靠左，默认关闭（默认右侧）
  @State showHomeStats: boolean = true // 默认开启
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

  private db: DatabaseHelper = DatabaseHelper.getInstance()

  async aboutToAppear() {
    await this.loadSettings()
  }

  private async loadSettings() {
    this.theme = (await this.db.getSetting('theme')) || DEFAULT_SETTINGS.theme
    this.autoPlay = (await this.db.getSetting('autoPlay')) === 'true'
    this.autoJumpDetail = (await this.db.getSetting('autoJumpDetail')) === 'true'
    this.rememberProgress = (await this.db.getSetting('rememberProgress')) !== 'false' // 默认开启
    const searchMem = await this.db.getSetting('searchMemory')
    this.searchMemory = searchMem !== 'false' // 默认开启
    const searchPersist = await this.db.getSetting('searchPersist')
    this.searchPersist = searchPersist === 'true' // 搜索常驻，默认关闭
    const ball = await this.db.getSetting('searchFloatingBall')
    this.searchFloatingBall = ball !== 'false' // 悬浮球默认开启
    const ballLeft = await this.db.getSetting('searchFloatingBallLeft')
    this.searchFloatingBallLeft = ballLeft === 'true' // 悬浮球左侧默认关闭
    const homeStats = await this.db.getSetting('showHomeStats')
    this.showHomeStats = homeStats !== 'false' // 默认开启

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
    promptAction.showToast({ message: msg, duration: 2000 })
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
      const ctx = getContext(this) as common.UIAbilityContext
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
    promptAction.showActionMenu({
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
    promptAction.showActionMenu({
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
      if (this.subPage === 'main') {
        this.MainPage()
      } else if (this.subPage === 'personalization') {
        this.PersonalizationPage()
      } else if (this.subPage === 'player') {
        this.PlayerSettingsPage()
      } else if (this.subPage === 'webdev_config') {
        this.WebdevConfigPage()
      } else if (this.subPage === 'self_hosted_api') {
        this.SelfHostedApiPage()
      } else if (this.subPage === 'plugin_manager') {
        PluginManagerPage({ onBack: () => { this.subPage = 'main' } })
      } else if (this.subPage === 'about') {
        this.AboutPage()
      } else if (this.subPage === 'xuanchuang_settings') {
        this.XuanchuangSettingsPage()
      } else if (this.subPage === 'qinse_settings') {
        this.QinseSettingsPage()
      }
    }
    .width('100%').height('100%')
      .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
      .justifyContent(FlexAlign.Start)
      .bindSheet($$this.showLockDialog, this.LockPasswordSheet(), {
        height: 260,
        showClose: true,
        dragBar: false,
        backgroundColor: this.themeCardBg
      })
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
              this.subPage = target
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
        this.subPage = target
      }
    })
  }

  private async navigateWithLoginCheck(target: SubPage, locked: boolean = false): Promise<void> {
    const loggedIn = await AccountManager.isLoggedIn()
    if (loggedIn) {
      if (locked) {
        this.verifyLock(target)
      } else {
        this.subPage = target
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
    // 当前编译 SDK 的 bundleManager 不支持 setAlternateIcon 接口，保留图标选择 UI 但提示用户
    this.showToastMsg('当前系统版本不支持切换应用图标')
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
        this.subPage = target
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
          { icon: $r('sys.symbol.magnifyingglass'), label: '\u641C\u7D22', target: 'qinse_settings' }
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

  // ======================== 个性化 ========================
  @Builder
  PersonalizationPage() {
    Column() {
      this.SubPageHeader('\u4E2A\u6027\u5316')
      Scroll() {
        Column({ space: 12 }) {
          // 主题卡片（含缩略图）
          this.ThemeCard()

          // APP 图标
          this.AppIconCard()

          // 沉浸光感提示
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.sun_max'))
              .fontSize(18)
              .fontColor([this.themePrimary])
            Column({ space: 4 }) {
              Text('沉浸光感')
                .fontSize(15)
                .fontColor(this.themeTextPrimary)
                .fontWeight(FontWeight.Medium)
              Text('已开启，强度可在系统设置中调节')
                .fontSize(12)
                .fontColor(this.themeTextSecondary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([this.themeTextSecondary])
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.themeCardBg)
          .borderRadius(12)
          .onClick(() => { this.openImmersiveLightSettings() })

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

  // 跳转到系统显示设置（沉浸光感强度在显示设置内）
  private openImmersiveLightSettings(): void {
    try {
      const context = getContext(this) as common.UIAbilityContext
      context.startAbility({
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'display_setting_entry',
      }).then(() => {
        console.info('[LoushiTab] opened display settings')
      }).catch((e: Error) => {
        console.error('[LoushiTab] open display settings failed:', e)
        // 兜底：跳转到系统设置主页
        context.startAbility({
          bundleName: 'com.huawei.hmos.settings',
          abilityName: 'com.huawei.hmos.settings.MainAbility',
        }).catch((e2: Error) => {
          console.error('[LoushiTab] open settings home failed:', e2)
          promptAction.showToast({ message: '无法打开系统设置，请手动前往设置-桌面和个性化' })
        })
      })
    } catch (e) {
      console.error('[LoushiTab] openImmersiveLightSettings failed:', e)
      promptAction.showToast({ message: '无法打开系统设置' })
    }
  }

  // ======================== 播放器 ========================
  @Builder
  PlayerSettingsPage() {
    Column() {
      this.SubPageHeader('\u64AD\u653E\u5668')
      Scroll() {
        Column({ space: 12 }) {
          // 播放设置卡片
          this.PlayerSettingsCard()

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

  // ======================== WebDAV ========================
  @Builder
  WebdevConfigPage() {
    Column() {
      this.SubPageHeader('WebDAV')
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
        this.SubPageHeader('\u5173\u4E8E Sumy Music')
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
              Text('Version 2.0.5.8')
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
      this.SubPageHeader('自建 API')
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

  // ======================== 主页设置 ========================
  @Builder
  XuanchuangSettingsPage() {
    Column() {
      this.SubPageHeader('\u4E3B\u9875\u8BBE\u7F6E')
      Scroll() {
        Column({ space: 12 }) {
          // 统计卡片开关
          Column({ space: 8 }) {
            Text('\u4E3B\u9875\u7EDF\u8BA1')
              .fontSize(16).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium).width('100%')
            Text('\u5728\u4E3B\u9875\u663E\u793A\u6B4C\u5355\u6570\u3001\u542C\u6B4C\u65F6\u957F\u3001\u542C\u6B4C\u66F2\u76EE\u7B49\u7EDF\u8BA1\u4FE1\u606F')
              .fontSize(13).fontColor(this.themeTextSecondary).width('100%')
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text('\u663E\u793A\u7EDF\u8BA1\u5361\u7247')
                  .fontSize(15).fontColor(this.themeTextPrimary).width('100%')
                Text('\u5173\u95ED\u540E\u4E3B\u9875\u5C06\u9690\u85CF\u9876\u90E8\u7EDF\u8BA1\u5361\u7247')
                  .fontSize(12).fontColor(this.themeTextSecondary).width('100%')
              }
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.showHomeStats })
                .selectedColor(this.themePrimary)
                .onChange((v: boolean) => {
                  this.showHomeStats = v
                  this.saveSetting('showHomeStats', String(v))
                })
            }
            .width('100%').padding({ top: 8 })
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

  // ======================== 搜索设置 ========================
  @Builder
  QinseSettingsPage() {
    Column() {
      this.SubPageHeader('\u641C\u7D22\u8BBE\u7F6E')
      Scroll() {
        Column({ space: 12 }) {
          // 搜索记忆开关
          Column({ space: 8 }) {
            Text('\u641C\u7D22\u8BB0\u5FC6')
              .fontSize(16).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium).width('100%')
            Text('\u8BB0\u4F4F\u641C\u7D22\u5173\u952E\u8BCD\u548C\u7ED3\u679C\uFF0C\u5207\u6362\u9875\u9762\u540E\u81EA\u52A8\u6062\u590D')
              .fontSize(13).fontColor(this.themeTextSecondary).width('100%')
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text('\u542F\u7528\u641C\u7D22\u8BB0\u5FC6')
                  .fontSize(15).fontColor(this.themeTextPrimary).width('100%')
                Text('\u5173\u95ED\u540E\u5207\u6362\u9875\u9762\u4E0D\u518D\u4FDD\u7559\u641C\u7D22\u7ED3\u679C')
                  .fontSize(12).fontColor(this.themeTextSecondary).width('100%')
              }
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.searchMemory })
                .selectedColor(this.themePrimary)
                .onChange((v: boolean) => {
                  this.searchMemory = v
                  this.saveSetting('searchMemory', String(v))
                })
            }
            .width('100%').padding({ top: 8 })
          }
          .width('100%').padding(16)
          .backgroundColor(this.themeCardBg).borderRadius(12)

          // 搜索常驻开关
          Column({ space: 8 }) {
            Text('\u641C\u7D22\u5E38\u9A7B')
              .fontSize(16).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium).width('100%')
            Text('\u5E38\u9A7B\u4E0A\u6B21\u7684\u641C\u7D22\u540D\u548C\u641C\u7D22\u7ED3\u679C\uFF0C\u9700\u624B\u52A8\u6E05\u7A7A')
              .fontSize(13).fontColor(this.themeTextSecondary).width('100%')
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text('\u542F\u7528\u641C\u7D22\u5E38\u9A7B')
                  .fontSize(15).fontColor(this.themeTextPrimary).width('100%')
                Text('\u5173\u95ED\u540E\u4E0D\u5E38\u9A7B\u641C\u7D22\u540D\u548C\u7ED3\u679C')
                  .fontSize(12).fontColor(this.themeTextSecondary).width('100%')
              }
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.searchPersist })
                .selectedColor(this.themePrimary)
                .onChange((v: boolean) => {
                  this.searchPersist = v
                  this.saveSetting('searchPersist', String(v))
                })
            }
            .width('100%').padding({ top: 8 })
          }
          .width('100%').padding(16)
          .backgroundColor(this.themeCardBg).borderRadius(12)

          // 悬浮球设置
          Column({ space: 8 }) {
            Text('\u60AC\u6D6E\u7403')
              .fontSize(16).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium).width('100%')
            Text('\u641C\u7D22\u9875\u53F3\u4E0B\u89D2\u60AC\u6D6E\u7403\uFF1A\u957F\u6309\u56DE\u9876\uFF0C\u5355\u51FB\u5C55\u5F00\u83DC\u5355\uFF08\u5237\u65B0/\u6765\u6E90\u7B5B\u9009\uFF09')
              .fontSize(13).fontColor(this.themeTextSecondary).width('100%')
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text('\u5F00\u542F\u60AC\u6D6E\u7403')
                  .fontSize(15).fontColor(this.themeTextPrimary).width('100%')
                Text('\u9ED8\u8BA4\u5F00\u542F')
                  .fontSize(12).fontColor(this.themeTextSecondary).width('100%')
              }
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.searchFloatingBall })
                .selectedColor(this.themePrimary)
                .onChange((v: boolean) => {
                  this.searchFloatingBall = v
                  this.saveSetting('searchFloatingBall', String(v))
                  AppStorage.setOrCreate('searchFloatingBall', v)
                })
            }
            .width('100%').padding({ top: 8 })
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text('\u60AC\u6D6E\u7403\u5DE6\u4FA7')
                  .fontSize(15).fontColor(this.themeTextPrimary).width('100%')
                Text('\u9ED8\u8BA4\u663E\u793A\u5728\u53F3\u4FA7\uFF0C\u5F00\u542F\u540E\u955C\u50CF\u5230\u5DE6\u4FA7\u5BF9\u79F0\u4F4D\u7F6E')
                  .fontSize(12).fontColor(this.themeTextSecondary).width('100%')
              }
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.searchFloatingBallLeft })
                .selectedColor(this.themePrimary)
                .onChange((v: boolean) => {
                  this.searchFloatingBallLeft = v
                  this.saveSetting('searchFloatingBallLeft', String(v))
                  AppStorage.setOrCreate('searchFloatingBallLeft', v)
                })
            }
            .width('100%').padding({ top: 8 })
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
}
