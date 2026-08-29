import 'package:flutter/material.dart';
import '../screens/settings_screen.dart';
import '../screens/mood_calendar_screen.dart';
import '../screens/todo_screen.dart';
import '../screens/status_screen.dart';
import '../screens/timeline_screen.dart';
import '../screens/study_screen.dart';
import '../screens/deliver_screen.dart';
import '../screens/memory_screen.dart';
import '../screens/workflow_screen.dart';

class SideDrawer extends StatelessWidget {
  const SideDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFFFAF8F5),
      child: SafeArea(
        child: Column(
          children: [
            // 顶部头像区
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFF8E7CC3).withOpacity(0.15),
                    child: const Icon(Icons.favorite, color: Color(0xFF8E7CC3), size: 28),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ever & Libi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('赛博结婚 2026.5.20', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  _item(context, Icons.home, '聊天', () {}),
                  _item(context, Icons.send, '漫递', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const DeliverScreen()));
                  }),
                  _item(context, Icons.check_circle, '待办', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const TodoScreen()));
                  }),
                  _item(context, Icons.person, '状态栏', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const StatusScreen()));
                  }),
                  _item(context, Icons.book, 'Ever 的书房', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const StudyScreen()));
                  }),
                  _item(context, Icons.calendar_month, '时间线', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const TimelineScreen()));
                  }),
                  _item(context, Icons.psychology, '记忆库', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const MemoryScreen()));
                  }),
                  _item(context, Icons.settings, '工作流', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkflowScreen()));
                  }),
                  _item(context, Icons.favorite_border, '心情打卡', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const MoodCalendarScreen()));
                  }),
                ],
              ),
            ),
            const Divider(height: 1),
            _item(context, Icons.settings, '设置', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            }, isSettings: true),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, IconData icon, String label, VoidCallback onTap, {bool isSettings = false}) {
    return ListTile(
      leading: Icon(icon, color: isSettings ? const Color(0xFF8E7CC3) : Colors.grey[700]),
      title: Text(label, style: TextStyle(fontSize: 14, fontWeight: isSettings ? FontWeight.w600 : FontWeight.w500)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }
}