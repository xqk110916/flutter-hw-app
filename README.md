# PAD 离线作业 — 实物盘存

面向仓储管理场景的 Flutter 离线盘存应用。支持导入 JSON 任务单、扫码/手动查询容器、录入盘存结果（正常/不正常）、按库房汇总盘盈盘亏并本地磁盘导出，所有数据持久化在设备本地，无需联网。

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
| AST 分析 | [analyzer](https://pub.dev/packages/analyzer) | `^10.0.1` (dev) |
| 路径处理 | [path](https://pub.dev/packages/path) | `^1.9.1` (dev) |

> 无第三方状态管理库（无 Bloc/Riverpod/Provider），无网络请求库（无 Dio），无路由框架（无 GoRouter）。采用原生 `setState` + `SharedPreferences` 的轻量方案。

### 状态管理与路由架构

```
┌─────────────────────────────────────────────────────────────┐
│                      MaterialApp                            │
│  theme: Material3 (seedColor: #1f4e79)                      │
│  home: InventoryHomePage                                    │
├─────────────────────────────────────────────────────────────┤
│  路由方式: Navigator 1.0 (无命名路由表)                       │
│  InventoryHomePage ←→ ScannerPage (MaterialPageRoute)       │
├─────────────────────────────────────────────────────────────┤
│  状态管理: setState() (原生)                                 │
│                                                             │
│  StatefulWidget                                              │
│  └── State._InventoryHomePageState                          │
│      ├── 15 个可变状态字段 (taskData, currentContainer...)  │
│      ├── 17 个计算属性 getter (warehouses, hasData...)      │
│      └── 47 个实例方法 (业务逻辑 + UI 构建)                  │
└─────────────────────────────────────────────────────────────┘
```

**Widget 继承关系**（基于 AST 提取）：

```
StatelessWidget
└── InventoryApp                    # 应用根，配置主题与入口

StatefulWidget
├── InventoryHomePage               # 主页面，createState → _InventoryHomePageState
└── ScannerPage                     # 扫码页面，createState → _ScannerPageState

State
├── _InventoryHomePageState         # 核心状态：数据管理 + 扫码查询 + 结果录入 + UI
└── _ScannerPageState               # 扫码状态：handled 标记防重复
```

### 核心模块依赖字典

基于 `project_graph.json` 提取的高频引用模块：

| 模块 | 类型 | 被引用次数 | 职责边界 |
|------|------|-----------|----------|
| `_InventoryHomePageState` | State | 全局核心 | 唯一的状态容器，持有全部业务数据和 UI 构建逻辑 |
| `SharedPreferences` | 外部依赖 | 5 个 SP 键 | 持久化存储层：原始备份、工作文件、文件名、路径配置 |
| `FilePicker` | 外部依赖 | 1 处 | 文件系统交互：选择 JSON/TXT 导入文件 |
| `MobileScanner` | 外部依赖 | 1 处 | 摄像头硬件交互：二维码扫描 |
| `TextEditingController` | Flutter | 2 个实例 | 输入控制：scanController（扫码框）、remarkController（备注框） |

**顶层工具函数**（纯函数，无副作用）：

| 函数 | 签名 | 职责 |
|------|------|------|
| `getWarehouseList` | `(Map<String,dynamic>?) → List<Map<String,dynamic>>` | 从任务单提取库房列表 |
| `getGoodsList` | `(Map<String,dynamic>) → List<Map<String,dynamic>>` | 从库房提取容器列表 |
| `findContainerInData` | `(Map, String) → Map?` | 按容器号全局检索 |
| `stringField` | `(Map, String) → String` | 安全提取字符串字段 |
| `isContainerChecked` | `(Map) → bool` | 判断容器是否已盘存 |
| `resultLabel` | `(int) → String` | 结果码转中文标签 |
| `formatDateTime` | `(DateTime) → String` | 日期格式化为 `yyyy-MM-dd HH:mm:ss` |

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
| Release 签名 | 使用 debug 签名（最终安装时由内部签名流程覆盖） |

> **注意**: `applicationId` 当前为 `com.example.hw_app`，发布前需替换为正式包名。

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

项目采用 **单文件单体架构**（Monolithic Single-File），所有 UI 与业务逻辑集中在 `lib/main.dart`（约 2476 行）。无分层目录、无独立 Model/Service/Widget 文件。

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
│           │   ├── submitInventoryResult()  # 提交入口（逐条）
│           │   ├── saveMatchedInventoryResult()   # 列表内容器
│           │   └── saveUnmatchedInventoryResult() # 列表外容器（标为不正常）
│           ├── 保存汇总
│           │   ├── confirmSaveInventory()        # 全盘校验 + 强制保存
│           │   ├── openInventorySummaryDialog()  # 按库房构建盘盈盘亏弹窗
│           │   └── persistInventorySummary()     # 写库房级/任务级汇总并导出
│           └── UI 构建
│               ├── buildHeader()         # 顶栏（标题+文件状态）
│               ├── buildStatsRow()       # 统计卡片（已加载/已盘存/未盘存/异常）
│               ├── buildControlPanel()   # 左侧控制面板（含"保存盘存"按钮）
│               ├── buildListPanel()      # 列表面板
│               └── buildDetailPanel()    # 容器详情面板
├── ScannerPage                           # 摄像头扫码页面
├── InventorySummaryDialog                # 盘盈盘亏汇总弹窗（按库房填写）
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
| `hw-flutter-app.settings.read-path` | 自动读取目录 | 默认 `/data/userdata/ZM/DR` |
| `hw-flutter-app.settings.save-path` | 结果导出目录 | 默认 `/data/userdata/ZM/DC`，不可用时提示手动选择 |

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
| `1` | 不正常 | 红色 |
| `null` | 未盘存 | 灰色 |

> 盘盈/盘亏不再逐条录入容器，改由"保存盘存"时按库房汇总录入。完整的盘盈盘亏汇总字段（库房级 + 任务级，供 PC 导入）见 [BUSINESS_GUIDE.md](BUSINESS_GUIDE.md) 第 5.4 节。

## 多端适配

项目支持 Android、Windows、Web、iOS、macOS、Linux 六端构建。UI 层通过 `LayoutBuilder` 检测宽度（≥900px 触发宽屏布局），自动切换横纵排列。

- **宽屏模式**：左侧控制面板 + 右侧主面板（列表/详情可并排）
- **窄屏模式**：上下堆叠排列
