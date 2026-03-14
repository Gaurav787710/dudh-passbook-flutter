class Advance {
  int? id;
  int farmerId;
  String farmerCode;
  String farmerName;
  DateTime date;
  double amount;
  String type; // 'advance' or 'loan'
  String? remarks;
  bool isPaid;
  int? dairyId;

  Advance({
    this.id,
    required this.farmerId,
    required this.farmerCode,
    required this.farmerName,
    required this.date,
    required this.amount,
    this.type = 'advance',
    this.remarks,
    this.isPaid = false,
    this.dairyId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'farmerId': farmerId,
      'farmerCode': farmerCode,
      'farmerName': farmerName,
      'date': date.toIso8601String(),
      'amount': amount,
      'type': type,
      'remarks': remarks,
      'isPaid': isPaid ? 1 : 0,
      'dairyId': dairyId,
    };
  }

  factory Advance.fromMap(Map<String, dynamic> map) {
    return Advance(
      id: map['id'],
      farmerId: (map['farmerId'] as num?)?.toInt() ?? 0,
      farmerCode: map['farmerCode'] ?? '',
      farmerName: map['farmerName'] ?? '',
      date: DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      type: map['type'] ?? 'advance',
      remarks: map['remarks'],
      isPaid: map['isPaid'] == 1,
      dairyId: (map['dairyId'] as num?)?.toInt(),
    );
  }
}
