/**
 * MusicStoreService - 最小适配层
 * 替代 123 项目中的 musicbasic 依赖，提供音源激活/存储功能
 */
import { preferences } from '@kit.ArkData';

export class MusicStoreService {
  private static instance: MusicStoreService | null = null;
  private preferences: preferences.Preferences | null = null;

  static getInstance(): MusicStoreService {
    if (!MusicStoreService.instance) {
      MusicStoreService.instance = new MusicStoreService();
    }
    return MusicStoreService.instance;
  }

  async init(context: Context): Promise<void> {
    this.preferences = await preferences.getPreferences(context, 'music_store');
  }

  getActiveSource(): string {
    if (this.preferences) {
      try {
        return this.preferences.getSync('active_source', '') as string;
      } catch (_e) {
        return '';
      }
    }
    return '';
  }

  setActiveSource(sourceId: string): void {
    if (this.preferences) {
      try {
        this.preferences.putSync('active_source', sourceId);
        this.preferences.flushSync();
      } catch (_e) {
        // ignore
      }
    }
  }
}

export let musicStoreService: MusicStoreService = MusicStoreService.getInstance();
