import 'package:shared_preferences/shared_preferences.dart';

/// Centralized rate calculation utility for milk pricing.
/// Used by milk_entry_screen, entry_history_screen, and rate_chart_screen.
/// Ensures consistent rate calculation across the entire app.
class RateCalculator {
  // Buffalo settings
  double buffaloPerKgFatRate = 820.0;

  // Cow settings
  double cowEfuRate = 382.69;
  double cowDefaultSnf = 8.5;

  // SNF deduction settings (Buffalo) — values are PERCENTAGE deductions (e.g., 2.0 = 2%)
  double buffaloSnf88to89Deduction = 2.0;
  double buffaloSnf85to87Deduction = 4.0;
  double buffaloSnf84Penalty = 7.5;   // Fixed: was 75% (farmer got only 25%), now 7.5%
  double buffaloLowQualityPenalty = 7.5; // Fixed: was 75%, now 7.5%

  // SNF deduction settings (Cow) — values are PERCENTAGE deductions
  double cowSnf83to84Deduction = 2.0;
  double cowSnf81to82Deduction = 4.0;
  double cowHighFatDeduction = 15.0;
  double cowSnf80Penalty = 7.5;   // Fixed: was 75% (farmer got only 25%), now 7.5%
  double cowLowFatPenalty = 7.5;  // Fixed: was 50%, now 7.5%

  /// Load all rate settings from SharedPreferences
  Future<void> loadSettings(SharedPreferences prefs) async {
    buffaloPerKgFatRate = prefs.getDouble('buffaloPerKgFatRate') ?? 820.0;
    cowEfuRate = prefs.getDouble('cowEfuRate') ?? 382.69;
    cowDefaultSnf = prefs.getDouble('cowDefaultSnf') ?? 8.5;

    buffaloSnf88to89Deduction = prefs.getDouble('buffaloSnf88to89Deduction') ?? 2.0;
    buffaloSnf85to87Deduction = prefs.getDouble('buffaloSnf85to87Deduction') ?? 4.0;
    buffaloSnf84Penalty = prefs.getDouble('buffaloSnf84Penalty') ?? 7.5;
    buffaloLowQualityPenalty = prefs.getDouble('buffaloLowQualityPenalty') ?? 7.5;

    cowSnf83to84Deduction = prefs.getDouble('cowSnf83to84Deduction') ?? 2.0;
    cowSnf81to82Deduction = prefs.getDouble('cowSnf81to82Deduction') ?? 4.0;
    cowHighFatDeduction = prefs.getDouble('cowHighFatDeduction') ?? 15.0;
    cowSnf80Penalty = prefs.getDouble('cowSnf80Penalty') ?? 7.5;
    cowLowFatPenalty = prefs.getDouble('cowLowFatPenalty') ?? 7.5;
  }

  /// Calculate rate based on cattle type, fat, and SNF
  double calculateRate(String cattleType, double fat, double? snf) {
    if (cattleType.toLowerCase() == 'buffalo') {
      return calculateBuffaloRate(fat, snf ?? 9.0);
    } else {
      return calculateCowRate(fat, snf ?? cowDefaultSnf);
    }
  }

  /// Buffalo rate calculation with per-0.1-step SNF deduction
  /// Each 0.1 SNF below 9.0 adds the zone's deduction % (like cow where each 0.1 changes rate)
  double calculateBuffaloRate(double fat, double snf) {
    double baseRate = fat * buffaloPerKgFatRate / 100;

    // Clamp penalty percentages to safe range [0, 50] to prevent accidental 75%+ deductions
    final snf88Ded = buffaloSnf88to89Deduction.clamp(0.0, 50.0);
    final snf85Ded = buffaloSnf85to87Deduction.clamp(0.0, 50.0);
    final snf84Pen = buffaloSnf84Penalty.clamp(0.0, 50.0);
    final lowQPen = buffaloLowQualityPenalty.clamp(0.0, 50.0);

    if (snf >= 9.0 && fat >= 5.1) {
      return baseRate; // Premium quality — no deduction
    } else if (fat <= 5.0 && snf <= 9.0) {
      return baseRate * (1 - lowQPen / 100);
    }

    if (snf >= 9.0) return baseRate;

    // Per-0.1-step SNF deduction: each step adds its zone's % deduction
    int totalSteps = ((9.0 - snf) * 10).round();
    double totalDeduction = 0;

    for (int i = 1; i <= totalSteps; i++) {
      double stepSnf = (90 - i) / 10.0; // 8.9, 8.8, 8.7, ...

      if (stepSnf >= 8.8) {
        totalDeduction += snf88Ded;     // Zone: 8.8-8.9
      } else if (stepSnf >= 8.5) {
        totalDeduction += snf85Ded;     // Zone: 8.5-8.7
      } else if (stepSnf >= 8.4) {
        totalDeduction += snf84Pen;     // Zone: 8.4
      } else {
        totalDeduction += lowQPen;      // Zone: below 8.4
      }
    }

    // Cap total deduction at 50%
    totalDeduction = totalDeduction.clamp(0.0, 50.0);
    return baseRate * (1 - totalDeduction / 100);
  }

  /// Cow rate calculation with EFU formula and SNF deduction
  /// Deduction values are percentages: 2% = ₹ rate * 0.98
  double calculateCowRate(double fat, double snf) {
    if (fat < 3.0) {
      return 0.0;
    }

    final snfEfu = snf * (2 / 3);
    final totalEfu = fat + snfEfu;
    double baseRate = totalEfu * cowEfuRate / 100;

    // Clamp penalty percentages to safe range [0, 50] to prevent accidental 75%+ deductions
    final highFatDed = cowHighFatDeduction.clamp(0.0, 50.0);
    final snf83Ded = cowSnf83to84Deduction.clamp(0.0, 50.0);
    final snf81Ded = cowSnf81to82Deduction.clamp(0.0, 50.0);
    final snf80Pen = cowSnf80Penalty.clamp(0.0, 50.0);

    if (fat >= 5.1 && snf >= 8.5) {
      return baseRate * (1 - highFatDed / 100);
    } else if (snf >= 8.5 && fat >= 3.0 && fat <= 5.0) {
      return baseRate; // Normal quality — no deduction
    } else if (snf >= 8.3 && snf < 8.5) {
      return baseRate * (1 - snf83Ded / 100);
    } else if (snf >= 8.1 && snf < 8.3) {
      return baseRate * (1 - snf81Ded / 100);
    } else if (snf >= 8.0 && snf < 8.1) {
      return baseRate * (1 - snf80Pen / 100);
    } else if (snf < 8.0) {
      return baseRate * (1 - snf80Pen / 100);
    }
    return baseRate;
  }

  /// Simple buffalo base rate (for rate chart grid display only)
  double calcBuffaloBaseRate(double fat) {
    return fat * buffaloPerKgFatRate / 100;
  }

  /// Simple cow base rate (for rate chart grid display only)
  double calcCowBaseRate(double fat, double snf) {
    final snfEfu = snf * (2 / 3);
    final totalEfu = fat + snfEfu;
    return totalEfu * cowEfuRate / 100;
  }
}
