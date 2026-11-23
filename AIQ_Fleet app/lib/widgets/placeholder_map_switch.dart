import 'package:flutter/material.dart';

/// PlaceholderMapSwitch is hidden for the time being as requested.
/// Returns an empty SizedBox so all caller layouts continue to work without layout shifts.
class PlaceholderMapSwitch extends StatelessWidget {
  final bool showPlaceholders;
  final int realCount;
  final int totalCount;
  final ValueChanged<bool> onChanged;

  const PlaceholderMapSwitch({
    super.key,
    required this.showPlaceholders,
    required this.realCount,
    required this.totalCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
