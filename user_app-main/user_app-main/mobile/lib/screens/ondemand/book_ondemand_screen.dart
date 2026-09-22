import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

class BookOndemandScreen extends StatefulWidget {
  const BookOndemandScreen({super.key});

  @override
  State<BookOndemandScreen> createState() => _BookOndemandScreenState();
}

class _BookOndemandScreenState extends State<BookOndemandScreen> {
  final Set<String> _selectedCategories = {};
  String? _selectedQuantity;
  int _baseFare = 0;
  bool _isLoading = false;

  final List<Map<String, dynamic>> _categories = [
    {'id': 'household', 'label': 'Household Waste', 'icon': '🗑'},
    {'id': 'dry', 'label': 'Dry Waste', 'icon': '♻'},
    {'id': 'bulk', 'label': 'Bulk Waste', 'icon': '📦'},
    {'id': 'garden', 'label': 'Garden Waste', 'icon': '🌿'},
    {'id': 'other', 'label': 'Other', 'icon': '⚠'},
  ];

  final List<Map<String, dynamic>> _quantities = [
    {'id': 'small', 'label': 'Small', 'desc': 'Up to 5 kg', 'price': 29},
    {'id': 'medium', 'label': 'Medium', 'desc': '5–15 kg', 'price': 49},
    {'id': 'large', 'label': 'Large', 'desc': '15–30 kg', 'price': 79},
    {'id': 'xl', 'label': 'Extra Large', 'desc': '30+ kg', 'price': 0},
  ];

  void _toggleCategory(String id) {
    setState(() {
      if (_selectedCategories.contains(id)) {
        _selectedCategories.remove(id);
      } else {
        _selectedCategories.add(id);
      }
      _calculateFare();
    });
  }

  void _selectQuantity(String id) {
    setState(() {
      _selectedQuantity = id;
      _calculateFare();
    });
  }

  void _calculateFare() {
    if (_selectedQuantity == null) {
      _baseFare = 0;
      return;
    }
    
    final qty = _quantities.firstWhere((q) => q['id'] == _selectedQuantity);
    if (qty['price'] == 0) {
      _baseFare = 0; // Dynamic pricing
      return;
    }

    _baseFare = (qty['price'] as int) + (_selectedCategories.length > 1 ? 10 : 0);
  }

  void _confirmBooking() async {
    if (_selectedCategories.isEmpty || _selectedQuantity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select waste type and quantity.', style: TextStyle(fontFamily: 'Plus Jakarta Sans'))),
      );
      return;
    }

    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 1)); // Simulate processing
    setState(() => _isLoading = false);

    if (!mounted) return;
    context.push('/matching');
  }

  @override
  Widget build(BuildContext context) {
    final estimatedTotal = _baseFare > 0 ? _baseFare + 15 : null; // +10 handling + 5 service

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: AppColors.textPrimary),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
        title: const Text(
          'Book a Pickup',
          style: TextStyle(fontFamily: 'Plus Jakarta Sans', color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(left: 24, right: 24, top: 8, bottom: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                            child: const Icon(Icons.local_shipping, color: Colors.white, size: 32),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text('Doorstep Collection', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                SizedBox(height: 4),
                                Text('Fast • Affordable • Tracked', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 13, color: Colors.white70)),
                                SizedBox(height: 4),
                                Text('Starting from ₹29', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // 1. Waste Category
                    const Text('What would you like us to collect?', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: _categories.map((cat) {
                        final isSelected = _selectedCategories.contains(cat['id']);
                        return GestureDetector(
                          onTap: () => _toggleCategory(cat['id']),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primary.withOpacity(0.1) : AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: 2),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(cat['icon'], style: const TextStyle(fontSize: 16)),
                                const SizedBox(width: 8),
                                Text(
                                  cat['label'],
                                  style: TextStyle(
                                    fontFamily: 'Plus Jakarta Sans',
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 32),

                    // 2. Quantity
                    const Text('How much waste do you have?', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.8,
                      ),
                      itemCount: _quantities.length,
                      itemBuilder: (context, index) {
                        final qty = _quantities[index];
                        final isSelected = _selectedQuantity == qty['id'];
                        return GestureDetector(
                          onTap: () => _selectQuantity(qty['id']),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primary.withOpacity(0.1) : AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: 2),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  qty['label'],
                                  style: TextStyle(
                                    fontFamily: 'Plus Jakarta Sans',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  qty['desc'],
                                  style: TextStyle(
                                    fontFamily: 'Plus Jakarta Sans',
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  qty['price'] > 0 ? '₹${qty['price']}' : 'Calculated later',
                                  style: TextStyle(
                                    fontFamily: 'Plus Jakarta Sans',
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text('Final price may vary depending on waste type and quantity.', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 11, color: AppColors.textMuted)),
                    const SizedBox(height: 32),

                    // 3. Optional Photo
                    const Text('Add a photo (Optional)', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    const Text('Help the rider understand what needs to be collected.', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border, style: BorderStyle.solid),
                      ),
                      child: Column(
                        children: const [
                          Icon(Icons.add_a_photo, color: AppColors.textSecondary, size: 28),
                          SizedBox(height: 8),
                          Text('+ Add Photo', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // 4. Pickup Location
                    const Text('Pickup Location', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.location_on, color: AppColors.primary),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text('Current Location', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                                SizedBox(height: 2),
                                Text('12 Example Street, Bengaluru', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 15, color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () {},
                            child: const Text('Change', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // 5. Instructions
                    const Text('Instructions for rider', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 16),
                    TextField(
                      maxLines: 2,
                      maxLength: 300,
                      decoration: InputDecoration(
                        hintText: 'Example: Call me when you arrive, gate is beside the pharmacy...',
                        hintStyle: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 13, color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // 6. Pickup Time
                    const Text('Pickup Time', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.primary, width: 2),
                            ),
                            child: Column(
                              children: const [
                                Text('ASAP', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 16)),
                                SizedBox(height: 4),
                                Text('Usually 10–20 min', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 12, color: AppColors.primary)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              children: const [
                                Text('Schedule', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 16)),
                                SizedBox(height: 4),
                                Text('For later', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 12, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 80), // Extra padding for bottom sticky header
                  ],
                ),
              ),
            ),
            
            // 7. Sticky Bottom Pricing & Confirm
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5)),
                ],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Estimated Fare', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(estimatedTotal != null ? '₹$estimatedTotal' : 'To be calculated', style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5)),
                        ],
                      ),
                      const Text('No hidden charges', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 12, color: AppColors.success, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _confirmBooking,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: _isLoading 
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Confirm & Find Rider', style: TextStyle(fontFamily: 'Plus Jakarta Sans', fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
