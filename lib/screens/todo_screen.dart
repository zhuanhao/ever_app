import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_client.dart';
import 'dart:convert';

class TodoItem {
  String id;
  String text;
  bool done;
  String source; // 'me' 自己 / 'ever' Ever设的
  DateTime createdAt;

  TodoItem({
    required this.id,
    required this.text,
    this.done = false,
    this.source = 'me',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'done': done,
        'source': source,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TodoItem.fromJson(Map<String, dynamic> json) => TodoItem(
        id: json['id'] as String,
        text: json['text'] as String,
        done: json['done'] as bool,
        source: (json['source'] as String?) ?? 'me',
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  final TextEditingController _input = TextEditingController();
  final ApiClient _api = ApiClient();
  final List<TodoItem> _todos = [];
  static const _kKey = 'ever_todos';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        setState(() => _todos..clear()..addAll(list.map((e) => TodoItem.fromJson(e as Map<String, dynamic>))));
      } catch (_) {}
    }
    // 拉取云端共享待办，合并到本地（按 id 去重）
    final cloud = await _api.fetchShared('todo');
    final cloudList = (cloud['items'] as List? ?? []);
    setState(() {
      for (final c in cloudList) {
        final item = TodoItem.fromJson(c as Map<String, dynamic>);
        if (!_todos.any((t) => t.id == item.id)) {
          _todos.add(item);
        }
      }
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final json = _todos.map((t) => t.toJson()).toList();
    await prefs.setString(_kKey, jsonEncode(json));
    // 同步到云端
    await _api.saveShared('todo', {'items': json});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('待办')),
      body: Column(
        children: [
          _buildStats(),
          Expanded(
            child: _todos.isEmpty ? _buildEmpty() : _buildList(),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final total = _todos.length;
    final done = _todos.where((t) => t.done).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          const Icon(Icons.local_fire_department, color: Color(0xFF8E7CC3), size: 18),
          const SizedBox(width: 6),
          Text('$done/$total 已完成', style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const Spacer(),
          if (total > 0)
            TextButton(
              onPressed: _clearDone,
              child: Text('清除已完成', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.checklist, size: 56, color: Color(0xFFD9CFEC)),
          const SizedBox(height: 12),
          const Text('还没有待办', style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 4),
          Text('在下面加一个吧', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildList() {
    final pending = _todos.where((t) => !t.done).toList();
    final done = _todos.where((t) => t.done).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      children: [
        ...pending.map(_buildItem),
        ...done.map((t) => _buildItem(t, dimmed: true)),
      ],
    );
  }

  Widget _buildItem(TodoItem item, {bool dimmed = false}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: GestureDetector(
          onTap: () => _toggle(item),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: item.done ? const Color(0xFF8E7CC3) : Colors.transparent,
              border: Border.all(color: item.done ? Colors.transparent : const Color(0xFFD9CFEC), width: 2),
            ),
            child: item.done
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : null,
          ),
        ),
        title: Text(
          item.text,
          style: TextStyle(
            fontSize: 15,
            decoration: item.done ? TextDecoration.lineThrough : null,
            color: dimmed ? Colors.grey[400] : const Color(0xFF3B3B3B),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.source == 'ever')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF8E7CC3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Ever', style: TextStyle(fontSize: 10, color: Color(0xFF8E7CC3))),
              ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _delete(item),
              child: Icon(Icons.close, size: 16, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      color: const Color(0xFFFAF8F5),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              decoration: const InputDecoration(
                hintText: '添加待办…',
                hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _add,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF8E7CC3),
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  void _add() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final item = TodoItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      source: 'me',
      createdAt: DateTime.now(),
    );
    setState(() => _todos.add(item));
    _input.clear();
    _persist();
  }

  void _toggle(TodoItem item) {
    setState(() => item.done = !item.done);
    _persist();
  }

  void _delete(TodoItem item) {
    setState(() => _todos.remove(item));
    _persist();
  }

  void _clearDone() {
    setState(() => _todos.removeWhere((t) => t.done));
    _persist();
  }
}