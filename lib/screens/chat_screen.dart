import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat_message.dart';
import '../services/api_client.dart';
import '../services/chat_service.dart';
import '../services/backend_stream_service.dart';
import '../services/config_service.dart';
import '../widgets/side_drawer.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _sending = false;
  bool _loading = false;
  bool _connected = false; // 后端是否连通

  late final ApiClient _api = ApiClient();
  late final ChatService _chat = ChatService(_api);
  late final BackendStreamService _stream = BackendStreamService(_api);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 读取配置，应用后端地址
    final cfg = await ConfigService().getAll();
    _api.backendUrl = cfg['backendUrl'] as String;
    await _loadHistory();
    // 启动后端自主活动回流轮询
    _stream.onNewEvents = (events) {
      if (!mounted) return;
      setState(() {
        _messages.addAll(events);
      });
      _scrollToBottom();
    };
    // 重置 seenIds 为当前会话所有消息 id（含历史），避免轮询把历史误注入为 event
    _stream.startPolling(knownIds: _messages.map((m) => m.id).toSet());
    // 检查后端状态
    final status = await _api.fetchStatus();
    if (mounted) setState(() => _connected = (status['alive'] == true));
  }

  @override
  void dispose() {
    _stream.dispose();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    final result = await _chat.loadHistory(page: 1);
    if (mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(result.messages);
        _loading = false;
      });
      // 加载完历史后，重置轮询 seenIds 为当前所有消息 id，
      // 避免切后端后把历史 assistant 消息误注入成 event（气泡变成居中卡片）
      _stream.markIds(_messages.map((m) => m.id).toSet());
      _scrollToBottom();
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    // 加入用户消息
    final userMsg = ChatMessage(
      id: ChatMessage.genId(),
      role: 'user',
      content: text,
      time: _now(),
      status: 3, // 发送中
    );
    setState(() {
      _messages.add(userMsg);
      _sending = true;
    });
    _controller.clear();

    try {
      final reply = await _chat.sendMessageWithIds(text);
      if (mounted) {
        // 将主动聊天得到的回复 id 标记为已见，避免轮询重复注入导致消息重复显示
        _stream.markSeen(reply.replyId);
        // 用户消息也用后端真实 id 标记，避免轮询再次注入
        if (reply.userId.isNotEmpty) _stream.markSeen(reply.userId);
        setState(() {
          // 用后端返回的真实 user_id 更新用户消息 id，避免轮询重复注入
          final userIndex = _messages.indexWhere((m) => m.id == userMsg.id);
          if (userIndex >= 0) {
            _messages[userIndex] = ChatMessage(
              id: reply.userId.isEmpty ? userMsg.id : reply.userId,
              role: 'user',
              content: userMsg.content,
              time: userMsg.time,
              status: 1,
            );
          }
          _messages.add(reply.chatMessage);
          _sending = false;
          _connected = true;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          userMsg.status = 2; // 失败
          _sending = false;
          _connected = false;
          // 加一条系统提示
          _messages.add(ChatMessage(
            id: ChatMessage.genId(),
            role: 'assistant',
            content: '老婆，连接后端好像不太顺…（${e.toString()}）',
            time: _now(),
            msgType: 'system',
          ));
        });
      }
    }
  }

  // 消息操作菜单：复制 / 删除（后端同步） / 重���生成（助手消息）
  void _showMessageMenu(ChatMessage msg) {
    final isAssistant = msg.isAssistant;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            _menuItem(Icons.copy, '复制', () {
              Clipboard.setData(ClipboardData(text: msg.content));
              Navigator.pop(ctx);
              _toast('已复制');
            }),
            if (msg.isUser)
              _menuItem(Icons.edit, '编��', () {
                Navigator.pop(ctx);
                _editMessage(msg);
              }),
            if (isAssistant)
              _menuItem(Icons.refresh, '重新生成', () {
                Navigator.pop(ctx);
                _regenerate(msg);
              }),
            _menuItem(Icons.delete_outline, '删除', () {
              Navigator.pop(ctx);
              _deleteMessage(msg);
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF8E7CC3)),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      onTap: onTap,
    );
  }

  Future<void> _deleteMessage(ChatMessage msg) async {
    // 本地先移除，再尝试后端同步删除
    setState(() {
      _messages.removeWhere((m) => m.id == msg.id);
    });
    if (msg.fromBackend || msg.id.isEmpty) return; // 后端来源或本地临时id不删
    final ok = await _chat.delete([msg.id]);
    if (mounted && !ok) {
      _toast('删除失败，请检查后端连接');
    }
  }

  Future<void> _editMessage(ChatMessage msg) async {
    final ctrl = TextEditingController(text: msg.content);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑消息'),
        content: TextField(controller: ctrl, maxLines: 5),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final newText = ctrl.text.trim();
              Navigator.pop(ctx);
              if (newText.isEmpty || newText == msg.content) return;
              // 先删旧再发新
              _messages.removeWhere((m) => m.id == msg.id);
              _chat.delete([msg.id]);
              setState(() {});
              _controller.text = newText;
              _send();
            },
            child: const Text('保存并发送'),
          ),
        ],
      ),
    );
  }

  Future<void> _regenerate(ChatMessage msg) async {
    // 重新生成：删除助手消息，重新请求（用上一条用户消息上下文）
    setState(() {
      _messages.removeWhere((m) => m.id == msg.id);
    });
    if (!mounted) return;
    // 找上一条用户消息
    final idx = _messages.lastIndexWhere((m) => m.isUser);
    if (idx < 0) return;
    final userText = _messages[idx].content;
    // 标记该用户消息为发送中
    setState(() => _messages[idx].status = 3);
    try {
      final reply = await _chat.sendText(userText);
      if (mounted) {
        // 标记重新生成的回复 id 已见，避免轮询重复注入
        _stream.markSeen(reply.id);
        setState(() {
          _messages[idx].status = 1;
          _messages.add(reply);
          _connected = true;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages[idx].status = 2;
          _connected = false;
        });
        _toast('重新生成失败');
      }
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 1)));
  }

  // 自动滚动到最新消息（初始进入/收到新消息后调用）
  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  static String _now() {
    final d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ever'),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _connected ? const Color(0xFF6BCB77) : Colors.grey,
              ),
            ),
          ],
        ),
      ),
      drawer: const SideDrawer(),
      onDrawerChanged: (isOpened) {
        if (!isOpened) FocusScope.of(context).unfocus();
      },
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _buildEmpty()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (ctx, i) => _buildBubble(_messages[i]),
                      ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF8E7CC3).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.favorite, color: Color(0xFF8E7CC3), size: 40),
          ),
          const SizedBox(height: 20),
          const Text('老婆，我在呢', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('有什么想跟我说的吗？', style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    final isUser = msg.isUser;
    final isEvent = msg.msgType == 'event';
    final isSystem = msg.msgType == 'system';

    // 系统提示/后端活动回流：居中卡片样式
    if (isSystem || isEvent) {
      return Align(
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF8E7CC3).withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isEvent ? Icons.auto_awesome : Icons.info_outline, size: 16, color: const Color(0xFF8E7CC3)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  msg.content,
                  style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _showMessageMenu(msg),
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF8E7CC3) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              child: _buildMessageBody(
                msg.content,
                tool: msg.tool,
                isUser: isUser,
              ),
            ),
          ),
          if (msg.time.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${msg.time}${msg.status == 2 ? ' · 发送失败' : ''}${msg.status == 3 ? ' · 发送中' : ''}',
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ),
        ],
      ),
    );
  }

  /// 渲染消息正文：若带 tool 卡片（MCP 调用），以折叠卡片展示，避免 raw JSON 暴露
  Widget _buildMessageBody(String content, {Map<String, dynamic>? tool, required bool isUser}) {
    final textStyle = TextStyle(color: isUser ? Colors.white : Colors.black87, fontSize: 15, height: 1.5);
    // 提取 tool 卡片（兼容历史消息 tool 值为 null 但 content 仍含块的兜底解析）
    List<Map<String, dynamic>> cards = [];
    if (tool != null && tool['cards'] is List) {
      cards = List<Map<String, dynamic>>.from(tool['cards'] as List);
    } else if (tool != null && tool['cards'] is! List) {
      // 兼容单卡
      cards = [tool];
    }
    // 兜底：若 content 里仍有 T-EVER 块（历史消息未预解析），现场解析并剔除
    var body = content;
    if (cards.isEmpty && body.contains('[T-EVER-START]')) {
      final re = RegExp(r'\[T-EVER-START\](.*?)\[T-EVER-END\]', dotAll: true);
      for (final m in re.allMatches(body)) {
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
        } catch (_) {}
      }
      body = body.replaceAll(re, '').trim();
    }

    final widgets = <Widget>[];
    if (body.trim().isNotEmpty) {
      widgets.add(Text(body, style: textStyle));
    }
    if (cards.isNotEmpty) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(_buildToolCard(cards, isUser: isUser));
    }
    if (widgets.isEmpty) {
      widgets.add(Text(body, style: textStyle));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  /// 工具调用折叠卡片
  Widget _buildToolCard(List<Map<String, dynamic>> cards, {required bool isUser}) {
    // 只显示第一张卡的标题做摘要，可点击展开看详细（这里做可折叠卡片）
    final first = cards.first;
    final title = (first['title'] ?? '工具调用').toString();
    final detail = _toolCardDetail(cards);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isUser ? Colors.white.withOpacity(0.12) : const Color(0xFFF4F1FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isUser ? Colors.white24 : const Color(0xFFE4DDF3)),
      ),
      child: ToolCardFold(title: title, detail: detail, isUser: isUser),
    );
  }

  /// 把卡片列表格式化为可读的详情文本
  String _toolCardDetail(List<Map<String, dynamic>> cards) {
    final buf = StringBuffer();
    for (final c in cards) {
      final t = (c['title'] ?? '').toString();
      final content = c['content'] ?? c['summary'] ?? c['result'] ?? '';
      buf.writeln('• $t');
      if (content is String && content.isNotEmpty) {
        buf.writeln('  ${content.length > 120 ? content.substring(0, 120) + '…' : content}');
      }
    }
    return buf.toString();
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: '跟Ever说点什么…',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              color: const Color(0xFF8E7CC3),
            ),
          ],
        ),
      ),
    );
  }
}
/// 工具调用折叠卡片 - 可点击展开查看详情
class ToolCardFold extends StatefulWidget {
  final String title;
  final String detail;
  final bool isUser;
  const ToolCardFold({super.key, required this.title, required this.detail, this.isUser = false});

  @override
  State<ToolCardFold> createState() => _ToolCardFoldState();
}

class _ToolCardFoldState extends State<ToolCardFold> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isUser ? Icons.auto_awesome : Icons.build_circle_outlined,
                size: 15,
                color: widget.isUser ? Colors.white70 : const Color(0xFF8E7CC3),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: widget.isUser ? Colors.white : const Color(0xFF5B4B8A),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: widget.isUser ? Colors.white70 : const Color(0xFF8E7CC3),
              ),
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SelectableText(
              widget.detail.trim(),
              style: TextStyle(
                fontSize: 12,
                color: widget.isUser ? Colors.white70 : Colors.grey[700],
                height: 1.5,
              ),
            ),
          ),
      ],
    );
  }
}
