
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../Provider/lanprovider.dart';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ItemPurchasePage extends StatefulWidget {
  final String? initialVendorId;
  final String? initialVendorName;
  final List<Map<String, dynamic>> initialItems;
  final bool isFromPurchaseOrder;
  final bool isEditMode;
  final String? purchaseKey;

  ItemPurchasePage({
    this.initialVendorId,
    this.initialVendorName,
    this.initialItems = const [],
    this.isFromPurchaseOrder = false,
    this.isEditMode = false,
    this.purchaseKey,
  });

  @override
  _ItemPurchasePageState createState() => _ItemPurchasePageState();
}

class _ItemPurchasePageState extends State<ItemPurchasePage> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _selectedDateTime;

  late TextEditingController _vendorSearchController;
  late TextEditingController _refNoController;

  bool _isLoadingItems = false;
  bool _isLoadingVendors = false;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _vendors = [];
  Map<String, dynamic>? _selectedVendor;

  List<PurchaseItem> _purchaseItems = [];
  List<Map<String, dynamic>> _bomComponents = [];
  Map<String, double> _wastageRecords = {};

  @override
  void initState() {
    super.initState();
    _selectedDateTime = DateTime.now();
    _vendorSearchController = TextEditingController();
    _refNoController = TextEditingController();

    if (widget.isEditMode && widget.purchaseKey != null) {
      _loadExistingPurchase();
    } else if (widget.initialItems.isNotEmpty) {
      _purchaseItems = widget.initialItems.map((item) {
        return PurchaseItem()
          ..itemNameController.text = item['itemName']?.toString() ?? ''
          ..lengthController.text = item['length']?.toString() ?? ''
          ..bodyTypeController.text = item['bodyType']?.toString() ?? ''
          ..quantityController.text =
              (item['quantity'] as num?)?.toString() ?? '0'
          ..weightController.text =
              (item['weight'] as num?)?.toString() ?? '0'
          ..priceController.text =
              (item['purchasePrice'] as num?)?.toString() ?? '0';
      }).toList();
    } else {
      _purchaseItems = List.generate(3, (index) => PurchaseItem());
    }

    if (widget.initialVendorId != null && widget.initialVendorName != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedVendor = {
              'key': widget.initialVendorId,
              'name': widget.initialVendorName,
            };
            _vendorSearchController.text = widget.initialVendorName!;
          });
        }
      });
    }
    fetchItems();
    fetchVendors();
  }

  Future<void> _loadExistingPurchase() async {
    if (!widget.isEditMode || widget.purchaseKey == null) return;

    final database = FirebaseDatabase.instance.ref();
    final snapshot =
    await database.child('purchases').child(widget.purchaseKey!).get();

    if (snapshot.exists) {
      final purchaseData = snapshot.value as Map<dynamic, dynamic>;

      if (mounted) {
        setState(() {
          if (purchaseData['timestamp'] != null) {
            _selectedDateTime =
                DateTime.parse(purchaseData['timestamp'].toString());
          }

          if (purchaseData['vendorId'] != null &&
              purchaseData['vendorName'] != null) {
            _selectedVendor = {
              'key': purchaseData['vendorId'].toString(),
              'name': purchaseData['vendorName'].toString(),
            };
            _vendorSearchController.text =
                purchaseData['vendorName'].toString();
          }

          if (purchaseData['refNo'] != null) {
            _refNoController.text = purchaseData['refNo'].toString();
          }

          final items = purchaseData['items'] as List<dynamic>?;
          if (items != null) {
            _purchaseItems = items.map((item) {
              final itemMap =
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>);
              double weight = 0.0;
              if (itemMap['weight'] != null) {
                weight = (itemMap['weight'] as num).toDouble();
              }
              return PurchaseItem()
                ..itemNameController.text =
                    itemMap['itemName']?.toString() ?? ''
                ..lengthController.text = itemMap['length']?.toString() ?? ''
                ..bodyTypeController.text =
                    itemMap['bodyType']?.toString() ?? ''
                ..quantityController.text =
                    (itemMap['quantity'] as num?)?.toString() ?? '0'
                ..weightController.text = weight.toString()
                ..priceController.text =
                    (itemMap['purchasePrice'] as num?)?.toString() ?? '0'
                ..descriptionController.text =
                    itemMap['description']?.toString() ?? '';
            }).toList();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _vendorSearchController.dispose();
    _refNoController.dispose();
    for (var item in _purchaseItems) {
      item.dispose();
    }
    super.dispose();
  }

  // ── Batch helpers ─────────────────────────────────────────────────────────

  /// Creates one batch document per valid purchase item.
  /// Called after a successful purchase save.
  Future<void> _createBatches(
      List<PurchaseItem> validItems, String purchaseId) async {
    final db = FirebaseDatabase.instance.ref();

    for (int i = 0; i < validItems.length; i++) {
      final purchaseItem = validItems[i];

      final String itemName = purchaseItem.itemNameController.text.trim();
      final String length = purchaseItem.lengthController.text.trim();
      final String bodyType = purchaseItem.bodyTypeController.text.trim();
      final double qty =
          double.tryParse(purchaseItem.quantityController.text) ?? 0.0;
      final double wtPerUnit =
          double.tryParse(purchaseItem.weightController.text) ?? 0.0;
      final double totalWeight = qty * wtPerUnit;
      final double price =
          double.tryParse(purchaseItem.priceController.text) ?? 0.0;

      if (totalWeight <= 0) continue; // skip zero-weight items

      // Resolve the item key from _items list
      final existingItem = _items.firstWhere(
            (it) => it['itemName'].toString().toLowerCase() == itemName.toLowerCase(),
        orElse: () => {},
      );
      final String itemKey = existingItem['key']?.toString() ?? '';

      // Generate a readable batch number  e.g. BATCH-AB12CD-1
      final String shortId =
      purchaseId.length >= 6 ? purchaseId.substring(0, 6).toUpperCase() : purchaseId.toUpperCase();
      final String batchNumber = 'BATCH-$shortId-${i + 1}';

      final Map<String, dynamic> batchData = {
        'batchNumber': batchNumber,
        'purchaseId': purchaseId,
        'itemKey': itemKey,
        'itemName': itemName,
        'length': length,
        'bodyType': bodyType,
        // quantity = total weight in kg (wt/unit × qty)
        'quantity': totalWeight,
        'remainingQty': totalWeight,
        'costPrice': price,
        'vendorId': _selectedVendor?['key'] ?? '',
        'vendorName': _selectedVendor?['name'] ?? '',
        'timestamp': _selectedDateTime.toIso8601String(),
        'isActive': true,
      };

      await db.child('batches').push().set(batchData);
    }
  }

  /// For edit mode: marks all batches linked to the old purchase as inactive
  /// so they are effectively replaced by the new ones.
  Future<void> _revertOldBatches(String purchaseId) async {
    final db = FirebaseDatabase.instance.ref();
    final snap = await db
        .child('batches')
        .orderByChild('purchaseId')
        .equalTo(purchaseId)
        .get();

    if (!snap.exists) return;

    final batches = snap.value as Map<dynamic, dynamic>;
    for (final entry in batches.entries) {
      await db.child('batches').child(entry.key.toString()).update({
        'isActive': false,
        'replacedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  // ── Item search / combination dialog ──────────────────────────────────────

  void _showLengthCombinationDialogForPurchase(PurchaseItem item) {
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);

    if (item.selectedItem == null ||
        item.selectedItem!['lengthBodyCombinations'] == null) {
      return;
    }

    final List<dynamic> combinations =
    item.selectedItem!['lengthBodyCombinations'] as List<dynamic>;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            languageProvider.isEnglish
                ? 'Select Length-Body Combination'
                : 'لمبائی-جسم کا مجموعہ منتخب کریں',
          ),
          content: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 400),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: combinations.length,
              itemBuilder: (context, index) {
                final combination = combinations[index];
                final length = combination['length']?.toString() ?? '';
                final bodyType = combination['bodyType']?.toString() ?? '';
                final lengthDecimal =
                    combination['lengthDecimal']?.toString() ?? '';
                final costPricePerKg =
                    (combination['costPricePerKg'] as num?)?.toDouble() ?? 0.0;
                final weightPerUnit =
                (combination['weightPerUnit'] as num?)?.toDouble();
                final weightUnit =
                    combination['weightUnit']?.toString() ?? 'kg';

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text('$length - $bodyType'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (lengthDecimal.isNotEmpty)
                          Text(
                            'Decimal: $lengthDecimal',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        if (weightPerUnit != null && weightPerUnit > 0)
                          Text(
                            'Weight/Unit: $weightPerUnit $weightUnit',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.blue),
                          ),
                        Text(
                          'Cost Price: ${costPricePerKg.toStringAsFixed(2)} PKR/kg',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.green),
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.arrow_forward),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        item.selectedLengthBodyCombination =
                        Map<String, dynamic>.from(combination);
                        item.lengthController.text = length;
                        item.bodyTypeController.text = bodyType;
                        item.priceController.text =
                            costPricePerKg.toStringAsFixed(2);
                        if (weightPerUnit != null && weightPerUnit > 0) {
                          item.weightController.text =
                              weightPerUnit.toStringAsFixed(2);
                        }
                      });
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                  languageProvider.isEnglish ? 'Cancel' : 'منسوخ'),
            ),
          ],
        );
      },
    );
  }

  Future<int> _findCombinationIndex(
      DatabaseReference db, String itemKey, String length, String bodyType) async {
    final snap =
    await db.child('items/$itemKey/lengthBodyCombinations').get();
    if (!snap.exists) return -1;
    final List<dynamic> raw = snap.value as List<dynamic>;
    for (int i = 0; i < raw.length; i++) {
      if (raw[i] == null) continue;
      final combo = Map<String, dynamic>.from(raw[i]);
      if (combo['length']?.toString().trim() == length.trim() &&
          combo['bodyType']?.toString().trim() == bodyType.trim()) {
        return i;
      }
    }
    return -1;
  }

  Future<void> _updateCombinationStock(DatabaseReference db, String itemKey,
      String length, String bodyType, double delta) async {
    if (length.trim().isEmpty || bodyType.trim().isEmpty) return;

    final int idx =
    await _findCombinationIndex(db, itemKey, length, bodyType);
    if (idx == -1) {
      print('⚠️ Combination "$length / $bodyType" not found in item $itemKey');
      return;
    }

    final stockSnap = await db
        .child('items/$itemKey/lengthBodyCombinations/$idx/stockQuantity')
        .get();
    final double current =
        (stockSnap.value as num?)?.toDouble() ?? 0.0;

    await db
        .child('items/$itemKey/lengthBodyCombinations/$idx')
        .update({'stockQuantity': current + delta});
  }

  Future<Map<String, dynamic>?> fetchBomForItem(String itemName) async {
    final item = _items.firstWhere(
          (item) => item['itemName'].toLowerCase() == itemName.toLowerCase(),
      orElse: () => {},
    );
    if (item.isNotEmpty && item['isBOM'] == true) {
      return {
        'itemName': item['itemName'],
        'components': item['components'],
      };
    }
    return null;
  }

  Future<void> recordWastage(
      String itemName, double quantity, String purchaseId) async {
    final database = FirebaseDatabase.instance.ref();
    try {
      await database.child('wastage').push().set({
        'itemName': itemName,
        'quantity': quantity,
        'date': DateTime.now().toString(),
        'purchaseId': purchaseId,
        'type': 'production',
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error recording wastage: $e')));
      }
    }
  }

  Future<Map<String, double>> checkBomComponentsForWastage(
      String itemName, double purchasedQty) async {
    final bom = await fetchBomForItem(itemName);
    Map<String, double> wastage = {};

    if (bom != null && bom['components'] != null) {
      final components =
      (bom['components'] as Map<dynamic, dynamic>).cast<String, dynamic>();

      for (var componentEntry in components.entries) {
        final componentName = componentEntry.key;
        final componentQty = (componentEntry.value as num).toDouble();
        final totalComponentQty = componentQty * purchasedQty;

        final componentItem = _items.firstWhere(
              (item) =>
          item['itemName'].toLowerCase() == componentName.toLowerCase(),
          orElse: () => {},
        );

        if (componentItem.isNotEmpty) {
          final currentQty =
              componentItem['qtyOnHand']?.toDouble() ?? 0.0;
          if (currentQty < totalComponentQty) {
            wastage[componentName] = totalComponentQty - currentQty;
          }
        }
      }
    }

    return wastage;
  }

  Future<void> fetchVendors() async {
    if (!mounted) return;
    setState(() => _isLoadingVendors = true);
    final database = FirebaseDatabase.instance.ref();
    try {
      final snapshot = await database.child('vendors').get();
      if (snapshot.exists && mounted) {
        final Map<dynamic, dynamic> vendorData =
        snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          _vendors = vendorData.entries
              .map((entry) => {
            'key': entry.key,
            'name': entry.value['name'] ?? '',
          })
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error fetching vendors: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoadingVendors = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDateTime && mounted) {
      setState(() {
        _selectedDateTime = DateTime(picked.year, picked.month, picked.day,
            _selectedDateTime.hour, _selectedDateTime.minute);
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDateTime = DateTime(_selectedDateTime.year,
            _selectedDateTime.month, _selectedDateTime.day,
            picked.hour, picked.minute);
      });
    }
  }

  void addNewItem() => setState(() => _purchaseItems.add(PurchaseItem()));

  void removeItem(int index) {
    if (_purchaseItems.length <= 1 ||
        index < 0 ||
        index >= _purchaseItems.length) return;
    final itemToRemove = _purchaseItems[index];
    setState(() {
      _purchaseItems = List.from(_purchaseItems)..removeAt(index);
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) itemToRemove.dispose();
    });
  }

  Future<void> _showItemSearchDialog(PurchaseItem item, int index) async {
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    final searchController = TextEditingController();
    List<Map<String, dynamic>> filteredItems = List.from(_items);

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                languageProvider.isEnglish
                    ? 'Select Item'
                    : 'آئٹم منتخب کریں',
                style: const TextStyle(color: Color(0xFFE65100)),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 500,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: languageProvider.isEnglish
                            ? 'Search items...'
                            : 'آئٹمز تلاش کریں...',
                        prefixIcon: const Icon(Icons.search,
                            color: Color(0xFFFF8A65)),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: Color(0xFFFF8A65), width: 2),
                        ),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          filteredItems = value.isEmpty
                              ? List.from(_items)
                              : _items.where((item) {
                            final n = item['itemName']
                                .toString()
                                .toLowerCase();
                            final d = item['description']
                                .toString()
                                .toLowerCase();
                            final q = value.toLowerCase();
                            return n.contains(q) || d.contains(q);
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: filteredItems.isEmpty
                          ? Center(
                        child: Text(
                          languageProvider.isEnglish
                              ? 'No items found'
                              : 'کوئی آئٹم نہیں ملا',
                          style:
                          const TextStyle(color: Colors.grey),
                        ),
                      )
                          : ListView.builder(
                        itemCount: filteredItems.length,
                        itemBuilder: (context, i) {
                          final listItem = filteredItems[i];
                          final hasLengthCombinations =
                              listItem['lengthBodyCombinations'] !=
                                  null &&
                                  (listItem['lengthBodyCombinations']
                                  as List)
                                      .isNotEmpty;

                          return Card(
                            margin: const EdgeInsets.symmetric(
                                vertical: 4),
                            child: ListTile(
                              title: Text(
                                listItem['itemName'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFE65100),
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  if (listItem['description']
                                      ?.toString()
                                      .isNotEmpty ??
                                      false)
                                    Text(
                                        listItem['description']
                                            .toString(),
                                        style: const TextStyle(
                                            fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${languageProvider.isEnglish ? 'Cost Price' : 'لاگت قیمت'}: ${listItem['costPrice']?.toStringAsFixed(2) ?? '0'} | '
                                        '${languageProvider.isEnglish ? 'Stock' : 'اسٹاک'}: ${listItem['qtyOnHand']?.toStringAsFixed(2) ?? '0'} ${listItem['unit'] ?? 'kg'}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600]),
                                  ),
                                  if (hasLengthCombinations)
                                    Container(
                                      margin: const EdgeInsets.only(
                                          top: 4),
                                      padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.blue[50],
                                        borderRadius:
                                        BorderRadius.circular(4),
                                        border: Border.all(
                                            color: Colors.blue[100]!),
                                      ),
                                      child: Text(
                                        languageProvider.isEnglish
                                            ? 'Has length combinations'
                                            : 'لمبائی کے مجموعے ہیں',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.blue,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              trailing: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                  color: Color(0xFFFF8A65)),
                              onTap: () {
                                setState(() {
                                  item.selectedItem = listItem;
                                  item.itemNameController.text =
                                  listItem['itemName'];
                                  item.priceController.text =
                                      listItem['costPrice']
                                          ?.toStringAsFixed(2) ??
                                          '0';
                                  if (listItem['unit'] == 'Kg') {
                                    item.weightController.text = '1';
                                  }
                                  item.selectedLengthBodyCombination =
                                  null;
                                  item.lengthController.clear();
                                  item.bodyTypeController.clear();
                                });
                                Navigator.of(dialogContext).pop();
                                if (hasLengthCombinations) {
                                  Future.delayed(
                                    const Duration(milliseconds: 200),
                                        () {
                                      if (mounted) {
                                        _showLengthCombinationDialogForPurchase(
                                            item);
                                      }
                                    },
                                  );
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    languageProvider.isEnglish ? 'Cancel' : 'منسوخ کریں',
                    style: const TextStyle(color: Color(0xFFFF8A65)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  double calculateTotal() {
    double total = 0.0;
    for (var item in _purchaseItems) {
      final quantity =
          double.tryParse(item.quantityController.text) ?? 0.0;
      final weight = double.tryParse(item.weightController.text) ?? 0.0;
      final price = double.tryParse(item.priceController.text) ?? 0.0;
      total += weight * quantity * price;
    }
    return total;
  }

  double calculateItemTotal(PurchaseItem item) {
    final quantity =
        double.tryParse(item.quantityController.text) ?? 0.0;
    final weight = double.tryParse(item.weightController.text) ?? 0.0;
    final price = double.tryParse(item.priceController.text) ?? 0.0;
    return weight * quantity * price;
  }

  void _clearForm() {
    if (!mounted) return;
    final itemsToDispose = List<PurchaseItem>.from(_purchaseItems);
    setState(() {
      _purchaseItems = List.generate(3, (index) => PurchaseItem());
      _selectedVendor = null;
      _selectedDateTime = DateTime.now();
      _refNoController.clear();
    });
    _vendorSearchController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (var item in itemsToDispose) {
        item.dispose();
      }
    });
  }

  // ── PDF ───────────────────────────────────────────────────────────────────

  Widget tableHeader(String text) => Padding(
    padding: const EdgeInsets.all(8.0),
    child: Text(
      text,
      style: const TextStyle(
          fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
    ),
  );

  Future<Uint8List> _generatePdf(BuildContext context) async {
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    final total = calculateTotal();
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    final validItems = _purchaseItems
        .where((item) =>
    item.itemNameController.text.isNotEmpty &&
        item.quantityController.text.isNotEmpty &&
        item.priceController.text.isNotEmpty)
        .toList();

    final Map<String, Uint8List> sizeImages = {};
    final Map<String, Uint8List> lengthImages = {};
    final Map<String, Uint8List> bodyImages = {};
    final Map<String, Uint8List> descImages = {};

    for (final item in validItems) {
      final size = item.itemNameController.text;
      if (size.isNotEmpty && !sizeImages.containsKey(size)) {
        sizeImages[size] = await _renderTextAsImage(size,
            fontSize: 11, width: 130, height: 20);
      }
      final length = item.lengthController.text;
      if (length.isNotEmpty && !lengthImages.containsKey(length)) {
        lengthImages[length] = await _renderTextAsImage(length,
            fontSize: 11, width: 70, height: 20);
      }
      final body = item.bodyTypeController.text;
      if (body.isNotEmpty && !bodyImages.containsKey(body)) {
        bodyImages[body] = await _renderTextAsImage(body,
            fontSize: 11, width: 80, height: 20);
      }
      String desc = item.descriptionController.text.trim();
      if (desc.isEmpty && item.selectedItem != null) {
        desc = item.selectedItem!['description']?.toString() ?? '';
      }
      if (desc.isNotEmpty && !descImages.containsKey(desc)) {
        descImages[desc] = await _renderTextAsImage(desc,
            fontSize: 11, width: 110, height: 18);
      }
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context ctx) {
          const colWidths = {
            0: pw.FixedColumnWidth(22),
            1: pw.FlexColumnWidth(2.0),
            2: pw.FlexColumnWidth(1.3),
            3: pw.FlexColumnWidth(1.3),
            4: pw.FlexColumnWidth(1.8),
            5: pw.FlexColumnWidth(1.1),
            6: pw.FlexColumnWidth(1.0),
            7: pw.FlexColumnWidth(0.8),
            8: pw.FlexColumnWidth(1.2),
            9: pw.FlexColumnWidth(1.2),
          };

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    widget.isFromPurchaseOrder
                        ? (languageProvider.isEnglish
                        ? 'Purchase Receipt'
                        : 'Receipt')
                        : (languageProvider.isEnglish
                        ? 'Purchase Invoice'
                        : 'Invoice'),
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#E65100'),
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Date: ${dateFormat.format(_selectedDateTime)}',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey600),
                      ),
                      if (_refNoController.text.isNotEmpty)
                        pw.Text(
                          'Ref: ${_refNoController.text}',
                          style: const pw.TextStyle(
                              fontSize: 9, color: PdfColors.grey600),
                        ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(children: [
                pw.Text('Vendor: ',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 10)),
                pw.Text(_selectedVendor?['name'] ?? '',
                    style: const pw.TextStyle(fontSize: 10)),
              ]),
              pw.SizedBox(height: 10),
              pw.Divider(
                  color: PdfColor.fromHex('#FF8A65'), thickness: 1.5),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(
                    color: PdfColors.grey300, width: 0.5),
                columnWidths: colWidths,
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#FF8A65')),
                    children: [
                      _pdfHeader('No.'),
                      _pdfHeader('Size'),
                      _pdfHeader('Length'),
                      _pdfHeader('Body'),
                      _pdfHeader('Desc.'),
                      _pdfHeader('Rate'),
                      _pdfHeader('Wt/Unit'),
                      _pdfHeader('Qty'),
                      _pdfHeader('Tot.Wt'),
                      _pdfHeader('Amount'),
                    ],
                  ),
                  ...validItems.asMap().entries.map((entry) {
                    final i = entry.key;
                    final item = entry.value;
                    final qty =
                        double.tryParse(item.quantityController.text) ??
                            0.0;
                    final wtPerUnit =
                        double.tryParse(item.weightController.text) ?? 0.0;
                    final rate =
                        double.tryParse(item.priceController.text) ?? 0.0;
                    final totalWt = wtPerUnit * qty;
                    final itemTotal = calculateItemTotal(item);

                    String desc = item.descriptionController.text.trim();
                    if (desc.isEmpty && item.selectedItem != null) {
                      desc = item.selectedItem!['description']
                          ?.toString() ??
                          '';
                    }

                    final bgColor =
                    i % 2 == 0 ? PdfColors.white : PdfColors.grey50;

                    pw.Widget imgCell(
                        Uint8List? bytes, String fallback) {
                      if (bytes != null) {
                        return pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 3, vertical: 2),
                          child: pw.SizedBox(
                            height: 20,
                            child: pw.Image(pw.MemoryImage(bytes),
                                fit: pw.BoxFit.contain),
                          ),
                        );
                      }
                      return _pdfCell(fallback);
                    }

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(color: bgColor),
                      children: [
                        _pdfCell('${i + 1}', center: true),
                        imgCell(sizeImages[item.itemNameController.text],
                            item.itemNameController.text),
                        imgCell(lengthImages[item.lengthController.text],
                            item.lengthController.text),
                        imgCell(bodyImages[item.bodyTypeController.text],
                            item.bodyTypeController.text),
                        imgCell(descImages[desc], desc),
                        _pdfCell(rate.toStringAsFixed(2), center: true),
                        _pdfCell(wtPerUnit.toStringAsFixed(2),
                            center: true),
                        _pdfCell(qty.toStringAsFixed(2), center: true),
                        _pdfCell('${totalWt.toStringAsFixed(2)}kg',
                            center: true),
                        _pdfCell(itemTotal.toStringAsFixed(2),
                            center: true, bold: true),
                      ],
                    );
                  }).toList(),
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                        color: PdfColors.grey200),
                    children: [
                      _pdfCell(''),
                      _pdfCell('TOTAL', bold: true),
                      _pdfCell(''),
                      _pdfCell(''),
                      _pdfCell(''),
                      _pdfCell(''),
                      _pdfCell(''),
                      _pdfCell(
                        validItems
                            .fold<double>(
                            0,
                                (s, it) =>
                            s +
                                (double.tryParse(
                                    it.quantityController.text) ??
                                    0))
                            .toStringAsFixed(0),
                        center: true,
                        bold: true,
                      ),
                      _pdfCell(
                        '${validItems.fold<double>(0, (s, it) {
                          final q = double.tryParse(
                              it.quantityController.text) ??
                              0;
                          final w =
                              double.tryParse(it.weightController.text) ??
                                  0;
                          return s + q * w;
                        }).toStringAsFixed(2)}kg',
                        center: true,
                        bold: true,
                      ),
                      _pdfCell(total.toStringAsFixed(2),
                          center: true, bold: true),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#FFF3E0'),
                    border: pw.Border.all(
                        color: PdfColor.fromHex('#FF8A65')),
                    borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    'Grand Total: ${total.toStringAsFixed(2)} PKR',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#E65100'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _pdfHeader(String text) => pw.Padding(
    padding:
    const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
    child: pw.Text(
      text,
      style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white),
      textAlign: pw.TextAlign.center,
    ),
  );

  pw.Widget _pdfCell(String text,
      {bool center = false, bool bold = false}) =>
      pw.Padding(
        padding:
        const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Text(
          text,
          style: pw.TextStyle(
              fontSize: 8,
              fontWeight:
              bold ? pw.FontWeight.bold : pw.FontWeight.normal),
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
        ),
      );

  Future<Uint8List> _renderTextAsImage(
      String text, {
        double fontSize = 10,
        double width = 100,
        double height = 20,
      }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bgPaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style:
        TextStyle(color: const Color(0xFF000000), fontSize: fontSize),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    );
    textPainter.layout(maxWidth: width - 4);
    textPainter.paint(
        canvas, Offset(2, (height - textPainter.height) / 2));
    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData =
    await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  // ── Inventory helpers ─────────────────────────────────────────────────────

  Future<void> _revertOldPurchaseQuantities() async {
    if (!widget.isEditMode || widget.purchaseKey == null) return;

    final database = FirebaseDatabase.instance.ref();
    final oldPurchaseSnapshot = await database
        .child('purchases')
        .child(widget.purchaseKey!)
        .get();
    if (!oldPurchaseSnapshot.exists) return;

    final oldPurchaseData =
    oldPurchaseSnapshot.value as Map<dynamic, dynamic>;
    final oldItems = oldPurchaseData['items'] as List<dynamic>?;
    if (oldItems == null) return;

    for (var oldItem in oldItems) {
      final itemName = oldItem['itemName']?.toString() ?? '';
      final oldQuantity =
          (oldItem['quantity'] as num?)?.toDouble() ?? 0.0;
      final oldWeightPerUnit =
          (oldItem['weightPerUnit'] as num?)?.toDouble() ?? 1.0;
      final double oldTotalWeight = oldQuantity * oldWeightPerUnit;

      if (itemName.isNotEmpty) {
        var existingItem = _items.firstWhere(
              (inventoryItem) =>
          inventoryItem['itemName'].toLowerCase() ==
              itemName.toLowerCase(),
          orElse: () => {},
        );

        if (existingItem.isNotEmpty) {
          String itemKey = existingItem['key'];
          double currentQty =
              existingItem['qtyOnHand']?.toDouble() ?? 0.0;
          await database.child('items').child(itemKey).update({
            'qtyOnHand': currentQty - oldTotalWeight,
          });
        }
      }
    }
  }

  Future<void> _updateInventoryQuantities(
      List<PurchaseItem> validItems, String purchaseId) async {
    final database = FirebaseDatabase.instance.ref();
    final componentConsumptionRef =
    database.child('componentConsumption').child(purchaseId);
    Map<String, Map<String, dynamic>> missingComponents = {};

    for (var purchaseItem in validItems) {
      final String itemName = purchaseItem.itemNameController.text;
      final double quantity =
          double.tryParse(purchaseItem.quantityController.text) ?? 0.0;
      final double weightPerUnit =
          double.tryParse(purchaseItem.weightController.text) ?? 0.0;
      final double totalWeightPurchased = quantity * weightPerUnit;
      final double purchasePrice =
          double.tryParse(purchaseItem.priceController.text) ?? 0.0;
      final String purchasedLength =
      purchaseItem.lengthController.text.trim();
      final String purchasedBodyType =
      purchaseItem.bodyTypeController.text.trim();

      var existingItem = _items.firstWhere(
            (i) => i['itemName'].toLowerCase() == itemName.toLowerCase(),
        orElse: () => {},
      );
      if (existingItem.isEmpty) continue;

      final String itemKey = existingItem['key'];
      final double currentQty =
          (existingItem['qtyOnHand'] as num?)?.toDouble() ?? 0.0;

      await database.child('items').child(itemKey).update({
        'qtyOnHand': currentQty + totalWeightPurchased,
        'costPrice': purchasePrice,
      });

      await _updateCombinationStock(database, itemKey, purchasedLength,
          purchasedBodyType, totalWeightPurchased);

      if (existingItem['isBOM'] == true) {
        dynamic componentsData = existingItem['components'];
        Map<String, dynamic> components = {};

        if (componentsData is Map) {
          components = componentsData.cast<String, dynamic>();
        } else if (componentsData is List) {
          for (int i = 0; i < componentsData.length; i += 2) {
            if (i + 1 < componentsData.length) {
              components[componentsData[i].toString()] =
              componentsData[i + 1];
            }
          }
        }

        Map<String, dynamic> consumptionRecord = {
          'bomItemName': itemName,
          'bomItemKey': itemKey,
          'quantityProduced': quantity,
          'totalWeightProduced': totalWeightPurchased,
          'timestamp': _selectedDateTime.toString(),
          'components': {},
        };

        for (var componentEntry in components.entries) {
          String componentName = componentEntry.key;
          double qtyPerUnit = 0.0;
          if (componentEntry.value is num) {
            qtyPerUnit = (componentEntry.value as num).toDouble();
          } else if (componentEntry.value is String) {
            qtyPerUnit =
                double.tryParse(componentEntry.value as String) ?? 0.0;
          }
          double totalQtyRequired = qtyPerUnit * quantity;

          var componentItem = _items.firstWhere(
                (item) =>
            item['itemName'].toLowerCase() ==
                componentName.toLowerCase(),
            orElse: () => {},
          );

          if (componentItem.isNotEmpty) {
            String componentKey = componentItem['key'];
            double currentComponentQty =
                (componentItem['qtyOnHand'] as num?)?.toDouble() ?? 0.0;

            if (currentComponentQty < totalQtyRequired) {
              missingComponents[componentKey] = {
                'name': componentName,
                'requiredQty': totalQtyRequired,
                'availableQty': currentComponentQty,
                'unit': componentItem['unit'] ?? '',
              };
            }

            consumptionRecord['components'][componentName] = {
              'required': totalQtyRequired,
              'used': currentComponentQty >= totalQtyRequired
                  ? totalQtyRequired
                  : currentComponentQty,
              'remaining': currentComponentQty >= totalQtyRequired
                  ? currentComponentQty - totalQtyRequired
                  : 0.0,
            };
          }
        }

        await componentConsumptionRef.set(consumptionRecord);
      }
    }

    if (missingComponents.isNotEmpty) {
      final languageProvider =
      Provider.of<LanguageProvider>(context, listen: false);
      bool proceed = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(languageProvider.isEnglish
              ? 'Insufficient Components'
              : 'اجزاء کی کمی'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: missingComponents.values.map((comp) {
                return ListTile(
                  title: Text('${comp['name']} (${comp['unit']})'),
                  subtitle: Text(languageProvider.isEnglish
                      ? 'Required: ${comp['requiredQty']}, Available: ${comp['availableQty']}'
                      : 'درکار: ${comp['requiredQty']}, دستیاب: ${comp['availableQty']}'),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(languageProvider.isEnglish
                  ? 'Cancel'
                  : 'منسوخ کریں'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(languageProvider.isEnglish
                  ? 'Proceed Anyway'
                  : 'پھر بھی جاری رکھیں'),
            ),
          ],
        ),
      );

      if (!proceed) {
        await _revertInventoryUpdates(validItems);
        return;
      }
    }

    for (var purchaseItem in validItems) {
      String itemName = purchaseItem.itemNameController.text;
      double quantity =
          double.tryParse(purchaseItem.quantityController.text) ?? 0.0;

      var existingItem = _items.firstWhere(
            (i) => i['itemName'].toLowerCase() == itemName.toLowerCase(),
        orElse: () => {},
      );

      if (existingItem.isNotEmpty && existingItem['isBOM'] == true) {
        dynamic componentsData = existingItem['components'];
        Map<String, dynamic> components = {};
        if (componentsData is Map) {
          components = componentsData.cast<String, dynamic>();
        } else if (componentsData is List) {
          for (int i = 0; i < componentsData.length; i += 2) {
            if (i + 1 < componentsData.length) {
              components[componentsData[i].toString()] =
              componentsData[i + 1];
            }
          }
        }

        for (var componentEntry in components.entries) {
          String componentName = componentEntry.key;
          double qtyPerUnit = 0.0;
          if (componentEntry.value is num) {
            qtyPerUnit = (componentEntry.value as num).toDouble();
          } else if (componentEntry.value is String) {
            qtyPerUnit =
                double.tryParse(componentEntry.value as String) ?? 0.0;
          }
          double totalQtyRequired = qtyPerUnit * quantity;

          var componentItem = _items.firstWhere(
                (item) =>
            item['itemName'].toLowerCase() ==
                componentName.toLowerCase(),
            orElse: () => {},
          );

          if (componentItem.isNotEmpty) {
            String componentKey = componentItem['key'];
            double currentQty =
                (componentItem['qtyOnHand'] as num?)?.toDouble() ?? 0.0;
            double qtyToDeduct = currentQty < totalQtyRequired
                ? currentQty
                : totalQtyRequired;

            await database
                .child('items')
                .child(componentKey)
                .update({'qtyOnHand': currentQty - qtyToDeduct});

            if (qtyToDeduct < totalQtyRequired) {
              await database.child('wastage').push().set({
                'itemName': componentName,
                'quantity': totalQtyRequired - qtyToDeduct,
                'date': DateTime.now().toString(),
                'purchaseId': purchaseId,
                'type': 'component_shortage',
                'relatedBOM': itemName,
              });
            }
          }
        }
      }
    }
  }

  Future<void> _revertInventoryUpdates(
      List<PurchaseItem> validItems) async {
    final database = FirebaseDatabase.instance.ref();

    for (var purchaseItem in validItems) {
      final String itemName = purchaseItem.itemNameController.text;
      final double quantity =
          double.tryParse(purchaseItem.quantityController.text) ?? 0.0;
      final double weightPerUnit =
          double.tryParse(purchaseItem.weightController.text) ?? 0.0;
      final double totalWeight = quantity * weightPerUnit;
      final String length = purchaseItem.lengthController.text.trim();
      final String bodyType =
      purchaseItem.bodyTypeController.text.trim();

      var existingItem = _items.firstWhere(
            (i) => i['itemName'].toLowerCase() == itemName.toLowerCase(),
        orElse: () => {},
      );
      if (existingItem.isEmpty) continue;

      final String itemKey = existingItem['key'];
      final double currentQty =
          (existingItem['qtyOnHand'] as num?)?.toDouble() ?? 0.0;

      await database
          .child('items')
          .child(itemKey)
          .update({'qtyOnHand': currentQty - totalWeight});

      await _updateCombinationStock(
          database, itemKey, length, bodyType, -totalWeight);
    }

    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(languageProvider.isEnglish
              ? 'Purchase cancelled due to insufficient components'
              : 'اجزاء کی کمی کی وجہ سے خریداری منسوخ کر دی گئی')));
    }
    throw Exception('Purchase cancelled due to insufficient components');
  }

  // ── Save purchase (main entry point) ──────────────────────────────────────

  Future<void> savePurchase() async {
    if (!mounted) return;

    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);

    if (_formKey.currentState!.validate()) {
      if (_selectedVendor == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(languageProvider.isEnglish
                  ? 'Please select a vendor'
                  : 'براہ کرم فروش منتخب کریں')),
        );
        return;
      }

      List<PurchaseItem> validItems = _purchaseItems
          .where((purchaseItem) =>
      purchaseItem.itemNameController.text.isNotEmpty &&
          purchaseItem.quantityController.text.isNotEmpty &&
          purchaseItem.priceController.text.isNotEmpty)
          .toList();

      if (validItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(languageProvider.isEnglish
                  ? 'Please add at least one item'
                  : 'براہ کرم کم از کم ایک آئٹم شامل کریں')),
        );
        return;
      }

      try {
        final database = FirebaseDatabase.instance.ref();
        String vendorKey = _selectedVendor!['key'];
        _wastageRecords.clear();

        final purchaseData = {
          'items': validItems.map((purchaseItem) {
            String description =
            purchaseItem.descriptionController.text.trim();
            if (description.isEmpty &&
                purchaseItem.selectedItem != null) {
              description =
                  purchaseItem.selectedItem!['description']?.toString() ??
                      '';
            }
            return {
              'itemName': purchaseItem.itemNameController.text,
              'length': purchaseItem.lengthController.text,
              'bodyType': purchaseItem.bodyTypeController.text,
              'description': description,
              'weight':
              double.tryParse(purchaseItem.weightController.text) ??
                  0.0,
              'weightPerUnit':
              double.tryParse(purchaseItem.weightController.text) ??
                  0.0,
              'quantity':
              double.tryParse(purchaseItem.quantityController.text) ??
                  0.0,
              'purchasePrice':
              double.tryParse(purchaseItem.priceController.text) ?? 0.0,
              'totalWeight':
              (double.tryParse(purchaseItem.weightController.text) ??
                  0.0) *
                  (double.tryParse(
                      purchaseItem.quantityController.text) ??
                      0.0),
              'total': calculateItemTotal(purchaseItem),
              'isBOM': _items.any((item) =>
              item['itemName'].toLowerCase() ==
                  purchaseItem.itemNameController.text.toLowerCase() &&
                  item['isBOM'] == true),
            };
          }).toList(),
          'vendorId': vendorKey,
          'vendorName': _selectedVendor!['name'],
          'refNo': _refNoController.text,
          'grandTotal': calculateTotal(),
          'timestamp': _selectedDateTime.toString(),
          'type': 'credit',
          'hasBOM': validItems.any((purchaseItem) => _items.any(
                  (inventoryItem) =>
              inventoryItem['itemName'].toLowerCase() ==
                  purchaseItem.itemNameController.text.toLowerCase() &&
                  inventoryItem['isBOM'] == true)),
        };

        DatabaseReference purchaseRef;
        String purchaseId;

        if (widget.isEditMode && widget.purchaseKey != null) {
          purchaseId = widget.purchaseKey!;
          purchaseRef = database.child('purchases').child(purchaseId);
          await _revertOldPurchaseQuantities();
          await purchaseRef.update(purchaseData);
          // Mark old batches as inactive before creating new ones
          await _revertOldBatches(purchaseId);
        } else {
          purchaseRef = database.child('purchases').push();
          purchaseId = purchaseRef.key!;
          await purchaseRef.set(purchaseData);
        }

        // Update inventory stock levels
        await _updateInventoryQuantities(validItems, purchaseId);

        // ── NEW: Create one batch per purchase item ───────────────────
        await _createBatches(validItems, purchaseId);
        // ─────────────────────────────────────────────────────────────

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(languageProvider.isEnglish
                    ? widget.isEditMode
                    ? 'Purchase updated successfully!'
                    : 'Purchase recorded successfully!'
                    : widget.isEditMode
                    ? 'خریداری کامیابی سے اپ ڈیٹ ہو گئی!'
                    : 'خریداری کامیابی سے ریکارڈ ہو گئی!')),
          );

          if (!widget.isEditMode) {
            _clearForm();
          } else {
            Navigator.of(context).pop();
          }
        }
      } catch (error) {
        if (error
            .toString()
            .contains('cancelled due to insufficient components')) {
          return;
        }
        print('Purchase error: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(languageProvider.isEnglish
                    ? 'Failed to ${widget.isEditMode ? 'update' : 'record'} purchase: ${error.toString()}'
                    : 'خریداری ${widget.isEditMode ? 'اپ ڈیٹ' : 'ریکارڈ'} کرنے میں ناکامی: ${error.toString()}')),
          );
        }
      }
    }
  }

  // ── fetchItems ────────────────────────────────────────────────────────────

  Future<void> fetchItems() async {
    if (!mounted) return;
    setState(() => _isLoadingItems = true);
    final database = FirebaseDatabase.instance.ref();
    try {
      final snapshot = await database.child('items').get();
      if (snapshot.exists && mounted) {
        dynamic itemData = snapshot.value;
        Map<dynamic, dynamic> itemsMap = {};

        if (itemData is Map) {
          itemsMap = itemData;
        } else if (itemData is List) {
          itemsMap = {
            for (var i = 0; i < itemData.length; i++)
              i.toString(): itemData[i]
          };
        }

        setState(() {
          _items = itemsMap.entries.map((entry) {
            dynamic componentsData = entry.value['components'];
            Map<String, dynamic> componentsMap = {};

            if (componentsData != null) {
              if (componentsData is Map) {
                componentsMap = componentsData.cast<String, dynamic>();
              } else if (componentsData is List) {
                for (int i = 0; i < componentsData.length; i += 2) {
                  if (i + 1 < componentsData.length) {
                    componentsMap[componentsData[i].toString()] =
                    componentsData[i + 1];
                  }
                }
              }
            }

            return {
              'key': entry.key,
              'itemName': entry.value['itemName']?.toString() ?? '',
              'description':
              entry.value['description']?.toString() ?? '',
              'costPrice':
              (entry.value['costPrice'] as num?)?.toDouble() ?? 0.0,
              'qtyOnHand':
              (entry.value['qtyOnHand'] as num?)?.toDouble() ?? 0.0,
              'isBOM': entry.value['isBOM'] == true,
              'components': componentsMap,
              'unit': entry.value['unit']?.toString() ?? 'kg',
              'lengthBodyCombinations':
              entry.value['lengthBodyCombinations'],
            };
          }).toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error fetching items: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoadingItems = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final total = calculateTotal();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditMode
              ? languageProvider.isEnglish
              ? 'Edit Purchase'
              : 'خریداری میں ترمیم کریں'
              : widget.isFromPurchaseOrder
              ? languageProvider.isEnglish
              ? 'Receive Items'
              : 'آئٹمز وصول کریں'
              : languageProvider.isEnglish
              ? 'Purchase Items'
              : 'آئٹمز خریداری',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF8A65), Color(0xFFFFB74D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () async {
              try {
                final pdfBytes = await _generatePdf(context);
                await Printing.layoutPdf(onLayout: (format) => pdfBytes);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      languageProvider.isEnglish
                          ? 'Error generating PDF: $e'
                          : 'PDF بنانے میں خرابی: $e',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.print, color: Colors.white),
          )
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vendor search
                  Text(
                    languageProvider.isEnglish
                        ? 'Search Vendor'
                        : 'وینڈر تلاش کریں',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE65100)),
                  ),
                  const SizedBox(height: 8),
                  Autocomplete<Map<String, dynamic>>(
                    optionsBuilder: (textEditingValue) {
                      if (textEditingValue.text.isEmpty)
                        return const Iterable.empty();
                      return _vendors.where((vendor) => vendor['name']
                          .toLowerCase()
                          .contains(
                          textEditingValue.text.toLowerCase()));
                    },
                    displayStringForOption: (vendor) => vendor['name'],
                    onSelected: (vendor) {
                      setState(() => _selectedVendor = vendor);
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onSubmit) {
                      _vendorSearchController = controller;
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: languageProvider.isEnglish
                              ? 'Search Vendor'
                              : 'وینڈر تلاش کریں',
                          border: const OutlineInputBorder(
                            borderSide: BorderSide(
                                color: Color(0xFFFF8A65)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(
                                color: Color(0xFFFF8A65)),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Ref No
                  Text(
                    languageProvider.isEnglish
                        ? 'Reference Number'
                        : 'ریفیرنس نمبر',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE65100)),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _refNoController,
                    decoration: InputDecoration(
                      labelText: languageProvider.isEnglish
                          ? 'Enter Reference Number'
                          : 'ریفیرنس نمبر درج کریں',
                      border: const OutlineInputBorder(
                          borderSide:
                          BorderSide(color: Color(0xFFFF8A65))),
                      focusedBorder: const OutlineInputBorder(
                          borderSide:
                          BorderSide(color: Color(0xFFFF8A65))),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Items table
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                languageProvider.isEnglish
                                    ? 'Invoice Items'
                                    : 'خریداری کے آئٹمز',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFE65100),
                                  fontSize: 16,
                                ),
                              ),
                              ElevatedButton(
                                onPressed: addNewItem,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF8A65),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                      BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.add,
                                        size: 16, color: Colors.white),
                                    const SizedBox(width: 4),
                                    Text(
                                      languageProvider.isEnglish
                                          ? 'Add Item'
                                          : 'آئٹم شامل کریں',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                  minWidth:
                                  MediaQuery.of(context).size.width),
                              child: Table(
                                defaultVerticalAlignment:
                                TableCellVerticalAlignment.middle,
                                columnWidths: const {
                                  0: FixedColumnWidth(40),
                                  1: FixedColumnWidth(200),
                                  2: FixedColumnWidth(100),
                                  3: FixedColumnWidth(120),
                                  4: FixedColumnWidth(180),
                                  5: FixedColumnWidth(90),
                                  6: FixedColumnWidth(90),
                                  7: FixedColumnWidth(80),
                                  8: FixedColumnWidth(100),
                                  9: FixedColumnWidth(110),
                                  10: FixedColumnWidth(50),
                                },
                                border: TableBorder.all(
                                    color: Colors.orange.shade100,
                                    width: 1),
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(
                                        color: Colors.orange.shade50),
                                    children: [
                                      tableHeader('No.'),
                                      tableHeader(
                                          languageProvider.isEnglish
                                              ? 'Size'
                                              : 'سائز'),
                                      tableHeader(
                                          languageProvider.isEnglish
                                              ? 'Length'
                                              : 'لمبائی'),
                                      tableHeader(
                                          languageProvider.isEnglish
                                              ? 'Body Type'
                                              : 'باڈی قسم'),
                                      tableHeader(
                                          languageProvider.isEnglish
                                              ? 'Description'
                                              : 'تفصیل'),
                                      tableHeader(
                                          languageProvider.isEnglish
                                              ? 'Rate'
                                              : 'ریٹ'),
                                      tableHeader(
                                          languageProvider.isEnglish
                                              ? 'Wt/Unit'
                                              : 'وزن/یونٹ'),
                                      tableHeader(
                                          languageProvider.isEnglish
                                              ? 'Qty'
                                              : 'مقدار'),
                                      tableHeader(
                                          languageProvider.isEnglish
                                              ? 'Total Wt'
                                              : 'کل وزن'),
                                      tableHeader(
                                          languageProvider.isEnglish
                                              ? 'Amount'
                                              : 'رقم'),
                                      const SizedBox(),
                                    ],
                                  ),
                                  ..._purchaseItems.asMap().entries.map(
                                          (entry) {
                                        final index = entry.key;
                                        final item = entry.value;

                                        final weightPerUnit =
                                            double.tryParse(
                                                item.weightController
                                                    .text) ??
                                                0.0;
                                        final quantity = double.tryParse(
                                            item.quantityController
                                                .text) ??
                                            0.0;
                                        final totalWeight =
                                            weightPerUnit * quantity;
                                        final totalAmount =
                                        calculateItemTotal(item);

                                        return TableRow(children: [
                                          Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Center(
                                              child: Text('${index + 1}',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                      FontWeight.bold)),
                                            ),
                                          ),
                                          Padding(
                                            padding:
                                            const EdgeInsets.all(6.0),
                                            child: Row(children: [
                                              Expanded(
                                                child: TextFormField(
                                                  controller:
                                                  item.itemNameController,
                                                  readOnly: true,
                                                  decoration: InputDecoration(
                                                    isDense: true,
                                                    border:
                                                    const OutlineInputBorder(),
                                                    contentPadding:
                                                    const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 10),
                                                    hintText: languageProvider
                                                        .isEnglish
                                                        ? 'Select item'
                                                        : 'آئٹم منتخب کریں',
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              IconButton(
                                                icon: const Icon(Icons.search,
                                                    color:
                                                    Color(0xFFFF8A65)),
                                                onPressed: () =>
                                                    _showItemSearchDialog(
                                                        item, index),
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                const BoxConstraints(),
                                              ),
                                            ]),
                                          ),
                                          Padding(
                                            padding:
                                            const EdgeInsets.all(6.0),
                                            child: TextFormField(
                                              controller:
                                              item.lengthController,
                                              readOnly: true,
                                              decoration: InputDecoration(
                                                isDense: true,
                                                border:
                                                const OutlineInputBorder(),
                                                contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 10),
                                                hintText:
                                                languageProvider.isEnglish
                                                    ? 'Length'
                                                    : 'لمبائی',
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding:
                                            const EdgeInsets.all(6.0),
                                            child: TextFormField(
                                              controller:
                                              item.bodyTypeController,
                                              readOnly: true,
                                              decoration: InputDecoration(
                                                isDense: true,
                                                border:
                                                const OutlineInputBorder(),
                                                contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 10),
                                                hintText:
                                                languageProvider.isEnglish
                                                    ? 'Body Type'
                                                    : 'باڈی قسم',
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding:
                                            const EdgeInsets.all(6.0),
                                            child: TextFormField(
                                              controller:
                                              item.descriptionController,
                                              maxLines: 1,
                                              decoration: InputDecoration(
                                                isDense: true,
                                                border:
                                                const OutlineInputBorder(),
                                                contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 10),
                                                hintText:
                                                languageProvider.isEnglish
                                                    ? 'Desc'
                                                    : 'تفصیل',
                                              ),
                                              onChanged: (_) =>
                                                  setState(() {}),
                                            ),
                                          ),
                                          Padding(
                                            padding:
                                            const EdgeInsets.all(6.0),
                                            child: TextFormField(
                                              controller: item.priceController,
                                              keyboardType:
                                              TextInputType.numberWithOptions(
                                                  decimal: true),
                                              onChanged: (_) =>
                                                  setState(() {}),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                                contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 10),
                                                hintText: '0.0',
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding:
                                            const EdgeInsets.all(6.0),
                                            child: TextFormField(
                                              controller:
                                              item.weightController,
                                              keyboardType:
                                              TextInputType.numberWithOptions(
                                                  decimal: true),
                                              onChanged: (_) =>
                                                  setState(() {}),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                                contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 10),
                                                hintText: '0.0',
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding:
                                            const EdgeInsets.all(6.0),
                                            child: TextFormField(
                                              controller:
                                              item.quantityController,
                                              keyboardType:
                                              TextInputType.numberWithOptions(
                                                  decimal: true),
                                              onChanged: (_) =>
                                                  setState(() {}),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                                contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 10),
                                                hintText: '0',
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding:
                                            const EdgeInsets.all(6.0),
                                            child: Container(
                                              height: 40,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: Colors.grey[100],
                                                borderRadius:
                                                BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                totalWeight.toStringAsFixed(2),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue[700],
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding:
                                            const EdgeInsets.all(6.0),
                                            child: Container(
                                              height: 40,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: Colors.green[50],
                                                borderRadius:
                                                BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                totalAmount.toStringAsFixed(0),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green[700],
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Center(
                                            child: IconButton(
                                              icon: const Icon(
                                                  Icons.remove_circle,
                                                  color: Colors.red,
                                                  size: 20),
                                              onPressed:
                                              _purchaseItems.length > 1
                                                  ? () =>
                                                  removeItem(index)
                                                  : null,
                                            ),
                                          ),
                                        ]);
                                      }),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Date / Time pickers
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.calendar_today,
                              size: 18, color: Colors.white),
                          label: Text(
                            languageProvider.isEnglish
                                ? 'Select Date'
                                : 'تاریخ منتخب کریں',
                            style:
                            const TextStyle(color: Colors.white),
                          ),
                          onPressed: () => _selectDate(context),
                          style: ElevatedButton.styleFrom(
                              backgroundColor:
                              const Color(0xFFFF8A65)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.access_time,
                              size: 18, color: Colors.white),
                          label: Text(
                            languageProvider.isEnglish
                                ? 'Select Time'
                                : 'وقت منتخب کریں',
                            style:
                            const TextStyle(color: Colors.white),
                          ),
                          onPressed: () => _selectTime(context),
                          style: ElevatedButton.styleFrom(
                              backgroundColor:
                              const Color(0xFFFF8A65)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    languageProvider.isEnglish
                        ? 'Selected: ${DateFormat('yyyy-MM-dd HH:mm').format(_selectedDateTime)}'
                        : 'منتخب شدہ: ${DateFormat('yyyy-MM-dd HH:mm').format(_selectedDateTime)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16, color: Color(0xFFE65100)),
                  ),
                  const SizedBox(height: 16),

                  // Grand total
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFFF8A65)),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          languageProvider.isEnglish
                              ? 'Grand Total:'
                              : 'کل کل:',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFE65100)),
                        ),
                        Text(
                          '${total.toStringAsFixed(2)} PKR',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE65100),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Save button
                  Center(
                    child: ElevatedButton(
                      onPressed: savePurchase,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8A65),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 10),
                      ),
                      child: Text(
                        widget.isFromPurchaseOrder
                            ? languageProvider.isEnglish
                            ? 'Receive Items'
                            : 'آئٹمز وصول کریں'
                            : languageProvider.isEnglish
                            ? 'Record Purchase'
                            : 'خریداری ریکارڈ کریں',
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
        ),
      ),
    );
  }

  // ── Misc helpers kept from original ───────────────────────────────────────

  Future<Map<String, Map<String, dynamic>>> getBomComponents(
      String itemName, double purchasedQty) async {
    final database = FirebaseDatabase.instance.ref();
    final snapshot = await database
        .child('items')
        .orderByChild('itemName')
        .equalTo(itemName)
        .get();

    if (snapshot.exists) {
      final itemsData = snapshot.value as Map<dynamic, dynamic>;
      for (final itemEntry in itemsData.entries) {
        final item = itemEntry.value;
        if (item['itemName'] == itemName && item['isBOM'] == true) {
          final components = item['components'];
          if (components is List) {
            final componentMap = <String, Map<String, dynamic>>{};
            for (int i = 0; i < components.length; i++) {
              final component = components[i];
              if (component is Map && component['id'] != null) {
                final componentName = component['name']?.toString() ?? '';
                final componentId = component['id'].toString();
                final componentQty =
                    (component['quantity'] as num?)?.toDouble() ?? 0.0;
                componentMap[componentId] = {
                  'name': componentName,
                  'quantity': componentQty * purchasedQty,
                  'unit': component['unit']?.toString() ?? '',
                };
              }
            }
            return componentMap;
          }
        }
      }
    }
    return {};
  }

  Future<Map<String, dynamic>> checkBomFeasibility(
      String bomItemName, double quantity) async {
    final bomItem = _items.firstWhere(
          (item) =>
      item['itemName'].toLowerCase() == bomItemName.toLowerCase(),
      orElse: () => {},
    );

    if (bomItem.isEmpty || bomItem['isBOM'] != true) {
      return {'feasible': true, 'missingComponents': {}};
    }

    Map<String, dynamic> components = bomItem['components'] ?? {};
    Map<String, dynamic> result = {
      'feasible': true,
      'missingComponents': {},
      'totalRequired': {},
    };

    for (var componentEntry in components.entries) {
      String componentName = componentEntry.key;
      double componentQtyPerUnit =
      (componentEntry.value as num).toDouble();
      double totalComponentQty = componentQtyPerUnit * quantity;

      var componentItem = _items.firstWhere(
            (item) =>
        item['itemName'].toLowerCase() == componentName.toLowerCase(),
        orElse: () => {},
      );

      if (componentItem.isEmpty) {
        result['feasible'] = false;
        result['missingComponents'][componentName] = {
          'required': totalComponentQty,
          'available': 0.0,
          'shortage': totalComponentQty,
        };
      } else {
        double availableQty =
            componentItem['qtyOnHand']?.toDouble() ?? 0.0;
        result['totalRequired'][componentName] = totalComponentQty;
        if (availableQty < totalComponentQty) {
          result['feasible'] = false;
          result['missingComponents'][componentName] = {
            'required': totalComponentQty,
            'available': availableQty,
            'shortage': totalComponentQty - availableQty,
          };
        }
      }
    }

    return result;
  }
}

// ── PurchaseItem model ────────────────────────────────────────────────────────

class PurchaseItem {
  late TextEditingController itemNameController;
  late TextEditingController quantityController;
  late TextEditingController weightController;
  late TextEditingController priceController;
  late TextEditingController descriptionController;
  late TextEditingController lengthController;
  late TextEditingController bodyTypeController;
  Map<String, dynamic>? selectedItem;
  Map<String, dynamic>? selectedLengthBodyCombination;

  PurchaseItem() {
    itemNameController = TextEditingController();
    quantityController = TextEditingController();
    weightController = TextEditingController();
    priceController = TextEditingController();
    descriptionController = TextEditingController();
    lengthController = TextEditingController();
    bodyTypeController = TextEditingController();
    selectedItem = null;
    selectedLengthBodyCombination = null;
  }

  void dispose() {
    itemNameController.dispose();
    quantityController.dispose();
    weightController.dispose();
    priceController.dispose();
    descriptionController.dispose();
    lengthController.dispose();
    bodyTypeController.dispose();
  }
}