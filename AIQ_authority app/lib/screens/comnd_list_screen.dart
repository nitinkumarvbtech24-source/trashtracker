import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/role_service.dart';
import 'comnd_deflag_screen.dart';

class ComndListScreen extends StatefulWidget {
  const ComndListScreen({super.key});

  @override
  State<ComndListScreen> createState() => _ComndListScreenState();
}

class _ComndListScreenState extends State<ComndListScreen> {
  Future<void> _openMaps(double lat, double lng) async {
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open maps')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowedZones = RoleService.getAllowedZonesForModule('COM&D');
    final allowedWards = RoleService.getAllowedWardsForModule('COM&D');
    final hasAllAccess = RoleService.hasAllAccess('COM&D');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Complaints List', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F5132),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('trash_spots').where('status', isNotEqualTo: 'Deflagged').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];
          final filteredDocs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final docZone = data['zone'] ?? '';
            final docWard = data['ward'] ?? '';

            bool hasAccess = hasAllAccess;
            if (!hasAccess && allowedZones.isNotEmpty) {
              if (allowedZones.contains(docZone)) hasAccess = true;
            }
            if (!hasAccess && allowedWards.isNotEmpty) {
              if (allowedWards.contains(docWard)) hasAccess = true;
            }
            return hasAccess;
          }).toList();

          if (filteredDocs.isEmpty) {
            return const Center(child: Text('No active complaints found for your region.', style: TextStyle(fontSize: 16, color: Colors.grey)));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredDocs.length,
            itemBuilder: (context, index) {
              final doc = filteredDocs[index];
              final data = doc.data() as Map<String, dynamic>;
              final imageUrl = data['image_url'] ?? '';
              final lat = (data['lat'] ?? 0.0).toDouble();
              final lng = (data['lng'] ?? 0.0).toDouble();
              final status = data['status'] ?? 'Flagged';
              final ward = data['ward'] ?? 'Unknown Ward';
              final zone = data['zone'] ?? 'Unknown Zone';
              final timestamp = data['timestamp'] as Timestamp?;
              final dateStr = timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp.millisecondsSinceEpoch).toString().split('.')[0] : 'Unknown Time';

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (imageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        child: Image.network(
                          imageUrl,
                          height: 200,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 200,
                            color: Colors.grey[200],
                            child: const Icon(Icons.broken_image, color: Colors.grey, size: 50),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '$zone - $ward',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red[100],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  status,
                                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('Reported: $dateStr', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _openMaps(lat, lng),
                                  icon: const Icon(LucideIcons.navigation, size: 18),
                                  label: const Text('Directions'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF0F5132),
                                    side: const BorderSide(color: Color(0xFF0F5132)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ComndDeflagScreen(documentId: doc.id),
                                      ),
                                    );
                                  },
                                  icon: const Icon(LucideIcons.camera, size: 18),
                                  label: const Text('Deflag'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F5132),
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
