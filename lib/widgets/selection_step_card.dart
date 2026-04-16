import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SelectionStepCard extends StatelessWidget {
  final String title;
  final String? value;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;
  final bool isLocked;
  final bool isLoading;

  const SelectionStepCard({
    super.key,
    required this.title,
    this.value,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    this.isLocked = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasValue = value != null && value!.isNotEmpty;

    return MouseRegion(
      cursor: (isLocked || isLoading) ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: (isLocked || isLoading) ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isLocked ? Colors.grey[50] : Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isLocked ? Colors.grey[200]! : (hasValue ? accentColor.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.4)),
              width: 1.5,
            ),
            boxShadow: [
              if (!isLocked)
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isLocked ? Colors.grey[200] : accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isLoading 
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: accentColor))
                  : Icon(icon, color: isLocked ? Colors.grey[500] : accentColor, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value ?? 'Tap to select',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        color: hasValue ? const Color(0xFF1B1F3B) : Colors.grey[400],
                        fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!isLocked && !isLoading)
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.grey[300],
                  size: 14,
                ),
              if (isLocked)
                Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.grey[400],
                  size: 14,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
