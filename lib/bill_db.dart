import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class MenuItemModel {
  final String id;
  final String name;
  final String category;
  final double price;
  final bool isVeg;
  final String? imagePath;

  const MenuItemModel({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.isVeg,
    this.imagePath,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'price': price,
        'is_veg': isVeg ? 1 : 0,
        'image_path': imagePath,
      };

  factory MenuItemModel.fromMap(Map<String, dynamic> map) => MenuItemModel(
        id: map['id'] as String,
        name: map['name'] as String,
        category: map['category'] as String,
        price: (map['price'] as num).toDouble(),
        isVeg: (map['is_veg'] as int) == 1,
        imagePath: map['image_path'] as String?,
      );
}

class SavedBill {
  final int? id;
  final int billNumber;
  final String tableName;
  final double subtotal;
  final double gst;
  final double grandTotal;
  final String createdAt;
  final List<Map<String, dynamic>> items;

  SavedBill({
    this.id,
    required this.billNumber,
    required this.tableName,
    required this.subtotal,
    required this.gst,
    required this.grandTotal,
    required this.createdAt,
    required this.items,
  });

  Map<String, dynamic> toMap() => {
        'bill_number': billNumber,
        'table_name': tableName,
        'subtotal': subtotal,
        'gst': gst,
        'grand_total': grandTotal,
        'created_at': createdAt,
        'items_json': jsonEncode(items),
      };

  factory SavedBill.fromMap(Map<String, dynamic> map) => SavedBill(
        id: map['id'] as int?,
        billNumber: map['bill_number'] as int,
        tableName: map['table_name'] as String,
        subtotal: (map['subtotal'] as num).toDouble(),
        gst: (map['gst'] as num).toDouble(),
        grandTotal: (map['grand_total'] as num).toDouble(),
        createdAt: map['created_at'] as String,
        items: List<Map<String, dynamic>>.from(jsonDecode(map['items_json'] as String)),
      );
}

class BillDatabase {
  static final BillDatabase instance = BillDatabase._init();
  static Database? _database;

  BillDatabase._init();

  static const List<MenuItemModel> _defaultMenu = [
    MenuItemModel(id: "1", name: "Paneer Tikka", category: "Starters", price: 240, isVeg: true),
    MenuItemModel(id: "2", name: "Veg Manchurian", category: "Starters", price: 180, isVeg: true),
    MenuItemModel(id: "3", name: "Chicken 65", category: "Starters", price: 260, isVeg: false),
    MenuItemModel(id: "4", name: "Paneer Butter Masala", category: "Main Course", price: 280, isVeg: true),
    MenuItemModel(id: "5", name: "Dal Makhani", category: "Main Course", price: 220, isVeg: true),
    MenuItemModel(id: "6", name: "Butter Chicken", category: "Main Course", price: 320, isVeg: false),
    MenuItemModel(id: "7", name: "Butter Naan", category: "Breads", price: 55, isVeg: true),
    MenuItemModel(id: "8", name: "Tandoori Roti", category: "Breads", price: 30, isVeg: true),
    MenuItemModel(id: "9", name: "Masala Chai", category: "Beverages", price: 40, isVeg: true),
    MenuItemModel(id: "10", name: "Mango Lassi", category: "Beverages", price: 90, isVeg: true),
  ];

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'spicepos_bills.db');
    _database = await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE bills (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bill_number INTEGER NOT NULL,
            table_name TEXT NOT NULL,
            subtotal REAL NOT NULL,
            gst REAL NOT NULL,
            grand_total REAL NOT NULL,
            created_at TEXT NOT NULL,
            items_json TEXT NOT NULL
          )
        ''');
        await _createMenuTable(db);
        await _createPrinterPrefsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createMenuTable(db);
        }
        if (oldVersion < 3) {
          await _createPrinterPrefsTable(db);
        }
      },
    );
    return _database!;
  }

  Future<void> _createMenuTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS menu_items (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        price REAL NOT NULL,
        is_veg INTEGER NOT NULL,
        image_path TEXT
      )
    ''');
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM menu_items'),
    );
    if (count == 0) {
      for (final item in _defaultMenu) {
        await db.insert('menu_items', item.toMap());
      }
    }
  }

  Future<void> _createPrinterPrefsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS printer_prefs (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> savePrinterPref(String mac, String name, bool is80mm) async {
    final db = await database;
    await db.insert('printer_prefs', {'key': 'mac', 'value': mac}, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('printer_prefs', {'key': 'name', 'value': name}, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('printer_prefs', {'key': 'is80mm', 'value': is80mm ? '1' : '0'}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String>> getPrinterPref() async {
    final db = await database;
    final rows = await db.query('printer_prefs');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  Future<List<MenuItemModel>> getMenuItems() async {
    final db = await database;
    final rows = await db.query('menu_items');
    return rows.map((r) => MenuItemModel.fromMap(r)).toList();
  }

  Future<void> insertMenuItem(MenuItemModel item) async {
    final db = await database;
    await db.insert(
      'menu_items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteMenuItem(String id) async {
    final db = await database;
    await db.delete('menu_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveBill(SavedBill bill) async {
    final db = await database;
    await db.insert('bills', bill.toMap());
  }

  Future<List<SavedBill>> getAllBills() async {
    final db = await database;
    final rows = await db.query('bills', orderBy: 'id DESC');
    return rows.map((r) => SavedBill.fromMap(r)).toList();
  }

  Future<List<SavedBill>> getTodaysBills() async {
    final db = await database;
    final now = DateTime.now();
    final todayPrefix =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final rows = await db.query(
      'bills',
      where: 'created_at LIKE ?',
      whereArgs: ['$todayPrefix%'],
      orderBy: 'id DESC',
    );
    return rows.map((r) => SavedBill.fromMap(r)).toList();
  }
}
