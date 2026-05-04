import 'package:flutter/material.dart';
import '../models/admin_models.dart';
import '../services/admin_api_service.dart';
import '../services/event_log.dart';
import 'admin_qr_screen.dart';
import 'share_credentials_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _api = AdminApiService();
  final _log = EventLog();

  // Users tab state
  List<AdminUser> _users = [];
  bool _usersLoading = false;
  String? _usersError;

  // Clients tab state
  List<ConnectedClient> _clients = [];
  bool _clientsLoading = false;
  String? _clientsError;

  // Server tab state
  AdminStatus? _status;
  bool _statusLoading = false;
  String? _statusError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(_onTabChanged);
    _loadUsers();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    switch (_tabs.index) {
      case 0:
        if (_users.isEmpty && !_usersLoading) _loadUsers();
      case 1:
        _loadClients();
      case 2:
        _loadStatus();
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  // -- Users --

  Future<void> _loadUsers() async {
    setState(() {
      _usersLoading = true;
      _usersError = null;
    });
    try {
      final users = await _api.listUsers();
      if (mounted) setState(() => _users = users);
    } on AdminApiException catch (e) {
      if (mounted) setState(() => _usersError = e.message);
    } catch (e) {
      if (mounted) setState(() => _usersError = e.toString());
    } finally {
      if (mounted) setState(() => _usersLoading = false);
    }
  }

  Future<void> _showAddUserDialog() async {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add User'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: usernameCtrl,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: AdminConstraints.validateUsername,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passwordCtrl,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: AdminConstraints.validatePassword,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _api.createUser(usernameCtrl.text, passwordCtrl.text);
      _loadUsers();
      if (!mounted) return;
      _log.debug('User created: ${usernameCtrl.text}, offering share');
      final share = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('User Created'),
          content: Text('Share credentials for "${usernameCtrl.text}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Later'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.share),
              label: const Text('Share Now'),
            ),
          ],
        ),
      );
      if (share == true && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ShareCredentialsScreen(
              username: usernameCtrl.text,
              prefilledPassword: passwordCtrl.text,
            ),
          ),
        );
      }
    } on AdminApiException catch (e) {
      _showError('Create failed: ${e.message}');
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _showChangePasswordDialog(String username) async {
    final passwordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change password for "$username"'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: passwordCtrl,
            decoration: const InputDecoration(labelText: 'New Password'),
            obscureText: true,
            validator: AdminConstraints.validatePassword,
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _api.updatePassword(username, passwordCtrl.text);
      _showSnack('Password updated');
    } on AdminApiException catch (e) {
      _showError('Update failed: ${e.message}');
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _confirmDeleteUser(String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Delete user "$username"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _api.deleteUser(username);
      _loadUsers();
    } on AdminApiException catch (e) {
      _showError('Delete failed: ${e.message}');
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _toggleDisabled(AdminUser user) async {
    try {
      if (user.disabled) {
        await _api.enable(user.username);
      } else {
        await _api.disable(user.username);
      }
      _loadUsers();
    } on AdminApiException catch (e) {
      _showError('Failed: ${e.message}');
    } catch (e) {
      _showError(e.toString());
    }
  }

  // -- Clients --

  Future<void> _loadClients() async {
    setState(() {
      _clientsLoading = true;
      _clientsError = null;
    });
    try {
      final clients = await _api.listClients();
      if (mounted) setState(() => _clients = clients);
    } on AdminApiException catch (e) {
      if (mounted) setState(() => _clientsError = e.message);
    } catch (e) {
      if (mounted) setState(() => _clientsError = e.toString());
    } finally {
      if (mounted) setState(() => _clientsLoading = false);
    }
  }

  Future<void> _confirmDisconnect(ConnectedClient client) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Client'),
        content: Text(
          'Disconnect "${client.username}" (${client.assignedIp})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _api.disconnectClient(client.id);
      _loadClients();
    } on AdminApiException catch (e) {
      _showError('Failed: ${e.message}');
    } catch (e) {
      _showError(e.toString());
    }
  }

  // -- Server status --

  Future<void> _loadStatus() async {
    setState(() {
      _statusLoading = true;
      _statusError = null;
    });
    try {
      final status = await _api.getStatus();
      if (mounted) setState(() => _status = status);
    } on AdminApiException catch (e) {
      if (mounted) setState(() => _statusError = e.message);
    } catch (e) {
      if (mounted) setState(() => _statusError = e.toString());
    } finally {
      if (mounted) setState(() => _statusLoading = false);
    }
  }

  // -- Helpers --

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // -- Build --

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.people), text: 'Users'),
            Tab(icon: Icon(Icons.devices), text: 'Clients'),
            Tab(icon: Icon(Icons.dns), text: 'Server'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildUsersTab(),
          _buildClientsTab(),
          _buildServerTab(),
        ],
      ),
    );
  }

  Widget _buildUsersTab() {
    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: _usersLoading
          ? const Center(child: CircularProgressIndicator())
          : _usersError != null
              ? _errorView(_usersError!, _loadUsers)
              : _users.isEmpty
                  ? _emptyView('No users found')
                  : Stack(
                      children: [
                        ListView.separated(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: _users.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) => _userTile(_users[i]),
                        ),
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: FloatingActionButton.extended(
                            heroTag: 'addUser',
                            onPressed: _showAddUserDialog,
                            icon: const Icon(Icons.person_add),
                            label: const Text('Add User'),
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _userTile(AdminUser user) {
    return ListTile(
      leading: Icon(
        user.disabled ? Icons.person_off : Icons.person,
        color: user.disabled ? Colors.grey : null,
      ),
      title: Text(
        user.username,
        style: user.disabled
            ? const TextStyle(color: Colors.grey)
            : null,
      ),
      subtitle: Text(user.createdAt.isNotEmpty ? 'Created: ${user.createdAt}' : ''),
      trailing: PopupMenuButton<String>(
        onSelected: (action) {
          switch (action) {
            case 'share':
              _log.debug('Share credentials tapped for user: ${user.username}');
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ShareCredentialsScreen(username: user.username),
                ),
              );
            case 'password':
              _showChangePasswordDialog(user.username);
            case 'toggle':
              _toggleDisabled(user);
            case 'delete':
              _confirmDeleteUser(user.username);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'share',
            child: ListTile(
              leading: Icon(Icons.share),
              title: Text('Share Credentials'),
              dense: true,
            ),
          ),
          const PopupMenuItem(
            value: 'password',
            child: ListTile(
              leading: Icon(Icons.key),
              title: Text('Change Password'),
              dense: true,
            ),
          ),
          PopupMenuItem(
            value: 'toggle',
            child: ListTile(
              leading: Icon(user.disabled ? Icons.person : Icons.person_off),
              title: Text(user.disabled ? 'Enable' : 'Disable'),
              dense: true,
            ),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete, color: Colors.red),
              title: Text('Delete', style: TextStyle(color: Colors.red)),
              dense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientsTab() {
    return RefreshIndicator(
      onRefresh: _loadClients,
      child: _clientsLoading
          ? const Center(child: CircularProgressIndicator())
          : _clientsError != null
              ? _errorView(_clientsError!, _loadClients)
              : _clients.isEmpty
                  ? _emptyView('No connected clients')
                  : ListView.separated(
                      itemCount: _clients.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _clientTile(_clients[i]),
                    ),
    );
  }

  Widget _clientTile(ConnectedClient client) {
    final kb = (client.bytesIn + client.bytesOut) ~/ 1024;
    return ListTile(
      leading: const Icon(Icons.devices),
      title: Text(client.username),
      subtitle: Text(
        '${client.assignedIp} · ${client.remoteAddr}\n${kb}KB transferred',
      ),
      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Icons.logout, color: Colors.red),
        tooltip: 'Disconnect',
        onPressed: () => _confirmDisconnect(client),
      ),
    );
  }

  Widget _buildServerTab() {
    return RefreshIndicator(
      onRefresh: _loadStatus,
      child: _statusLoading
          ? const Center(child: CircularProgressIndicator())
          : _statusError != null
              ? _errorView(_statusError!, _loadStatus)
              : _status == null
                  ? _emptyView('No data')
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _statusCard(),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AdminQrScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.qr_code),
                          label: const Text('Generate Client QR'),
                        ),
                      ],
                    ),
    );
  }

  Widget _statusCard() {
    final s = _status!;
    final uptime = Duration(seconds: s.uptimeSecs);
    final uptimeStr =
        '${uptime.inHours}h ${uptime.inMinutes.remainder(60)}m ${uptime.inSeconds.remainder(60)}s';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statusRow(Icons.circle, 'Status', s.status.toUpperCase()),
            _statusRow(Icons.info_outline, 'Version', s.version),
            _statusRow(Icons.timer, 'Uptime', uptimeStr),
            _statusRow(Icons.people, 'Clients', '${s.clientCount}'),
            _statusRow(Icons.lan, 'Listen', s.listen),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: Colors.grey)),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _errorView(String error, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _emptyView(String message) {
    return Center(
      child: Text(message, style: const TextStyle(color: Colors.grey)),
    );
  }
}
