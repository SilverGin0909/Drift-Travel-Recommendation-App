import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SideMenu extends StatefulWidget {
  final String? currentSessionId;
  final Function(String) onSessionSelected;
  final VoidCallback onNewSessionCreated;
  final String userName;
  final String avatarUrl;
  final VoidCallback onChangeProfilePicture;

  const SideMenu({
    super.key,
    required this.currentSessionId,
    required this.onSessionSelected,
    required this.onNewSessionCreated,
    required this.userName,
    required this.avatarUrl,
    required this.onChangeProfilePicture,
  });

  @override
  State<SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<SideMenu> {
  List<Map<String, dynamic>> _allSessions = [];
  List<Map<String, dynamic>> _filteredSessions = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchSessions();
  }

  Future<void> _fetchSessions() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final data = await Supabase.instance.client
          .from('chat_sessions')
          .select('id, title, created_at')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _allSessions = List<Map<String, dynamic>>.from(data);
          _filteredSessions = _allSessions;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching sessions: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterSessions(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        _filteredSessions = _allSessions;
      } else {
        _filteredSessions = _allSessions
            .where(
              (session) => session['title'].toString().toLowerCase().contains(
                query.toLowerCase(),
              ),
            )
            .toList();
      }
    });
  }

  Future<void> _createNewSession() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final newSession = await Supabase.instance.client
          .from('chat_sessions')
          .insert({
            'user_id': user.id,
            'title': 'New Trip ${DateTime.now().day}/${DateTime.now().month}',
          })
          .select('id')
          .single();

      widget.onNewSessionCreated();
      widget.onSessionSelected(newSession['id']);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint("Error creating new session: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF09090F), // Velvet dark theme background
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        hintText: "Search trips...",
                        hintStyle: TextStyle(
                          color: Colors.white38,
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: Colors.white38,
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: _filterSessions,
                    ),
                  ),
                  const SizedBox(height: 24),
                  InkWell(
                    onTap: _createNewSession,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6155F5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.add, color: Colors.white, size: 20),
                          SizedBox(width: 12),
                          Text(
                            "Plan a New Trip",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Sub-Label
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                "Recent Itineraries",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white38,
                  letterSpacing: 0.5,
                ),
              ),
            ),

            // Middle: Scrollable History Selection Stream
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredSessions.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      child: Text(
                        "No itineraries found.",
                        style: TextStyle(color: Colors.white24),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _filteredSessions.length,
                      itemBuilder: (context, index) {
                        final session = _filteredSessions[index];
                        final bool isActive =
                            session['id'] == widget.currentSessionId;
                        return _buildHistoryItem(
                          session['id'],
                          session['title'] ?? 'Untitled Trip',
                          isActive: isActive,
                        );
                      },
                    ),
            ),

            const Divider(height: 1, color: Colors.white10),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // 1. Profile Picture Avatar Module (Clickable for Photo Uploads)
                  GestureDetector(
                    onTap: widget.onChangeProfilePicture,
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.white10,
                      backgroundImage: NetworkImage(widget.avatarUrl),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 2. Center User Name Metadata Context Block
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Hi, ${widget.userName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Text(
                          'Welcome Back',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),

                  IconButton(
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Colors.white54,
                      size: 22,
                    ),
                    onPressed: () {
                      // Navigate or trigger settings page action logic here
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(
    String sessionId,
    String title, {
    required bool isActive,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(
          Icons.chat_bubble_outline,
          size: 18,
          color: isActive ? const Color(0xFF818CF8) : Colors.white54,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? Colors.white : Colors.white70,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () {
          widget.onSessionSelected(sessionId);
          Navigator.pop(context);
        },
      ),
    );
  }
}
