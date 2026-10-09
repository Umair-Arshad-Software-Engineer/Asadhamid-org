import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../Filled/Filledpage.dart';
import '../Models/itemModel.dart';
import '../Models/mazdoorModel.dart';
import '../Provider/Mazdoorprovider ·.dart';
import '../Provider/filled provider.dart';
import '../Provider/lanprovider.dart';
import '../bankmanagement/banknames.dart';

enum MazdoorJobMode { giveWire, receiveReturn }

/// One row for a wire line in "give wire" mode.
class _WireRow {
  final itemNameController = TextEditingController();
  final lengthController = TextEditingController();
  final bodyTypeController = TextEditingController();
  final qtyController = TextEditingController();
  final weightController = TextEditingController();
  String? batchId;
  String? batchNumber;
  Item? selectedItem;
}

class MazdoorJobPage extends StatefulWidget {
  final String mazdoorId;
  final String mazdoorName;
  final MazdoorJobMode mode;

  const MazdoorJobPage({
    Key? key,
    required this.mazdoorId,
    required this.mazdoorName,
    required this.mode,
  }) : super(key: key);

  @override
  _MazdoorJobPageState createState() => _MazdoorJobPageState();
}

class _MazdoorJobPageState extends State<MazdoorJobPage> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  // ── Give-wire state ──
  final List<_WireRow> _wireRows = [_WireRow()];
  final TextEditingController _valueController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  List<Item> _items = [];
  bool _isLoadingItems = false;
  bool _isSaving = false;

  // ── Receive-return state ──
  String _returnType = 'bolt'; // 'bolt' | 'wire' | 'cash'
  final TextEditingController _boltItemController = TextEditingController();
  Item? _selectedBoltItem;
  final TextEditingController _boltQtyController = TextEditingController();
  final TextEditingController _boltRateController = TextEditingController();
  final TextEditingController _cashAmountController = TextEditingController();
  final TextEditingController _returnDescController = TextEditingController();

  // ── Wire-return state ──
  final TextEditingController _wireItemController = TextEditingController();
  Item? _selectedWireItem;
  final TextEditingController _wireQtyController = TextEditingController();
  final TextEditingController _wireWeightController = TextEditingController();
  final TextEditingController _wireRateController = TextEditingController();
  String? _wireBatchId;
  String? _wireBatchNumber;

  // ── NEW: Cash payment method state (mirrors CustomerList) ──
  String? _selectedPaymentMethod; // 'Cash' | 'Online' | 'Cheque' | 'Bank' | 'Slip'
  DateTime _selectedPaymentDate = DateTime.now();
  String? _selectedBankId;
  String? _selectedBankName;
  final TextEditingController _chequeNumberController = TextEditingController();
  DateTime? _selectedChequeDate;
  Uint8List? _paymentImage;
  List<Map<String, dynamic>> _cachedBanks = [];

  bool get _isGiveWire => widget.mode == MazdoorJobMode.giveWire;

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  Future<void> _fetchItems() async {
    setState(() => _isLoadingItems = true);
    try {
      final snapshot = await _db.child('items').get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          _items = data.entries
              .map((e) => Item.fromMap(
              e.value as Map<dynamic, dynamic>, e.key.toString()))
              .toList();
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingItems = false);
    }
  }

  void _addWireRow() {
    setState(() => _wireRows.add(_WireRow()));
  }

  void _removeWireRow(int index) {
    setState(() => _wireRows.removeAt(index));
  }

  void _applyItemToWireRow(_WireRow row, Item item) {
    setState(() {
      row.selectedItem = item;
      row.itemNameController.text = item.itemName;

      if (item.lengthBodyCombinations != null &&
          item.lengthBodyCombinations!.isNotEmpty) {
        final combo = item.lengthBodyCombinations!.first;
        if (row.lengthController.text.isEmpty) {
          row.lengthController.text = combo.length;
        }
        if (row.bodyTypeController.text.isEmpty) {
          row.bodyTypeController.text = combo.bodyType;
        }
        if (combo.weightPerUnit != null && row.weightController.text.isEmpty) {
          row.weightController.text = combo.weightPerUnit!.toStringAsFixed(2);
        }
      }
    });
  }

  double _computeTotalWireWeight(_WireRow row) {
    final qty = double.tryParse(row.qtyController.text) ?? 0.0;
    final weightPerUnit = double.tryParse(row.weightController.text) ?? 0.0;
    if (weightPerUnit > 0 && qty > 0) return weightPerUnit * qty;
    return qty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // BANK / IMAGE HELPERS (mirrors CustomerList)
  // ═══════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> _selectBank(BuildContext context) async {
    if (_cachedBanks.isEmpty) {
      final bankSnapshot =
      await FirebaseDatabase.instance.ref('banks').once();
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

    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    Map<String, dynamic>? selectedBank;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(languageProvider.isEnglish
            ? 'Select Bank'
            : 'بینک منتخب کریں'),
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
                orElse: () =>
                    Bank(name: bankName, iconPath: 'assets/default_bank.png'),
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
                  title: Text(
                    bankName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
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
            child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ کریں'),
          ),
        ],
      ),
    );

    return selectedBank;
  }

  Future<Uint8List?> _pickImage(BuildContext context) async {
    Uint8List? imageBytes;
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);

    if (kIsWeb) {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        imageBytes = result.files.first.bytes;
      }
    } else {
      final ImagePicker _picker = ImagePicker();
      final ImageSource? source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(languageProvider.isEnglish
              ? 'Select Source'
              : 'ذریعہ منتخب کریں'),
          actions: [
            TextButton(
              child: Text(languageProvider.isEnglish ? 'Camera' : 'کیمرہ'),
              onPressed: () => Navigator.pop(context, ImageSource.camera),
            ),
            TextButton(
              child: Text(languageProvider.isEnglish ? 'Gallery' : 'گیلری'),
              onPressed: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      );
      if (source == null) return null;
      XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        final file = File(pickedFile.path);
        imageBytes = await file.readAsBytes();
      }
    }
    return imageBytes;
  }

  // ═══════════════════════════════════════════════════════════════════
  // SUBMIT: RECEIVE (bolt/wire/cash) — Cash now goes through payment methods
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _submitReceive() async {
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);

    setState(() => _isSaving = true);
    try {
      final provider = Provider.of<MazdoorProvider>(context, listen: false);

      if (_returnType == 'bolt') {
        // ── Bolts (unchanged) ──
        final qty = double.tryParse(_boltQtyController.text);
        final rate = double.tryParse(_boltRateController.text);
        if (_boltItemController.text.isEmpty ||
            qty == null ||
            qty <= 0 ||
            rate == null ||
            rate <= 0) {
          _showValidationSnack(languageProvider,
              'Please enter item, quantity and rate',
              'براہ کرم آئٹم، مقدار اور ریٹ درج کریں');
          setState(() => _isSaving = false);
          return;
        }

        if (_isGiveWire) {
          await provider.giveBolts(
            mazdoorId: widget.mazdoorId,
            mazdoorName: widget.mazdoorName,
            boltItemName: _boltItemController.text,
            quantity: qty,
            rate: rate,
            description: _returnDescController.text.isEmpty
                ? null
                : _returnDescController.text,
          );
        } else {
          await provider.receiveBolts(
            mazdoorId: widget.mazdoorId,
            mazdoorName: widget.mazdoorName,
            boltItemName: _boltItemController.text,
            boltItemId: (_selectedBoltItem != null &&
                !_selectedBoltItem!.id.startsWith('manual_'))
                ? _selectedBoltItem!.id
                : null,
            quantity: qty,
            rate: rate,
            description: _returnDescController.text.isEmpty
                ? null
                : _returnDescController.text,
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(languageProvider.isEnglish
              ? 'Bolts ${_isGiveWire ? 'given' : 'recorded'} — ${widget.mazdoorName}\'s balance updated.'
              : 'بولٹس ریکارڈ ہو گئیں۔'),
          backgroundColor: Colors.green,
        ));
      } else if (_returnType == 'wire') {
        // ── Wire return (unchanged) ──
        final qty = double.tryParse(_wireQtyController.text);
        final rate = double.tryParse(_wireRateController.text);
        final weightPerUnit = double.tryParse(_wireWeightController.text);

        if (_wireItemController.text.isEmpty ||
            qty == null ||
            qty <= 0 ||
            rate == null ||
            rate <= 0) {
          _showValidationSnack(languageProvider,
              'Please enter wire item, quantity and rate',
              'براہ کرم وائر آئٹم، مقدار اور ریٹ درج کریں');
          setState(() => _isSaving = false);
          return;
        }

        final double totalWeight = (weightPerUnit != null && weightPerUnit > 0)
            ? weightPerUnit * qty
            : qty;

        if (_isGiveWire) {
          await provider.giveWireItem(
            mazdoorId: widget.mazdoorId,
            mazdoorName: widget.mazdoorName,
            wireItemName: _wireItemController.text,
            quantity: qty,
            rate: rate,
            weightPerUnit: weightPerUnit,
            totalWeight: totalWeight,
            batchId: _wireBatchId,
            batchNumber: _wireBatchNumber,
            description: _returnDescController.text.isEmpty
                ? null
                : _returnDescController.text,
          );
        } else {
          await provider.receiveWire(
            mazdoorId: widget.mazdoorId,
            mazdoorName: widget.mazdoorName,
            wireItemName: _wireItemController.text,
            wireItemId: (_selectedWireItem != null &&
                !_selectedWireItem!.id.startsWith('manual_'))
                ? _selectedWireItem!.id
                : null,
            quantity: qty,
            rate: rate,
            weightPerUnit: weightPerUnit,
            totalWeight: totalWeight,
            batchId: _wireBatchId,
            description: _returnDescController.text.isEmpty
                ? null
                : _returnDescController.text,
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(languageProvider.isEnglish
              ? 'Wire ${_isGiveWire ? 'given' : 'return recorded'} — ${widget.mazdoorName}\'s balance updated.'
              : 'وائر واپسی ریکارڈ ہو گئی۔'),
          backgroundColor: Colors.green,
        ));
      } else {
        // ── CASH ── now with full payment-method flow
        final amount = double.tryParse(_cashAmountController.text);
        if (amount == null || amount <= 0) {
          _showValidationSnack(languageProvider, 'Please enter a valid amount',
              'براہ کرم درست رقم درج کریں');
          setState(() => _isSaving = false);
          return;
        }

        if (_selectedPaymentMethod == null) {
          _showValidationSnack(
              languageProvider,
              'Please select a payment method',
              'براہ کرم ادائیگی کا طریقہ منتخب کریں');
          setState(() => _isSaving = false);
          return;
        }

        // ── Cheque validation ──
        if (_selectedPaymentMethod == 'Cheque') {
          if (_selectedBankId == null || _selectedBankName == null) {
            _showValidationSnack(
                languageProvider,
                'Please select a bank for the cheque',
                'براہ کرم چیک کے لیے بینک منتخب کریں');
            setState(() => _isSaving = false);
            return;
          }
          if (_chequeNumberController.text.isEmpty) {
            _showValidationSnack(languageProvider, 'Please enter cheque number',
                'براہ کرم چیک نمبر درج کریں');
            setState(() => _isSaving = false);
            return;
          }
          if (_selectedChequeDate == null) {
            _showValidationSnack(languageProvider, 'Please select cheque date',
                'براہ کرم چیک کی تاریخ منتخب کریں');
            setState(() => _isSaving = false);
            return;
          }
        }

        // ── Bank validation ──
        if (_selectedPaymentMethod == 'Bank' &&
            (_selectedBankId == null || _selectedBankName == null)) {
          _showValidationSnack(languageProvider, 'Please select a bank',
              'براہ کرم بینک منتخب کریں');
          setState(() => _isSaving = false);
          return;
        }

        // 1. Ledger credit on the Mazdoor (reduces their balance)
        final cashDesc = _returnDescController.text.isEmpty
            ? '${_selectedPaymentMethod ?? "Cash"} payment'
            : _returnDescController.text;
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

        // 2. Side effects per method
        final filledProvider =
        Provider.of<FilledProvider>(context, listen: false);
        final filledNumber = DateTime.now().millisecondsSinceEpoch.toString();

        if (_selectedPaymentMethod == 'Cash') {
          await filledProvider.addCashBookEntry(
            description: _returnDescController.text.isEmpty
                ? flowLabel
                : _returnDescController.text,
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
        } else if (_selectedPaymentMethod == 'Bank' &&
            _selectedBankId != null) {
          await _db
              .child('banks/$_selectedBankId/transactions')
              .push()
              .set({
            'amount': amount,
            'description': _returnDescController.text.isEmpty
                ? flowLabel
                : _returnDescController.text,
            'type': flowType,
            'timestamp': _selectedPaymentDate.millisecondsSinceEpoch,
            'mazdoorId': widget.mazdoorId,
            'bankName': _selectedBankName,
            'createdAt': _selectedPaymentDate.toIso8601String(),
            'source': 'mazdoor',
          });

          final bankBalanceRef =
          _db.child('banks/$_selectedBankId/balance');
          final currentBalance =
              (await bankBalanceRef.get()).value as num? ?? 0.0;
          await bankBalanceRef.set(currentBalance + (bankSign * amount));
        }
        // 'Online' and 'Slip' → no additional side effects, matching
        // the customer-side behaviour.

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(languageProvider.isEnglish
              ? '${_selectedPaymentMethod ?? "Cash"} payment of ${amount.toStringAsFixed(2)} PKR ${_isGiveWire ? 'given' : 'recorded'}.'
              : '${amount.toStringAsFixed(2)} روپے کی ادائیگی ریکارڈ ہو گئی۔'),
          backgroundColor: Colors.green,
        ));
      }

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showValidationSnack(
      LanguageProvider lp, String en, String ur) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(lp.isEnglish ? en : ur)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isGiveWire
              ? (languageProvider.isEnglish
              ? 'Give — ${widget.mazdoorName}'
              : 'دیں — ${widget.mazdoorName}')
              : (languageProvider.isEnglish
              ? 'Receive — ${widget.mazdoorName}'
              : 'وصول کریں — ${widget.mazdoorName}'),
          style: const TextStyle(color: Colors.white),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF26A69A), Color(0xFF80CBC4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: _isLoadingItems
          ? const Center(child: CircularProgressIndicator())
          : _buildReceiveForm(languageProvider),
    );
  }

  Future<void> _pickBatchForWireReturn() async {
    final itemName = _wireItemController.text;
    if (itemName.isEmpty) return;

    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    final batches = await _fetchBatchesForItem(itemName);

    if (batches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(languageProvider.isEnglish
            ? 'No batches available for $itemName'
            : '$itemName کے لیے کوئی بیچ دستیاب نہیں'),
      ));
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(languageProvider.isEnglish
            ? 'Select Batch for $itemName'
            : '$itemName کے لیے بیچ منتخب کریں'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: batches.length,
            itemBuilder: (context, i) {
              final batch = batches[i];
              final qty = (batch['quantity'] as num?)?.toDouble() ?? 0.0;
              final purchasePrice =
                  (batch['purchasePrice'] as num?)?.toDouble() ?? 0.0;
              final batchNumber =
                  batch['batchNumber']?.toString() ?? 'Batch ${i + 1}';

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(batchNumber,
                      style:
                      const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    'Available: ${qty.toStringAsFixed(2)} kg  |  ${purchasePrice.toStringAsFixed(2)} PKR/kg',
                  ),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green),
                    onPressed: () {
                      setState(() {
                        _wireBatchId = batch['id'];
                        _wireBatchNumber = batchNumber;
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
            onPressed: () => Navigator.pop(context),
            child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ'),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchBatchesForItem(
      String itemName) async {
    List<Map<String, dynamic>> batches = [];
    try {
      final snapshot = await _db.child('batches').get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          final batch = Map<String, dynamic>.from(value);
          double quantity = (batch['quantity'] as num?)?.toDouble() ?? 0.0;
          bool isActive = batch['isActive'] == true;
          if (batch['itemName'] == itemName && quantity > 0 && isActive) {
            double purchasePrice =
                (batch['purchasePrice'] as num?)?.toDouble() ??
                    (batch['costPrice'] as num?)?.toDouble() ??
                    0.0;
            batches.add({
              'id': key,
              'itemName': batch['itemName'] ?? '',
              'batchNumber': batch['batchNumber'] ?? 'N/A',
              'quantity': quantity,
              'purchasePrice': purchasePrice,
            });
          }
        });
      }
    } catch (e) {
      print('Error fetching batches: $e');
    }
    return batches;
  }

  // ═══════════════════════════════════════════════════════════════════
  // RECEIVE FORM (3 tabs: Bolts | Wire | Cash)
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildReceiveForm(LanguageProvider lp) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Three-tab selector ─────────────────────────────────
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _returnType = 'bolt'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _returnType == 'bolt'
                            ? Colors.teal[400]
                            : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(7)),
                      ),
                      child: Center(
                        child: Text(
                          lp.isEnglish ? 'Bolts' : 'بولٹس',
                          style: TextStyle(
                            fontSize: 12,
                            color: _returnType == 'bolt'
                                ? Colors.white
                                : Colors.grey[600],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _returnType = 'wire'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _returnType == 'wire'
                            ? Colors.teal[400]
                            : Colors.transparent,
                      ),
                      child: Center(
                        child: Text(
                          lp.isEnglish ? 'Wire' : 'وائر',
                          style: TextStyle(
                            fontSize: 12,
                            color: _returnType == 'wire'
                                ? Colors.white
                                : Colors.grey[600],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _returnType = 'cash'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _returnType == 'cash'
                            ? Colors.teal[400]
                            : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(7)),
                      ),
                      child: Center(
                        child: Text(
                          lp.isEnglish ? 'Cash' : 'نقد',
                          style: TextStyle(
                            fontSize: 12,
                            color: _returnType == 'cash'
                                ? Colors.white
                                : Colors.grey[600],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ══════════════════════════════════════════════════════
          // BOLTS TAB
          // ══════════════════════════════════════════════════════
          if (_returnType == 'bolt') ...[
            CustomAutocomplete(
              items: _items,
              controller: _boltItemController,
              selectedCustomerId: null,
              allowManualEntry: true,
              onSelected: (Item selectedItem) {
                setState(() {
                  _selectedBoltItem = selectedItem;
                  _boltItemController.text = selectedItem.itemName;
                  if (selectedItem.avgSalePricePerKg > 0 &&
                      _boltRateController.text.isEmpty) {
                    _boltRateController.text =
                        selectedItem.avgSalePricePerKg.toStringAsFixed(2);
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _boltQtyController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: lp.isEnglish ? 'Quantity' : 'مقدار',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _boltRateController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: lp.isEnglish ? 'Rate (PKR)' : 'ریٹ',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final qty = double.tryParse(_boltQtyController.text) ?? 0.0;
              final rate = double.tryParse(_boltRateController.text) ?? 0.0;
              final value = qty * rate;
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${lp.isEnglish ? 'Bolt value' : 'بولٹ ویلیو'}: ${value.toStringAsFixed(2)} PKR',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            }),
          ]

          // ══════════════════════════════════════════════════════
          // WIRE TAB
          // ══════════════════════════════════════════════════════
          else if (_returnType == 'wire') ...[
            CustomAutocomplete(
              items: _items,
              controller: _wireItemController,
              selectedCustomerId: null,
              allowManualEntry: true,
              onSelected: (Item selectedItem) {
                setState(() {
                  _selectedWireItem = selectedItem;
                  _wireItemController.text = selectedItem.itemName;
                  double wirePrice = 0;
                  if (selectedItem.lengthBodyCombinations != null &&
                      selectedItem.lengthBodyCombinations!.isNotEmpty) {
                    final combo =
                        selectedItem.lengthBodyCombinations!.first;
                    if (combo.weightPerUnit != null &&
                        _wireWeightController.text.isEmpty) {
                      _wireWeightController.text =
                          combo.weightPerUnit!.toStringAsFixed(2);
                    }
                    wirePrice = combo.salePricePerKg ?? 0;
                    if (wirePrice <= 0) {
                      for (final c in selectedItem.lengthBodyCombinations!) {
                        if ((c.salePricePerKg ?? 0) > 0) {
                          wirePrice = c.salePricePerKg!;
                          break;
                        }
                      }
                    }
                  }
                  if (wirePrice <= 0) {
                    wirePrice = selectedItem.avgSalePricePerKg;
                  }
                  if (wirePrice > 0) {
                    _wireRateController.text = wirePrice.toStringAsFixed(2);
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _wireQtyController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: lp.isEnglish ? 'Quantity' : 'مقدار',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _wireWeightController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText:
                      lp.isEnglish ? 'Weight/Unit (kg)' : 'وزن/یونٹ',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _wireRateController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: lp.isEnglish ? 'Rate (PKR/kg)' : 'ریٹ',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.inventory_2,
                      size: 18, color: Colors.blue),
                  onPressed: () async {
                    if (_wireItemController.text.isEmpty) return;
                    await _pickBatchForWireReturn();
                  },
                  tooltip: lp.isEnglish ? 'Select Batch' : 'بیچ منتخب کریں',
                ),
                Expanded(
                  child: Text(
                    _wireBatchNumber != null
                        ? '${lp.isEnglish ? 'Batch' : 'بیچ'}: $_wireBatchNumber'
                        : (lp.isEnglish
                        ? 'No batch selected (optional)'
                        : 'کوئی بیچ منتخب نہیں (اختیاری)'),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final qty = double.tryParse(_wireQtyController.text) ?? 0.0;
              final rate = double.tryParse(_wireRateController.text) ?? 0.0;
              final wtPerUnit =
                  double.tryParse(_wireWeightController.text) ?? 0.0;
              final totalWt = wtPerUnit > 0 ? wtPerUnit * qty : qty;
              final value = totalWt * rate;

              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${lp.isEnglish ? 'Total Weight' : 'کل وزن'}: '
                          '${totalWt.toStringAsFixed(2)} kg',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${lp.isEnglish ? 'Wire value' : 'وائر ویلیو'}: '
                          '${value.toStringAsFixed(2)} PKR',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }),
          ]

          // ══════════════════════════════════════════════════════
          // CASH TAB — now with full payment-method selection
          // ══════════════════════════════════════════════════════
          else ...[
              // Amount
              TextField(
                controller: _cashAmountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _isGiveWire ? (lp.isEnglish ? 'Cash Given (PKR)' : 'دی گئی رقم') : (lp.isEnglish ? 'Cash Amount (PKR)' : 'نقد رقم'),
                  border: const OutlineInputBorder(),
                  prefixText: 'PKR ',
                ),
              ),
              const SizedBox(height: 16),

              // Payment method
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
                onChanged: (value) =>
                    setState(() => _selectedPaymentMethod = value),
                decoration: InputDecoration(
                  labelText: lp.isEnglish
                      ? 'Select Payment Method'
                      : 'ادائیگی کا طریقہ منتخب کریں',
                  border: const OutlineInputBorder(),
                ),
              ),

              // Cheque-specific fields
              if (_selectedPaymentMethod == 'Cheque') ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _chequeNumberController,
                  decoration: InputDecoration(
                    labelText:
                    lp.isEnglish ? 'Cheque Number' : 'چیک نمبر',
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
                    final pickedDate = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (pickedDate != null) {
                      setState(() => _selectedChequeDate = pickedDate);
                    }
                  },
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    title: Text(_selectedBankName ??
                        (lp.isEnglish ? 'Select Bank' : 'بینک منتخب کریں')),
                    trailing: const Icon(Icons.arrow_drop_down),
                    onTap: () async {
                      final selectedBank = await _selectBank(context);
                      if (selectedBank != null) {
                        setState(() {
                          _selectedBankId = selectedBank['id'];
                          _selectedBankName = selectedBank['name'];
                        });
                      }
                    },
                  ),
                ),
              ],

              // Bank-specific fields
              if (_selectedPaymentMethod == 'Bank') ...[
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    title: Text(_selectedBankName ??
                        (lp.isEnglish ? 'Select Bank' : 'بینک منتخب کریں')),
                    trailing: const Icon(Icons.arrow_drop_down),
                    onTap: () async {
                      final selectedBank = await _selectBank(context);
                      if (selectedBank != null) {
                        setState(() {
                          _selectedBankId = selectedBank['id'];
                          _selectedBankName = selectedBank['name'];
                        });
                      }
                    },
                  ),
                ),
              ],

              // Optional receipt image (parity with customer-side)
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  final image = await _pickImage(context);
                  if (image != null) setState(() => _paymentImage = image);
                },
                child: Text(lp.isEnglish
                    ? 'Upload Receipt'
                    : 'رسید اپ لوڈ کریں'),
              ),
              if (_paymentImage != null)
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  height: 100,
                  width: 100,
                  child: Image.memory(_paymentImage!),
                ),
            ],

          const SizedBox(height: 12),
          TextField(
            controller: _returnDescController,
            decoration: InputDecoration(
              labelText: lp.isEnglish
                  ? 'Description (optional)'
                  : 'تفصیل (اختیاری)',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _submitReceive,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal[400],
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSaving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                _isGiveWire ? (lp.isEnglish ? 'Give' : 'دیں') : (lp.isEnglish ? 'Record' : 'ریکارڈ کریں'),
                style: const TextStyle(
                    color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final row in _wireRows) {
      row.itemNameController.dispose();
      row.lengthController.dispose();
      row.bodyTypeController.dispose();
      row.qtyController.dispose();
      row.weightController.dispose();
    }
    _valueController.dispose();
    _notesController.dispose();
    _boltItemController.dispose();
    _boltQtyController.dispose();
    _boltRateController.dispose();
    _cashAmountController.dispose();
    _returnDescController.dispose();
    _wireItemController.dispose();
    _wireQtyController.dispose();
    _wireWeightController.dispose();
    _wireRateController.dispose();
    _chequeNumberController.dispose();
    super.dispose();
  }
}