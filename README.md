# 词记本 wordlog

个人自用的 Android 应用：白天只记词名，晚上让大模型批量解释，最后导出 Markdown 进 Obsidian。

## 核心流程

1. **记**：桌面小组件 → 点一下 → 敲词 → 回车（不启动 Flutter 引擎，秒开，先暂存到 SharedPreferences）
2. **收**：打开 App 时把暂存的词收进 SQLite
3. **解释**：勾选当天要解释的词 → 一次请求打包发给大模型 → 先给严谨专业定义（含 LaTeX 公式），再用大白话讲一遍
4. **笔记**：在词条下随手记自己的理解，可插图片（相册/拍照），图片存应用私有目录
5. **回看**：「历史」页按天倒序列出所有记过的词，支持搜索，带笔记/待解释标记
6. **导出**：SAF 授权 Obsidian 仓库目录一次 → 写入 `YYYY-MM.md`，按天分组，同月多次导出自动合并；笔记和图片一并导出（图片进 `images/` 子目录）
7. **复习**：解释过的词 8 小时后进入复习队列，简化版 SM-2 调度

## 解释的四段结构

| 段 | 含义 | 长度 |
|---|---|---|
| 专业定义 | 严谨准确的表述；涉及数学/统计/算法必须给公式（`$...$` 行内、`$$...$$` 独立行），并说明符号含义 | 唯一可以写长的，100-300 字 |
| 通俗解释 | 一两句点破直觉，打一个比方就够，不复述定义 | 短，30-80 字 |
| 例子 | 一个小例子，能带数字就带数字，不写长推导 | 短，50-120 字 |
| 延伸 | 3-6 个相关概念，顿号分隔 | 一行 |

模板可在「设置」里改，点「恢复默认模板」可拿回最新版。

## 应用内看公式

解释、笔记、闪卡背面都用 `RichContent`（`lib/widgets/rich_content.dart`）渲染：

- `$$...$$` → 独立成行、居中，过长可横向滑动
- `$...$` → 行内公式
- 顺带认 `**粗体**`、`` `行内代码` ``、`#` 标题、`-` / `1.` 列表、``` 代码块

公式渲染用 `flutter_math_fork`（KaTeX 移植，纯 Dart，无原生代码，不牵出 jni/CMake）。
列表页的一行预览不做渲染，改成把公式替换成「〔公式〕」占位，避免露出 LaTeX 源码。

词条详情页分两栏：**解释**（渲染后的样子）和 **Markdown**（与导出完全一致的原文，可一键复制进 Obsidian）。

## 目录结构

```
lib/
  main.dart                 入口与全局 Provider
  theme.dart                浅色主题
  models/term.dart          Term / ReviewState
  db/database.dart          sqflite 建表与全部查询
  services/
    ai_service.dart         OpenAI 兼容接口调用 + JSON 解析
    setting_service.dart    配置读写（Key 走 flutter_secure_storage）
    export_service.dart     Markdown 生成与同月合并
    platform_service.dart   MethodChannel 桥接原生
    notify_service.dart     每日提醒与导出结果通知
    image_store.dart        笔记图片存到应用私有目录
  widgets/
    rich_content.dart       LaTeX + 轻量 Markdown 渲染
  screens/
    home_shell.dart         底部导航 + 暂存词回收
    today_screen.dart       今日记词 / 搜索 / 导出
    history_screen.dart     按天回看历史记录 + 搜索
    detail_screen.dart      词条详情 / 笔记（文本+图片）/ Markdown 栏 / 单条重新生成
    batch_screen.dart       批量解释
    review_screen.dart      闪卡复习
    stats_screen.dart       热力图与统计
    settings_screen.dart    API / 导出目录 / 提醒 / 模板

android/app/src/main/kotlin/com/wenxu/wordlog/
  MainActivity.kt           MethodChannel：SAF 读写、暂存词、小组件数据
  QuickAddActivity.kt       小组件点击后秒开的记录页（纯原生）
  WordWidgetProvider.kt     桌面小组件
  WidgetBridge.kt           暂存与刷新工具
```

## 原生通道 `wordlog/native`

| 方法 | 参数 | 返回 |
|---|---|---|
| `pickDirectory` | – | 授权目录 URI 字符串或 null |
| `writeFile` | uri, fileName, content | bool |
| `readFile` | uri, fileName | 内容字符串或 null |
| `writeBytes` | uri, relativePath, bytes | bool（子目录自动创建） |
| `filesDir` | – | 应用私有目录绝对路径 |
| `getPending` | – | 暂存词列表 |
| `clearPending` | – | bool |
| `setWidgetStats` | count, recent | bool |

## 数据库（schema v3）

- `terms` 词条（含四段解释、模型名、解释时间）
- `notes` 词条下的笔记（正文 + 图片路径 JSON）
- `tags` / `term_tags` 标签多对多
- `reviews` SM-2 调度状态
- `settings` 键值配置（含 API Key、导出目录、模板）

- v1 → v2：新增 `notes` 表，老数据无损
- v2 → v3：重置 `prompt_template`。只要点过一次「保存」，旧默认模板就会被固化在设置表里，
  不重置的话升级后拿不到新模板（自定义过的模板会被覆盖，需重新改）

## 构建

```powershell
# 环境变量已在安装时写入 User 级，重开终端即生效
cd "E:\workbuddy ws new\2026-09-22-19-48-18\wordlog"
flutter pub get
flutter build apk --release --target-platform android-arm64
```

产物：`build\app\outputs\flutter-apk\app-release.apk`（约 18 MB，仅 arm64）

装机（手机开 USB 调试后）：

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

也可以直接把 APK 传到手机上安装。

## 数据存放位置

- 数据库：应用私有目录下的 `wordlog.db`（Android 卸载即清除，导出 md 是唯一持久备份）
- API Key：存在 `settings` 表里。个人自用场景可接受；若要更高安全性可自行改回 `flutter_secure_storage`

## 已做的环境取舍

- Flutter SDK `E:\flutter`，pub 缓存 `E:\flutter\.pub-cache`
- Gradle 缓存 `E:\AndroidHome\gradle`，Android 用户目录 `E:\AndroidHome\.android`
- Gradle 分发走腾讯云镜像，Maven 走阿里云镜像（官方源超时）
- C 盘不落任何构建产物

### 为适配本机 SDK 做过的调整

| 问题 | 处理 |
|---|---|
| Flutter 插件要自动装 NDK 28.2.13676358，而新版 Android CLI 装不了 | 手动下载 `android-ndk-r28c` 解压到 `E:\AndroidSDK\ndk\28.2.13676358` |
| AGP 9.1 要 Build Tools 36.0.0，SDK 里只有 36.1.0 | 下载 `build-tools_r36_windows.zip` 补装 36.0.0 |
| 子模块 `jni` 要 `android-35` 平台 | 下载 `platform-35_r02.zip` 补装 android-35 |
| `flutter_local_notifications` 要求脱糖 | 开启 `isCoreLibraryDesugaringEnabled` 并加 `desugar_jdk_libs` |
| `path_provider → jni` 需要 CMake 编译原生代码 | 改用 sqflite 自带的 `getDatabasesPath()`，去掉 `path_provider`；同时去掉 `flutter_secure_storage`，Key 改存数据库 |
| 用 `dependencyResolutionManagement` 加镜像导致找不到 `io.flutter:*` | 移除该块，镜像只保留在 `pluginManagement` |

## 已知限制

- `flutter doctor` 中 Windows 版本 / Visual Studio / Edge 三项因沙箱禁用 `wmic.exe`、`reg.exe` 而崩溃，不影响 Android 构建
- 只编了 arm64；32 位老机型需重编并加 `--target-platform android-arm`
- 每日提醒用 `periodicallyShow`（非精确闹钟），重启手机后需打开一次 App 才会恢复
- 国产 ROM 需在系统设置中允许自启动与后台运行
