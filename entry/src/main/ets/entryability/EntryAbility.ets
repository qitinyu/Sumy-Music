import { UIAbility, AbilityConstant, Want, abilityAccessCtrl, common, Permissions, Configuration } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'
import wantAgent, { WantAgent } from '@ohos.app.ability.wantAgent'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { AudioPlayer } from '../utils/AudioPlayer'
import { BackgroundHelper } from '../utils/BackgroundHelper'
import { ThemeManager } from '../utils/ThemeManager'
import { PlayerStore } from '../utils/PlayerStore'
import { MusicApi } from '../utils/MusicApi'
import { SongInfo } from '../model/MusicModel'
import { SelfHostedApi } from '../utils/SelfHostedApi'
import { StatusBarManager } from '../utils/StatusBarManager'
import { CoverFetcher } from '../utils/CoverFetcher'
import { CacheManager } from '../utils/CacheManager'

export default class EntryAbility extends UIAbility {
  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private backgroundHelper: BackgroundHelper = BackgroundHelper.getInstance()
  private wantAgentObj: WantAgent | null = null
  private launchTime: number = Date.now()

  async onCreate(want: Want, param: AbilityConstant.LaunchParam): Promise<void> {
    console.info('[EntryAbility] onCreate - start')
    this.launchTime = Date.now()
    try {
      await this.db.init(this.context)
      console.info('[EntryAbility] Database initialized')
    } catch (e) {
      console.error('[EntryAbility] Database init failed:', e)
    }
    // 在 UI 创建前应用保存的主题，确保 @StorageProp 首次读取即为正确主题
    try {
      const colorMode = this.context.config.colorMode ?? 1
      await ThemeManager.initTheme(colorMode)
      console.info('[EntryAbility] Theme initialized, colorMode=', colorMode)
    } catch (e) {
      console.error('[EntryAbility] Theme init failed:', e)
    }
    try {
      console.info('[EntryAbility] initializing BackgroundHelper')
      await this.backgroundHelper.init(this.context)
      console.info('[EntryAbility] BackgroundHelper initialized')
    } catch (e) {
      console.error('[EntryAbility] BackgroundHelper init failed:', e)
    }
    try {
      CoverFetcher.getInstance().init(this.context as common.UIAbilityContext)
      console.info('[EntryAbility] CoverFetcher initialized')
    } catch (e) {
      console.error('[EntryAbility] CoverFetcher init failed:', e)
    }
    try {
      CacheManager.init(this.context as common.UIAbilityContext)
      console.info('[EntryAbility] CacheManager initialized')
    } catch (e) {
      console.error('[EntryAbility] CacheManager init failed:', e)
    }
    await this.requestBackgroundRunningPermission()
    // 初始化自建API模式（确保应用启动后立即可用，无需先进入设置页）
    await this.initSelfHostedApi()
    // 恢复上次播放状态（若开启自动播放）
    await this.restoreLastPlayback()
    console.info('[EntryAbility] onCreate - done')
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    console.info('[EntryAbility] onWindowStageCreate')
    try {
      const windowClass = await windowStage.loadContent('pages/Index')
      console.info('[EntryAbility] Window content loaded')

      const mainWindow = await windowStage.getMainWindow()
      if (mainWindow) {
        await mainWindow.setWindowLayoutFullScreen(true)
        StatusBarManager.setMainWindow(mainWindow)
        const defaultThemeBg = AppStorage.get<string>('theme_bg') || '#F5F5FA'
        await StatusBarManager.applyForBackground(defaultThemeBg)
        console.info('[EntryAbility] System bar properties set via StatusBarManager')
      }
    } catch (e) {
      console.error('[EntryAbility] onWindowStageCreate failed:', e)
    }
  }

  async onWindowStageDestroy(): Promise<void> {
    console.info('[EntryAbility] onWindowStageDestroy')
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    const newColorMode = newConfig.colorMode ?? 1
    console.info('[EntryAbility] onConfigurationUpdate, colorMode=', newColorMode)
    ThemeManager.onSystemDarkModeChange(newColorMode)
  }

  async onForeground(): Promise<void> {
    console.info('[EntryAbility] onForeground')
    try {
      await AudioPlayer.getInstance().syncStateAfterForeground()
      console.info('[EntryAbility] Player state synced after foreground')
    } catch (e) {
      console.error('[EntryAbility] sync player state failed:', e)
    }
  }

  async onBackground(): Promise<void> {
    console.info('[EntryAbility] onBackground')
    // 保存当前播放状态（若开启自动记忆）
    await this.saveCurrentPlayback()
  }

  // 保存当前播放曲目和进度（应用退到后台时调用）
  private async saveCurrentPlayback(): Promise<void> {
    try {
      const remember = await this.db.getSetting('rememberProgress')
      if (remember === 'false') return // 默认开启，仅显式关闭才不保存

      const track = PlayerStore.getCurrentTrack()
      if (!track) return

      const position = AudioPlayer.getInstance().currentTime
      // 即便进度为 0，也保存曲目和队列，下次进入可恢复列表
      const queue = PlayerStore.getQueue()
      const queueIndex = PlayerStore.getQueueIndex()
      const playMode = PlayerStore.getPlayMode()

      await this.db.setSetting('lastTrack', JSON.stringify(track))
      await this.db.setSetting('lastPosition', String(position))
      await this.db.setSetting('lastQueue', JSON.stringify(queue))
      await this.db.setSetting('lastQueueIndex', String(queueIndex))
      await this.db.setSetting('lastPlayMode', String(playMode))
      console.info('[EntryAbility] playback saved:', track.songName, position, 'queueLen=', queue.length)
    } catch (e) {
      console.error('[EntryAbility] saveCurrentPlayback failed:', e)
    }
  }

  // 恢复上次播放状态（应用启动时调用）
  private async restoreLastPlayback(): Promise<void> {
    try {
      const autoPlay = await this.db.getSetting('autoPlay')
      if (autoPlay !== 'true') return // 默认关闭，仅显式开启才恢复

      const trackJson = await this.db.getSetting('lastTrack')
      if (!trackJson) return

      const track = JSON.parse(trackJson) as SongInfo
      if (!track.songId) return

      const posStr = await this.db.getSetting('lastPosition')
      const queueJson = await this.db.getSetting('lastQueue')
      const queueIndexStr = await this.db.getSetting('lastQueueIndex')
      const playModeStr = await this.db.getSetting('lastPlayMode')

      const position = posStr ? Number(posStr) : 0
      let queue: SongInfo[] = [track]
      let queueIndex = 0
      if (queueJson) {
        try {
          const parsed = JSON.parse(queueJson) as SongInfo[]
          if (parsed && parsed.length > 0) {
            queue = parsed
            queueIndex = queueIndexStr ? Number(queueIndexStr) : 0
            if (queueIndex < 0 || queueIndex >= queue.length) queueIndex = 0
          }
        } catch (_e) {}
      }
      if (playModeStr) {
        PlayerStore.setPlayMode(Number(playModeStr))
      }

      // 等待开屏动画结束（动画 3s，延迟到 3.5s 后恢复，避免播放抢占动画）
      const elapsed = Date.now() - this.launchTime
      const remain = 3500 - elapsed
      if (remain > 0) {
        await new Promise<void>((resolve) => setTimeout(resolve, remain))
      }

      // 恢复曲目到 PlayerStore（UI 立即显示）
      PlayerStore.play(track, queue, queueIndex)

      const player = AudioPlayer.getInstance()
      player.setCurrentSong(track)

      // 进度/时长/播完/出错回调由 AudioPlayer 中央化处理

      // 获取播放链接：优先用保存的，失效则重新获取
      let url = track.playUrl
      if (!url && track.source !== 'local') {
        url = await MusicApi.getPlayUrl(track.songId, track.source, track)
        if (url) {
          track.playUrl = url
          PlayerStore.refreshCurrentTrack(track)
        }
      }
      if (!url) {
        console.warn('[EntryAbility] restore: no playUrl, UI only')
        PlayerStore.pause()
        return
      }

      await player.play(url)
      if (position > 1) {
        await player.seekTo(position)
      }
      console.info('[EntryAbility] playback restored:', track.songName, position)
    } catch (e) {
      console.error('[EntryAbility] restoreLastPlayback failed:', e)
    }
  }

  async onDestroy(): Promise<void> {
    console.info('[EntryAbility] onDestroy')
    try {
      await AudioPlayer.getInstance().release()
    } catch (_e) {}
    try {
      await this.backgroundHelper.stopBackgroundRunning()
    } catch (_e) {}
    try {
      await this.backgroundHelper.release()
    } catch (_e) {}
  }

  private async requestBackgroundRunningPermission(): Promise<void> {
    try {
      const atManager = abilityAccessCtrl.createAtManager()
      const context = this.context as common.UIAbilityContext
      const permissions: Permissions[] = ['ohos.permission.KEEP_BACKGROUND_RUNNING']
      const data = await atManager.requestPermissionsFromUser(context, permissions)
      if (data.authResults[0] === 0) {
        console.info('[EntryAbility] Background running permission granted')
      } else {
        console.warn('[EntryAbility] Background running permission denied:', data.authResults[0])
      }
    } catch (e) {
      console.error('[EntryAbility] Request background running permission failed:', e)
    }
  }

  // 初始化自建API模式：从数据库读取配置并同步到 MusicApi/SelfHostedApi
  private async initSelfHostedApi(): Promise<void> {
    try {
      const locked = (await this.db.getSetting('selfHostedApiLocked')) !== 'false'
      const enabled = !locked && (await this.db.getSetting('useSelfHostedApi')) === 'true'
      const url = (await this.db.getSetting('selfHostedApiUrl')) || ''
      if (locked && (await this.db.getSetting('useSelfHostedApi')) === 'true') {
        // 锁定状态下发现有残留启用标记，清理掉防止下次误导
        await this.db.setSetting('useSelfHostedApi', 'false')
        console.info('[EntryAbility] SelfHostedApi locked, cleaned stale enabled flag')
      }
      MusicApi.setSelfHostedMode(enabled, url)
      console.info(`[EntryAbility] SelfHostedApi initialized: enabled=${enabled}, url=${url}`)
    } catch (e) {
      console.error('[EntryAbility] initSelfHostedApi failed:', e)
    }
  }

  private async createWantAgent(): Promise<void> {
    try {
      const wants: Want[] = [
        {
          bundleName: 'com.sumyu.music',
          abilityName: 'EntryAbility'
        }
      ]
      const agentInfo: wantAgent.WantAgentInfo = {
        wants: wants,
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      }
      this.wantAgentObj = await wantAgent.getWantAgent(agentInfo)
    } catch (e) {
      console.error('[EntryAbility] createWantAgent failed:', e)
    }
  }

  async startBackgroundRunning(): Promise<void> {
    try {
      if (!this.wantAgentObj) {
        await this.createWantAgent()
      }
      if (this.wantAgentObj) {
        await backgroundTaskManager.startBackgroundRunning(this.context, backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, this.wantAgentObj)
        console.info('[EntryAbility] Background running started for audio playback')
      }
    } catch (e) {
      console.error('[EntryAbility] Start background running failed:', e)
    }
  }

  async stopBackgroundRunning(): Promise<void> {
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context)
      console.info('[EntryAbility] Background running stopped')
    } catch (e) {
      console.error('[EntryAbility] Stop background running failed:', e)
    }
  }
}
