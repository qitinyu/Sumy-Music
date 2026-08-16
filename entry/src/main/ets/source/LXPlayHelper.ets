/**
 * 播放请求封装
 * 提供 getMusicUrl / getLyric / getPic 等高级 API
 * 适配自 123 项目 LXPlayHelper
 */
import { LXSourceRequestData, LXMusicUrlResult, LXLyricResult, LXPicResult, LXSource } from './Interface';
import { lxEngineSendRequest, lxEngineRegisterPromise, lxEngineIsReady } from './LXSourceEngine';

interface MusicInfoBrief {
  songmid: string;
  source: string;
  name?: string;
  singer?: string;
  albumName?: string;
  img?: string;
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
    resolve: (result: object) => void, reject: (reason: Error) => void) => void = lxEngineRegisterPromise;
  let requestKey: string = 'musicUrl_' + Date.now() + '_' + Math.random().toString(36).substring(2);
  let musicInfo: MusicInfoBrief = buildMusicInfo(source, songId, name, singer);
  let info: MusicUrlRequestInfo = { type: quality, musicInfo: musicInfo };
  let reqData: LXSourceRequestData = { source: source as LXSource, action: 'musicUrl', info: info };
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
    });
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
    resolve: (result: object) => void, reject: (reason: Error) => void) => void = lxEngineRegisterPromise;
  let requestKey: string = 'lyric_' + Date.now() + '_' + Math.random().toString(36).substring(2);
  let musicInfo: MusicInfoBrief = buildMusicInfo(source, songId, name, singer);
  let info: LyricPicRequestInfo = { musicInfo: musicInfo };
  let reqData: LXSourceRequestData = { source: source as LXSource, action: 'lyric', info: info };
  return new Promise<string>((resolve: (text: string) => void, reject: (reason: Error) => void): void => {
    regReq(requestKey, (result: object): void => {
      let lr: LXLyricResult = result as LXLyricResult;
      if (lr.data !== undefined) {
        resolve(lr.data.lyric);
      } else {
        logError('getLXLyric: 无效响应');
        reject(new Error('Invalid lyric response'));
      }
    }, reject);
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