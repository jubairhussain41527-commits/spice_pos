import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'bill_db.dart';

class BillHistoryScreen extends StatefulWidget {
  final bool is80mm;
  const BillHistoryScreen({super.key, required this.is80mm});

  @override
  State<BillHistoryScreen> createState() => _BillHistoryScreenState();
}

class _BillHistoryScreenState extends State<BillHistoryScreen> {
  late Future<List<SavedBill>> _billsFuture;

  @override
  void initState() {
    super.initState();
    _billsFuture = BillDatabase.instance.getAllBills();
  }

  Future<void> _reprintBill(SavedBill bill) async {
    if (!await PrintBluetoothThermal.connectionStatus) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pehle Bluetooth printer connect karein.")),
      );
      return;
    }

    final profile = await CapabilityProfile.load();
    final generator = Generator(widget.is80mm ? PaperSize.mm80 : PaperSize.mm58, profile);

    List<int> bytes = [];
    bytes += generator.reset();
    bytes += generator.text(
      "SPICE GARDEN KITCHEN",
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.text(
      "** DUPLICATE COPY **",
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.hr(ch: '=');
    bytes += generator.row([
      PosColumn(text: "Bill: #${bill.billNumber}", width: 6),
      PosColumn(text: bill.tableName, width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.hr();

    for (final item in bill.items) {
      final double lineAmt = (item['price'] as num).toDouble() * (item['qty'] as int);
      bytes += generator.row([
        PosColumn(text: item['name'] as String, width: 6),
        PosColumn(text: "${item['qty']}", width: 2, styles: const PosStyles(align: PosAlign.right)),
        PosColumn(
          text: "Rs.${lineAmt.toStringAsFixed(0)}",
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    bytes += generator.hr();
    bytes += generator.row([
      PosColumn(text: "GRAND TOTAL", width: 6, styles: const PosStyles(bold: true)),
      PosColumn(
        text: "Rs.${bill.grandTotal.toStringAsFixed(2)}",
        width: 6,
        styles: const PosStyles(bold: true, align: PosAlign.right),
      ),
    ]);
    bytes += generator.feed(2);
    bytes += generator.cut();

    final ok = await PrintBluetoothThermal.writeBytes(bytes);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? "Bill #${bill.billNumber} re-printed!" : "Re-print failed")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Saved Bills (Offline)")),
      body: FutureBuilder<List<SavedBill>>(
        future: _billsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final bills = snapshot.data ?? [];
          if (bills.isEmpty) {
            return const Center(child: Text("Abhi tak koi bill save nahi hua hai."));
          }
          return ListView.separated(
            itemCount: bills.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final b = bills[i];
              return ListTile(
                title: Text("Bill #${b.billNumber} • ${b.tableName}"),
                subtitle: Text("${b.createdAt} • ${b.items.length} items"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Rs.${b.grandTotal.toStringAsFixed(0)}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.print),
                      onPressed: () => _reprintBill(b),
                      tooltip: "Re-print Bill",
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
