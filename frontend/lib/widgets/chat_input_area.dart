import 'package:flutter/material.dart';
import 'dart:math' as math;

class ChatInputArea extends StatelessWidget {
  final TextEditingController inputController;
  final bool isSending;
  final ValueChanged<String> onSend;

  const ChatInputArea({
    super.key,
    required this.inputController,
    required this.isSending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 20),
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
          color: const Color(0xFFF0F4F9),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: inputController,
              onSubmitted: isSending ? null : onSend,
              enabled: !isSending,
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
            Row(
              children: [
                _buildPillButton(Icons.person_outline, "Preferences"),
                const Spacer(),
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
                  child: isSending
                      ? const Padding(
                          padding: EdgeInsets.all(10.0),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF6155F5), // Custom theme purple/blue
                            ),
                          ),
                        )
                      : IconButton(
                          padding: EdgeInsets.zero,
                          icon: Transform.translate(
                            offset: const Offset(2, -1),
                            child: Transform.rotate(
                              angle: -45 * (math.pi / 180),
                              child: const Icon(
                                Icons.send_rounded,
                                color: Color(
                                  0xFF6155F5,
                                ), // Custom theme purple/blue
                                size: 20,
                              ),
                            ),
                          ),
                          onPressed: () {
                            if (inputController.text.trim().isNotEmpty) {
                              onSend(inputController.text);
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
            offset: const Offset(0, 0.5),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: const Color(0xFF6155F5),
          ), // Custom theme purple/blue
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
}
