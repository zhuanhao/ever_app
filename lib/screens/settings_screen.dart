import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/config_service.dart';
import '../services/api_client.dart';
import '../services/backup_service.dart';

/// 设置页 - 接入 ConfigService，真实可编辑
/// 支持：后端API地址 / 上游LLM地址 / API Key / 模型拉取选择 / 思维链开关 / 通知开关
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _config = ConfigService();
  final _backendCtrl = TextEditingController();
  final _llmCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  bool _showKey = false;

  bool _thinkingEnabled = false;
  bool _thinkingShow = false;
  bool _pushEnabled = false;

  List<String> _models = [];
  bool _loadingModels = false;
  bool _saving = false;

  // 版本更新相关
  String _currentVersion = '1.0.0+2'; // 本地版本（与 pubspec 同步手动维护）
  Map<String, dynamic> _latestVersion = {}; // 远端版本信息
  bool _checkingVersion = false;
  bool _versionChecked = false;
  bool _hasUpdate = false;

  // 备份/恢复相关
  bool _backingUp = false;
  bool _restoring = false;
  String? _lastBackupTime;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await _config.getAll();
    if (!mounted) return;
    setState(() {
      _backendCtrl.text = cfg['backendUrl'] as String;
      _llmCtrl.text = cfg['llmUrl'] as String;
      _apiKeyCtrl.text = cfg['apiKey'] as String;
      _modelCtrl.text = cfg['model'] as String;
      _thinkingEnabled = cfg['thinkingEnabled'] as bool;
      _thinkingShow = cfg['thinkingShow'] as bool;
      _pushEnabled = cfg['pushEnabled'] as bool;
    });
    // 加载最近备份时间
    final backend = cfg['backendUrl'] as String? ?? 'https://ever.phywn.top';
    final backup = BackupService(ApiClient(backendUrl: backend));
    final t = await backup.lastBackupTime();
    if (!mounted) return;
    setState(() => _lastBackupTime = t);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _config.set('backendUrl', _backendCtrl.text.trim());
    await _config.set('llmUrl', _llmCtrl.text.trim());
    await _config.set('apiKey', _apiKeyCtrl.text.trim());
    await _config.set('model', _modelCtrl.text.trim());
    await _config.set('thinkingEnabled', _thinkingEnabled);
    await _config.set('thinkingShow', _thinkingShow);
    await _config.set('pushEnabled', _pushEnabled);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存设置')),
      );
    }
  }

  Future<void> _fetchModels() async {
    setState(() => _loadingModels = true);
    final models = await _config.fetchModels();
    if (!mounted) return;
    setState(() {
      _models = models;
      _loadingModels = false;
    });
    if (models.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('拉取模型失败，请检查 LLM 地址和 Key')),
      );
    }
  }

  void _pickModel(String model) {
    setState(() => _modelCtrl.text = model);
  }

  @override
  void dispose() {
    _backendCtrl.dispose();
    _llmCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      backgroundColor: const Color(0xFFFAF8F5),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle('API 配置'),
          _textField(_backendCtrl, icon: Icons.dns, label: '后端 API 地址', hint: 'http://你的VPS:8899'),
          _textField(_llmCtrl, icon: Icons.language, label: '上游 LLM 地址', hint: 'https://中转站/v1'),
          _textField(_apiKeyCtrl, icon: Icons.key, label: 'API Key', hint: 'sk-...', obscure: !_showKey, suffix: IconButton(
            icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility, size: 18, color: Colors.grey),
            onPressed: () => setState(() => _showKey = !_showKey),
          )),
          _modelField(),
          const SizedBox(height: 8),
          _SaveBar(onSave: _save, saving: _saving),

          const SizedBox(height: 16),
          _SectionTitle('MCP 配置'),
          _SettingTile(
            icon: Icons.extension,
            title: 'MCP Server',
            subtitle: '像 RikkaHub 那样填写，同步后端共用',
            onTap: () => _showMcpHint(),
          ),

          const SizedBox(height: 16),
          _SectionTitle('偏好'),
          _SwitchTile(
            icon: Icons.psychology,
            title: '思维链开关',
            subtitle: '默认关闭节省 token，复杂问题可开启',
            value: _thinkingEnabled,
            onChanged: (v) => setState(() => _thinkingEnabled = v),
          ),
          _SwitchTile(
            icon: Icons.visibility,
            title: '展示思考过程',
            subtitle: '显示 AI 的思考过程（需开启思维链）',
            value: _thinkingShow,
            onChanged: (v) => setState(() => _thinkingShow = v),
          ),
          _SwitchTile(
            icon: Icons.notifications,
            title: '通知推送',
            subtitle: '后台有回复时及时提醒',
            value: _pushEnabled,
            onChanged: (v) => setState(() => _pushEnabled = v),
          ),

          const SizedBox(height: 16),
          _SectionTitle('数据备份'),
          _SettingTile(
            icon: Icons.cloud_upload,
            title: '备份到云端',
            subtitle: _backingUp
                ? '正在备份...'
                : '当前配置与数据一键备份\n上次备份：${_formatBackupTime(_lastBackupTime)}',
            onTap: _backupNow,
          ),
          _SettingTile(
            icon: Icons.cloud_download,
            title: '从云端导入',
            subtitle: _restoring
                ? '正在导入...'
                : '拉取最近一次备份并覆盖本地数据',
            onTap: _restoreNow,
          ),

          const SizedBox(height: 16),
          _SectionTitle('版本更新'),
          _SettingTile(
            icon: Icons.system_update,
            title: '检查更新',
            subtitle: _checkingVersion
                ? '正在检查...'
                : (_versionChecked && _hasUpdate)
                    ? '发现新版本 ${_latestVersion['version'] ?? ''}，点击查看'
                    : '当前版本 $_currentVersion',
            onTap: _checkForUpdate,
          ),
        ],
      ),
    );
  }

  Widget _textField(TextEditingController ctrl, {required IconData icon, required String label, required String hint, bool obscure = false, Widget? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: const Color(0xFF8E7CC3), size: 20),
          suffixIcon: suffix,
        ),
      ),
    );
  }

  Widget _modelField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _modelCtrl,
        readOnly: true,
        onTap: _models.isEmpty ? _fetchModels : _showModelPicker,
        decoration: InputDecoration(
          labelText: '模型选择',
          hintText: '点击拉取并选择可用模型',
          prefixIcon: const Icon(Icons.model_training, color: Color(0xFF8E7CC3), size: 20),
          suffixIcon: _loadingModels
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.arrow_drop_down, color: Color(0xFF8E7CC3), size: 22),
        ),
      ),
    );
  }

  void _showModelPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final list = _models;
        if (list.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('暂无模型，请检查 LLM 地址和 Key')),
          );
        }
        return SizedBox(
          height: 400,
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (ctx, i) {
              final model = list[i];
              final selected = model == _modelCtrl.text;
              return ListTile(
                title: Text(model, style: TextStyle(fontSize: 14, color: selected ? const Color(0xFF8E7CC3) : Colors.black87)),
                trailing: selected ? const Icon(Icons.check, color: Color(0xFF8E7CC3), size: 18) : null,
                onTap: () {
                  _pickModel(model);
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        );
      },
    );
  }

  void _showMcpHint() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('MCP Server', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            SizedBox(height: 12),
            Text('这里将来填写 MCP Server 配置（掌心窗/论坛/邮箱等），\n本地存一份并同步给后端，前后端共用同一套工具。\n\n当前为占位入口，后续版本接入。', style: TextStyle(fontSize: 14, height: 1.6, color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Future<void> _checkForUpdate() async {
    if (_checkingVersion) return;
    setState(() => _checkingVersion = true);
    final cfg = await _config.getAll();
    final backendUrl = (cfg['backendUrl'] as String? ?? 'https://ever.phywn.top');
    final api = ApiClient(backendUrl: backendUrl);
    final remote = await api.fetchVersion();
    if (!mounted) return;
    setState(() {
      _latestVersion = remote;
      _versionChecked = true;
      _checkingVersion = false;
      // 对比 build 号，远端 build > 本地则有更新
      final remoteBuild = (remote['build'] as num? ?? 0).toInt();
      final localBuild = _parseLocalBuild(_currentVersion);
      _hasUpdate = !remote.isEmpty && remoteBuild > localBuild;
    });

    if (!mounted) return;
    if (remote.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('检查版本失败，请确认后端地址')),
      );
    } else if (_hasUpdate) {
      _showUpdateDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('当前已是最新版本 ${_currentVersion}')),
      );
    }
  }

  Future<void> _backupNow() async {
    if (_backingUp) return;
    setState(() => _backingUp = true);
    final backend = _backendCtrl.text.trim().isEmpty ? 'https://ever.phywn.top' : _backendCtrl.text.trim();
    final backup = BackupService(ApiClient(backendUrl: backend));
    final ok = await backup.backup();
    if (!mounted) return;
    setState(() {
      _backingUp = false;
      if (ok) _lastBackupTime = DateTime.now().toIso8601String();
    });
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('备份成功，已存到云端')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('备份失败，请检查后端地址和网络')),
      );
    }
  }

  Future<void> _restoreNow() async {
    // 先确认，避免误覆盖
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入备份?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('将从云端拉取最近一次备份并覆盖当前本地配置与数据。\n此操作不可撤销，是否继续?', style: TextStyle(fontSize: 14, height: 1.6)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8E7CC3)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_restoring) return;
    setState(() => _restoring = true);
    final backend = _backendCtrl.text.trim().isEmpty ? 'https://ever.phywn.top' : _backendCtrl.text.trim();
    final backup = BackupService(ApiClient(backendUrl: backend));
    final ok = await backup.restore();
    if (!mounted) return;
    setState(() => _restoring = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导入成功，重新加载设置...')),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导入失败，云端没有备份或网络异常')),
      );
    }
  }

  String _formatBackupTime(String? iso) {
    if (iso == null || iso.isEmpty) return '尚未备份';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final p = (int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${p(dt.month)}-${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}';
  }

  int _parseLocalBuild(String version) {
    // version 形如 '1.0.0+1'，取 + 后面的 build 号
    final idx = version.indexOf('+');
    if (idx >= 0) {
      return int.tryParse(version.substring(idx + 1)) ?? 1;
    }
    return 1;
  }

  void _showUpdateDialog() {
    final latest = _latestVersion;
    final ver = latest['version']?.toString() ?? '未知';
    final notes = latest['notes']?.toString() ?? '';
    final url = latest['url']?.toString() ?? 'https://ever.phywn.top/latest.apk';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现新版本', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本：$_currentVersion', style: const TextStyle(fontSize: 14)),
            Text('最新版本：$ver', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF8E7CC3))),
            if (notes.isNotEmpty) ...[const SizedBox(height: 8), Text('更新内容：', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)), Text(notes, style: const TextStyle(fontSize: 13, height: 1.5))],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后再说'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _promptDownload(url);
            },
            child: const Text('去更新'),
          ),
        ],
      ),
    );
  }

  void _promptDownload(String url) {
    // 用系统分享/复制链接方式引导下载到浏览器安装
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('下载链接已���制：$url\n请粘贴到浏览器打开下载安装'), duration: const Duration(seconds: 5)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 10),
      child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF8E7CC3))),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SettingTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF8E7CC3)),
        title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile({required this.icon, required this.title, required this.subtitle, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeTrackColor: const Color(0xFF8E7CC3),
        secondary: Icon(icon, color: const Color(0xFF8E7CC3)),
        title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  final VoidCallback onSave;
  final bool saving;
  const _SaveBar({required this.onSave, required this.saving});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: saving ? null : onSave,
        icon: saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save, size: 18),
        label: Text(saving ? '保存中...' : '保存设置'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF8E7CC3),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}