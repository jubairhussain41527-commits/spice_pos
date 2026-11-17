import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'bill_db.dart';
import 'history_screen.dart';
import 'sales_summary_screen.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PosOrderScreen(),
  ));
}

class CartItem {
  final MenuItemModel item;
  int qty;
  CartItem({required this.item, this.qty = 1});
}

class PosOrderScreen extends StatefulWidget {
  const PosOrderScreen({super.key});

  @override
  State<PosOrderScreen> createState() => _PosOrderScreenState();
}

class _PosOrderScreenState extends State<PosOrderScreen> {
  final List<String> _categories = ["All", "Starters", "Main Course", "Breads", "Beverages"];
  final List<String> _tables = ["Table 1", "Table 2", "Table 3", "Table 4", "Takeaway"];

  List<MenuItemModel> _menu = [];
  String _selectedCategory = "All";
  String _selectedTable = "Table 2";
  int _orderNumber = 1042;
  bool _is80mm = false;
  bool _connected = false;
  bool _connecting = false;
  String? _connectedMac;
  String? _connectedName;

  final List<CartItem> _cart = [];
  final TextEditingController _kotNoteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMenu();
    _autoConnectSavedPrinter();
  }

  @override
  void dispose() {
    _kotNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMenu() async {
    final items = await BillDatabase.instance.getMenuItems();
    if (!mounted) return;
    setState(() => _menu = items);
  }

  Future<void> _autoConnectSavedPrinter() async {
    final prefs = await BillDatabase.instance.getPrinterPref();
    final savedMac = prefs['mac'];
    final savedName = prefs['name'];
    final saved80 = prefs['is80mm'] == '1';
    if (mounted) {
      setState(() => _is80mm = saved80);
    }
    if (savedMac == null || savedMac.isEmpty) return;

    final btOn = await PrintBluetoothThermal.bluetoothEnabled;
    final permOk = await PrintBluetoothThermal.isPermissionBluetoothGranted;
    if (!btOn || !permOk) return;

    if (mounted) setState(() => _connecting = true);
    final ok = await PrintBluetoothThermal.connect(macPrinterAddress: savedMac);
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _connected = ok;
      _connectedMac = ok ? savedMac : null;
      _connectedName = ok ? (savedName ?? savedMac) : null;
    });
  }

  double get _subtotal => _cart.fold(0, (sum, c) => sum + (c.item.price * c.qty));
  double get _gst => _subtotal * 0.05;
  double get _grandTotal => (_subtotal + _gst).roundToDouble();

  void _addToCart(MenuItemModel item) {
    setState(() {
      final idx = _cart.indexWhere((c) => c.item.id == item.id);
      if (idx >= 0) {
        _cart[idx].qty += 1;
      } else {
        _cart.add(CartItem(item: item));
      }
    });
  }

  void _updateQty(String id, int delta) {
    setState(() {
      final idx = _cart.indexWhere((c) => c.item.id == id);
      if (idx < 0) return;
      _cart[idx].qty += delta;
      if (_cart[idx].qty <= 0) {
        _cart.removeAt(idx);
      }
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openAddItemDialog() async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    String category = "Starters";
    bool isVeg = true;
    String? pickedImagePath;
    final picker = ImagePicker();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text("Add Menu Item", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () async {
                    final XFile? file = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 600,
                      imageQuality: 80,
                    );
                    if (file == null) return;
                    final appDir = await getApplicationDocumentsDirectory();
                    final fileName = "item_${DateTime.now().millisecondsSinceEpoch}${p.extension(file.path)}";
                    final saved = await File(file.path).copy(p.join(appDir.path, fileName));
                    setSheetState(() => pickedImagePath = saved.path);
                  },
                  child: Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: pickedImagePath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(File(pickedImagePath!), fit: BoxFit.cover, width: double.infinity),
                          )
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo, size: 32, color: Colors.grey),
                              SizedBox(height: 6),
                              Text("Tap to upload item image", style: TextStyle(color: Colors.grey, fontSize: 13)),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: "Item Name", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "Price (Rs.)", border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: const InputDecoration(labelText: "Category", border: OutlineInputBorder()),
                        items: _categories
                            .where((c) => c != "All")
                            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setSheetState(() => category = v);
                        },
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Veg Item"),
                  value: isVeg,
                  onChanged: (v) => setSheetState(() => isVeg = v),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
                    if (name.isEmpty || price <= 0) {
                      _showSnack("Valid item name aur price dalein.");
                      return;
                    }
                    final newItem = MenuItemModel(
                      id: "item_${DateTime.now().millisecondsSinceEpoch}",
                      name: name,
                      category: category,
                      price: price,
                      isVeg: isVeg,
                      imagePath: pickedImagePath,
                    );
                    await BillDatabase.instance.insertMenuItem(newItem);
                    await _loadMenu();
                    if (ctx.mounted) Navigator.pop(ctx);
                    _showSnack("$name menu mein add ho gaya!");
                  },
                  child: const Text("Save Item"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteItem(MenuItemModel item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Item?"),
        content: Text("Kya aap '${item.name}' ko menu se hatana chahte hain?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await BillDatabase.instance.deleteMenuItem(item.id);
      await _loadMenu();
      _showSnack("${item.name} deleted");
    }
  }

  Future<void> _testPrint() async {
    if (!await PrintBluetoothThermal.connectionStatus) {
      _showSnack("Pehle Bluetooth printer connect karein.");
      return;
    }
    final profile = await CapabilityProfile.load();
    final generator = Generator(_is80mm ? PaperSize.mm80 : PaperSize.mm58, profile);
    List<int> bytes = [];
    bytes += generator.reset();
    bytes += generator.text(
      "SPICEPOS TEST PRINT",
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.text(
      "Paper: ${_is80mm ? '80mm' : '58mm'} | Status: OK",
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.feed(2);
    bytes += generator.cut();
    final ok = await PrintBluetoothThermal.writeBytes(bytes);
    _showSnack(ok ? "Test print successful!" : "Test print failed");
  }

  Future<void> _printKot() async {
    if (_cart.isEmpty) {
      _showSnack("Cart khaali hai! Pehle items add karein.");
      return;
    }
    if (!await PrintBluetoothThermal.connectionStatus) {
      _showSnack("Pehle Bluetooth printer connect karein.");
      _openPrinterSheet();
      return;
    }

    final profile = await CapabilityProfile.load();
    final generator = Generator(_is80mm ? PaperSize.mm80 : PaperSize.mm58, profile);
    final now = DateTime.now();
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    List<int> bytes = [];
    bytes += generator.reset();
    bytes += generator.text(
      "** KITCHEN ORDER (KOT) **",
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.hr(ch: '=');
    bytes += generator.row([
      PosColumn(text: "KOT #$_orderNumber", width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text: "Time: $timeStr", width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.text(
      "Location: $_selectedTable",
      styles: const PosStyles(
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size1,
      ),
    );
    bytes += generator.hr(ch: '=');
    bytes += generator.row([
      PosColumn(text: "ITEM", width: 9, styles: const PosStyles(bold: true)),
      PosColumn(text: "QTY", width: 3, styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]);
    bytes += generator.hr();

    for (final c in _cart) {
      bytes += generator.row([
        PosColumn(text: c.item.name, width: 9),
        PosColumn(
          text: "${c.qty}x",
          width: 3,
          styles: const PosStyles(bold: true, align: PosAlign.right),
        ),
      ]);
    }

    if (_kotNoteCtrl.text.trim().isNotEmpty) {
      bytes += generator.hr();
      bytes += generator.text("NOTE:", styles: const PosStyles(bold: true));
      bytes += generator.text(_kotNoteCtrl.text.trim());
    }

    bytes += generator.hr(ch: '=');
    bytes += generator.text("--- END OF KOT ---", styles: const PosStyles(align: PosAlign.center));
    bytes += generator.feed(2);
    bytes += generator.cut();

    final bool ok = await PrintBluetoothThermal.writeBytes(bytes);
    _showSnack(ok ? "KOT #$_orderNumber printed!" : "KOT print failed");
  }

  Future<void> _printCustomerBill() async {
    if (_cart.isEmpty) {
      _showSnack("Cart khaali hai! Pehle items add karein.");
      return;
    }
    if (!await PrintBluetoothThermal.connectionStatus) {
      _showSnack("Pehle Bluetooth printer connect karein.");
      _openPrinterSheet();
      return;
    }

    final profile = await CapabilityProfile.load();
    final generator = Generator(_is80mm ? PaperSize.mm80 : PaperSize.mm58, profile);

    List<int> bytes = [];
    bytes += generator.reset();
    bytes += generator.text(
      "SPICE GARDEN KITCHEN",
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size1,
      ),
    );
    bytes += generator.text("GS Road, Guwahati, Assam", styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text("GSTIN: 18AABCU9603R1ZM", styles: const PosStyles(align: PosAlign.center));
    bytes += generator.hr(ch: '=');

    bytes += generator.row([
      PosColumn(text: "Bill: #$_orderNumber", width: 6),
      PosColumn(text: _selectedTable, width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.hr();

    bytes += generator.row([
      PosColumn(text: "Item", width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text: "Qty", width: 2, styles: const PosStyles(bold: true, align: PosAlign.right)),
      PosColumn(text: "Amt", width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]);
    bytes += generator.hr();

    for (final c in _cart) {
      final lineTotal = c.item.price * c.qty;
      bytes += generator.row([
        PosColumn(text: c.item.name, width: 6),
        PosColumn(text: "${c.qty}", width: 2, styles: const PosStyles(align: PosAlign.right)),
        PosColumn(
          text: "Rs.${lineTotal.toStringAsFixed(0)}",
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    final halfGst = _gst / 2;
    bytes += generator.hr();
    bytes += generator.row([
      PosColumn(text: "Subtotal", width: 7),
      PosColumn(text: "Rs.${_subtotal.toStringAsFixed(2)}", width: 5, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.row([
      PosColumn(text: "CGST (2.5%)", width: 7),
      PosColumn(text: "Rs.${halfGst.toStringAsFixed(2)}", width: 5, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.row([
      PosColumn(text: "SGST (2.5%)", width: 7),
      PosColumn(text: "Rs.${halfGst.toStringAsFixed(2)}", width: 5, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.hr(ch: '=');
    bytes += generator.row([
      PosColumn(text: "GRAND TOTAL", width: 6, styles: const PosStyles(bold: true)),
      PosColumn(
        text: "Rs.${_grandTotal.toStringAsFixed(2)}",
        width: 6,
        styles: const PosStyles(bold: true, align: PosAlign.right),
      ),
    ]);
    bytes += generator.hr(ch: '=');

    final upiUri = "upi://pay?pa=spicegarden@upi&pn=Spice%20Garden&am=${_grandTotal.toStringAsFixed(2)}&cu=INR";
    bytes += generator.text("Scan & Pay via UPI", styles: const PosStyles(align: PosAlign.center), linesAfter: 1);
    bytes += generator.qrcode(upiUri, size: QRSize.size5);
    bytes += generator.text("Thank You! Visit Again", styles: const PosStyles(align: PosAlign.center));
    bytes += generator.feed(2);
    bytes += generator.cut();

    final bool ok = await PrintBluetoothThermal.writeBytes(bytes);
    if (ok) {
      await BillDatabase.instance.saveBill(
        SavedBill(
          billNumber: _orderNumber,
          tableName: _selectedTable,
          subtotal: _subtotal,
          gst: _gst,
          grandTotal: _grandTotal,
          createdAt: DateTime.now().toString().substring(0, 16),
          items: _cart.map((c) => {'name': c.item.name, 'qty': c.qty, 'price': c.item.price}).toList(),
        ),
      );
      setState(() {
        _orderNumber += 1;
        _cart.clear();
        _kotNoteCtrl.clear();
      });
      _showSnack("Bill printed & saved offline!");
    } else {
      _showSnack("Bill print failed");
    }
  }

  Future<void> _openPrinterSheet() async {
    final bool btEnabled = await PrintBluetoothThermal.bluetoothEnabled;
    final bool permOk = await PrintBluetoothThermal.isPermissionBluetoothGranted;
    if (!btEnabled) {
      _showSnack("Phone ka Bluetooth ON karein.");
      return;
    }
    if (!permOk) {
      _showSnack("App Settings se Nearby Devices / Bluetooth permission allow karein.");
      return;
    }
    List<BluetoothInfo> devices = await PrintBluetoothThermal.pairedBluetooths;
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Bluetooth Thermal Printer", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      const Text("80mm"),
                      Switch(
                        value: _is80mm,
                        onChanged: (v) async {
                          setState(() => _is80mm = v);
                          setSheetState(() {});
                          if (_connectedMac != null) {
                            await BillDatabase.instance.savePrinterPref(_connectedMac!, _connectedName ?? _connectedMac!, v);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Pehle phone Bluetooth settings mein printer pair karein.", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  TextButton.icon(
                    onPressed: () async {
                      final refreshed = await PrintBluetoothThermal.pairedBluetooths;
                      setSheetState(() => devices = refreshed);
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text("Refresh"),
                  ),
                ],
              ),
              const Divider(),
              if (devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text("Koi paired printer nahi mila. Phone settings mein pair karein.")),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    itemBuilder: (_, i) {
                      final d = devices[i];
                      final isThis = _connected && _connectedMac == d.macAdress;
                      return ListTile(
                        leading: Icon(Icons.print, color: isThis ? Colors.green : Colors.grey),
                        title: Text(d.name),
                        subtitle: Text(d.macAdress),
                        trailing: ElevatedButton(
                          onPressed: () async {
                            if (isThis) {
                              await PrintBluetoothThermal.disconnect;
                              setState(() {
                                _connected = false;
                                _connectedMac = null;
                                _connectedName = null;
                              });
                              setSheetState(() {});
                            } else {
                              setState(() => _connecting = true);
                              final ok = await PrintBluetoothThermal.connect(macPrinterAddress: d.macAdress);
                              if (ok) {
                                await BillDatabase.instance.savePrinterPref(d.macAdress, d.name, _is80mm);
                              }
                              setState(() {
                                _connecting = false;
                                _connected = ok;
                                _connectedMac = ok ? d.macAdress : null;
                                _connectedName = ok ? d.name : null;
                              });
                              setSheetState(() {});
                              _showSnack(ok ? "Connected to ${d.name}" : "Connect nahi ho paya");
                            }
                          },
                          child: Text(isThis ? "Disconnect" : "Connect"),
                        ),
                      );
                    },
                  ),
                ),
              if (_connected) ...[
                const Divider(),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _testPrint,
                    icon: const Icon(Icons.receipt_long),
                    label: const Text("Test Print"),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredMenu = _selectedCategory == "All"
        ? _menu
        : _menu.where((m) => m.category == _selectedCategory).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("SpicePOS Billing"),
        actions: [
          DropdownButton<String>(
            value: _selectedTable,
            underline: const SizedBox(),
            items: _tables.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) {
              if (v != null) setState(() => _selectedTable = v);
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: "Add Menu Item",
            onPressed: _openAddItemDialog,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: "Today's Sales",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SalesSummaryScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: "Bill History",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => BillHistoryScreen(is80mm: _is80mm)),
            ),
          ),
          IconButton(
            icon: Icon(Icons.bluetooth, color: _connected ? Colors.green : Colors.red),
            onPressed: _openPrinterSheet,
            tooltip: "Connect Printer",
          ),
        ],
      ),
      body: Column(
        children: [
          // Prominent Bluetooth Printer Status Bar
          InkWell(
            onTap: _openPrinterSheet,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: _connected ? Colors.green.shade50 : Colors.amber.shade50,
              child: Row(
                children: [
                  Icon(
                    _connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    size: 18,
                    color: _connected ? Colors.green.shade700 : Colors.amber.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _connecting
                          ? "Thermal printer se connect ho raha hai..."
                          : _connected
                              ? "Printer Connected: ${_connectedName ?? _connectedMac} (${_is80mm ? '80mm' : '58mm'})"
                              : "Thermal Printer Disconnected — Connect karne ke liye tap karein",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _connected ? Colors.green.shade800 : Colors.amber.shade900,
                      ),
                    ),
                  ),
                  Text(
                    _connected ? "Manage" : "Connect",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _connected ? Colors.green.shade700 : Colors.amber.shade900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat = _categories[i];
                final active = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat),
                  selected: active,
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                );
              },
            ),
          ),
          Expanded(
            flex: 5,
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.25,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: filteredMenu.length,
              itemBuilder: (_, i) {
                final item = filteredMenu[i];
                final hasImg = item.imagePath != null && File(item.imagePath!).existsSync();
                return InkWell(
                  onTap: () => _addToCart(item),
                  onLongPress: () => _confirmDeleteItem(item),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (hasImg)
                          Expanded(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                              child: Image.file(File(item.imagePath!), fit: BoxFit.cover),
                            ),
                          )
                        else
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                              ),
                              child: Icon(Icons.fastfood, color: Colors.amber.shade700, size: 28),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                  ),
                                  Icon(
                                    Icons.circle,
                                    size: 10,
                                    color: item.isVeg ? Colors.green : Colors.red,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Rs.${item.price.toStringAsFixed(0)}",
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade800),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_cart.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text("Cart khaali hai — upar se items tap karein", style: TextStyle(color: Colors.grey)),
                  )
                else
                  SizedBox(
                    height: 110,
                    child: ListView.builder(
                      itemCount: _cart.length,
                      itemBuilder: (_, i) {
                        final c = _cart[i];
                        return Row(
                          children: [
                            Expanded(child: Text(c.item.name, style: const TextStyle(fontWeight: FontWeight.w500))),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, size: 20),
                              onPressed: () => _updateQty(c.item.id, -1),
                            ),
                            Text("${c.qty}", style: const TextStyle(fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, size: 20),
                              onPressed: () => _updateQty(c.item.id, 1),
                            ),
                            SizedBox(
                              width: 60,
                              child: Text(
                                "Rs.${(c.item.price * c.qty).toStringAsFixed(0)}",
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                TextField(
                  controller: _kotNoteCtrl,
                  decoration: const InputDecoration(
                    hintText: "KOT Note (e.g. Less spicy, extra butter)",
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Total (incl. 5% GST): Rs.${_grandTotal.toStringAsFixed(0)}",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _cart.clear()),
                      child: const Text("Clear", style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _printKot,
                        icon: const Icon(Icons.restaurant_menu),
                        label: const Text("Print KOT"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _printCustomerBill,
                        icon: const Icon(Icons.print),
                        label: const Text("Print Bill"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
