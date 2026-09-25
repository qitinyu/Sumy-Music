// 音迹 Tab - 听歌记录页（顶部统计卡片为真实数据，榜单/最近播放仍为示例数据）
// YinjiTab.ets

import { DatabaseHelper } from '../database/DatabaseHelper'
import { AccountManager } from '../utils/AccountManager'
import { ListeningLevelManager } from '../utils/ListeningLevelManager'

interface RecentItem {
  name: string
  singer: string
  time: string
}

interface RankItem {
  name: string
  sub: string
  count: string
}

const RANK_TABS: string[] = ['最爱音乐', '最爱歌手', '最爱专辑']
const TIME_TABS: string[] = ['按周', '按月']

@Component
export struct YinjiTab {
  @StorageProp('theme_bg') themeBg: string = '#F5F5F7'
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_primaryLight') themePrimaryLight: string = '#E0F0FF'
  @StorageProp('theme_cardBg') themeCardBg: string = '#FFFFFF'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'
  @StorageProp('theme_divider') themeDivider: string = '#E8E8E8'
  @StorageProp('theme_bgImageName') themeBgImageName: string = ''

  // ==== 我的页听歌统计卡片同款数据（V2.0.9.3：复制到音迹顶部；与我的页同源同值） ====
  @State playlistCount: number = 0
  @State listenTime: number = 0      // 听歌时长（分钟）
  @State listenSongs: number = 0     // 听歌曲目数
  // 音迹 Tab 可见信号（时间戳）：切换到音迹时刷新统计数据
  @StorageProp('yinjiTabVisible') @Watch('onTabVisibleSignal') tabVisibleSignal: number = 0

  private db: DatabaseHelper = DatabaseHelper.getInstance()

  // ==== 示例统计数据（先做样式，后续替换为真实听歌记录数据源） ====
  @State totalMin: number = 4860       // 累计听歌分钟
  @State totalSongs: number = 1286     // 累计听歌首数（去重）
  @State listenDays: number = 96       // 累计听歌天数
  @State weekValues: number[] = [42, 78, 35, 90, 66, 120, 75]  // 近7天每日听歌分钟
  @State weekLabels: string[] = ['一', '二', '三', '四', '五', '六', '日']

  // ==== 听歌榜数据（示例，前三红色渐弱字体） ====
  // 时间维度（timeTab）全局同步作用于三个子页：0按周 1按月
  @State rankTab: number = 0        // 0最爱音乐 1最爱歌手 2最爱专辑
  @State timeTab: number = 0        // 0按周 1按月（全局生效）
  @State favSongsWeek: RankItem[] = [
    { name: '晴天', sub: '周杰伦', count: '32次' },
    { name: '泡沫', sub: '邓紫棋', count: '28次' },
    { name: '稻香', sub: '周杰伦', count: '25次' },
    { name: '光年之外', sub: '邓紫棋', count: '20次' },
    { name: '夜曲', sub: '周杰伦', count: '18次' },
  ]
  @State favSongsMonth: RankItem[] = [
    { name: '晴天', sub: '周杰伦', count: '128次' },
    { name: '稻香', sub: '周杰伦', count: '106次' },
    { name: '泡沫', sub: '邓紫棋', count: '97次' },
    { name: '光年之外', sub: '邓紫棋', count: '85次' },
    { name: '夜曲', sub: '周杰伦', count: '79次' },
  ]
  @State favArtistsWeek: RankItem[] = [
    { name: '周杰伦', sub: '播放 6 首', count: '112次' },
    { name: '邓紫棋', sub: '播放 5 首', count: '98次' },
    { name: '林俊杰', sub: '播放 4 首', count: '76次' },
    { name: '陈奕迅', sub: '播放 3 首', count: '62次' },
    { name: '薛之谦', sub: '播放 3 首', count: '51次' },
  ]
  @State favArtistsMonth: RankItem[] = [
    { name: '周杰伦', sub: '播放 12 首', count: '486次' },
    { name: '邓紫棋', sub: '播放 8 首', count: '352次' },
    { name: '林俊杰', sub: '播放 7 首', count: '298次' },
    { name: '陈奕迅', sub: '播放 6 首', count: '240次' },
    { name: '薛之谦', sub: '播放 5 首', count: '196次' },
  ]
  @State favAlbumsWeek: RankItem[] = [
    { name: '叶惠美', sub: '周杰伦', count: '12次' },
    { name: '摩天动物园', sub: '邓紫棋', count: '10次' },
    { name: '跨时代', sub: '周杰伦', count: '9次' },
    { name: '因你而在', sub: '林俊杰', count: '8次' },
    { name: 'U87', sub: '陈奕迅', count: '6次' },
  ]
  @State favAlbumsMonth: RankItem[] = [
    { name: '叶惠美', sub: '周杰伦', count: '42次' },
    { name: '摩天动物园', sub: '邓紫棋', count: '35次' },
    { name: '跨时代', sub: '周杰伦', count: '30次' },
    { name: '因你而在', sub: '林俊杰', count: '27次' },
    { name: 'U87', sub: '陈奕迅', count: '22次' },
  ]

  private recent: RecentItem[] = [
    { name: '晴天', singer: '周杰伦', time: '今天 09:20' },
    { name: '稻香', singer: '周杰伦', time: '今天 08:44' },
    { name: '泡沫', singer: '邓紫棋', time: '昨天 22:10' },
    { name: '光年之外', singer: '邓紫棋', time: '昨天 21:35' },
    { name: '海底', singer: '一支榴莲', time: '昨天 20:02' },
  ]

  // 下拉刷新状态
  @State isRefreshing: boolean = false

  aboutToAppear(): void {
    this.loadMyStats()
  }

  // 音迹 Tab 可见：刷新与我的页同步的听歌统计
  private onTabVisibleSignal(): void {
    this.loadMyStats()
  }

  // 与我的页 StatsCard 同源同值：登录读取真实数据，未登录显示 0
  private async loadMyStats() {
    const savedUser = await AccountManager.loadSavedUserInfo()
    if (!savedUser) {
      this.playlistCount = 0
      this.listenSongs = 0
      this.listenTime = 0
      return
    }
    const playlists = await this.db.getPlaylists()
    this.playlistCount = playlists.length
    const allSongs = await this.db.getAllSongs()
    this.listenSongs = allSongs.length
    const manager = ListeningLevelManager.getInstance()
    await manager.init()
    this.listenTime = Math.floor(manager.getTotalSeconds() / 60)
  }

  // 下拉刷新：刷新顶部统计卡片数据
  private async refreshData(): Promise<void> {
    await this.loadMyStats()
    this.isRefreshing = false
  }

  // 返回当前选中的榜单（时间维度全局同步作用于三个子页）
  private currentRank(): RankItem[] {
    if (this.rankTab === 0) {
      return this.timeTab === 0 ? this.favSongsWeek : this.favSongsMonth
    } else if (this.rankTab === 1) {
      return this.timeTab === 0 ? this.favArtistsWeek : this.favArtistsMonth
    }
    return this.timeTab === 0 ? this.favAlbumsWeek : this.favAlbumsMonth
  }

  // 前三名红色逐渐减弱，第四五名用主题正文色
  private rankColor(i: number): string {
    if (i === 0) {
      return '#FF4444'
    } else if (i === 1) {
      return '#FF7A6B'
    } else if (i === 2) {
      return '#FFB3A8'
    }
    return this.themeTextPrimary
  }

  private maxWeek(): number {
    let m: number = 1
    for (let i: number = 0; i < this.weekValues.length; i++) {
      if (this.weekValues[i] > m) {
        m = this.weekValues[i]
      }
    }
    return m
  }

  private barHeight(v: number): number {
    return Math.max(8, Math.round(v / this.maxWeek() * 90))
  }

  private formatDuration(min: number): string {
    if (min < 60) {
      return `${min}`
    }
    const h: number = Math.floor(min / 60)
    const m: number = Math.round(min % 60)
    return m > 0 ? `${h}时${m}分` : `${h}时`
  }

  build() {
    Refresh({ refreshing: $$this.isRefreshing }) {
      Scroll() {
        Column({ space: 16 }) {
          // V2.1.9：页头「音迹」移入顶部沉浸标题栏，此处不再重复展示

          // 我的页听歌统计卡片同款（V2.0.9.3：歌单数 | 听歌时长 | 听歌曲目）
          this.TopStatsCard()

          // 顶部统计卡片
          Row({ space: 10 }) {
            this.StatCard('累计听歌', this.formatDuration(this.totalMin), '分钟(约)', this.themePrimary)
            this.StatCard('听过歌曲', `${this.totalSongs}`, '首(去重)', this.themePrimaryLight)
          }
          .width('100%')

          // 听歌天数横幅
          Row() {
            Column({ space: 4 }) {
              Text(`${this.listenDays}`)
                .fontSize(30)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.themePrimary)
              Text('累计听歌天数')
                .fontSize(12)
                .fontColor(this.themeTextSecondary)
            }
            .alignItems(HorizontalAlign.Center)
            .layoutWeight(1)

            Column()
              .width(1)
              .height(40)
              .backgroundColor(this.themeDivider)

            Column({ space: 4 }) {
              Text('平均')
                .fontSize(12)
                .fontColor(this.themeTextSecondary)
              Text(`${Math.max(1, Math.round(this.totalMin / Math.max(1, this.listenDays)))} 分钟/天`)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themeTextPrimary)
            }
            .alignItems(HorizontalAlign.Center)
            .layoutWeight(1)
          }
          .width('100%')
          .backgroundColor(this.themeCardBg)
          .borderRadius(16)
          .padding({ top: 18, bottom: 18, left: 16, right: 16 })

          // 近7天听歌趋势
          Column({ space: 10 }) {
            Row() {
              Text('近7天听歌趋势')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themeTextPrimary)
              Text('(分钟/天)')
                .fontSize(11)
                .fontColor(this.themeTextSecondary)
            }
            .width('100%')

            Row() {
              ForEach(this.weekValues, (v: number, i: number) => {
                Column({ space: 6 }) {
                  Text(`${v}`)
                    .fontSize(9)
                    .fontColor(this.themeTextSecondary)
                  Column()
                    .width(14)
                    .height(this.barHeight(v))
                    .borderRadius(7)
                    .backgroundColor(i === this.weekValues.length - 1 ? this.themePrimary : this.themePrimaryLight)
                  Text(this.weekLabels[i])
                    .fontSize(10)
                    .fontColor(i === this.weekValues.length - 1 ? this.themePrimary : this.themeTextSecondary)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)
              }, (v: number, i: number) => `${v}-${i}`)
            }
            .width('100%')
            .alignItems(VerticalAlign.Bottom)
          }
          .width('100%')
          .backgroundColor(this.themeCardBg)
          .borderRadius(16)
          .padding(16)

          // ======================== 听歌榜 ========================
          Column({ space: 12 }) {
            Row() {
              Text('听歌榜')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themeTextPrimary)

              // 时间维度切换：pv 图标，点击弹出按周/按月，全局同步作用于三个子页
              Stack() {
                Column()
                  .width(26)
                  .height(26)
                  .borderRadius(13)
                  .backgroundColor(this.themePrimaryLight)
                Image($rawfile('pv.svg'))
                  .width(14)
                  .height(14)
              }
              .width(26)
              .height(26)
              .alignContent(Alignment.Center)
              .margin({ left: 8 })
              .bindMenu([
                { value: '按周', action: () => { this.timeTab = 0 } },
                { value: '按月', action: () => { this.timeTab = 1 } }
              ])

              Text(this.timeTab === 0 ? '按周' : '按月')
                .fontSize(11)
                .fontColor(this.themePrimary)
                .margin({ left: 2 })

              Blank()

              Text('前5名')
                .fontSize(11)
                .fontColor(this.themeTextSecondary)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            // 顶部三格：最爱音乐 / 最爱歌手 / 最爱专辑（拉宽等分）
            Row({ space: 6 }) {
              ForEach(RANK_TABS, (label: string, i: number) => {
                Text(label)
                  .fontSize(13)
                  .fontColor(i === this.rankTab ? Color.White : this.themeTextSecondary)
                  .backgroundColor(i === this.rankTab ? this.themePrimary : this.themePrimaryLight)
                  .borderRadius(16)
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
                  .height(32)
                  .onClick(() => {
                    this.rankTab = i
                  })
              }, (label: string, i: number) => `${label}-${i}`)
            }
            .width('100%')

            // 内容区：各自榜单前5，前三红色渐弱
            Column({ space: 0 }) {
              ForEach(this.currentRank(), (item: RankItem, i: number) => {
                if (i < 5) {
                  Row({ space: 12 }) {
                    Text(`${i + 1}`)
                      .fontSize(16)
                      .fontWeight(i < 3 ? FontWeight.Bold : FontWeight.Medium)
                      .fontColor(this.rankColor(i))
                      .width(28)
                      .textAlign(TextAlign.Center)

                    Column({ space: 2 }) {
                      Text(item.name)
                        .fontSize(15)
                        .fontWeight(i < 3 ? FontWeight.Medium : FontWeight.Normal)
                        .fontColor(this.rankColor(i))
                      Text(item.sub)
                        .fontSize(11)
                        .fontColor(this.themeTextSecondary)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Text(item.count)
                      .fontSize(12)
                      .fontColor(this.themeTextSecondary)
                  }
                  .width('100%')
                  .padding({ top: 9, bottom: 9 })

                  if (i < 4) {
                    Divider()
                      .color(this.themeDivider)
                      .strokeWidth(0.5)
                  }
                }
              }, (item: RankItem, i: number) => `${item.name}-${item.count}-${i}`)
            }
            .width('100%')
          }
          .width('100%')
          .backgroundColor(this.themeCardBg)
          .borderRadius(16)
          .padding(16)

          // 最近播放记录
          Column({ space: 10 }) {
            Text('最近播放')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themeTextPrimary)
              .width('100%')

            ForEach(this.recent, (item: RecentItem, i: number) => {
              Row({ space: 12 }) {
                Stack() {
                  Column()
                    .width(40)
                    .height(40)
                    .borderRadius(12)
                    .backgroundColor(this.themePrimaryLight)
                  Text(`${i + 1}`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.themePrimary)
                }
                .width(40)
                .height(40)
                .alignContent(Alignment.Center)

                Column({ space: 3 }) {
                  Text(item.name)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.themeTextPrimary)
                  Text(`${item.singer} · ${item.time}`)
                    .fontSize(11)
                    .fontColor(this.themeTextSecondary)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })

              // 分隔线（最后一项不显示）
              if (i < this.recent.length - 1) {
                Divider()
                  .color(this.themeDivider)
                  .strokeWidth(0.5)
              }
            }, (item: RecentItem, i: number) => `${item.name}-${item.time}-${i}`)
          }
          .width('100%')
          .backgroundColor(this.themeCardBg)
          .borderRadius(16)
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })

          Text('此处为样式初版，示例数据，待接入真实听歌记录')
            .fontSize(11)
            .fontColor(this.themeTextSecondary)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 4 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 100 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .onRefreshing(() => {
      this.refreshData()
    })
    .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
  }

  // ===== 我的页听歌统计卡片同款 =====
  @Builder
  TopStatsCard() {
    Row({ space: 0 }) {
      Column({ space: 2 }) {
        Text(`${this.playlistCount}`)
          .fontSize(28)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Bold)
        Text('歌单数')
          .fontSize(12)
          .fontColor(this.themeTextSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      Divider()
        .width(1)
        .height(40)
        .color(this.themeDivider)

      Column({ space: 2 }) {
        Text(`${this.listenTime}`)
          .fontSize(28)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Bold)
        Text('听歌时长(分钟)')
          .fontSize(12)
          .fontColor(this.themeTextSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      Divider()
        .width(1)
        .height(40)
        .color(this.themeDivider)

      Column({ space: 2 }) {
        Text(`${this.listenSongs}`)
          .fontSize(28)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Bold)
        Text('听歌曲目')
          .fontSize(12)
          .fontColor(this.themeTextSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 20, bottom: 20 })
    .backgroundColor(this.themeCardBg)
    .borderRadius(16)
    .shadow({ radius: 4, color: '#00000008', offsetY: 2 })
  }

  @Builder
  StatCard(title: string, value: string, unit: string, accent: string) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(11)
        .fontColor(this.themeTextSecondary)
      Row({ space: 3 }) {
        Text(value)
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(accent)
        Text(unit)
          .fontSize(10)
          .fontColor(this.themeTextSecondary)
          .margin({ bottom: 4 })
      }
      .alignItems(VerticalAlign.Bottom)
    }
    .layoutWeight(1)
    .backgroundColor(this.themeCardBg)
    .borderRadius(16)
    .padding({ top: 16, bottom: 16, left: 16, right: 10 })
    .alignItems(HorizontalAlign.Start)
  }
}
