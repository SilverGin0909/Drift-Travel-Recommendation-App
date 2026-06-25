import 'package:flutter/material.dart';

class CustomToast {
  static void show(BuildContext context, String message) {
    if (!context.mounted) return;

    final overlayState = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 180.0, // Floating above the bottom elements
        left: 20.0,
        right: 20.0,
        child: ToastWidget(
          message: message,
          onDismiss: () {
            overlayEntry.remove();
          },
        ),
      ),
    );

    overlayState.insert(overlayEntry);

    // Automatically remove after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }
}

class ToastWidget extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;

  const ToastWidget({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  @override
  State<ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.forward();

    // Start fade out slightly before 3 seconds
    Future.delayed(const Duration(milliseconds: 2700), () {
      if (mounted) {
        _controller.reverse().then((_) {
          widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacityAnimation,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
          decoration: BoxDecoration(
            color: Color.fromARGB(255, 66, 66, 66), // Light grey background
            border: Border(
              top: BorderSide(
                color: Color.fromARGB(255, 66, 66, 66),
                width: 1.0,
              ),
              bottom: BorderSide(
                color: Color.fromARGB(255, 66, 66, 66),
                width: 1.0,
              ),
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Color(0x15000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFFFFFFFF), // White icon
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF), // White text
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
