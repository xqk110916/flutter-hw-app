# PAD 离线作业 — 实物盘存

面向仓储管理场景的 Flutter 离线盘存应用。支持导入 JSON 任务单、扫码/手动查询容器、录入盘存结果（正常/盘盈/盘亏）、本地磁盘导出，所有数据持久化在设备本地，无需联网。

> 详细业务逻辑、操作流程、数据结构说明请参阅 **[BUSINESS_GUIDE.md](BUSINESS_GUIDE.md)**。

## 技术栈

| 类别 | 技术 | 版本 |
|------|------|------|
| 框架 | Flutter | Dart SDK `^3.11.5` |
| 语言 | Dart | 3.x (null-safety) |
| 文件选择 | [file_picker](https://pub.dev/packages/file_picker) | `^10.3.7` |
| 二维码扫描 | [mobile_scanner](https://pub.dev/packages/mobile_scanner) | `^7.1.3` |
| 本地存储 | [shared_preferences](https://pub.dev/packages/shared_preferences) | `^2.5.4` |
| 图标 | [cupertino_icons](https://pub.dev/packages/cupertino_icons) | `^1.0.8` |
| 应用图标生成 | [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons) | `^0.13.1` (dev) |
| 代码规范 | [flutter_lints](https://pub.dev/packages/flutter_lints) | `^6.0.0` (dev) |

> 无第三方状态管理库（无 Bloc/Riverpod/Provider），无网络请求库（无 Dio），无路由框架（无 GoRouter）。采用原生 `setState` + `SharedPreferences` 的轻量方案。

## Android 构建配置

| 字段 | 值 |
|------|------|
| applicationId | `com.example.hw_app` |
| namespace | `com.example.hw_app` |
| compileSdk | Flutter 默认（当前 `35`） |
| minSdk | Flutter 默认（当前 `21`） |
| targetSdk | Flutter 默认（当前 `35`） |
| Java 兼容 | `Java 17` |
| Kotlin JVM Target | `17` |
| Release 签名 | `android/app/hw-release.jks`（RSA 2048，有效期 30 年） |

> **注意**: `applicationId` 当前为 `com.example.hw_app`，发布前需替换为正式包名。

### Release 签名配置

| 文件 | 路径 | 说明 |
|------|------|------|
| 密钥库 | `android/app/hw-release.jks` | 已提交到仓库 |
| 签名配置 | `android/app/key.properties` | 已加入 `.gitignore`，需本地维护 |

`key.properties` 格式：

```properties
storePassword=你的密钥库密码
keyPassword=你的密钥密码
keyAlias=hw-release
storeFile=hw-release.jks
```

首次构建前需在 `android/app/` 下创建 `key.properties` 并填入正确的密码。`build.gradle.kts` 会自动读取该文件配置 Release 签名。

## 环境与运行指南

### 前置条件

- Flutter SDK ≥ 3.x（Dart SDK `^3.11.5`）
- Android Studio 或 VS Code + Flutter 插件
- JDK 17
- Android 设备/模拟器（API 21+）或 Windows 桌面环境

### 快速启动

```bash
# 1. 安装依赖
flutter pub get

# 2. 调试运行（连接设备或模拟器）
flutter run

# 3. 一键打包（Windows 下双击 build.bat）
#    或手动执行：
flutter build apk --release        # Android APK
flutter build windows --release    # Windows 桌面
flutter build web --release        # Web 静态页面
```

### 构建产物路径

| 平台 | 输出路径 |
|------|----------|
| Android | `build/app/outputs/flutter-apk/app-release.apk` |
| Windows | `build/windows/x64/runner/Release/` |
| Web | `build/web/` |

## 目录结构

```
hw-app-new/
├── android/                  # Android 原生工程
│   └── app/
│       └── build.gradle.kts  # Android 构建配置 (Kotlin DSL)
├── assets/
│   └── logo.png              # 应用图标源文件
├── ios/                      # iOS 原生工程（模板）
├── lib/
│   └── main.dart             # 全部业务代码（单文件）
├── linux/                    # Linux 原生工程
├── macos/                    # macOS 原生工程
├── test/                     # 测试目录
├── web/                      # Web 工程
├── windows/                  # Windows 原生工程
├── build.bat                 # Windows 一键打包脚本
├── pubspec.yaml              # 依赖与项目元数据
└── analysis_options.yaml     # Dart 静态分析规则
```

## 架构说明

### 整体模式

项目采用 **单文件单体架构**（Monolithic Single-File），所有 UI 与业务逻辑集中在 `lib/main.dart`（约 1924 行）。无分层目录、无独立 Model/Service/Widget 文件。

### 核心类结构

```
main.dart
├── InventoryApp                          # MaterialApp 根组件
│   └── InventoryHomePage                 # 主页面 (StatefulWidget)
│       └── _InventoryHomePageState       # 状态与业务逻辑
│           ├── 数据管理
│           │   ├── taskData              # 任务单数据 (Map?)
│           │   ├── loadDefaultFiles()    # 启动时从 SP 加载
│           │   ├── autoLoadFromDefaultPath() # 默认路径自动导入
│           │   ├── chooseInventoryFile() # FilePicker 导入
│           │   ├── parseInventoryContent() # JSON 解析与校验
│           │   ├── writeWorkFile()       # 写回 SP
│           │   └── saveToLocalDisk()     # 导出至本地文件系统
│           ├── 扫码查询
│           │   ├── searchContainer()     # 手动输入查询
│           │   ├── openScanner()         # 摄像头扫码
│           │   └── parseQrActual()       # 二维码 JSON 解析
│           ├── 结果录入
│           │   ├── submitInventoryResult()  # 提交入口
│           │   ├── saveMatchedInventoryResult()   # 列表内容器
│           │   └── saveUnmatchedInventoryResult() # 盘盈容器
│           └── UI 构建
│               ├── buildHeader()         # 顶栏（标题+文件状态）
│               ├── buildStatsRow()       # 统计卡片（已加载/已盘存/未盘存/异常）
│               ├── buildControlPanel()   # 左侧控制面板
│               ├── buildListPanel()      # 列表面板
│               └── buildDetailPanel()    # 容器详情面板
├── ScannerPage                           # 摄像头扫码页面
└── 顶层工具函数
    ├── getWarehouseList() / getGoodsList()  # 数据提取
    ├── findContainerInData()                # 容器检索
    ├── normalizeOldArray()                  # 旧格式兼容
    └── formatDateTime() / fieldLabel() 等   # 格式化工具
```

### 数据流

```
┌──────────────────────────────────────────────────┐
│                  SharedPreferences                │
│  ┌─────────────────────┐  ┌────────────────────┐ │
│  │ sourceKey (原始备份) │  │ workKey (工作文件)  │ │
│  └─────────┬───────────┘  └────────┬───────────┘ │
└────────────┼───────────────────────┼─────────────┘
             │ 启动加载              │ 启动加载（优先）
             ▼                      ▼
┌─────────────────────────────────────────────────┐
│              taskData (Map<String,dynamic>?)     │
│              内存中的完整任务单数据                │
└────────────┬────────────────────┬───────────────┘
             │ 查询/扫码           │ 录入结果
             ▼                    ▼
┌─────────────────┐  ┌─────────────────────────┐
│   UI 渲染展示    │  │ applyResultFields() →   │
│   setState()    │  │ saveTaskData() → SP 写回 │
└─────────────────┘  └─────────────────────────┘
```

### 数据持久化机制

应用使用 `SharedPreferences` 维护两份数据：

| Key | 用途 | 写入时机 |
|-----|------|----------|
| `hw-flutter-app.inventory-source` | 原始 JSON 备份 | 用户导入文件时 |
| `hw-flutter-app.inventory-work` | 工作文件（含盘存结果） | 导入时生成 + 每次提交盘存结果时更新 |
| `hw-flutter-app.loaded-file-name` | 已加载文件名 | 导入时记录 |
| `hw-flutter-app.settings.read-path` | 自动读取目录 | 默认 `data/Document/hw/original` |
| `hw-flutter-app.settings.save-path` | 结果导出目录 | 默认 `data/Document/hw/result` |

启动加载优先级：**工作文件 > 原始备份 > 默认路径自动加载 > 等待导入**。

### 支持的 JSON 数据格式

应用兼容两种 JSON 结构：

**格式一：任务单对象（推荐）**
```json
{
  "inventory": { "taskNum": "TASK-001", "warehouseNames": "库房A" },
  "warehouseList": [
    {
      "warehouseId": "W01",
      "warehouseName": "库房A",
      "goodsList": [
        { "containerCode": "C001", "goodCode": "G001", ... }
      ]
    }
  ]
}
```

**格式二：扁平数组（旧格式兼容）**
```json
[
  { "containerCode": "C001", "warehouseName": "库房A", ... },
  { "containerCode": "C002", "warehouseName": "库房A", ... }
]
```

扁平数组会被自动按 `warehouseName` 分组归入 `warehouseList`。

### 盘存结果状态

| 值 | 含义 | 颜色标识 |
|----|------|----------|
| `0` | 正常 | 绿色 |
| `1` | 盘亏 | 红色 |
| `2` | 盘盈 | 蓝色 |
| `null` | 未盘存 | 灰色 |

## 多端适配

项目支持 Android、Windows、Web、iOS、macOS、Linux 六端构建。UI 层通过 `LayoutBuilder` 检测宽度（≥900px 触发宽屏布局），自动切换横纵排列。

- **宽屏模式**：左侧控制面板 + 右侧主面板（列表/详情可并排）
- **窄屏模式**：上下堆叠排列
