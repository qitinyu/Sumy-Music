# Sumy Music

一款鸿蒙原生音乐播放器，支持插件化多音源聚合搜索、自建API、本地音乐、WebDAV云盘播放与数据同步。听你想听，回归音乐本质！

> 当前版本：V2.0.7.7 ｜ [完整更新日志](https://github.com/qitinyu/Sumy-Music/wiki/)

## 功能特性

### 播放与搜索
- 插件化多音源聚合搜索（支持导入 LX v1 / LX v3 / MusicFree 音源插件）
- 自建API搜索（自定义API地址，与导入源强制隔离）
- 音源自检与诊断（导入即自检，播放失败自动标记音源并提示）
- 播放队列管理、多种播放模式（顺序 / 随机 / 单曲循环）
- 播放失败自动反馈并跳下一首，连续失败自动停止
- 歌词显示（逐行高亮，本地歌词乱码自动修复与联网补全）
- 网易云歌单ID导入

### 歌单管理
- 自建歌单（创建、编辑、排序、导出/导入）
- 本地音乐导入与播放（歌词/封面自动补全）
- WebDAV云盘歌单播放

### 数据同步
- 华为账号登录（获取头像昵称）
- WebDAV 全量数据备份与恢复（歌单、收藏、搜索记录、音源配置、主题设置等）

### 个性化
- 主题色自定义 / 预设主题 / 应用图标热切换
- 深色/浅色模式
- 沉浸光感材质UI

## 技术栈

- **HarmonyOS** Stage模型
- **ArkTS** + ArkUI 声明式UI
- **QuickJS** 原生JS内核（NAPI，承载 JS 音源插件执行）
- **API 26**（HarmonyOS 6.0），最低兼容 6.1.1(API 24)
- 关键Kit：AccountKit、NetworkKit、CoreFileKit、MediaKit、ArkData

## 项目结构

```
entry/src/main/ets/
├── components/          # UI组件（迷你栏、歌曲卡片、长按菜单、音源管理等）
├── database/            # 数据库管理（relationalStore）
├── entryability/        # Ability入口
├── model/               # 数据模型定义
├── pages/               # 页面（推荐、音迹、搜索、我的、设置、播放详情页）
├── source/              # LX音源引擎（WebView桥接）
├── utils/               # 工具类（API、播放器、音源引擎、同步、账号）
│   ├── AudioPlayer.ets        # 音频播放核心（切歌串行队列、错误自动跳过）
│   ├── PlayerStore.ets        # 播放状态中枢（AppStorage）
│   ├── MusicApi.ets           # 搜索/取链/歌词统一入口
│   ├── SourceManager.ets      # 音源插件管理与调度
│   ├── JsPluginEngine.ets     # LX v1 插件引擎
│   ├── JsPluginEngineV2.ets   # LX v3 插件引擎（QuickJS）
│   ├── QuickJSEngine.ets      # QuickJS 原生内核封装
│   ├── MFEngine.ets           # MusicFree 插件引擎
│   ├── SelfHostedApi.ets      # 自建API
│   ├── WebDavSync.ets         # WebDAV数据同步
│   ├── AccountManager.ets     # 华为账号登录
│   ├── CacheManager.ets       # 缓存管理
│   └── ThemeManager.ets       # 主题管理
└── resources/           # 资源文件

quickjs/                 # QuickJS 原生内核模块（CMake/Ninja 构建）
```

## 开发环境

- DevEco Studio 6.0+
- HarmonyOS SDK 26.0+
- 编译目标：HarmonyOS 6.0

## 构建说明

1. 克隆仓库
2. 用 DevEco Studio 打开项目
3. 配置签名证书（Project Structure → Signing Configs）
4. 同步项目并编译运行


## 权限说明

| 权限 | 用途 |
|------|------|
| INTERNET | 网络请求（搜索、播放、同步） |
| GET_NETWORK_INFO | 检测网络状态 |
| SHORT_TERM_WRITE_IMAGEVIDEO | 保存歌单封面图片 |
| READ_PASTEBOARD | 粘贴链接/歌单ID快速导入 |
| KEEP_BACKGROUND_RUNNING | 后台播放 |

## 开源协议

- MIT License

## 免责声明

- 本项目仅供学习和个人使用，不提供任何音源接口。
- 音源搜索功能依赖用户自行导入的第三方插件，使用者需自行承担相关风险。
