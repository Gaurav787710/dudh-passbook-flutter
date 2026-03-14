import 'package:uuid/uuid.dart';

class Payment {
  int? id;
  int farmerId;
  String farmerCode;
  String farmerName;
  DateTime paymentDate;
  DateTime? fromDate;
  DateTime? toDate;
  String type; // 'PAYMENT' or 'ADVANCE'
  double amount; // Total amount (for PAYMENT = total milk amount, for ADVANCE = advance amount)
  double advanceDeduction;
  double netAmount;
  double totalLiters;
  String paymentMode; // 'cash', 'upi', 'bank'
  String? transactionId;
  String? notes;
  bool? isPaid; // For ADVANCE: whether it's been deducted from payment
  int? dairyId;
  String syncId; // UUID for cloud sync dedup

  // Legacy getter for totalAmount compatibility
  double get totalAmount => amount;

  Payment({
    this.id,
    required this.farmerId,
    required this.farmerCode,
    required this.farmerName,
    required this.paymentDate,
    this.fromDate,
    this.toDate,
    this.type = 'PAYMENT',
    required this.amount,
    this.advanceDeduction = 0.0,
    required this.netAmount,
    required this.totalLiters,
    this.paymentMode = 'cash',
    this.transactionId,
    this.notes,
    this.isPaid,
    this.dairyId,
    String? syncId,
  }) : syncId = syncId ?? const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'farmerId': farmerId,
      'farmerCode': farmerCode,
      'farmerName': farmerName,
      'paymentDate': paymentDate.toIso8601String(),
      'fromDate': fromDate?.toIso8601String(),
      'toDate': toDate?.toIso8601String(),
      'type': type,
      'totalAmount': amount,
      'advanceDeduction': advanceDeduction,
      'netAmount': netAmount,
      'totalLiters': totalLiters,
      'paymentMode': paymentMode,
      'transactionId': transactionId,
      'notes': notes,
      'isPaid': isPaid == true ? 1 : 0,
      'dairyId': dairyId,
      'syncId': syncId,
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: map['id'],
      farmerId: (map['farmerId'] as num?)?.toInt() ?? 0,
      farmerCode: map['farmerCode']?.toString() ?? '',
      farmerName: map['farmerName']?.toString() ?? '',
      paymentDate: DateTime.tryParse(map['paymentDate']?.toString() ?? '') ?? DateTime.now(),
      fromDate: map['fromDate'] != null ? DateTime.tryParse(map['fromDate'].toString()) : null,
      toDate: map['toDate'] != null ? DateTime.tryParse(map['toDate'].toString()) : null,
      type: map['type'] ?? 'PAYMENT',
      amount: (map['totalAmount'] as num?)?.toDouble() ?? (map['amount'] as num?)?.toDouble() ?? 0.0,
      advanceDeduction: (map['advanceDeduction'] as num?)?.toDouble() ?? 0.0,
      netAmount: (map['netAmount'] as num?)?.toDouble() ?? 0.0,
      totalLiters: (map['totalLiters'] as num?)?.toDouble() ?? 0.0,
      paymentMode: map['paymentMode'] ?? 'cash',
      transactionId: map['transactionId'],
      notes: map['notes'] ?? map['remarks'],
      isPaid: map['isPaid'] == 1,
      dairyId: (map['dairyId'] as num?)?.toInt(),
      syncId: map['syncId'] as String?,
    );
  }
}

