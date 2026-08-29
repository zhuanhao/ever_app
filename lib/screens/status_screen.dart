import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_client.dart';
import 'dart:convert';

class StatusPost {
  String id;
  String text;
  bool onlyMe;
  DateTime createdAt;

  StatusPost({
    required this.id,
    required this.text,
    this.onlyMe = false,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'onlyMe': onlyMe,
        'createdAt': createdAt.toIso8601String(),
      };

  factory StatusPost.fromJson(Map<String, dynamic> json) => StatusPost(
        id: json['id'] as String,
        text: json['text'] as String,
        onlyMe: json['onlyMe'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final TextEditingController _input = TextEditingController();
  final ApiClient _api = ApiClient();
  final List<StatusPost> _posts = [];
  bool _onlyMe = false;
  static const _kKey = 'ever_status_posts';

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
        setState(() => _posts..clear()..addAll(list.map((e) => StatusPost.fromJson(e as Map<String, dynamic>))));
      } catch (_) {}
    }
    // 拉取云端公开状态，合并到本地（按 id 去重）
    final cloud = await _api.fetchShared('status');
    final cloudList = (cloud['items'] as List? ?? []);
    setState(() {
      for (final c in cloudList) {
        final item = StatusPost.fromJson(c as Map<String, dynamic>);
        if (!_posts.any((p) => p.id == item.id)) {
          _posts.add(item);
        }
      }
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(_posts.map((p) => p.toJson()).toList()));
    // 仅同步公开状态到云端（onlyMe=false 才给别人看）
    final publicPosts = _posts.where((p) => !p.onlyMe).map((p) => p.toJson()).toList();
    await _api.saveShared('status', {'items': publicPosts});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('状态栏')),
      body: Column(
        children: [
          _buildInputArea(),
          const Divider(height: 1),
          Expanded(
            child: _posts.isEmpty ? _buildEmpty() : _buildFeed(),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      color: const Color(0xFFFAF8F5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _input,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              hintText: '此刻的状态…',
              hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _onlyMe = !_onlyMe),
                child: Row(
                  children: [
                    Icon(
                      _onlyMe ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                      color: _onlyMe ? const Color(0xFF8E7CC3) : Colors.grey[500],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _onlyMe ? '仅自己可见' : '公开',
                      style: TextStyle(
                        fontSize: 13,
                        color: _onlyMe ? const Color(0xFF8E7CC3) : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _publish,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8E7CC3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('发布', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
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
          const Icon(Icons.waving_hand, size: 56, color: Color(0xFFD9CFEC)),
          const SizedBox(height: 12),
          const Text('还没有状态', style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 4),
          Text('分享此刻的你在做什么', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildFeed() {
    final visible = _posts.toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: visible.map(_buildPost).toList(),
    );
  }

  Widget _buildPost(StatusPost post) {
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
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: Color(0xFF8E7CC3),
                  child: Icon(Icons.favorite, color: Colors.white, size: 14),
                ),
                const SizedBox(width: 10),
                const Text('Libi', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                if (post.onlyMe) ...[const SizedBox(width: 6), Icon(Icons.lock, size: 13, color: Colors.grey[400])],
                const Spacer(),
                Text(
                  _formatTime(post.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(post.text, style: const TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF3B3B3B))),
          ],
        ),
      ),
    );
  }

  void _publish() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final post = StatusPost(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      onlyMe: _onlyMe,
      createdAt: DateTime.now(),
    );
    setState(() {
      _posts.insert(0, post);
      _onlyMe = false;
    });
    _input.clear();
    _persist();
  }

  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }
}