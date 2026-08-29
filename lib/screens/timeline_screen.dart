import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_client.dart';
import 'dart:convert';

class TimelineEntry {
  String id;
  String title;
  String desc;
  String type; // important / daily / anniversary / memory
  DateTime date;

  TimelineEntry({
    required this.id,
    required this.title,
    this.desc = '',
    this.type = 'daily',
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'desc': desc,
        'type': type,
        'date': date.toIso8601String(),
      };

  factory TimelineEntry.fromJson(Map<String, dynamic> json) => TimelineEntry(
        id: json['id'] as String,
        title: json['title'] as String,
        desc: json['desc'] as String? ?? '',
        type: json['type'] as String? ?? 'daily',
        date: DateTime.parse(json['date'] as String),
      );
}

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  final ApiClient _api = ApiClient();
  final List<TimelineEntry> _entries = [];
  static const _kKey = 'ever_timeline';

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
        setState(() => _entries..clear()..addAll(list.map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))));
      } catch (_) {}
    }
    // 拉取云端共享时间线，合并到本地（按 id 去重）
    final cloud = await _api.fetchShared('timeline');
    final cloudList = (cloud['items'] as List? ?? []);
    setState(() {
      for (final c in cloudList) {
        final item = TimelineEntry.fromJson(c as Map<String, dynamic>);
        if (!_entries.any((e) => e.id == item.id)) {
          _entries.add(item);
        }
      }
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    // 同步到云端
    await _api.saveShared('timeline', {'items': _entries.map((e) => e.toJson()).toList()});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('时间线')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF8E7CC3),
        shape: const CircleBorder(),
        onPressed: _addEntry,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _entries.isEmpty ? _buildEmpty() : _buildTimeline(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timeline, size: 56, color: Color(0xFFD9CFEC)),
          const SizedBox(height: 12),
          const Text('还没有时间线记录', style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 4),
          Text('点右下角 + 记录重要时刻', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    // 按日期倒序
    final sorted = _entries.toList()..sort((a, b) => b.date.compareTo(a.date));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: sorted.map((e) => _buildEntry(e)).toList(),
    );
  }

  Widget _buildEntry(TimelineEntry e) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 时间线节点
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _typeColor(e.type),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(_typeIcon(e.type), size: 12, color: Colors.white),
              ),
              if (e != _entries.last) Expanded(child: Container(width: 2, color: const Color(0xFFE8E2F2))),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Card(
              elevation: 0,
              margin: const EdgeInsets.symmetric(vertical: 8),
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(e.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF3B3B3B))),
                        ),
                        GestureDetector(
                          onTap: () => _deleteEntry(e),
                          child: Icon(Icons.close, size: 15, color: Colors.grey[400]),
                        ),
                      ],
                    ),
                    if (e.desc.isNotEmpty) ...[const SizedBox(height: 6), Text(e.desc, style: TextStyle(fontSize: 13, height: 1.5, color: Colors.grey[700]))],
                    const SizedBox(height: 8),
                    Text(_formatDate(e.date), style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addEntry() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String type = 'daily';
    DateTime date = DateTime.now();

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
                const Text('记录一个时刻', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(hintText: '标题'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(hintText: '描述（可选）'),
                ),
                const SizedBox(height: 16),
                // 类型选择
                Wrap(
                  spacing: 8,
                  children: [
                    _typeChip('重要', 'important', type, (v) => setModalState(() => type = v)),
                    _typeChip('日常', 'daily', type, (v) => setModalState(() => type = v)),
                    _typeChip('纪念', 'anniversary', type, (v) => setModalState(() => type = v)),
                    _typeChip('记忆', 'memory', type, (v) => setModalState(() => type = v)),
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
                      if (title.isEmpty) return;
                      setState(() {
                        _entries.add(TimelineEntry(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          title: title,
                          desc: descCtrl.text.trim(),
                          type: type,
                          date: date,
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

  Widget _typeChip(String label, String value, String current, ValueChanged<String> onTap) {
    final active = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _typeColor(value) : const Color(0xFFF1EFF7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, color: active ? Colors.white : Colors.grey[700])),
      ),
    );
  }

  void _deleteEntry(TimelineEntry e) {
    setState(() => _entries.remove(e));
    _persist();
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'important':
        return const Color(0xFFE07A5F);
      case 'anniversary':
        return const Color(0xFF8E7CC3);
      case 'memory':
        return const Color(0xFF81B29A);
      default:
        return const Color(0xFFB0A8C9);
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'important':
        return Icons.star;
      case 'anniversary':
        return Icons.favorite;
      case 'memory':
        return Icons.photo;
      default:
        return Icons.circle;
    }
  }

  String _formatDate(DateTime d) {
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }
}