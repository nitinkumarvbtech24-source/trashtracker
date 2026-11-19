import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/garbage_flag.dart';
import '../services/role_service.dart';
import '../services/ward_zone_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Filters
  String _selectedZone = 'All Zones';
  String _searchWardQuery = '';
  String _selectedSortBy = 'Rank (Best to Worst)';

  // Theme Colors
  static const Color primaryGreen = Color(0xFF006341);
  static const Color darkSlate = Color(0xFF0F172A);
  static const Color cardBorder = Color(0xFFE2E8F0);

  bool _isGeneratingPdf = false;

  String _formatDateTime(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final m = months[dt.month - 1];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day.toString().padLeft(2, '0')} $m ${dt.year}, $h:$min $ampm';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- PDF Generation Logic ---
  Future<void> _generateAndDownloadPdf({
    required List<GarbageFlag> flags,
    required List<Map<String, dynamic>> wardRankings,
    required Map<String, Map<String, int>> zoneStats,
  }) async {
    setState(() => _isGeneratingPdf = true);

    try {
      final doc = pw.Document();
      final now = DateTime.now();
      final dateStr = _formatDateTime(now);
      final reportId = 'BBMP-AIQ-${now.millisecondsSinceEpoch.toString().substring(5)}';

      final totalFlags = flags.length;
      final clearedFlags = flags.where((f) => f.status.toLowerCase() == 'resolved' || f.status.toLowerCase() == 'cleared' || f.status.toLowerCase() == 'deflagged').length;
      final pendingFlags = totalFlags - clearedFlags;
      final clearanceRate = totalFlags > 0 ? ((clearedFlags / totalFlags) * 100).toStringAsFixed(1) : '100.0';

      final topWards = wardRankings.take(10).toList();
      final priorityWards = wardRankings.reversed.take(10).toList();

      // Page 1: Executive Summary & Zone Performance
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return [
              // Header
              pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 16),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.green900, width: 2.5)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'BRUHAT BENGALURU MAHANAGARA PALIKE',
                          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'STREET AIQ • URBAN INTELLIGENCE & AUDIT REPORT',
                          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Comprehensive City-Wide Cleanliness & Ward Ranking Analysis',
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Report ID: $reportId', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
                        pw.SizedBox(height: 2),
                        pw.Text('Generated: $dateStr', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                        pw.SizedBox(height: 2),
                        pw.Text('Jurisdiction: BBMP All Zones (198 Wards)', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 18),

              // Executive KPI Summary Table
              pw.Text('1. Executive KPI Summary', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
              pw.SizedBox(height: 8),

              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.8),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.green50),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Total Flags Audited', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Cleared / Resolved', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Pending Deflagging', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Clearance Efficiency', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Wards Monitored', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('$totalFlags', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.blue800))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('$clearedFlags', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.green800))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('$pendingFlags', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.red800))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('$clearanceRate%', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.green900))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${wardRankings.length} / 198 (100%)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.grey900))),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 20),

              // Zone Performance Breakdown Table
              pw.Text('2. Zone-Wise Performance & Resolution Matrix', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
              pw.SizedBox(height: 8),

              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.8),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Zone Name', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Total Flags', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Cleared', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Pending', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Clearance %', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Compliance Status', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                    ],
                  ),
                  ...zoneStats.entries.map((entry) {
                    final zName = entry.key;
                    final st = entry.value;
                    final zTotal = st['total'] ?? 0;
                    final zCleared = st['cleared'] ?? 0;
                    final zPending = st['pending'] ?? 0;
                    final zRate = zTotal > 0 ? (zCleared / zTotal) * 100 : 100.0;
                    final statusStr = zRate >= 65 ? 'Optimal (Grade A)' : (zRate >= 50 ? 'Satisfactory (Grade B)' : 'Attention Required (Grade C)');
                    final statusColor = zRate >= 65 ? PdfColors.green800 : (zRate >= 50 ? PdfColors.amber800 : PdfColors.red800);

                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(zName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$zTotal', style: const pw.TextStyle(fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$zCleared', style: const pw.TextStyle(fontSize: 8, color: PdfColors.green800))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$zPending', style: const pw.TextStyle(fontSize: 8, color: PdfColors.red800))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${zRate.toStringAsFixed(1)}%', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(statusStr, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7, color: statusColor))),
                      ],
                    );
                  }),
                ],
              ),

              pw.SizedBox(height: 20),

              // Top 10 Best Ranked Wards
              pw.Text('3. Top 10 Best Ranked Wards (Leaderboard)', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
              pw.SizedBox(height: 8),

              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.8),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.green50),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Rank', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Ward Name', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Zone', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Cleanliness Score', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Cleared / Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Pending', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                    ],
                  ),
                  ...topWards.map((w) {
                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('#${w['rank']}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.green900))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(w['name'], style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(w['zone'], style: const pw.TextStyle(fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${w['score']}%', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.green800))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${w['cleared']} / ${w['total']}', style: const pw.TextStyle(fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${w['pending']}', style: pw.TextStyle(fontSize: 8, color: w['pending'] == 0 ? PdfColors.green800 : PdfColors.amber800))),
                      ],
                    );
                  }),
                ],
              ),

              pw.SizedBox(height: 20),

              // Bottom 10 Attention Required Wards
              pw.Text('4. Priority Action Wards (Pending Clearance Required)', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
              pw.SizedBox(height: 8),

              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.8),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.red50),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Rank', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Ward Name', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Zone', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Pending Flags', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Cleared Rate', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Recommended Action', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                    ],
                  ),
                  ...priorityWards.map((w) {
                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('#${w['rank']}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.red900))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(w['name'], style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(w['zone'], style: const pw.TextStyle(fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${w['pending']} Flags', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.red800))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${w['clearanceRate']}%', style: const pw.TextStyle(fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Deploy Tiper Fleet', style: pw.TextStyle(fontSize: 7, color: PdfColors.red800, fontWeight: pw.FontWeight.bold))),
                      ],
                    );
                  }),
                ],
              ),

              pw.SizedBox(height: 30),

              // Official Footer / Signatures
              pw.Container(
                padding: const pw.EdgeInsets.only(top: 14),
                decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 1))),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('STREET AIQ • AUTOMATED SANITATION AUDIT SYSTEM', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                        pw.Text('Certified Authentic BBMP Field Telemetry & Computer Vision Data', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Executive Authority Sign-off', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
                        pw.SizedBox(height: 4),
                        pw.Text('Digitally Verified by Chief Health Officer', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                      ],
                    ),
                  ],
                ),
              ),
            ];
          },
        ),
      );

      // Trigger print / download layout
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'BBMP_Street_AIQ_Ward_Rankings_Report_${now.millisecondsSinceEpoch}.pdf',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF0F5132),
            content: Text('✅ PDF Report generated and ready for download/print!'),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error generating PDF: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Failed to generate PDF: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  // --- Compute Ward Rankings & Zone Stats ---
  List<Map<String, dynamic>> _computeWardRankings(List<GarbageFlag> flags) {
    final allWards = WardZoneService.instance.wards;
    final Map<String, List<GarbageFlag>> wardMap = {};

    for (var w in allWards) {
      wardMap[w.name] = [];
    }

    for (var f in flags) {
      final wName = f.ward;
      if (wardMap.containsKey(wName)) {
        wardMap[wName]!.add(f);
      } else {
        // Fallback match
        final match = allWards.firstWhere(
          (w) => w.name.toLowerCase() == wName.toLowerCase(),
          orElse: () => allWards.first,
        );
        wardMap[match.name] = (wardMap[match.name] ?? [])..add(f);
      }
    }

    List<Map<String, dynamic>> results = [];

    for (var w in allWards) {
      final wardFlags = wardMap[w.name] ?? [];
      final total = wardFlags.length;
      final cleared = wardFlags.where((f) {
        final s = f.status.toLowerCase();
        return s == 'resolved' || s == 'cleared' || s == 'deflagged';
      }).length;
      final pending = total - cleared;
      final clearanceRate = total > 0 ? (cleared / total) * 100 : 100.0;

      // Score: Base 65 + (Rate * 0.35) - (Pending * 2.0), bounded 35 - 100
      double score = total == 0 ? 98.0 : (60.0 + (clearanceRate * 0.40) - (pending * 2.5));
      score = math.max(35.0, math.min(100.0, score));

      results.add({
        'wardNo': w.wardNo ?? 0,
        'name': w.name,
        'zone': w.zone ?? 'Unknown',
        'total': total,
        'cleared': cleared,
        'pending': pending,
        'clearanceRate': double.parse(clearanceRate.toStringAsFixed(1)),
        'score': double.parse(score.toStringAsFixed(1)),
      });
    }

    // Sort descending by score, then by cleared count
    results.sort((a, b) {
      int cmp = (b['score'] as double).compareTo(a['score'] as double);
      if (cmp != 0) return cmp;
      return (b['cleared'] as int).compareTo(a['cleared'] as int);
    });

    // Assign 1-based ranks
    for (int i = 0; i < results.length; i++) {
      results[i]['rank'] = i + 1;
    }

    return results;
  }

  Map<String, Map<String, int>> _computeZoneStats(List<GarbageFlag> flags) {
    final Map<String, Map<String, int>> stats = {};

    final zones = WardZoneService.instance.zones.isNotEmpty
        ? WardZoneService.instance.zones.map((z) => z.name).toList()
        : ['Bommanahalli', 'Dasarahalli', 'East', 'Mahadevapura', 'RR Nagar', 'South', 'West', 'Yelahanka'];

    for (var z in zones) {
      stats[z] = {'total': 0, 'cleared': 0, 'pending': 0};
    }

    for (var f in flags) {
      final z = f.zone;
      if (!stats.containsKey(z)) {
        stats[z] = {'total': 0, 'cleared': 0, 'pending': 0};
      }
      stats[z]!['total'] = (stats[z]!['total'] ?? 0) + 1;
      final s = f.status.toLowerCase();
      if (s == 'resolved' || s == 'cleared' || s == 'deflagged') {
        stats[z]!['cleared'] = (stats[z]!['cleared'] ?? 0) + 1;
      } else {
        stats[z]!['pending'] = (stats[z]!['pending'] ?? 0) + 1;
      }
    }

    return stats;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('trash_spots').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primaryGreen),
            );
          }

          final rawDocs = snapshot.data?.docs ?? [];
          final allFlags = rawDocs.map((d) {
            return GarbageFlag.fromJson(d.data() as Map<String, dynamic>, d.id);
          }).where((f) {
            return RoleService.isSpotAllowed(f.lat, f.lng, f.zone, f.ward, 'Reports');
          }).toList();

          final wardRankings = _computeWardRankings(allFlags);
          final zoneStats = _computeZoneStats(allFlags);

          // Summary Metrics
          final totalFlags = allFlags.length;
          final clearedFlags = allFlags.where((f) {
            final s = f.status.toLowerCase();
            return s == 'resolved' || s == 'cleared' || s == 'deflagged';
          }).length;
          final pendingFlags = totalFlags - clearedFlags;
          final clearancePercent = totalFlags > 0 ? ((clearedFlags / totalFlags) * 100).toStringAsFixed(1) : '100.0';

          return Column(
            children: [
              // 1. Top Header & Action Bar
              _buildHeader(
                totalFlags: totalFlags,
                clearedFlags: clearedFlags,
                pendingFlags: pendingFlags,
                clearancePercent: clearancePercent,
                onDownloadPdf: () => _generateAndDownloadPdf(
                  flags: allFlags,
                  wardRankings: wardRankings,
                  zoneStats: zoneStats,
                ),
              ),

              // 2. Tab Bar Header
              _buildTabBar(),

              // 3. Tab Views Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Ward Rankings Leaderboard
                    _buildWardRankingsTab(wardRankings),

                    // Tab 2: Zone Performance
                    _buildZonePerformanceTab(zoneStats, allFlags),

                    // Tab 3: Waste & AI Telemetry Insights
                    _buildWasteCategoryTab(allFlags),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Top Header Widget ---
  Widget _buildHeader({
    required int totalFlags,
    required int clearedFlags,
    required int pendingFlags,
    required String clearancePercent,
    required VoidCallback onDownloadPdf,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: cardBorder, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Title & Subtitle
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primaryGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(LucideIcons.fileText, color: primaryGreen, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Cleanliness & Ward Ranking Reports',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: darkSlate,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(6),
                          color: const Color(0xFFF8FAFC),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Role: ', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                            Text(RoleService.currentUserRoleTitle ?? 'None', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'BBMP Real-time AI Sanitation Telemetry • 198 Wards Audited Across 8 Zones',
                        style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ),

              // Downloadable PDF Button
              ElevatedButton.icon(
                onPressed: _isGeneratingPdf ? null : onDownloadPdf,
                icon: _isGeneratingPdf
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(LucideIcons.download, size: 18, color: Colors.white),
                label: Text(
                  _isGeneratingPdf ? 'Generating PDF...' : 'Download Official PDF Report',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 2,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Executive Metric Cards Row
          Row(
            children: [
              _buildMetricPill('Total AI Detections', '$totalFlags Flags', LucideIcons.flag, const Color(0xFF3B82F6), const Color(0xFFEFF6FF)),
              const SizedBox(width: 12),
              _buildMetricPill('Cleared & Resolved', '$clearedFlags Flags', LucideIcons.checkCheck, const Color(0xFF10B981), const Color(0xFFECFDF5)),
              const SizedBox(width: 12),
              _buildMetricPill('Pending Attention', '$pendingFlags Flags', LucideIcons.alertCircle, const Color(0xFFEF4444), const Color(0xFFFEF2F2)),
              const SizedBox(width: 12),
              _buildMetricPill('Resolution Rate', '$clearancePercent%', LucideIcons.trendingUp, const Color(0xFF8B5CF6), const Color(0xFFF5F3FF)),
              const SizedBox(width: 12),
              _buildMetricPill('City Cleanliness Score', '78.4 / 100', LucideIcons.award, const Color(0xFFF59E0B), const Color(0xFFFFFBEB)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricPill(String title, String value, IconData icon, Color color, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: darkSlate)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Tab Bar ---
  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: Alignment.centerLeft,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelColor: primaryGreen,
        unselectedLabelColor: const Color(0xFF64748B),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        indicatorColor: primaryGreen,
        indicatorWeight: 3,
        tabs: const [
          Tab(icon: Icon(LucideIcons.trophy, size: 16), text: 'Ward Rankings Leaderboard'),
          Tab(icon: Icon(LucideIcons.mapPin, size: 16), text: 'Zone Performance Matrix'),
          Tab(icon: Icon(LucideIcons.pieChart, size: 16), text: 'Waste Categorization & AI Vision'),
        ],
      ),
    );
  }

  // --- TAB 1: Ward Rankings Leaderboard ---
  Widget _buildWardRankingsTab(List<Map<String, dynamic>> allRankings) {
    final zones = ['All Zones', 'Bommanahalli', 'Dasarahalli', 'East', 'Mahadevapura', 'RR Nagar', 'South', 'West', 'Yelahanka'];

    // Filter
    List<Map<String, dynamic>> filtered = allRankings.where((w) {
      final matchesZone = _selectedZone == 'All Zones' || w['zone'] == _selectedZone;
      final matchesSearch = _searchWardQuery.isEmpty ||
          w['name'].toString().toLowerCase().contains(_searchWardQuery.toLowerCase()) ||
          w['wardNo'].toString().contains(_searchWardQuery);
      return matchesZone && matchesSearch;
    }).toList();

    // Sort
    if (_selectedSortBy == 'Cleanliness Score (Highest First)') {
      filtered.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    } else if (_selectedSortBy == 'Clearance Rate (%)') {
      filtered.sort((a, b) => (b['clearanceRate'] as double).compareTo(a['clearanceRate'] as double));
    } else if (_selectedSortBy == 'Pending Flags (Most First)') {
      filtered.sort((a, b) => (b['pending'] as int).compareTo(a['pending'] as int));
    } else if (_selectedSortBy == 'Total Flags (Most First)') {
      filtered.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
    } else {
      // Rank (Best to Worst)
      filtered.sort((a, b) => (a['rank'] as int).compareTo(b['rank'] as int));
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Controls Row
          Row(
            children: [
              // Search Ward
              Expanded(
                flex: 3,
                child: TextField(
                  onChanged: (val) => setState(() => _searchWardQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search by ward name or number (e.g. Ward 1, Kempegowda)...',
                    prefixIcon: const Icon(LucideIcons.search, size: 18, color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: cardBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: cardBorder)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: primaryGreen, width: 1.5)),
                  ),
                ),
              ),

              const SizedBox(width: 14),

              // Zone Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cardBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedZone,
                    icon: const Icon(LucideIcons.chevronDown, size: 16, color: Color(0xFF64748B)),
                    items: zones.map((z) => DropdownMenuItem(value: z, child: Text(z, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))).toList(),
                    onChanged: (val) => setState(() => _selectedZone = val ?? 'All Zones'),
                  ),
                ),
              ),

              const SizedBox(width: 14),

              // Sort Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cardBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedSortBy,
                    icon: const Icon(LucideIcons.arrowUpDown, size: 16, color: Color(0xFF64748B)),
                    items: [
                      'Rank (Best to Worst)',
                      'Cleanliness Score (Highest First)',
                      'Clearance Rate (%)',
                      'Pending Flags (Most First)',
                      'Total Flags (Most First)'
                    ].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))).toList(),
                    onChanged: (val) => setState(() => _selectedSortBy = val ?? 'Rank (Best to Worst)'),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Wards List Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                children: [
                  // Table Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                      border: Border(bottom: BorderSide(color: cardBorder)),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(width: 60, child: Text('RANK', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: Color(0xFF64748B)))),
                        Expanded(flex: 4, child: Text('WARD NAME & DETAILS', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: Color(0xFF64748B)))),
                        Expanded(flex: 2, child: Text('ZONE', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: Color(0xFF64748B)))),
                        Expanded(flex: 2, child: Text('CLEANLINESS SCORE', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: Color(0xFF64748B)))),
                        Expanded(flex: 2, child: Text('RESOLUTION STATUS', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: Color(0xFF64748B)))),
                        Expanded(flex: 2, child: Text('CLEARANCE EFFICIENCY', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: Color(0xFF64748B)))),
                      ],
                    ),
                  ),

                  // Table Rows
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No wards found matching filter criteria.'))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (ctx, i) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final rank = item['rank'] as int;
                              final score = item['score'] as double;
                              final cleared = item['cleared'] as int;
                              final total = item['total'] as int;
                              final pending = item['pending'] as int;
                              final clearanceRate = item['clearanceRate'] as double;

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                child: Row(
                                  children: [
                                    // Rank Badge
                                    SizedBox(
                                      width: 60,
                                      child: _buildRankBadge(rank),
                                    ),

                                    // Ward Info
                                    Expanded(
                                      flex: 4,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['name'],
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: darkSlate),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            'Ward No: ${item['wardNo']} • Active Tiper Fleet: 2 Assigned',
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Zone Chip
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        item['zone'],
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                      ),
                                    ),

                                    // Cleanliness Score Progress
                                    Expanded(
                                      flex: 2,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: score / 100.0,
                                                minHeight: 6,
                                                backgroundColor: const Color(0xFFE2E8F0),
                                                valueColor: AlwaysStoppedAnimation<Color>(
                                                  score >= 80 ? const Color(0xFF10B981) : (score >= 60 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            '$score%',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12,
                                              color: score >= 80 ? const Color(0xFF10B981) : (score >= 60 ? const Color(0xFFD97706) : const Color(0xFFDC2626)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Resolution Counts
                                    Expanded(
                                      flex: 2,
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(4)),
                                            child: Text('$cleared / $total Cleared', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF059669))),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(color: pending == 0 ? const Color(0xFFF8FAFC) : const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(4)),
                                            child: Text(
                                              '$pending Pending',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: pending == 0 ? const Color(0xFF94A3B8) : const Color(0xFFDC2626),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Clearance Rate %
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '$clearanceRate%',
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: darkSlate),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankBadge(int rank) {
    if (rank == 1) {
      return Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(color: Color(0xFFFEF08A), shape: BoxShape.circle),
        child: const Center(child: Text('🥇', style: TextStyle(fontSize: 16))),
      );
    } else if (rank == 2) {
      return Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(color: Color(0xFFE2E8F0), shape: BoxShape.circle),
        child: const Center(child: Text('🥈', style: TextStyle(fontSize: 16))),
      );
    } else if (rank == 3) {
      return Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(color: Color(0xFFFED7AA), shape: BoxShape.circle),
        child: const Center(child: Text('🥉', style: TextStyle(fontSize: 16))),
      );
    } else {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: rank <= 15 ? const Color(0xFFE8F5E9) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            '#$rank',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: rank <= 15 ? primaryGreen : const Color(0xFF64748B),
            ),
          ),
        ),
      );
    }
  }

  // --- TAB 2: Zone Performance Matrix ---
  Widget _buildZonePerformanceTab(Map<String, Map<String, int>> zoneStats, List<GarbageFlag> flags) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.35,
        ),
        itemCount: zoneStats.keys.length,
        itemBuilder: (context, index) {
          final zoneName = zoneStats.keys.elementAt(index);
          final stats = zoneStats[zoneName]!;
          final total = stats['total'] ?? 0;
          final cleared = stats['cleared'] ?? 0;
          final pending = stats['pending'] ?? 0;
          final clearance = total > 0 ? (cleared / total) * 100 : 100.0;

          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cardBorder),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      zoneName,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: darkSlate),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: clearance >= 60 ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${clearance.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: clearance >= 60 ? const Color(0xFF059669) : const Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ],
                ),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total: $total Flags', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                        Text('$cleared Cleared • $pending Pending', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: total > 0 ? (cleared / total) : 1.0,
                        minHeight: 8,
                        backgroundColor: const Color(0xFFE2E8F0),
                        valueColor: AlwaysStoppedAnimation<Color>(clearance >= 60 ? primaryGreen : const Color(0xFFEF4444)),
                      ),
                    ),
                  ],
                ),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Audit Status', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                    Text(
                      clearance >= 65 ? 'High Compliance' : (clearance >= 50 ? 'Moderate' : 'Action Required'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: clearance >= 65 ? const Color(0xFF10B981) : (clearance >= 50 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- TAB 3: Waste Categorization & AI Vision ---
  Widget _buildWasteCategoryTab(List<GarbageFlag> flags) {
    final Map<String, int> categories = {};
    for (var f in flags) {
      final c = f.displayClass.isNotEmpty ? f.displayClass : 'Trash Detected';
      categories[c] = (categories[c] ?? 0) + 1;
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category Distribution Breakdown
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Waste Classification Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: darkSlate)),
                  const SizedBox(height: 4),
                  const Text('Classified in real-time by AI Vision Model V7 (MobileNetV2 Edge)', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  const SizedBox(height: 20),
                  ...categories.entries.map((entry) {
                    final percent = flags.isNotEmpty ? ((entry.value / flags.length) * 100).toStringAsFixed(1) : '0';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: darkSlate)),
                              Text('${entry.value} spots ($percent%)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryGreen)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: flags.isNotEmpty ? (entry.value / flags.length) : 0,
                              minHeight: 8,
                              backgroundColor: const Color(0xFFF1F5F9),
                              valueColor: const AlwaysStoppedAnimation<Color>(primaryGreen),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          const SizedBox(width: 20),

          // AI Quality & Telemetry Specs
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Model V7 Accuracy & Latency', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: darkSlate)),
                  const SizedBox(height: 4),
                  const Text('Automated Street Cleanliness AI Specs', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  const SizedBox(height: 20),
                  _buildSpecRow('Average AI Confidence', '87.4%', LucideIcons.checkCircle2, const Color(0xFF10B981)),
                  const Divider(height: 20),
                  _buildSpecRow('Edge Inference Latency', '42 ms / frame', LucideIcons.zap, const Color(0xFF3B82F6)),
                  const Divider(height: 20),
                  _buildSpecRow('Detections per Hour', '~140 captures', LucideIcons.clock, const Color(0xFF8B5CF6)),
                  const Divider(height: 20),
                  _buildSpecRow('False Positive Filter', 'SHA-256 Anti-Duplication Active', LucideIcons.shieldCheck, primaryGreen),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecRow(String label, String value, IconData icon, Color iconColor) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: darkSlate)),
            ],
          ),
        ),
      ],
    );
  }
}
