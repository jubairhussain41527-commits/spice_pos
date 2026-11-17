import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'bill_db.dart';

class SalesSummaryScreen extends StatefulWidget {
  const SalesSummaryScreen({super.key});

  @override
  State<SalesSummaryScreen> createState() => _SalesSummaryScreenState();
}

class _SalesSummaryScreenState extends State<SalesSummaryScreen> {
  List<SavedBill> _todayBills = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    final bills = await BillDatabase.instance.getTodaysBills();
    if (!mounted) return;
    setState(() {
      _todayBills = bills;
      _loading = false;
    });
  }

  double get _totalSales => _todayBills.fold(0, (s, b) => s + b.grandTotal);
  double get _totalGst => _todayBills.fold(0, (s, b) => s + b.gst);
  double get _totalSubtotal => _todayBills.fold(0, (s, b) => s + b.subtotal);

  String _escapeCsv(String value) {
    final clean = value.replaceAll('"', '""');
    return '"$clean"';
  }

  Future<void> _exportCsv() async {
    if (_todayBills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Aaj koi bill save nahi hua hai.")),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln("Bill No,Table,Date Time,Subtotal,GST,Grand Total,Items");

    for (final b in _todayBills) {
      final itemsSummary = b.items
          .map((i) => "${i['qty']}x ${i['name']}")
          .join(" | ");
      buffer.writeln([
        "#${b.billNumber}",
        _escapeCsv(b.tableName),
        _escapeCsv(b.createdAt),
        b.subtotal.toStringAsFixed(2),
        b.gst.toStringAsFixed(2),
        b.grandTotal.toStringAsFixed(2),
        _escapeCsv(itemsSummary),
      ].join(","));
    }

    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final fileName =
        "sales_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.csv";
    final file = File("${dir.path}/$fileName");
    await file.writeAsString(buffer.toString());

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: "Today's Restaurant Sales Report ($fileName)",
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Sales Summary"),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportCsv,
            tooltip: "Export CSV",
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _statCard("Total Sales", "Rs.${_totalSales.toStringAsFixed(0)}", Colors.green.shade700),
                      const SizedBox(width: 10),
                      _statCard("Total Bills", "${_todayBills.length}", Colors.blue.shade700),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _statCard("Net (Excl. GST)", "Rs.${_totalSubtotal.toStringAsFixed(0)}", Colors.orange.shade800),
                      const SizedBox(width: 10),
                      _statCard("GST Collected", "Rs.${_totalGst.toStringAsFixed(0)}", Colors.purple.shade700),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _exportCsv,
                    icon: const Icon(Icons.share),
                    label: const Text("Export & Share Today's CSV"),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                  const SizedBox(height: 16),
                  const Text("Today's Bills", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const Divider(),
                  Expanded(
                    child: _todayBills.isEmpty
                        ? const Center(child: Text("Aaj abhi tak koi bill print nahi hua hai."))
                        : ListView.separated(
                            itemCount: _todayBills.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final b = _todayBills[i];
                              return ListTile(
                                dense: true,
                                title: Text("Bill #${b.billNumber} (${b.tableName})"),
                                subtitle: Text(b.createdAt),
                                trailing: Text(
                                  "Rs.${b.grandTotal.toStringAsFixed(0)}",
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
