import 'dart:async';
import '../models/chat_message.dart';
import 'api_client.dart';

/// 后端自主活动回流服务
/// 需求：关掉APK后，后端自主活动（自主唤醒/逛论坛/调MCP/邮件等）
///   写成一条条消息进入与聊天共用的会话流，打开App时像正常聊天一样显示。
/// 当前后端无WebSocket推送，用轮询 history 的方式，识别新增的 assistant 消息
///   作为回流事件注入聊天流。
/// 未来后端加 /stream 可切为 WebSocket/SSE。
class BackendStreamService {
  final ApiClient _api;
  Timer? _timer;
  // 已见过的 message id 集合（避免重复注入）
  Set<String> _seenIds = {};

  // 回调：收到新的后端自主活动消息时通知 UI
  void Function(List<ChatMessage> newEvents)? onNewEvents;

  BackendStreamService(this._api);

  void startPolling({
    int intervalSeconds = 15,
    Set<String>? knownIds,
  }) {
    if (knownIds != null) _seenIds = Set.from(knownIds);
    _stop();
    _timer = Timer.periodic(Duration(seconds: intervalSeconds), (_) => _poll());
  }

  void stopPolling() => _stop();

  Future<void> _poll() async {
    try {
      // 拉最新一页（默认倒序/最新30条）
      final result = await _api.fetchHistory(page: 1, limit: 30);
      final newEvents = <ChatMessage>[];
      for (final msg in result.messages) {
        if (_seenIds.contains(msg.id)) continue;
        _seenIds.add(msg.id);
        // 后端自主活动回流消息：assistant 且非用户主动发起
        if (msg.isAssistant) {
          // 标记为 event 类型（后端活动的客观记录），tool 字段可存 MCP 记录
          newEvents.add(ChatMessage(
            id: msg.id,
            role: 'assistant',
            content: msg.content,
            time: msg.time,
            msgType: 'event',
            tool: msg.tool,
            fromBackend: true,
          ));
        }
      }
      if (newEvents.isNotEmpty) {
        onNewEvents?.call(newEvents);
      }
    } catch (e) {
      // 静默失败，下次再试
    }
  }

  /// 初始化已见过的 id（首次加载历史时用）
  void markIds(Set<String> ids) {
    _seenIds = Set.from(ids);
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _stop();
  }
}
