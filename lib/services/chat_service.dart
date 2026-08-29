import 'dart:convert';
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
    final parsed = ChatService._parseToolCards(result.reply);
    final chatMessage = ChatMessage(
      id: result.replyId.isEmpty ? ChatMessage.genId() : result.replyId,
      role: 'assistant',
      content: parsed.content,
      time: _now(),
      msgType: parsed.toolCards.isNotEmpty && parsed.content.trim().isEmpty ? 'tool' : 'text',
      tool: parsed.toolCards.isNotEmpty ? {'cards': parsed.toolCards} : null,
    );
    return (replyId: result.replyId, userId: result.userId, chatMessage: chatMessage);
  }

  /// 解析后端 reply 文本里的可信卡块 [T-EVER-START]...JSON...[T-EVER-END]
  /// 拆出 tool_cards 存到 tool 字段；正文清理掉 JSON 块，避免 raw JSON 暴露在气泡里。
  /// 返回 (content, toolCards)。
  static ({String content, List<Map<String, dynamic>> toolCards}) _parseToolCards(String reply) {
    if (reply.isEmpty) return (content: '', toolCards: <Map<String, dynamic>>[]);
    final cards = <Map<String, dynamic>>[];
    final re = RegExp(r'\[T-EVER-START\](.*?)\[T-EVER-END\]', dotAll: true);
    var cleaned = reply;
    // 逐个替换：先解析 JSON，再从正文删掉整个块
    for (final m in re.allMatches(reply)) {
      final jsonStr = m.group(1)?.trim() ?? '';
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is List) {
          for (final it in decoded) {
            if (it is Map) cards.add(Map<String, dynamic>.from(it));
          }
        } else if (decoded is Map) {
          cards.add(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        // JSON 解析失败：保留原始块？不，删掉以免 raw JSON 暴露，但卡片无法展示
      }
    }
    // 删除所有块（含未解析成功的），保持正文干净
    cleaned = cleaned.replaceAll(re, '').trim();
    return (content: cleaned, toolCards: cards);
  }

  /// 删除消息
  Future<bool> delete(List<String> ids) => _api.deleteMessages(ids);

  static String _now() {
    final d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }
}