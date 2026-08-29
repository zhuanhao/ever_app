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
  /// 流程：post /api/chat -> 后端存库 & 生成回复 -> 返回 reply + reply_id
  /// 用后端返回的稳定 reply_id 构造消息，确保 markSeen 与轮询去重匹配
  Future<ChatMessage> sendText(String text) async {
    final result = await _api.sendMessage(text);
    return ChatMessage(
      id: result.replyId.isEmpty ? ChatMessage.genId() : result.replyId,
      role: 'assistant',
      content: result.reply,
      time: _now(),
    );
  }

  /// 发送消息并返回后端真实 id（reply_id + user_id）
  /// 用于主动聊天：用后端 user_id 更新用户消息 id、reply_id 标记 assistant 已见
  Future<({String replyId, String userId, ChatMessage chatMessage})> sendMessageWithIds(String text) async {
    final result = await _api.sendMessage(text);
    final chatMessage = ChatMessage(
      id: result.replyId.isEmpty ? ChatMessage.genId() : result.replyId,
      role: 'assistant',
      content: result.reply,
      time: _now(),
    );
    return (replyId: result.replyId, userId: result.userId, chatMessage: chatMessage);
  }

  /// 删除消息
  Future<bool> delete(List<String> ids) => _api.deleteMessages(ids);

  static String _now() {
    final d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }
}