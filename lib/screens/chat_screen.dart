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
    };
    _stream.startPolling(knownIds: _messages.map((m) => m.id).toSet());
    // 检查后端状态
    final status = await _api.fetchStatus();
    if (mounted) setState(() => _connected = (status['alive'] == true));
  }

  @override
  void dispose() {
    _stream.dispose();
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
      final reply = await _chat.sendText(text);
      if (mounted) {
        setState(() {
          userMsg.status = 1; // 标记发送成功
          _messages.add(reply);
          _sending = false;
          _connected = true;
        });
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

  // 消息操作菜单：复制 / 删除（后端同步） / 重新生成（助手消息）
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
              _menuItem(Icons.edit, '编辑', () {
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
        setState(() {
          _messages[idx].status = 1;
          _messages.add(reply);
          _connected = true;
        });
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
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _buildEmpty()
                    : ListView.builder(
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
    final isEvent = msg.msgType == 'event' || msg.fromBackend;
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
              child: Text(
                msg.content,
                style: TextStyle(color: isUser ? Colors.white : Colors.black87, fontSize: 15, height: 1.5),
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