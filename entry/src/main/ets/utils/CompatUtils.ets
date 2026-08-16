import { deviceInfo } from '@kit.BasicServicesKit'
import { util } from '@kit.ArkTS'

export class CompatUtils {
  private static _supportImmersive: boolean | null = null

  static isImmersiveSupported(): boolean {
    if (CompatUtils._supportImmersive === null) {
      // API 26+ 支持沉浸式材质（ImmersiveMaterial），低版本使用毛玻璃降级效果
      const apiVersion: number = deviceInfo.sdkApiVersion
      CompatUtils._supportImmersive = apiVersion >= 26
    }
    return CompatUtils._supportImmersive as boolean
  }

  /**
   * 按响应字符集正确解码文本（修复歌词/歌曲名乱码）
   * 策略：先按 UTF-8 解码，若出现替换字符 \uFFFD（说明原始数据非 UTF-8），
   * 或响应头声明 gbk/gb2312/gb18030 时，改用 GB18030/GBK 重新解码。
   * 适用于酷我 krc.php 等返回 GBK 编码歌词、但响应头未声明 charset 的接口。
   */
  static decodeResponse(bytes: Uint8Array, contentType?: string): string {
    if (bytes === undefined || bytes === null || bytes.length === 0) {
      return ''
    }
    const ct: string = (contentType ?? '').toLowerCase()
    const utf8Str: string = CompatUtils.tryDecode('utf-8', bytes)
    const hasReplacement: boolean = utf8Str.indexOf('\uFFFD') >= 0
    const gbkHint: boolean = ct.includes('gb2312') || ct.includes('gbk') || ct.includes('gb18030')
    if (!hasReplacement && !gbkHint) {
      return utf8Str
    }
    const candidates: string[] = gbkHint ? ['gb18030', 'gbk'] : ['gb18030', 'gbk']
    for (let i = 0; i < candidates.length; i++) {
      const s: string = CompatUtils.tryDecode(candidates[i], bytes)
      if (s.length > 0 && (gbkHint || s.indexOf('\uFFFD') < 0)) {
        return s
      }
    }
    return utf8Str
  }

  private static tryDecode(label: string, bytes: Uint8Array): string {
    try {
      const decoder: util.TextDecoder = util.TextDecoder.create(label)
      return decoder.decodeWithStream(bytes)
    } catch (_e) {
      return ''
    }
  }
}
