// SHMY 数据模型定义 - V1.0.3 多源聚合
// MusicModel.ets
//
// 音源可用性（2026-06 参考 LX Music HarmonyOS 实测）
//   KW 酷我   ── 搜索 ✅  播放 ✅  歌词 ⚠️
//   KG 酷狗   ── 搜索 ✅  播放 ✅  歌词 ✅
//   TX QQ音乐 ── 搜索 ✅  播放 ✅  歌词 ✅
//   WY 网易云 ── 搜索 ✅  播放 ✅  歌词 ✅
//   MG 咪咕   ── 搜索 ✅  播放 ✅  歌词 ✅

// 音源类型
export enum SourceType {
  KW = 'kw',  // 酷我
  KG = 'kg',  // 酷狗
  TX = 'tx',  // QQ音乐
  WY = 'wy',  // 网易云
  MG = 'mg',  // 咪咕
  SPOTIFY = 'spotify',  // Spotify
  CUSTOM = 'custom',  // 自定义音源
}

// 音源信息项接口
export interface SourceInfoItem {
  name: string
  codeName: string
  color: string
  enabled: boolean
}

// 音源配置 - V1.0.3 新增
export interface SourceConfig {
  sources: Record<string, SourceInfoItem>
  enabledSources: string[]
  customSourceUrl: string
}

// 歌词颜色项接口
export interface LyricsColorItem {
  label: string
  value: string
}

// 音源信息映射（V1.0.3 更新：5大内置音源全部启用）
export class SourceInfo {
  static readonly MAP: Record<string, SourceInfoItem> = {
    [SourceType.KW]: { name: '\u9177\u6211', codeName: '\u9177\u6211\u97F3\u4E50', color: '#FF9800', enabled: true },
    [SourceType.KG]: { name: '\u9177\u72D7', codeName: '\u9177\u72D7\u97F3\u4E50', color: '#2196F3', enabled: true },
    [SourceType.TX]: { name: 'QQ', codeName: 'QQ\u97F3\u4E50', color: '#4CAF50', enabled: true },
    [SourceType.WY]: { name: '\u7F51\u6613\u4E91', codeName: '\u7F51\u6613\u4E91\u97F3\u4E50', color: '#E53935', enabled: true },
    [SourceType.MG]: { name: '\u54AA\u5495', codeName: '\u54AA\u5495\u97F3\u4E50', color: '#9C27B0', enabled: true },
    [SourceType.SPOTIFY]: { name: 'Spotify', codeName: 'Spotify', color: '#1DB954', enabled: true },
    [SourceType.CUSTOM]: { name: '\u81EA\u5B9A\u4E49', codeName: '\u81EA\u5B9A\u4E49\u97F3\u6E90', color: '#607D8B', enabled: false },
    'local': { name: '\u672C\u5730', codeName: '\u672C\u5730\u97F3\u4E50', color: '#607D8B', enabled: true },
    // 自建 API 源
    'netease': { name: '\u7F51\u6613\u4E91', codeName: '\u7F51\u6613\u4E91\u97F3\u4E50', color: '#E53935', enabled: true },
    'qq': { name: 'QQ', codeName: 'QQ\u97F3\u4E50', color: '#4CAF50', enabled: true },
    'kugou': { name: '\u9177\u72D7', codeName: '\u9177\u72D7\u97F3\u4E50', color: '#2196F3', enabled: true },
    'kuwo': { name: '\u9177\u6211', codeName: '\u9177\u6211\u97F3\u4E50', color: '#FF9800', enabled: true },
    'migu': { name: '\u54AA\u5495', codeName: '\u54AA\u5495\u97F3\u4E50', color: '#9C27B0', enabled: true },
  }

  // 默认启用的音源列表（用于"全部"聚合搜索）
  static readonly DEFAULT_ENABLED: string[] = [
    SourceType.KW, SourceType.KG, SourceType.TX, SourceType.WY, SourceType.MG, SourceType.SPOTIFY,
  ]

  static getName(source: string): string {
    return SourceInfo.MAP[source]?.name ?? source
  }

  static getColor(source: string): string {
    return SourceInfo.MAP[source]?.color ?? '#999999'
  }

  static getCodeName(source: string): string {
    return SourceInfo.MAP[source]?.codeName ?? source
  }

  static isEnabled(source: string): boolean {
    return SourceInfo.MAP[source]?.enabled ?? false
  }
}

// 歌曲信息（V1.0.3：新增 albumId/artistId 用于多平台播放）
export interface SongInfo {
  songId: string
  songName: string
  artist: string
  album: string
  coverUrl: string
  source: string
  playUrl: string
  quality?: string
  lyricUrl?: string
  // V1.0.3 新增：用于播放URL获取的额外参数
  albumId?: string
  artistId?: string
  hash?: string
  mid?: string
}

// 搜索结果（同 SongInfo）
export type SearchResult = SongInfo

// 歌词行
export interface LyricLine {
  time: number   // 秒
  text: string
}

// 下载状态
export enum DownloadStatus {
  PENDING = 'pending',
  DOWNLOADING = 'downloading',
  COMPLETED = 'completed',
  FAILED = 'failed',
}

// 下载记录
export interface DownloadItem {
  id: string
  songId: string
  songName: string
  artist: string
  album: string
  coverUrl: string
  source: string
  playUrl: string
  quality: string
  status: string
  progress: number
  createdAt: number
}

// 歌单
export interface Playlist {
  id: string
  name: string
  songCount: number
  createdAt: number
  updatedAt: number
  coverUrl: string
  sortOrder: number
}

// 应用设置
export interface AppSettings {
  theme: string
  customBackground: boolean
  customBackgroundPath: string
  useSystemFont: boolean
  fontSize: string
  autoPlay: boolean
  autoJumpDetail: boolean
  lyricsPosition: string
  rememberProgress: boolean
  autoStopOnOtherAudio: boolean
  desktopLyrics: boolean
  lockDesktopLyrics: boolean
  notificationCard: boolean
  multiLineLyrics: boolean
  lyricsSize: string
  lyricsColor: string
  lyricsBgOpacity: number
  // V1.0.3 新增
  enabledSources: string[]
  customSourceUrl: string
  // 自建 API 模式
  useSelfHostedApi: boolean
  selfHostedApiUrl: string
}

// 默认设置
export const DEFAULT_SETTINGS: AppSettings = {
  theme: 'light',
  customBackground: false,
  customBackgroundPath: '',
  useSystemFont: false,
  fontSize: 'standard',
  autoPlay: false,
  autoJumpDetail: false,
  lyricsPosition: 'center',
  rememberProgress: true,
  autoStopOnOtherAudio: false,
  desktopLyrics: false,
  lockDesktopLyrics: false,
  notificationCard: false,
  multiLineLyrics: false,
  lyricsSize: 'standard',
  lyricsColor: '#FFFFFF',
  lyricsBgOpacity: 50,
  enabledSources: SourceInfo.DEFAULT_ENABLED.slice(),
  customSourceUrl: '',
  useSelfHostedApi: false,
  selfHostedApiUrl: '',
}

// 桌面歌词颜色预设
export const LYRICS_COLORS: LyricsColorItem[] = [
  { label: '\u767D\u8272', value: '#FFFFFF' },
  { label: '\u5929\u84DD', value: '#64B5F6' },
  { label: '\u6D45\u7EFF', value: '#81C784' },
  { label: '\u6696\u6A59', value: '#FFB74D' },
  { label: '\u6DE1\u7C89', value: '#F48FB1' },
]

// 启动弹窗信息
export interface StartupInfo {
  version: string
  updateUrl: string
  updateContent: string[]
}

// 创建空 SongInfo 的辅助函数
export function createEmptySongInfo(): SongInfo {
  return {
    songId: '',
    songName: '',
    artist: '',
    album: '',
    coverUrl: '',
    source: '',
    playUrl: '',
  }
}