/**
 * JS 音源引擎 V2：基于 QuickJS 轻量级 JS 引擎执行标准格式 JS 插件
 * - 使用 QuickJS 引擎替代 WebView，提升性能和内存效率
 * - 支持插件全局 API：request / http.get / http.post / log
 * - v3 事件驱动插件（全豆要等）：globalThis.lx 兼容层
 * - 向后兼容原有 JsPluginEngine 接口
 */
import type { SongInfo } from '../model/MusicModel';
import type { SourceConfig } from './SourceManager';
import { QuickJSEngine, QuickJSPluginCallResult } from './QuickJSEngine';
import { PluginDiagnostics } from './PluginDiagnostics';

/** 插件调用结果 */
export interface PluginCallResult {
  ok: boolean;
  data?: Object;
  error?: string;
}

/** 插件 search(info, page, type) 兼容参数（信息对象形式） */
interface SearchInfoArg {
  keyword: string;
  name: string;
  artist: string;
  album: string;
}

/** 插件歌曲参数回退结构 */
interface FallbackSongPayload {
  id: string;
  songId: string;
  songmid: string;
  hash: string;
  name: string;
  title: string;
  singer: string;
  artist: string;
  album: string;
}

/** v3 插件 musicSearch 参数 */
interface V3SearchInfo {
  keyword: string;
  page: number;
  pagesize: number;
}

/** v3 插件 musicUrl 参数 */
interface V3MusicInfo {
  musicInfo: Object;
  type: string;
}

/** v3 插件 lyric 参数 */
interface V3LyricInfo {
  musicInfo: Object;
}

const SEARCH_TIMEOUT: number = 30000;
const PLAY_TIMEOUT: number = 50000;
const LYRIC_TIMEOUT: number = 30000;
const DEFAULT_QUALITY: string = '128k';

/**
 * JS 插件引擎单例 V2
 * 使用 QuickJS 引擎替代 WebView
 */
export class JsPluginEngine {
  static ready: boolean = false;
  /** 最近一次插件调用失败原因 */
  static lastError: string = '';
  private static initialized: boolean = false;

  /** 初始化引擎 */
  static init(): void {
    if (JsPluginEngine.initialized) {
      return;
    }
    QuickJSEngine.init();
    JsPluginEngine.ready = true;
    JsPluginEngine.initialized = true;
    console.info('[JsPluginEngine] QuickJS engine initialized');
  }

  /** 确保引擎就绪 */
  public static async ensureReady(): Promise<boolean> {
    if (!JsPluginEngine.initialized) {
      JsPluginEngine.init();
    }
    return JsPluginEngine.ready;
  }

  /** 执行插件方法 */
  static async callPlugin(config: SourceConfig, func: string, args: Object[], timeoutMs: number): Promise<PluginCallResult> {
    await JsPluginEngine.ensureReady();
    PluginDiagnostics.info(config.name, func, 'call start', `timeout=${timeoutMs}`)
    const result = await QuickJSEngine.callPlugin(config, func, args, timeoutMs);
    if (!result.ok) {
      PluginDiagnostics.error(config.name, func, 'call failed', result.error ?? '')
    } else {
      PluginDiagnostics.info(config.name, func, 'call success')
    }
    return result as PluginCallResult;
  }

  /** 执行 v3 插件动作 */
  private static async callV3(config: SourceConfig, action: string, source: string, infoJson: string, timeoutMs: number): Promise<PluginCallResult> {
    await JsPluginEngine.ensureReady();
    PluginDiagnostics.info(config.name, action, 'v3 call start', `source=${source}; timeout=${timeoutMs}`)
    const result = await QuickJSEngine.callV3(config, action, source, infoJson, timeoutMs);
    if (!result.ok) {
      PluginDiagnostics.error(config.name, action, 'v3 call failed', result.error ?? '')
    } else {
      PluginDiagnostics.info(config.name, action, 'v3 call success', `source=${source}`)
    }
    return result as PluginCallResult;
  }

  /** 执行 v3 插件动作（多音源分发） */
  private static async callV3Multi(config: SourceConfig, action: string, sources: string[], infoJson: string, timeoutMs: number): Promise<PluginCallResult> {
    await JsPluginEngine.ensureReady();
    // 简化实现：依次尝试每个音源
    for (const source of sources) {
      const result = await QuickJSEngine.callV3(config, action, source, infoJson, timeoutMs);
      if (result.ok) {
        return result;
      }
    }
    return { ok: false, error: '所有音源均失败' };
  }

  /** v3 插件已解析的音源 id 缓存 */
  private static v3SourcesCache: Map<string, string> = new Map();

  static clearV3SourcesCache(pluginName?: string): void {
    if (!pluginName || pluginName.length === 0) {
      JsPluginEngine.v3SourcesCache.clear();
      return;
    }
    const prefix: string = pluginName + '|';
    const keys: string[] = [];
    JsPluginEngine.v3SourcesCache.forEach((_value: string, key: string) => {
      if (key.startsWith(prefix)) {
        keys.push(key);
      }
    });
    for (let i = 0; i < keys.length; i++) {
      JsPluginEngine.v3SourcesCache.delete(keys[i]);
    }
  }

  /** 按 action 解析 v3 插件中支持该 action 的所有音源 id */
  private static async resolveV3SourcesForAction(config: SourceConfig, action: string): Promise<string[]> {
    const cacheKey: string = config.name + '|' + action;
    const cached: string | undefined = JsPluginEngine.v3SourcesCache.get(cacheKey);
    if (cached !== undefined && cached.length > 0) {
      try {
        return JSON.parse(cached) as string[];
      } catch (_e) {
      }
    }

    // 经 QuickJS __v3Sources 解析插件 send(inited,{sources}) 上报的音源 id 集合
    const sources: string[] = await QuickJSEngine.getV3Sources(config, action);
    JsPluginEngine.v3SourcesCache.set(cacheKey, JSON.stringify(sources));
    return sources;
  }

  /** 解析 v3 插件中支持 musicSearch 的所有音源 id */
  private static async resolveV3SearchSources(config: SourceConfig): Promise<string[]> {
    return await JsPluginEngine.resolveV3SourcesForAction(config, 'musicSearch');
  }

  /** v3 插件搜索 */
  private static async searchV3(config: SourceConfig, keyword: string): Promise<SongInfo[]> {
    const sources: string[] = await JsPluginEngine.resolveV3SearchSources(config);
    if (sources.length === 0) {
      JsPluginEngine.lastError = `插件 ${config.name} 未声明支持搜索动作(musicSearch)`;
      console.warn('[JsPluginEngine] v3 search: ' + JsPluginEngine.lastError);
      return [];
    }
    const info: V3SearchInfo = { keyword: keyword, page: 1, pagesize: 30 };
    const result: PluginCallResult = await JsPluginEngine.callV3Multi(config, 'musicSearch', sources, JSON.stringify(info), SEARCH_TIMEOUT);
    if (!result.ok || result.data === undefined || result.data === null) {
      JsPluginEngine.lastError = `插件 ${config.name} 搜索失败：${result.error ?? '无返回数据'}`;
      console.warn('[JsPluginEngine] v3 search failed:', JsPluginEngine.lastError);
      return [];
    }
    const rec: Record<string, Object> = result.data as Record<string, Object>;
    const list: Object | undefined = rec['list'];
    if (!(list instanceof Array)) {
      JsPluginEngine.lastError = `插件 ${config.name} 搜索返回数据格式异常`;
      return [];
    }
    const arr: Object[] = list as Object[];
    const songs: SongInfo[] = [];
    for (let i = 0; i < arr.length; i++) {
      const item: Record<string, Object> = arr[i] as Record<string, Object>;
      const song: SongInfo | null = JsPluginEngine.toSongInfo(item, config.name);
      if (song) {
        songs.push(song);
      }
    }
    JsPluginEngine.lastError = '';
    return songs;
  }

  /** 插件搜索 */
  static async search(config: SourceConfig, keyword: string): Promise<SongInfo[]> {
    JsPluginEngine.lastError = '';
    await JsPluginEngine.ensureReady();

    // v3 事件驱动插件
    if (config.jsMode === 'v3') {
      return await JsPluginEngine.searchV3(config, keyword);
    }

    // 兼容两种插件签名
    let data: Object | undefined;
    const start: number = Date.now();
    const searchNames: string[] = ['search', 'searchMusic'];
    
    for (let attempt = 0; attempt < searchNames.length; attempt++) {
      const first = await JsPluginEngine.callPlugin(config, searchNames[attempt], [keyword, 1, ''], SEARCH_TIMEOUT);
      if (!first.ok) {
        if (attempt === 0) {
          console.warn(`[JsPluginEngine] search "${keyword}" failed with 'search', trying 'searchMusic': ${first.error}`);
        } else {
          console.warn(`[JsPluginEngine] search "${keyword}" failed: ${first.error}`);
        }
        continue;
      }
      const arr: Object[] | null = JsPluginEngine.extractSongArray(first.data);
      if (arr !== null) {
        data = arr;
        break;
      } else if (first.ok && (Date.now() - start) < 5000) {
        const info: SearchInfoArg = { keyword: keyword, name: keyword, artist: '', album: '' };
        const retry = await JsPluginEngine.callPlugin(config, searchNames[attempt],
          [info as Object, 1, ''], SEARCH_TIMEOUT);
        if (retry.ok) {
          const arr2: Object[] | null = JsPluginEngine.extractSongArray(retry.data);
          if (arr2 !== null) {
            data = arr2;
            break;
          }
        }
      }
    }
    
    if (data === undefined || !(data instanceof Array)) {
      JsPluginEngine.lastError = `插件 ${config.name} 搜索无返回结果`;
      return [];
    }
    
    const arr3: Object[] = data as Object[];
    const songs: SongInfo[] = [];
    for (let i = 0; i < arr3.length; i++) {
      const item = arr3[i] as Record<string, Object>;
      const song: SongInfo | null = JsPluginEngine.toSongInfo(item, config.name);
      if (song) {
        songs.push(song);
      }
    }
    return songs;
  }

  /** 从插件返回数据中提取歌曲数组 */
  private static extractSongArray(data: Object | undefined): Object[] | null {
    if (data === undefined || data === null) {
      return null;
    }
    if (data instanceof Array) {
      return data as Object[];
    }
    if (typeof data === 'object') {
      const rec: Record<string, Object> = data as Record<string, Object>;
      const keys: string[] = ['list', 'data', 'result', 'songs'];
      for (let i = 0; i < keys.length; i++) {
        const val: Object | undefined = rec[keys[i]];
        if (val instanceof Array) {
          return val as Object[];
        }
      }
    }
    return null;
  }

  /** 插件取播放链接 */
  static async getPlayUrl(config: SourceConfig, song?: SongInfo): Promise<string> {
    if (!song) {
      return '';
    }
    
    await JsPluginEngine.ensureReady();

    if (song.playUrl && (song.playUrl.startsWith('http://') || song.playUrl.startsWith('https://'))) {
      return song.playUrl;
    }

    // v3 事件驱动插件
    if (config.jsMode === 'v3') {
      const sources: string[] = await JsPluginEngine.resolveV3SourcesForAction(config, 'musicUrl');
      if (sources.length === 0) {
        JsPluginEngine.lastError = `插件 ${config.name} 未声明支持播放动作(musicUrl)`;
        return '';
      }
      const musicInfo: Object = JSON.parse(JsPluginEngine.buildSongInfoJson(song)) as Object;
      const info: V3MusicInfo = { musicInfo: musicInfo, type: DEFAULT_QUALITY };
      const result = await JsPluginEngine.callV3Multi(config, 'musicUrl', sources, JSON.stringify(info), PLAY_TIMEOUT);
      if (!result.ok) {
        JsPluginEngine.lastError = `插件 ${config.name} 获取播放链接失败：${result.error ?? ''}`;
        return '';
      }
      const url: string = JsPluginEngine.extractUrl(result.data);
      if (url.length === 0) {
        JsPluginEngine.lastError = `插件 ${config.name} 播放链接为空`;
      }
      return url;
    }

    const songInfoJson: string = JsPluginEngine.buildSongInfoJson(song);
    const songInfoObj: Object = JSON.parse(songInfoJson) as Object;
    
    // 按优先级尝试多种播放方法名
    const methodNames: string[] = ['getMusicUrl', 'requestMusicUrl', 'getPlayUrl', 'getMusicInfo', 'getMediaSource'];
    for (let i = 0; i < methodNames.length; i++) {
      const qualityArg: string = methodNames[i] === 'getMediaSource' ? 'low' : DEFAULT_QUALITY;
      const result = await JsPluginEngine.callPlugin(config, methodNames[i], [songInfoObj, qualityArg], PLAY_TIMEOUT);
      if (result.ok) {
        const url: string = JsPluginEngine.extractUrl(result.data);
        if (url.length > 0) {
          if (i > 0) {
            console.info(`[JsPluginEngine] 播放方法名兼容: ${methodNames[i]} (非首选)`);
          }
          return url;
        }
      }
    }
    return '';
  }

  /** 从插件返回数据中提取 http(s) 播放链接 */
  private static extractUrl(data: Object | undefined): string {
    if (data === undefined || data === null) {
      return '';
    }
    if (typeof data === 'string') {
      const s = data as string;
      return (s.startsWith('http://') || s.startsWith('https://')) ? s.trim() : '';
    }
    const rec = data as Record<string, Object>;
    const u: string = (JsPluginEngine.strOf(rec['url']) || JsPluginEngine.strOf(rec['data'])).trim();
    return (u.startsWith('http://') || u.startsWith('https://')) ? u : '';
  }

  /** 插件取歌词 */
  static async getLyric(config: SourceConfig, song?: SongInfo): Promise<string> {
    if (!song) {
      return '';
    }
    
    await JsPluginEngine.ensureReady();

    // v3 事件驱动插件
    if (config.jsMode === 'v3') {
      const sources: string[] = await JsPluginEngine.resolveV3SourcesForAction(config, 'lyric');
      if (sources.length === 0) {
        JsPluginEngine.lastError = `插件 ${config.name} 未声明支持歌词动作(lyric)`;
        return '';
      }
      const musicInfo: Object = JSON.parse(JsPluginEngine.buildSongInfoJson(song)) as Object;
      const info: V3LyricInfo = { musicInfo: musicInfo };
      const result = await JsPluginEngine.callV3Multi(config, 'lyric', sources, JSON.stringify(info), LYRIC_TIMEOUT);
      if (!result.ok) {
        JsPluginEngine.lastError = `插件 ${config.name} 获取歌词失败：${result.error ?? ''}`;
        return '';
      }
      const data: Object | undefined = result.data;
      if (data === undefined || data === null) {
        JsPluginEngine.lastError = `插件 ${config.name} 歌词为空`;
        return '';
      }
      const rec = data as Record<string, Object>;
      const lrc: string = JsPluginEngine.strOf(rec['lrc']) || JsPluginEngine.strOf(rec['lyric']) || JsPluginEngine.strOf(rec['data']);
      return lrc.includes('[') ? lrc : '';
    }

    const songInfoJson: string = JsPluginEngine.buildSongInfoJson(song);
    const songInfoObj: Object = JSON.parse(songInfoJson) as Object;
    
    // 按优先级尝试多种歌词方法名
    const methodNames: string[] = ['getLyric', 'getLrc', 'getMusicLyric', 'getMediaSource'];
    for (let i = 0; i < methodNames.length; i++) {
      const lyricArgs: Object[] = methodNames[i] === 'getMediaSource' ?
        ([songInfoObj, 'low'] as Object[]) : [songInfoObj];
      const result = await JsPluginEngine.callPlugin(config, methodNames[i], lyricArgs, LYRIC_TIMEOUT);
      if (result.ok) {
        const data: Object | undefined = result.data;
        if (data === undefined || data === null) {
          continue;
        }
        if (typeof data === 'string') {
          const s = data as string;
          if (s.includes('[')) {
            if (i > 0) {
              console.info(`[JsPluginEngine] 歌词方法名兼容: ${methodNames[i]} (非首选)`);
            }
            return s;
          }
          continue;
        }
        const rec = data as Record<string, Object>;
        const lrc: string = JsPluginEngine.strOf(rec['lrc']) || JsPluginEngine.strOf(rec['lyric']) ||
          JsPluginEngine.strOf(rec['rawLrc']) || JsPluginEngine.strOf(rec['data']);
        if (lrc.includes('[')) {
          if (i > 0) {
            console.info(`[JsPluginEngine] 歌词方法名兼容: ${methodNames[i]} (非首选)`);
          }
          return lrc;
        }
      }
    }
    return '';
  }

  /** 将 SongInfo 还原为插件可识别的歌曲对象 */
  private static buildSongInfoJson(song: SongInfo): string {
    if (song.rawData && song.rawData.length > 0) {
      try {
        const parsed: Record<string, Object> = JSON.parse(song.rawData) as Record<string, Object>;
        if (Object.keys(parsed).length > 0) {
          return song.rawData;
        }
      } catch (_e) {
      }
    }
    const fb: FallbackSongPayload = {
      id: song.songId,
      songId: song.songId,
      songmid: song.mid || song.hash || song.songId,
      hash: song.hash || song.mid || song.songId,
      name: song.songName,
      title: song.songName,
      singer: song.artist,
      artist: song.artist,
      album: song.album,
    };
    return JSON.stringify(fb);
  }

  /** 字符串转换辅助 */
  private static strOf(v: Object | undefined): string {
    if (v === undefined || v === null) {
      return '';
    }
    if (typeof v === 'string') {
      return v as string;
    }
    if (typeof v === 'number' || typeof v === 'boolean') {
      return String(v);
    }
    return '';
  }

  /** 搜索项 → SongInfo */
  private static toSongInfo(item: Record<string, Object>, platform: string): SongInfo | null {
    const id: string = JsPluginEngine.strOf(item['id']) || JsPluginEngine.strOf(item['songId']) ||
      JsPluginEngine.strOf(item['hash']) || JsPluginEngine.strOf(item['mid']);
    const name: string = JsPluginEngine.strOf(item['name']) || JsPluginEngine.strOf(item['title']) ||
      JsPluginEngine.strOf(item['songName']);
    if (id.length === 0 || name.length === 0) {
      return null;
    }
    let artist: string = JsPluginEngine.strOf(item['singer']) || JsPluginEngine.strOf(item['artist']) ||
      JsPluginEngine.strOf(item['singerName']);
    if (artist.length === 0 && item['singer'] instanceof Array) {
      const names: string[] = [];
      const arr = item['singer'] as Object[];
      for (let j = 0; j < arr.length; j++) {
        const s = arr[j] as Record<string, Object>;
        const n: string = JsPluginEngine.strOf(s['name']) || JsPluginEngine.strOf(s['singer']);
        if (n.length > 0) {
          names.push(n);
        }
      }
      artist = names.join('/');
    }
    let cover: string = JsPluginEngine.strOf(item['pic']) || JsPluginEngine.strOf(item['picUrl']) ||
      JsPluginEngine.strOf(item['albumPic']) || JsPluginEngine.strOf(item['coverUrl']) || JsPluginEngine.strOf(item['artwork']);
    if (cover.startsWith('//')) {
      cover = 'https:' + cover;
    }
    let durNum: number = 0;
    const durVal: Object | undefined = item['duration'] ?? item['interval'] ?? item['durationTime'];
    if (typeof durVal === 'number') {
      durNum = durVal as number;
    } else {
      durNum = Number.parseInt(JsPluginEngine.strOf(durVal)) || 0;
    }
    if (durNum > 3600) {
      durNum = Math.floor(durNum / 1000);
    }
    const durText: string = `${Math.floor(durNum / 60)}:${(durNum % 60).toString().padStart(2, '0')}`;
    const hash: string = JsPluginEngine.strOf(item['hash']);
    const mid: string = JsPluginEngine.strOf(item['mid']);
    const itemSource: string = JsPluginEngine.strOf(item['source']);
    const song: SongInfo = {
      songId: id,
      songName: name,
      artist: artist,
      album: JsPluginEngine.strOf(item['album']) || JsPluginEngine.strOf(item['albumName']),
      coverUrl: cover,
      source: itemSource.length > 0 ? itemSource : 'custom_' + platform,
      playUrl: JsPluginEngine.strOf(item['url']),
      quality: '128kbps/' + durText,
      hash: hash.length > 0 ? hash : undefined,
      mid: mid.length > 0 ? mid : undefined,
      rawData: JSON.stringify(item),
    };
    return song;
  }

  /** 释放引擎资源 */
  static release(): void {
    QuickJSEngine.release();
    JsPluginEngine.ready = false;
    JsPluginEngine.initialized = false;
    console.info('[JsPluginEngine] released');
  }
}
