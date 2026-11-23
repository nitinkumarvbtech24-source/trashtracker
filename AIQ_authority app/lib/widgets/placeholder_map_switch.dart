import 'package:flutter/material.dart';

/// PlaceholderMapSwitch is hidden for the time being as requested.
/// Returns an empty SizedBox so all caller layouts continue to work without layout shifts.
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
    return const SizedBox.shrink();
  }
}
