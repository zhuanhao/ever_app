import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_client.dart';
import 'dart:convert';

class WorkflowTask {
  final String id;
  final String name;
  final String desc;
  bool enabled;

  WorkflowTask({
    required this.id,
    required this.name,
    required this.desc,
    required this.enabled,
  });

  factory WorkflowTask.fromJson(Map<String, dynamic> json) => WorkflowTask(
        id: json['id'],
        name: json['name'],
        desc: json['desc'] ?? '',
        enabled: json['enabled'] ?? true,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'desc': desc, 'enabled': enabled};
}

class WorkflowScreen extends StatefulWidget {
  const WorkflowScreen({super.key});

  @override
  State<WorkflowScreen> createState() => _WorkflowScreenState();
}

class _WorkflowScreenState extends State<WorkflowScreen> {
  List<WorkflowTask> _tasks = [];
  bool _loaded = false;
  final ApiClient _api = ApiClient();
  static const _prefKey = 'workflow_tasks';

  final _defaultTasks = [
    WorkflowTask(id: 'auto_wake', name: '自动唤醒', desc: '超过1小时无聊天时主动发起问候', enabled: true),
    WorkflowTask(id: 'activity_log', name: '活动日志', desc: '记录自动活动，供回溯查看', enabled: true),
    WorkflowTask(id: 'daily_summary', name: '每日摘要', desc: '每天整理日常，沉淀到时间线', enabled: false),
    WorkflowTask(id: 'mood_checkin', name: '心情打卡提醒', desc: '每天提醒一次打卡心情', enabled: false),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw != null) {
      final list = (jsonDecode(raw) as List).map((e) => WorkflowTask.fromJson(e)).toList();
      setState(() {
        _tasks = list;
        _loaded = true;
      });
    } else {
      // 首次使用，写入默认任务
      _tasks = _defaultTasks.map((t) => WorkflowTask(id: t.id, name: t.name, desc: t.desc, enabled: t.enabled)).toList();
      await _save();
      setState(() => _loaded = true);
    }
    // 拉取云端共享工作流，补充本地缺失的任务（按 id 去重）
    final cloud = await _api.fetchShared('workflow');
    final cloudList = (cloud['items'] as List? ?? []);
    setState(() {
      for (final c in cloudList) {
        final item = WorkflowTask.fromJson(c as Map<String, dynamic>);
        if (!_tasks.any((t) => t.id == item.id)) {
          _tasks.add(item);
        }
      }
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(_tasks.map((e) => e.toJson()).toList()));
    // 同步整个列表到云端
    await _api.saveShared('workflow', {'items': _tasks.map((e) => e.toJson()).toList()});
  }

  void _toggle(String id, bool value) {
    setState(() {
      final idx = _tasks.indexWhere((t) => t.id == id);
      if (idx >= 0) _tasks[idx].enabled = value;
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F5),
      appBar: AppBar(
        title: const Text('工作流', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFFFAF8F5),
        elevation: 0,
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('自动化的行为开关，控制 Ever 的自主生活', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ),
                ..._tasks.map((task) => Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: SwitchListTile(
                        value: task.enabled,
                        onChanged: (v) => _toggle(task.id, v),
                        activeColor: const Color(0xFF8E7CC3),
                        title: Text(task.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(task.desc, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ),
                    )),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  color: const Color(0xFFF0EDE8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFF8E7CC3), size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '工作流开关会同步到后端，Ever 会据此决定是否自主活动\n（当前为本地版，后端同步待接入）',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}