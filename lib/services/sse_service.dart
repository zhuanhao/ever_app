import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_client.dart';

/// SSE 实时推送服务
/// 连接到后端 /api/stream 长连接，接收后端广播事件（主动聊天回复 + 自主活动消息）。
/// 收到 message 事件时弹本地系统通知，实现 App 打开/锁屏阶段实时收到 Ever 的消息提醒。
///
/// 效果边界（方案A）：App 进程活着（前台/后台/锁屏）都能收到通知；
///   进程被系统杀掉后 SSE 断连，无法收到（用户已接受此边界）。
class SseService {
  final ApiClient _api;

  // 本地通知插件（全局单例，避免重复初始化）
  static final FlutterLocalNotificationsPlugin _notif = FlutterLocalNotificationsPlugin();
  static bool _notifInitialized = false;
  static int _notifIdCounter = 1000; // 通知 id，递增避免覆盖

  // SSE 连接状态
  http.Client? _client;
  bool _running = false;
  bool _reconnecting = false;
  Timer? _reconnectTimer;

  // 回调：收到新消息时通知 UI 注入聊天流（可选，与轮询互补）
  void Function(dynamic messageData)? onSseMessage;

  SseService(this._api);

  /// 初始化本地通知（Android 13+ 请求运行时权限）。在 main() 或首次启动时调用一次。
  static Future<void> initNotifications() async {
    if (_notifInitialized) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _notif.initialize(initSettings);

      // Android 13+ 请求通知运行时权限
      final androidImpl = _notif.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();

      _notifInitialized = true;
      debugPrint('[SseService] notifications initialized');
    } catch (e) {
      debugPrint('[SseService] initNotifications error: $e');
    }
  }

  /// 启动 SSE 长连接。自动重连（断线 5 秒后重试）。
  Future<void> start() async {
    await initNotifications();
    _running = true;
    _connect();
  }

  Future<void> _connect() async {
    if (_reconnecting) return;
    _reconnecting = true;
    try {
      final client = http.Client();
      _client = client;
      final request = http.Request('GET', Uri.parse('${_api.backendUrl}/api/stream'));
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';

      final resp = await client.send(request).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        debugPrint('[SseService] stream HTTP ${resp.statusCode}');
        _scheduleReconnect();
        return;
      }
      _reconnecting = false;
      debugPrint('[SseService] SSE connected');

      // 逐行解析 SSE：'data: {...}'，空行作为事件分隔符
      final lines = resp.stream.transform(utf8.decoder).transform(const LineSplitter());
      final dataBuffer = StringBuffer();
      await for (final line in lines) {
        if (!_running) break;
        if (line.isEmpty) {
          // 事件结束，处理累积的 data
          final payload = dataBuffer.toString().trim();
          dataBuffer.clear();
          if (payload.isNotEmpty) {
            _handleEvent(payload);
          }
        } else if (line.startsWith('data:')) {
          final data = line.substring(5).trim();
          if (dataBuffer.isNotEmpty) dataBuffer.write('\n');
          dataBuffer.write(data);
        }
        // ': ping' 心跳行忽略
      }
    } catch (e) {
      debugPrint('[SseService] SSE error: $e');
    } finally {
      _client?.close();
      _client = null;
      if (_running) {
        _scheduleReconnect();
      }
    }
  }

  void _scheduleReconnect() {
    if (!_running || _reconnecting) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _reconnecting = false;
      _connect();
    });
  }

  void _handleEvent(String payload) {
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      final type = json['type']?.toString() ?? '';
      final data = json['data'];

      // 消息事件：弹系统通知 + 回调 UI
      if (type == 'message' && data is Map<String, dynamic>) {
        final role = data['role']?.toString() ?? 'assistant';
        final content = data['content']?.toString() ?? '';
        final fullContent = data['full_content']?.toString() ?? content;
        if (role == 'assistant' && content.isNotEmpty) {
          _showNotification(content, fullContent);
        }
        onSseMessage?.call(data);
      }
    } catch (e) {
      debugPrint('[SseService] parse event error: $e');
    }
  }

  Future<void> _showNotification(String preview, String fullContent) async {
    try {
      _notifIdCounter++;
      const androidDetails = AndroidNotificationDetails(
        'ever_chat',            // channel id
        '珩心消息',             // channel name
        channelDescription: 'Ever 发来的聊天消息提醒',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
      );
      const details = NotificationDetails(android: androidDetails);
      await _notif.show(
        _notifIdCounter,
        '珩心',
        preview.length > 60 ? preview.substring(0, 60) : preview,
        details,
      );
    } catch (e) {
      debugPrint('[SseService] showNotification error: $e');
    }
  }

  void stop() {
    _running = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _client?.close();
    _client = null;
  }

  void dispose() => stop();
}
