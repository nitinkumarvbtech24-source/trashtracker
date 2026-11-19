import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/ward.dart';
import '../models/ward_official.dart';
import '../services/ward_officials_service.dart';

class WardHierarchySheet extends StatefulWidget {
  final Ward ward;

  const WardHierarchySheet({super.key, required this.ward});

  static void show(BuildContext context, Ward ward) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.70),
      builder: (ctx) => WardHierarchySheet(ward: ward),
    );
  }

  @override
  State<WardHierarchySheet> createState() => _WardHierarchySheetState();
}

class _WardHierarchySheetState extends State<WardHierarchySheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<WardOfficial> _officials;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _officials = WardOfficialsService.instance.getHierarchyForWard(widget.ward);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 700;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? 680 : double.infinity,
          maxHeight: size.height * 0.88,
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.94),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: const Color(0xFF334155), width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black87, blurRadius: 28, spreadRadius: 4, offset: Offset(0, -4)),
                ],
              ),
              child: Column(
                children: [
                  _buildDragHandle(),
                  _buildHeader(),
                  _buildTabBar(),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildFlowchartView(),
                        _buildDirectoryListView(),
                        _buildEmergencyEscalationView(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00B0FF), Color(0xFF00E5FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(color: Color(0x6600B0FF), blurRadius: 12, offset: Offset(0, 3)),
              ],
            ),
            child: const Icon(Icons.account_tree_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF00E5FF), width: 1),
                      ),
                      child: Text(
                        widget.ward.wardNo != null ? 'WARD #${widget.ward.wardNo}' : 'BBMP WARD',
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF00E676), width: 1),
                      ),
                      child: Text(
                        '${widget.ward.zone ?? "Bengaluru"} ZONE',
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  widget.ward.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.ward.constituency != null)
                  Text(
                    'Constituency: ${widget.ward.constituency} · 8 Key Officials in Command',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: const Color(0xFF2563EB),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(color: Color(0x662563EB), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF94A3B8),
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        tabs: const [
          Tab(icon: Icon(Icons.alt_route_rounded, size: 16), text: 'Flowchart'),
          Tab(icon: Icon(Icons.contacts_rounded, size: 16), text: 'Directory'),
          Tab(icon: Icon(Icons.emergency_rounded, size: 16), text: 'Escalations'),
        ],
      ),
    );
  }

  // --- TAB 1: INTERACTIVE HIERARCHY FLOWCHART ---
  Widget _buildFlowchartView() {
    final Map<int, List<WardOfficial>> grouped = {};
    for (var o in _officials) {
      grouped.putIfAbsent(o.tier, () => []).add(o);
    }

    final tiers = [1, 2, 3, 4];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      itemCount: tiers.length,
      itemBuilder: (context, index) {
        final tier = tiers[index];
        final tierOfficials = grouped[tier] ?? [];
        final isLast = index == tiers.length - 1;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTierHeader(tier, tierOfficials.first.tierTitle),
            const SizedBox(height: 10),
            ...tierOfficials.map((official) => _buildOfficialNodeCard(official, isFlowchart: true)),
            if (!isLast) _buildFlowchartConnector(),
          ],
        );
      },
    );
  }

  Widget _buildTierHeader(int tier, String title) {
    Color tierColor;
    IconData tierIcon;
    switch (tier) {
      case 1:
        tierColor = const Color(0xFFFFB300); // Gold
        tierIcon = Icons.shield_rounded;
        break;
      case 2:
        tierColor = const Color(0xFF00E676); // Emerald
        tierIcon = Icons.domain_rounded;
        break;
      case 3:
        tierColor = const Color(0xFF00E5FF); // Cyan
        tierIcon = Icons.home_work_rounded;
        break;
      default:
        tierColor = const Color(0xFFFF9100); // Amber
        tierIcon = Icons.cleaning_services_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tierColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tierColor.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tierIcon, color: tierColor, size: 14),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: tierColor,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowchartConnector() {
    return Center(
      child: Column(
        children: [
          Container(
            width: 2,
            height: 16,
            color: const Color(0xFF475569),
          ),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF1E293B),
            ),
            child: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF00E5FF),
              size: 16,
            ),
          ),
          Container(
            width: 2,
            height: 16,
            color: const Color(0xFF475569),
          ),
        ],
      ),
    );
  }

  // --- OFFICIAL NODE CARD (WITH DIRECT CALL, MAIL, MESSAGE ACTIONS) ---
  Widget _buildOfficialNodeCard(WardOfficial official, {bool isFlowchart = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E293B),
            const Color(0xFF0F172A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: official.accentColor.withValues(alpha: 0.40),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar with accent badge
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: official.accentColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: official.accentColor, width: 1.5),
                  ),
                  child: Center(
                    child: Icon(official.icon, color: official.accentColor, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              official.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.greenAccent, width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircleAvatar(radius: 3, backgroundColor: Colors.greenAccent),
                                const SizedBox(width: 4),
                                Text(
                                  official.status,
                                  style: const TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        official.designation,
                        style: TextStyle(
                          color: official.accentColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        official.department,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF334155), height: 1),
            const SizedBox(height: 10),

            // ACTION BUTTON BAR: CALL, MAIL, MESSAGE
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.phone_in_talk_rounded,
                    label: 'Call',
                    color: const Color(0xFF00E676),
                    onTap: () async {
                      _showActionToast('Calling ${official.name} (${official.phone})...');
                      await WardOfficialsService.instance.launchCall(official.phone);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.email_rounded,
                    label: 'Email',
                    color: const Color(0xFF00B0FF),
                    onTap: () async {
                      _showActionToast('Drafting email to ${official.name}...');
                      await WardOfficialsService.instance.mailOfficial(
                        official.email,
                        wardName: widget.ward.name,
                        officialName: official.name,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.chat_bubble_rounded,
                    label: 'Message',
                    color: const Color(0xFF26A69A),
                    onTap: () async {
                      _showActionToast('Opening message for ${official.name}...');
                      await WardOfficialsService.instance.messageOfficial(
                        official.whatsapp ?? official.phone,
                        wardName: widget.ward.name,
                        officialName: official.name,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- TAB 2: DIRECTORY LIST VIEW ---
  Widget _buildDirectoryListView() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      itemCount: _officials.length,
      itemBuilder: (context, index) {
        return _buildOfficialNodeCard(_officials[index]);
      },
    );
  }

  // --- TAB 3: EMERGENCY ESCALATION WORKFLOW ---
  Widget _buildEmergencyEscalationView() {
    final shi = _officials.firstWhere((o) => o.id == 'field_shi', orElse: () => _officials.last);
    final aee = _officials.firstWhere((o) => o.id == 'subdiv_aee', orElse: () => _officials.first);
    final mla = _officials.firstWhere((o) => o.id == 'zonal_mla', orElse: () => _officials.first);

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
          ),
          child: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Immediate Civic Escalation Path:\nIf waste accumulation is critical or poses a public health risk, follow this sequential chain of command.',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildEscalationStep(
          step: '1',
          role: 'First Responder: Senior Health Inspector (SHI)',
          name: shi.name,
          phone: shi.phone,
          color: const Color(0xFFFF9100),
          official: shi,
        ),
        _buildEscalationArrow(),
        _buildEscalationStep(
          step: '2',
          role: 'Secondary Level: Assistant Executive Engineer (AEE)',
          name: aee.name,
          phone: aee.phone,
          color: const Color(0xFF00E5FF),
          official: aee,
        ),
        _buildEscalationArrow(),
        _buildEscalationStep(
          step: '3',
          role: 'Apex Escalation: MLA / Grievance Redressal Cell',
          name: mla.name,
          phone: mla.phone,
          color: const Color(0xFF00E676),
          official: mla,
        ),
      ],
    );
  }

  Widget _buildEscalationStep({
    required String step,
    required String role,
    required String name,
    required String phone,
    required Color color,
    required WardOfficial official,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color,
            child: Text(step, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(role, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                Text(phone, style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => WardOfficialsService.instance.launchCall(phone),
            icon: const Icon(Icons.call, color: Color(0xFF00E676)),
            tooltip: 'Call Now',
          ),
        ],
      ),
    );
  }

  Widget _buildEscalationArrow() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Icon(Icons.arrow_downward_rounded, color: Colors.white38, size: 20),
      ),
    );
  }

  void _showActionToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF1E293B),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
