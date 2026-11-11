import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';
import '../services/ai_service.dart';
import '../services/notify_service.dart';
import '../services/platform_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _baseCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _tplCtrl = TextEditingController();
  bool _loading = true;
  bool _testing = false;
  bool _remindOn = false;
  int _hour = 21;
  int _minute = 0;
  String? _exportUri;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = ref.read(settingsProvider);
    final cfg = await s.loadConfig();
    _baseCtrl.text = cfg.baseUrl;
    _keyCtrl.text = cfg.apiKey;
    _modelCtrl.text = cfg.model;
    _tplCtrl.text = await s.template();
    _remindOn = await s.remindOn();
    _hour = await s.remindHour();
    _minute = await s.remindMinute();
    _exportUri = await s.exportUri();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final s = ref.read(settingsProvider);
    await s.saveConfig(AiConfig(
      baseUrl: _baseCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
    ));
    await s.saveTemplate(_tplCtrl.text);
    await s.setRemindOn(_remindOn);
    await s.saveRemindTime(_hour, _minute);
    if (_remindOn) {
      await NotifyService.ensurePermission();
      await NotifyService.scheduleDailyReminder(_hour, _minute);
    } else {
      await NotifyService.cancelReminder();
    }
    if (mounted) _snack('已保存');
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final cfg = AiConfig(
      baseUrl: _baseCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
    );
    final ok = await AiService.testConnection(cfg);
    if (!mounted) return;
    setState(() => _testing = false);
    _snack(ok ? '连接正常' : '连接失败，请检查 BaseURL / Key / 模型名');
  }

  Future<void> _pickDir() async {
    final uri = await PlatformService.pickDirectory();
    if (uri == null || uri.isEmpty) return;
    await ref.read(settingsProvider).saveExportUri(uri);
    setState(() => _exportUri = uri);
    if (mounted) _snack('已设置导出目录');
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
    );
    if (t == null) return;
    setState(() {
      _hour = t.hour;
      _minute = t.minute;
    });
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  void dispose() {
    _baseCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _tplCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Section(
            title: '大模型接口',
            children: [
              TextField(
                controller: _baseCtrl,
                decoration: const InputDecoration(
                  labelText: 'BaseURL',
                  hintText: 'https://api.deepseek.com',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _keyCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'API Key'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _modelCtrl,
                decoration: const InputDecoration(
                  labelText: '模型名',
                  hintText: 'deepseek-chat',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _testing ? null : _test,
                icon: const Icon(Icons.wifi_tethering),
                label: Text(_testing ? '测试中…' : '测试连接'),
              ),
              const SizedBox(height: 6),
              const Text(
                '兼容 OpenAI 的 /v1/chat/completions 接口，DeepSeek、通义、智谱、本地 Ollama 都能填。',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
          _Section(
            title: '导出到 Obsidian',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_open_outlined),
                title: Text(_exportUri == null
                    ? '还没选择目录'
                    : '已选择：${_exportUri!.split('/').last}'),
                subtitle: const Text('点一下可重新选择'),
                onTap: _pickDir,
              ),
              const Text(
                '选你手机上 Obsidian 仓库的目录（授权一次长期有效），导出后靠你已有的同步到电脑。',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
          _Section(
            title: '每日提醒',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('开启提醒'),
                value: _remindOn,
                onChanged: (v) => setState(() => _remindOn = v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.alarm),
                title: const Text('提醒时间'),
                trailing: Text(
                    '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}'),
                onTap: _pickTime,
              ),
              const Text(
                '国产 ROM 需要在系统设置里允许本应用自启动和后台运行，否则提醒可能不送达。',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
          _Section(
            title: '解释模板',
            children: [
              TextField(
                controller: _tplCtrl,
                maxLines: 12,
                decoration: const InputDecoration(
                  alignLabelWithHint: true,
                  hintText: '留空则使用默认四段式模板',
                ),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => setState(
                    () => _tplCtrl.text = AiService.defaultTemplate),
                icon: const Icon(Icons.restart_alt),
                label: const Text('恢复默认模板'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1F2430)),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
