import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sourceKey = 'hw-flutter-app.inventory-source';
const workKey = 'hw-flutter-app.inventory-work';
const unassignedWarehouseName = '未归属库房';
// 默认读取目录（自动导入数据文件）
const defaultReadPath = '/data/userdata/ZM/DR';
// 默认保存目录（导出结果文件）
const defaultSavePath = '/data/userdata/ZM/DC';

void main() {
  runApp(const InventoryApp());
}

class InventoryApp extends StatelessWidget {
  const InventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '账目管理系统',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xfff4f6f8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff1f4e79),
          primary: const Color(0xff1f4e79),
          surface: Colors.white,
        ),
      ),
      home: const InventoryHomePage(),
    );
  }
}

class InventoryHomePage extends StatefulWidget {
  const InventoryHomePage({super.key});

  @override
  State<InventoryHomePage> createState() => _InventoryHomePageState();
}

class _InventoryHomePageState extends State<InventoryHomePage> {
  Map<String, dynamic>? taskData;
  Map<String, dynamic>? currentContainer;
  Map<String, dynamic>? matchedContainer;
  List<Map<String, dynamic>> actualDisplayFields = [];
  List<Map<String, String>> compareIssues = [];
  String fileStatus = '未加载';
  String scanText = '';
  String scanNotice = '';
  String remark = '';
  String activeListType = '';
  int selectedWarehouseFilterIndex = -1;
  int? selectedResult;
  bool currentShowsActual = false;
  DateTime? lastBackPressedAt;

  String? _readPath;
  String? _savePath;

  final scanController = TextEditingController();
  final remarkController = TextEditingController();
  final quickRemarks = const ['位置错误', '铅封状态异常', '不在列表中', '其他'];

  @override
  void initState() {
    super.initState();
    loadDefaultFiles();
  }

  @override
  void dispose() {
    scanController.dispose();
    remarkController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get warehouses => getWarehouseList(taskData);

  bool get hasData => taskData != null;

  int get warehouseCount => warehouses.length;

  int get totalCount => warehouses.fold(0, (sum, warehouse) {
    return sum + getGoodsList(warehouse).length;
  });

  int get checkedCount {
    var count = 0;
    for (final warehouse in warehouses) {
      for (final item in getGoodsList(warehouse)) {
        if (isContainerChecked(item)) count++;
      }
    }
    return count;
  }

  int get uncheckedCount => totalCount - checkedCount;

  int get abnormalCount {
    var count = 0;
    for (final warehouse in warehouses) {
      for (final item in getGoodsList(warehouse)) {
        if (isContainerAbnormal(item)) count++;
      }
    }
    return count;
  }

  String get taskNumText {
    final inventory = taskData?['inventory'];
    if (inventory is Map) {
      final taskNum = stringField(inventory.cast<String, dynamic>(), 'taskNum');
      return taskNum.isEmpty ? '-' : taskNum;
    }
    return '-';
  }

  String get activeListTitle {
    switch (activeListType) {
      case 'checked':
        return '已盘存列表';
      case 'unchecked':
        return '未盘存列表';
      case 'abnormal':
        return '异常列表';
      default:
        return '已加载列表';
    }
  }

  List<String> get warehouseFilterOptions {
    return ['全部库房', ...warehouses.map(getGroupWarehouseName)];
  }

  String get currentWarehouseFilterLabel {
    if (selectedWarehouseFilterIndex < 0 ||
        selectedWarehouseFilterIndex >= warehouses.length) {
      return '全部库房';
    }
    return getGroupWarehouseName(warehouses[selectedWarehouseFilterIndex]);
  }

  List<Map<String, dynamic>> get visibleWarehouseGroups {
    final groups = <Map<String, dynamic>>[];
    for (var i = 0; i < warehouses.length; i++) {
      if (selectedWarehouseFilterIndex >= 0 &&
          selectedWarehouseFilterIndex != i) {
        continue;
      }
      final goods = getGoodsList(warehouses[i])
          .where(shouldIncludeItem)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (goods.isNotEmpty) {
        groups.add({
          'warehouseId': stringField(warehouses[i], 'warehouseId'),
          'warehouseName': getGroupWarehouseName(warehouses[i]),
          'goodsList': goods,
        });
      }
    }
    return groups;
  }

  int get visibleCount {
    return visibleWarehouseGroups.fold(
      0,
      (sum, group) => sum + getGoodsList(group).length,
    );
  }

  String get currentResultLabel {
    if (selectedResult == null) return '未盘存';
    return resultLabel(selectedResult!);
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _readPath = prefs.getString('hw-flutter-app.settings.read-path') ?? defaultReadPath;
      _savePath = prefs.getString('hw-flutter-app.settings.save-path') ?? defaultSavePath;
    });
  }

  Future<void> loadDefaultFiles() async {
    await loadSettings();
    setState(() => fileStatus = '读取工作文件');
    final prefs = await SharedPreferences.getInstance();
    final work = prefs.getString(workKey);
    if (work != null && work.trim().isNotEmpty) {
      loadInventoryContent(work, '已加载工作文件');
      return;
    }

    setState(() => fileStatus = '读取原始文件');
    final source = prefs.getString(sourceKey);
    if (source != null && source.trim().isNotEmpty) {
      final parsed = parseInventoryContent(source);
      if (parsed == null) {
        setState(() => fileStatus = '原始文件无效');
        return;
      }
      await writeWorkFile(parsed);
      setState(() {
        taskData = parsed;
        fileStatus = '已生成工作文件';
      });
      return;
    }

    // Try auto-loading from default path
    setState(() => fileStatus = '检测默认路径');
    final readPath = _readPath ?? defaultReadPath;
    try {
      final dir = Directory(readPath);
      if (await dir.exists()) {
        final files = dir.listSync()
            .whereType<File>()
            .where((file) {
              final name = file.path.toLowerCase();
              return name.endsWith('.json') || name.endsWith('.txt');
            })
            .toList();
        if (files.isNotEmpty) {
          files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
          final latestFile = files.first;
          final content = await latestFile.readAsString();
          final fileName = latestFile.path.split(RegExp(r'[/\\]')).last;
          
          final parsed = parseInventoryContent(content);
          if (parsed != null) {
            await prefs.setString(sourceKey, content);
            await prefs.setString(workKey, jsonEncode(parsed));
            await prefs.setString('hw-flutter-app.loaded-file-name', fileName);
            setState(() {
              taskData = parsed;
              fileStatus = '自动导入: $fileName';
            });
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('初始自动从默认路径读取文件失败: $e');
    }

    setState(() => fileStatus = '等待导入');
  }

  Future<void> autoLoadFromDefaultPath() async {
    final readPath = _readPath ?? defaultReadPath;
    try {
      final dir = Directory(readPath);
      if (!await dir.exists()) {
        showToast('默认读取目录不存在: $readPath');
        return;
      }
      final files = dir.listSync()
          .whereType<File>()
          .where((file) {
            final name = file.path.toLowerCase();
            return name.endsWith('.json') || name.endsWith('.txt');
          })
          .toList();
      if (files.isEmpty) {
        showToast('默认读取目录下未找到 JSON 或 TXT 文件');
        return;
      }
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final latestFile = files.first;
      final content = await latestFile.readAsString();
      final fileName = latestFile.path.split(RegExp(r'[/\\]')).last;

      final parsed = parseInventoryContent(content);
      if (parsed == null) {
        showToast('解析该目录下最新的数据文件失败');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(sourceKey, content);
      await prefs.setString(workKey, jsonEncode(parsed));
      await prefs.setString('hw-flutter-app.loaded-file-name', fileName);
      setState(() {
        taskData = parsed;
        fileStatus = '自动导入: $fileName';
        clearCurrentState();
      });
      showToast('已成功从默认路径自动导入最新文件：$fileName');
    } catch (e) {
      showToast('从默认路径导入失败: $e');
    }
  }

  Future<String?> saveToLocalDisk(Map<String, dynamic> data) async {
    try {
      final savePath = _savePath ?? defaultSavePath;
      final dir = Directory(savePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final saveFileName = await resolveResultFileName(data);
      final fullPath = joinPath(savePath, saveFileName);
      await File(fullPath).writeAsString(jsonEncode(data), flush: true);
      return saveFileName;
    } catch (e) {
      debugPrint('同步写入本地文件失败: $e');
      return null;
    }
  }

  /// 推导结果文件名：{原始文件名或任务单号}_result.json
  Future<String> resolveResultFileName(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    String loadedName = prefs.getString('hw-flutter-app.loaded-file-name') ?? '';
    if (loadedName.isEmpty) {
      final inventory = data['inventory'];
      String taskNum = '';
      if (inventory is Map) {
        taskNum = (inventory['taskNum'] ?? '').toString().trim();
      }
      loadedName = (taskNum.isNotEmpty && taskNum != 'null') ? '$taskNum.json' : 'task.json';
    }
    final dotIndex = loadedName.lastIndexOf('.');
    final baseName = dotIndex != -1 ? loadedName.substring(0, dotIndex) : loadedName;
    return '${baseName}_result.json';
  }

  /// 拼接目录与文件名（兼容 / 与 \）
  String joinPath(String dir, String fileName) {
    if (dir.endsWith('/') || dir.endsWith('\\')) return '$dir$fileName';
    final separator = dir.contains('\\') ? '\\' : '/';
    return '$dir$separator$fileName';
  }

  /// 保存到本地磁盘：先尝试配置的保存路径，不可用则提示并让用户手动选择位置。
  /// 返回最终保存标识（文件名或完整路径），用于提示；用户全程取消返回 null。
  Future<String?> persistToLocalDisk(Map<String, dynamic> data) async {
    final fileName = await saveToLocalDisk(data);
    if (fileName != null) return fileName;

    final savePath = _savePath ?? defaultSavePath;
    if (!await confirmManualSave(savePath)) return null;
    return saveToManualLocation(data);
  }

  /// 让用户选择保存目录，在该目录下写入结果文件。
  /// Android 无系统级"另存为"对话框（saveFile 会返回 null），故采用选目录方式。
  /// 返回写入的完整路径；用户取消或写入失败返回 null。
  Future<String?> saveToManualLocation(Map<String, dynamic> data) async {
    final saveFileName = await resolveResultFileName(data);
    final dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择保存目录',
    );
    if (dirPath == null || dirPath.isEmpty) return null;
    final fullPath = joinPath(dirPath, saveFileName);
    try {
      await File(fullPath).writeAsString(jsonEncode(data), flush: true);
      return fullPath;
    } catch (e) {
      debugPrint('手动保存写入失败: $e');
      showToast('写入所选目录失败: $e');
      return null;
    }
  }

  /// 保存路径不可用时，确认是否手动选择保存位置。
  Future<bool> confirmManualSave(String unavailablePath) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('保存路径不可用'),
            content: Text('配置的保存路径无法创建或写入：\n$unavailablePath\n\n是否手动选择保存位置？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('手动选择'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void loadInventoryContent(String content, String status) {
    final parsed = parseInventoryContent(content);
    if (parsed == null) {
      setState(() => fileStatus = '文件无效');
      return;
    }
    setState(() {
      taskData = parsed;
      fileStatus = status;
    });
  }

  Future<void> chooseInventoryFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      showToast('未选择文件');
      return;
    }
    final bytes = result.files.single.bytes;
    if (bytes == null) {
      showToast('读取导入文件失败');
      return;
    }
    final fileName = result.files.single.name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hw-flutter-app.loaded-file-name', fileName);
    
    importSelectedContent(utf8.decode(bytes));
  }

  Future<void> importSelectedContent(String content) async {
    final parsed = parseInventoryContent(content);
    if (parsed == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(sourceKey, content);
    await prefs.setString(workKey, jsonEncode(parsed));
    setState(() {
      taskData = parsed;
      fileStatus = '已导入工作文件';
      clearCurrentState();
    });
    showToast('导入成功');
  }

  Map<String, dynamic>? parseInventoryContent(String content) {
    try {
      final text = content.trim();
      final decoded = jsonDecode(text);
      if (decoded is List) {
        final list = decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        for (final item in list) {
          if (stringField(item, 'containerCode').isEmpty) {
            showToast('JSON 缺少容器号字段');
            return null;
          }
        }
        return normalizeOldArray(list);
      }
      if (decoded is Map) {
        final root = Map<String, dynamic>.from(decoded);
        final warehouseList = getWarehouseList(root);
        if (warehouseList.isEmpty) {
          showToast('JSON 缺少 warehouseList');
          return null;
        }
        for (final warehouse in warehouseList) {
          for (final item in getGoodsList(warehouse)) {
            if (stringField(item, 'containerCode').isEmpty) {
              showToast('JSON 缺少容器号字段');
              return null;
            }
          }
        }
        root['warehouseList'] = warehouseList;
        return root;
      }
      showToast('JSON 根节点必须是任务单对象');
      return null;
    } catch (_) {
      showToast('JSON 解析失败');
      return null;
    }
  }

  Map<String, dynamic> normalizeOldArray(List<Map<String, dynamic>> list) {
    final groups = <Map<String, dynamic>>[];
    for (final item in list) {
      var warehouseName = stringField(item, 'warehouseName');
      if (warehouseName.isEmpty) warehouseName = unassignedWarehouseName;
      var index = groups.indexWhere(
        (group) => getGroupWarehouseName(group) == warehouseName,
      );
      if (index < 0) {
        groups.add({
          'warehouseId': stringField(item, 'warehouseId'),
          'warehouseName': warehouseName,
          'goodsList': <Map<String, dynamic>>[],
          'normalCount': 0,
          'excessCount': 0,
          'deficitCount': 0,
        });
        index = groups.length - 1;
      }
      getGoodsList(groups[index]).add(item);
    }
    return {
      'inventory': {'taskNum': '', 'warehouseNames': ''},
      'warehouseList': groups,
    };
  }

  Future<void> writeWorkFile(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(workKey, jsonEncode(data));
  }

  Future<void> confirmClearFiles() async {
    final confirmed = await showConfirmDialog(
      title: '清除文件',
      content: '将删除当前导入的原始备份和盘存工作文件，已录入结果也会从本机清除。',
    );
    if (!confirmed) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(sourceKey);
    await prefs.remove(workKey);
    await prefs.remove('hw-flutter-app.loaded-file-name');
    setState(() {
      taskData = null;
      fileStatus = '等待导入';
      clearCurrentState();
      activeListType = '';
      selectedWarehouseFilterIndex = -1;
    });
    showToast('已清除当前文件');
  }

  Future<void> confirmReimport() async {
    final confirmed = await showConfirmDialog(
      title: '重新导入',
      content: '重新导入会覆盖当前工作文件，已录入的盘存结果将被新文件替换。',
    );
    if (confirmed) chooseInventoryFile();
  }

  void searchByInput() {
    searchContainer(scanController.text);
  }

  void searchContainer(String rawCode) {
    final code = rawCode.trim();
    if (code.isEmpty) {
      showToast('请输入容器号或二维码 JSON');
      return;
    }
    final data = taskData;
    if (data == null) {
      showToast('请先导入任务单');
      return;
    }
    final actual = parseQrActual(code);
    final actualCode = actual == null
        ? code
        : stringField(actual, 'containerCode');
    if (actualCode.isEmpty) {
      showToast('二维码缺少容器号字段');
      return;
    }
    final found = findContainerInData(data, actualCode);
    if (found == null) {
      if (actual == null) {
        setState(() {
          clearCurrentState();
          scanController.text = code;
        });
        showToast('未找到容器: $code');
        return;
      }
      setState(() {
        activeListType = '';
        selectedWarehouseFilterIndex = -1;
        currentContainer = actual;
        matchedContainer = null;
        currentShowsActual = true;
        actualDisplayFields = ensureLocationField(
          getMapList(actual['__displayFields']),
          null,
        );
        compareIssues = [];
        selectedResult = 1;
        remark = '不在列表中';
        remarkController.text = remark;
        scanController.text = actualCode;
        scanNotice = '该容器不在本次盘存列表中';
      });
      showToast('扫码成功：容器 $actualCode 不在盘存列表中（已设为不正常）');
      return;
    }
    setCurrentFromMatch(actual, found);

    if (actual != null) {
      showToast('扫码成功：已匹配容器 $actualCode');
    } else {
      showToast('查询成功：已找到容器 $actualCode');
    }
  }

  Map<String, dynamic>? parseQrActual(String rawCode) {
    try {
      final decoded = jsonDecode(rawCode);
      if (decoded is! List) return null;
      final actual = <String, dynamic>{};
      final fields = <Map<String, dynamic>>[];
      for (final raw in decoded.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        final key = stringField(item, 'fileValue');
        final value = item['value'];
        if (key.isEmpty || value == null) continue;
        actual[key] = value.toString();
        var label = stringField(item, 'name');
        if (label.isEmpty) label = stringField(item, 'fileName');
        final sortOrder =
            int.tryParse('${item['sortOrder']}') ?? fields.length + 1;
        fields.add({
          'key': key,
          'label': label.isEmpty ? fieldLabel(key) : label,
          'value': value.toString(),
          'sortOrder': sortOrder,
        });
      }
      if (actual.isEmpty) return null;
      fields.sort(
        (a, b) => (a['sortOrder'] as int).compareTo(b['sortOrder'] as int),
      );
      actual['__displayFields'] = fields;
      return actual;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? findContainerInData(
    Map<String, dynamic> data,
    String code,
  ) {
    final list = getWarehouseList(data);
    for (var i = 0; i < list.length; i++) {
      final goods = getGoodsList(list[i]);
      for (var j = 0; j < goods.length; j++) {
        if (stringField(goods[j], 'containerCode') == code) {
          return {'warehouseIndex': i, 'goodsIndex': j, 'item': goods[j]};
        }
      }
    }
    return null;
  }

  void setCurrentFromMatch(
    Map<String, dynamic>? actual,
    Map<String, dynamic> found,
  ) {
    final item = Map<String, dynamic>.from(found['item'] as Map);
    final fields = actual == null
        ? <Map<String, dynamic>>[]
        : ensureLocationField(getMapList(actual['__displayFields']), item);
    final issues = actual == null
        ? <Map<String, String>>[]
        : buildCompareIssues(actual, item, fields);
    final result = getItemResultValue(item);
    final restoredRemark = '${item['resultRemark'] ?? item['remark'] ?? ''}';
    setState(() {
      activeListType = '';
      selectedWarehouseFilterIndex = -1;
      matchedContainer = item;
      currentContainer = actual ?? item;
      currentShowsActual = actual != null;
      actualDisplayFields = fields;
      compareIssues = issues;
      selectedResult = result;
      remark = restoredRemark == 'null' ? '' : restoredRemark;
      remarkController.text = remark;
      scanController.text = stringField(currentContainer!, 'containerCode');
      scanNotice = issues.isNotEmpty ? '已匹配到盘存列表，但部分字段与实际情况不一致。' : '';
    });
  }

  List<Map<String, String>> buildCompareIssues(
    Map<String, dynamic> actual,
    Map<String, dynamic> listItem,
    List<Map<String, dynamic>> fields,
  ) {
    final issues = <Map<String, String>>[];
    for (final entry in actual.entries) {
      final key = entry.key;
      final actualValue = entry.value;
      if (key == 'containerCode' || key.startsWith('__')) continue;
      if (actualValue == null || actualValue.toString().trim().isEmpty) {
        continue;
      }
      dynamic listValue = listItem[key];
      if (key == 'location') listValue = normalizePosition(listItem);
      final actualCompare = normalizeValueForCompare(key, actualValue);
      final listCompare = normalizeValueForCompare(key, listValue);
      if (actualCompare != listCompare) {
        issues.add({
          'key': key,
          'label': actualFieldLabel(fields, key),
          'actualValue': actualValue.toString().trim(),
          'listValue': displayValue(listValue),
        });
      }
    }
    return issues;
  }

  void selectContainerFromList(Map<String, dynamic> item) {
    final code = stringField(item, 'containerCode');
    if (code.isEmpty || taskData == null) return;
    final found = findContainerInData(taskData!, code);
    if (found != null) {
      setCurrentFromMatch(null, found);
    }
  }

  Future<void> openScanner() async {
    final result = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const ScannerPage()));
    if (result == null || result.trim().isEmpty) return;
    scanController.text = result;
    searchContainer(result);
  }

  void selectResult(int result) {
    setState(() => selectedResult = result);
  }

  void appendQuickRemark(String text) {
    final current = remarkController.text.trim();
    if (current.isEmpty) {
      remarkController.text = text;
    } else if (!current.contains(text)) {
      remarkController.text = '$current；$text';
    }
    setState(() => remark = remarkController.text);
  }

  Future<void> submitInventoryResult() async {
    if (currentContainer == null) {
      showToast('请先扫描容器');
      return;
    }
    if (selectedResult == null) {
      showToast('请选择盘存结果');
      return;
    }
    if (matchedContainer != null && isContainerChecked(matchedContainer!)) {
      final confirmed = await showConfirmDialog(
        title: '修改盘存结果',
        content: '该容器已盘存，确认覆盖当前盘存情况？',
      );
      if (!confirmed) return;
    }
    await saveInventoryResult();
  }

  Future<void> saveInventoryResult() async {
    if (matchedContainer == null) {
      await saveUnmatchedInventoryResult();
    } else {
      await saveMatchedInventoryResult();
    }
  }

  Future<void> saveMatchedInventoryResult() async {
    final data = cloneTaskData();
    final container = currentContainer;
    if (data == null || container == null) {
      showToast('任务单数据已失效');
      return;
    }
    final code = stringField(container, 'containerCode');
    final found = findContainerInData(data, code);
    if (found == null) {
      showToast('容器数据已失效');
      return;
    }
    final item = found['item'] as Map<String, dynamic>;
    applyResultFields(item);
    await saveTaskData(data, '盘存结果已提交');
  }

  Future<void> saveUnmatchedInventoryResult() async {
    final data = cloneTaskData();
    final container = currentContainer;
    if (data == null || container == null) {
      showToast('任务单数据已失效');
      return;
    }
    final warehouseIndex = findWarehouseIndexForActual(data, container);
    if (warehouseIndex >= 0) {
      await appendUnmatchedToWarehouse(data, warehouseIndex);
      return;
    }
    final list = getWarehouseList(data);
    if (list.isEmpty) {
      data['warehouseList'] = [
        {
          'warehouseId': '',
          'warehouseName': unassignedWarehouseName,
          'goodsList': <Map<String, dynamic>>[],
          'normalCount': 0,
          'excessCount': 0,
          'deficitCount': 0,
        },
      ];
      await appendUnmatchedToWarehouse(data, 0);
      return;
    }
    final chosen = await chooseWarehouseIndex(list);
    if (chosen == null) {
      showToast('请选择库房后再保存');
      return;
    }
    await appendUnmatchedToWarehouse(data, chosen);
  }

  Future<int?> chooseWarehouseIndex(List<Map<String, dynamic>> list) {
    return showModalBottomSheet<int>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('选择容器归属库房')),
              for (var i = 0; i < list.length; i++)
                ListTile(
                  title: Text(getGroupWarehouseName(list[i])),
                  onTap: () => Navigator.of(context).pop(i),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> appendUnmatchedToWarehouse(
    Map<String, dynamic> data,
    int warehouseIndex,
  ) async {
    final list = getWarehouseList(data);
    final warehouse = list[warehouseIndex];
    final goods = getGoodsList(warehouse);
    final item = Map<String, dynamic>.from(currentContainer!);
    item.removeWhere((key, _) => key.startsWith('__'));
    item['warehouseId'] = stringField(warehouse, 'warehouseId');
    item['warehouseName'] = getGroupWarehouseName(warehouse);
    applyResultFields(item);
    goods.add(item);
    warehouse['goodsList'] = goods;
    data['warehouseList'] = list;
    await saveTaskData(data, '容器已追加');
  }

  int findWarehouseIndexForActual(
    Map<String, dynamic> data,
    Map<String, dynamic> actual,
  ) {
    final warehouseId = stringField(actual, 'warehouseId');
    final warehouseName = stringField(actual, 'warehouseName');
    final list = getWarehouseList(data);
    for (var i = 0; i < list.length; i++) {
      if (warehouseId.isNotEmpty &&
          stringField(list[i], 'warehouseId') == warehouseId) {
        return i;
      }
      if (warehouseName.isNotEmpty &&
          getGroupWarehouseName(list[i]) == warehouseName) {
        return i;
      }
    }
    return -1;
  }

  void applyResultFields(Map<String, dynamic> item) {
    final text = remarkController.text;
    item['result'] = selectedResult;
    item['remark'] = text;
    item['resultRemark'] = text;
    item['inventorySubmitTime'] = formatDateTime(DateTime.now());
    item['inventorySource'] = 'pad';
  }

  Future<void> saveTaskData(Map<String, dynamic> data, String message) async {
    await writeWorkFile(data);
    final savedFileName = await saveToLocalDisk(data);
    setState(() {
      taskData = data;
      fileStatus = '已更新工作文件';
      clearCurrentState();
    });
    if (savedFileName != null) {
      showToast('$message，已同步保存为 $savedFileName');
    } else {
      showToast(message);
    }
  }

  // 保存盘存入口：校验是否全部盘存，未完成则提示但允许强制保存，随后进入盘盈盘亏汇总弹窗。
  Future<void> confirmSaveInventory() async {
    if (taskData == null) {
      showToast('请先导入任务单');
      return;
    }
    final isComplete = uncheckedCount == 0;
    if (!isComplete) {
      final force = await showConfirmDialog(
        title: '存在未盘存容器',
        content: '当前还有 $uncheckedCount 个容器未盘存，是否强制保存？',
      );
      if (!force) return;
    }
    await openInventorySummaryDialog(isComplete);
  }

  // 构建按库房维度的盘盈盘亏录入数据，并弹出汇总弹窗。
  Future<void> openInventorySummaryDialog(bool isComplete) async {
    final data = cloneTaskData();
    if (data == null) {
      showToast('任务单数据已失效');
      return;
    }
    final warehouseList = getWarehouseList(data);
    final inputs = <Map<String, dynamic>>[];
    var totalNormal = 0;
    var totalAbnormal = 0;
    var totalUnchecked = 0;
    for (var i = 0; i < warehouseList.length; i++) {
      final goods = getGoodsList(warehouseList[i]);
      var normal = 0, abnormal = 0, unchecked = 0;
      for (final item in goods) {
        final result = getItemResultValue(item);
        if (result == 0) {
          normal++;
        } else if (result == 1) {
          abnormal++;
        } else {
          unchecked++;
        }
      }
      totalNormal += normal;
      totalAbnormal += abnormal;
      totalUnchecked += unchecked;
      if (goods.isEmpty) continue;
      inputs.add({
        'warehouseIndex': i,
        'warehouseName': getGroupWarehouseName(warehouseList[i]),
        'normalCount': normal,
        'abnormalCount': abnormal,
        'uncheckedCount': unchecked,
      });
    }

    if (inputs.isEmpty) {
      showToast('当前无可盘存的库房数据');
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => InventorySummaryDialog(
        inputs: inputs,
        totalAbnormal: totalAbnormal,
        totalUnchecked: totalUnchecked,
        totalChecked: totalNormal + totalAbnormal,
        isComplete: isComplete,
      ),
    );
    if (result == null) return;
    await persistInventorySummary(data, result, isComplete);
  }

  // 写入库房级 5 个计数字段与任务级汇总，并重新导出结果文件。
  Future<void> persistInventorySummary(
    Map<String, dynamic> data,
    Map<String, dynamic> summary,
    bool isComplete,
  ) async {
    final entries = (summary['entries'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final warehouseList = getWarehouseList(data);

    // 获取人员信息（全局设置，写入每个库房）
    final inventoryUser = summary['inventoryUser'] ?? '';
    final sealChecker = summary['sealChecker'] ?? '';
    final responsibleUser = summary['responsibleUser'] ?? '';
    final supervisor = summary['supervisor'] ?? '';

    // 写入库房级数据
    for (final entry in entries) {
      final index = entry['warehouseIndex'] as int;
      final warehouse = warehouseList[index];
      warehouse['normalCount'] = entry['normalCount'];
      warehouse['abnormalCount'] = entry['abnormalCount'];
      warehouse['uncheckedCount'] = entry['uncheckedCount'];
      warehouse['excessCount'] = entry['excessCount'];
      warehouse['deficitCount'] = entry['deficitCount'];
      warehouse['excessRemark'] = entry['excessRemark'] ?? '';
      warehouse['deficitRemark'] = entry['deficitRemark'] ?? '';
      // 写入人员信息到每个库房
      warehouse['inventoryUser'] = inventoryUser;
      warehouse['sealChecker'] = sealChecker;
      warehouse['responsibleUser'] = responsibleUser;
      warehouse['supervisor'] = supervisor;
    }

    // 空库房计数字段和人员信息统一补默认值，保持结构一致。
    for (final warehouse in warehouseList) {
      if (getGoodsList(warehouse).isEmpty) {
        warehouse['normalCount'] = 0;
        warehouse['abnormalCount'] = 0;
        warehouse['uncheckedCount'] = 0;
        warehouse['excessCount'] = 0;
        warehouse['deficitCount'] = 0;
        warehouse['excessRemark'] = '';
        warehouse['deficitRemark'] = '';
        warehouse['inventoryUser'] = inventoryUser;
        warehouse['sealChecker'] = sealChecker;
        warehouse['responsibleUser'] = responsibleUser;
        warehouse['supervisor'] = supervisor;
      }
    }

    var sumTotal = 0;
    var sumUnchecked = 0;
    var sumNormal = 0;
    var sumAbnormal = 0;
    var sumExcess = 0;
    var sumDeficit = 0;
    for (final warehouse in warehouseList) {
      sumTotal += getGoodsList(warehouse).length;
      sumNormal += (warehouse['normalCount'] as num?)?.toInt() ?? 0;
      sumAbnormal += (warehouse['abnormalCount'] as num?)?.toInt() ?? 0;
      sumUnchecked += (warehouse['uncheckedCount'] as num?)?.toInt() ?? 0;
      sumExcess += (warehouse['excessCount'] as num?)?.toInt() ?? 0;
      sumDeficit += (warehouse['deficitCount'] as num?)?.toInt() ?? 0;
    }

    final inventory = data['inventory'] is Map
        ? Map<String, dynamic>.from(data['inventory'] as Map)
        : <String, dynamic>{};
    inventory['totalCount'] = sumTotal;
    inventory['checkedCount'] = sumTotal - sumUnchecked;
    inventory['uncheckedCount'] = sumUnchecked;
    inventory['normalCount'] = sumNormal;
    inventory['abnormalCount'] = sumAbnormal;
    inventory['excessCount'] = sumExcess;
    inventory['deficitCount'] = sumDeficit;
    inventory['inventoryComplete'] = isComplete;
    inventory['inventorySaveTime'] = formatDateTime(DateTime.now());

    data['inventory'] = inventory;
    data['warehouseList'] = warehouseList;

    await writeWorkFile(data);
    final savedTo = await persistToLocalDisk(data);
    setState(() {
      taskData = data;
      fileStatus = '盘存已保存';
    });
    if (savedTo != null) {
      showToast('盘存已保存，已同步保存为 $savedTo');
    } else {
      showToast('盘存已保存（未导出到本地磁盘）');
    }
  }

  Map<String, dynamic>? cloneTaskData() {
    if (taskData == null) return null;
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(taskData)));
  }

  bool shouldIncludeItem(Map<String, dynamic> item) {
    switch (activeListType) {
      case 'checked':
        return isContainerChecked(item);
      case 'unchecked':
        return !isContainerChecked(item);
      case 'abnormal':
        return isContainerAbnormal(item);
      default:
        return true;
    }
  }

  void clearCurrent() {
    setState(clearCurrentState);
  }

  void clearCurrentState() {
    currentContainer = null;
    matchedContainer = null;
    currentShowsActual = false;
    actualDisplayFields = [];
    compareIssues = [];
    selectedResult = null;
    scanNotice = '';
    remark = '';
    scanController.text = '';
    remarkController.text = '';
  }

  Future<bool> showConfirmDialog({
    required String title,
    required String content,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    return result == true;
  }

  void showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        if (lastBackPressedAt != null &&
            now.difference(lastBackPressedAt!).inMilliseconds < 2000) {
          SystemNavigator.pop();
        } else {
          lastBackPressedAt = now;
          showToast('再按一次退出应用');
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              return SingleChildScrollView(
                padding: EdgeInsets.all(wide ? 16 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buildHeader(),
                    const SizedBox(height: 14),
                    buildStatsRow(),
                    const SizedBox(height: 14),
                    if (!hasData) buildEmptyPanel() else buildWorkspace(wide),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> showSettingsDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final readController = TextEditingController(
      text: prefs.getString('hw-flutter-app.settings.read-path') ?? defaultReadPath,
    );
    final saveController = TextEditingController(
      text: prefs.getString('hw-flutter-app.settings.save-path') ?? defaultSavePath,
    );

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.settings, color: Color(0xff1f4e79)),
              SizedBox(width: 8),
              Text('系统参数设置', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '默认读取文件路径 (JSON / TXT 目录)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xff475569)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: readController,
                  decoration: InputDecoration(
                    hintText: '请输入本地文件夹路径',
                    filled: true,
                    fillColor: const Color(0xfff8fafc),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '系统初始时从此路径自动加载最新文件',
                  style: TextStyle(fontSize: 11, color: Color(0xff64748b)),
                ),
                const SizedBox(height: 16),
                const Text(
                  '默认保存文件路径 (输出目录)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xff475569)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: saveController,
                  decoration: InputDecoration(
                    hintText: '请输入本地保存文件夹路径',
                    filled: true,
                    fillColor: const Color(0xfff8fafc),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '进行盘库修改盘存状态时，将结果文件同步输出至此路径',
                  style: TextStyle(fontSize: 11, color: Color(0xff64748b)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消', style: TextStyle(color: Color(0xff64748b))),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff1f4e79),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final navigator = Navigator.of(context);
                final rPath = readController.text.trim();
                final sPath = saveController.text.trim();
                if (rPath.isEmpty || sPath.isEmpty) {
                  showToast('路径不能为空');
                  return;
                }
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('hw-flutter-app.settings.read-path', rPath);
                await prefs.setString('hw-flutter-app.settings.save-path', sPath);
                await loadSettings();
                navigator.pop();
                showToast('设置永久保存成功');
              },
              child: const Text('保存', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget buildHeader() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 10,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PAD 离线作业', style: TextStyle(color: Color(0xff64748b))),
            Text(
              '实物盘存',
              style: TextStyle(
                color: Color(0xff14213d),
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.settings, color: Color(0xff1f4e79)),
              tooltip: '系统设置',
              onPressed: showSettingsDialog,
            ),
            Chip(
              avatar: const Icon(
                Icons.circle,
                size: 10,
                color: Color(0xff2f855a),
              ),
              label: Text(fileStatus),
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xffd8dee8)),
            ),
            if (hasData)
              OutlinedButton(
                onPressed: confirmClearFiles,
                child: const Text('清除文件'),
              ),
            if (hasData)
              OutlinedButton(
                onPressed: confirmReimport,
                child: const Text('重新导入'),
              ),
          ],
        ),
      ],
    );
  }

  Widget buildStatsRow() {
    final stats = [
      (
        type: 'all',
        label: '已加载',
        count: totalCount,
        selectedBg: const Color(0xffeff6ff),
        selectedBorder: const Color(0xff3b82f6),
        selectedText: const Color(0xff1e40af),
        badgeColor: const Color(0xff2563eb),
      ),
      (
        type: 'checked',
        label: '已盘存',
        count: checkedCount,
        selectedBg: const Color(0xffecfdf5),
        selectedBorder: const Color(0xff10b981),
        selectedText: const Color(0xff065f46),
        badgeColor: const Color(0xff059669),
      ),
      (
        type: 'unchecked',
        label: '未盘存',
        count: uncheckedCount,
        selectedBg: const Color(0xfffef2f2),
        selectedBorder: const Color(0xffef4444),
        selectedText: const Color(0xff991b1b),
        badgeColor: const Color(0xffdc2626),
      ),
      (
        type: 'abnormal',
        label: '异常',
        count: abnormalCount,
        selectedBg: const Color(0xfffffbeb),
        selectedBorder: const Color(0xfff59e0b),
        selectedText: const Color(0xff92400e),
        badgeColor: const Color(0xffd97706),
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: hasData
                  ? () => setState(() {
                        activeListType = stats[i].type;
                      })
                  : null,
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: activeListType == stats[i].type
                      ? stats[i].selectedBg
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: activeListType == stats[i].type
                        ? stats[i].selectedBorder
                        : const Color(0xffe2e8f0),
                    width: activeListType == stats[i].type ? 2 : 1,
                  ),
                  boxShadow: activeListType == stats[i].type
                      ? [
                          BoxShadow(
                            color: stats[i].selectedBorder.withOpacity(0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          )
                        ]
                      : [
                          const BoxShadow(
                            color: Color(0x05000000),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          )
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${stats[i].count}',
                      style: TextStyle(
                        color: activeListType == stats[i].type
                            ? stats[i].selectedText
                            : stats[i].badgeColor,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stats[i].label,
                      style: TextStyle(
                        color: activeListType == stats[i].type
                            ? stats[i].selectedText.withOpacity(0.8)
                            : const Color(0xff64748b),
                        fontSize: 13,
                        fontWeight: activeListType == stats[i].type
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]
      ],
    );
  }

  Widget buildEmptyPanel() {
    return panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '未找到本机工作文件',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            '应用支持从本机默认路径自动读取数据文件，若没有检测到，可在“设置”中配置或手动选择 JSON 导入。\n\n当前读取路径：${_readPath ?? defaultReadPath}',
            style: const TextStyle(color: Color(0xff64748b), height: 1.5),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff1f4e79),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: autoLoadFromDefaultPath,
                icon: const Icon(Icons.refresh),
                label: const Text('从默认路径导入'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xff1f4e79),
                  side: const BorderSide(color: Color(0xff1f4e79)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: chooseInventoryFile,
                icon: const Icon(Icons.file_open),
                label: const Text('手动选择 JSON 文件'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildWorkspace(bool wide) {
    final control = SizedBox(
      width: wide ? 320 : null,
      child: buildControlPanel(),
    );
    final main = Expanded(child: buildMainPanel(wide));
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [control, const SizedBox(width: 12), main],
      );
    }
    return Column(
      children: [control, const SizedBox(height: 12), buildMainPanel(false)],
    );
  }

  Widget buildControlPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xff1e3a8a), Color(0xff1f4e79)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xff1e3a8a).withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.assignment, color: Colors.white70, size: 16),
                  SizedBox(width: 6),
                  Text(
                    '当前任务单',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                taskNumText,
                style: const TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$warehouseCount 个库房 / $totalCount 个容器',
                  style: const TextStyle(color: Color(0xe6ffffff), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xffe2e8f0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x04000000),
                blurRadius: 6,
                offset: Offset(0, 3),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: scanController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => searchByInput(),
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '输入容器号/扫描二维码 JSON',
                        hintStyle: const TextStyle(color: Color(0xff94a3b8), fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xfff8fafc),
                        prefixIcon: const Icon(Icons.search, color: Color(0xff64748b), size: 20),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xffe2e8f0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xff3b82f6), width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: openScanner,
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: const Text('扫码', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff1f4e79),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              if (currentContainer != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: clearCurrent,
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('清空当前查询'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xff64748b),
                    side: const BorderSide(color: Color(0xffcbd5e1)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: confirmSaveInventory,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text(
              '保存盘存',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff1f4e79),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildMainPanel(bool wide) {
    final list = activeListType.isEmpty ? null : buildListPanel();
    final detail = currentContainer == null
        ? buildHintPanel()
        : buildDetailPanel();
    if (wide && list != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 380, child: list),
          const SizedBox(width: 12),
          Expanded(child: detail),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (list != null) ...[list, const SizedBox(height: 12)],
        detail,
      ],
    );
  }

  Widget buildListPanel() {
    return panel(
      padding: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activeListTitle,
                    style: const TextStyle(color: Color(0xff64748b)),
                  ),
                  Text(
                    '$visibleCount 条记录',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() {
                      activeListType = '';
                      selectedWarehouseFilterIndex = -1;
                    }),
                    child: const Text('收起'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: selectedWarehouseFilterIndex,
            decoration: const InputDecoration(
              labelText: '库房筛选',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: -1, child: Text('全部库房')),
              for (var i = 0; i < warehouses.length; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text(getGroupWarehouseName(warehouses[i])),
                ),
            ],
            onChanged: (value) =>
                setState(() => selectedWarehouseFilterIndex = value ?? -1),
          ),
          const SizedBox(height: 10),
          if (visibleCount == 0)
            const SizedBox(height: 88, child: Center(child: Text('暂无记录')))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 430),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final group in visibleWarehouseGroups)
                    buildWarehouseGroup(group),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget buildWarehouseGroup(Map<String, dynamic> group) {
    final goods = getGoodsList(group);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xfff1f5f9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  getGroupWarehouseName(group),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text('${goods.length} 条'),
            ],
          ),
        ),
        for (final item in goods)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              stringField(item, 'containerCode'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '材料代码 ${displayValue(item['goodCode'])}\n位置 ${getItemPositionText(item)}',
            ),
            trailing: resultChip(getItemResultValue(item)),
            onTap: () => selectContainerFromList(item),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget buildHintPanel() {
    return panel(
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '等待扫描容器',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 8),
          Text(
            '扫码枪输入后确认，或点击“扫码”使用摄像头读取二维码 JSON。也可以直接输入容器号查询盘存列表。',
            style: TextStyle(color: Color(0xff64748b), height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget buildDetailPanel() {
    final container = currentContainer!;
    return panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentShowsActual ? '实际情况' : '当前容器',
                      style: const TextStyle(color: Color(0xff64748b)),
                    ),
                    Text(
                      displayValue(container['containerCode']),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              resultChip(selectedResult),
            ],
          ),
          if (scanNotice.isNotEmpty) ...[
            const SizedBox(height: 12),
            infoBox(
              scanNotice,
              const Color(0xfffff7ed),
              const Color(0xff9a3412),
            ),
          ],
          if (compareIssues.isNotEmpty) ...[
            const SizedBox(height: 12),
            buildDiffPanel(),
          ],
          const SizedBox(height: 12),
          buildInfoGrid(container),
          const Divider(height: 28),
          const Text('盘存结果', style: TextStyle(color: Color(0xff64748b))),
          if (matchedContainer != null && isContainerChecked(matchedContainer!))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('当前盘存情况'),
                  resultChip(getItemResultValue(matchedContainer!)),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              resultButton(0, '正常'),
              const SizedBox(width: 8),
              resultButton(1, '不正常'),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in quickRemarks)
                Theme(
                  data: Theme.of(context).copyWith(canvasColor: Colors.transparent),
                  child: ActionChip(
                    elevation: 0,
                    pressElevation: 2,
                    backgroundColor: const Color(0xfff1f5f9),
                    side: const BorderSide(color: Color(0xffe2e8f0)),
                    label: Text(
                      item,
                      style: const TextStyle(
                        color: Color(0xff475569),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    onPressed: () => appendQuickRemark(item),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: remarkController,
            maxLines: 3,
            onChanged: (value) => remark = value,
            decoration: const InputDecoration(
              hintText: '填写备注（选填）',
              filled: true,
              fillColor: Color(0xfff8fafc),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: submitInventoryResult,
            child: const Text('提交盘存结果'),
          ),
        ],
      ),
    );
  }

  Widget buildDiffPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xfffff1f2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xfffecdd3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '以下信息存在差异',
            style: TextStyle(
              color: Color(0xff9f1239),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final issue in compareIssues)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    issue['label'] ?? '-',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text('实际：${issue['actualValue'] ?? '-'}'),
                  Text(
                    '盘存列表：${issue['listValue'] ?? '-'}',
                    style: const TextStyle(color: Color(0xffb91c1c)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget buildInfoGrid(Map<String, dynamic> container) {
    final fields = currentShowsActual
        ? actualDisplayFields
        : [
            {'label': '材料代码', 'value': container['goodCode']},
            {'label': '生产单位', 'value': container['productionUnit']},
            {'label': '库房', 'value': container['warehouseName']},
            {'label': '入库人', 'value': container['createUname']},
            {
              'label': '入库时间',
              'value': container['storageTime'] ?? container['createTime'],
            },
            {'label': '位置', 'value': normalizePosition(container)},
            {'label': '封记编码 1', 'value': container['sealCode1']},
            {'label': '封记编码 2', 'value': container['sealCode2']},
          ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xfff8fafc),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xffe2e8f0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cols = constraints.maxWidth >= 500 ? 2 : 1;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: fields.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: cols == 2 ? 3.5 : 5.0,
              mainAxisSpacing: 0,
              crossAxisSpacing: 0,
            ),
            itemBuilder: (context, index) {
              final field = fields[index];
              final isRightCol = cols == 2 && index % 2 == 1;
              final isBottomRow = index >= fields.length - cols;
              return Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: isBottomRow ? BorderSide.none : const BorderSide(color: Color(0xffe2e8f0)),
                    right: isRightCol ? BorderSide.none : const BorderSide(color: Color(0xffe2e8f0)),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${field['label'] ?? '-'}',
                      style: const TextStyle(
                        color: Color(0xff64748b),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      displayValue(field['value']),
                      style: const TextStyle(
                        color: Color(0xff1e293b),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget resultButton(int value, String label) {
    final active = selectedResult == value;
    final color = switch (value) {
      0 => const Color(0xff10b981),
      1 => const Color(0xffef4444),
      _ => const Color(0xff64748b),
    };
    return Expanded(
      child: active
          ? FilledButton(
              onPressed: () => selectResult(value),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            )
          : OutlinedButton(
              onPressed: () => selectResult(value),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withOpacity(0.4)),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(label),
            ),
    );
  }

  Widget resultChip(int? value) {
    final color = switch (value) {
      0 => const Color(0xff166534),
      1 => const Color(0xff991b1b),
      _ => const Color(0xff475569),
    };
    final background = switch (value) {
      0 => const Color(0xffdcfce7),
      1 => const Color(0xfffee2e2),
      _ => const Color(0xffeef2f7),
    };
    return Chip(
      label: Text(value == null ? '未盘存' : resultLabel(value)),
      labelStyle: TextStyle(color: color),
      backgroundColor: background,
      side: BorderSide.none,
    );
  }

  Widget panel({required Widget child, double padding = 18}) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffd8dee8)),
      ),
      child: child,
    );
  }

  Widget infoBox(String text, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(color: foreground)),
    );
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (handled) return;
              final code = capture.barcodes.firstOrNull?.rawValue;
              if (code == null || code.trim().isEmpty) return;
              handled = true;
              Navigator.of(context).pop(code);
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.black54,
              child: const Text(
                '请将二维码放入取景框',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class InventorySummaryDialog extends StatefulWidget {
  const InventorySummaryDialog({
    super.key,
    required this.inputs,
    required this.totalAbnormal,
    required this.totalUnchecked,
    required this.totalChecked,
    required this.isComplete,
  });

  final List<Map<String, dynamic>> inputs;
  final int totalAbnormal;
  final int totalUnchecked;
  final int totalChecked;
  final bool isComplete;

  @override
  State<InventorySummaryDialog> createState() => _InventorySummaryDialogState();
}

class _InventorySummaryDialogState extends State<InventorySummaryDialog> {
  // 库房级盘盈盘亏输入
  late final List<TextEditingController> _excessControllers;
  late final List<TextEditingController> _deficitControllers;
  late final List<TextEditingController> _excessRemarkControllers;
  late final List<TextEditingController> _deficitRemarkControllers;

  // 全局人员信息输入
  final _inventoryUserController = TextEditingController();
  final _sealCheckerController = TextEditingController();
  final _responsibleUserController = TextEditingController();
  final _supervisorController = TextEditingController();

  String? _errorText;

  @override
  void initState() {
    super.initState();
    _excessControllers = widget.inputs
        .map((_) => TextEditingController())
        .toList(growable: false);
    _deficitControllers = widget.inputs
        .map((_) => TextEditingController())
        .toList(growable: false);
    _excessRemarkControllers = widget.inputs
        .map((_) => TextEditingController())
        .toList(growable: false);
    _deficitRemarkControllers = widget.inputs
        .map((_) => TextEditingController())
        .toList(growable: false);
  }

  @override
  void dispose() {
    for (final controller in _excessControllers) {
      controller.dispose();
    }
    for (final controller in _deficitControllers) {
      controller.dispose();
    }
    for (final controller in _excessRemarkControllers) {
      controller.dispose();
    }
    for (final controller in _deficitRemarkControllers) {
      controller.dispose();
    }
    _inventoryUserController.dispose();
    _sealCheckerController.dispose();
    _responsibleUserController.dispose();
    _supervisorController.dispose();
    super.dispose();
  }

  int? _parseCount(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    if (value == null || value < 0) return null;
    return value;
  }

  void _submit() {
    final entries = <Map<String, dynamic>>[];
    for (var i = 0; i < widget.inputs.length; i++) {
      final input = widget.inputs[i];
      final excess = _parseCount(_excessControllers[i]);
      final deficit = _parseCount(_deficitControllers[i]);
      if (excess == null || deficit == null) {
        setState(() => _errorText = '请填写所有库房的盘盈数与盘亏数（允许填 0）');
        return;
      }
      final abnormal = (input['abnormalCount'] as num).toInt();
      if (excess + deficit != abnormal) {
        final name = input['warehouseName'];
        setState(() => _errorText = '「$name」盘盈+盘亏($excess+$deficit)≠不正常数($abnormal)');
        return;
      }
      entries.add({
        'warehouseIndex': input['warehouseIndex'],
        'warehouseName': input['warehouseName'],
        'normalCount': input['normalCount'],
        'abnormalCount': input['abnormalCount'],
        'uncheckedCount': input['uncheckedCount'],
        'excessCount': excess,
        'deficitCount': deficit,
        'excessRemark': _excessRemarkControllers[i].text.trim(),
        'deficitRemark': _deficitRemarkControllers[i].text.trim(),
      });
    }

    // 添加全局人员信息
    final summary = {
      'entries': entries,
      'inventoryUser': _inventoryUserController.text.trim(),
      'sealChecker': _sealCheckerController.text.trim(),
      'responsibleUser': _responsibleUserController.text.trim(),
      'supervisor': _supervisorController.text.trim(),
    };

    Navigator.of(context).pop(summary);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xff1f4e79),
                borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.assignment_turned_in, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  const Text(
                    '盘存结果汇总',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // 内容区域
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 汇总统计
                    _buildSummaryStats(),
                    const SizedBox(height: 16),
                    // 人员信息填写
                    _buildPersonnelSection(),
                    const SizedBox(height: 16),
                    // 库房盘点明细
                    _buildWarehouseSection(),
                    if (_errorText != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xfffef2f2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xfffecdd3)),
                        ),
                        child: Text(
                          _errorText!,
                          style: const TextStyle(color: Color(0xff991b1b), fontSize: 13),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 底部按钮
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: const Color(0xfff8fafc),
                border: Border(top: BorderSide(color: const Color(0xffe2e8f0))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xff64748b),
                    ),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xff1f4e79),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text('确认保存', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStats() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xffeff6ff), Color(0xfff0f9ff)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffbfdbfe)),
      ),
      child: Row(
        children: [
          _buildStatItem('不正常', widget.totalAbnormal, const Color(0xffdc2626)),
          const SizedBox(width: 24),
          _buildStatItem('未盘存', widget.totalUnchecked, const Color(0xfff59e0b)),
          const SizedBox(width: 24),
          _buildStatItem('已盘存', widget.totalChecked, const Color(0xff10b981)),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: color.withOpacity(0.7),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildPersonnelSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffe2e8f0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.people, color: Color(0xff1f4e79), size: 18),
              SizedBox(width: 8),
              Text(
                '人员信息',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xff1e293b),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 第一行：盘存人、封记检查人
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inventoryUserController,
                  decoration: const InputDecoration(
                    labelText: '盘存人',
                    labelStyle: TextStyle(fontSize: 13),
                    isDense: true,
                    filled: true,
                    fillColor: Color(0xfff8fafc),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _sealCheckerController,
                  decoration: const InputDecoration(
                    labelText: '封记检查人',
                    labelStyle: TextStyle(fontSize: 13),
                    isDense: true,
                    filled: true,
                    fillColor: Color(0xfff8fafc),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 第二行：负责人、监盘人
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _responsibleUserController,
                  decoration: const InputDecoration(
                    labelText: '负责人',
                    labelStyle: TextStyle(fontSize: 13),
                    isDense: true,
                    filled: true,
                    fillColor: Color(0xfff8fafc),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _supervisorController,
                  decoration: const InputDecoration(
                    labelText: '监盘人',
                    labelStyle: TextStyle(fontSize: 13),
                    isDense: true,
                    filled: true,
                    fillColor: Color(0xfff8fafc),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWarehouseSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.warehouse, color: Color(0xff1f4e79), size: 18),
            SizedBox(width: 8),
            Text(
              '库房盘点明细',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xff1e293b),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < widget.inputs.length; i++)
          _buildWarehouseCard(i),
      ],
    );
  }

  Widget _buildWarehouseCard(int i) {
    final input = widget.inputs[i];
    final abnormal = (input['abnormalCount'] as num).toInt();
    final unchecked = (input['uncheckedCount'] as num).toInt();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffe2e8f0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 库房标题
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${input['warehouseName']}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xff1e293b),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: abnormal > 0
                      ? const Color(0xfffef2f2)
                      : const Color(0xffecfdf5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '不正常 $abnormal / 未盘存 $unchecked',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: abnormal > 0
                        ? const Color(0xff991b1b)
                        : const Color(0xff065f46),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 盘盈数输入
          Row(
            children: [
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _excessControllers[i],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: '盘盈数',
                    labelStyle: const TextStyle(fontSize: 12),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xfff0fdf4),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _excessRemarkControllers[i],
                  decoration: const InputDecoration(
                    labelText: '盘盈备注',
                    labelStyle: TextStyle(fontSize: 12),
                    isDense: true,
                    filled: true,
                    fillColor: Color(0xfff8fafc),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 盘亏数输入
          Row(
            children: [
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _deficitControllers[i],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: '盘亏数',
                    labelStyle: const TextStyle(fontSize: 12),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xfffef2f2),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _deficitRemarkControllers[i],
                  decoration: const InputDecoration(
                    labelText: '盘亏备注',
                    labelStyle: TextStyle(fontSize: 12),
                    isDense: true,
                    filled: true,
                    fillColor: Color(0xfff8fafc),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

List<Map<String, dynamic>> getWarehouseList(Map<String, dynamic>? data) {
  final value = data?['warehouseList'];
  if (value is! List) return [];
  final list = value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
  if (data != null) data['warehouseList'] = list;
  return list;
}

List<Map<String, dynamic>> getGoodsList(Map<String, dynamic> warehouse) {
  final value = warehouse['goodsList'];
  if (value is! List) {
    final empty = <Map<String, dynamic>>[];
    warehouse['goodsList'] = empty;
    return empty;
  }
  final list = value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
  warehouse['goodsList'] = list;
  return list;
}

List<Map<String, dynamic>> getMapList(dynamic value) {
  if (value is! List) return [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

String stringField(Map<String, dynamic> item, String key) {
  final value = item[key];
  if (value == null) return '';
  final text = value.toString().trim();
  return text == 'null' ? '' : text;
}

String displayValue(dynamic value) {
  if (value == null ||
      value.toString().trim().isEmpty ||
      value.toString() == 'null') {
    return '-';
  }
  return value.toString();
}

String getGroupWarehouseName(Map<String, dynamic> group) {
  final name = stringField(group, 'warehouseName');
  return name.isEmpty ? unassignedWarehouseName : name;
}

String normalizePosition(Map<String, dynamic> item) {
  final location = stringField(item, 'location');
  if (location.isNotEmpty) return location;
  final shelf = stringField(item, 'shelfCode');
  final row = stringField(item, 'rowCode');
  final column = stringField(item, 'columnCode');
  if (shelf.isEmpty && row.isEmpty && column.isEmpty) return '';
  return '$shelf-$row-$column';
}

String getItemPositionText(Map<String, dynamic> item) {
  final position = normalizePosition(item);
  return position.isEmpty ? '-' : position;
}

// 二维码未携带 location 时，在字段网格末尾追加"位置"行（取列表容器位置）；二维码已带则保持原样不重复。
List<Map<String, dynamic>> ensureLocationField(
  List<Map<String, dynamic>> fields,
  Map<String, dynamic>? listItem,
) {
  if (fields.any((field) => stringField(field, 'key') == 'location')) {
    return fields;
  }
  final location = listItem == null ? '' : normalizePosition(listItem);
  return [
    ...fields,
    {
      'key': 'location',
      'label': fieldLabel('location'),
      'value': location,
      'sortOrder': 999,
    },
  ];
}

int? getItemResultValue(Map<String, dynamic> item) {
  final value = int.tryParse('${item['result'] ?? ''}');
  if (value == 0 || value == 1) return value;
  return null;
}

bool isContainerChecked(Map<String, dynamic> item) =>
    getItemResultValue(item) != null;

bool isContainerAbnormal(Map<String, dynamic> item) {
  final result = getItemResultValue(item);
  return result == 1;
}

String resultLabel(int result) {
  return switch (result) {
    0 => '正常',
    1 => '不正常',
    _ => '未盘存',
  };
}

String fieldLabel(String key) {
  return switch (key) {
    'containerCode' => '容器号',
    'goodCode' => '材料代码',
    'goodName' => '材料名称',
    'productionUnit' => '生产单位',
    'warehouseName' => '库房',
    'warehouseId' => '库房ID',
    'createUname' => '入库人',
    'storageTime' || 'createTime' => '入库时间',
    'location' => '位置',
    'sealCode1' => '封记编码 1',
    'sealCode2' => '封记编码 2',
    _ => key,
  };
}

bool isDateCompareField(String key) {
  return key == 'storageTime' ||
      key == 'createTime' ||
      key == 'inventoryTime' ||
      key == 'inventorySubmitTime';
}

String normalizeValueForCompare(String key, dynamic value) {
  if (value == null) return '';
  final text = value.toString().trim();
  if (isDateCompareField(key) && text.length >= 10) {
    return text.substring(0, 10);
  }
  return text;
}

String actualFieldLabel(List<Map<String, dynamic>> fields, String key) {
  for (final field in fields) {
    if (stringField(field, 'key') == key) {
      final label = stringField(field, 'label');
      if (label.isNotEmpty) return label;
    }
  }
  return fieldLabel(key);
}

String formatDateTime(DateTime date) {
  String two(int value) => value < 10 ? '0$value' : '$value';
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
}
