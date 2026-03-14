class RateChart {
  int? id;
  String cattleType; // 'cow' or 'buffalo'
  double fatMin;
  double fatMax;
  double snfMin;
  double snfMax;
  double rate;
  String calculationType; // 'fat_only', 'fat_snf', 'kg_fat_kg_snf'
  int? dairyId;

  RateChart({
    this.id,
    required this.cattleType,
    required this.fatMin,
    required this.fatMax,
    required this.snfMin,
    required this.snfMax,
    required this.rate,
    this.calculationType = 'fat_snf',
    this.dairyId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cattleType': cattleType,
      'fatMin': fatMin,
      'fatMax': fatMax,
      'snfMin': snfMin,
      'snfMax': snfMax,
      'rate': rate,
      'calculationType': calculationType,
      'dairyId': dairyId,
    };
  }

  factory RateChart.fromMap(Map<String, dynamic> map) {
    return RateChart(
      id: map['id'],
      cattleType: map['cattleType'] ?? 'cow',
      fatMin: (map['fatMin'] as num?)?.toDouble() ?? 0.0,
      fatMax: (map['fatMax'] as num?)?.toDouble() ?? 0.0,
      snfMin: (map['snfMin'] as num?)?.toDouble() ?? 0.0,
      snfMax: (map['snfMax'] as num?)?.toDouble() ?? 0.0,
      rate: (map['rate'] as num?)?.toDouble() ?? 0.0,
      calculationType: map['calculationType'] ?? 'fat_snf',
      dairyId: (map['dairyId'] as num?)?.toInt(),
    );
  }
}
