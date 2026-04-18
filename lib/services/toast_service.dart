import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ToastType { success, error, info, warning }

class ToastService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static void show(String message, {ToastType type = ToastType.info, Duration duration = const Duration(seconds: 30)}) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _ModernToastWidget(
        message: message,
        type: type,
        onClose: () => overlayEntry.remove(),
        duration: duration,
      ),
    );

    overlay.insert(overlayEntry);
  }

  static void success(String message) => show(message, type: ToastType.success);
  static void error(String message) => show(message, type: ToastType.error);
  static void info(String message) => show(message, type: ToastType.info);
  static void warning(String message) => show(message, type: ToastType.warning);
}

class _ModernToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final VoidCallback onClose;
  final Duration duration;

  const _ModernToastWidget({
    required this.message,
    required this.type,
    required this.onClose,
    required this.duration,
  });

  @override
  State<_ModernToastWidget> createState() => _ModernToastWidgetState();
}

class _ModernToastWidgetState extends State<_ModernToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    _opacityAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _controller.forward();

    _timer = Timer(widget.duration, () {
      if (mounted) {
        _handleClose();
      }
    });
  }

  void _handleClose() {
    _controller.reverse().then((_) => widget.onClose());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color primaryColor;
    IconData icon;

    switch (widget.type) {
      case ToastType.success:
        primaryColor = Colors.green.shade600;
        icon = Icons.check_circle_rounded;
        break;
      case ToastType.error:
        primaryColor = Colors.red.shade600;
        icon = Icons.error_rounded;
        break;
      case ToastType.warning:
        primaryColor = Colors.orange.shade600;
        icon = Icons.warning_rounded;
        break;
      case ToastType.info:
        primaryColor = Colors.blue.shade600;
        icon = Icons.info_rounded;
        break;
    }

    return Material(
      color: Colors.transparent,
      child: Center(
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: FadeTransition(
            opacity: _opacityAnimation,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: primaryColor.withValues(alpha: 0.1), width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: primaryColor, size: 36),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1F36),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 40,
                        child: ElevatedButton(
                          onPressed: _handleClose,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                          ),
                          child: Text(
                            'Dismiss',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
