import 'package:flutter/material.dart';
import 'package:frontend/services/location_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';

import 'package:image_picker/image_picker.dart';

import 'package:frontend/widgets/background_glow.dart';
import 'package:frontend/widgets/chat_input_area.dart';
import 'package:frontend/widgets/chat_header.dart';
import 'package:frontend/widgets/side_menu.dart';
import 'package:frontend/widgets/welcome_screen.dart';
import 'package:frontend/widgets/thinking_indicator.dart';

class Chatbot extends StatefulWidget {
  const Chatbot({super.key});

  @override
  State<Chatbot> createState() => Chatbot_State();
}

class Chatbot_State extends State<Chatbot> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, String>> _messages = [];
  bool _isTyping = false;
  bool _isSending = false;

  String _userName = "Loading...";
  String _avatarUrl = "https://i.pravatar.cc/150?img=5";

  String? _currentSessionId;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // 1. FETCH PROFILE DETAILS (Fixes the "Loading..." issue)
      final profileData = await Supabase.instance.client
          .from('user_preferences')
          .select('username, avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (profileData != null && mounted) {
        setState(() {
          _userName = profileData['username'] ?? "User";
          _avatarUrl =
              profileData['avatar_url'] ?? "https://i.pravatar.cc/150?img=5";
        });
      }

      final existingSessions = await Supabase.instance.client
          .from('chat_sessions')
          .select('id')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existingSessions != null && mounted) {
        setState(() {
          _currentSessionId = existingSessions['id'];
        });
      } else {
        if (mounted) {
          setState(() {
            _currentSessionId = null;
          });
        }
      }
    } catch (e) {
      debugPrint("Error initializing user profile data and session: $e");
    }
  }

  // 4. Handle Image Picking and Uploading
  Future<void> _changeProfilePicture() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Pick image from gallery
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800, // Compress slightly
        imageQuality: 80,
      );

      if (image == null) return; // User canceled

      // Read bytes for upload
      final bytes = await image.readAsBytes();
      final fileExt = image.name.split('.').last;
      final fileName =
          '${user.id}-${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      // Upload to Supabase Storage (bucket name: 'avatars')
      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(fileName, bytes);

      // Get the public URL of the uploaded image
      final String publicUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(fileName);

      // Update the profiles table with the new URL
      await Supabase.instance.client
          .from('user_preferences')
          .update({'avatar_url': publicUrl})
          .eq('id', user.id);

      // Update UI
      if (mounted) {
        setState(() {
          _avatarUrl = publicUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile picture updated!")),
        );
      }
    } catch (e) {
      debugPrint("Error uploading image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to update picture.")),
        );
      }
    }
  }

  Future<void> _handleSend(String text) async {
    if (text.trim().isEmpty || _isSending) return;

    final userID = Supabase.instance.client.auth.currentUser!.id;
    final String backendUrl = "http://10.0.2.2:8000/api/chat";

    setState(() {
      _messages.add({"role": "user", "text": text});
      _isTyping = true;
      _isSending = true;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      Position? position = await LocationService.determinePosition();

      final request = http.Request('POST', Uri.parse(backendUrl));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        "user_id": userID,
        "session_id": _currentSessionId ?? "",
        "message": text,
        "user_lat": position?.latitude,
        "user_lng": position?.longitude,
      });

      final response = await http.Client().send(request);

      if (response.statusCode == 200) {
        setState(() {
          _isTyping = false;
          _messages.add({"role": "bot", "text": ""});
        });

        int botIndex = _messages.length - 1;

        await for (var line
            in response.stream
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          if (line.startsWith('data: ')) {
            final data = jsonDecode(line.substring(6));

            if (data.containsKey('session_id')) {
              final String receivedId = data['session_id'];
              if (_currentSessionId != receivedId) {
                setState(() {
                  _currentSessionId = receivedId;
                });
              }
            }

            if (data.containsKey('text')) {
              setState(() {
                _messages[botIndex]["text"] =
                    _messages[botIndex]["text"]! + data['text'];
              });
            }
          }
        }
      } else {
        throw Exception("Server error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Stream Error: $e");
      setState(() {
        _messages.add({
          "role": "bot",
          "text": "Sorry, I lost my connection to KL!",
        });
        _isTyping = false;
      });
    } finally {
      setState(() {
        _isSending = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadChatMessages(String sessionId) async {
    try {
      final messagesData = await Supabase.instance.client
          .from('chat_messages')
          .select('role, content')
          .eq('session_id', sessionId)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _messages.clear();
          for (var entry in messagesData) {
            _messages.add({"role": entry['role'], "text": entry['content']});
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint("Error loading historical messages: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      drawer: SideMenu(
        currentSessionId: _currentSessionId,
        userName: _userName,
        avatarUrl: _avatarUrl,
        onChangeProfilePicture: _changeProfilePicture,
        onNewSessionCreated: () {
          setState(() {
            _currentSessionId = null;
            _messages.clear();
          });
        },
        onSessionSelected: (selectedSessionId) {
          setState(() {
            _currentSessionId = selectedSessionId;
            _messages.clear();
          });
          _loadChatMessages(selectedSessionId);
        },
      ),
      body: Stack(
        children: [
          // 1. BACKGROUND GLOW EFFECTS
          const BackgroundGlow(),

          // 2. MAIN CONTENT
          Column(
            children: [
              SafeArea(
                bottom: false,
                child: ChatHeader(
                  userName: _userName,
                  avatarUrl: _avatarUrl,
                  onChangeProfilePicture: _changeProfilePicture,
                ),
              ),
              Expanded(
                child: _messages.isEmpty
                    ? const WelcomeScreen()
                    : _buildChatList(),
              ),
            ],
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ChatInputArea(
              inputController: _inputController,
              isSending: _isSending,
              onSend: (text) {
                _handleSend(text);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    return ListView.builder(
      controller: _scrollController,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 180),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return const ThinkingIndicator();
        }

        final msg = _messages[index];
        final isUser = msg["role"] == "user";

        // 1. USER STYLE: THE BUBBLE
        if (isUser) {
          return Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF6155F5), // Your theme blue
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                msg["text"] ?? "",
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          );
        }

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectionArea(
                child: MarkdownBody(
                  data: msg["text"] ?? "",
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Colors.black87,
                      fontWeight: FontWeight.w400,
                    ),
                    strong: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    h3: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.5,
                    ),
                    h3Padding: const EdgeInsets.only(top: 30),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}
