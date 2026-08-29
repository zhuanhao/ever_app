import '../models/chat_message.dart';
import 'api_client.dart';

/// 聊天服务 - 统一业务逻辑：加载历史、发消息、删除
/// 状态：
///   - 用户消息发送中 status=3
///   - 发送成功 status=1
///   - 失败 status=2（保留重试）
class ChatService {
  final ApiClient _api;

  ChatService(this._api);

  /// 加载聊天历史
  Future<({List<ChatMessage> messages, bool hasMore, int total})> loadHistory({int page = 1}) =>
      _api.fetchHistory(page: page);

  /// 发送消息：addUserMsg 后调用 sendText，返回 assistant 回复
  /// 流程：post /api/chat -> 后端存库 & 生成回复 -> 返回 reply
  Future<ChatMessage> sendText(String text) async {
    final reply = await _api.sendMessage(text);
    return ChatMessage(
      id: ChatMessage.genId(),
      role: 'assistant',
      content: reply,
      time: _now(),
    );
  }

  /// 删除消息
  Future<bool> delete(List<String> ids) => _api.deleteMessages(ids);

  static String _now() {
    final d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }
}
