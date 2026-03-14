import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/farmer.dart';
import '../models/milk_entry.dart';
import '../models/payment.dart';
import '../models/rate_chart.dart';
import '../models/advance.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static Completer<Database>? _initCompleter;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<Database>();
    try {
      _database = await _initDB('dairymaster.db');
      _initCompleter!.complete(_database!);
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 13,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add users table in version 2
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          mobile TEXT NOT NULL UNIQUE,
          password TEXT NOT NULL,
          role TEXT NOT NULL,
          dairyName TEXT,
          createdAt TEXT NOT NULL,
          isActive INTEGER NOT NULL DEFAULT 1
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_user_mobile ON users(mobile)',
      );
    }
    if (oldVersion < 3) {
      // Add createdByUserId column to milk_entries in version 3
      await db.execute(
        'ALTER TABLE milk_entries ADD COLUMN createdByUserId INTEGER',
      );
      await db.execute(
        'ALTER TABLE milk_entries ADD COLUMN createdByUserName TEXT',
      );
    }
    if (oldVersion < 4) {
      // Add dairyId to all tables for data isolation between different admin accounts
      await db.execute('ALTER TABLE users ADD COLUMN dairyId INTEGER');
      await db.execute('ALTER TABLE farmers ADD COLUMN dairyId INTEGER');
      await db.execute('ALTER TABLE milk_entries ADD COLUMN dairyId INTEGER');
      await db.execute('ALTER TABLE payments ADD COLUMN dairyId INTEGER');
      await db.execute('ALTER TABLE advances ADD COLUMN dairyId INTEGER');
      await db.execute('ALTER TABLE rate_chart ADD COLUMN dairyId INTEGER');
      // Create index for faster queries
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_farmer_dairy ON farmers(dairyId)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_entry_dairy ON milk_entries(dairyId)',
      );
    }
    if (oldVersion < 5) {
      // Remove global UNIQUE constraint on farmers.code - make it unique per dairyId
      // SQLite doesn't support DROP CONSTRAINT, so we recreate the table
      await db.execute('DROP INDEX IF EXISTS sqlite_autoindex_farmers_1');
      // Create new composite unique index for code + dairyId
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_farmer_code_dairy ON farmers(code, dairyId)',
      );
    }
    if (oldVersion < 6) {
      // Add fatherName column to farmers table
      await db.execute('ALTER TABLE farmers ADD COLUMN fatherName TEXT');
    }
    if (oldVersion < 7) {
      // Add isPending column to milk_entries for Quick Entry Mode
      await db.execute(
        'ALTER TABLE milk_entries ADD COLUMN isPending INTEGER DEFAULT 0',
      );
    }
    if (oldVersion < 8) {
      // Add additional staff fields for website sync compatibility
      await db.execute('ALTER TABLE users ADD COLUMN username TEXT');
      await db.execute('ALTER TABLE users ADD COLUMN fatherName TEXT');
      await db.execute('ALTER TABLE users ADD COLUMN email TEXT');
      await db.execute('ALTER TABLE users ADD COLUMN address TEXT');
      await db.execute('ALTER TABLE users ADD COLUMN aadhar TEXT');
      await db.execute('ALTER TABLE users ADD COLUMN pan TEXT');
      await db.execute('ALTER TABLE users ADD COLUMN bankAccount TEXT');
      await db.execute('ALTER TABLE users ADD COLUMN ifsc TEXT');
    }
    if (oldVersion < 9) {
      // Add type, notes, isPaid fields to payments table for advance tracking
      await db.execute(
        "ALTER TABLE payments ADD COLUMN type TEXT DEFAULT 'PAYMENT'",
      );
      await db.execute('ALTER TABLE payments ADD COLUMN notes TEXT');
      await db.execute(
        'ALTER TABLE payments ADD COLUMN isPaid INTEGER DEFAULT 0',
      );
    }
    if (oldVersion < 10) {
      // Add syncId (UUID) for cloud sync dedup
      await db.execute('ALTER TABLE milk_entries ADD COLUMN syncId TEXT');
    }
    if (oldVersion < 11) {
      // Add farmerFatherName to milk_entries (model had it but table didn't)
      await db.execute('ALTER TABLE milk_entries ADD COLUMN farmerFatherName TEXT');
    }
    if (oldVersion < 12) {
      // Add syncId to payments for cloud sync dedup (same as milk_entries)
      await db.execute('ALTER TABLE payments ADD COLUMN syncId TEXT');
    }
    if (oldVersion < 13) {
      // Add per-cattleType fixed rates for cow and buffalo
      await db.execute('ALTER TABLE farmers ADD COLUMN cowFixedRate REAL');
      await db.execute('ALTER TABLE farmers ADD COLUMN buffaloFixedRate REAL');
      // Migrate existing fixedRate → appropriate per-type column
      await db.execute('''
        UPDATE farmers
        SET cowFixedRate = fixedRate
        WHERE useFixedRate = 1 AND fixedRate IS NOT NULL AND cattleType = 'cow'
      ''');
      await db.execute('''
        UPDATE farmers
        SET buffaloFixedRate = fixedRate
        WHERE useFixedRate = 1 AND fixedRate IS NOT NULL AND cattleType = 'buffalo'
      ''');
    }
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const realType = 'REAL NOT NULL';
    const intType = 'INTEGER NOT NULL';

    // Farmers Table - code is unique per dairyId, not globally
    await db.execute('''
      CREATE TABLE farmers (
        id $idType,
        code $textType,
        name $textType,
        fatherName TEXT,
        mobile $textType,
        cattleType $textType,
        useFixedRate $intType,
        fixedRate REAL,
        cowFixedRate REAL,
        buffaloFixedRate REAL,
        currentBalance $realType,
        createdAt $textType,
        isActive $intType,
        dairyId INTEGER,
        UNIQUE(code, dairyId)
      )
    ''');

    // Milk Entries Table
    await db.execute('''
      CREATE TABLE milk_entries (
        id $idType,
        farmerId $intType,
        farmerCode $textType,
        farmerName $textType,
        farmerFatherName TEXT,
        dateTime $textType,
        shift $textType,
        quantity $realType,
        fat $realType,
        snf REAL,
        rate $realType,
        amount $realType,
        cattleType $textType,
        collectorName TEXT,
        isLabTested $intType,
        isPending INTEGER DEFAULT 0,
        createdByUserId INTEGER,
        createdByUserName TEXT,
        dairyId INTEGER,
        syncId TEXT
      )
    ''');

    // Payments Table
    await db.execute('''
      CREATE TABLE payments (
        id $idType,
        farmerId $intType,
        farmerCode $textType,
        farmerName $textType,
        paymentDate $textType,
        fromDate TEXT,
        toDate TEXT,
        type TEXT DEFAULT 'PAYMENT',
        totalAmount $realType,
        advanceDeduction $realType,
        netAmount $realType,
        totalLiters $realType,
        paymentMode $textType,
        transactionId TEXT,
        notes TEXT,
        isPaid INTEGER DEFAULT 0,
        dairyId INTEGER,
        syncId TEXT
      )
    ''');

    // Rate Chart Table
    await db.execute('''
      CREATE TABLE rate_chart (
        id $idType,
        cattleType $textType,
        fatMin $realType,
        fatMax $realType,
        snfMin $realType,
        snfMax $realType,
        rate $realType,
        calculationType $textType,
        dairyId INTEGER
      )
    ''');

    // Advances Table
    await db.execute('''
      CREATE TABLE advances (
        id $idType,
        farmerId $intType,
        farmerCode $textType,
        farmerName $textType,
        date $textType,
        amount $realType,
        type $textType,
        remarks TEXT,
        isPaid $intType,
        dairyId INTEGER
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_farmer_code ON farmers(code)');
    await db.execute('CREATE INDEX idx_milk_date ON milk_entries(dateTime)');
    await db.execute('CREATE INDEX idx_farmer_id ON milk_entries(farmerId)');
    await db.execute('CREATE INDEX idx_farmer_dairy ON farmers(dairyId)');
    await db.execute('CREATE INDEX idx_entry_dairy ON milk_entries(dairyId)');

    // Users Table for authentication
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        mobile TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL,
        role TEXT NOT NULL,
        dairyName TEXT,
        dairyId INTEGER,
        username TEXT,
        fatherName TEXT,
        email TEXT,
        address TEXT,
        aadhar TEXT,
        pan TEXT,
        bankAccount TEXT,
        ifsc TEXT,
        createdAt TEXT NOT NULL,
        isActive INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('CREATE INDEX idx_user_mobile ON users(mobile)');
  }

  // ===== USER AUTHENTICATION OPERATIONS =====

  // Check if mobile number already exists
  Future<bool> isMobileExists(String mobile) async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'mobile = ?',
      whereArgs: [mobile],
    );
    return result.isNotEmpty;
  }

  // Create new user account
  Future<int> createUser({
    required String name,
    required String mobile,
    required String password,
    required String role,
    String? dairyName,
    int? dairyId,
    String? username,
    String? fatherName,
    String? email,
    String? address,
    String? aadhar,
    String? pan,
    String? bankAccount,
    String? ifsc,
  }) async {
    final db = await database;
    final userId = await db.insert('users', {
      'name': name,
      'mobile': mobile,
      'password': password,
      'role': role,
      'dairyName': dairyName,
      'dairyId': dairyId,
      'username': username ?? mobile, // Default username to mobile
      'fatherName': fatherName,
      'email': email,
      'address': address,
      'aadhar': aadhar,
      'pan': pan,
      'bankAccount': bankAccount,
      'ifsc': ifsc,
      'createdAt': DateTime.now().toIso8601String(),
      'isActive': 1,
    });

    // If this is an admin account, set dairyId = their own userId
    if (role == 'admin' && dairyId == null) {
      await db.update(
        'users',
        {'dairyId': userId},
        where: 'id = ?',
        whereArgs: [userId],
      );
    }

    return userId;
  }

  // Login with mobile and password
  Future<Map<String, dynamic>?> loginUser(
    String mobile,
    String password,
  ) async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'mobile = ? AND password = ? AND isActive = 1',
      whereArgs: [mobile, password],
    );
    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  // Get user by mobile
  Future<Map<String, dynamic>?> getUserByMobile(String mobile) async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'mobile = ?',
      whereArgs: [mobile],
    );
    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  // Get all users (filtered by dairyId for staff listing)
  Future<List<Map<String, dynamic>>> getAllUsers({int? dairyId}) async {
    final db = await database;
    if (dairyId != null) {
      return await db.query(
        'users',
        where: 'dairyId = ?',
        whereArgs: [dairyId],
        orderBy: 'createdAt DESC',
      );
    }
    return await db.query('users', orderBy: 'createdAt DESC');
  }

  // Update user password
  Future<int> updateUserPassword(int userId, String newPassword) async {
    final db = await database;
    return await db.update(
      'users',
      {'password': newPassword},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  // Update user/staff details
  Future<int> updateUser(int userId, Map<String, dynamic> updates) async {
    final db = await database;
    return await db.update(
      'users',
      updates,
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  // Delete user
  Future<int> deleteUser(int userId) async {
    final db = await database;
    return await db.delete('users', where: 'id = ?', whereArgs: [userId]);
  }

  // Get staff count (filtered by dairyId)
  Future<int> getStaffCount({int? dairyId}) async {
    final db = await database;
    if (dairyId != null) {
      final result = await db.rawQuery(
        "SELECT COUNT(*) as count FROM users WHERE role = 'staff' AND dairyId = ?",
        [dairyId],
      );
      return result.first['count'] as int;
    }
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM users WHERE role = 'staff'",
    );
    return result.first['count'] as int;
  }

  // ===== FARMER OPERATIONS =====
  Future<int> insertFarmer(Farmer farmer) async {
    final db = await database;
    return await db.insert('farmers', farmer.toMap());
  }

  Future<Farmer?> getFarmer(int id) async {
    final db = await database;
    final maps = await db.query('farmers', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return Farmer.fromMap(maps.first);
    }
    return null;
  }

  Future<Farmer?> getFarmerByCode(String code, {int? dairyId}) async {
    final db = await database;
    String whereClause = 'code = ?';
    List<dynamic> whereArgs = [code];

    if (dairyId != null) {
      whereClause += ' AND dairyId = ?';
      whereArgs.add(dairyId);
    }

    final maps = await db.query(
      'farmers',
      where: whereClause,
      whereArgs: whereArgs,
    );
    if (maps.isNotEmpty) {
      return Farmer.fromMap(maps.first);
    }
    return null;
  }

  Future<Farmer?> getFarmerByName(String name, {int? dairyId}) async {
    final db = await database;
    String whereClause = 'name = ?';
    List<dynamic> whereArgs = [name];

    if (dairyId != null) {
      whereClause += ' AND dairyId = ?';
      whereArgs.add(dairyId);
    }

    final maps = await db.query(
      'farmers',
      where: whereClause,
      whereArgs: whereArgs,
    );
    if (maps.isNotEmpty) {
      return Farmer.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Farmer>> getAllFarmers({
    bool activeOnly = true,
    int? dairyId,
  }) async {
    final db = await database;

    String? whereClause;
    List<dynamic>? whereArgs;

    if (activeOnly && dairyId != null) {
      whereClause = 'isActive = ? AND dairyId = ?';
      whereArgs = [1, dairyId];
    } else if (activeOnly) {
      whereClause = 'isActive = ?';
      whereArgs = [1];
    } else if (dairyId != null) {
      whereClause = 'dairyId = ?';
      whereArgs = [dairyId];
    }

    final result = await db.query(
      'farmers',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
    );
    return result.map((map) => Farmer.fromMap(map)).toList();
  }

  // Get next available farmer code for auto-generation
  Future<String> getNextFarmerCode({int? dairyId}) async {
    final farmers = await getAllFarmers(activeOnly: false, dairyId: dairyId);
    int maxCode = 0;

    for (var farmer in farmers) {
      // Try to parse the farmer code as integer
      final codeNum = int.tryParse(farmer.code);
      if (codeNum != null && codeNum > maxCode) {
        maxCode = codeNum;
      }
    }

    return (maxCode + 1).toString();
  }

  Future<int> updateFarmer(Farmer farmer) async {
    final db = await database;
    return await db.update(
      'farmers',
      farmer.toMap(),
      where: 'id = ?',
      whereArgs: [farmer.id],
    );
  }

  Future<int> deleteFarmer(int id) async {
    final db = await database;
    return await db.delete('farmers', where: 'id = ?', whereArgs: [id]);
  }

  // ===== MILK ENTRY OPERATIONS =====
  Future<int> insertMilkEntry(MilkEntry entry) async {
    final db = await database;
    return await db.insert('milk_entries', entry.toMap());
  }

  Future<List<MilkEntry>> getMilkEntries({
    DateTime? date,
    String? shift,
    int? farmerId,
    DateTime? startDate,
    DateTime? endDate,
    int? createdByUserId,
    int? dairyId,
  }) async {
    final db = await database;
    String? whereClause;
    List<dynamic>? whereArgs;

    if (date != null) {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      whereClause = 'dateTime >= ? AND dateTime < ?';
      whereArgs = [startOfDay.toIso8601String(), endOfDay.toIso8601String()];

      if (shift != null) {
        whereClause += ' AND shift = ?';
        whereArgs.add(shift);
      }
    } else if (startDate != null && endDate != null) {
      whereClause = 'dateTime >= ? AND dateTime <= ?';
      whereArgs = [startDate.toIso8601String(), endDate.toIso8601String()];
    }

    if (farmerId != null) {
      if (whereClause != null) {
        whereClause += ' AND farmerId = ?';
        whereArgs!.add(farmerId);
      } else {
        whereClause = 'farmerId = ?';
        whereArgs = [farmerId];
      }
    }

    // Filter by user who created the entry (for staff view)
    if (createdByUserId != null) {
      if (whereClause != null) {
        whereClause += ' AND createdByUserId = ?';
        whereArgs!.add(createdByUserId);
      } else {
        whereClause = 'createdByUserId = ?';
        whereArgs = [createdByUserId];
      }
    }

    // Filter by dairyId for data isolation between accounts
    if (dairyId != null) {
      if (whereClause != null) {
        whereClause += ' AND dairyId = ?';
        whereArgs!.add(dairyId);
      } else {
        whereClause = 'dairyId = ?';
        whereArgs = [dairyId];
      }
    }

    final result = await db.query(
      'milk_entries',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'dateTime DESC',
    );
    return result.map((map) => MilkEntry.fromMap(map)).toList();
  }

  Future<int> updateMilkEntry(MilkEntry entry) async {
    final db = await database;
    return await db.update(
      'milk_entries',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  /// Update a milk entry matched by syncId (for cloud sync updates)
  Future<int> updateMilkEntryBySyncId(MilkEntry entry) async {
    final db = await database;
    final map = entry.toMap();
    map.remove('id'); // Don't overwrite local auto-increment id
    return await db.update(
      'milk_entries',
      map,
      where: 'syncId = ?',
      whereArgs: [entry.syncId],
    );
  }

  Future<int> deleteMilkEntry(int id) async {
    final db = await database;
    return await db.delete('milk_entries', where: 'id = ?', whereArgs: [id]);
  }

  // Get pending entries (Quick Entry Mode - without FAT/SNF)
  Future<List<MilkEntry>> getPendingEntries({
    int? createdByUserId,
    int? dairyId,
  }) async {
    final db = await database;
    String whereClause = 'm.isPending = 1';
    List<dynamic> whereArgs = [];

    if (createdByUserId != null) {
      whereClause += ' AND m.createdByUserId = ?';
      whereArgs.add(createdByUserId);
    }

    if (dairyId != null) {
      whereClause += ' AND m.dairyId = ?';
      whereArgs.add(dairyId);
    }

    final result = await db.rawQuery('''
      SELECT m.*, f.fatherName as farmerFatherName
      FROM milk_entries m
      LEFT JOIN farmers f ON m.farmerId = f.id
      WHERE $whereClause
      ORDER BY m.dateTime DESC
    ''', whereArgs.isEmpty ? null : whereArgs);
    return result.map((map) => MilkEntry.fromMap(map)).toList();
  }

  // ===== PAYMENT OPERATIONS =====
  Future<int> insertPayment(Payment payment) async {
    final db = await database;
    return await db.insert('payments', payment.toMap());
  }

  Future<int> updatePayment(Payment payment) async {
    final db = await database;
    return await db.update(
      'payments',
      payment.toMap(),
      where: 'id = ?',
      whereArgs: [payment.id],
    );
  }

  Future<int> deletePayment(int id) async {
    final db = await database;
    return await db.delete('payments', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Payment>> getPayments({int? farmerId, int? dairyId, DateTime? startDate, DateTime? endDate}) async {
    final db = await database;
    String? whereClause;
    List<dynamic>? whereArgs;

    if (farmerId != null) {
      whereClause = 'farmerId = ?';
      whereArgs = [farmerId];
    }

    if (dairyId != null) {
      if (whereClause != null) {
        whereClause += ' AND dairyId = ?';
        whereArgs!.add(dairyId);
      } else {
        whereClause = 'dairyId = ?';
        whereArgs = [dairyId];
      }
    }

    if (startDate != null && endDate != null) {
      if (whereClause != null) {
        whereClause += ' AND paymentDate >= ? AND paymentDate <= ?';
        whereArgs!.addAll([startDate.toIso8601String(), endDate.toIso8601String()]);
      } else {
        whereClause = 'paymentDate >= ? AND paymentDate <= ?';
        whereArgs = [startDate.toIso8601String(), endDate.toIso8601String()];
      }
    }

    final result = await db.query(
      'payments',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'paymentDate DESC',
    );
    return result.map((map) => Payment.fromMap(map)).toList();
  }

  /// Compute pending amounts (milk money owed) for ALL farmers efficiently using SQL.
  /// Returns Map<farmerId, pendingAmount>.
  /// Pending = total milk entry amounts AFTER the farmer's last payment date.
  /// If no payments exist, pending = total of ALL milk entry amounts.
  Future<Map<int, double>> getPendingAmountsForAllFarmers({int? dairyId}) async {
    final db = await database;
    final dairyFilter = dairyId != null ? 'AND m.dairyId = ?' : '';
    final dairyFilterP = dairyId != null ? 'AND dairyId = ?' : '';
    final args = dairyId != null ? [dairyId, dairyId] : <dynamic>[];

    final result = await db.rawQuery('''
      SELECT m.farmerId, COALESCE(SUM(m.amount), 0) as pending
      FROM milk_entries m
      LEFT JOIN (
        SELECT farmerId, MAX(paymentDate) as lastPayment
        FROM payments
        WHERE type != 'ADVANCE' $dairyFilterP
        GROUP BY farmerId
      ) p ON m.farmerId = p.farmerId
      WHERE m.dateTime > COALESCE(p.lastPayment, '1900-01-01')
      $dairyFilter
      GROUP BY m.farmerId
    ''', args);

    final map = <int, double>{};
    for (var row in result) {
      final farmerId = row['farmerId'] as int?;
      final pending = row['pending'];
      if (farmerId != null) {
        map[farmerId] = (pending is num) ? pending.toDouble() : 0.0;
      }
    }
    return map;
  }

  Future<List<Payment>> getPaymentsByFarmerCode(
    String farmerCode, {
    int? dairyId,
  }) async {
    final db = await database;
    String whereClause = 'farmerCode = ?';
    List<dynamic> whereArgs = [farmerCode];

    if (dairyId != null) {
      whereClause += ' AND dairyId = ?';
      whereArgs.add(dairyId);
    }

    final result = await db.query(
      'payments',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'paymentDate DESC',
    );
    return result.map((map) => Payment.fromMap(map)).toList();
  }

  // ===== BILLING OPERATIONS =====
  Future<List<MilkEntry>> getMilkEntriesForBilling({
    required DateTime startDate,
    required DateTime endDate,
    String? farmerCode,
    int? createdByUserId,
    int? dairyId,
  }) async {
    final db = await database;

    String whereClause = 'm.dateTime >= ? AND m.dateTime <= ?';
    List<dynamic> whereArgs = [
      startDate.toIso8601String(),
      DateTime(
        endDate.year,
        endDate.month,
        endDate.day,
        23,
        59,
        59,
      ).toIso8601String(),
    ];

    if (farmerCode != null && farmerCode.isNotEmpty) {
      whereClause += ' AND m.farmerCode = ?';
      whereArgs.add(farmerCode);
    }

    // Filter by user who created the entry (for staff view)
    if (createdByUserId != null) {
      whereClause += ' AND m.createdByUserId = ?';
      whereArgs.add(createdByUserId);
    }

    // Filter by dairyId for data isolation between accounts
    if (dairyId != null) {
      whereClause += ' AND m.dairyId = ?';
      whereArgs.add(dairyId);
    }

    final result = await db.rawQuery('''
      SELECT m.*, f.fatherName as farmerFatherName
      FROM milk_entries m
      LEFT JOIN farmers f ON m.farmerId = f.id
      WHERE $whereClause
      ORDER BY m.dateTime DESC
    ''', whereArgs);
    return result.map((map) => MilkEntry.fromMap(map)).toList();
  }

  // ===== RATE CHART OPERATIONS =====
  Future<int> insertRateChart(RateChart rateChart) async {
    final db = await database;
    return await db.insert('rate_chart', rateChart.toMap());
  }

  Future<List<RateChart>> getRateCharts({String? cattleType}) async {
    final db = await database;
    final result = await db.query(
      'rate_chart',
      where: cattleType != null ? 'cattleType = ?' : null,
      whereArgs: cattleType != null ? [cattleType] : null,
      orderBy: 'fatMin ASC',
    );
    return result.map((map) => RateChart.fromMap(map)).toList();
  }

  Future<int> updateRateChart(RateChart rateChart) async {
    final db = await database;
    return await db.update(
      'rate_chart',
      rateChart.toMap(),
      where: 'id = ?',
      whereArgs: [rateChart.id],
    );
  }

  Future<int> deleteRateChart(int id) async {
    final db = await database;
    return await db.delete('rate_chart', where: 'id = ?', whereArgs: [id]);
  }

  // ===== ADVANCE OPERATIONS =====
  Future<int> insertAdvance(Advance advance) async {
    final db = await database;
    return await db.insert('advances', advance.toMap());
  }

  Future<List<Advance>> getAdvances({
    int? farmerId,
    bool unpaidOnly = false,
    int? dairyId,
  }) async {
    final db = await database;
    String? whereClause;
    List<dynamic>? whereArgs;

    if (farmerId != null && unpaidOnly) {
      whereClause = 'farmerId = ? AND isPaid = ?';
      whereArgs = [farmerId, 0];
    } else if (farmerId != null) {
      whereClause = 'farmerId = ?';
      whereArgs = [farmerId];
    } else if (unpaidOnly) {
      whereClause = 'isPaid = ?';
      whereArgs = [0];
    }

    if (dairyId != null) {
      if (whereClause != null) {
        whereClause += ' AND dairyId = ?';
        whereArgs!.add(dairyId);
      } else {
        whereClause = 'dairyId = ?';
        whereArgs = [dairyId];
      }
    }

    final result = await db.query(
      'advances',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'date DESC',
    );
    return result.map((map) => Advance.fromMap(map)).toList();
  }

  Future<double> getTotalUnpaidAdvance(int farmerId) async {
    final advances = await getAdvances(farmerId: farmerId, unpaidOnly: true);
    return advances.fold<double>(0.0, (sum, advance) => sum + advance.amount);
  }

  Future<int> updateAdvance(Advance advance) async {
    final db = await database;
    return await db.update(
      'advances',
      advance.toMap(),
      where: 'id = ?',
      whereArgs: [advance.id],
    );
  }

  // Mark all unpaid advances as paid for a farmer
  Future<void> markAdvancesPaid(int farmerId) async {
    final db = await database;
    await db.update(
      'advances',
      {'isPaid': 1},
      where: 'farmerId = ? AND isPaid = 0',
      whereArgs: [farmerId],
    );
  }

  // ===== ANALYTICS & REPORTS =====
  Future<List<Map<String, dynamic>>> getLast7DaysData({int? dairyId}) async {
    final db = await database;
    final today = DateTime.now();
    final startDate = today.subtract(const Duration(days: 7));

    // First try last 7 days
    String query = '''
      SELECT 
        DATE(dateTime) as date,
        SUM(quantity) as totalLiters,
        SUM(amount) as totalAmount,
        COUNT(*) as entries
      FROM milk_entries
      WHERE dateTime >= ?
      GROUP BY DATE(dateTime)
      ORDER BY date ASC
    ''';
    List<dynamic> args = [startDate.toIso8601String()];

    if (dairyId != null) {
      query = '''
        SELECT 
          DATE(dateTime) as date,
          SUM(quantity) as totalLiters,
          SUM(amount) as totalAmount,
          COUNT(*) as entries
        FROM milk_entries
        WHERE dateTime >= ? AND dairyId = ?
        GROUP BY DATE(dateTime)
        ORDER BY date ASC
      ''';
      args.add(dairyId);
    }

    var result = await db.rawQuery(query, args);
    
    // If no data in last 7 days, get ALL available data (for new users)
    if (result.isEmpty) {
      if (dairyId != null) {
        result = await db.rawQuery('''
          SELECT 
            DATE(dateTime) as date,
            SUM(quantity) as totalLiters,
            SUM(amount) as totalAmount,
            COUNT(*) as entries
          FROM milk_entries
          WHERE dairyId = ?
          GROUP BY DATE(dateTime)
          ORDER BY date ASC
          LIMIT 7
        ''', [dairyId]);
      } else {
        result = await db.rawQuery('''
          SELECT 
            DATE(dateTime) as date,
            SUM(quantity) as totalLiters,
            SUM(amount) as totalAmount,
            COUNT(*) as entries
          FROM milk_entries
          GROUP BY DATE(dateTime)
          ORDER BY date ASC
          LIMIT 7
        ''');
      }
    }
    
    return result;
  }

  // Get dashboard stats - enhanced for new dashboard
  Future<Map<String, dynamic>> getDashboardStats({int? dairyId}) async {
    final db = await database;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final sevenDaysAgo = startOfDay.subtract(const Duration(days: 7));
    final tenDaysAgo = startOfDay.subtract(const Duration(days: 10));

    final dairyFilter = dairyId != null ? 'AND dairyId = $dairyId' : '';
    final dairyFilterWhere = dairyId != null ? 'WHERE dairyId = $dairyId' : '';
    final dairyFilterFarmers = dairyId != null ? 'WHERE dairyId = $dairyId' : '';

    // Get today's data with morning/evening split
    final todayResult = await db.rawQuery('''
      SELECT 
        SUM(quantity) as todaysMilk,
        SUM(amount) as todaysAmount,
        SUM(CASE WHEN shift = 'morning' THEN quantity ELSE 0 END) as morningMilk,
        SUM(CASE WHEN shift = 'evening' THEN quantity ELSE 0 END) as eveningMilk,
        SUM(CASE WHEN shift = 'morning' THEN amount ELSE 0 END) as morningAmount,
        SUM(CASE WHEN shift = 'evening' THEN amount ELSE 0 END) as eveningAmount,
        COUNT(DISTINCT farmerId) as farmersCollectedToday
      FROM milk_entries
      WHERE dateTime >= ? AND dateTime < ? $dairyFilter
    ''', [startOfDay.toIso8601String(), endOfDay.toIso8601String()]);

    // Get total farmers count
    final farmersResult = await db.rawQuery('SELECT COUNT(*) as total FROM farmers $dairyFilterFarmers');
    
    // Get average milk - use up to 7 days BUT if less data exists, use all available days
    // This ensures new users see meaningful data from day 1
    final avgResult = await db.rawQuery('''
      SELECT AVG(dailyTotal) as avg7DayMilk, COUNT(*) as daysWithData FROM (
        SELECT DATE(dateTime) as dt, SUM(quantity) as dailyTotal
        FROM milk_entries
        WHERE dateTime >= ? $dairyFilter
        GROUP BY DATE(dateTime)
      )
    ''', [sevenDaysAgo.toIso8601String()]);

    // If no data in last 7 days, try all-time average
    double avg7DayMilk = (avgResult.first['avg7DayMilk'] as num?)?.toDouble() ?? 0;
    int daysWithData = (avgResult.first['daysWithData'] as num?)?.toInt() ?? 0;
    
    if (avg7DayMilk == 0 || daysWithData == 0) {
      // Use all-time average
      final allTimeAvg = await db.rawQuery('''
        SELECT AVG(dailyTotal) as avgMilk FROM (
          SELECT DATE(dateTime) as dt, SUM(quantity) as dailyTotal
          FROM milk_entries
          $dairyFilterWhere
          GROUP BY DATE(dateTime)
        )
      ''');
      avg7DayMilk = (allTimeAvg.first['avgMilk'] as num?)?.toDouble() ?? 0;
    }

    // Get payment stats for last 10 days
    int farmersPaid = 0;
    try {
      final paymentResult = await db.rawQuery('''
        SELECT 
          COUNT(DISTINCT farmerId) as farmersPaid
        FROM payments
        WHERE paymentDate >= ? $dairyFilter
      ''', [tenDaysAgo.toIso8601String()]);
      farmersPaid = (paymentResult.first['farmersPaid'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('[DatabaseHelper] payment stats error: $e');
    }

    final todayData = todayResult.first;
    final totalFarmers = (farmersResult.first['total'] as num?)?.toInt() ?? 0;
    final farmersCollectedToday = (todayData['farmersCollectedToday'] as num?)?.toInt() ?? 0;

    return {
      'todaysMilk': (todayData['todaysMilk'] as num?)?.toDouble() ?? 0,
      'todaysAmount': (todayData['todaysAmount'] as num?)?.toDouble() ?? 0,
      'morningMilk': (todayData['morningMilk'] as num?)?.toDouble() ?? 0,
      'eveningMilk': (todayData['eveningMilk'] as num?)?.toDouble() ?? 0,
      'morningAmount': (todayData['morningAmount'] as num?)?.toDouble() ?? 0,
      'eveningAmount': (todayData['eveningAmount'] as num?)?.toDouble() ?? 0,
      'totalFarmers': totalFarmers,
      'farmersCollectedToday': farmersCollectedToday,
      'avg7DayMilk': avg7DayMilk,
      'farmersPaid10Days': farmersPaid,
    };
  }

  // ===== DEMO DATA =====
  Future<void> insertDemoData() async {
    // Insert demo farmers
    await insertFarmer(
      Farmer(
        code: 'F001',
        name: 'राजेश कुमार',
        mobile: '9876543210',
        cattleType: 'buffalo',
      ),
    );

    await insertFarmer(
      Farmer(
        code: 'F002',
        name: 'सुरेश पटेल',
        mobile: '9876543211',
        cattleType: 'cow',
      ),
    );

    await insertFarmer(
      Farmer(
        code: 'F003',
        name: 'मुकेश शर्मा',
        mobile: '9876543212',
        cattleType: 'buffalo',
        useFixedRate: true,
        fixedRate: 45.0,
      ),
    );

    // Insert demo rate charts
    await insertRateChart(
      RateChart(
        cattleType: 'buffalo',
        fatMin: 6.0,
        fatMax: 7.0,
        snfMin: 8.0,
        snfMax: 9.0,
        rate: 50.0,
      ),
    );

    await insertRateChart(
      RateChart(
        cattleType: 'cow',
        fatMin: 3.5,
        fatMax: 4.5,
        snfMin: 8.0,
        snfMax: 9.0,
        rate: 35.0,
      ),
    );

    // Insert demo milk entries
    final farmer1 = await getFarmerByCode('F001');
    if (farmer1 != null) {
      await insertMilkEntry(
        MilkEntry(
          farmerId: farmer1.id!,
          farmerCode: farmer1.code,
          farmerName: farmer1.name,
          dateTime: DateTime.now(),
          shift: 'morning',
          quantity: 10.0,
          fat: 6.5,
          snf: 8.5,
          rate: 50.0,
          amount: 500.0,
          cattleType: 'buffalo',
        ),
      );
    }
  }

  Future<void> clearAllData({int? preserveUserId}) async {
    final db = await database;

    // Delete all data from all tables
    await db.delete('farmers');
    await db.delete('milk_entries');
    await db.delete('payments');
    await db.delete('rate_chart');
    await db.delete('advances');
    if (preserveUserId != null) {
      await db.delete('users', where: 'id != ?', whereArgs: [preserveUserId]);
    } else {
      await db.delete('users');
    }
  }

  /// Completely reset the database - delete and recreate
  Future<void> resetDatabase() async {

    // Close existing connection
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    _initCompleter = null;

    // Delete the database file
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'dairymaster.db');
    await deleteDatabase(path);

    // Reinitialize
    _initCompleter = Completer<Database>();
    _database = await _initDB('dairymaster.db');
    _initCompleter!.complete(_database!);
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
