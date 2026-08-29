import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 配置存储服务 - 本地存 API/MCP/偏好，部分同步给后端
/// 用 shared_preferences 本地存，未来可换 SQLite
class ConfigService {
  static const _kBackendUrl = 'backend_url';
  static const _kLlmUrl = 'llm_url';
  static const _kApiKey = 'api_key';
  static const _kModel = 'model';
  static const _kThinking = 'thinking_enabled';
  static const _kThinkingShow = 'thinking_show';
  static const _kPushEnabled = 'push_enabled';

  static final _client = http.Client();

  /// 读取全部配置
  Future<Map<String, dynamic>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'backendUrl': prefs.getString(_kBackendUrl) ?? 'https://ever.phywn.top',
      'llmUrl': prefs.getString(_kLlmUrl) ?? 'https://cn.jixiangai.xyz/v1',
      'apiKey': prefs.getString(_kApiKey) ?? '',
      'model': prefs.getString(_kModel) ?? 'claude-opus-4-6',
      'thinkingEnabled': prefs.getBool(_kThinking) ?? false, // 默认关
      'thinkingShow': prefs.getBool(_kThinkingShow) ?? false,
      'pushEnabled': prefs.getBool(_kPushEnabled) ?? false,
    };
  }

  Future<void> set(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is String) prefs.setString(key, value);
    else if (value is bool) prefs.setBool(key, value);
    else if (value is int) prefs.setInt(key, value);
  }

  Future<String> getBackendUrl() async => (await getAll())['backendUrl'] as String;
  Future<String> getModel() async => (await getAll())['model'] as String;
  Future<bool> isThinkingEnabled() async => (await getAll())['thinkingEnabled'] as bool;

  /// 拉取上游可用模型列表（/v1/models）
  /// 用 llmUrl + apiKey 请求
  Future<List<String>> fetchModels() async {
    final cfg = await getAll();
    final llmUrl = (cfg['llmUrl'] as String).replaceAll(RegExp(r'/$'), '');
    final apiKey = cfg['apiKey'] as String;
    if (llmUrl.isEmpty) return [];
    try {
      final resp = await httpGet('$llmUrl/models', apiKey: apiKey);
      if (resp['status'] == 200) {
        final data = resp['data'] as Map<String, dynamic>;
        final list = (data['data'] as List? ?? [])
            .map((e) => ((e as Map)['id'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toList();
        return list;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // 简单的 http get 封装
  Future<Map<String, dynamic>> httpGet(String url, {String? apiKey}) async {
    final headers = <String, String>{};
    if (apiKey != null && apiKey.isNotEmpty) headers['Authorization'] = 'Bearer $apiKey';
    try {
      final resp = await _client.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 10));
      return {'status': resp.statusCode, 'data': jsonDecode(utf8.decode(resp.bodyBytes))};
    } catch (e) {
      return {'status': -1, 'data': null, 'error': e.toString()};
    }
  }
}