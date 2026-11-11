import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotifyService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _remindId = 1001;

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
    );
  }

  static Future<bool> ensurePermission() async {
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final granted =
        await androidImpl?.requestNotificationsPermission() ?? false;
    return granted;
  }

  static Future<void> cancelReminder() => _plugin.cancel(id: _remindId);

  static Future<void> scheduleDailyReminder(int hour, int minute) async {
    await cancelReminder();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'wordlog_remind',
        '每日回顾提醒',
        channelDescription: '提醒你回顾今天记下的词并生成解释',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    await _plugin.periodicallyShow(
      id: _remindId,
      title: '今天记了几个词？',
      body: '点开看看，让 AI 帮你把没搞懂的讲清楚',
      repeatInterval: RepeatInterval.daily,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> notifyExportDone(String fileName) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'wordlog_export',
        '导出结果',
        channelDescription: 'Markdown 导出完成通知',
        importance: Importance.low,
        priority: Priority.low,
      ),
    );
    await _plugin.show(
      id: 2002,
      title: '导出完成',
      body: '已写入 $fileName',
      notificationDetails: details,
    );
  }
}
