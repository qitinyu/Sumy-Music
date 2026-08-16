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
  private resolving: boolean = false

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
      return
    }
    // 同一来源已解析成功：跳过，避免重复解析导致封面闪烁/消失
    if (url === this.resolvedSource) {
      return
    }
    if (this.resolving) {
      return
    }
    this.resolving = true
    CoverFetcher.resolve(url).then((resolved: string) => {
      this.resolving = false
      if (this.url === url && resolved.length > 0) {
        this.resolvedSource = url
        this.resolvedUrl = resolved
      }
    }).catch((_e: Error) => {
      this.resolving = false
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
