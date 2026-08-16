// PluginManagerPage.ets - JS 插件管理
// 支持导入/查看/删除 JS 插件（标准格式）

import { SourceManager } from '../utils/SourceManager'
import { MusicApi } from '../utils/MusicApi'
import { DatabaseHelper } from '../database/DatabaseHelper'
import { picker } from '@kit.CoreFileKit'
import { promptAction } from '@kit.ArkUI'
import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import type { SongInfo } from '../model/MusicModel'
import { JsPluginEngine } from '../utils/JsPluginEngine'

/** 自检步骤详情 */
interface TestDetail {
  step: string
  status: 'success' | 'failure' | 'info' | 'pending'
  message: string
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
  @State showImportSheet: boolean = false
  @State importUrl: string = ''
  @State showUrlInput: boolean = false
  @State isImporting: boolean = false
  @State importProgress: string = ''
  @State enabledMap: Record<string, boolean> = {}
  // 批量删除模式
  @State batchDeleteMode: boolean = false
  @State selectedForDelete: Set<string> = new Set()
  // 音源自测（验证闭环：搜索 → 取链 → 歌词 → 封面）
  @State testingSource: string = ''
  @State testResults: string[] = []
  @State showTestDialog: boolean = false
  // 增强自检详情：每个音源保存详细步骤结果
  @State testDetailMap: Record<string, TestDetail[]> = {}
  // 每个音源的自检可用状态（''=未测，'ok'=可用，'fail'=不可用，'partial'=部分可用）
  @State sourceTestStatus: Map<string, string> = new Map()
  @State expandedTestSource: string = ''
  onBack?: () => void

  async aboutToAppear() {
    await this.loadSources()
    await this.loadEnabledStates()
    // 如果没有激活的音源，自动选择第一个可用的
    const active = AppStorage.get<string>('lxActiveSource') || ''
    if (!active && this.sourceNames.length > 0) {
      AppStorage.setOrCreate('lxActiveSource', this.sourceNames[0])
      console.info(`[PluginManager] 自动激活音源: ${this.sourceNames[0]}`)
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

  // ===== 音源自测（验证闭环） =====
  // 跑真实链路：搜索「海阔天空」→ 取第一首播放链接 → 歌词 → 封面，结果实时显示
  private async runSourceTest(name: string): Promise<void> {
    // 强制激活新引擎
    const active = AppStorage.get<string>('lxActiveSource') || ''
    if (active !== name) {
      AppStorage.setOrCreate('lxActiveSource', name)
      console.info(`[PluginManager] 激活音源: ${name}`)
    }
    this.testingSource = name
    this.testResults = []
    this.showTestDialog = true
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

    // 1. 搜索（25s 超时截断，避免死源拖死自测）
    push(`搜索「海阔天空」`, false)
    push('搜索中…', true)
    let songs: SongInfo[] = []
    // 优先用插件自身搜索（v1/MusicFree 插件走 JsPluginEngine），真实验证插件；
    // v3 插件无 musicSearch 或无结果时回退内置五源
    try {
      songs = await SourceManager.search(name, '海阔天空')
    } catch (_e) {
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
    if (songs.length === 0) {
      push(`搜索无结果${MusicApi.lastError.length > 0 ? '：' + MusicApi.lastError : ''}`, true)
      this.sourceTestStatus.set(name, 'fail')
      this.testingSource = ''
      return
    }
    push(`搜索到 ${songs.length} 首`, true)
    const first: SongInfo = songs[0]
    push(`示例：${first.songName} - ${first.artist}`, true)

    // 2. 播放链接
    push('获取播放链接', false)
    let urlOk = false
    const url: string = await MusicApi.getPlayUrl(first.songId, first.source, first)
    if (url && url.length > 0) {
      push('播放链接可用', true)
      first.playUrl = url
      urlOk = true
    } else {
      push('播放链接获取失败', true)
    }

    // 3. 歌词
    push('获取歌词', false)
    const lrc: string = await MusicApi.getLyrics(first.songId, first.source, first)
    if (lrc && lrc.length > 0) {
      push(`歌词 ${lrc.length} 字符`, true)
    } else {
      push('歌词为空', true)
    }

    // 4. 封面
    push('封面字段', false)
    if (first.coverUrl && first.coverUrl.length > 0) {
      push('封面已提供', true)
    } else {
      push('封面字段为空（播放时再补）', true)
    }

    // 记录该源的可用状态
    if (urlOk) {
      this.sourceTestStatus.set(name, 'ok')
    } else {
      this.sourceTestStatus.set(name, 'partial')
    }
    push('自测结束')
    this.testingSource = ''
  }

  private async runAllSourceTests(): Promise<void> {
    if (this.sourceNames.length === 0) {
      this.showToastMsg('暂无 JS 插件')
      return
    }
    this.testResults = []
    this.showTestDialog = true
    // 清空旧状态
    this.sourceTestStatus = new Map()
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
      else if (st === 'partial') label = '⚠️ 部分可用（搜索成功但无播放链接）'
      else if (st === 'fail') label = '❌ 不可用'
      summary.push(`${i + 1}. ${name}：${label}`)
    }
    this.testResults = summary
    this.showToastMsg('全部音源自测完成')
  }

  private testLineColor(line: string): string {
    // 主步骤（数字开头）：主题色
    if (/^\d+\./.test(line)) return this.themePrimary
    // 子步骤（- 开头）：失败/成功/普通
    if (line.indexOf('失败') >= 0 || line.indexOf('无结果') >= 0 || line.indexOf('为空') >= 0) return this.themeDanger
    if (line.indexOf('可用') >= 0 || line.indexOf('已提供') >= 0) return '#2E7D32'
    return this.themeTextSecondary
  }

  async importFromFile() {
    try {
      const docPicker = new picker.DocumentViewPicker()
      const uris = await docPicker.select({ maxSelectNumber: 50 })
      if (!uris || uris.length === 0) return

      let successCount = 0
      let failCount = 0
      for (let i = 0; i < uris.length; i++) {
        const name = await SourceManager.importFromFile(uris[i])
        if (name) {
          successCount++
        } else {
          failCount++
        }
      }

      await this.loadSources()
      await this.loadEnabledStates()

      if (uris.length === 1) {
        if (successCount > 0) {
          this.showToastMsg(`已导入音源: ${this.sourceNames[this.sourceNames.length - 1]}`)
        } else {
          this.showToastMsg('导入失败，请检查文件格式')
        }
      } else {
        this.showToastMsg(`成功导入 ${successCount} 个音源${failCount > 0 ? `，${failCount} 个失败` : ''}`)
      }
    } catch (_e) {
      this.showToastMsg('导入失败')
    }
  }

  async importFromUrl() {
    const url = this.importUrl.trim()
    if (!url) {
      this.showToastMsg('请输入 URL')
      return
    }
    try {
      this.isImporting = true
      this.importProgress = '正在下载...'
      this.importUrl = ''
      this.showUrlInput = false

      const httpRequest = http.createHttp()
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        readTimeout: 10000,
        connectTimeout: 10000,
      })
      httpRequest.destroy()
      let text = ''
      const result = response.result
      if (typeof result === 'string') {
        text = result
      } else if (result instanceof ArrayBuffer) {
        const decoder = util.TextDecoder.create('utf-8')
        text = decoder.decodeWithStream(new Uint8Array(result))
      }
      if (!text) {
        this.showToastMsg('下载失败')
        this.isImporting = false
        return
      }

      // 检测是否为订阅格式 (包含 plugins 数组)
      let parsed: Record<string, Object> | null = null
      try {
        parsed = JSON.parse(text) as Record<string, Object>
      } catch (_e) {}

      if (parsed !== null && parsed['plugins'] !== undefined && parsed['plugins'] instanceof Array) {
        // 订阅格式：批量导入
        const plugins = parsed['plugins'] as Object[]
        this.importProgress = `发现 ${plugins.length} 个插件，正在导入...`
        const results = await SourceManager.importFromSubscriptionJson(text)

        // 统计结果
        let successCount = 0
        let failCount = 0
        const failNames: string[] = []
        for (let i = 0; i < results.length; i++) {
          if (results[i].success) {
            successCount++
          } else {
            failCount++
            if (results[i].error) {
              failNames.push(`${results[i].name}: ${results[i].error}`)
            }
          }
        }

        this.isImporting = false
        await this.loadSources()

        // 显示结果
        let msg = `成功导入 ${successCount} 个 JS 插件`
        if (failCount > 0) {
          msg += `，${failCount} 个失败`
          if (failNames.length > 0 && failNames.length <= 3) {
            msg += `\n${failNames.join('\n')}`
          }
        }
        this.showImportResult(msg)
      } else {
        // 尝试作为 JS 插件导入
        const name: string = await SourceManager.autoDetectAndImport(text, url.substring(url.lastIndexOf('/') + 1).replace(/\.[^.]+$/, ''))
        this.isImporting = false
        if (name) {
          this.showToastMsg(`已导入 JS 插件: ${name}`)
          await this.loadSources()
        } else {
          this.showToastMsg('不支持的格式，请输入 JS 插件或订阅链接')
        }
      }
    } catch (_e) {
      this.isImporting = false
      this.showToastMsg('下载失败，请检查 URL')
    }
  }

  showImportResult(msg: string) {
    promptAction.showDialog({
      title: '导入结果',
      message: msg,
      buttons: [
        { text: '确定', color: this.themePrimary },
      ],
    })
  }

  getPluginType(name: string): string {
    const config = SourceManager.getConfig(name)
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
      this.showToastMsg('暂无音源')
      return
    }
    for (let i = 0; i < this.sourceNames.length; i++) {
      await this.setSourceEnabled(this.sourceNames[i], true)
    }
    this.showToastMsg(`已开启全部 ${this.sourceNames.length} 个音源`)
  }

  // 一键关闭所有源
  async disableAllSources() {
    if (this.sourceNames.length === 0) {
      this.showToastMsg('暂无音源')
      return
    }
    for (let i = 0; i < this.sourceNames.length; i++) {
      await this.setSourceEnabled(this.sourceNames[i], false)
    }
    this.showToastMsg(`已关闭全部 ${this.sourceNames.length} 个音源`)
  }

  // 进入批量删除模式
  enterBatchDeleteMode() {
    if (this.sourceNames.length === 0) {
      this.showToastMsg('暂无音源')
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
      this.showToastMsg('请先勾选要删除的音源')
      return
    }
    const count = this.selectedForDelete.size
    promptAction.showDialog({
      title: '批量删除',
      message: `确定要删除选中的 ${count} 个音源吗？`,
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
        this.showToastMsg(`已删除 ${count} 个音源`)
      }
    })
  }

  @Builder PluginItem(name: string) {
    Row({ space: 12 }) {
      // 批量删除模式下显示左侧勾选圆圈
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

      Row() {
        SymbolGlyph($r('sys.symbol.play_circle'))
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(44)
      .height(44)
      .borderRadius(12)
      .backgroundColor(this.themePrimary)
      .justifyContent(FlexAlign.Center)
      .flexShrink(0)

      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(name)
            .fontSize(15)
            .fontColor(this.themeTextPrimary)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          // 自检状态徽章
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

      // 非批量删除模式下显示自测按钮与启用开关
      if (!this.batchDeleteMode) {
        if (this.testingSource === name) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(this.themePrimary)
            .flexShrink(0)
        } else {
          Row() {
            SymbolGlyph($r('sys.symbol.waveform'))
              .fontSize(16)
              .fontColor([this.themeTextSecondary])
          }
          .width(30)
          .height(30)
          .justifyContent(FlexAlign.Center)
          .flexShrink(0)
          .onClick(() => {
            this.runSourceTest(name)
          })
        }
        Toggle({ type: ToggleType.Switch, isOn: this.isSourceEnabled(name) })
          .selectedColor(this.themePrimary)
          .width(40)
          .onChange((isOn: boolean) => {
            this.setSourceEnabled(name, isOn)
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

      Text(this.batchDeleteMode ? `已选 ${this.selectedForDelete.size} 项` : '插件管理')
        .fontSize(17)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)

          // 批量删除模式下的操作栏
          if (this.batchDeleteMode) {
            Row() {
              SymbolGlyph(this.selectedForDelete.size === this.sourceNames.length && this.sourceNames.length > 0
                ? $r('sys.symbol.checkmark_circle_fill')
                : $r('sys.symbol.checkmark_circle'))
                .fontSize(20)
                .fontColor([this.themeTextPrimary])
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.toggleSelectAll() })

            Row() {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(20)
                .fontColor([this.themeDanger])
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.batchDeleteSelected() })
          } else {
            // 正常模式：一键自测 / 批量导入 / 一键开启 / 一键关闭 / 批量删除
            Row() {
              SymbolGlyph($r('sys.symbol.waveform'))
                .fontSize(20)
                .fontColor([this.themePrimary])
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.runAllSourceTests() })

            Row() {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(20)
                .fontColor([this.themeTextPrimary])
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.showImportSheet = true })

            Row() {
              SymbolGlyph($r('sys.symbol.checkmark_circle'))
                .fontSize(20)
                .fontColor([this.themeTextPrimary])
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.enableAllSources() })

            Row() {
              SymbolGlyph($r('sys.symbol.xmark_circle'))
                .fontSize(20)
                .fontColor([this.themeTextPrimary])
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.disableAllSources() })

            Row() {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(20)
                .fontColor([this.themeTextPrimary])
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.enterBatchDeleteMode() })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        // Hint
        if (this.sourceNames.length === 0) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.folder'))
              .fontSize(48)
              .fontColor([this.themeTextSecondary])
              .opacity(0.3)
            Text('暂无 JS 插件')
              .fontSize(16)
              .fontColor(this.themeTextPrimary)
              .fontWeight(FontWeight.Medium)
            Text('点击右上角「导入」添加 JS 插件\n支持标准格式的 .js 插件和在线订阅')
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
          // Plugin list
          Scroll() {
            Column({ space: 8 }) {
              Text('已安装 ${this.sourceNames.length} 个 JS 插件')
                .fontSize(12)
                .fontColor(this.themeTextSecondary)
                .width('100%')
                .padding({ left: 4, bottom: 4, top: 4 })

              ForEach(this.sourceNames, (name: string) => {
                this.PluginItem(name)
              })
            }
            .width('100%')
            // 底部留出增量空间，避免最后一个音源被底部栏遮挡
            .padding({ left: 16, right: 16, top: 4, bottom: 120 })
          }
          .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themeBg)

      // Loading overlay
      if (this.isImporting) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.themePrimary)
          Text(this.importProgress)
            .fontSize(14)
            .fontColor(this.themeTextSecondary)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.isDarkMode ? '#000000CC' : '#FFFFFFCC')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      // URL input overlay
      if (this.showUrlInput) {
        Column() {
          Column({ space: 16 }) {
            Text('输入链接')
              .fontSize(17)
              .fontColor(this.themeTextPrimary)
              .fontWeight(FontWeight.Bold)
              .width('100%')

            TextInput({ placeholder: '粘贴 JS 插件链接或订阅链接', text: this.importUrl })
              .width('100%')
              .height(44)
              .fontSize(14)
              .backgroundColor(this.themePlaceholder)
              .borderRadius(10)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                this.importUrl = value
              })
              .onSubmit(() => {
                this.importFromUrl()
              })

            Row({ space: 12 }) {
              Button('取消')
                .fontSize(14)
                .fontColor(this.themeTextSecondary)
                .backgroundColor(this.themePlaceholder)
                .borderRadius(10)
                .layoutWeight(1)
                .onClick(() => {
                  this.showUrlInput = false
                  this.importUrl = ''
                })

              Button('导入')
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor(this.themePrimary)
                .borderRadius(10)
                .layoutWeight(1)
                .onClick(() => {
                  this.importFromUrl()
                })
            }
            .width('100%')
          }
          .width('80%')
          .padding(20)
          .backgroundColor(this.themeCardBg)
          .borderRadius(16)
          .shadow({ radius: 20, color: '#00000020', offsetY: 4 })
          .onClick(() => {})
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#00000050')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.showUrlInput = false
          this.importUrl = ''
        })
      }

      // Import sheet
      Row()
        .width(1)
        .height(1)
        .bindSheet($$this.showImportSheet, this.ImportSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: true,
          backgroundColor: this.themeCardBg,
          onDisappear: () => { this.showImportSheet = false },
        })

      // 自测结果 sheet
      Row()
        .width(1)
        .height(1)
        .bindSheet($$this.showTestDialog, this.SelfTestSheet(), {
          height: 420,
          dragBar: true,
          showClose: true,
          backgroundColor: this.themeCardBg,
          onDisappear: () => { this.showTestDialog = false },
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SelfTestSheet() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('音源自测')
          .fontSize(17)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Bold)
        Text('搜索 → 播放链接 → 歌词 → 封面')
          .fontSize(12)
          .fontColor(this.themeTextSecondary)
      }
      .width('100%')

      Scroll() {
        Column({ space: 4 }) {
          ForEach(this.testResults, (line: string) => {
            Text(line)
              .fontSize(13)
              .fontColor(this.testLineColor(line))
              .width('100%')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
    }
    .padding(20)
    .width('100%')
    .height('100%')
  }

  @Builder
  ImportSheet() {
    Column({ space: 16 }) {
      Text('导入 JS 插件')
        .fontSize(17)
        .fontColor(this.themeTextPrimary)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      // File import
      Row({ space: 12 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(22)
            .fontColor([Color.White])
        }
        .width(44)
        .height(44)
        .borderRadius(12)
        .backgroundColor(this.themePrimary)
        .justifyContent(FlexAlign.Center)
        .flexShrink(0)

        Column({ space: 4 }) {
          Text('从文件导入')
            .fontSize(16)
            .fontColor(this.themeTextPrimary)
            .fontWeight(FontWeight.Medium)
          Text('选择本地的 .js 插件文件')
            .fontSize(12)
            .fontColor(this.themeTextSecondary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(14)
      .backgroundColor(this.themePlaceholder)
      .borderRadius(12)
      .onClick(() => {
        this.showImportSheet = false
        this.importFromFile()
      })

      // URL import
      Row({ space: 12 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.link'))
            .fontSize(22)
            .fontColor([Color.White])
        }
        .width(44)
        .height(44)
        .borderRadius(12)
        .backgroundColor('#FF9800')
        .justifyContent(FlexAlign.Center)
        .flexShrink(0)

        Column({ space: 4 }) {
          Text('从 URL 导入')
            .fontSize(16)
            .fontColor(this.themeTextPrimary)
            .fontWeight(FontWeight.Medium)
          Text('输入 JS 插件或订阅链接')
            .fontSize(12)
            .fontColor(this.themeTextSecondary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(14)
      .backgroundColor(this.themePlaceholder)
      .borderRadius(12)
      .onClick(() => {
        this.showImportSheet = false
        this.showUrlInput = true
      })

      Column().height(8)
    }
    .padding(24)
  }
}