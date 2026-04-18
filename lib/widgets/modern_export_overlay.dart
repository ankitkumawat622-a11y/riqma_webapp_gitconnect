import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ModernExportOverlay extends StatefulWidget {
  final String initialMessage;
  final Stream<ExportProgress> progressStream;
  final VoidCallback onDismiss;

  const ModernExportOverlay({
    super.key,
    required this.initialMessage,
    required this.progressStream,
    required this.onDismiss,
  });

  @override
  State<ModernExportOverlay> createState() => _ModernExportOverlayState();
}

class _ModernExportOverlayState extends State<ModernExportOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  ExportProgress _currentProgress = ExportProgress(0.0, '');
  bool _isCompleted = false;
  bool _isError = false;
  String? _errorMessage;
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _currentProgress = ExportProgress(0.0, widget.initialMessage);
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    widget.progressStream.listen(
      (progress) {
        if (mounted) {
          setState(() {
            _currentProgress = progress;
            if (progress.value >= 1.0) {
              _isCompleted = true;
            }
          });
        }
      },
      onError: (Object error) {
        if (mounted) {
          setState(() {
            _isError = true;
            _errorMessage = error.toString();
          });
        }
      },
      onDone: () {
        if (mounted && !_isError) {
          setState(() {
            _isCompleted = true;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _getRemainingTime() {
    if (_startTime == null || _currentProgress.value <= 0.0 || _isCompleted) return '--:--';
    
    final elapsed = DateTime.now().difference(_startTime!);
    final estimatedTotal = elapsed.inMilliseconds / _currentProgress.value;
    final remaining = estimatedTotal - elapsed.inMilliseconds;
    
    if (remaining < 0) return '00:00';
    
    final duration = Duration(milliseconds: remaining.toInt());
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Backdrop Blur
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              color: Colors.black.withValues(alpha: 0.4),
            ),
          ),
          
          Center(
            child: Container(
              width: 400,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon Section
                  _buildStatusIcon(),
                  const SizedBox(height: 24),
                  
                  // Message
                  Text(
                    _isError ? 'Export Failed' : (_isCompleted ? 'Success!' : 'Generating Report'),
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isError ? (_errorMessage ?? 'Unknown error occurred') : _currentProgress.message,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Progress Section
                  if (!_isError && !_isCompleted) ...[
                    _buildProgressBar(),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(_currentProgress.value * 100).toInt()}% Completed',
                          style: GoogleFonts.outfit(fontSize: 12, color: Colors.white70),
                        ),
                        Text(
                          'Est. Time: ${_getRemainingTime()}',
                          style: GoogleFonts.outfit(fontSize: 12, color: Colors.white70),
                        ),
                      ],
                    ),
                  ],

                  if (_isCompleted || _isError) ...[
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: widget.onDismiss,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isError ? Colors.redAccent : Colors.indigoAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: Text(
                        _isError ? 'Try Again' : 'Done',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    if (_isError) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
      );
    }
    
    if (_isCompleted) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 48),
      );
    }

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.indigoAccent.withValues(alpha: 0.2 + (0.1 * _pulseController.value)),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.indigoAccent.withValues(alpha: 0.3 * _pulseController.value),
                blurRadius: 20 * _pulseController.value,
                spreadRadius: 5 * _pulseController.value,
              )
            ],
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.indigoAccent, size: 48),
        );
      },
    );
  }

  Widget _buildProgressBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Container(
              height: 12,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 12,
              width: constraints.maxWidth * _currentProgress.value,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.indigoAccent, Colors.cyanAccent],
                ),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.indigoAccent.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
            ),
          ],
        );
      }
    );
  }
}

class ExportProgress {
  final double value; // 0.0 to 1.0
  final String message;

  ExportProgress(this.value, this.message);
}
