import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class TrainingImagesScreen extends StatelessWidget {
  final String folderName;
  final String date;

  const TrainingImagesScreen({super.key, required this.folderName, required this.date});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text('$folderName - $date', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('training_data')
            .where('folder_name', isEqualTo: folderName)
            .where('date', isEqualTo: date)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
             return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No images available', style: TextStyle(color: Colors.white54)));
          }

          final docs = snapshot.data!.docs.toList();
          docs.sort((a, b) {
            Timestamp tA = (a.data() as Map<String, dynamic>)['timestamp'] ?? Timestamp.now();
            Timestamp tB = (b.data() as Map<String, dynamic>)['timestamp'] ?? Timestamp.now();
            return tB.compareTo(tA);
          });

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.8,
            ),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final imageUrl = data['image_url'] ?? '';
              
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: const Color(0xFF1E293B),
                  child: imageUrl.isEmpty 
                    ? const Center(child: Icon(Icons.broken_image, color: Colors.white54))
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(child: CircularProgressIndicator());
                        },
                      ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
