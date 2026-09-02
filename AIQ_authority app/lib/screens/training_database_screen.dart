import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'training_date_screen.dart';

class TrainingDatabaseScreen extends StatelessWidget {
  const TrainingDatabaseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text('Training Database', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('training_data').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No training data available', style: TextStyle(color: Colors.white54)));
          }

          final Set<String> folders = {};
          for (var doc in snapshot.data!.docs) {
            folders.add(doc['folder_name'] as String);
          }

          final folderList = folders.toList()..sort();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: folderList.length,
            itemBuilder: (context, index) {
              final folder = folderList[index];
              return Card(
                color: const Color(0xFF1E293B),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: const Icon(Icons.folder, color: Colors.orangeAccent, size: 32),
                  title: Text(folder, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => TrainingDateScreen(folderName: folder)));
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
