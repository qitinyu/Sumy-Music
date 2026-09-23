# API 24 兼容性验证报告

> 结论先行：**已定位 API 24 无法启动的根因并修复**。修复为静态验证（崩溃日志 + SDK 类型定义双向确认）；
> 实机/模拟器复测需在 DevEco Studio 中执行（本机缺少 hvigor CLI，无法用命令行编译验证）。

## 一、问题现象

更新日志中长期未勾选的条目：

```
- [] 修复应用在API24设备无法打开的问题
```

## 二、根因（已确认）

### 2.1 崩溃日志（项目自带）

文件：`ziyuan/log/1.txt`（崩溃时版本 `2.0.7.7`）

```
Reason:TypeError
Error name:TypeError
Error message:Cannot read property THICK of undefined
Stacktrace:
    at immersiveMaterial shym1032 (entry/src/main/ets/utils/MaterialCompat.ets:101:52)
    at anonymous shym1032 (entry/src/main/ets/pages/XuanchuangTab.ets:1985:42)
    at updateFunc (.../stateMgmt.js:9479:1)
    at observeComponentCreation2 (.../stateMgmt.js:9509:1)
    at initialRender shym1032 (entry/src/main/ets/pages/XuanchuangTab.ets:1960:13)
```

关键点：崩溃发生在 **`initialRender` 阶段**，即首帧渲染前就抛异常 → 表现为「应用打不开 / 闪退」。
崩溃位置是 `uiMaterial.ImmersiveStyle.THICK`，说明 `uiMaterial.ImmersiveStyle` 为 `undefined`。

### 2.2 SDK 类型定义证据

对两套本地 SDK 做交叉比对（`D:\HM\Harmory-sdk\23` 与 `D:\HM\Harmory-sdk\26.0.0`）：

| API | 项目 | 结果 |
| --- | --- | --- |
| `uiMaterial` | `@kit.ArkUI` 导出 | **仅 API 26 有**，API 23 无 |
| `systemMaterial(...)` | `CommonMethod` | **`@since 26.0.0`** |
| `SystemUiMaterial` | 类型 | API 26 才有，API 23 完全不存在 |
| `SystemMaterialParams.systemMaterialEffect` | HDS | `@since 6.1.0(23)` |
| `hdsMaterial.MaterialType.IMMERSIVE` | HDS | `@since 6.1.0(23)` |
| `backgroundEffect(...)` | `CommonMethod` | `@since 11`（低版本可用）|

即：**`uiMaterial` / `systemMaterial` 是 API 26 才引入的能力**，低于 26 的设备上运行时确实不存在。

### 2.3 触发链路

`V2.0.7.7` 版本的 `MaterialCompat.immersiveMaterial()` **既无版本守卫、也无 try/catch**：

```ts
static immersiveMaterial(style?: MaterialCompatStyle, options?: MaterialImmersiveOptions): uiMaterial.Material {
  const s = style !== undefined ? style : MaterialCompatStyle.REGULAR
  let immersiveStyle: uiMaterial.ImmersiveStyle
  switch (s) {
    case MaterialCompatStyle.THICK:
      immersiveStyle = uiMaterial.ImmersiveStyle.THICK   // ← 低版本此处抛 TypeError
```

而 `XuanchuangTab` 等在 `bindSheet` 的 `systemMaterial:` 参数中**无条件**调用它，
该参数在构建组件树时即求值，因此异常在首帧渲染前抛出。

## 三、修复内容

### 3.1 已有守卫（工作区已含，本次快照一并入库）

`CompatUtils.isImmersiveSupported()`：以 `deviceInfo.sdkApiVersion >= 26` 判定。

### 3.2 本次新增：运行时能力探测（纵深防御）

仅靠版本号判定不够——**崩溃日志中的模拟器 `Build info: 6.1.0.126`，其 SDK 版本上报与能力注入可能不一致**，
故在 `MaterialCompat.immersiveMaterial()` 内增加 `typeof` 能力探测，能力缺失即降级：

```ts
if (typeof uiMaterial.ImmersiveStyle === 'undefined') {
  return undefined
}
```

配合已有的 `try/catch` 兜底，形成「版本判定 → 能力探测 → 异常兜底」三层防护。

`immersiveMaterial()` 返回 `undefined` 时，调用方 `.systemMaterial(undefined)` 与
`systemMaterial: undefined` 均表示「无材质效果」，自动回退到 `backgroundEffect` 模拟路径（API 11+ 可用）。

### 3.3 调用点守卫盘点

| 位置 | 形式 | 状态 |
| --- | --- | --- |
| `BottomPlayer.ets:185` | `if (supportImmersive)` 分支 | ✅ 已守卫 |
| `FloatingTabBar.ets:236` | `if (supportImmersive)` 分支 | ✅ 已守卫 |
| `FloatingActionPopup.ets:53,145` | `if (supportImmersive)` 分支 | ✅ 已守卫 |
| `FullPlayerPage.ets` ×5 | `this.supportImmersive ? … : undefined` | ✅ 已守卫 |
| `QinseTab.ets:371` | 三元守卫 | ✅ 已守卫 |
| `XuanchuangTab.ets` ×10 | `systemMaterial:` 直接调用 | ⚠️ 依赖 `immersiveMaterial` 内部守卫（本次已加固）|

> 说明：`XuanchuangTab` 的 10 处未在调用点做三元守卫，但其安全性由
> `immersiveMaterial()` 内部三层防护保证（返回 `undefined` 即无效果）。
> 若后续要统一风格，可参照 `FullPlayerPage` 改为三元写法。

## 四、实机/模拟器复测步骤（待执行）

本机缺少 hvigor CLI 与设备连接工具（`hdc` 未随当前 SDK 安装），无法命令行验证，请在 DevEco Studio 中执行：

1. **准备 API 24 环境**
   - Device Manager 中创建 API 24（HarmonyOS 6.1.1）模拟器，或连接 API 24 真机。
2. **构建安装**
   - Build → Build Hap(s)/APP(s)，安装到该设备。
3. **回归验证点**
   - [ ] 应用能正常启动进入首页，无闪退
   - [ ] 首页底部悬浮页签栏正常显示（走 `backgroundEffect` 降级路径，应有毛玻璃观感）
   - [ ] 进入「我的」页，上下滚动不崩溃（原崩溃点）
   - [ ] 打开歌单/长按歌曲，`bindSheet` 弹窗正常弹出
   - [ ] 播放页、迷你栏样式正常
   - [ ] 切换深色/浅色模式正常
4. **日志核对**
   - 若仍崩溃，抓取 `TypeError` 堆栈，核对是否仍是 `uiMaterial` 相关；
   - 成功时不应再出现 `Cannot read property ... of undefined` 类异常。
5. **对照验证（可选）**
   - 同时在 API 26 设备上验证沉浸光感材质仍正常生效（确认没有把高版本能力误降级）。

## 五、结论

| 项 | 状态 |
| --- | --- |
| 根因定位 | ✅ 完成（崩溃日志 + SDK 类型定义双向确认） |
| 代码修复 | ✅ 完成（`MaterialCompat` 增加运行时能力探测） |
| 静态验证 | ✅ 完成（API 23/26 SDK 差异比对） |
| 实机复测 | ⏳ 待在 DevEco Studio 中执行（见第四节） |

修复后，更新日志中「修复应用在API24设备无法打开的问题」具备勾选条件，但**建议实机复测通过后再勾选**。
