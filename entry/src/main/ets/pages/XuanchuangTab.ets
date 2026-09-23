// SHMY 轩窗 Tab - 我的音乐
// XuanchuangTab.ets
import { SongInfo, Playlist, SourceInfo, SourceStatus } from '../model/MusicModel'
import { DatabaseHelper, LocalMusicItem } from '../database/DatabaseHelper'
import { AudioPlayer } from '../utils/AudioPlayer'
import { MusicApi } from '../utils/MusicApi'
import { PlayerStore } from '../utils/PlayerStore'
import { SongCard } from '../components/SongCard'
import { SongActionSheet } from '../components/SongActionSheet'
import { EmptyState } from '../components/EmptyState'
import { fileIo } from '@kit.CoreFileKit'
import { picker } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { http } from '@kit.NetworkKit'
import { promptAction } from '@kit.ArkUI'
import { CompatUtils } from '../utils/CompatUtils'
import { MaterialCompat, MaterialCompatStyle } from '../utils/MaterialCompat'
import { AccountManager, UserInfo } from '../utils/AccountManager'
import { FloatingAction } from '../components/FloatingActionPopup'
import { ListeningLevelManager, LevelInfo } from '../utils/ListeningLevelManager'
import { WebDAVProfileSync } from '../utils/WebDAVProfileSync'
import { SignatureEditDialog } from '../components/SignatureEditDialog'
import { LevelGuideDialog } from '../components/LevelGuideDialog'
import { CoverImage } from '../components/CoverImage'
import { getLevelColor } from '../utils/LevelConfig'
import { pasteboard } from '@kit.BasicServicesKit'
import { systemShare } from '@kit.ShareKit'
import { uniformTypeDescriptor as utd } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { CloudTagEnricher } from '../utils/CloudTagEnricher'
import { HdsNavDestination } from '@kit.UIDesignKit'

type SubPage = 'main' | 'playlistDetail' | 'localMusicDetail' | 'cloudPlaylistDetail'

// 歌曲名排序（按字母/拼音首字母）：zh 区域 collation 按拼音排序，失败时退化为码点比较
function compareNameForSort(a: string, b: string): number {
  try {
    return a.localeCompare(b, 'zh-CN')
  } catch (_e) {
    if (a < b) return -1
    if (a > b) return 1
    return 0
  }
}

interface DirEntry {
  href: string
  name: string
}

@Component
export struct XuanchuangTab {
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_bg') themeBg: string = '#F5F5F7'
  @StorageProp('theme_cardBg') themeCardBg: string = '#FFFFFF'
  @StorageProp('isDarkMode') isDarkMode: boolean = false
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'
  @StorageProp('theme_divider') themeDivider: string = '#E8E8E8'
  @StorageProp('theme_placeholder') themePlaceholder: string = '#E0E0E0'
  @StorageProp('theme_primaryLight') themePrimaryLight: string = '#E0F0FF'
  @StorageProp('theme_danger') themeDanger: string = '#F44336'
  @StorageProp('theme_bgImageName') themeBgImageName: string = ''
  // 当前播放曲目（V2.0.8：歌单打开自动定位 + 正在播放行高亮）
  @StorageProp('currentTrack') currentTrack: SongInfo | null = null

  @State favorites: SongInfo[] = []
  @State playlists: Playlist[] = []
  @StorageLink('xuanchuang_subPage') subPage: SubPage = 'main'

  // 本地音乐
  @State localMusicList: LocalMusicItem[] = []
  @State localMusicExpanded: boolean = false

  // Playlist detail
  @State selectedPlaylist: Playlist | null = null
  @State playlistSongs: SongInfo[] = []

  // 歌单排序（新在前/旧在前/按字母，各歌单独立记忆）
  @State playlistSortMode: string = 'old'
  @State localSortMode: string = 'new'
  @State sortPopupTarget: string = ''

  // Dialogs
  @State showRenameDialog: boolean = false
  @State renamePlaylistId: string = ''
  @State renameValue: string = ''

  // Export dialog
  @State showExportDialog: boolean = false
  @State exportPlaylistTarget: Playlist | null = null

  // Import playlist
  @State showImportPlaylistPicker: boolean = false

  // Playlist first covers cache
  @State playlistCovers: Map<string, string> = new Map()

  // Action sheet
  @State selectedSong: SongInfo | null = null
  @State showSongActionSheet: boolean = false


  @State showFloatingPopup: boolean = false
  @State showAccountMenu: boolean = false
  @State floatingSong: SongInfo | null = null
  @State showReorderDialog: boolean = false
  @State reorderInput: string = ''
  @State showMovePlaylistDialog: boolean = false
  @State movePlaylistTarget: SongInfo | null = null
  @State pendingReorder: boolean = false
  @State pendingMovePlaylist: boolean = false

  // 复制到歌单
  @State showCopyPlaylistDialog: boolean = false
  @State copyPlaylistTarget: SongInfo | null = null
  @State pendingCopyPlaylist: boolean = false

  // 歌单操作底部弹窗
  @State showPlaylistActionSheet: boolean = false
  @State playlistActionTarget: Playlist | null = null

  // 多选编辑模式
  @State multiSelectMode: boolean = false
  @State selectedSongKeys: Set<string> = new Set()

  // Edit playlist
  @State showEditPlaylistSheet: boolean = false
  @State editPlaylistName: string = ''
  @State editPlaylistCoverUri: string = ''
  @State editPlaylistTarget: Playlist | null = null

  // Song info dialog
  @State showSongInfo: boolean = false
  @State songInfoSong: SongInfo | null = null

  // Reorder mode
  @State reorderMode: boolean = false
  @State reorderedIds: string[] = []
  @State draggingPlaylistId: string = ''
  @State dragOffset: number = 0
  private accumulatedOffset: number = 0

  // Pull-to-refresh
  @State refreshing: boolean = false
  // 歌单详情页下拉刷新（与主页独立，避免互相干扰）
  @State detailRefreshing: boolean = false

  // Cloud playlists
  @State cloudPlaylists: Playlist[] = []
  @State webdavConfigured: boolean = false
  @State cloudPlaylistLoading: boolean = false
  @State localPlaylistExpanded: boolean = false

  // Cloud playlist detail
  @State selectedCloudPlaylist: Playlist | null = null
  @State cloudPlaylistSongs: SongInfo[] = []
  @State cloudPlaylistLoadingSongs: boolean = false

  // Expanding sections
  @State playlistsExpanded: boolean = true

  // User info
  @State userName: string = '点击登录'
  @State userAccount: string = ''
  @State avatarUrl: string = ''
  @State isLoggedIn: boolean = false
  @State loggingIn: boolean = false

  // Level & signature
  @State levelInfo: LevelInfo = { level: 1, current: 0, need: 1160, totalSeconds: 0, percent: 0 }
  @State signature: string = ''
  private signatureDialogController: CustomDialogController | null = null
  private levelGuideDialogController: CustomDialogController | null = null
  private levelRefreshTimer: number = -1

  // Stats
  @State playlistCount: number = 0
  @State listenTime: number = 0
  @State listenSongs: number = 0
  @State showHomeStats: boolean = true // 默认开启

  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private supportImmersive: boolean = CompatUtils.isImmersiveSupported()

  // 列表滚动器（V2.0.8：打开歌单时自动定位到正在播放的歌曲）
  private playlistDetailScroller: Scroller = new Scroller()
  private localDetailScroller: Scroller = new Scroller()
  private cloudDetailScroller: Scroller = new Scroller()
  // 版块设置-主页-歌单内设置：定位播放歌曲（默认关闭）
  @StorageProp('playlistLocatePlaying') playlistLocatePlaying: boolean = false

  async aboutToAppear() {
    await this.loadAllData()
    this.startLevelRefresh()
  }

  aboutToDisappear() {
    this.stopLevelRefresh()
    if (this.levelGuideDialogController) {
      this.levelGuideDialogController.close()
      this.levelGuideDialogController = null
    }
    if (this.signatureDialogController) {
      this.signatureDialogController.close()
      this.signatureDialogController = null
    }
  }

  private async loadAllData() {
    const homeStats = await this.db.getSetting('showHomeStats')
    this.showHomeStats = homeStats !== 'false' // 默认开启
    // 加载已保存的用户信息
    const savedUser = await AccountManager.loadSavedUserInfo()
    if (savedUser) {
      this.userName = savedUser.displayName
      this.avatarUrl = savedUser.avatarUri
      this.userAccount = '已登录'
      this.isLoggedIn = true
    }
    if (this.isLoggedIn) {
      // 登录后才加载用户数据
      await Promise.all([
        this.loadFavorites(),
        this.loadPlaylists(),
        this.loadLocalMusic(),
      ])
      this.loadStats()
      this.checkWebdavConfig()
      await this.loadProfileData()
      this.syncProfileFromWebDAV()
    } else {
      // 未登录时清空所有用户数据
      this.playlists = []
      this.favorites = []
      this.localMusicList = []
      this.playlistCount = 0
      this.listenSongs = 0
      this.listenTime = 0
      this.levelInfo = { level: 1, current: 0, need: 1160, totalSeconds: 0, percent: 0 }
      this.signature = ''
    }
  }

  private async loadProfileData() {
    const manager = ListeningLevelManager.getInstance()
    await manager.init()
    this.levelInfo = manager.getLevelInfo()
    this.signature = manager.getSignature()
    this.listenTime = this.calculateListenTime()
  }

  private async syncProfileFromWebDAV() {
    const result = await WebDAVProfileSync.downloadProfile()
    if (result.success && result.data) {
      const manager = ListeningLevelManager.getInstance()
      const changed = await manager.mergeFromRemote(
        result.data.listening_total_seconds,
        result.data.user_signature,
        result.data.signature_updated_at
      )
      if (changed) {
        this.levelInfo = manager.getLevelInfo()
        this.signature = manager.getSignature()
        this.listenTime = this.calculateListenTime()
      }
    }
  }

  private startLevelRefresh() {
    this.stopLevelRefresh()
    this.levelRefreshTimer = setInterval(() => {
      this.levelInfo = ListeningLevelManager.getInstance().getLevelInfo()
      this.listenTime = this.calculateListenTime()
    }, 5000)
  }

  private stopLevelRefresh() {
    if (this.levelRefreshTimer >= 0) {
      clearInterval(this.levelRefreshTimer)
      this.levelRefreshTimer = -1
    }
  }

  private openSignatureEdit() {
    if (this.signatureDialogController) {
      this.signatureDialogController.close()
      this.signatureDialogController = null
    }
    this.signatureDialogController = new CustomDialogController({
      builder: SignatureEditDialog({
        signatureValue: this.signature,
        onSave: (value: string): void => { this.saveSignature(value) },
        themePrimary: this.themePrimary,
        themeCardBg: this.themeCardBg,
        themeTextPrimary: this.themeTextPrimary,
        themeTextSecondary: this.themeTextSecondary
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    })
    this.signatureDialogController.open()
  }

  private openLevelGuide() {
    if (this.levelGuideDialogController) {
      this.levelGuideDialogController.close()
      this.levelGuideDialogController = null
    }
    this.levelGuideDialogController = new CustomDialogController({
      builder: LevelGuideDialog({
        currentLevel: this.levelInfo.level,
        themePrimary: this.themePrimary,
        themeCardBg: this.themeCardBg,
        themeTextPrimary: this.themeTextPrimary,
        themeTextSecondary: this.themeTextSecondary,
        themeDivider: this.themeDivider
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    })
    this.levelGuideDialogController.open()
  }

  private async saveSignature(value: string) {
    const manager = ListeningLevelManager.getInstance()
    await manager.setSignature(value)
    this.signature = value
  }

  private async checkWebdavConfig() {
    const url = await this.db.getSetting('webdav_url')
    this.webdavConfigured = !!(url && url.length > 0)
    if (this.webdavConfigured) {
      await this.loadCloudPlaylists()
    }
  }

  private async loadCloudPlaylists() {
    const raw = await this.db.getSetting('cloud_playlists')
    if (raw) {
      try {
        const playlists = JSON.parse(raw) as Playlist[]
        // 过滤掉旧的"全部音乐"歌单
        this.cloudPlaylists = playlists.filter(p => p.id !== 'cloud_root' && p.name !== '全部音乐')
      } catch (_) {
        this.cloudPlaylists = []
      }
    }
  }

  private async loadStats() {
    this.playlistCount = this.playlists.length
    const allSongs = await this.db.getAllSongs()
    this.listenSongs = allSongs.length
    this.listenTime = this.calculateListenTime()
  }

  private calculateListenTime(): number {
    return Math.floor(ListeningLevelManager.getInstance().getTotalSeconds() / 60)
  }

  private async loadFavorites() {
    this.favorites = await this.db.getFavorites()
  }

  private async loadPlaylists() {
    this.playlists = await this.db.getPlaylists()
    await this.loadPlaylistCovers()
  }

  private async loadPlaylistCovers() {
    const covers: Map<string, string> = new Map()
    for (let i = 0; i < this.playlists.length; i++) {
      const p = this.playlists[i]
      if (p.coverUrl && p.coverUrl.length > 0) {
        covers.set(p.id, p.coverUrl)
      } else {
        const songs = await this.db.getPlaylistSongs(p.id)
        if (songs.length > 0 && songs[0].coverUrl.length > 0) {
          covers.set(p.id, songs[0].coverUrl)
        }
      }
    }
    this.playlistCovers = covers
  }

  private async loadLocalMusic() {
    const allItems = await this.db.getLocalMusic()
    // 过滤掉文件已不存在的条目（例如沙箱文件被清理）
    const validItems: LocalMusicItem[] = []
    const staleIds: string[] = []
    for (const item of allItems) {
      const rawPath = item.filePath.replace('file://', '')
      try {
        fileIo.accessSync(rawPath)
        validItems.push(item)
      } catch (_e) {
        console.warn('[XuanchuangTab] stale local music entry, file missing:', item.filePath)
        staleIds.push(item.id)
      }
    }
    // 异步清理数据库中已失效的条目
    if (staleIds.length > 0) {
      for (const id of staleIds) {
        await this.db.removeLocalMusic(id)
      }
      console.info('[XuanchuangTab] removed', staleIds.length, 'stale local music entries')
    }
    // 读取保存的排序顺序
    const orderRaw = await this.db.getSetting('local_music_order')
    if (orderRaw) {
      try {
        const orderedIds: string[] = JSON.parse(orderRaw)
        const idToItem = new Map(validItems.map(lm => [lm.id, lm]))
        const reordered: LocalMusicItem[] = []
        for (const id of orderedIds) {
          const item = idToItem.get(id)
          if (item) {
            reordered.push(item)
            idToItem.delete(id)
          }
        }
        // 追加新导入的、不在排序列表中的项
        for (const item of idToItem.values()) {
          reordered.push(item)
        }
        this.localMusicList = reordered
        // V2.1.0：按记忆的排序模式重排（新在前/旧在前/按字母）
        await this.applySavedLocalSort()
        return
      } catch (_e) {
        // 解析失败，使用默认顺序
      }
    }
    this.localMusicList = validItems
    // V2.1.0：按记忆的排序模式重排
    await this.applySavedLocalSort()
  }

  // 读取本地音乐排序记忆并应用
  private async applySavedLocalSort(): Promise<void> {
    const savedMode = await this.db.getSetting('local_music_sort')
    this.localSortMode = savedMode.length > 0 ? savedMode : 'new'
    this.localMusicList = this.sortLocalMusic(this.localMusicList, this.localSortMode)
  }

  // ===== 播放歌曲（在线） =====
  private async playSong(song: SongInfo, customQueue?: SongInfo[]) {
    if (!song.playUrl) {
      song.playUrl = await MusicApi.getPlayUrl(song.songId, song.source, song)
    }
    if (!song.playUrl) {
      SourceStatus.markUnplayable(song.source)
      this.showToastMsg('无法获取播放链接')
      return
    }

    // V2.1.6：WebDAV 授权封面补全统一移入 PlayerStore.play（ensureCoverAsync），所有切歌路径共用
    // V2.1.2：确保云端歌曲内嵌标签已解析（歌名/歌手/封面/歌词）
    if (song.source === 'webdav' && !CloudTagEnricher.isAttempted(song.songId)) {
      CloudTagEnricher.ensureEnriched(song).then(() => {
        PlayerStore.refreshCurrentTrack(song)
      }).catch((_e: Error) => {})
    }

    let queue = customQueue ?? (this.playlistSongs.length > 0 ? this.playlistSongs : this.favorites)
    let idx = queue.findIndex(s => s.songId === song.songId && s.source === song.source)
    if (idx < 0) idx = 0

    PlayerStore.play(song, queue, idx)

    // 进度/时长/播完/出错回调由 AudioPlayer 中央化处理
    const player = AudioPlayer.getInstance()
    player.setCurrentSong(song)
    await player.play(song.playUrl)

    // 播放成功：标记该音源可用（恢复彩色标签）
    SourceStatus.markPlayable(song.source)

    // 自动详情：点击歌曲后同步打开详情页
    if (AppStorage.get<boolean>('autoJumpDetail') === true) {
      PlayerStore.showFullPlayer()
    }
  }

  // ===== 播放本地音乐 =====
  private async playLocalSong(item: LocalMusicItem) {
    const song: SongInfo = {
      songId: 'local_' + item.id,
      songName: item.songName || item.fileName.replace(/\.[^.]+$/, ''),
      artist: item.artist || '本地音乐',
      album: '',
      coverUrl: item.coverUrl || '',
      source: 'local',
      playUrl: item.filePath,
      lyric: item.lyric || '',
    }

    const queue: SongInfo[] = this.localMusicList.map((lm): SongInfo => {
      return {
        songId: 'local_' + lm.id,
        songName: lm.songName || lm.fileName.replace(/\.[^.]+$/, ''),
        artist: lm.artist || '本地音乐',
        album: '',
        coverUrl: lm.coverUrl || '',
        source: 'local',
        playUrl: lm.filePath,
        lyric: lm.lyric || '',
      } as SongInfo
    })
    const idx = queue.findIndex(s => s.songId === song.songId)
    const playIdx = idx >= 0 ? idx : 0

    const rawPath = item.filePath.replace('file://', '')
    try {
      fileIo.statSync(rawPath)
    } catch (_e) {
      console.error('[XuanchuangTab] file not found:', item.filePath)
      this.showToastMsg('本地音乐文件不存在，请重新导入')
      return
    }

    PlayerStore.play(song, queue, playIdx)

    // 进度/时长/播完/出错回调由 AudioPlayer 中央化处理（本地队列 SongInfo 已带 playUrl）
    const player = AudioPlayer.getInstance()
    player.setCurrentSong(song)

    try {
      await player.play(song.playUrl)
      // 播放成功：标记本地音源可用
      SourceStatus.markPlayable('local')
      // 自动详情：点击歌曲后同步打开详情页
      if (AppStorage.get<boolean>('autoJumpDetail') === true) {
        PlayerStore.showFullPlayer()
      }
    } catch (e) {
      console.error('[XuanchuangTab] playLocalSong error:', e)
      PlayerStore.pause()
      const errMsg = (e && typeof (e as Record<string, string>).message === 'string') ? (e as Record<string, string>).message : String(e)
      this.showToastMsg('本地音乐播放失败: ' + errMsg)
    }
  }

  // ===== 导入本地音乐 =====
  private async importLocalMusic() {
    try {
      const context: Context = getContext(this)
      const documentPicker = new picker.DocumentViewPicker()
      const uris = await documentPicker.select({
        maxSelectNumber: 50,
      })

      if (!uris || uris.length === 0) {
        return
      }

      let importedCount = 0
      let duplicateCount = 0

      for (let i = 0; i < uris.length; i++) {
        const uri = uris[i]
        console.info('[XuanchuangTab] importing local music:', uri)

        // 1. 从原始 URI 中提取原始文件名（用于歌名回退，避免沙箱 hash 文件名）
        let originalFileName = ''
        let uriPath = uri
        if (uriPath.startsWith('file://')) {
          uriPath = uriPath.slice(7)
        }
        const uriLastSlash = Math.max(uriPath.lastIndexOf('/'), uriPath.lastIndexOf('\\'))
        if (uriLastSlash >= 0) {
          originalFileName = uriPath.substring(uriLastSlash + 1)
        }
        try {
          originalFileName = decodeURIComponent(originalFileName)
        } catch (_e) {
        }

        // 2. 先复制到沙箱（确保后续所有操作都使用可靠的沙箱路径）
        let sandboxPath: string
        try {
          sandboxPath = await AudioPlayer.copyToSandbox(uri, context)
        } catch (e) {
          console.error('[XuanchuangTab] copy to sandbox failed:', uri, e)
          this.showToastMsg('文件复制失败: ' + (e instanceof Error ? e.message : String(e)))
          continue
        }
        console.info('[XuanchuangTab] sandbox path:', sandboxPath)

        // 3. 从沙箱路径提取元数据（沙箱路径更可靠，不会因临时权限过期而失败）
        const metadata = await AudioPlayer.extractMetadata(sandboxPath)
        console.info('[XuanchuangTab] extracted metadata:', JSON.stringify(metadata))

        // 4. 歌名回退：元数据标题 → 原始文件名（去除扩展名）→ 沙箱文件名
        let songName = metadata.title || ''
        let artist = metadata.artist || ''
        if (!songName) {
          songName = originalFileName.replace(/\.[^.]+$/, '')
          const dashIdx = songName.indexOf(' - ')
          if (dashIdx > 0) {
            artist = songName.substring(0, dashIdx).trim()
            songName = songName.substring(dashIdx + 3).trim()
          }
        }
        // 歌手回退：如果元数据没有歌手，尝试从原始文件名解析
        if (!artist) {
          const cleanName = originalFileName.replace(/\.[^.]+$/, '')
          const dashIdx = cleanName.indexOf(' - ')
          if (dashIdx > 0) {
            artist = cleanName.substring(0, dashIdx).trim()
            if (!songName) {
              songName = cleanName.substring(dashIdx + 3).trim()
            }
          }
        }

        // 5. 文件名和文件大小
        const sandboxFilePath = sandboxPath.replace('file://', '')
        const lastSlash = Math.max(sandboxFilePath.lastIndexOf('/'), sandboxFilePath.lastIndexOf('\\'))
        const fileName = lastSlash >= 0 ? sandboxFilePath.substring(lastSlash + 1) : sandboxFilePath

        let fileSize = 0
        try {
          const stat = fileIo.statSync(sandboxFilePath)
          fileSize = stat.size
          console.info('[XuanchuangTab] file size:', fileSize)
        } catch (_e) {
        }

        // 6. 从沙箱路径提取封面和歌词（传入原始 URI 用于外部封面回退）
        let coverUrl = await AudioPlayer.extractCoverFromAudio(sandboxPath, context, uri)
        console.info('[XuanchuangTab] cover url:', coverUrl)

        let lyric = await AudioPlayer.extractLyricFromAudio(sandboxPath, uri)
        console.info('[XuanchuangTab] lyric length:', lyric.length)

        const added = await this.db.addLocalMusic(sandboxPath, originalFileName, songName, artist, metadata.duration,
          fileSize, coverUrl, lyric)
        if (added) {
          importedCount++
        } else {
          // V2.1.2：已存在则刷新元数据（重新导入可更新封面/歌手/歌名/歌词）
          await this.db.updateLocalMusic(sandboxPath, originalFileName, songName, artist, metadata.duration,
            fileSize, coverUrl, lyric)
          duplicateCount++
        }
      }

      await this.loadLocalMusic()
      this.localMusicExpanded = true

      if (importedCount > 0) {
        this.showToastMsg(`已导入 ${importedCount} 首` + (duplicateCount > 0 ? `，${duplicateCount} 首已存在` : ''))
      } else if (duplicateCount > 0) {
        this.showToastMsg(`${duplicateCount} 首已存在`)
      }
    } catch (e) {
      console.error('[XuanchuangTab] importLocalMusic failed:', e)
      this.showToastMsg('导入失败，请检查权限')
    }
  }

  // ===== 收藏 =====
  private async removeFavorite(song: SongInfo) {
    await this.db.removeFavorite(song.songId, song.source)
    await this.loadFavorites()
  }

  // ===== 歌单 CRUD =====
  private async doRenamePlaylist() {
    if (!this.renameValue.trim()) return
    await this.db.renamePlaylist(this.renamePlaylistId, this.renameValue.trim())
    this.renameValue = ''
    this.showRenameDialog = false
    await this.loadPlaylists()
  }

  private async deletePlaylist(id: string) {
    promptAction.showDialog({
      title: '移除歌单',
      message: '确定要移除该歌单吗？此操作不可恢复。',
      buttons: [
        { text: '取消', color: this.themeTextSecondary },
        { text: '移除', color: '#F44336' },
      ],
    }).then((result) => {
      if (result.index === 1) {
        this.db.deletePlaylist(id)
        this.loadPlaylists()
        this.showToastMsg('歌单已移除')
      }
    })
  }

  private async openPlaylistDetail(playlist: Playlist) {
    this.selectedPlaylist = playlist
    this.playlistSongs = await this.db.getPlaylistSongs(playlist.id)
    // V2.1.0：读取该歌单独立的排序记忆并应用
    const savedMode = await this.db.getSetting('playlist_sort_' + playlist.id)
    this.playlistSortMode = savedMode.length > 0 ? savedMode : 'old'
    this.playlistSongs = this.sortPlaylistSongs(this.playlistSongs, this.playlistSortMode)
    this.subPage = 'playlistDetail'
    // V2.0.8：打开歌单自动定位到正在播放的歌曲（受"歌单内-定位播放歌曲"开关控制，默认关闭）
    if (this.playlistLocatePlaying) {
      this.locatePlayingSong('playlist')
    }
  }

  // V2.0.8：打开列表后自动定位/跳转正在播放的歌曲（滚动到该行）
  // 行高：歌单/云端行 64 + 间距 8 = 72；本地行 72 + 间距 8 = 80
  private locatePlayingSong(list: string): void {
    const track: SongInfo | null = this.currentTrack
    if (!track) {
      return
    }
    let idx: number = -1
    let step: number = 72
    let scroller: Scroller | null = null
    if (list === 'playlist') {
      idx = this.playlistSongs.findIndex(s => s.songId === track.songId && s.source === track.source)
      scroller = this.playlistDetailScroller
    } else if (list === 'local') {
      step = 80
      if (track.source === 'local' && track.songId.startsWith('local_')) {
        idx = this.localMusicList.findIndex(lm => 'local_' + lm.id === track.songId)
      }
      scroller = this.localDetailScroller
    } else {
      idx = this.cloudPlaylistSongs.findIndex(s => s.songId === track.songId && s.source === track.source)
      scroller = this.cloudDetailScroller
    }
    if (idx <= 0 || !scroller) {
      return
    }
    const target: Scroller | null = scroller
    const yOffset: number = Math.max(0, idx * step)
    setTimeout(() => {
      target.scrollTo({ xOffset: 0, yOffset: yOffset, animation: { duration: 300, curve: Curve.EaseOut } })
    }, 300)
  }

  // 正在播放的歌曲行（歌单/云端列表高亮）
  private isPlayingTrackSong(song: SongInfo): boolean {
    const t: SongInfo | null = this.currentTrack
    return t !== null && t.songId === song.songId && t.source === song.source
  }

  // ===== 歌单排序（新在前/旧在前/按字母，各歌单独立记忆） =====

  private async reloadPlaylistSongs(): Promise<void> {
    if (!this.selectedPlaylist) return
    this.playlistSongs = await this.db.getPlaylistSongs(this.selectedPlaylist.id)
    this.playlistSongs = this.sortPlaylistSongs(this.playlistSongs, this.playlistSortMode)
  }

  private async applyPlaylistSort(mode: string): Promise<void> {
    this.playlistSortMode = mode
    this.sortPopupTarget = ''
    if (this.selectedPlaylist) {
      await this.db.setSetting('playlist_sort_' + this.selectedPlaylist.id, mode)
      this.playlistSongs = this.sortPlaylistSongs(this.playlistSongs, mode)
    }
  }

  private async applyLocalSort(mode: string): Promise<void> {
    this.localSortMode = mode
    this.sortPopupTarget = ''
    await this.db.setSetting('local_music_sort', mode)
    this.localMusicList = this.sortLocalMusic(this.localMusicList, mode)
  }

  private sortPlaylistSongs(songs: SongInfo[], mode: string): SongInfo[] {
    const arr: SongInfo[] = songs.slice()
    if (mode === 'new') {
      arr.sort((a: SongInfo, b: SongInfo) => (b.addedAt ?? 0) - (a.addedAt ?? 0))
    } else if (mode === 'alpha') {
      arr.sort((a: SongInfo, b: SongInfo) => compareNameForSort(a.songName, b.songName))
    } else {
      arr.sort((a: SongInfo, b: SongInfo) => (a.addedAt ?? 0) - (b.addedAt ?? 0))
    }
    return arr
  }

  private sortLocalMusic(items: LocalMusicItem[], mode: string): LocalMusicItem[] {
    const arr: LocalMusicItem[] = items.slice()
    if (mode === 'new') {
      arr.sort((a: LocalMusicItem, b: LocalMusicItem) => b.addedAt - a.addedAt)
    } else if (mode === 'alpha') {
      arr.sort((a: LocalMusicItem, b: LocalMusicItem) =>
        compareNameForSort(a.songName || a.fileName, b.songName || b.fileName))
    } else {
      arr.sort((a: LocalMusicItem, b: LocalMusicItem) => a.addedAt - b.addedAt)
    }
    return arr
  }

  // ===== 播放歌单 =====
  private async playPlaylist(playlist: Playlist) {
    // 云端歌单：从 WebDAV 加载歌曲后播放
    if (playlist.id === 'cloud_main' || playlist.id.startsWith('cloud_')) {
      this.selectedCloudPlaylist = playlist
      await this.loadCloudPlaylistSongs(playlist)
      const songs = this.cloudPlaylistSongs
      if (songs.length === 0) {
        this.showToastMsg('歌单为空')
        return
      }
      this.playSong(songs[0], songs)
      return
    }

    // 自建歌单：从数据库读取
    const songs = await this.db.getPlaylistSongs(playlist.id)
    if (songs.length === 0) {
      this.showToastMsg('歌单为空')
      return
    }
    // V2.1.0：应用该歌单记忆的排序模式
    const savedMode = await this.db.getSetting('playlist_sort_' + playlist.id)
    const mode = savedMode.length > 0 ? savedMode : 'old'
    this.playlistSongs = this.sortPlaylistSongs(songs, mode)
    this.playSong(this.playlistSongs[0], this.playlistSongs)
  }

  // ===== 导入歌单 =====
  private async importPlaylist() {
    try {
      const documentPicker = new picker.DocumentViewPicker()
      const uris = await documentPicker.select({
        maxSelectNumber: 1,
      })
      if (!uris || uris.length === 0) return
      const uri = uris[0]
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const stat: fileIo.Stat = fileIo.statSync(file.fd)
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buffer)
      fileIo.closeSync(file.fd)
      const decoder = util.TextDecoder.create('utf-8')
      const content = decoder.decodeWithStream(new Uint8Array(buffer))
      if (!content || content.length === 0) {
        this.showToastMsg('文件内容为空')
        return
      }
      let jsonStr = content
      if (content.startsWith('LXMC_V1.0.0')) {
        const newlineIdx = content.indexOf('\n')
        if (newlineIdx > 0) {
          jsonStr = content.substring(newlineIdx + 1)
        }
      }
      if (!content.startsWith('LXMC_V1.0.0') && !jsonStr.trim().startsWith('{')) {
        this.showToastMsg('无法识别的歌单文件格式')
        return
      }
      const parsed = JSON.parse(jsonStr) as Record<string, Object>
      const name = String(parsed['name'] ?? '导入歌单')
      const songs = parsed['songs'] as Object[] | undefined
      if (!(songs instanceof Array) || songs.length === 0) {
        this.showToastMsg('未找到歌曲数据')
        return
      }
      const playlistId = await this.db.createPlaylist(name)
      if (!playlistId) {
        this.showToastMsg('创建歌单失败')
        return
      }
      let addedCount = 0
      for (let i = 0; i < songs.length; i++) {
        const s = songs[i] as Record<string, Object>
        const song: SongInfo = {
          songId: String(s['songId'] ?? ''),
          songName: String(s['songName'] ?? ''),
          artist: String(s['artist'] ?? ''),
          album: String(s['album'] ?? ''),
          coverUrl: String(s['coverUrl'] ?? ''),
          source: String(s['source'] ?? 'kg'),
          playUrl: String(s['playUrl'] ?? ''),
        }
        if (song.songId && song.songName) {
          await this.db.addSongToPlaylist(playlistId, song)
          addedCount++
        }
      }
      await this.loadPlaylists()
      this.showToastMsg(`已导入歌单「${name}」(${addedCount}首)`)
    } catch (e) {
      console.error('[XuanchuangTab] importPlaylist failed:', e)
      this.showToastMsg('导入歌单失败，请检查文件格式')
    }
  }

  // ===== 导出歌单到选择路径 =====
  private async exportPlaylistToFile(playlist: Playlist) {
    try {
      const songs = await this.db.getPlaylistSongs(playlist.id)
      const jsonStr = JSON.stringify({
        name: playlist.name,
        exportTime: new Date().toISOString(),
        songCount: songs.length,
        songs: songs,
      })
      const documentPicker = new picker.DocumentViewPicker()
      const uris = await documentPicker.save({
        fileName: `${playlist.name.replace(/[\/\\:*?"<>|]/g, '_')}.json`,
        fileKind: 0,
      } as picker.DocumentSaveOptions)
      if (!uris || uris.length === 0) return
      const saveUri = uris[0]
      const file = fileIo.openSync(saveUri, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(file.fd, jsonStr)
      fileIo.closeSync(file.fd)
      this.showToastMsg('歌单导出成功')
    } catch (e) {
      console.error('[XuanchuangTab] exportPlaylistToFile failed:', e)
      this.showToastMsg('导出失败')
    }
  }

  private async removeSongFromPlaylist(song: SongInfo) {
    if (!this.selectedPlaylist) return
    await this.db.removeSongFromPlaylist(this.selectedPlaylist.id, song.songId, song.source)
    await this.reloadPlaylistSongs()
    await this.loadPlaylists()
  }

  // ===== 歌单导出 =====
  private async exportPlaylist(playlist: Playlist, format: string): Promise<void> {
    try {
      const songs = await this.db.getPlaylistSongs(playlist.id)

      const exportDir = '/SHMY/Playlist/'
      try {
        fileIo.mkdirSync(exportDir)
      } catch (_e) {
      }

      const safeName = playlist.name.replace(/[\/\\:*?"<>|]/g, '_')

      if (format === 'json') {
        const jsonStr: string = JSON.stringify({
          name: playlist.name,
          exportTime: new Date().toISOString(),
          songCount: songs.length,
          songs: songs,
        })
        const jsonFilePath: string = exportDir + safeName + '.json'
        const jsonFile = fileIo.openSync(jsonFilePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
        fileIo.writeSync(jsonFile.fd, jsonStr)
        fileIo.closeSync(jsonFile.fd)
        this.showToastMsg(`已导出: ${exportDir}${safeName}.json`)
      } else if (format === 'lxmc') {
        const header: string = 'LXMC_V1.0.0'
        const lxmcJson: string = JSON.stringify({
          name: playlist.name,
          exportTime: new Date().toISOString(),
          songCount: songs.length,
          songs: songs,
        })
        const lxmcContent: string = header + '\n' + lxmcJson
        const lxmcFilePath: string = exportDir + safeName + '.lxmc'
        const lxmcFile = fileIo.openSync(lxmcFilePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
        fileIo.writeSync(lxmcFile.fd, lxmcContent)
        fileIo.closeSync(lxmcFile.fd)
        this.showToastMsg(`已导出: ${exportDir}${safeName}.lxmc`)
      }

      this.showExportDialog = false
    } catch (e) {
      console.error('[XuanchuangTab] exportPlaylist failed:', e)
      this.showToastMsg('导出失败，请检查存储权限')
    }
  }

  private formatFileSize(bytes: number): string {
    if (bytes <= 0) return ''
    if (bytes < 1024) return bytes + 'B'
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + 'KB'
    return (bytes / (1024 * 1024)).toFixed(1) + 'MB'
  }

  private showToastMsg(msg: string): void {
    promptAction.showToast({ message: msg, duration: 2000 })
  }

  // 彻底退出应用
  private exitApp(): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext
      ctx.terminateSelf()
    } catch (e) {
      console.error('[XuanchuangTab] exit app failed:', e)
      this.showToastMsg('退出失败')
    }
  }

  // 重启应用
  private restartApp(): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext
      ctx.startAbility({
        bundleName: ctx.abilityInfo.bundleName,
        abilityName: ctx.abilityInfo.name
      })
      ctx.terminateSelf()
    } catch (e) {
      console.error('[XuanchuangTab] restart app failed:', e)
      this.showToastMsg('重启失败')
    }
  }

  // ===== 统一的 Section Header Builder =====
  // 自建歌单和本地音乐使用相同的 header 样式
  @Builder
  SectionHeader(title: string, count: number, expanded: boolean,
    onToggleExpand: () => void, onAdd?: () => void) {
    Row() {
      Row({ space: 8 }) {
        Text(title)
          .fontSize(18)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Bold)

        Text(`${count} ${title === '自建歌单' ? '个' : '首'}`)
          .fontSize(13)
          .fontColor(this.themeTextSecondary)
      }
      .layoutWeight(1)

      // 添加按钮（如果提供了 onAdd 回调）
      if (onAdd) {
        if (this.supportImmersive) {
          Row() {
            Image($rawfile('sum.svg'))
              .width(18)
              .height(18)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(Color.Transparent)
          .systemMaterial(MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN))
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            onAdd()
          })
        } else {
          Row() {
            Image($rawfile('sum.svg'))
              .width(18)
              .height(18)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(Color.Transparent)
          .backgroundEffect(MaterialCompat.effect(this.isDarkMode, this.themeCardBg, MaterialCompatStyle.THIN))
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            onAdd()
          })
        }
      }

      // 展开/收起箭头
      Row() {
        SymbolGlyph(expanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(16)
          .fontColor([this.themeTextPrimary])
      }
      .width(32)
      .height(32)
      .justifyContent(FlexAlign.Center)
      .margin({ left: onAdd ? 4 : 0 })
      .onClick(() => {
        onToggleExpand()
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  // 当前长按弹窗的操作列表
  private get floatingActions(): FloatingAction[] {
    const isCloud = this.floatingSong?.source === 'webdav'
    const actions: FloatingAction[] = [
      { icon: $r('sys.symbol.forward_end_fill'), label: '下首播放', action: 'play_next' },
      { icon: $r('sys.symbol.list_bullet'), label: '移动到歌单', action: 'move_playlist' },
      { icon: $r('sys.symbol.plus_square'), label: '复制到歌单', action: 'copy_playlist' },
      { icon: $r('sys.symbol.chevron_up'), label: '调整位置', action: 'reorder' },
      { icon: $r('sys.symbol.share'), label: '分享歌曲至', action: 'share_song' },
    ]
    if (!isCloud) {
      actions.push({ icon: $r('sys.symbol.trash'), label: '移除歌曲', action: 'delete_song', isDanger: true })
    }
    return actions
  }

  private async handleFloatingAction(action: string, song: SongInfo): Promise<void> {
    this.showFloatingPopup = false

    const isCloud = song.source === 'webdav'

    switch (action) {
      case 'play_next':
        PlayerStore.insertNext(song)
        this.showToastMsg('已添加到下一首播放')
        break
      case 'favorite':
        const added = await this.db.addFavorite(song)
        this.showToastMsg(added ? '已添加到收藏' : '已在收藏中')
        await this.loadFavorites()
        break
      case 'move_playlist':
        this.movePlaylistTarget = song
        this.showMovePlaylistDialog = true
        break
      case 'copy_playlist':
        this.copyPlaylistTarget = song
        this.showCopyPlaylistDialog = true
        break
      case 'reorder':
        this.floatingSong = song
        this.showReorderDialog = true
        break
      case 'delete_song':
        if (isCloud) {
          this.showToastMsg('云端歌曲无法从应用内删除')
        } else if (this.subPage === 'localMusicDetail') {
          // 本地音乐存在 local_music 表，不在 playlist_song 表：必须走本地删除
          const localId = song.songId.replace('local_', '')
          await this.db.removeLocalMusic(localId)
          await this.loadLocalMusic()
          this.showToastMsg('已从本地音乐移除')
        } else {
          await this.removeSongFromPlaylist(song)
          this.showToastMsg('已从歌单删除')
        }
        break
      case 'share_song':
        this.shareSong(song)
        break
      case 'song_info':
        this.showSongInfoDialog(song)
        break
      case 'view_artist':
        this.showToastMsg('功能开发中')
        break
      case 'view_album':
        this.showToastMsg('功能开发中')
        break
      default:
        break
    }
  }

  // 生成歌曲唯一 key
  private songKey(song: SongInfo): string {
    return `${song.songId}|${song.source}`
  }

  // 进入多选模式
  enterMultiSelectMode(): void {
    this.multiSelectMode = true
    this.selectedSongKeys = new Set()
  }

  // 退出多选模式
  exitMultiSelectMode(): void {
    this.multiSelectMode = false
    this.selectedSongKeys = new Set()
  }

  // 切换某首歌的勾选状态
  toggleSongSelect(song: SongInfo): void {
    const key = this.songKey(song)
    const newSet = new Set(this.selectedSongKeys)
    if (newSet.has(key)) {
      newSet.delete(key)
    } else {
      newSet.add(key)
    }
    this.selectedSongKeys = newSet
  }

  // 判断歌曲是否被选中
  isSongSelected(song: SongInfo): boolean {
    return this.selectedSongKeys.has(this.songKey(song))
  }

  // 获取当前列表中所有选中的歌曲
  private getSelectedSongs(): SongInfo[] {
    const result: SongInfo[] = []
    const seen = new Set<string>()
    const collect = (songs: SongInfo[]) => {
      for (let i = 0; i < songs.length; i++) {
        const k = this.songKey(songs[i])
        if (this.selectedSongKeys.has(k) && !seen.has(k)) {
          seen.add(k)
          result.push(songs[i])
        }
      }
    }
    if (this.subPage === 'playlistDetail') {
      collect(this.playlistSongs)
    } else if (this.subPage === 'localMusicDetail') {
      const localSongs: SongInfo[] = this.localMusicList.map((lm): SongInfo => ({
        songId: 'local_' + lm.id, songName: lm.songName || lm.fileName.replace(/\.[^.]+$/, ''),
        artist: lm.artist || '本地音乐', album: '', coverUrl: lm.coverUrl,
        source: 'local', playUrl: lm.filePath, lyric: lm.lyric || '',
      }))
      collect(localSongs)
    }
    return result
  }

  // 全选/取消全选
  toggleSelectAll(): void {
    let allSongs: SongInfo[] = []
    if (this.subPage === 'playlistDetail') {
      allSongs = this.playlistSongs
    } else if (this.subPage === 'localMusicDetail') {
      allSongs = this.localMusicList.map((lm): SongInfo => ({
        songId: 'local_' + lm.id, songName: lm.songName || lm.fileName.replace(/\.[^.]+$/, ''),
        artist: lm.artist || '本地音乐', album: '', coverUrl: lm.coverUrl,
        source: 'local', playUrl: lm.filePath, lyric: lm.lyric || '',
      }))
    }
    if (this.selectedSongKeys.size === allSongs.length && allSongs.length > 0) {
      this.selectedSongKeys = new Set()
    } else {
      const newSet = new Set<string>()
      for (let i = 0; i < allSongs.length; i++) {
        newSet.add(this.songKey(allSongs[i]))
      }
      this.selectedSongKeys = newSet
    }
  }

  // 多选模式下处理长按（弹出多选气泡弹窗）
  private handleMultiSelectLongPress(song: SongInfo): void {
    // 确保该歌曲已被选中
    if (!this.isSongSelected(song)) {
      this.toggleSongSelect(song)
    }
    this.floatingSong = song
    this.showFloatingPopup = true
  }

  // 批量移动到歌单
  private async batchMoveToPlaylist(playlist: Playlist): Promise<void> {
    const songs = this.getSelectedSongs()
    if (songs.length === 0) {
      this.showToastMsg('请先选择歌曲')
      return
    }
    for (let i = 0; i < songs.length; i++) {
      await this.db.addSongToPlaylist(playlist.id, songs[i])
      await this.removeSongFromPlaylist(songs[i])
    }
    this.showToastMsg(`已移动 ${songs.length} 首歌曲到「${playlist.name}」`)
    this.showMovePlaylistDialog = false
    this.movePlaylistTarget = null
    this.exitMultiSelectMode()
    if (this.subPage === 'playlistDetail') {
      await this.reloadPlaylistSongs()
    }
    await this.loadPlaylists()
  }

  // 批量复制到歌单
  private async batchCopyToPlaylist(playlist: Playlist): Promise<void> {
    const songs = this.getSelectedSongs()
    if (songs.length === 0) {
      this.showToastMsg('请先选择歌曲')
      return
    }
    for (let i = 0; i < songs.length; i++) {
      await this.db.addSongToPlaylist(playlist.id, songs[i])
    }
    this.showToastMsg(`已复制 ${songs.length} 首歌曲到「${playlist.name}」`)
    this.showCopyPlaylistDialog = false
    this.copyPlaylistTarget = null
    this.exitMultiSelectMode()
    await this.loadPlaylists()
  }

  // 批量彻底移除
  private async batchRemoveSongs(): Promise<void> {
    const songs = this.getSelectedSongs()
    if (songs.length === 0) {
      this.showToastMsg('请先选择歌曲')
      return
    }
    const count = songs.length
    promptAction.showDialog({
      title: '移除歌曲',
      message: `确定要移除选中的 ${count} 首歌曲吗？`,
      buttons: [
        { text: '取消', color: this.themeTextSecondary },
        { text: '移除', color: '#F44336' },
      ],
    }).then(async (result) => {
      if (result.index === 1) {
        if (this.subPage === 'localMusicDetail') {
          // 本地音乐：从 local_music 表删除
          for (let i = 0; i < songs.length; i++) {
            const localId = songs[i].songId.replace('local_', '')
            await this.db.removeLocalMusic(localId)
          }
          await this.loadLocalMusic()
        } else {
          // 自建歌单：从歌单中移除
          for (let i = 0; i < songs.length; i++) {
            await this.removeSongFromPlaylist(songs[i])
          }
          if (this.subPage === 'playlistDetail') {
            await this.reloadPlaylistSongs()
          }
          await this.loadPlaylists()
        }
        this.showToastMsg(`已移除 ${count} 首歌曲`)
        this.exitMultiSelectMode()
      }
    })
  }

  // 批量分享
  private async batchShareSongs(): Promise<void> {
    const songs = this.getSelectedSongs()
    if (songs.length === 0) {
      this.showToastMsg('请先选择歌曲')
      return
    }
    try {
      const lines = songs.map((s) => this.buildShareText(s))
      const shareText = lines.join('\n')
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: shareText,
        title: `分享 ${songs.length} 首歌曲`,
        description: `${songs.length} 首歌曲`,
      })
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData)
      const context = getContext(this) as common.UIAbilityContext
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL,
      })
    } catch (e) {
      console.error('[XuanchuangTab] batchShareSongs failed:', e)
      this.showToastMsg('分享失败')
    }
  }

  // ===== 歌单排序气泡弹窗 =====
  @Builder
  SortModePopup() {
    Column({ space: 4 }) {
      if (this.sortPopupTarget === 'playlist') {
        this.SortModeOption('歌曲新在前', 'new', this.playlistSortMode,
          (mode: string) => { this.applyPlaylistSort(mode) })
        this.SortModeOption('歌曲旧在前', 'old', this.playlistSortMode,
          (mode: string) => { this.applyPlaylistSort(mode) })
        this.SortModeOption('按字母排序', 'alpha', this.playlistSortMode,
          (mode: string) => { this.applyPlaylistSort(mode) })
      } else {
        this.SortModeOption('歌曲新在前', 'new', this.localSortMode,
          (mode: string) => { this.applyLocalSort(mode) })
        this.SortModeOption('歌曲旧在前', 'old', this.localSortMode,
          (mode: string) => { this.applyLocalSort(mode) })
        this.SortModeOption('按字母排序', 'alpha', this.localSortMode,
          (mode: string) => { this.applyLocalSort(mode) })
      }
    }
    .width(150)
    .padding(6)
    .backgroundColor(this.themeCardBg)
    .borderRadius(12)
    .shadow({ radius: 12, color: '#00000020', offsetY: 4 })
  }

  @Builder
  SortModeOption(label: string, value: string, currentMode: string, onSelect: (mode: string) => void) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(13)
        .fontColor(currentMode === value ? this.themePrimary : this.themeTextPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (currentMode === value) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(13)
          .fontColor([this.themePrimary])
          .flexShrink(0)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(currentMode === value ? this.themePrimaryLight : this.themeCardBg)
    .borderRadius(8)
    .justifyContent(FlexAlign.SpaceBetween)
    .onClick(() => {
      onSelect(value)
    })
  }

  @Builder
  SongActionPopupBuilder() {
    Column() {
      if (this.floatingSong) {
        Row({ space: 12 }) {
          if (this.floatingSong.coverUrl && this.floatingSong.coverUrl.length > 0) {
            CoverImage({
              url: this.floatingSong.coverUrl,
              coverWidth: 40,
              coverHeight: 40,
              radius: 8
            })
          } else {
            Row() {
              Image($r('app.media.music_note'))
                .width(18)
                .height(18)
            }
            .width(40)
            .height(40)
            .borderRadius(8)
            .backgroundColor(this.themePrimary)
            .justifyContent(FlexAlign.Center)
          }

          Column({ space: 2 }) {
            Text(this.multiSelectMode
              ? `已选 ${this.selectedSongKeys.size} 项`
              : this.floatingSong.songName)
              .fontSize(14)
              .fontColor(this.themeTextPrimary)
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.multiSelectMode
              ? '对选中歌曲批量操作'
              : this.floatingSong.artist)
              .fontSize(11)
              .fontColor(this.themeTextSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 4 })

        Divider()
          .width('100%')
          .color(this.themeDivider)
          .margin({ left: 12, right: 12 })

        Column({ space: 0 }) {
          if (this.multiSelectMode) {
            // ===== 多选模式：批量操作 =====
            // 移动到歌单（本地音乐详情页不显示，因为本地音乐不在歌单中）
            if (this.subPage !== 'localMusicDetail') {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.list_bullet'))
                  .fontSize(18)
                  .fontColor([this.themePrimary])
                Text('移动到歌单')
                  .fontSize(15)
                  .fontColor(this.themeTextPrimary)
                  .layoutWeight(1)
              }
              .width('100%')
              .height(44)
              .padding({ left: 16, right: 16 })
              .onClick(() => {
                this.showFloatingPopup = false
                this.movePlaylistTarget = this.floatingSong
                this.pendingMovePlaylist = true
              })
              Divider().color(this.themeDivider).margin({ left: 44, right: 16 })
            }

            // 复制到歌单
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.plus_square'))
                .fontSize(18)
                .fontColor([this.themePrimary])
              Text('复制到歌单')
                .fontSize(15)
                .fontColor(this.themeTextPrimary)
                .layoutWeight(1)
            }
            .width('100%')
            .height(44)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.showFloatingPopup = false
              this.copyPlaylistTarget = this.floatingSong
              this.pendingCopyPlaylist = true
            })
            Divider().color(this.themeDivider).margin({ left: 44, right: 16 })

            // 分享至
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.share'))
                .fontSize(18)
                .fontColor([this.themePrimary])
              Text('分享至')
                .fontSize(15)
                .fontColor(this.themeTextPrimary)
                .layoutWeight(1)
            }
            .width('100%')
            .height(44)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.showFloatingPopup = false
              this.batchShareSongs()
            })

            // 彻底移除
            Divider().color(this.themeDivider).margin({ left: 44, right: 16 })
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(18)
                .fontColor([this.themeDanger])
              Text('移除歌曲')
                .fontSize(15)
                .fontColor(this.themeDanger)
                .fontWeight(FontWeight.Medium)
                .layoutWeight(1)
            }
            .width('100%')
            .height(44)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.showFloatingPopup = false
              this.batchRemoveSongs()
            })
          } else {
            // ===== 单选模式：原有操作 =====
            // 下首播放
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.forward_end_fill'))
                .fontSize(18)
                .fontColor([this.themePrimary])
              Text('下首播放')
                .fontSize(15)
                .fontColor(this.themeTextPrimary)
                .layoutWeight(1)
            }
            .width('100%')
            .height(44)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.showFloatingPopup = false
              this.handleFloatingAction('play_next', this.floatingSong!)
            })
            Divider().color(this.themeDivider).margin({ left: 44, right: 16 })

            // 调整位置
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.chevron_up'))
                .fontSize(18)
                .fontColor([this.themePrimary])
              Text('调整位置')
                .fontSize(15)
                .fontColor(this.themeTextPrimary)
                .layoutWeight(1)
            }
            .width('100%')
            .height(44)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.showFloatingPopup = false
              this.pendingReorder = true
            })
            Divider().color(this.themeDivider).margin({ left: 44, right: 16 })

            // 分享歌曲至
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.share'))
                .fontSize(18)
                .fontColor([this.themePrimary])
              Text('分享歌曲至')
                .fontSize(15)
                .fontColor(this.themeTextPrimary)
                .layoutWeight(1)
            }
            .width('100%')
            .height(44)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.showFloatingPopup = false
              this.handleFloatingAction('share_song', this.floatingSong!)
            })

            // 移除歌曲（仅非云端歌单显示）
            if (this.floatingSong?.source !== 'webdav') {
              Divider().color(this.themeDivider).margin({ left: 44, right: 16 })
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(18)
                  .fontColor([this.themeDanger])
                Text('移除歌曲')
                  .fontSize(15)
                  .fontColor(this.themeDanger)
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)
              }
              .width('100%')
              .height(44)
              .padding({ left: 16, right: 16 })
              .onClick(() => {
                this.showFloatingPopup = false
                this.handleFloatingAction('delete_song', this.floatingSong!)
              })
            }
          }
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })
      }
    }
    .width('100%')
    .backgroundColor(this.themeCardBg)
    .borderRadius(14)
    .shadow({ radius: 16, color: '#00000020', offsetY: 4 })
  }

  private async shareSong(song: SongInfo): Promise<void> {
    try {
      const shareText = this.buildShareText(song)
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: shareText,
        title: `分享歌曲：${song.songName}`,
        description: `${song.songName} - ${song.artist}`,
      })
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData)
      const context = getContext(this) as common.UIAbilityContext
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL,
      })
    } catch (e) {
      console.error('[XuanchuangTab] shareSong failed:', e)
      // 降级方案：复制到剪贴板
      try {
        const shareText = this.buildShareText(song)
        const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, shareText)
        const systemPasteboard = pasteboard.getSystemPasteboard()
        await systemPasteboard.setDataSync(pasteData)
        this.showToastMsg('分享面板拉起失败，已复制到剪贴板')
      } catch (_) {
        this.showToastMsg('分享失败')
      }
    }
  }

  // 构造分享文本（含原平台链接）
  private buildShareText(song: SongInfo): string {
    const shareUrl = this.getShareUrl(song)
    if (shareUrl) {
      return `♫ ${song.songName} - ${song.artist}\n${shareUrl}`
    }
    return `♫ ${song.songName} - ${song.artist}\n快来听这首歌吧！`
  }

  // 根据音源生成原平台详情页链接
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

  private showSongInfoDialog(song: SongInfo): void {
    this.songInfoSong = song
    this.showSongInfo = true
  }

  private async pickPlaylistCover(): Promise<void> {
    try {
      const photoPicker = new picker.PhotoViewPicker()
      const result = await photoPicker.select({ maxSelectNumber: 1 })
      if (result.photoUris && result.photoUris.length > 0) {
        this.editPlaylistCoverUri = result.photoUris[0]
      }
    } catch (e) {
      console.error('[XuanchuangTab] pick cover failed:', e)
    }
  }

  private async doSaveEditPlaylist(): Promise<void> {
    if (!this.editPlaylistName.trim()) {
      this.showToastMsg('歌单名称不能为空')
      return
    }
    if (this.editPlaylistTarget) {
      await this.db.updatePlaylist(
        this.editPlaylistTarget.id,
        this.editPlaylistName.trim(),
        this.editPlaylistCoverUri
      )
      this.showToastMsg('歌单已更新')
    } else {
      const id = await this.db.createPlaylist(this.editPlaylistName.trim())
      if (id && this.editPlaylistCoverUri) {
        await this.db.updatePlaylist(id, this.editPlaylistName.trim(), this.editPlaylistCoverUri)
      }
      this.showToastMsg('歌单已创建')
    }
    this.showEditPlaylistSheet = false
    this.editPlaylistTarget = null
    await this.loadPlaylists()
  }

  // 歌单操作底部弹窗内容
  @Builder
  PlaylistActionSheet() {
    Column() {
      if (this.playlistActionTarget) {
        // 歌单信息头部
        Row({ space: 12 }) {
          Stack() {
            if (this.playlistCovers.has(this.playlistActionTarget.id) && this.playlistCovers.get(this.playlistActionTarget.id)!.length > 0) {
              Image(this.playlistCovers.get(this.playlistActionTarget.id)!)
                .width(48).height(48).borderRadius(8).objectFit(ImageFit.Cover)
                .backgroundColor(this.themePlaceholder)
            } else {
              Row() {
                Image($r('app.media.music_note')).width(24).height(24)
              }
              .width(48).height(48).borderRadius(8)
              .backgroundColor(this.themePlaceholder).justifyContent(FlexAlign.Center)
            }
          }.flexShrink(0)

          Column({ space: 2 }) {
            Text(this.playlistActionTarget.name)
              .fontSize(15).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Bold)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${this.playlistActionTarget.songCount} 首`)
              .fontSize(12).fontColor(this.themeTextSecondary)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start).layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })

        Divider().width('100%').color(this.themeDivider)

        // 操作列表
        Column({ space: 0 }) {
          // 播放歌单
          Row({ space: 12 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.play_fill')).fontSize(18).fontColor([this.themePrimary])
            }
            .width(36).height(36).borderRadius(9)
            .backgroundColor(this.themePrimaryLight).justifyContent(FlexAlign.Center).flexShrink(0)

            Text('播放歌单').fontSize(14).fontColor(this.themeTextPrimary).layoutWeight(1)
          }
          .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onClick(() => {
            this.showPlaylistActionSheet = false
            this.playPlaylist(this.playlistActionTarget!)
          })

          if (this.playlistActionTarget && !this.playlistActionTarget.id.startsWith('cloud_')) {
            Divider().width('100%').color(this.themeDivider).margin({ left: 16, right: 16 })

            // 编辑歌单
            Row({ space: 12 }) {
              Row() {
                SymbolGlyph($r('sys.symbol.gearshape')).fontSize(18).fontColor([this.themePrimary])
              }
              .width(36).height(36).borderRadius(9)
              .backgroundColor(this.themePrimaryLight).justifyContent(FlexAlign.Center).flexShrink(0)

              Text('编辑歌单').fontSize(14).fontColor(this.themeTextPrimary).layoutWeight(1)
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => {
              this.showPlaylistActionSheet = false
              this.editPlaylistTarget = this.playlistActionTarget
              this.editPlaylistName = this.playlistActionTarget!.name
              this.editPlaylistCoverUri = this.playlistActionTarget!.coverUrl || ''
              this.showEditPlaylistSheet = true
            })

            Divider().width('100%').color(this.themeDivider).margin({ left: 16, right: 16 })

            // 排序歌单
            Row({ space: 12 }) {
              Row() {
                SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(18).fontColor([this.themePrimary])
              }
              .width(36).height(36).borderRadius(9)
              .backgroundColor(this.themePrimaryLight).justifyContent(FlexAlign.Center).flexShrink(0)

              Text('排序歌单').fontSize(14).fontColor(this.themeTextPrimary).layoutWeight(1)
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => {
              this.showPlaylistActionSheet = false
              this.reorderMode = !this.reorderMode
              if (this.reorderMode) {
                this.reorderedIds = this.playlists.map(p => p.id)
                this.showToastMsg('长按拖动歌单排序，点击空白处保存')
              } else {
                this.db.reorderPlaylists(this.reorderedIds)
                this.loadPlaylists()
                this.showToastMsg('排序已保存')
              }
            })

            Divider().width('100%').color(this.themeDivider).margin({ left: 16, right: 16 })

            // 删除歌单
            Row({ space: 12 }) {
              Row() {
                SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor([this.themeDanger])
              }
              .width(36).height(36).borderRadius(9)
              .backgroundColor(this.themePlaceholder).justifyContent(FlexAlign.Center).flexShrink(0)

              Text('删除歌单').fontSize(14).fontColor(this.themeDanger).layoutWeight(1)
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => {
              this.showPlaylistActionSheet = false
              this.deletePlaylist(this.playlistActionTarget!.id)
            })
          }
        }
        .width('100%')

        Column().height(16)
      }
    }
  }

  private async doReorder(): Promise<void> {
    if (!this.floatingSong) return
    const isCloud = this.subPage === 'cloudPlaylistDetail'
    const isLocal = this.subPage === 'localMusicDetail'
    const sourceSongs = isCloud ? this.cloudPlaylistSongs : (isLocal ? this.localMusicList.map((lm): SongInfo => ({
      songId: 'local_' + lm.id, songName: lm.songName, artist: lm.artist, album: '',
      coverUrl: lm.coverUrl, source: 'local', playUrl: lm.filePath, lyric: lm.lyric || '',
    })) : this.playlistSongs)
    const targetIndex = parseInt(this.reorderInput)
    if (isNaN(targetIndex) || targetIndex < 1 || targetIndex > sourceSongs.length) {
      this.showToastMsg('请输入有效序号')
      return
    }
    const currentIndex = sourceSongs.findIndex(s => s.songId === this.floatingSong!.songId && s.source === this.floatingSong!.source)
    if (currentIndex < 0) {
      this.showReorderDialog = false
      this.reorderInput = ''
      this.floatingSong = null
      return
    }
    const songs = sourceSongs.slice()
    const moved = songs.splice(currentIndex, 1)[0]
    songs.splice(targetIndex - 1, 0, moved)

    if (isCloud && this.selectedCloudPlaylist) {
      this.cloudPlaylistSongs = songs
      const orderKey = `cloud_playlist_order_${this.selectedCloudPlaylist.id}`
      const orderedIds = songs.map(s => s.songId)
      await this.db.setSetting(orderKey, JSON.stringify(orderedIds))
    } else if (isLocal) {
      // 本地音乐详情页：根据排序后的 songId 重新排列 localMusicList
      const orderedIds = songs.map(s => s.songId.replace('local_', ''))
      const idToItem = new Map(this.localMusicList.map(lm => [lm.id, lm]))
      const reordered: LocalMusicItem[] = []
      for (const id of orderedIds) {
        const item = idToItem.get(id)
        if (item) {
          reordered.push(item)
        }
      }
      // 补充未在排序列表中的项（防御性）
      for (const lm of this.localMusicList) {
        if (!orderedIds.includes(lm.id)) {
          reordered.push(lm)
        }
      }
      this.localMusicList = reordered
      await this.db.setSetting('local_music_order', JSON.stringify(orderedIds))
    } else {
      // 自建歌单详情页
      if (!this.selectedPlaylist) {
        // 兜底：无选中歌单，清理状态后退出，避免卡死
        this.showReorderDialog = false
        this.reorderInput = ''
        this.floatingSong = null
        this.showToastMsg('未找到歌单信息')
        return
      }
      this.playlistSongs = songs
      await this.db.updatePlaylistSongs(this.selectedPlaylist.id, songs)
    }

    this.showReorderDialog = false
    this.reorderInput = ''
    this.floatingSong = null
    this.showToastMsg('已调整位置')
  }

  build() {
    Stack() {
      Column() {
        if (this.subPage === 'main') {
          this.MainContent()
        } else if (this.subPage === 'playlistDetail') {
          this.PlaylistDetailContent()
        } else if (this.subPage === 'localMusicDetail') {
          this.LocalMusicDetailContent()
        } else if (this.subPage === 'cloudPlaylistDetail') {
          this.CloudPlaylistDetailContent()
        }

      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
      .alignItems(HorizontalAlign.Start)

      // Sheet trigger: 重命名歌单
      Row()
        .width(1)
        .height(1)
        .bindSheet($$this.showRenameDialog, this.RenamePlaylistSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: true,
          systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK),
          onDisappear: () => {
            this.showRenameDialog = false
          },
        })

      // Sheet trigger: 导出歌单
      Row()
        .width(1)
        .height(1)
        .bindSheet($$this.showExportDialog, this.ExportPlaylistSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: true,
          systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK),
          onDisappear: () => {
            this.showExportDialog = false
          },
        })

      // Sheet trigger: 歌单操作底部弹窗
      Row()
        .width(1)
        .height(1)
        .bindSheet($$this.showPlaylistActionSheet, this.PlaylistActionSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: true,
          systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK),
          onDisappear: () => {
            this.showPlaylistActionSheet = false
            this.playlistActionTarget = null
          },
        })

      // Sheet trigger: 移动歌单
      Row()
        .width(1)
        .height(1)
        .bindSheet($$this.showMovePlaylistDialog, this.MovePlaylistDialogSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: true,
          systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK),
          onDisappear: () => {
            this.showMovePlaylistDialog = false
            this.movePlaylistTarget = null
          },
        })

      // Sheet trigger: 复制到歌单
      Row()
        .width(1)
        .height(1)
        .bindSheet($$this.showCopyPlaylistDialog, this.CopyPlaylistDialogSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: true,
          systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK),
          onDisappear: () => {
            this.showCopyPlaylistDialog = false
            this.copyPlaylistTarget = null
          },
        })

      // Sheet trigger: 调整位置
      Row()
        .width(1)
        .height(1)
        .bindSheet($$this.showReorderDialog, this.ReorderDialogSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: true,
          systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK),
          onDisappear: () => {
            this.showReorderDialog = false
            this.reorderInput = ''
            this.floatingSong = null
          },
        })

      // Sheet trigger: 歌曲信息
      Row()
        .width(1)
        .height(1)
        .bindSheet($$this.showSongInfo, this.SongInfoSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: true,
          systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK),
          onDisappear: () => {
            this.showSongInfo = false
            this.songInfoSong = null
          },
        })

      // Song action sheet for playlist songs
      if (this.selectedSong) {
        SongActionSheet({
          song: this.selectedSong!,
          visible: this.showSongActionSheet,
          onDismiss: () => {
            this.showSongActionSheet = false
            this.selectedSong = null
          },
          onPlay: (song: SongInfo) => {
            this.playSong(song)
          },
          onAddFavorite: (song: SongInfo) => {
            this.db.addFavorite(song).then((result) => {
              if (result) {
                this.showToastMsg('已添加到收藏')
              } else {
                this.showToastMsg('已在收藏中')
              }
            })
          },
        })
      }

      // Sheet trigger: 编辑歌单
      Row()
        .width(1)
        .height(1)
        .bindSheet($$this.showEditPlaylistSheet, this.EditPlaylistSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: true,
          systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK),
          onDisappear: () => {
            this.editPlaylistTarget = null
          },
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  MainContent() {
    Refresh({ refreshing: $$this.refreshing, offset: 64 }) {
      Scroll() {
        Column({ space: 14 }) {
          // Section 1: 用户账号卡片
          this.UserAccountCard()

          // Section 2: 统计数据卡片
          if (this.showHomeStats) {
            this.StatsCard()
          }

          // Section 3: 自建歌单
          this.PlaylistsSectionV2()

          // Section 4: 本地歌单
          this.LocalMusicSimpleCard()

          // Section 5: 云端歌单
          this.CloudPlaylistSection()

          Column().height(168)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 28 })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .scrollBarColor('#CCCCCC')
      .scrollBarWidth(4)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
    }
    .width('100%')
    .layoutWeight(1)
    .onRefreshing(() => {
      this.refreshing = true
      this.loadAllData().then(() => {
        this.refreshing = false
      })
    })
  }

  // ===== 用户账号卡片 =====
  @Builder
  UserAccountCard() {
    Row({ space: 16 }) {
      // 左侧：头像 + 用户信息（点击登录）
      Row({ space: 16 }) {
        Stack() {
          // 头像：已登录且有头像用网络图片，否则用默认图标
          if (this.isLoggedIn && this.avatarUrl.length > 0) {
            Image(this.avatarUrl)
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

          // 未登录时显示登录引导角标
          if (!this.isLoggedIn) {
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
          if (this.loggingIn) {
            Row({ space: 6 }) {
              LoadingProgress().width(16).height(16).color(this.themePrimary)
              Text('登录中...')
                .fontSize(16)
                .fontColor(this.themeTextSecondary)
            }
          } else {
            Row({ space: 8 }) {
              Text(this.userName)
                .fontSize(18)
                .fontColor(this.themeTextPrimary)
                .fontWeight(FontWeight.Bold)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .flexShrink(1)

              // LV 等级徽章：文字镂空（显示底部背景色），背景填充区段颜色
              Stack() {
                Text(`LV${this.levelInfo.level}`)
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.themeCardBg)
              }
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(getLevelColor(this.levelInfo.level))
              .borderRadius(10)
              .onClick(() => {
                this.openLevelGuide()
              })
            }
            .width('100%')

            // 等级进度条
            Row({ space: 8 }) {
              Stack({ alignContent: Alignment.Start }) {
                Row()
                  .width('100%')
                  .height(5)
                  .borderRadius(2.5)
                  .backgroundColor(this.themeDivider)
                Row()
                  .width(`${this.levelInfo.percent}%`)
                  .height(5)
                  .borderRadius(2.5)
                  .backgroundColor(this.themePrimary)
                  .constraintSize({ minWidth: this.levelInfo.percent > 0 ? 3 : 0 })
              }
              .layoutWeight(1)
              .height(5)
              .constraintSize({ maxWidth: 120 })

              Text(`${this.levelInfo.current}/${this.levelInfo.need}`)
                .fontSize(11)
                .fontColor(this.themeTextSecondary)
            }
            .width('100%')

            // 个性签名
            Text(this.signature.length > 0 ? this.signature : '个性签名：编辑后展现更个性的你!')
              .fontSize(13)
              .fontColor(this.themeTextSecondary)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .onClick(() => {
                this.openSignatureEdit()
              })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .layoutWeight(1)
      .onClick(() => {
        if (this.isLoggedIn) {
          // 已登录，不做操作（或可弹出退出登录选项）
        } else if (!this.loggingIn) {
          this.doLogin()
        }
      })

      // 右侧：设置图标（无字样），点击以全屏侧边栏形式展开设置页
      Row() {
        Image($rawfile('sz.svg'))
          .width(18)
          .height(18)
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        AppStorage.setOrCreate('showSettingsSidebar', true)
      })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.themeCardBg)
    .borderRadius(16)
    .shadow({ radius: 4, color: '#00000008', offsetY: 2 })
  }

  private async doLogin() {
    this.loggingIn = true
    try {
      const context = this.getUIContext().getHostContext() as common.Context
      const result = await AccountManager.login(context)
      if (result.success && result.userInfo) {
        this.userName = result.userInfo.displayName
        this.avatarUrl = result.userInfo.avatarUri
        this.userAccount = '已登录'
        this.isLoggedIn = true
        // 登录后加载 WebDAV 配置和同步用户画像
        this.checkWebdavConfig()
        this.loadProfileData()
        this.syncProfileFromWebDAV()
        this.showToastMsg('登录成功')
      } else {
        this.showToastMsg(result.error || '登录失败')
      }
    } finally {
      this.loggingIn = false
    }
  }

  private async doLogout() {
    await AccountManager.logout()
    // 重置听歌等级管理器内存状态
    ListeningLevelManager.getInstance().reset()
    // 重置自建 API 模式
    MusicApi.setSelfHostedMode(false, '')
    // 清除本地 UI 状态
    this.userName = '点击登录'
    this.userAccount = ''
    this.avatarUrl = ''
    this.isLoggedIn = false
    this.showAccountMenu = false
    this.webdavConfigured = false
    this.cloudPlaylists = []
    this.playlists = []
    this.favorites = []
    this.localMusicList = []
    this.playlistCount = 0
    this.listenTime = 0
    this.listenSongs = 0
    this.levelInfo = { level: 1, current: 0, need: 1160, totalSeconds: 0, percent: 0 }
    this.signature = ''
    this.showToastMsg('已退出登录，数据已清除')
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
          this.showAccountMenu = false
          this.exitApp()
        })

      Divider().color(this.themeDivider).strokeWidth(0.5)

      Text('重启软件')
        .fontSize(15)
        .fontColor(this.themeTextPrimary)
        .width('100%')
        .height(44)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.showAccountMenu = false
          this.restartApp()
        })

      Divider().color(this.themeDivider).strokeWidth(0.5)

      Text('退出登录')
        .fontSize(15)
        .fontColor('#FF6B6B')
        .width('100%')
        .height(44)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.doLogout()
        })
    }
    .width(120)
    .borderRadius(10)
    .padding({ top: 4, bottom: 4 })
  }

  // ===== 统计数据卡片 =====
  @Builder
  StatsCard() {
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

  // ===== 歌单列表 Section V2（区块包裹：题头与子歌单同一容器） =====
  @Builder
  PlaylistsSectionV2() {
    Column({ space: 10 }) {
      Row() {
        Text(this.reorderMode ? '拖动排序' : '自建歌单')
          .fontSize(18)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Bold)

        Text(`${this.playlists.length} 个`)
          .fontSize(13)
          .fontColor(this.themeTextSecondary)
          .margin({ left: 8 })

        Blank().layoutWeight(1)

        if (this.reorderMode) {
          Row() {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(15).fontColor([Color.White])
          }
          .width(52).height(26).borderRadius(13)
          .backgroundColor('#4CAF50')
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.db.reorderPlaylists(this.reorderedIds)
            this.reorderMode = false
            this.loadPlaylists()
            this.showToastMsg('排序已保存')
          })
        } else {
          if (this.supportImmersive) {
            Row() {
              Image($rawfile('sum.svg'))
                .width(16)
                .height(16)
            }
            .width(28)
            .height(28)
            .borderRadius(14)
            .backgroundColor(Color.Transparent)
            .systemMaterial(MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN))
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.editPlaylistTarget = null
              this.editPlaylistName = ''
              this.editPlaylistCoverUri = ''
              this.showEditPlaylistSheet = true
            })
          } else {
            Row() {
              Image($rawfile('sum.svg'))
                .width(16)
                .height(16)
            }
            .width(28)
            .height(28)
            .borderRadius(14)
            .backgroundColor(Color.Transparent)
            .backgroundEffect(MaterialCompat.effect(this.isDarkMode, this.themeCardBg, MaterialCompatStyle.THIN))
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.editPlaylistTarget = null
              this.editPlaylistName = ''
              this.editPlaylistCoverUri = ''
              this.showEditPlaylistSheet = true
            })
          }
        }
      }
      .width('100%')

      if (this.playlists.length === 0) {
        Column({ space: 8 }) {
          Text('还没有创建歌单')
            .fontSize(14)
            .fontColor(this.themeTextSecondary)
          Text('点击 + 创建你的第一个歌单')
            .fontSize(12)
            .fontColor(this.themeTextSecondary)
        }
        .width('100%')
        .height(80)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
          ForEach(this.reorderMode ? this.reorderedIds : this.playlists.map(p => p.id), (id: string, index: number) => {
            Column() {
              if (index > 0) {
                Divider()
                  .color(this.themeDivider)
                  .margin({ left: 64 })
              }
              if (this.playlists.find(p => p.id === id)) {
                this.PlaylistCardV2(this.playlists.find(p => p.id === id)!)
              }
            }
          }, (id: string) => id)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeCardBg)
    .borderRadius(16)
  }

  // ===== 歌单卡片 V2 =====
  @Builder
  PlaylistCardV2(playlist: Playlist) {
    Row({ space: 10 }) {
      // 排序模式：拖拽手柄（长按+拖动）
      if (this.reorderMode) {
        Row() {
          SymbolGlyph($r('sys.symbol.list_bullet'))
            .fontSize(20).fontColor([
              this.draggingPlaylistId === playlist.id ? this.themePrimary : this.themeTextSecondary
            ])
        }
        .width(32).height(32)
        .justifyContent(FlexAlign.Center)
        .flexShrink(0)
        .gesture(
          GestureGroup(GestureMode.Sequence,
            LongPressGesture({ repeat: false, duration: 300 })
              .onAction(() => {
                this.draggingPlaylistId = playlist.id
                this.dragOffset = 0
                this.accumulatedOffset = 0
              }),
            PanGesture({ direction: PanDirection.Vertical, distance: 15 })
              .onActionUpdate((event: GestureEvent) => {
                if (this.draggingPlaylistId !== playlist.id) return
                const rawY = event.offsetY
                this.dragOffset = rawY - this.accumulatedOffset
                const cardHeight = 78
                const idx = this.reorderedIds.indexOf(playlist.id)
                if (this.dragOffset > cardHeight && idx < this.reorderedIds.length - 1) {
                  const tmp = this.reorderedIds[idx]
                  this.reorderedIds[idx] = this.reorderedIds[idx + 1]
                  this.reorderedIds[idx + 1] = tmp
                  this.reorderedIds = [...this.reorderedIds]
                  this.accumulatedOffset += cardHeight
                  this.dragOffset -= cardHeight
                } else if (this.dragOffset < -cardHeight && idx > 0) {
                  const tmp = this.reorderedIds[idx]
                  this.reorderedIds[idx] = this.reorderedIds[idx - 1]
                  this.reorderedIds[idx - 1] = tmp
                  this.reorderedIds = [...this.reorderedIds]
                  this.accumulatedOffset -= cardHeight
                  this.dragOffset += cardHeight
                }
              })
              .onActionEnd(() => {
                this.draggingPlaylistId = ''
                this.dragOffset = 0
                this.accumulatedOffset = 0
              })
          )
        )
      }

      Stack() {
        if (this.playlistCovers.has(playlist.id) && this.playlistCovers.get(playlist.id)!.length > 0) {
          CoverImage({
            url: this.playlistCovers.get(playlist.id)!,
            coverWidth: 52,
            coverHeight: 52,
            radius: 10
          })
        } else {
          Row() {
            Image($r('app.media.music_note'))
              .width(24)
              .height(24)
              .objectFit(ImageFit.Contain)
          }
          .width(52)
          .height(52)
          .borderRadius(10)
          .backgroundColor(this.themePlaceholder)
          .justifyContent(FlexAlign.Center)
        }
      }
      .flexShrink(0)

      Column({ space: 4 }) {
        Text(playlist.name)
          .fontSize(15)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 6 }) {
          Text(`${playlist.songCount} 首`)
            .fontSize(12)
            .fontColor(this.themeTextSecondary)

          Text('歌单')
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor('#607D8B')
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .borderRadius(4)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 播放按钮
      Row() {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(16)
          .fontColor([this.themePrimary])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(this.themePrimaryLight)
      .justifyContent(FlexAlign.Center)
      .flexShrink(0)
      .onClick(() => {
        this.playPlaylist(playlist)
      })

      Image($rawfile('jinxin_right.svg'))
        .width(16)
        .height(16)
        .objectFit(ImageFit.Contain)
        .fillColor(this.themeTextSecondary)
        .flexShrink(0)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .animation({ duration: 200 })
    .offset({ y: this.draggingPlaylistId === playlist.id ? this.dragOffset : 0 })
    .zIndex(this.draggingPlaylistId === playlist.id ? 10 : 0)
    .scale({ x: this.draggingPlaylistId === playlist.id ? 1.05 : 1, y: this.draggingPlaylistId === playlist.id ? 1.05 : 1 })
    .shadow({ radius: 6, color: this.draggingPlaylistId === playlist.id ? '#33000000' : Color.Transparent, offsetY: this.draggingPlaylistId === playlist.id ? 6 : 0 })
    .onClick(() => {
      if (this.reorderMode) {
        const idx = this.reorderedIds.indexOf(playlist.id)
        if (idx < this.reorderedIds.length - 1) {
          const tmp = this.reorderedIds[idx + 1]
          this.reorderedIds[idx + 1] = this.reorderedIds[idx]
          this.reorderedIds[idx] = tmp
          this.reorderedIds = [...this.reorderedIds]
        }
      } else {
        this.openPlaylistDetail(playlist)
      }
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 300 })
        .onAction(() => {
          this.playlistActionTarget = playlist
          this.showPlaylistActionSheet = true
        })
    )
  }

  // ===== 本地歌单区块（题头 + 单行入口） =====
  @Builder
  LocalMusicSimpleCard() {
    Column({ space: 10 }) {
      Row() {
        Text('本地歌单')
          .fontSize(18)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Bold)

        Text(`${this.localMusicList.length} 首`)
          .fontSize(13)
          .fontColor(this.themeTextSecondary)
          .margin({ left: 8 })

        Blank().layoutWeight(1)
      }
      .width('100%')

      // 单行入口：本地歌单统一入口
      Row({ space: 12 }) {
        // 封面：第一首歌的封面或默认图标
        Stack() {
          if (this.localMusicList.length > 0 && this.localMusicList[0].coverUrl) {
            Image(this.localMusicList[0].coverUrl)
              .width(52)
              .height(52)
              .borderRadius(10)
              .objectFit(ImageFit.Cover)
          } else {
            Row() {
              Image($r('app.media.music_note'))
                .width(24)
                .height(24)
                .objectFit(ImageFit.Contain)
            }
            .width(52)
            .height(52)
            .borderRadius(10)
            .backgroundColor(this.themePlaceholder)
            .justifyContent(FlexAlign.Center)
          }
        }
        .flexShrink(0)

        Column({ space: 4 }) {
          Text('本地音乐')
            .fontSize(15)
            .fontColor(this.themeTextPrimary)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: 6 }) {
            Text(`${this.localMusicList.length} 首`)
              .fontSize(12)
              .fontColor(this.themeTextSecondary)

            Text('本地')
              .fontSize(10)
              .fontColor(Color.White)
              .backgroundColor('#607D8B')
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .borderRadius(4)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 播放按钮
        Row() {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(16)
            .fontColor([this.themePrimary])
        }
        .width(32)
        .height(32)
        .borderRadius(16)
        .backgroundColor(this.themePrimaryLight)
        .justifyContent(FlexAlign.Center)
        .flexShrink(0)
        .onClick(() => {
          if (this.localMusicList.length > 0) {
            this.playLocalSong(this.localMusicList[0])
          }
        })

        Image($rawfile('jinxin_right.svg'))
          .width(16)
          .height(16)
          .objectFit(ImageFit.Contain)
          .fillColor(this.themeTextSecondary)
          .flexShrink(0)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .onClick(() => {
        this.subPage = 'localMusicDetail'
        // V2.0.8：打开本地音乐自动定位到正在播放的歌曲（受"歌单内-定位播放歌曲"开关控制）
        if (this.playlistLocatePlaying) {
          this.locatePlayingSong('local')
        }
      })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeCardBg)
    .borderRadius(16)
  }

  // ===== 云端歌单区块（题头 + 云端歌单列表，无右上角刷新） =====
  @Builder
  CloudPlaylistSection() {
    Column({ space: 10 }) {
      Row() {
        Text('云端歌单')
          .fontSize(18)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Bold)

        Text(`${this.cloudPlaylists.length} 个`)
          .fontSize(13)
          .fontColor(this.themeTextSecondary)
          .margin({ left: 8 })

        Blank().layoutWeight(1)
      }
      .width('100%')

      if (!this.webdavConfigured) {
        // 未配置 WebDAV
        Row({ space: 12 }) {
          Row() {
            Image($r('app.media.music_note')).width(24).height(24)
          }
          .width(52).height(52).borderRadius(10)
          .backgroundColor(this.themePlaceholder)
          .justifyContent(FlexAlign.Center).flexShrink(0)

          Column({ space: 4 }) {
            Text('云端歌单')
              .fontSize(15).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium)
            Text('请在陋室配置 WebDAV')
              .fontSize(12).fontColor(this.themeTextSecondary)
          }
          .alignItems(HorizontalAlign.Start).layoutWeight(1)

          Image($rawfile('jinxin_right.svg'))
            .width(16).height(16)
            .objectFit(ImageFit.Contain)
            .fillColor(this.themeTextSecondary).flexShrink(0)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onClick(() => {
          this.showToastMsg('请在陋室配置 WebDAV')
        })
      } else if (this.cloudPlaylistLoading) {
        // 加载中
        Row({ space: 12 }) {
          LoadingProgress()
            .width(24).height(24).color(this.themePrimary)
          Text('正在加载云端歌单...')
            .fontSize(14).fontColor(this.themeTextSecondary)
        }
        .width('100%').padding(16)
      } else if (this.cloudPlaylists.length === 0) {
        // 已配置但无歌单：点击加载云端歌单
        Row({ space: 12 }) {
          Row() {
            SymbolGlyph($r('sys.symbol.cloud'))
              .fontSize(24).fontColor([this.themePrimary])
          }
          .width(52).height(52).borderRadius(10)
          .backgroundColor(this.themePrimaryLight)
          .justifyContent(FlexAlign.Center).flexShrink(0)

          Column({ space: 4 }) {
            Text('WebDAV 已配置')
              .fontSize(15).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium)
            Text('点击加载云端歌单')
              .fontSize(12).fontColor(this.themeTextSecondary)
          }
          .alignItems(HorizontalAlign.Start).layoutWeight(1)

          Image($rawfile('jinxin_right.svg'))
            .width(16).height(16)
            .objectFit(ImageFit.Contain)
            .fillColor(this.themeTextSecondary).flexShrink(0)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onClick(() => {
          this.refreshCloudPlaylists()
        })
      } else {
        Column() {
          ForEach(this.cloudPlaylists, (playlist: Playlist, index: number) => {
            Column() {
              if (index > 0) {
                Divider()
                  .color(this.themeDivider)
                  .margin({ left: 64 })
              }
              Row({ space: 12 }) {
                Stack() {
                  Row() {
                    Image($r('app.media.music_note')).width(24).height(24)
                  }
                  .width(52).height(52).borderRadius(10)
                  .backgroundColor(this.themePlaceholder).justifyContent(FlexAlign.Center)
                }.flexShrink(0)

                Column({ space: 4 }) {
                  Text(playlist.name)
                    .fontSize(15).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${playlist.songCount} 首`)
                    .fontSize(12).fontColor(this.themeTextSecondary)
                }
                .alignItems(HorizontalAlign.Start).layoutWeight(1)

                // 播放按钮
                Row() {
                  SymbolGlyph($r('sys.symbol.play_fill'))
                    .fontSize(16)
                    .fontColor([this.themePrimary])
                }
                .width(32)
                .height(32)
                .borderRadius(16)
                .backgroundColor(this.themePrimaryLight)
                .justifyContent(FlexAlign.Center)
                .flexShrink(0)
                .onClick(() => {
                  this.playPlaylist(playlist)
                })

                Image($rawfile('jinxin_right.svg'))
                  .width(16).height(16)
                  .objectFit(ImageFit.Contain)
                  .fillColor(this.themeTextSecondary).flexShrink(0)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .onClick(() => {
                this.selectedCloudPlaylist = playlist
                this.subPage = 'cloudPlaylistDetail'
                this.loadCloudPlaylistSongs(playlist).then(() => {
                  // V2.0.8：云端歌曲加载完成后自动定位到正在播放的歌曲（受"歌单内-定位播放歌曲"开关控制）
                  if (this.playlistLocatePlaying) {
                    this.locatePlayingSong('cloud')
                  }
                })
              })
            }
          }, (playlist: Playlist) => playlist.id)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeCardBg)
    .borderRadius(16)
  }

  private async refreshCloudPlaylists() {
    this.cloudPlaylistLoading = true
    try {
      const url = await this.db.getSetting('webdav_url')
      const user = await this.db.getSetting('webdav_user')
      const pass = await this.db.getSetting('webdav_pass')
      const subPath = await this.db.getSetting('webdav_path')

      if (!url || !user || !pass) {
        this.showToastMsg('WebDAV 配置不完整')
        this.cloudPlaylistLoading = false
        return
      }

      const playlists = await this.fetchWebdavMusicList(url, user, pass, subPath)
      this.cloudPlaylists = playlists
      await this.db.setSetting('cloud_playlists', JSON.stringify(playlists))
      if (playlists.length > 0) {
        this.showToastMsg(`已加载 ${playlists.length} 个云端歌单`)
      } else {
        this.showToastMsg('未找到音乐文件夹，请检查路径配置')
      }
    } catch (e) {
      console.error('[Xuanchuang] refreshCloudPlaylists:', e)
      this.showToastMsg('加载云端歌单失败，请检查配置')
    }
    this.cloudPlaylistLoading = false
  }

  private async fetchWebdavMusicList(url: string, user: string, pass: string, subPath: string): Promise<Playlist[]> {
    const auth = this.base64Encode(`${user}:${pass}`)
    try {
      // 构建请求 URL：服务器地址 + 音乐路径（对路径进行 URL 编码，处理空格等特殊字符）
      let baseUrl = url.endsWith('/') ? url : url + '/'
      if (subPath && subPath.length > 0) {
        const path = subPath.startsWith('/') ? subPath.substring(1) : subPath
        const cleanPath = path.endsWith('/') ? path : path + '/'
        baseUrl += encodeURI(cleanPath)
      }

      const body = await this.webdavPropfind(baseUrl, auth)
      if (!body) return []

      return await this.parseWebdavResponse(body, baseUrl, auth, subPath)
    } catch (e) {
      console.error('[Xuanchuang] fetchWebdavMusicList:', e)
      return []
    }
  }

  private async webdavPropfind(url: string, auth: string): Promise<string> {
    const httpRequest = http.createHttp()
    try {
      // WebDAV 规范要求 PROPFIND 携带 XML body，否则部分服务器（如坚果云）会返回 503
      const propfindBody = '<?xml version="1.0" encoding="utf-8"?>' +
        '<D:propfind xmlns:D="DAV:"><D:prop><D:resourcetype/><D:displayname/><D:getcontentlength/></D:prop></D:propfind>'
      const response = await httpRequest.request(url, {
        method: 'PROPFIND' as http.RequestMethod,
        header: {
          'Authorization': `Basic ${auth}`,
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
          'User-Agent': 'Sumy/1.0',
        },
        extraData: propfindBody,
        readTimeout: 15000,
        connectTimeout: 15000,
      } as http.HttpRequestOptions)
      httpRequest.destroy()

      const result = response.result
      if (typeof result === 'string') return result
      if (result instanceof ArrayBuffer) {
        const decoder = util.TextDecoder.create('utf-8')
        return decoder.decodeWithStream(new Uint8Array(result))
      }
      return ''
    } catch (e) {
      httpRequest.destroy()
      return ''
    }
  }

  private async parseWebdavResponse(xml: string, baseUrl: string, auth: string, subPath: string): Promise<Playlist[]> {
    const playlists: Playlist[] = []
    const hrefRegex = /<[Dd]:href>([^<]+)<\/[Dd]:href>/g
    const audioExts = ['.mp3', '.flac', '.wav', '.ogg', '.aac', '.m4a', '.wma', '.ape']
    const seen: Set<string> = new Set()
    let audioCount = 0

    // 收集所有子目录
    const dirs: DirEntry[] = []

    let match = hrefRegex.exec(xml)
    while (match !== null) {
      const rawHref = match[1]
      const lower = rawHref.toLowerCase()

      // 判断是否为目录
      const isDir = rawHref.endsWith('/') && rawHref !== '/' && !seen.has(rawHref)
      // 排除 baseUrl 自身
      const isSelf = this.isSamePath(rawHref, baseUrl)

      if (isDir && !isSelf && !seen.has(rawHref)) {
        seen.add(rawHref)
        let dirName = rawHref.replace(/\/+$/, '').split('/').pop() || rawHref
        try { dirName = decodeURIComponent(dirName) } catch (_) {}
        dirs.push({ href: rawHref, name: dirName })
      }
      // 统计当前目录下的音频文件
      if (!isDir && !rawHref.endsWith('/')) {
        const isAudio = audioExts.some(ext => lower.endsWith(ext))
        if (isAudio) {
          audioCount++
        }
      }

      match = hrefRegex.exec(xml)
    }

    // 提取路径名称作为主歌单名
    let mainPlaylistName = '云端音乐'
    if (subPath && subPath.length > 0) {
      const path = subPath.startsWith('/') ? subPath.substring(1) : subPath
      const cleanPath = path.endsWith('/') ? path.substring(0, path.length - 1) : path
      mainPlaylistName = decodeURIComponent(cleanPath) || '云端音乐'
    }

    // 当前目录有音频文件：创建主歌单
    if (audioCount > 0) {
      playlists.push({
        id: 'cloud_main',
        name: mainPlaylistName,
        songCount: audioCount,
        createdAt: Date.now(),
        updatedAt: Date.now(),
        coverUrl: '',
        sortOrder: 0,
      })
    }

    // 子目录：创建子歌单（排除与主歌单同名的目录）
    for (let i = 0; i < dirs.length; i++) {
      const dir = dirs[i]
      // 排除与主歌单同名的目录（避免重复）
      if (dir.name === mainPlaylistName) continue

      let dirUrl = dir.href
      if (!dirUrl.startsWith('http')) {
        if (dirUrl.startsWith('/')) {
          const m = baseUrl.match(/^(https?:\/\/[^\/]+)/)
          dirUrl = (m ? m[1] : baseUrl) + dirUrl
        } else {
          dirUrl = baseUrl + dirUrl
        }
      }
      const count = await this.countAudioFiles(dirUrl, auth)
      if (count > 0) {
        playlists.push({
          id: `cloud_${i}`,
          name: dir.name,
          songCount: count,
          createdAt: Date.now(),
          updatedAt: Date.now(),
          coverUrl: '',
          sortOrder: i + 1,
        })
      }
    }

    return playlists
  }

  // 判断 rawHref 是否指向 baseUrl 同一路径
  private isSamePath(rawHref: string, baseUrl: string): boolean {
    try {
      const decoded = decodeURIComponent(rawHref)
      // 去除末尾斜杠后比较
      const a = decoded.replace(/\/+$/, '')
      const b = baseUrl.replace(/\/+$/, '')
      // baseUrl 可能是完整 URL，decoded 可能是相对路径
      if (b.endsWith(a)) return true
      if (a.endsWith(b)) return true
    } catch (_) {}
    return false
  }

  private async countAudioFiles(dirUrl: string, auth: string): Promise<number> {
    const body = await this.webdavPropfind(dirUrl, auth)
    if (!body) return 0

    const audioExts = ['.mp3', '.flac', '.wav', '.ogg', '.aac', '.m4a', '.wma', '.ape']
    const hrefRegex = /<[Dd]:href>([^<]+)<\/[Dd]:href>/g
    let count = 0

    let match = hrefRegex.exec(body)
    while (match !== null) {
      let href = match[1]
      const lower = href.toLowerCase()
      const isAudio = audioExts.some(ext => lower.endsWith(ext))
      if (isAudio) count++
      match = hrefRegex.exec(body)
    }
    return count
  }

  private base64Encode(str: string): string {
    const helper = new util.Base64Helper()
    const uint8Array = new Uint8Array(str.split('').map(c => c.charCodeAt(0)))
    return helper.encodeToStringSync(uint8Array)
  }

  // ===== 本地音乐 Section V2（可折叠：先展示整体卡片，点击展开具体内容）=====
  @Builder
  LocalMusicSectionV2() {
    Column({ space: 12 }) {
      if (!this.localMusicExpanded) {
        // 折叠态：整体卡片，点击展开
        Row({ space: 14 }) {
          Row() {
            Image($r('app.media.music_note'))
              .width(28)
              .height(28)
              .objectFit(ImageFit.Contain)
          }
          .width(60)
          .height(60)
          .borderRadius(12)
          .backgroundColor(this.themePlaceholder)
          .justifyContent(FlexAlign.Center)
          .flexShrink(0)

          Column({ space: 6 }) {
            Text('本地音乐')
              .fontSize(16)
              .fontColor(this.themeTextPrimary)
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Row({ space: 8 }) {
              Text(`${this.localMusicList.length} 首`)
                .fontSize(13)
                .fontColor(this.themeTextSecondary)

              Text('本地')
                .fontSize(10)
                .fontColor(Color.White)
                .backgroundColor('#607D8B')
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .borderRadius(4)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Image($rawfile('jinxin_right.svg'))
            .width(18)
            .height(18)
            .objectFit(ImageFit.Contain)
            .fillColor(this.themeTextSecondary)
            .flexShrink(0)
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.themeCardBg)
        .borderRadius(16)
        .shadow({ radius: 2, color: '#00000005', offsetY: 1 })
        .onClick(() => {
          this.localMusicExpanded = true
        })
      } else {
        // 展开态：标题栏 + 具体内容
        Row() {
          Text('本地音乐')
            .fontSize(18)
            .fontColor(this.themeTextPrimary)
            .fontWeight(FontWeight.Bold)

          Text(`${this.localMusicList.length} 首`)
            .fontSize(13)
            .fontColor(this.themeTextSecondary)
            .margin({ left: 8 })

          Blank().layoutWeight(1)

          if (this.supportImmersive) {
            Row() {
              Image($rawfile('sum.svg'))
                .width(16)
                .height(16)
            }
            .width(28)
            .height(28)
            .borderRadius(14)
            .backgroundColor(Color.Transparent)
            .systemMaterial(MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN))
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.importLocalMusic()
            })
          } else {
            Row() {
              Image($rawfile('sum.svg'))
                .width(16)
                .height(16)
            }
            .width(28)
            .height(28)
            .borderRadius(14)
            .backgroundColor(Color.Transparent)
            .backgroundEffect(MaterialCompat.effect(this.isDarkMode, this.themeCardBg, MaterialCompatStyle.THIN))
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.importLocalMusic()
            })
          }

          Row() {
            SymbolGlyph($r('sys.symbol.chevron_up'))
              .fontSize(16)
              .fontColor([this.themePrimary])
          }
          .width(32)
          .height(32)
          .borderRadius(16)
          .backgroundColor(this.themePlaceholder)
          .justifyContent(FlexAlign.Center)
          .margin({ left: 12 })
          .onClick(() => {
            this.localMusicExpanded = false
          })
        }
        .width('100%')

        if (this.localMusicList.length === 0) {
          Column({ space: 8 }) {
            Text('还没有本地音乐')
              .fontSize(14)
              .fontColor(this.themeTextSecondary)
            Text('点击 + 导入本地音乐文件')
              .fontSize(12)
              .fontColor(this.themeTextSecondary)
          }
          .width('100%')
          .height(100)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(this.themeCardBg)
          .borderRadius(16)
        } else {
          Column({ space: 8 }) {
            ForEach(this.localMusicList, (item: LocalMusicItem) => {
              this.LocalMusicCard(item)
            })
          }
          .width('100%')
        }
      }
    }
    .width('100%')
  }

  // ===== 本地音乐卡片 =====
  @Builder
  LocalMusicCard(item: LocalMusicItem) {
    Row({ space: 12 }) {
      if (item.coverUrl && item.coverUrl.length > 0) {
        Image(item.coverUrl)
          .width(48)
          .height(48)
          .borderRadius(10)
          .objectFit(ImageFit.Cover)
          .backgroundColor(this.themePlaceholder)
          .flexShrink(0)
      } else {
        Row() {
          Image($r('app.media.music_note'))
            .width(22)
            .height(22)
        }
        .width(48)
        .height(48)
        .borderRadius(10)
        .backgroundColor(this.themePlaceholder)
        .justifyContent(FlexAlign.Center)
        .flexShrink(0)
      }

      Column({ space: 4 }) {
        Text(item.songName || item.fileName.replace(/\.[^.]+$/, ''))
          .fontSize(15)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(item.artist || '本地音乐')
          .fontSize(13)
          .fontColor(this.themeTextSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.themeCardBg)
    .borderRadius(14)
    .onClick(() => {
      this.playLocalSong(item)
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          const fakeSong: SongInfo = {
            songId: 'local_' + item.id,
            songName: item.songName || item.fileName.replace(/\.[^.]+$/, ''),
            artist: item.artist || '本地音乐',
            album: '',
            coverUrl: item.coverUrl || '',
            source: 'local',
            playUrl: item.filePath,
          }
          this.floatingSong = fakeSong
          this.showFloatingPopup = true
        })
    )
    .bindPopup(this.showFloatingPopup && this.floatingSong?.songId === 'local_' + item.id && this.floatingSong?.source === 'local', {
      builder: this.SongActionPopupBuilder(),
      placement: Placement.Bottom,
      systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN),
      width: '78%',
      onStateChange: (e: PopupStateChangeParam) => {
        if (!e.isVisible) {
          this.showFloatingPopup = false
          if (this.pendingReorder) {
            this.pendingReorder = false
            this.showReorderDialog = true
          }
          if (this.pendingMovePlaylist) {
            this.pendingMovePlaylist = false
            this.showMovePlaylistDialog = true
          }
          if (this.pendingCopyPlaylist) {
            this.pendingCopyPlaylist = false
            this.showCopyPlaylistDialog = true
          }
        }
      }
    })
  }

  // ===== 本地音乐 Section =====
  @Builder
  LocalMusicSection() {
    Column({ space: 12 }) {
      // 统一的 Section Header（与自建歌单完全一致）
      this.SectionHeader(
        '本地音乐',
        this.localMusicList.length,
        this.localMusicExpanded,
        () => {
          this.localMusicExpanded = !this.localMusicExpanded
        },
        () => {
          this.importLocalMusic()
        }
      )

      if (this.localMusicExpanded) {
        if (this.localMusicList.length === 0) {
          Column({ space: 8 }) {
            Text('还没有本地音乐')
              .fontSize(14)
              .fontColor(this.themeTextSecondary)
            Text('点击 + 导入本地音乐文件')
              .fontSize(12)
              .fontColor(this.themeTextSecondary)
          }
          .width('100%')
          .height(120)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 16, right: 16 })
        } else {
          Column({ space: 8 }) {
            ForEach(this.localMusicList, (item: LocalMusicItem) => {
              Row({ space: 12 }) {
                // 封面图或默认图标
                if (item.coverUrl && item.coverUrl.length > 0) {
                  Image(item.coverUrl)
                    .width(48)
                    .height(48)
                    .borderRadius(8)
                    .objectFit(ImageFit.Cover)
                    .backgroundColor(this.themeCardBg)
                    .flexShrink(0)
                } else {
                  Row() {
                    Image($r('app.media.music_note'))
                      .width(24)
                      .height(24)
                  }
                  .width(48)
                  .height(48)
                  .borderRadius(8)
                  .backgroundColor(this.themeCardBg)
                  .justifyContent(FlexAlign.Center)
                  .flexShrink(0)
                }

                // 信息
                Column({ space: 4 }) {
                  Text(item.songName || item.fileName.replace(/\.[^.]+$/, ''))
                    .fontSize(15)
                    .fontColor(this.themeTextPrimary)
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Row({ space: 8 }) {
                    Text('本地')
                      .fontSize(10)
                      .fontColor(Color.White)
                      .backgroundColor('#607D8B')
                      .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                      .borderRadius(3)
                      .flexShrink(0)

                    Text(item.artist || '未知歌手')
                      .fontSize(12)
                      .fontColor(this.themeTextSecondary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)

                    if (item.fileSize > 0) {
                      Text(this.formatFileSize(item.fileSize))
                        .fontSize(11)
                        .fontColor(this.themeTextSecondary)
                        .flexShrink(0)
                    }
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                // 删除按钮
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(18)
                  .fontColor([this.themeTextSecondary])
                  .width(28)
                  .height(28)
                  .flexShrink(0)
                  .onClick(() => {
                    this.db.removeLocalMusic(item.id)
                    this.loadLocalMusic()
                  })
              }
              .width('100%')
              .padding({ left: 12, right: 8, top: 10, bottom: 10 })
              .backgroundColor(this.themeCardBg)
              .borderRadius(12)
              .onClick(() => {
                this.playLocalSong(item)
              })
              .gesture(
                LongPressGesture({ repeat: false, duration: 500 })
                  .onAction(() => {
                    const fakeSong: SongInfo = {
                      songId: 'local_' + item.id,
                      songName: item.songName || item.fileName.replace(/\.[^.]+$/, ''),
                      artist: item.artist || '本地音乐',
                      album: '',
                      coverUrl: item.coverUrl || '',
                      source: 'local',
                      playUrl: item.filePath,
                    }
                    this.floatingSong = fakeSong
                    this.showFloatingPopup = true
                  })
              )
              .bindPopup(this.showFloatingPopup && this.floatingSong?.songId === 'local_' + item.id && this.floatingSong?.source === 'local', {
                builder: this.SongActionPopupBuilder(),
                placement: Placement.Bottom,
                width: '78%',
                onStateChange: (e: PopupStateChangeParam) => {
                  if (!e.isVisible) {
                    this.showFloatingPopup = false
                    if (this.pendingReorder) {
                      this.pendingReorder = false
                      this.showReorderDialog = true
                    }
                    if (this.pendingMovePlaylist) {
                      this.pendingMovePlaylist = false
                      this.showMovePlaylistDialog = true
                    }
                    if (this.pendingCopyPlaylist) {
                      this.pendingCopyPlaylist = false
                      this.showCopyPlaylistDialog = true
                    }
                  }
                }
              })
            })

            // 清空全部按钮
            if (this.localMusicList.length > 0) {
              Row() {
                Text('清空全部本地音乐')
                  .fontSize(13)
                  .fontColor('#F44336')
              }
              .width('100%')
              .padding({ top: 8, bottom: 4 })
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                this.db.clearLocalMusic()
                this.loadLocalMusic()
                this.showToastMsg('已清空本地音乐列表')
              })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
      }
    }
    .width('100%')
  }

  @Builder
  PlaylistsSection() {
    Column({ space: 12 }) {
      // 统一的 Section Header（与本地音乐完全一致）
      this.SectionHeader(
        '自建歌单',
        this.playlists.length,
        this.playlistsExpanded,
        () => {
          this.playlistsExpanded = !this.playlistsExpanded
        },
        () => {
          this.editPlaylistTarget = null
          this.editPlaylistName = ''
          this.editPlaylistCoverUri = ''
          this.showEditPlaylistSheet = true
        }
      )

      if (this.playlistsExpanded) {
        if (this.playlists.length === 0) {
          Column({ space: 0 }) {
            Text('还没有创建歌单')
              .fontSize(14)
              .fontColor(this.themeTextSecondary)
          }
          .width('100%')
          .height(60)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 16, right: 16 })
        } else {
          Column({ space: 8 }) {
            ForEach(this.playlists, (playlist: Playlist) => {
              this.PlaylistCard(playlist)
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
      }
    }
    .width('100%')
  }

  @Builder
  PlaylistCard(playlist: Playlist) {
    Row({ space: 12 }) {
      // 自动识别第一首歌曲封面
      Stack() {
        if (this.playlistCovers.has(playlist.id) && this.playlistCovers.get(playlist.id)!.length > 0) {
          CoverImage({
            url: this.playlistCovers.get(playlist.id)!,
            coverWidth: 44,
            coverHeight: 44,
            radius: 10
          })
        } else {
          Row() {
            Image($r('app.media.music_note'))
              .width(20)
              .height(20)
              .objectFit(ImageFit.Contain)
          }
          .width(44)
          .height(44)
          .borderRadius(10)
          .backgroundColor(this.themeCardBg)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width(44)
      .height(44)
      .borderRadius(10)
      .flexShrink(0)

      Column({ space: 2 }) {
        Text(playlist.name)
          .fontSize(15)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`${playlist.songCount} 首`)
          .fontSize(12)
          .fontColor(this.themeTextSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 播放按钮
      Row() {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(16)
          .fontColor([this.themePrimary])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(this.themePrimaryLight)
      .justifyContent(FlexAlign.Center)
      .flexShrink(0)
      .onClick(() => {
        this.playPlaylist(playlist)
      })

      // 三点菜单
      Row() {
        SymbolGlyph($r('sys.symbol.ellipsis_circle'))
          .fontSize(20)
          .fontColor([this.themeTextSecondary])
      }
      .width(32)
      .height(32)
      .justifyContent(FlexAlign.Center)
      .flexShrink(0)
      .bindMenu([
        {
          value: '播放歌单',
          action: () => { this.playPlaylist(playlist) }
        },
        {
          value: '命名歌单',
          action: () => {
            this.renamePlaylistId = playlist.id
            this.renameValue = playlist.name
            this.showRenameDialog = true
          }
        },
        {
          value: '导出歌单',
          action: () => { this.exportPlaylistToFile(playlist) }
        },
        {
          value: '移除歌单',
          action: () => { this.deletePlaylist(playlist.id) }
        },
      ], {
        systemMaterial: MaterialCompat.immersiveMaterial(MaterialCompatStyle.THICK)
      })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.themeCardBg)
    .borderRadius(12)
    .onClick(() => {
      this.openPlaylistDetail(playlist)
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 300 })
        .onAction(() => {
          this.playlistActionTarget = playlist
          this.showPlaylistActionSheet = true
        })
    )
  }

  @Builder
  PlaylistDetailContent() {
    HdsNavDestination() {
      Column() {
        // 多选模式：标题栏整体隐藏，使用自定义头部
        if (this.multiSelectMode) {
          Row({ space: 12 }) {
            Row() {
              Image($rawfile('fanhui_left.svg'))
                .width(22)
                .height(22)
                .objectFit(ImageFit.Contain)
                .fillColor(this.themeTextPrimary)
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.exitMultiSelectMode()
            })

            Text(`已选 ${this.selectedSongKeys.size} 项`)
              .fontSize(17)
              .fontColor(this.themeTextPrimary)
              .fontWeight(FontWeight.Bold)
              .layoutWeight(1)

            // 全选/取消按钮
            if (this.supportImmersive) {
              Row() {
                SymbolGlyph(this.selectedSongKeys.size === this.playlistSongs.length && this.playlistSongs.length > 0
                  ? $r('sys.symbol.checkmark_circle_fill')
                  : $r('sys.symbol.checkmark_circle'))
                  .fontSize(16)
                  .fontColor([this.themeTextPrimary])
              }
              .width(28)
              .height(28)
              .borderRadius(14)
              .backgroundColor(Color.Transparent)
              .systemMaterial(MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN))
              .justifyContent(FlexAlign.Center)
              .onClick(() => { this.toggleSelectAll() })
            } else {
              Row() {
                SymbolGlyph(this.selectedSongKeys.size === this.playlistSongs.length && this.playlistSongs.length > 0
                  ? $r('sys.symbol.checkmark_circle_fill')
                  : $r('sys.symbol.checkmark_circle'))
                  .fontSize(16)
                  .fontColor([this.themeTextPrimary])
              }
              .width(28)
              .height(28)
              .borderRadius(14)
              .backgroundColor(Color.Transparent)
              .backgroundEffect(MaterialCompat.effect(this.isDarkMode, this.themeCardBg, MaterialCompatStyle.THIN))
              .justifyContent(FlexAlign.Center)
              .onClick(() => { this.toggleSelectAll() })
            }
          }
          .width('100%')
          .height(56)
          .padding({ left: 8, right: 16 })
          .alignItems(VerticalAlign.Center)
        }

        // 排序弹窗隐藏锚点（由标题栏菜单 px 图标触发）
        Row()
          .width(1)
          .height(1)
          .bindPopup(this.sortPopupTarget === 'playlist', {
            builder: this.SortModePopup(),
            placement: Placement.Bottom,
            onStateChange: (e: PopupStateChangeParam) => {
              if (!e.isVisible) {
                this.sortPopupTarget = ''
              }
            }
          })

        // 标题栏悬浮于内容之上：非多选时为返回/排序/多选按钮让出高度
        if (!this.multiSelectMode) {
          Column().height(64)
        }

      if (this.playlistSongs.length === 0) {
        EmptyState({ icon: '', title: '歌单是空的', subtitle: '在搜索页搜索并添加歌曲' })
      } else {
        Refresh({ refreshing: $$this.detailRefreshing, offset: 64 }) {
        Scroll(this.playlistDetailScroller) {
          Column({ space: 8 }) {
            ForEach(this.playlistSongs, (song: SongInfo, index?: number) => {
              Row({ space: 10 }) {
                if (this.multiSelectMode) {
                  Row() {
                    SymbolGlyph(this.isSongSelected(song)
                      ? $r('sys.symbol.checkmark_circle_fill')
                      : $r('sys.symbol.circle'))
                      .fontSize(22)
                      .fontColor(this.isSongSelected(song) ? [this.themePrimary] : [this.themeTextSecondary])
                  }
                  .width(28)
                  .height(28)
                  .justifyContent(FlexAlign.Center)
                  .flexShrink(0)
                } else if (this.isPlayingTrackSong(song)) {
                  SymbolGlyph($r('sys.symbol.waveform'))
                    .fontSize(14)
                    .fontColor([this.themePrimary])
                    .width(28)
                    .flexShrink(0)
                } else {
                  Text(`${(index ?? 0) + 1}`)
                    .fontSize(14)
                    .fontColor(this.themeTextSecondary)
                    .width(28)
                    .textAlign(TextAlign.Center)
                    .flexShrink(0)
                }

                Image(song.coverUrl)
                  .width(44)
                  .height(44)
                  .borderRadius(8)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor(this.themePlaceholder)
                  .flexShrink(0)

                Column({ space: 2 }) {
                  Text(song.songName)
                    .fontSize(15)
                    .fontColor(this.themeTextPrimary)
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Row({ space: 6 }) {
                    Text(SourceInfo.getName(song.source))
                      .fontSize(10)
                      .fontColor(Color.White)
                      .backgroundColor(SourceInfo.getColor(song.source))
                      .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                      .borderRadius(3)
                      .flexShrink(0)

                    Text(song.artist)
                      .fontSize(12)
                      .fontColor(this.themeTextSecondary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 12, right: 8, top: 10, bottom: 10 })
              .backgroundColor(this.themeCardBg)
              .borderRadius(12)
              .onClick(() => {
                if (this.multiSelectMode) {
                  this.toggleSongSelect(song)
                } else {
                  this.playSong(song)
                }
              })
              .gesture(
                LongPressGesture({ repeat: false, duration: 500 })
                  .onAction(() => {
                    if (this.multiSelectMode) {
                      this.handleMultiSelectLongPress(song)
                    } else {
                      this.floatingSong = song
                      this.showFloatingPopup = true
                    }
                  })
              )
              .bindPopup(this.showFloatingPopup && this.floatingSong?.songId === song.songId && this.floatingSong?.source === song.source, {
                builder: this.SongActionPopupBuilder(),
                placement: Placement.Bottom,
                width: '78%',
                onStateChange: (e: PopupStateChangeParam) => {
                  if (!e.isVisible) {
                    this.showFloatingPopup = false
                    if (this.pendingReorder) {
                      this.pendingReorder = false
                      this.showReorderDialog = true
                    }
                    if (this.pendingMovePlaylist) {
                      this.pendingMovePlaylist = false
                      this.showMovePlaylistDialog = true
                    }
                    if (this.pendingCopyPlaylist) {
                      this.pendingCopyPlaylist = false
                      this.showCopyPlaylistDialog = true
                    }
                  }
                }
              })
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 200 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
        }
        .onRefreshing(() => {
          this.detailRefreshing = true
          this.reloadPlaylistSongs().then(() => {
            this.detailRefreshing = false
          })
        })
      }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
    }
    .titleBar({
      content: {
        title: {
          mainTitle: this.selectedPlaylist?.name ?? '歌单详情',
          subTitle: `${this.playlistSongs.length} 首`,
        },
        menu: {
          value: [
            {
              content: {
                icon: $rawfile('px.svg'),
                action: (): void => {
                  this.sortPopupTarget = this.sortPopupTarget === 'playlist' ? '' : 'playlist'
                },
              },
            },
            {
              content: {
                icon: $rawfile('dx.svg'),
                action: (): void => {
                  this.enterMultiSelectMode()
                },
              },
            },
          ],
        },
        backIcon: {
          icon: $rawfile('fanhui_left.svg'),
          action: (): void => {
            if (this.multiSelectMode) {
              this.exitMultiSelectMode()
            } else {
              this.subPage = 'main'
            }
          },
        },
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: false
        }
      },
    })
    .hideTitleBar(this.multiSelectMode)
    .width('100%')
    .height('100%')
  }

  @Builder
  RenamePlaylistSheet() {
    Column({ space: 20 }) {
      Text('重命名歌单')
        .fontSize(17)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      TextInput({ placeholder: '输入新名称', text: this.renameValue })
        .width('100%')
        .height(48)
        .fontSize(15)
        .padding({ left: 16, right: 16 })
        .backgroundColor(this.themePlaceholder)
        .borderRadius(12)
        .onChange((value: string) => {
          this.renameValue = value
        })

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor(this.themeTextPrimary)
          .backgroundColor(this.themeCardBg)
          .borderRadius(22)
          .onClick(() => {
            this.showRenameDialog = false
          })

        Button('确定')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor(this.themePrimary)
          .borderRadius(22)
          .onClick(() => {
            this.doRenamePlaylist()
          })
      }
      .width('100%')
    }
    .padding(24)
  }

  @Builder
  ExportPlaylistSheet() {
    Column({ space: 20 }) {
      Text('导出歌单')
        .fontSize(17)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      Text(`将歌单「${this.exportPlaylistTarget?.name ?? ''}」导出`)
        .fontSize(13)
        .fontColor(this.themeTextSecondary)
        .width('100%')

      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text('JS')
            .fontSize(18)
            .fontColor(this.themeTextPrimary)
            .fontWeight(FontWeight.Bold)
          Text('通用格式，便于跨平台')
            .fontSize(11)
            .fontColor(this.themeTextSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .padding(16)
        .backgroundColor(this.themeCardBg)
        .borderRadius(12)
        .onClick(() => {
          if (this.exportPlaylistTarget) {
            this.exportPlaylist(this.exportPlaylistTarget, 'json')
          }
        })
      }

      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text('LXMC')
            .fontSize(18)
            .fontColor(this.themeTextPrimary)
            .fontWeight(FontWeight.Bold)
          Text('应用专用格式')
            .fontSize(11)
            .fontColor(this.themeTextSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .padding(16)
        .backgroundColor(this.themeCardBg)
        .borderRadius(12)
        .onClick(() => {
          if (this.exportPlaylistTarget) {
            this.exportPlaylist(this.exportPlaylistTarget, 'lxmc')
          }
        })
      }

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor(this.themeTextPrimary)
          .backgroundColor(this.themeCardBg)
          .borderRadius(22)
          .onClick(() => {
            this.showExportDialog = false
          })
      }
      .width('100%')
    }
    .padding(24)
  }

  // ===== 本地音乐详情页 =====
  @Builder
  LocalMusicDetailContent() {
    HdsNavDestination() {
      Column() {
        // 多选模式：标题栏整体隐藏，使用自定义头部
        if (this.multiSelectMode) {
          Row({ space: 12 }) {
            Row() {
              Image($rawfile('fanhui_left.svg'))
                .width(22).height(22)
                .objectFit(ImageFit.Contain)
                .fillColor(this.themeTextPrimary)
            }
            .width(36).height(36).justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.exitMultiSelectMode()
            })

            Text(`已选 ${this.selectedSongKeys.size} 项`)
              .fontSize(17).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Bold)
              .layoutWeight(1)

            if (this.supportImmersive) {
              Row() {
                SymbolGlyph(this.selectedSongKeys.size === this.localMusicList.length && this.localMusicList.length > 0
                  ? $r('sys.symbol.checkmark_circle_fill')
                  : $r('sys.symbol.checkmark_circle'))
                  .fontSize(16).fontColor([this.themeTextPrimary])
              }
              .width(28).height(28)
              .borderRadius(14)
              .backgroundColor(Color.Transparent)
              .systemMaterial(MaterialCompat.immersiveMaterial(MaterialCompatStyle.THIN))
              .justifyContent(FlexAlign.Center)
              .onClick(() => { this.toggleSelectAll() })
            } else {
              Row() {
                SymbolGlyph(this.selectedSongKeys.size === this.localMusicList.length && this.localMusicList.length > 0
                  ? $r('sys.symbol.checkmark_circle_fill')
                  : $r('sys.symbol.checkmark_circle'))
                  .fontSize(16).fontColor([this.themeTextPrimary])
              }
              .width(28).height(28)
              .borderRadius(14)
              .backgroundColor(Color.Transparent)
              .backgroundEffect(MaterialCompat.effect(this.isDarkMode, this.themeCardBg, MaterialCompatStyle.THIN))
              .justifyContent(FlexAlign.Center)
              .onClick(() => { this.toggleSelectAll() })
            }
          }
          .width('100%').height(56).padding({ left: 8, right: 16 }).alignItems(VerticalAlign.Center)
        }

        // 排序弹窗隐藏锚点（由标题栏菜单 px 图标触发）
        Row()
          .width(1)
          .height(1)
          .bindPopup(this.sortPopupTarget === 'local', {
            builder: this.SortModePopup(),
            placement: Placement.Bottom,
            onStateChange: (e: PopupStateChangeParam) => {
              if (!e.isVisible) {
                this.sortPopupTarget = ''
              }
            }
          })

        // 标题栏悬浮于内容之上：非多选时为返回/排序/多选按钮让出高度
        if (!this.multiSelectMode) {
          Column().height(64)
        }

      if (this.localMusicList.length === 0) {
        Column({ space: 12 }) {
          Text('暂无本地音乐').fontSize(14).fontColor(this.themeTextSecondary)
          Text('点击右上角 + 导入本地音乐文件').fontSize(12).fontColor(this.themeTextSecondary)
          Button('导入音乐')
            .width(160).height(44).fontSize(15).fontColor(Color.White)
            .backgroundColor(this.themePrimary).borderRadius(22)
            .onClick(() => { this.importLocalMusic() })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        Refresh({ refreshing: $$this.detailRefreshing, offset: 64 }) {
        Scroll(this.localDetailScroller) {
          Column({ space: 8 }) {
            ForEach(this.localMusicList, (item: LocalMusicItem) => {
              Row({ space: 12 }) {
                if (this.multiSelectMode) {
                  Row() {
                    SymbolGlyph(this.isSongSelected({
                          songId: 'local_' + item.id,
                          songName: '', artist: '', album: '',
                          coverUrl: '', source: 'local', playUrl: '',
                        } as SongInfo)
                      ? $r('sys.symbol.checkmark_circle_fill')
                      : $r('sys.symbol.circle'))
                      .fontSize(22)
                      .fontColor(this.isSongSelected({
                        songId: 'local_' + item.id,
                        songName: '', artist: '', album: '',
                        coverUrl: '', source: 'local', playUrl: '',
                      } as SongInfo) ? [this.themePrimary] : [this.themeTextSecondary])
                  }
                  .width(28).height(28).justifyContent(FlexAlign.Center).flexShrink(0)
                }

                if (item.coverUrl && item.coverUrl.length > 0) {
                  Image(item.coverUrl).width(48).height(48).borderRadius(10).objectFit(ImageFit.Cover).flexShrink(0)
                } else {
                  Row() {
                    Image($r('app.media.music_note')).width(22).height(22)
                  }
                  .width(48).height(48).borderRadius(10)
                  .backgroundColor(this.themePlaceholder).justifyContent(FlexAlign.Center).flexShrink(0)
                }

                Column({ space: 4 }) {
                  Text(item.songName || item.fileName.replace(/\.[^.]+$/, ''))
                    .fontSize(15).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.artist || '本地音乐').fontSize(12).fontColor(this.themeTextSecondary)
                }
                .alignItems(HorizontalAlign.Start).layoutWeight(1)
              }
              .width('100%').padding(12).backgroundColor(this.themeCardBg).borderRadius(12)
              .onClick(() => {
                if (this.multiSelectMode) {
                  const fakeSong: SongInfo = {
                    songId: 'local_' + item.id,
                    songName: item.songName || item.fileName.replace(/\.[^.]+$/, ''),
                    artist: item.artist || '本地音乐',
                    album: '',
                    coverUrl: item.coverUrl || '',
                    source: 'local',
                    playUrl: item.filePath,
                  } as SongInfo
                  this.toggleSongSelect(fakeSong)
                } else {
                  this.playLocalSong(item)
                }
              })
              .gesture(
                LongPressGesture({ repeat: false, duration: 500 })
                  .onAction(() => {
                    const fakeSong: SongInfo = {
                      songId: 'local_' + item.id,
                      songName: item.songName || item.fileName.replace(/\.[^.]+$/, ''),
                      artist: item.artist || '本地音乐',
                      album: '',
                      coverUrl: item.coverUrl || '',
                      source: 'local',
                      playUrl: item.filePath,
                    } as SongInfo
                    if (this.multiSelectMode) {
                      this.handleMultiSelectLongPress(fakeSong)
                    } else {
                      this.floatingSong = fakeSong
                      this.showFloatingPopup = true
                    }
                  })
              )
              .bindPopup(this.showFloatingPopup && this.floatingSong?.songId === 'local_' + item.id && this.floatingSong?.source === 'local', {
                builder: this.SongActionPopupBuilder(),
                placement: Placement.Bottom,
                width: '78%',
                onStateChange: (e: PopupStateChangeParam) => {
                  if (!e.isVisible) {
                    this.showFloatingPopup = false
                    if (this.pendingReorder) {
                      this.pendingReorder = false
                      this.showReorderDialog = true
                    }
                    if (this.pendingMovePlaylist) {
                      this.pendingMovePlaylist = false
                      this.showMovePlaylistDialog = true
                    }
                    if (this.pendingCopyPlaylist) {
                      this.pendingCopyPlaylist = false
                      this.showCopyPlaylistDialog = true
                    }
                  }
                }
              })
            })
          }
          .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 168 })
        }
        .layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring).align(Alignment.Top)
        }
        .onRefreshing(() => {
          this.detailRefreshing = true
          this.loadLocalMusic().then(() => {
            this.detailRefreshing = false
          })
        })
      }
      }
      .width('100%').height('100%')
      .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
    }
    .titleBar({
      content: {
        title: {
          mainTitle: '本地音乐',
          subTitle: `${this.localMusicList.length} 首`,
        },
        menu: {
          value: [
            {
              content: {
                icon: $rawfile('px.svg'),
                action: (): void => {
                  this.sortPopupTarget = this.sortPopupTarget === 'local' ? '' : 'local'
                },
              },
            },
            {
              content: {
                icon: $rawfile('dx.svg'),
                action: (): void => {
                  this.enterMultiSelectMode()
                },
              },
            },
            {
              content: {
                icon: $rawfile('sum.svg'),
                action: (): void => {
                  this.importLocalMusic()
                },
              },
            },
          ],
        },
        backIcon: {
          icon: $rawfile('fanhui_left.svg'),
          action: (): void => {
            if (this.multiSelectMode) {
              this.exitMultiSelectMode()
            } else {
              this.subPage = 'main'
            }
          },
        },
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: false
        }
      },
    })
    .hideTitleBar(this.multiSelectMode)
    .width('100%')
    .height('100%')
  }

  // ===== 云端歌单详情页 =====
  @Builder
  CloudPlaylistDetailContent() {
    HdsNavDestination() {
      Column() {
        // 标题栏悬浮于内容之上：为返回/刷新按钮让出高度
        Column().height(64)

      if (this.cloudPlaylistLoadingSongs) {
        Column() {
          LoadingProgress().width(32).height(32).color(this.themePrimary)
          Text('正在加载...').fontSize(14).fontColor(this.themeTextSecondary).margin({ top: 12 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.cloudPlaylistSongs.length === 0) {
        EmptyState({ icon: '', title: '歌单是空的', subtitle: '请检查网盘目录是否有音乐文件' })
      } else {
        Refresh({ refreshing: $$this.detailRefreshing, offset: 64 }) {
        Scroll(this.cloudDetailScroller) {
          Column({ space: 8 }) {
            ForEach(this.cloudPlaylistSongs, (song: SongInfo, index?: number) => {
              Row({ space: 10 }) {
                if (this.isPlayingTrackSong(song)) {
                  SymbolGlyph($r('sys.symbol.waveform'))
                    .fontSize(14)
                    .fontColor([this.themePrimary])
                    .width(28)
                    .flexShrink(0)
                } else {
                  Text(`${(index ?? 0) + 1}`)
                    .fontSize(14).fontColor(this.themeTextSecondary)
                    .width(28).textAlign(TextAlign.Center).flexShrink(0)
                }

                Row() {
                  CoverImage({
                    url: song.coverUrl,
                    coverWidth: 44,
                    coverHeight: 44,
                    radius: 8
                  })
                }
                .width(44).height(44).borderRadius(8)
                .backgroundColor(this.themePrimaryLight).justifyContent(FlexAlign.Center).flexShrink(0)

                Column({ space: 2 }) {
                  Text(song.songName)
                    .fontSize(15).fontColor(this.themeTextPrimary).fontWeight(FontWeight.Medium)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

                  Row({ space: 6 }) {
                    Text('WebDAV')
                      .fontSize(10).fontColor(Color.White)
                      .backgroundColor('#607D8B')
                      .padding({ left: 5, right: 5, top: 1, bottom: 1 }).borderRadius(3)
                      .flexShrink(0)

                    Text(song.artist)
                      .fontSize(12).fontColor(this.themeTextSecondary)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                  }
                }
                .alignItems(HorizontalAlign.Start).layoutWeight(1)
              }
              .width('100%').padding({ left: 12, right: 8, top: 10, bottom: 10 })
              .backgroundColor(this.themeCardBg).borderRadius(12)
              .onClick(() => {
                this.playSong(song)
              })
              .gesture(LongPressGesture({ repeat: false, duration: 500 })
                .onAction(() => {
                  this.floatingSong = song
                  this.showFloatingPopup = true
                })
              )
              .bindPopup(this.showFloatingPopup && this.floatingSong?.songId === song.songId && this.floatingSong?.source === song.source, {
                builder: this.SongActionPopupBuilder(),
                placement: Placement.Bottom,
                width: '78%',
                onStateChange: (e: PopupStateChangeParam) => {
                  if (!e.isVisible) {
                    this.showFloatingPopup = false
                    if (this.pendingReorder) {
                      this.pendingReorder = false
                      this.showReorderDialog = true
                    }
                    if (this.pendingMovePlaylist) {
                      this.pendingMovePlaylist = false
                      this.showMovePlaylistDialog = true
                    }
                    if (this.pendingCopyPlaylist) {
                      this.pendingCopyPlaylist = false
                      this.showCopyPlaylistDialog = true
                    }
                  }
                }
              })
            })
          }
          .width('100%').padding({ top: 12, left: 16, right: 16, bottom: 200 })
        }
        .layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring)
        }
        .onRefreshing(() => {
          if (this.selectedCloudPlaylist) {
            this.detailRefreshing = true
            this.loadCloudPlaylistSongs(this.selectedCloudPlaylist).then(() => {
              this.detailRefreshing = false
            })
          } else {
            this.detailRefreshing = false
          }
        })
      }
      }
      .width('100%').height('100%')
      .backgroundColor(this.themeBgImageName.length > 0 ? Color.Transparent : this.themeBg)
    }
    .titleBar({
      content: {
        title: {
          mainTitle: this.selectedCloudPlaylist?.name ?? '云端歌单',
          subTitle: `${this.cloudPlaylistSongs.length} 首`,
        },
        menu: {
          value: [
            {
              content: {
                icon: $rawfile('sx.svg'),
                action: (): void => {
                  if (this.selectedCloudPlaylist) {
                    this.loadCloudPlaylistSongs(this.selectedCloudPlaylist)
                  }
                },
              },
            },
          ],
        },
        backIcon: {
          icon: $rawfile('fanhui_left.svg'),
          action: (): void => {
            this.subPage = 'main'
          },
        },
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: false
        }
      },
    })
    .width('100%')
    .height('100%')
  }

  private async loadCloudPlaylistSongs(playlist: Playlist) {
    this.cloudPlaylistLoadingSongs = true
    this.cloudPlaylistSongs = []
    try {
      const url = await this.db.getSetting('webdav_url')
      const user = await this.db.getSetting('webdav_user')
      const pass = await this.db.getSetting('webdav_pass')
      const subPath = await this.db.getSetting('webdav_path')

      if (!url || !user || !pass) {
        this.showToastMsg('WebDAV 配置不完整')
        this.cloudPlaylistLoadingSongs = false
        return
      }

      // 构建目录 URL
      let dirUrl = url.endsWith('/') ? url : url + '/'
      if (subPath && subPath.length > 0) {
        const path = subPath.startsWith('/') ? subPath.substring(1) : subPath
        const cleanPath = path.endsWith('/') ? path : path + '/'
        dirUrl += encodeURI(cleanPath)
      }

      // 如果是主歌单（cloud_main），直接读取当前目录下的文件
      // 如果是子目录歌单，需要拼接子目录名
      if (playlist.id !== 'cloud_main') {
        const encodedName = encodeURIComponent(playlist.name)
        dirUrl += encodedName + '/'
      }

      const auth = this.base64Encode(`${user}:${pass}`)
      const body = await this.webdavPropfind(dirUrl, auth)

      if (!body) {
        this.cloudPlaylistLoadingSongs = false
        return
      }

      // 获取文件名解析方式
      const parseMode = await this.db.getSetting('webdav_parse_mode') || 'song-artist'
      const songs = this.parseWebdavSongs(body, dirUrl, user, pass, parseMode)

      // 应用本地保存的排序（WebDAV 服务器文件顺序无法修改，排序仅保存在本地）
      this.cloudPlaylistSongs = await this.applyCloudPlaylistOrder(playlist.id, songs)

      // V2.1.2：异步读取云端歌曲内嵌标签（歌名/歌手/封面/歌词），不阻塞列表展示
      this.enrichCloudSongsAsync(this.cloudPlaylistSongs)

      if (songs.length > 0) {
        this.showToastMsg(`已加载 ${songs.length} 首歌曲`)
      }
    } catch (e) {
      console.error('[Xuanchuang] loadCloudPlaylistSongs:', e)
      this.showToastMsg('加载歌单失败')
    }
    this.cloudPlaylistLoadingSongs = false
  }

  // 分批异步增强云端歌曲内嵌标签（并发 2 个，避免与封面下载抢占 WebDAV 连接）
  private async enrichCloudSongsAsync(songs: SongInfo[]): Promise<void> {
    const batchSize: number = 2
    for (let i = 0; i < songs.length; i += batchSize) {
      const batch: SongInfo[] = songs.slice(i, i + batchSize)
      await Promise.all(batch.map((s: SongInfo) => CloudTagEnricher.ensureEnriched(s)))
    }
    // V2.1.3：增强完成（歌名/歌手/封面已写回对象）后克隆为新对象数组，
    // 强制 ForEach 行重新构建，行内封面以新 url 重新解析（slice() 复用旧对象不会刷新）
    // V2.1.4：仅当列表仍是本次增强的数组时刷新，避免播放按钮触发重载后覆盖新列表
    if (this.subPage === 'cloudPlaylistDetail' && this.cloudPlaylistSongs === songs) {
      const refreshed: SongInfo[] = []
      for (let j = 0; j < this.cloudPlaylistSongs.length; j++) {
        try {
          refreshed.push(JSON.parse(JSON.stringify(this.cloudPlaylistSongs[j])) as SongInfo)
        } catch (_e) {
          refreshed.push(this.cloudPlaylistSongs[j])
        }
      }
      this.cloudPlaylistSongs = refreshed
    }
  }

  // 应用本地保存的云端歌单排序：按保存的 songId 顺序排列，未记录的追加到末尾
  private async applyCloudPlaylistOrder(playlistId: string, songs: SongInfo[]): Promise<SongInfo[]> {
    if (songs.length === 0) return songs
    const orderJson = await this.db.getSetting('cloud_playlist_order_' + playlistId)
    if (!orderJson) return songs
    try {
      const orderedIds: string[] = JSON.parse(orderJson)
      if (!Array.isArray(orderedIds) || orderedIds.length === 0) return songs
      const songById = new Map<string, SongInfo>()
      songs.forEach(s => {
        if (!songById.has(s.songId)) songById.set(s.songId, s)
      })
      const result: SongInfo[] = []
      const used = new Set<string>()
      for (let i = 0; i < orderedIds.length; i++) {
        const s = songById.get(orderedIds[i])
        if (s && !used.has(s.songId)) {
          result.push(s)
          used.add(s.songId)
        }
      }
      // 追加未在保存序列中的歌曲（如新增到网盘的歌曲）
      for (let i = 0; i < songs.length; i++) {
        if (!used.has(songs[i].songId)) {
          result.push(songs[i])
          used.add(songs[i].songId)
        }
      }
      return result
    } catch (_) {
      return songs
    }
  }

  private parseWebdavSongs(xml: string, baseUrl: string, user: string, pass: string, parseMode: string): SongInfo[] {
    const songs: SongInfo[] = []
    const audioExts = ['.mp3', '.flac', '.wav', '.ogg', '.aac', '.m4a', '.wma', '.ape']
    const coverExts = ['.jpg', '.jpeg', '.png', '.webp']
    const lyricExts = ['.lrc']

    // 收集所有文件路径（用于查找封面和歌词）
    const allFiles: Set<string> = new Set()
    const collectRegex = /<[Dd]:href>([^<]+)<\/[Dd]:href>/g
    let match = collectRegex.exec(xml)
    while (match !== null) {
      allFiles.add(match[1])
      match = collectRegex.exec(xml)
    }

    // 重新解析歌曲
    const hrefRegex = /<[Dd]:href>([^<]+)<\/[Dd]:href>/g
    match = hrefRegex.exec(xml)
    while (match !== null) {
      const rawHref = match[1]
      const lower = rawHref.toLowerCase()

      if (rawHref.endsWith('/')) {
        match = hrefRegex.exec(xml)
        continue
      }

      const isAudio = audioExts.some(ext => lower.endsWith(ext))
      if (!isAudio) {
        match = hrefRegex.exec(xml)
        continue
      }

      // 构建播放 URL
      let playUrl = rawHref
      if (!playUrl.startsWith('http')) {
        if (playUrl.startsWith('/')) {
          const m = baseUrl.match(/^(https?:\/\/[^\/]+)/)
          playUrl = (m ? m[1] : baseUrl) + playUrl
        } else {
          playUrl = baseUrl + playUrl
        }
      }
      const encodedUser = encodeURIComponent(user)
      const encodedPass = encodeURIComponent(pass)
      playUrl = playUrl.replace(/^(https?:\/\/)([^@]*@)?/, `$1${encodedUser}:${encodedPass}@`)

      // 提取文件名
      let fileName = rawHref.replace(/\/+$/, '').split('/').pop() || rawHref
      try { fileName = decodeURIComponent(fileName) } catch (_) {}

      // 去除扩展名
      let nameWithoutExt = fileName
      let fileExt = ''
      for (const ext of audioExts) {
        if (nameWithoutExt.toLowerCase().endsWith(ext)) {
          fileExt = ext
          nameWithoutExt = nameWithoutExt.substring(0, nameWithoutExt.length - ext.length)
          break
        }
      }

      // 根据解析模式提取歌手和歌曲名
      let artist = ''
      let songName = nameWithoutExt

      const parts = nameWithoutExt.split('-')
      if (parts.length >= 2) {
        const first = parts[0].trim()
        const second = parts.slice(1).join('-').trim()

        switch (parseMode) {
          case 'artist-song':
            artist = first
            songName = second
            break
          case 'song-artist':
            artist = second
            songName = first
            break
          case 'auto':
          default:
            if (second.length > first.length + 4) {
              artist = first
              songName = second
            } else {
              artist = second
              songName = first
            }
            break
        }
      }

      // 查找封面和歌词（allFiles 中是完整 href，需用 endsWith 匹配文件名）
      let coverUrl = ''
      let lyricUrl = ''

      const baseName = fileName.substring(0, fileName.length - fileExt.length)
      const baseNameEncoded = encodeURIComponent(baseName)

      // 辅助：从 allFiles 中查找匹配文件名的条目，返回完整 href
      const findFileInAllFiles = (nameWithoutExt: string, exts: string[]): string | null => {
        const candidates = [
          ...exts.map(ext => `${nameWithoutExt}${ext}`),           // 未编码
          ...exts.map(ext => `${encodeURIComponent(nameWithoutExt)}${ext}`), // 编码
        ]
        for (const candidate of candidates) {
          for (const f of allFiles) {
            // 匹配：文件名完全一致，或以 /文件名 结尾
            if (f === candidate || f.endsWith('/' + candidate)) {
              return f
            }
          }
        }
        return null
      }

      // 查找封面
      let coverHref = findFileInAllFiles(baseName, coverExts)
      // V2.1.1：无同名封面时回退查找常见封面名（cover/folder/front/album/artwork）
      if (!coverHref) {
        const commonNames: string[] = ['cover', 'folder', 'front', 'album', 'artwork', 'AlbumArt']
        for (let ci = 0; ci < commonNames.length && !coverHref; ci++) {
          coverHref = findFileInAllFiles(commonNames[ci], coverExts)
        }
      }
      if (coverHref) {
        coverUrl = coverHref.startsWith('http') ? coverHref : (baseUrl + coverHref)
        coverUrl = coverUrl.replace(/^(https?:\/\/)([^@]*@)?/, `$1${encodedUser}:${encodedPass}@`)
      }

      // 查找歌词
      const lyricHref = findFileInAllFiles(baseName, lyricExts)
      if (lyricHref) {
        lyricUrl = lyricHref.startsWith('http') ? lyricHref : (baseUrl + lyricHref)
        lyricUrl = lyricUrl.replace(/^(https?:\/\/)([^@]*@)?/, `$1${encodedUser}:${encodedPass}@`)
      }

      songs.push({
        songId: `cloud_${fileName}`,
        songName: songName || fileName,
        artist: artist || '未知歌手',
        album: '',
        coverUrl: coverUrl,
        source: 'webdav',
        playUrl: playUrl,
        lyricUrl: lyricUrl,
      })

      match = hrefRegex.exec(xml)
    }

    return songs
  }

  // ===== 编辑/新建歌单 Sheet =====
  @Builder
  EditPlaylistSheet() {
    Column({ space: 20 }) {
      Text(this.editPlaylistTarget ? '编辑歌单' : '新建歌单')
        .fontSize(17)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      Row({ space: 16 }) {
        // 封面选择 - 方形虚线+
        Stack() {
          if (this.editPlaylistCoverUri && this.editPlaylistCoverUri.length > 0) {
            Image(this.editPlaylistCoverUri)
              .width(80).height(80).borderRadius(12).objectFit(ImageFit.Cover)
          } else {
            Column() {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(28).fontColor([this.themeTextSecondary])
            }
            .width(80).height(80)
            .border({ width: 2, color: this.themeDivider, style: BorderStyle.Dashed })
            .borderRadius(12)
            .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          }

          Row() {
            SymbolGlyph($r('sys.symbol.ellipsis_circle'))
              .fontSize(20).fontColor([Color.White])
          }
          .width(28).height(28).borderRadius(14).backgroundColor(this.themePrimary)
          .justifyContent(FlexAlign.Center)
          .position({ x: 56, y: 56 })
        }
        .flexShrink(0)
        .onClick(() => { this.pickPlaylistCover() })

        // 歌单名称输入
        TextInput({ placeholder: '歌单名称', text: this.editPlaylistName })
          .layoutWeight(1)
          .height(48)
          .fontSize(15)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.themePlaceholder)
          .borderRadius(12)
          .onChange((value: string) => { this.editPlaylistName = value })
      }
      .width('100%')

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1).height(44).fontSize(15)
          .fontColor(this.themeTextPrimary).backgroundColor(this.themeCardBg).borderRadius(22)
          .onClick(() => {
            this.showEditPlaylistSheet = false
            this.editPlaylistTarget = null
          })

        Button(this.editPlaylistTarget ? '保存' : '创建')
          .layoutWeight(1).height(44).fontSize(15)
          .fontColor(Color.White).backgroundColor(this.themePrimary).borderRadius(22)
          .onClick(() => { this.doSaveEditPlaylist() })
      }
      .width('100%')
    }
    .padding(24)
  }

  // ===== 移动歌单 Sheet =====
  @Builder
  MovePlaylistDialogSheet() {
    Column({ space: 12 }) {
      Text('移动到歌单')
        .fontSize(17)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 24, right: 24, top: 16 })

      Column({ space: 0 }) {
        ForEach(this.playlists, (playlist: Playlist) => {
          if (playlist.id !== this.selectedPlaylist?.id) {
            Row({ space: 12 }) {
              Row() {
                SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(18)
              }
              .width(36)
              .height(36)
              .borderRadius(8)
              .backgroundColor(this.themeCardBg)
              .justifyContent(FlexAlign.Center)

              Column({ space: 2 }) {
                Text(playlist.name)
                  .fontSize(15)
                  .fontColor(this.themeTextPrimary)
                  .fontWeight(FontWeight.Medium)
                Text(`${playlist.songCount} 首`)
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
            .onClick(async () => {
              if (this.multiSelectMode) {
                await this.batchMoveToPlaylist(playlist)
              } else if (this.movePlaylistTarget) {
                await this.db.addSongToPlaylist(playlist.id, this.movePlaylistTarget)
                await this.removeSongFromPlaylist(this.movePlaylistTarget)
                this.showToastMsg('已移动到歌单')
                this.showMovePlaylistDialog = false
                this.movePlaylistTarget = null
              }
            })
          }
        })
      }
      .width('100%')
      .constraintSize({ maxHeight: 300 })

      Column().height(16)
    }
    .width('100%')
    .backgroundColor(this.themeCardBg)
  }

  // ===== 复制到歌单 Sheet =====
  @Builder
  CopyPlaylistDialogSheet() {
    Column({ space: 12 }) {
      Text('复制到歌单')
        .fontSize(17)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 24, right: 24, top: 16 })

      Column({ space: 0 }) {
        ForEach(this.playlists, (playlist: Playlist) => {
          Row({ space: 12 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.list_bullet')).fontSize(18)
            }
            .width(36)
            .height(36)
            .borderRadius(8)
            .backgroundColor(this.themeCardBg)
            .justifyContent(FlexAlign.Center)

            Column({ space: 2 }) {
              Text(playlist.name)
                .fontSize(15)
                .fontColor(this.themeTextPrimary)
                .fontWeight(FontWeight.Medium)
              Text(`${playlist.songCount} 首`)
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
          .onClick(async () => {
            if (this.multiSelectMode) {
              await this.batchCopyToPlaylist(playlist)
            } else if (this.copyPlaylistTarget) {
              const added = await this.db.addSongToPlaylist(playlist.id, this.copyPlaylistTarget)
              this.showToastMsg(added ? '已复制到歌单' : '复制失败')
              if (this.subPage === 'playlistDetail') {
                await this.reloadPlaylistSongs()
              }
              await this.loadPlaylists()
              this.showCopyPlaylistDialog = false
              this.copyPlaylistTarget = null
            }
          })
        })
      }
      .width('100%')
      .constraintSize({ maxHeight: 300 })

      Column().height(16)
    }
    .width('100%')
    .backgroundColor(this.themeCardBg)
  }

  // ===== 调整位置 Sheet =====
  @Builder
  ReorderDialogSheet() {
    Column({ space: 20 }) {
      Text('调整位置')
        .fontSize(17)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      Text(`当前位置：${(this.reorderCurrentList ?? []).findIndex(s => s.songId === this.floatingSong?.songId && s.source === this.floatingSong?.source) + 1} / ${(this.reorderCurrentList ?? []).length}`)
        .fontSize(14)
        .fontColor(this.themeTextSecondary)
        .width('100%')

      TextInput({ placeholder: '请输入目标位置', text: this.reorderInput })
        .width('100%')
        .height(48)
        .fontSize(15)
        .padding({ left: 16, right: 16 })
        .backgroundColor(this.themePlaceholder)
        .borderRadius(12)
        .onChange((value: string) => {
          this.reorderInput = value
        })

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor(this.themeTextPrimary)
          .backgroundColor(this.themeCardBg)
          .borderRadius(22)
          .onClick(() => {
            this.showReorderDialog = false
            this.reorderInput = ''
          })

        Button('确定')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor(this.themePrimary)
          .borderRadius(22)
          .onClick(() => {
            this.doReorder()
          })
      }
      .width('100%')
    }
    .padding(24)
  }

  // 当前用于排序的歌曲列表
  private get reorderCurrentList(): SongInfo[] {
    if (this.subPage === 'cloudPlaylistDetail') {
      return this.cloudPlaylistSongs
    } else if (this.subPage === 'localMusicDetail') {
      return this.localMusicList.map((lm): SongInfo => ({
        songId: 'local_' + lm.id, songName: lm.songName, artist: lm.artist, album: '',
        coverUrl: lm.coverUrl, source: 'local', playUrl: lm.filePath, lyric: lm.lyric || '',
      }))
    }
    return this.playlistSongs
  }

  // ===== 歌曲信息 Sheet =====
  @Builder
  SongInfoSheet() {
    Column({ space: 16 }) {
      Text('歌曲信息')
        .fontSize(17)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      Column({ space: 12 }) {
        this.InfoRow('歌曲名称', this.songInfoSong?.songName || '-')
        this.InfoRow('歌手', this.songInfoSong?.artist || '-')
        this.InfoRow('专辑', this.songInfoSong?.album && this.songInfoSong.album.length > 0 ? this.songInfoSong.album : '-')
        this.InfoRow('来源', this.getSourceLabel(this.songInfoSong?.source || ''))
      }
      .width('100%')
    }
    .width('100%')
    .padding(24)
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(this.themeTextSecondary)
        .width(80)

      Text(value)
        .fontSize(14)
        .fontColor(this.themeTextPrimary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
  }

  private getSourceLabel(source: string): string {
    const map: Record<string, string> = {
      'qq': 'QQ音乐',
      'netease': '网易云音乐',
      'kugou': '酷狗音乐',
      'webdav': 'WebDAV 云端',
      'local': '本地音乐',
    }
    if (map[source]) return map[source]
    // 自定义源（custom_前缀）：显示源名称
    return SourceInfo.getName(source)
  }
}