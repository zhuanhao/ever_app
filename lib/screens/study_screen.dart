import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_client.dart';
import 'dart:convert';

class StudyEntry {
  String id;
  String title;
  String content;
  bool onlyMe;
  DateTime createdAt;

  StudyEntry({
    required this.id,
    required this.title,
    required this.content,
    this.onlyMe = false,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'onlyMe': onlyMe,
        'createdAt': createdAt.toIso8601String(),
      };

  factory StudyEntry.fromJson(Map<String, dynamic> json) => StudyEntry(
        id: json['id'] as String,
        title: json['title'] as String,
        content: json['content'] as String,
        onlyMe: json['onlyMe'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  final List<StudyEntry> _entries = [];
  final ApiClient _api = ApiClient();
  static const _kKey = 'ever_study';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        setState(() => _entries..clear()..addAll(list.map((e) => StudyEntry.fromJson(e as Map<String, dynamic>))));
      } catch (_) {}
    }
    // 拉取云端共享书房（仅公开帖），合并到本地（按 id 去重）
    final cloud = await _api.fetchShared('study');
    final cloudList = (cloud['items'] as List? ?? []);
    setState(() {
      for (final c in cloudList) {
        final item = StudyEntry.fromJson(c as Map<String, dynamic>);
        if (!_entries.any((e) => e.id == item.id)) {
          _entries.add(item);
        }
      }
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    // 仅同步公开帖到云端，仅自己可见的只留本地
    final publicList = _entries.where((e) => !e.onlyMe).map((e) => e.toJson()).toList();
    await _api.saveShared('study', {'items': publicList});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的书房')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF8E7CC3),
        shape: const CircleBorder(),
        onPressed: _addEntry,
        child: const Icon(Icons.edit, color: Colors.white),
      ),
      body: _entries.isEmpty ? _buildEmpty() : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.menu_book, size: 56, color: Color(0xFFD9CFEC)),
          const SizedBox(height: 12),
          const Text('书房空空', style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 4),
          Text('记录想法、日记或成长', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildList() {
    final sorted = _entries.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: sorted.map(_buildCard).toList(),
    );
  }

  Widget _buildCard(StudyEntry e) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(e.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                if (e.onlyMe) Icon(Icons.lock, size: 13, color: Colors.grey[400]),
                if (e.onlyMe) const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _deleteEntry(e),
                  child: Icon(Icons.close, size: 15, color: Colors.grey[400]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(e.content, style: TextStyle(fontSize: 14, height: 1.6, color: Colors.grey[700])),
            const SizedBox(height: 10),
            Text(_formatTime(e.createdAt), style: TextStyle(fontSize: 11, color: Colors.grey[400])),
          ],
        ),
      ),
    );
  }

  void _addEntry() {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    bool onlyMe = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('写一篇', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(hintText: '标题'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentCtrl,
                  maxLines: 5,
                  minLines: 3,
                  decoration: const InputDecoration(hintText: '写点什么…'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => setModalState(() => onlyMe = !onlyMe),
                      child: Row(
                        children: [
                          Icon(
                            onlyMe ? Icons.visibility_off : Icons.visibility,
                            size: 18,
                            color: onlyMe ? const Color(0xFF8E7CC3) : Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(onlyMe ? '仅自己可见' : '公开给Ever', style: TextStyle(fontSize: 13, color: onlyMe ? const Color(0xFF8E7CC3) : Colors.grey[500])),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8E7CC3),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      final title = titleCtrl.text.trim();
                      final content = contentCtrl.text.trim();
                      if (title.isEmpty) return;
                      setState(() {
                        _entries.add(StudyEntry(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          title: title,
                          content: content,
                          onlyMe: onlyMe,
                          createdAt: DateTime.now(),
                        ));
                      });
                      _persist();
                      Navigator.pop(ctx);
                    },
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _deleteEntry(StudyEntry e) {
    setState(() => _entries.remove(e));
    _persist();
  }

  String _formatTime(DateTime t) {
    return '${t.year}.${t.month.toString().padLeft(2, '0')}.${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}