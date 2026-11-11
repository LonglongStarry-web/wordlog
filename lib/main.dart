import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/database.dart';
import 'models/term.dart';
import 'screens/home_shell.dart';
import 'services/notify_service.dart';
import 'services/setting_service.dart';
import 'theme.dart';

final dbProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());

final settingsProvider =
    Provider<SettingService>((ref) => SettingService(ref.watch(dbProvider)));

/// 数据变更计数器，任何写操作后 +1 触发刷新
class RevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final revisionProvider =
    NotifierProvider<RevisionNotifier, int>(RevisionNotifier.new);

final todayTermsProvider = FutureProvider<List<Term>>((ref) async {
  ref.watch(revisionProvider);
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 1));
  return ref.watch(dbProvider).termsBetween(start, end);
});

final allTermsProvider = FutureProvider<List<Term>>((ref) async {
  ref.watch(revisionProvider);
  return ref.watch(dbProvider).allTerms();
});

final searchProvider = FutureProvider.family<List<Term>, String>((ref, kw) async {
  ref.watch(revisionProvider);
  if (kw.trim().isEmpty) return <Term>[];
  return ref.watch(dbProvider).search(kw.trim());
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  await NotifyService.init();
  runApp(
    ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const WordLogApp(),
    ),
  );
}

class WordLogApp extends StatelessWidget {
  const WordLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '词记本',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeShell(),
    );
  }
}
