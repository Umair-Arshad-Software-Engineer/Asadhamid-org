import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../Provider/lanprovider.dart';

class ProfitLossPage extends StatefulWidget {
  const ProfitLossPage({Key? key}) : super(key: key);

  @override
  State<ProfitLossPage> createState() => _ProfitLossPageState();
}

class _ProfitLossPageState extends State<ProfitLossPage> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  bool _isLoading = false;

  // Full dataset
  List<Map<String, dynamic>> _purchaseRows = [];
  List<Map<String, dynamic>> _saleRows = [];

  // Per-item aggregated result
  List<Map<String, dynamic>> _itemStats = [];

  // Active filter (applied after Generate)
  DateTime? _fromDate;
  DateTime? _toDate;

  // Pending filter (what the user has picked but not yet applied)
  DateTime? _pendingFromDate;
  DateTime? _pendingToDate;

  bool _reportGenerated = false;

  // ── Totals ────────────────────────────────────────────────────────────────
  double _totalPurchaseCost = 0;
  double _totalSaleRevenue = 0;
  double _totalProfit = 0;
  double _totalProfitPct = 0;
  double _totalPurchaseWeight = 0;
  double _totalSoldWeight = 0;

  @override
  void initState() {
    super.initState();
    // No auto-load. The user must pick dates and tap "Generate Report".
  }

  // ═════════════════════════════════════════════════════════════════════════
  // DATA LOADING
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _generateReport() async {
    if (mounted) setState(() => _isLoading = true);

    // Apply pending filter to active filter
    _fromDate = _pendingFromDate;
    _toDate = _pendingToDate;

    try {
      await Future.wait([
        _loadPurchases(),
        _loadSales(),
      ]);
      _computeStats();
      _reportGenerated = true;
    } catch (e) {
      debugPrint('ProfitLoss generate error: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // ── Purchases: each item line = a real cost entry ─────────────────────────
  Future<void> _loadPurchases() async {
    _purchaseRows.clear();

    final snap = await _db.child('purchases').get();
    if (!snap.exists) return;

    final rawData = snap.value;

    // Normalise to a Map regardless of storage form
    Map<dynamic, dynamic> data;
    if (rawData is Map) {
      data = rawData;
    } else if (rawData is List) {
      final Map<dynamic, dynamic> converted = {};
      for (int i = 0; i < rawData.length; i++) {
        if (rawData[i] != null) converted[i.toString()] = rawData[i];
      }
      data = converted;
    } else {
      return;
    }

    data.forEach((purchaseKey, purchaseValue) {
      if (purchaseValue is! Map) return;

      final purchase = Map<String, dynamic>.from(purchaseValue);

      // ── Purchase date ──────────────────────────────────────────────────
      DateTime? purchaseDate;
      final ts = purchase['timestamp'];
      if (ts is String) {
        purchaseDate = DateTime.tryParse(ts);
      } else if (ts is int) {
        purchaseDate = DateTime.fromMillisecondsSinceEpoch(ts);
      }

      final vendorName = purchase['vendorName']?.toString() ?? 'N/A';

      // ── Items (List or Map) ────────────────────────────────────────────
      final rawItems = purchase['items'];
      final List<dynamic> itemsList = [];

      if (rawItems is List) {
        itemsList.addAll(rawItems);
      } else if (rawItems is Map) {
        rawItems.forEach((_, v) => itemsList.add(v));
      }

      for (final rawItem in itemsList) {
        if (rawItem is! Map) continue;
        final item = Map<String, dynamic>.from(rawItem);

        final itemName = item['itemName']?.toString() ?? '';
        if (itemName.isEmpty) continue;

        final length = item['length']?.toString() ?? '';
        final bodyType = item['bodyType']?.toString() ?? '';

        final qty = _toDouble(item['quantity']);
        final wtPerUnit = _toDouble(item['weightPerUnit']);
        final pricePerKg = _toDouble(item['purchasePrice']);

        // total weight in kg = qty × weight-per-unit
        final totalWeight = qty * wtPerUnit;

        // true acquisition cost = weight × price/kg (fallback to stored total)
        double cost = totalWeight * pricePerKg;
        if (cost == 0) cost = _toDouble(item['total']);

        _purchaseRows.add({
          'purchaseKey': purchaseKey,
          'date': purchaseDate,
          'vendor': vendorName,
          'itemName': itemName,
          'length': length,
          'bodyType': bodyType,
          'qty': qty,
          'weight': totalWeight,
          'pricePerKg': pricePerKg,
          'cost': cost,
          'key': _itemKey(itemName, length, bodyType),
        });
      }
    });
  }

  // ── Sales: each item line = real revenue entry ───────────────────────────
  Future<void> _loadSales() async {
    _saleRows.clear();

    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🔵 _loadSales() STARTED');

    final snap = await _db.child('filled').get();

    debugPrint('🔵 snapshot.exists = ${snap.exists}');

    if (!snap.exists) {
      debugPrint('🔴 EXIT: filled node does not exist');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return;
    }

    final rawData = snap.value;
    debugPrint('🔵 snap.value runtimeType = ${rawData.runtimeType}');

    // ── Normalise to a Map regardless of storage form ─────────────────────
    Map<dynamic, dynamic> data;

    if (rawData is Map) {
      data = rawData;
      debugPrint('🔵 Top-level filled keys count = ${data.length}');
      debugPrint('🔵 Top-level filled keys = ${data.keys.toList()}');
    } else if (rawData is List) {
      final Map<dynamic, dynamic> converted = {};
      for (int i = 0; i < rawData.length; i++) {
        if (rawData[i] != null) converted[i.toString()] = rawData[i];
      }
      data = converted;
      debugPrint('🔵 snap.value is a List — converted to Map '
          '(skipped nulls). Entries = ${data.length}');
      debugPrint('🔵 Converted keys = ${data.keys.toList()}');
    } else {
      debugPrint('🔴 EXIT: filled value is neither Map nor List '
          '(it is ${rawData.runtimeType})');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return;
    }

    int filledProcessed = 0;
    int filledSkippedQuotation = 0;
    int filledSkippedNotMap = 0;
    int totalItemLines = 0;
    int itemsAddedToRows = 0;
    int itemsSkippedEmptyName = 0;
    int itemsSkippedNonMap = 0;
    int itemsSkippedZeroRevenueAndWeight = 0;

    data.forEach((filledKey, filledValue) {
      // ── Guard: value must be a Map ──────────────────────────────────────
      if (filledValue is! Map) {
        filledSkippedNotMap++;
        debugPrint('   ⚠️ [$filledKey] value is not a Map '
            '(type=${filledValue.runtimeType}) — skipping');
        return;
      }

      final filled = Map<String, dynamic>.from(filledValue);

      debugPrint('');
      debugPrint('   📄 Processing filledKey="$filledKey"');
      debugPrint('      └─ Available keys: ${filled.keys.toList()}');

      // ── Skip quotation-origin entries ───────────────────────────────────
      final isFromQuotation = filled['isFromQuotation'];
      final filledNumber = filled['filledNumber'];

      debugPrint('      ├─ isFromQuotation = $isFromQuotation '
          '(${isFromQuotation.runtimeType})');
      debugPrint('      ├─ filledNumber     = $filledNumber '
          '(${filledNumber.runtimeType})');

      if (isFromQuotation == true && filledNumber == null) {
        filledSkippedQuotation++;
        debugPrint('      ⏭️  SKIPPED: quotation-only entry');
        return;
      }

      filledProcessed++;

      // ── Sale date ───────────────────────────────────────────────────────
      DateTime? saleDate;
      final ts = filled['createdAt'];
      debugPrint('      ├─ createdAt = $ts (${ts.runtimeType})');

      if (ts is String) {
        saleDate = DateTime.tryParse(ts);
        debugPrint('      │   └─ parsed as String → $saleDate');
      } else if (ts is int) {
        saleDate = DateTime.fromMillisecondsSinceEpoch(ts);
        debugPrint('      │   └─ parsed as int (ms) → $saleDate');
      } else {
        debugPrint('      │   └─ ⚠️ unknown type, saleDate stays null');
      }

      final customerName = filled['customerName']?.toString() ?? 'N/A';
      final invoiceNo = filled['filledNumber']?.toString() ?? filledKey;

      debugPrint('      ├─ customerName = "$customerName"');
      debugPrint('      ├─ invoiceNo    = "$invoiceNo"');

      // ── Items (List or Map) ─────────────────────────────────────────────
      final rawItems = filled['items'];
      debugPrint('      ├─ items runtimeType = ${rawItems.runtimeType}');

      final List<dynamic> itemsList = [];

      if (rawItems is List) {
        itemsList.addAll(rawItems);
        debugPrint('      │   └─ items is List, length = ${rawItems.length}');
      } else if (rawItems is Map) {
        rawItems.forEach((_, v) => itemsList.add(v));
        debugPrint('      │   └─ items is Map, converted to list, '
            'length = ${itemsList.length}');
      } else {
        debugPrint('      │   └─ 🔴 items is neither List nor Map — '
            'SKIPPING invoice');
        return;
      }

      debugPrint('      └─ processing ${itemsList.length} item line(s)');

      for (int i = 0; i < itemsList.length; i++) {
        final rawItem = itemsList[i];

        if (rawItem is! Map) {
          itemsSkippedNonMap++;
          debugPrint('         [$i] ⚠️ item is not a Map — skipping');
          continue;
        }

        totalItemLines++;

        final item = Map<String, dynamic>.from(rawItem);

        debugPrint('         [$i] item keys: ${item.keys.toList()}');

        final itemName = item['itemName']?.toString() ?? '';
        debugPrint('         [$i] itemName = "$itemName"');

        if (itemName.isEmpty) {
          itemsSkippedEmptyName++;
          debugPrint('         [$i] ⏭️  SKIPPED: empty itemName');
          continue;
        }

        final length = item['length']?.toString() ?? '';
        final bodyType = item['bodyType']?.toString() ?? '';

        debugPrint('         [$i] length="$length"  bodyType="$bodyType"');

        // ── Qty ─────────────────────────────────────────────────────────
        final qtyRaw = item['qty'];
        final quantityRaw = item['quantity'];

        final qty = _toDouble(qtyRaw) != 0
            ? _toDouble(qtyRaw)
            : _toDouble(quantityRaw);

        debugPrint('         [$i] qty(raw)=$qtyRaw  quantity(raw)=$quantityRaw '
            '→ using $qty');

        // ── Rate ────────────────────────────────────────────────────────
        final rate = _toDouble(item['rate']);
        debugPrint('         [$i] rate = $rate');

        // ── Calculation type ────────────────────────────────────────────
        final calcType =
            item['calculationType']?.toString() ?? 'quantity';
        debugPrint('         [$i] calculationType = "$calcType"');

        // ── Total weight ────────────────────────────────────────────────
        final totalWeight = _toDouble(item['totalWeight']);
        debugPrint('         [$i] totalWeight = $totalWeight');

        // ── Revenue ─────────────────────────────────────────────────────
        double revenue = _toDouble(item['total']);
        debugPrint('         [$i] revenue(raw total) = $revenue');

        if (revenue == 0) {
          if (calcType == 'weight' && totalWeight > 0) {
            revenue = totalWeight * rate;
            debugPrint('         [$i] recomputed revenue = '
                '$totalWeight × $rate = $revenue');
          } else {
            revenue = qty * rate;
            debugPrint('         [$i] recomputed revenue = '
                '$qty × $rate = $revenue');
          }
        }

        // ── Weight sold ─────────────────────────────────────────────────
        final wtSold = totalWeight > 0 ? totalWeight : qty;
        debugPrint('         [$i] wtSold = $wtSold');

        if (revenue <= 0 && wtSold <= 0) {
          itemsSkippedZeroRevenueAndWeight++;
          debugPrint('         [$i] ⏭️  SKIPPED: revenue=$revenue '
              'and weight=$wtSold (both ≤ 0)');
          continue;
        }

        _saleRows.add({
          'filledKey': filledKey,
          'invoice': invoiceNo,
          'date': saleDate,
          'customer': customerName,
          'itemName': itemName,
          'length': length,
          'bodyType': bodyType,
          'qty': qty,
          'weight': wtSold,
          'rate': rate,
          'revenue': revenue,
          'key': _itemKey(itemName, length, bodyType),
        });

        itemsAddedToRows++;
        debugPrint('         [$i] ✅ ADDED to _saleRows '
            '(total now: ${_saleRows.length})');
      }
    });

    debugPrint('');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('📊 _loadSales() SUMMARY');
    debugPrint('   Total top-level entries        : ${data.length}');
    debugPrint('   Skipped (not a Map)            : $filledSkippedNotMap');
    debugPrint('   Skipped (quotation-only)       : $filledSkippedQuotation');
    debugPrint('   Invoices processed             : $filledProcessed');
    debugPrint('   Total item lines seen          : $totalItemLines');
    debugPrint('   Skipped (non-Map item)         : $itemsSkippedNonMap');
    debugPrint('   Skipped (empty itemName)       : $itemsSkippedEmptyName');
    debugPrint('   Skipped (0 revenue & 0 weight) : $itemsSkippedZeroRevenueAndWeight');
    debugPrint('   ✅ Item lines added            : $itemsAddedToRows');
    debugPrint('   📦 _saleRows.length            : ${_saleRows.length}');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  // ═════════════════════════════════════════════════════════════════════════
  // AGGREGATION
  // ═════════════════════════════════════════════════════════════════════════

  void _computeStats() {
    _itemStats.clear();
    _totalPurchaseCost = 0;
    _totalSaleRevenue = 0;
    _totalProfit = 0;
    _totalProfitPct = 0;
    _totalPurchaseWeight = 0;
    _totalSoldWeight = 0;

    // ── Apply date filter ──────────────────────────────────────────────────
    final purchases = _purchaseRows.where(_inDateRange).toList();
    final sales = _saleRows.where(_inDateRange).toList();

    // ── Group by item key ──────────────────────────────────────────────────
    final Map<String, Map<String, dynamic>> grouped = {};

    for (final p in purchases) {
      final key = p['key'] as String;
      grouped.putIfAbsent(
        key,
            () => {
          'itemName': p['itemName'],
          'length': p['length'],
          'bodyType': p['bodyType'],
          'purchasedWeight': 0.0,
          'purchasedCost': 0.0,
          'soldWeight': 0.0,
          'saleRevenue': 0.0,
          'purchaseCount': 0,
          'saleCount': 0,
        },
      );
      grouped[key]!['purchasedWeight'] =
          (grouped[key]!['purchasedWeight'] as double) +
              (p['weight'] as double);
      grouped[key]!['purchasedCost'] =
          (grouped[key]!['purchasedCost'] as double) + (p['cost'] as double);
      grouped[key]!['purchaseCount'] =
          (grouped[key]!['purchaseCount'] as int) + 1;
    }

    for (final s in sales) {
      final key = s['key'] as String;
      grouped.putIfAbsent(
        key,
            () => {
          'itemName': s['itemName'],
          'length': s['length'],
          'bodyType': s['bodyType'],
          'purchasedWeight': 0.0,
          'purchasedCost': 0.0,
          'soldWeight': 0.0,
          'saleRevenue': 0.0,
          'purchaseCount': 0,
          'saleCount': 0,
        },
      );
      grouped[key]!['soldWeight'] =
          (grouped[key]!['soldWeight'] as double) + (s['weight'] as double);
      grouped[key]!['saleRevenue'] =
          (grouped[key]!['saleRevenue'] as double) + (s['revenue'] as double);
      grouped[key]!['saleCount'] =
          (grouped[key]!['saleCount'] as int) + 1;
    }

    // ── Compute per-item profit ────────────────────────────────────────────
    for (final entry in grouped.entries) {
      final g = entry.value;

      final purchasedWeight = g['purchasedWeight'] as double;
      final purchasedCost = g['purchasedCost'] as double;
      final soldWeight = g['soldWeight'] as double;
      final saleRevenue = g['saleRevenue'] as double;

      final avgCostPerKg =
      purchasedWeight > 0 ? purchasedCost / purchasedWeight : 0.0;

      final costOfGoodsSold = soldWeight * avgCostPerKg;

      final profit = saleRevenue - costOfGoodsSold;

      final profitPct =
      costOfGoodsSold > 0 ? (profit / costOfGoodsSold) * 100 : 0.0;

      _itemStats.add({
        'itemName': g['itemName'],
        'length': g['length'],
        'bodyType': g['bodyType'],
        'purchasedWeight': purchasedWeight,
        'purchasedCost': purchasedCost,
        'avgCostPerKg': avgCostPerKg,
        'soldWeight': soldWeight,
        'saleRevenue': saleRevenue,
        'avgSalePerKg': soldWeight > 0 ? saleRevenue / soldWeight : 0.0,
        'costOfGoodsSold': costOfGoodsSold,
        'profit': profit,
        'profitPct': profitPct,
        'purchaseCount': g['purchaseCount'],
        'saleCount': g['saleCount'],
      });

      _totalPurchaseCost += purchasedCost;
      _totalSaleRevenue += saleRevenue;
      _totalProfit += profit;
      _totalPurchaseWeight += purchasedWeight;
      _totalSoldWeight += soldWeight;
    }

    // Sort by profit descending
    _itemStats.sort((a, b) =>
        (b['profit'] as double).compareTo(a['profit'] as double));

    // Overall profit %
    if (_totalPurchaseCost > 0) {
      _totalProfitPct = (_totalProfit / _totalPurchaseCost) * 100;
    }
  }

  bool _inDateRange(Map<String, dynamic> row) {
    final d = row['date'] as DateTime?;
    if (d == null) return true;
    if (_fromDate != null && d.isBefore(_fromDate!)) return false;
    if (_toDate != null &&
        d.isAfter(_toDate!.add(const Duration(days: 1)))) return false;
    return true;
  }

  String _itemKey(String name, String length, String body) {
    return '${name.toLowerCase().trim()}|${length.toLowerCase().trim()}|${body.toLowerCase().trim()}';
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // DATE PICKERS (update pending dates only)
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _pendingFromDate ??
          DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _pendingFromDate = picked);
    }
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _pendingToDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _pendingToDate = picked);
    }
  }

  void _clearFilter() {
    setState(() {
      _pendingFromDate = null;
      _pendingToDate = null;
    });
  }

  // ═════════════════════════════════════════════════════════════════════════
  // PDF EXPORT
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _exportPdf() async {
    if (!_reportGenerated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generate the report first')),
      );
      return;
    }

    final lp = Provider.of<LanguageProvider>(context, listen: false);
    final pdf = pw.Document();
    final dateFmt = DateFormat('dd MMM yyyy');

    final rangeText = (_fromDate == null && _toDate == null)
        ? 'All Time'
        : '${_fromDate != null ? dateFmt.format(_fromDate!) : "Start"} → '
        '${_toDate != null ? dateFmt.format(_toDate!) : "Now"}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              lp.isEnglish ? 'Profit & Loss Report' : 'نفع و نقصان رپورٹ',
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text('Period: $rangeText',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 6),
          pw.Text(
            'Total Purchase Cost: ${_totalPurchaseCost.toStringAsFixed(2)} PKR',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.Text(
            'Total Sale Revenue: ${_totalSaleRevenue.toStringAsFixed(2)} PKR',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.Text(
            'Net Profit: ${_totalProfit.toStringAsFixed(2)} PKR '
                '(${_totalProfitPct.toStringAsFixed(2)}%)',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: _totalProfit >= 0
                  ? PdfColors.green800
                  : PdfColors.red800,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headers: [
              'Item',
              'Length',
              'Body',
              'Purchased (kg)',
              'Avg Cost/kg',
              'Sold (kg)',
              'Avg Sale/kg',
              'Revenue',
              'COGS',
              'Profit',
              'Profit %',
            ],
            data: _itemStats.map((s) {
              return [
                s['itemName'].toString(),
                s['length'].toString(),
                s['bodyType'].toString(),
                (s['purchasedWeight'] as double).toStringAsFixed(2),
                (s['avgCostPerKg'] as double).toStringAsFixed(2),
                (s['soldWeight'] as double).toStringAsFixed(2),
                (s['avgSalePerKg'] as double).toStringAsFixed(2),
                (s['saleRevenue'] as double).toStringAsFixed(2),
                (s['costOfGoodsSold'] as double).toStringAsFixed(2),
                (s['profit'] as double).toStringAsFixed(2),
                '${(s['profitPct'] as double).toStringAsFixed(2)}%',
              ];
            }).toList(),
            headerStyle:
            pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(4),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    await Printing.layoutPdf(onLayout: (_) => bytes);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final lp = Provider.of<LanguageProvider>(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        title: Text(
          lp.isEnglish ? 'Profit & Loss' : 'نفع و نقصان',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF8A65), Color(0xFFFFB74D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            tooltip: lp.isEnglish ? 'Export PDF' : 'PDF بنائیں',
            onPressed: _exportPdf,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFilterBar(lp),
            const SizedBox(height: 16),
            if (_reportGenerated) ...[
              _buildSummaryCards(lp),
              const SizedBox(height: 20),
              _buildItemTable(lp),
            ] else ...[
              _buildEmptyPrompt(lp),
            ],
          ],
        ),
      ),
    );
  }

  // ── Empty prompt before Generate is pressed ───────────────────────────────
  Widget _buildEmptyPrompt(LanguageProvider lp) {
    return Card(
      elevation: 2,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.bar_chart, size: 56, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                lp.isEnglish
                    ? 'Pick a date range and tap "Generate Report"'
                    : 'تاریخ کی حد منتخب کریں اور "رپورٹ بنائیں" پر کلک کریں',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                lp.isEnglish
                    ? 'Leave dates empty to include all data'
                    : 'تمام ڈیٹا کے لیے تاریخیں خالی چھوڑ دیں',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Filter bar with Generate button ───────────────────────────────────────
  Widget _buildFilterBar(LanguageProvider lp) {
    final dateFmt = DateFormat('dd MMM yyyy');
    return Card(
      elevation: 2,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // ── Date row ─────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      _pendingFromDate == null
                          ? (lp.isEnglish ? 'From Date' : 'شروع تاریخ')
                          : dateFmt.format(_pendingFromDate!),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: _pickFromDate,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event, size: 16),
                    label: Text(
                      _pendingToDate == null
                          ? (lp.isEnglish ? 'To Date' : 'اختتام تاریخ')
                          : dateFmt.format(_pendingToDate!),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: _pickToDate,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.redAccent),
                  tooltip:
                  lp.isEnglish ? 'Clear filter' : 'فلٹر صاف کریں',
                  onPressed: _clearFilter,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Generate Report button ───────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow,
                    size: 20, color: Colors.white),
                label: Text(
                  lp.isEnglish ? 'Generate Report' : 'رپورٹ بنائیں',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[700],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isLoading ? null : _generateReport,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Summary cards ─────────────────────────────────────────────────────────
  Widget _buildSummaryCards(LanguageProvider lp) {
    final profitColor =
    _totalProfit >= 0 ? Colors.green[700]! : Colors.red[700]!;

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _summaryCard(
                  icon: Icons.shopping_cart,
                  title: lp.isEnglish ? 'Purchase Cost' : 'خریداری لاگت',
                  value: 'PKR ${_totalPurchaseCost.toStringAsFixed(2)}',
                  subtitle: '${_totalPurchaseWeight.toStringAsFixed(2)} kg',
                  color: Colors.blue[700]!,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryCard(
                  icon: Icons.sell,
                  title: lp.isEnglish ? 'Sale Revenue' : 'فروخت آمدنی',
                  value: 'PKR ${_totalSaleRevenue.toStringAsFixed(2)}',
                  subtitle: '${_totalSoldWeight.toStringAsFixed(2)} kg',
                  color: Colors.purple[700]!,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _summaryCard(
          icon: _totalProfit >= 0
              ? Icons.trending_up
              : Icons.trending_down,
          title: lp.isEnglish ? 'Net Profit' : 'خالص نفع',
          value: 'PKR ${_totalProfit.toStringAsFixed(2)}',
          subtitle: '${_totalProfitPct.toStringAsFixed(2)}%',
          color: profitColor,
          big: true,
        ),
      ],
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    bool big = false,
  }) {
    return Card(
      elevation: 3,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.08), color.withOpacity(0.02)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: big ? 26 : 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: big ? 20 : 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Per-item table (full width) ───────────────────────────────────────────
  Widget _buildItemTable(LanguageProvider lp) {
    if (_itemStats.isEmpty) {
      return Card(
        elevation: 2,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.bar_chart, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  lp.isEnglish
                      ? 'No purchase / sale data found for this range'
                      : 'اس حد کے لیے کوئی خریداری / فروخت ڈیٹا نہیں ملا',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.orange[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  lp.isEnglish
                      ? 'Per Item Profit & Loss'
                      : 'فی آئٹم نفع و نقصان',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Text(
                    '${_itemStats.length} ${lp.isEnglish ? "items" : "آئٹمز"}',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[800],
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // ── Table ────────────────────────────────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                const double minTableWidth = 1400;
                final double tableWidth =
                constraints.maxWidth < minTableWidth
                    ? minTableWidth
                    : constraints.maxWidth;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: DataTable(
                      headingRowColor:
                      MaterialStateProperty.all(Colors.orange[50]),
                      headingRowHeight: 44,
                      dataRowMinHeight: 40,
                      dataRowMaxHeight: 52,
                      columnSpacing: 20,
                      horizontalMargin: 16,
                      headingTextStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Color(0xFFE65100),
                      ),
                      dataTextStyle: const TextStyle(fontSize: 11),
                      columns: [
                        DataColumn(
                            label:
                            Text(lp.isEnglish ? 'Item' : 'آئٹم')),
                        DataColumn(
                            label:
                            Text(lp.isEnglish ? 'Length' : 'لمبائی')),
                        DataColumn(
                            label: Text(lp.isEnglish ? 'Body' : 'باڈی')),
                        DataColumn(
                            label: Text(lp.isEnglish
                                ? 'Purchased (kg)'
                                : 'خریدا (کلو)'),
                            numeric: true),
                        DataColumn(
                            label: Text(lp.isEnglish
                                ? 'Avg Cost/kg'
                                : 'اوسط لاگت/کلو'),
                            numeric: true),
                        DataColumn(
                            label: Text(
                                lp.isEnglish ? 'Sold (kg)' : 'فروخت (کلو)'),
                            numeric: true),
                        DataColumn(
                            label: Text(lp.isEnglish
                                ? 'Avg Sale/kg'
                                : 'اوسط فروخت/کلو'),
                            numeric: true),
                        DataColumn(
                            label: Text(
                                lp.isEnglish ? 'Revenue' : 'آمدنی'),
                            numeric: true),
                        DataColumn(
                            label: Text(
                                lp.isEnglish ? 'COGS' : 'لاگتِ مال'),
                            numeric: true),
                        DataColumn(
                            label: Text(
                                lp.isEnglish ? 'Profit' : 'نفع'),
                            numeric: true),
                        DataColumn(
                            label: Text(
                                lp.isEnglish ? 'Profit %' : 'نفع %'),
                            numeric: true),
                      ],
                      rows: _itemStats.asMap().entries.map((entry) {
                        final i = entry.key;
                        final s = entry.value;

                        final profit = s['profit'] as double;
                        final profitPct = s['profitPct'] as double;
                        final pColor = profit >= 0
                            ? Colors.green[700]!
                            : Colors.red[700]!;

                        final bg = i.isEven
                            ? Colors.white
                            : Colors.orange[50]!.withOpacity(0.35);

                        final lengthText = s['length'].toString().trim();
                        final bodyText = s['bodyType'].toString().trim();

                        return DataRow(
                          color: MaterialStateProperty.all<Color>(bg),
                          cells: [
                            DataCell(
                              Text(
                                s['itemName'].toString(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            DataCell(Text(
                                lengthText.isEmpty ? '—' : lengthText)),
                            DataCell(Text(
                                bodyText.isEmpty ? '—' : bodyText)),
                            DataCell(Text(
                                (s['purchasedWeight'] as double)
                                    .toStringAsFixed(2))),
                            DataCell(Text(
                                (s['avgCostPerKg'] as double)
                                    .toStringAsFixed(2))),
                            DataCell(Text(
                                (s['soldWeight'] as double)
                                    .toStringAsFixed(2))),
                            DataCell(Text(
                                (s['avgSalePerKg'] as double)
                                    .toStringAsFixed(2))),
                            DataCell(Text(
                                (s['saleRevenue'] as double)
                                    .toStringAsFixed(2))),
                            DataCell(Text(
                                (s['costOfGoodsSold'] as double)
                                    .toStringAsFixed(2))),
                            DataCell(
                              Text(
                                profit.toStringAsFixed(2),
                                style: TextStyle(
                                  color: pColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: pColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: pColor.withOpacity(0.3)),
                                ),
                                child: Text(
                                  '${profitPct.toStringAsFixed(2)}%',
                                  style: TextStyle(
                                    color: pColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}