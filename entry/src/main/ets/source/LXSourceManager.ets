/**
 * 音源脚本文件管理器
 * 负责 JS 插件脚本的导入、存储、加载和删除
 * 适配自 123 项目 LXSourceManager
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { LXUserApiInfo, LXUserApiInfoFull } from './Interface';

const LX_API_LIST_FILE: string = 'lx_api_list.json';
const LX_API_SCRIPT_PREFIX: string = 'lx_api_script_';

interface LXApiListStore {
  apis: LXUserApiInfo[];
}

interface ApiScriptInfo {
  name: string;
  description: string;
  author: string;
  homepage: string;
  version: string;
}

class LXSourceManager {
  private apiList: LXUserApiInfo[] | null = null;
  private filesDir: string = '';

  setFilesDir(dir: string): void {
    this.filesDir = dir;
  }

  private getListFilePath(): string {
    return this.filesDir + '/' + LX_API_LIST_FILE;
  }

  private getScriptFilePath(apiId: string): string {
    return this.filesDir + '/' + LX_API_SCRIPT_PREFIX + apiId + '.js';
  }

  getApiList(): LXUserApiInfo[] {
    if (this.apiList !== null) {
      return this.apiList;
    }
    this.apiList = this.loadApiListFromFile();
    return this.apiList;
  }

  private loadApiListFromFile(): LXUserApiInfo[] {
    let path: string = this.getListFilePath();
    try {
      if (!fs.accessSync(path)) {
        return [];
      }
      let stat: fs.Stat = fs.statSync(path);
      let buf: ArrayBuffer = new ArrayBuffer(stat.size);
      let file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
      fs.readSync(file.fd, buf, { offset: 0, length: stat.size });
      fs.closeSync(file);
      let decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      let text: string = decoder.decodeToString(new Uint8Array(buf));
      let store: LXApiListStore = JSON.parse(text) as LXApiListStore;
      if (store.apis !== undefined) {
        return store.apis;
      }
      return [];
    } catch (_err) {
      return [];
    }
  }

  private saveApiListToFile(): void {
    let path: string = this.getListFilePath();
    let list: LXUserApiInfo[] = this.apiList !== null ? this.apiList : [];
    let store: LXApiListStore = { apis: list };
    let text: string = JSON.stringify(store) || '';
    let encoder: util.TextEncoder = new util.TextEncoder();
    let data: Uint8Array = encoder.encodeInto(text);
    try {
      let file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, data.buffer as ArrayBuffer);
      fs.closeSync(file);
    } catch (_err) {
      console.error('LXSourceManager saveApiListToFile error');
    }
  }

  async getScript(apiId: string): Promise<string> {
    let scriptPath: string = this.getScriptFilePath(apiId);
    try {
      if (!fs.accessSync(scriptPath)) {
        return '';
      }
      let stat: fs.Stat = fs.statSync(scriptPath);
      let buf: ArrayBuffer = new ArrayBuffer(stat.size);
      let file: fs.File = fs.openSync(scriptPath, fs.OpenMode.READ_ONLY);
      fs.readSync(file.fd, buf, { offset: 0, length: stat.size });
      fs.closeSync(file);
      let decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      let raw: string = decoder.decodeToString(new Uint8Array(buf));
      if (raw.startsWith('gz_')) {
        return await this.inflateBase64(raw.substring(3));
      }
      return raw;
    } catch (_err) {
      return '';
    }
  }

  private async inflateBuffer(compressedBuffer: ArrayBuffer): Promise<string> {
    let zipObj: zlib.Zip = zlib.createZipSync();
    try {
      const outBufSize: number = Math.max(compressedBuffer.byteLength * 8 + 1024, 64 * 1024);
      let outBuf: ArrayBuffer = new ArrayBuffer(outBufSize);
      let result: zlib.ZipOutputInfo = await zipObj.uncompress(outBuf, compressedBuffer, compressedBuffer.byteLength);
      if (result !== undefined && result.destLen > 0) {
        let data: Uint8Array = new Uint8Array(outBuf, 0, result.destLen);
        let decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
        return decoder.decodeToString(data);
      }
      return '';
    } catch (_err) {
      return '';
    }
  }

  private async inflateBase64(base64: string): Promise<string> {
    try {
      let compressed: Uint8Array = this.base64ToUint8Array(base64);
      if (compressed.length === 0) {
        return '';
      }
      return await this.inflateBuffer(compressed.buffer as ArrayBuffer);
    } catch (_err) {
      return '';
    }
  }

  private base64ToUint8Array(base64: string): Uint8Array {
    try {
      let clean: string = base64.replace(/-/g, '+').replace(/_/g, '/');
      let remainder: number = clean.length % 4;
      if (remainder > 0) {
        for (let i: number = 0; i < 4 - remainder; i++) {
          clean += '=';
        }
      }
      let bytes: number[] = [];
      let chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      let i: number = 0;
      while (i < clean.length) {
        let enc1: number = chars.indexOf(clean.charAt(i));
        i++;
        let enc2: number = chars.indexOf(clean.charAt(i));
        i++;
        if (enc1 === -1 || enc2 === -1) {
          break;
        }
        bytes.push((enc1 << 2) | (enc2 >> 4));
        let enc3: number = chars.indexOf(clean.charAt(i));
        i++;
        if (enc3 !== -1) {
          bytes.push(((enc2 & 15) << 4) | (enc3 >> 2));
        } else {
          break;
        }
        let enc4: number = chars.indexOf(clean.charAt(i));
        i++;
        if (enc4 !== -1) {
          bytes.push(((enc3 & 3) << 6) | enc4);
        }
      }
      return new Uint8Array(bytes);
    } catch (_err) {
      return new Uint8Array(0);
    }
  }

  saveScript(apiId: string, script: string): void {
    let scriptPath: string = this.getScriptFilePath(apiId);
    let encoder: util.TextEncoder = new util.TextEncoder();
    let data: Uint8Array = encoder.encodeInto(script);
    try {
      let file: fs.File = fs.openSync(scriptPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, data.buffer as ArrayBuffer);
      fs.closeSync(file);
    } catch (_err) {
      console.error('LXSourceManager saveScript error');
    }
  }

  importApi(scriptRaw: string): LXUserApiInfo {
    let parsed: ApiScriptInfo = this.parseScriptInfo(scriptRaw);
    let apiId: string = 'user_api_' + Math.random().toString().substring(2, 5) + '_' + Date.now().toString();
    let apiInfo: LXUserApiInfo = {
      id: apiId,
      name: parsed.name,
      description: parsed.description,
      allowShowUpdateAlert: true,
      author: parsed.author,
      homepage: parsed.homepage,
      version: parsed.version,
      sources: {}
    };
    this.saveScript(apiId, scriptRaw);
    let list: LXUserApiInfo[] = this.getApiList();
    list = list.filter((item: LXUserApiInfo) => item.name !== apiInfo.name);
    list.push(apiInfo);
    this.apiList = list;
    this.saveApiListToFile();
    return apiInfo;
  }

  private parseScriptInfo(script: string): ApiScriptInfo {
    let result: RegExpExecArray | null = /\/\*[\S\s]+?\*\//.exec(script);
    if (result === null) {
      throw new Error('Invalid source file: no header comment found');
    }
    let header: string = result[0];
    let infoResult: ApiScriptInfo = this.matchInfo(header);
    if (infoResult.name.length === 0) {
      infoResult.name = 'user_api_' + new Date().toLocaleString();
    }
    return infoResult;
  }

  private matchInfo(scriptInfo: string): ApiScriptInfo {
    let infoArr: string[] = scriptInfo.split(/\r?\n/);
    let rxp: RegExp = /^\s?\*\s?@(\w+)\s(.+)$/;
    let infos: ApiScriptInfo = { name: '', description: '', author: '', homepage: '', version: '' };
    for (let i: number = 0; i < infoArr.length; i++) {
      let result: RegExpExecArray | null = rxp.exec(infoArr[i]);
      if (result === null) {
        continue;
      }
      let key: string = result[1];
      let value: string = result[2].trim();
      switch (key) {
        case 'name':
          infos.name = value.substring(0, Math.min(value.length, 24));
          break;
        case 'description':
          infos.description = value.substring(0, Math.min(value.length, 36));
          break;
        case 'author':
          infos.author = value.substring(0, Math.min(value.length, 56));
          break;
        case 'homepage':
          infos.homepage = value.substring(0, Math.min(value.length, 1024));
          break;
        case 'version':
          infos.version = value.substring(0, Math.min(value.length, 36));
          break;
      }
    }
    return infos;
  }

  removeApi(apiId: string): void {
    let list: LXUserApiInfo[] = this.getApiList();
    let newList: LXUserApiInfo[] = [];
    for (let i: number = 0; i < list.length; i++) {
      if (list[i].id !== apiId) {
        newList.push(list[i]);
      }
    }
    this.apiList = newList;
    this.saveApiListToFile();
    let scriptPath: string = this.getScriptFilePath(apiId);
    try {
      if (fs.accessSync(scriptPath)) {
        fs.unlinkSync(scriptPath);
      }
    } catch (_err) {
      // ignore
    }
  }

  async getFullApiInfo(apiId: string): Promise<LXUserApiInfoFull | null> {
    let list: LXUserApiInfo[] = this.getApiList();
    let apiInfo: LXUserApiInfo | undefined;
    for (let i: number = 0; i < list.length; i++) {
      if (list[i].id === apiId) {
        apiInfo = list[i];
        break;
      }
    }
    // 兼容：按名称匹配（音源管理传入的是插件名）
    if (apiInfo === undefined) {
      for (let i: number = list.length - 1; i >= 0; i--) {
        if (list[i].name === apiId) {
          apiInfo = list[i];
          break;
        }
      }
    }
    if (apiInfo === undefined) {
      return null;
    }
    let script: string = await this.getScript(apiId);
    if (script.length === 0) {
      // 按名称匹配到但 id 不同，改用真实 id 读脚本
      script = await this.getScript(apiInfo.id);
    }
    let fullInfo: LXUserApiInfoFull = {
      id: apiInfo.id,
      name: apiInfo.name,
      description: apiInfo.description,
      script: script,
      allowShowUpdateAlert: apiInfo.allowShowUpdateAlert,
      author: apiInfo.author,
      homepage: apiInfo.homepage,
      version: apiInfo.version,
      sources: apiInfo.sources
    };
    return fullInfo;
  }
}

export let lxSourceManager: LXSourceManager = new LXSourceManager();