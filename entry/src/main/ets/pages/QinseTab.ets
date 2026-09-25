// SHMY 搜索 Tab - 搜索与播放
// QinseTab.ets - V1.1.1 常驻搜索 Tab：搜索栏内嵌联想面板 + 筛选下拉（自动检测音源）
import { SongInfo, SourceStatus, SourceInfo } from '../model/MusicModel'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { AudioPlayer } from '../utils/AudioPlayer'
import { MusicApi } from '../utils/MusicApi'
import { PlayerStore } from '../utils/PlayerStore'
import { SongCard } from '../components/SongCard'

import { SongActionSheet } from '../components/SongActionSheet'

import { CompatUtils } from '../utils/CompatUtils'
import { MaterialCompat, MaterialCompatStyle } from '../utils/MaterialCompat'
import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit'

interface SearchSuggestion {
  text: string
  fromHistory: boolean
}

interface FilterMenuItem {
  value: string
  action: () => void
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
  // 筛选：从当前结果中自动检测可用音源
  @State sourceFilter: string = 'all'
  // 版块设置-搜索：筛选源规定-自动定位跳转（默认开启）：自动记忆、定位、跳转上次的音源位置
  @StorageProp('searchSourceLocate') searchSourceLocate: boolean = true
  // 上次选择的音源筛选（持久化，新搜索自动沿用）
  private lastSourceFilter: string = 'all'

  // Action sheet
  @State selectedSong: SongInfo | null = null
  @State showActionSheet: boolean = false

  // 搜索历史
  @State searchHistory: string[] = []
  @State searchMemoryEnabled: boolean = true
  // 搜索常驻（设置-版块设置-搜索）
  @State searchPersist: boolean = false
  // 搜索联想词开关（设置-版块设置-搜索）
  @State searchSuggestEnabled: boolean = true

  // 搜索联想词面板（内嵌于搜索栏下方）
  @State suggestions: SearchSuggestion[] = []
  @State showSuggestPanel: boolean = false
  private suggestTimer: number = -1
  private suggestGen: number = 0

  // 搜索 Tab 可见信号（Index 切换到搜索 Tab 时写入时间戳）
  @StorageProp('qinseTabVisible') @Watch('onTabVisibleSignal') tabVisibleSignal: number = 0

  // 搜索防抖定时器
  private searchTimer: number = -1

  // 结果列表滚动器
  private scroller: Scroller = new Scroller()

  // 下拉刷新状态
  @State isRefreshing: boolean = false
  @State refreshProgress: number = 0
  @State pullStartY: number = -1
  @State showPullIndicator: boolean = false
  private pullThreshold: number = 50
  // 自检结果弹窗（底部，与“播放失败”同一位置，沉浸光感）
  @State resultPillText: string = ''
  @State resultPillVisible: boolean = false
  private resultPillTimer: number = -1
  // 自检完成的左上角总结（下拉时不显示，回弹后出现）
  @State refreshSummary: string = ''
  @State refreshSummaryVisible: boolean = false

  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private supportImmersive: boolean = CompatUtils.isImmersiveSupported()

  // V2.0.8 单曲换源会话状态：播放失败后在已有搜索结果内换源重播（不改歌名）
  private sessionToken: number = 0            // 会话令牌：每次新会话递增，旧异步流程据此自行中止
  private sessionSong: SongInfo | null = null // 本会话正在播放的原曲（歌名/歌手展示保持不变）
  private sessionCandidates: SongInfo[] = []  // 候选音源列表：[0]=原曲 + 搜索结果中同名其它源
  private sessionCursor: number = 0           // 当前尝试到的候选下标
  private sessionBusyToken: number = -1       // 正在运行的重试循环令牌（-1=无循环在跑）
  private sessionAttemptFailed: boolean = false // 起播宽限期内的失败标记（由播放错误回调写入）
  private sessionShownKey: string = ''        // 当前 UI 展示的会话曲目标识（source|songId），换源成功后随身份过继更新

  async aboutToAppear() {
    // 读取搜索常驻 / 搜索记忆 / 搜索联想词开关
    const persist = await this.db.getSetting('searchPersist')
    this.searchPersist = persist === 'true'
    const mem = await this.db.getSetting('searchMemory')
    this.searchMemoryEnabled = mem !== 'false'
    const suggest = await this.db.getSetting('searchSuggest')
    this.searchSuggestEnabled = suggest !== 'false'
    // 自动定位跳转开启时恢复上次选择的音源筛选
    const savedFilter = await this.db.getSetting('searchSourceFilter')
    this.lastSourceFilter = savedFilter.length > 0 ? savedFilter : 'all'
    // 恢复上次搜索（搜索常驻 / 搜索记忆开启时）
    await this.restorePersistedSearch()
    this.loadSearchHistory()
  }

  // Index 切换到搜索 Tab 时触发：状态被清空后尝试恢复
  private onTabVisibleSignal(): void {
    this.restorePersistedSearch()
  }

  private async restorePersistedSearch(): Promise<void> {
    if (this.isSearched || this.keyword.length > 0) {
      return
    }
    if (!this.searchPersist && !this.searchMemoryEnabled) {
      return
    }
    // 1. 优先从 AppStorage 恢复（本会话内切换）
    const savedKeyword = AppStorage.get('qinseKeyword') as string | undefined
    const savedResults = AppStorage.get('qinseSearchResults') as SongInfo[] | undefined
    const savedIsSearched = AppStorage.get('qinseIsSearched') as boolean | undefined
    if (savedResults && savedResults.length > 0 && savedIsSearched) {
      this.keyword = savedKeyword ?? ''
      this.searchResults = savedResults
      this.isSearched = true
      this.applyRememberedFilter()
      return
    }
    // 2. 跨进程重启：AppStorage 不持久化，回退到数据库恢复上次搜索
    if (this.searchPersist) {
      const saved = await this.db.getSearchResults()
      if (saved.results.length > 0) {
        this.keyword = saved.keyword
        this.searchResults = saved.results
        this.isSearched = true
        AppStorage.setOrCreate('qinseKeyword', saved.keyword)
        AppStorage.setOrCreate('qinseSearchResults', saved.results)
        AppStorage.setOrCreate('qinseIsSearched', true)
        this.applyRememberedFilter()
      }
    }
  }

  // 自动定位跳转：新搜索/恢复结果后自动沿用上次选择的音源（结果中无该源时回退"全部"）
  private applyRememberedFilter(): void {
    let next: string = 'all'
    if (this.searchSourceLocate && this.lastSourceFilter !== 'all') {
      const hasSource = this.searchResults.some((s: SongInfo) => this.getSourceOfSong(s) === this.lastSourceFilter)
      if (hasSource) {
        next = this.lastSourceFilter
      }
    }
    this.sourceFilter = next
  }

  private async loadSearchHistory(): Promise<void> {
    this.searchHistory = await this.db.getSearchHistory()
  }

  private saveToAppStorage(): void {
    AppStorage.setOrCreate('qinseKeyword', this.keyword)
    AppStorage.setOrCreate('qinseSearchResults', this.searchResults)
    AppStorage.setOrCreate('qinseIsSearched', this.isSearched)
  }

  aboutToDisappear(): void {
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer)
    }
    if (this.suggestTimer !== -1) {
      clearTimeout(this.suggestTimer)
      this.suggestTimer = -1
    }
    if (this.resultPillTimer !== -1) {
      clearTimeout(this.resultPillTimer)
      this.resultPillTimer = -1
    }
    // V2.0.8：销毁搜索页时结束换源会话，恢复默认错误处理
    this.sessionToken++
    this.sessionSong = null
    this.sessionCandidates = []
    AudioPlayer.getInstance().endRetrySession()
  }

  build() {
    Stack() {
      // V2.1.9：搜索栏迁入 HdsNavDestination 标题栏 bottomBuilder（HDS 官方模式：自定义区放搜索框），
      // 栏体静止透明、样式与歌单详情页一致（GRADIENT_BLUR + systemMaterialEffect）
      HdsNavDestination() {
        Column() {
          // === 搜索联想词面板（直接展示在搜索栏下方，把历史挤压到下面） ===
          if (this.showSuggestPanel && this.keyword.trim().length > 0) {
            // 宽度与标题栏搜索栏对齐（V2.1.9：左右各 16vp）
            Column() {
              this.SuggestPanel()
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
          }

        if (this.showPullIndicator) {
          Column({ space: 2 }) {
            Text(this.refreshProgress >= this.pullThreshold ? '↓ 松开刷新' : '↓ 下拉刷新')
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
        // 搜索结果列表由列表自身 Scroll 处理下拉（Scroll 会拦截外层触摸事件）
        if (this.isSearched && this.searchResults.length > 0) {
          return
        }
        // 联想面板展开时不触发下拉刷新
        if (this.showSuggestPanel) {
          return
        }
        this.handleContentPull(event)
      })
      // V2.1.9：为浮动标题栏让位（stackBuilder 56vp + 8vp 间隙）
      .padding({ top: 64 })
      }
      .titleBar({
        content: {
          // V2.1.9：stackBuilder 叠加于标题行，栏高保持 56vp（bottomBuilder 会附加 56vp 空标题行，弃用）
          stackBuilder: (): void => this.SearchBar(),
        },
        // V2.1.9：与详情页同款——静止透明，滚动浮出浅灰模糊板
        style: {
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.IMMERSIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
          },
        },
      })
      .width('100%')
      .height('100%')

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
          .backgroundColor(this.supportImmersive ? Color.Transparent : (this.isDarkMode ? '#1A1A1A' : '#FFFFFF'))
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

  // V2.1.9：搜索栏（迁入标题栏 stackBuilder，行高 56vp，左右 16vp 与联想面板对齐）
  @Builder
  SearchBar() {
    Row() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(14)
          .fontColor([$r('sys.color.font_primary')])
          .margin({ left: 10 })

        TextInput({ placeholder: '搜索音乐', text: this.keyword })
          .layoutWeight(1)
          .height(32)
          .backgroundColor(Color.Transparent)
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
          .placeholderColor($r('sys.color.font_secondary'))
          .placeholderFont({ size: 14 })
          .onChange((value: string) => {
            // 程序化设置 text（选中联想词/历史记录、清空）时也会触发 onChange：
            // 值与当前关键词一致说明不是用户输入，跳过，避免重复触发联想/搜索
            if (value === this.keyword) {
              return
            }
            this.keyword = value
            if (this.searchSuggestEnabled) {
              // 联想模式：输入即出联想词，不再自动搜索
              this.handleSuggestInput(value)
            } else {
              this.debouncedSearch(value)
            }
          })
          .onSubmit(() => {
            if (this.keyword.trim().length > 0) {
              this.hideSuggestPanel()
              if (this.searchTimer !== -1) {
                clearTimeout(this.searchTimer)
              }
              this.doSearch(this.keyword.trim())
            }
          })

        if (this.keyword.length > 0) {
          Row() {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(16)
              .fontColor([$r('sys.color.font_primary')])
          }
          .width(28)
          .height(28)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.keyword = ''
            this.isSearched = false
            this.searchResults = []
            this.hideSuggestPanel()
            AppStorage.setOrCreate('qinseKeyword', '')
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
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.themeCardBg)
      .padding({ right: 8 })

      // 筛选：点击展开当前结果中自动检测到的音源（选中具体音源时标蓝）
      Button({ type: ButtonType.Normal }) {
        Row({ space: 3 }) {
          Text(this.sourceFilter === 'all' ? '筛选' : SourceInfo.getAbbr(this.sourceFilter))
            .fontSize(11)
            .fontColor(this.sourceFilter === 'all' ? $r('sys.color.font_primary') : this.themePrimary)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(9)
            .fontColor([this.sourceFilter === 'all' ? $r('sys.color.font_primary') : this.themePrimary])
        }
        .justifyContent(FlexAlign.Center)
      }
      .height(36)
      .padding({ left: 10, right: 10 })
      .margin({ left: 8 })
      .borderRadius(18)
      .backgroundColor(this.sourceFilter === 'all' ? this.themeCardBg : this.themePrimaryLight)
      .enabled(this.isSearched && this.searchResults.length > 0)
      .opacity(this.isSearched && this.searchResults.length > 0 ? 1 : 0.4)
      .bindMenu(this.buildFilterMenuItems())
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
  }

  // ===== 搜索联想词 =====

  // 内嵌联想面板：展示在搜索栏正下方
  @Builder
  SuggestPanel() {
    Column() {
      if (this.suggestions.length === 0) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.themePrimary)
          Text('正在获取联想词…')
            .fontSize(13)
            .fontColor(this.themeTextSecondary)
        }
        .width('100%')
        .height(46)
        .justifyContent(FlexAlign.Center)
      } else {
        ForEach(this.suggestions, (item: SearchSuggestion) => {
          Row({ space: 10 }) {
            SymbolGlyph(item.fromHistory ? $r('sys.symbol.clock') : $r('sys.symbol.magnifyingglass'))
              .fontSize(15)
              .fontColor([this.themeTextSecondary])
            Text(item.text)
              .fontSize(14)
              .fontColor(this.themeTextPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .height(42)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            // 点击联想词：关闭面板并搜索
            this.applySuggestion(item.text)
          })
        }, (item: SearchSuggestion) => `${item.fromHistory}_${item.text}`)
      }
    }
    .width('100%')
    .margin({ top: 2 })
    .padding({ left: 14, right: 14, top: 4, bottom: 4 })
    .backgroundColor(this.themeCardBg)
    .borderRadius(14)
    .shadow({ radius: 10, color: '#1A000000', offsetY: 2 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
  }

  // 输入变化：立即展示历史联想 + 防抖拉取在线联想
  private handleSuggestInput(value: string): void {
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer)
      this.searchTimer = -1
    }
    const kw: string = value.trim()
    if (kw.length === 0) {
      this.hideSuggestPanel()
      this.isSearched = false
      this.searchResults = []
      return
    }
    // 代际 +1：作废在途的在线联想请求
    this.suggestGen++
    const gen: number = this.suggestGen
    // 历史联想立即展示
    const merged: SearchSuggestion[] = []
    const hist: string[] = this.buildHistorySuggestions(kw)
    for (let i = 0; i < hist.length; i++) {
      merged.push({ text: hist[i], fromHistory: true })
    }
    this.suggestions = merged
    this.showSuggestPanel = true
    // 在线联想防抖拉取
    if (this.suggestTimer !== -1) {
      clearTimeout(this.suggestTimer)
    }
    this.suggestTimer = setTimeout(() => {
      this.suggestTimer = -1
      this.fetchOnlineSuggestions(kw, gen)
    }, 400)
  }

  // 历史记录联想：包含输入词的历史词条
  private buildHistorySuggestions(kw: string): string[] {
    const k: string = kw.toLowerCase()
    const res: string[] = []
    for (let i = 0; i < this.searchHistory.length; i++) {
      const h: string = this.searchHistory[i]
      if (h.toLowerCase().indexOf(k) >= 0 && h.toLowerCase() !== k) {
        res.push(h)
        if (res.length >= 4) {
          break
        }
      }
    }
    return res
  }

  // 在线联想：取搜索结果的歌名/歌手去重
  private async fetchOnlineSuggestions(kw: string, gen: number): Promise<void> {
    try {
      const songs: SongInfo[] = await MusicApi.search(kw, this.selectedSource)
      if (gen !== this.suggestGen || !this.showSuggestPanel) {
        return
      }
      const seen: Set<string> = new Set()
      for (let i = 0; i < this.suggestions.length; i++) {
        seen.add(this.suggestions[i].text.toLowerCase())
      }
      const online: SearchSuggestion[] = []
      for (let i = 0; i < songs.length; i++) {
        const s: SongInfo = songs[i]
        const candidates: string[] = [s.songName, s.artist]
        for (let j = 0; j < candidates.length; j++) {
          const t: string = candidates[j].trim()
          const key: string = t.toLowerCase()
          if (t.length === 0 || key === kw.toLowerCase() || seen.has(key)) {
            continue
          }
          seen.add(key)
          online.push({ text: t, fromHistory: false })
          if (online.length >= 6) {
            break
          }
        }
        if (online.length >= 6) {
          break
        }
      }
      // 历史联想在前，在线联想在后
      this.suggestions = this.suggestions.concat(online)
    } catch (_e) {
      // 忽略：仅保留历史联想
    }
  }

  // 点击联想词：关闭面板并搜索
  private applySuggestion(text: string): void {
    this.hideSuggestPanel()
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer)
      this.searchTimer = -1
    }
    this.keyword = text
    this.doSearch(text)
  }

  private hideSuggestPanel(): void {
    this.showSuggestPanel = false
    this.suggestions = []
    if (this.suggestTimer !== -1) {
      clearTimeout(this.suggestTimer)
      this.suggestTimer = -1
    }
    this.suggestGen++
  }

  // 防抖搜索（关闭联想后保留的输入即搜行为）
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

  // ===== 筛选（自动检测当前结果中的音源） =====

  private getSourceOfSong(song: SongInfo): string {
    if (song.rawData) {
      try {
        const obj: Record<string, Object> = JSON.parse(song.rawData) as Record<string, Object>
        const p = obj['__platform']
        if (typeof p === 'string' && p.length > 0) {
          return p
        }
      } catch (_e) {}
    }
    return song.source
  }

  private buildFilterMenuItems(): FilterMenuItem[] {
    const items: FilterMenuItem[] = []
    items.push({
      value: `全部（${this.searchResults.length}）`,
      action: () => {
        this.sourceFilter = 'all'
        this.lastSourceFilter = 'all'
        this.db.setSetting('searchSourceFilter', 'all')
      }
    })
    // 统计当前结果中各音源数量
    const counts: Map<string, number> = new Map()
    for (let i = 0; i < this.searchResults.length; i++) {
      const src: string = this.getSourceOfSong(this.searchResults[i])
      counts.set(src, (counts.get(src) ?? 0) + 1)
    }
    const names: string[] = []
    counts.forEach((cnt: number, src: string) => {
      names.push(src)
    })
    names.sort((a: string, b: string) => (counts.get(b) ?? 0) - (counts.get(a) ?? 0))
    for (let i = 0; i < names.length; i++) {
      const src: string = names[i]
      items.push({
        value: `${SourceInfo.getAbbr(src)}（${counts.get(src) ?? 0}）`,
        action: () => {
          this.sourceFilter = src
          this.lastSourceFilter = src
          this.db.setSetting('searchSourceFilter', src)
        }
      })
    }
    return items
  }

  /** 按筛选条件展示的结果列表 */
  private getDisplayResults(): SongInfo[] {
    if (this.sourceFilter === 'all') {
      return this.searchResults
    }
    return this.searchResults.filter((s: SongInfo) => this.getSourceOfSong(s) === this.sourceFilter)
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

  // 结果列表 Scroll 的下拉处理：仅当列表位于顶部时才允许触发
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

  // 全源自检：依次测试所有已启用音源，统计可用/不可用
  private async startFullSourceRefresh(): Promise<void> {
    if (this.isRefreshing) return
    this.isRefreshing = true
    this.showPullIndicator = false
    this.refreshProgress = 0
    if (this.keyword.trim().length > 0) {
      this.showResultPill('正在刷新搜索…', false)
      try {
        this.searchResults = await MusicApi.search(this.keyword.trim(), this.selectedSource)
        this.saveToAppStorage()
        this.showResultPill(`刷新完成，${this.searchResults.length} 条结果`, true)
      } catch (_e) {
        this.showResultPill('刷新失败', true)
      }
    } else {
      this.showResultPill('请先输入关键词搜索', true)
    }
    this.isRefreshing = false
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

          // 自检完成后的总结：常驻不消失
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
              this.hideSuggestPanel()
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

  // 搜索结果列表（筛选后）
  @Builder
  SearchResultsContent() {
    if (this.getDisplayResults().length === 0) {
      Column({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(48)
          .fontColor(['#999999'])
          .opacity(0.3)
        if (this.sourceFilter !== 'all' && this.searchResults.length > 0) {
          // 该来源无结果
          Text(`\u300C${SourceInfo.getAbbr(this.sourceFilter)}\u300D\u6765\u6E90\u6682\u65E0\u6B4C\u66F2`)
            .fontSize(16)
            .fontColor(this.themeTextPrimary)
            .fontWeight(FontWeight.Medium)
          Text('\u70B9\u51FB\u641C\u7D22\u680F\u53F3\u4FA7\u201C\u7B5B\u9009\u201D\u5207\u56DE\u201C\u5168\u90E8\u201D')
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
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding(40)
    } else {
      Scroll(this.scroller) {
        Column({ space: 8 }) {
          if (this.refreshSummaryVisible && this.refreshSummary.length > 0) {
            // 自检完成后的总结
            Text(this.refreshSummary)
              .fontSize(12)
              .fontColor(this.themeTextSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .height(18)
              .padding({ left: 4 })
          }

          // Song list - 单击播放
          ForEach(this.getDisplayResults(), (song: SongInfo) => {
            SongCard({
              song: song,
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
      .height('100%')
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

    console.info(`[QinseTab] doSearch: keyword="${kw}", source=${this.selectedSource}`)

    try {
      this.searchResults = await MusicApi.search(kw, this.selectedSource)
      console.info(`[QinseTab] search done: ${this.searchResults.length} results`)
      if (this.searchResults.length === 0) {
        this.searchError = MusicApi.lastError || '未找到相关歌曲'
      }
    } catch (e) {
      console.error('[QinseTab] search error:', e)
      this.searchResults = []
      this.searchError = '搜索异常：' + String(e)
    }

    // 自动定位跳转开启时沿用上次选择的音源筛选（新结果中无该源则回退"全部"），否则重置"全部"
    this.applyRememberedFilter()

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
    this.getUIContext().getPromptAction().showToast({ message: '\u641C\u7D22\u8BB0\u5F55\u5DF2\u6E05\u7A7A', duration: 1500 })
  }

  // V2.0.8：单歌播放（带失败自动换源）
  // 先立即切换曲目与队列（UI/歌词即时跟随）；取链/起播失败时在已有搜索结果内
  // 逐个换源重播同一首歌（不改变歌名），每一步通过底部弹窗可视化。
  private async playSong(song: SongInfo): Promise<void> {
    const queue: SongInfo[] = this.searchResults
    const idx: number = queue.indexOf(song)
    PlayerStore.play(song, queue, idx >= 0 ? idx : 0)

    // V2.1.9 自动换源关闭：不做候选换源，直接取链起播；失败提示后自动跳过下一首
    if (AppStorage.get<boolean>('autoSourceSwitch') === false) {
      this.sessionToken++
      this.sessionSong = null
      this.sessionCandidates = []
      const player = AudioPlayer.getInstance()
      player.endRetrySession()
      let directUrl: string = song.playUrl
      if (!directUrl) {
        directUrl = await MusicApi.getPlayUrl(song.songId, song.source, song)
      }
      if (!directUrl) {
        SourceStatus.markUnplayable(song.source)
        this.showResultPill(`「${song.songName}」取链失败，已跳过`, true)
        player.playNext()
        return
      }
      song.playUrl = directUrl
      player.setCurrentSong(song)
      await player.play(directUrl)
      SourceStatus.markPlayable(song.source)
      this.showResultPill(`「${song.songName}」播放成功`, true)
      if (AppStorage.get<boolean>('autoJumpDetail') === true) {
        PlayerStore.showFullPlayer()
      }
      return
    }

    // 开启新的换源会话：作废旧会话，注册错误接管回调
    this.sessionToken++
    const token: number = this.sessionToken
    this.sessionSong = song
    this.sessionCursor = 0
    this.sessionAttemptFailed = false
    this.sessionShownKey = song.source + '|' + song.songId
    this.sessionCandidates = this.buildSourceCandidates(song)

    const player = AudioPlayer.getInstance()
    player.beginRetrySession(song.source + '|' + song.songId, (message: string): void => {
      this.onSessionPlayError(token)
    })

    this.runSourceFallback(token)
  }

  // 组装备选音源列表：首位为原曲，其后为搜索结果中同名同歌手的其它音源（去重）
  private buildSourceCandidates(song: SongInfo): SongInfo[] {
    const candidates: SongInfo[] = [song]
    for (let i = 0; i < this.searchResults.length; i++) {
      const c: SongInfo = this.searchResults[i]
      if (c.source === song.source && c.songId === song.songId) {
        continue
      }
      if (!this.isSameSongForSwitch(c, song)) {
        continue
      }
      let dup: boolean = false
      for (let j = 0; j < candidates.length; j++) {
        if (candidates[j].source === c.source) {
          dup = true
          break
        }
      }
      if (!dup) {
        candidates.push(c)
      }
    }
    return candidates
  }

  // 换源匹配：歌名一致（忽略大小写/首尾空白），歌手互相包含（为空则放行）
  private isSameSongForSwitch(a: SongInfo, b: SongInfo): boolean {
    const na: string = a.songName.trim().toLowerCase()
    const nb: string = b.songName.trim().toLowerCase()
    if (na !== nb) {
      return false
    }
    const aa: string = a.artist.trim().toLowerCase()
    const ab: string = b.artist.trim().toLowerCase()
    if (aa.length === 0 || ab.length === 0) {
      return true
    }
    return aa.includes(ab) || ab.includes(aa)
  }

  // 换源会话内的播放错误回调（由 AudioPlayer 在会话曲目出错时调用）
  private onSessionPlayError(token: number): void {
    if (token !== this.sessionToken) {
      return // 旧会话的错误：忽略
    }
    if (token === this.sessionBusyToken) {
      // 重试循环正在运行：置失败标记，由循环在起播宽限期后读取
      this.sessionAttemptFailed = true
      return
    }
    // 之前已成功起播、播放中途失败：从下一个候选源继续换源
    this.sessionCursor++
    this.runSourceFallback(token)
  }

  // 换源重试主循环：从 sessionCursor 起依次尝试候选音源，直至起播成功或全部失败
  private async runSourceFallback(token: number): Promise<void> {
    if (token !== this.sessionToken || token <= this.sessionBusyToken) {
      return // 会话已过期，或已有更新的循环在运行
    }
    this.sessionBusyToken = token
    const player = AudioPlayer.getInstance()
    const origin: SongInfo | null = this.sessionSong
    try {
      while (token === this.sessionToken && this.sessionCursor < this.sessionCandidates.length) {
        const candidate: SongInfo = this.sessionCandidates[this.sessionCursor]
        const isOrigin: boolean = this.sessionCursor === 0
        const label: string = SourceInfo.getName(candidate.source)

        // 步骤1：取链
        this.showResultPill(`正在获取「${label}」播放链接…`, false)
        let playUrl: string = candidate.playUrl
        if (!playUrl) {
          playUrl = await MusicApi.getPlayUrl(candidate.songId, candidate.source, candidate)
        }
        if (token !== this.sessionToken) {
          return
        }
        if (!playUrl) {
          SourceStatus.markUnplayable(candidate.source)
          if (this.sessionCursor >= this.sessionCandidates.length - 1) {
            break // 最后一个候选也取链失败
          }
          this.showResultPill(`「${label}」取链失败，准备换源…`, false)
          this.sessionCursor++
          continue
        }
        candidate.playUrl = playUrl

        // 步骤2：起播（曲目信息始终保持原歌，仅换播放链接）
        this.showResultPill(isOrigin ? `正在通过「${label}」播放…` : `已换源至「${label}」，正在播放…`, false)
        if (origin !== null) {
          player.setCurrentSong(origin)
        }
        this.sessionAttemptFailed = false
        await player.play(playUrl)
        if (token !== this.sessionToken) {
          return
        }

        // 步骤3：起播宽限期（2秒），捕获“play() 成功但随即出错”的情况
        await this.waitMoment(2000)
        if (token !== this.sessionToken) {
          return
        }
        if (this.sessionAttemptFailed) {
          // 起播失败：标记不可用并换下一个源
          if (this.sessionCursor >= this.sessionCandidates.length - 1) {
            break
          }
          this.showResultPill(`「${label}」播放失败，准备换源…`, false)
          this.sessionCursor++
          continue
        }

        // 播放成功：标记该音源可用，保留会话以接管后续中途失败
        SourceStatus.markPlayable(candidate.source)
        // V2.1.8 换源成功：把新源的播放身份过继给原曲（歌名/歌手/封面保持不变），
        // 使来源徽章与歌词/收藏取数都切换到实际可用的新源
        if (!isOrigin && origin !== null) {
          const prevSource: string = origin.source
          const prevSongId: string = origin.songId
          const shown: SongInfo | undefined = PlayerStore.getCurrentTrack()
          if (shown !== undefined && shown.source + '|' + shown.songId === this.sessionShownKey) {
            origin.source = candidate.source
            origin.songId = candidate.songId
            origin.rawData = candidate.rawData
            origin.playUrl = playUrl
            if (candidate.lyric !== undefined && candidate.lyric.length > 0) {
              origin.lyric = candidate.lyric
            }
            if (candidate.albumId !== undefined) {
              origin.albumId = candidate.albumId
            }
            if (candidate.artistId !== undefined) {
              origin.artistId = candidate.artistId
            }
            if (candidate.hash !== undefined) {
              origin.hash = candidate.hash
            }
            if (candidate.mid !== undefined) {
              origin.mid = candidate.mid
            }
            this.sessionShownKey = origin.source + '|' + origin.songId
            // 无条件克隆刷新当前曲目（同曲守卫会拦截身份已变的曲目）
            PlayerStore.forceRefreshCurrentTrack(origin)
            // 同步到操作面板选中的歌曲引用（若为独立克隆对象），确保随后「加入歌单」保存的是实际可用的新源
            if (this.selectedSong !== null && this.selectedSong !== undefined &&
              this.selectedSong.source === prevSource && this.selectedSong.songId === prevSongId) {
              this.selectedSong.source = origin.source
              this.selectedSong.songId = origin.songId
              this.selectedSong.rawData = origin.rawData
              this.selectedSong.playUrl = origin.playUrl
              this.selectedSong.coverUrl = origin.coverUrl
            }
            // 重注册换源会话：错误接管按 source|songId 匹配，身份已变需同步更新
            player.beginRetrySession(this.sessionShownKey, (message: string): void => {
              this.onSessionPlayError(token)
            })
            // 歌词改从新源获取（旧源接口可能已不可用）
            PlayerStore.loadLyricsAsync(origin)
            // 重赋值触发搜索结果行的来源徽章刷新
            this.searchResults = this.searchResults.slice()
          }
        }
        this.sessionCursor++
        this.showResultPill(`「${origin?.songName ?? candidate.songName}」播放成功`, true)
        // 自动详情：点击歌曲后同步打开详情页
        if (AppStorage.get<boolean>('autoJumpDetail') === true) {
          PlayerStore.showFullPlayer()
        }
        return
      }

      // 全部候选源尝试完毕仍失败：结束会话并停止播放
      this.showResultPill('已尝试所有音源，均无法播放', true)
      await player.pause()
      player.endRetrySession()
      this.sessionSong = null
      this.sessionCandidates = []
    } finally {
      if (this.sessionBusyToken === token) {
        this.sessionBusyToken = -1
      }
    }
  }

  private waitMoment(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms)
    })
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
    this.getUIContext().getPromptAction().showToast({ message, duration: 2000 })
  }
}
