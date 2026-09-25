import { MusicApi } from '../utils/MusicApi'
import { SourceInfo } from '../model/MusicModel'
import type { SongInfo } from '../model/MusicModel'
import { CoverImage } from '../components/CoverImage'
import { HdsTabs, HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit'

interface RecommendCategory {
  title: string
  keyword: string
  icon: Resource
}

@Component
export struct TuijianTab {
  @StorageProp('theme_bg') themeBg: string = '#F5F5F7'
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'
  @StorageProp('theme_cardBg') themeCardBg: string = '#FFFFFF'
  @StorageProp('theme_placeholder') themePlaceholder: string = '#E0E0E0'
  @StorageProp('isDarkMode') isDarkMode: boolean = false
  @StorageProp('theme_bgImageName') themeBgImageName: string = ''
  @State currentCategoryIndex: number = 0
  // 各分类懒加载缓存：下标与 categories 对应
  @State categoryData: SongInfo[][] = []
  @State loadingCategories: boolean[] = []

  private categories: RecommendCategory[] = [
    { title: '热门', keyword: '2024热门歌曲', icon: $r('sys.symbol.flame') },
    { title: '新歌', keyword: '2024新歌', icon: $r('sys.symbol.plus') },
    { title: '流行', keyword: '流行歌曲', icon: $r('sys.symbol.star') },
    { title: '经典', keyword: '经典老歌', icon: $r('sys.symbol.clock') },
    { title: '民谣', keyword: '民谣', icon: $r('sys.symbol.play') },
    { title: '摇滚', keyword: '摇滚', icon: $r('sys.symbol.bolt') },
    { title: '电子', keyword: '电子音乐', icon: $r('sys.symbol.waveform') },
    { title: 'R&B', keyword: 'R&B', icon: $r('sys.symbol.heart') },
  ]

  aboutToAppear(): void {
    const count: number = this.categories.length
    for (let i = 0; i < count; i++) {
      this.categoryData.push([])
      this.loadingCategories.push(false)
    }
    this.loadCategorySongs(0)
  }

  private async loadCategorySongs(index: number): Promise<void> {
    if (index < 0 || index >= this.categories.length) {
      return
    }
    // 已缓存或加载中则跳过
    if (this.loadingCategories[index] || this.categoryData[index].length > 0) {
      return
    }
    this.loadingCategories[index] = true
    try {
      const keyword = this.categories[index].keyword
      const songs = await MusicApi.search(keyword)
      const list = songs.slice(0, 20)
      this.categoryData[index] = list
    } catch (_e) {
      this.categoryData[index] = []
    }
    this.loadingCategories[index] = false
  }

  private playSong(song: SongInfo): void {
    AppStorage.setOrCreate('pendingPlaySong', song)
    AppStorage.setOrCreate('pendingPlayRequest', Date.now())
  }

  build() {
    // V2.1.9：搜索栏迁入 HdsNavDestination 标题栏 bottomBuilder（HDS 官方模式：自定义区放搜索框），
    // 栏体静止透明、样式与歌单详情页一致（GRADIENT_BLUR + systemMaterialEffect）
    HdsNavDestination() {
      Column() {
        // 分类标签 HdsTabs：顶部分类栏可横向滚动，各分类懒加载缓存
        HdsTabs() {
          ForEach(this.categories, (cat: RecommendCategory, index: number) => {
            TabContent() {
              this.CategoryContent(index)
            }
            .tabBar(this.CategoryTabBar(cat, index))
          }, (cat: RecommendCategory) => cat.title)
        }
        .barPosition(BarPosition.Start)
        // V2.1.9：margin=TabBar 左右边距——首/末标签与搜索栏、内容区 16vp 对齐
        .barMode(BarMode.Scrollable, { margin: 16 })
        .onChange((index: number) => {
          this.currentCategoryIndex = index
          this.loadCategorySongs(index)
        })
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      // V2.1.9：为浮动标题栏让位（stackBuilder 56vp + 8vp 间隙）
      .padding({ top: 64 })
      .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
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
  }

  @Builder SearchBar() {
    Row() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(14)
          .fontColor([$r('sys.color.font_primary')])
          .margin({ left: 10 })
        Text('搜索音乐')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.themeCardBg)
      .padding({ right: 10 })
    }
    .width('100%')
    .height(56)
    // V2.1.9：标题栏 stackBuilder 行高 56vp，左右 16vp 与下方分类标签、内容区对齐
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      // 跳转到搜索 Tab（由 Index 监听信号切换）
      AppStorage.setOrCreate('jumpToSearchTab', Date.now())
    })
  }

  @Builder CategoryTabBar(cat: RecommendCategory, index: number) {
    Row({ space: 6 }) {
      SymbolGlyph(cat.icon)
        .fontSize(13)
        .fontColor([index === this.currentCategoryIndex ? Color.White : this.themeTextPrimary])
      Text(cat.title)
        .fontSize(14)
        .fontColor(index === this.currentCategoryIndex ? Color.White : this.themeTextPrimary)
        .fontWeight(index === this.currentCategoryIndex ? FontWeight.Medium : FontWeight.Regular)
    }
    .height(32)
    // V2.1.9：标签背景原本紧贴相邻，增加标签间距使其更美观（首/末标签边距由 barMode margin 统一控制）
    .margin({ left: index === 0 ? 0 : 6, right: index === this.categories.length - 1 ? 0 : 6 })
    .padding({ left: 12, right: 12, top: 0, bottom: 0 })
    .justifyContent(FlexAlign.Center)
    .borderRadius(16)
    .backgroundColor(index === this.currentCategoryIndex ? this.themePrimary : this.themeCardBg)
  }

  @Builder CategoryContent(index: number) {
    Column() {
      if (this.loadingCategories[index]) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(this.themePrimary)
          Text('加载中…')
            .fontSize(13)
            .fontColor(this.themeTextSecondary)
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.categoryData[index].length === 0) {
        Column() {
          Text('暂无歌曲')
            .fontSize(14)
            .fontColor(this.themeTextSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            ForEach(this.categoryData[index], (song: SongInfo) => {
              this.SongItem(song)
            }, (song: SongInfo) => `${song.songId}_${song.source}`)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 100 })
        }
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder SongItem(song: SongInfo) {
    Row({ space: 12 }) {
      CoverImage({
        url: song.coverUrl,
        coverWidth: 48,
        coverHeight: 48,
        radius: 8
      })
      .flexShrink(0)

      Column({ space: 2 }) {
        Text(song.songName)
          .fontSize(15)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 6 }) {
          Text(song.artist)
            .fontSize(12)
            .fontColor(this.themeTextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(SourceInfo.getAbbr(song.source))
            .fontSize(9)
            .fontColor(Color.White)
            .backgroundColor(SourceInfo.getColor(song.source))
            .borderRadius(3)
            .padding({ left: 3, right: 3, top: 1, bottom: 1 })
            .flexShrink(0)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      this.playSong(song)
    })
  }
}
