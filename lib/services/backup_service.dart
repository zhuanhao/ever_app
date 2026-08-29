import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// 数据备份/恢复服务
/// 提供云端（后端 /api/shared）+ 本地文件两条通道，避免数据丢失。
/// 云端：将本地 SharedPreferences 全部数据打包成 JSON，利用后端 /api/shared 的
///   'app_backup' type 做云端备份。
/// 本地：导出 JSON 文件到本地（可传回/存档），再从本地 JSON 文件导入恢复。
class BackupService {
  final ApiClient _api;

  BackupService(this._api);

  static const _kBackupType = 'app_backup';

  /// 把 SharedPreferences 全量数据打包成 payload
  Future<Map<String, dynamic>> _collectPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      final v = prefs.get(key);
      if (v == null) continue;
      if (v is String) {
        data[key] = v;
      } else if (v is bool) {
        data[key] = v;
      } else if (v is int) {
        data[key] = v;
      } else if (v is double) {
        data[key] = v;
      } else if (v is List<String>) {
        data[key] = v;
      } else {
        data[key] = v.toString();
      }
    }
    return data;
  }

  /// 用 payload 覆盖写入 SharedPreferences
  Future<void> _applyPrefs(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in data.entries) {
      final key = entry.key.toString();
      final v = entry.value;
      if (v is String) {
        await prefs.setString(key, v);
      } else if (v is bool) {
        await prefs.setBool(key, v);
      } else if (v is int) {
        await prefs.setInt(key, v);
      } else if (v is double) {
        await prefs.setDouble(key, v);
      } else if (v is List) {
        await prefs.setStringList(key, v.map((e) => e.toString()).toList());
      }
    }
  }

  // ============ 云端备份/恢复 ============

  /// 导出本地 SharedPreferences 全部数据到云端
  Future<bool> backup() async {
    final data = await _collectPrefs();
    final payload = {'saved': DateTime.now().toIso8601String(), 'data': data};
    return await _api.saveShared(_kBackupType, payload);
  }

  /// 从云端拉回并覆盖写入本地 SharedPreferences
  Future<bool> restore() async {
    final remote = await _api.fetchShared(_kBackupType);
    if (remote.isEmpty || !remote.containsKey('data')) return false;
    final data = remote['data'];
    if (data is! Map) return false;
    await _applyPrefs(data.cast<String, dynamic>());
    return true;
  }

  /// 获取最近一次云备份时间（用于显示）
  Future<String?> lastBackupTime() async {
    final remote = await _api.fetchShared(_kBackupType);
    return remote['saved']?.toString();
  }

  // ============ 本地文件备份/恢复 ============

  /// 导出到本地 JSON 文件，返回保存的路径（取消则返回 null）
  Future<String?> backupToLocal() async {
    final data = await _collectPrefs();
    final payload = {'saved': DateTime.now().toIso8601String(), 'data': data};
    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);

    // 用系统文件选择器让用户选保存位置（部分平台退化到应用文档目录）
    String? path;
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '保存本地备份',
        fileName: 'ever_app_backup_${DateTime.now().millisecondsSinceEpoch}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: utf8.encode(jsonStr),
      );
      if (result != null) {
        path = result;
      }
    } catch (e) {
      // saveFile 可能不被所有平台支持，退化到文档目录
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/ever_app_backup_${DateTime.now().millisecondsSinceEpoch}.json');
        await file.writeAsString(jsonStr, flush: true);
        path = file.path;
      } catch (_) {
        return null;
      }
    }

    if (path == null) return null;
    // 若 saveFile 未直接写入字节，则手动写入
    try {
      final f = File(path);
      if (!await f.exists() || await f.length() == 0) {
        await f.writeAsString(jsonStr, flush: true);
      }
    } catch (_) {}
    return path;
  }

  /// 从本地 JSON 文件导入并覆盖 SharedPreferences，返回是否成功
  Future<bool> restoreFromLocal() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择本地备份文件',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return false;
    final path = result.files.first.path;
    if (path == null) return false;

    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final content = await file.readAsString();
      final map = jsonDecode(content) as Map<String, dynamic>;
      final data = map['data'];
      if (data is! Map) return false;
      await _applyPrefs(data.cast<String, dynamic>());
      return true;
    } catch (_) {
      return false;
    }
  }
}
