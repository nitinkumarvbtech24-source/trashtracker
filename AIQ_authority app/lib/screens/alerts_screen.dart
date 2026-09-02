import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../constants.dart';
import '../models/vehicle.dart';
import '../widgets/ngrok_image.dart';
import 'cleanliness_screen.dart';
import '../models/garbage_flag.dart';

class AlertsListScreen extends StatefulWidget {
  const AlertsListScreen({super.key});

  @override
  State<AlertsListScreen> createState() => _AlertsListScreenState();
}

class _AlertsListScreenState extends State<AlertsListScreen> {
  List<Vehicle> _vehicles = [];
  Map<String, GarbageFlag> _latestAlerts = {};

  @override
  void initState() {
    super.initState();
    _fetchVehiclesAndAlerts();
  }

  void _fetchVehiclesAndAlerts() {
    // 1. Fetch Vehicles
    FirebaseFirestore.instance.collection('vehicles').snapshots().listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _vehicles = snapshot.docs.map((doc) => Vehicle.fromJson(doc.id, doc.data())).toList();
      });
    });

    // 2. Fetch Latest Alerts for each vehicle
    FirebaseFirestore.instance.collection('trash_spots').snapshots().listen((snapshot) {
      if (!mounted) return;
      final flags = snapshot.docs
          .map((doc) => GarbageFlag.fromJson(doc.data(), doc.id))
          .where((f) => f.status != 'Resolved' && (f.className == 'Very_Dirty' || f.className == 'Slightly_Dirty' || f.displayClass == 'Very Dirty' || f.displayClass == 'Slightly Dirty'))
          .toList();

      Map<String, GarbageFlag> latest = {};
      for (var flag in flags) {
        if (!latest.containsKey(flag.vehicleNumber)) {
          latest[flag.vehicleNumber] = flag;
        } else {
          // Compare timestamps
          DateTime existing = DateTime.parse(latest[flag.vehicleNumber]!.timestamp);
          DateTime current = DateTime.parse(flag.timestamp);
          if (current.isAfter(existing)) {
            latest[flag.vehicleNumber] = flag;
          }
        }
      }
      
      setState(() {
        _latestAlerts = latest;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        title: const Text('Alerts Inbox', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _vehicles.isEmpty 
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _vehicles.length,
              itemBuilder: (context, index) {
                final vehicle = _vehicles[index];
                final latestAlert = _latestAlerts[vehicle.vehicleNumber];

                return InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AlertChatScreen(vehicle: vehicle),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: const Color(0xFF1E293B),
                          child: Text(
                            vehicle.vehicleNumber.isNotEmpty ? vehicle.vehicleNumber.substring(0, 2).toUpperCase() : 'V',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    vehicle.vehicleNumber,
                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  if (latestAlert != null)
                                    Text(
                                      _formatTime(latestAlert.timestamp),
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (latestAlert != null)
                                Row(
                                  children: [
                                    Icon(
                                      latestAlert.className == 'Clean' ? LucideIcons.checkCircle : LucideIcons.alertCircle,
                                      size: 14,
                                      color: latestAlert.className == 'Clean' ? Colors.greenAccent : Colors.redAccent,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Sent a new alert: ${latestAlert.displayClass}',
                                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                const Text(
                                  'No active alerts.',
                                  style: TextStyle(color: Colors.white54, fontSize: 13),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (latestAlert != null && latestAlert.className != 'Clean')
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                          )
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

class AlertChatScreen extends StatefulWidget {
  final Vehicle vehicle;

  const AlertChatScreen({super.key, required this.vehicle});

  @override
  State<AlertChatScreen> createState() => _AlertChatScreenState();
}

class _AlertChatScreenState extends State<AlertChatScreen> {
  List<GarbageFlag> _alerts = [];

  @override
  void initState() {
    super.initState();
    _fetchVehicleAlerts();
  }

  void _fetchVehicleAlerts() {
    FirebaseFirestore.instance
        .collection('trash_spots')
        .where('vehicle_number', isEqualTo: widget.vehicle.vehicleNumber)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final flags = snapshot.docs
          .map((doc) => GarbageFlag.fromJson(doc.data(), doc.id))
          .toList();
      
      flags.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      setState(() {
        _alerts = flags;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 1,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF1E293B),
              child: Text(
                widget.vehicle.vehicleNumber.isNotEmpty ? widget.vehicle.vehicleNumber.substring(0, 2).toUpperCase() : 'V',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.vehicle.vehicleNumber, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Active Route', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
              ],
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _alerts.isEmpty
          ? const Center(child: Text("No alerts for this vehicle.", style: TextStyle(color: Colors.white54)))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              itemCount: _alerts.length,
              itemBuilder: (context, index) {
                return _buildChatBubble(_alerts[index]);
              },
            ),
    );
  }

  Widget _buildChatBubble(GarbageFlag flag) {
    final isClean = flag.className == 'Clean';
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFF1E293B),
            child: const Icon(LucideIcons.bot, size: 14, color: Colors.white54),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                      bottomLeft: Radius.circular(4),
                    ),
                    border: Border.all(color: const Color(0xFF334155), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: double.maxFinite,
                          child: NgrokImage(
                            url: flag.imageUrl,
                            height: 180,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            isClean ? LucideIcons.checkCircle : LucideIcons.alertTriangle,
                            color: isClean ? Colors.greenAccent : Colors.redAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            flag.displayClass,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Confidence: ${(flag.confidence * 100).toStringAsFixed(1)}% • ${flag.ward}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    _formatTime(flag.timestamp),
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 40), // Pad right side so bubble doesn't stretch completely
        ],
      ),
    );
  }
  
  String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
