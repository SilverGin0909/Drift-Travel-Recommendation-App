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

  String _userName = "Loading...";
  String _avatarUrl = "https://i.pravatar.cc/150?img=5";

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // Assuming your table is named 'profiles'
        final data = await Supabase.instance.client
            .from('user_preferences')
            .select('username, avatar_url')
            .eq('id', user.id)
            .maybeSingle();

        if (data != null && mounted) {
          setState(() {
            _userName = data['username'] ?? "User";
            _avatarUrl = data['avatar_url'] ?? _avatarUrl;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching user data: $e");
      if (mounted) {
        setState(() => _userName = "User"); // Fallback if fetch fails
      }
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
    if (text.trim().isEmpty) return;

    final userID = Supabase.instance.client.auth.currentUser!.id;
    final String backendUrl = "http://10.0.2.2:8000/api/chat";

    setState(() {
      _messages.add({"role": "user", "text": text});
      _isTyping = true;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      Position? position = await LocationService.determinePosition();

      final request = http.Request('POST', Uri.parse(backendUrl));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        "user_id": userID,
        "message": text,
        "user_lat": position?.latitude,
        "user_lng": position?.longitude,
      });

      // Use .send() to get a StreamedResponse
      final response = await http.Client().send(request);

      if (response.statusCode == 200) {
        // Hide the thinking indicator and add an empty bubble for the AI
        setState(() {
          _isTyping = false;
          _messages.add({"role": "bot", "text": ""});
        });

        int botIndex = _messages.length - 1;

        // Listen to the stream chunk by chunk
        await for (var line
            in response.stream
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          if (line.startsWith('data: ')) {
            // Remove 'data: ' and decode the inner JSON
            final data = jsonDecode(line.substring(6));

            if (data.containsKey('text')) {
              setState(() {
                // Append the new token to the existing text
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
    }
    _scrollToBottom();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Base background
      drawer: const SideMenu(),
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
                    h3Padding: const EdgeInsets.only(top: 20),
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
