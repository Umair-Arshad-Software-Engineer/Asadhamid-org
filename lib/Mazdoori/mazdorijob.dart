import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Filled/Filledpage.dart';
import '../Models/itemModel.dart';
import '../Models/mazdoorModel.dart';
import '../Provider/Mazdoorprovider ·.dart';
import '../Provider/lanprovider.dart';

enum MazdoorJobMode { giveWire, receiveReturn }

/// One row for a wire line in "give wire" mode. Mirrors the shape used
/// in the Filled page (item name / length / bodyType / qty / weight).
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

  // ── Receive-return state (no job selection — just credits the
  //     Mazdoor's running balance directly) ──
  String _returnType = 'bolt'; // 'bolt' | 'cash'
  final TextEditingController _boltItemController = TextEditingController();
  Item? _selectedBoltItem;
  final TextEditingController _boltQtyController = TextEditingController();
  final TextEditingController _boltRateController = TextEditingController();
  final TextEditingController _cashAmountController = TextEditingController();
  final TextEditingController _returnDescController = TextEditingController();

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

  /// Applies an item picked via CustomAutocomplete to a wire row —
  /// same field population pattern as the Filled page's _addItemToRow,
  /// but simplified since Mazdoor wire lines don't carry pricing (only
  /// length/bodyType/qty/weight matter for stock deduction).
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

  Future<void> _submitGiveWire() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final value = double.tryParse(_valueController.text);

    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(languageProvider.isEnglish
            ? 'Please enter a valid value'
            : 'براہ کرم درست قیمت درج کریں'),
      ));
      return;
    }

    final validRows = _wireRows.where((r) => r.itemNameController.text.isNotEmpty).toList();
    if (validRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(languageProvider.isEnglish
            ? 'Please add at least one wire item'
            : 'براہ کرم کم از کم ایک وائر آئٹم شامل کریں'),
      ));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final lines = validRows.map((r) {
        final qty = double.tryParse(r.qtyController.text) ?? 0.0;
        final weightPerUnit = double.tryParse(r.weightController.text);
        return MazdoorWireLine(
          itemName: r.itemNameController.text,
          length: r.lengthController.text,
          bodyType: r.bodyTypeController.text,
          qty: qty,
          weightPerUnit: weightPerUnit,
          totalWeight: _computeTotalWireWeight(r),
          batchId: r.batchId,
          batchNumber: r.batchNumber,
        );
      }).toList();

      final provider = Provider.of<MazdoorProvider>(context, listen: false);
      final reference = await provider.giveWire(
        mazdoorId: widget.mazdoorId,
        mazdoorName: widget.mazdoorName,
        wireLines: lines,
        value: value,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
      );

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(languageProvider.isEnglish
            ? 'Wire given ($reference). ${widget.mazdoorName} now owes ${value.toStringAsFixed(2)} PKR more.'
            : 'وائر دے دیا گیا ($reference)۔'),
        backgroundColor: Colors.green,
      ));
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _submitReceive() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    setState(() => _isSaving = true);
    try {
      final provider = Provider.of<MazdoorProvider>(context, listen: false);

      if (_returnType == 'bolt') {
        final qty = double.tryParse(_boltQtyController.text);
        final rate = double.tryParse(_boltRateController.text);
        if (_boltItemController.text.isEmpty || qty == null || qty <= 0 ||
            rate == null || rate <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(languageProvider.isEnglish
                ? 'Please enter item, quantity and rate'
                : 'براہ کرم آئٹم، مقدار اور ریٹ درج کریں'),
          ));
          setState(() => _isSaving = false);
          return;
        }

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

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(languageProvider.isEnglish
              ? 'Bolts recorded — ${widget.mazdoorName}\'s balance updated.'
              : 'بولٹس ریکارڈ ہو گئیں۔'),
          backgroundColor: Colors.green,
        ));
      } else {
        final amount = double.tryParse(_cashAmountController.text);
        if (amount == null || amount <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(languageProvider.isEnglish
                ? 'Please enter a valid amount'
                : 'براہ کرم درست رقم درج کریں'),
          ));
          setState(() => _isSaving = false);
          return;
        }

        await provider.receiveCashPayment(
          mazdoorId: widget.mazdoorId,
          mazdoorName: widget.mazdoorName,
          amount: amount,
          description: _returnDescController.text.isEmpty
              ? null
              : _returnDescController.text,
        );

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(languageProvider.isEnglish
              ? 'Cash payment recorded.'
              : 'نقد ادائیگی ریکارڈ ہو گئی۔'),
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

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isGiveWire
              ? (languageProvider.isEnglish
              ? 'Give Wire — ${widget.mazdoorName}'
              : 'وائر دیں — ${widget.mazdoorName}')
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
          : (_isGiveWire
          ? _buildGiveWireForm(languageProvider)
          : _buildReceiveForm(languageProvider)),
    );
  }

  Widget _buildGiveWireForm(LanguageProvider lp) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lp.isEnglish ? 'Wire Items' : 'وائر آئٹمز',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._wireRows.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Same item picker as the Filled page ──
                        Expanded(
                          flex: 2,
                          child: CustomAutocomplete(
                            items: _items,
                            controller: row.itemNameController,
                            selectedCustomerId: null,
                            allowManualEntry: false,
                            onSelected: (Item selectedItem) {
                              _applyItemToWireRow(row, selectedItem);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_wireRows.length > 1)
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _removeWireRow(index),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: row.lengthController,
                            decoration: InputDecoration(
                              labelText: lp.isEnglish ? 'Length' : 'لمبائی',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: row.bodyTypeController,
                            decoration: InputDecoration(
                              labelText: lp.isEnglish ? 'Body Type' : 'باڈی قسم',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: row.qtyController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: lp.isEnglish ? 'Qty' : 'مقدار',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: row.weightController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: lp.isEnglish ? 'Weight/Unit (kg)' : 'وزن/یونٹ',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (row.itemNameController.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.inventory_2, size: 16, color: Colors.blue),
                              onPressed: () => _pickBatchForRow(row),
                              tooltip: lp.isEnglish ? 'Select Batch' : 'بیچ منتخب کریں',
                            ),
                            Text(
                              row.batchNumber != null
                                  ? '${lp.isEnglish ? 'Batch' : 'بیچ'}: ${row.batchNumber}'
                                  : (lp.isEnglish
                                  ? 'No batch selected (optional)'
                                  : 'کوئی بیچ منتخب نہیں (اختیاری)'),
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addWireRow,
              icon: const Icon(Icons.add),
              label: Text(lp.isEnglish ? 'Add Item' : 'آئٹم شامل کریں'),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _valueController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: lp.isEnglish ? 'Value (PKR)' : 'قیمت (روپے)',
              border: const OutlineInputBorder(),
              prefixText: 'PKR ',
              helperText: lp.isEnglish
                  ? 'This amount is added to what the Mazdoor owes you'
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            decoration: InputDecoration(
              labelText: lp.isEnglish ? 'Notes (optional)' : 'نوٹس (اختیاری)',
              border: const OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _submitGiveWire,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal[400],
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSaving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                lp.isEnglish ? 'Give Wire' : 'وائر دیں',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickBatchForRow(_WireRow row) async {
    final itemName = row.itemNameController.text;
    if (itemName.isEmpty) return;

    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
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
              final purchasePrice = (batch['purchasePrice'] as num?)?.toDouble() ?? 0.0;
              final batchNumber = batch['batchNumber']?.toString() ?? 'Batch ${i + 1}';

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(batchNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    'Available: ${qty.toStringAsFixed(2)} kg  |  ${purchasePrice.toStringAsFixed(2)} PKR/kg',
                  ),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () {
                      setState(() {
                        row.batchId = batch['id'];
                        row.batchNumber = batchNumber;
                      });
                      Navigator.pop(context);
                    },
                    child: const Text('Select', style: TextStyle(color: Colors.white)),
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

  Future<List<Map<String, dynamic>>> _fetchBatchesForItem(String itemName) async {
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
            double purchasePrice = (batch['purchasePrice'] as num?)?.toDouble() ??
                (batch['costPrice'] as num?)?.toDouble() ?? 0.0;
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

  Widget _buildReceiveForm(LanguageProvider lp) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                          lp.isEnglish ? 'Bolts Returned' : 'بولٹس واپس',
                          style: TextStyle(
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
                          lp.isEnglish ? 'Cash Payment' : 'نقد ادائیگی',
                          style: TextStyle(
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

          if (_returnType == 'bolt') ...[
            // ── Same item picker as the Filled page, for the bolt item ──
            CustomAutocomplete(
              items: _items,
              controller: _boltItemController,
              selectedCustomerId: null,
              allowManualEntry: true, // bolts may be a brand-new catalog item
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
          ] else ...[
            TextField(
              controller: _cashAmountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: lp.isEnglish ? 'Cash Amount (PKR)' : 'نقد رقم',
                border: const OutlineInputBorder(),
                prefixText: 'PKR ',
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _returnDescController,
            decoration: InputDecoration(
              labelText: lp.isEnglish ? 'Description (optional)' : 'تفصیل (اختیاری)',
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
                lp.isEnglish ? 'Record' : 'ریکارڈ کریں',
                style: const TextStyle(color: Colors.white, fontSize: 16),
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
    super.dispose();
  }
}