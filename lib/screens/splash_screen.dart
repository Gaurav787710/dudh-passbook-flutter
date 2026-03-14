import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

/// Professional animated splash screen — Google-style
/// Guarantees minimum display time so logo is always visible until app loads.
class SplashScreen extends StatefulWidget {
  final Widget nextScreen;

  const SplashScreen({super.key, required this.nextScreen});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ── Controllers ──
  late AnimationController _logoController;   // 800ms
  late AnimationController _textController;   // 600ms
  late AnimationController _rippleController; // 900ms
  late AnimationController _shimmerController; // 2000ms repeat
  late AnimationController _exitController;   // 500ms
  late AnimationController _dotsController;   // 1400ms repeat (loading dots)

  bool _navigating = false;
  bool _imageReady = false;

  // Original app icon
  static const _iconAsset = AssetImage('assets/icon/app_icon.png');

  // Fast splash — total ~700ms so app feels snappy
  static const _minDisplayDuration = Duration(milliseconds: 700);
  late DateTime _startTime;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    _initControllers();

    // Logo is already visible on native splash — keep it at full scale
    // from frame 0 so there's no visual discontinuity.
    _logoController.value = 1.0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_imageReady) {
      // Precache in parallel, but DON'T block animations on it.
      // The Image widget will load/display the asset on its own.
      precacheImage(_iconAsset, context).then((_) {
        if (mounted) setState(() => _imageReady = true);
      });
      // Start animations immediately — logo is already visible from native splash
      _runEntrySequence();
    }
  }

  void _initControllers() {
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  Future<void> _runEntrySequence() async {
    if (!mounted) return;

    // Logo already visible from native splash (controller at 1.0).
    // Immediately start the "come alive" effects around it.

    // All animations fire together for a quick 700ms burst
    _rippleController.forward();
    _shimmerController.repeat();
    _textController.forward();
    _dotsController.repeat();

    // Wait just enough to let user see the branding
    final elapsed = DateTime.now().difference(_startTime);
    final remaining = _minDisplayDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }
    if (!mounted) return;

    _navigateOut();
  }

  Future<void> _navigateOut() async {
    if (_navigating) return;
    _navigating = true;

    // Stop loops
    _shimmerController.stop();
    _dotsController.stop();

    // Play exit
    await _exitController.forward();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => widget.nextScreen,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _rippleController.dispose();
    _shimmerController.dispose();
    _dotsController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _logoController,
          _textController,
          _rippleController,
          _shimmerController,
          _dotsController,
          _exitController,
        ]),
        builder: (context, _) {
          // Exit values
          final exitProgress = _exitController.value;
          final exitOpacity = (1.0 - exitProgress).clamp(0.0, 1.0);
          final exitScale = 1.0 + (exitProgress * 0.08);

          return Opacity(
            opacity: exitOpacity,
            child: Transform.scale(
              scale: exitScale,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isDark
                        ? [const Color(0xFF0D1B0E), const Color(0xFF121212)]
                        : [const Color(0xFFF5FFF5), Colors.white],
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _buildRipple(isDark),
                    _buildDotGrid(isDark),
                    SafeArea(
                      child: Column(
                        children: [
                          const Spacer(flex: 3),
                          _buildLogo(isDark),
                          const SizedBox(height: 28),
                          _buildAppName(isDark),
                          const SizedBox(height: 12),
                          _buildTagline(isDark),
                          const Spacer(flex: 3),
                          _buildLoadingDots(isDark),
                          const SizedBox(height: 20),
                          _buildFooterText(isDark),
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  WIDGETS (all use manual .value — no implicit transition widgets)
  // ═══════════════════════════════════════════════

  Widget _buildRipple(bool isDark) {
    final progress = _rippleController.value;
    final scale = Curves.easeOutCubic.transform(progress) * 3.5;
    final opacity = (0.4 * (1.0 - progress)).clamp(0.0, 1.0);
    final color = isDark
        ? const Color(0xFF2E7D32).withOpacity(0.2)
        : const Color(0xFF2E7D32).withOpacity(0.08);

    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2.5),
          ),
        ),
      ),
    );
  }

  Widget _buildDotGrid(bool isDark) {
    final opacity = (_logoController.value * 2).clamp(0.0, 1.0);
    final dotColor = isDark
        ? Colors.white.withOpacity(0.025)
        : const Color(0xFF2E7D32).withOpacity(0.03);

    return Positioned.fill(
      child: Opacity(
        opacity: opacity,
        child: CustomPaint(painter: _DotPainter(color: dotColor)),
      ),
    );
  }

  Widget _buildLogo(bool isDark) {
    // Logo is always visible (matches native splash). No bounce-in needed.
    final raw = _logoController.value;
    // Since raw is already 1.0 from initState, scale & opacity stay at 1.0
    final scale = Curves.easeOutBack.transform(raw.clamp(0.0, 1.0));
    final opacity = (raw / 0.35).clamp(0.0, 1.0);

    // Shimmer value
    final shimVal = _shimmerController.isAnimating
        ? _shimmerController.value
        : -1.0;

    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale.clamp(0.0, 1.15),
        child: Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2E7D32)
                    .withOpacity(isDark ? 0.35 : 0.18),
                blurRadius: 28,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: const Color(0xFF2E7D32)
                    .withOpacity(isDark ? 0.12 : 0.06),
                blurRadius: 50,
                spreadRadius: 8,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Stack(
              children: [
                // splash_logo.png: white-bg removed, only cow content
                Image(
                  image: _iconAsset,
                  width: 140,
                  height: 140,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.local_drink,
                    size: 70,
                    color: Color(0xFF2E7D32),
                  ),
                ),
                // Shimmer sweep
                if (shimVal >= 0)
                  Positioned.fill(
                    child: _ShimmerOverlay(progress: shimVal),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppName(bool isDark) {
    final raw = _textController.value;
    final opacity = Curves.easeIn.transform(raw.clamp(0.0, 1.0));
    final slideY = 20.0 * (1.0 - Curves.easeOutCubic.transform(raw.clamp(0.0, 1.0)));

    return Transform.translate(
      offset: Offset(0, slideY),
      child: Opacity(
        opacity: opacity,
        child: Column(
          children: [
            Text(
              'Dudh Passbook',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                letterSpacing: 0.5,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'दूध पासबुक',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? const Color(0xFF81C784)
                    : const Color(0xFF2E7D32),
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagline(bool isDark) {
    final raw = _textController.value;
    // Tagline appears in the second half of _textController
    final mapped = ((raw - 0.4) / 0.6).clamp(0.0, 1.0);
    final opacity = Curves.easeIn.transform(mapped);
    final slideY = 16.0 * (1.0 - Curves.easeOutCubic.transform(mapped));

    return Transform.translate(
      offset: Offset(0, slideY),
      child: Opacity(
        opacity: opacity,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF2E7D32).withOpacity(0.12)
                : const Color(0xFF2E7D32).withOpacity(0.07),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Smart Dairy Management',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white54 : const Color(0xFF888888),
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  // ── Google-style loading dots ──
  Widget _buildLoadingDots(bool isDark) {
    final textRaw = _textController.value;
    final show = ((textRaw - 0.6) / 0.4).clamp(0.0, 1.0);

    return Opacity(
      opacity: show,
      child: SizedBox(
        height: 24,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return _buildSingleDot(i, isDark);
          }),
        ),
      ),
    );
  }

  Widget _buildSingleDot(int index, bool isDark) {
    if (!_dotsController.isAnimating) {
      return Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark
              ? const Color(0xFF81C784).withOpacity(0.4)
              : const Color(0xFF2E7D32).withOpacity(0.25),
        ),
      );
    }

    // Each dot has a staggered bounce
    // Dot 0: offset 0.0, Dot 1: offset 0.15, Dot 2: offset 0.30
    final stagger = index * 0.15;
    final raw = _dotsController.value;
    final adjusted = ((raw - stagger) % 1.0).clamp(0.0, 1.0);

    // Bounce curve: up in first half, down in second half
    double bounce;
    if (adjusted < 0.5) {
      bounce = Curves.easeOutCubic.transform(adjusted * 2);
    } else {
      bounce = Curves.easeInCubic.transform(1.0 - (adjusted - 0.5) * 2);
    }

    final translateY = -8.0 * bounce;
    final scale = 1.0 + 0.3 * bounce;
    final dotOpacity = 0.3 + 0.7 * bounce;

    final baseColor = isDark
        ? const Color(0xFF81C784)
        : const Color(0xFF2E7D32);

    return Transform.translate(
      offset: Offset(0, translateY),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: baseColor.withOpacity(dotOpacity.clamp(0.0, 1.0)),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterText(bool isDark) {
    final raw = _textController.value;
    final opacity = ((raw - 0.5) / 0.5).clamp(0.0, 1.0);

    return Opacity(
      opacity: opacity,
      child: Text(
        'Made in India 🇮🇳',
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white24 : Colors.grey.shade400,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
//  SHIMMER OVERLAY (extracted to avoid issues)
// ═══════════════════════════════════════════════
class _ShimmerOverlay extends StatelessWidget {
  final double progress;
  const _ShimmerOverlay({required this.progress});

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    return IgnorePointer(
      child: CustomPaint(
        painter: _ShimmerPainter(progress: p),
      ),
    );
  }
}

/// Draws only a thin diagonal shimmer highlight — no solid fill.
class _ShimmerPainter extends CustomPainter {
  final double progress;
  _ShimmerPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withOpacity(0.0),
        Colors.white.withOpacity(0.18),
        Colors.white.withOpacity(0.0),
      ],
      stops: [
        (progress - 0.25).clamp(0.0, 1.0),
        progress,
        (progress + 0.25).clamp(0.0, 1.0),
      ],
      transform: const GradientRotation(math.pi / 4),
    );
    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.progress != progress;
}

// ═══════════════════════════════════════════════
//  DOT GRID BACKGROUND
// ═══════════════════════════════════════════════
class _DotPainter extends CustomPainter {
  final Color color;
  _DotPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
