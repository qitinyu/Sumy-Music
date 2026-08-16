// WebDAVProfileSync.ets - 听歌等级/签名等用户画像数据的 WebDAV 同步
import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { DatabaseHelper } from '../database/DatabaseHelper'

const PROFILE_FILENAME: string = 'sumy_profile.json'
const UA: string = 'Sumy/1.0'

export interface ProfileData {
  listening_total_seconds: number
  user_signature: string
  signature_updated_at: number
  last_sync_time: number
}

export interface ProfileSyncResult {
  success: boolean
  message: string
  data?: ProfileData
}

interface RawProfileData {
  listening_total_seconds?: number
  user_signature?: string
  signature_updated_at?: number
  last_sync_time?: number
}

interface DavConfig {
  url: string
  user: string
  pass: string
  path: string
  auth: string
}

export class WebDAVProfileSync {
  private static db: DatabaseHelper = DatabaseHelper.getInstance()

  private static async getConfig(): Promise<DavConfig | null> {
    const url = await WebDAVProfileSync.db.getSetting('webdav_url')
    const user = await WebDAVProfileSync.db.getSetting('webdav_user')
    const pass = await WebDAVProfileSync.db.getSetting('webdav_pass')
    const path = await WebDAVProfileSync.db.getSetting('webdav_path')
    if (!url || url.length === 0 || !user || user.length === 0) {
      return null
    }
    const auth = WebDAVProfileSync.base64Encode(`${user}:${pass}`)
    const result: DavConfig = { url, user, pass, path, auth }
    return result
  }

  private static buildProfileUrl(url: string, path: string): string {
    let baseUrl = url.endsWith('/') ? url : url + '/'
    if (path.length > 0) {
      let cleanPath = path.startsWith('/') ? path.substring(1) : path
      if (!cleanPath.endsWith('/')) {
        cleanPath = cleanPath + '/'
      }
      baseUrl += encodeURI(cleanPath)
    }
    return baseUrl + PROFILE_FILENAME
  }

  static async uploadProfile(): Promise<ProfileSyncResult> {
    try {
      const config = await WebDAVProfileSync.getConfig()
      if (!config) {
        return { success: false, message: 'WebDAV 未配置' }
      }

      const totalSecondsRaw = await WebDAVProfileSync.db.getSetting('listening_total_seconds')
      const signature = await WebDAVProfileSync.db.getSetting('user_signature')
      const signatureUpdatedAtRaw = await WebDAVProfileSync.db.getSetting('user_signature_updated_at')

      const profile: ProfileData = {
        listening_total_seconds: totalSecondsRaw ? Number(totalSecondsRaw) : 0,
        user_signature: signature,
        signature_updated_at: signatureUpdatedAtRaw ? Number(signatureUpdatedAtRaw) : 0,
        last_sync_time: Date.now()
      }

      const jsonStr = JSON.stringify(profile)
      const profileUrl = WebDAVProfileSync.buildProfileUrl(config.url, config.path)
      const httpRequest = http.createHttp()
      const response = await httpRequest.request(profileUrl, {
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
      if (code === 200 || code === 201 || code === 204) {
        return { success: true, message: '同步成功' }
      } else if (code === 401 || code === 403) {
        return { success: false, message: `认证失败（${code}），请检查用户名和密码` }
      } else if (code === 405) {
        return { success: false, message: 'WebDAV 服务器不支持 PUT 上传' }
      } else if (code === 409) {
        return { success: false, message: '目标目录不存在，请检查 WebDAV 路径' }
      } else {
        return { success: false, message: `同步失败，响应码: ${code}` }
      }
    } catch (e) {
      const err = e as Error
      const msg = err.message || JSON.stringify(e)
      console.error('[WebDAVProfileSync] uploadProfile failed:', msg)
      return { success: false, message: '同步失败: ' + msg }
    }
  }

  static async downloadProfile(): Promise<ProfileSyncResult> {
    try {
      const config = await WebDAVProfileSync.getConfig()
      if (!config) {
        return { success: false, message: 'WebDAV 未配置' }
      }

      const profileUrl = WebDAVProfileSync.buildProfileUrl(config.url, config.path)
      const httpRequest = http.createHttp()
      const response = await httpRequest.request(profileUrl, {
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
      if (code === 404) {
        return { success: false, message: '云端无配置文件' }
      }
      if (code !== 200) {
        return { success: false, message: `下载失败，响应码: ${code}` }
      }

      const result = response.result
      let jsonStr = ''
      if (typeof result === 'string') {
        jsonStr = result
      } else if (result instanceof ArrayBuffer) {
        const decoder = util.TextDecoder.create('utf-8')
        jsonStr = decoder.decodeToString(new Uint8Array(result))
      } else if (result instanceof Uint8Array) {
        const decoder = util.TextDecoder.create('utf-8')
        jsonStr = decoder.decodeToString(result)
      } else {
        jsonStr = String(result)
      }

      if (jsonStr.length <= 2) {
        return { success: false, message: '配置文件内容为空' }
      }

      const parsed = JSON.parse(jsonStr) as RawProfileData
      const data: ProfileData = {
        listening_total_seconds: parsed.listening_total_seconds || 0,
        user_signature: parsed.user_signature || '',
        signature_updated_at: parsed.signature_updated_at || 0,
        last_sync_time: parsed.last_sync_time || 0
      }
      return { success: true, message: '下载成功', data: data }
    } catch (e) {
      console.error('[WebDAVProfileSync] downloadProfile failed:', e)
      return { success: false, message: '下载失败: ' + String(e) }
    }
  }

  private static base64Encode(str: string): string {
    const helper = new util.Base64Helper()
    const uint8Array = new Uint8Array(str.split('').map(c => c.charCodeAt(0)))
    return helper.encodeToStringSync(uint8Array)
  }
}
