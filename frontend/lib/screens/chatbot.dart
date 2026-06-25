import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/services/location_service.dart';
import 'dart:convert';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

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
import 'package:frontend/screens/itinerary_viewer.dart';
import 'package:frontend/widgets/custom_toast.dart';

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
  String _thinkingText = "Thinking...";

  StreamSubscription<String>? _chatStreamSubscription;
  Completer<void>? _streamCompleter;
  http.Client? _activeHttpClient;

  Map<String, String> _lastPreferences = {
    "budget": "Moderate",
    "style": "General",
    "interests": "Sightseeing"
  };

  int _getLatestUserMessageIndex() {
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i]["role"] == "user") {
        return i;
      }
    }
    return -1;
  }

  void _showUserMessageActions(int messageIndex, String currentMessage, {required bool isLatest}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: Colors.grey),
                title: const Text(
                  'Copy Message',
                  style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                ),
                onTap: () async {
                  final mainContext = this.context;
                  Navigator.pop(context);
                  await Clipboard.setData(ClipboardData(text: currentMessage));
                  if (mainContext.mounted) {
                    CustomToast.show(mainContext, "Message copied to clipboard");
                  }
                },
              ),
              if (isLatest)
                ListTile(
                  leading: Icon(
                    Icons.edit_note_rounded,
                    color: _isSending ? Colors.white24 : Colors.grey,
                  ),
                  title: Text(
                    'Edit Message',
                    style: TextStyle(
                      color: _isSending ? Colors.white24 : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  enabled: !_isSending,
                  onTap: () {
                    Navigator.pop(context);
                    _showEditMessageDialog(messageIndex, currentMessage);
                  },
                ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showEditMessageDialog(int messageIndex, String currentMessage) async {
    final localContext = context;
    final textController = TextEditingController(text: currentMessage);
    
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161622),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.white10, width: 1),
          ),
          title: const Text(
            "Edit Message",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: TextField(
              controller: textController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: "Edit your query...",
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF6155F5), width: 1.5),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6155F5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                "Send",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true || textController.text.trim().isEmpty) return;

    final String editedQuery = textController.text.trim();

    // Determine if this turn was in itinerary mode based on the subsequent bot message content
    bool wasItineraryMode = false;
    if (messageIndex + 1 < _messages.length) {
      final String botText = _messages[messageIndex + 1]["text"] ?? "";
      if (botText.trim().startsWith('{"destination":')) {
        wasItineraryMode = true;
      }
    }

    try {
      if (_currentSessionId != null) {
        // Query the latest 2 messages in Supabase to delete them
        final res = await Supabase.instance.client
            .from('chat_messages')
            .select('id')
            .eq('session_id', _currentSessionId!)
            .order('created_at', ascending: false)
            .limit(2);

        if (res.isNotEmpty) {
          final List<dynamic> idsToDelete = res.map((msg) => msg['id'] as String).toList();
          await Supabase.instance.client
              .from('chat_messages')
              .delete()
              .inFilter('id', idsToDelete);
        }
      }

      // Update local state by removing the latest user and all subsequent messages
      setState(() {
        if (messageIndex >= 0 && messageIndex < _messages.length) {
          _messages.removeRange(messageIndex, _messages.length);
        }
      });

      _handleSend(editedQuery, _lastPreferences, wasItineraryMode);

    } catch (e) {
      debugPrint("Error editing query: $e");
      if (localContext.mounted) {
        CustomToast.show(localContext, "Failed to edit query: $e");
      }
    }
  }

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
        CustomToast.show(context, "Profile picture updated!");
      }
    } catch (e) {
      debugPrint("Error uploading image: $e");
      if (mounted) {
        CustomToast.show(context, "Failed to update picture.");
      }
    }
  }

  void _stopGeneration() {
    if (_chatStreamSubscription != null) {
      _chatStreamSubscription!.cancel();
      _chatStreamSubscription = null;
    }
    if (_activeHttpClient != null) {
      _activeHttpClient!.close();
      _activeHttpClient = null;
    }
    if (_streamCompleter != null && !_streamCompleter!.isCompleted) {
      _streamCompleter!.complete();
      _streamCompleter = null;
    }
    setState(() {
      _isTyping = false;
      _isSending = false;
    });
  }

  Future<void> _handleSend(
    String text,
    Map<String, String> preferences,
    bool itineraryMode,
  ) async {
    if (text.trim().isEmpty || _isSending) return;

    final userID = Supabase.instance.client.auth.currentUser!.id;

    String initialThinking = "Thinking...";
    if (itineraryMode) {
      initialThinking = "Generating itinerary for user's destination...";
    }

    _lastPreferences = preferences;

    setState(() {
      _messages.add({"role": "user", "text": text});
      _isTyping = true;
      _isSending = true;
      _thinkingText = initialThinking;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      Position? position = await LocationService.determinePosition();

      final String formattedPrefs =
          "Budget: ${preferences['budget']}, Style: ${preferences['style']}, Interests: ${preferences['interests']}";

      _activeHttpClient = http.Client();
      final response = await ApiService.sendChatMessage(
        client: _activeHttpClient!,
        userID: userID,
        sessionId: _currentSessionId,
        text: text,
        lat: position?.latitude,
        lng: position?.longitude,
        prefsContext: formattedPrefs,
        isItineraryMode: itineraryMode,
      );

      if (response.statusCode == 200) {
        if (itineraryMode) {
          int? botIndex;
          final stream = response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter());

          _streamCompleter = Completer<void>();
          _chatStreamSubscription = stream.listen(
            (line) {
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

                if (data.containsKey('status')) {
                  final String statusVal = data['status'];
                  if (statusVal == 'searching') {
                    setState(() {
                      _thinkingText = "Searching KL for you...";
                    });
                  }
                } else if (data.containsKey('type') && data['type'] == 'itinerary') {
                  final itineraryData = data['data'];
                  setState(() {
                    _isTyping = false;
                    _messages.add({
                      "role": "bot",
                      "text": jsonEncode(itineraryData),
                    });
                  });
                  _scrollToBottom();

                  if (mounted) {
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (context) => ItineraryViewer(
                              itinerary: itineraryData as Map<String, dynamic>,
                              sessionId: _currentSessionId!,
                            ),
                          ),
                        )
                        .then((hasChanged) {
                          if (hasChanged == true &&
                              _currentSessionId != null &&
                              mounted) {
                            _loadChatMessages(_currentSessionId!);
                          }
                        });
                  }
                  _chatStreamSubscription?.cancel();
                  if (_streamCompleter != null && !_streamCompleter!.isCompleted) {
                    _streamCompleter!.complete();
                  }
                } else if (data.containsKey('text')) {
                  setState(() {
                    _isTyping = false;
                    if (botIndex == null) {
                      _messages.add({"role": "bot", "text": data['text']});
                      botIndex = _messages.length - 1;
                    } else {
                      _messages[botIndex!]["text"] =
                          _messages[botIndex!]["text"]! + data['text'];
                    }
                  });
                  _scrollToBottom();
                }
              }
            },
            onError: (error) {
              if (_streamCompleter != null && !_streamCompleter!.isCompleted) {
                _streamCompleter!.completeError(error);
              }
            },
            onDone: () {
              if (_streamCompleter != null && !_streamCompleter!.isCompleted) {
                _streamCompleter!.complete();
              }
            },
            cancelOnError: true,
          );

          await _streamCompleter!.future;
        } else {
          int? botIndex;
          final stream = response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter());

          _streamCompleter = Completer<void>();
          _chatStreamSubscription = stream.listen(
            (line) {
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

                if (data.containsKey('status')) {
                  final String statusVal = data['status'];
                  if (statusVal == 'searching') {
                    setState(() {
                      _thinkingText = "Searching KL for you...";
                    });
                  }
                } else if (data.containsKey('text')) {
                  setState(() {
                    _isTyping = false;
                    if (botIndex == null) {
                      _messages.add({"role": "bot", "text": data['text']});
                      botIndex = _messages.length - 1;
                    } else {
                      _messages[botIndex!]["text"] =
                          _messages[botIndex!]["text"]! + data['text'];
                    }
                  });
                  _scrollToBottom();
                }
              }
            },
            onError: (error) {
              if (_streamCompleter != null && !_streamCompleter!.isCompleted) {
                _streamCompleter!.completeError(error);
              }
            },
            onDone: () {
              if (_streamCompleter != null && !_streamCompleter!.isCompleted) {
                _streamCompleter!.complete();
              }
            },
            cancelOnError: true,
          );

          await _streamCompleter!.future;
        }
      } else {
        throw Exception("Server error: ${response.statusCode}");
      }
      _activeHttpClient?.close();
      _activeHttpClient = null;
      setState(() {
        _isTyping = false;
        _isSending = false;
      });
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
      _chatStreamSubscription = null;
      _streamCompleter = null;
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
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutQuint,
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
      backgroundColor: Colors.black,
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
          BackgroundGlow(isThinking: _isTyping || _isSending),

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
              onStop: _stopGeneration,
              onSend: (text, preferences, itineraryMode) {
                _handleSend(text, preferences, itineraryMode);
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
          return ThinkingIndicator(text: _thinkingText);
        }

        final msg = _messages[index];
        final isUser = msg["role"] == "user";

        if (isUser) {
          final int latestUserIndex = _getLatestUserMessageIndex();
          final bool isLatest = index == latestUserIndex;
          
          return GestureDetector(
            onLongPress: () {
              _showUserMessageActions(index, msg["text"] ?? "", isLatest: isLatest);
            },
            child: UserMessageBubble(text: msg["text"] ?? ""),
          );
        }

        final text = msg["text"] ?? "";
        if (text.startsWith('{"destination":')) {
          return ItineraryPreviewCard(
            jsonText: text,
            sessionId: _currentSessionId ?? "",
            onReload: () {
              if (_currentSessionId != null) {
                _loadChatMessages(_currentSessionId!);
              }
            },
          );
        }

        return BotMessageBubble(text: text);
      },
    );
  }
}

class ItineraryPreviewCard extends StatelessWidget {
  final String jsonText;
  final String sessionId;
  final VoidCallback onReload;

  const ItineraryPreviewCard({
    super.key,
    required this.jsonText,
    required this.sessionId,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    try {
      final data = jsonDecode(jsonText) as Map<String, dynamic>;
      final destination = data['destination'] ?? "Trip Plan";
      final days = data['days'] as List<dynamic>? ?? [];
      final totalDays = data['duration_days'] ?? days.length;

      int totalActivities = 0;
      for (var day in days) {
        if (day['activities'] != null) {
          totalActivities += (day['activities'] as List<dynamic>).length;
        }
      }

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF6155F5).withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6155F5).withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6155F5).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.map_outlined,
                    color: Color(0xFF818CF8),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "DRAFT ITINERARY GENERATED",
                        style: TextStyle(
                          color: Color(0xFF818CF8),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        destination,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoColumn(
                  Icons.calendar_today_rounded,
                  "$totalDays Days",
                ),
                _buildInfoColumn(
                  Icons.alt_route_rounded,
                  "$totalActivities Stops",
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6155F5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                onPressed: () {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (context) => ItineraryViewer(
                            itinerary: data,
                            sessionId: sessionId,
                          ),
                        ),
                      )
                      .then((hasChanged) {
                        if (hasChanged == true) {
                          onReload();
                        }
                      });
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.edit_road_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      "View & Edit Itinerary",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      return BotMessageBubble(text: jsonText);
    }
  }

  Widget _buildInfoColumn(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white38),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
