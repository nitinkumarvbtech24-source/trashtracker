import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/role_service.dart';
import 'comnd_list_screen.dart';

class ComndScreen extends StatefulWidget {
  const ComndScreen({super.key});

  @override
  State<ComndScreen> createState() => _ComndScreenState();
}

class _ComndScreenState extends State<ComndScreen> {
  final MapController _mapController = MapController();
  List<Map<String, dynamic>> _complaints = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchComplaints();
  }

  Future<void> _fetchComplaints() async {
    final allowedZones = RoleService.getAllowedZonesForModule('COM&D');
    final allowedWards = RoleService.getAllowedWardsForModule('COM&D');
    final hasAllAccess = RoleService.hasAllAccess('COM&D');

    try {
      final snapshot = await FirebaseFirestore.instance.collection('trash_spots').get();
      List<Map<String, dynamic>> filtered = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        final docZone = data['zone'] ?? '';
        final docWard = data['ward'] ?? '';

        bool hasAccess = hasAllAccess;
        if (!hasAccess && allowedZones.isNotEmpty) {
          if (allowedZones.contains(docZone)) hasAccess = true;
        }
        if (!hasAccess && allowedWards.isNotEmpty) {
          if (allowedWards.contains(docWard)) hasAccess = true;
        }

        if (hasAccess) {
          filtered.add(data);
        }
      }

      if (mounted) {
        setState(() {
          _complaints = filtered;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching complaints: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildSummaryCard(String title, String count, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  count,
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int totalComplaints = _complaints.length;
    final int activeComplaints = _complaints.where((c) => c['status'] != 'Deflagged').length;
    final int deflaggedComplaints = _complaints.where((c) => c['status'] == 'Deflagged').length;

    return Column(
      children: [
        // Summary Cards Section
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              _buildSummaryCard('Total Complaints', totalComplaints.toString(), LucideIcons.list, const Color(0xFF3B82F6)),
              const SizedBox(width: 16),
              _buildSummaryCard('Pending / Active', activeComplaints.toString(), LucideIcons.alertTriangle, const Color(0xFFF59E0B)),
              const SizedBox(width: 16),
              _buildSummaryCard('Deflagged / Cleaned', deflaggedComplaints.toString(), LucideIcons.checkCircle, const Color(0xFF10B981)),
            ],
          ),
        ),
        
        // Map Section
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: const LatLng(13.003, 77.564), // Default Bangalore
                      initialZoom: 12,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                        subdomains: const ['a', 'b', 'c'],
                      ),
                      MarkerLayer(
                        markers: _complaints.map<Marker>((c) {
                          final lat = (c['lat'] ?? 0.0).toDouble();
                          final lng = (c['lng'] ?? 0.0).toDouble();
                          final status = c['status'] ?? 'Flagged';
                          
                          return Marker(
                            point: LatLng(lat, lng),
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.location_on,
                              color: status == 'Deflagged' ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              size: 40,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                  
                  // Action Button overlay
                  Positioned(
                    top: 16,
                    right: 16,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const ComndListScreen()));
                      },
                      icon: const Icon(LucideIcons.list, size: 18),
                      label: const Text('View Complaints List'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F5132),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  
                  if (_isLoading)
                    Container(
                      color: Colors.white.withOpacity(0.7),
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
