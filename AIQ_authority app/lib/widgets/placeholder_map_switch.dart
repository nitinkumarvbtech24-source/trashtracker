import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/trash_spots_service.dart';

/// Reusable switch control for maps to toggle between showing placeholder flags and real flags only.
class PlaceholderMapSwitch extends StatelessWidget {
  final bool isDark;
  final bool compact;

  const PlaceholderMapSwitch({
    super.key,
    this.isDark = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<dynamic>>(
      valueListenable: TrashSpotsService.instance.flagsNotifier,
      builder: (context, flags, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: TrashSpotsService.instance.showPlaceholdersNotifier,
          builder: (context, showPlaceholders, _) {
            final realCount = TrashSpotsService.instance.realFlagsCount;
            final totalCount = TrashSpotsService.instance.allTrashFlagsCount;
            final activeCount = showPlaceholders ? totalCount : realCount;

            final accentColor = showPlaceholders ? const Color(0xFFF59E0B) : const Color(0xFF10B981);
            final bgColor = isDark
                ? const Color(0xFF0F172A).withValues(alpha: 0.92)
                : Colors.white.withValues(alpha: 0.96);
            final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

            return Tooltip(
              message: showPlaceholders
                  ? 'Showing all flags (Placeholders + Real Detections). Click to show Real Flags Only.'
                  : 'Showing Real Flags Only. Click to include Placeholders.',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => TrashSpotsService.instance.toggleShowPlaceholders(),
                  borderRadius: BorderRadius.circular(24),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 8 : 12,
                      vertical: compact ? 3 : 5,
                    ),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: accentColor.withValues(alpha: 0.7), width: 1.5),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          showPlaceholders ? Icons.flag_rounded : Icons.verified_rounded,
                          size: compact ? 14 : 16,
                          color: accentColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          showPlaceholders ? 'Placeholders (All)' : 'Real Flags Only',
                          style: GoogleFonts.inter(
                            color: textColor,
                            fontSize: compact ? 10 : 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 1),
                          ),
                          child: Text(
                            '$activeCount',
                            style: GoogleFonts.inter(
                              color: accentColor,
                              fontSize: compact ? 9 : 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Transform.scale(
                          scale: compact ? 0.65 : 0.75,
                          child: Switch(
                            value: showPlaceholders,
                            activeColor: const Color(0xFFF59E0B),
                            activeTrackColor: const Color(0xFF78350F),
                            inactiveThumbColor: const Color(0xFF10B981),
                            inactiveTrackColor: const Color(0xFF064E3B),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            onChanged: (val) {
                              TrashSpotsService.instance.setShowPlaceholders(val);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
