/**
 * CoverFetcher - WebDAV 封面下载缓存器
 * WebDAV 资源 URL 内嵌 user:pass@ 账号密码，系统 Image 组件无法直接加载，
 * 此工具将这类封面经 http(Basic Auth) 下载到本地缓存目录后返回 file:// 路径。
 * 普通 http(s) 封面（无账号密码）原样返回，不拦截。
 */
import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'

export class CoverFetcher {
  private static instance: CoverFetcher | null = null
  private context: common.UIAbilityContext | null = null
  private memCache: Map<string, string> = new Map()
  private failedCache: Map<string, number> = new Map()

  static getInstance(): CoverFetcher {
    if (!CoverFetcher.instance) {
      CoverFetcher.instance = new CoverFetcher()
    }
    return CoverFetcher.instance
  }

  /** 在应用启动时注入 UIAbilityContext（EntryAbility.onCreate 调用） */
  init(context: common.UIAbilityContext): void {
    CoverFetcher.getInstance().context = context
  }

  /** 解析封面 URL：带账号密码的下载为本地文件，其余原样返回 */
  static async resolve(url: string): Promise<string> {
    return await CoverFetcher.getInstance().resolveInternal(url)
  }

  /** 将内存中的封面字节写入缓存目录（云端歌曲内嵌封面解析后使用），返回 file:// 路径 */
  static async saveBytes(key: string, bytes: Uint8Array, ext: string): Promise<string> {
    const ctx: common.UIAbilityContext | null = CoverFetcher.getInstance().context
    if (!ctx || !bytes || bytes.length === 0) {
      return ''
    }
    try {
      // V2.1.3：存 filesDir 防止系统清理 cacheDir 导致封面消失
      const coverDir: string = ctx.filesDir + '/covers'
      try {
        await fileIo.mkdir(coverDir, true)
      } catch (_e) {
      }
      const filePath: string = coverDir + '/cover_' + key + '.' + ext
      // TRUNC 截断写入，避免覆盖旧文件时残留尾部字节导致图片损坏
      const file = await fileIo.open(filePath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      try {
        await fileIo.write(file.fd, bytes.slice().buffer as ArrayBuffer)
      } finally {
        fileIo.close(file)
      }
      return 'file://' + filePath
    } catch (_e) {
      return ''
    }
  }

  private async resolveInternal(url: string): Promise<string> {
    if (!url || url.length === 0) {
      return ''
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return url
    }
    if (!/^(https?:\/\/)([^/@]+)@/.test(url)) {
      return url
    }
    const cached: string | undefined = this.memCache.get(url)
    if (cached !== undefined && cached.length > 0) {
      return cached
    }
    // 失败冷却：10s 内不重试同一 URL（避免并发下载失败时反复请求打满连接）
    const lastFail: number | undefined = this.failedCache.get(url)
    if (lastFail !== undefined && Date.now() - lastFail < 10000) {
      return ''
    }
    const localPath: string = await this.download(url)
    if (localPath.length > 0) {
      this.memCache.set(url, localPath)
      this.failedCache.delete(url)
    } else {
      this.failedCache.set(url, Date.now())
    }
    return localPath
  }

  private async download(rawUrl: string): Promise<string> {
    const ctx: common.UIAbilityContext | null = this.context
    if (!ctx) {
      return ''
    }
    let httpRequest: http.HttpRequest | null = null
    try {
      let url: string = rawUrl
      const headerObj: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      } as Record<string, string>
      const uiMatch: RegExpMatchArray | null = url.match(/^(https?:\/\/)([^/@]+)@/)
      if (uiMatch) {
        const ui: string = uiMatch[2]
        const idx: number = ui.indexOf(':')
        let user: string = idx >= 0 ? ui.substring(0, idx) : ui
        let pass: string = idx >= 0 ? ui.substring(idx + 1) : ''
        try {
          user = decodeURIComponent(user)
        } catch (_e) {
        }
        try {
          pass = decodeURIComponent(pass)
        } catch (_e) {
        }
        const encoder: util.TextEncoder = new util.TextEncoder()
        const helper: util.Base64Helper = new util.Base64Helper()
        headerObj['Authorization'] = 'Basic ' + helper.encodeToStringSync(encoder.encodeInto(user + ':' + pass))
        url = url.replace(/^(https?:\/\/)([^/@]+)@/, '$1')
      }

      // V2.1.3：封面缓存改存 filesDir（cacheDir 会被系统清理，导致封面失效消失）
      const coverDir: string = ctx.filesDir + '/covers'
      const fileName: string = 'cover_' + this.simpleHash(rawUrl) + '.jpg'
      const filePath: string = coverDir + '/' + fileName
      try {
        if (await fileIo.access(filePath)) {
          return 'file://' + filePath
        }
      } catch (_e) {
      }

      httpRequest = http.createHttp()
      // 失败自动重试一次（网络抖动/连接抢占场景）
      let response: http.HttpResponse | null = null
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          response = await httpRequest.request(url, {
            method: http.RequestMethod.GET,
            header: headerObj,
            expectDataType: http.HttpDataType.ARRAY_BUFFER,
            readTimeout: 15000,
            connectTimeout: 15000,
          } as http.HttpRequestOptions)
          if (response.responseCode === 200) {
            break
          }
        } catch (_e) {
          response = null
        }
        if (attempt === 0) {
          await new Promise<void>((resolve: () => void) => setTimeout(resolve, 400))
        }
      }
      if (response !== null && response.responseCode === 200 && response.result instanceof ArrayBuffer) {
        try {
          await fileIo.mkdir(coverDir, true)
        } catch (_e) {
        }
        // V2.1.3：TRUNC 截断写入，避免覆盖旧文件时残留尾部字节导致图片损坏
        const file = await fileIo.open(filePath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
        try {
          await fileIo.write(file.fd, response.result as ArrayBuffer)
        } finally {
          fileIo.close(file)
        }
        console.info('[CoverFetcher] cached: ' + filePath)
        return 'file://' + filePath
      }
      return ''
    } catch (e) {
      console.error('[CoverFetcher] download failed:', e)
      return ''
    } finally {
      if (httpRequest !== null) {
        httpRequest.destroy()
      }
    }
  }

  private simpleHash(str: string): string {
    let hash: number = 0
    for (let i = 0; i < str.length; i++) {
      const char: number = str.charCodeAt(i)
      hash = ((hash << 5) - hash) + char
      hash = hash & hash
    }
    return Math.abs(hash).toString(16)
  }
}
