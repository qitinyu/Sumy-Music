// PluginManagerPage.ets - 音源插件管理
// 支持导入/查看/删除音源插件

import { SourceManager } from '../utils/SourceManager'
import { picker } from '@kit.CoreFileKit'
import { promptAction } from '@kit.ArkUI'
import { pasteboard } from '@kit.BasicServicesKit'
import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'

@Component
export struct PluginManagerPage {
  @StorageProp('theme_primary') themePrimary: string = '#007DFF'
  @StorageProp('theme_bg') themeBg: string = '#F8F8FA'
  @StorageProp('theme_cardBg') themeCardBg: string = '#FFFFFF'
  @StorageProp('theme_textPrimary') themeTextPrimary: string = '#1A1A1A'
  @StorageProp('theme_textSecondary') themeTextSecondary: string = '#999999'
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
  onBack?: () => void

  async aboutToAppear() {
    await this.loadSources()
    await this.loadEnabledStates()
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
  }

  showToastMsg(msg: string) {
    promptAction.showToast({ message: msg, duration: 2000 })
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

  async importFromClipboard() {
    try {
      const sysPaste = pasteboard.getSystemPasteboard()
      const data = await sysPaste.getData()
      const text = data.getPrimaryText()
      if (!text || text.length === 0) {
        this.showToastMsg('剪贴板为空')
        return
      }
      // 自动检测：先尝试 JSON，再尝试 JS 插件
      const name = await SourceManager.autoDetectAndImport(text, 'clipboard_plugin')
      if (name) {
        this.showToastMsg(`已导入音源: ${name}`)
        await this.loadSources()
      } else {
        this.showToastMsg('剪贴板内容不是有效的音源配置或 JS 插件')
      }
    } catch (_e) {
      this.showToastMsg('剪贴板内容不是有效的音源配置')
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
        let msg = `成功导入 ${successCount} 个音源`
        if (failCount > 0) {
          msg += `，${failCount} 个失败`
          if (failNames.length > 0 && failNames.length <= 3) {
            msg += `\n${failNames.join('\n')}`
          }
        }
        this.showImportResult(msg)
      } else if (parsed !== null && parsed['name'] !== undefined && parsed['search'] !== undefined && parsed['play'] !== undefined) {
        // 单个音源配置格式
        const name = await SourceManager.importConfig(text)
        this.isImporting = false
        if (name) {
          this.showToastMsg(`已导入音源: ${name}`)
          await this.loadSources()
        } else {
          this.showToastMsg('配置格式无效')
        }
      } else {
        // 尝试作为 JS 插件导入
        const name = await SourceManager.autoDetectAndImport(text, url.substring(url.lastIndexOf('/') + 1).replace(/\.[^.]+$/, ''))
        this.isImporting = false
        if (name) {
          this.showToastMsg(`已导入 JS 插件: ${name}`)
          await this.loadSources()
        } else {
          this.showToastMsg('不支持的格式，请输入音源配置、JS 插件或订阅链接')
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
    return (config && config.type === 'lx_plugin') ? 'JS 插件' : 'JSON 音源插件'
  }

  async deleteSource(name: string) {
    promptAction.showDialog({
      title: '删除音源',
      message: `确定要删除音源「${name}」吗？`,
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '删除', color: '#F44336' },
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
        { text: '取消', color: '#999999' },
        { text: '删除', color: '#F44336' },
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
        Text(name)
          .fontSize(15)
          .fontColor(this.themeTextPrimary)
          .fontWeight(FontWeight.Medium)
        Text(this.getPluginType(name))
          .fontSize(12)
          .fontColor(this.themeTextSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 非批量删除模式下显示启用开关
      if (!this.batchDeleteMode) {
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

          Text(this.batchDeleteMode ? `已选 ${this.selectedForDelete.size} 项` : '音源管理')
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
                .fontColor(['#F44336'])
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.batchDeleteSelected() })
          } else {
            // 正常模式：批量导入 / 一键开启 / 一键关闭 / 批量删除
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
              .fontColor(['#999999'])
              .opacity(0.3)
            Text('暂无音源插件')
              .fontSize(16)
              .fontColor(this.themeTextPrimary)
              .fontWeight(FontWeight.Medium)
            Text('点击右上角「导入」添加音源插件\n支持 JSON 音源配置和 JS 插件（LX Music 格式）')
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
              Text(`已安装 ${this.sourceNames.length} 个音源`)
                .fontSize(12)
                .fontColor(this.themeTextSecondary)
                .width('100%')
                .padding({ left: 4, bottom: 4, top: 4 })

              ForEach(this.sourceNames, (name: string) => {
                this.PluginItem(name)
              })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 4, bottom: 24 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
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
        .backgroundColor('#FFFFFFCC')
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

            TextInput({ placeholder: '粘贴音源配置或订阅链接', text: this.importUrl })
              .width('100%')
              .height(44)
              .fontSize(14)
              .backgroundColor('#F5F5F5')
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
                .backgroundColor('#F0F0F0')
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
          .backgroundColor(Color.White)
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
          backgroundColor: '#FFFFFF',
          onDisappear: () => { this.showImportSheet = false },
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ImportSheet() {
    Column({ space: 16 }) {
      Text('导入音源插件')
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
          Text('选择本地的 .json 音源配置或 .js 插件文件')
            .fontSize(12)
            .fontColor(this.themeTextSecondary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#F8F8FA')
      .borderRadius(12)
      .onClick(() => {
        this.showImportSheet = false
        this.importFromFile()
      })

      // Clipboard import
      Row({ space: 12 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(22)
            .fontColor([Color.White])
        }
        .width(44)
        .height(44)
        .borderRadius(12)
        .backgroundColor('#4CAF50')
        .justifyContent(FlexAlign.Center)
        .flexShrink(0)

        Column({ space: 4 }) {
          Text('从剪贴板导入')
            .fontSize(16)
            .fontColor(this.themeTextPrimary)
            .fontWeight(FontWeight.Medium)
          Text('粘贴 JSON 音源配置或 JS 插件代码')
            .fontSize(12)
            .fontColor(this.themeTextSecondary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#F8F8FA')
      .borderRadius(12)
      .onClick(() => {
        this.showImportSheet = false
        this.importFromClipboard()
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
          Text('输入音源配置或订阅链接（支持 LX Music 订阅）')
            .fontSize(12)
            .fontColor(this.themeTextSecondary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#F8F8FA')
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