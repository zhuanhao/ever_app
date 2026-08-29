import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// 数据备份/恢复服务
/// 将本地 SharedPreferences 的全部数据打包成 JSON，利用后端 /api/shared 的
/// 'app_backup' type 做云端备份，避免卸载重装后本地数据丢失。
/// 说明：各业务模块（todo/status/timeline/deliver/workflow/memory）已在
/// /api/shared 按 type 有云备份，这里额外把本地 SharedPreferences 全量数据
/// 集中备份一份兜底（覆盖配置项及所有业务本地缓存）。
class BackupService {
  final ApiClient _api;

  BackupService(this._api);

  static const _kBackupType = 'app_backup';

  /// 导出本地 SharedPreferences 全部数据到云端
  Future<bool> backup() async {
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
    // 带时间戳便于识别最新备份
    final payload = {'saved': DateTime.now().toIso8601String(), 'data': data};
    return await _api.saveShared(_kBackupType, payload);
  }

  /// 从云端拉回并覆盖写入本地 SharedPreferences
  Future<bool> restore() async {
    final remote = await _api.fetchShared(_kBackupType);
    if (remote.isEmpty || !remote.containsKey('data')) return false;
    final saved = remote['saved']?.toString() ?? '';
    final data = remote['data'];
    if (data is! Map) return false;
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
    return true;
  }

  /// 获取最近一次备份时间（用于显示）
  Future<String?> lastBackupTime() async {
    final remote = await _api.fetchShared(_kBackupType);
    return remote['saved']?.toString();
  }
}
