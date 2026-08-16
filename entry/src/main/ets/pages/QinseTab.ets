// SHMY 搜索 Tab - 搜索与播放
// QinseTab.ets - V1.0.8.4 搜索记忆+历史
import { SongInfo, SourceStatus, SourceInfo } from '../model/MusicModel'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { AudioPlayer } from '../utils/AudioPlayer'
import { MusicApi } from '../utils/MusicApi'
import { PlayerStore } from '../utils/PlayerStore'
import { SongCard } from '../components/SongCard'
import { SearchBar } from '../components/SearchBar'
import { SourceManager } from '../utils/SourceManager'
import { SelfHostedApi } from '../utils/SelfHostedApi'

import { SongActionSheet } from '../components/SongActionSheet'
import { promptAction } from '@kit.ArkUI'
import { CompatUtils } from '../utils/CompatUtils'
import { MaterialCompat, MaterialCompatStyle } from '../utils/MaterialCompat'

interface SourceOption {
  label: string
  value: string
}

@Component
export struct QinseTab {
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_primaryLight') themePrimaryLight: string = '#E0F0FF'
  @StorageProp('theme_bg') themeBg: string = '#F8F8FA'
  @StorageProp('theme_cardBg') themeCardBg: string = '#F5F5F5'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'
  @StorageProp('theme_bgImageName') themeBgImageName: string = ''
  @StorageProp('isDarkMode') isDarkMode: boolean = false

  @State keyword: string = ''
  @State selectedSource: string = 'all'
  @State searchResults: SongInfo[] = []
  @State isLoading: boolean = false
  @State isSearched: boolean = false
  @State searchError: string = ''

  // Action sheet
  @State selectedSong: SongInfo | null = null
  @State showActionSheet: boolean = false

  // 搜索历史
  @State searchHistory: string[] = []
  @State searchMemoryEnabled: boolean = true
  // 搜索常驻（设置-版块设置-搜索）
  @State searchPersist: boolean = false

  // 搜索防抖定时器
  private searchTimer: number = -1

  // Source dropdown
  @State showSourceDropdown: boolean = false
  @State sourceOptions: SourceOption[] = []

  // 下拉刷新状态
  @State isRefreshing: boolean = false
  @State refreshProgress: number = 0
  @State pullStartY: number = -1
  @State showPullIndicator: boolean = false
  private pullThreshold: number = 50
  private scroller: Scroller = new Scroller()
  // 自检结果弹窗（底部，与“播放失败”同一位置，沉浸光感）
  @State resultPillText: string = ''
  @State resultPillVisible: boolean = false
  private resultPillTimer: number = -1
  // 自检完成的左上角总结（下拉时不显示，回弹后出现）
  @State refreshSummary: string = ''
  @State refreshSummaryVisible: boolean = false

  // 搜索页悬浮球（设置-版块设置-搜索 控制）
  @StorageProp('searchFloatingBall') searchFloatingBall: boolean = true
  @StorageProp('searchFloatingBallLeft') searchFloatingBallLeft: boolean = false
  // 悬浮球菜单状态 + 来源筛选
  @State showBallMenu: boolean = false
  @State sourceFilter: string = 'all'

  // 搜索模式标记
  @State apiModeLabel: string = ''
  // 监听自建 API 开关变化（插件源互斥关闭自建 API 后实时刷新标签）
  @StorageProp('useSelfHostedApi') @Watch('onSelfHostedModeChange') useSelfHostedApi: boolean = false

  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private supportImmersive: boolean = CompatUtils.isImmersiveSupported()

  // 自建 API 开关变化（插件源互斥关闭自建 API 后）实时刷新搜索模式标签
  onSelfHostedModeChange(): void {
    this.apiModeLabel = this.useSelfHostedApi ? '自建API' : 'JS源'
  }

  async aboutToAppear() {
    this.apiModeLabel = MusicApi.isSelfHostedMode() ? '自建API' : 'JS源'
    // 读取搜索常驻 / 搜索记忆开关
    const persist = await this.db.getSetting('searchPersist')
    this.searchPersist = persist === 'true'
    const mem = await this.db.getSetting('searchMemory')
    this.searchMemoryEnabled = mem !== 'false'
    // 悬浮球设置（默认开启/右侧）
    const ball = await this.db.getSetting('searchFloatingBall')
    AppStorage.setOrCreate('searchFloatingBall', ball !== 'false')
    const ballLeft = await this.db.getSetting('searchFloatingBallLeft')
    AppStorage.setOrCreate('searchFloatingBallLeft', ballLeft === 'true')
    if (this.searchPersist || this.searchMemoryEnabled) {
      // 1. 优先从 AppStorage 恢复（本会话内切换）
      const savedKeyword = AppStorage.get('qinseKeyword') as string | undefined
      const savedResults = AppStorage.get('qinseSearchResults') as SongInfo[] | undefined
      const savedIsSearched = AppStorage.get('qinseIsSearched') as boolean | undefined
      if (savedResults && savedResults.length > 0 && savedIsSearched) {
        this.keyword = savedKeyword ?? ''
        this.searchResults = savedResults
        this.isSearched = true
      } else if (this.searchPersist) {
        // 2. 跨进程重启：AppStorage 不持久化，回退到数据库恢复上次搜索
        const saved = await this.db.getSearchResults()
        if (saved.results.length > 0) {
          this.keyword = saved.keyword
          this.searchResults = saved.results
          this.isSearched = true
          AppStorage.setOrCreate('qinseKeyword', saved.keyword)
          AppStorage.setOrCreate('qinseSearchResults', saved.results)
          AppStorage.setOrCreate('qinseIsSearched', true)
        }
      }
    }
    // 完整加载源列表（确保筛选器可用）
    await this.loadSourceOptions()
    this.loadSearchHistory()
  }

  async loadSourceOptions() {
    if (MusicApi.isSelfHostedMode()) {
      const sources = SelfHostedApi.getAvailableSources()
      const options: SourceOption[] = [{ label: '全部', value: 'all' }]
      for (let i = 0; i < sources.length; i++) {
        options.push({ label: SelfHostedApi.getDisplayName(sources[i]), value: sources[i] })
      }
      this.sourceOptions = options
      return
    }
    await SourceManager.ensureLoaded()
    const names = SourceManager.getSourceNames()
    const options: SourceOption[] = [{ label: '全部', value: 'all' }]
    for (let i = 0; i < names.length; i++) {
      const enabled: boolean = await SourceManager.isSourceEnabled(names[i])
      if (enabled) {
        options.push({ label: names[i], value: names[i] })
      }
    }
    // 始终在前：当前选中的源排在"全部"之后的第一位
    if (this.selectedSource !== 'all' && this.selectedSource.length > 0) {
      const idx = options.findIndex(o => o.value === this.selectedSource)
      if (idx > 1) {
        const item = options.splice(idx, 1)[0]
        options.splice(1, 0, item)
      }
    }
    this.sourceOptions = options
  }

  // 展开筛选下拉前重新加载音源列表，保证与设置-音源管理实时同步
  private async refreshAndToggleDropdown(): Promise<void> {
    await this.loadSourceOptions()
    this.showSourceDropdown = !this.showSourceDropdown
  }

  private async loadSearchMemory(): Promise<void> {
    const val = await this.db.getSetting('searchMemory')
    this.searchMemoryEnabled = val !== 'false'
  }

  private async loadSearchHistory(): Promise<void> {
    this.searchHistory = await this.db.getSearchHistory()
  }

  private saveToAppStorage(): void {
    AppStorage.setOrCreate('qinseKeyword', this.keyword)
    AppStorage.setOrCreate('qinseSearchResults', this.searchResults)
    AppStorage.setOrCreate('qinseIsSearched', this.isSearched)
  }

  private getSourceLabel(source: string): string {
    const option = this.sourceOptions.find(opt => opt.value === source)
    return option ? option.label : source
  }

  aboutToDisappear(): void {
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer)
    }
    if (this.resultPillTimer !== -1) {
      clearTimeout(this.resultPillTimer)
      this.resultPillTimer = -1
    }
  }

  build() {
    Stack() {
      // === Main content (bottom layer, never moves) ===
      Column() {
        // Search bar
        Row({ space: 12 }) {
          // Search input with icon button
          if (this.supportImmersive) {
            Row({ space: 8 }) {
              Row() {
                SymbolGlyph($r('sys.symbol.magnifyingglass'))
                  .fontSize(18)
                  .fontColor([this.themeTextSecondary])
              }
              .width(40)
              .height(40)
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                if (this.keyword.trim().length > 0) {
                  if (this.searchTimer !== -1) {
                    clearTimeout(this.searchTimer)
                  }
                  this.doSearch(this.keyword.trim())
                }
              })

              TextInput({ placeholder: '搜索音乐', text: this.keyword })
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .backgroundColor(Color.Transparent)
                .borderRadius(20)
                .padding({ left: 8 })
                .focusOnTouch(true)
                .onChange((value: string) => {
                  this.keyword = value
                  this.debouncedSearch(value)
                })
                .onSubmit(() => {
                  if (this.keyword.trim().length > 0) {
                    if (this.searchTimer !== -1) {
                      clearTimeout(this.searchTimer)
                    }
                    this.doSearch(this.keyword.trim())
                  }
                })

                if (this.keyword.length > 0) {
                  Row() {
                    SymbolGlyph($r('sys.symbol.xmark'))
                      .fontSize(14)
                      .fontColor([this.themeTextSecondary])
                  }
                  .width(32)
                  .height(32)
                  .justifyContent(FlexAlign.Center)
                  .onClick(() => {
                    this.keyword = ''
                    this.isSearched = false
                    this.searchResults = []
                    AppStorage.setOrCreate('qinseIsSearched', false)
                    AppStorage.setOrCreate('qinseSearchResults', [])
                    this.db.clearSearchResults()
                    if (this.searchTimer !== -1) {
                      clearTimeout(this.searchTimer)
                    }
                  })
                }
            }
            .layoutWeight(1)
            .systemMaterial(MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN))
            .borderRadius(20)
            .padding({ right: 8 })
          } else {
            Row({ space: 8 }) {
              Row() {
                SymbolGlyph($r('sys.symbol.magnifyingglass'))
                  .fontSize(18)
                  .fontColor([this.themeTextSecondary])
              }
              .width(40)
              .height(40)
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                if (this.keyword.trim().length > 0) {
                  if (this.searchTimer !== -1) {
                    clearTimeout(this.searchTimer)
                  }
                  this.doSearch(this.keyword.trim())
                }
              })

              TextInput({ placeholder: '搜索音乐', text: this.keyword })
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .backgroundColor(Color.Transparent)
                .borderRadius(20)
                .padding({ left: 8 })
                .focusOnTouch(true)
                .onChange((value: string) => {
                  this.keyword = value
                  this.debouncedSearch(value)
                })
                .onSubmit(() => {
                  if (this.keyword.trim().length > 0) {
                    if (this.searchTimer !== -1) {
                      clearTimeout(this.searchTimer)
                    }
                    this.doSearch(this.keyword.trim())
                  }
                })

                if (this.keyword.length > 0) {
                  Row() {
                    SymbolGlyph($r('sys.symbol.xmark'))
                      .fontSize(14)
                      .fontColor([this.themeTextSecondary])
                  }
                  .width(32)
                  .height(32)
                  .justifyContent(FlexAlign.Center)
                  .onClick(() => {
                    this.keyword = ''
                    this.isSearched = false
                    this.searchResults = []
                    AppStorage.setOrCreate('qinseIsSearched', false)
                    AppStorage.setOrCreate('qinseSearchResults', [])
                    this.db.clearSearchResults()
                    if (this.searchTimer !== -1) {
                      clearTimeout(this.searchTimer)
                    }
                  })
                }
            }
            .layoutWeight(1)
            .backgroundColor(this.themeCardBg)
            .blur(8)
            .borderRadius(20)
            .padding({ right: 8 })
          }

          // Source dropdown button (筛选选择器) - V2.1: 已移除，改为悬浮球筛选（后续接入）
          // 搜索框直接占满宽度
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        // 下拉自检提示（随内容流显示，占位不悬浮；触发刷新后由底部弹窗接替）
        if (this.showPullIndicator) {
          Column({ space: 2 }) {
            Text(this.refreshProgress >= this.pullThreshold ? '↓ 松开自检音源' : '↓ 下拉自检音源')
              .fontSize(12)
              .fontColor(this.themeTextSecondary)
            Text(`${Math.min(100, Math.round(this.refreshProgress / this.pullThreshold * 100))}%`)
              .fontSize(11)
              .fontColor(this.themeTextSecondary)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 2, bottom: 8 })
        }

        // Content area
        if (this.isLoading) {
          this.LoadingSkeleton()
        } else if (this.isSearched) {
          this.SearchResultsContent()
        } else {
          if (this.searchHistory.length > 0) {
            this.SearchHistoryContent()
          } else {
            Column({ space: 12 }) {
              Image($r('app.media.music_note'))
                .width(56)
                .height(56)
                .objectFit(ImageFit.Contain)
                .opacity(0.3)
              Text('\u641C\u7D22\u4F60\u559C\u6B22\u7684\u97F3\u4E50')
                .fontSize(16)
                .fontColor(this.themeTextPrimary)
                .fontWeight(FontWeight.Medium)
              Text('\u5168\u7F51\u97F3\u6E90\u641C\u7D22\u00B7\u4E00\u7AD9\u5F0F\u67E5\u627E')
                .fontSize(13)
                .fontColor(this.themeTextSecondary)
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .padding(40)
            .layoutWeight(1)
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
      .onTouch((event: TouchEvent) => {
        // 搜索结果列表由 Scroll 自身的 onTouch 处理下拉（Scroll 会拦截外层触摸事件）
        if (this.isSearched && this.searchResults.length > 0) {
          return
        }
        this.handleContentPull(event)
      })

      // === 自检进度/结果弹窗（底部，与“播放失败”同一位置，沉浸光感） ===
      if (this.resultPillVisible && this.resultPillText.length > 0) {
        Column() {
          Row({ space: 6 }) {
            Text(this.resultPillText)
              .fontSize(13)
              .fontColor(this.themeTextPrimary)
              .maxLines(1)
          }
          .padding({ left: 18, right: 18, top: 9, bottom: 9 })
          .systemMaterial(this.supportImmersive ? MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN) : undefined)
          .backgroundColor(this.supportImmersive ? Color.Transparent : (this.isDarkMode ? '#CC1A1A1A' : '#CCFFFFFF'))
          .borderRadius(22)
          .shadow({ radius: 12, color: '#33000000', offsetY: 3 })
          .onClick(() => {
            this.hideResultPill()
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: '120vp' })
        .hitTestBehavior(HitTestMode.None)
      }

      // === 悬浮球菜单展开时：点击菜单外任意区域关闭（透明遮罩，置于悬浮球之下） ===
      if (this.showBallMenu) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showBallMenu = false
          })
      }

      // === 搜索页悬浮球（迷你栏上方；单击展开菜单、长按回顶；菜单为独立圆角矩形按钮，沉浸光感） ===
      if (this.searchFloatingBall) {
        Column({ space: 12 }) {
          // 展开菜单：直接内联于球体上方（非气泡弹窗，每个子功能为独立按钮）
          if (this.showBallMenu) {
            this.BallMenuContent()
          }
          Stack() {
            Image($r('app.media.ic_gallery_photoedit_more'))
              .width(30)
              .height(30)
              .objectFit(ImageFit.Contain)
              .fillColor(this.themeTextPrimary)
          }
          .width(50)
          .height(50)
          .borderRadius(25)
          .systemMaterial(this.supportImmersive ? MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK) : undefined)
          .backgroundColor(this.supportImmersive ? Color.Transparent : (this.isDarkMode ? '#CC2C2C32' : '#CCFFFFFF'))
          .shadow({ radius: 14, color: '#33000000', offsetY: 4 })
          .gesture(
            GestureGroup(GestureMode.Exclusive,
              LongPressGesture({ repeat: false, duration: 500 })
                .onAction(() => {
                  this.showBallMenu = false
                  this.scrollSearchToTop()
                }),
              TapGesture({ count: 1 })
                .onAction(() => {
                  this.showBallMenu = !this.showBallMenu
                }),
            )
          )
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(this.searchFloatingBallLeft ? HorizontalAlign.Start : HorizontalAlign.End)
        .padding({ left: this.searchFloatingBallLeft ? 18 : 0, right: this.searchFloatingBallLeft ? 0 : 18, bottom: '84vp' })
        .hitTestBehavior(HitTestMode.None)
      }

      // === Floating dropdown overlay (top layer, covers content below) ===
      // V2.1: 筛选器已移除，改为悬浮球（后续接入）

      // Action sheet
      if (this.selectedSong) {
        SongActionSheet({
          song: this.selectedSong!,
          visible: this.showActionSheet,
          mode: 'search',
          onDismiss: () => {
            this.showActionSheet = false
            this.selectedSong = null
          },
          onPlay: (song: SongInfo) => {
            this.playSong(song)
          },
          onAddFavorite: (song: SongInfo) => {
            this.addFavorite(song)
          },
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  // 防抖搜索
  private debouncedSearch(kw: string): void {
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer)
    }
    if (kw.trim().length === 0) {
      this.isSearched = false
      this.searchResults = []
      return
    }
    this.searchTimer = setTimeout(() => {
      this.doSearch(kw.trim())
    }, 500)
  }

  // ===== 下拉刷新：全部音源自检 / 链路打通 =====
  private onPullStart(event: TouchEvent): void {
    if (this.isRefreshing || this.isLoading) return
    const touch = event.touches[0]
    if (!touch) return
    // 记录起点（滚动区域需在顶部，由 handleScrollPull 控制）；不立即显示，有真实下拉位移后再显示
    this.pullStartY = touch.y
    this.refreshProgress = 0
    this.showPullIndicator = false
  }

  private onPullMove(event: TouchEvent): void {
    if (this.pullStartY < 0 || this.isRefreshing || this.isLoading) return
    const touch = event.touches[0]
    if (!touch) return
    const delta = touch.y - this.pullStartY
    if (delta > 6) {
      // 下拉 50px 才触发：1:1 记录实际位移；超过 6px 才算真正下拉，避免一碰就触发
      if (!this.showPullIndicator) {
        this.showPullIndicator = true
        // 真正开始下拉时隐藏上一次的结果提示与左上角总结
        this.hideResultPill()
        this.refreshSummaryVisible = false
      }
      this.refreshProgress = Math.min(delta, 120)
    } else {
      this.refreshProgress = 0
      this.showPullIndicator = false
    }
  }

  private onPullEnd(): void {
    if (this.pullStartY < 0) {
      return
    }
    this.pullStartY = -1
    if (this.refreshProgress >= this.pullThreshold && !this.isRefreshing) {
      // 达到 50px 触发刷新：顶部指示器回落，由底部沉浸光感弹窗接替
      this.startFullSourceRefresh()
    } else {
      this.showPullIndicator = false
      this.refreshProgress = 0
    }
  }

  // 非滚动区域（历史/空态/加载态）的下拉处理
  private handleContentPull(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.onPullStart(event)
    } else if (event.type === TouchType.Move) {
      this.onPullMove(event)
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.onPullEnd()
    }
  }

  // 搜索结果 Scroll 内的下拉处理：仅当列表位于顶部时才允许触发
  private handleScrollPull(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      if (this.scroller.currentOffset().yOffset > 0) {
        // 列表已向下滚动，不触发下拉
        this.pullStartY = -1
        return
      }
      this.onPullStart(event)
    } else if (event.type === TouchType.Move) {
      this.onPullMove(event)
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.onPullEnd()
    }
  }

  // 底部橙色结果弹窗（与“播放失败”弹窗同一位置，自动消失）
  private showResultPill(text: string, autoDismiss: boolean): void {
    if (this.resultPillTimer !== -1) {
      clearTimeout(this.resultPillTimer)
      this.resultPillTimer = -1
    }
    this.resultPillText = text
    this.resultPillVisible = true
    if (autoDismiss) {
      this.resultPillTimer = setTimeout(() => {
        this.resultPillVisible = false
        this.resultPillTimer = -1
      }, 2500)
    }
  }

  private hideResultPill(): void {
    if (this.resultPillTimer !== -1) {
      clearTimeout(this.resultPillTimer)
      this.resultPillTimer = -1
    }
    this.resultPillVisible = false
  }

  // ===== 悬浮球 =====

  /** 长按回顶：仅搜索结果列表可滚动时生效 */
  private scrollSearchToTop(): void {
    if (this.isSearched && this.searchResults.length > 0) {
      this.scroller.scrollEdge(Edge.Top)
    }
  }

  /** 菜单-刷新：回到顶部并触发全源自检（下拉刷新同款） */
  private handleBallRefresh(): void {
    this.showBallMenu = false
    this.scrollSearchToTop()
    this.startFullSourceRefresh()
  }

  /** 来源筛选后的展示列表（'all' 显示全部） */
  private getDisplayResults(): SongInfo[] {
    if (this.sourceFilter === 'all') {
      return this.searchResults
    }
    return this.searchResults.filter((s: SongInfo) => s.source === this.sourceFilter)
  }

  /** 悬浮球菜单：无气泡容器，每个子功能为独立圆角矩形按钮（Button 示例7），上下间距 8，全部沉浸光感 */
  @Builder
  BallMenuContent() {
    Column({ space: 8 }) {
      this.BallMenuButton('刷新', 'refresh')
      this.BallMenuButton('全部', 'all')
      this.BallMenuButton('KG', 'kg')
      this.BallMenuButton('KW', 'kw')
      this.BallMenuButton('QQ', 'tx')
      this.BallMenuButton('WY', 'wy')
    }
    // 容器自身不拦截触摸，按钮之间的空隙可点击关闭菜单
    .hitTestBehavior(HitTestMode.None)
  }

  /** 独立胶囊形菜单按钮：选中/刷新 = 主题浅色底+主题色加粗；其余 = 沉浸光感磨砂底+投影 */
  @Builder
  BallMenuButton(label: string, value: string) {
    Button(label)
      .type(ButtonType.Capsule)
      .controlSize(ControlSize.NORMAL)
      .width(96)
      .height(40)
      .fontSize(14)
      .fontColor(this.ballButtonColor(value))
      .fontWeight(value === 'refresh' || this.sourceFilter === value ? FontWeight.Bold : FontWeight.Normal)
      .backgroundColor(this.ballButtonBg(value))
      .systemMaterial(this.supportImmersive ? MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK) : undefined)
      .shadow({ radius: 12, color: '#33000000', offsetY: 3 })
      .stateEffect(true)
      .onClick(() => {
        if (value === 'refresh') {
          this.handleBallRefresh()
        } else {
          this.sourceFilter = value
          this.showBallMenu = false
        }
      })
  }

  private ballButtonBg(value: string): ResourceColor {
    if (value === 'refresh' || this.sourceFilter === value) {
      return this.themePrimaryLight
    }
    return Color.Transparent
  }

  private ballButtonColor(value: string): ResourceColor {
    if (value === 'refresh') {
      return this.themePrimary
    }
    return this.sourceFilter === value ? this.themePrimary : this.themeTextPrimary
  }

  // 全源自检：依次测试所有已启用音源，统计可用/不可用
  private async startFullSourceRefresh(): Promise<void> {
    if (this.isRefreshing) return
    this.isRefreshing = true
    // 顶部指示器回落，改由底部沉浸光感弹窗常驻（与“播放失败”同一位置）
    this.showPullIndicator = false
    this.refreshProgress = 0
    this.showResultPill('正在自检全部音源…', false)

    let enabledSources = 0
    let availableSources = 0
    // 按 songId 去重统计实际歌曲数，避免多源重复虚高
    const seenSongKeys = new Set<string>()
    const names = SourceManager.getSourceNames()

    for (let i = 0; i < names.length; i++) {
      const name = names[i]
      if (!(await SourceManager.isSourceEnabled(name))) continue
      enabledSources++
      // 尝试用该源搜索一首测试歌
      try {
        const songs = await MusicApi.search('海阔天空', name)
        if (songs.length > 0) {
          availableSources++
          for (let j = 0; j < songs.length; j++) {
            const s = songs[j]
            const key = (s.source || '') + '|' + (s.songId || '')
            if (!seenSongKeys.has(key)) {
              seenSongKeys.add(key)
            }
          }
        }
      } catch (_e) {
        // 忽略单个源失败
      }
    }

    // 刷新完成：内容回弹后，底部弹窗显示可用源数，左上角显示总结
    this.isRefreshing = false
    this.refreshProgress = 0
    console.info(`[QinseTab] refresh done: enabled=${enabledSources}, available=${availableSources}, songs=${seenSongKeys.size}`)
    this.showResultPill(`${availableSources}/${enabledSources} 个源可用`, true)
    // 左上角总结：徽章已显示“JS源/自建API”，这里存歌曲数，渲染时拼成“JS源 / 共找到 X 首歌曲”，常驻显示
    this.refreshSummary = `共找到 ${seenSongKeys.size} 首歌曲`
    this.refreshSummaryVisible = true
  }

  @Builder
  SearchHistoryContent() {
    Column() {
      Row() {
        Row({ space: 6 }) {
          Text('搜索记录')
            .fontSize(14)
            .fontColor(this.themeTextPrimary)
            .fontWeight(FontWeight.Medium)
          Text(this.apiModeLabel)
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor(this.apiModeLabel === '自建API' ? '#007DFF' : '#FF9800')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(8)

          // 自检完成后的总结：随内容流显示（同 JS源 徽章），常驻不消失
          if (this.refreshSummaryVisible && this.refreshSummary.length > 0) {
            Text(' / ' + this.refreshSummary)
              .fontSize(12)
              .fontColor(this.themeTextSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
        }
        .layoutWeight(1)

        Row() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(16)
            .fontColor([this.themeTextSecondary])
        }
        .width(32)
        .height(32)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.clearAllHistory()
        })
      }
      .width('100%')
      .padding({ left: 4, right: 4, bottom: 8 })

      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        ForEach(this.searchHistory, (keyword: string) => {
          Text(keyword)
            .fontSize(13)
            .fontColor(this.themeTextPrimary)
            .backgroundColor(this.themeCardBg)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.keyword = keyword
              this.doSearch(keyword)
            })
        })
      }
      .width('100%')
      .padding({ left: 4 })
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16, top: 4 })
  }

  @Builder
  SearchResultsContent() {
    if (this.getDisplayResults().length === 0) {
      Column({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(48)
          .fontColor(['#999999'])
          .opacity(0.3)
        if (this.sourceFilter !== 'all' && this.searchResults.length > 0) {
          // 来源筛选后无该源歌曲
          Text(`\u300C${SourceInfo.getAbbr(this.sourceFilter)}\u300D\u6765\u6E90\u6682\u65E0\u6B4C\u66F2`)
            .fontSize(16)
            .fontColor(this.themeTextPrimary)
            .fontWeight(FontWeight.Medium)
          Text('\u4F7F\u7528\u60AC\u6D6E\u7403\u83DC\u5355\u5207\u56DE\u201C\u5168\u90E8\u201D\u5373\u53EF')
            .fontSize(13)
            .fontColor(this.themeTextSecondary)
        } else {
          Text('\u672A\u627E\u5230\u76F8\u5173\u6B4C\u66F2')
            .fontSize(16)
            .fontColor(this.themeTextPrimary)
            .fontWeight(FontWeight.Medium)

          // 显示具体错误原因
          if (this.searchError.length > 0) {
            Text(this.searchError)
              .fontSize(12)
              .fontColor('#FF6B6B')
              .textAlign(TextAlign.Center)
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 20, right: 20 })
          } else {
            Text('\u6362\u4E2A\u5173\u952E\u8BCD\u8BD5\u8BD5\u5427')
              .fontSize(13)
              .fontColor(this.themeTextSecondary)
          }

          // 显示当前搜索模式
          Text(`\u5F53\u524D\u6A21\u5F0F\uFF1A${this.apiModeLabel}`)
            .fontSize(11)
            .fontColor(this.themeTextSecondary)
            .opacity(0.6)
            .margin({ top: 4 })
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding(40)
      .layoutWeight(1)
    } else {
      Scroll(this.scroller) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text(this.apiModeLabel)
              .fontSize(10)
              .fontColor(Color.White)
              .backgroundColor(this.apiModeLabel === '自建API' ? '#007DFF' : '#FF9800')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(8)
              .flexShrink(0)

            // 自检完成后的总结：与徽章、右侧小字三者共存；总结占中间弹性位，超长省略不挤压
            if (this.refreshSummaryVisible && this.refreshSummary.length > 0) {
              Text(' / ' + this.refreshSummary)
                .fontSize(12)
                .fontColor(this.themeTextSecondary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
                .textAlign(TextAlign.Start)
              Text('\u53CC\u51FB\u64AD\u653E \u00B7 \u957F\u6309\u66F4\u591A\u64CD\u4F5C')
                .fontSize(11)
                .fontColor(this.themeTextSecondary)
                .flexShrink(0)
                .textAlign(TextAlign.End)
            } else {
              Text('\u53CC\u51FB\u64AD\u653E \u00B7 \u957F\u6309\u66F4\u591A\u64CD\u4F5C')
                .fontSize(11)
                .fontColor(this.themeTextSecondary)
                .layoutWeight(1)
                .textAlign(TextAlign.End)
            }
          }
          .width('100%')
          .padding({ left: 4, bottom: 8 })

          // Song list - 使用双击播放模式（来源筛选后只显示对应来源歌曲）
          ForEach(this.getDisplayResults(), (song: SongInfo) => {
            SongCard({
              song: song,
              doubleTapToPlay: true,
              onPlay: (s: SongInfo) => {
                this.playSong(s)
              },
              onMore: (s: SongInfo) => {
                this.selectedSong = s
                this.showActionSheet = true
              },
            })
          })

          // Bottom spacing
          Column().height(168)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .scrollBarColor('#CCCCCC')
      .scrollBarWidth(4)
      .edgeEffect(EdgeEffect.Spring)
      .onTouch((event: TouchEvent) => {
        // 列表自身的下拉处理：Scroll 会拦截外层 onTouch，必须在列表上直接监听
        this.handleScrollPull(event)
      })
    }
  }

  @Builder
  LoadingSkeleton() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(this.themePrimary)
        .margin({ bottom: 12 })

      Text('正在搜索...')
        .fontSize(14)
        .fontColor(this.themeTextSecondary)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private async doSearch(kw: string) {
    this.keyword = kw
    this.isLoading = true
    this.isSearched = true
    this.searchError = ''
    // 新搜索重置来源筛选
    this.sourceFilter = 'all'
    this.showBallMenu = false

    const mode = MusicApi.isSelfHostedMode() ? '自建API' : 'JS源'
    console.info(`[QinseTab] doSearch: keyword="${kw}", source=${this.selectedSource}, mode=${mode}`)

    try {
      this.searchResults = await MusicApi.search(kw, this.selectedSource)
      // V1.1.0 防御性过滤：确保只展示当前选中源的歌曲
      if (this.selectedSource !== 'all' && this.searchResults.length > 0) {
        this.searchResults = this.searchResults.filter(s => s.source === 'custom_' + this.selectedSource)
      }
      console.info(`[QinseTab] search done: ${this.searchResults.length} results`)
      if (this.searchResults.length === 0) {
        this.searchError = MusicApi.lastError || '未找到相关歌曲'
      }
    } catch (e) {
      console.error('[QinseTab] search error:', e)
      this.searchResults = []
      this.searchError = '搜索异常：' + String(e)
    }

    this.isLoading = false
    this.saveToAppStorage()

    // 保存搜索历史和结果
    if (this.searchMemoryEnabled) {
      await this.db.addSearchHistory(kw)
      await this.db.saveSearchResults(kw, this.searchResults)
      this.loadSearchHistory()
    }
  }

  private async clearAllHistory(): Promise<void> {
    await this.db.clearSearchHistory()
    await this.db.clearSearchResults()
    this.searchHistory = []
    promptAction.showToast({ message: '\u641C\u7D22\u8BB0\u5F55\u5DF2\u6E05\u7A7A', duration: 1500 })
  }

  private async playSong(song: SongInfo) {
    // 获取播放链接
    let playUrl = song.playUrl
    if (!playUrl) {
      playUrl = await MusicApi.getPlayUrl(song.songId, song.source, song)
    }
    if (!playUrl) {
      SourceStatus.markUnplayable(song.source)
      this.showToastMessage('\u65E0\u6CD5\u83B7\u53D6\u64AD\u653E\u94FE\u63A5')
      return
    }

    // 更新歌曲播放链接
    song.playUrl = playUrl

    // 设置播放器状态和队列
    PlayerStore.play(song, this.searchResults, this.searchResults.indexOf(song))

    // 配置音频播放器回调
    const player = AudioPlayer.getInstance()
    player.setCurrentSong(song)
    player.onTimeUpdate = (time: number) => {
      PlayerStore.updateTime(time)
    }
    player.onDurationUpdate = (duration: number) => {
      PlayerStore.updateDuration(duration)
    }
    player.onPlayEnd = () => {
      const nextTrack = PlayerStore.onTrackEnd()
      if (nextTrack) {
        this.playSong(nextTrack)
      } else {
        PlayerStore.pause()
      }
    }
    player.onError = (error: string) => {
      console.error('[QinseTab] play error:', error)
      SourceStatus.markUnplayable(song.source)
      PlayerStore.pause()
      promptAction.showToast({
        message: error || '播放失败，3秒后自动播放下一首',
        duration: 3000,
        bottom: '120vp'
      })
      setTimeout(() => {
        const nextTrack = PlayerStore.next()
        if (nextTrack) {
          this.playSong(nextTrack)
        }
      }, 3000)
    }

    await player.play(playUrl)

    // 播放成功：标记该音源可用（恢复彩色标签）
    SourceStatus.markPlayable(song.source)

    // 自动详情：点击歌曲后同步打开详情页
    if (AppStorage.get<boolean>('autoJumpDetail') === true) {
      PlayerStore.showFullPlayer()
    }
  }

  private async addFavorite(song: SongInfo) {
    const result = await this.db.addFavorite(song)
    if (result) {
      this.showToastMessage('\u5DF2\u6DFB\u52A0\u5230\u6536\u85CF')
    } else {
      this.showToastMessage('\u5DF2\u5728\u6536\u85CF\u4E2D')
    }
  }

  private showToastMessage(message: string) {
    promptAction.showToast({ message, duration: 2000 })
  }
}