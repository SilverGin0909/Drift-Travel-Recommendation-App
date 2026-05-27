import 'package:flutter/material.dart';
import 'package:frontend/services/location_service.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

import 'package:image_picker/image_picker.dart';

import 'package:frontend/widgets/background_glow.dart';
import 'package:frontend/widgets/chat_input_area.dart';
import 'package:frontend/widgets/chat_header.dart';
import 'package:frontend/widgets/side_menu.dart';
import 'package:frontend/widgets/welcome_screen.dart';
import 'package:frontend/widgets/thinking_indicator.dart';

import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/user_service.dart';
import 'package:frontend/widgets/chat_bubbles.dart';

class Chatbot extends StatefulWidget {
  const Chatbot({super.key});

  @override
  State<Chatbot> createState() => ChatbotState();
}

class ChatbotState extends State<Chatbot> {
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
      final profileData = await UserService.fetchProfileDetails(user.id);

      if (profileData != null && mounted) {
        setState(() {
          _userName = profileData['username'] ?? "User";
          _avatarUrl =
              profileData['avatar_url'] ?? "https://i.pravatar.cc/150?img=5";
        });
      }

      final existingSessions = await UserService.fetchLatestSession(user.id);

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

      final publicUrl = await UserService.uploadProfilePicture(user.id, image);

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

  Future<void> _handleSend(String text, Map<String, String> preferences) async {
    if (text.trim().isEmpty || _isSending) return;

    final userID = Supabase.instance.client.auth.currentUser!.id;

    setState(() {
      _messages.add({"role": "user", "text": text});
      _isTyping = true;
      _isSending = true;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      Position? position = await LocationService.determinePosition();

      final String formattedPrefs =
          "Budget: ${preferences['budget']}, Style: ${preferences['style']}, Interests: ${preferences['interests']}";

      final response = await ApiService.sendChatMessage(
        userID: userID,
        sessionId: _currentSessionId,
        text: text,
        lat: position?.latitude,
        lng: position?.longitude,
        prefsContext: formattedPrefs,
      );

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
              _scrollToBottom();
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

  bool _isScrollingAnimationActive = false;

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_scrollController.hasClients) return;

      final position = _scrollController.position;

      if (_isScrollingAnimationActive ||
          position.pixels >= position.maxScrollExtent) {
        return;
      }

      try {
        _isScrollingAnimationActive = true;

        await _scrollController.animateTo(
          position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      } catch (e) {
        debugPrint("Scroll animation interrupted: $e");
      } finally {
        _isScrollingAnimationActive = false;

        if (mounted &&
            _scrollController.position.pixels <
                _scrollController.position.maxScrollExtent) {
          _scrollToBottom();
        }
      }
    });
  }

  Future<void> _loadChatMessages(String sessionId) async {
    try {
      final messagesData = await UserService.fetchChatMessages(sessionId);

      if (mounted) {
        setState(() {
          _messages.clear();
          for (var entry in messagesData) {
            _messages.add({"role": entry['role'], "text": entry['content']});
          }
        });
        _scrollToBottom();
        await Future.delayed(const Duration(milliseconds: 150));
        if (mounted) {
          _scrollToBottom();
        }
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
              onSend: (text, preferences) {
                _handleSend(text, preferences);
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
          return UserMessageBubble(text: msg["text"] ?? "");
        }

        return BotMessageBubble(text: msg["text"] ?? "");
      },
    );
  }
}
