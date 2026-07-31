import type { SongInfo } from '../model/MusicModel'
import notificationManager from '@ohos.notificationManager'
import { WantAgent } from '@ohos.app.ability.wantAgent'
import wantAgent from '@ohos.app.ability.wantAgent'

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
      const agentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: 'com.sumyu.music',
            abilityName: 'EntryAbility'
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
        wantAgent: this.wantAgentObj ?? undefined,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
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