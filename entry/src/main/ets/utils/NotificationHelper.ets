import type { SongInfo } from '../model/MusicModel'
import notificationManager from '@ohos.notificationManager'
import { WantAgent } from '@ohos.app.ability.wantAgent'
import wantAgent from '@ohos.app.ability.wantAgent'
import { common } from '@kit.AbilityKit'

const NOTIFICATION_ID: number = 1001

export class NotificationHelper {
  private static instance: NotificationHelper | null = null
  private isPlaying: boolean = false
  private currentSong: SongInfo | null = null
  private context: Context | null = null
  private wantAgentObj: WantAgent | null = null

  static getInstance(): NotificationHelper {
    if (!NotificationHelper.instance) {
      NotificationHelper.instance = new NotificationHelper()
    }
    return NotificationHelper.instance
  }

  async init(context: Context): Promise<void> {
    this.context = context
    try {
      await notificationManager.requestEnableNotification()
      console.info('[NotificationHelper] Notification permission granted')
    } catch (e) {
      console.error('[NotificationHelper] Failed to request notification permission:', e)
    }
    await this.createWantAgent()
  }

  private async createWantAgent(): Promise<void> {
    if (!this.context) return
    try {
      // 动态获取 bundleName/abilityName，避免硬编码拼写错误导致 getWantAgent 返回 Invalid wantAgent object
      const abilityCtx = this.context as common.UIAbilityContext
      const bundleName: string = abilityCtx.abilityInfo.bundleName
      const abilityName: string = abilityCtx.abilityInfo.name
      const agentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: bundleName,
            abilityName: abilityName
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      }
      this.wantAgentObj = await wantAgent.getWantAgent(agentInfo)
      console.info('[NotificationHelper] WantAgent created')
    } catch (e) {
      console.error('[NotificationHelper] createWantAgent failed:', e)
    }
  }

  async updateMusicNotification(song: SongInfo, playing: boolean): Promise<void> {
    this.currentSong = song
    this.isPlaying = playing

    if (!this.wantAgentObj) {
      await this.createWantAgent()
    }

    try {
      const request: notificationManager.NotificationRequest = {
        id: NOTIFICATION_ID,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: song.songName || '未知歌曲',
            text: song.artist || '未知歌手'
          }
        },
        isOngoing: playing,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        // 关闭通知提示音与震动，避免听歌时"叮咚"打断体验（NotificationFlagStatus.TYPE_CLOSE = 2，API 23+ 生效）
        notificationFlags: {
          soundEnabled: 2,
          vibrationEnabled: 2
        }
      }
      // 仅当 WantAgent 创建成功时挂载，避免 undefined 导致整个通知发布失败（点击跳转会缺失，但通知仍能显示）
      if (this.wantAgentObj) {
        request.wantAgent = this.wantAgentObj
      }
      await notificationManager.publish(request)
      console.info('[NotificationHelper] Music notification published:', song.songName, playing)
    } catch (e) {
      console.error('[NotificationHelper] publish notification failed:', e)
    }
  }

  async cancelMusicNotification(): Promise<void> {
    try {
      await notificationManager.cancel(NOTIFICATION_ID)
      console.info('[NotificationHelper] Notification cancelled')
    } catch (e) {
      console.error('[NotificationHelper] cancel notification failed:', e)
    }
  }

  async updatePlaybackState(playing: boolean): Promise<void> {
    this.isPlaying = playing
    // 更新通知的 ongoing 状态
    if (this.currentSong) {
      await this.updateMusicNotification(this.currentSong, playing)
    }
    console.info('[NotificationHelper] Playback state updated:', playing)
  }

  getCurrentSong(): SongInfo | null {
    return this.currentSong
  }

  getIsPlaying(): boolean {
    return this.isPlaying
  }
}