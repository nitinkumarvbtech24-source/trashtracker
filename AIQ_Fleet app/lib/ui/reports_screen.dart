import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'package:intl/intl.dart';
import 'trip_map_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}
class _ReportsScreenState extends State<ReportsScreen> {
  @override
  Widget build(BuildContext context) {
    final vehicleNo = context.watch<AuthService>().vehicleNumber;

    if (vehicleNo == null || vehicleNo.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF020617),
        body: Center(
          child: Text('Not logged in', style: GoogleFonts.outfit(color: Colors.white)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Trip Reports', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('vehicles')
            .doc(vehicleNo)
            .collection('trips')
            .orderBy('startTime', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.blueAccent));
          }

          final docs = snapshot.data?.docs ?? [];
          
          double totalKms = 0;
          int totalFlags = 0;
          
          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            totalKms += (data['distanceKm'] as num?)?.toDouble() ?? 0.0;
            totalFlags += (data['flags'] as num?)?.toInt() ?? 0;
          }

          return Column(
            children: [
              // Top Stats Cards
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(child: _buildStatCard('Total KMs', '${totalKms.toStringAsFixed(1)} km', Icons.route_outlined, Colors.blueAccent)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard('Flags', '$totalFlags', Icons.tour_outlined, Colors.orangeAccent)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard('Trips', '${docs.length}', Icons.local_shipping_outlined, Colors.greenAccent)),
                  ],
                ),
              ),
              
              const Divider(color: Colors.white12, height: 1),
              
              // Bottom Trips List
              Expanded(
                child: docs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.history_rounded, size: 64, color: Colors.white24),
                          const SizedBox(height: 16),
                          Text('No trips recorded.', style: GoogleFonts.inter(color: Colors.white54, fontSize: 16)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final distanceKm = (data['distanceKm'] as num?)?.toDouble() ?? 0.0;
                        final flags = (data['flags'] as num?)?.toInt() ?? 0;
                        final startTimeStr = data['startTime'] as String?;
                        final endTimeStr = data['endTime'] as String?;
                        
                        DateTime? stTime;
                        DateTime? enTime;
                        if (startTimeStr != null) stTime = DateTime.tryParse(startTimeStr);
                        if (endTimeStr != null) enTime = DateTime.tryParse(endTimeStr);
                        
                        final timeFormat = DateFormat('hh:mm a');
                        
                        String durationStr = "In Progress";
                        if (stTime != null && enTime != null) {
                          final dur = enTime.difference(stTime);
                          final hours = dur.inHours;
                          final mins = dur.inMinutes.remainder(60);
                          if (hours > 0) {
                            durationStr = "${hours}h ${mins}m";
                          } else {
                            durationStr = "${mins}m";
                          }
                        }

                        return GestureDetector(
                          onTap: () {
                            if (data['date'] != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => TripMapScreen(
                                    vehicleNo: vehicleNo,
                                    date: data['date'],
                                    startTime: stTime,
                                    endTime: enTime,
                                  ),
                                ),
                              );
                            }
                          },
                          child: Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.greenAccent.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.play_circle_outline, color: Colors.greenAccent, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        stTime != null ? timeFormat.format(stTime) : 'Unknown',
                                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  const Icon(Icons.arrow_forward_rounded, color: Colors.white38, size: 20),
                                  Row(
                                    children: [
                                      Text(
                                        enTime != null ? timeFormat.format(enTime) : 'Ongoing',
                                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: enTime != null ? Colors.redAccent.withOpacity(0.1) : Colors.blueAccent.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(enTime != null ? Icons.stop_circle_outlined : Icons.sync, color: enTime != null ? Colors.redAccent : Colors.blueAccent, size: 20),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildTripDetail('Duration', durationStr, Icons.timer_outlined, Colors.white70),
                                  _buildTripDetail('Distance', '${distanceKm.toStringAsFixed(2)} km', Icons.route_outlined, Colors.blueAccent),
                                  _buildTripDetail('Flags', '$flags', Icons.tour_outlined, Colors.orangeAccent),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                      },
                    ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(title, style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTripDetail(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
            Text(value, style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }
}
