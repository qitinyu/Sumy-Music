/**
 * 隐藏 WebView 宿主：承载 JS 音源引擎（js_engine.html）
 * 生命周期：首次 onPageEnd → JsPluginEngine.init（注册 __host 桥 + refresh）
 *          二次 onPageEnd（refresh 后）→ JsPluginEngine.markReady
 */
import { webview } from '@kit.ArkWeb';
import { JsPluginEngine } from '../utils/JsPluginEngine';

@Component
export struct JsEngineHost {
  private controller: webview.WebviewController = new webview.WebviewController();
  private loaded: boolean = false;

  build() {
    Web({ src: $rawfile('js_engine.html'), controller: this.controller })
      .width(1)
      .height(1)
      .position({ x: -100, y: -100 })
      .opacity(0)
      .javaScriptAccess(true)
      .domStorageAccess(false)
      .onPageEnd(() => {
        if (!this.loaded) {
          this.loaded = true;
          JsPluginEngine.init(this.controller);
        } else {
          JsPluginEngine.markReady();
        }
      })
      .onErrorReceive((event) => {
        console.error('[JsEngineHost] error: ' + JSON.stringify(event));
      })
  }
}
