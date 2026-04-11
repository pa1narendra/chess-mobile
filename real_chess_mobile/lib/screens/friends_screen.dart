import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_service.dart';
import '../providers/auth_provider.dart';
import '../providers/game_provider.dart';
import '../main.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _friends = [];
  List<dynamic> _incoming = [];
  List<dynamic> _outgoing = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadFriends();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;

    setState(() { _isLoading = true; _error = null; });
    try {
      final result = await ApiService.getFriends(token);
      final data = result['data'] as Map<String, dynamic>;
      setState(() {
        _friends = data['friends'] ?? [];
        _incoming = data['incoming'] ?? [];
        _outgoing = data['outgoing'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _acceptRequest(String friendshipId) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;
    try {
      await ApiService.acceptFriendRequest(token, friendshipId);
      _loadFriends();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.roseError),
        );
      }
    }
  }

  Future<void> _removeFriend(String friendshipId) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;
    try {
      await ApiService.removeFriend(token, friendshipId);
      _loadFriends();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.roseError),
        );
      }
    }
  }

  void _openSearch() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _UserSearchSheet(),
    );
    _loadFriends();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Friends', style: TextStyle(color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.tealAccent),
            tooltip: 'Add friend',
            onPressed: _openSearch,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.tealAccent,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.tealAccent,
          tabs: [
            Tab(text: 'Friends (${_friends.length})'),
            Tab(text: 'Requests${_incoming.isEmpty ? "" : " (${_incoming.length})"}'),
            const Tab(text: 'Sent'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.tealAccent))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.roseError)))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildFriendsList(),
                    _buildIncomingList(),
                    _buildOutgoingList(),
                  ],
                ),
    );
  }

  Widget _buildFriendsList() {
    if (_friends.isEmpty) {
      return _emptyState(Icons.people_outline, 'No friends yet', 'Search for users to add them as friends');
    }
    return RefreshIndicator(
      color: AppColors.tealAccent,
      onRefresh: _loadFriends,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _friends.length,
        itemBuilder: (_, i) => _buildUserCard(_friends[i], showRemoveButton: true),
      ),
    );
  }

  Widget _buildIncomingList() {
    if (_incoming.isEmpty) {
      return _emptyState(Icons.inbox_outlined, 'No requests', 'Friend requests will appear here');
    }
    return RefreshIndicator(
      color: AppColors.tealAccent,
      onRefresh: _loadFriends,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _incoming.length,
        itemBuilder: (_, i) => _buildUserCard(_incoming[i], showAcceptButton: true),
      ),
    );
  }

  Widget _buildOutgoingList() {
    if (_outgoing.isEmpty) {
      return _emptyState(Icons.send_outlined, 'No pending requests', 'Your sent requests will appear here');
    }
    return RefreshIndicator(
      color: AppColors.tealAccent,
      onRefresh: _loadFriends,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _outgoing.length,
        itemBuilder: (_, i) => _buildUserCard(_outgoing[i], showPending: true),
      ),
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textMuted, size: 64),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user, {bool showRemoveButton = false, bool showAcceptButton = false, bool showPending = false}) {
    final name = user['displayName'] ?? user['username'] ?? 'Unknown';
    final username = user['username'] ?? '';
    final rating = user['rating'] ?? 1200;
    final isOnline = user['isOnline'] == true;
    final friendshipId = user['friendshipId']?.toString() ?? user['_id']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.tealAccent.withValues(alpha: 0.15),
                child: Text(
                  (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                  style: const TextStyle(color: AppColors.tealAccent, fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              if (isOnline)
                Positioned(
                  right: 0, bottom: 0,
                  child: Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.emeraldGreen,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surfaceDark, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, overflow: TextOverflow.ellipsis, maxLines: 1, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                Text('@$username  |  $rating', overflow: TextOverflow.ellipsis, maxLines: 1, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          if (showAcceptButton && friendshipId != null) ...[
            IconButton(
              icon: const Icon(Icons.check_rounded, color: AppColors.emeraldGreen),
              onPressed: () => _acceptRequest(friendshipId),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.roseError),
              onPressed: () => _removeFriend(friendshipId),
            ),
          ] else if (showRemoveButton) ...[
            IconButton(
              icon: const Icon(Icons.sports_esports_rounded, color: AppColors.tealAccent),
              tooltip: 'Challenge',
              onPressed: () => _showChallengeDialog(user),
            ),
          ] else if (showPending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Pending', style: TextStyle(color: AppColors.amberWarning, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  void _showChallengeDialog(Map<String, dynamic> user) {
    final timeControls = [
      {'minutes': 1, 'label': '1 min', 'subtitle': 'Bullet'},
      {'minutes': 3, 'label': '3 min', 'subtitle': 'Blitz'},
      {'minutes': 5, 'label': '5 min', 'subtitle': 'Blitz'},
      {'minutes': 10, 'label': '10 min', 'subtitle': 'Rapid'},
      {'minutes': 15, 'label': '15 min', 'subtitle': 'Rapid'},
      {'minutes': 30, 'label': '30 min', 'subtitle': 'Classical'},
    ];

    final name = user['displayName'] ?? user['username'] ?? 'Player';
    final userId = user['_id'].toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Row(
          children: [
            const Icon(Icons.sports_esports_rounded, color: AppColors.tealAccent),
            const SizedBox(width: 8),
            Flexible(child: Text('Challenge $name', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16), overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: timeControls.map((tc) {
              return ListTile(
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.tealAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('${tc['minutes']}', style: const TextStyle(color: AppColors.tealAccent, fontWeight: FontWeight.bold)),
                  ),
                ),
                title: Text(tc['label'] as String, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                subtitle: Text(tc['subtitle'] as String, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  final game = Provider.of<GameProvider>(context, listen: false);
                  game.sendChallenge(userId, tc['minutes'] as int);
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _confirmRemove(Map<String, dynamic> user) {
    // Note: for accepted friendships, we need the friendship _id. For now, we'll
    // pass the user _id and expect the backend to use it — but actually we should
    // fetch the friendship ID. For simplicity, this will show the dialog.
    // TODO: Backend returns friend user data but not friendship ID for accepted.
    // Implement a separate endpoint or include friendshipId in the response.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Remove not yet supported for accepted friends')),
    );
  }
}

// --- Search bottom sheet ---

class _UserSearchSheet extends StatefulWidget {
  const _UserSearchSheet();

  @override
  State<_UserSearchSheet> createState() => _UserSearchSheetState();
}

class _UserSearchSheetState extends State<_UserSearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<dynamic> _results = [];
  bool _isLoading = false;
  Set<String> _pendingIds = {};

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query.trim()));
  }

  Future<void> _search(String query) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;
    setState(() => _isLoading = true);
    try {
      final result = await ApiService.searchUsers(token, query);
      setState(() {
        _results = result['data'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendRequest(String userId) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;
    try {
      await ApiService.sendFriendRequest(token, userId);
      setState(() => _pendingIds.add(userId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request sent'), backgroundColor: AppColors.emeraldGreen),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.roseError),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.borderColor, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search by username...',
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                      filled: true,
                      fillColor: AppColors.deepDark,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.tealAccent))
                  : _results.isEmpty
                      ? const Center(child: Text('No results', style: TextStyle(color: AppColors.textMuted)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _results.length,
                          itemBuilder: (_, i) {
                            final user = _results[i] as Map<String, dynamic>;
                            final name = user['displayName'] ?? user['username'] ?? 'Unknown';
                            final username = user['username'] ?? '';
                            final rating = user['rating'] ?? 1200;
                            final userId = user['_id'].toString();
                            final isSent = _pendingIds.contains(userId);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.deepDark,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: AppColors.tealAccent.withValues(alpha: 0.15),
                                    child: Text(
                                      (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                                      style: const TextStyle(color: AppColors.tealAccent, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name, overflow: TextOverflow.ellipsis, maxLines: 1, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                                        Text('@$username  |  $rating', overflow: TextOverflow.ellipsis, maxLines: 1, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  isSent
                                      ? const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 12),
                                          child: Text('Sent', style: TextStyle(color: AppColors.emeraldGreen, fontSize: 12)),
                                        )
                                      : IconButton(
                                          icon: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.tealAccent),
                                          onPressed: () => _sendRequest(userId),
                                        ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
