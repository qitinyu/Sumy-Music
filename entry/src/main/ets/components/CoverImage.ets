/**
 * CoverImage - 封面图片组件
 * 兼容 WebDAV 带账号密码（user:pass@）的封面 URL：由 CoverFetcher 下载为本地文件后显示。
 * 普通 URL/本地路径直接显示，加载中/失败显示占位图。
 * V2.1.3：解析改为幂等（同一来源只解析一次、解析期间保留旧封面），
 * 修复列表刷新/切歌后封面一闪而过又消失的问题。
 */
import { CoverFetcher } from '../utils/CoverFetcher'

@Component
export struct CoverImage {
  @Prop @Watch('onUrlChange') url: string = ''
  coverWidth: Length = 48
  coverHeight: Length = 48
  radius: Length = 8
  placeholder: Resource = $r('app.media.logo')

  @State resolvedUrl: string = ''
  private resolvedSource: string = ''
  private resolvingUrl: string = ''

  aboutToAppear(): void {
    this.resolve()
  }

  // 切歌/封面异步更新后 url 变化时重新解析
  onUrlChange(): void {
    this.resolve()
  }

  private resolve(): void {
    const url: string = this.url
    if (url.length === 0) {
      this.resolvedSource = ''
      this.resolvedUrl = ''
      this.resolvingUrl = ''
      return
    }
    // 同一来源已解析成功：跳过，避免重复解析导致封面闪烁/消失
    if (url === this.resolvedSource) {
      return
    }
    // 同一 URL 已在解析中：跳过，避免重复请求
    if (url === this.resolvingUrl) {
      return
    }
    // 记录正在解析的 URL（而非布尔锁）：
    // 切歌时旧封面的异步解析尚未返回，新 URL 会立即开始解析；
    // 旧结果返回时 resolvingUrl 已是新 URL，被丢弃，不再污染当前封面。
    this.resolvingUrl = url
    CoverFetcher.resolve(url).then((resolved: string) => {
      if (this.resolvingUrl !== url) {
        // 期间已切歌：丢弃旧结果，最新 URL 的解析会另行刷新
        return
      }
      this.resolvingUrl = ''
      if (this.url === url && resolved.length > 0) {
        this.resolvedSource = url
        this.resolvedUrl = resolved
      }
    }).catch((_e: Error) => {
      if (this.resolvingUrl === url) {
        this.resolvingUrl = ''
      }
    })
  }

  build() {
    if (this.resolvedUrl.length > 0) {
      this.CoverImageInner(this.resolvedUrl)
    } else if (this.url.length > 0) {
      this.CoverImageInner(this.url)
    } else {
      this.CoverImageInner(this.placeholder)
    }
  }

  @Builder
  CoverImageInner(source: ResourceStr) {
    Image(source)
      .width(this.coverWidth)
      .height(this.coverHeight)
      .borderRadius(this.radius)
      .objectFit(ImageFit.Cover)
      .backgroundColor('#E0E0E0')
      .alt(this.placeholder)
  }
}
