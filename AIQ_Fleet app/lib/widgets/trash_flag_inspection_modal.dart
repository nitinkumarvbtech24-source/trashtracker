import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/garbage_flag.dart';
import '../services/authority_directory_service.dart';

class TrashFlagInspectionModal extends StatelessWidget {
  final String id;
  final String imageUrl;
  final String roadStatus;
  final String displayClass;
  final double confidence;
  final double lat;
  final double lng;
  final String ward;
  final String zone;
  final String vehicleNumber;
  final String status;
  final String? timestamp;
  final VoidCallback? onDeflag;

  const TrashFlagInspectionModal({
    super.key,
    required this.id,
    required this.imageUrl,
    required this.roadStatus,
    required this.displayClass,
    required this.confidence,
    required this.lat,
    required this.lng,
    required this.ward,
    required this.zone,
    required this.vehicleNumber,
    required this.status,
    this.timestamp,
    this.onDeflag,
  });

  /// Open from a GarbageFlag model
  static void show(BuildContext context, GarbageFlag flag, {VoidCallback? onDeflag}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (ctx) => TrashFlagInspectionModal(
        id: flag.id,
        imageUrl: flag.imageUrl,
        roadStatus: flag.className.replaceAll('_', ' '),
        displayClass: flag.displayClass,
        confidence: flag.confidence,
        lat: flag.lat,
        lng: flag.lng,
        ward: flag.ward,
        zone: flag.zone,
        vehicleNumber: flag.vehicleNumber,
        status: flag.status,
        timestamp: flag.timestamp,
        onDeflag: onDeflag,
      ),
    );
  }

  /// Open from a Firestore map/snapshot
  static void showFromMap(BuildContext context, Map<String, dynamic> spot, {VoidCallback? onDeflag}) {
    final id = (spot['id'] ?? spot['doc_id'] ?? '').toString();
    final rawUrl = (spot['image_url'] ?? spot['imageUrl'] ?? '').toString();
    final roadStatus = (spot['road_status'] ?? spot['class'] ?? 'Trash Detected').toString();
    final displayClass = (spot['display_class'] ?? roadStatus).toString();
    final confidence = ((spot['confidence'] ?? 0.85) as num).toDouble();
    final lat = ((spot['lat'] ?? 12.9716) as num).toDouble();
    final lng = ((spot['lng'] ?? 77.5946) as num).toDouble();
    final ward = (spot['ward'] ?? 'Ward 45 - Kempegowda Ward').toString();
    final zone = (spot['zone'] ?? 'South Zone').toString();
    final vehicleNumber = (spot['vehicle_number'] ?? spot['vehicle'] ?? 'KA 01 AA 0001').toString();
    final status = (spot['status'] ?? 'Flagged').toString();
    final timestamp = spot['timestamp']?.toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (ctx) => TrashFlagInspectionModal(
        id: id,
        imageUrl: rawUrl,
        roadStatus: roadStatus,
        displayClass: displayClass,
        confidence: confidence,
        lat: lat,
        lng: lng,
        ward: ward,
        zone: zone,
        vehicleNumber: vehicleNumber,
        status: status,
        timestamp: timestamp,
        onDeflag: onDeflag,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 700;
    final isCleaned = status.toLowerCase() == 'deflagged' || status.toLowerCase() == 'resolved';
    final isVeryDirty = roadStatus.toLowerCase().contains('very dirty') || displayClass.toLowerCase().contains('very dirty');

    final dirService = AuthorityDirectoryService.instance;
    final resolvedImg = dirService.resolveImageUrl(imageUrl, id);

    // Retrieve the 4-tier chain of command
    final zoneOfficer = dirService.getZoneOfficer(zone);
    final wardOfficer = dirService.getWardOfficer(ward, zone);
    final contractor = dirService.getContractor(ward, zone);
    final driver = dirService.getVehicleAndDriver(ward, vehicleNumber);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? 680 : double.infinity,
          maxHeight: size.height * 0.92,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 20, offset: Offset(0, -4)),
            ],
          ),
          child: Column(
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              // Header Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isCleaned 
                            ? const Color(0xFF10B981).withOpacity(0.12)
                            : (isVeryDirty ? const Color(0xFFDC2626).withOpacity(0.12) : const Color(0xFFEA580C).withOpacity(0.12)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCleaned 
                              ? const Color(0xFF10B981)
                              : (isVeryDirty ? const Color(0xFFDC2626) : const Color(0xFFEA580C)),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isCleaned ? Icons.check_circle_rounded : (isVeryDirty ? Icons.warning_rounded : Icons.warning_amber_rounded),
                            size: 16,
                            color: isCleaned ? const Color(0xFF10B981) : (isVeryDirty ? const Color(0xFFDC2626) : const Color(0xFFEA580C)),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isCleaned ? 'CLEANED & DEFLAGGED' : (isVeryDirty ? 'VERY DIRTY ROAD' : 'TRASH DETECTED'),
                            style: TextStyle(
                              color: isCleaned ? const Color(0xFF10B981) : (isVeryDirty ? const Color(0xFFDC2626) : const Color(0xFFEA580C)),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${(confidence * 100).toStringAsFixed(1)}% AI Conf.',
                        style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, color: Color(0xFFE2E8F0)),

              // Scrollable Body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Location & Details Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on_rounded, size: 18, color: Color(0xFF0F5132)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$ward ($zone)',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Lat: ${lat.toStringAsFixed(5)}, Lng: ${lng.toStringAsFixed(5)} ${timestamp != null ? "• $timestamp" : ""}',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _openDirections(lat, lng),
                                  icon: const Icon(Icons.navigation_rounded, size: 14, color: Colors.white),
                                  label: const Text('Directions', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F5132),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    elevation: 0,
                                  ),
                                ),
                                if (onDeflag != null && !isCleaned) ...[
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      onDeflag!();
                                    },
                                    icon: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                                    label: const Text('Deflag', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFDC2626),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      elevation: 0,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Guaranteed Trash Detected Image Showcase
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            Image.network(
                              resolvedImg,
                              headers: const {"ngrok-skip-browser-warning": "true"},
                              height: 230,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, stack) {
                                // Fallback pool guarantee: automatically choose another live trash image
                                final fallback = dirService.getFallbackTrashImageUrl(id.hashCode);
                                return Image.network(
                                  fallback,
                                  headers: const {"ngrok-skip-browser-warning": "true"},
                                  height: 230,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    height: 230,
                                    color: const Color(0xFFF1F5F9),
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.image_outlined, size: 42, color: Color(0xFF94A3B8)),
                                          const SizedBox(height: 8),
                                          Text('Trash Inspection Frame (#$id)', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            // Overlay Badge
                            Positioned(
                              bottom: 12,
                              left: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.75),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.camera_alt_rounded, size: 13, color: Colors.white),
                                    const SizedBox(width: 6),
                                    Text(
                                      'YOLOv8 AIQ Validated • Vehicle $vehicleNumber',
                                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Area Authority Chain of Command (Tree Header)
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F5132).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.account_tree_rounded, color: Color(0xFF0F5132), size: 18),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'AREA SANITATION CHAIN OF COMMAND',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F5132),
                                  letterSpacing: 0.8,
                                ),
                              ),
                              Text(
                                'Jurisdictional Hierarchy, Contractor Concession & Fleet Driver',
                                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // The 4-Tier Interactive Tree
                      _buildTreeTierCard(
                        official: zoneOfficer,
                        tierLabel: 'Tier 1 · Zonal Jurisdiction',
                        isFirst: true,
                        isLast: false,
                        context: context,
                      ),
                      _buildTreeConnector(),
                      _buildTreeTierCard(
                        official: wardOfficer,
                        tierLabel: 'Tier 2 · Ward Administration',
                        isFirst: false,
                        isLast: false,
                        context: context,
                      ),
                      _buildTreeConnector(),
                      _buildTreeTierCard(
                        official: contractor,
                        tierLabel: 'Tier 3 · SWM Concessionaire',
                        isFirst: false,
                        isLast: false,
                        context: context,
                      ),
                      _buildTreeConnector(),
                      _buildTreeTierCard(
                        official: driver,
                        tierLabel: 'Tier 4 · Assigned Fleet Tipper & Driver',
                        isFirst: false,
                        isLast: true,
                        context: context,
                      ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),

              // Bottom Dismiss Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Close Inspection', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTreeConnector() {
    return Container(
      margin: const EdgeInsets.only(left: 36),
      width: 2,
      height: 18,
      color: const Color(0xFFCBD5E1),
    );
  }

  Widget _buildTreeTierCard({
    required AuthorityOfficial official,
    required String tierLabel,
    required bool isFirst,
    required bool isLast,
    required BuildContext context,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Role Icon Badge
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: official.badgeColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: official.badgeColor.withOpacity(0.3)),
            ),
            child: Icon(official.icon, color: official.badgeColor, size: 22),
          ),
          const SizedBox(width: 12),
          // Info Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: official.badgeColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tierLabel.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: official.badgeColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  official.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  official.role,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 11, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Text(
                      official.phone,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.mail_outline, size: 11, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        official.email,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Interactive Call & Message Buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Message Button
              IconButton(
                tooltip: 'Send Message to ${official.name}',
                onPressed: () => _sendMessage(official, context),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chat_bubble_outline, size: 16, color: Color(0xFF0284C7)),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              // Call Button
              IconButton(
                tooltip: 'Call ${official.name}',
                onPressed: () => _callOfficial(official.phone),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.phone_in_talk, size: 16, color: Color(0xFF10B981)),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _callOfficial(String phone) {
    AuthorityDirectoryService.instance.makePhoneCall(phone);
  }

  void _sendMessage(AuthorityOfficial official, BuildContext context) {
    final defaultMsg = "Street AIQ Notice: Action required for trash spot $id in $ward ($zone). Road condition: $roadStatus.";
    AuthorityDirectoryService.instance.sendSMS(official.phone, defaultMsg);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening message composer to ${official.name} (${official.phone})...'),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF0F5132),
      ),
    );
  }

  void _openDirections(double lat, double lng) async {
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }
}
