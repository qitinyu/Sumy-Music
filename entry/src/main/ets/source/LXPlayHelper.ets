/**
 * 播放请求封装
 * 提供 getMusicUrl / getLyric / getPic 等高级 API
 * 适配自 123 项目 LXPlayHelper
 */
import { LXSourceRequestData, LXMusicUrlResult, LXLyricResult, LXPicResult, LXSource } from './Interface';
import type { SongInfo } from '../model/MusicModel';
import { lxEngineSendRequest, lxEngineRegisterPromise, lxEngineIsReady } from './LXSourceEngine';

interface MusicInfoBrief {
  songmid: string;
  source: string;
  name?: string;
  singer?: string;
  albumName?: string;
  img?: string;
}

interface SearchRequestInfo {
  keyword: string;
  page: number;
  pagesize: number;
}

interface SearchListItem {
  id?: string;
  songmid?: string;
  hash?: string;
  name?: string;
  singer?: string;
  artist?: string;
  albumName?: string;
  album?: string;
  duration?: number | string;
  pic?: string;
  img?: string;
  _raw?: object;
}

interface SearchResultList {
  list: SearchListItem[];
}

interface SearchResult {
  source: string;
  action: string;
  data: SearchResultList;
}

interface MusicUrlRequestInfo {
  type: string;
  musicInfo: MusicInfoBrief;
}

interface LyricPicRequestInfo {
  musicInfo: MusicInfoBrief;
}

function logError(msg: string): void {
  let prev: string = AppStorage.get<string>('lxLastError') || '';
  let now: Date = new Date();
  let time: string = now.getHours().toString().padStart(2, '0') + ':' +
    now.getMinutes().toString().padStart(2, '0') + ':' +
    now.getSeconds().toString().padStart(2, '0');
  AppStorage.setOrCreate('lxLastError', '[' + time + '] ' + msg);
  let log: string = AppStorage.get<string>('lxPlayLog') || '';
  log += '[' + time + '] ' + msg + '\n';
  if (log.length > 20000) {
    log = log.substring(log.length - 5000);
  }
  AppStorage.setOrCreate('lxPlayLog', log);
}
export { logError };

function buildMusicInfo(source: string, songId: string, name?: string, singer?: string,
  albumName?: string, img?: string): MusicInfoBrief {
  const info: MusicInfoBrief = { songmid: songId, source: source };
  if (name !== undefined && name.length > 0) {
    info.name = name;
  }
  if (singer !== undefined && singer.length > 0) {
    info.singer = singer;
  }
  if (albumName !== undefined && albumName.length > 0) {
    info.albumName = albumName;
  }
  if (img !== undefined && img.length > 0) {
    info.img = img;
  }
  return info;
}

export async function getLXMusicUrl(source: string, songId: string, quality: string, name?: string,
  singer?: string): Promise<string> {
  if (!lxEngineIsReady) {
    logError('引擎未就绪');
    throw new Error('引擎未就绪');
  }
  if (lxEngineSendRequest === null || lxEngineRegisterPromise === null) {
    logError('引擎回调未初始化');
    throw new Error('引擎回调未初始化');
  }
  let sendReq: (key: string, data: LXSourceRequestData) => void = lxEngineSendRequest;
  let regReq: (key: string,
    resolve: (result: object) => void, reject: (reason: Error) => void, timeoutMs?: number) => void = lxEngineRegisterPromise;
  let requestKey: string = 'musicUrl_' + Date.now() + '_' + Math.random().toString(36).substring(2);
  let musicInfo: MusicInfoBrief = buildMusicInfo(source, songId, name, singer);
  let info: MusicUrlRequestInfo = { type: quality, musicInfo: musicInfo };
  let reqData: LXSourceRequestData = { source: source as LXSource, action: 'musicUrl', info: info };
  // 插件内部取链超时 20s，汽水 VIP 代理解密可达 60s，留足余量
  const PLAY_TIMEOUT: number = 80000;
  logError('发送请求: ' + source + '/' + songId + '/' + quality);
  return new Promise<string>((resolve: (url: string) => void, reject: (reason: Error) => void): void => {
    regReq(requestKey, (result: object): void => {
      let mr: LXMusicUrlResult = result as LXMusicUrlResult;
      if (mr !== undefined && mr.data !== undefined && mr.data.url !== undefined && mr.data.url.length > 0) {
        logError('获取成功: ' + mr.data.url.substring(0, 80));
        resolve(mr.data.url);
      } else {
        let msg: string = '响应数据无效: ' + JSON.stringify(result).substring(0, 200);
        logError(msg);
        reject(new Error(msg));
      }
    }, (reason: Error): void => {
      logError('请求失败: ' + reason.message);
      reject(reason);
    }, PLAY_TIMEOUT);
    sendReq(requestKey, reqData);
  });
}

export async function getLXLyric(source: string, songId: string, name?: string, singer?: string): Promise<string> {
  if (!lxEngineIsReady || lxEngineSendRequest === null || lxEngineRegisterPromise === null) {
    logError('getLXLyric: 引擎未就绪');
    throw new Error('引擎未就绪');
  }
  let sendReq: (key: string, data: LXSourceRequestData) => void = lxEngineSendRequest;
  let regReq: (key: string,
    resolve: (result: object) => void, reject: (reason: Error) => void, timeoutMs?: number) => void = lxEngineRegisterPromise;
  let requestKey: string = 'lyric_' + Date.now() + '_' + Math.random().toString(36).substring(2);
  let musicInfo: MusicInfoBrief = buildMusicInfo(source, songId, name, singer);
  let info: LyricPicRequestInfo = { musicInfo: musicInfo };
  let reqData: LXSourceRequestData = { source: source as LXSource, action: 'lyric', info: info };
  const LYRIC_TIMEOUT: number = 40000;
  return new Promise<string>((resolve: (text: string) => void, reject: (reason: Error) => void): void => {
    regReq(requestKey, (result: object): void => {
      let lr: LXLyricResult = result as LXLyricResult;
      if (lr.data !== undefined) {
        resolve(lr.data.lyric);
      } else {
        logError('getLXLyric: 无效响应');
        reject(new Error('Invalid lyric response'));
      }
    }, reject, LYRIC_TIMEOUT);
    sendReq(requestKey, reqData);
  });
}

export async function getLXPic(source: string, songId: string, name?: string, singer?: string): Promise<string> {
  if (!lxEngineIsReady || lxEngineSendRequest === null || lxEngineRegisterPromise === null) {
    logError('getLXPic: 引擎未就绪');
    throw new Error('引擎未就绪');
  }
  let sendReq: (key: string, data: LXSourceRequestData) => void = lxEngineSendRequest;
  let regReq: (key: string,
    resolve: (result: object) => void, reject: (reason: Error) => void) => void = lxEngineRegisterPromise;
  let requestKey: string = 'pic_' + Date.now() + '_' + Math.random().toString(36).substring(2);
  let musicInfo: MusicInfoBrief = buildMusicInfo(source, songId, name, singer);
  let info: LyricPicRequestInfo = { musicInfo: musicInfo };
  let reqData: LXSourceRequestData = { source: source as LXSource, action: 'pic', info: info };
  return new Promise<string>((resolve: (url: string) => void, reject: (reason: Error) => void): void => {
    regReq(requestKey, (result: object): void => {
      let pr: LXPicResult = result as LXPicResult;
      if (pr.data !== undefined) {
        resolve(pr.data);
      } else {
        logError('getLXPic: 无效响应');
        reject(new Error('Invalid pic response'));
      }
    }, reject);
    sendReq(requestKey, reqData);
  });
}

/**
 * 通过 LX 引擎搜索歌曲（v3 插件，如全豆要的 qsvip 源）。
 * 引擎就绪时向插件发送 musicSearch 请求，把返回的 list 归一化为 SongInfo。
 */
export async function getLXSearch(source: string, keyword: string, page: number = 1,
  pagesize: number = 30): Promise<SongInfo[]> {
  if (!lxEngineIsReady || lxEngineSendRequest === null || lxEngineRegisterPromise === null) {
    logError('getLXSearch: 引擎未就绪');
    throw new Error('引擎未就绪');
  }
  let sendReq: (key: string, data: LXSourceRequestData) => void = lxEngineSendRequest;
  let regReq: (key: string,
    resolve: (result: object) => void, reject: (reason: Error) => void, timeoutMs?: number) => void = lxEngineRegisterPromise;
  let requestKey: string = 'musicSearch_' + Date.now() + '_' + Math.random().toString(36).substring(2);
  let info: SearchRequestInfo = { keyword: keyword, page: page, pagesize: pagesize };
  let reqData: LXSourceRequestData = { source: source as LXSource, action: 'musicSearch', info: info };
  // 插件内部搜索超时 15s，引擎层需留足余量，避免提前掐断
  const SEARCH_TIMEOUT: number = 40000;
  return new Promise<SongInfo[]>((resolve: (songs: SongInfo[]) => void, reject: (reason: Error) => void): void => {
    regReq(requestKey, (result: object): void => {
      let sr: SearchResult = result as SearchResult;
      let list: SearchListItem[] = (sr !== undefined && sr.data !== undefined && sr.data.list !== undefined)
        ? sr.data.list : [];
      let songs: SongInfo[] = [];
      for (let i = 0; i < list.length; i++) {
        let song: SongInfo | null = toSongInfo(list[i], source);
        if (song !== null) {
          songs.push(song);
        }
      }
      logError('搜索成功: ' + source + ' 返回 ' + songs.length + ' 首');
      resolve(songs);
    }, (reason: Error): void => {
      logError('搜索失败: ' + reason.message);
      reject(reason);
    }, SEARCH_TIMEOUT);
    sendReq(requestKey, reqData);
  });
}

/** 插件搜索条目 → SongInfo（字段名兼容 LX 系与 MusicFree 系） */
function toSongInfo(item: SearchListItem, platform: string): SongInfo | null {
  let strOf = (v: string | number | undefined | null): string => {
    if (v === undefined || v === null) return '';
    if (typeof v === 'string') return v;
    return String(v);
  };
  let id: string = strOf(item.id) || strOf(item.songmid) || strOf(item.hash);
  let name: string = strOf(item.name);
  if (id.length === 0 || name.length === 0) return null;
  let artist: string = strOf(item.singer) || strOf(item.artist);
  let cover: string = strOf(item.pic) || strOf(item.img);
  if (cover.startsWith('//')) cover = 'https:' + cover;
  let durNum: number = 0;
  if (typeof item.duration === 'number') {
    durNum = item.duration as number;
  } else {
    durNum = Number.parseInt(strOf(item.duration)) || 0;
  }
  // 插件返回的 duration 单位是毫秒，转成 mm:ss
  if (durNum > 3600) durNum = Math.floor(durNum / 1000);
  let durText: string = `${Math.floor(durNum / 60)}:${(durNum % 60).toString().padStart(2, '0')}`;
  let song: SongInfo = {
    songId: id,
    songName: name,
    artist: artist,
    album: strOf(item.albumName) || strOf(item.album),
    coverUrl: cover,
    source: platform,
    playUrl: '',
    quality: '128kbps/' + durText,
    rawData: JSON.stringify(item),
  };
  return song;
}