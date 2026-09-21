import { DatabaseHelper } from '../database/DatabaseHelper'
import { FullPlayerPage } from './FullPlayerPage'
import { StartupDialog } from '../components/StartupDialog'
import { DesktopLyricsWindow } from '../components/DesktopLyricsWindow'
import { StatusBarManager } from '../utils/StatusBarManager'
import {
  HdsTabs,
  HdsTabsController,
  HdsTabsFloatingStyle,
  HdsBarStyle,
  HdsTabsBarChangeMode,
  hdsMaterial
} from '@kit.UIDesignKit'

import { XuanchuangTab } from './XuanchuangTab'
import { QinseTab } from './QinseTab'
import { TuijianTab } from './TuijianTab'
import { YinjiTab } from './YinjiTab'
import { LoushiTab } from './LoushiTab'
import { JsEngineHost } from '../components/JsEngineHost'
import { MFEngineHost } from '../components/MFEngineHost'
import { LXSourceHost } from '../source/LXSourceHost'
import { MiniBarPlayer } from '../components/MiniBarPlayer'
import { MaterialCompat } from '../utils/MaterialCompat'
import { promptAction } from '@kit.ArkUI'

@Entry
@Component
struct Index {
  @State activeTab: number = 3
  @StorageProp('showSettingsSidebar') @Watch('onSettingsSidebarChange') showSettingsSidebar: boolean = false
  @StorageProp('showFullPlayer') @Watch('onShowFullPlayerChange') showFullPlayer: boolean = false
  @StorageProp('fullPlayerPage') fullPlayerPage: string = 'cover'
  @StorageProp('autoJumpDetail') autoJumpDetail: boolean = false
  @StorageProp('theme_bg') @Watch('onThemeBgChange') themeBg: string = '#F5F5F7'
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'
  @StorageProp('theme_bgImageName') @Watch('onThemeBgChange') themeBgImageName: string = ''
  // 播放失败全局提示（由 AudioPlayer 统一写入：消息|时间戳）
  @StorageProp('playerErrorNotice') @Watch('onPlayerErrorNotice') playerErrorNotice: string = ''
  // 推荐页搜索栏点击信号（时间戳）：跳转到搜索 Tab
  @StorageProp('jumpToSearchTab') @Watch('onJumpToSearchTab') jumpToSearchTab: number = 0
  @State showPlayerOverlay: boolean = false

  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private controller: HdsTabsController = new HdsTabsController()
  @State private miniBarApplied: boolean = false

  aboutToAppear(): void {
    // 主题初始化已移至 EntryAbility.onCreate，在 UI 创建前完成
    AppStorage.setOrCreate('desktopLyrics', false)
    AppStorage.setOrCreate('lockDesktopLyrics', false)
    AppStorage.setOrCreate('multiLineLyrics', false)
    AppStorage.setOrCreate('lyricsSize', 'standard')
    AppStorage.setOrCreate('lyricsColor', '#FFFFFF')
    AppStorage.setOrCreate('lyricsBgOpacity', 50)
    AppStorage.setOrCreate('playMode', 0)
    // 迷你栏默认展开（1 = EXPAND）
    AppStorage.setOrCreate('miniBarStyle', 1)
    // 封面/歌词自动补全默认关闭（设置-播放器内开启；LocalTagEnricher 读取此开关）
    AppStorage.setOrCreate('autoEnrichTags', false)
    // 迷你栏歌曲来源徽章默认开启（设置-播放器-Minibar 设置内开关）
    AppStorage.setOrCreate('miniBarShowSource', true)
    // 设置页以全屏侧边栏形式展开，默认关闭
    AppStorage.setOrCreate('showSettingsSidebar', false)
    // 初始化各 Tab 的子页面状态，用于侧滑返回统一处理
    AppStorage.setOrCreate('xuanchuang_subPage', 'main')
    AppStorage.setOrCreate('loushi_subPage', 'main')
    this.checkAnnouncementDate()
    this.loadAutoJumpSetting()
    // 默认展示展开的迷你栏
    setTimeout(() => {
      if (!this.miniBarApplied) {
        this.miniBarApplied = true
        this.controller.applyMiniBarStyle(HdsBarStyle.EXPAND)
      }
    }, 100)
  }

  // 播放失败提示：AudioPlayer 写入 "消息|时间戳"，时间戳保证每次都触发 @Watch
  private onPlayerErrorNotice(): void {
    const sep: number = this.playerErrorNotice.indexOf('|')
    const msg: string = sep > 0 ? this.playerErrorNotice.substring(0, sep) : this.playerErrorNotice
    if (msg.length > 0) {
      promptAction.showToast({ message: msg, duration: 2000, bottom: '120vp' })
    }
  }

  // 侧滑 / 返回键统一处理：优先关闭全屏播放器，其次关闭设置侧边栏，再返回当前 Tab 子页，最后退出应用
  onBackPress(): boolean {
    if (this.showPlayerOverlay) {
      this.closePlayerOverlay()
      return true
    }

    if (this.showSettingsSidebar) {
      this.closeSettingsSidebar()
      return true
    }

    // 搜索页 index=0：返回键回到推荐页，避免直接退出应用
    if (this.activeTab === 0) {
      this.controller.changeIndex(1)
      return true
    }

    // 我的页 index=3
    if (this.activeTab === 3) {
      const xuanchuangSubPage: string = AppStorage.get<string>('xuanchuang_subPage') ?? 'main'
      if (xuanchuangSubPage !== 'main') {
        AppStorage.setOrCreate('xuanchuang_subPage', 'main')
        return true
      }
    }

    return false
  }

  private onJumpToSearchTab(): void {
    // 推荐页搜索栏被点击，切换到搜索 Tab
    this.controller.changeIndex(0)
  }

  private onSettingsSidebarChange(): void {
    // 侧边栏状态变化时无需额外处理；展开/关闭由 AppStorage 标志驱动
  }

  private closeSettingsSidebar(): void {
    AppStorage.setOrCreate('showSettingsSidebar', false)
    // 关闭侧边栏时复位设置子页为首页，下次展开回到设置主界面
    AppStorage.setOrCreate('loushi_subPage', 'main')
  }

  private async checkAnnouncementDate(): Promise<void> {
    const lastDate: string = await this.db.getSetting('announcementDismissedDate')
    if (lastDate === this.getTodayStr()) {
      AppStorage.setOrCreate('showStartup', false)
    }
  }

  private async loadAutoJumpSetting(): Promise<void> {
    const val = await this.db.getSetting('autoJumpDetail')
    if (val === 'true') {
      AppStorage.setOrCreate('autoJumpDetail', true)
    }
  }

  private getTodayStr(): string {
    const d = new Date()
    const year: number = d.getFullYear()
    const month: string = (d.getMonth() + 1).toString().padStart(2, '0')
    const day: string = d.getDate().toString().padStart(2, '0')
    return year + '-' + month + '-' + day
  }

  private onTabChange(index: number): void {
    this.activeTab = index
    if (index === 0) {
      // 搜索 Tab 可见：通知 QinseTab 恢复上次搜索状态
      AppStorage.setOrCreate('qinseTabVisible', Date.now())
    }
  }

  private async handleStartupDismiss(dontShowToday: boolean): Promise<void> {
    if (dontShowToday) {
      await this.db.setSetting('announcementDismissedDate', this.getTodayStr())
    }
  }

  private onThemeBgChange(): void {
    if (!this.showFullPlayer) {
      StatusBarManager.applyForBackground(this.themeBg)
    }
  }

  private onShowFullPlayerChange(): void {
    if (this.showFullPlayer) {
      this.showPlayerOverlay = true
      // 全屏播放器使用深色背景，状态栏文字改为白色
      StatusBarManager.applyForBackground('#1A1A1A')
    } else {
      // 退出全屏播放器，恢复主题背景色的状态栏
      StatusBarManager.applyForBackground(this.themeBg)
    }
  }

  private closePlayerOverlay(): void {
    this.showPlayerOverlay = false
    AppStorage.setOrCreate('showFullPlayer', false)
  }

  private getBarFloatingStyle(): HdsTabsFloatingStyle {
    return {
      barBottomMargin: 20,
      // V2.1.0：加强底部栏沉浸光感 —— 系统沉浸式材质 + 主题色光晕 + 微透明
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      lightColor: MaterialCompat.withAlpha(this.themePrimary, 0.12),
      barOpacity: 0.9,
      miniBar: {
        miniBarBuilder: () => this.MiniBarBuilder(),
        onBarStyleChange: (style: HdsBarStyle, _tabBarStyle: HdsBarStyle, _miniBarWidth: number, _tabBarWidth: number, _mode: HdsTabsBarChangeMode) => {
          // 迷你栏样式写入 AppStorage，供 MiniBarPlayer 独立订阅（避免 builder 缓存导致不刷新）
          AppStorage.setOrCreate('miniBarStyle', style)
        }
      }
    }
  }

  build() {
    Stack() {
      // 全局主题背景图（仅部分主题有背景图）
      this.ThemeBackgroundImage()

      // 顶部留出 44px 状态栏高度，HdsTabs 内容从此处开始
      Column() {
        // index=3：启动默认展示「我的」页；index=0：搜索页（常驻）
        HdsTabs({ controller: this.controller, index: this.activeTab }) {
          TabContent() {
            QinseTab({
              onBack: () => {
                // 搜索页返回：回到推荐页
                this.controller.changeIndex(1)
              }
            })
          }
          .tabBar(this.buildTabBarBuilder(0, '搜索', $r('sys.symbol.magnifyingglass'), 'serch.svg'))

          TabContent() {
            TuijianTab()
          }
          .tabBar(this.buildTabBarBuilder(1, '推荐', $r('sys.symbol.star'), 'tj.svg'))

          TabContent() {
            YinjiTab()
          }
          .tabBar(this.buildTabBarBuilder(2, '音迹', $r('sys.symbol.waveform'), 'xj.svg'))

          TabContent() {
            XuanchuangTab()
          }
          .tabBar(this.buildTabBarBuilder(3, '我的', $r('sys.symbol.person_fill'), 'my.svg'))
        }
        .vertical(false)
        .barPosition(BarPosition.End)
        .barMode(BarMode.Fixed)
        .scrollable(false)
        .barOverlap(true)
        .onChange((index: number) => {
          this.onTabChange(index)
        })
        .barFloatingStyle(this.getBarFloatingStyle())
      }
      .width('100%')
      .height('100%')
      .padding({ top: 44 })

      StartupDialog({
        onDismiss: (dontShowToday: boolean) => {
          this.handleStartupDismiss(dontShowToday)
        },
      })

      DesktopLyricsWindow()

      // V1 引擎宿主（js_engine.html，兼容 module.exports 格式插件）
      JsEngineHost()

      // MusicFree 插件沙箱宿主（mf_host.html，CommonJS + axios/crypto-js/cheerio 等库环境）
      MFEngineHost()

      // V3 引擎宿主（lx_bridge.html，兼容 globalThis.lx 事件驱动插件）
      LXSourceHost()

      // 全屏播放器 Overlay（底部上滑，渐缓动画）
      if (this.showPlayerOverlay) {
        Column() {
          FullPlayerPage({
            onClose: () => this.closePlayerOverlay()
          })
        }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.translate({ y: '100%' }).animation({ duration: 400, curve: Curve.EaseOut }))
      }

      // 设置页：全屏侧边栏（从右侧滑入，点击遮蔽背景关闭）
      if (this.showSettingsSidebar) {
        Stack({ alignContent: Alignment.Start }) {
          // 遮蔽背景：点击关闭侧边栏
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#66000000')
            .onClick(() => {
              this.closeSettingsSidebar()
            })

          // 右侧面板：容纳设置页（顶边距交由 LoushiTab 根处理，使背景延伸到状态栏）
          Column() {
            LoushiTab()
          }
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.translate({ x: '100%' }).animation({ duration: 320, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
  }

  @Builder
  ThemeBackgroundImage() {
    if (this.themeBgImageName === 'lxtx') {
      Image($rawfile('theme-lxtx.jpg'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else if (this.themeBgImageName === 'xrhf') {
      Image($rawfile('theme-xrhf.jpg'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else if (this.themeBgImageName === 'nyqf') {
      Image($rawfile('theme-nyqf.jpg'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else if (this.themeBgImageName === 'nyha') {
      Image($rawfile('theme-nyha.jpg'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else if (this.themeBgImageName === 'xcwh') {
      Image($rawfile('theme-xcwh.jpg'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    }
  }

  @Builder
  MiniBarBuilder() {
    // 独立组件直接订阅 AppStorage，切歌后封面/歌词实时刷新（不受 HdsTabs builder 缓存影响）
    MiniBarPlayer({
      onExpandRequest: () => {
        this.controller.applyMiniBarStyle(HdsBarStyle.EXPAND)
      }
    })
  }

  @Builder
  buildTabBarBuilder(index: number, label: string, icon: Resource, iconRaw?: string) {
    Column({ space: 2 }) {
      if (iconRaw !== undefined && iconRaw.length > 0) {
        Image($rawfile(iconRaw))
          .width(22)
          .height(22)
      } else {
        SymbolGlyph(icon)
          .fontSize(22)
          .fontColor(['#000000'])
      }
      Text(label)
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor('#000000')
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .height('100%')
  }
}
