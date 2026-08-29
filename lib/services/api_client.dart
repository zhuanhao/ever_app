import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';

/// 后端 API 客户端 - 连接 VPS ever-agent 的 8899 端口
/// 当前后端为 HTTP 非流式返回，未来升级流式在此加抽象
/// 配置项（后可从设置页读取）：
///   backendUrl: https://ever.phywn.top
class ApiClient {
  String backendUrl;

  ApiClient({this.backendUrl = 'https://ever.phywn.top'});

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$backendUrl$path').replace(queryParameters: query);

  /// 获取聊天历史
  Future<({List<ChatMessage> messages, bool hasMore, int total})> fetchHistory({int page = 1, int limit = 30}) async {
    try {
      final resp = await http.get(_uri('/api/history', {'page': '$page', 'limit': '$limit'})).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final List<ChatMessage> list = (data['history'] as List? ?? [])
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        return (messages: list, hasMore: data['has_more'] == true, total: (data['total'] as num? ?? 0).toInt());
      }
      return (messages: <ChatMessage>[], hasMore: false, total: 0);
    } catch (e) {
      return (messages: <ChatMessage>[], hasMore: false, total: 0);
    }
  }

  /// 发送消息，接收回复（非流式，一次拿全量）
  /// 返回 assistant 回复内容及后端生成的稳定 id（reply_id 与 user_id）。发送失败抛异常。
  Future<({String reply, String replyId, String userId})> sendMessage(String message) async {
    final resp = await http
        .post(_uri('/api/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': message}))
        .timeout(const Duration(seconds: 60));
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    if (data.containsKey('error')) {
      throw Exception(data['error']?.toString() ?? 'unknown_error');
    }
    return (reply: data['reply'] as String? ?? '', replyId: data['reply_id'] as String? ?? '', userId: data['user_id'] as String? ?? '');
  }

  /// 删除消息（多条）
  Future<bool> deleteMessages(List<String> ids) async {
    try {
      final resp = await http
          .post(_uri('/api/delete'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'ids': ids}))
          .timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 后端状态
  Future<Map<String, dynamic>> fetchStatus() async {
    try {
      final resp = await http.get(_uri('/api/status')).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  /// 读取共享数据（按 type，如 todo/status/timeline）
  /// 返回该 type 下的共享 dict；失败返回空 map
  Future<Map<String, dynamic>> fetchShared(String type) async {
    try {
      final resp = await http.get(_uri('/api/shared', {'type': type})).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        return (data['data'] as Map<String, dynamic>? ?? {});
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  /// 保存共享数据（按 type 合并）。返回是否成功
  Future<bool> saveShared(String type, Map<String, dynamic> data) async {
    try {
      final resp = await http
          .post(_uri('/api/shared'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'type': type, 'data': data}))
          .timeout(const Duration(seconds: 8));
      return resp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 拉取中转站配置（/api/config）。返回 providers 列表 + active_provider
  Future<Map<String, dynamic>> fetchConfig() async {
    try {
      final resp = await http.get(_uri('/api/config')).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  /// 保存中转站配置（POST /api/config）。action: set_active / upsert / remove
  /// 返回后端响应 map；失败返回空 map
  Future<Map<String, dynamic>> saveConfig(Map<String, dynamic> body) async {
    try {
      final resp = await http
          .post(_uri('/api/config'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200 || resp.statusCode == 404) {
        return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  /// 拉取最新版本信息（/api/version）。失败返回空 map
  Future<Map<String, dynamic>> fetchVersion() async {
    try {
      final resp = await http.get(_uri('/api/version')).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  /// 下载最新 APK（/latest.apk）。返回字节，失败返回 null
  Future<List<int>?> downloadApk() async {
    try {
      final resp = await http.get(_uri('/latest.apk')).timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200) {
        return resp.bodyBytes;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}