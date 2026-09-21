/**
 * PlayLog - 统一的播放/音源日志工具
 *
 * 所有播放、取链、歌词、封面、自检的关键节点都应调用本工具记录日志，
 * 日志统一写入 AppStorage 'lxPlayLog'（与引擎日志同一存储），
 * 因此在「音源管理 → 自检日志 → 分享」时会一并导出，便于排查问题。
 *
 * 格式：[HH:MM:SS] [分类] 消息
 * 例：  [21:50:33] [播放] 开始取链 source=kw songId=37813010 quality=128k
 */

const MAX_LOG_LENGTH: number = 20000

/**
 * 追加一行带分类标签的日志到共享播放日志，并同步输出到控制台。
 * @param tag   分类标签，如 '播放'、'引擎'、'歌词'、'封面'、'自检'
 * @param msg   日志内容
 */
export function playLog(tag: string, msg: string): void {
  const now: Date = new Date()
  const hh: string = now.getHours().toString().padStart(2, '0')
  const mm: string = now.getMinutes().toString().padStart(2, '0')
  const ss: string = now.getSeconds().toString().padStart(2, '0')
  const line: string = `[${hh}:${mm}:${ss}] [${tag}] ${msg}\n`

  let prev: string = AppStorage.get<string>('lxPlayLog') || ''
  let log: string = prev + line
  if (log.length > MAX_LOG_LENGTH) {
    log = log.substring(log.length - 5000)
  }
  AppStorage.setOrCreate('lxPlayLog', log)
  console.info(`[${tag}] ${msg}`)
}

/**
 * 清空共享播放日志（通常用于一次自检开始前）。
 */
export function clearPlayLog(): void {
  AppStorage.setOrCreate('lxPlayLog', '')
}

/**
 * 读取当前共享播放日志。
 */
export function getPlayLog(): string {
  return AppStorage.get<string>('lxPlayLog') || ''
}
