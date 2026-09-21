// SHMY 歌曲操作底部弹窗组件
// SongActionSheet.ets
import { SongInfo, Playlist, SourceInfo, createEmptySongInfo } from '../model/MusicModel'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { PlayerStore } from '../utils/PlayerStore'
import { MusicApi } from '../utils/MusicApi'
import { AudioPlayer } from '../utils/AudioPlayer'
import { CoverImage } from './CoverImage'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { systemShare } from '@kit.ShareKit'
import { uniformTypeDescriptor as utd } from '@kit.ArkData'
import { MaterialCompat, MaterialCompatStyle } from '../utils/MaterialCompat'
import { CompatUtils } from '../utils/CompatUtils'
import fs from '@ohos.file.fs'
import { http } from '@kit.NetworkKit'
import { promptAction } from '@kit.ArkUI'

interface ActionItem {
  icon: Resource
  label: string
  action: string
}

// 完整模式操作列表（轩窗版块用）
const FULL_ACTION_LIST: ActionItem[] = [
  { icon: $r('sys.symbol.play_fill'), label: '\u64AD\u653E', action: 'play' },
  { icon: $r('sys.symbol.heart'), label: '\u6536\u85CF', action: 'favorite' },
  { icon: $r('sys.symbol.clock'), label: '\u7A0D\u540E\u64AD\u653E', action: 'later' },
  { icon: $r('sys.symbol.share'), label: '\u5206\u4EAB', action: 'share' },
  { icon: $r('sys.symbol.list_bullet'), label: '\u6DFB\u52A0\u5230\u6B4C\u5355', action: 'playlist' },
  { icon: $r('sys.symbol.square_and_arrow_down'), label: '\u4E0B\u8F7D', action: 'download' },
]

// 搜索模式操作列表（搜索版块用）：加入歌单 / 下曲播放 / 分享歌曲（系统分享）
const SEARCH_ACTION_LIST: ActionItem[] = [
  { icon: $r('sys.symbol.list_bullet'), label: '\u52A0\u5165\u6B4C\u5355', action: 'playlist' },
  { icon: $r('sys.symbol.forward_end_fill'), label: '\u4E0B\u66F2\u64AD\u653E', action: 'play_next' },
  { icon: $r('sys.symbol.share'), label: '\u5206\u4EAB\u6B4C\u66F2', action: 'share' },
]

// 下载音质选项
interface QualityOption {
  label: string
  value: string
}

const QUALITY_OPTIONS: QualityOption[] = [
  { label: '\u6807\u51C6\u54C1\u8D28 (128kbps)', value: 'standard' },
  { label: '\u9AD8\u54C1\u8D28 (320kbps)', value: 'high' },
  { label: '\u65E0\u635F\u54C1\u8D28 (FLAC)', value: 'lossless' },
]

@Component
export struct SongActionSheet {
  song: SongInfo = createEmptySongInfo()
  visible: boolean = false
  onDismiss?: () => void
  onPlay?: (song: SongInfo) => void
  onAddFavorite?: (song: SongInfo) => void

  // 模式: 'full' = 完整操作（轩窗），'search' = 简化操作（搜索）
  mode: string = 'full'

  @State private sheetVisible: boolean = false
  @State private showPlaylistPicker: boolean = false
  @State private showQualityPicker: boolean = false
  @State private showCreatePlaylistInline: boolean = false
  @State private newPlaylistName: string = ''
  @State private playlists: Playlist[] = []


  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private supportImmersive: boolean = CompatUtils.isImmersiveSupported()
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_primaryLight') themePrimaryLight: string = '#E0F0FF'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'
  @StorageProp('theme_cardBg') themeCardBg: string = '#FFFFFF'
  @StorageProp('theme_placeholder') themePlaceholder: string = '#E0E0E0'
  @StorageProp('theme_divider') themeDivider: string = '#E8E8E8'
  @StorageProp('isDarkMode') isDarkMode: boolean = false

  aboutToAppear(): void {
    this.sheetVisible = this.visible
  }

  aboutToUpdate(): void {
    this.sheetVisible = this.visible
  }

  private async loadPlaylists(): Promise<void> {
    const list: Playlist[] = await this.db.getPlaylists()
    // 歌单自身未设封面时回退取第一首歌的封面（与轩窗歌单列表一致）
    for (let i = 0; i < list.length; i++) {
      const p: Playlist = list[i]
      if (!p.coverUrl || p.coverUrl.length === 0) {
        const songs: SongInfo[] = await this.db.getPlaylistSongs(p.id)
        if (songs.length > 0 && songs[0].coverUrl.length > 0) {
          p.coverUrl = songs[0].coverUrl
        }
      }
    }
    this.playlists = list
  }

  private async doAddToPlaylist(playlistId: string): Promise<void> {
    const result = await this.db.addSongToPlaylist(playlistId, this.song)
    if (result) {
      this.showToastMsg('\u5DF2\u6DFB\u52A0\u5230\u6B4C\u5355')
    } else {
      this.showToastMsg('\u6DFB\u52A0\u5931\u8D25\uFF0C\u8BF7\u91CD\u8BD5')
    }
    this.showPlaylistPicker = false
  }

  // 搜索模式：创建新歌单并自动添加歌曲
  private async doCreateAndAdd(): Promise<void> {
    const name = this.newPlaylistName.trim()
    if (!name) {
      this.showToastMsg('\u8BF7\u8F93\u5165\u6B4C\u5355\u540D\u79F0')
      return
    }
    const playlistId = await this.db.createPlaylist(name)
    if (playlistId) {
      await this.db.addSongToPlaylist(playlistId, this.song)
      this.showToastMsg(`\u5DF2\u521B\u5EFA\u6B4C\u5355\u300C${name}\u300D\u5E76\u6DFB\u52A0\u6B4C\u66F2`)
      this.newPlaylistName = ''
      this.showCreatePlaylistInline = false
      this.showPlaylistPicker = false
    } else {
      this.showToastMsg('\u521B\u5EFA\u6B4C\u5355\u5931\u8D25')
    }
  }

  private async doDownload(quality: string): Promise<void> {
    // 检查高品质并发下载限制
    if (quality === 'high' || quality === 'lossless') {
      const downloads = await this.db.getDownloads()
      const activeCount = downloads.filter(d =>
        d.status === 'downloading' || d.status === 'pending'
      ).length
      if (activeCount >= 5) {
        this.showToastMsg('\u9AD8\u54C1\u8D28\u4E0B\u8F7D\u6700\u591A\u540C\u65F6\u8FDB\u884C5\u9996\uFF0C\u8BF7\u7B49\u5F85\u5B8C\u6210')
        return
      }
    }

    const result = await this.db.addDownload(this.song, quality)
    if (result) {
      this.showToastMsg('\u5DF2\u6DFB\u52A0\u5230\u4E0B\u8F7D\u5217\u8868')
      this.executeDownload(result, this.song, quality)
    } else {
      this.showToastMsg('\u4E0B\u8F7D\u4EFB\u52A1\u6DFB\u52A0\u5931\u8D25')
    }
    this.showQualityPicker = false
  }

  // 搜索模式：自动下载普通音质
  private async doAutoDownload(): Promise<void> {
    const result = await this.db.addDownload(this.song, 'standard')
    if (result) {
      this.showToastMsg('\u5DF2\u5F00\u59CB\u4E0B\u8F7D\uFF08\u6807\u51C6\u54C1\u8D28\uFF09')
      this.executeDownload(result, this.song, 'standard')
    } else {
      this.showToastMsg('\u4E0B\u8F7D\u4EFB\u52A1\u6DFB\u52A0\u5931\u8D25')
    }
  }

  // 下曲播放
  private doPlayNext(): void {
    PlayerStore.insertNext(this.song)
    this.showToastMsg('\u5DF2\u6DFB\u52A0\u5230\u4E0B\u4E00\u9996\u64AD\u653E')
  }

  private async executeDownload(downloadId: string, song: SongInfo, quality: string): Promise<void> {
    try {
      await this.db.updateDownloadStatus(downloadId, 'downloading', 0)

      // 获取播放URL
      let playUrl = song.playUrl
      if (!playUrl) {
        playUrl = await MusicApi.getPlayUrl(song.songId, song.source, song)
      }
      if (!playUrl) {
        await this.db.updateDownloadStatus(downloadId, 'failed', 0)
        return
      }

      // 使用 http 下载文件
      const httpRequest = http.createHttp()

      try {
        const response = await httpRequest.request(playUrl, {
          method: http.RequestMethod.GET,
          readTimeout: 120000,
          connectTimeout: 15000,
        } as http.HttpRequestOptions)

        if (response.responseCode === 200 && response.result) {
          // 确定文件扩展名
          let ext: string = '.mp3'
          if (quality === 'lossless') {
            ext = '.flac'
          }

          // 安全文件名
          const safeName = song.songName.replace(/[\/\\:*?"<>|]/g, '_')
          const fileName = `${safeName} - ${song.artist.replace(/[\/\\:*?"<>|]/g, '_')}${ext}`

          // 确保目录存在
          const dirPath = '/SHMY/Music/'
          try {
            fs.mkdir(dirPath, true)
          } catch (_e) {
            // 目录可能已存在
          }

          const filePath: string = dirPath + fileName

          // 写入文件
          if (typeof response.result === 'string') {
            const file: fs.File = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY)
            fs.writeSync(file.fd, response.result)
            fs.closeSync(file)
          }

          await this.db.updateDownloadStatus(downloadId, 'completed', 100)
        } else {
          await this.db.updateDownloadStatus(downloadId, 'failed', 0)
        }
      } catch (_e) {
        console.error('[SongActionSheet] download write failed')
        await this.db.updateDownloadStatus(downloadId, 'failed', 0)
      } finally {
        httpRequest.destroy()
      }
    } catch (e) {
      console.error('[SongActionSheet] executeDownload failed:', e)
      await this.db.updateDownloadStatus(downloadId, 'failed', 0)
    }
  }

  private async doShare(): Promise<void> {
    try {
      const shareText = this.buildShareText(this.song)
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: shareText,
        title: `分享歌曲：${this.song.songName}`,
        description: `${this.song.songName} - ${this.song.artist}`,
      })
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData)
      const context = getContext(this) as common.UIAbilityContext
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL,
      })
    } catch (e) {
      console.error('[SongActionSheet] share failed:', e)
      // 降级：复制到剪贴板
      try {
        const shareText = this.buildShareText(this.song)
        const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, shareText)
        const systemPasteboard = pasteboard.getSystemPasteboard()
        await systemPasteboard.setDataSync(pasteData)
        this.showToastMsg('\u5206\u4EAB\u9762\u677F\u62C9\u8D77\u5931\u8D25\uFF0C\u5DF2\u590D\u5236\u5230\u526A\u8D34\u677F')
      } catch (_) {
        this.showToastMsg('\u5206\u4EAB\u5931\u8D25')
      }
    }
  }

  // 分享文本与歌单内分享一致
  private buildShareText(song: SongInfo): string {
    const url = this.getShareUrl(song)
    if (url) {
      return `♫ ${song.songName} - ${song.artist}\n${url}`
    }
    return `♫ ${song.songName} - ${song.artist}\n快来听这首歌吧！`
  }

  // 根据音源生成原平台详情页链接（与歌单分享一致）
  private getShareUrl(song: SongInfo): string {
    const id = song.songId
    switch (song.source) {
      case 'wy':
      case 'netease':
      case 'WY':
        return `https://music.163.com/#/song?id=${id}`
      case 'tx':
      case 'qq':
      case 'TX':
        return `https://y.qq.com/n/ryqq/songDetail/${id}`
      case 'kw':
      case 'kuwo':
      case 'KW':
        return `https://www.kuwo.cn/play_detail/${id}`
      case 'kg':
      case 'kugou':
      case 'KG':
        return `https://www.kugou.com/song/#hash=${id}`
      case 'mg':
      case 'migu':
      case 'MG':
        return `https://music.migu.cn/v3/music/song/${id}`
      default:
        // local、webdav 等无原平台链接
        return ''
    }
  }

  private doPlayLater(): void {
    PlayerStore.addToQueue(this.song)
    this.showToastMsg('\u5DF2\u6DFB\u52A0\u5230\u7A0D\u540E\u64AD\u653E\u961F\u5217')
  }

  private showToastMsg(msg: string): void {
    promptAction.showToast({ message: msg, duration: 2000 })
  }

  private dismiss(): void {
    this.sheetVisible = false
    if (this.onDismiss) {
      this.onDismiss()
    }
  }

  // 获取当前模式的操作列表
  private getActionList(): ActionItem[] {
    if (this.mode === 'search') {
      return SEARCH_ACTION_LIST
    }
    return FULL_ACTION_LIST
  }

  /** 歌曲时长：quality 字段「128kbps/mm:ss」取时长段，缺失时回退 rawData.duration（毫秒） */
  private getDurationLabel(): string {
    const q: string = this.song.quality || ''
    if (q.indexOf('/') >= 0) {
      const parts: string[] = q.split('/')
      const t: string = parts[parts.length - 1]
      if (t.length > 0) {
        return t
      }
    } else if (q.length > 0 && q.indexOf(':') >= 0) {
      return q
    }
    const raw: string = this.song.rawData || ''
    if (raw.length > 0) {
      try {
        const obj: Record<string, Object> = JSON.parse(raw) as Record<string, Object>
        const d: Object | undefined = obj['duration']
        if (d !== undefined && typeof d === 'number' && d > 0) {
          const totalSec: number = d > 3600 ? Math.floor(d / 1000) : Math.floor(d)
          const mm: number = Math.floor(totalSec / 60)
          const ss: number = totalSec % 60
          const pad = (n: number): string => n < 10 ? '0' + n : '' + n
          return `${pad(mm)}:${pad(ss)}`
        }
      } catch (_e) {}
    }
    return ''
  }

  build() {
    Stack() {
      Column() {
        // 主操作面板（沉浸光感：内容自适应材质，不支持时回退卡片背景）
        Row()
          .width(1)
          .height(1)
          .bindSheet($$this.sheetVisible, this.SheetContent(), {
            height: SheetSize.FIT_CONTENT,
            dragBar: true,
            showClose: false,
            backgroundColor: Color.Transparent,
            systemMaterial: this.supportImmersive ? MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK) : undefined,
            onDisappear: () => {
              this.visible = false
              this.sheetVisible = false
              if (this.onDismiss) {
                this.onDismiss()
              }
            },
          })

        // 歌单选择面板
        Row()
          .width(1)
          .height(1)
          .bindSheet($$this.showPlaylistPicker, this.PlaylistPickerContent(), {
            height: SheetSize.FIT_CONTENT,
            dragBar: true,
            showClose: false,
            backgroundColor: Color.Transparent,
            systemMaterial: this.supportImmersive ? MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK) : undefined,
            onDisappear: () => {
              this.showPlaylistPicker = false
              this.showCreatePlaylistInline = false
            },
          })

        // 音质选择面板（仅完整模式）
        if (this.mode === 'full') {
          Row()
            .width(1)
            .height(1)
            .bindSheet($$this.showQualityPicker, this.QualityPickerContent(), {
              height: SheetSize.FIT_CONTENT,
              dragBar: true,
              showClose: false,
              backgroundColor: Color.Transparent,
              systemMaterial: this.supportImmersive ? MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK) : undefined,
              onDisappear: () => {
                this.showQualityPicker = false
              },
            })
        }
      }

    }
  }

  @Builder
  SheetContent() {
    Column() {
      Row({ space: 12 }) {
        Image(this.song.coverUrl)
          .width(48)
          .height(48)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .backgroundColor(this.themePlaceholder)
          .flexShrink(0)

        Column({ space: 2 }) {
          Text(this.song.songName)
            .fontSize(17)
            .fontColor(this.themeTextPrimary)
            .fontWeight(FontWeight.Bold)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.song.artist)
            .fontSize(13)
            .fontColor(this.themeTextSecondary)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Divider()
        .width('100%')
        .color(this.themeDivider)

      if (this.mode === 'search') {
        // 基础操作：四宫格（图标 + 文字）
        Text('\u57FA\u7840\u64CD\u4F5C')
          .fontSize(16)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .padding({ left: 16, top: 12, bottom: 4 })

        Row() {
          this.ActionGridItem('bofang.svg', '\u6B4C\u66F2\u64AD\u653E', 'play')
          this.ActionGridItem('copy.svg', '\u52A0\u5165\u6B4C\u5355', 'playlist')
          this.ActionGridItem('xys.svg', '\u4E0B\u9996\u64AD\u653E', 'play_next')
          this.ActionGridItem('share.svg', '\u5206\u4EAB\u6B4C\u66F2', 'share')
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 4, bottom: 12 })

        Divider()
          .width('100%')
          .color(this.themeDivider)

        // 歌曲信息：每行一条，无图标，缺失显示 -
        Text('\u6B4C\u66F2\u4FE1\u606F')
          .fontSize(16)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .padding({ left: 16, top: 12, bottom: 4 })

        Column() {
          this.InfoRow('\u6B4C\u624B', this.song.artist)
          this.InfoRow('\u4E13\u8F91', this.song.album)
          this.InfoRow('\u6B4C\u66F2\u6765\u6E90', SourceInfo.getAbbr(this.song.source))
          this.InfoRow('\u6B4C\u66F2\u65F6\u957F', this.getDurationLabel())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 2 })
      } else {
        Column({ space: 0 }) {
          ForEach(this.getActionList(), (item: ActionItem, index: number) => {
            Row({ space: 12 }) {
              Row() {
                SymbolGlyph(item.icon)
                  .fontSize(18)
                  .fontColor(item.action === 'download_disabled' ? [this.themeTextSecondary] : [this.themePrimary])
              }
              .width(36)
              .height(36)
              .borderRadius(9)
              .backgroundColor(item.action === 'download_disabled' ? this.themePlaceholder : this.themePrimaryLight)
              .justifyContent(FlexAlign.Center)
              .flexShrink(0)

              Text(item.label)
                .fontSize(14)
                .fontColor(item.action === 'download_disabled' ? this.themeTextSecondary : this.themeTextPrimary)
                .layoutWeight(1)

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(16)
                .fontColor([this.themeTextSecondary])
                .opacity(item.action === 'download_disabled' ? 0 : 1)
                .flexShrink(0)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => {
              this.handleAction(item.action)
            })

            if (index < this.getActionList().length - 1) {
              Divider()
                .width('100%')
                .color(this.themeDivider)
                .margin({ left: 16, right: 16 })
            }
          })
        }
        .width('100%')
      }

      Column().height(16)
    }
    .width('100%')
  }

  @Builder
  ActionGridItem(iconRaw: string, label: string, action: string) {
    Column({ space: 6 }) {
      Row() {
        Image($rawfile(iconRaw))
          .width(24)
          .height(24)
      }
      .width(44)
      .height(44)
      .borderRadius(12)
      .backgroundColor(this.themePrimaryLight)
      .justifyContent(FlexAlign.Center)

      Text(label)
        .fontSize(12)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
    }
    .layoutWeight(1)
    .onClick(() => {
      this.handleAction(action)
    })
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor(this.themeTextSecondary)
        .width(72)
        .flexShrink(0)

      Text(value && value.length > 0 ? value : '-')
        .fontSize(13)
        .fontColor(this.themeTextPrimary)
        .layoutWeight(1)
        .textAlign(TextAlign.End)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 })
  }

  @Builder
  PlaylistPickerContent() {
    Column() {
      Text('\u9009\u62E9\u6B4C\u5355')
        .fontSize(17)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 24, right: 24, top: 16, bottom: 12 })

      if (this.playlists.length === 0 && !this.showCreatePlaylistInline) {
        // 无歌单时显示创建入口
        Column({ space: 12 }) {
          Text('\u6682\u65E0\u6B4C\u5355\uFF0C\u8BF7\u5148\u521B\u5EFA\u4E00\u4E2A')
            .fontSize(14)
            .fontColor(this.themeTextSecondary)
            .width('100%')
            .textAlign(TextAlign.Center)

          // 内联创建歌单
          if (this.showCreatePlaylistInline) {
            Column({ space: 12 }) {
              TextInput({ placeholder: '\u8F93\u5165\u6B4C\u5355\u540D\u79F0', text: this.newPlaylistName })
                .width('100%')
                .height(44)
                .fontSize(15)
                .padding({ left: 16, right: 16 })
                .backgroundColor(this.themePlaceholder)
                .borderRadius(10)
                .onChange((value: string) => {
                  this.newPlaylistName = value
                })

              Row({ space: 12 }) {
                Button('\u53D6\u6D88')
                  .layoutWeight(1)
                  .height(40)
                  .fontSize(14)
                  .fontColor(this.themeTextPrimary)
                  .backgroundColor(this.themeCardBg)
                  .borderRadius(20)
                  .onClick(() => {
                    this.showCreatePlaylistInline = false
                    this.newPlaylistName = ''
                  })

                Button('\u521B\u5EFA\u5E76\u6DFB\u52A0')
                  .layoutWeight(1)
                  .height(40)
                  .fontSize(14)
                  .fontColor(Color.White)
                  .backgroundColor(this.themePrimary)
                  .borderRadius(20)
                  .onClick(() => {
                    this.doCreateAndAdd()
                  })
              }
              .width('100%')
            }
            .padding({ left: 24, right: 24, top: 4 })
          } else {
            Button('\u65B0\u5EFA\u6B4C\u5355')
              .width('80%')
              .height(40)
              .fontSize(14)
              .fontColor(Color.White)
              .backgroundColor(this.themePrimary)
              .borderRadius(20)
              .onClick(() => {
                this.showCreatePlaylistInline = true
              })
          }
        }
        .padding(24)
      } else {
        // 歌单列表
        ForEach(this.playlists, (playlist: Playlist) => {
          Row({ space: 12 }) {
            if (playlist.coverUrl && playlist.coverUrl.length > 0) {
              CoverImage({
                url: playlist.coverUrl,
                coverWidth: 36,
                coverHeight: 36,
                radius: 8
              })
              .flexShrink(0)
            } else {
              Row() {
                SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(18)
              }
              .width(36)
              .height(36)
              .borderRadius(8)
              .backgroundColor(this.themeCardBg)
              .justifyContent(FlexAlign.Center)
              .flexShrink(0)
            }

            Column({ space: 2 }) {
              Text(playlist.name)
                .fontSize(15)
                .fontColor(this.themeTextPrimary)
                .fontWeight(FontWeight.Medium)
              Text(`${playlist.songCount} \u9996`)
                .fontSize(12)
                .fontColor(this.themeTextSecondary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(18)
              .fontColor([this.themePrimary])
              .width(32)
              .height(32)
          }
          .width('100%')
          .padding({ left: 24, right: 24, top: 12, bottom: 12 })
          .onClick(() => {
            this.doAddToPlaylist(playlist.id)
          })
        })

        // 搜索模式下始终显示创建新歌单入口
        if (this.mode === 'search') {
          if (this.showCreatePlaylistInline) {
            Column({ space: 12 }) {
              Divider().width('100%').color(this.themeDivider)

              Text('\u65B0\u5EFA\u6B4C\u5355')
                .fontSize(15)
                .fontColor(this.themeTextPrimary)
                .fontWeight(FontWeight.Medium)
                .width('100%')

              TextInput({ placeholder: '\u8F93\u5165\u6B4C\u5355\u540D\u79F0', text: this.newPlaylistName })
                .width('100%')
                .height(44)
                .fontSize(15)
                .padding({ left: 16, right: 16 })
                .backgroundColor(this.themePlaceholder)
                .borderRadius(10)
                .onChange((value: string) => {
                  this.newPlaylistName = value
                })

              Row({ space: 12 }) {
                Button('\u53D6\u6D88')
                  .layoutWeight(1)
                  .height(40)
                  .fontSize(14)
                  .fontColor(this.themeTextPrimary)
                  .backgroundColor(this.themeCardBg)
                  .borderRadius(20)
                  .onClick(() => {
                    this.showCreatePlaylistInline = false
                    this.newPlaylistName = ''
                  })

                Button('\u521B\u5EFA\u5E76\u6DFB\u52A0')
                  .layoutWeight(1)
                  .height(40)
                  .fontSize(14)
                  .fontColor(Color.White)
                  .backgroundColor(this.themePrimary)
                  .borderRadius(20)
                  .onClick(() => {
                    this.doCreateAndAdd()
                  })
              }
              .width('100%')
            }
            .padding({ left: 24, right: 24, top: 12 })
          } else {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(16)
                .fontColor([this.themePrimary])
              Text('\u65B0\u5EFA\u6B4C\u5355')
                .fontSize(14)
                .fontColor(this.themePrimary)
            }
            .width('100%')
            .padding({ left: 24, right: 24, top: 16, bottom: 8 })
            .onClick(() => {
              this.showCreatePlaylistInline = true
            })
          }
        }
      }

      Column().height(16)
    }
  }

  @Builder
  QualityPickerContent() {
    Column() {
      Text('\u9009\u62E9\u4E0B\u8F7D\u97F3\u8D28')
        .fontSize(17)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 24, right: 24, top: 16, bottom: 12 })

      ForEach(QUALITY_OPTIONS, (option: QualityOption) => {
        Row({ space: 12 }) {
          Text(option.label)
            .fontSize(15)
            .fontColor(this.themeTextPrimary)
            .layoutWeight(1)

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([this.themeTextSecondary])
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 14, bottom: 14 })
        .onClick(() => {
          this.doDownload(option.value)
        })
      })

      if (QUALITY_OPTIONS.some(q => q.value === 'high' || q.value === 'lossless')) {
        Text('\u9AD8\u54C1\u8D28\u97F3\u4E50\u4E00\u6B21\u81F3\u591A\u4E0B\u8F7D5\u9996')
          .fontSize(12)
          .fontColor(this.themeTextSecondary)
          .width('100%')
          .padding({ left: 24, right: 24, bottom: 16 })
      }

      Column().height(8)
    }
  }

  private handleAction(action: string): void {
    switch (action) {
      case 'play':
        if (this.onPlay) {
          this.onPlay(this.song)
        }
        break
      case 'favorite':
        if (this.onAddFavorite) {
          this.onAddFavorite(this.song)
        }
        break
      case 'later':
        this.doPlayLater()
        break
      case 'share':
        this.doShare()
        break
      case 'playlist':
        this.loadPlaylists().then(() => {
          this.showCreatePlaylistInline = false
          this.showPlaylistPicker = true
        })
        break
      case 'download':
        this.showQualityPicker = true
        break
      case 'play_next':
        this.doPlayNext()
        break
      case 'auto_download':
        this.doAutoDownload()
        break
      case 'download_disabled':
        this.showToastMsg('\u6B64\u529F\u80FD\u5C1A\u672A\u5F00\u542F')
        break
      default:
        break
    }
    // 非弹窗操作时关闭主面板
    if (action !== 'playlist' && action !== 'download' && action !== 'download_disabled') {
      this.dismiss()
    }
  }
}