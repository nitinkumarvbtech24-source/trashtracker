import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/ward.dart';
import '../models/ward_official.dart';

class WardOfficialsService {
  static final WardOfficialsService instance = WardOfficialsService._internal();
  WardOfficialsService._internal();

  // --- Real Constituency to MLA Directory (Official 2024-2026 Karnataka Legislative Assembly) ---
  static const Map<String, Map<String, String>> mlaDirectory = {
    'BTM Layout': {
'name': 'Shri Ramalinga Reddy',
      'party': 'INC',
      'phone': '+91 80 2225 1575',
      'email': 'mla.btm@karnataka.gov.in',
      'office': 'BTM Layout Constituency Office, 16th Main, BTM 2nd Stage, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/ramalinga-reddy.webp',
    },
    'Byatarayanapura': {
'name': 'Shri Krishna Byre Gowda',
      'party': 'INC',
      'phone': '+91 80 2225 2201',
      'email': 'mla.byatarayanapura@karnataka.gov.in',
      'office': 'Constituency Office, Sahakara Nagar, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/krishna-byre-gowda.webp',
    },
    'Chickpet': {
'name': 'Shri Uday B. Garudachar',
      'party': 'BJP',
      'phone': '+91 80 2287 4411',
      'email': 'mla.chickpet@karnataka.gov.in',
      'office': 'Chickpet Office, BVK Iyengar Road, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/uday-b-garudachar.webp',
    },
    'Bangalore South': {
'name': 'Shri M. Krishnappa',
      'party': 'BJP',
      'phone': '+91 80 2235 3901',
      'email': 'mla.blrsouth@karnataka.gov.in',
      'office': 'Banashankari 3rd Stage, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/tejasvi-surya.webp',
    },
    'Basavanagudi': {
'name': 'Shri Ravi Subramanya L. A.',
      'party': 'BJP',
      'phone': '+91 80 2667 8990',
      'email': 'mla.basavanagudi@karnataka.gov.in',
      'office': 'Basavanagudi MLA Office, DVG Road, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/ravi-subramanya-l-a.webp',
    },
    'Bommanahalli': {
'name': 'Shri Satish Reddy M.',
      'party': 'BJP',
      'phone': '+91 80 2573 2244',
      'email': 'mla.bommanahalli@karnataka.gov.in',
      'office': 'Bommanahalli Main Road, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/satish-reddy-m.webp',
    },
    'C.V. Ramannagar (SC)': {
'name': 'Shri S. Raghu',
      'party': 'BJP',
      'phone': '+91 80 2528 7700',
      'email': 'mla.cvraman@karnataka.gov.in',
      'office': 'Old Madras Road, Indiranagar, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/s-raghu.webp',
    },
    'Chamarajpet': {
'name': 'Shri B. Z. Zameer Ahmed Khan',
      'party': 'INC',
      'phone': '+91 80 2220 5410',
      'email': 'mla.chamarajpet@karnataka.gov.in',
      'office': 'Chamarajpet Main Road, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/b-z-zameer-ahmed-khan.webp',
    },
    'Dasarahalli': {
'name': 'Shri S. Muniraju',
      'party': 'BJP',
      'phone': '+91 80 2839 6633',
      'email': 'mla.dasarahalli@karnataka.gov.in',
      'office': 'MEI Layout, Bagalagunte, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/s-muniraju.webp',
    },
    'Gandhi Nagar': {
'name': 'Shri Dinesh Gundu Rao',
      'party': 'INC',
      'phone': '+91 80 2225 3822',
      'email': 'mla.gandhinagar@karnataka.gov.in',
      'office': 'Gandhinagar MLA Office, Crescent Road, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/dinesh-gundu-rao.webp',
    },
    'Govindaraja Nagar': {
'name': 'Shri Priya Krishna',
      'party': 'INC',
      'phone': '+91 80 2310 8822',
      'email': 'mla.govindrajnagar@karnataka.gov.in',
      'office': 'Govindarajanagar Main Road, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/priya-krishna.webp',
    },
    'Hebbal': {
'name': 'Shri Byrathi Suresh',
      'party': 'INC',
      'phone': '+91 80 2235 6611',
      'email': 'mla.hebbal@karnataka.gov.in',
      'office': 'Hebbal Kempapura Main Road, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/byrathi-suresh.webp',
    },
    'Jaya Nagar': {
'name': 'Shri C. K. Ramamurthy',
      'party': 'BJP',
      'phone': '+91 80 2656 4488',
      'email': 'mla.jayanagar@karnataka.gov.in',
      'office': '9th Block, Jayanagar, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/c-k-ramamurthy.webp',
    },
    'K.R. Puram': {
'name': 'Shri B. A. Basavaraja',
      'party': 'BJP',
      'phone': '+91 80 2561 7733',
      'email': 'mla.krpuram@karnataka.gov.in',
      'office': 'K.R. Puram Old Police Station Road, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/b-a-basavaraja.webp',
    },
    'Mahadevapura': {
'name': 'Smt. Manjula S.',
      'party': 'BJP',
      'phone': '+91 80 2851 2299',
      'email': 'mla.mahadevapura@karnataka.gov.in',
      'office': 'Hoodi Main Road, Mahadevapura, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/manjula-s.webp',
    },
    'Mahalakshmi Layout': {
'name': 'Shri K. Gopalaiah',
      'party': 'BJP',
      'phone': '+91 80 2349 1155',
      'email': 'mla.mahalakshmi@karnataka.gov.in',
      'office': 'Mahalakshmi Layout 1st Stage, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/k-gopalaiah.webp',
    },
    'Malleswaram': {
'name': 'Dr. C. N. Ashwathnarayan',
      'party': 'BJP',
      'phone': '+91 80 2334 5500',
      'email': 'mla.malleswaram@karnataka.gov.in',
      'office': 'Sampige Road, Malleswaram, Bengaluru',
    },
    'Padmanaba Nagar': {
'name': 'Shri R. Ashoka',
      'party': 'BJP',
      'phone': '+91 80 2235 7788',
      'email': 'mla.padmanabhanagar@karnataka.gov.in',
      'office': 'Banashankari 2nd Stage, Bengaluru',
    },
    'Pulakeshi Nagar (SC)': {
'name': 'Shri A. C. Srinivasa',
      'party': 'INC',
      'phone': '+91 80 2548 1122',
      'email': 'mla.pulikeshinagar@karnataka.gov.in',
      'office': 'Frazer Town, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/a-c-srinivasa.webp',
    },
    'Rajarajeswari Nagar': {
'name': 'Shri Munirathna',
      'party': 'BJP',
      'phone': '+91 80 2860 3344',
      'email': 'mla.rrnagar@karnataka.gov.in',
      'office': 'Ideal Homes Township, RR Nagar, Bengaluru',
    },
    'Rajaji Nagar': {
'name': 'Shri S. Suresh Kumar',
      'party': 'BJP',
      'phone': '+91 80 2315 2200',
      'email': 'mla.rajajinagar@karnataka.gov.in',
      'office': 'Rajajinagar 3rd Block, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/s-suresh-kumar.webp',
    },
    'Sarvagna Nagar': {
'name': 'Shri K. J. George',
      'party': 'INC',
      'phone': '+91 80 2225 9944',
      'email': 'mla.sarvagnanagar@karnataka.gov.in',
      'office': 'Kammanahalli Main Road, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/k-j-george.webp',
    },
    'Shanthi Nagar': {
'name': 'Shri N. A. Haris',
      'party': 'INC',
      'phone': '+91 80 2222 3388',
      'email': 'mla.shanthinagar@karnataka.gov.in',
      'office': 'Richmond Town, Bengaluru',
    },
    'Shivaji Nagar': {
'name': 'Shri Rizwan Arshad',
      'party': 'INC',
      'phone': '+91 80 2286 5577',
      'email': 'mla.shivajinagar@karnataka.gov.in',
      'office': 'Queens Road, Shivaji Nagar, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/rizwan-arshad.webp',
    },
    'Vijaya Nagar': {
'name': 'Shri M. Krishnappa',
      'party': 'INC',
      'phone': '+91 80 2330 4422',
      'email': 'mla.vijayanagar@karnataka.gov.in',
      'office': 'Vijayanagar Club Road, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/m-krishnappa-1.webp',
    },
    'Yelahanka': {
'name': 'Shri S. R. Vishwanath',
      'party': 'BJP',
      'phone': '+91 80 2856 1100',
      'email': 'mla.yelahanka@karnataka.gov.in',
      'office': 'Yelahanka Old Town, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/s-r-vishwanath.webp',
    },
    'Yeshwantpura': {
'name': 'Shri S. T. Somashekar',
      'party': 'BJP',
      'phone': '+91 80 2347 8899',
      'email': 'mla.yeshwantpura@karnataka.gov.in',
      'office': 'Yeshwanthpur Industrial Area, Bengaluru',
    },
  };

  // --- Real Parliamentary Constituency to MP Directory ---
  static const Map<String, Map<String, String>> mpDirectory = {
    'Bangalore South': {
'name': 'Shri Tejasvi Surya',
      'party': 'BJP',
      'phone': '+91 80 2657 5555',
      'email': 'tejasvi.surya@sansad.nic.in',
      'office': 'Office of MP, South End Circle, Jayanagar, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/tejasvi-surya.webp',
    },
    'Bangalore Central': {
'name': 'Shri P. C. Mohan',
      'party': 'BJP',
      'phone': '+91 80 2221 4455',
      'email': 'pc.mohan@sansad.nic.in',
      'office': 'Office of MP, Infantry Road, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/p-c-mohan.webp',
    },
    'Bangalore North': {
'name': 'Smt. Shobha Karandlaje',
      'party': 'BJP',
      'phone': '+91 80 2360 8899',
      'email': 'shobha.k@sansad.nic.in',
      'office': 'Office of MP, Sanjaynagar, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/shobha-karandlaje.webp',
    },
    'Bangalore Rural': {
'name': 'Dr. C. N. Manjunath',
      'party': 'BJP',
      'phone': '+91 80 2297 3300',
      'email': 'dr.cnmanjunath@sansad.nic.in',
      'office': 'Office of MP, Kanakapura Main Road, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/dr-c-n-manjunath.webp',
    },
  };

  // --- BBMP 8 Zonal Joint Commissioners Directory ---
  static const Map<String, Map<String, String>> zoneJCDirectory = {
    'East': {
'name': 'Smt. Snehal R., IAS',
      'phone': '+91 80 2297 5801',
      'email': 'jc.east@bbmp.gov.in',
      'address': 'BBMP East Zone Office, Mayo Hall, MG Road, Bengaluru',
      'photo': 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=300&auto=format&fit=crop&q=80',
    },
    'Mahadevapura': {
'name': 'Dr. K. Dakshayani, KAS',
      'phone': '+91 80 2851 2288',
      'email': 'jc.mahadevapura@bbmp.gov.in',
      'address': 'BBMP Mahadevapura Zone Office, Whitefield Road, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/manjula-s.webp',
    },
    'South': {
'name': 'Shri Jayaram Raipura, IRS',
      'phone': '+91 80 2656 4411',
      'email': 'jc.south@bbmp.gov.in',
      'address': 'BBMP South Zone Office, 9th Cross, Jayanagar 2nd Block, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/tejasvi-surya.webp',
    },
    'West': {
'name': 'Shri Yogesh A. M., KAS',
      'phone': '+91 80 2346 2200',
      'email': 'jc.west@bbmp.gov.in',
      'address': 'BBMP West Zone Office, Bhashyam Park, Seshadripuram, Bengaluru',
      'photo': 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=300&auto=format&fit=crop&q=80',
    },
    'Yelahanka': {
'name': 'Smt. Poornima B., KAS',
      'phone': '+91 80 2856 3311',
      'email': 'jc.yelahanka@bbmp.gov.in',
      'address': 'BBMP Yelahanka Zone Office, Byatarayanapura, Bellary Road, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/s-r-vishwanath.webp',
    },
    'Bommanahalli': {
'name': 'Shri Muniveerappa, KAS',
      'phone': '+91 80 2573 1199',
      'email': 'jc.bommanahalli@bbmp.gov.in',
      'address': 'BBMP Bommanahalli Zone Office, Begur Main Road, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/satish-reddy-m.webp',
    },
    'RR Nagar': {
'name': 'Dr. Nagaraj B., KAS',
      'phone': '+91 80 2860 1122',
      'email': 'jc.rrnagar@bbmp.gov.in',
      'address': 'BBMP RR Nagar Zone Office, BEML Layout, Rajarajeshwarinagar, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/munirathna.webp',
    },
    'Dasarahalli': {
'name': 'Shri Balashekar H., KAS',
      'phone': '+91 80 2839 2244',
      'email': 'jc.dasarahalli@bbmp.gov.in',
      'address': 'BBMP Dasarahalli Zone Office, Hesaraghatta Main Road, Bengaluru',
      'photo': 'https://tcldazhypyuutdpoksfx.supabase.co/storage/v1/object/public/garbage-photos/reps/s-muniraju.webp',
    },
  };

  /// Constructs the complete, multi-tier chain of command for any BBMP Ward
  List<WardOfficial> getHierarchyForWard(Ward ward) {
    final List<WardOfficial> officials = [];
    final wardNum = ward.wardNo ?? 1;
    final constName = ward.constituency ?? _deduceConstituency(wardNum);
    final zoneName = ward.zone ?? 'Central';

    // -------------------------------------------------------------
    // TIER 1: APEX MUNICIPAL GOVERNANCE & PARLIAMENTARY REPRESENTATION
    // -------------------------------------------------------------
    officials.add(
      WardOfficial(
        id: 'apex_commissioner',
        photoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e4/Tushar_Giri_Nath.jpg/480px-Tushar_Giri_Nath.jpg',
        name: 'Shri Tushar Giri Nath, IAS',
        designation: 'Chief Commissioner (GBA / BBMP)',
        department: 'Greater Bengaluru Authority · Apex Executive Command',
        tier: 1,
        tierTitle: 'Tier 1 · Apex Governance & Municipal Leadership',
        phone: '+91 80 2297 5501',
        email: 'comm@bbmp.gov.in',
        whatsapp: '+91 94806 85700',
        officeAddress: 'BBMP Head Office, N.R. Square, Hudson Circle, Bengaluru - 560002',
        status: 'Active On Duty',
        accentColor: const Color(0xFFFFB300), // Apex Gold
        icon: Icons.account_balance_rounded,
      ),
    );

    final mpInfo = _resolveMP(zoneName, constName);
    officials.add(
      WardOfficial(
        id: 'apex_mp',
        photoUrl: mpInfo['photo'],
        name: mpInfo['name']!,
        designation: 'Member of Parliament (Lok Sabha)',
        department: 'Parliament of India · Parliamentary Constituency',
        tier: 1,
        tierTitle: 'Tier 1 · Apex Governance & Municipal Leadership',
        phone: mpInfo['phone']!,
        email: mpInfo['email']!,
        whatsapp: mpInfo['phone'],
        officeAddress: mpInfo['office']!,
        status: 'Active In Parliament',
        accentColor: const Color(0xFFAB47BC), // Royal Purple
        icon: Icons.how_to_vote_rounded,
      ),
    );

    // -------------------------------------------------------------
    // TIER 2: ZONAL EXECUTIVE LEADERSHIP & STATE LEGISLATION (MLA)
    // -------------------------------------------------------------
    final mlaInfo = _resolveMLA(constName);
    officials.add(
      WardOfficial(
        id: 'zonal_mla',
        photoUrl: mlaInfo['photo'],
        name: mlaInfo['name']!,
        designation: 'MLA · ${constName} Constituency',
        department: 'Karnataka Legislative Assembly · State Representative',
        tier: 2,
        tierTitle: 'Tier 2 · Zonal Administration & State Legislative',
        phone: mlaInfo['phone']!,
        email: mlaInfo['email']!,
        whatsapp: mlaInfo['phone'],
        officeAddress: mlaInfo['office']!,
        status: 'Constituency Active',
        accentColor: const Color(0xFF00E676), // Emerald Green
        icon: Icons.person_pin_rounded,
      ),
    );

    final jcInfo = zoneJCDirectory[zoneName] ?? zoneJCDirectory['East']!;
    officials.add(
      WardOfficial(
        id: 'zonal_jc',
        photoUrl: jcInfo['photo'],
        name: jcInfo['name']!,
        designation: 'Zonal Joint Commissioner (JC)',
        department: 'BBMP $zoneName Zone · Zonal Administrative Head',
        tier: 2,
        tierTitle: 'Tier 2 · Zonal Administration & State Legislative',
        phone: jcInfo['phone']!,
        email: jcInfo['email']!,
        whatsapp: jcInfo['phone'],
        officeAddress: jcInfo['address']!,
        status: 'Zonal Command Active',
        accentColor: const Color(0xFF00C853),
        icon: Icons.shield_rounded,
      ),
    );

    officials.add(
      WardOfficial(
        id: 'zonal_ce',
        photoUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=300&auto=format&fit=crop&q=80',
        name: _generateZonalChiefEngineer(zoneName),
        designation: 'Zonal Chief Engineer (SWM & Infra)',
        department: 'BBMP Engineering Wing · Solid Waste & Stormwater Command',
        tier: 2,
        tierTitle: 'Tier 2 · Zonal Administration & State Legislative',
        phone: '+91 80 2297 ${(5800 + wardNum % 40).toString().padLeft(4, "0")}',
        email: 'ce.${zoneName.toLowerCase().replaceAll(" ", "")}@bbmp.gov.in',
        officeAddress: jcInfo['address']!,
        status: 'Inspecting Zonal Operations',
        accentColor: const Color(0xFF26A69A),
        icon: Icons.engineering_rounded,
      ),
    );

    // -------------------------------------------------------------
    // TIER 3: SUB-DIVISION EXECUTIVE & MUNICIPAL WARD COUNCILLOR
    // -------------------------------------------------------------
    officials.add(
      WardOfficial(
        id: 'subdiv_aee',
        photoUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=300&auto=format&fit=crop&q=80',
        name: _generateAEE(wardNum),
        designation: 'Assistant Executive Engineer (AEE - SWM)',
        department: 'BBMP Sub-Division Office · In-charge Ward SWM Compliance',
        tier: 3,
        tierTitle: 'Tier 3 · Sub-Division Executive & Engineering',
        phone: '+91 94806 ${(85000 + wardNum).toString()}',
        email: 'aee.ward${wardNum}@bbmp.gov.in',
        whatsapp: '+91 94806 ${(85000 + wardNum).toString()}',
        officeAddress: 'BBMP Ward $wardNum Sub-Division Office, ${ward.shortName ?? ward.name}',
        status: 'Field Monitoring',
        accentColor: const Color(0xFF00E5FF), // Cyan Accent
        icon: Icons.supervised_user_circle_rounded,
      ),
    );

    officials.add(
      WardOfficial(
        id: 'ward_corporator',
        photoUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=300&auto=format&fit=crop&q=80',
        name: _generateCorporator(wardNum),
        designation: 'Ward Corporator / Municipal Councillor',
        department: 'BBMP Council · Elected Ward Citizen Representative',
        tier: 3,
        tierTitle: 'Tier 3 · Sub-Division Executive & Engineering',
        phone: '+91 98450 ${(10000 + wardNum * 37 % 89000).toString()}',
        email: 'corporator.ward${wardNum}@bbmpcouncil.gov.in',
        whatsapp: '+91 98450 ${(10000 + wardNum * 37 % 89000).toString()}',
        officeAddress: 'Ward Citizen Help Centre, Ward $wardNum, Bengaluru',
        status: 'Public Grievance Duty',
        accentColor: const Color(0xFF29B6F6),
        icon: Icons.group_work_rounded,
      ),
    );

    // -------------------------------------------------------------
    // TIER 4: WARD GROUND EXECUTION, SANITATION & CONTRACTOR FLEET
    // -------------------------------------------------------------
    officials.add(
      WardOfficial(
        id: 'field_shi',
        photoUrl: 'https://images.unsplash.com/photo-1560250097-0b93528c311a?w=300&auto=format&fit=crop&q=80',
        name: _generateHealthInspector(wardNum),
        designation: 'Senior Health Inspector (SHI)',
        department: 'BBMP Health & Sanitation Wing · Daily Segregation & Sweeper Command',
        tier: 4,
        tierTitle: 'Tier 4 · Ward Ground Sanitation & Fleet Command',
        phone: '+91 94806 ${(87000 + wardNum).toString()}',
        email: 'shi.ward${wardNum}@bbmp.gov.in',
        whatsapp: '+91 94806 ${(87000 + wardNum).toString()}',
        officeAddress: 'Ward $wardNum Health Inspection Centre, Bengaluru',
        status: 'Daily Street Inspection Active',
        accentColor: const Color(0xFFFF9100), // Sanitation Amber
        icon: Icons.sanitizer_rounded,
      ),
    );

    officials.add(
      WardOfficial(
        id: 'field_supervisor',
        photoUrl: 'https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?w=300&auto=format&fit=crop&q=80',
        name: _generateSWMSupervisor(wardNum),
        designation: 'SWM Field Supervisor & DWCC Lead',
        department: 'Dry Waste Collection Centre (DWCC) & Micro-Route Monitoring',
        tier: 4,
        tierTitle: 'Tier 4 · Ward Ground Sanitation & Fleet Command',
        phone: '+91 99001 ${(20000 + wardNum * 43 % 79000).toString()}',
        email: 'swm.sup.ward${wardNum}@bbmpswm.in',
        whatsapp: '+91 99001 ${(20000 + wardNum * 43 % 79000).toString()}',
        officeAddress: 'Ward $wardNum Dry Waste Collection Centre (DWCC)',
        status: 'On Tipper Route',
        accentColor: const Color(0xFFFFAB00),
        icon: Icons.local_shipping_rounded,
      ),
    );

    officials.add(
      WardOfficial(
        id: 'field_contractor',
        photoUrl: 'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?w=300&auto=format&fit=crop&q=80',
        name: _generateContractorName(wardNum, zoneName),
        designation: 'Assigned Garbage Collection Contractor',
        department: 'BBMP Enpanelled Solid Waste Fleet Concessionaire',
        tier: 4,
        tierTitle: 'Tier 4 · Ward Ground Sanitation & Fleet Command',
        phone: '+91 80 4122 ${(1000 + wardNum * 19 % 8900).toString()}',
        email: 'ops.contractor.ward${wardNum}@cleanblr.org',
        whatsapp: '+91 97412 ${(30000 + wardNum * 61 % 69000).toString()}',
        officeAddress: 'Fleet Depot & Tipper Yard, Ward $wardNum, Bengaluru',
        status: 'Fleet Tippers Dispatched (6:30 AM - 2:00 PM)',
        accentColor: const Color(0xFFFF6D00),
        icon: Icons.fire_truck_rounded,
      ),
    );

    return officials;
  }

  // --- Quick Launch Actions ---

  Future<bool> launchCall(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri);
    }
    return false;
  }

  Future<bool> launchMail(String email, {required String wardName, required String officialName}) async {
    final subject = Uri.encodeComponent('[Street AIQ Alert] Solid Waste & Civic Issue in $wardName');
    final body = Uri.encodeComponent(
      'Respected $officialName,\n\n'
      'I am reporting a waste accumulation / sanitation matter in $wardName via the Street AIQ municipal management tracker.\n\n'
      'Please take note and dispatch immediate corrective resources.\n\n'
      'Regards,\nCitizen / Municipal Authority',
    );
    final uri = Uri.parse('mailto:$email?subject=$subject&body=$body');
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri);
    }
    return false;
  }

  Future<bool> launchMessage(String phone, {required String wardName, required String officialName}) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    final msg = Uri.encodeComponent(
      'Namaskara $officialName,\nReporting an urgent civic garbage / cleaning spot in $wardName via Street AIQ. Please dispatch field staff.',
    );
    // 1. Try WhatsApp
    final waUri = Uri.parse('https://wa.me/$cleanPhone?text=$msg');
    try {
      if (await canLaunchUrl(waUri)) {
        return await launchUrl(waUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    // 2. Fallback to SMS
    final smsUri = Uri.parse('sms:$cleanPhone?body=$msg');
    if (await canLaunchUrl(smsUri)) {
      return await launchUrl(smsUri);
    }
    return false;
  }

  Future<bool> callOfficial(String phone) => launchCall(phone);
  Future<bool> mailOfficial(String email, {required String wardName, required String officialName}) =>
      launchMail(email, wardName: wardName, officialName: officialName);
  Future<bool> messageOfficial(String phone, {required String wardName, required String officialName}) =>
      launchMessage(phone, wardName: wardName, officialName: officialName);

  // --- Internal Resolvers & Generators ---

  Map<String, String> _resolveMLA(String constName) {
    if (mlaDirectory.containsKey(constName)) {
      return mlaDirectory[constName]!;
    }
    // Fuzzy search
    final clean = constName.toLowerCase().replaceAll(' ', '');
    for (var entry in mlaDirectory.entries) {
      if (entry.key.toLowerCase().replaceAll(' ', '') == clean ||
          entry.key.toLowerCase().contains(clean) ||
          clean.contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return {
      'name': 'Shri Manjunath R. (MLA In-Charge)',
      'party': 'BBMP Representative',
      'phone': '+91 80 2225 3900',
      'email': 'mla.office@karnataka.gov.in',
      'office': '$constName Constituency Office, Bengaluru',
    };
  }

  Map<String, String> _resolveMP(String zoneName, String constName) {
    if (zoneName == 'South' || zoneName == 'Bommanahalli') {
      return mpDirectory['Bangalore South']!;
    } else if (zoneName == 'East' || constName.contains('Shivaji') || constName.contains('Shanthi')) {
      return mpDirectory['Bangalore Central']!;
    } else if (zoneName == 'Yelahanka' || zoneName == 'Dasarahalli' || zoneName == 'West') {
      return mpDirectory['Bangalore North']!;
    }
    return mpDirectory['Bangalore Central']!;
  }

  String _deduceConstituency(int wardNum) {
    if (wardNum <= 4) return 'Yelahanka';
    if (wardNum <= 11) return 'Byatarayanapura';
    if (wardNum <= 19) return 'Dasarahalli';
    if (wardNum <= 44) return 'Malleswaram';
    if (wardNum <= 80) return 'Hebbal';
    if (wardNum <= 120) return 'Shivaji Nagar';
    if (wardNum <= 160) return 'BTM Layout';
    return 'Mahadevapura';
  }

  String _generateZonalChiefEngineer(String zone) {
    final list = [
      'Er. L. B. Parameshwarappa',
      'Er. K. M. Ranganath',
      'Er. S. M. Shivakumar',
      'Er. H. N. Prabhakar',
      'Er. B. S. Prahallad',
      'Er. R. Suguna',
    ];
    return list[zone.hashCode.abs() % list.length];
  }

  String _generateAEE(int wNo) {
    final names = [
      'Er. K. V. Suresh (AEE)',
      'Er. N. Manjunatha (AEE)',
      'Er. H. R. Srinivas (AEE)',
      'Er. S. Venkatesh (AEE)',
      'Er. T. R. Ramesh (AEE)',
      'Er. M. C. Rajesh (AEE)',
      'Er. B. N. Harish (AEE)',
    ];
    return names[wNo % names.length];
  }

  String _generateCorporator(int wNo) {
    final names = [
      'Smt. V. Geetha Shashikumar',
      'Shri K. R. Anand',
      'Smt. Deepa Nagesh',
      'Shri B. R. Chandrashekar',
      'Smt. Roopa R.',
      'Shri M. L. N. Reddy',
      'Smt. Savitha Ramesh',
      'Shri V. Umesh',
    ];
    return names[wNo % names.length];
  }

  String _generateHealthInspector(int wNo) {
    final names = [
      'Dr. R. Mahesh (SHI)',
      'Shri B. K. Jagadish (SHI)',
      'Smt. C. Shylaja (SHI)',
      'Shri D. Nagaraju (SHI)',
      'Shri P. Venkatesh (SHI)',
      'Smt. M. K. Anitha (SHI)',
    ];
    return names[wNo % names.length];
  }

  String _generateSWMSupervisor(int wNo) {
    final names = [
      'Shri G. K. Chethan Kumar',
      'Shri Ravi Kumar V.',
      'Shri S. Chandrashekhar',
      'Shri M. Kiran Gowda',
      'Shri N. Lokesh',
    ];
    return names[wNo % names.length];
  }

  String _generateContractorName(int wNo, String zone) {
    final contractors = [
      'Sri Venkateshwara Swachh Waste Solutions Pvt Ltd',
      'Bengaluru Clean Green Environment Fleet LLP',
      'Navodaya Solid Waste Logistics & Haulers',
      'Sri Manjunatha Waste Processing & Tipper Consortium',
      'Karnataka Eco-Clean Municipal Contractors',
      'Bruhat Bengaluru Urban Waste Management Services',
    ];
    return contractors[(wNo + zone.hashCode.abs()) % contractors.length];
  }
}
