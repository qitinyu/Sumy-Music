// MFSubscription.ets - MusicFree 订阅源管理
// 订阅源 = 聚合插件地址：.json 为插件列表（{"plugins":[{"name","url"},...]}），.js 为单个插件
// 存储：DatabaseHelper settings（mfSubscriptionList / mfSubscriptionEnabled / mfSubscriptionActiveList）
// 同步：解析订阅 → 逐个下载插件 → SourceManager.importMusicFreePlugin（沙箱挂载验证后注册）

import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { SourceManager } from './SourceManager'
import { MFEngine } from './MFEngine'
import { playLog } from './PlayLog'

const KEY_URL: string = 'mfSubscriptionUrl'
const KEY_LIST: string = 'mfSubscriptionList'
const KEY_ENABLED: string = 'mfSubscriptionEnabled'
const KEY_ACTIVE: string = 'mfSubscriptionActive'
const KEY_ACTIVE_LIST: string = 'mfSubscriptionActiveList'

/** 订阅内插件条目 */
export interface MFSubPlugin {
  name: string
  url: string
}

/** 订阅同步结果 */
export interface MFSyncResult {
  okCount: number
  failCount: number
  installedNames: string[]
}

/** 下载结果：text 为正文（失败为空串），error 为失败原因（成功为空串） */
export interface MFDownloadResult {
  text: string
  error: string
}

export class MFSubscription {
  /** 读取订阅源列表；旧版单订阅配置自动迁移为列表 */
  static async getList(): Promise<string[]> {
    const raw: string = await DatabaseHelper.getInstance().getSetting(KEY_LIST)
    if (raw.length > 0) {
      try {
        const arr: Object[] = JSON.parse(raw) as Object[]
        const out: string[] = []
        for (let i = 0; i < arr.length; i++) {
          if (typeof arr[i] === 'string' && (arr[i] as string).length > 0) {
            out.push(arr[i] as string)
          }
        }
        return out
      } catch (_e) {
      }
    }
    // 旧版单订阅迁移：迁移完成后清空旧键，避免删除全部订阅后被回迁
    const legacy: string = await DatabaseHelper.getInstance().getSetting(KEY_URL)
    if (legacy.length > 0) {
      await MFSubscription.saveList([legacy])
      await DatabaseHelper.getInstance().setSetting(KEY_URL, '')
      return [legacy]
    }
    return []
  }

  /** 保存订阅源列表（过滤空项） */
  static async saveList(urls: string[]): Promise<void> {
    const cleaned: string[] = []
    for (let i = 0; i < urls.length; i++) {
      const u: string = urls[i].trim()
      if (u.length > 0) {
        cleaned.push(u)
      }
    }
    await DatabaseHelper.getInstance().setSetting(KEY_LIST, JSON.stringify(cleaned))
  }

  /** 读取启用状态（默认启用） */
  static async getEnabled(): Promise<boolean> {
    const raw: string = await DatabaseHelper.getInstance().getSetting(KEY_ENABLED)
    return raw !== 'false'
  }

  /** 保存启用状态 */
  static async saveEnabled(enabled: boolean): Promise<void> {
    await DatabaseHelper.getInstance().setSetting(KEY_ENABLED, enabled ? 'true' : 'false')
  }

  /** 读取已启用的订阅源地址列表（支持多源同时启用，空列表=未启用任何订阅）；旧版单启用配置自动迁移为列表 */
  static async getActiveList(): Promise<string[]> {
    const raw: string = await DatabaseHelper.getInstance().getSetting(KEY_ACTIVE_LIST)
    if (raw.length > 0) {
      try {
        const arr: Object[] = JSON.parse(raw) as Object[]
        const out: string[] = []
        for (let i = 0; i < arr.length; i++) {
          if (typeof arr[i] === 'string' && (arr[i] as string).length > 0) {
            out.push(arr[i] as string)
          }
        }
        return out
      } catch (_e) {
      }
    }
    // 旧版单启用迁移：迁移完成后清空旧键，避免释放后又被回迁
    const legacy: string = await DatabaseHelper.getInstance().getSetting(KEY_ACTIVE)
    if (legacy.length > 0) {
      await MFSubscription.saveActiveList([legacy])
      await DatabaseHelper.getInstance().setSetting(KEY_ACTIVE, '')
      return [legacy]
    }
    return []
  }

  /** 保存已启用的订阅源地址列表（去重、过滤空项） */
  static async saveActiveList(urls: string[]): Promise<void> {
    const cleaned: string[] = []
    for (let i = 0; i < urls.length; i++) {
      const u: string = urls[i].trim()
      if (u.length > 0 && cleaned.indexOf(u) < 0) {
        cleaned.push(u)
      }
    }
    await DatabaseHelper.getInstance().setSetting(KEY_ACTIVE_LIST, JSON.stringify(cleaned))
  }

  /** 校验订阅源地址：http(s) 且以 .js 或 .json 结尾 */
  static isValidUrl(url: string): boolean {
    if (!(url.startsWith('https://') || url.startsWith('http://'))) {
      return false
    }
    const q: string = url.indexOf('?') >= 0 ? url.substring(0, url.indexOf('?')) : url
    return q.endsWith('.js') || q.endsWith('.json')
  }

  /**
   * 对 URL 的 path/query 做百分号编码（保留 scheme/host 与 / 分隔符），
   * 处理插件地址中的中文、空格等字符；已编码片段（含 %）保持不变。
   */
  static encodeUrl(url: string): string {
    try {
      const hashIdx: number = url.indexOf('#')
      const base: string = hashIdx >= 0 ? url.substring(0, hashIdx) : url
      let prefix: string = ''
      let rest: string = base
      const schemeIdx: number = base.indexOf('://')
      if (schemeIdx > 0) {
        prefix = base.substring(0, schemeIdx + 3)
        rest = base.substring(schemeIdx + 3)
      }
      let host: string = rest
      let tail: string = ''
      const slashIdx: number = rest.indexOf('/')
      if (slashIdx >= 0) {
        host = rest.substring(0, slashIdx)
        tail = rest.substring(slashIdx)
      }
      let path: string = tail
      let query: string = ''
      const qIdx: number = tail.indexOf('?')
      if (qIdx >= 0) {
        path = tail.substring(0, qIdx)
        query = tail.substring(qIdx + 1)
      }
      const segs: string[] = path.split('/')
      const out: string[] = []
      for (let i = 0; i < segs.length; i++) {
        out.push(MFSubscription.encodeSegment(segs[i]))
      }
      let result: string = prefix + host + out.join('/')
      if (query.length > 0) {
        const pairs: string[] = query.split('&')
        const qOut: string[] = []
        for (let i = 0; i < pairs.length; i++) {
          const eqIdx: number = pairs[i].indexOf('=')
          if (eqIdx >= 0) {
            qOut.push(`${MFSubscription.encodeSegment(pairs[i].substring(0, eqIdx))}=${MFSubscription.encodeSegment(pairs[i].substring(eqIdx + 1))}`)
          } else {
            qOut.push(MFSubscription.encodeSegment(pairs[i]))
          }
        }
        result += `?${qOut.join('&')}`
      }
      return result
    } catch (_e) {
      return url
    }
  }

  /** 编码单个 path/query 片段：跳过已编码片段，保留 jsdelivr 路径需要的 @ 与 : */
  static encodeSegment(seg: string): string {
    if (seg.length === 0 || seg.indexOf('%') >= 0) {
      return seg
    }
    return encodeURIComponent(seg)
      .replace(/%40/g, '@')
      .replace(/%3A/g, ':')
  }

  /**
   * 生成候选下载地址：原始地址 + 公共镜像。
   * cdn.jsdelivr.net 在部分网络不可达（DNS 污染），
   * 形如 https://cdn.jsdelivr.net/gh/user/repo@ver/path 的地址额外派生
   * fastly/gcore/testingcf 镜像与 raw.githubusercontent.com 直链。
   */
  static candidateUrls(url: string): string[] {
    const list: string[] = [url]
    const marker: string = '://cdn.jsdelivr.net/gh/'
    const idx: number = url.indexOf(marker)
    if (idx >= 0) {
      const tail: string = url.substring(idx + marker.length)
      const slashIdx: number = tail.indexOf('/')
      if (slashIdx > 0) {
        const repoPart: string = tail.substring(0, slashIdx)
        const filePath: string = tail.substring(slashIdx)
        const atIdx: number = repoPart.indexOf('@')
        if (atIdx > 0) {
          const userRepo: string = repoPart.substring(0, atIdx)
          const ver: string = repoPart.substring(atIdx + 1)
          list.push(`https://fastly.jsdelivr.net/gh/${repoPart}${filePath}`)
          list.push(`https://gcore.jsdelivr.net/gh/${repoPart}${filePath}`)
          list.push(`https://testingcf.jsdelivr.net/gh/${repoPart}${filePath}`)
          list.push(`https://raw.githubusercontent.com/${userRepo}/${ver}${filePath}`)
        }
      }
    }
    return list
  }

  /** 下载文本（自动百分号编码 URL），失败时 error 给出原因（HTTP 码或异常信息） */
  static async downloadTextDetailed(url: string, timeoutMs: number = 15000): Promise<MFDownloadResult> {
    const r: MFDownloadResult = { text: '', error: '' }
    const encoded: string = MFSubscription.encodeUrl(url)
    try {
      const req: http.HttpRequest = http.createHttp()
      try {
        const resp: http.HttpResponse = await req.request(encoded, {
          method: http.RequestMethod.GET,
          readTimeout: timeoutMs,
          connectTimeout: timeoutMs,
          header: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
          } as Record<string, string>,
        })
        if (resp.responseCode < 200 || resp.responseCode >= 400) {
          r.error = `HTTP ${resp.responseCode}`
          return r
        }
        const result: Object = resp.result
        if (typeof result === 'string') {
          r.text = result as string
          return r
        }
        if (result instanceof ArrayBuffer) {
          const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
          r.text = decoder.decodeToString(new Uint8Array(result as ArrayBuffer))
          return r
        }
        r.error = '响应格式异常'
        return r
      } finally {
        req.destroy()
      }
    } catch (e) {
      r.error = String(e)
      return r
    }
  }

  /**
   * 解析订阅源为插件列表：.json 为插件列表，.js 为单插件；失败返回 null
   */
  static async resolvePluginUrls(url: string): Promise<MFSubPlugin[] | null> {
    if (url.endsWith('.json')) {
      const dl: MFDownloadResult = await MFSubscription.downloadTextDetailed(url)
      if (dl.text.length === 0) {
        playLog('订阅同步', `订阅源下载失败: ${dl.error}`)
        return null
      }
      try {
        const parsed: Record<string, Object> = JSON.parse(dl.text) as Record<string, Object>
        const plugins: Object | undefined = parsed['plugins']
        if (!(plugins instanceof Array)) {
          return null
        }
        const arr: Object[] = plugins as Object[]
        const list: MFSubPlugin[] = []
        for (let i = 0; i < arr.length; i++) {
          const rec: Record<string, Object> = arr[i] as Record<string, Object>
          const u: string = rec['url'] !== undefined && rec['url'] !== null ? String(rec['url']) : ''
          if (u.length === 0) {
            continue
          }
          const n: string = rec['name'] !== undefined && rec['name'] !== null ? String(rec['name']) : ''
          list.push({ name: n, url: u })
        }
        return list.length > 0 ? list : null
      } catch (_e) {
        return null
      }
    }
    // 单插件订阅
    const fallbackName: string = MFSubscription.nameFromUrl(url)
    return [{ name: fallbackName, url: url }]
  }

  /** 从 URL 推断插件名（取最后一段文件名，去扩展名） */
  static nameFromUrl(url: string): string {
    const noQuery: string = url.indexOf('?') >= 0 ? url.substring(0, url.indexOf('?')) : url
    const seg: string = noQuery.substring(noQuery.lastIndexOf('/') + 1)
    const name: string = seg.replace(/\.(js|json)$/i, '')
    return name.length > 0 ? name : 'mf_plugin'
  }

  /**
   * 同步订阅：解析 → 逐个下载 → 沙箱挂载验证 → 注册安装。
   * onLog 为进度回调（每插件一行）；返回成功/失败计数与安装成功的插件名。
   */
  static async sync(url: string, onLog?: (line: string) => void): Promise<MFSyncResult> {
    const result: MFSyncResult = { okCount: 0, failCount: 0, installedNames: [] }
    const log = (line: string): void => {
      if (onLog !== undefined) {
        onLog(line)
      }
      playLog('订阅同步', line)
    }
    const plugins: MFSubPlugin[] | null = await MFSubscription.resolvePluginUrls(url)
    if (plugins === null) {
      log('订阅源获取失败或格式不正确: ' + url)
      result.failCount++
      return result
    }
    log(`解析到 ${plugins.length} 个插件，开始逐个安装…`)
    for (let i = 0; i < plugins.length; i++) {
      const p: MFSubPlugin = plugins[i]
      const label: string = p.name.length > 0 ? p.name : MFSubscription.nameFromUrl(p.url)
      log(`[${i + 1}/${plugins.length}] 下载 ${label}…`)
      // 原始地址失败时依次尝试镜像（CDN 不可达/URL 被墙场景）
      const candidates: string[] = MFSubscription.candidateUrls(p.url)
      let content: string = ''
      let lastErr: string = ''
      let mirrorUsed: boolean = false
      for (let c = 0; c < candidates.length; c++) {
        const dl: MFDownloadResult = await MFSubscription.downloadTextDetailed(candidates[c], 10000)
        if (dl.text.length > 0) {
          content = dl.text
          mirrorUsed = c > 0
          break
        }
        lastErr = dl.error.length > 0 ? dl.error : '未知错误'
      }
      if (content.length === 0) {
        const brief: string = lastErr.length > 60 ? `${lastErr.substring(0, 60)}…` : lastErr
        log(`[${i + 1}/${plugins.length}] ${label} 下载失败: ${brief}`)
        result.failCount++
        continue
      }
      const name: string = await SourceManager.importMusicFreePlugin(content, label)
      if (name.length > 0) {
        log(`[${i + 1}/${plugins.length}] ${name} 安装成功${mirrorUsed ? '（经镜像下载）' : ''}`)
        result.okCount++
        result.installedNames.push(name)
      } else {
        const err: string = MFEngine.lastError
        log(`[${i + 1}/${plugins.length}] ${label} 安装失败${err.length > 0 ? `: ${err}` : ''}`)
        result.failCount++
      }
    }
    return result
  }
}
