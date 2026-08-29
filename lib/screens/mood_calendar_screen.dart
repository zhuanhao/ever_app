import 'package:flutter/material.dart';

/// 心情打卡日历 - 情侣双方每日打卡，互相可见
/// 骨架版本：月度日历 + 每天心情标签 + 打卡入口
/// TODO: 接后端数据同步（双方心情互通）、心情标签体系完善
class MoodCalendarScreen extends StatefulWidget {
  const MoodCalendarScreen({super.key});

  @override
  State<MoodCalendarScreen> createState() => _MoodCalendarScreenState();
}

class _MoodCalendarScreenState extends State<MoodCalendarScreen> {
  // 当前显示的月份（默认今天所在月）
  late DateTime _currentMonth;
  // 心情标签映射：日期(yyyy-MM-dd) -> 心情表情
  final Map<String, String> _moods = {};
  // 心情标签可选集合
  static const List<Map<String, String>> _moodOptions = [
    {'emoji': '😊', 'label': '开心'},
    {'emoji': '🥰', 'label': '想你了'},
    {'emoji': '😢', 'label': '难过'},
    {'emoji': '😴', 'label': '累了'},
    {'emoji': '🤔', 'label': '一般'},
    {'emoji': '😡', 'label': '烦'},
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
  }

  String _dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // 计算当月第一天是周几（0=周日）
  int _firstWeekday(DateTime month) => DateTime(month.year, month.month, 1).weekday % 7;

  // 当月天数
  int _daysInMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

  void _prevMonth() => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1));
  void _nextMonth() => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1));

  /// 打卡：弹出底部选择心情
  void _pickMood(DateTime day) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${day.month}月${day.day}日 打卡心情', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _moodOptions.map((m) {
                    return GestureDetector(
                      onTap: () {
                        setState(() => _moods[_dateKey(day)] = m['emoji']!);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8E7CC3).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text('${m['emoji']} ${m['label']}', style: const TextStyle(fontSize: 15)),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstWd = _firstWeekday(_currentMonth);
    final days = _daysInMonth(_currentMonth);
    // 总格子数：补齐前导空格 + 当月天
    final totalCells = firstWd + days;

    return Scaffold(
      appBar: AppBar(title: const Text('心情打卡')),
      backgroundColor: const Color(0xFFFAF8F5),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 月份切换
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(onPressed: _prevMonth, icon: const Icon(Icons.chevron_left)),
              Text('${_currentMonth.year}年 ${_currentMonth.month}月', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              IconButton(onPressed: _nextMonth, icon: const Icon(Icons.chevron_right)),
            ],
          ),
          const SizedBox(height: 12),
          // 星期表头
          Row(
            children: ['日', '一', '二', '三', '四', '五', '六'].map((w) {
              return Expanded(
                child: Center(child: Text(w, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // 日历网格
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: totalCells,
            itemBuilder: (ctx, index) {
              final dayNum = index - firstWd + 1;
              if (dayNum < 1 || dayNum > days) {
                return const SizedBox.shrink(); // 空白
              }
              final date = DateTime(_currentMonth.year, _currentMonth.month, dayNum);
              final mood = _moods[_dateKey(date)];
              return GestureDetector(
                onTap: () => _pickMood(date),
                child: Container(
                  decoration: BoxDecoration(
                    color: mood != null ? const Color(0xFF8E7CC3).withOpacity(0.15) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$dayNum', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                      if (mood != null) Text(mood, style: const TextStyle(fontSize: 18)),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Text('点日期即可打卡心情，双方互相可见', style: TextStyle(color: Colors.grey[600], fontSize: 12), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
