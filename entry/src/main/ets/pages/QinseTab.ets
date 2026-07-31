// SHMY 搜索 Tab - 搜索与播放
// QinseTab.ets - V1.0.8.4 搜索记忆+历史
import { SongInfo } from '../model/MusicModel'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { AudioPlayer } from '../utils/AudioPlayer'
import { MusicApi } from '../utils/MusicApi'
import { PlayerStore } from '../utils/PlayerStore'
import { SongCard } from '../components/SongCard'
import { SearchBar } from '../components/SearchBar'
import { SourceManager } from '../utils/SourceManager'
import { SelfHostedApi } from '../utils/SelfHostedApi'

import { SongActionSheet } from '../components/SongActionSheet'
import { promptAction, uiMaterial } from '@kit.ArkUI'

interface SourceOption {
  label: string
  value: string
}

@Component
export struct QinseTab {
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_bg') themeBg: string = '#F8F8FA'
  @StorageProp('theme_cardBg') themeCardBg: string = '#F5F5F5'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'

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

  // 搜索防抖定时器
  private searchTimer: number = -1

  // Source dropdown
  @State showSourceDropdown: boolean = false
  @State sourceOptions: SourceOption[] = []

  // 搜索模式标记
  @State apiModeLabel: string = ''

  private db: DatabaseHelper = DatabaseHelper.getInstance()

  async aboutToAppear() {
    this.apiModeLabel = MusicApi.isSelfHostedMode() ? '自建API' : 'JSON源'
    // 1. 立即从 AppStorage 恢复搜索结果（无需等待 DB）
    const savedKeyword = AppStorage.get('qinseKeyword') as string | undefined
    const savedResults = AppStorage.get('qinseSearchResults') as SongInfo[] | undefined
    const savedIsSearched = AppStorage.get('qinseIsSearched') as boolean | undefined
    if (savedResults && savedResults.length > 0 && savedIsSearched) {
      this.keyword = savedKeyword ?? ''
      this.searchResults = savedResults
      this.isSearched = true
    }
    // 2. 完整加载源列表（确保筛选器可用）
    await this.loadSourceOptions()
    this.loadSearchMemory()
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
    this.sourceOptions = options
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
  }

  build() {
    Stack() {
      // === Main content (bottom layer, never moves) ===
      Column() {
        // Search bar
        Row({ space: 12 }) {
          // Search input with icon button
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
          .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
          .borderRadius(20)
          .padding({ right: 8 })

          // Source dropdown button (筛选选择器)
          Row({ space: 4 }) {
            Text(this.getSourceLabel(this.selectedSource))
              .fontSize(14)
              .fontColor(this.themeTextPrimary)

            SymbolGlyph(this.showSourceDropdown ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
              .fontSize(14)
              .fontColor([this.themeTextSecondary])
          }
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
          .borderRadius(20)
          .onClick(() => {
            this.showSourceDropdown = !this.showSourceDropdown
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

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
      .backgroundColor(this.themeBg)

      // === Floating dropdown overlay (top layer, covers content below) ===
      if (this.showSourceDropdown) {
        Column({ space: 4 }) {
          ForEach(this.sourceOptions, (option: SourceOption) => {
            Row() {
              Text(option.label)
                .fontSize(13)
                .fontColor(this.selectedSource === option.value ? this.themePrimary : this.themeTextPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              if (this.selectedSource === option.value) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(13)
                  .fontColor([this.themePrimary])
                  .flexShrink(0)
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(this.selectedSource === option.value ? '#E3F2FD' : Color.White)
            .borderRadius(8)
            .justifyContent(FlexAlign.SpaceBetween)
            .onClick(() => {
              this.selectedSource = option.value
              this.showSourceDropdown = false
              if (this.keyword.trim().length > 0) {
                this.doSearch(this.keyword.trim())
              }
            })
          })
        }
        .width(140)
        .backgroundColor(Color.White)
        .borderRadius(12)
        .shadow({ radius: 12, color: '#00000020', offsetY: 4 })
        .padding(6)
        .position({ right: 16, top: 56 })
      }

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
    if (this.searchResults.length === 0) {
      Column({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(48)
          .fontColor(['#999999'])
          .opacity(0.3)
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
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding(40)
      .layoutWeight(1)
    } else {
      Scroll() {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text(`\u627E\u5230 ${this.searchResults.length} \u9996\u6B4C\u66F2`)
              .fontSize(13)
              .fontColor(this.themeTextSecondary)

            Text(this.apiModeLabel)
              .fontSize(10)
              .fontColor(Color.White)
              .backgroundColor(this.apiModeLabel === '自建API' ? '#007DFF' : '#FF9800')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(8)
          }
          .width('100%')
          .padding({ left: 4, bottom: 4 })

          // 双击播放提示
          Text('\u53CC\u51FB\u64AD\u653E \u00B7 \u957F\u6309\u66F4\u591A\u64CD\u4F5C')
            .fontSize(11)
            .fontColor(this.themeTextSecondary)
            .width('100%')
            .padding({ left: 4, bottom: 8 })

          // Song list - 使用双击播放模式
          ForEach(this.searchResults, (song: SongInfo) => {
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

    const mode = MusicApi.isSelfHostedMode() ? '自建API' : 'JSON源'
    console.info(`[QinseTab] doSearch: keyword="${kw}", source=${this.selectedSource}, mode=${mode}`)

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