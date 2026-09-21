/**
 * 隐藏 WebView 宿主：承载 MusicFree 插件沙箱（mf_host.html）
 * 生命周期：mf_host.html 末尾调用 mfNative.markReady() → MFEngine.markReady
 *          onPageEnd 兜底再触发一次 markReady（幂等）
 * 协议：__mf.load / __mf.call → mfNative.onPluginResult；HTTP 走 mfNative.httpRequest
 */

import { webview } from '@kit.ArkWeb'
import { MFEngine } from '../utils/MFEngine'

@Component
export struct MFEngineHost {
  private controller: webview.WebviewController = new webview.WebviewController()

  aboutToAppear(): void {
    // 必须在组件创建时把 controller 绑定进引擎，否则所有 runCall 抛「沙箱未初始化」
    MFEngine.getInstance().attachController(this.controller)
  }

  build() {
    // 必须用 resource://rawfile/ 形式加载：$rawfile() 会破坏页面内相对路径（libs/*.js）的解析，
    // 导致沙箱依赖库全部加载失败（require('axios') 抛错、所有插件挂载失败）；?v=2 为缓存版本号
    Web({ src: 'resource://rawfile/mf_host.html?v=2', controller: this.controller })
      .width(1)
      .height(1)
      .position({ x: -100, y: -100 })
      .opacity(0)
      .javaScriptAccess(true)
      .domStorageAccess(false)
      .javaScriptProxy({
        object: MFEngine.getInstance().bridge,
        name: 'mfNative',
        methodList: ['onPluginResult', 'markReady', 'getUserVariables', 'httpRequest', 'log'],
        controller: this.controller,
      })
      .onPageEnd(() => {
        MFEngine.getInstance().markReady()
      })
      .onErrorReceive((event) => {
        console.error('[MFEngineHost] error: ' + JSON.stringify(event))
      })
  }
}
