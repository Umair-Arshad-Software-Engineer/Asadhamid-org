import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:js_interop';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../Models/itemModel.dart';
import '../Models/mazdoorModel.dart';
import '../Provider/Mazdoorprovider ·.dart';
import '../Provider/filled provider.dart';
import '../Provider/lanprovider.dart';
import '../Purchase/pdf_branding.dart';
import '../bankmanagement/banknames.dart';

@JS('copyPngToClipboard')
external JSPromise<JSBoolean> _copyPngToClipboardJs(JSString base64Png);

@JS('sharePngWithText')
external JSPromise<JSBoolean> _sharePngWithTextJs(
    JSString base64Png, JSString text, JSString fileName);

enum MazdoorJobMode { giveWire, receiveReturn }

// ─────────────────────────────────────────────────────────────────────────────
// Row model
// ─────────────────────────────────────────────────────────────────────────────
class _JobRow {
  final itemNameController = TextEditingController();
  final lengthController = TextEditingController();
  final bodyTypeController = TextEditingController();
  final descriptionController = TextEditingController();
  final quantityController = TextEditingController();
  final weightController = TextEditingController();
  final rateController = TextEditingController();

  Item? selectedItem;
  String? fullName;
  String? displayName;

  // Batch tracking
  String? batchId;
  String? batchNumber;
  double? availableBatchQty;

  // Calculation state
  String calculationType = 'quantity';
  double? weightPerUnit;
  String weightUnit = 'kg';
  double? totalWeight;
  double computedTotal = 0.0;

  void dispose() {
    itemNameController.dispose();
    lengthController.dispose();
    bodyTypeController.dispose();
    descriptionController.dispose();
    quantityController.dispose();
    weightController.dispose();
    rateController.dispose();
  }
}

class _ReceiptRow {
  final String item, length, body, desc, batch;
  final double rate, qty, wpu, totalWt, amount;
  const _ReceiptRow({
    required this.item,
    required this.length,
    required this.body,
    required this.desc,
    required this.batch,
    required this.rate,
    required this.qty,
    required this.wpu,
    required this.totalWt,
    required this.amount,
  });
}

class _Receipt {
  final String title;
  final String kind;
  final bool isGive;
  final List<_ReceiptRow> rows;
  final double value;
  final double previousBalance;
  final double currentBalance;
  final DateTime when;
  final String method, bank, chequeNo, description;
  final String summary;

  const _Receipt({
    required this.title,
    required this.kind,
    required this.isGive,
    required this.rows,
    required this.value,
    required this.previousBalance,
    required this.currentBalance,
    required this.when,
    this.method = '',
    this.bank = '',
    this.chequeNo = '',
    this.description = '',
    required this.summary,
  });
}

class MazdoorJobPage extends StatefulWidget {
  final String mazdoorId;
  final String mazdoorName;
  final String mazdoorPhone;
  final MazdoorJobMode mode;

  const MazdoorJobPage({
    Key? key,
    required this.mazdoorId,
    required this.mazdoorName,
    this.mazdoorPhone = '',
    required this.mode,
  }) : super(key: key);

  @override
  _MazdoorJobPageState createState() => _MazdoorJobPageState();
}

class _MazdoorJobPageState extends State<MazdoorJobPage> {
  static const Color _orange = Color(0xFFFF8A65);
  static const Color _orangeDark = Color(0xFFE65100);

  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  List<Item> _items = [];
  bool _isLoadingItems = false;
  bool _isSaving = false;

  String _tab = 'bolt';
  final List<_JobRow> _boltRows = [_JobRow(), _JobRow(), _JobRow()];
  final List<_JobRow> _wireRows = [_JobRow(), _JobRow(), _JobRow()];

  // Header fields
  final TextEditingController _biltiNumberController = TextEditingController();
  final TextEditingController _transportCompanyController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  bool _isAutoReference = true;

  // Cash State
  final TextEditingController _cashAmountController = TextEditingController();
  final TextEditingController _cashDescController = TextEditingController();
  String? _selectedPaymentMethod;
  DateTime _selectedPaymentDate = DateTime.now();
  String? _selectedBankId;
  String? _selectedBankName;
  final TextEditingController _chequeNumberController = TextEditingController();
  DateTime? _selectedChequeDate;
  Uint8List? _paymentImage;
  List<Map<String, dynamic>> _cachedBanks = [];

  String _phone = '';
  String _address = '';

  bool get _isGiveWire => widget.mode == MazdoorJobMode.giveWire;
  bool get _isWireTab => _tab == 'wire';
  List<_JobRow> get _rows => _isWireTab ? _wireRows : _boltRows;

  @override
  void initState() {
    super.initState();
    PdfBranding.ensureAssets();
    _phone = widget.mazdoorPhone;
    _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _resolveContact();
    _fetchItems();
  }

  void _resolveContact() {
    try {
      final list = Provider.of<MazdoorProvider>(context, listen: false).mazdoors;
      final found = list.where((m) => m.id == widget.mazdoorId);
      if (found.isNotEmpty) {
        final m = found.first;
        if (_phone.trim().isEmpty) _phone = m.phone.toString();
        final parts = <String>[
          m.address.toString().trim(),
          m.city.toString().trim(),
        ].where((s) => s.isNotEmpty).toList();
        _address = parts.join(', ');
      }
    } catch (e) {
      print('Mazdoor contact lookup failed: $e');
    }
  }

  Future<void> _fetchItems() async {
    setState(() => _isLoadingItems = true);
    try {
      final snapshot = await _db.child('items').get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        if (mounted) {
          setState(() {
            _items = data.entries
                .map((e) => Item.fromMap(e.value as Map<dynamic, dynamic>, e.key.toString()))
                .toList();
          });
        }
      }
    } finally {
      if (mounted) setState(() => _isLoadingItems = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateController.text.isNotEmpty ? DateTime.parse(_dateController.text) : DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════

  double _parse(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String _fmtQty(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);

  String _fmtWeight(double w, [String unit = 'kg']) =>
      w > 0 ? '${w.toStringAsFixed(2)} $unit' : 'N/A';

  String _rowName(_JobRow r) {
    final t = r.itemNameController.text.trim();
    if (r.fullName != null && r.displayName == t) return r.fullName!;
    return t;
  }

  String? _rowItemId(_JobRow r) {
    final s = r.selectedItem;
    if (s == null || s.id.startsWith('manual_')) return null;
    return _rowName(r) == s.itemName ? s.id : null;
  }

  double _tabTotal() => _rows.fold<double>(0, (s, r) => s + r.computedTotal);

  double _tabTotalWeight() =>
      _rows.fold<double>(0, (s, r) => s + (r.totalWeight ?? 0.0));

  String? _ledgerDescription(_JobRow r) {
    final parts = <String>[];
    final l = r.lengthController.text.trim();
    final b = r.bodyTypeController.text.trim();
    final d = r.descriptionController.text.trim();
    if (l.isNotEmpty) parts.add('Length: $l');
    if (b.isNotEmpty) parts.add('Body: $b');
    if (d.isNotEmpty) parts.add(d);
    return parts.isEmpty ? null : parts.join(' | ');
  }

  Map<String, String> _parseBOMName(String bomName) {
    final res = {'size': bomName, 'length': '', 'bodyType': '', 'fullName': bomName};
    if (bomName.contains('|')) {
      final parts = bomName.split('|').map((e) => e.trim()).toList();
      if (parts.isNotEmpty) res['size'] = parts[0];
      if (parts.length >= 2) res['length'] = parts[1];
      if (parts.length >= 3) res['bodyType'] = parts[2];
    }
    return res;
  }

  String _formatBOMName(String bomName) {
    if (!bomName.contains('|')) return bomName;
    final p = bomName.split('|');
    if (p.length >= 3) {
      return 'Size: ${p[0].trim()} | Length: ${p[1].trim()} | Body: ${p[2].trim()}';
    }
    return bomName;
  }

  void _parseWeightInput(_JobRow row, String raw) {
    if (raw.trim().isEmpty) {
      row.weightPerUnit = null;
      row.totalWeight = null;
      _recalcRow(row);
      return;
    }
    final parts = raw.trim().split(RegExp(r'\s+'));
    double? value = double.tryParse(parts.first);
    String unit = row.weightUnit;
    if (parts.length > 1) {
      final u = parts.sublist(1).join(' ').toLowerCase();
      if (u.contains('kg') || u.contains('kilogram')) unit = 'kg';
      else if (u.contains('gram') || u == 'g') unit = 'g';
      else if (u.contains('lb') || u.contains('pound')) unit = 'lb';
      else if (u.contains('ton')) unit = 'ton';
    }
    row.weightUnit = unit;
    row.weightPerUnit = value;
    _recalcRow(row);
  }

  void _recalcRow(_JobRow row) {
    final qty = _parse(row.quantityController.text);
    final rate = _parse(row.rateController.text);

    double? totalWeight;
    if (row.weightPerUnit != null && row.weightPerUnit! > 0 && qty > 0) {
      totalWeight = row.weightPerUnit! * qty;
    } else {
      totalWeight = row.totalWeight;
    }
    row.totalWeight = totalWeight;

    double total;
    if (row.calculationType == 'weight' && totalWeight != null && totalWeight > 0) {
      total = rate * totalWeight;
    } else {
      total = rate * qty;
    }
    row.computedTotal = total;

    setState(() {});
  }

  String _displayTotalWeight(_JobRow row) {
    final qty = _parse(row.quantityController.text);
    final wpu = row.weightPerUnit;
    if (qty > 0 && wpu != null && wpu > 0) {
      return _fmtWeight(qty * wpu, row.weightUnit);
    }
    if (row.totalWeight != null && row.totalWeight! > 0) {
      return _fmtWeight(row.totalWeight!, row.weightUnit);
    }
    return 'N/A';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _validation(LanguageProvider lp, String en, String ur) =>
      _snack(lp.isEnglish ? en : ur);

  void _addRow() => setState(() => _rows.add(_JobRow()));

  void _removeRow(int index) {
    final rows = _rows;
    if (rows.length <= 1 || index < 0 || index >= rows.length) return;
    final r = rows[index];
    setState(() => rows.removeAt(index));
    WidgetsBinding.instance.addPostFrameCallback((_) => r.dispose());
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Item selection & Batch Selection
  // ═══════════════════════════════════════════════════════════════════════

  void _applyItem(_JobRow row, Item item, LengthBodyCombination? combo, bool wire) {
    final parsed = _parseBOMName(item.itemName);
    setState(() {
      row.selectedItem = item;
      row.fullName = item.itemName;
      row.displayName = parsed['size'];
      row.itemNameController.text = parsed['size']!;
      row.lengthController.text = parsed['length']!;
      row.bodyTypeController.text = parsed['bodyType']!;

      row.batchId = null;
      row.batchNumber = null;
      row.availableBatchQty = null;

      double rate = 0;
      if (combo != null) {
        row.lengthController.text = combo.length;
        row.bodyTypeController.text = combo.bodyType;
        final w = combo.weightPerUnit ?? 0;
        if (w > 0) {
          row.weightPerUnit = w;
          row.weightUnit = combo.weightUnit ?? 'kg';
          row.weightController.text = '$w ${row.weightUnit}';
          row.calculationType = 'weight';
        }
        rate = combo.salePricePerKg ?? 0;
      }
      if (rate <= 0 && wire && item.lengthBodyCombinations != null) {
        for (final c in item.lengthBodyCombinations!) {
          if ((c.salePricePerKg ?? 0) > 0) {
            rate = c.salePricePerKg!;
            break;
          }
        }
      }
      if (rate <= 0) rate = item.avgSalePricePerKg;
      if (rate > 0) row.rateController.text = rate.toStringAsFixed(2);

      if (_parse(row.quantityController.text) <= 0) {
        row.quantityController.text = '1';
      }
      _recalcRow(row);
    });
  }

  Future<void> _showItemSearchDialog(_JobRow row, bool wire) async {
    final lp = Provider.of<LanguageProvider>(context, listen: false);
    final searchController = TextEditingController();
    List<Item> filtered = List.from(_items);

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            lp.isEnglish ? 'Select Item' : 'آئٹم منتخب کریں',
            style: const TextStyle(color: _orangeDark),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 520,
            child: Column(children: [
              TextField(
                controller: searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: lp.isEnglish ? 'Search items...' : 'آئٹمز تلاش کریں...',
                  prefixIcon: const Icon(Icons.search, color: _orange),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _orange, width: 2),
                  ),
                ),
                onChanged: (v) => setDialogState(() {
                  final q = v.toLowerCase();
                  filtered = v.isEmpty
                      ? List.from(_items)
                      : _items
                      .where((i) => i.itemName.toLowerCase().contains(q))
                      .toList();
                }),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                  child: Text(
                    lp.isEnglish ? 'No items found' : 'کوئی آئٹم نہیں ملا',
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
                    : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final it = filtered[i];
                    final hasCombos = it.lengthBodyCombinations != null &&
                        it.lengthBodyCombinations!.isNotEmpty;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(
                          it.itemName.contains('|')
                              ? _parseBOMName(it.itemName)['size'] ?? it.itemName
                              : it.itemName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: _orangeDark),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (it.itemName.contains('|'))
                              Text(
                                _formatBOMName(it.itemName),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                    fontStyle: FontStyle.italic),
                              ),
                            Text(
                              '${lp.isEnglish ? "Sale" : "سیل"}: ${it.avgSalePricePerKg.toStringAsFixed(2)} | '
                                  '${lp.isEnglish ? "Stock" : "اسٹاک"}: ${it.qtyOnHand.toStringAsFixed(2)}',
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                            if (hasCombos)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.blue[100]!),
                                ),
                                child: Text(
                                  lp.isEnglish
                                      ? 'Has length combinations'
                                      : 'لمبائی کے مجموعے ہیں',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                        trailing:
                        const Icon(Icons.add, size: 16, color: _orange),
                        onTap: () {
                          Navigator.pop(dialogContext);
                          if (hasCombos) {
                            Future.delayed(const Duration(milliseconds: 100), () {
                              if (mounted) _showCombinationDialog(row, it, wire);
                            });
                          } else {
                            _applyItem(row, it, null, wire);
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(lp.isEnglish ? 'Cancel' : 'منسوخ کریں',
                  style: const TextStyle(color: _orange)),
            ),
          ],
        ),
      ),
    );
    searchController.dispose();
  }

  void _showCombinationDialog(_JobRow row, Item item, bool wire) {
    final lp = Provider.of<LanguageProvider>(context, listen: false);
    final combos = item.lengthBodyCombinations ?? [];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(lp.isEnglish
            ? 'Select Length-Body Combination'
            : 'لمبائی-جسم کا مجموعہ منتخب کریں'),
        content: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxHeight: 400),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: combos.length,
            itemBuilder: (context, index) {
              final c = combos[index];
              final wpu = c.weightPerUnit ?? 0;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text('${c.length} - ${c.bodyType}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (c.lengthDecimal.isNotEmpty)
                        Text('Decimal: ${c.lengthDecimal}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      if (wpu > 0)
                        Text('Weight/Unit: $wpu ${c.weightUnit ?? 'kg'}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.blue)),
                      if ((c.salePricePerKg ?? 0) > 0)
                        Text(
                            'Price/Kg: ${c.salePricePerKg!.toStringAsFixed(2)} PKR',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.green)),
                    ],
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () {
                    Navigator.pop(context);
                    _applyItem(row, item, c, wire);
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(lp.isEnglish ? 'Cancel' : 'منسوخ'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _applyItem(row, item, null, wire);
            },
            child: Text(lp.isEnglish ? 'Skip' : 'چھوڑ دیں'),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchBatchesForItem(String itemName) async {
    final List<Map<String, dynamic>> batches = [];
    try {
      final snapshot = await _db.child('batches').get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          final batch = Map<String, dynamic>.from(value);
          final quantity = (batch['quantity'] as num?)?.toDouble() ?? 0.0;
          final isActive = batch['isActive'] == true;
          if (batch['itemName'] == itemName && quantity > 0 && isActive) {
            final purchasePrice = (batch['purchasePrice'] as num?)?.toDouble() ??
                (batch['costPrice'] as num?)?.toDouble() ??
                0.0;
            batches.add({
              'id': key,
              'batchNumber': batch['batchNumber'] ?? 'N/A',
              'quantity': quantity,
              'purchasePrice': purchasePrice,
              'timestamp': batch['timestamp']?.toString() ?? '',
            });
          }
        });
        batches.sort((a, b) => a['timestamp'].toString().compareTo(b['timestamp'].toString()));
      }
    } catch (e) {
      print('Error fetching batches: $e');
    }
    return batches;
  }

  Future<void> _pickBatch(_JobRow row) async {
    final lp = Provider.of<LanguageProvider>(context, listen: false);
    final itemName = _rowName(row);
    if (itemName.isEmpty) {
      _snack(lp.isEnglish ? 'Please select an item first' : 'پہلے آئٹم منتخب کریں');
      return;
    }
    final batches = await _fetchBatchesForItem(itemName);
    if (!mounted) return;
    if (batches.isEmpty) {
      _snack(lp.isEnglish
          ? 'No batches available for $itemName'
          : '$itemName کے لیے کوئی بیچ دستیاب نہیں');
      return;
    }
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(lp.isEnglish
            ? 'Select Batch for $itemName'
            : '$itemName کے لیے بیچ منتخب کریں'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: batches.length,
            itemBuilder: (context, i) {
              final b = batches[i];
              final qty = (b['quantity'] as num).toDouble();
              final price = (b['purchasePrice'] as num).toDouble();
              final number = b['batchNumber'].toString();
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(number,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'Available: ${qty.toStringAsFixed(2)} kg  |  ${price.toStringAsFixed(2)} PKR/kg'),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () {
                      setState(() {
                        row.batchId = b['id'].toString();
                        row.batchNumber = number;
                        row.availableBatchQty = qty;
                      });
                      Navigator.pop(context);
                    },
                    child: const Text('Select',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                row.batchId = null;
                row.batchNumber = null;
                row.availableBatchQty = null;
              });
              Navigator.pop(context);
            },
            child: Text(lp.isEnglish ? 'No batch' : 'بیچ نہیں'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(lp.isEnglish ? 'Cancel' : 'منسوخ'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // WhatsApp / Share Helpers
  // ═══════════════════════════════════════════════════════════════════════

  String? _normalizePkNumber(String raw) {
    var n = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (n.startsWith('+')) n = n.substring(1);
    if (n.startsWith('00')) n = n.substring(2);
    if (n.startsWith('0')) n = '92${n.substring(1)}';
    if (n.startsWith('92') && n.length == 12) return n;
    return null;
  }

  Future<bool> _isWhatsAppAvailable(String number) async {
    if (kIsWeb) return true;
    try {
      return await canLaunchUrl(Uri.parse('whatsapp://send?phone=$number'));
    } catch (_) {
      return false;
    }
  }

  Future<bool> _copyImageToClipboard(Uint8List png) async {
    if (!kIsWeb) return false;
    try {
      final r = await _copyPngToClipboardJs(base64Encode(png).toJS).toDart;
      return r.toDart;
    } catch (e) {
      print('Clipboard copy failed: $e');
      return false;
    }
  }

  Future<bool> _shareImageWithText(
      Uint8List png, String text, String fileName) async {
    if (kIsWeb) {
      try {
        final r =
        await _sharePngWithTextJs(base64Encode(png).toJS, text.toJS, fileName.toJS)
            .toDart;
        return r.toDart;
      } catch (e) {
        print('Web share failed: $e');
        return false;
      }
    }
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(png);
      await Share.shareXFiles([XFile(file.path)], text: text);
      return true;
    } catch (e) {
      print('Share failed: $e');
      return false;
    }
  }

  Future<void> _downloadPDFWeb(Uint8List bytes, String fileName) async {
    try {
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      print('PDF download failed: $e');
    }
  }

  Future<void> _sendWhatsAppTextOnly(String number, String message) async {
    final link =
        'whatsapp://send?phone=$number&text=${Uri.encodeComponent(message)}';
    if (kIsWeb) {
      final a = html.AnchorElement(href: link)
        ..target = '_self'
        ..style.display = 'none';
      html.document.body?.append(a);
      a.click();
      a.remove();
    } else {
      await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // RECEIPT PDF
  // ═══════════════════════════════════════════════════════════════════════

  String _balanceText(double b) {
    if (b.abs() < 0.005) return 'Settled';
    return b > 0
        ? '${b.toStringAsFixed(2)} PKR (owes you)'
        : '${(-b).toStringAsFixed(2)} PKR (you owe)';
  }

  Future<Uint8List> _buildReceiptPdf(_Receipt r) async {
    await PdfBranding.ensureAssets();

    final isWire = r.kind == 'wire';
    final isCash = r.kind == 'cash';
    final name = widget.mazdoorName.trim();

    final jobs = <Future<void>>[];
    Map<String, pw.MemoryImage> prepare(
        Iterable<String> texts, double fs, double w, double h) {
      final m = <String, pw.MemoryImage>{};
      for (final raw in texts) {
        final t = raw.trim();
        if (!PdfBranding.needsImage(t) || m.containsKey(t)) continue;
        jobs.add(PdfBranding.textImage(t, fontSize: fs, width: w, height: h)
            .then((img) => m[t] = img));
      }
      return m;
    }

    final sizeImgs = prepare(r.rows.map((e) => e.item), 42, 228, 66);
    final lengthImgs = prepare(r.rows.map((e) => e.length), 42, 201, 66);
    final bodyImgs = prepare(r.rows.map((e) => e.body), 42, 144, 66);
    final descImgs = prepare(r.rows.map((e) => e.desc), 11, 110, 20);
    final fieldImgs =
    prepare([name, _address, r.description, r.bank], 42, 165 * 3, 66);
    await Future.wait(jobs);

    String two(int n) => n.toString().padLeft(2, '0');
    final w = r.when;
    final dateText = '${w.year}-${two(w.month)}-${two(w.day)} '
        '${two(w.hour)}:${two(w.minute)}';

    pw.Widget fieldFor(String label, String text) =>
        PdfBranding.field(label, img: fieldImgs[text.trim()], text: text);

    pw.Widget mazdoorSection() => pw.Column(children: [
      PdfBranding.sectionHeader('MAZDOOR DETAILS'),
      PdfBranding.sectionBody(pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
                child: pw.Column(children: [
                  fieldFor('Mazdoor Name', name),
                  PdfBranding.field('Transaction',
                      text: r.isGive
                          ? 'Given to Mazdoor'
                          : 'Received from Mazdoor'),
                ])),
            pw.SizedBox(width: 18),
            pw.Expanded(
                child: pw.Column(children: [
                  PdfBranding.field('Phone Number', text: _phone),
                  fieldFor('Address', _address),
                ])),
          ])),
    ]);

    pw.Widget itemsSection() {
      final headers = isWire
          ? [
        'No.',
        'Size',
        'Length',
        'Body Type',
        'Desc.',
        'Rate\n(PKR/KG)',
        'Wt/Unit\n(KG)',
        'Qty',
        'Tot.Wt\n(KG)',
        'Amount\n(PKR)'
      ]
          : [
        'No.',
        'Size',
        'Length',
        'Body Type',
        'Desc.',
        'Rate\n(PKR)',
        'Qty',
        'Amount\n(PKR)'
      ];

      final widths = isWire
          ? const {
        0: pw.FlexColumnWidth(0.6),
        1: pw.FlexColumnWidth(1.8),
        2: pw.FlexColumnWidth(1.6),
        3: pw.FlexColumnWidth(1.2),
        4: pw.FlexColumnWidth(1.4),
        5: pw.FlexColumnWidth(1.1),
        6: pw.FlexColumnWidth(1.1),
        7: pw.FlexColumnWidth(0.8),
        8: pw.FlexColumnWidth(1.1),
        9: pw.FlexColumnWidth(1.4),
      }
          : const {
        0: pw.FlexColumnWidth(0.6),
        1: pw.FlexColumnWidth(2.2),
        2: pw.FlexColumnWidth(1.6),
        3: pw.FlexColumnWidth(1.3),
        4: pw.FlexColumnWidth(1.8),
        5: pw.FlexColumnWidth(1.2),
        6: pw.FlexColumnWidth(0.9),
        7: pw.FlexColumnWidth(1.5),
      };

      const minRows = 8;
      final rowCount = r.rows.length > minRows ? r.rows.length : minRows;

      pw.TableRow dataRow(int i) {
        final e = r.rows[i];
        final cells = <pw.Widget>[
          PdfBranding.cell('${i + 1}'),
          PdfBranding.imgCell(sizeImgs[e.item.trim()], e.item, h: 22),
          PdfBranding.imgCell(lengthImgs[e.length.trim()], e.length, h: 22),
          PdfBranding.imgCell(bodyImgs[e.body.trim()], e.body, h: 22),
          PdfBranding.imgCell(descImgs[e.desc.trim()], e.desc),
          PdfBranding.cell(e.rate.toStringAsFixed(2)),
          if (isWire)
            PdfBranding.cell(e.wpu > 0 ? e.wpu.toStringAsFixed(2) : '-'),
          PdfBranding.cell(_fmtQty(e.qty)),
          if (isWire)
            PdfBranding.cell(e.totalWt > 0 ? e.totalWt.toStringAsFixed(2) : '-'),
          PdfBranding.cell(e.amount.toStringAsFixed(2), bold: true),
        ];
        return pw.TableRow(
          decoration: pw.BoxDecoration(
              color: i.isEven ? PdfColors.white : PdfBranding.softBg),
          children: cells,
        );
      }

      pw.TableRow emptyRow(int i) => pw.TableRow(
        decoration: pw.BoxDecoration(
            color: i.isEven ? PdfColors.white : PdfBranding.softBg),
        children: [
          PdfBranding.cell('${i + 1}'),
          for (int k = 0; k < headers.length - 1; k++)
            PdfBranding.cell(''),
        ],
      );

      return pw.Column(children: [
        PdfBranding.sectionHeader(isWire ? 'WIRE DETAILS' : 'BOLT DETAILS'),
        pw.Table(
          border: pw.TableBorder(
            left: pw.BorderSide(color: PdfBranding.navy, width: 0.8),
            right: pw.BorderSide(color: PdfBranding.navy, width: 0.8),
            bottom: pw.BorderSide(color: PdfBranding.navy, width: 0.8),
            horizontalInside:
            pw.BorderSide(color: PdfBranding.softLine, width: 0.4),
            verticalInside:
            pw.BorderSide(color: PdfBranding.softLine, width: 0.4),
          ),
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          columnWidths: widths,
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfBranding.orange),
              children: headers.map(PdfBranding.headCell).toList(),
            ),
            for (int i = 0; i < rowCount; i++)
              i < r.rows.length ? dataRow(i) : emptyRow(i),
          ],
        ),
      ]);
    }

    pw.Widget cashSection() => pw.Column(children: [
      PdfBranding.sectionHeader('PAYMENT DETAILS'),
      PdfBranding.sectionBody(pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
                child: pw.Column(children: [
                  PdfBranding.field('Method', text: r.method),
                  PdfBranding.field('Date', text: dateText),
                  fieldFor('Description',
                      r.description.isEmpty ? '-' : r.description),
                ])),
            pw.SizedBox(width: 18),
            pw.Expanded(
                child: pw.Column(children: [
                  PdfBranding.field('Amount',
                      text: '${r.value.toStringAsFixed(2)} PKR'),
                  fieldFor('Bank', r.bank.isEmpty ? '-' : r.bank),
                  PdfBranding.field('Cheque No',
                      text: r.chequeNo.isEmpty ? '-' : r.chequeNo),
                ])),
          ])),
    ]);

    final totalQty = r.rows.fold<double>(0, (s, e) => s + e.qty);
    final totalWt = r.rows.fold<double>(0, (s, e) => s + e.totalWt);

    pw.Widget summaryBox() => PdfBranding.framed(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          PdfBranding.boxTitle('TOTAL SUMMARY'),
          pw.SizedBox(height: 6),
          pw.Expanded(
            child: pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8),
              color: PdfBranding.softBg,
              child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: isCash
                      ? [
                    PdfBranding.sumRow('Method', r.method, bold: true),
                    PdfBranding.sumRow('Amount',
                        '${r.value.toStringAsFixed(2)} PKR',
                        big: true, color: PdfBranding.orange),
                  ]
                      : [
                    PdfBranding.sumRow(
                        'Total Items', '${r.rows.length}',
                        bold: true),
                    isWire
                        ? PdfBranding.sumRow(
                        'Total Weight',
                        '${totalWt.toStringAsFixed(2)} KG',
                        bold: true)
                        : PdfBranding.sumRow(
                        'Total Quantity', _fmtQty(totalQty),
                        bold: true),
                    PdfBranding.sumRow('Total Value',
                        '${r.value.toStringAsFixed(2)} PKR',
                        big: true, color: PdfBranding.orange),
                  ]),
            ),
          ),
        ]));

    pw.Widget accountBox() => PdfBranding.framed(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          PdfBranding.boxTitle('MAZDOOR ACCOUNT'),
          pw.SizedBox(height: 6),
          PdfBranding.acctRow(
              'Previous Balance', _balanceText(r.previousBalance)),
          PdfBranding.acctRow(r.title, '${r.value.toStringAsFixed(2)} PKR'),
          pw.Spacer(),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: pw.BoxDecoration(
                color: PdfBranding.orange,
                borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  PdfBranding.txt('Current Balance',
                      size: 10, bold: true, color: PdfColors.white),
                  PdfBranding.txt(_balanceText(r.currentBalance),
                      size: 10.5, bold: true, color: PdfColors.white),
                ]),
          ),
        ]));

    final batchNumbers = r.rows
        .map((e) => e.batch)
        .where((b) => b.isNotEmpty)
        .toSet()
        .toList();
    final noteText = [
      if (!isCash) 'Weight and Amount are calculated automatically.',
      if (batchNumbers.isNotEmpty) 'Batch: ${batchNumbers.join(', ')}',
    ].join('   |   ');

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        header: (ctx) =>
        ctx.pageNumber == 1 ? PdfBranding.header() : pw.SizedBox(height: 18),
        footer: (ctx) => PdfBranding.footer(),
        build: (ctx) => [
          PdfBranding.pad(PdfBranding.titleBanner(r.title.toUpperCase()), v: 10),
          PdfBranding.pad(pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                PdfBranding.infoBox('Transaction', r.title),
                PdfBranding.infoBox('Date & Time', dateText),
              ])),
          pw.SizedBox(height: 10),
          PdfBranding.pad(mazdoorSection()),
          pw.SizedBox(height: 12),
          PdfBranding.pad(isCash ? cashSection() : itemsSection()),
          if (noteText.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            PdfBranding.pad(
                PdfBranding.txt(noteText, size: 7.5, color: PdfBranding.grey)),
          ],
          pw.SizedBox(height: 8),
          PdfBranding.pad(pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: summaryBox()),
                pw.SizedBox(width: 12),
                pw.Expanded(child: accountBox()),
              ])),
        ],
      ),
    );
    return pdf.save();
  }

  Future<void> _showReceiptDialog(_Receipt r) async {
    if (!mounted) return;
    final isEn =
        Provider.of<LanguageProvider>(context, listen: false).isEnglish;

    final number = _normalizePkNumber(_phone);
    final canWa = number != null && await _isWhatsAppAvailable(number);
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    Uint8List? pdfBytes;
    Uint8List? pngBytes;
    try {
      pdfBytes = await _buildReceiptPdf(r);
      if (canWa) {
        await for (final page in Printing.raster(pdfBytes, pages: [0], dpi: 110)) {
          pngBytes = await page.toPng();
          break;
        }
      }
    } catch (e) {
      print('Receipt build failed: $e');
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final balanceLine = r.currentBalance.abs() < 0.005
        ? 'Balance: Settled'
        : r.currentBalance > 0
        ? 'Balance: Rs ${r.currentBalance.toStringAsFixed(2)} (owed to us)'
        : 'Balance: Rs ${(-r.currentBalance).toStringAsFixed(2)} (we owe you)';

    final message = 'Assalam o Alaikum ${widget.mazdoorName},\n'
        '${r.summary}\n'
        'Date: ${DateFormat('dd/MM/yyyy').format(r.when)}\n'
        '$balanceLine\n'
        'Thank you!';

    final fileBase =
        'Mazdoor_${widget.mazdoorName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}_${DateFormat('yyyyMMdd_HHmm').format(r.when)}';

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(canWa
            ? (isEn ? 'Send on WhatsApp' : 'واٹس ایپ پر بھیجیں')
            : (isEn ? 'Receipt ready' : 'رسید تیار ہے')),
        content: Text(canWa
            ? (isEn
            ? 'Send receipt to ${widget.mazdoorName} ($_phone)?\n\n'
            'Image + Message: the receipt is copied and WhatsApp opens the '
            'chat. Press Ctrl+V to attach it.\n\n'
            'Share Image: pick WhatsApp from the share sheet.'
            : '${widget.mazdoorName} ($_phone) کو رسید بھیجیں؟\n\n'
            'تصویر + پیغام: رسید کاپی ہوگی اور چیٹ کھلے گی، پھر Ctrl+V دبائیں۔\n\n'
            'شیئر: شیئر مینو سے واٹس ایپ منتخب کریں۔')
            : (isEn
            ? 'Saved. No valid WhatsApp number on file for this Mazdoor, '
            'you can still print or download the receipt.'
            : 'محفوظ ہو گیا۔ اس مزدور کا درست واٹس ایپ نمبر موجود نہیں، '
            'آپ رسید پرنٹ یا ڈاؤن لوڈ کر سکتے ہیں۔')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isEn ? 'Close' : 'بند کریں'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.print, size: 18),
            label: Text(isEn ? 'Print' : 'پرنٹ'),
            onPressed: pdfBytes == null
                ? null
                : () async {
              await Printing.layoutPdf(
                  onLayout: (format) async => pdfBytes!);
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: Text(isEn ? 'Download PDF' : 'پی ڈی ایف ڈاؤن لوڈ'),
            onPressed: pdfBytes == null
                ? null
                : () => _downloadPDFWeb(pdfBytes!, '$fileBase.pdf'),
          ),
          if (canWa) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.message, size: 18),
              label: Text(isEn ? 'Text Only' : 'صرف پیغام'),
              onPressed: () async {
                Navigator.pop(ctx);
                await _sendWhatsAppTextOnly(number!, message);
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.share, size: 18),
              label: Text(isEn ? 'Share Image' : 'تصویر شیئر کریں'),
              onPressed: pngBytes == null
                  ? null
                  : () async {
                Navigator.pop(ctx);
                final ok = await _shareImageWithText(
                    pngBytes!, message, '$fileBase.png');
                if (!ok) {
                  _snack(isEn
                      ? 'Sharing not supported here. Use Image + Message.'
                      : 'یہاں شیئرنگ دستیاب نہیں۔ تصویر + پیغام استعمال کریں۔');
                }
              },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.image, size: 18),
              label: Text(isEn ? 'Image + Message' : 'تصویر + پیغام'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: pngBytes == null
                  ? null
                  : () async {
                Navigator.pop(ctx);
                final copied = await _copyImageToClipboard(pngBytes!);
                await _sendWhatsAppTextOnly(number!, message);
                _snack(copied
                    ? (isEn
                    ? 'Receipt copied. Press Ctrl+V in the chat.'
                    : 'رسید کاپی ہو گئی۔ چیٹ میں Ctrl+V دبائیں۔')
                    : (isEn
                    ? 'Could not copy the image. Use Share Image or Download PDF.'
                    : 'تصویر کاپی نہیں ہو سکی۔ شیئر یا پی ڈی ایف استعمال کریں۔'));
              },
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Bank / Image helpers
  // ═══════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> _selectBank(BuildContext context) async {
    if (_cachedBanks.isEmpty) {
      final bankSnapshot = await FirebaseDatabase.instance.ref('banks').once();
      if (bankSnapshot.snapshot.value == null) return null;
      final banks = bankSnapshot.snapshot.value as Map<dynamic, dynamic>;
      _cachedBanks = banks.entries
          .map((e) => {
        'id': e.key,
        'name': e.value['name'],
        'balance': e.value['balance'],
      })
          .toList();
    }

    final lp = Provider.of<LanguageProvider>(context, listen: false);
    Map<String, dynamic>? selectedBank;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(lp.isEnglish ? 'Select Bank' : 'بینک منتخب کریں'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _cachedBanks.length,
            itemBuilder: (context, index) {
              final bankData = _cachedBanks[index];
              final bankName = bankData['name'];
              Bank? matchedBank = pakistaniBanks.firstWhere(
                    (b) => b.name.toLowerCase() == bankName.toLowerCase(),
                orElse: () => Bank(
                    name: bankName, iconPath: 'assets/default_bank.png'),
              );
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: Image.asset(
                    matchedBank.iconPath,
                    width: 40,
                    height: 40,
                    errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.account_balance, size: 40),
                  ),
                  title: Text(bankName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () {
                    selectedBank = {
                      'id': bankData['id'],
                      'name': bankName,
                      'balance': bankData['balance'],
                    };
                    Navigator.pop(context);
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(lp.isEnglish ? 'Cancel' : 'منسوخ کریں'),
          ),
        ],
      ),
    );
    return selectedBank;
  }

  Future<Uint8List?> _pickImage(BuildContext context) async {
    Uint8List? imageBytes;
    final lp = Provider.of<LanguageProvider>(context, listen: false);

    if (kIsWeb) {
      final result = await FilePicker.platform
          .pickFiles(type: FileType.image, allowMultiple: false);
      if (result != null && result.files.isNotEmpty) {
        imageBytes = result.files.first.bytes;
      }
    } else {
      final picker = ImagePicker();
      final ImageSource? source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(lp.isEnglish ? 'Select Source' : 'ذریعہ منتخب کریں'),
          actions: [
            TextButton(
              child: Text(lp.isEnglish ? 'Camera' : 'کیمرہ'),
              onPressed: () => Navigator.pop(context, ImageSource.camera),
            ),
            TextButton(
              child: Text(lp.isEnglish ? 'Gallery' : 'گیلری'),
              onPressed: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      );
      if (source == null) return null;
      final picked = await picker.pickImage(source: source);
      if (picked != null) {
        imageBytes = await File(picked.path).readAsBytes();
      }
    }
    return imageBytes;
  }

  Future<void> _pickPaymentDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _selectedPaymentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null && mounted) {
      setState(() {
        _selectedPaymentDate = DateTime(d.year, d.month, d.day,
            _selectedPaymentDate.hour, _selectedPaymentDate.minute);
      });
    }
  }

  Future<void> _pickPaymentTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedPaymentDate),
    );
    if (t != null && mounted) {
      setState(() {
        _selectedPaymentDate = DateTime(
            _selectedPaymentDate.year,
            _selectedPaymentDate.month,
            _selectedPaymentDate.day,
            t.hour,
            t.minute);
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SUBMIT
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _submit() async {
    if (_isSaving) return;
    final lp = Provider.of<LanguageProvider>(context, listen: false);
    if (_tab == 'cash') {
      await _submitCash(lp);
    } else {
      await _submitItems(lp);
    }
  }

  Future<void> _submitItems(LanguageProvider lp) async {
    final wire = _isWireTab;
    final rows = _rows;
    final filled = rows.where((r) => _rowName(r).isNotEmpty).toList();

    if (filled.isEmpty) {
      _validation(lp, 'Please add at least one item',
          'براہ کرم کم از کم ایک آئٹم شامل کریں');
      return;
    }
    for (final r in filled) {
      final qty = _parse(r.quantityController.text);
      final rate = _parse(r.rateController.text);
      if (qty <= 0 || rate <= 0) {
        _validation(
            lp,
            'Please enter quantity and rate for "${_rowName(r)}"',
            '"${_rowName(r)}" کی مقدار اور ریٹ درج کریں');
        return;
      }
    }

    setState(() => _isSaving = true);
    final provider = Provider.of<MazdoorProvider>(context, listen: false);
    final saved = <_JobRow>[];

    try {
      final previous = await provider.getMazdoorBalance(widget.mazdoorId);
      final receiptRows = <_ReceiptRow>[];
      final lines = <String>[];
      double total = 0;

      for (final r in filled) {
        final name = _rowName(r);
        final qty = _parse(r.quantityController.text);
        final rate = _parse(r.rateController.text);
        final wpu = r.weightPerUnit ?? 0.0;
        final totalWt = r.totalWeight ?? (wpu > 0 ? wpu * qty : qty);
        final amount = r.computedTotal;
        final desc = _ledgerDescription(r);

        if (!wire) {
          if (_isGiveWire) {
            await provider.giveBolts(
              mazdoorId: widget.mazdoorId,
              mazdoorName: widget.mazdoorName,
              boltItemName: name,
              quantity: qty,
              rate: rate,
              overrideValue: amount,
              description: desc,
            );
          } else {
            await provider.receiveBolts(
              mazdoorId: widget.mazdoorId,
              mazdoorName: widget.mazdoorName,
              boltItemName: name,
              boltItemId: _rowItemId(r),
              quantity: qty,
              rate: rate,
              overrideValue: amount,
              description: desc,
            );
          }
        } else {
          if (_isGiveWire) {
            await provider.giveWireItem(
              mazdoorId: widget.mazdoorId,
              mazdoorName: widget.mazdoorName,
              wireItemName: name,
              quantity: qty,
              rate: rate,
              weightPerUnit: wpu > 0 ? wpu : null,
              weightUnit: r.weightUnit,
              totalWeight: totalWt,
              overrideValue: amount,
              length: r.lengthController.text.trim(),
              bodyType: r.bodyTypeController.text.trim(),
              batchId: r.batchId,
              batchNumber: r.batchNumber,
              description: desc,
            );
          } else {
            await provider.receiveWire(
              mazdoorId: widget.mazdoorId,
              mazdoorName: widget.mazdoorName,
              wireItemName: name,
              wireItemId: _rowItemId(r),
              quantity: qty,
              rate: rate,
              weightPerUnit: wpu > 0 ? wpu : null,
              weightUnit: r.weightUnit,
              totalWeight: totalWt,
              overrideValue: amount,
              length: r.lengthController.text.trim(),
              bodyType: r.bodyTypeController.text.trim(),
              batchId: r.batchId,
              description: desc,
            );
          }
        }
        saved.add(r);
        total += amount;

        receiptRows.add(_ReceiptRow(
          item: r.itemNameController.text.trim(),
          length: r.lengthController.text.trim(),
          body: r.bodyTypeController.text.trim(),
          desc: r.descriptionController.text.trim(),
          batch: r.batchNumber ?? '',
          rate: rate,
          qty: qty,
          wpu: wpu,
          totalWt: wire ? totalWt : 0,
          amount: amount,
        ));
        lines.add(wire
            ? '$name: ${totalWt.toStringAsFixed(2)} kg × Rs ${rate.toStringAsFixed(2)} = Rs ${amount.toStringAsFixed(2)}'
            : '$name: ${qty.toStringAsFixed(2)} × Rs ${rate.toStringAsFixed(2)} = Rs ${amount.toStringAsFixed(2)}');
      }

      final current = await provider.getMazdoorBalance(widget.mazdoorId);

      final title = wire
          ? (_isGiveWire ? 'Wire Given' : 'Wire Received')
          : (_isGiveWire ? 'Bolts Given' : 'Bolts Received');

      final receipt = _Receipt(
        title: title,
        kind: wire ? 'wire' : 'bolt',
        isGive: _isGiveWire,
        rows: receiptRows,
        value: total,
        previousBalance: previous,
        currentBalance: current,
        when: DateTime.now(),
        summary: '$title:\n${lines.join('\n')}\n'
            'Total: Rs ${total.toStringAsFixed(2)}',
      );

      _snack(lp.isEnglish
          ? '$title — ${widget.mazdoorName}\'s balance updated.'
          : 'ریکارڈ ہو گیا — بیلنس اپ ڈیٹ ہو گیا۔');

      await _showReceiptDialog(receipt);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted && saved.isNotEmpty) {
        setState(() {
          for (final r in saved) {
            rows.remove(r);
          }
          if (rows.isEmpty) rows.add(_JobRow());
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final r in saved) {
            r.dispose();
          }
        });
      }
      _snack(saved.isEmpty
          ? 'Error: $e'
          : 'Error: $e  (${saved.length} row(s) were already saved and removed from the table)');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _submitCash(LanguageProvider lp) async {
    final amount = double.tryParse(_cashAmountController.text.trim());
    if (amount == null || amount <= 0) {
      _validation(lp, 'Please enter a valid amount', 'براہ کرم درست رقم درج کریں');
      return;
    }
    if (_selectedPaymentMethod == null) {
      _validation(lp, 'Please select a payment method',
          'براہ کرم ادائیگی کا طریقہ منتخب کریں');
      return;
    }
    if (_selectedPaymentMethod == 'Cheque') {
      if (_selectedBankId == null || _selectedBankName == null) {
        _validation(lp, 'Please select a bank for the cheque',
            'براہ کرم چیک کے لیے بینک منتخب کریں');
        return;
      }
      if (_chequeNumberController.text.isEmpty) {
        _validation(lp, 'Please enter cheque number', 'براہ کرم چیک نمبر درج کریں');
        return;
      }
      if (_selectedChequeDate == null) {
        _validation(
            lp, 'Please select cheque date', 'براہ کرم چیک کی تاریخ منتخب کریں');
        return;
      }
    }
    if (_selectedPaymentMethod == 'Bank' &&
        (_selectedBankId == null || _selectedBankName == null)) {
      _validation(lp, 'Please select a bank', 'براہ کرم بینک منتخب کریں');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final provider = Provider.of<MazdoorProvider>(context, listen: false);
      final filledProvider = Provider.of<FilledProvider>(context, listen: false);

      final previous = await provider.getMazdoorBalance(widget.mazdoorId);

      final cashDesc = _cashDescController.text.isEmpty
          ? '${_selectedPaymentMethod ?? "Cash"} payment'
          : _cashDescController.text;

      if (_isGiveWire) {
        await provider.giveCashPayment(
          mazdoorId: widget.mazdoorId,
          mazdoorName: widget.mazdoorName,
          amount: amount,
          description: cashDesc,
          date: _selectedPaymentDate,
        );
      } else {
        await provider.receiveCashPayment(
          mazdoorId: widget.mazdoorId,
          mazdoorName: widget.mazdoorName,
          amount: amount,
          description: cashDesc,
        );
      }

      final String flowType = _isGiveWire ? 'cash_out' : 'cash_in';
      final String flowLabel = _isGiveWire
          ? 'Payment to Mazdoor: ${widget.mazdoorName}'
          : 'Payment from Mazdoor: ${widget.mazdoorName}';
      final double bankSign = _isGiveWire ? -1.0 : 1.0;

      if (_selectedPaymentMethod == 'Cash') {
        await filledProvider.addCashBookEntry(
          description: _cashDescController.text.isEmpty
              ? flowLabel
              : _cashDescController.text,
          amount: amount,
          dateTime: _selectedPaymentDate,
          type: flowType,
        );
      } else if (_selectedPaymentMethod == 'Cheque') {
        await _db.child('banks/$_selectedBankId/cheques').push().set({
          'mazdoorId': widget.mazdoorId,
          'mazdoorName': widget.mazdoorName,
          'amount': amount,
          'chequeNumber': _chequeNumberController.text,
          'chequeDate': _selectedChequeDate!.toIso8601String(),
          'status': 'cleared',
          'clearedAt': _selectedPaymentDate.toIso8601String(),
          'createdAt': _selectedPaymentDate.toIso8601String(),
          'bankName': _selectedBankName,
          'direction': _isGiveWire ? 'out' : 'in',
          'source': 'mazdoor',
        });
      } else if (_selectedPaymentMethod == 'Bank' && _selectedBankId != null) {
        await _db.child('banks/$_selectedBankId/transactions').push().set({
          'amount': amount,
          'description': _cashDescController.text.isEmpty
              ? flowLabel
              : _cashDescController.text,
          'type': flowType,
          'timestamp': _selectedPaymentDate.millisecondsSinceEpoch,
          'mazdoorId': widget.mazdoorId,
          'bankName': _selectedBankName,
          'createdAt': _selectedPaymentDate.toIso8601String(),
          'source': 'mazdoor',
        });
        final bankBalanceRef = _db.child('banks/$_selectedBankId/balance');
        final currentBalance = (await bankBalanceRef.get()).value as num? ?? 0.0;
        await bankBalanceRef.set(currentBalance + (bankSign * amount));
      }

      final current = await provider.getMazdoorBalance(widget.mazdoorId);

      final showBank = _selectedBankName != null &&
          (_selectedPaymentMethod == 'Bank' ||
              _selectedPaymentMethod == 'Cheque');
      final title = _isGiveWire ? 'Payment Given' : 'Payment Received';

      final receipt = _Receipt(
        title: title,
        kind: 'cash',
        isGive: _isGiveWire,
        rows: const [],
        value: amount,
        previousBalance: previous,
        currentBalance: current,
        when: _selectedPaymentDate,
        method: _selectedPaymentMethod ?? 'Cash',
        bank: showBank ? _selectedBankName! : '',
        chequeNo: _selectedPaymentMethod == 'Cheque'
            ? _chequeNumberController.text
            : '',
        description: _cashDescController.text,
        summary: '$title: Rs ${amount.toStringAsFixed(2)} '
            '(${_selectedPaymentMethod ?? 'Cash'}${showBank ? ' - $_selectedBankName' : ''})'
            '${_selectedPaymentMethod == 'Cheque' ? '\nCheque #: ${_chequeNumberController.text}' : ''}',
      );

      _snack(lp.isEnglish
          ? '${_selectedPaymentMethod ?? "Cash"} payment of ${amount.toStringAsFixed(2)} PKR ${_isGiveWire ? 'given' : 'recorded'}.'
          : '${amount.toStringAsFixed(2)} روپے کی ادائیگی ریکارڈ ہو گئی۔');

      await _showReceiptDialog(receipt);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // UI (Header & Items Table)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildHeaderCard(LanguageProvider lp) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.orange[50]!, Colors.amber[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long, color: Colors.orange[700], size: 22),
                const SizedBox(width: 8),
                Text(
                  lp.isEnglish ? 'Job Details' : 'کام کی تفصیلات',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _biltiNumberController,
                    label: lp.isEnglish ? 'Bilti Number' : 'بلٹی نمبر',
                    icon: Icons.confirmation_number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildTextField(
                    controller: _transportCompanyController,
                    label: lp.isEnglish ? 'Transport Company' : 'ٹرانسپورٹ کمپنی',
                    icon: Icons.local_shipping,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _referenceController,
                          label: lp.isEnglish ? 'Reference Number' : 'ریفرنس نمبر',
                          icon: Icons.tag,
                          readOnly: _isAutoReference,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Switch(
                        value: _isAutoReference,
                        onChanged: (v) => setState(() => _isAutoReference = v),
                        activeColor: Colors.green,
                      ),
                      Text(
                        _isAutoReference
                            ? (lp.isEnglish ? 'Auto' : 'آٹو')
                            : (lp.isEnglish ? 'Manual' : 'مینوئل'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: _buildTextField(
                    controller: _dateController,
                    label: lp.isEnglish ? 'Date' : 'تاریخ',
                    icon: Icons.calendar_today,
                    readOnly: true,
                    onTap: _pickDate,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        prefixIcon: icon != null ? Icon(icon, color: Colors.grey[600], size: 20) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[400]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.teal, width: 2),
        ),
        filled: true,
        fillColor: readOnly ? Colors.grey[100] : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
      style: const TextStyle(fontSize: 13),
    );
  }

  Widget _buildItemsTable(LanguageProvider lp) {
    final wire = _isWireTab;
    final rows = _rows;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final r = rows[index];

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Size / Item Name
              Expanded(
                flex: 2,
                child: TextField(
                  controller: r.itemNameController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: lp.isEnglish ? 'Item' : 'آئٹم',
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search, size: 18, color: Colors.black87),
                      onPressed: () => _showItemSearchDialog(r, wire),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 4),

              // 2. Batch (Wire only)
              if (wire) ...[
                Expanded(
                  flex: 1,
                  child: InkWell(
                    onTap: () => _pickBatch(r),
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: r.batchId != null ? Colors.green : Colors.grey[300]!,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        color: r.batchId != null ? Colors.green[50] : Colors.grey[50],
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              r.batchNumber ?? (lp.isEnglish ? 'Select\nBatch' : 'بیچ'),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: r.batchId != null ? FontWeight.bold : FontWeight.normal,
                                color: r.batchId != null ? Colors.green[800] : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],

              // 3. Length
              Expanded(
                flex: 1,
                child: TextField(
                  controller: r.lengthController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: lp.isEnglish ? 'Length' : 'لمبائی',
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 4),

              // 4. Body Type
              Expanded(
                flex: 1,
                child: TextField(
                  controller: r.bodyTypeController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: lp.isEnglish ? 'Body T...' : 'باڈی',
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 4),

              // 5. Description
              Expanded(
                flex: 2,
                child: TextField(
                  controller: r.descriptionController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: lp.isEnglish ? 'Description' : 'تفصیل',
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 4),

              // 6. Qty
              Expanded(
                flex: 1,
                child: TextField(
                  controller: r.quantityController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: lp.isEnglish ? 'Qty' : 'مقدار',
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onChanged: (_) => _recalcRow(r),
                ),
              ),
              const SizedBox(width: 4),

              // 7. Weight/Unit
              Expanded(
                flex: 1,
                child: TextField(
                  controller: r.weightController,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: lp.isEnglish ? 'Wt/U...' : 'وزن',
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onChanged: (v) => _parseWeightInput(r, v),
                ),
              ),
              const SizedBox(width: 4),

              // 8. Total Wt (Read-only)
              Expanded(
                flex: 1,
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.grey[50],
                  ),
                  child: Text(
                    _displayTotalWeight(r).replaceAll(' kg', ''),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // 9. Calc (Dropdown)
              Expanded(
                flex: 1,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: r.calculationType,
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down, size: 16),
                      style: const TextStyle(fontSize: 11, color: Colors.black87),
                      items: const [
                        DropdownMenuItem(
                          value: 'quantity',
                          child: Text('Qty×Rate', textAlign: TextAlign.center),
                        ),
                        DropdownMenuItem(
                          value: 'weight',
                          child: Text('Wt×Rate', textAlign: TextAlign.center),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => r.calculationType = v);
                        _recalcRow(r);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // 10. Rate
              Expanded(
                flex: 1,
                child: TextField(
                  controller: r.rateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: lp.isEnglish ? 'Rate' : 'ریٹ',
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onChanged: (_) => _recalcRow(r),
                ),
              ),
              const SizedBox(width: 4),

              // 11. Total (Read-only)
              Expanded(
                flex: 1,
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    r.computedTotal.toStringAsFixed(2),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // 12. Delete Button
              SizedBox(
                width: 40,
                height: 40,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  onPressed: rows.length > 1 ? () => _removeRow(index) : null,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabSelector(LanguageProvider lp) {
    Widget seg(String key, String label) {
      final selected = _tab == key;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = key),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? _orange : Colors.white,
              borderRadius: key == 'bolt'
                  ? const BorderRadius.horizontal(left: Radius.circular(7))
                  : key == 'cash'
                  ? const BorderRadius.horizontal(right: Radius.circular(7))
                  : null,
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? Colors.white : Colors.grey[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _orange),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Row(children: [
          seg('bolt', lp.isEnglish ? 'Bolts' : 'بولٹس'),
          seg('wire', lp.isEnglish ? 'Wire' : 'وائر'),
          seg('cash', lp.isEnglish ? 'Cash' : 'نقد'),
        ]),
      ),
    );
  }

  Widget _buildItemsCard(LanguageProvider lp) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, color: Colors.green, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      lp.isEnglish ? 'Items' : 'آئٹمز',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(lp.isEnglish ? 'Add Item' : 'آئٹم شامل کریں'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Header Row
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Expanded(flex: 2, child: Text(lp.isEnglish ? 'Size' : 'سائز', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13))),
                  if (_isWireTab) Expanded(flex: 1, child: Text(lp.isEnglish ? 'Batch' : 'بیچ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(lp.isEnglish ? 'Length' : 'لمبائی', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(lp.isEnglish ? 'Body Type' : 'باڈی', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13), textAlign: TextAlign.center)),
                  Expanded(flex: 2, child: Text(lp.isEnglish ? 'Description' : 'تفصیل', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13))),
                  Expanded(flex: 1, child: Text(lp.isEnglish ? 'Qty' : 'مقدار', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(lp.isEnglish ? 'Weight/Unit' : 'وزن', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(lp.isEnglish ? 'Total Wt' : 'کل وزن', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(lp.isEnglish ? 'Calc' : 'حساب', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(lp.isEnglish ? 'Rate' : 'ریٹ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13), textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text(lp.isEnglish ? 'Total' : 'کل', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13), textAlign: TextAlign.center)),
                  const SizedBox(width: 40), // for delete button
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Data Rows
            _buildItemsTable(lp),
          ],
        ),
      ),
    );
  }

  Widget _totalBox(LanguageProvider lp) {
    final total = _tabTotal();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: _orange),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Column(children: [
        if (_isWireTab)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(lp.isEnglish ? 'Total Weight:' : 'کل وزن:',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: _orangeDark)),
              Text('${_tabTotalWeight().toStringAsFixed(2)} kg',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: _orangeDark)),
            ],
          ),
        if (_isWireTab) const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(lp.isEnglish ? 'Grand Total:' : 'کل رقم:',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: _orangeDark)),
            Text('${total.toStringAsFixed(2)} PKR',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _orangeDark,
                    fontSize: 16)),
          ],
        ),
      ]),
    );
  }

  Widget _buildCashCard(LanguageProvider lp) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isGiveWire
                  ? (lp.isEnglish ? 'Cash Given' : 'دی گئی رقم')
                  : (lp.isEnglish ? 'Cash Received' : 'وصول شدہ رقم'),
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _orangeDark,
                  fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cashAmountController,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: lp.isEnglish ? 'Amount (PKR)' : 'رقم',
                border: const OutlineInputBorder(),
                prefixText: 'PKR ',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedPaymentMethod,
              items: [
                DropdownMenuItem(
                    value: 'Cash',
                    child: Text(lp.isEnglish ? 'Cash' : 'نقدی')),
                DropdownMenuItem(
                    value: 'Online',
                    child: Text(lp.isEnglish ? 'Online' : 'آن لائن')),
                DropdownMenuItem(
                    value: 'Cheque',
                    child: Text(lp.isEnglish ? 'Cheque' : 'چیک')),
                DropdownMenuItem(
                    value: 'Bank',
                    child: Text(lp.isEnglish ? 'Bank' : 'بینک')),
                DropdownMenuItem(
                    value: 'Slip',
                    child: Text(lp.isEnglish ? 'Slip' : 'پرچی')),
              ],
              onChanged: (v) => setState(() => _selectedPaymentMethod = v),
              decoration: InputDecoration(
                labelText: lp.isEnglish
                    ? 'Select Payment Method'
                    : 'ادائیگی کا طریقہ منتخب کریں',
                border: const OutlineInputBorder(),
              ),
            ),
            if (_selectedPaymentMethod == 'Cheque') ...[
              const SizedBox(height: 16),
              TextField(
                controller: _chequeNumberController,
                decoration: InputDecoration(
                  labelText: lp.isEnglish ? 'Cheque Number' : 'چیک نمبر',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                title: Text(_selectedChequeDate == null
                    ? (lp.isEnglish
                    ? 'Select Cheque Date'
                    : 'چیک کی تاریخ منتخب کریں')
                    : DateFormat('yyyy-MM-dd').format(_selectedChequeDate!)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() => _selectedChequeDate = picked);
                  }
                },
              ),
            ],
            if (_selectedPaymentMethod == 'Cheque' ||
                _selectedPaymentMethod == 'Bank') ...[
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  title: Text(_selectedBankName ??
                      (lp.isEnglish ? 'Select Bank' : 'بینک منتخب کریں')),
                  trailing: const Icon(Icons.arrow_drop_down),
                  onTap: () async {
                    final b = await _selectBank(context);
                    if (b != null) {
                      setState(() {
                        _selectedBankId = b['id'];
                        _selectedBankName = b['name'];
                      });
                    }
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.calendar_today,
                      size: 18, color: Colors.white),
                  label: Text(
                      lp.isEnglish ? 'Select Date' : 'تاریخ منتخب کریں',
                      style: const TextStyle(color: Colors.white)),
                  onPressed: _pickPaymentDate,
                  style: ElevatedButton.styleFrom(backgroundColor: _orange),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.access_time,
                      size: 18, color: Colors.white),
                  label: Text(lp.isEnglish ? 'Select Time' : 'وقت منتخب کریں',
                      style: const TextStyle(color: Colors.white)),
                  onPressed: _pickPaymentTime,
                  style: ElevatedButton.styleFrom(backgroundColor: _orange),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${lp.isEnglish ? 'Selected' : 'منتخب شدہ'}: ${DateFormat('yyyy-MM-dd HH:mm').format(_selectedPaymentDate)}',
                style: const TextStyle(fontSize: 15, color: _orangeDark),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cashDescController,
              decoration: InputDecoration(
                labelText:
                lp.isEnglish ? 'Description (optional)' : 'تفصیل (اختیاری)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                final image = await _pickImage(context);
                if (image != null) setState(() => _paymentImage = image);
              },
              style: ElevatedButton.styleFrom(backgroundColor: _orange),
              child: Text(lp.isEnglish ? 'Upload Receipt' : 'رسید اپ لوڈ کریں',
                  style: const TextStyle(color: Colors.white)),
            ),
            if (_paymentImage != null)
              Container(
                margin: const EdgeInsets.only(top: 16),
                height: 100,
                width: 100,
                child: Image.memory(_paymentImage!),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lp = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isGiveWire
              ? (lp.isEnglish
              ? 'Give — ${widget.mazdoorName}'
              : 'دیں — ${widget.mazdoorName}')
              : (lp.isEnglish
              ? 'Receive — ${widget.mazdoorName}'
              : 'وصول کریں — ${widget.mazdoorName}'),
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
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
          ),
        ),
        child: _isLoadingItems
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 1. Header Card (Invoice Details) ──
              _buildHeaderCard(lp),
              const SizedBox(height: 16),

              // ── 2. Tab Selector ──
              _buildTabSelector(lp),
              const SizedBox(height: 16),

              // ── 3. Items or Cash ──
              if (_tab == 'cash')
                _buildCashCard(lp)
              else ...[
                _buildItemsCard(lp),
                const SizedBox(height: 16),
                _totalBox(lp),
              ],
              const SizedBox(height: 16),

              // ── 4. Submit Button ──
              Center(
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _orange,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 40),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                      : Text(
                    _isGiveWire
                        ? (lp.isEnglish ? 'Give' : 'دیں')
                        : (lp.isEnglish
                        ? 'Record'
                        : 'ریکارڈ کریں'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final r in _boltRows) {
      r.dispose();
    }
    for (final r in _wireRows) {
      r.dispose();
    }
    _biltiNumberController.dispose();
    _transportCompanyController.dispose();
    _dateController.dispose();
    _referenceController.dispose();
    _cashAmountController.dispose();
    _cashDescController.dispose();
    _chequeNumberController.dispose();
    super.dispose();
  }
}