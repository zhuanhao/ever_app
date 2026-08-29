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

  bool _thinkingEnabled = false;
  bool _thinkingShow = false;
  bool _pushEnabled = false;

  bool _saving = false;

  // 中转站管理状态
  List<Map<String, dynamic>> _providers = [];
  String? _activeProvider;
  bool _loadingProviders = false;

  // 版本更新相关
  String _currentVersion = '1.0.0+5'; // 本地版本（与 pubspec 同步手动维护）
  Map<String, dynamic> _latestVersion = {}; // 远端版本信息
  bool _checkingVersion = false;
  bool _versionChecked = false;
  bool _hasUpdate = false;

  // 备份/恢复相关
  bool _backingUp = false;
  bool _restoring = false;
  bool _backingUpLocal = false;
  bool _restoringLocal = false;
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
      _thinkingEnabled = cfg['thinkingEnabled'] as bool;
      _thinkingShow = cfg['thinkingShow'] as bool;
      _pushEnabled = cfg['pushEnabled'] as bool;
    });
    // 从后端拉取中转站列表
    await _loadProviders();
    // 加载最近备份时间
    final backend = cfg['backendUrl'] as String? ?? 'https://ever.phywn.top';
    final backup = BackupService(ApiClient(backendUrl: backend));
    final t = await backup.lastBackupTime();
    if (!mounted) return;
    setState(() => _lastBackupTime = t);
  }

  // 从后端 /api/config 拉取中转站列表和当前激活站
  Future<void> _loadProviders() async {
    final backend = _backendCtrl.text.trim().isEmpty
        ? 'https://ever.phywn.top'
        : _backendCtrl.text.trim();
    final api = ApiClient(backendUrl: backend);
    final cfg = await api.fetchConfig();
    if (!mounted) return;
    setState(() {
      _providers = (cfg['providers'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _activeProvider = cfg['active_provider'] as String?;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    // 后端地址、偏好开关保存到本地
    await _config.set('backendUrl', _backendCtrl.text.trim());
    await _config.set('thinkingEnabled', _thinkingEnabled);
    await _config.set('thinkingShow', _thinkingShow);
    await _config.set('pushEnabled', _pushEnabled);
    // 中转站管理已即时同步后端，无需在此处理
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存设置')),
      );
    }
  }

  // ─── 中转站管理 ───────────────────────────

  // 渲染中转站列表卡片
  Widget _providerList() {
    if (_loadingProviders) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_providers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('暂无中转站，点击下方按钮添加', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
      );
    }
    return Column(
      children: _providers.map((p) {
        final name = p['name']?.toString() ?? '';
        final base = p['base_url']?.toString() ?? '';
        final model = p['model']?.toString() ?? '';
        final isActive = name == _activeProvider;
        return Card(
          color: isActive ? const Color(0xFFF0EBFF) : Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: isActive ? const Color(0xFF8E7CC3) : Colors.transparent, width: 1.5),
          ),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(isActive ? Icons.check_circle : Icons.dns, color: isActive ? const Color(0xFF8E7CC3) : Colors.grey),
            title: Row(
              children: [
                Expanded(child: Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF8E7CC3), borderRadius: BorderRadius.circular(10)),
                    child: const Text('当前', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            subtitle: Text('$base\n$model', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.grey),
              onSelected: (v) {
                if (v == 'active') _setActiveProvider(name);
                if (v == 'edit') _editProvider(p);
                if (v == 'remove') _removeProvider(name);
              },
              itemBuilder: (ctx) => [
                if (!isActive) const PopupMenuItem(value: 'active', child: Text('设为当前')),
                const PopupMenuItem(value: 'edit', child: Text('编辑')),
                const PopupMenuItem(value: 'remove', child: Text('删除')),
              ],
            ),
            onTap: () {
              if (!isActive) _setActiveProvider(name);
            },
          ),
        );
      }).toList(),
    );
  }

  // 新增中转站
  Future<void> _addProvider() async {
    await _showProviderDialog(null);
  }

  // 编辑中转站
  Future<void> _editProvider(Map<String, dynamic> provider) async {
    await _showProviderDialog(provider);
  }

  // 弹出新增/编辑中转站表单
  Future<void> _showProviderDialog(Map<String, dynamic>? existing) async {
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final urlCtrl = TextEditingController(text: existing?['base_url']?.toString() ?? '');
    final keyCtrl = TextEditingController(text: existing?['api_key']?.toString() ?? '');
    final modelCtrl = TextEditingController(text: existing?['model']?.toString() ?? '');
    // 拉取到的模型列表（非空时 model 显示为下拉选择）
    List<String> fetchedModels = [];
    bool fetching = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null ? '新增中转站' : '编辑中转站', style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(nameCtrl, '名称', hint: '如 jixiang'),
                _dialogField(urlCtrl, 'Base URL', hint: 'https://中转站/v1'),
                _dialogField(keyCtrl, 'API Key', hint: 'sk-...', obscure: true),
                // 模型输入 + 拉取按钮
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: modelCtrl,
                              enabled: false,
                              decoration: InputDecoration(
                                labelText: '模型',
                                hintText: fetchedModels.isEmpty ? 'claude-opus-4-6' : '从下方拉取下拉选择',
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _dialogBtn(
                            icon: fetching ? Icons.hourglass_top : Icons.cloud_download,
                            label: '拉取',
                            onTap: () async {
                              if (urlCtrl.text.trim().isEmpty || keyCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('请先填写 Base URL 和 API Key')),
                                );
                                return;
                              }
                              setDialogState(() => fetching = true);
                              final api = ApiClient();
                              final models = await api.fetchProviderModels(urlCtrl.text.trim(), keyCtrl.text.trim());
                              setDialogState(() {
                                fetching = false;
                                fetchedModels = models;
                                if (models.isNotEmpty) {
                                  modelCtrl.text = models.first;
                                }
                              });
                              if (models.isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('拉取失败，请检查地址/Key 或该站不支持 /models')),
                                );
                              } else {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text('已拉取 ${models.length} 个模型，可在下拉中选择')),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      if (fetchedModels.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: fetchedModels
                                .map((m) => ActionChip(
                                      label: Text(m, style: const TextStyle(fontSize: 12)),
                                      backgroundColor: m == modelCtrl.text ? const Color(0xFF8E7CC3).withOpacity(0.2) : null,
                                      onPressed: () => setDialogState(() => modelCtrl.text = m),
                                    ))
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8E7CC3)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) {
      nameCtrl.dispose(); urlCtrl.dispose(); keyCtrl.dispose(); modelCtrl.dispose();
      return;
    }

    final name = nameCtrl.text.trim();
    final url = urlCtrl.text.trim();
    final key = keyCtrl.text.trim();
    final model = modelCtrl.text.trim();
    nameCtrl.dispose(); urlCtrl.dispose(); keyCtrl.dispose(); modelCtrl.dispose();

    if (name.isEmpty || url.isEmpty || key.isEmpty || model.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称、地址、Key、模型均不能为空')),
      );
      return;
    }

    final backend = _backendCtrl.text.trim().isEmpty ? 'https://ever.phywn.top' : _backendCtrl.text.trim();
    final api = ApiClient(backendUrl: backend);
    final provider = {'name': name, 'base_url': url, 'api_key': key, 'model': model};
    final resp = await api.saveConfig({'action': existing == null ? 'upsert' : 'upsert', 'provider': provider});
    if (!mounted) return;
    if (resp.containsKey('ok') && resp['ok'] == true) {
      await _loadProviders();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(existing == null ? '已新增中转站 $name' : '已更新中转站 $name')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resp['error']?.toString() ?? '保存失败，请检查后端地址')),
      );
    }
  }

  // 设为当前中转站
  Future<void> _setActiveProvider(String name) async {
    final backend = _backendCtrl.text.trim().isEmpty ? 'https://ever.phywn.top' : _backendCtrl.text.trim();
    final api = ApiClient(backendUrl: backend);
    final resp = await api.saveConfig({'action': 'set_active', 'name': name});
    if (!mounted) return;
    if (resp.containsKey('ok') && resp['ok'] == true) {
      await _loadProviders();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换到 $name')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resp['error']?.toString() ?? '切换失败')),
      );
    }
  }

  // 删除中转站
  Future<void> _removeProvider(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除中转站', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text('确定删除 $name 吗？\n若为当前中转站，将自动切换到剩余第一个。', style: const TextStyle(fontSize: 14, height: 1.6)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD05A5A)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final backend = _backendCtrl.text.trim().isEmpty ? 'https://ever.phywn.top' : _backendCtrl.text.trim();
    final api = ApiClient(backendUrl: backend);
    final resp = await api.saveConfig({'action': 'remove', 'name': name});
    if (!mounted) return;
    if (resp.containsKey('ok') && resp['ok'] == true) {
      await _loadProviders();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resp['error']?.toString() ?? '删除失败')),
      );
    }
  }

  // 编辑表单中的输入框
  Widget _dialogField(TextEditingController ctrl, String label, {String? hint, bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  // 对话框内的小按钮（如拉取图标按钮）
  Widget _dialogBtn({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF8E7CC3).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF8E7CC3), size: 20),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Color(0xFF8E7CC3), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _backendCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设���')),
      backgroundColor: const Color(0xFFFAF8F5),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle('连接设置'),
          _textField(_backendCtrl, icon: Icons.dns, label: '后端 API 地址', hint: 'http://你的VPS:8899'),
          const SizedBox(height: 8),
          _SaveBar(onSave: _save, saving: _saving),

          const SizedBox(height: 16),
          _SectionTitle('中转站管理'),
          _providerList(),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addProvider,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新增中转站'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF8E7CC3),
                side: const BorderSide(color: Color(0xFF8E7CC3)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

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
          _SettingTile(
            icon: Icons.save_alt,
            title: '本地备份',
            subtitle: _backingUpLocal
                ? '正在导出...'
                : '导出为本地 JSON 文件，可自行保存/传回',
            onTap: _backupToLocal,
          ),
          _SettingTile(
            icon: Icons.file_open,
            title: '从本地导入',
            subtitle: _restoringLocal
                ? '正在导入...'
                : '选择本地备��� JSON 文件并覆盖本地数据',
            onTap: _restoreFromLocal,
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

  Future<void> _backupToLocal() async {
    if (_backingUpLocal) return;
    setState(() => _backingUpLocal = true);
    final backend = _backendCtrl.text.trim().isEmpty ? 'https://ever.phywn.top' : _backendCtrl.text.trim();
    final backup = BackupService(ApiClient(backendUrl: backend));
    final path = await backup.backupToLocal();
    if (!mounted) return;
    setState(() => _backingUpLocal = false);
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('本地备份成功：$path')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地备份已取消或写入失败')),
      );
    }
  }

  Future<void> _restoreFromLocal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认从本地导入?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('将读取所选本地 JSON 备份文件并覆盖当前本地配置与数据。\n此操作不可撤销，是否继续?', style: TextStyle(fontSize: 14, height: 1.6)),
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
    if (_restoringLocal) return;
    setState(() => _restoringLocal = true);
    final backend = _backendCtrl.text.trim().isEmpty ? 'https://ever.phywn.top' : _backendCtrl.text.trim();
    final backup = BackupService(ApiClient(backendUrl: backend));
    final ok = await backup.restoreFromLocal();
    if (!mounted) return;
    setState(() => _restoringLocal = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地导入成功，重新加载设置...')),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地导入失败，文件无效或已取消')),
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
    // version 形如 '1.0.0+1'，�� + 后面的 build 号
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
    // 用系统分享/复制链接��式引导下载到浏览器安装
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