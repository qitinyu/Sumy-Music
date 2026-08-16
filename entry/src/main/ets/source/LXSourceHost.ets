/**
 * 音源引擎宿主
 * 常驻挂载于主页面，负责初始化音源脚本存储目录、恢复上次选中的音源。
 * 引擎（隐藏 WebView）在存在音源时才挂载，保证 WebView 页面处于新鲜加载状态。
 * 适配自 123 项目 LXSourceHost
 */
import { LXSourceEngine } from './LXSourceEngine';
import { lxSourceManager } from './LXSourceManager';
import { DatabaseHelper } from '../database/DatabaseHelper';

@Component
export struct LXSourceHost {
  @StorageLink('lxActiveSource') @Watch('onActiveSourceChanged') lxActiveSource: string = '';
  @State showEngine: boolean = false;

  async aboutToAppear(): Promise<void> {
    let context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      lxSourceManager.setFilesDir(context.filesDir);
    }
    // 恢复上次选中的音源：优先 AppStorage（音源管理开关设置），其次数据库
    try {
      const fromStorage: string = AppStorage.get<string>('lxActiveSource') || '';
      if (fromStorage.length > 0) {
        AppStorage.setOrCreate('lxActiveSource', fromStorage);
      } else {
        const saved: string = await DatabaseHelper.getInstance().getSetting('lxActiveSource');
        if (saved.length > 0) {
          AppStorage.setOrCreate('lxActiveSource', saved);
        }
      }
    } catch (_e) {
      // ignore
    }
    // 始终渲染引擎（无源时引擎内部 destroy 即可）
    this.showEngine = true;
  }

  onActiveSourceChanged(): void {
    // 只要有变化就渲染引擎（无论是否有源）
    this.showEngine = true;
  }

  build() {
    Column() {
      if (this.showEngine) {
        LXSourceEngine()
      }
    }
    .width(1)
    .height(1)
    .opacity(0)
  }
}
