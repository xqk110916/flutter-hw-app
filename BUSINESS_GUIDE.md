# PAD 离线作业 — 实物盘存系统 · 业务与开发指南

> **本文档与 README.md 为项目核心文档，任何功能变更（新增/修改/删除）必须同步更新两份文档。**

---

## 一、业务概述

本系统是面向仓储管理场景的 **Android PAD 离线盘存工具**。核心流程：

1. **导入** — 从 PC 端导出的 JSON 任务单导入到 PAD
2. **盘点** — 通过扫码枪或摄像头扫描容器二维码，或手动输入容器号查询
3. **录入** — 对每个容器录入盘存结果（正常 / 不正常）和备注
4. **保存汇总** — 点击"保存盘存"，按库房录入盘盈数/盘亏数并落盘
5. **导出** — 将含盘存结果与盘盈盘亏汇总的工作文件导出回 PC

整个流程**无需联网**，所有数据持久化在设备本地。

---

## 二、用户操作流程

```
启动应用
  │
  ├─ 自动检测默认路径 → 有文件 → 自动导入 → 进入工作台
  │                    → 无文件 → 显示"等待导入"面板
  │
  ├─ 手动导入 JSON 文件（FilePicker 选择 .json/.txt）
  │
  └─ 加载工作台后：
       ├─ 扫码/手动输入容器号 → 匹配盘存列表 → 录入结果（正常/不正常）
       │                     → 不在列表中 → 自动设为不正常
       ├─ 查看列表（已盘存/未盘存/异常）→ 点击容器 → 录入结果
       └─ 保存盘存 → 校验全盘完成（未完成可强制保存）
                   → 按库房录入盘盈数/盘亏数 → 确定 → 落盘导出
```

---

## 三、数据导入机制

### 3.1 启动加载优先级

应用启动时 `loadDefaultFiles()` 按以下顺序尝试加载数据：

| 优先级 | 来源 | SharedPreferences Key | 说明 |
|--------|------|----------------------|------|
| 1 | 工作文件 | `hw-flutter-app.inventory-work` | 含盘存结果的完整数据，直接加载 |
| 2 | 原始备份 | `hw-flutter-app.inventory-source` | 首次导入时的原始 JSON，解析后生成工作文件 |
| 3 | 默认路径自动加载 | — | 扫描设备本地目录，详见 3.3 |
| 4 | 等待导入 | — | 以上均无数据，显示导入引导 |

### 3.2 手动导入

- 用户点击 **"导入 JSON 文件"** 按钮
- 通过 `FilePicker` 选择 `.json` 或 `.txt` 文件
- 系统将原始内容存入 `sourceKey`，解析后存入 `workKey`
- 同时记录文件名到 `hw-flutter-app.loaded-file-name`

### 3.3 默认路径自动加载

应用维护两个可配置的本地路径（存储在 SharedPreferences）：

| 配置项 | Key | 默认值 | 用途 |
|--------|-----|--------|------|
| 读取路径 | `hw-flutter-app.settings.read-path` | `/data/userdata/ZM/DR` | 自动扫描此目录下最新的 JSON/TXT 文件导入 |
| 保存路径 | `hw-flutter-app.settings.save-path` | `/data/userdata/ZM/DC` | 导出结果文件的存放目录 |

> **保存路径不可用兜底**：点击"保存盘存"时，若配置的保存路径无法创建或写入，弹出确认框提示，用户确认后通过目录选择器（`FilePicker.getDirectoryPath`）选择保存目录，结果文件 `{原文件名}_result.json` 写入该目录；仅本次生效，不写回配置项。

自动加载逻辑：
- 扫描读取路径下所有 `.json` / `.txt` 文件
- 按**最后修改时间降序**排列，取最新文件
- 解析成功后自动导入并写入 SharedPreferences

---

## 四、核心业务功能

### 4.1 容器查询与扫码

| 功能 | 入口 | 说明 |
|------|------|------|
| 手动输入查询 | 搜索框 + 确认键 | 输入容器号，精确匹配盘存列表 |
| 摄像头扫码 | "扫码"按钮 | 调用 `mobile_scanner` 读取二维码，跳转 `ScannerPage` |
| 扫码枪输入 | 搜索框直接接收 | 扫码枪模拟键盘输入到搜索框 |

**二维码格式**：扫码支持两种输入——

1. **纯文本容器号** — 直接作为 `containerCode` 匹配
2. **JSON 数组** — 二维码内容为 `[{fileValue, value, name, sortOrder}, ...]` 格式，解析后提取 `containerCode` 并与盘存列表中的其他字段对比差异

**位置字段显示**：二维码字段网格在以下规则下展示"位置"行——

- 二维码**携带** `location` → 作为普通字段按 `sortOrder` 显示，并参与字段差异对比
- 二维码**未携带** `location` → 在网格**最底部追加**"位置"行，取值来自盘存列表（`location` 或 `shelf-row-column`），**不参与对比**

**匹配结果处理**：

| 场景 | 行为 |
|------|------|
| 在列表中且无差异 | 显示容器详情，等待录入结果 |
| 在列表中但有字段差异 | 显示容器详情 + 差异对比面板（红色高亮不一致字段） |
| 不在列表中 | 自动设为**不正常**，备注"不在列表中"，用户需选择归属库房 |

### 4.2 盘存结果录入

每个容器可录入以下信息：

| 字段 | 说明 |
|------|------|
| **盘存结果** | `0`=正常（绿）、`1`=不正常（红）；盘盈/盘亏不再逐条录入，改为保存时按库房汇总 |
| **备注** | 自由文本 + 快捷标签（位置错误 / 铅封状态异常 / 不在列表中 / 其他）；具体容器的盈亏归属可在备注中体现 |
| **提交时间** | 自动记录 `inventorySubmitTime` |
| **数据来源** | 自动标记 `inventorySource: "pad"` |

**快捷备注机制**：
- 点击预设标签自动追加到备注文本
- 已存在的标签不会重复追加
- 多个标签之间用 `；` 分隔

### 4.3 保存盘存与盘盈盘亏汇总

- 功能入口：控制面板（扫码框下方）的 **"保存盘存"** 按钮
- **全盘校验**：点击后检查是否所有容器均已盘存；若存在未盘存容器，提示"还有 X 个未盘存，是否强制保存？"，允许**强制保存**继续
- **盘盈盘亏弹窗**（按库房填写）：
  - 顶部合计行：`合计：不正常 N 个 / 未盘存 X 个`
  - 每个非空库房一行：`库房名　不正常 N_wh 个 / 未盘存 X_wh 个` + 盘盈数输入 + 盘亏数输入
  - 输入无默认值，**必须手填（允许填 0）**
  - **校验规则**：每个库房 `盘盈数 + 盘亏数 == 该库房不正常数`，否则拦截并提示具体库房
  - 未盘存数 X 仅为提示，不参与校验；未盘存容器保持 `result=null`
- **落盘**：点击"确定"后，写入库房级与任务级汇总字段，重新导出 `{原文件名}_result.json`；重复保存覆盖上次数据

### 4.4 列表查看与筛选

四个统计卡片可切换不同视图：

| 卡片 | 筛选条件 | 颜色 |
|------|----------|------|
| 已加载 | 全部容器 | 蓝色 |
| 已盘存 | `result` 不为 null | 绿色 |
| 未盘存 | `result` 为 null | 红色 |
| 异常 | `result` 为 1（不正常） | 黄色 |

列表支持**库房筛选**下拉框，按库房维度过滤容器。

### 4.5 文件管理

| 操作 | 功能 | 确认弹窗 |
|------|------|----------|
| 清除文件 | 删除 SP 中的 sourceKey、workKey、文件名，重置所有状态 | 是 |
| 重新导入 | 清除当前数据后打开文件选择器 | 是 |

### 4.6 本地磁盘导出

`saveToLocalDisk()` 将当前工作数据写回设备文件系统：

- 导出路径：`_savePath`（默认 `/data/userdata/ZM/DC`）；若该路径无法创建或写入，弹确认框提示用户选择保存目录（`FilePicker.getDirectoryPath`），结果文件写入该目录
- 文件命名：`{原始文件名}_result.json`（如原始为 `task001.json`，导出为 `task001_result.json`）
- 若原始文件名不存在，尝试用任务单号命名，否则命名为 `task_result.json`
- 自动创建不存在的目录

---

## 五、数据结构

### 5.1 支持的 JSON 导入格式

**格式一：任务单对象（推荐）**

```json
{
  "inventory": {
    "taskNum": "PD-20250101-001",
    "warehouseNames": "库房A,库房B"
  },
  "warehouseList": [
    {
      "warehouseId": "W01",
      "warehouseName": "库房A",
      "goodsList": [
        {
          "containerCode": "RQ-001",
          "goodCode": "CL-001",
          "goodName": "材料名称",
          "productionUnit": "生产单位A",
          "warehouseName": "库房A",
          "createUname": "张三",
          "storageTime": "2025-01-01 10:00:00",
          "location": "A-01-02",
          "sealCode1": "FJ001",
          "sealCode2": "FJ002"
        }
      ]
    }
  ]
}
```

**格式二：扁平数组（旧格式兼容）**

```json
[
  { "containerCode": "RQ-001", "warehouseName": "库房A", ... },
  { "containerCode": "RQ-002", "warehouseName": "库房A", ... }
]
```

扁平数组会被 `normalizeOldArray()` 按 `warehouseName` 分组，归入 `warehouseList`。无 `warehouseName` 的条目归入"未归属库房"。

**必填字段**：每条容器记录必须包含 `containerCode`，否则导入失败。

### 5.2 盘存结果写入字段

提交盘存结果时，`applyResultFields()` 向容器对象写入：

```json
{
  "result": 0,
  "remark": "位置错误",
  "resultRemark": "位置错误",
  "inventorySubmitTime": "2025-06-04 14:30:00",
  "inventorySource": "pad"
}
```

> `result` 取值：`0`=正常、`1`=不正常、`null`=未盘存。盘盈/盘亏不再逐条记录于容器，改由保存时的盘盈盘亏汇总承接（见 5.4）。

### 5.3 二维码 JSON 格式

扫码识别的二维码内容为 JSON 数组：

```json
[
  { "fileValue": "containerCode", "value": "RQ-001", "name": "容器号", "sortOrder": 1 },
  { "fileValue": "goodCode", "value": "CL-001", "name": "材料代码", "sortOrder": 2 }
]
```

系统按 `sortOrder` 排序后构建实际数据字典，与盘存列表逐字段对比差异。

### 5.4 盘盈盘亏汇总数据结构（PC 导入字段规范）

点击"保存盘存"并在弹窗中填写盘盈盘亏后，结果写入工作文件的两个层级。**PC 端按以下字段导入**。

**库房级**（`warehouseList[i]`，每个库房对象新增/更新以下字段）：

| 字段 | 类型 | 含义 | 来源 |
|------|------|------|------|
| `normalCount` | int | 正常容器数（`result=0`） | 自动统计 |
| `abnormalCount` | int | 不正常容器数（`result=1`）= 该库房 N_wh | 自动统计 |
| `uncheckedCount` | int | 未盘存容器数（`result=null`）= X_wh | 自动统计 |
| `excessCount` | int | **盘盈数（容器个数，操作员手填）** | 盘盈盘亏弹窗 |
| `deficitCount` | int | **盘亏数（容器个数，操作员手填）** | 盘盈盘亏弹窗 |

**任务级汇总**（`inventory` 对象，= 各库房对应字段求和）：

| 字段 | 类型 | 含义 | 来源 |
|------|------|------|------|
| `totalCount` | int | 容器总数 | 各库房 goodsList 求和 |
| `checkedCount` | int | 已盘存数 = `totalCount - uncheckedCount` | 计算 |
| `uncheckedCount` | int | 未盘存数（各库房求和） | 求和 |
| `normalCount` | int | 正常数（各库房求和） | 求和 |
| `abnormalCount` | int | 不正常数 N（各库房求和） | 求和 |
| `excessCount` | int | **盘盈数（各库房求和）** | 求和 |
| `deficitCount` | int | **盘亏数（各库房求和）** | 求和 |
| `inventoryComplete` | bool | 是否全部盘存完成（`false`=强制保存） | 保存校验 |
| `inventorySaveTime` | String | 保存时间，格式 `yyyy-MM-dd HH:mm:ss` | 自动 |

**字段格式约定**：

- 所有计数均为非负整数（`int`），盘盈/盘亏允许为 `0`
- 校验不变量：每个库房 `excessCount + deficitCount == abnormalCount`
- `inventoryComplete=false` 时，`uncheckedCount` 可能 > 0，PC 可据此判断数据完整性
- 盘盈/盘亏仅存于计数层级，**不标注具体哪些容器**为盈或亏；逐条盈亏归属由操作员写入容器 `remark`

```json
{
  "inventory": {
    "taskNum": "PD-20250101-001",
    "warehouseNames": "库房A,库房B",
    "totalCount": 100,
    "checkedCount": 95,
    "uncheckedCount": 5,
    "normalCount": 90,
    "abnormalCount": 5,
    "excessCount": 3,
    "deficitCount": 2,
    "inventoryComplete": false,
    "inventorySaveTime": "2026-06-17 14:30:00"
  },
  "warehouseList": [
    {
      "warehouseId": "W01",
      "warehouseName": "库房A",
      "goodsList": [],
      "normalCount": 90,
      "abnormalCount": 3,
      "uncheckedCount": 1,
      "excessCount": 2,
      "deficitCount": 1
    }
  ]
}
```

---

## 六、SharedPreferences 键值一览

| Key | 类型 | 用途 |
|-----|------|------|
| `hw-flutter-app.inventory-source` | String | 原始 JSON 文件内容备份 |
| `hw-flutter-app.inventory-work` | String | 工作文件（含盘存结果） |
| `hw-flutter-app.loaded-file-name` | String | 当前加载的文件名 |
| `hw-flutter-app.settings.read-path` | String | 自动读取目录路径 |
| `hw-flutter-app.settings.save-path` | String | 结果导出目录路径 |

---

## 七、UI 布局说明

### 7.1 响应式布局

- **宽屏**（宽度 ≥ 900px）：左侧控制面板（320px）+ 右侧主面板
- **窄屏**（宽度 < 900px）：上下堆叠排列
- 宽屏下列表面板（380px）和详情面板可并排显示

### 7.2 页面组成

```
┌─────────────────────────────────────────────────────┐
│ Header：标题 + 文件状态 Chip + 操作按钮              │
├─────────┬──────────┬──────────┬──────────┬──────────┤
│ 已加载   │ 已盘存    │ 未盘存    │ 异常      │ 统计卡片 │
├─────────┴──────────┴──────────┴──────────┴──────────┤
│                                                     │
│  ┌─ 控制面板 ──┐   ┌─ 主面板 ──────────────────────┐ │
│  │ 任务单卡片   │   │ 列表面板（可选）               │ │
│  │ 扫码输入框   │   │ + 库房筛选 + 容器列表          │ │
│  │ + 扫码按钮   │   │                               │ │
│  │ + 保存盘存   │   │ 详情面板                        │ │
│  │             │   │ + 容器信息 + 差异对比           │ │
│  │             │   │ + 盘存结果选择 + 备注 + 提交    │ │
│  └─────────────┘   └───────────────────────────────┘ │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 7.3 物理返回键

双击退出机制：首次按返回键显示 Toast "再按一次退出应用"，2 秒内再次按下则退出应用（`SystemNavigator.pop()`）。

---

## 八、打包与构建

### 8.1 一键打包脚本

项目根目录 `build.bat` 为 Windows 下的交互式打包工具，支持：

| 选项 | 命令 | 说明 |
|------|------|------|
| 1 | `flutter build windows --release` | 编译 Windows 桌面应用 |
| 2 | `flutter build apk --release` | 编译 Android APK |
| 3 | `flutter build web --release` | 编译 Web 静态页面 |
| 4 | 依次执行以上三项 | 编译全部平台 |
| 5 | `flutter clean` | 清理项目缓存 |

### 8.2 手动构建命令

```bash
# Android APK（Release）
flutter build apk --release

# Android AppBundle（用于上架应用商店）
flutter build appbundle --release

# Windows 桌面
flutter build windows --release

# Web
flutter build web --release
```

### 8.3 构建产物路径

| 平台 | 产物路径 |
|------|----------|
| Android APK | `build/app/outputs/flutter-apk/app-release.apk` |
| Android AppBundle | `build/app/outputs/bundle/release/app-release.aab` |
| Windows | `build/windows/x64/runner/Release/` |
| Web | `build/web/` |

### 8.4 Android 构建配置摘要

| 字段 | 值 |
|------|------|
| applicationId | `com.example.hw_app` |
| compileSdk | Flutter 默认（当前 `35`） |
| minSdk | Flutter 默认（当前 `21`） |
| targetSdk | Flutter 默认（当前 `35`） |
| Java | `17` |
| Release 签名 | 使用 debug 签名（最终安装时由内部签名流程覆盖） |

> **发布前必做**：替换 `applicationId`。最终 APK 签名由内部安全流程在安装时处理，构建阶段无需额外配置。

---

## 九、Agent 开发规范

### 9.1 文档同步规则

> **强制要求**：任何 Agent 在修改代码功能（新增 / 修改 / 删除）后，必须同步更新以下两份文档：
>
> 1. **`README.md`** — 更新技术栈、目录结构、架构说明等受影响章节
> 2. **`BUSINESS_GUIDE.md`**（本文件）— 更新业务逻辑、数据结构、UI 布局、操作流程等受影响章节
>
> 判断标准：
> - 新增/删除依赖 → 更新 README.md 技术栈
> - 新增/修改/删除功能 → 更新 BUSINESS_GUIDE.md 对应章节
> - 修改数据结构或 SP 键值 → 更新 BUSINESS_GUIDE.md 第五章/第六章
> - 修改 UI 布局 → 更新 BUSINESS_GUIDE.md 第七章
> - 修改构建配置 → 更新 README.md 和 BUSINESS_GUIDE.md 第八章
> - 仅修改注释或样式微调（颜色值、间距）→ 无需更新文档

### 9.2 代码风格约定

- 项目采用单文件架构，所有业务代码在 `lib/main.dart`
- 状态管理使用原生 `setState`，不引入第三方状态管理库
- 注释语言与现有代码保持一致（中文）
- 修改后无需手动重启服务（Flutter 热更新自动生效）
