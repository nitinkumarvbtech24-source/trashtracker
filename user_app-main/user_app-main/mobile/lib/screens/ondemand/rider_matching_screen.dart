import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;
import '../../core/theme/app_theme.dart';

class RiderMatchingScreen extends StatefulWidget {
  const RiderMatchingScreen({super.key});

  @override
  State<RiderMatchingScreen> createState() => _RiderMatchingScreenState();
}

class _RiderMatchingScreenState extends State<RiderMatchingScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;
  
  bool _riderFound = false;

  @override
  void initState() {
    super.initState();
    
    // Radar Pulse Animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Slide up animation for Rider Found Card
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutQuart),
    );

    _simulateMatching();
  }

  Future<void> _simulateMatching() async {
    // Simulate searching for 3 seconds
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    
    setState(() => _riderFound = true);
    _slideController.forward();

    // Wait 2 seconds on the assigned card before going to live tracking
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    
    context.go('/tracking_live');
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background Mock Map Pattern
          Positioned.fill(
            child: Opacity(
              opacity: 0.05,
              child: CustomPaint(painter: _MockMapPainter()),
            ),
          ),
          
          // Radar Animation
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _RadarPainter(_pulseController.value),
                      size: const Size(300, 300),
                    );
                  },
                ),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10)),
                    ],
                  ),
                  child: const Icon(Icons.location_on, color: AppColors.primary, size: 40),
                ),
              ],
            ),
          ),

          // Searching Text (Top)
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  _riderFound ? 'Rider Found' : 'Finding a nearby rider...',
                  style: const TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _riderFound ? 'Preparing to navigate' : 'Looking for the closest available collection partner.',
                  style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 14, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),

          // Rider Found Bottom Sheet
          if (_riderFound)
            AnimatedBuilder(
              animation: _slideAnimation,
              builder: (context, child) {
                return Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Transform.translate(
                    offset: Offset(0, _slideAnimation.value * 300),
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 30, offset: const Offset(0, -10)),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Your pickup partner', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: const Icon(Icons.local_shipping, color: AppColors.primary, size: 32),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Arun Kumar', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: const [
                                        Icon(Icons.star, color: AppColors.warning, size: 16),
                                        SizedBox(width: 4),
                                        Text('4.8', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                        SizedBox(width: 8),
                                        Text('• 245 pickups', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 13, color: AppColors.textSecondary)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text('Vehicle', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 12, color: AppColors.textSecondary)),
                                    SizedBox(height: 2),
                                    Text('Mini Tipper', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                                  child: const Text('KA 01 AB 1234', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;

  _RadarPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    final paint1 = Paint()
      ..color = AppColors.primary.withOpacity((1 - progress) * 0.5)
      ..style = PaintingStyle.fill;

    final paint2 = Paint()
      ..color = AppColors.primary.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, maxRadius * progress, paint1);
    canvas.drawCircle(center, maxRadius * progress, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _MockMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw some random grid lines to look like a map
    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
