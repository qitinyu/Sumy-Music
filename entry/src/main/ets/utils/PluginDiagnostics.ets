export interface PluginDiagnosticEntry {
  time: number
  level: string
  source: string
  action: string
  message: string
  detail?: string
}

const MAX_ENTRIES: number = 500

export class PluginDiagnostics {
  private static entries: PluginDiagnosticEntry[] = []

  static record(level: string, source: string, action: string, message: string, detail: string = ''): void {
    const item: PluginDiagnosticEntry = {
      time: Date.now(),
      level: level,
      source: source,
      action: action,
      message: message
    }
    if (detail.length > 0) item.detail = detail
    PluginDiagnostics.entries.push(item)
    if (PluginDiagnostics.entries.length > MAX_ENTRIES) {
      PluginDiagnostics.entries.splice(0, PluginDiagnostics.entries.length - MAX_ENTRIES)
    }
    const prefix = `[PluginDiag][${source || 'unknown'}][${action || 'runtime'}]`
    if (level === 'error') {
      console.error(`${prefix} ${message}`, detail)
    } else if (level === 'warn') {
      console.warn(`${prefix} ${message}`, detail)
    } else {
      console.info(`${prefix} ${message}`, detail)
    }
  }

  static info(source: string, action: string, message: string, detail: string = ''): void {
    PluginDiagnostics.record('info', source, action, message, detail)
  }

  static warn(source: string, action: string, message: string, detail: string = ''): void {
    PluginDiagnostics.record('warn', source, action, message, detail)
  }

  static error(source: string, action: string, message: string, detail: string = ''): void {
    PluginDiagnostics.record('error', source, action, message, detail)
  }

  static clear(): void {
    PluginDiagnostics.entries = []
  }

  static snapshot(source: string = ''): PluginDiagnosticEntry[] {
    if (source.length === 0) return PluginDiagnostics.entries.slice()
    return PluginDiagnostics.entries.filter((item: PluginDiagnosticEntry) => item.source === source)
  }

  static exportJson(source: string = ''): string {
    return JSON.stringify({
      exportedAt: new Date().toISOString(),
      source: source,
      entries: PluginDiagnostics.snapshot(source)
    }, null, 2)
  }

  /**
   * 导出可读的纯文本日志（供系统分享/复制）。
   * 格式：[HH:MM:SS] [级别] [来源/动作] 消息，详情缩进折行。
   */
  static getLogText(source: string = ''): string {
    const list: PluginDiagnosticEntry[] = PluginDiagnostics.snapshot(source)
    if (list.length === 0) {
      return '(暂无诊断日志)'
    }
    const lines: string[] = []
    for (let i = 0; i < list.length; i++) {
      const e: PluginDiagnosticEntry = list[i]
      const d: Date = new Date(e.time)
      const hh: string = d.getHours().toString().padStart(2, '0')
      const mm: string = d.getMinutes().toString().padStart(2, '0')
      const ss: string = d.getSeconds().toString().padStart(2, '0')
      let line: string = `[${hh}:${mm}:${ss}] [${e.level}] [${e.source || 'unknown'}/${e.action || 'runtime'}] ${e.message}`
      if (e.detail !== undefined && e.detail.length > 0) {
        line += `\n    ${e.detail}`
      }
      lines.push(line)
    }
    return lines.join('\n')
  }
}
