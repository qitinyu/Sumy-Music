import { fileIo } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { CoverFetcher } from './CoverFetcher'
import { CloudTagEnricher } from './CloudTagEnricher'
import { JsPluginEngine } from './JsPluginEngine'

export interface CacheInfo {
  bytes: number
  files: number
}

export class CacheManager {
  private static context: common.UIAbilityContext | null = null

  static init(context: common.UIAbilityContext): void {
    CacheManager.context = context
  }

  static async getInfo(): Promise<CacheInfo> {
    const ctx = CacheManager.context
    if (!ctx) return { bytes: 0, files: 0 }
    const cacheInfo = await CacheManager.scanDir(ctx.cacheDir)
    const coverInfo = await CacheManager.scanDir(ctx.filesDir + '/covers')
    return {
      bytes: cacheInfo.bytes + coverInfo.bytes,
      files: cacheInfo.files + coverInfo.files
    }
  }

  static async clear(): Promise<void> {
    const ctx = CacheManager.context
    if (!ctx) return
    await CacheManager.clearDir(ctx.cacheDir, false)
    await CacheManager.clearDir(ctx.filesDir + '/covers', false)
    CoverFetcher.getInstance().clearMemoryCache()
    CloudTagEnricher.clearMemoryCache()
    JsPluginEngine.clearV3SourcesCache()
  }

  static formatBytes(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`
    return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`
  }

  private static async scanDir(path: string): Promise<CacheInfo> {
    let bytes = 0
    let files = 0
    try {
      const entries = await fileIo.listFile(path)
      for (let i = 0; i < entries.length; i++) {
        const child = path + '/' + entries[i]
        const fileStat = await fileIo.stat(child)
        if (fileStat.isDirectory()) {
          const info = await CacheManager.scanDir(child)
          bytes += info.bytes
          files += info.files
        } else {
          bytes += fileStat.size
          files++
        }
      }
    } catch (_e) {
    }
    return { bytes, files }
  }

  private static async clearDir(path: string, removeSelf: boolean): Promise<void> {
    try {
      const entries = await fileIo.listFile(path)
      for (let i = 0; i < entries.length; i++) {
        const child = path + '/' + entries[i]
        const fileStat = await fileIo.stat(child)
        if (fileStat.isDirectory()) {
          await CacheManager.clearDir(child, true)
        } else {
          try { await fileIo.unlink(child) } catch (_e) {}
        }
      }
      if (removeSelf) {
        try { await fileIo.rmdir(path) } catch (_e) {}
      }
    } catch (_e) {
    }
  }
}
