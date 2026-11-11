import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';
import '../models/term.dart';
import '../services/platform_service.dart';
import 'history_screen.dart';
import 'review_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'today_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainPending());
  }

  /// 把小组件 / 快捷入口暂存的词收进数据库
  Future<void> _drainPending() async {
    try {
      final items = await PlatformService.pending();
      if (items.isEmpty) {
        await _pushStats();
        return;
      }
      final db = ref.read(dbProvider);
      for (final m in items) {
        final name = (m['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final ctx = (m['context'] ?? '').toString();
        final ts = (m['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
        await db.insertTerm(Term(
          name: name,
          context: ctx.isEmpty ? null : ctx,
          createdAt: DateTime.fromMillisecondsSinceEpoch(ts),
        ));
      }
      await PlatformService.clearPending();
      ref.read(revisionProvider.notifier).bump();
    } catch (_) {
      // 原生通道不可用时静默降级
    }
    await _pushStats();
  }

  Future<void> _pushStats() async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));
      final list = await ref.read(dbProvider).termsBetween(start, end);
      await PlatformService.updateWidgetStats(
        list.length,
        list.take(3).map((e) => e.name).toList(),
      );
    } catch (_) {}
  }

  void _go(int i) {
    setState(() => _index = i);
    if (i == 0) _drainPending();
  }

  @override
  Widget build(BuildContext context) {
    final pages = const [
      TodayScreen(),
      HistoryScreen(),
      ReviewScreen(),
      StatsScreen(),
      SettingsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE8ECFE),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: '今日'),
          NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: '历史'),
          NavigationDestination(icon: Icon(Icons.style_outlined), selectedIcon: Icon(Icons.style), label: '复习'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: '统计'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
