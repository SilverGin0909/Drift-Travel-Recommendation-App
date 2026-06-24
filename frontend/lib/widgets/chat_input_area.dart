import 'package:flutter/material.dart';
import 'dart:math' as math;

class ChatInputArea extends StatefulWidget {
  final TextEditingController inputController;
  final bool isSending;

  /// Updated callback to pass the native message string along with the current preferences payload matrix and itinerary mode
  final Function(String message, Map<String, String> preferences, bool isItineraryMode) onSend;
  final VoidCallback? onStop;

  const ChatInputArea({
    super.key,
    required this.inputController,
    required this.isSending,
    required this.onSend,
    this.onStop,
  });

  @override
  State<ChatInputArea> createState() => _ChatInputAreaState();
}

class _ChatInputAreaState extends State<ChatInputArea> {
  // Native storage variables initialized with sensible default values
  String _budget = "Moderate";
  String _travelStyle = "General";
  String _interests = "Sightseeing";
  bool _itineraryMode = false;

  /// Displays the interactive preference configuration dialog window
  void _showPreferencesDialog() {
    // Temporary variables to hold modifications prior to hitting the 'Save' gate
    String tempBudget = _budget;
    final styleController = TextEditingController(text: _travelStyle);
    final interestsController = TextEditingController(text: _interests);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161622), // Deep dark modal background
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Colors.white10, width: 1),
              ),
              title: const Row(
                children: [
                  Icon(Icons.tune_rounded, color: Color(0xFF818CF8)),
                  SizedBox(width: 10),
                  Text(
                    "Travel Preferences",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Budget",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: ["Budget", "Moderate", "Luxury"].map((option) {
                        final bool isSelected = tempBudget == option;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isSelected
                                    ? const Color(0xFF6155F5)
                                    : Colors.white.withValues(alpha: 0.08),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(
                                    color: isSelected
                                        ? const Color(0xFF818CF8)
                                        : Colors.transparent,
                                    width: 1,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () {
                                setStateDialog(() {
                                  tempBudget = option;
                                });
                              },
                              child: Text(
                                option,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    _buildModalField(
                      "Travel Style",
                      styleController,
                      "e.g., Backpacker, Family, Solo",
                    ),
                    const SizedBox(height: 12),
                    _buildModalField(
                      "Interests",
                      interestsController,
                      "e.g., Food, Sightseeing, Nature",
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6155F5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      _budget = tempBudget;
                      _travelStyle = styleController.text.trim().isEmpty
                          ? "General"
                          : styleController.text.trim();
                      _interests = interestsController.text.trim().isEmpty
                          ? "Sightseeing"
                          : interestsController.text.trim();
                    });
                    Navigator.of(
                      context,
                    ).pop(); // Closes dialog instantly upon saving
                  },
                  child: const Text(
                    "Save",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildModalField(
    String label,
    TextEditingController controller,
    String hint,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF6155F5),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pack the native live parameters up into a matching schema payload layout
    final Map<String, String> currentPreferences = {
      "budget": _budget,
      "style": _travelStyle,
      "interests": _interests,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.9),
            Colors.black,
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08), // Frost-glass dark background
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widget.inputController,
              onSubmitted: widget.isSending
                  ? null
                  : (val) => widget.onSend(val, currentPreferences, _itineraryMode),
              enabled: !widget.isSending,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: const InputDecoration(
                hintText: "Ask Drift...",
                hintStyle: TextStyle(color: Colors.white54, fontSize: 15),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Pill button upgraded with InkWell gesture interactions
                InkWell(
                  onTap: widget.isSending ? null : _showPreferencesDialog,
                  borderRadius: BorderRadius.circular(14),
                  child: _buildPillButton(
                    Icons.person_outline,
                    "Prefs ($_budget)",
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: widget.isSending
                      ? null
                      : () {
                          setState(() {
                            _itineraryMode = !_itineraryMode;
                          });
                        },
                  borderRadius: BorderRadius.circular(14),
                  child: _buildTogglePill(
                    Icons.map_outlined,
                    "Itinerary Mode",
                    _itineraryMode,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6155F5), // Glowing blue-purple button
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: widget.isSending
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.stop_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          onPressed: widget.onStop,
                        )
                      : IconButton(
                          padding: EdgeInsets.zero,
                          icon: Transform.translate(
                            offset: const Offset(2, -1),
                            child: Transform.rotate(
                              angle: -45 * (math.pi / 180),
                              child: const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                          onPressed: () {
                            final textMsg = widget.inputController.text.trim();
                            if (textMsg.isNotEmpty) {
                              widget.onSend(textMsg, currentPreferences, _itineraryMode);
                            }
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

  Widget _buildPillButton(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06), // Frosted glass pill button
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF818CF8)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTogglePill(IconData icon, String label, bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isActive 
            ? const Color(0xFF6155F5).withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive 
              ? const Color(0xFF818CF8) 
              : Colors.white10,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon, 
            size: 16, 
            color: isActive ? const Color(0xFF818CF8) : Colors.white54,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isActive ? Colors.white : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}
