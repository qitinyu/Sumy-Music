// WebDavSync.ets - WebDAV 数据同步
// 复用已有 WebDAV 配置，上传/下载全量备份 JSON
import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { DatabaseHelper } from '../database/DatabaseHelper'

const BACKUP_FILENAME = 'sumy_backup.json'
const UA = 'Sumy/1.0'

export interface SyncResult {
  success: boolean
  message: string
  syncTime?: number
}

interface DavConfig {
  url: string
  user: string
  pass: string
  path: string
  auth: string
}

interface CheckResult {
  exists: boolean
  message: string
}

export class WebDavSync {
  private static db: DatabaseHelper = DatabaseHelper.getInstance()

  // 获取 WebDAV 配置
  private static async getConfig(): Promise<DavConfig | null> {
    const url = await WebDavSync.db.getSetting('webdav_url')
    const user = await WebDavSync.db.getSetting('webdav_user')
    const pass = await WebDavSync.db.getSetting('webdav_pass')
    const path = await WebDavSync.db.getSetting('webdav_path')
    if (!url || url.length === 0 || !user || user.length === 0) return null
    const auth = WebDavSync.base64Encode(`${user}:${pass}`)
    return { url, user, pass, path, auth }
  }

  // 构建备份文件的完整 URL
  private static buildBackupUrl(url: string, path: string): string {
    let baseUrl = url.endsWith('/') ? url : url + '/'
    if (path.length > 0) {
      let cleanPath = path.startsWith('/') ? path.substring(1) : path
      if (!cleanPath.endsWith('/')) cleanPath = cleanPath + '/'
      baseUrl += encodeURI(cleanPath)
    }
    return baseUrl + BACKUP_FILENAME
  }

  // 上传备份到 WebDAV
  static async uploadBackup(): Promise<SyncResult> {
    try {
      const config = await WebDavSync.getConfig()
      if (!config) {
        return { success: false, message: 'WebDAV 未配置，请先在设置中配置' }
      }

      const backupUrl = WebDavSync.buildBackupUrl(config.url, config.path)
      console.info('[WebDavSync] Upload URL:', backupUrl)
      const jsonStr = await WebDavSync.db.exportAll()
      if (jsonStr.length <= 2) {
        return { success: false, message: '导出数据为空' }
      }

      const httpRequest = http.createHttp()
      const response = await httpRequest.request(backupUrl, {
        method: http.RequestMethod.PUT,
        header: {
          'Authorization': `Basic ${config.auth}`,
          'Content-Type': 'application/json; charset=utf-8',
          'User-Agent': UA,
        },
        extraData: jsonStr,
        readTimeout: 30000,
        connectTimeout: 10000,
      } as http.HttpRequestOptions)
      httpRequest.destroy()

      const code = response.responseCode
      console.info('[WebDavSync] Upload response code:', code)
      if (code === 200 || code === 201 || code === 204) {
        const syncTime = Date.now()
        await WebDavSync.db.setSetting('lastSyncTime', String(syncTime))
        console.info('[WebDavSync] Upload success')
        return { success: true, message: '备份上传成功', syncTime }
      } else if (code === 401 || code === 403) {
        return { success: false, message: `认证失败（${code}），请检查用户名和密码` }
      } else if (code === 405) {
        return { success: false, message: 'WebDAV服务器不支持PUT上传（响应码405）' }
      } else if (code === 409) {
        return { success: false, message: '目标目录不存在（响应码409），请检查WebDAV路径' }
      } else {
        return { success: false, message: `上传失败，响应码: ${code}` }
      }
    } catch (e) {
      const err = e as Error
      const msg = err.message || JSON.stringify(e)
      console.error('[WebDavSync] uploadBackup failed:', msg)
      return { success: false, message: '上传失败: ' + msg }
    }
  }

  // 从 WebDAV 下载备份并导入
  static async downloadBackup(): Promise<SyncResult> {
    try {
      const config = await WebDavSync.getConfig()
      if (!config) {
        return { success: false, message: 'WebDAV 未配置，请先在设置中配置' }
      }

      const backupUrl = WebDavSync.buildBackupUrl(config.url, config.path)
      const httpRequest = http.createHttp()
      const response = await httpRequest.request(backupUrl, {
        method: http.RequestMethod.GET,
        header: {
          'Authorization': `Basic ${config.auth}`,
          'User-Agent': UA,
        },
        readTimeout: 30000,
        connectTimeout: 10000,
      } as http.HttpRequestOptions)
      httpRequest.destroy()

      const code = response.responseCode
      if (code !== 200) {
        if (code === 404) {
          return { success: false, message: '云端无备份文件，请先上传备份' }
        } else if (code === 401 || code === 403) {
          return { success: false, message: `认证失败（${code}），请检查用户名和密码` }
        }
        return { success: false, message: `下载失败，响应码: ${code}` }
      }

      const result = response.result
      let jsonStr = ''
      if (typeof result === 'string') {
        jsonStr = result
      } else {
        const bytes = result as Uint8Array
        const decoder = util.TextDecoder.create('utf-8')
        jsonStr = decoder.decodeToString(bytes)
      }

      if (jsonStr.length <= 2) {
        return { success: false, message: '备份文件内容为空' }
      }

      const ok = await WebDavSync.db.importAll(jsonStr)
      if (ok) {
        const syncTime = Date.now()
        await WebDavSync.db.setSetting('lastSyncTime', String(syncTime))
        console.info('[WebDavSync] Download & import success')
        return { success: true, message: '备份恢复成功', syncTime }
      } else {
        return { success: false, message: '导入数据失败，备份文件格式可能不兼容' }
      }
    } catch (e) {
      console.error('[WebDavSync] downloadBackup failed:', e)
      return { success: false, message: '下载失败: ' + String(e) }
    }
  }

  // 检查云端是否有备份文件
  static async checkRemoteBackup(): Promise<CheckResult> {
    try {
      const config = await WebDavSync.getConfig()
      if (!config) {
        return { exists: false, message: 'WebDAV 未配置' }
      }

      const backupUrl = WebDavSync.buildBackupUrl(config.url, config.path)
      const httpRequest = http.createHttp()
      const response = await httpRequest.request(backupUrl, {
        method: http.RequestMethod.HEAD,
        header: {
          'Authorization': `Basic ${config.auth}`,
          'User-Agent': UA,
        },
        readTimeout: 10000,
        connectTimeout: 10000,
      } as http.HttpRequestOptions)
      httpRequest.destroy()

      const code = response.responseCode
      if (code === 200) {
        return { exists: true, message: '云端有备份文件' }
      } else if (code === 404) {
        return { exists: false, message: '云端无备份文件' }
      } else {
        return { exists: false, message: `检查失败，响应码: ${code}` }
      }
    } catch (e) {
      return { exists: false, message: '检查失败: ' + String(e) }
    }
  }

  // 获取上次同步时间
  static async getLastSyncTime(): Promise<number> {
    const val = await WebDavSync.db.getSetting('lastSyncTime')
    return val ? Number(val) : 0
  }

  private static base64Encode(str: string): string {
    const helper = new util.Base64Helper()
    const uint8Array = new Uint8Array(str.split('').map(c => c.charCodeAt(0)))
    return helper.encodeToStringSync(uint8Array)
  }
}
