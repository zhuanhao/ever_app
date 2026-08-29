import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/config_service.dart';

/// MCP 配置页 - 精细版
/// 展示后端所有 MCP server(状态 + 原始工具清单 + 独立开关)
/// 工具描述由 MCP server 自带 list_tools description 透传,前端直接展示
class McpSettingsScreen extends StatefulWidget {
  const McpSettingsScreen({super.key});

  @override
  State<McpSettingsScreen> createState() => _McpSettingsScreenState();
}

class _McpSettingsScreenState extends State<McpSettingsScreen> {
  ApiClient _api = ApiClient();

  List<Map<String, dynamic>> _servers = [];
  bool _loading = true;
  String? _error;
  bool _changed = false; // 是否发生过开关改动(供返回时刷新)

  @override
  void initState() {
    super.initState();
    _initApi();
  }

  Future<void> _initApi() async {
    final backendUrl = await ConfigService().getBackendUrl();
    if (!mounted) return;
    setState(() => _api = ApiClient(backendUrl: backendUrl));
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final servers = await _api.fetchMcp();
    if (!mounted) return;
    setState(() {
      _servers = servers;
      _loading = false;
      if (servers.isEmpty) _error = '无 MCP 数据，请确认后端地址及后台服务';
    });
  }

  Future<void> _toggleServer(Map<String, dynamic> server, bool enabled) async {
    final name = server['name'] as String? ?? '';
    final res = await _api.toggleMcp({'action': 'server', 'name': name, 'enabled': enabled});
    if (!mounted) return;
    if (res['ok'] == true) {
      setState(() => _changed = true);
      _snack('已${enabled ? "开启" : "关闭"} $name');
      _load();
    } else {
      _snack(res['error']?.toString() ?? '操作失败');
    }
  }

  Future<void> _toggleTool(Map<String, dynamic> server, String tool, bool enabled) async {
    final name = server['name'] as String? ?? '';
    final res = await _api.toggleMcp({'action': 'tool', 'name': name, 'tool': tool, 'enabled': enabled});
    if (!mounted) return;
    if (res['ok'] == true) {
      setState(() => _changed = true);
      _snack('已${enabled ? "开启" : "关闭"} $name.$tool');
      _load();
    } else {
      _snack(res['error']?.toString() ?? '操作失败');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
  }

  Color _stateColor(String s) {
    switch (s) {
      case 'ok':
        return const Color(0xFF4CAF50);
      case 'error':
        return const Color(0xFFE53935);
      case 'disabled':
        return const Color(0xFF9E9E9E);
      default:
        return const Color(0xFFFF9800);
    }
  }

  String _stateText(String s) {
    switch (s) {
      case 'ok':
        return '已连接';
      case 'error':
        return '连接失败';
      case 'disabled':
        return '已关闭';
      default:
        return '未连接';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP 配置'),
        backgroundColor: const Color(0xFF8E7CC3),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _servers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error ?? '没有可用的 MCP server', style: const TextStyle(color: Colors.black54)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _servers.length,
                    itemBuilder: (ctx, i) => _serverCard(_servers[i]),
                  ),
                ),
    );
  }

  Widget _serverCard(Map<String, dynamic> server) {
    final name = server['name'] as String? ?? '';
    final enabled = server['enabled'] == true;
    final state = server['connect_state'] as String? ?? 'off';
    final tools = (server['tools'] as List? ?? []).cast<Map<String, dynamic>>();
    final isProtected = name == 'ob'; // 记忆库受保护不可关

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        key: PageStorageKey(name),
        title: Row(
          children: [
            Expanded(
              child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _stateColor(state).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _stateText(state),
                style: TextStyle(color: _stateColor(state), fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${tools.length} 个工具  ·  ${server['base_url'] ?? ''}',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isProtected
            ? const Tooltip(
                message: '记忆库为 Ever 的大脑，不可关闭',
                child: Icon(Icons.lock, color: Colors.black38),
              )
            : Switch(
                value: enabled,
                onChanged: (v) => _toggleServer(server, v),
              ),
        children:
            enabled
                ? tools.map((t) => _toolTile(server, t)).toList()
                : [
                    const ListTile(
                      dense: true,
                      title: Text('server 已关闭，工具不可用', style: TextStyle(color: Colors.black45, fontSize: 13)),
                    ),
                  ],
      ),
    );
  }

  Widget _toolTile(Map<String, dynamic> server, Map<String, dynamic> tool) {
    final name = server['name'] as String? ?? '';
    final toolName = tool['name'] as String? ?? '';
    final desc = tool['description'] as String? ?? '';
    final toolStates = (server['tool_states'] as Map<String, dynamic>?) ?? {};
    final on = toolStates[toolName] != false; // 默认开启(未记录为关闭)

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(toolName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: desc.isEmpty
          ? const Text('(无描述)', style: TextStyle(color: Colors.black38, fontSize: 12))
          : Text(
              desc,
              style: const TextStyle(color: Colors.black54, fontSize: 12, height: 1.4),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Switch(
        value: on,
        onChanged: (v) => _toggleTool(server, toolName, v),
      ),
    );
  }
}