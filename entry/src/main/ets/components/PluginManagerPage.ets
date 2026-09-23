// PluginManagerPage.ets - 音源管理
// 订阅导入（MusicFree）/ 插件管理 / 自检日志

import { SourceManager } from '../utils/SourceManager'
import { MusicApi } from '../utils/MusicApi'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { promptAction } from '@kit.ArkUI'
import type { SongInfo } from '../model/MusicModel'
import { JsPluginEngine } from '../utils/JsPluginEngine'
import { PluginDiagnostics } from '../utils/PluginDiagnostics'
import { MFSubscription } from '../utils/MFSubscription'
import { MFEngine } from '../utils/MFEngine'
import { playLog, clearPlayLog } from '../utils/PlayLog'
import { systemShare } from '@kit.ShareKit'
import { uniformTypeDescriptor as utd } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { ChipGroup, ChipSize, SymbolGlyphModifier } from '@kit.ArkUI'

/** 自检步骤详情 */
interface TestDetail {
  step: string
  status: 'success' | 'failure' | 'info' | 'pending'
  message: string
}

/** 插件管理页 more 菜单项 */
interface MoreMenuItem {
  value: string
  action: () => void
}

interface TestLogRecord {
  timestamp: string
  pluginCount: number
  okCount: number
  failCount: number
  lines: string[]
}

/** 自检失败信号：记录各步骤成功与否及失败时的错误文本，供诊断归类 */
interface DiagnosticSignal {
  searchOk: boolean
  urlOk: boolean
  lrcOk: boolean
  coverOk: boolean
  // 歌手字段：搜索结果是否携带歌手信息（四项能力之一）
  artistOk: boolean
  searchErr: string
  urlErr: string
  engineErr: string
  // 取链失败的平台名（如「酷狗、酷我」），用于分平台诊断
  platFail: string
}

/** 音源四项能力（自检汇总用）：歌手 / 可播放 / 歌词 / 封面 */
interface SourceCaps {
  artist: boolean
  playable: boolean
  lrc: boolean
  cover: boolean
}

/** MusicFree 订阅源卡片（id 用于 ForEach 稳定 key） */
class MFSubCard {
  id: number
  url: string

  constructor(id: number, url: string) {
    this.id = id
    this.url = url
  }
}

@Component
export struct PluginManagerPage {
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_bg') themeBg: string = '#F8F8FA'
  @StorageProp('theme_cardBg') themeCardBg: string = '#FFFFFF'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'
  @StorageProp('theme_placeholder') themePlaceholder: string = '#E0E0E0'
  @StorageProp('theme_danger') themeDanger: string = '#F44336'
  @StorageProp('isDarkMode') isDarkMode: boolean = false
  @State sourceNames: string[] = []
  @State enabledMap: Record<string, boolean> = {}
  // 插件多选模式
  @State batchDeleteMode: boolean = false
  @State selectedForDelete: Set<string> = new Set()
  // 音源自测（验证闭环：搜索 → 取链 → 歌词 → 封面）
  @State testingSource: string = ''
  @State testResults: string[] = []
  @State testPanelExpanded: boolean = false
  // 增强自检详情：每个音源保存详细步骤结果
  @State testDetailMap: Record<string, TestDetail[]> = {}
  // 每个音源的自检可用状态（''=未测，'ok'=可用，'fail'=不可用，'partial'=部分可用）
  @State sourceTestStatus: Map<string, string> = new Map()
  @State expandedTestSource: string = ''
  @State currentTabIndex: number = 0
  @State chipSelectedIndex: Array<number> = [0]
  @State prefixModifierSub: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.link'))
  @State prefixModifierSubActivated: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.link'))
  @State prefixModifierManage: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.list_bullet'))
  @State prefixModifierManageActivated: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.list_bullet'))
  @State prefixModifierLog: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.waveform'))
  @State prefixModifierLogActivated: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.waveform'))
  @State testLogHistory: TestLogRecord[] = []
  // 自检四项能力记录（歌手/可播放/歌词/封面），键为音源名
  private sourceCaps: Map<string, SourceCaps> = new Map()
  // MusicFree 订阅导入（多订阅卡片）
  @State mfSubs: MFSubCard[] = []
  @State mfSubEnabled: boolean = true
  @State mfChecking: boolean = false
  @State mfCheckLines: string[] = []
  // 当前启用的订阅源地址（单一启用，''=未启用任何订阅）
  @State mfActiveUrl: string = ''
  private mfSubSeq: number = 1
  onBack?: () => void

  async aboutToAppear() {
    await this.loadSources()
    await this.loadEnabledStates()
    await this.loadTestLogHistory()
    await this.loadMfSubscription()
    const active = AppStorage.get<string>('lxActiveSource') || ''
    if (!active && this.sourceNames.length > 0) {
      // 优先选择 v3 插件（需要 LXSourceEngine WebView）
      let targetName = this.sourceNames[0]
      for (let i = 0; i < this.sourceNames.length; i++) {
        const cfg = SourceManager.getConfig(this.sourceNames[i])
        if (cfg && cfg.jsMode === 'v3') {
          targetName = this.sourceNames[i]
          break
        }
      }
      AppStorage.setOrCreate('lxActiveSource', targetName)
      console.info(`[PluginManager] 自动激活音源: ${targetName}`)
    }
  }

  async loadSources() {
    await SourceManager.ensureLoaded()
    this.sourceNames = SourceManager.getSourceNames()
  }

  async loadEnabledStates() {
    const map: Record<string, boolean> = {}
    for (let i = 0; i < this.sourceNames.length; i++) {
      map[this.sourceNames[i]] = await SourceManager.isSourceEnabled(this.sourceNames[i])
    }
    this.enabledMap = map
  }

  async loadTestLogHistory() {
    const db = DatabaseHelper.getInstance()
    const raw = await db.getSetting('testLogHistory')
    if (raw && raw.length > 2) {
      try {
        const arr: TestLogRecord[] = JSON.parse(raw) as TestLogRecord[]
        if (arr instanceof Array && arr.length > 0) {
          this.testLogHistory = arr.slice(0, 3)
        }
      } catch (_e) {}
    }
  }

  async saveTestLogHistory() {
    const db = DatabaseHelper.getInstance()
    try {
      await db.setSetting('testLogHistory', JSON.stringify(this.testLogHistory))
    } catch (_e) {}
  }

  isSourceEnabled(name: string): boolean {
    // 默认启用
    return this.enabledMap[name] !== false
  }

  async setSourceEnabled(name: string, enabled: boolean) {
    this.enabledMap[name] = enabled
    await SourceManager.setSourceEnabled(name, enabled)
    // 互斥：启用插件源时自动关闭自建 API，确保搜索/播放走插件源
    if (enabled && MusicApi.isSelfHostedMode()) {
      const db = DatabaseHelper.getInstance()
      await db.setSetting('useSelfHostedApi', 'false')
      MusicApi.setSelfHostedMode(false, '')
      AppStorage.setOrCreate('useSelfHostedApi', false)
      this.showToastMsg('已自动关闭自建 API')
    }
    // 启用音源时，自动激活新引擎
    if (enabled) {
      AppStorage.setOrCreate('lxActiveSource', name)
      console.info(`[PluginManager] 开关开启，激活音源: ${name}`)
    }
  }

  showToastMsg(msg: string) {
    promptAction.showToast({ message: msg, duration: 2000 })
  }

  /**
   * 分享完整自检日志（自检结果 + 诊断日志 + 引擎日志）。
   * 调用系统分享面板，可复制或发送到社交软件；面板拉起失败时降级复制到剪贴板。
   */
  private async shareTestLog(): Promise<void> {
    const parts: string[] = []
    parts.push('===== Sumy 音源自检日志 =====')
    parts.push(`导出时间：${new Date().toLocaleString()}`)
    parts.push(`已装音源：${this.sourceNames.length > 0 ? this.sourceNames.join('、') : '(无)'}`)
    parts.push('')
    parts.push('----- 自检结果 -----')
    parts.push(this.testResults.length > 0 ? this.testResults.join('\n') : '(尚未执行自检)')
    parts.push('')
    parts.push('----- 诊断日志 -----')
    parts.push(PluginDiagnostics.getLogText())
    const engineLog: string = AppStorage.get<string>('lxPlayLog') || ''
    if (engineLog.length > 0) {
      parts.push('')
      parts.push('----- 引擎日志 -----')
      parts.push(engineLog)
    }
    await this.doShareText(parts.join('\n'))
  }

  private async shareHistoryLog(record: TestLogRecord): Promise<void> {
    const parts: string[] = []
    parts.push(`===== ${record.timestamp} Sumy Music自检日志 =====`)
    parts.push(`自检${record.pluginCount}个插件，可用${record.okCount}个，失效${record.failCount}个`)
    parts.push('')
    parts.push('----- 详细结果 -----')
    parts.push(record.lines.length > 0 ? record.lines.join('\n') : '(无)')
    await this.doShareText(parts.join('\n'))
  }

  private async doShareText(text: string): Promise<void> {
    try {
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: text,
        title: 'Sumy 自检日志',
        description: '音源自检结果与诊断日志',
      })
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData)
      const context = getContext(this) as common.UIAbilityContext
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL,
      })
    } catch (e) {
      console.error('[PluginManager] share test log failed:', e)
      // 降级：复制到剪贴板
      try {
        const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
        const systemPasteboard = pasteboard.getSystemPasteboard()
        await systemPasteboard.setDataSync(pasteData)
        this.showToastMsg('分享面板拉起失败，日志已复制到剪贴板')
      } catch (_e) {
        this.showToastMsg('分享失败')
      }
    }
  }

  // ===== 音源自测（验证闭环） =====
  // 跑真实链路：搜索「海阔天空」→ 取第一首播放链接 → 歌词 → 封面，结果实时显示
  private async runSourceTest(name: string): Promise<void> {
    this.currentTabIndex = 2
    const active = AppStorage.get<string>('lxActiveSource') || ''
    if (active !== name) {
      AppStorage.setOrCreate('lxActiveSource', name)
      console.info(`[PluginManager] 激活音源: ${name}`)
    }

    this.testingSource = name
    this.testResults = []
    this.testPanelExpanded = true
    const results: string[] = []
    // 主步骤序号（1,2,3...），子步骤用原点（-）
    let mainStep = 0
    const push = (line: string, isSub: boolean = false): void => {
      if (!isSub) {
        mainStep++
        results.push(`${mainStep}. ${line}`)
      } else {
        results.push(`- ${line}`)
      }
      this.testResults = results.slice()
    }
    push('自测开始')
    playLog('自检', `开始自检音源: ${name}`)

    // 收集失败信号：各步骤失败时的错误文本，供末尾诊断归类使用
    const signals: DiagnosticSignal = { searchOk: false, urlOk: false, lrcOk: false, coverOk: false, artistOk: false, searchErr: '', urlErr: '', engineErr: '', platFail: '' }

    // 检查是否为 v3 插件，需要等待 WebView 引擎就绪
    const cfg = SourceManager.getConfig(name)
    const isV3 = cfg && cfg.jsMode === 'v3'
    if (isV3) {
      push('等待 JsPluginEngine 就绪…', true)
      playLog('自检', '音源为 v3 插件，等待 JsPluginEngine 就绪')
      const jsReady: boolean = await JsPluginEngine.isReadyPublic()
      if (jsReady) {
        push('JsPluginEngine 已就绪', true)
        playLog('自检', 'JsPluginEngine 已就绪')
      } else {
        push('JsPluginEngine 未就绪，尝试初始化…', true)
        const engineErrMsg: string = JsPluginEngine.lastError.length > 0 ? JsPluginEngine.lastError : '引擎未就绪'
        signals.engineErr = engineErrMsg
        playLog('自检', `JsPluginEngine 未就绪: ${engineErrMsg}`)
        PluginDiagnostics.warn(name, 'engine', 'JsPluginEngine 未就绪', engineErrMsg)
       }
    }

    // 1. 搜索（25s 超时截断，避免死源拖死自测）
    push(`搜索「海阔天空」`, false)
    push('搜索中…', true)
    playLog('自检', `开始搜索「海阔天空」，音源=${name}`)
    const searchStart: number = Date.now()
    let songs: SongInfo[] = []
    // 优先用插件自身搜索（v1/MusicFree 插件走 JsPluginEngine），真实验证插件；
    // v3 插件无 musicSearch 或无结果时回退内置五源
    try {
      songs = await SourceManager.search(name, '海阔天空')
    } catch (_e) {
      playLog('自检', `SourceManager.search 抛出异常: ${String(_e)}`)
      songs = []
    }
    if (songs.length === 0) {
      const searchP: Promise<SongInfo[]> = MusicApi.search('海阔天空', name)
      const timeoutP: Promise<SongInfo[]> = new Promise<SongInfo[]>((resolve: (v: SongInfo[]) => void) => {
        setTimeout(() => { resolve([]) }, 25000)
      })
      try {
        songs = await Promise.race([searchP, timeoutP])
      } catch (_e) {
        songs = []
      }
    }
    const searchCost: number = Date.now() - searchStart
    playLog('自检', `搜索完成，耗时=${searchCost}ms，返回=${songs.length}首`)
    if (songs.length === 0) {
      signals.searchErr = MusicApi.lastError.length > 0 ? MusicApi.lastError : '搜索无结果'
      if (signals.engineErr.length === 0 && JsPluginEngine.lastError.length > 0) {
        signals.engineErr = JsPluginEngine.lastError
      }
      push(`搜索无结果：${signals.searchErr}`, true)
      playLog('自检', `搜索无结果，lastError=${signals.searchErr}`)
      PluginDiagnostics.error(name, 'search', '搜索无结果', signals.searchErr)
      // 附上诊断结论，引导用户判断问题来源
      const failedDiag: string[] = this.buildDiagnosis(signals, results)
      for (let i = 0; i < failedDiag.length; i++) {
        push(failedDiag[i], true)
      }
      this.sourceCaps.set(name, { artist: false, playable: false, lrc: false, cover: false })
      this.sourceTestStatus.set(name, 'fail')
      this.testingSource = ''
      const record: TestLogRecord = {
        timestamp: this.formatLogTimestamp(),
        pluginCount: 1,
        okCount: 0,
        failCount: 1,
        lines: results.slice(),
      }
      this.testLogHistory = [record, ...this.testLogHistory].slice(0, 3)
      this.saveTestLogHistory()
      return
    }
    signals.searchOk = true
    push(`搜索到 ${songs.length} 首`, true)
    const first: SongInfo = songs[0]
    push(`示例：${first.songName} - ${first.artist}`, true)
    // 歌手能力：搜索结果是否携带歌手字段
    for (let i = 0; i < songs.length; i++) {
      if (songs[i].artist && songs[i].artist.length > 0) {
        signals.artistOk = true
        break
      }
    }
    if (signals.artistOk) {
      push('歌手信息已提供', true)
    } else {
      push('歌手信息缺失（搜索结果无歌手字段）', true)
    }

    // 2. 播放链接：按平台分组逐平台取链（fastTest：跳过跨源兜底，只测目标插件取链）
    // 搜索结果是聚合多平台的（kg/kw/tx/wy/mg），只测第一首会漏掉其它平台的失败。
    push('获取播放链接', false)
    // 从 SongInfo 解析平台：优先 rawData.__platform，回退 song.source（去 custom_ 前缀）
    const platOf = (s: SongInfo): string => {
      if (s.rawData && s.rawData.length > 0) {
        try {
          const rawObj: Record<string, Object> = JSON.parse(s.rawData) as Record<string, Object>
          const p = rawObj['__platform']
          if (p !== undefined && p !== null) return String(p)
        } catch (_e) {}
      }
      let src = s.source || ''
      if (src.startsWith('custom_')) src = src.substring(7)
      return src
    }
    // 平台码 → 中文名
    const platName: Record<string, string> = {
      'kg': '酷狗', 'kugou': '酷狗',
      'kw': '酷我', 'kuwo': '酷我',
      'tx': 'QQ', 'qq': 'QQ',
      'wy': '网易', 'netease': '网易',
      'mg': '咪咕', 'migu': '咪咕',
    }
    const fname = (p: string): string => platName[p] ? platName[p] : p
    // 首轮仍验证第一首（兼容单平台插件），额外再测其它平台
    const testedPlat: Set<string> = new Set()
    const failedPlats: string[] = []
    const testOne = async (s: SongInfo, label: string): Promise<void> => {
      const plat: string = platOf(s)
      playLog('自检', `[取链] 试平台=${label}(${plat}) 歌曲=${s.songName}-${s.artist}`)
      const urlStart: number = Date.now()
      const u: string = await MusicApi.getPlayUrl(s.songId, s.source, s, true)
      const urlCost: number = Date.now() - urlStart
      if (u && u.length > 0) {
        playLog('自检', `[取链] 成功 平台=${label}(${plat}) 耗时=${urlCost}ms url=${u.substring(0, 80)}`)
        push(`${label}：播放链接可用`, true)
        PluginDiagnostics.info(name, 'musicUrl', `取链成功 ${label}`, `耗时=${urlCost}ms`)
        signals.urlOk = true
        if (s === first) {
          first.playUrl = u
        }
      } else {
        const err: string = MusicApi.lastError.length > 0 ? MusicApi.lastError : '取链失败'
        playLog('自检', `[取链] 失败 平台=${label}(${plat}) 耗时=${urlCost}ms err=${err}`)
        failedPlats.push(label)
        push(`${label}：取链失败（${err}）`, true)
        PluginDiagnostics.error(name, 'musicUrl', `取链失败 ${label}`, err)
        signals.urlErr = signals.urlErr.length > 0 ? signals.urlErr : err
      }
    }
    const p0: string = platOf(first)
    testedPlat.add(p0)
    await testOne(first, fname(p0))
    // 遍历所有搜索结果，找到不同平台各测一首（最多额外测 4 个平台，避免自检过慢）
    let extraTested = 0
    for (let i = 0; i < songs.length && extraTested < 4; i++) {
      const p: string = platOf(songs[i])
      if (testedPlat.has(p)) continue
      testedPlat.add(p)
      await testOne(songs[i], fname(p))
      extraTested++
    }
    if (failedPlats.length > 0) {
      signals.platFail = failedPlats.join('、')
      playLog('自检', `取链失败平台: ${signals.platFail}`)
    }

    // 3. 歌词（fastTest：只测目标插件歌词，跳过跨源歌词兜底）
    push('获取歌词', false)
    playLog('自检', `[歌词] 开始获取 songId=${first.songId} source=${first.source}`)
    const lrcStart: number = Date.now()
    const lrc: string = await MusicApi.getLyrics(first.songId, first.source, first, true)
    const lrcCost: number = Date.now() - lrcStart
    if (lrc && lrc.length > 0) {
      push(`歌词 ${lrc.length} 字符`, true)
      playLog('自检', `[歌词] 成功 长度=${lrc.length}字符 耗时=${lrcCost}ms`)
      PluginDiagnostics.info(name, 'lyric', '歌词获取成功', `长度=${lrc.length}`)
      signals.lrcOk = true
    } else {
      push('歌词为空（该源可能无歌词数据）', true)
      playLog('自检', `[歌词] 为空 耗时=${lrcCost}ms`)
      PluginDiagnostics.info(name, 'lyric', '歌词为空', '该源可能无歌词数据')
    }

    // 4. 封面
    push('封面字段', false)
    if (first.coverUrl && first.coverUrl.length > 0) {
      push('封面已提供', true)
      playLog('自检', `封面已提供，URL前${first.coverUrl.substring(0, 60)}`)
      PluginDiagnostics.info(name, 'cover', '封面已提供', first.coverUrl.substring(0, 100))
      signals.coverOk = true
    } else {
      push('封面字段为空（播放时再补）', true)
      playLog('自检', '封面字段为空（播放时再补）')
      PluginDiagnostics.info(name, 'cover', '封面为空', '播放时再补')
    }

    // 诊断结论：归类问题并给出处理建议
    const diagnosis: string[] = this.buildDiagnosis(signals, results)
    for (let i = 0; i < diagnosis.length; i++) {
      push(diagnosis[i], true)
    }
    // 记录四项能力（歌手/可播放/歌词/封面）
    const caps: SourceCaps = { artist: signals.artistOk, playable: signals.urlOk, lrc: signals.lrcOk, cover: signals.coverOk }
    this.sourceCaps.set(name, caps)
    const missingCaps: string[] = this.capsMissing(caps)
    if (missingCaps.length === 0) {
      push('四项能力：歌手、可播放、歌词、封面 全部具备', true)
    } else {
      push(`四项能力：具备 ${4 - missingCaps.length}/4（缺：${missingCaps.join('、')}）`, true)
    }
    playLog('自检', `自检结束 音源=${name} searchOk=${signals.searchOk} urlOk=${signals.urlOk} lrcOk=${signals.lrcOk}`)

    // 记录该源的可用状态（部分平台失败 → 部分可用）
    if (signals.urlOk && signals.platFail.length === 0) {
      this.sourceTestStatus.set(name, 'ok')
    } else if (signals.urlOk) {
      // 部分平台可取链、部分失败（如 qq/wy 正常、kg/kw 不可播放）
      this.sourceTestStatus.set(name, 'partial')
    } else {
      this.sourceTestStatus.set(name, 'partial')
    }
    push('自测结束')
    this.testingSource = ''

    const okCount = this.sourceTestStatus.get(name) === 'ok' ? 1 : 0
    const failCount = this.sourceTestStatus.get(name) === 'fail' ? 1 : 0
    const record: TestLogRecord = {
      timestamp: this.formatLogTimestamp(),
      pluginCount: 1,
      okCount: okCount,
      failCount: failCount,
      lines: results.slice(),
    }
    this.testLogHistory = [record, ...this.testLogHistory].slice(0, 3)
  }

  /**
   * 强制重新加载引擎：先置空激活源触发 WebView 销毁，再重新激活触发刷新+重注入。
   * 用于引擎卡在未就绪状态时（如插件环境残留、注入中断）的自愈。
   */
  private async forceReloadEngine(name: string): Promise<void> {
    AppStorage.setOrCreate('lxActiveSource', '')
    await new Promise<void>((resolve: () => void) => { setTimeout(() => { resolve() }, 400) })
    AppStorage.setOrCreate('lxActiveSource', name)
    await new Promise<void>((resolve: () => void) => { setTimeout(() => { resolve() }, 400) })
  }

  /** 等待 LX WebView 引擎就绪（轮询 AppStorage lxEngineReady） */
  private async waitForLxEngine(timeoutMs: number): Promise<boolean> {
    const start = Date.now()
    while (Date.now() - start < timeoutMs) {
      const ready = AppStorage.get<boolean>('lxEngineReady') || false
      if (ready) return true
      await new Promise<void>((resolve: () => void) => { setTimeout(() => { resolve() }, 500) })
    }
    return AppStorage.get<boolean>('lxEngineReady') || false
  }

  private async runAllSourceTests(): Promise<void> {
    if (this.sourceNames.length === 0) {
      this.showToastMsg('暂无已安装插件')
      return
    }
    this.testResults = []
    this.testPanelExpanded = true
    // 清空旧状态
    this.sourceTestStatus = new Map()
    this.sourceCaps = new Map()
    for (let i = 0; i < this.sourceNames.length; i++) {
      await this.runSourceTest(this.sourceNames[i])
    }
    // 汇总每个源的可用性，显示在弹窗中
    const summary: string[] = []
    summary.push('自检汇总：')
    for (let i = 0; i < this.sourceNames.length; i++) {
      const name = this.sourceNames[i]
      const st = this.sourceTestStatus.get(name)
      let label = '未测'
      if (st === 'ok') label = '✅ 可用'
      else if (st === 'partial') label = '⚠️ 部分可用（部分平台取链失败，详见日志）'
      else if (st === 'fail') label = '❌ 不可用'
      // 四项能力标注（歌手/可播放/歌词/封面）
      if (st === 'ok' || st === 'partial') {
        const caps = this.sourceCaps.get(name)
        if (caps) {
          const missing = this.capsMissing(caps)
          if (missing.length === 0) {
            label += '｜四项能力齐备'
          } else {
            label += `｜缺：${missing.join('、')}`
          }
        }
      }
      summary.push(`${i + 1}. ${name}：${label}`)
    }
    // 四项能力统计：哪些音源同时具备歌手/可播放/歌词/封面，哪些四缺一
    summary.push('— 四项能力统计（歌手/可播放/歌词/封面）—')
    const fullCaps: string[] = []
    const missOne: string[] = []
    const missMore: string[] = []
    for (let i = 0; i < this.sourceNames.length; i++) {
      const name = this.sourceNames[i]
      const st = this.sourceTestStatus.get(name)
      if (st !== 'ok' && st !== 'partial') {
        continue
      }
      const caps = this.sourceCaps.get(name)
      if (!caps) {
        continue
      }
      const missing = this.capsMissing(caps)
      if (missing.length === 0) {
        fullCaps.push(name)
      } else if (missing.length === 1) {
        missOne.push(`${name}（缺${missing[0]}）`)
      } else {
        missMore.push(`${name}（缺${missing.join('、')}）`)
      }
    }
    summary.push(`四项齐备：${fullCaps.length > 0 ? fullCaps.join('、') : '（无）'}`)
    if (missOne.length > 0) {
      summary.push(`四缺一：${missOne.join('、')}`)
    }
    if (missMore.length > 0) {
      summary.push(`缺多项：${missMore.join('、')}`)
    }
    this.testResults = summary
    this.showToastMsg('全部音源自测完成')

    let okCount = 0
    let failCount = 0
    for (let i = 0; i < this.sourceNames.length; i++) {
      const st = this.sourceTestStatus.get(this.sourceNames[i])
      if (st === 'ok') okCount++
      else if (st === 'fail') failCount++
    }
    const record: TestLogRecord = {
      timestamp: this.formatLogTimestamp(),
      pluginCount: this.sourceNames.length,
      okCount: okCount,
      failCount: failCount,
      lines: summary.slice(),
    }
    this.testLogHistory = [record, ...this.testLogHistory].slice(0, 3)
  }

  /**
   * 生成诊断结论：根据自检各阶段失败信号，将问题归类为
   * ① 插件损坏/不兼容 ② 软件/引擎问题 ③ 其它（网络/无版权/单曲无数据），并给出处理建议。
   * 返回的每一行作为自检结果中的子项（- 前缀）展示。
   */
  private buildDiagnosis(sig: DiagnosticSignal, results: string[]): string[] {
    const out: string[] = []
    const errText: string = [sig.searchErr, sig.urlErr, sig.engineErr].filter((s: string) => s.length > 0).join(' | ')
    // 归一化错误文本，便于关键词匹配
    const low: string = errText.toLowerCase()

    // 引擎初始化/就绪异常 → 属软件/引擎问题
    const engineIssue: boolean =
      low.indexOf('未初始化') >= 0 || low.indexOf('初始化超时') >= 0 || low.indexOf('引擎未就绪') >= 0 ||
      low.indexOf('引擎调用异常') >= 0 || low.indexOf('初始化失败') >= 0 || low.indexOf('is not defined') >= 0

    // 插件声明/解析异常（缺 action、数据格式异常、任务启动失败）→ 属插件损坏或不兼容
    const pluginIssue: boolean =
      low.indexOf('未声明支持') >= 0 || low.indexOf('格式异常') >= 0 || low.indexOf('任务启动失败') >= 0 ||
      low.indexOf('返回空 id') >= 0 || low.indexOf('解析') >= 0 || low.indexOf('unexpected') >= 0 ||
      low.indexOf('syntaxerror') >= 0

    // 网络/超时类 → 多属其它（网络或目标源不可达）
    const networkIssue: boolean =
      low.indexOf('timeout') >= 0 || low.indexOf('超时') >= 0 || low.indexOf('socket') >= 0 ||
      low.indexOf('dns') >= 0 || low.indexOf('connect') >= 0 || low.indexOf('请求失败') >= 0

    // 引擎已就绪但插件无动作 → 强信号指向插件本身（可能损坏/缺入口）
    const engineReadyButNoAction: boolean = results.some((l: string) => l.indexOf('已就绪') >= 0 && l.indexOf('JsPluginEngine') >= 0)

    out.push('— 诊断结论 —')
    if (!sig.searchOk && !sig.urlOk && sig.searchErr.length === 0 && sig.urlErr.length === 0) {
      // 搜索与取链都没有具体错误（可能超时/被软超时掐断）
      out.push('问题来源：搜索与取链均无返回（可能超时或插件无响应）')
      out.push('处理建议：① 检查网络 ② 等待片刻后重试 ③ 若持续，重装该插件')
    } else if (sig.engineErr.length === 0 && pluginIssue) {
      out.push('问题来源：插件损坏或不兼容')
      out.push('处理建议：删除并重新导入该音源；若为旧格式插件请更新为最新版')
    } else if (engineIssue) {
      out.push('问题来源：软件/引擎问题（插件运行环境异常）')
      out.push('处理建议：① 在音源管理点「强制重载引擎」 ② 重启 App ③ 仍无效则反馈开发者并附本日志')
    } else if (networkIssue && !sig.searchOk) {
      out.push('问题来源：网络问题或目标平台不可达')
      out.push('处理建议：检查网络连接，切换 Wi-Fi/移动数据后重试')
    } else if (sig.searchOk && !sig.urlOk) {
      // 搜索成功但取链失败
      if (engineReadyButNoAction) {
        out.push('问题来源：插件已就绪但取链返回空（可能无版权、插件过时或该曲目无资源）')
      } else {
        out.push('问题来源：搜索正常但取链返回空（多为无版权/插件过时/该曲目无资源）')
      }
      out.push('处理建议：① 换一首常见歌曲再测 ② 更新插件 ③ 若固定失败多为此源无播放权限')
    } else if (sig.searchOk && sig.urlOk && sig.platFail.length > 0) {
      // 至少一个平台可取链，但部分平台失败（如 kg/kw 不可播放而 qq/wy 正常）
      out.push(`问题来源：部分平台取链失败（${sig.platFail}），其余平台正常`)
      out.push('处理建议：① 失败平台多为该源(插件)对应接口失效/无版权/该曲目无资源 ② 若其它软件可播该平台，多为本插件该平台通道异常，可换其它插件或等插件更新 ③ 可先用可用平台播放')
    } else if (sig.searchOk && sig.urlOk && !sig.lrcOk) {
      out.push('问题来源：播放链接正常，仅歌词为空')
      out.push('处理建议：歌词缺失多为单曲数据本身无歌词，非故障，可忽略')
    } else {
      out.push('问题来源：暂未识别到明显异常')
      out.push('处理建议：可直接播放验证；如有异常请提供自检日志反馈')
    }
    return out
  }

  /** 返回四项能力中缺失项的中文名列表 */
  private capsMissing(caps: SourceCaps): string[] {
    const missing: string[] = []
    if (!caps.artist) missing.push('歌手')
    if (!caps.playable) missing.push('可播放')
    if (!caps.lrc) missing.push('歌词')
    if (!caps.cover) missing.push('封面')
    return missing
  }

  private testLineColor(line: string): string {
    if (/^\d+\./.test(line)) return this.themePrimary
    if (line.indexOf('失败') >= 0 || line.indexOf('无结果') >= 0 || line.indexOf('为空') >= 0) return this.themeDanger
    if (line.indexOf('可用') >= 0 || line.indexOf('已提供') >= 0 || line.indexOf('齐备') >= 0) return '#2E7D32'
    return this.themeTextSecondary
  }

  private formatLogTimestamp(): string {
    const d = new Date()
    const pad = (n: number): string => n < 10 ? '0' + n : '' + n
    return `${d.getFullYear()}/${pad(d.getMonth() + 1)}/${pad(d.getDate())}/${pad(d.getHours())}${pad(d.getMinutes())}`
  }

  // ===== MusicFree 订阅导入（多订阅卡片） =====
  private async loadMfSubscription(): Promise<void> {
    this.mfSubEnabled = await MFSubscription.getEnabled()
    this.mfActiveUrl = await MFSubscription.getActive()
    const urls: string[] = await MFSubscription.getList()
    const cards: MFSubCard[] = []
    this.mfSubSeq = 1
    for (let i = 0; i < urls.length; i++) {
      cards.push(new MFSubCard(this.mfSubSeq, urls[i]))
      this.mfSubSeq++
    }
    this.mfSubs = cards
  }

  /** 触发 ForEach 刷新（数组元素变更需整体重赋值） */
  private touchSubs(): void {
    this.mfSubs = this.mfSubs.slice()
  }

  private updateSubUrl(sub: MFSubCard, url: string): void {
    // 已启用的订阅地址被修改时自动释放启用状态，避免标记与实际地址不符
    if (this.mfActiveUrl.length > 0 && sub.url.trim() === this.mfActiveUrl && url.trim() !== this.mfActiveUrl) {
      this.mfActiveUrl = ''
      MFSubscription.saveActive('')
      this.showToastMsg('订阅地址已修改，请重新启用')
    }
    sub.url = url
    this.touchSubs()
  }

  private addMfSub(): void {
    this.mfSubs.push(new MFSubCard(this.mfSubSeq, ''))
    this.mfSubSeq++
    this.touchSubs()
  }

  private async removeMfSub(sub: MFSubCard): Promise<void> {
    const next: MFSubCard[] = []
    for (let i = 0; i < this.mfSubs.length; i++) {
      if (this.mfSubs[i].id !== sub.id) {
        next.push(this.mfSubs[i])
      }
    }
    this.mfSubs = next
    await this.persistMfSubs()
  }

  private confirmRemoveMfSub(sub: MFSubCard): void {
    promptAction.showDialog({
      title: '删除订阅源',
      message: '确定要删除该订阅源吗？\n（已安装的插件不受影响，可在「插件管理」页管理）',
      buttons: [
        { text: '取消', color: this.themeTextSecondary },
        { text: '删除', color: this.themeDanger },
      ],
    }).then(async (result) => {
      if (result.index === 1) {
        await this.removeMfSub(sub)
        this.showToastMsg('订阅源已删除')
      }
    })
  }

  /** 持久化当前全部卡片地址（过滤空项） */
  private async persistMfSubs(): Promise<void> {
    const urls: string[] = []
    for (let i = 0; i < this.mfSubs.length; i++) {
      const u: string = this.mfSubs[i].url.trim()
      if (u.length > 0) {
        urls.push(u)
      }
    }
    await MFSubscription.saveList(urls)
  }

  /** 保存启用开关并应用到全部已安装的 MusicFree 插件 */
  private async saveMfEnabled(): Promise<void> {
    await MFSubscription.saveEnabled(this.mfSubEnabled)
    await this.loadSources()
    await this.applyMfEnabledToSources()
    await this.loadEnabledStates()
  }

  private async saveMfSubscription(sub: MFSubCard): Promise<void> {
    const url: string = sub.url.trim()
    if (url.length > 0 && !MFSubscription.isValidUrl(url)) {
      this.showToastMsg('地址需为 http(s) 且以 .js 或 .json 结尾')
      return
    }
    await this.persistMfSubs()
    await this.saveMfEnabled()
    this.showToastMsg(url.length > 0 ? '订阅已保存' : '订阅已清空')
  }

  /** 该订阅是否为当前启用的订阅（按地址匹配） */
  private isSubActive(sub: MFSubCard): boolean {
    return this.mfActiveUrl.length > 0 && sub.url.trim() === this.mfActiveUrl
  }

  /** 是否存在已启用的订阅（存在时其余订阅的「启用」按钮锁定为黑色） */
  private hasAnyActiveSub(): boolean {
    if (this.mfActiveUrl.length === 0) {
      return false
    }
    for (let i = 0; i < this.mfSubs.length; i++) {
      if (this.mfSubs[i].url.trim() === this.mfActiveUrl) {
        return true
      }
    }
    return false
  }

  /** 启用订阅（只允许单一启用）：标记后立即拉取安装该订阅的插件 */
  private async enableMfSub(sub: MFSubCard): Promise<void> {
    if (this.mfChecking) {
      return
    }
    const url: string = sub.url.trim()
    if (url.length === 0) {
      this.showToastMsg('请输入订阅源地址')
      return
    }
    if (!MFSubscription.isValidUrl(url)) {
      this.showToastMsg('地址需为 http(s) 且以 .js 或 .json 结尾')
      return
    }
    await MFSubscription.saveActive(url)
    this.mfActiveUrl = url
    this.showToastMsg('已启用该订阅源，开始安装插件…')
    await this.runMfCheck(sub, true)
  }

  /** 释放已启用的订阅（再次点击已启用订阅的「已启用」按钮触发，之后才能启用其它订阅） */
  private async releaseMfSub(): Promise<void> {
    await MFSubscription.saveActive('')
    this.mfActiveUrl = ''
    this.showToastMsg('已释放订阅源，可启用其它订阅源')
  }

  // 把订阅启用状态应用到全部已安装的 MusicFree 插件
  private async applyMfEnabledToSources(): Promise<void> {
    for (let i = 0; i < this.sourceNames.length; i++) {
      const cfg = SourceManager.getConfig(this.sourceNames[i])
      if (cfg && cfg.jsMode === 'mf') {
        await SourceManager.setSourceEnabled(this.sourceNames[i], this.mfSubEnabled)
      }
    }
  }

  private finishMfCheck(okCount: number, failCount: number, lines: string[]): void {
    this.mfChecking = false
    const record: TestLogRecord = {
      timestamp: this.formatLogTimestamp(),
      pluginCount: okCount + failCount,
      okCount: okCount,
      failCount: failCount,
      lines: lines.slice(),
    }
    this.testLogHistory = [record, ...this.testLogHistory].slice(0, 3)
    this.saveTestLogHistory()
  }

  private async waitMfEngineReady(timeoutMs: number): Promise<boolean> {
    const start: number = Date.now()
    while (Date.now() - start < timeoutMs) {
      if (MFEngine.getInstance().isReady()) {
        return true
      }
      await new Promise<void>((resolve: () => void) => {
        setTimeout(() => { resolve() }, 300)
      })
    }
    return MFEngine.getInstance().isReady()
  }

  private async mfSearchWithTimeout(name: string, jsSource: string, keyword: string, timeoutMs: number): Promise<SongInfo[]> {
    const task: Promise<SongInfo[]> = MFEngine.getInstance().search(name, jsSource, keyword)
    const timeoutP: Promise<SongInfo[]> = new Promise<SongInfo[]>((resolve: (v: SongInfo[]) => void) => {
      setTimeout(() => { resolve([]) }, timeoutMs)
    })
    try {
      return await Promise.race([task, timeoutP])
    } catch (_e) {
      return []
    }
  }

  private async mfGetUrlWithTimeout(name: string, jsSource: string, song: SongInfo, timeoutMs: number): Promise<string> {
    const task: Promise<string> = MFEngine.getInstance().getPlayUrl(name, jsSource, song)
    const timeoutP: Promise<string> = new Promise<string>((resolve: (v: string) => void) => {
      setTimeout(() => { resolve('') }, timeoutMs)
    })
    try {
      return await Promise.race([task, timeoutP])
    } catch (_e) {
      return ''
    }
  }

  // 订阅自检/启用安装：校验 → 沙箱就绪/依赖库检测 → 拉取安装 →（自检模式）搜索/取链冒烟 → 汇总写历史
  // enableMode=true 为「启用」按钮触发：跳过冒烟测试，只拉取安装并应用启用状态
  private async runMfCheck(sub: MFSubCard, enableMode: boolean = false): Promise<void> {
    if (this.mfChecking) {
      return
    }
    const url: string = sub.url.trim()
    if (url.length === 0) {
      this.showToastMsg('请输入订阅源地址')
      return
    }
    // 自检基于当前输入内容，先静默保存
    await this.persistMfSubs()
    await MFSubscription.saveEnabled(this.mfSubEnabled)
    const logTag: string = enableMode ? '订阅启用' : '订阅自检'

    this.mfChecking = true
    this.mfCheckLines = []
    const lines: string[] = []
    let mainStep = 0
    const push = (line: string, isSub: boolean = false): void => {
      if (!isSub) {
        mainStep++
        lines.push(`${mainStep}. ${line}`)
      } else {
        lines.push(`- ${line}`)
      }
      this.mfCheckLines = lines.slice()
    }
    playLog(logTag, `开始${enableMode ? '启用' : '自检'}订阅源: ${url}`)

    // 1. 地址校验
    push('地址校验')
    if (!MFSubscription.isValidUrl(url)) {
      push('地址需为 http(s) 且以 .js 或 .json 结尾', true)
      playLog(logTag, '地址校验失败')
      this.finishMfCheck(0, 1, lines)
      return
    }
    push('格式正确', true)

    // 2. MF 沙箱引擎就绪 + 依赖库检测
    push('检查 MusicFree 沙箱引擎')
    const engineReady: boolean = await this.waitMfEngineReady(10000)
    if (!engineReady) {
      push('MF 沙箱引擎未就绪（WebView 加载失败）', true)
      playLog(logTag, 'MF 沙箱引擎未就绪')
      if (enableMode) {
        this.showToastMsg('订阅已启用，但沙箱引擎未就绪，详见订阅自检')
      }
      this.finishMfCheck(0, 1, lines)
      return
    }
    push('沙箱引擎就绪', true)
    try {
      const probeRaw: string = await MFEngine.getInstance().probeEnvironment()
      const probe: Record<string, Object> = JSON.parse(probeRaw) as Record<string, Object>
      const libs: number = probe['libs'] !== undefined && probe['libs'] !== null ? Number(probe['libs']) : -1
      const total: number = probe['total'] !== undefined && probe['total'] !== null ? Number(probe['total']) : -1
      let missing: string = ''
      if (probe['missing'] instanceof Array) {
        const arr: Object[] = probe['missing'] as Object[]
        const parts: string[] = []
        for (let i = 0; i < arr.length; i++) {
          parts.push(String(arr[i]))
        }
        missing = parts.join('、')
      }
      if (libs >= total && total > 0) {
        push(`依赖库 ${libs}/${total} 全部可用`, true)
      } else {
        push(`依赖库 ${libs}/${total} 可用，缺失: ${missing}（插件将无法使用这些库）`, true)
        playLog(logTag, `沙箱依赖库缺失: ${missing}`)
      }
    } catch (_e) {
      push('依赖库检测失败（沙箱协议异常）', true)
    }

    // 3. 拉取订阅并安装
    push('拉取订阅并安装插件')
    const started: number = Date.now()
    const result = await MFSubscription.sync(url, (line: string) => {
      push(line, true)
    })
    push(`安装完成：成功 ${result.okCount} 个，失败 ${result.failCount} 个，耗时 ${Date.now() - started}ms`, true)

    // 4. 冒烟测试：搜索 + 取链（最多测 2 个已安装插件）；启用模式跳过，只做安装
    let smokeOk = false
    let smokeFail = 0
    if (!enableMode && result.installedNames.length > 0) {
      push('搜索冒烟测试')
      const testNames: string[] = result.installedNames.slice(0, 2)
      for (let i = 0; i < testNames.length; i++) {
        const name: string = testNames[i]
        const cfg = SourceManager.getConfig(name)
        if (!cfg || !cfg.jsSource) {
          continue
        }
        const songs: SongInfo[] = await this.mfSearchWithTimeout(name, cfg.jsSource, '海阔天空', 12000)
        if (songs.length === 0) {
          push(`${name}：搜索无结果（插件可能需要网络或接口失效）`, true)
          smokeFail++
          continue
        }
        push(`${name}：搜索到 ${songs.length} 首（${songs[0].songName} - ${songs[0].artist}）`, true)
        const playUrl: string = await this.mfGetUrlWithTimeout(name, cfg.jsSource, songs[0], 10000)
        if (playUrl.length > 0) {
          push(`${name}：播放链接可用`, true)
          smokeOk = true
        } else {
          push(`${name}：取链失败（${MFEngine.lastError}）`, true)
          smokeFail++
        }
      }
    }

    // 5. 汇总
    push(enableMode ? '启用汇总' : '自检汇总')
    push(`插件安装：成功 ${result.okCount}，失败 ${result.failCount}`, true)
    if (!enableMode && result.installedNames.length > 0) {
      push(`冒烟测试：${smokeOk ? '通过' : '未通过'}${smokeFail > 0 ? `（${smokeFail} 项失败）` : ''}`, true)
    }
    push('已安装插件可在「插件管理」页单独启用/关闭', true)
    playLog(logTag, `${enableMode ? '启用' : '自检'}结束 安装成功=${result.okCount} 失败=${result.failCount}`)

    // 刷新插件列表并应用订阅启用状态
    await this.loadSources()
    await this.applyMfEnabledToSources()
    await this.loadEnabledStates()
    this.finishMfCheck(result.okCount, result.failCount, lines)
    if (enableMode) {
      this.showToastMsg(result.okCount > 0 ? `订阅已启用，安装成功 ${result.okCount} 个插件` : '订阅已启用，但插件安装失败，详见订阅自检')
    }
  }

  getPluginType(name: string): string {
    const config = SourceManager.getConfig(name)
    if (config && config.jsMode === 'mf') {
      return 'MusicFree 插件'
    }
    return (config && config.type === 'lx_plugin') ? 'JS 插件' : 'JS 插件'
  }

  async deleteSource(name: string) {
    promptAction.showDialog({
      title: '删除音源',
      message: `确定要删除音源「${name}」吗？`,
      buttons: [
        { text: '取消', color: this.themeTextSecondary },
        { text: '删除', color: this.themeDanger },
      ],
    }).then(async (result) => {
      if (result.index === 1) {
        await SourceManager.removeSource(name)
        await this.loadSources()
        this.showToastMsg(`已删除: ${name}`)
      }
    })
  }

  // 一键开启所有源
  async enableAllSources() {
    if (this.sourceNames.length === 0) {
      this.showToastMsg('暂无已安装插件')
      return
    }
    for (let i = 0; i < this.sourceNames.length; i++) {
      await this.setSourceEnabled(this.sourceNames[i], true)
    }
    this.showToastMsg(`已开启全部 ${this.sourceNames.length} 个插件`)
  }

  // 一键关闭所有源
  async disableAllSources() {
    if (this.sourceNames.length === 0) {
      this.showToastMsg('暂无已安装插件')
      return
    }
    for (let i = 0; i < this.sourceNames.length; i++) {
      await this.setSourceEnabled(this.sourceNames[i], false)
    }
    this.showToastMsg(`已关闭全部 ${this.sourceNames.length} 个插件`)
  }

  // 进入插件多选模式
  enterBatchDeleteMode() {
    if (this.sourceNames.length === 0) {
      this.showToastMsg('暂无已安装插件')
      return
    }
    this.selectedForDelete = new Set()
    this.batchDeleteMode = true
  }

  // 退出批量删除模式
  exitBatchDeleteMode() {
    this.batchDeleteMode = false
    this.selectedForDelete = new Set()
  }

  // 切换某个源的勾选状态
  toggleSelectForDelete(name: string) {
    const newSet = new Set(this.selectedForDelete)
    if (newSet.has(name)) {
      newSet.delete(name)
    } else {
      newSet.add(name)
    }
    this.selectedForDelete = newSet
  }

  // 全选/取消全选
  toggleSelectAll() {
    if (this.selectedForDelete.size === this.sourceNames.length) {
      this.selectedForDelete = new Set()
    } else {
      const newSet = new Set<string>()
      for (let i = 0; i < this.sourceNames.length; i++) {
        newSet.add(this.sourceNames[i])
      }
      this.selectedForDelete = newSet
    }
  }

  // 批量删除勾选的源
  async batchDeleteSelected() {
    if (this.selectedForDelete.size === 0) {
      this.showToastMsg('请先勾选插件')
      return
    }
    const count = this.selectedForDelete.size
    promptAction.showDialog({
      title: '批量删除',
      message: `确定要删除选中的 ${count} 个插件吗？`,
      buttons: [
        { text: '取消', color: this.themeTextSecondary },
        { text: '删除', color: this.themeDanger },
      ],
    }).then(async (result) => {
      if (result.index === 1) {
        const names = Array.from(this.selectedForDelete)
        for (let i = 0; i < names.length; i++) {
          await SourceManager.removeSource(names[i])
        }
        await this.loadSources()
        this.exitBatchDeleteMode()
        this.showToastMsg(`已删除 ${count} 个插件`)
      }
    })
  }

  // 批量启用/关闭勾选的插件
  async batchSetSelectedEnabled(enabled: boolean) {
    if (this.selectedForDelete.size === 0) {
      this.showToastMsg('请先勾选插件')
      return
    }
    const names: string[] = Array.from(this.selectedForDelete)
    for (let i = 0; i < names.length; i++) {
      await this.setSourceEnabled(names[i], enabled)
    }
    await this.loadEnabledStates()
    this.showToastMsg(enabled ? `已启用 ${names.length} 个插件` : `已关闭 ${names.length} 个插件`)
  }

  // 插件管理页右上角 more 菜单
  private buildMoreMenuItems(): MoreMenuItem[] {
    return [
      { value: '一键全启', action: (): void => { this.enableAllSources() } },
      { value: '一键关闭', action: (): void => { this.disableAllSources() } },
      { value: '插件多选', action: (): void => { this.enterBatchDeleteMode() } },
      { value: '全部自检', action: (): void => { this.runAllSourceTests() } },
    ]
  }

  @Builder PluginItem(name: string, index: number) {
    Row({ space: 12 }) {
      // 多选模式下显示左侧勾选圆圈
      if (this.batchDeleteMode) {
        Row() {
          SymbolGlyph(this.selectedForDelete.has(name) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
            .fontSize(22)
            .fontColor(this.selectedForDelete.has(name) ? [this.themePrimary] : [this.themeTextSecondary])
        }
        .width(28)
        .height(28)
        .justifyContent(FlexAlign.Center)
        .flexShrink(0)
      }

      // 序号（替代原自检图标）
      Text(String(index + 1))
        .fontSize(13)
        .fontColor(this.themeTextSecondary)
        .fontWeight(FontWeight.Medium)
        .width(22)
        .textAlign(TextAlign.Center)
        .flexShrink(0)

      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(name)
            .fontSize(15)
            .fontColor(this.themeTextPrimary)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.sourceTestStatus.get(name) === 'ok') {
            Text('可用')
              .fontSize(10)
              .fontColor(Color.White)
              .backgroundColor('#2E7D32')
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .borderRadius(4)
              .flexShrink(0)
          } else if (this.sourceTestStatus.get(name) === 'partial') {
            Text('部分可用')
              .fontSize(10)
              .fontColor(Color.White)
              .backgroundColor('#FF9800')
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .borderRadius(4)
              .flexShrink(0)
          } else if (this.sourceTestStatus.get(name) === 'fail') {
            Text('不可用')
              .fontSize(10)
              .fontColor(Color.White)
              .backgroundColor(this.themeDanger)
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .borderRadius(4)
              .flexShrink(0)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.getPluginType(name))
          .fontSize(12)
          .fontColor(this.themeTextSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (!this.batchDeleteMode) {
        Toggle({ type: ToggleType.Switch, isOn: this.isSourceEnabled(name) })
          .selectedColor(this.themePrimary)
          .width(40)
          .onChange((isOn: boolean) => {
            this.setSourceEnabled(name, isOn)
          })

        Row() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(16)
            .fontColor([this.themeDanger])
        }
        .width(30)
        .height(30)
        .justifyContent(FlexAlign.Center)
        .flexShrink(0)
        .onClick(() => {
          this.deleteSource(name)
        })
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeCardBg)
    .borderRadius(14)
    .onClick(() => {
      if (this.batchDeleteMode) {
        this.toggleSelectForDelete(name)
      }
    })
  }

  build() {
    Stack() {
      Column() {
        // Header
        Row({ space: 12 }) {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(24)
              .fontColor([this.themeTextPrimary])
          }
          .width(36)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            if (this.batchDeleteMode) {
              this.exitBatchDeleteMode()
            } else if (this.onBack) {
              this.onBack()
            }
          })

          Text(this.batchDeleteMode ? `已选 ${this.selectedForDelete.size} 项` : '音源管理')
            .fontSize(17)
            .fontColor(this.themeTextPrimary)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 4 })

        // ChipGroup 标签切换
        Row() {
          ChipGroup({
            items: [
              {
                prefixSymbol: {
                  normal: this.prefixModifierSub,
                  activated: this.prefixModifierSubActivated
                },
                label: { text: '订阅导入' },
              },
              {
                prefixSymbol: {
                  normal: this.prefixModifierManage,
                  activated: this.prefixModifierManageActivated
                },
                label: { text: '插件管理' },
              },
              {
                prefixSymbol: {
                  normal: this.prefixModifierLog,
                  activated: this.prefixModifierLogActivated
                },
                label: { text: '自检日志' },
              },
            ],
            itemStyle: {
              size: ChipSize.NORMAL,
              backgroundColor: this.isDarkMode ? '#333333' : '#F0F0F0',
              fontColor: this.themeTextSecondary,
              selectedBackgroundColor: this.themePrimary,
              selectedFontColor: Color.White,
            },
            selectedIndexes: this.chipSelectedIndex,
            multiple: false,
            chipGroupSpace: { itemSpace: 8, startSpace: 16, endSpace: 16 },
            chipGroupPadding: { top: 6, bottom: 6 },
            onChange: (activatedChipsIndex: Array<number>) => {
              if (activatedChipsIndex.length > 0) {
                this.chipSelectedIndex = activatedChipsIndex
                this.currentTabIndex = activatedChipsIndex[0]
              }
            },
          })
        }
        .width('100%')

        // Swiper 左右滑动页面
        Swiper() {
          // 页面1: 订阅导入
          Column() {
            Scroll() {
              Column({ space: 12 }) {
                // 说明 + 全局启用开关
                Column({ space: 10 }) {
                  Row() {
                    Text('MusicFree 订阅')
                      .fontSize(16)
                      .fontColor(this.themeTextPrimary)
                      .fontWeight(FontWeight.Bold)
                      .layoutWeight(1)

                    Toggle({ type: ToggleType.Switch, isOn: this.mfSubEnabled })
                      .selectedColor(this.themePrimary)
                      .width(40)
                      .onChange((isOn: boolean) => {
                        this.mfSubEnabled = isOn
                        this.saveMfEnabled()
                      })
                  }
                  .width('100%')

                  Text('开启后依靠插件进行歌曲搜索、播放等操作。')
                    .fontSize(12)
                    .fontColor(this.themeTextSecondary)
                    .width('100%')
                }
                .width('100%')
                .padding(16)
                .backgroundColor(this.themeCardBg)
                .borderRadius(14)

                // 订阅源卡片（多个，竖排）
                ForEach(this.mfSubs, (sub: MFSubCard) => {
                  Column({ space: 12 }) {
                    Row() {
                      Text('订阅源')
                        .fontSize(15)
                        .fontColor(this.themeTextPrimary)
                        .fontWeight(FontWeight.Medium)
                      Blank()
                      SymbolGlyph($r('sys.symbol.trash'))
                        .fontSize(16)
                        .fontColor([this.themeTextSecondary])
                        .onClick(() => {
                          this.confirmRemoveMfSub(sub)
                        })
                    }
                    .width('100%')

                    Row({ space: 8 }) {
                      TextInput({ placeholder: 'https://example.com/plugins.json', text: sub.url })
                        .layoutWeight(1)
                        .height(44)
                        .fontSize(14)
                        .fontColor(this.themeTextPrimary)
                        .placeholderColor(this.themeTextSecondary)
                        .backgroundColor(this.themePlaceholder)
                        .borderRadius(10)
                        .padding({ left: 12, right: 12 })
                        .onChange((value: string) => {
                          this.updateSubUrl(sub, value)
                        })

                      if (sub.url.length > 0) {
                        SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
                          .fontSize(18)
                          .fontColor([this.themeTextSecondary])
                          .onClick(() => {
                            this.updateSubUrl(sub, '')
                          })
                      }
                    }
                    .width('100%')

                    Row({ space: 10 }) {
                      // 启用：单一启用；已启用=红色背景，再点释放；存在已启用订阅时其余「启用」标黑锁定
                      Button(this.isSubActive(sub) ? '已启用' : '启用')
                        .fontSize(13)
                        .fontColor(this.isSubActive(sub) || this.hasAnyActiveSub() ? Color.White : this.themeTextPrimary)
                        .backgroundColor(this.isSubActive(sub) ? this.themeDanger : (this.hasAnyActiveSub() ? (this.isDarkMode ? '#333333' : '#000000') : this.themePlaceholder))
                        .borderRadius(10)
                        .layoutWeight(1)
                        .enabled(!this.mfChecking && (!this.hasAnyActiveSub() || this.isSubActive(sub)))
                        .onClick(() => {
                          if (this.isSubActive(sub)) {
                            this.releaseMfSub()
                          } else if (!this.hasAnyActiveSub()) {
                            this.enableMfSub(sub)
                          }
                        })

                      Button('保存')
                        .fontSize(13)
                        .fontColor(this.themeTextPrimary)
                        .backgroundColor(this.themePlaceholder)
                        .borderRadius(10)
                        .layoutWeight(1)
                        .onClick(() => {
                          this.saveMfSubscription(sub)
                        })

                      Button(this.mfChecking ? '自检中…' : '自检')
                        .fontSize(13)
                        .fontColor(Color.White)
                        .backgroundColor(this.themePrimary)
                        .borderRadius(10)
                        .layoutWeight(1)
                        .enabled(!this.mfChecking)
                        .onClick(() => {
                          this.runMfCheck(sub)
                        })
                    }
                    .width('100%')
                  }
                  .width('100%')
                  .padding(16)
                  .backgroundColor(this.themeCardBg)
                  .borderRadius(14)
                }, (sub: MFSubCard) => sub.id.toString())

                // 添加订阅源
                Button('＋ 添加订阅源')
                  .fontSize(14)
                  .fontColor(this.themePrimary)
                  .backgroundColor(this.themeCardBg)
                  .borderRadius(14)
                  .width('100%')
                  .height(44)
                  .onClick(() => {
                    this.addMfSub()
                  })

                // 订阅自检输出
                Column() {
                  Row() {
                    Column({ space: 2 }) {
                      Text('订阅自检')
                        .fontSize(15)
                        .fontColor(this.themeTextPrimary)
                        .fontWeight(FontWeight.Medium)
                      Text('拉取订阅 → 安装插件 → 沙箱挂载 → 搜索/取链冒烟')
                        .fontSize(11)
                        .fontColor(this.themeTextSecondary)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    if (this.mfChecking) {
                      LoadingProgress()
                        .width(18)
                        .height(18)
                        .color(this.themePrimary)
                        .margin({ right: 8 })
                    }
                  }
                  .width('100%')
                  .padding({ bottom: 8 })

                  if (this.mfCheckLines.length === 0) {
                    Text('点击「自检」开始验证订阅源')
                      .fontSize(12)
                      .fontColor(this.themeTextSecondary)
                      .width('100%')
                  } else {
                    Column({ space: 3 }) {
                      ForEach(this.mfCheckLines, (line: string) => {
                        Text(line)
                          .fontSize(12)
                          .fontColor(this.testLineColor(line))
                          .width('100%')
                          .maxLines(3)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      })
                    }
                    .width('100%')
                    .alignItems(HorizontalAlign.Start)
                  }
                }
                .width('100%')
                .padding(16)
                .backgroundColor(this.themeCardBg)
                .borderRadius(14)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 8, bottom: 100 })
            }
            .layoutWeight(1)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
            .align(Alignment.Top)
          }
          .width('100%')
          .height('100%')

          // 页面2: 插件管理（仅展示已安装插件）
          Column() {
            if (this.sourceNames.length === 0) {
              Column({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.list_bullet'))
                  .fontSize(48)
                  .fontColor([this.themeTextSecondary])
                  .opacity(0.3)
                Text('暂无已安装插件')
                  .fontSize(16)
                  .fontColor(this.themeTextPrimary)
                  .fontWeight(FontWeight.Medium)
                Text('前往「订阅导入」添加订阅源并自检安装')
                  .fontSize(13)
                  .fontColor(this.themeTextSecondary)
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Start)
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 48, left: 40, right: 40 })
            } else {
              Scroll() {
                Column({ space: 8 }) {
                  Row() {
                    Text(`已安装 ${this.sourceNames.length} 个插件`)
                      .fontSize(12)
                      .fontColor(this.themeTextSecondary)
                      .layoutWeight(1)
                      .padding({ left: 4, bottom: 4, top: 4 })

                    Row() {
                      SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                        .fontSize(18)
                        .fontColor([this.themePrimary])
                    }
                    .width(32)
                    .height(32)
                    .justifyContent(FlexAlign.Center)
                    .backgroundColor(this.isDarkMode ? '#333333' : '#F0F0F0')
                    .borderRadius(8)
                    .bindMenu(this.buildMoreMenuItems())
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)

                  ForEach(this.sourceNames, (name: string, index: number) => {
                    this.PluginItem(name, index)
                  })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 4, bottom: 100 })
              }
              .layoutWeight(1)
              .scrollBar(BarState.Auto)
              .edgeEffect(EdgeEffect.Spring)
              .align(Alignment.Top)
            }
          }
          .width('100%')
          .height('100%')

          // 页面3: 自检日志
          Column() {
            if (this.testResults.length === 0 && this.testingSource.length === 0 && this.testLogHistory.length === 0) {
              Column({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.waveform'))
                  .fontSize(48)
                  .fontColor([this.themeTextSecondary])
                  .opacity(0.3)
                Text('暂无自检记录')
                  .fontSize(16)
                  .fontColor(this.themeTextPrimary)
                  .fontWeight(FontWeight.Medium)
                Text('点击「订阅导入」页的「自检」按钮\n或使用「插件管理」的「全部自检」')
                  .fontSize(13)
                  .fontColor(this.themeTextSecondary)
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .padding({ left: 40, right: 40 })
            } else {
              Scroll() {
                Column({ space: 12 }) {
                  // 当前自检进行中
                  if (this.testResults.length > 0 || this.testingSource.length > 0) {
                    Column() {
                      Row() {
                        Column({ space: 2 }) {
                          Text(this.testingSource.length > 0 ? `正在自检: ${this.testingSource}` : '音源自检')
                            .fontSize(15)
                            .fontColor(this.themeTextPrimary)
                            .fontWeight(FontWeight.Medium)
                          Text('搜索 → 播放链接 → 歌词 → 封面')
                            .fontSize(11)
                            .fontColor(this.themeTextSecondary)
                        }
                        .alignItems(HorizontalAlign.Start)
                        .layoutWeight(1)

                        if (this.testingSource.length > 0) {
                          LoadingProgress()
                            .width(18)
                            .height(18)
                            .color(this.themePrimary)
                            .margin({ right: 8 })
                        }

                        Row() {
                          SymbolGlyph($r('sys.symbol.share'))
                            .fontSize(16)
                            .fontColor([this.themeTextPrimary])
                        }
                        .width(30)
                        .height(30)
                        .justifyContent(FlexAlign.Center)
                        .onClick(() => {
                          this.shareTestLog()
                        })
                      }
                      .width('100%')
                      .padding({ bottom: 8 })

                      Column({ space: 3 }) {
                        ForEach(this.testResults, (line: string) => {
                          Text(line)
                            .fontSize(12)
                            .fontColor(this.testLineColor(line))
                            .width('100%')
                            .maxLines(3)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                        })
                      }
                      .width('100%')
                      .alignItems(HorizontalAlign.Start)

                      if (this.testingSource.length === 0 && this.sourceTestStatus.size > 0) {
                        Column({ space: 4 }) {
                          Divider().color(this.themePlaceholder).margin({ top: 8, bottom: 4 })
                          ForEach(this.sourceNames, (name: string) => {
                            Row() {
                              Text(name)
                                .fontSize(12)
                                .fontColor(this.themeTextPrimary)
                                .layoutWeight(1)
                                .maxLines(1)
                                .textOverflow({ overflow: TextOverflow.Ellipsis })
                              if (this.sourceTestStatus.get(name) === 'ok') {
                                Text('✓ 可用')
                                  .fontSize(11)
                                  .fontColor('#2E7D32')
                              } else if (this.sourceTestStatus.get(name) === 'partial') {
                                Text('⚠ 部分可用')
                                  .fontSize(11)
                                  .fontColor('#FF9800')
                              } else if (this.sourceTestStatus.get(name) === 'fail') {
                                Text('✗ 不可用')
                                  .fontSize(11)
                                  .fontColor(this.themeDanger)
                              }
                            }
                            .width('100%')
                          })
                        }
                      }
                    }
                    .width('100%')
                    .padding(16)
                    .backgroundColor(this.themeCardBg)
                    .borderRadius(14)
                  }

                  // 历史自检记录（最多3份）
                  if (this.testLogHistory.length > 0) {
                    Column({ space: 6 }) {
                      ForEach(this.testLogHistory, (record: TestLogRecord) => {
                        Row({ space: 8 }) {
                          Column({ space: 1 }) {
                            Text(`${record.timestamp}`)
                              .fontSize(11)
                              .fontColor(this.themeTextSecondary)
                            Text(`自检${record.pluginCount}个，可用${record.okCount}个，失效${record.failCount}个`)
                              .fontSize(12)
                              .fontColor(this.themeTextPrimary)
                              .fontWeight(FontWeight.Medium)
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                          }
                          .alignItems(HorizontalAlign.Start)
                          .layoutWeight(1)

                          Row() {
                            SymbolGlyph($r('sys.symbol.share'))
                              .fontSize(13)
                              .fontColor([this.themePrimary])
                          }
                          .width(26)
                          .height(26)
                          .justifyContent(FlexAlign.Center)
                          .onClick(() => {
                            this.shareHistoryLog(record)
                          })
                        }
                        .width('100%')
                        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                        .backgroundColor(this.themeCardBg)
                        .borderRadius(10)
                      })
                    }
                    .width('100%')
                  }
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 8, bottom: 100 })
              }
              .layoutWeight(1)
              .scrollBar(BarState.Auto)
              .edgeEffect(EdgeEffect.Spring)
              .align(Alignment.Top)
            }
          }
          .width('100%')
          .height('100%')
        }
        .layoutWeight(1)
        .index(this.currentTabIndex)
        .indicator(false)
        .loop(false)
        .onChange((index: number) => {
          this.currentTabIndex = index
          this.chipSelectedIndex = [index]
        })

        // 插件多选模式底部操作栏
        if (this.batchDeleteMode) {
          Row({ space: 8 }) {
            Button('全选')
              .fontSize(13)
              .height(36)
              .layoutWeight(1)
              .fontColor(this.themeTextPrimary)
              .backgroundColor(this.themePlaceholder)
              .borderRadius(10)
              .onClick(() => { this.toggleSelectAll() })

            Button('启用')
              .fontSize(13)
              .height(36)
              .layoutWeight(1)
              .fontColor(Color.White)
              .backgroundColor(this.themePrimary)
              .borderRadius(10)
              .onClick(() => { this.batchSetSelectedEnabled(true) })

            Button('关闭')
              .fontSize(13)
              .height(36)
              .layoutWeight(1)
              .fontColor(this.themeTextPrimary)
              .backgroundColor(this.themePlaceholder)
              .borderRadius(10)
              .onClick(() => { this.batchSetSelectedEnabled(false) })

            Button('删除')
              .fontSize(13)
              .height(36)
              .layoutWeight(1)
              .fontColor(Color.White)
              .backgroundColor(this.themeDanger)
              .borderRadius(10)
              .onClick(() => { this.batchDeleteSelected() })

            Button('完成')
              .fontSize(13)
              .height(36)
              .layoutWeight(1)
              .fontColor(this.themeTextPrimary)
              .backgroundColor(this.themeCardBg)
              .borderRadius(10)
              .borderWidth(1)
              .borderColor(this.themePlaceholder)
              .onClick(() => { this.exitBatchDeleteMode() })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 10 })
          .backgroundColor(this.themeCardBg)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themeBg)
    }
    .width('100%')
    .height('100%')
  }
}
