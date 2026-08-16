# Sumy Music

一款鸿蒙原生音乐播放器，支持多音源聚合搜索、自建API、WebDAV云盘播放、数据同步等功能。

## 功能特性

### 播放与搜索
- 多音源聚合搜索（酷我、酷狗、QQ音乐、网易云、咪咕）
- 自建API搜索（支持自定义API地址）
- 插件化音源管理（支持导入JSON/JS插件）
- 歌词显示（逐行高亮、桌面歌词）
- 播放队列管理、多种播放模式

### 歌单管理
- 自建歌单（创建、编辑、排序）
- 本地音乐导入与播放
- WebDAV云盘歌单播放

### 数据同步
- 华为账号登录（获取头像昵称）
- WebDAV 全量数据备份与恢复（歌单、收藏、搜索记录、音源配置、主题设置等）

### 个性化
- 主题色自定义
- 深色/浅色模式
- 沉浸光感材质UI

## 技术栈

- **HarmonyOS** Stage模型
- **ArkTS** + ArkUI 声明式UI
- **API 26** (HarmonyOS 6.0)
- 关键Kit：AccountKit、NetworkKit、CoreFileKit、MediaKit

## 项目结构

```
entry/src/main/ets/
├── components/          # UI组件（播放器、搜索栏、歌曲卡片等）
├── database/            # 数据库管理（relationalStore）
├── entryability/        # Ability入口
├── model/               # 数据模型定义
├── pages/               # 页面（主页、搜索、设置、详情）
├── utils/               # 工具类（API、播放器、主题、同步、账号）
│   ├── AccountManager.ets    # 华为账号登录
│   ├── MusicApi.ets          # 音乐搜索API
│   ├── SelfHostedApi.ets     # 自建API
│   ├── WebDavSync.ets        # WebDAV数据同步
│   ├── AudioPlayer.ets       # 音频播放
│   ├── SourceManager.ets     # 音源插件管理
│   └── ThemeManager.ets      # 主题管理
└── resources/           # 资源文件
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

> **注意**：`build-profile.json5`（根目录）包含签名密码，已在 `.gitignore` 中排除，需本地自行配置。

## 权限说明

| 权限 | 用途 |
|------|------|
| INTERNET | 网络请求（搜索、播放） |
| GET_NETWORK_INFO | 检测网络状态 |
| READ_MEDIA | 读取本地音乐文件 |
| WRITE_MEDIA | 写入下载文件 |
| KEEP_BACKGROUND_RUNNING | 后台播放 |

## 开源协议

MIT License

## 免责声明

本项目仅供学习和个人使用，不提供任何音源接口。项目中的音源搜索功能依赖第三方公开接口，使用者需自行承担相关风险。请支持正版音乐，通过官方渠道获取音乐资源。
