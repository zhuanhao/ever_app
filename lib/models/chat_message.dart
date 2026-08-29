/// 聊天消息模型 - 对标后端 chat_history 结构
/// 后端 history 每条：{id, role, content, time, attachments?}
/// 我们扩展：tool(工具调用记录), msgType(类型: text/tool/system/event)
class ChatMessage {
  final String id;           // 唯一id，用于删除/编辑
  final String role;         // 'user' | 'assistant'
  final String content;      // 文本内容
  final String time;         // 'YYYY-MM-DD HH:mm' 或 ISO
  final String msgType;      // 'text' | 'tool' | 'event' (后端自主活动消息)
  final List<Map<String, dynamic>>? attachments; // [{url,name}]
  final Map<String, dynamic>? tool; // 工具调用记录（MCP），折叠卡片用
  int? status;         // 0=待发送 1=已发送 2=失败 3=发送中
  final bool fromBackend;    // 是否为后端自主活动回流消息

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.time,
    this.msgType = 'text',
    this.attachments,
    this.tool,
    this.status,
    this.fromBackend = false,
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'time': time,
    'msgType': msgType,
    'attachments': attachments,
    'tool': tool,
    'status': status,
    'fromBackend': fromBackend,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      role: (json['role'] ?? 'assistant') as String,
      content: (json['content'] ?? '') as String,
      time: (json['time'] ?? '') as String,
      msgType: (json['msgType'] ?? 'text') as String,
      attachments: (json['attachments'] as List?)?.cast<Map<String, dynamic>>(),
      tool: json['tool'] as Map<String, dynamic>?,
      status: json['status'] as int?,
      fromBackend: json['fromBackend'] == true,
    );
  }

  /// 本地生成临时 id
  static String genId()=> '${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecondsSinceEpoch}';
}
