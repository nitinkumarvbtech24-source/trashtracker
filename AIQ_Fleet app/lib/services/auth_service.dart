import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:android_id/android_id.dart';

enum LoginResult { success, failed, alreadyLoggedIn }

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal() {
    _checkLoginStatus();
  }

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  String? _driverName;
  String? get driverName => _driverName;
  String? _vehicleNumber;
  String? get vehicleNumber => _vehicleNumber;
  String? _sessionId;
  String? _deviceId;
  String? get deviceId => _deviceId;
  
  StreamSubscription<QuerySnapshot>? _sessionSub;

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    
    // Try to load Device ID, but generation is handled securely
    _deviceId = prefs.getString('deviceId');
    if (_deviceId == null || _deviceId!.contains('-')) {
      _deviceId = null;
      await _generateDeviceIdIfNotExists();
    }

    if (_isLoggedIn) {
      _driverName = prefs.getString('driverName');
      _vehicleNumber = prefs.getString('vehicleNumber');
      _sessionId = prefs.getString('sessionId');
      _startSessionListener();
    }
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _generateDeviceIdIfNotExists() async {
    if (_deviceId != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString('deviceId');
      
      // If the device ID is the old UUID format, force generation of the new format
      if (_deviceId != null && _deviceId!.contains('-')) {
        _deviceId = null;
      }
      
      if (_deviceId != null) return;

      // Try to get hardware ID to reuse assigned UID if previously uninstalled
      String? hardwareId;
      if (!kIsWeb) {
        try {
          const androidIdPlugin = AndroidId();
          hardwareId = await androidIdPlugin.getId();
        } catch (e) {
          debugPrint("Could not get hardware ID: $e");
        }
      }

      if (hardwareId != null) {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('metadata')
            .doc('hardware_mappings')
            .collection('devices')
            .where('hardwareId', isEqualTo: hardwareId)
            .limit(1)
            .get();
        if (querySnapshot.docs.isNotEmpty) {
          _deviceId = querySnapshot.docs.first.data()['uid'];
          await prefs.setString('deviceId', _deviceId!);
          return; // Successfully recovered UID
        }
      }

      final counterRef = FirebaseFirestore.instance.collection('metadata').doc('counters');
      final currentCount = await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(counterRef);
        if (!snapshot.exists) {
          transaction.set(counterRef, {'deviceCount': 1});
          return 0;
        }
        int count = snapshot.data()?['deviceCount'] ?? 0;
        transaction.update(counterRef, {'deviceCount': count + 1});
        return count;
      });
      final now = DateTime.now();
      final dateStr = "${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.year}";
      _deviceId = "${currentCount}_$dateStr";
      await prefs.setString('deviceId', _deviceId!);

      // Save mapping for future reinstalls
      if (hardwareId != null) {
        await FirebaseFirestore.instance
            .collection('metadata')
            .doc('hardware_mappings')
            .collection('devices')
            .add({'hardwareId': hardwareId, 'uid': _deviceId});
      }
    } catch (e) {
      debugPrint("Failed to generate sequential ID: $e");
    }
  }

  String _generateSessionId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
  String _normalizePhone(String p) {
    String clean = p.replaceAll(RegExp(r'\D'), '');
    if (clean.length > 10 && clean.startsWith('91')) {
      clean = clean.substring(2);
    }
    return clean;
  }

  Future<DocumentSnapshot?> _findVehicleDoc(String vehicleNo, String mobile, String password) async {
    final vTrim = vehicleNo.trim();
    final mTrim = mobile.trim();
    final pTrim = password.trim();

    // 1. Try exact match
    try {
      final snap1 = await FirebaseFirestore.instance
          .collection('vehicles')
          .where('vehicleNumber', isEqualTo: vTrim)
          .where('phoneNumber', isEqualTo: mTrim)
          .where('password', isEqualTo: pTrim)
          .limit(1)
          .get();
      if (snap1.docs.isNotEmpty) return snap1.docs.first;
    } catch (_) {}

    // 2. Try uppercase vehicleNumber
    try {
      final snap2 = await FirebaseFirestore.instance
          .collection('vehicles')
          .where('vehicleNumber', isEqualTo: vTrim.toUpperCase())
          .where('phoneNumber', isEqualTo: mTrim)
          .where('password', isEqualTo: pTrim)
          .limit(1)
          .get();
      if (snap2.docs.isNotEmpty) return snap2.docs.first;
    } catch (_) {}

    // 3. Try document ID directly
    try {
      final docById = await FirebaseFirestore.instance.collection('vehicles').doc(vTrim).get();
      if (docById.exists && docById.data() != null) {
        final data = docById.data()!;
        final storedPhone = _normalizePhone((data['phoneNumber'] ?? '').toString());
        final storedPass = (data['password'] ?? '').toString().trim();
        if ((storedPhone == _normalizePhone(mTrim) || storedPhone.isEmpty) &&
            (storedPass == pTrim || storedPass.isEmpty)) {
          return docById;
        }
      }
    } catch (_) {}

    // 4. Flexible in-memory scan over all registered vehicles
    try {
      final allSnap = await FirebaseFirestore.instance.collection('vehicles').get();
      final normV = _normalize(vTrim);
      final normPhone = _normalizePhone(mTrim);

      for (var doc in allSnap.docs) {
        final data = doc.data();
        final storedV = _normalize((data['vehicleNumber'] ?? doc.id).toString());
        final storedPhone = _normalizePhone((data['phoneNumber'] ?? '').toString());
        final storedPass = (data['password'] ?? '').toString().trim();

        final isVehicleMatch = storedV == normV;
        final isPhoneMatch = storedPhone == normPhone || 
            (normPhone.isNotEmpty && (storedPhone.endsWith(normPhone) || normPhone.endsWith(storedPhone))) ||
            storedPhone.isEmpty;
        final isPassMatch = storedPass == pTrim || storedPass.isEmpty;

        if (isVehicleMatch && isPhoneMatch && isPassMatch) {
          return doc;
        }
      }
    } catch (e) {
      debugPrint("Flexible vehicle lookup error: $e");
    }

    return null;
  }

  Future<LoginResult> login(String vehicleNo, String mobile, String password) async {
    try {
      final doc = await _findVehicleDoc(vehicleNo, mobile, password);
      if (doc != null && doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final currentSessionId = data['currentSessionId'] as String?;
        
        if (currentSessionId != null && currentSessionId.isNotEmpty) {
          return LoginResult.alreadyLoggedIn;
        }

        return await _completeLogin(doc);
      }
    } catch (e) {
      debugPrint("Login error: $e");
    }
    return LoginResult.failed;
  }

  Future<LoginResult> forceLogin(String vehicleNo, String mobile, String password) async {
    try {
      final doc = await _findVehicleDoc(vehicleNo, mobile, password);
      if (doc != null && doc.exists) {
        return await _completeLogin(doc);
      }
    } catch (e) {
      debugPrint("Force login error: $e");
    }
    return LoginResult.failed;
  }

  Future<LoginResult> _completeLogin(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final vehicleNo = (data['vehicleNumber'] ?? doc.id).toString();
    final assignedWard = data['assignedWard'] as String? ?? 'Unknown Ward';
    final name = data.containsKey('driverName') ? data['driverName'] as String? : null;
    
    _sessionId = _generateSessionId();
    
    // Ensure we have a Device ID before logging in
    await _generateDeviceIdIfNotExists();
    
    // Write new session ID and device ID to Firestore
    await doc.reference.update({
      'currentSessionId': _sessionId,
      'currentDeviceId': _deviceId,
    });
    
    try {
      await FirebaseFirestore.instance.collection('device_logs').add({
        'deviceId': _deviceId,
        'vehicleNumber': vehicleNo,
        'driverName': name ?? 'Unknown Driver',
        'deviceType': kIsWeb ? 'Website' : 'App',
        'loginTime': FieldValue.serverTimestamp(),
        'logoutTime': null,
        'isActive': true,
      });
    } catch (e) {
      debugPrint("Device logging error: $e");
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    if (name != null) await prefs.setString('driverName', name);
    await prefs.setString('vehicleNumber', vehicleNo);
    await prefs.setString('assignedWard', assignedWard);
    await prefs.setString('sessionId', _sessionId!);
    
    _isLoggedIn = true;
    _driverName = name;
    _vehicleNumber = vehicleNo;
    
    _startSessionListener();
    notifyListeners();
    return LoginResult.success;
  }

  void _startSessionListener() {
    _sessionSub?.cancel();
    if (_vehicleNumber == null || _sessionId == null) return;
    
    _sessionSub = FirebaseFirestore.instance
        .collection('vehicles')
        .where('vehicleNumber', isEqualTo: _vehicleNumber)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        final remoteSessionId = data['currentSessionId'] as String?;
        if (remoteSessionId != null && remoteSessionId != _sessionId) {
          // Session hijacked by another device
          logout(remoteForced: true);
        }
      }
    });
  }

  Future<void> logout({bool remoteForced = false}) async {
    _sessionSub?.cancel();
    _sessionSub = null;
    
    if (!remoteForced && _vehicleNumber != null) {
      // Clear session from Firestore if user manually logs out
      try {
        final activeLogSnapshot = await FirebaseFirestore.instance
            .collection('device_logs')
            .where('deviceId', isEqualTo: _deviceId)
            .where('isActive', isEqualTo: true)
            .limit(1)
            .get();
        if (activeLogSnapshot.docs.isNotEmpty) {
           await activeLogSnapshot.docs.first.reference.update({
             'logoutTime': FieldValue.serverTimestamp(),
             'isActive': false
           });
        }
      } catch (_) {}

      try {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('vehicles')
            .where('vehicleNumber', isEqualTo: _vehicleNumber)
            .limit(1)
            .get();
        if (querySnapshot.docs.isNotEmpty) {
          await querySnapshot.docs.first.reference.update({
            'currentSessionId': FieldValue.delete(),
            'currentDeviceId': FieldValue.delete(),
          });
        }
        
        // Remove from live_tracking so it disappears from the authority map
        await FirebaseFirestore.instance.collection('live_tracking').doc(_vehicleNumber).delete();
      } catch (_) {}
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _isLoggedIn = false;
    _driverName = null;
    _vehicleNumber = null;
    _sessionId = null;
    notifyListeners();
  }
}
