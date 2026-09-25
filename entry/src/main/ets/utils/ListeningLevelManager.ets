// ListeningLevelManager.ets - 听歌等级与个性签名管理
// 本地持久化 + WebDAV 同步支持
import { DatabaseHelper } from '../database/DatabaseHelper'
import { WebDAVProfileSync, ProfileData } from './WebDAVProfileSync'
import { MAX_LEVEL, getNeedForLevel } from './LevelConfig'

const KEY_TOTAL_SECONDS: string = 'listening_total_seconds'
const KEY_SIGNATURE: string = 'user_signature'
const KEY_SIGNATURE_UPDATED_AT: string = 'user_signature_updated_at'
const SESSION_SAVE_INTERVAL_MS: number = 30000

export interface LevelInfo {
  level: number
  current: number
  need: number
  totalSeconds: number
  percent: number
}

export class ListeningLevelManager {
  private static instance: ListeningLevelManager | null = null
  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private totalSeconds: number = 0
  private signature: string = ''
  private signatureUpdatedAt: number = 0
  private sessionStart: number = 0
  private syncTimer: number = -1
  private sessionSaveTimer: number = -1
  private initialized: boolean = false

  static getInstance(): ListeningLevelManager {
    if (!ListeningLevelManager.instance) {
      ListeningLevelManager.instance = new ListeningLevelManager()
    }
    return ListeningLevelManager.instance
  }

  async init(): Promise<void> {
    if (this.initialized) {
      return
    }
    const secondsRaw = await this.db.getSetting(KEY_TOTAL_SECONDS)
    this.totalSeconds = secondsRaw ? Number(secondsRaw) : 0
    if (isNaN(this.totalSeconds) || this.totalSeconds < 0) {
      this.totalSeconds = 0
    }
    this.signature = await this.db.getSetting(KEY_SIGNATURE)
    const updatedAtRaw = await this.db.getSetting(KEY_SIGNATURE_UPDATED_AT)
    this.signatureUpdatedAt = updatedAtRaw ? Number(updatedAtRaw) : 0
    if (isNaN(this.signatureUpdatedAt) || this.signatureUpdatedAt < 0) {
      this.signatureUpdatedAt = 0
    }
    this.initialized = true
    this.notifyUpdate()
    console.info('[ListeningLevelManager] init, totalSeconds:', this.totalSeconds)
  }

  // 重置内存状态（退出登录时调用，配合 DB 数据已清除）
  reset(): void {
    this.stopSessionSaveTimer()
    if (this.syncTimer >= 0) {
      clearTimeout(this.syncTimer)
      this.syncTimer = -1
    }
    this.totalSeconds = 0
    this.signature = ''
    this.signatureUpdatedAt = 0
    this.sessionStart = 0
    this.initialized = true
    this.notifyUpdate()
    console.info('[ListeningLevelManager] reset - in-memory state cleared')
  }

  private async ensureInit(): Promise<void> {
    if (!this.initialized) {
      await this.init()
    }
  }

  getTotalSeconds(): number {
    return this.totalSeconds
  }

  getSignature(): string {
    return this.signature
  }

  async setSignature(value: string): Promise<void> {
    await this.ensureInit()
    this.signature = value
    this.signatureUpdatedAt = Date.now()
    await this.db.setSetting(KEY_SIGNATURE, value)
    await this.db.setSetting(KEY_SIGNATURE_UPDATED_AT, String(this.signatureUpdatedAt))
    this.notifyUpdate()
    this.scheduleSync()
  }

  async startSession(): Promise<void> {
    await this.ensureInit()
    this.sessionStart = Date.now()
    this.startSessionSaveTimer()
  }

  async endSession(): Promise<void> {
    await this.ensureInit()
    this.stopSessionSaveTimer()
    if (this.sessionStart <= 0) {
      return
    }
    const elapsed = Math.floor((Date.now() - this.sessionStart) / 1000)
    this.sessionStart = 0
    if (elapsed > 0) {
      this.addSeconds(elapsed)
    }
  }

  private startSessionSaveTimer(): void {
    this.stopSessionSaveTimer()
    this.sessionSaveTimer = setInterval(() => {
      if (this.sessionStart <= 0) {
        this.stopSessionSaveTimer()
        return
      }
      const elapsed = Math.floor((Date.now() - this.sessionStart) / 1000)
      if (elapsed > 0) {
        this.addSeconds(elapsed)
        this.sessionStart = Date.now()
      }
    }, SESSION_SAVE_INTERVAL_MS)
  }

  private stopSessionSaveTimer(): void {
    if (this.sessionSaveTimer >= 0) {
      clearInterval(this.sessionSaveTimer)
      this.sessionSaveTimer = -1
    }
  }

  addSeconds(seconds: number): void {
    if (seconds <= 0) {
      return
    }
    this.totalSeconds += seconds
    this.db.setSetting(KEY_TOTAL_SECONDS, String(this.totalSeconds))
      .then(() => {
        this.notifyUpdate()
        this.scheduleSync()
      })
      .catch((e: Error) => {
        console.error('[ListeningLevelManager] save seconds failed:', e)
      })
  }

  // V2.1.7：等级改为 LV1-8 八区段阈值表（LevelConfig），按累计分钟查表定位
  getLevelInfo(): LevelInfo {
    const totalMinutes: number = Math.floor(this.totalSeconds / 60)
    let currentLevel: number = MAX_LEVEL
    let accumulated: number = 0

    for (let i: number = 1; i < MAX_LEVEL; i++) {
      const levelNeed = getNeedForLevel(i)
      if (totalMinutes < accumulated + levelNeed) {
        currentLevel = i
        break
      }
      accumulated += levelNeed
    }

    const need: number = getNeedForLevel(currentLevel)
    const current: number = Math.min(totalMinutes - accumulated, need)
    const percent = need > 0 ? Math.min(100, Math.floor((current / need) * 100)) : 100

    const result: LevelInfo = {
      level: currentLevel,
      current: current,
      need: need,
      totalSeconds: this.totalSeconds,
      percent: percent
    }
    return result
  }

  async mergeFromRemote(remoteSeconds: number, remoteSignature: string, remoteSignatureUpdatedAt: number): Promise<boolean> {
    await this.ensureInit()
    let changed = false

    if (remoteSeconds > this.totalSeconds) {
      this.totalSeconds = remoteSeconds
      await this.db.setSetting(KEY_TOTAL_SECONDS, String(this.totalSeconds))
      changed = true
    }

    if (remoteSignatureUpdatedAt > this.signatureUpdatedAt) {
      this.signature = remoteSignature
      this.signatureUpdatedAt = remoteSignatureUpdatedAt
      await this.db.setSetting(KEY_SIGNATURE, remoteSignature)
      await this.db.setSetting(KEY_SIGNATURE_UPDATED_AT, String(remoteSignatureUpdatedAt))
      changed = true
    }

    if (changed) {
      this.notifyUpdate()
    }
    return changed
  }

  buildProfileData(): ProfileData {
    const result: ProfileData = {
      listening_total_seconds: this.totalSeconds,
      user_signature: this.signature,
      signature_updated_at: this.signatureUpdatedAt,
      last_sync_time: Date.now()
    }
    return result
  }

  private notifyUpdate(): void {
    AppStorage.setOrCreate('listening_total_seconds', this.totalSeconds)
    AppStorage.setOrCreate('user_signature', this.signature)
  }

  private scheduleSync(): void {
    if (this.syncTimer >= 0) {
      clearTimeout(this.syncTimer)
    }
    this.syncTimer = setTimeout(() => {
      this.syncTimer = -1
      WebDAVProfileSync.uploadProfile()
        .then((result) => {
          if (result.success) {
            console.info('[ListeningLevelManager] webdav sync success')
          } else {
            console.warn('[ListeningLevelManager] webdav sync:', result.message)
          }
        })
        .catch((e: Error) => {
          console.error('[ListeningLevelManager] webdav sync failed:', e)
        })
    }, 5000)
  }
}
