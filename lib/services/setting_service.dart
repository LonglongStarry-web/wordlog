import '../db/database.dart';
import 'ai_service.dart';

class SettingService {
  static const _kKey = 'api_key';

  static const kBaseUrl = 'api_base_url';
  static const kModel = 'model';
  static const kTemplate = 'prompt_template';
  static const kExportUri = 'export_dir_uri';
  static const kRemindHour = 'remind_hour';
  static const kRemindMinute = 'remind_minute';
  static const kRemindOn = 'remind_on';

  final AppDatabase db;

  SettingService(this.db);

  Future<AiConfig> loadConfig() async {
    final all = await db.allSettings();
    final key = (await db.getSetting(_kKey)) ?? '';
    return AiConfig(
      baseUrl: all[kBaseUrl] ?? 'https://api.deepseek.com',
      apiKey: key,
      model: all[kModel] ?? 'deepseek-chat',
    );
  }

  Future<void> saveConfig(AiConfig cfg) async {
    await db.setSetting(kBaseUrl, cfg.baseUrl);
    await db.setSetting(kModel, cfg.model);
    await db.setSetting(_kKey, cfg.apiKey);
  }

  Future<String> template() async {
    final v = await db.getSetting(kTemplate);
    if (v == null || v.trim().isEmpty) return AiService.defaultTemplate;
    return v;
  }

  Future<void> saveTemplate(String v) => db.setSetting(kTemplate, v);

  Future<String?> exportUri() => db.getSetting(kExportUri);

  Future<void> saveExportUri(String uri) => db.setSetting(kExportUri, uri);

  Future<bool> remindOn() async => (await db.getSetting(kRemindOn)) == '1';

  Future<void> setRemindOn(bool on) =>
      db.setSetting(kRemindOn, on ? '1' : '0');

  Future<int> remindHour() async =>
      int.tryParse((await db.getSetting(kRemindHour)) ?? '21') ?? 21;

  Future<int> remindMinute() async =>
      int.tryParse((await db.getSetting(kRemindMinute)) ?? '0') ?? 0;

  Future<void> saveRemindTime(int h, int m) async {
    await db.setSetting(kRemindHour, '$h');
    await db.setSetting(kRemindMinute, '$m');
  }
}
