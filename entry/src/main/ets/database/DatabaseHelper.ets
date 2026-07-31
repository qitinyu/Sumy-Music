// DatabaseHelper.ets - 本地数据库管理
// 基于 @kit.ArkData 的关系型数据库 RDB
import { relationalStore } from '@kit.ArkData'
import type { SongInfo, Playlist, DownloadItem } from '../model/MusicModel'

// 本地音乐条目类型
export interface LocalMusicItem {
  id: string
  filePath: string
  fileName: string
  songName: string
  artist: string
  duration: number
  fileSize: number
  addedAt: number
  coverUrl: string
}

export interface SearchResult {
  keyword: string
  results: SongInfo[]
}

const DB_NAME = 'shmy.db'
const DB_VERSION = 1

// 建表 SQL
const SQL_CREATE_FAVORITES = `
  CREATE TABLE IF NOT EXISTS favorite (
    id TEXT PRIMARY KEY,
    songId TEXT NOT NULL,
    songName TEXT NOT NULL,
    artist TEXT DEFAULT '',
    album TEXT DEFAULT '',
    coverUrl TEXT DEFAULT '',
    source TEXT DEFAULT 'kg',
    playUrl TEXT DEFAULT '',
    createdAt INTEGER NOT NULL
  )
`

const SQL_CREATE_PLAYLISTS = `
  CREATE TABLE IF NOT EXISTS playlist (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    coverUrl TEXT DEFAULT '',
    sortOrder INTEGER DEFAULT 0,
    createdAt INTEGER NOT NULL,
    updatedAt INTEGER NOT NULL
  )
`

const SQL_CREATE_PLAYLIST_SONGS = `
  CREATE TABLE IF NOT EXISTS playlist_song (
    id TEXT PRIMARY KEY,
    playlistId TEXT NOT NULL,
    songId TEXT NOT NULL,
    songName TEXT NOT NULL,
    artist TEXT DEFAULT '',
    album TEXT DEFAULT '',
    coverUrl TEXT DEFAULT '',
    source TEXT DEFAULT 'kg',
    playUrl TEXT DEFAULT '',
    createdAt INTEGER NOT NULL,
    FOREIGN KEY (playlistId) REFERENCES playlist(id) ON DELETE CASCADE
  )
`

const SQL_CREATE_DOWNLOADS = `
  CREATE TABLE IF NOT EXISTS download (
    id TEXT PRIMARY KEY,
    songId TEXT NOT NULL,
    songName TEXT NOT NULL,
    artist TEXT DEFAULT '',
    album TEXT DEFAULT '',
    coverUrl TEXT DEFAULT '',
    source TEXT DEFAULT 'kg',
    playUrl TEXT DEFAULT '',
    quality TEXT DEFAULT 'standard',
    status TEXT DEFAULT 'pending',
    progress REAL DEFAULT 0,
    createdAt INTEGER NOT NULL,
    updatedAt INTEGER NOT NULL
  )
`

const SQL_CREATE_SETTINGS = `
  CREATE TABLE IF NOT EXISTS app_setting (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )
`

const SQL_CREATE_LOCAL_MUSIC = `
  CREATE TABLE IF NOT EXISTS local_music (
    id TEXT PRIMARY KEY,
    filePath TEXT NOT NULL UNIQUE,
    fileName TEXT NOT NULL,
    songName TEXT DEFAULT '',
    artist TEXT DEFAULT '',
    duration INTEGER DEFAULT 0,
    fileSize INTEGER DEFAULT 0,
    addedAt INTEGER NOT NULL,
    coverUrl TEXT DEFAULT ''
  )
`

export class DatabaseHelper {
  private static instance: DatabaseHelper | null = null
  private store: relationalStore.RdbStore | null = null

  static getInstance(): DatabaseHelper {
    if (!DatabaseHelper.instance) {
      DatabaseHelper.instance = new DatabaseHelper()
    }
    return DatabaseHelper.instance
  }

  // 初始化数据库（在 EntryAbility.onCreate 中调用）
  async init(context: Context): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1,
    }
    this.store = await relationalStore.getRdbStore(context, config)
    await this.createTables()
  }

  private async createTables(): Promise<void> {
    if (!this.store) return
    await this.store.executeSql(SQL_CREATE_FAVORITES)
    await this.store.executeSql(SQL_CREATE_PLAYLISTS)
    await this.store.executeSql(SQL_CREATE_PLAYLIST_SONGS)
    await this.store.executeSql(SQL_CREATE_DOWNLOADS)
    await this.store.executeSql(SQL_CREATE_SETTINGS)
    await this.store.executeSql(SQL_CREATE_LOCAL_MUSIC)
    // 迁移：添加 coverUrl / sortOrder 列（如果不存在）
    try {
      await this.store.executeSql("ALTER TABLE local_music ADD COLUMN coverUrl TEXT DEFAULT ''")
    } catch (_e) {
    }
    try {
      await this.store.executeSql("ALTER TABLE playlist ADD COLUMN coverUrl TEXT DEFAULT ''")
    } catch (_e) {
    }
    try {
      await this.store.executeSql("ALTER TABLE playlist ADD COLUMN sortOrder INTEGER DEFAULT 0")
    } catch (_e) {
    }
  }

  // ===== 收藏 CRUD =====

  async addFavorite(song: SongInfo): Promise<boolean> {
    if (!this.store) return false
    try {
      // 检查重复
      const predicates = new relationalStore.RdbPredicates('favorite')
      predicates.equalTo('songId', song.songId).equalTo('source', song.source)
      const cursor = await this.store.query(predicates)
      if (cursor.goToFirstRow()) {
        cursor.close()
        return false // 已存在
      }
      cursor.close()

      const valueBucket: relationalStore.ValuesBucket = {
        'id': generateId(),
        'songId': song.songId,
        'songName': song.songName,
        'artist': song.artist,
        'album': song.album,
        'coverUrl': song.coverUrl,
        'source': song.source,
        'playUrl': song.playUrl,
        'createdAt': Date.now(),
      }
      await this.store.insert('favorite', valueBucket)
      return true
    } catch (e) {
      console.error('[DB] addFavorite failed:', e)
      return false
    }
  }

  async getFavorites(): Promise<SongInfo[]> {
    if (!this.store) return []
    try {
      const predicates = new relationalStore.RdbPredicates('favorite')
      predicates.orderByDesc('createdAt')
      const cursor = await this.store.query(predicates)
      const songs: SongInfo[] = []
      while (cursor.goToNextRow()) {
        songs.push({
          songId: cursor.getString(cursor.getColumnIndex('songId')),
          songName: cursor.getString(cursor.getColumnIndex('songName')),
          artist: cursor.getString(cursor.getColumnIndex('artist')),
          album: cursor.getString(cursor.getColumnIndex('album')),
          coverUrl: cursor.getString(cursor.getColumnIndex('coverUrl')),
          source: cursor.getString(cursor.getColumnIndex('source')),
          playUrl: cursor.getString(cursor.getColumnIndex('playUrl')),
        })
      }
      cursor.close()
      return songs
    } catch (e) {
      console.error('[DB] getFavorites failed:', e)
      return []
    }
  }

  async removeFavorite(songId: string, source: string): Promise<void> {
    if (!this.store) return
    try {
      const predicates = new relationalStore.RdbPredicates('favorite')
      predicates.equalTo('songId', songId).equalTo('source', source)
      await this.store.delete(predicates)
    } catch (e) {
      console.error('[DB] removeFavorite failed:', e)
    }
  }

  // ===== 歌单 CRUD =====

  async createPlaylist(name: string, coverUrl: string = ''): Promise<string | null> {
    if (!this.store) return null
    try {
      const id = generateId()
      const now = Date.now()
      const valueBucket: relationalStore.ValuesBucket = {
        'id': id,
        'name': name,
        'coverUrl': coverUrl,
        'sortOrder': 0,
        'createdAt': now,
        'updatedAt': now,
      }
      await this.store.insert('playlist', valueBucket)
      return id
    } catch (e) {
      console.error('[DB] createPlaylist failed:', e)
      return null
    }
  }

  async getPlaylists(): Promise<Playlist[]> {
    if (!this.store) return []
    try {
      const predicates = new relationalStore.RdbPredicates('playlist')
      predicates.orderByAsc('sortOrder').orderByDesc('updatedAt')
      const cursor = await this.store.query(predicates)
      const playlists: Playlist[] = []
      while (cursor.goToNextRow()) {
        const id = cursor.getString(cursor.getColumnIndex('id'))
        playlists.push({
          id,
          name: cursor.getString(cursor.getColumnIndex('name')),
          songCount: await this.getPlaylistSongCount(id),
          coverUrl: cursor.getString(cursor.getColumnIndex('coverUrl')) ?? '',
          sortOrder: cursor.getLong(cursor.getColumnIndex('sortOrder')) ?? 0,
          createdAt: cursor.getLong(cursor.getColumnIndex('createdAt')),
          updatedAt: cursor.getLong(cursor.getColumnIndex('updatedAt')),
        })
      }
      cursor.close()
      return playlists
    } catch (e) {
      console.error('[DB] getPlaylists failed:', e)
      return []
    }
  }

  async renamePlaylist(id: string, newName: string): Promise<void> {
    if (!this.store) return
    try {
      const valueBucket: relationalStore.ValuesBucket = {
        'name': newName,
        'updatedAt': Date.now(),
      }
      const predicates = new relationalStore.RdbPredicates('playlist')
      predicates.equalTo('id', id)
      await this.store.update(valueBucket, predicates)
    } catch (e) {
      console.error('[DB] renamePlaylist failed:', e)
    }
  }

  async updatePlaylist(id: string, name: string, coverUrl: string): Promise<void> {
    if (!this.store) return
    try {
      const valueBucket: relationalStore.ValuesBucket = {
        'name': name,
        'coverUrl': coverUrl,
        'updatedAt': Date.now(),
      }
      const predicates = new relationalStore.RdbPredicates('playlist')
      predicates.equalTo('id', id)
      await this.store.update(valueBucket, predicates)
    } catch (e) {
      console.error('[DB] updatePlaylist failed:', e)
    }
  }

  async reorderPlaylists(ids: string[]): Promise<void> {
    if (!this.store) return
    try {
      for (let i = 0; i < ids.length; i++) {
        const valueBucket: relationalStore.ValuesBucket = {
          'sortOrder': i,
          'updatedAt': Date.now(),
        }
        const predicates = new relationalStore.RdbPredicates('playlist')
        predicates.equalTo('id', ids[i])
        await this.store.update(valueBucket, predicates)
      }
    } catch (e) {
      console.error('[DB] reorderPlaylists failed:', e)
    }
  }

  async deletePlaylist(id: string): Promise<void> {
    if (!this.store) return
    try {
      const predicates = new relationalStore.RdbPredicates('playlist')
      predicates.equalTo('id', id)
      await this.store.delete(predicates)
      // CASCADE 会自动删除关联歌曲
    } catch (e) {
      console.error('[DB] deletePlaylist failed:', e)
    }
  }

  async addSongToPlaylist(playlistId: string, song: SongInfo): Promise<boolean> {
    if (!this.store) return false
    try {
      const valueBucket: relationalStore.ValuesBucket = {
        'id': generateId(),
        'playlistId': playlistId,
        'songId': song.songId,
        'songName': song.songName,
        'artist': song.artist,
        'album': song.album,
        'coverUrl': song.coverUrl,
        'source': song.source,
        'playUrl': song.playUrl,
        'createdAt': Date.now(),
      }
      await this.store.insert('playlist_song', valueBucket)
      // 更新歌单的 updatedAt
      const updateBucket: relationalStore.ValuesBucket = { 'updatedAt': Date.now() }
      const updatePred = new relationalStore.RdbPredicates('playlist')
      updatePred.equalTo('id', playlistId)
      await this.store.update(updateBucket, updatePred)
      return true
    } catch (e) {
      console.error('[DB] addSongToPlaylist failed:', e)
      return false
    }
  }

  async getPlaylistSongs(playlistId: string): Promise<SongInfo[]> {
    if (!this.store) return []
    try {
      const predicates = new relationalStore.RdbPredicates('playlist_song')
      predicates.equalTo('playlistId', playlistId).orderByAsc('createdAt')
      const cursor = await this.store.query(predicates)
      const songs: SongInfo[] = []
      while (cursor.goToNextRow()) {
        songs.push({
          songId: cursor.getString(cursor.getColumnIndex('songId')),
          songName: cursor.getString(cursor.getColumnIndex('songName')),
          artist: cursor.getString(cursor.getColumnIndex('artist')),
          album: cursor.getString(cursor.getColumnIndex('album')),
          coverUrl: cursor.getString(cursor.getColumnIndex('coverUrl')),
          source: cursor.getString(cursor.getColumnIndex('source')),
          playUrl: cursor.getString(cursor.getColumnIndex('playUrl')),
        })
      }
      cursor.close()
      return songs
    } catch (e) {
      console.error('[DB] getPlaylistSongs failed:', e)
      return []
    }
  }

  private async getPlaylistSongCount(playlistId: string): Promise<number> {
    if (!this.store) return 0
    try {
      const predicates = new relationalStore.RdbPredicates('playlist_song')
      predicates.equalTo('playlistId', playlistId)
      const cursor = await this.store.query(predicates)
      const count = cursor.rowCount
      cursor.close()
      return count
    } catch (_) { return 0 }
  }

  async updatePlaylistSongs(playlistId: string, songs: SongInfo[]): Promise<void> {
    if (!this.store) return
    try {
      // 先删除该歌单的所有现有歌曲关联
      const deletePred = new relationalStore.RdbPredicates('playlist_song')
      deletePred.equalTo('playlistId', playlistId)
      await this.store.delete(deletePred)

      // 按新顺序重新插入所有歌曲
      const now = Date.now()
      for (let i = 0; i < songs.length; i++) {
        const song = songs[i]
        const valueBucket: relationalStore.ValuesBucket = {
          'id': generateId(),
          'playlistId': playlistId,
          'songId': song.songId,
          'songName': song.songName,
          'artist': song.artist,
          'album': song.album,
          'coverUrl': song.coverUrl,
          'source': song.source,
          'playUrl': song.playUrl,
          'createdAt': now + i,
        }
        await this.store.insert('playlist_song', valueBucket)
      }

      // 更新歌单的 updatedAt
      const updateBucket: relationalStore.ValuesBucket = { 'updatedAt': Date.now() }
      const updatePred = new relationalStore.RdbPredicates('playlist')
      updatePred.equalTo('id', playlistId)
      await this.store.update(updateBucket, updatePred)
    } catch (e) {
      console.error('[DB] updatePlaylistSongs failed:', e)
    }
  }

  async removeSongFromPlaylist(playlistId: string, songId: string, source: string): Promise<void> {
    if (!this.store) return
    try {
      const predicates = new relationalStore.RdbPredicates('playlist_song')
      predicates.equalTo('playlistId', playlistId)
        .equalTo('songId', songId)
        .equalTo('source', source)
      await this.store.delete(predicates)
    } catch (e) {
      console.error('[DB] removeSongFromPlaylist failed:', e)
    }
  }

  // ===== 下载 CRUD =====

  async addDownload(song: SongInfo, quality: string): Promise<string | null> {
    if (!this.store) return null
    try {
      const id = generateId()
      const now = Date.now()
      const valueBucket: relationalStore.ValuesBucket = {
        'id': id,
        'songId': song.songId,
        'songName': song.songName,
        'artist': song.artist,
        'album': song.album,
        'coverUrl': song.coverUrl,
        'source': song.source,
        'playUrl': song.playUrl,
        'quality': quality,
        'status': 'pending',
        'progress': 0,
        'createdAt': now,
        'updatedAt': now,
      }
      await this.store.insert('download', valueBucket)
      return id
    } catch (e) {
      console.error('[DB] addDownload failed:', e)
      return null
    }
  }

  async getDownloads(): Promise<DownloadItem[]> {
    if (!this.store) return []
    try {
      const predicates = new relationalStore.RdbPredicates('download')
      predicates.orderByDesc('createdAt')
      const cursor = await this.store.query(predicates)
      const items: DownloadItem[] = []
      while (cursor.goToNextRow()) {
        items.push({
          id: cursor.getString(cursor.getColumnIndex('id')),
          songId: cursor.getString(cursor.getColumnIndex('songId')),
          songName: cursor.getString(cursor.getColumnIndex('songName')),
          artist: cursor.getString(cursor.getColumnIndex('artist')),
          album: cursor.getString(cursor.getColumnIndex('album')),
          coverUrl: cursor.getString(cursor.getColumnIndex('coverUrl')),
          source: cursor.getString(cursor.getColumnIndex('source')),
          playUrl: cursor.getString(cursor.getColumnIndex('playUrl')),
          quality: cursor.getString(cursor.getColumnIndex('quality')),
          status: cursor.getString(cursor.getColumnIndex('status')),
          progress: cursor.getDouble(cursor.getColumnIndex('progress')),
          createdAt: cursor.getLong(cursor.getColumnIndex('createdAt')),
        })
      }
      cursor.close()
      return items
    } catch (e) {
      console.error('[DB] getDownloads failed:', e)
      return []
    }
  }

  async updateDownloadStatus(id: string, status: string, progress: number): Promise<void> {
    if (!this.store) return
    try {
      const valueBucket: relationalStore.ValuesBucket = {
        'status': status,
        'progress': progress,
        'updatedAt': Date.now(),
      }
      const predicates = new relationalStore.RdbPredicates('download')
      predicates.equalTo('id', id)
      await this.store.update(valueBucket, predicates)
    } catch (e) {
      console.error('[DB] updateDownloadStatus failed:', e)
    }
  }

  async deleteDownload(id: string): Promise<void> {
    if (!this.store) return
    try {
      const predicates = new relationalStore.RdbPredicates('download')
      predicates.equalTo('id', id)
      await this.store.delete(predicates)
    } catch (e) {
      console.error('[DB] deleteDownload failed:', e)
    }
  }

  // ===== 设置 KV =====

  async getSetting(key: string): Promise<string> {
    if (!this.store) return ''
    try {
      const predicates = new relationalStore.RdbPredicates('app_setting')
      predicates.equalTo('key', key)
      const cursor = await this.store.query(predicates)
      let value = ''
      if (cursor.goToFirstRow()) {
        value = cursor.getString(cursor.getColumnIndex('value'))
      }
      cursor.close()
      return value
    } catch (_) { return '' }
  }

  async setSetting(key: string, value: string): Promise<void> {
    if (!this.store) return
    try {
      const valueBucket: relationalStore.ValuesBucket = { 'key': key, 'value': value }
      await this.store.insert('app_setting', valueBucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE)
    } catch (e) {
      console.error('[DB] setSetting failed:', e)
    }
  }

  // ===== 本地音乐 CRUD =====

  async addLocalMusic(filePath: string, fileName: string, songName: string, artist: string,
    duration: number, fileSize: number, coverUrl: string = ''): Promise<boolean> {
    if (!this.store) return false
    try {
      // 检查重复（按 filePath 去重）
      const predicates = new relationalStore.RdbPredicates('local_music')
      predicates.equalTo('filePath', filePath)
      const cursor = await this.store.query(predicates)
      if (cursor.goToFirstRow()) {
        cursor.close()
        return false // 已存在
      }
      cursor.close()

      const valueBucket: relationalStore.ValuesBucket = {
        'id': generateId(),
        'filePath': filePath,
        'fileName': fileName,
        'songName': songName,
        'artist': artist,
        'duration': duration,
        'fileSize': fileSize,
        'addedAt': Date.now(),
        'coverUrl': coverUrl,
      }
      await this.store.insert('local_music', valueBucket)
      return true
    } catch (e) {
      console.error('[DB] addLocalMusic failed:', e)
      return false
    }
  }

  async getLocalMusic(): Promise<Array<LocalMusicItem>> {
    if (!this.store) return []
    try {
      const predicates = new relationalStore.RdbPredicates('local_music')
      predicates.orderByDesc('addedAt')
      const cursor = await this.store.query(predicates)
      const list: Array<LocalMusicItem> = []
      while (cursor.goToNextRow()) {
        let coverUrl: string = ''
        try {
          coverUrl = cursor.getString(cursor.getColumnIndex('coverUrl'))
        } catch (_e) {
          coverUrl = ''
        }
        list.push({
          id: cursor.getString(cursor.getColumnIndex('id')),
          filePath: cursor.getString(cursor.getColumnIndex('filePath')),
          fileName: cursor.getString(cursor.getColumnIndex('fileName')),
          songName: cursor.getString(cursor.getColumnIndex('songName')),
          artist: cursor.getString(cursor.getColumnIndex('artist')),
          duration: cursor.getLong(cursor.getColumnIndex('duration')),
          fileSize: cursor.getLong(cursor.getColumnIndex('fileSize')),
          addedAt: cursor.getLong(cursor.getColumnIndex('addedAt')),
          coverUrl: coverUrl,
        })
      }
      cursor.close()
      return list
    } catch (e) {
      console.error('[DB] getLocalMusic failed:', e)
      return []
    }
  }

  async removeLocalMusic(id: string): Promise<void> {
    if (!this.store) return
    try {
      const predicates = new relationalStore.RdbPredicates('local_music')
      predicates.equalTo('id', id)
      await this.store.delete(predicates)
    } catch (e) {
      console.error('[DB] removeLocalMusic failed:', e)
    }
  }

  async clearLocalMusic(): Promise<void> {
    if (!this.store) return
    try {
      const predicates = new relationalStore.RdbPredicates('local_music')
      await this.store.delete(predicates)
    } catch (e) {
      console.error('[DB] clearLocalMusic failed:', e)
    }
  }

  // ===== 搜索历史 =====

  async addSearchHistory(keyword: string): Promise<void> {
    const raw = await this.getSetting('qinseSearchHistory')
    let history: string[] = []
    if (raw) {
      try { history = JSON.parse(raw) as string[] } catch (_) { history = [] }
    }
    // 去重：移除旧记录，插入到最前面
    history = history.filter(k => k !== keyword)
    history.unshift(keyword)
    // 最多保留20条
    if (history.length > 20) {
      history = history.slice(0, 20)
    }
    await this.setSetting('qinseSearchHistory', JSON.stringify(history))
  }

  async getSearchHistory(): Promise<string[]> {
    const raw = await this.getSetting('qinseSearchHistory')
    if (!raw) return []
    try { return JSON.parse(raw) as string[] } catch (_) { return [] }
  }

  async clearSearchHistory(): Promise<void> {
    await this.setSetting('qinseSearchHistory', '[]')
  }

  async saveSearchResults(keyword: string, results: SongInfo[]): Promise<void> {
    await this.setSetting('qinseSearchKeyword', keyword)
    const data = results.slice(0, 30) // 最多保存30条
    await this.setSetting('qinseSearchResults', JSON.stringify(data))
  }

  async getSearchResults(): Promise<SearchResult> {
    const keyword = await this.getSetting('qinseSearchKeyword')
    const raw = await this.getSetting('qinseSearchResults')
    if (!keyword || !raw) return { keyword: '', results: [] } as SearchResult
    try {
      return { keyword, results: JSON.parse(raw) as SongInfo[] } as SearchResult
    } catch (_) {
      return { keyword: '', results: [] } as SearchResult
    }
  }

  async clearSearchResults(): Promise<void> {
    await this.setSetting('qinseSearchKeyword', '')
    await this.setSetting('qinseSearchResults', '[]')
  }

  // ===== 全量导出/导入（用于数据同步） =====

  // 导出所有表数据为 JSON 字符串
  async exportAll(): Promise<string> {
    if (!this.store) return '{}'
    try {
      const data: Record<string, Object> = {}

      // 导出 favorite 表
      data['favorite'] = await this.exportTable('favorite')

      // 导出 playlist 表
      data['playlist'] = await this.exportTable('playlist')

      // 导出 playlist_song 表
      data['playlist_song'] = await this.exportTable('playlist_song')

      // 导出 download 表
      data['download'] = await this.exportTable('download')

      // 导出 local_music 表
      data['local_music'] = await this.exportTable('local_music')

      // 导出 app_setting 表
      data['app_setting'] = await this.exportTable('app_setting')

      const result: Record<string, Object> = {
        'version': DB_VERSION,
        'exportTime': Date.now(),
        'tables': data,
      }
      return JSON.stringify(result)
    } catch (e) {
      console.error('[DB] exportAll failed:', e)
      return '{}'
    }
  }

  private async exportTable(tableName: string): Promise<Object[]> {
    if (!this.store) return []
    try {
      const predicates = new relationalStore.RdbPredicates(tableName)
      const cursor = await this.store.query(predicates)
      const rows: Object[] = []
      const columnCount = cursor.columnCount
      while (cursor.goToNextRow()) {
        const row: Record<string, string | number> = {}
        for (let i = 0; i < columnCount; i++) {
          const colName = cursor.getColumnName(i)
          // 先尝试获取 long，如果与字符串表示一致则存为 number
          const strVal = cursor.getString(i)
          const longVal = cursor.getLong(i)
          if (String(longVal) === strVal) {
            row[colName] = longVal
          } else {
            row[colName] = strVal
          }
        }
        rows.push(row)
      }
      cursor.close()
      return rows
    } catch (e) {
      console.error(`[DB] exportTable ${tableName} failed:`, e)
      return []
    }
  }

  // 从 JSON 字符串导入所有表数据（全量替换）
  async importAll(jsonStr: string): Promise<boolean> {
    if (!this.store) return false
    try {
      const parsed = JSON.parse(jsonStr) as Record<string, Object>
      const tables = parsed['tables'] as Record<string, Object[]>
      if (!tables) return false

      // 按顺序清空再插入（注意外键依赖顺序）
      const clearOrder = ['playlist_song', 'playlist', 'favorite', 'download', 'local_music', 'app_setting']
      for (let i = 0; i < clearOrder.length; i++) {
        const predicates = new relationalStore.RdbPredicates(clearOrder[i])
        await this.store.delete(predicates)
      }

      // 按顺序插入（先 playlist 再 playlist_song）
      const insertOrder = ['playlist', 'playlist_song', 'favorite', 'download', 'local_music', 'app_setting']
      for (let i = 0; i < insertOrder.length; i++) {
        const tableName = insertOrder[i]
        const rows = tables[tableName]
        if (rows instanceof Array) {
          for (let j = 0; j < rows.length; j++) {
            const row = rows[j] as Record<string, string | number>
            const valueBucket: relationalStore.ValuesBucket = {}
            const keys = Object.keys(row)
            for (let k = 0; k < keys.length; k++) {
              valueBucket[keys[k]] = row[keys[k]]
            }
            await this.store.insert(tableName, valueBucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE)
          }
        }
      }

      console.info('[DB] importAll done')
      return true
    } catch (e) {
      console.error('[DB] importAll failed:', e)
      return false
    }
  }

  // ===== 所有歌曲 =====

  async getAllSongs(): Promise<SongInfo[]> {
    if (!this.store) return []
    const songs: SongInfo[] = []
    const seenIds: Set<string> = new Set()

    const addUnique = (song: SongInfo): void => {
      const key = song.songId + '_' + song.source
      if (!seenIds.has(key)) {
        seenIds.add(key)
        songs.push(song)
      }
    }

    try {
      const favorites = await this.getFavorites()
      for (let i = 0; i < favorites.length; i++) {
        addUnique(favorites[i])
      }

      const playlists = await this.getPlaylists()
      for (let i = 0; i < playlists.length; i++) {
        const playlistSongs = await this.getPlaylistSongs(playlists[i].id)
        for (let j = 0; j < playlistSongs.length; j++) {
          addUnique(playlistSongs[j])
        }
      }

      const downloads = await this.getDownloads()
      for (let i = 0; i < downloads.length; i++) {
        const d = downloads[i]
        addUnique({
          songId: d.songId,
          songName: d.songName,
          artist: d.artist,
          album: d.album,
          coverUrl: d.coverUrl,
          source: d.source,
          playUrl: d.playUrl,
        })
      }
    } catch (e) {
      console.error('[DB] getAllSongs failed:', e)
    }

    return songs
  }
}

// 生成唯一 ID
function generateId(): string {
  return Date.now().toString(36) + Math.random().toString(36).substring(2, 8)
}
