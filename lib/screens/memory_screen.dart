import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_client.dart';
import 'dart:convert';

class MemoryItem {
  final String id;
  final String title;
  final String content;
  final String layer; // important / daily / anchor
  final DateTime createdAt;

  MemoryItem({
    required this.id,
    required this.title,
    required this.content,
    required this.layer,
    required this.createdAt,
  });

  factory MemoryItem.fromJson(Map<String, dynamic> json) => MemoryItem(
        id: json['id'],
        title: json['title'],
        content: json['content'],
        layer: json['layer'] ?? 'daily',
        createdAt: DateTime.parse(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'layer': layer,
        'createdAt': createdAt.toIso8601String(),
      };
}

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  List<MemoryItem> _items = [];
  bool _loaded = false;
  final ApiClient _api = ApiClient();
  static const _prefKey = 'memory_items';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw != null) {
      final list = (jsonDecode(raw) as List).map((e) => MemoryItem.fromJson(e)).toList();
      setState(() {
        _items = list;
        _loaded = true;
      });
    } else {
      setState(() => _loaded = true);
    }
    // 拉取云端共享记忆库，合并到本地（按 id 去重）
    final cloud = await _api.fetchShared('memory');
    final cloudList = (cloud['items'] as List? ?? []);
    setState(() {
      for (final c in cloudList) {
        final item = MemoryItem.fromJson(c as Map<String, dynamic>);
        if (!_items.any((e) => e.id == item.id)) {
          _items.add(item);
        }
      }
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(_items.map((e) => e.toJson()).toList()));
    // 同步整个列表到云端
    await _api.saveShared('memory', {'items': _items.map((e) => e.toJson()).toList()});
  }

  Future<void> _showAddDialog() async {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    String layer = 'daily';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('记录一条记忆'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(hintText: '标题')),
              const SizedBox(height: 12),
              TextField(controller: contentCtrl, maxLines: 3, decoration: const InputDecoration(hintText: '内容')),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'daily', label: Text('日常')),
                  ButtonSegment(value: 'important', label: Text('重要')),
                  ButtonSegment(value: 'anchor', label: Text('锚点')),
                ],
                selected: {layer},
                onSelectionChanged: (s) => setModalState(() => layer = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) return;
                final item = MemoryItem(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  title: titleCtrl.text.trim(),
                  content: contentCtrl.text.trim(),
                  layer: layer,
                  createdAt: DateTime.now(),
                );
                Navigator.pop(ctx);
                setState(() => _items.insert(0, item));
                _save();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _delete(String id) {
    setState(() => _items.removeWhere((e) => e.id == id));
    _save();
  }

  (String, Color) _layerInfo(String layer) {
    switch (layer) {
      case 'important':
        return ('重��', const Color(0xFFE07A5F));
      case 'anchor':
        return ('锚点', const Color(0xFF8E7CC3));
      default:
        return ('日常', Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter == 'all' ? _items : _items.where((e) => e.layer == _filter).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F5),
      appBar: AppBar(
        title: const Text('记忆库', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFFFAF8F5),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => setState(() => _filter = v),
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'all', child: Text('全部')),
              PopupMenuItem(value: 'daily', child: Text('日常')),
              PopupMenuItem(value: 'important', child: Text('重要')),
              PopupMenuItem(value: 'anchor', child: Text('锚点')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF8E7CC3),
        onPressed: _showAddDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : filtered.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.psychology_outlined, size: 56, color: Color(0xFF8E7CC3)),
                      SizedBox(height: 12),
                      Text('还没有记忆', style: TextStyle(color: Colors.grey, fontSize: 14)),
                      Text('把重要的东西存下来', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final item = filtered[i];
                    final (label, color) = _layerInfo(item.layer);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                                  child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                                  onPressed: () => _delete(item.id),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(item.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            if (item.content.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(item.content, style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.4)),
                            ],
                            const SizedBox(height: 6),
                            Text('${item.createdAt.month}/${item.createdAt.day}', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}