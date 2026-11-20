class GarbageVehicleModel {
  final String vehicleId;
  final String vehicleNumber;
  final double currentLatitude;
  final double currentLongitude;
  final String status; // Active, In Route, Idle, Offline
  final int etaMinutes;
  final String assignedRoute;
  final DateTime lastUpdatedTimestamp;
  final String driverName;
  final String? phoneNumber;
  final String? ward;
  final String? zone;
  final double speed;
  final bool isActive;
  final double? distanceMeters;

  GarbageVehicleModel({
    required this.vehicleId,
    required this.vehicleNumber,
    required this.currentLatitude,
    required this.currentLongitude,
    required this.status,
    required this.etaMinutes,
    required this.assignedRoute,
    required this.lastUpdatedTimestamp,
    this.driverName = 'Fleet Driver',
    this.phoneNumber,
    this.ward,
    this.zone,
    this.speed = 0.0,
    this.isActive = true,
    this.distanceMeters,
  });

  GarbageVehicleModel copyWith({
    String? vehicleId,
    String? vehicleNumber,
    double? currentLatitude,
    double? currentLongitude,
    String? status,
    int? etaMinutes,
    String? assignedRoute,
    DateTime? lastUpdatedTimestamp,
    String? driverName,
    String? phoneNumber,
    String? ward,
    String? zone,
    double? speed,
    bool? isActive,
    double? distanceMeters,
  }) {
    return GarbageVehicleModel(
      vehicleId: vehicleId ?? this.vehicleId,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      currentLatitude: currentLatitude ?? this.currentLatitude,
      currentLongitude: currentLongitude ?? this.currentLongitude,
      status: status ?? this.status,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      assignedRoute: assignedRoute ?? this.assignedRoute,
      lastUpdatedTimestamp: lastUpdatedTimestamp ?? this.lastUpdatedTimestamp,
      driverName: driverName ?? this.driverName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      ward: ward ?? this.ward,
      zone: zone ?? this.zone,
      speed: speed ?? this.speed,
      isActive: isActive ?? this.isActive,
      distanceMeters: distanceMeters ?? this.distanceMeters,
    );
  }

  factory GarbageVehicleModel.fromJson(Map<String, dynamic> json) {
    return GarbageVehicleModel(
      vehicleId: (json['vehicleId'] ?? json['id'] ?? '').toString(),
      vehicleNumber: (json['vehicleNumber'] ?? json['id'] ?? '').toString(),
      currentLatitude: ((json['currentLatitude'] ?? json['lat'] ?? 0.0) as num).toDouble(),
      currentLongitude: ((json['currentLongitude'] ?? json['lng'] ?? 0.0) as num).toDouble(),
      status: (json['status'] ?? (json['isActive'] == true ? 'In Route' : 'Idle')).toString(),
      etaMinutes: ((json['etaMinutes'] ?? 5) as num).toInt(),
      assignedRoute: (json['assignedRoute'] ?? json['assignedWard'] ?? 'Ward Route').toString(),
      lastUpdatedTimestamp: json['lastUpdatedTimestamp'] != null 
          ? DateTime.parse(json['lastUpdatedTimestamp'].toString())
          : (json['timestamp'] != null ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now() : DateTime.now()),
      driverName: (json['driverName'] ?? 'Fleet Driver').toString(),
      phoneNumber: json['phoneNumber']?.toString(),
      ward: json['ward']?.toString() ?? json['assignedWard']?.toString(),
      zone: json['zone']?.toString(),
      speed: ((json['speed'] ?? 0.0) as num).toDouble(),
      isActive: json['isActive'] as bool? ?? true,
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vehicleId': vehicleId,
      'vehicleNumber': vehicleNumber,
      'currentLatitude': currentLatitude,
      'currentLongitude': currentLongitude,
      'status': status,
      'etaMinutes': etaMinutes,
      'assignedRoute': assignedRoute,
      'lastUpdatedTimestamp': lastUpdatedTimestamp.toIso8601String(),
      'driverName': driverName,
      'phoneNumber': phoneNumber,
      'ward': ward,
      'zone': zone,
      'speed': speed,
      'isActive': isActive,
      'distanceMeters': distanceMeters,
    };
  }
}
