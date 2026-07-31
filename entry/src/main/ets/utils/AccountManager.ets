// AccountManager.ets - 华为账号登录管理
// 使用 authentication 授权获取头像昵称，纯客户端无需服务端
import { authentication } from '@kit.AccountKit'
import { util } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { DatabaseHelper } from '../database/DatabaseHelper'

export interface UserInfo {
  displayName: string
  avatarUri: string
  unionId: string
  loginTime: number
}

export interface LoginResult {
  success: boolean
  userInfo?: UserInfo
  error?: string
}

const ERROR_CODE_LOGIN_OUT = 1001502002
const ERROR_CODE_NETWORK_ERROR = 1001502005
const ERROR_CODE_USER_CANCEL = 1001502010
const ERROR_CODE_SYSTEM_SERVICE = 1001502001
const ERROR_CODE_REQUEST_REFUSE = 1001502014

export class AccountManager {
  private static db: DatabaseHelper = DatabaseHelper.getInstance()

  // 登录并获取头像昵称（纯客户端，无需服务端）
  // 需要传入 UIContext 的 HostContext
  static async login(context: common.Context): Promise<LoginResult> {
    try {
      const provider = new authentication.HuaweiIDProvider()
      const authRequest = provider.createAuthorizationWithHuaweiIDRequest()

      // 获取头像昵称需要 profile scope
      authRequest.scopes = ['profile']
      // 用户未登录或未授权时拉起登录/授权页面
      authRequest.forceAuthorization = true
      // 防跨站攻击
      authRequest.state = util.generateRandomUUID()

      const controller = new authentication.AuthenticationController(context)
      const data = await controller.executeRequest(authRequest) as authentication.AuthorizationWithHuaweiIDResponse

      // 校验 state 一致性
      if (authRequest.state && data.state && authRequest.state !== data.state) {
        return { success: false, error: '安全校验失败，请重试' }
      }

      const credential = data.data
      if (!credential) {
        return { success: false, error: '未获取到用户信息' }
      }

      const avatarUri = credential.avatarUri || ''
      const nickName = credential.nickName || '华为用户'
      const authorizationCode = credential.authorizationCode || ''

      const userInfo: UserInfo = {
        displayName: nickName,
        avatarUri: avatarUri,
        unionId: authorizationCode, // 纯客户端无法获取 unionId，暂存 authorizationCode 作为标识
        loginTime: Date.now(),
      }

      await AccountManager.saveUserInfo(userInfo)
      console.info('[Account] Login success:', userInfo.displayName)
      return { success: true, userInfo }
    } catch (e) {
      const err = e as BusinessError
      console.error(`[Account] Login failed: code=${err.code}, msg=${err.message}`)
      return { success: false, error: AccountManager.parseError(err) }
    }
  }

  private static parseError(err: BusinessError): string {
    if (err.code === ERROR_CODE_LOGIN_OUT) {
      return '华为账号未登录，请先在系统设置中登录华为账号'
    } else if (err.code === ERROR_CODE_NETWORK_ERROR) {
      return '网络错误，请检查网络状态'
    } else if (err.code === ERROR_CODE_USER_CANCEL) {
      return '用户取消了授权'
    } else if (err.code === ERROR_CODE_SYSTEM_SERVICE) {
      return '系统服务异常，请稍后重试'
    } else if (err.code === ERROR_CODE_REQUEST_REFUSE) {
      return '请求过于频繁，请稍后重试'
    } else if (err.code === 1001500001) {
      return '应用指纹证书验证失败，请在AGC配置签名指纹'
    } else if (err.code === 1001502003) {
      return 'Client ID无效，请检查module.json5配置'
    }
    return `登录失败: ${err.code} ${err.message}`
  }

  // 保存用户信息到数据库
  private static async saveUserInfo(info: UserInfo): Promise<void> {
    await AccountManager.db.setSetting('user_displayName', info.displayName)
    await AccountManager.db.setSetting('user_avatarUri', info.avatarUri)
    await AccountManager.db.setSetting('user_unionId', info.unionId)
    await AccountManager.db.setSetting('user_loginTime', String(info.loginTime))
  }

  // 从数据库加载已保存的用户信息
  static async loadSavedUserInfo(): Promise<UserInfo | null> {
    const displayName = await AccountManager.db.getSetting('user_displayName')
    if (!displayName) return null
    const avatarUri = await AccountManager.db.getSetting('user_avatarUri')
    const unionId = await AccountManager.db.getSetting('user_unionId')
    const loginTimeStr = await AccountManager.db.getSetting('user_loginTime')
    return {
      displayName,
      avatarUri,
      unionId,
      loginTime: loginTimeStr ? Number(loginTimeStr) : 0,
    }
  }

  // 登出
  static async logout(): Promise<void> {
    await AccountManager.db.setSetting('user_displayName', '')
    await AccountManager.db.setSetting('user_avatarUri', '')
    await AccountManager.db.setSetting('user_unionId', '')
    await AccountManager.db.setSetting('user_loginTime', '')
    console.info('[Account] Logout done')
  }

  // 是否已登录
  static async isLoggedIn(): Promise<boolean> {
    const name = await AccountManager.db.getSetting('user_displayName')
    return !!(name && name.length > 0)
  }
}
