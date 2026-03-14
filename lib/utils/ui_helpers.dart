import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';

// ═══════════════════════════════════════════════════════════════
// Dudh Passbook — Shared UI Performance Helpers
// Shimmer loaders, button guards, error dialogs, network banners
// ═══════════════════════════════════════════════════════════════

/// Professional shimmer loading effect — replaces blank screens / spinners
class ShimmerLoading extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerLoading({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade200;
    final highlightColor =
        isDark ? const Color(0xFF3A3A4E) : Colors.grey.shade50;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value + 1, 0),
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton card placeholder for dashboard-style cards
class SkeletonCard extends StatelessWidget {
  final double height;
  const SkeletonCard({super.key, this.height = 100});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerLoading(width: 120, height: 14),
          SizedBox(height: 12),
          ShimmerLoading(width: double.infinity, height: 12),
          SizedBox(height: 8),
          ShimmerLoading(width: 200, height: 12),
        ],
      ),
    );
  }
}

/// Skeleton list placeholder — shows N shimmer rows
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  const SkeletonList({super.key, this.itemCount = 6, this.itemHeight = 72});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemBuilder: (context, index) {
        return Container(
          height: itemHeight,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              ShimmerLoading(width: 44, height: 44, borderRadius: 22),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ShimmerLoading(width: 140, height: 14),
                    SizedBox(height: 8),
                    ShimmerLoading(width: 90, height: 11),
                  ],
                ),
              ),
              ShimmerLoading(width: 60, height: 14),
            ],
          ),
        );
      },
    );
  }
}

/// Dashboard skeleton — matches the dashboard card layout
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        // Stats cards row
        Row(
          children: [
            Expanded(child: SkeletonCard(height: 90)),
            Expanded(child: SkeletonCard(height: 90)),
          ],
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: SkeletonCard(height: 90)),
            Expanded(child: SkeletonCard(height: 90)),
          ],
        ),
        SizedBox(height: 16),
        // Chart placeholder
        SkeletonCard(height: 200),
        SizedBox(height: 16),
        // List rows
        SkeletonCard(height: 60),
        SkeletonCard(height: 60),
        SkeletonCard(height: 60),
      ],
    );
  }
}

/// Button with built-in loading state and double-tap prevention
class SafeAsyncButton extends StatefulWidget {
  final Future<void> Function() onPressed;
  final String label;
  final IconData? icon;
  final Color? color;
  final Color? textColor;
  final double? width;
  final double height;
  final double fontSize;
  final bool enabled;
  final BorderRadius? borderRadius;

  const SafeAsyncButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.color,
    this.textColor,
    this.width,
    this.height = 48,
    this.fontSize = 15,
    this.enabled = true,
    this.borderRadius,
  });

  @override
  State<SafeAsyncButton> createState() => _SafeAsyncButtonState();
}

class _SafeAsyncButtonState extends State<SafeAsyncButton> {
  bool _isWorking = false;

  Future<void> _handleTap() async {
    if (_isWorking || !widget.enabled) return;
    setState(() => _isWorking = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final btnColor = widget.color ??
        (isDark ? const Color(0xFF5C6BC0) : const Color(0xFF2E7D32));
    final txtColor = widget.textColor ?? Colors.white;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ElevatedButton(
        onPressed: (_isWorking || !widget.enabled) ? null : _handleTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: btnColor,
          foregroundColor: txtColor,
          disabledBackgroundColor: btnColor.withValues(alpha: 0.5),
          elevation: _isWorking ? 0 : 2,
          shape: RoundedRectangleBorder(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _isWorking
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(txtColor),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: widget.fontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Show a professional non-intrusive error banner
void showErrorBanner(BuildContext context, String message,
    {VoidCallback? onRetry}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(fontSize: 13, color: Colors.white)),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                onRetry();
              },
              child: const Text('Retry',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 5),
    ),
  );
}

/// Show a slow-network banner (non-intrusive)
void showSlowNetworkBanner(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Slow internet connection. Syncing in background…',
              style: TextStyle(fontSize: 13, color: Colors.white),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.orange.shade800,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 4),
    ),
  );
}

/// Show a modern error dialog for unexpected errors
Future<void> showErrorDialog(BuildContext context,
    {String? title, String? message}) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.warning_amber_rounded,
                color: Colors.red.shade600, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title ?? 'Something went wrong',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      content: Text(
        message ?? 'Please wait a moment and try again.',
        style: const TextStyle(fontSize: 14, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Debouncer for text input — prevents DB spam on every keystroke
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({this.delay = const Duration(milliseconds: 300)});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

// ═══════════════════════════════════════════════════════════════
// Network Connectivity Check
// ═══════════════════════════════════════════════════════════════

/// Check if device has internet connectivity by pinging Google DNS.
/// Returns true if connected, false if no internet.
Future<bool> hasInternetConnection() async {
  try {
    final result = await InternetAddress.lookup('google.com')
        .timeout(const Duration(seconds: 5));
    return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Show a professional no-internet popup dialog.
/// Returns true if user tapped 'Retry' and connection is now available.
Future<bool> showNoInternetDialog(BuildContext context, {bool isHindi = false}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.wifi_off_rounded, color: Colors.red.shade600, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              isHindi ? 'इंटरनेट नहीं है' : 'No Internet Connection',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.signal_cellular_off_rounded, color: Colors.red.shade400, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isHindi
                        ? 'कृपया अपना WiFi या मोबाइल डेटा चालू करें और फिर से कोशिश करें।'
                        : 'Please check your WiFi or mobile data connection and try again.',
                    style: TextStyle(fontSize: 13, color: Colors.red.shade700, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            isHindi ? 'बंद करें' : 'Close',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            final connected = await hasInternetConnection();
            if (ctx.mounted) {
              Navigator.pop(ctx, connected);
            }
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(isHindi ? 'पुनः प्रयास करें' : 'Retry'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade600,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    ),
  );
  return result == true;
}
