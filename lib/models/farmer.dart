class Farmer {
  int? id;
  String code;
  String name;
  String? fatherName;
  String mobile;
  String cattleType; // 'cow' or 'buffalo' — default cattle type
  bool useFixedRate;
  double? fixedRate; // Legacy single fixed rate (backward compat)
  double? cowFixedRate; // Fixed rate for cow milk (optional)
  double? buffaloFixedRate; // Fixed rate for buffalo milk (optional)
  double currentBalance;
  DateTime createdAt;
  bool isActive;
  int? dairyId;

  Farmer({
    this.id,
    required this.code,
    required this.name,
    this.fatherName,
    required this.mobile,
    required this.cattleType,
    this.useFixedRate = false,
    this.fixedRate,
    this.cowFixedRate,
    this.buffaloFixedRate,
    this.currentBalance = 0.0,
    DateTime? createdAt,
    this.isActive = true,
    this.dairyId,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Get the fixed rate for a specific cattle/milk type.
  /// Falls back to legacy fixedRate if per-type rate is not set.
  double? getFixedRateForType(String milkType) {
    if (!useFixedRate) return null;
    if (milkType == 'cow') {
      return cowFixedRate ?? fixedRate;
    } else if (milkType == 'buffalo') {
      return buffaloFixedRate ?? fixedRate;
    }
    return fixedRate;
  }

  /// Whether this farmer has a fixed rate for the given milk type.
  bool hasFixedRateForType(String milkType) {
    return getFixedRateForType(milkType) != null;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'fatherName': fatherName,
      'mobile': mobile,
      'cattleType': cattleType,
      'useFixedRate': useFixedRate ? 1 : 0,
      'fixedRate': fixedRate,
      'cowFixedRate': cowFixedRate,
      'buffaloFixedRate': buffaloFixedRate,
      'currentBalance': currentBalance,
      'createdAt': createdAt.toIso8601String(),
      'isActive': isActive ? 1 : 0,
      'dairyId': dairyId,
    };
  }

  factory Farmer.fromMap(Map<String, dynamic> map) {
    return Farmer(
      id: map['id'],
      code: map['code'] ?? '',
      name: map['name'] ?? '',
      fatherName: map['fatherName'],
      mobile: map['mobile'] ?? '',
      cattleType: map['cattleType'] ?? 'cow',
      useFixedRate: map['useFixedRate'] == 1 || map['useFixedRate'] == true,
      fixedRate: (map['fixedRate'] as num?)?.toDouble(),
      cowFixedRate: (map['cowFixedRate'] as num?)?.toDouble(),
      buffaloFixedRate: (map['buffaloFixedRate'] as num?)?.toDouble(),
      currentBalance: (map['currentBalance'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
      isActive: map['isActive'] == 1 || map['isActive'] == true,
      dairyId: (map['dairyId'] as num?)?.toInt(),
    );
  }

  // Override equality for DropdownButton to work correctly
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Farmer && other.id == id && other.code == code;
  }

  @override
  int get hashCode => id.hashCode ^ code.hashCode;
}
