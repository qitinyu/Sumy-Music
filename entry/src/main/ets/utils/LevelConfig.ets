// LevelConfig.ets - LV1-16 等级配置：徽章颜色与各级数据区间（分钟）
export const MAX_LEVEL: number = 16
export const BASE_NEED_MINUTES: number = 1160
export const GROWTH_RATE: number = 1.25

// 四区段颜色（由浅到深）：
// LV1-4 蓝；LV5-8 绿；LV9-12 橙；LV13-16 红
export const LEVEL_COLORS: string[] = [
  '#D9E1F4', // LV1
  '#B5C6EA', // LV2
  '#91AADF', // LV3
  '#2D529F', // LV4
  '#E3F2D9', // LV5
  '#C9E4B4', // LV6
  '#ADD88D', // LV7
  '#FCE4D3', // LV8
  '#F9CBAA', // LV9
  '#F9CBAA', // LV10
  '#F9CBAA', // LV11
  '#C55C10', // LV12
  '#FADADE', // LV13
  '#F4B7BE', // LV14
  '#EF949F', // LV15
  '#C91D32'  // LV16
]

export const SEGMENT_NAMES: string[] = ['蓝色区段 · LV1-4', '绿色区段 · LV5-8', '橙色区段 · LV9-12', '红色区段 · LV13-16']

export interface LevelRangeInfo {
  level: number
  color: string
  needMinutes: number
  rangeStart: number
  rangeEnd: number
  segment: number
}

export function getLevelColor(level: number): string {
  const clamped = Math.max(1, Math.min(MAX_LEVEL, Math.floor(level)))
  return LEVEL_COLORS[clamped - 1]
}

// 与 ListeningLevelManager 相同的递增公式：floor(1160 * 1.25^(level-1))
export function getNeedForLevel(level: number): number {
  if (level <= 1) {
    return BASE_NEED_MINUTES
  }
  return Math.floor(BASE_NEED_MINUTES * Math.pow(GROWTH_RATE, level - 1))
}

// 生成全部 16 级数据：rangeStart-rangeEnd 为累计听歌时长区间（分钟），总量区间 0-160000
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
      rangeEnd: Math.min(cumulative + need, 160000),
      segment: Math.floor((i - 1) / 4) + 1
    })
    cumulative += need
  }
  return rows
}