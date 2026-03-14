import 'package:uuid/uuid.dart';

class MilkEntry {
  int? id;
  int farmerId;
  String farmerCode;
  String farmerName;
  String? farmerFatherName;
  DateTime dateTime;
  String shift; // 'morning' or 'evening'
  double quantity; // in liters or kg
  double fat;
  double? snf;
  double rate;
  double amount;
  String cattleType;
  String? collectorName;
  bool isLabTested;
  bool isPending; // For Quick Entry Mode - pending FAT/SNF
  int? createdByUserId;
  String? createdByUserName;
  int? dairyId;
  String syncId; // UUID for cloud sync dedup

  MilkEntry({
    this.id,
    required this.farmerId,
    required this.farmerCode,
    required this.farmerName,
    this.farmerFatherName,
    required this.dateTime,
    required this.shift,
    required this.quantity,
    required this.fat,
    this.snf,
    required this.rate,
    required this.amount,
    required this.cattleType,
    this.collectorName,
    this.isLabTested = true,
    this.isPending = false,
    this.createdByUserId,
    this.createdByUserName,
    this.dairyId,
    String? syncId,
  }) : syncId = syncId ?? const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'farmerId': farmerId,
      'farmerCode': farmerCode,
      'farmerName': farmerName,
      'farmerFatherName': farmerFatherName,
      'dateTime': dateTime.toIso8601String(),
      'shift': shift,
      'quantity': quantity,
      'fat': fat,
      'snf': snf,
      'rate': rate,
      'amount': amount,
      'cattleType': cattleType,
      'collectorName': collectorName,
      'isLabTested': isLabTested ? 1 : 0,
      'isPending': isPending ? 1 : 0,
      'createdByUserId': createdByUserId,
      'createdByUserName': createdByUserName,
      'dairyId': dairyId,
      'syncId': syncId,
    };
  }

  factory MilkEntry.fromMap(Map<String, dynamic> map) {
    return MilkEntry(
      id: map['id'],
      farmerId: (map['farmerId'] as num?)?.toInt() ?? 0,
      farmerCode: map['farmerCode'] ?? '',
      farmerName: map['farmerName'] ?? '',
      farmerFatherName: map['farmerFatherName'],
      dateTime: DateTime.tryParse(map['dateTime']?.toString() ?? '') ?? DateTime.now(),
      shift: map['shift'] ?? 'morning',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      fat: (map['fat'] as num?)?.toDouble() ?? 0.0,
      snf: (map['snf'] as num?)?.toDouble(),
      rate: (map['rate'] as num?)?.toDouble() ?? 0.0,
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      cattleType: map['cattleType'] ?? 'cow',
      collectorName: map['collectorName'],
      isLabTested: map['isLabTested'] == 1,
      isPending: map['isPending'] == 1,
      createdByUserId: (map['createdByUserId'] as num?)?.toInt(),
      createdByUserName: map['createdByUserName'],
      dairyId: (map['dairyId'] as num?)?.toInt(),
      syncId: map['syncId'] as String?,
    );
  }
}
