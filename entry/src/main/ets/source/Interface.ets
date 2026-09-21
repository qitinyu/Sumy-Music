/**
 * 音源引擎接口定义
 * 基于 lx-music 插件标准，兼容 123 项目架构
 */

export type OnlineSource = 'kw' | 'kg' | 'tx' | 'wy' | 'mg'
// 自定义源（如全豆要的 qsvip）允许任意字符串，由引擎侧插件自行解释
export type LXSource = OnlineSource | 'local' | string
export type LXQuality = '128k' | '320k' | 'flac' | 'flac24bit' | '192k' | 'ape' | 'wav'

/** 音源信息（来自 JS 插件的 sources 声明） */
export interface LXUserApiSourceInfo {
  name: string
  type: string
  actions: string[]
  qualitys: LXQuality[]
}

/** 完整音源信息（含脚本内容） */
export interface LXUserApiInfoFull {
  id: string
  name: string
  description: string
  script: string
  allowShowUpdateAlert: boolean
  author: string
  homepage: string
  version: string
  sources: Record<string, LXUserApiSourceInfo>
}

/** 音源列表条目（不含脚本内容） */
export interface LXUserApiInfo {
  id: string
  name: string
  description: string
  allowShowUpdateAlert: boolean
  author: string
  homepage: string
  version: string
  sources: Record<string, LXUserApiSourceInfo>
}

/** 音乐 URL 信息 */
export interface LXMusicUrlInfo {
  type: LXQuality
  url: string
}

/** 音乐 URL 请求结果 */
export interface LXMusicUrlResult {
  source: LXSource
  action: string
  data: LXMusicUrlInfo
}

/** 歌词数据 */
export interface LXLyricData {
  lyric: string
  tlyric: string | null
  rlyric: string | null
  lxlyric: string | null
}

/** 歌词请求结果 */
export interface LXLyricResult {
  source: LXSource
  action: string
  data: LXLyricData
}

/** 封面请求结果 */
export interface LXPicResult {
  source: LXSource
  action: string
  data: string
}

/** 引擎初始化消息 */
export interface LXSourceInitMessage {
  sources: Record<string, LXUserApiSourceInfo>
}

/** 引擎请求数据 */
export interface LXSourceRequestData {
  source: LXSource
  action: string
  info: object
}