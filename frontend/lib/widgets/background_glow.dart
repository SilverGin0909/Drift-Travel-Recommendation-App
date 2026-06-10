import 'dart:ui';
import 'package:flutter/material.dart';
import 'dart:math' as math;

class BackgroundGlow extends StatefulWidget {
  final bool isThinking;

  const BackgroundGlow({super.key, this.isThinking = false});

  @override
  State<BackgroundGlow> createState() => _BackgroundGlowState();
}

class _BackgroundGlowState extends State<BackgroundGlow>
    with TickerProviderStateMixin {
  // _breathController: drives the repeating phase accumulator for the breathing/drift loop
  late AnimationController _breathController;
  // _mixController: ramps 0.0→1.0 when active, then reverses 1.0→0.0 smoothly on stop
  late AnimationController _mixController;

  double _phase = 0.0;
  double _lastBreathValue = 0.0;

  // Pre-generated dither grain points
  late List<Offset> _grainWhitePoints;
  late List<Offset> _grainBlackPoints;

  @override
  void initState() {
    super.initState();

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_onBreathTick);

    _mixController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), // Smooth 1.5s ramp-up and ramp-down
    );

    // Seeded Random to produce consistent dither patterns
    final random = math.Random(42);
    _grainWhitePoints = List.generate(600, (_) => Offset(random.nextDouble(), random.nextDouble()));
    _grainBlackPoints = List.generate(600, (_) => Offset(random.nextDouble(), random.nextDouble()));

    // Grain repaint needs the breath controller always ticking
    _breathController.repeat();
  }

  void _onBreathTick() {
    final double currentValue = _breathController.value;
    double delta = currentValue - _lastBreathValue;
    if (delta < 0) {
      // Handle loop boundary of the animation controller repeating
      delta = (currentValue + 1.0) - _lastBreathValue;
    }
    _lastBreathValue = currentValue;

    // Accumulate phase only while there is active mixing happening
    if (_mixController.value > 0.0) {
      _phase += delta * 1.4;
    }
  }

  @override
  void didUpdateWidget(covariant BackgroundGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isThinking != oldWidget.isThinking) {
      if (widget.isThinking) {
        // Ramp intensity up to 1.0 over 1.5 seconds
        _mixController.forward();
      } else {
        // Smoothly reverse intensity back to 0.0, from wherever it currently is
        _mixController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _breathController.dispose();
    _mixController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to both controllers so we repaint on every tick
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: Listenable.merge([_breathController, _mixController]),
        builder: (context, child) {
          final double mixValue = _mixController.value; // 0.0 = fully idle, 1.0 = fully active

          return Stack(
            children: [
              // 1. Original Glow Painter (with scale and drift animations)
              Positioned.fill(
                child: CustomPaint(
                  painter: OriginalGlowPainter(
                    phase: _phase,
                    mixValue: mixValue,
                  ),
                ),
              ),

              // 2. Frosted Blur Overlay: blends edge shapes and softens banding lines
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 70.0, sigmaY: 70.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.08),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.02),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.05),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

              // 3. Dithered Film Grain Overlay: textured matte finish
              Positioned.fill(
                child: CustomPaint(
                  painter: FilmGrainPainter(
                    whitePoints: _grainWhitePoints,
                    blackPoints: _grainBlackPoints,
                    animationValue: _breathController.value,
                    mixValue: mixValue,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class OriginalGlowPainter extends CustomPainter {
  final double phase;
  final double mixValue; // 0.0 = idle rest, 1.0 = fully active

  OriginalGlowPainter({required this.phase, required this.mixValue});

  @override
  void paint(Canvas canvas, Size size) {
    final double m = mixValue; // Shorthand

    // Breathing opacity factors: at m=0.0 they all equal 1.0, at m=1.0 they breathe dynamically
    final double opFactor1 = 1.0 - m + m * (0.45 + math.sin(phase * 1.5).abs() * 0.55);
    final double opFactor2 = 1.0 - m + m * (0.55 + math.cos(phase * 1.2).abs() * 0.45);
    final double opFactor3 = 1.0 - m + m * (0.40 + math.sin(phase * 0.8 + 1.0).abs() * 0.60);
    final double opFactor4 = 1.0 - m + m * (0.50 + math.cos(phase * 1.4 + 0.5).abs() * 0.50);

    // Opacity values multiplied by breathing factors
    final double alpha1 = 0.20 * opFactor1;
    final double alpha2 = 0.15 * opFactor2;
    final double alpha3 = 0.80 * opFactor3;
    final double alpha4 = 0.25 * opFactor4;

    // Drift movements: at m=0.0 they resolve to 0.0, at m=1.0 they fully oscillate
    final double dx1 = m * math.sin(phase * 0.8) * 15.0;
    final double dx2 = m * math.cos(phase * 0.7) * 12.0;
    final double dx3 = m * math.sin(phase * 0.9 + 1.0) * 10.0;
    final double dx4 = m * math.cos(phase * 0.5 + 2.0) * 15.0;

    // Scale factors: at m=0.0 they resolve to exactly 1.0, at m=1.0 they breathe
    final double scaleFactor1 = 1.0 - m + m * (0.94 + math.sin(phase * 0.5).abs() * 0.12);
    final double scaleFactor2 = scaleFactor1; // Mirrored from right side
    final double scaleFactor3 = 1.0 - m + m * (0.92 + math.sin(phase * 0.4).abs() * 0.16);
    final double scaleFactor4 = scaleFactor3; // Mirrored from right side

    // 1. Top Right (Light Blue)
    final double cx1 = size.width - 20.0 + dx1;
    final double cy1 = 400.0;
    final double r1 = 220.0 * scaleFactor1;
    _drawBlob(canvas, Offset(cx1, cy1), r1, Colors.lightBlueAccent, alpha1);

    // 2. Top Left (Amber) - Mirrored placement and size from Top Right
    final double cx2 = 20.0 + dx2;
    final double cy2 = 450.0;
    final double r2 = 270.0 * scaleFactor2;
    _drawBlob(canvas, Offset(cx2, cy2), r2, Colors.amber, alpha2);

    // 3. Bottom Right (Lavender/Indigo)
    final double cx3 = size.width + 10.0 + dx3;
    final double cy3 = size.height - 400.0;
    final double r3 = 150.0 * scaleFactor3;
    _drawBlob(canvas, Offset(cx3, cy3), r3, const Color(0xFFCAD5FF), alpha3);

    // 4. Bottom Left (Light Blue) - Mirrored placement and size from Bottom Right
    final double cx4 = -10.0 + dx4;
    final double cy4 = size.height - 400.0;
    final double r4 = 200.0 * scaleFactor4;
    _drawBlob(canvas, Offset(cx4, cy4), r4, Colors.lightBlueAccent, alpha4);
  }

  void _drawBlob(
    Canvas canvas,
    Offset center,
    double radius,
    Color baseColor,
    double opacity,
  ) {
    if (radius <= 0 || opacity <= 0) return;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    final Color color = baseColor.withValues(alpha: opacity);
    final Color colorZero = baseColor.withValues(alpha: 0.0);

    // Smooth exponential decay of alpha to completely eliminate banding borders
    final Paint paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color,
          baseColor.withValues(alpha: opacity * 0.65),
          baseColor.withValues(alpha: opacity * 0.30),
          baseColor.withValues(alpha: opacity * 0.10),
          colorZero,
        ],
        stops: const [0.0, 0.35, 0.65, 0.85, 1.0],
      ).createShader(rect);

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant OriginalGlowPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.mixValue != mixValue;
  }
}

class FilmGrainPainter extends CustomPainter {
  final List<Offset> whitePoints;
  final List<Offset> blackPoints;
  final double animationValue;
  final double mixValue;

  FilmGrainPainter({
    required this.whitePoints,
    required this.blackPoints,
    required this.animationValue,
    required this.mixValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Flicker only when mix is active; below a small threshold treat as idle/static
    final bool isActive = mixValue > 0.05;
    final int seed = isActive ? (animationValue * 24).floor() : 42;
    final random = math.Random(seed);

    final Paint whitePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.015)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.square;

    final Paint blackPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.022)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.square;

    canvas.save();
    if (isActive) {
      // Scale jitter intensity with mixValue so it fades out smoothly
      final double jitterRange = 8.0 * mixValue;
      final double dx = (random.nextDouble() - 0.5) * jitterRange;
      final double dy = (random.nextDouble() - 0.5) * jitterRange;
      canvas.translate(dx, dy);
    }

    final List<Offset> scaledWhite = whitePoints
        .map((p) => Offset(p.dx * size.width, p.dy * size.height))
        .toList();
    final List<Offset> scaledBlack = blackPoints
        .map((p) => Offset(p.dx * size.width, p.dy * size.height))
        .toList();

    canvas.drawPoints(PointMode.points, scaledWhite, whitePaint);
    canvas.drawPoints(PointMode.points, scaledBlack, blackPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FilmGrainPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.mixValue != mixValue ||
        oldDelegate.whitePoints != whitePoints ||
        oldDelegate.blackPoints != blackPoints;
  }
}
