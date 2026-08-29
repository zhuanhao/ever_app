import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_client.dart';
import 'dart:convert';

class DeliverItem {
  final String id;
  final String text;
  final DateTime deliverTime;
  final bool delivered;
  final DateTime createdAt;

  DeliverItem({
    required this.id,
    required this.text,
    required this.deliverTime,
    required this.delivered,
    required this.createdAt,
  });

  factory DeliverItem.fromJson(Map<String, dynamic> json) => DeliverItem(
        id: json['id'],
        text: json['text'],
        deliverTime: DateTime.parse(json['deliverTime']),
        delivered: json['delivered'] ?? false,
        createdAt: DateTime.parse(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'deliverTime': deliverTime.toIso8601String(),
        'delivered': delivered,
        'createdAt': createdAt.toIso8601String(),
      };
}

class DeliverScreen extends StatefulWidget {
  const DeliverScreen({super.key});

  @override
  State<DeliverScreen> createState() => _DeliverScreenState();
}

class _DeliverScreenState extends State<DeliverScreen> {
  List<DeliverItem> _items = [];
  bool _loaded = false;
  final ApiClient _api = ApiClient();
  static const _prefKey = 'deliver_items';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw != null) {
      final list = (jsonDecode(raw) as List).map((e) => DeliverItem.fromJson(e)).toList();
      setState(() {
        _items = list;
        _loaded = true;
      });
    } else {
      setState(() => _loaded = true);
    }
    // 拉取云端共享漫递，合并到本地（按 id 去重）
    final cloud = await _api.fetchShared('deliver');
    final cloudList = (cloud['items'] as List? ?? []);
    setState(() {
      for (final c in cloudList) {
        final item = DeliverItem.fromJson(c as Map<String, dynamic>);
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
    await _api.saveShared('deliver', {'items': _items.map((e) => e.toJson()).toList()});
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    DateTime? selected = DateTime.now().add(const Duration(days: 1));
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('投递一封时光信'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLines: 4,
                decoration: const InputDecoration(hintText: '写给未来的话...'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule, color: Color(0xFF8E7CC3)),
                title: Text(selected == null
                    ? '选择送达时间'
                    : '送达时间：${selected!.month}/${selected!.day} ${selected!.hour}:${selected!.minute.toString().padLeft(2, '0')}'),
                onTap: () async {
                  final dt = await showDatePicker(
                    context: ctx,
                    initialDate: selected ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (dt != null) {
                    final tm = await showTimePicker(
                      context: ctx,
                      initialTime: const TimeOfDay(hour: 20, minute: 0),
                    );
                    if (tm != null) {
                      setModalState(() {
                        selected = DateTime(dt.year, dt.month, dt.day, tm.hour, tm.minute);
                      });
                    }
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () {
                if (controller.text.trim().isEmpty || selected == null) return;
                final item = DeliverItem(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  text: controller.text.trim(),
                  deliverTime: selected!,
                  delivered: false,
                  createdAt: DateTime.now(),
                );
                Navigator.pop(ctx);
                setState(() => _items.insert(0, item));
                _save();
              },
              child: const Text('投递'),
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

  String _fmt(DateTime t) => '${t.year}.${t.month}.${t.day} ${t.hour}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // 更新已到期的信为已送达状态
    for (var i = 0; i < _items.length; i++) {
      if (!_items[i].delivered && _items[i].deliverTime.isBefore(now)) {
        _items[i] = DeliverItem(
          id: _items[i].id,
          text: _items[i].text,
          deliverTime: _items[i].deliverTime,
          delivered: true,
          createdAt: _items[i].createdAt,
        );
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F5),
      appBar: AppBar(
        title: const Text('漫递', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFFFAF8F5),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF8E7CC3),
        onPressed: _showAddDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.markunread_mailbox_outlined, size: 56, color: Color(0xFF8E7CC3)),
                      SizedBox(height: 12),
                      Text('还没有时光信', style: TextStyle(color: Colors.grey, fontSize: 14)),
                      Text('写给未来的ta，定时送达', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  itemBuilder: (ctx, i) {
                    final item = _items[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 0,
                      color: item.delivered ? const Color(0xFFF0EDE8) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              item.delivered ? Icons.mark_email_read : Icons.schedule,
                              color: item.delivered ? const Color(0xFF8E7CC3) : Colors.grey[400],
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.text, style: const TextStyle(fontSize: 14, height: 1.5)),
                                  const SizedBox(height: 8),
                                  Text(
                                    item.delivered ? '已送达 · ${_fmt(item.deliverTime)}' : '定��送达 · ${_fmt(item.deliverTime)}',
                                    style: TextStyle(fontSize: 12, color: item.delivered ? const Color(0xFF8E7CC3) : Colors.grey[500]),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                              onPressed: () => _delete(item.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}