import 'package:flutter/material.dart';
import 'package:frontend/services/location_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_markdown_stream/flutter_markdown_stream.dart';
import 'dart:math' as math;

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
      body: Stack(
        children: [
          // 1. BACKGROUND GLOW EFFECTS
          // Top Right Blue Glow
          Positioned(
            top: -140,
            right: -200,
            child: Container(
              width: 440,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.lightBlueAccent.withValues(alpha: 0.2),
                    Colors.lightBlueAccent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Bottom Left Yellow/Orange Glow
          Positioned(
            bottom: 160,
            left: -200,
            child: Container(
              width: 400,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.amber.withValues(alpha: 0.15),
                    Colors.amber.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 40,
            right: -160,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0xFFCAD5FF).withValues(alpha: 0.8),
                    Color(0xFFCAD5FF).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            bottom: -240,
            left: -160,
            child: Container(
              width: 300,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.lightBlueAccent.withValues(alpha: 0.25),
                    Colors.lightBlueAccent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          // 2. MAIN CONTENT
          Column(
            children: [
              SafeArea(bottom: false, child: _buildHeader()),

              Expanded(
                child: _messages.isEmpty
                    ? _buildWelcomeScreen()
                    : _buildChatList(),
              ),
            ],
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomInputArea(context),
          ),
        ],
      ),
    );
  }

  // --- Header Widget ---
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      child: Row(
        children: [
          // Menu Icon
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.menu, color: Colors.black87),
                onPressed: () {},
              ),
            ),
          ),

          // Center Logo
          const Text(
            'Drift',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),

          // User Profile
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Hi, Gin',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.black,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'Welcome Back',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  const CircleAvatar(
                    radius: 15,
                    backgroundColor: Colors.grey,
                    backgroundImage: NetworkImage(
                      'https://i.pravatar.cc/150?img=5',
                    ), // Placeholder Avatar
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Vertical centering
          crossAxisAlignment: CrossAxisAlignment.center, // Horizontal centering
          mainAxisSize:
              MainAxisSize.min, // Prevents column from expanding too far
          children: [
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (Rect bounds) {
                return const LinearGradient(
                  colors: [
                    Color(0xFFFFBD25), // Gold
                    Color(0xFF305DFF), // Blue
                    Color(0xFF30D2FF), // Light Blue
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ).createShader(bounds);
              },
              child: const Text(
                'Welcome to Drift AI',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Roboto',
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'How Can I Assist You Today?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Bottom Input Area Widget ---
  Widget _buildBottomInputArea(BuildContext context) {
    return Container(
      // The "Cover" effect: Gradient from transparent to solid white
      padding: const EdgeInsets.fromLTRB(
        16,
        40,
        16,
        20,
      ), // Top padding for the fade
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.9),
            Colors.white,
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4F9), // Subtle Gemini-style grey
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Text Input Area
            TextField(
              controller: _inputController,
              onSubmitted: _handleSend,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: "Ask Drift...",
                hintStyle: TextStyle(color: Colors.black54, fontSize: 15),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 12),

            // 2. Actions Row
            Row(
              children: [
                // Keeping your Preferences Pill
                _buildPillButton(Icons.person_outline, "Preferences"),

                const Spacer(),

                // Keeping your exact Send Button Design
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Transform.translate(
                      offset: const Offset(2, -1),
                      child: Transform.rotate(
                        angle: -45 * (math.pi / 180),
                        child: const Icon(
                          Icons.send_rounded,
                          color: Color(0xFF6155F5),
                          size: 20,
                        ),
                      ),
                    ),
                    onPressed: () {
                      _handleSend(_inputController.text);
                      _inputController.clear();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Helper for the small "Pill" buttons (AR Mode / Preferences)
  Widget _buildPillButton(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.5),
            spreadRadius: 0.2,
            blurRadius: 0.2,
            offset: Offset(0, 0.5),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF6155F5)), // Blue icon
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Drift",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.3, end: 0.8),
              duration: const Duration(milliseconds: 1000),
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF6155F5), // Matching your theme blue
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "Searching KL for you...",
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
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
          return _buildThinkingIndicator();
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
