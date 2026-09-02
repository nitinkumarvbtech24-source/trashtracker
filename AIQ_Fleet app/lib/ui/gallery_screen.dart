import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../constants.dart';

class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vehicleNo = context.watch<AuthService>().vehicleNumber;

    if (vehicleNo == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(title: const Text('Flags'), backgroundColor: const Color(0xFF111827)),
        body: const Center(child: Text('Not logged in', style: TextStyle(color: Colors.white))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text('Flags', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF111827),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('trash_spots')
            .where('vehicle_number', isEqualTo: vehicleNo)
            .where('status', isEqualTo: 'Flagged')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.blueAccent));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text(
                'No flags recorded yet.',
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 16),
              ),
            );
          }

          final docs = snapshot.data!.docs;

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.75,
            ),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final roadStatus = data['road_status'] ?? 'Unknown';
              final confidence = data['confidence'] ?? 0.0;
              final timestamp = data['timestamp'] as Timestamp?;
              
              String displayUrl = data['image_url'] ?? '';
              if (displayUrl.startsWith('http')) {
                try {
                  final uri = Uri.parse(displayUrl);
                  if (uri.host.contains('ngrok-free.dev')) {
                    displayUrl = '$GARBAGE_AI_URL${uri.path}';
                  }
                } catch (_) {}
              } else if (displayUrl.startsWith('/')) {
                displayUrl = '$GARBAGE_AI_URL$displayUrl';
              } else if (displayUrl.isNotEmpty) {
                displayUrl = '$GARBAGE_AI_URL/$displayUrl';
              }

              final isVeryDirty = roadStatus == 'Very Dirty Road';
              final color = isVeryDirty ? Colors.redAccent : Colors.orangeAccent;

              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withOpacity(0.5), width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                        child: displayUrl.isNotEmpty
                            ? Image.network(
                                displayUrl,
                                headers: const {"ngrok-skip-browser-warning": "true"},
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white24, size: 40),
                              )
                            : const Icon(Icons.image_not_supported, color: Colors.white24, size: 40),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            roadStatus,
                            style: GoogleFonts.outfit(color: color, fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Confidence: ${(confidence * 100).toStringAsFixed(1)}%",
                            style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            timestamp != null ? _formatTimestamp(timestamp.toDate()) : 'Unknown Time',
                            style: GoogleFonts.inter(color: Colors.white54, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }
}
