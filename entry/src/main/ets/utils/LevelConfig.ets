// LevelConfig.ets - LV1-8 八区段等级配置：徽章颜色与各区段数据区间（分钟），总量区间 0-160000
export const MAX_LEVEL: number = 8
export const TOTAL_MAX_MINUTES: number = 160000

// 八区段颜色（LV1-LV8，由浅到深）：
// 浅蓝、浅绿、浅紫、浅黄、浅橙、金黄、深橙、正红
export const LEVEL_COLORS: string[] = [
  '#7BCDEF', // LV1
  '#8BD29B', // LV2
  '#CCCCFF', // LV3
  '#FFFF99', // LV4
  '#FEBB8B', // LV5
  '#FFCC33', // LV6
  '#EE672A', // LV7
  '#FF0000'  // LV8
]

// 八区段色均为浅/中亮度，徽章文字统一用黑色保证对比度（白字在多数区段色上不达标）
export const LEVEL_TEXT_COLOR: string = '#000000'

// 各级升级所需分钟数（阈值表）：边界 0/1000/3000/8000/20000/45000/80000/120000/160000，合计恰为 160000
export const LEVEL_NEED_MINUTES: number[] = [1000, 2000, 5000, 12000, 25000, 35000, 40000, 40000]

export interface LevelRangeInfo {
  level: number
  color: string
  needMinutes: number
  rangeStart: number
  rangeEnd: number
}

export function getLevelColor(level: number): string {
  const clamped = Math.max(1, Math.min(MAX_LEVEL, Math.floor(level)))
  return LEVEL_COLORS[clamped - 1]
}

export function getNeedForLevel(level: number): number {
  const clamped = Math.max(1, Math.min(MAX_LEVEL, Math.floor(level)))
  return LEVEL_NEED_MINUTES[clamped - 1]
}

// 生成全部 8 级数据：rangeStart-rangeEnd 为累计听歌时长区间（分钟），总量区间 0-160000
export function buildLevelTable(): LevelRangeInfo[] {
  const rows: LevelRangeInfo[] = []
  let cumulative: number = 0
  for (let i: number = 1; i <= MAX_LEVEL; i++) {
    const need = getNeedForLevel(i)
    rows.push({
      level: i,
      color: getLevelColor(i),
      needMinutes: need,
      rangeStart: cumulative,
      rangeEnd: Math.min(cumulative + need, TOTAL_MAX_MINUTES)
    })
    cumulative += need
  }
  return rows
}
