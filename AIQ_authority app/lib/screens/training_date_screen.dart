import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'training_images_screen.dart';

class TrainingDateScreen extends StatelessWidget {
  final String folderName;
  const TrainingDateScreen({super.key, required this.folderName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(folderName, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('training_data')
            .where('folder_name', isEqualTo: folderName)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No dates available', style: TextStyle(color: Colors.white54)));
          }

          final Set<String> dates = {};
          for (var doc in snapshot.data!.docs) {
            dates.add(doc['date'] as String);
          }

          final dateList = dates.toList()..sort((a, b) => b.compareTo(a));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: dateList.length,
            itemBuilder: (context, index) {
              final date = dateList[index];
              return Card(
                color: const Color(0xFF1E293B),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: const Icon(Icons.calendar_today, color: Colors.blueAccent, size: 28),
                  title: Text(date, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => TrainingImagesScreen(folderName: folderName, date: date)));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
