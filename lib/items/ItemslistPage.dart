import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mughal_group_branch_two/items/stockreportpage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:ui' as ui;
import '../Provider/lanprovider.dart';
import '../Purchase/wastage recordpage.dart';
import 'AddItems.dart';
import 'editphysicalqty.dart';
import '../Models/batch_model.dart';

class ItemsListPage extends StatefulWidget {
  @override
  _ItemsListPageState createState() => _ItemsListPageState();
}

class _ItemsListPageState extends State<ItemsListPage> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _filteredItems = [];
  final TextEditingController _searchController = TextEditingController();
  Map<String, dynamic>? _selectedItem;
  List<Map<String, dynamic>> _itemTransactions = [];
  bool _isLoadingTransactions = false;
  String? _savedPdfPath;
  Uint8List? _pdfBytes;
  Map<String, String> customerIdNameMap = {};
  final Color _primaryColor = Color(0xFFFF8A65);
  final Color _secondaryColor = Color(0xFFFFB74D);
  final Color _backgroundColor = Colors.grey[50]!;
  final Color _cardColor = Colors.white;
  final Color _textColor = Colors.grey[800]!;
  Map<String, double> _expandedCombinations = {};

  // ── NEW: Batch data ──────────────────────────────────────────────────────
  Map<String, List<Batch>> _batchesByItemName = {};
  Map<String, bool> _expandedBatches = {};
  bool _isLoadingBatches = false;

  // ── Stock helpers ──────────────────────────────────────────────────────────
  Color _stockColor(double qty, double threshold) {
    if (qty <= 0) return Colors.red;
    if (qty <= threshold) return Colors.orange;
    return Colors.green;
  }

  IconData _stockIcon(double qty, double threshold) {
    if (qty <= 0) return Icons.remove_circle;
    if (qty <= threshold) return Icons.warning_amber_rounded;
    return Icons.check_circle;
  }

  String _stockLabel(double qty, double threshold) {
    if (qty <= 0) return 'Out of Stock';
    if (qty <= threshold) return 'Low Stock';
    return 'In Stock';
  }

  Future<void> _fetchCustomerNames() async {
    final snapshot = await FirebaseDatabase.instance.ref('customers').get();
    if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final Map<String, String> nameMap = {};
      data.forEach((key, value) {
        if (value is Map && value.containsKey('name')) {
          nameMap[key] = value['name'].toString();
        }
      });
      setState(() {
        customerIdNameMap = nameMap;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    fetchItems();
    _fetchCustomerNames();
    _fetchAllBatches();
    _searchController.addListener(_searchItems);
  }

  // ── NEW: Fetch all batches and group by item name ────────────────────────
  Future<void> _fetchAllBatches() async {
    if (mounted) setState(() => _isLoadingBatches = true);

    final snap = await FirebaseDatabase.instance.ref('batches').get();
    final Map<String, List<Batch>> grouped = {};

    if (snap.exists) {
      final data = snap.value as Map<dynamic, dynamic>;
      data.forEach((key, value) {
        final batch = Batch.fromMap(Map<String, dynamic>.from(value as Map), key.toString());
        // Only include active batches with remaining quantity > 0
        if (batch.isActive && batch.remainingQty > 0) {
          grouped.putIfAbsent(batch.itemName, () => []).add(batch);
        }
      });

      // Sort each batch list by purchase date (newest first)
      grouped.forEach((key, list) {
        list.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
      });
    }

    if (mounted) {
      setState(() {
        _batchesByItemName = grouped;
        _isLoadingBatches = false;
      });
    }
  }

  // ── NEW: Get total batch quantity for an item ────────────────────────────
  double _getTotalBatchQty(String itemName) {
    final batches = _batchesByItemName[itemName];
    if (batches == null) return 0.0;
    return batches.fold(0.0, (sum, b) => sum + b.remainingQty);
  }

  // ── NEW: Get batch count for an item ─────────────────────────────────────
  int _getBatchCount(String itemName) {
    return _batchesByItemName[itemName]?.length ?? 0;
  }

  // ── NEW: Toggle batch expansion for an item ──────────────────────────────
  void _toggleBatchExpansion(String itemName) {
    setState(() {
      _expandedBatches[itemName] = !(_expandedBatches[itemName] ?? false);
    });
  }

  // ── NEW: Show batch details dialog ───────────────────────────────────────
  void _showBatchDetails(Batch batch) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    final used = batch.usedQty;
    final pctUsed = batch.quantity > 0 ? used / batch.quantity : 0.0;
    final remainingValue = batch.remainingQty * batch.purchasePrice;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.inventory_2, color: _primaryColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                batch.batchNumber,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Item info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _primaryColor.withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch.itemName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _primaryColor,
                          fontSize: 15,
                        ),
                      ),
                      if (batch.length.isNotEmpty || batch.bodyType.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              if (batch.length.isNotEmpty) ...[
                                const Icon(Icons.straighten, size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(batch.length, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                const SizedBox(width: 12),
                              ],
                              if (batch.bodyType.isNotEmpty) ...[
                                const Icon(Icons.category, size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(batch.bodyType, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                _buildBatchDetailRow('Original Qty', '${batch.quantity.toStringAsFixed(2)} kg'),
                _buildBatchDetailRow('Remaining Qty', '${batch.remainingQty.toStringAsFixed(2)} kg',
                    color: batch.remainingQty <= 0 ? Colors.red : batch.remainingQty < 100 ? Colors.orange : Colors.green),
                _buildBatchDetailRow('Used Qty', '${used.toStringAsFixed(2)} kg', color: Colors.blueGrey),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pctUsed,
                    minHeight: 8,
                    backgroundColor: Colors.green[100],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.green[700]!),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${(pctUsed * 100).toStringAsFixed(1)}% consumed',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),

                _buildBatchDetailRow('Rate (Cost/kg)', '${batch.purchasePrice.toStringAsFixed(2)} PKR'),
                _buildBatchDetailRow('Remaining Value', '${remainingValue.toStringAsFixed(2)} PKR'),
                _buildBatchDetailRow('Vendor', batch.vendorName),
                _buildBatchDetailRow('Purchase Date', fmt.format(batch.purchaseDate)),
                if (batch.purchaseId.isNotEmpty)
                  _buildBatchDetailRow('Purchase ID', batch.purchaseId),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchDetailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const Text(': ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> fetchItems() async {
    _database.child('items').onValue.listen((event) {
      final Map? data = event.snapshot.value as Map?;
      if (data != null) {
        final fetchedItems = data.entries.map<Map<String, dynamic>>((entry) {
          final itemData = Map<String, dynamic>.from(entry.value as Map);
          itemData['key'] = entry.key;

          if (itemData['lengthBodyCombinations'] != null &&
              itemData['lengthBodyCombinations'] is List) {
            final combos = itemData['lengthBodyCombinations'] as List;
            for (int i = 0; i < combos.length; i++) {
              final key = '${entry.key}_$i';
              if (!_expandedCombinations.containsKey(key)) {
                _expandedCombinations[key] = 0.0;
              }
            }
          }

          return itemData;
        }).toList();

        setState(() {
          _items = fetchedItems;
          _filteredItems = fetchedItems;
        });
      }
    });
  }

  void _searchItems() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = _items.where((item) {
        String itemName = item['itemName']?.toString().toLowerCase() ?? '';
        String description = item['description']?.toString().toLowerCase() ?? '';
        return itemName.contains(query) || description.contains(query);
      }).toList();
    });
  }

  void _toggleCombinationExpansion(String itemKey, int index) {
    final key = '${itemKey}_$index';
    setState(() {
      _expandedCombinations[key] =
      (_expandedCombinations[key] == 1.0) ? 0.0 : 1.0;
    });
  }

  Future<pw.MemoryImage> _createTextImage(String text) async {
    final String displayText = text.isEmpty ? "N/A" : text;
    const double scaleFactor = 1.5;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromPoints(
        Offset(0, 0),
        Offset(500 * scaleFactor, 50 * scaleFactor),
      ),
    );

    final textStyle = TextStyle(
      fontSize: 12 * scaleFactor,
      fontFamily: 'JameelNoori',
      color: Colors.black,
      fontWeight: FontWeight.bold,
    );

    final textSpan = TextSpan(text: displayText, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.left,
      textDirection: ui.TextDirection.rtl,
    );

    textPainter.layout();
    final double width = textPainter.width * scaleFactor;
    final double height = textPainter.height * scaleFactor;

    if (width <= 0 || height <= 0) {
      throw Exception("Invalid text dimensions: width=$width, height=$height");
    }

    textPainter.paint(canvas, Offset(0, 0));
    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final buffer = byteData!.buffer.asUint8List();

    return pw.MemoryImage(buffer);
  }

  Future<void> _createPDFAndSave() async {
    final ByteData logoBytes = await rootBundle.load('assets/images/logo.png');
    final image = pw.MemoryImage(logoBytes.buffer.asUint8List());

    final pdf = pw.Document();
    List<pw.MemoryImage> descriptionImages = [];

    for (var row in _filteredItems) {
      final img = await _createTextImage(row['itemName']);
      descriptionImages.add(img);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Image(image, width: 100, height: 100),
              pw.Text('Items List',
                  style: pw.TextStyle(
                      fontSize: 20, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: [
              'Size',
              'Description',
              'Length-Body Combinations',
              'Avg Cost/Kg',
              'Avg Sale/Kg',
              '1Kg Profit',
              'Profit %',
              'Qty On Hand',
              'Batch Qty',
              'Batches',
              'Vendor',
            ],
            cellAlignment: pw.Alignment.centerLeft,
            data: _filteredItems.map((item) {
              String combosText = "";
              if (item['lengthBodyCombinations'] != null &&
                  item['lengthBodyCombinations'] is List) {
                final combos = item['lengthBodyCombinations'] as List;
                combosText = combos.map((combo) {
                  if (combo is Map) {
                    final map = Map<String, dynamic>.from(combo);
                    final stockQty =
                        (map['stockQuantity'] as num?)?.toDouble() ?? 0.0;
                    final stockUnit = map['stockUnit']?.toString() ?? 'kg';
                    String comboStr =
                        "Length: ${map['length'] ?? ''} (${map['lengthDecimal'] ?? ''})\n"
                        "Body: ${map['bodyType'] ?? ''}\n"
                        "Cost: ${map['costPricePerKg']?.toStringAsFixed(2) ?? '0.00'} | "
                        "Sale: ${map['salePricePerKg']?.toStringAsFixed(2) ?? '0.00'}\n"
                        "Stock: ${stockQty.toStringAsFixed(2)} $stockUnit";

                    if (map['customerPrices'] != null &&
                        (map['customerPrices'] as Map).isNotEmpty) {
                      final prices = map['customerPrices'] as Map;
                      final priceLines = prices.entries.map((e) {
                        final name =
                            customerIdNameMap[e.key.toString()] ?? e.key;
                        return "$name: ${e.value}";
                      }).join(", ");
                      comboStr += "\nCustomer Prices: $priceLines";
                    }
                    return comboStr;
                  }
                  return "";
                }).where((str) => str.isNotEmpty).join("\n\n");
              }

              double avgCost = item['avgCostPricePerKg']?.toDouble() ?? 0.0;
              double avgSale = item['avgSalePricePerKg']?.toDouble() ?? 0.0;
              double profitMargin = avgSale - avgCost;
              double profitPercentage =
              avgCost > 0 ? (profitMargin / avgCost) * 100 : 0.0;

              final batchQty = _getTotalBatchQty(item['itemName']?.toString() ?? '');
              final batchCount = _getBatchCount(item['itemName']?.toString() ?? '');

              return [
                item['itemName'].toString(),
                item['description']?.toString() ?? 'N/A',
                combosText.isNotEmpty ? combosText : 'N/A',
                avgCost.toStringAsFixed(2),
                avgSale.toStringAsFixed(2),
                profitMargin.toStringAsFixed(2),
                profitPercentage.toStringAsFixed(1) + '%',
                item['qtyOnHand']?.toString() ?? '0',
                batchQty.toStringAsFixed(2),
                batchCount.toString(),
                item['vendor']?.toString() ?? 'N/A',
              ];
            }).toList(),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    _pdfBytes = bytes;

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("PDF generated for web (use share button)")),
      );
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/items_list.pdf');
      await file.writeAsBytes(bytes);
      setState(() {
        _savedPdfPath = file.path;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("PDF saved to temporary folder")),
      );
    }
  }

  Future<void> _sharePDF() async {
    if (kIsWeb) {
      if (_pdfBytes == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Generate PDF first")));
        return;
      }
      await Printing.sharePdf(bytes: _pdfBytes!, filename: 'items_list.pdf');
    } else {
      if (_savedPdfPath == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Generate PDF first")));
        return;
      }
      await Share.shareXFiles([XFile(_savedPdfPath!)], text: 'Items List PDF');
    }
  }

  void updateItem(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RegisterItemPage(itemData: item),
      ),
    ).then((_) {
      fetchItems();
      _fetchAllBatches();
    });
  }

  void _confirmDelete(String key) {
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(languageProvider.isEnglish
              ? "Confirm Delete"
              : "حذف کرنے کی تصدیق کریں"),
          content: Text(languageProvider.isEnglish
              ? "Are you sure you want to delete this item?"
              : "کیا آپ واقعی اس آئٹم کو حذف کرنا چاہتے ہیں؟"),
          actions: <Widget>[
            TextButton(
              child: Text(
                  languageProvider.isEnglish ? "Cancel" : "منسوخ کریں",
                  style: TextStyle(color: Colors.teal)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text(
                  languageProvider.isEnglish ? "Delete" : "حذف کریں",
                  style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop();
                deleteItem(key);
              },
            ),
          ],
        );
      },
    );
  }

  void deleteItem(String key) {
    _database.child('items/$key').remove().then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Item deleted successfully!')),
      );
      setState(() {
        _selectedItem = null;
      });
    }).catchError((error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete item: $error')),
      );
    });
  }

  Future<List<Map<String, dynamic>>> _fetchItemTransactions(
      String itemKey) async {
    final database = FirebaseDatabase.instance.ref();
    List<Map<String, dynamic>> transactions = [];

    try {
      final purchaseSnapshot = await database.child('purchases').get();
      if (purchaseSnapshot.exists) {
        final purchases = purchaseSnapshot.value as Map<dynamic, dynamic>;
        purchases.forEach((purchaseKey, purchaseData) {
          if (purchaseData['items'] != null) {
            final items = purchaseData['items'] as List;
            for (var item in items) {
              if (item['itemName'] == _selectedItem!['itemName']) {
                transactions.add({
                  'type': 'Purchase',
                  'purchaseId': purchaseKey,
                  'date': purchaseData['timestamp'],
                  'quantity': item['quantity'],
                  'price': item['purchasePrice'],
                  'vendor': purchaseData['vendorName'] ?? 'Unknown Vendor',
                  'total': (item['quantity'] as num).toDouble() *
                      (item['purchasePrice'] as num).toDouble(),
                });
              }
            }
          }
        });
      }
      transactions.sort((a, b) => b['date'].compareTo(a['date']));
    } catch (e) {
      print('Error fetching transactions: $e');
    }

    return transactions;
  }

  Widget _buildPriceCard(String title, String value, Color color) {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          SizedBox(height: 4),
          Text("PKR $value",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LEFT PANEL: small stock chip shown on each item tile
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildItemStockChips(Map<String, dynamic> item) {
    final combos = item['lengthBodyCombinations'];
    if (combos == null || combos is! List || combos.isEmpty) return SizedBox();

    int outOfStock = 0;
    int lowStock = 0;
    double totalStock = 0;

    for (final c in combos) {
      if (c is Map) {
        final qty = (c['stockQuantity'] as num?)?.toDouble() ?? 0.0;
        final threshold = (c['lowStockThreshold'] as num?)?.toDouble() ?? 10.0;
        totalStock += qty;
        if (qty <= 0)
          outOfStock++;
        else if (qty <= threshold) lowStock++;
      }
    }

    Color chipColor = Colors.green;
    String chipLabel = '${totalStock.toStringAsFixed(1)} kg';
    if (outOfStock > 0) chipColor = Colors.red;
    else if (lowStock > 0) chipColor = Colors.orange;

    return Row(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: chipColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: chipColor.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2, size: 10, color: chipColor),
              SizedBox(width: 3),
              Text(
                chipLabel,
                style: TextStyle(
                    fontSize: 10,
                    color: chipColor,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        if (outOfStock > 0) ...[
          SizedBox(width: 4),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$outOfStock out',
              style: TextStyle(fontSize: 9, color: Colors.red[700]),
            ),
          ),
        ],
        if (lowStock > 0) ...[
          SizedBox(width: 4),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$lowStock low',
              style: TextStyle(fontSize: 9, color: Colors.orange[700]),
            ),
          ),
        ],
      ],
    );
  }

  // ── NEW: Batch section for an item (displayed in center panel) ───────────
  Widget _buildBatchSection(String itemName) {
    final batches = _batchesByItemName[itemName];
    if (batches == null || batches.isEmpty) {
      return SizedBox();
    }

    final isExpanded = _expandedBatches[itemName] ?? false;
    final totalBatchQty = batches.fold(0.0, (sum, b) => sum + b.remainingQty);
    final batchCount = batches.length;

    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.inventory, color: Colors.blue[700], size: 20),
            ),
            title: Text(
              'Batch Stock',
              style: TextStyle(fontWeight: FontWeight.bold, color: _primaryColor),
            ),
            subtitle: Text(
              '$batchCount batch(es) | Total: ${totalBatchQty.toStringAsFixed(2)} kg',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    totalBatchQty.toStringAsFixed(2),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => _toggleBatchExpansion(itemName),
                ),
              ],
            ),
          ),
          if (isExpanded)
            Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                children: batches.map((batch) {
                  return _buildBatchTile(batch);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ── NEW: Individual batch tile ───────────────────────────────────────────
  Widget _buildBatchTile(Batch batch) {
    final remaining = batch.remainingQty;
    final total = batch.quantity;
    final pctRemain = total > 0 ? remaining / total : 0.0;

    Color statusColor = Colors.green;
    if (remaining <= 0) statusColor = Colors.grey;
    else if (remaining < 100) statusColor = Colors.orange;

    return Card(
      margin: EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: () => _showBatchDetails(batch),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          batch.batchNumber,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _primaryColor,
                          ),
                        ),
                        if (batch.length.isNotEmpty || batch.bodyType.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                if (batch.length.isNotEmpty)
                                  Text(
                                    batch.length,
                                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                  ),
                                if (batch.length.isNotEmpty && batch.bodyType.isNotEmpty)
                                  SizedBox(width: 6),
                                if (batch.bodyType.isNotEmpty)
                                  Text(
                                    batch.bodyType,
                                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${remaining.toStringAsFixed(2)} kg',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pctRemain,
                  minHeight: 4,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
              ),
              SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Rate: ${batch.purchasePrice.toStringAsFixed(2)} PKR/kg',
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                  Text(
                    DateFormat('dd MMM yy').format(batch.purchaseDate),
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CENTER PANEL: combination list with stock
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildLengthBodyCombinations() {
    if (_selectedItem == null ||
        _selectedItem!['lengthBodyCombinations'] == null) {
      return SizedBox();
    }

    final combos = _selectedItem!['lengthBodyCombinations'] as List;
    if (combos.isEmpty) return SizedBox();

    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Length-Body Combinations (${combos.length})",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: _primaryColor),
                ),
                Text("Tap to expand details",
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            SizedBox(height: 8),

            // ── Stock overview bar ───────────────────────────────────────
            _buildCombinationsStockOverview(combos),
            SizedBox(height: 8),

            ...combos.asMap().entries.map((entry) {
              final index = entry.key;
              final combo = entry.value;
              if (combo is! Map) return SizedBox();

              final map = Map<String, dynamic>.from(combo);
              final itemKey = _selectedItem!['key'];
              final comboKey = '${itemKey}_$index';
              final isExpanded = _expandedCombinations[comboKey] == 1.0;

              final customerPricesMap = map['customerPrices'];
              final int customerPriceCount =
              (customerPricesMap is Map) ? customerPricesMap.length : 0;

              // Stock values
              final stockQty =
                  (map['stockQuantity'] as num?)?.toDouble() ?? 0.0;
              final lowThreshold =
                  (map['lowStockThreshold'] as num?)?.toDouble() ?? 10.0;
              final stockUnit = map['stockUnit']?.toString() ?? 'kg';
              final sColor = _stockColor(stockQty, lowThreshold);
              final sIcon = _stockIcon(stockQty, lowThreshold);
              final sLabel = _stockLabel(stockQty, lowThreshold);

              return Card(
                margin: EdgeInsets.symmetric(vertical: 4),
                elevation: 1,
                child: Column(
                  children: [
                    ListTile(
                      contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      leading: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "${index + 1}",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _primaryColor),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              "Length: ${map['length'] ?? ''}",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Body: ${map['bodyType'] ?? ''}",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (map['lengthDecimal'] != null &&
                              map['lengthDecimal'].toString().isNotEmpty)
                            Text(
                                "Length (Decimal): ${map['lengthDecimal']}"),

                          // ── Stock badge ──────────────────────────────
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Row(
                              children: [
                                Icon(sIcon, size: 14, color: sColor),
                                SizedBox(width: 4),
                                Text(
                                  '${stockQty.toStringAsFixed(2)} $stockUnit',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: sColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 6),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: sColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    sLabel,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: sColor,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  '(alert ≤ ${lowThreshold.toStringAsFixed(0)} $stockUnit)',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          ),

                          // Customer price badge
                          if (customerPriceCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Icon(Icons.people,
                                      size: 13, color: Colors.purple),
                                  SizedBox(width: 4),
                                  Text(
                                    "$customerPriceCount custom price(s)",
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.purple),
                                  ),
                                ],
                              ),
                            ),

                          if (isExpanded) _buildComboDetails(map),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (customerPriceCount > 0)
                            IconButton(
                              icon: Icon(Icons.people,
                                  color: Colors.purple, size: 20),
                              tooltip: 'View customer prices',
                              onPressed: () =>
                                  _showCombinationCustomerPrices(map, index),
                            ),
                          Icon(
                            isExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: _primaryColor,
                          ),
                        ],
                      ),
                      onTap: () =>
                          _toggleCombinationExpansion(itemKey, index),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  // ── Horizontal stock overview bar (all combos at a glance) ──────────────
  Widget _buildCombinationsStockOverview(List combos) {
    double totalStock = 0;
    int outOfStock = 0;
    int lowStock = 0;
    int inStock = 0;

    for (final c in combos) {
      if (c is Map) {
        final qty = (c['stockQuantity'] as num?)?.toDouble() ?? 0.0;
        final threshold = (c['lowStockThreshold'] as num?)?.toDouble() ?? 10.0;
        totalStock += qty;
        if (qty <= 0)
          outOfStock++;
        else if (qty <= threshold)
          lowStock++;
        else
          inStock++;
      }
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2, size: 16, color: _primaryColor),
          SizedBox(width: 8),
          Text(
            'Total Stock: ${totalStock.toStringAsFixed(2)} kg',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _primaryColor,
                fontSize: 13),
          ),
          Spacer(),
          if (inStock > 0) _buildOverviewChip('$inStock OK', Colors.green),
          if (lowStock > 0) ...[
            SizedBox(width: 4),
            _buildOverviewChip('$lowStock Low', Colors.orange),
          ],
          if (outOfStock > 0) ...[
            SizedBox(width: 4),
            _buildOverviewChip('$outOfStock Out', Colors.red),
          ],
        ],
      ),
    );
  }

  Widget _buildOverviewChip(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.bold)),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Expanded combo details — stock section at top + prices + customer prices
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildComboDetails(Map<String, dynamic> combo) {
    final costPrice = combo['costPricePerKg']?.toDouble() ?? 0.0;
    final salePrice = combo['salePricePerKg']?.toDouble() ?? 0.0;
    final profitMargin = salePrice - costPrice;
    final profitPercentage =
    costPrice > 0 ? (profitMargin / costPrice) * 100 : 0.0;

    final stockQty = (combo['stockQuantity'] as num?)?.toDouble() ?? 0.0;
    final lowThreshold =
        (combo['lowStockThreshold'] as num?)?.toDouble() ?? 10.0;
    final stockUnit = combo['stockUnit']?.toString() ?? 'kg';
    final sColor = _stockColor(stockQty, lowThreshold);
    final sIcon = _stockIcon(stockQty, lowThreshold);
    final sLabel = _stockLabel(stockQty, lowThreshold);

    final rawCustomerPrices = combo['customerPrices'];
    final Map<String, dynamic> customerPrices = {};
    if (rawCustomerPrices is Map) {
      rawCustomerPrices.forEach((k, v) {
        customerPrices[k.toString()] = v;
      });
    }

    return Container(
      margin: EdgeInsets.only(top: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Stock Status ──────────────────────────────────────────────
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: sColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: sColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(sIcon, size: 18, color: sColor),
                SizedBox(width: 8),
                Text(
                  'Stock: ${stockQty.toStringAsFixed(2)} $stockUnit',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: sColor,
                    fontSize: 13,
                  ),
                ),
                SizedBox(width: 8),
                Container(
                  padding:
                  EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: sColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    sLabel,
                    style: TextStyle(
                        fontSize: 11,
                        color: sColor,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Spacer(),
                Text(
                  'Alert ≤ ${lowThreshold.toStringAsFixed(0)} $stockUnit',
                  style:
                  TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),

          // ── Price Details ─────────────────────────────────────────────
          Text(
            "Price Details",
            style:
            TextStyle(fontWeight: FontWeight.bold, color: _primaryColor),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMiniPriceCard(
                  "Cost Price/Kg",
                  costPrice.toStringAsFixed(2),
                  Colors.blue[50]!,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _buildMiniPriceCard(
                  "Sale Price/Kg",
                  salePrice.toStringAsFixed(2),
                  Colors.green[50]!,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: profitMargin >= 0 ? Colors.green[50] : Colors.red[50],
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: profitMargin >= 0
                    ? Colors.green[100]!
                    : Colors.red[100]!,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Profit:",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: profitMargin >= 0
                        ? Colors.green[700]
                        : Colors.red[700],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "PKR ${profitMargin.toStringAsFixed(2)}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: profitMargin >= 0
                            ? Colors.green[700]
                            : Colors.red[700],
                      ),
                    ),
                    Text(
                      "${profitPercentage.toStringAsFixed(1)}%",
                      style: TextStyle(
                        fontSize: 12,
                        color: profitMargin >= 0
                            ? Colors.green[600]
                            : Colors.red[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Customer-Specific Prices ──────────────────────────────────
          if (customerPrices.isNotEmpty) ...[
            SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.people, size: 16, color: Colors.purple),
                SizedBox(width: 6),
                Text(
                  "Customer-Specific Prices",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.purple),
                ),
              ],
            ),
            SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: Colors.purple[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple[100]!),
              ),
              child: Column(
                children: customerPrices.entries.map((entry) {
                  final customerId = entry.key;
                  final price = entry.value;
                  final customerName =
                      customerIdNameMap[customerId] ??
                          'Customer ($customerId)';
                  final discount = salePrice > 0
                      ? salePrice -
                      (double.tryParse(price.toString()) ?? salePrice)
                      : 0.0;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    child: Row(
                      children: [
                        Icon(Icons.person,
                            size: 16, color: Colors.purple[300]),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(customerName,
                              style:
                              TextStyle(fontWeight: FontWeight.w500)),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "PKR $price /kg",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.purple[700],
                              ),
                            ),
                            if (discount != 0)
                              Text(
                                discount > 0
                                    ? "↓ ${discount.toStringAsFixed(2)} less"
                                    : "↑ ${(-discount).toStringAsFixed(2)} more",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: discount > 0
                                      ? Colors.orange[600]
                                      : Colors.green[600],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ] else ...[
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.people_outline, size: 14, color: Colors.grey),
                SizedBox(width: 4),
                Text(
                  "No customer-specific prices set",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Full-screen dialog: all customer prices for one combination
  // ─────────────────────────────────────────────────────────────────────────
  void _showCombinationCustomerPrices(
      Map<String, dynamic> combo, int index) {
    final rawCustomerPrices = combo['customerPrices'];
    final Map<String, dynamic> customerPrices = {};
    if (rawCustomerPrices is Map) {
      rawCustomerPrices.forEach(
              (k, v) => customerPrices[k.toString()] = v);
    }

    final salePrice = combo['salePricePerKg']?.toDouble() ?? 0.0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.people, color: Colors.purple),
                SizedBox(width: 8),
                Text("Customer Prices",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            Text(
              "${combo['length'] ?? ''} — ${combo['bodyType'] ?? ''}",
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: Colors.blue[700]),
                    SizedBox(width: 6),
                    Text(
                      "Default Sale Price: ${salePrice.toStringAsFixed(2)} PKR/kg",
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              customerPrices.isEmpty
                  ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  "No customer-specific prices set for this combination.",
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              )
                  : Container(
                constraints: BoxConstraints(maxHeight: 300),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: customerPrices.length,
                  separatorBuilder: (_, __) => Divider(height: 1),
                  itemBuilder: (context, i) {
                    final customerId =
                    customerPrices.keys.elementAt(i);
                    final price = customerPrices[customerId];
                    final customerName =
                        customerIdNameMap[customerId] ??
                            'Customer ($customerId)';
                    final parsedPrice =
                        double.tryParse(price.toString()) ?? salePrice;
                    final diff = salePrice - parsedPrice;

                    return ListTile(
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor:
                        Colors.purple.withOpacity(0.1),
                        child: Icon(Icons.person,
                            color: Colors.purple, size: 20),
                      ),
                      title: Text(customerName,
                          style:
                          TextStyle(fontWeight: FontWeight.bold)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.purple[50],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "PKR $price /kg",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.purple[700],
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (diff != 0)
                            Text(
                              diff > 0
                                  ? "↓ ${diff.toStringAsFixed(2)} less"
                                  : "↑ ${(-diff).toStringAsFixed(2)} more",
                              style: TextStyle(
                                fontSize: 10,
                                color: diff > 0
                                    ? Colors.orange[600]
                                    : Colors.green[600],
                              ),
                            ),
                        ],
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
            onPressed: () => Navigator.pop(context),
            child: Text("Close"),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniPriceCard(String title, String value, Color color) {
    return Container(
      padding: EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(title,
              style: TextStyle(fontSize: 10, color: Colors.grey[700])),
          SizedBox(height: 2),
          Text("PKR $value",
              style:
              TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // _showCustomerRates — per-combination breakdown
  // ─────────────────────────────────────────────────────────────────────────
  void _showCustomerRates(Map<String, dynamic> item) {
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);

    final combos = item['lengthBodyCombinations'];
    final List<Map<String, dynamic>> comboList = [];
    if (combos is List) {
      for (final c in combos) {
        if (c is Map) {
          final map = Map<String, dynamic>.from(c);
          final rawPrices = map['customerPrices'];
          if (rawPrices is Map && rawPrices.isNotEmpty) {
            comboList.add(map);
          }
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.attach_money, color: _secondaryColor),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                "${languageProvider.isEnglish ? 'Customer Prices for' : 'کسٹمر کی قیمتیں برائے'} ${item['itemName']}",
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: comboList.isEmpty
              ? Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              languageProvider.isEnglish
                  ? "No customer-specific prices set for any combination."
                  : "کسی مجموعے کے لیے کوئی مخصوص قیمتیں مقرر نہیں ہیں۔",
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          )
              : ListView.builder(
            shrinkWrap: true,
            itemCount: comboList.length,
            itemBuilder: (context, ci) {
              final combo = comboList[ci];
              final salePrice =
                  combo['salePricePerKg']?.toDouble() ?? 0.0;
              final rawPrices = combo['customerPrices'] as Map;
              final Map<String, dynamic> prices = {};
              rawPrices.forEach((k, v) => prices[k.toString()] = v);

              return Card(
                margin: EdgeInsets.symmetric(vertical: 6),
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "${combo['length'] ?? ''} — ${combo['bodyType'] ?? ''}",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _primaryColor,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            "Default: ${salePrice.toStringAsFixed(2)} PKR/kg",
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[700]),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Divider(height: 1),
                      ...prices.entries.map((entry) {
                        final customerId = entry.key;
                        final price = entry.value;
                        final customerName =
                            customerIdNameMap[customerId] ??
                                'Customer ($customerId)';
                        final parsedPrice =
                            double.tryParse(price.toString()) ??
                                salePrice;
                        final diff = salePrice - parsedPrice;

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 6, horizontal: 4),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor:
                                Colors.purple.withOpacity(0.1),
                                child: Icon(Icons.person,
                                    color: Colors.purple, size: 16),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(customerName,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w500)),
                              ),
                              Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.purple[50],
                                      borderRadius:
                                      BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      "PKR $price /kg",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple[700],
                                      ),
                                    ),
                                  ),
                                  if (diff != 0)
                                    Text(
                                      diff > 0
                                          ? "↓ ${diff.toStringAsFixed(2)} less"
                                          : "↑ ${(-diff).toStringAsFixed(2)} more",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: diff > 0
                                            ? Colors.orange[600]
                                            : Colors.green[600],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(languageProvider.isEnglish ? "Close" : "بند کریں"),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RIGHT PANEL: stock summary card
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildStockSummaryCard() {
    if (_selectedItem == null ||
        _selectedItem!['lengthBodyCombinations'] == null) {
      return SizedBox();
    }

    final combos = _selectedItem!['lengthBodyCombinations'] as List;
    double totalStock = 0;
    int outOfStock = 0;
    int lowStock = 0;
    int inStock = 0;

    for (final c in combos) {
      if (c is Map) {
        final qty = (c['stockQuantity'] as num?)?.toDouble() ?? 0.0;
        final threshold = (c['lowStockThreshold'] as num?)?.toDouble() ?? 10.0;
        totalStock += qty;
        if (qty <= 0)
          outOfStock++;
        else if (qty <= threshold)
          lowStock++;
        else
          inStock++;
      }
    }

    // Also get batch total
    final batchTotal = _getTotalBatchQty(_selectedItem!['itemName']?.toString() ?? '');
    final batchCount = _getBatchCount(_selectedItem!['itemName']?.toString() ?? '');

    Color overallColor = Colors.green;
    if (outOfStock > 0) overallColor = Colors.red;
    else if (lowStock > 0) overallColor = Colors.orange;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: overallColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child:
                  Icon(Icons.inventory_2, size: 16, color: overallColor),
                ),
                SizedBox(width: 8),
                Text(
                  'Stock Summary',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Text(
              '${totalStock.toStringAsFixed(2)} kg',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: overallColor),
            ),
            Text(
              'across ${combos.length} combination(s)',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            // ── Batch summary ──
            if (batchCount > 0) ...[
              SizedBox(height: 8),
              Divider(height: 1),
              SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.inventory, size: 14, color: Colors.blue),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Batch Stock: ${batchTotal.toStringAsFixed(2)} kg',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.blue[700],
                    ),
                  ),
                ],
              ),
              Text(
                '$batchCount active batch(es)',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
            SizedBox(height: 8),
            // Mini breakdown bars
            if (inStock > 0)
              _buildStockBreakdownRow('In Stock', inStock, Colors.green),
            if (lowStock > 0)
              _buildStockBreakdownRow('Low Stock', lowStock, Colors.orange),
            if (outOfStock > 0)
              _buildStockBreakdownRow('Out of Stock', outOfStock, Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildStockBreakdownRow(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
          Spacer(),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count combo${count > 1 ? 's' : ''}',
              style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Inventory Information'),
        actions: [
          IconButton(
              icon: Icon(Icons.picture_as_pdf, color: Colors.white),
              onPressed: _createPDFAndSave),
          IconButton(
              icon: Icon(Icons.share, color: Colors.white),
              onPressed: _sharePDF),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => StockReportPage()),
              );
            },
            icon: Icon(Icons.history, color: Colors.white),
          ),
          IconButton(
            onPressed: _fetchAllBatches,
            icon: Icon(Icons.refresh, color: Colors.white),
          ),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_primaryColor, _secondaryColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _backgroundColor.withOpacity(0.9),
              _backgroundColor
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Row(
          children: [
            // ── LEFT PANEL ─────────────────────────────────────────────────
            Expanded(
              flex: 2,
              child: Card(
                margin: EdgeInsets.all(8),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(12),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          labelText: 'Search Item',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: _cardColor,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = _filteredItems[index];
                          final itemName = item['itemName']?.toString() ?? '';
                          final combosCount =
                          item['lengthBodyCombinations'] != null
                              ? (item['lengthBodyCombinations'] as List)
                              .length
                              : 0;
                          final batchCount = _getBatchCount(itemName);
                          final batchQty = _getTotalBatchQty(itemName);

                          // Compute stock alert colour for left border
                          Color borderColor = Colors.grey[200]!;
                          if (item['lengthBodyCombinations'] != null &&
                              item['lengthBodyCombinations'] is List) {
                            final cs =
                            item['lengthBodyCombinations'] as List;
                            bool hasOut = false, hasLow = false;
                            for (final c in cs) {
                              if (c is Map) {
                                final q =
                                    (c['stockQuantity'] as num?)
                                        ?.toDouble() ??
                                        0.0;
                                final t =
                                    (c['lowStockThreshold'] as num?)
                                        ?.toDouble() ??
                                        10.0;
                                if (q <= 0) hasOut = true;
                                else if (q <= t) hasLow = true;
                              }
                            }
                            if (hasOut)
                              borderColor = Colors.red[300]!;
                            else if (hasLow)
                              borderColor = Colors.orange[300]!;
                            else if (cs.isNotEmpty)
                              borderColor = Colors.green[300]!;
                          }

                          return Card(
                            margin: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                  color: borderColor, width: 1.5),
                            ),
                            child: ListTile(
                              minVerticalPadding: 8,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              leading: SizedBox(
                                width: 35,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: combosCount > 0
                                            ? Colors.green[50]
                                            : Colors.grey[50],
                                        borderRadius:
                                        BorderRadius.circular(6),
                                        border: Border.all(
                                          color: combosCount > 0
                                              ? Colors.green[100]!
                                              : Colors.grey[200]!,
                                        ),
                                      ),
                                      child: Text(
                                        "$combosCount",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: combosCount > 0
                                              ? Colors.green[700]
                                              : Colors.grey[600],
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    if (batchCount > 0)
                                      Padding(
                                        padding: EdgeInsets.only(top: 2),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 3, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.blue[50],
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.blue[100]!),
                                          ),
                                          child: Text(
                                            "$batchCount",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue[700],
                                              fontSize: 9,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              title: Text(
                                item['itemName'] ?? '',
                                style: TextStyle(
                                    color: _textColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "Qty: ${item['qtyOnHand'] ?? 0}",
                                    style: TextStyle(
                                        color: _textColor.withOpacity(0.7),
                                        fontSize: 11),
                                  ),
                                  // const SizedBox(height: 2),
                                  // Stock chips (combinations)
                                  // _buildCompactStockChips(item),
                                  // Batch chip
                                  // if (batchCount > 0)
                                  //   Padding(
                                  //     padding: const EdgeInsets.only(top: 2),
                                  //     child: Container(
                                  //       padding: const EdgeInsets.symmetric(
                                  //           horizontal: 4, vertical: 1),
                                  //       decoration: BoxDecoration(
                                  //         color: Colors.blue.withOpacity(0.1),
                                  //         borderRadius: BorderRadius.circular(4),
                                  //       ),
                                  //       child: Row(
                                  //         mainAxisSize: MainAxisSize.min,
                                  //         children: [
                                  //           Icon(Icons.inventory,
                                  //               size: 8, color: Colors.blue),
                                  //           const SizedBox(width: 2),
                                  //           Text(
                                  //             '${batchQty.toStringAsFixed(1)} kg',
                                  //             style: const TextStyle(
                                  //                 fontSize: 9,
                                  //                 color: Colors.blue,
                                  //                 fontWeight: FontWeight.bold),
                                  //           ),
                                  //         ],
                                  //       ),
                                  //     ),
                                  //   ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_note,
                                        color: Colors.blue, size: 18),
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            EditQtyPage(itemData: item),
                                      ),
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 32),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red, size: 18),
                                    onPressed: () =>
                                        _confirmDelete(item['key']),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 32),
                                  ),
                                ],
                              ),
                              onTap: () async {
                                setState(() {
                                  _selectedItem = item;
                                  _isLoadingTransactions = true;
                                });
                                final transactions =
                                await _fetchItemTransactions(
                                    item['key']);
                                setState(() {
                                  _itemTransactions = transactions
                                      .where(
                                          (t) => t['type'] == 'Purchase')
                                      .toList();
                                  _isLoadingTransactions = false;
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── CENTER PANEL ───────────────────────────────────────────────
            Expanded(
              flex: 3,
              child: _selectedItem == null
                  ? Center(
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory,
                          size: 60,
                          color: _primaryColor.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Select an item to view details",
                          style: TextStyle(
                              color: _textColor, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Click on any item from the left panel",
                          style: TextStyle(
                              color: _textColor.withOpacity(0.6),
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              )
                  : Card(
                margin: EdgeInsets.all(8),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "Item Details",
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                        color: _primaryColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        if (_selectedItem!['isBOM'] == true)
                                          Padding(
                                            padding: EdgeInsets.only(right: 8),
                                            child: Chip(
                                              label: Text("BOM"),
                                              backgroundColor: Colors.blue[100],
                                            ),
                                          ),
                                        IconButton(
                                          icon: Icon(Icons.attach_money,
                                              color: _secondaryColor),
                                          tooltip: 'View customer prices per combination',
                                          onPressed: () => _showCustomerRates(_selectedItem!),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Divider(color: _primaryColor.withOpacity(0.3)),
                                const SizedBox(height: 16),

                                // Basic Info
                                Card(
                                  elevation: 2,
                                  margin: const EdgeInsets.only(bottom: 16),
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildDetailRow(
                                          "Size",
                                          _selectedItem!['itemName']?.toString() ?? 'N/A',
                                          isBold: true,
                                        ),
                                        _buildDetailRow(
                                          "Description",
                                          _selectedItem!['description']?.toString() ?? 'No description',
                                        ),
                                        _buildDetailRow(
                                          "Unit",
                                          _selectedItem!['unit']?.toString() ?? 'N/A',
                                        ),
                                        _buildDetailRow(
                                          "Quantity On Hand",
                                          _selectedItem!['qtyOnHand']?.toString() ?? '0',
                                        ),
                                        if (_selectedItem!['vendor'] != null)
                                          _buildDetailRow(
                                            "Vendor",
                                            _selectedItem!['vendor']?.toString() ?? 'N/A',
                                          ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Batch Section
                                _buildBatchSection(_selectedItem!['itemName']?.toString() ?? ''),

                                // Combinations
                                _buildLengthBodyCombinations(),

                                const SizedBox(height: 16),

                                // Average Price Summary - Fixed overflow
                                Container(
                                  padding: EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey[200]!),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min, // Added to prevent overflow
                                    children: [
                                      Text(
                                        "Average Price Summary",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: _primaryColor,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        "Based on ${_selectedItem!['lengthBodyCombinations'] != null ? (_selectedItem!['lengthBodyCombinations'] as List).length : 0} combination(s)",
                                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildPriceCard(
                                              "Avg Cost/Kg",
                                              _selectedItem!['avgCostPricePerKg']?.toStringAsFixed(2) ?? '0.00',
                                              Colors.blue[50]!,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: _buildPriceCard(
                                              "Avg Sale/Kg",
                                              _selectedItem!['avgSalePricePerKg']?.toStringAsFixed(2) ?? '0.00',
                                              Colors.green[50]!,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),

                                      // Profit Analysis - Fixed with SingleChildScrollView for horizontal scrolling if needed
                                      if (_selectedItem!['profitPercentage1kg'] != null)
                                        Container(
                                          padding: EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.orange[50],
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min, // Critical for preventing overflow
                                            children: [
                                              Text(
                                                "Profit Analysis",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.orange[700],
                                                  fontSize: 13, // Slightly reduced
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              // Use Wrap instead of Row for better responsiveness
                                              Wrap(
                                                spacing: 16,
                                                runSpacing: 8,
                                                children: [
                                                  // 1 Kg profit
                                                  Container(
                                                    width: 120, // Fixed width for consistency
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Text(
                                                          "1 Kg",
                                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Text(
                                                          "PKR ${_selectedItem!['profitMargin1kg']?.toStringAsFixed(2) ?? '0.00'}",
                                                          style: TextStyle(
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 12,
                                                            color: (_selectedItem!['profitMargin1kg'] ?? 0) >= 0
                                                                ? Colors.green
                                                                : Colors.red,
                                                          ),
                                                        ),
                                                        Text(
                                                          "${_selectedItem!['profitPercentage1kg']?.toStringAsFixed(1)}%",
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color: (_selectedItem!['profitPercentage1kg'] ?? 0) >= 0
                                                                ? Colors.green
                                                                : Colors.red,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  // 50 Kg profit
                                                  Container(
                                                    width: 120, // Fixed width for consistency
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Text(
                                                          "50 Kg",
                                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Text(
                                                          "PKR ${_selectedItem!['profitMargin50kg']?.toStringAsFixed(2) ?? '0.00'}",
                                                          style: TextStyle(
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 12,
                                                            color: (_selectedItem!['profitMargin50kg'] ?? 0) >= 0
                                                                ? Colors.green
                                                                : Colors.red,
                                                          ),
                                                        ),
                                                        Text(
                                                          "${_selectedItem!['profitPercentage50kg']?.toStringAsFixed(1)}%",
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color: (_selectedItem!['profitPercentage50kg'] ?? 0) >= 0
                                                                ? Colors.green
                                                                : Colors.red,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),

                                // BOM Components
                                if (_selectedItem!['isBOM'] == true && _selectedItem!['components'] != null) ...[
                                  const SizedBox(height: 16),
                                  Card(
                                    elevation: 2,
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min, // Added
                                        children: [
                                          Text(
                                            "BOM Components:",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: _primaryColor,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            height: 150,
                                            decoration: BoxDecoration(
                                              border: Border.all(color: Colors.grey[300]!),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: ListView.builder(
                                              padding: EdgeInsets.all(8),
                                              itemCount: _selectedItem!['components'].length,
                                              itemBuilder: (context, index) {
                                                final component = _selectedItem!['components'][index];
                                                return Card(
                                                  margin: EdgeInsets.symmetric(vertical: 4),
                                                  elevation: 1,
                                                  child: ListTile(
                                                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                                                    title: Text(component['name'] ?? 'Unnamed'),
                                                    subtitle: Text('${component['quantity']} ${component['unit']}'),
                                                    trailing: Text('${(component['price'] * component['quantity']).toStringAsFixed(2)} PKR'),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            "Total BOM Cost: PKR ${_selectedItem!['costPrice']?.toStringAsFixed(2) ?? '0.00'}",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue[700],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],

                                const Spacer(),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _primaryColor,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.edit, size: 16),
                                          SizedBox(width: 4),
                                          Text("Edit Item"),
                                        ],
                                      ),
                                      onPressed: () => updateItem(_selectedItem!),
                                    ),
                                    const SizedBox(width: 10),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.delete, size: 16),
                                          SizedBox(width: 4),
                                          Text("Delete"),
                                        ],
                                      ),
                                      onPressed: () => _confirmDelete(_selectedItem!['key']),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // ── RIGHT PANEL ────────────────────────────────────────────────
            Expanded(
              flex: 2,
              child: SingleChildScrollView(
                child: Card(
                  margin: EdgeInsets.all(8),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      Text("Item Image",
                          style: TextStyle(
                              color: _primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 18)),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: () {
                          if (_selectedItem != null &&
                              _selectedItem!['image'] != null) {
                            _showImagePreview(
                                context, _selectedItem!['image']);
                          }
                        },
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            color: _cardColor,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.3),
                                blurRadius: 5,
                                spreadRadius: 2,
                              )
                            ],
                            image: _selectedItem != null &&
                                _selectedItem!['image'] != null
                                ? DecorationImage(
                              image: MemoryImage(base64Decode(
                                  _selectedItem!['image'])),
                              fit: BoxFit.cover,
                            )
                                : null,
                          ),
                          child: _selectedItem != null &&
                              _selectedItem!['image'] != null
                              ? null
                              : Column(
                            mainAxisAlignment:
                            MainAxisAlignment.center,
                            children: [
                              Icon(Icons.image,
                                  size: 60, color: _secondaryColor),
                              const SizedBox(height: 8),
                              Text("No Image",
                                  style: TextStyle(
                                      color: _secondaryColor,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_selectedItem != null)
                        _buildStatCard(
                          "Stock Value",
                          "PKR ${((_selectedItem!['qtyOnHand'] ?? 0) * (_selectedItem!['avgSalePricePerKg'] ?? _selectedItem!['salePrice1kg'] ?? 0)).toStringAsFixed(2)}",
                        ),
                      const SizedBox(height: 10),
                      if (_selectedItem != null &&
                          _selectedItem!['lengthBodyCombinations'] != null)
                        _buildStatCard(
                          "Combinations",
                          "${(_selectedItem!['lengthBodyCombinations'] as List).length}",
                          icon: Icons.layers,
                          color: Colors.purple,
                        ),
                      const SizedBox(height: 10),

                      // Stock Summary card
                      _buildStockSummaryCard(),
                      const SizedBox(height: 10),

                      if (_selectedItem != null)
                        _buildStatCard(
                          "Avg Profit %",
                          "${_selectedItem!['profitPercentage1kg']?.toStringAsFixed(1) ?? '0.0'}%",
                          icon: Icons.trending_up,
                          color: (_selectedItem!['profitPercentage1kg'] ?? 0) >= 0
                              ? Colors.green
                              : Colors.red,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              blurRadius: 8,
              spreadRadius: 2,
            )
          ],
        ),
        padding: EdgeInsets.all(12),
        height: 250,
        child: DefaultTabController(
          length: 3,
          child: Column(
            children: [
              TabBar(
                labelColor: _primaryColor,
                unselectedLabelColor: _textColor.withOpacity(0.6),
                indicatorColor: _primaryColor,
                tabs: const [
                  Tab(text: 'Purchases'),
                  Tab(text: 'BOM Builds'),
                  Tab(text: 'Sales'),
                ],
              ),
              Divider(color: _primaryColor.withOpacity(0.3)),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildPurchaseReportsTab(),
                    _buildBomBuildsTab(),
                    _buildSalesTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: _primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => RegisterItemPage()),
          ).then((_) {
            fetchItems();
            _fetchAllBatches();
          });
        },
      ),
    );
  }

// Helper method for compact stock chips to prevent overflow
  Widget _buildCompactStockChips(Map<String, dynamic> item) {
    final combinations = item['lengthBodyCombinations'];
    if (combinations == null || combinations.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: combinations.map<Widget>((combo) {
        final qty = (combo['stockQuantity'] as num?)?.toDouble() ?? 0;
        final threshold = (combo['lowStockThreshold'] as num?)?.toDouble() ?? 10;

        Color chipColor;
        if (qty <= 0) {
          chipColor = Colors.red[100]!;
        } else if (qty <= threshold) {
          chipColor = Colors.orange[100]!;
        } else {
          chipColor = Colors.green[100]!;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: chipColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${combo['length'] ?? 'N/A'} - ${combo['body'] ?? 'N/A'}: ${qty.toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 9),
          ),
        );
      }).toList(),
    );
  }

  // ── All remaining helper methods (unchanged) ──────────────────────────────

  Widget _buildSalesTab() {
    return FutureBuilder(
      future: _fetchItemSales(_selectedItem?['key']),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(child: Text("No sales records for this item"));
        }
        final sales = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text("Sales Reports",
                    style: TextStyle(
                        color: _primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                Spacer(),
                IconButton(
                    onPressed: () => _showSalesReport(sales),
                    icon: Icon(Icons.details, color: _secondaryColor)),
              ],
            ),
            Divider(color: _primaryColor.withOpacity(0.3)),
            Expanded(
              child: ListView.builder(
                itemCount: min(3, sales.length),
                itemBuilder: (context, index) {
                  final sale = sales[index];
                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      contentPadding:
                      EdgeInsets.symmetric(horizontal: 12),
                      leading: Icon(Icons.sell, color: Colors.blue),
                      title:
                      Text(sale['customerName'] ?? 'Unknown Customer'),
                      subtitle: Text(DateFormat.yMMMd()
                          .add_jm()
                          .format(DateTime.fromMillisecondsSinceEpoch(
                          sale['date']))),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${sale['quantity']} @ ${sale['price']}'),
                          Text('${sale['total'].toStringAsFixed(2)} PKR'),
                        ],
                      ),
                      onTap: () => _showSaleDetails(sale),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _showSaleDetails(Map<String, dynamic> sale) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Sale Details"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSaleDetailRow(
                  "Customer", sale['customerName'] ?? 'Unknown'),
              _buildSaleDetailRow(
                  "Date",
                  DateFormat.yMMMd().add_jm().format(sale['date'] is int
                      ? DateTime.fromMillisecondsSinceEpoch(sale['date'])
                      : DateTime.parse(sale['date']))),
              _buildSaleDetailRow(
                  "Invoice #", sale['filledNumber'] ?? 'N/A'),
              _buildSaleDetailRow(
                  "Item", _selectedItem?['itemName'] ?? 'N/A'),
              _buildSaleDetailRow(
                  "Quantity", sale['quantity'].toString()),
              _buildSaleDetailRow("Price", sale['price'].toString()),
              _buildSaleDetailRow(
                  "Total", '${sale['total'].toStringAsFixed(2)} PKR'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close")),
        ],
      ),
    );
  }

  Widget _buildSaleDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 80,
              child: Text("$label:",
                  style: TextStyle(fontWeight: FontWeight.bold))),
          SizedBox(width: 10),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchItemSales(String? itemKey) async {
    if (itemKey == null) return [];
    final database = FirebaseDatabase.instance.ref();
    List<Map<String, dynamic>> sales = [];
    try {
      final salesSnapshot = await database.child('filled').get();
      if (salesSnapshot.exists) {
        final allSales = salesSnapshot.value;
        if (allSales is Map) {
          allSales
              .forEach((saleKey, saleData) => _processSaleData(saleData, sales));
        } else if (allSales is List) {
          for (var saleData in allSales) {
            _processSaleData(saleData, sales);
          }
        }
      }
      sales.sort((a, b) {
        DateTime dtA = a['date'] is int
            ? DateTime.fromMillisecondsSinceEpoch(a['date'])
            : DateTime.parse(a['date'].toString());
        DateTime dtB = b['date'] is int
            ? DateTime.fromMillisecondsSinceEpoch(b['date'])
            : DateTime.parse(b['date'].toString());
        return dtB.compareTo(dtA);
      });
    } catch (e) {
      print('Error fetching sales: $e');
    }
    return sales;
  }

  void _processSaleData(
      dynamic saleData, List<Map<String, dynamic>> sales) {
    try {
      final saleMap =
      saleData is Map ? Map<String, dynamic>.from(saleData) : {};
      if (saleMap['items'] != null) {
        final items = saleMap['items'] is List ? saleMap['items'] : [];
        for (var item in items) {
          if (item is Map &&
              item['itemName'] == _selectedItem!['itemName']) {
            String customerName = 'Unknown Customer';
            if (saleMap['customerName'] != null) {
              customerName = saleMap['customerName'].toString();
            } else if (saleMap['customerId'] != null) {
              customerName = "Customer ID: ${saleMap['customerId']}";
            }
            dynamic dateValue =
                saleMap['createdAt'] ?? saleMap['timestamp'];
            DateTime saleDate;
            if (dateValue is int) {
              saleDate = DateTime.fromMillisecondsSinceEpoch(dateValue);
            } else if (dateValue is String) {
              saleDate = DateTime.tryParse(dateValue) ?? DateTime.now();
            } else {
              saleDate = DateTime.now();
            }
            sales.add({
              'type': 'Sale',
              'date': saleDate.millisecondsSinceEpoch,
              'quantity': item['qty'] ?? 0,
              'price': item['rate'] ?? 0,
              'customerName': customerName,
              'total': (item['total'] ??
                  (item['qty'] ?? 0) * (item['rate'] ?? 0))
                  .toDouble(),
              'filledNumber': saleMap['filledNumber']?.toString() ?? '',
            });
          }
        }
      }
    } catch (e) {
      print('Error processing sale data: $e');
    }
  }

  void _showSalesReport(List<Map<String, dynamic>> sales) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text("Sales Report: ${_selectedItem?['itemName']}",
                style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: sales.length,
                itemBuilder: (context, index) {
                  final sale = sales[index];
                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      contentPadding:
                      EdgeInsets.symmetric(horizontal: 12),
                      leading: Icon(Icons.sell, color: Colors.blue),
                      title: Text(
                          sale['customerName'] ?? 'Unknown Customer'),
                      subtitle: Text(DateFormat.yMMMd().add_jm().format(
                          sale['date'] is int
                              ? DateTime.fromMillisecondsSinceEpoch(
                              sale['date'])
                              : DateTime.parse(sale['date']))),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${sale['quantity']} @ ${sale['price']}'),
                          Text('${sale['total'].toStringAsFixed(2)} PKR'),
                        ],
                      ),
                      onTap: () => _showSaleDetails(sale),
                    ),
                  );
                },
              ),
            ),
            Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Total Sold:",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                    "${sales.fold(0.0, (sum, sale) => sum + (sale['quantity'] as num).toDouble()).toStringAsFixed(2)} units",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Total Revenue:",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                    "${sales.fold(0.0, (sum, sale) => sum + (sale['total'] as num).toDouble()).toStringAsFixed(2)} PKR",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchaseReportsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text("Purchase Reports",
                style: TextStyle(
                    color: _primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            Spacer(),
            IconButton(
                onPressed: _showPurchaseReport,
                icon: Icon(Icons.details, color: _secondaryColor)),
          ],
        ),
        Divider(color: _primaryColor.withOpacity(0.3)),
        Expanded(
          child: _isLoadingTransactions
              ? Center(child: CircularProgressIndicator())
              : _itemTransactions.isEmpty
              ? Center(
            child: Text(
              "No purchase records for this item",
              style: TextStyle(
                  color: _textColor.withOpacity(0.6)),
            ),
          )
              : ListView.builder(
            itemCount: min(3, _itemTransactions.length),
            itemBuilder: (context, index) {
              final txn = _itemTransactions[index];
              return Card(
                margin: EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  contentPadding:
                  EdgeInsets.symmetric(horizontal: 8),
                  leading: Icon(Icons.shopping_cart,
                      color: Colors.green),
                  title: Text(txn['vendor']),
                  subtitle: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(DateFormat('MMM dd, yyyy').format(
                          DateTime.parse(txn['date']))),
                      Text(
                          'Qty: ${txn['quantity']} @ ${txn['price']}'),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment:
                    MainAxisAlignment.center,
                    crossAxisAlignment:
                    CrossAxisAlignment.end,
                    children: [
                      Text(
                          '${txn['total'].toStringAsFixed(2)} PKR'),
                      SizedBox(height: 4),
                      Text('View Details',
                          style: TextStyle(
                              color: Colors.blue,
                              fontSize: 10)),
                    ],
                  ),
                  onTap: () => _showPurchaseDetails(txn),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBomBuildsTab() {
    return FutureBuilder(
      future: _fetchBomBuilds(_selectedItem?['key']),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
              child: Text("No BOM build records for this item",
                  style: TextStyle(color: _textColor.withOpacity(0.6))));
        }
        final builds = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text("BOM Build History",
                    style: TextStyle(
                        color: _primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                Spacer(),
                IconButton(
                    onPressed: () => _showBomBuildReport(builds),
                    icon: Icon(Icons.details, color: _secondaryColor)),
              ],
            ),
            Divider(color: _primaryColor.withOpacity(0.3)),
            Expanded(
              child: ListView.builder(
                itemCount: min(3, builds.length),
                itemBuilder: (context, index) {
                  final build = builds[index];
                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      contentPadding:
                      EdgeInsets.symmetric(horizontal: 8),
                      leading: Icon(Icons.build, color: Colors.blue),
                      title: Text('Built ${build['quantityBuilt']} units'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(DateFormat('MMM dd, yyyy').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                  build['timestamp']))),
                          if (build['components'] != null &&
                              build['components'].isNotEmpty)
                            Text(
                                'Used ${build['components'].length} components'),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          SizedBox(height: 4),
                          Text('View Details',
                              style: TextStyle(
                                  color: Colors.blue, fontSize: 10)),
                        ],
                      ),
                      onTap: () => _showBomBuildDetails(build),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchBomBuilds(String? itemKey) async {
    if (itemKey == null) return [];
    final database = FirebaseDatabase.instance.ref();
    List<Map<String, dynamic>> builds = [];
    try {
      final snapshot = await database
          .child('buildTransactions')
          .orderByChild('bomItemKey')
          .equalTo(itemKey)
          .get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          final build =
          Map<String, dynamic>.from(value as Map<dynamic, dynamic>);
          build['key'] = key;
          builds.add(build);
        });
        builds.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
      }
    } catch (e) {
      print('Error fetching BOM builds: $e');
    }
    return builds;
  }

  void _showBomBuildDetails(Map<String, dynamic> build) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("BOM Build Details"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow("Item", build['bomItemName'] ?? 'N/A'),
              _buildDetailRow(
                  "Quantity Built", build['quantityBuilt'].toString()),
              _buildDetailRow(
                  "Date",
                  DateFormat.yMMMd().add_jm().format(
                      DateTime.fromMillisecondsSinceEpoch(
                          build['timestamp']))),
              SizedBox(height: 16),
              Text("Components Used:",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...(build['components'] as List?)
                  ?.map<Widget>((component) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                          flex: 2,
                          child: Text(
                              component['name'] ?? 'Unknown')),
                      Expanded(
                          child: Text(
                              '${component['quantityUsed']} ${component['unit']}')),
                    ],
                  ),
                );
              }).toList() ??
                  [Text("No component data")],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close")),
        ],
      ),
    );
  }

  void _showBomBuildReport(List<Map<String, dynamic>> builds) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text("BOM Build Report: ${_selectedItem?['itemName']}",
                style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: builds.length,
                itemBuilder: (context, index) {
                  final build = builds[index];
                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      contentPadding:
                      EdgeInsets.symmetric(horizontal: 12),
                      leading: Icon(Icons.build, color: Colors.blue),
                      title:
                      Text('Built ${build['quantityBuilt']} units'),
                      subtitle: Text(DateFormat.yMMMd().add_jm().format(
                          DateTime.fromMillisecondsSinceEpoch(
                              build['timestamp']))),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                              '${build['components']?.length ?? 0} components'),
                          Text('View',
                              style: TextStyle(
                                  color: Colors.blue, fontSize: 10)),
                        ],
                      ),
                      onTap: () => _showBomBuildDetails(build),
                    ),
                  );
                },
              ),
            ),
            Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Total Built:",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                    "${builds.fold(0, (sum, build) => sum + (build['quantityBuilt'] as num).toInt())} units",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPurchaseDetails(Map<String, dynamic> purchase) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Purchase Details"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPurchaseDetailRow(
                  "Date",
                  DateFormat.yMMMd()
                      .add_jm()
                      .format(DateTime.parse(purchase['date']))),
              _buildPurchaseDetailRow("Vendor", purchase['vendor']),
              _buildPurchaseDetailRow(
                  "Item", _selectedItem?['itemName'] ?? ''),
              _buildPurchaseDetailRow(
                  "Quantity", purchase['quantity'].toString()),
              _buildPurchaseDetailRow(
                  "Price", purchase['price'].toString()),
              _buildPurchaseDetailRow(
                  "Total",
                  '${purchase['total'].toStringAsFixed(2)} PKR'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close")),
        ],
      ),
    );
  }

  Widget _buildPurchaseDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 80,
              child: Text("$label:",
                  style: TextStyle(fontWeight: FontWeight.bold))),
          SizedBox(width: 10),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _showPurchaseReport() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text("Purchase Report: ${_selectedItem?['itemName']}",
                style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: _itemTransactions.length,
                itemBuilder: (context, index) {
                  final txn = _itemTransactions[index];
                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      contentPadding:
                      EdgeInsets.symmetric(horizontal: 12),
                      leading: Icon(Icons.shopping_cart,
                          color: Colors.green),
                      title: Text(txn['vendor']),
                      subtitle: Text(DateFormat.yMMMd()
                          .add_jm()
                          .format(DateTime.parse(txn['date']))),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${txn['quantity']} @ ${txn['price']}'),
                          Text(
                              '${txn['total'].toStringAsFixed(2)} PKR'),
                        ],
                      ),
                      onTap: () => _showPurchaseDetails(txn),
                    ),
                  );
                },
              ),
            ),
            Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Total Purchases:",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                    "${_calculateTotalPurchases().toStringAsFixed(2)} PKR",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _calculateTotalPurchases() {
    return _itemTransactions.fold(
        0.0, (sum, txn) => sum + (txn['total'] as double));
  }

  void _showImagePreview(BuildContext context, String imageBase64) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(20),
        child: Stack(
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4,
              child: kIsWeb
                  ? Image.network('data:image/png;base64,$imageBase64')
                  : Image.memory(base64Decode(imageBase64)),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value,
      {IconData? icon, Color? color}) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8),
      elevation: 2,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            if (icon != null)
              Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (color ?? _primaryColor).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon,
                    size: 20, color: color ?? _primaryColor),
              ),
            if (icon != null) SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: _textColor.withOpacity(0.7),
                          fontSize: 12)),
                  SizedBox(height: 4),
                  Text(value,
                      style: TextStyle(
                          color: color ?? _primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value,
      {double fontSize = 18.0, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text("$label:",
                style: TextStyle(
                    color: _textColor,
                    fontWeight:
                    isBold ? FontWeight.bold : FontWeight.normal,
                    fontSize: fontSize)),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(value.isNotEmpty ? value : 'N/A',
                style: TextStyle(
                    color: _textColor.withOpacity(0.8),
                    fontSize: fontSize,
                    fontWeight:
                    isBold ? FontWeight.bold : FontWeight.normal)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}