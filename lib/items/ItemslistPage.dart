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
    _searchController.addListener(_searchItems);
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
                    String comboStr =
                        "Length: ${map['length'] ?? ''} (${map['lengthDecimal'] ?? ''})\n"
                        "Body: ${map['bodyType'] ?? ''}\n"
                        "Cost: ${map['costPricePerKg']?.toStringAsFixed(2) ?? '0.00'} | "
                        "Sale: ${map['salePricePerKg']?.toStringAsFixed(2) ?? '0.00'}";

                    // Add per-combination customer prices to PDF
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

              double avgCost =
                  item['avgCostPricePerKg']?.toDouble() ?? 0.0;
              double avgSale =
                  item['avgSalePricePerKg']?.toDouble() ?? 0.0;
              double profitMargin = avgSale - avgCost;
              double profitPercentage =
              avgCost > 0 ? (profitMargin / avgCost) * 100 : 0.0;

              return [
                item['itemName'].toString(),
                item['description']?.toString() ?? 'N/A',
                combosText.isNotEmpty ? combosText : 'N/A',
                avgCost.toStringAsFixed(2),
                avgSale.toStringAsFixed(2),
                profitMargin.toStringAsFixed(2),
                profitPercentage.toStringAsFixed(1) + '%',
                item['qtyOnHand']?.toString() ?? '0',
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
      await Printing.sharePdf(
          bytes: _pdfBytes!, filename: 'items_list.pdf');
    } else {
      if (_savedPdfPath == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Generate PDF first")));
        return;
      }
      await Share.shareXFiles([XFile(_savedPdfPath!)],
          text: 'Items List PDF');
    }
  }

  void updateItem(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RegisterItemPage(itemData: item),
      ),
    ).then((_) => fetchItems());
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
        final purchases =
        purchaseSnapshot.value as Map<dynamic, dynamic>;
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
                  'vendor':
                  purchaseData['vendorName'] ?? 'Unknown Vendor',
                  'total':
                  (item['quantity'] as num).toDouble() *
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
              style:
              TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Combination list in detail panel
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
                    style:
                    TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            SizedBox(height: 8),
            ...combos.asMap().entries.map((entry) {
              final index = entry.key;
              final combo = entry.value;
              if (combo is! Map) return SizedBox();

              final map = Map<String, dynamic>.from(combo);
              final itemKey = _selectedItem!['key'];
              final comboKey = '${itemKey}_$index';
              final isExpanded =
                  _expandedCombinations[comboKey] == 1.0;

              // Count custom customer prices for this combo
              final customerPricesMap = map['customerPrices'];
              final int customerPriceCount =
              (customerPricesMap is Map)
                  ? customerPricesMap.length
                  : 0;

              return Card(
                margin: EdgeInsets.symmetric(vertical: 4),
                elevation: 1,
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      leading: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                          _primaryColor.withOpacity(0.1),
                          borderRadius:
                          BorderRadius.circular(8),
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
                              style: TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Body: ${map['bodyType'] ?? ''}",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          if (map['lengthDecimal'] != null &&
                              map['lengthDecimal']
                                  .toString()
                                  .isNotEmpty)
                            Text(
                                "Length (Decimal): ${map['lengthDecimal']}"),
                          // Purple badge for custom customer prices
                          if (customerPriceCount > 0)
                            Padding(
                              padding:
                              const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Icon(Icons.people,
                                      size: 13,
                                      color: Colors.purple),
                                  SizedBox(width: 4),
                                  Text(
                                    "$customerPriceCount custom price(s)",
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.purple),
                                  ),
                                ],
                              ),
                            ),
                          if (isExpanded)
                            _buildComboDetails(map),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Dedicated button to view customer prices
                          if (customerPriceCount > 0)
                            IconButton(
                              icon: Icon(Icons.people,
                                  color: Colors.purple, size: 20),
                              tooltip: 'View customer prices',
                              onPressed: () =>
                                  _showCombinationCustomerPrices(
                                    map,
                                    index,
                                  ),
                            ),
                          Icon(
                            isExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: _primaryColor,
                          ),
                        ],
                      ),
                      onTap: () => _toggleCombinationExpansion(
                          itemKey, index),
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

  // ─────────────────────────────────────────────────────────────────────────
  // Expanded combo details — now includes customer prices section
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildComboDetails(Map<String, dynamic> combo) {
    final costPrice = combo['costPricePerKg']?.toDouble() ?? 0.0;
    final salePrice = combo['salePricePerKg']?.toDouble() ?? 0.0;
    final profitMargin = salePrice - costPrice;
    final profitPercentage =
    costPrice > 0 ? (profitMargin / costPrice) * 100 : 0.0;

    // Parse customer prices for this combination
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
          // ── Price Details ──
          Text(
            "Price Details",
            style: TextStyle(
                fontWeight: FontWeight.bold, color: _primaryColor),
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
              color: profitMargin >= 0
                  ? Colors.green[50]
                  : Colors.red[50],
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

          // ── Customer-Specific Prices ──
          if (customerPrices.isNotEmpty) ...[
            SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.people, size: 16, color: Colors.purple),
                SizedBox(width: 6),
                Text(
                  "Customer-Specific Prices",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.purple,
                  ),
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
                      (double.tryParse(price.toString()) ??
                          salePrice)
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
                          child: Text(
                            customerName,
                            style: TextStyle(
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                        Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.end,
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
                Icon(Icons.people_outline,
                    size: 14, color: Colors.grey),
                SizedBox(width: 4),
                Text(
                  "No customer-specific prices set",
                  style:
                  TextStyle(fontSize: 12, color: Colors.grey),
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
              style:
              TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Default price banner
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
                  style:
                  TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              )
                  : Container(
                constraints: BoxConstraints(maxHeight: 300),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: customerPrices.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1),
                  itemBuilder: (context, i) {
                    final customerId =
                    customerPrices.keys.elementAt(i);
                    final price =
                    customerPrices[customerId];
                    final customerName =
                        customerIdNameMap[customerId] ??
                            'Customer ($customerId)';
                    final parsedPrice =
                        double.tryParse(price.toString()) ??
                            salePrice;
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
                      title: Text(
                        customerName,
                        style: TextStyle(
                            fontWeight: FontWeight.bold),
                      ),
                      trailing: Column(
                        mainAxisAlignment:
                        MainAxisAlignment.center,
                        crossAxisAlignment:
                        CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.purple[50],
                              borderRadius:
                              BorderRadius.circular(6),
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
                                  ? "↓ ${diff.toStringAsFixed(2)} less than default"
                                  : "↑ ${(-diff).toStringAsFixed(2)} more than default",
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

  Widget _buildMiniPriceCard(
      String title, String value, Color color) {
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
              style: TextStyle(
                  fontSize: 10, color: Colors.grey[700])),
          SizedBox(height: 2),
          Text("PKR $value",
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // _showCustomerRates — now shows per-combination breakdown
  // ─────────────────────────────────────────────────────────────────────────
  void _showCustomerRates(Map<String, dynamic> item) {
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);

    // Collect all combination-level customer prices
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
                  combo['salePricePerKg']?.toDouble() ??
                      0.0;
              final rawPrices = combo['customerPrices'] as Map;
              final Map<String, dynamic> prices = {};
              rawPrices.forEach(
                      (k, v) => prices[k.toString()] = v);

              return Card(
                margin: EdgeInsets.symmetric(vertical: 6),
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      // Combination header
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _primaryColor
                                  .withOpacity(0.1),
                              borderRadius:
                              BorderRadius.circular(6),
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
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Divider(height: 1),
                      // Customer prices for this combo
                      ...prices.entries.map((entry) {
                        final customerId = entry.key;
                        final price = entry.value;
                        final customerName =
                            customerIdNameMap[customerId] ??
                                'Customer ($customerId)';
                        final parsedPrice =
                            double.tryParse(
                                price.toString()) ??
                                salePrice;
                        final diff =
                            salePrice - parsedPrice;

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 6, horizontal: 4),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor:
                                Colors.purple
                                    .withOpacity(0.1),
                                child: Icon(Icons.person,
                                    color: Colors.purple,
                                    size: 16),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  customerName,
                                  style: TextStyle(
                                      fontWeight:
                                      FontWeight.w500),
                                ),
                              ),
                              Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3),
                                    decoration: BoxDecoration(
                                      color:
                                      Colors.purple[50],
                                      borderRadius:
                                      BorderRadius.circular(
                                          5),
                                    ),
                                    child: Text(
                                      "PKR $price /kg",
                                      style: TextStyle(
                                        fontWeight:
                                        FontWeight.bold,
                                        color:
                                        Colors.purple[700],
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
                                            ? Colors
                                            .orange[600]
                                            : Colors
                                            .green[600],
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
            child: Text(languageProvider.isEnglish
                ? "Close"
                : "بند کریں"),
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
                MaterialPageRoute(
                    builder: (context) => StockReportPage()),
              );
            },
            icon: Icon(Icons.history, color: Colors.white),
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
            /// Left Panel - Item List
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
                            borderRadius:
                            BorderRadius.circular(8),
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
                          final combosCount =
                          item['lengthBodyCombinations'] !=
                              null
                              ? (item[
                          'lengthBodyCombinations']
                          as List)
                              .length
                              : 0;

                          return Card(
                            margin: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(8),
                            ),
                            child: ListTile(
                              leading: Container(
                                padding: EdgeInsets.all(4),
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
                                  ),
                                ),
                              ),
                              title: Text(item['itemName'],
                                  style: TextStyle(
                                      color: _textColor,
                                      fontWeight:
                                      FontWeight.bold)),
                              subtitle: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Qty: ${item['qtyOnHand'] ?? 0}",
                                    style: TextStyle(
                                        color: _textColor
                                            .withOpacity(0.7)),
                                  ),
                                  if (combosCount > 0)
                                    Text(
                                      "$combosCount combo${combosCount > 1 ? 's' : ''}",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.blue[600],
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.edit_note,
                                        color: Colors.blue),
                                    onPressed: () =>
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                EditQtyPage(
                                                    itemData: item),
                                          ),
                                        ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: () =>
                                        _confirmDelete(
                                            item['key']),
                                  ),
                                ],
                              ),
                              onTap: () async {
                                setState(() {
                                  _selectedItem = item;
                                  _isLoadingTransactions =
                                  true;
                                });
                                final transactions =
                                await _fetchItemTransactions(
                                    item['key']);
                                setState(() {
                                  _itemTransactions =
                                      transactions
                                          .where((t) =>
                                      t['type'] ==
                                          'Purchase')
                                          .toList();
                                  _isLoadingTransactions =
                                  false;
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

            /// Center Panel - Item Detail
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
                          color:
                          _primaryColor.withOpacity(0.5),
                        ),
                        SizedBox(height: 16),
                        Text(
                          "Select an item to view details",
                          style: TextStyle(
                              color: _textColor,
                              fontSize: 16),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Click on any item from the left panel",
                          style: TextStyle(
                              color: _textColor
                                  .withOpacity(0.6),
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
                            minHeight:
                            constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                  MainAxisAlignment
                                      .spaceBetween,
                                  children: [
                                    Text(
                                      "Item Details",
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                        color:
                                        _primaryColor,
                                        fontWeight:
                                        FontWeight
                                            .bold,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        if (_selectedItem![
                                        'isBOM'] ==
                                            true)
                                          Padding(
                                            padding: EdgeInsets
                                                .only(
                                                right: 8),
                                            child: Chip(
                                              label:
                                              Text("BOM"),
                                              backgroundColor:
                                              Colors.blue[
                                              100],
                                            ),
                                          ),
                                        // 💰 Customer rates button — now shows per-combo prices
                                        IconButton(
                                          icon: Icon(
                                              Icons
                                                  .attach_money,
                                              color:
                                              _secondaryColor),
                                          tooltip:
                                          'View customer prices per combination',
                                          onPressed: () =>
                                              _showCustomerRates(
                                                  _selectedItem!),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Divider(
                                    color: _primaryColor
                                        .withOpacity(0.3)),
                                SizedBox(height: 16),

                                // Basic Info
                                Card(
                                  elevation: 2,
                                  margin: EdgeInsets.only(
                                      bottom: 16),
                                  child: Padding(
                                    padding:
                                    EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                      children: [
                                        _buildDetailRow(
                                          "Size",
                                          _selectedItem!['itemName']
                                              ?.toString() ??
                                              'N/A',
                                          isBold: true,
                                        ),
                                        _buildDetailRow(
                                          "Description",
                                          _selectedItem!['description']
                                              ?.toString() ??
                                              'No description',
                                        ),
                                        _buildDetailRow(
                                          "Unit",
                                          _selectedItem!['unit']
                                              ?.toString() ??
                                              'N/A',
                                        ),
                                        _buildDetailRow(
                                          "Quantity On Hand",
                                          _selectedItem!['qtyOnHand']
                                              ?.toString() ??
                                              '0',
                                        ),
                                        if (_selectedItem![
                                        'vendor'] !=
                                            null)
                                          _buildDetailRow(
                                            "Vendor",
                                            _selectedItem!['vendor']
                                                ?.toString() ??
                                                'N/A',
                                          ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Combinations (with inline customer prices)
                                _buildLengthBodyCombinations(),

                                SizedBox(height: 16),
                                Expanded(
                                  child:
                                  SingleChildScrollView(
                                    child: Container(
                                      padding:
                                      EdgeInsets.all(12),
                                      decoration:
                                      BoxDecoration(
                                        color:
                                        Colors.grey[50],
                                        borderRadius:
                                        BorderRadius
                                            .circular(8),
                                        border: Border.all(
                                            color: Colors
                                                .grey[200]!),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                        children: [
                                          Text(
                                            "Average Price Summary",
                                            style: TextStyle(
                                              fontWeight:
                                              FontWeight
                                                  .bold,
                                              fontSize: 16,
                                              color:
                                              _primaryColor,
                                            ),
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            "Based on ${_selectedItem!['lengthBodyCombinations'] != null ? (_selectedItem!['lengthBodyCombinations'] as List).length : 0} combination(s)",
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors
                                                    .grey[600]),
                                          ),
                                          SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Expanded(
                                                child:
                                                _buildPriceCard(
                                                  "Avg Cost/Kg",
                                                  _selectedItem!['avgCostPricePerKg']
                                                      ?.toStringAsFixed(
                                                      2) ??
                                                      '0.00',
                                                  Colors
                                                      .blue[50]!,
                                                ),
                                              ),
                                              SizedBox(
                                                  width: 8),
                                              Expanded(
                                                child:
                                                _buildPriceCard(
                                                  "Avg Sale/Kg",
                                                  _selectedItem!['avgSalePricePerKg']
                                                      ?.toStringAsFixed(
                                                      2) ??
                                                      '0.00',
                                                  Colors.green[
                                                  50]!,
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 8),
                                          if (_selectedItem![
                                          'profitPercentage1kg'] !=
                                              null)
                                            Container(
                                              padding:
                                              EdgeInsets
                                                  .all(8),
                                              decoration:
                                              BoxDecoration(
                                                color: Colors
                                                    .orange[50],
                                                borderRadius:
                                                BorderRadius
                                                    .circular(
                                                    8),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                CrossAxisAlignment
                                                    .start,
                                                children: [
                                                  Text(
                                                    "Profit Analysis",
                                                    style: TextStyle(
                                                        fontWeight:
                                                        FontWeight
                                                            .bold,
                                                        color: Colors
                                                            .orange[700]),
                                                  ),
                                                  SizedBox(
                                                      height:
                                                      8),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child:
                                                        Column(
                                                          children: [
                                                            Text(
                                                                "1 Kg",
                                                                style: TextStyle(
                                                                    fontSize:
                                                                    12)),
                                                            Text(
                                                              "PKR ${_selectedItem!['profitMargin1kg']?.toStringAsFixed(2) ?? '0.00'}",
                                                              style: TextStyle(
                                                                  fontWeight:
                                                                  FontWeight.bold,
                                                                  color: (_selectedItem!['profitMargin1kg'] ?? 0) >= 0
                                                                      ? Colors.green
                                                                      : Colors.red),
                                                            ),
                                                            Text(
                                                              "${_selectedItem!['profitPercentage1kg']?.toStringAsFixed(1)}%",
                                                              style: TextStyle(
                                                                  fontSize:
                                                                  11,
                                                                  color: (_selectedItem!['profitPercentage1kg'] ?? 0) >= 0
                                                                      ? Colors.green
                                                                      : Colors.red),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child:
                                                        Column(
                                                          children: [
                                                            Text(
                                                                "50 Kg",
                                                                style: TextStyle(
                                                                    fontSize:
                                                                    12)),
                                                            Text(
                                                              "PKR ${_selectedItem!['profitMargin50kg']?.toStringAsFixed(2) ?? '0.00'}",
                                                              style: TextStyle(
                                                                  fontWeight:
                                                                  FontWeight.bold,
                                                                  color: (_selectedItem!['profitMargin50kg'] ?? 0) >= 0
                                                                      ? Colors.green
                                                                      : Colors.red),
                                                            ),
                                                            Text(
                                                              "${_selectedItem!['profitPercentage50kg']?.toStringAsFixed(1)}%",
                                                              style: TextStyle(
                                                                  fontSize:
                                                                  11,
                                                                  color: (_selectedItem!['profitPercentage50kg'] ?? 0) >= 0
                                                                      ? Colors.green
                                                                      : Colors.red),
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
                                  ),
                                ),

                                // BOM Components
                                if (_selectedItem!['isBOM'] ==
                                    true &&
                                    _selectedItem![
                                    'components'] !=
                                        null) ...[
                                  SizedBox(height: 16),
                                  Card(
                                    elevation: 2,
                                    child: Padding(
                                      padding:
                                      EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                        children: [
                                          Text(
                                              "BOM Components:",
                                              style: TextStyle(
                                                  fontWeight:
                                                  FontWeight
                                                      .bold,
                                                  fontSize: 16,
                                                  color:
                                                  _primaryColor)),
                                          SizedBox(height: 8),
                                          Container(
                                            height: 150,
                                            decoration:
                                            BoxDecoration(
                                              border: Border.all(
                                                  color: Colors
                                                      .grey[300]!),
                                              borderRadius:
                                              BorderRadius
                                                  .circular(
                                                  8),
                                            ),
                                            child: ListView
                                                .builder(
                                              padding:
                                              EdgeInsets.all(
                                                  8),
                                              itemCount:
                                              _selectedItem![
                                              'components']
                                                  .length,
                                              itemBuilder:
                                                  (context,
                                                  index) {
                                                final component =
                                                _selectedItem![
                                                'components']
                                                [index];
                                                return Card(
                                                  margin: EdgeInsets
                                                      .symmetric(
                                                      vertical:
                                                      4),
                                                  elevation: 1,
                                                  child:
                                                  ListTile(
                                                    contentPadding:
                                                    EdgeInsets.symmetric(
                                                        horizontal:
                                                        12),
                                                    title: Text(
                                                        component[
                                                        'name'] ??
                                                            'Unnamed'),
                                                    subtitle: Text(
                                                        '${component['quantity']} ${component['unit']}'),
                                                    trailing: Text(
                                                        '${(component['price'] * component['quantity']).toStringAsFixed(2)} PKR'),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            "Total BOM Cost: PKR ${_selectedItem!['costPrice']?.toStringAsFixed(2) ?? '0.00'}",
                                            style: TextStyle(
                                                fontWeight:
                                                FontWeight
                                                    .bold,
                                                color: Colors
                                                    .blue[700]),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],

                                Spacer(),
                                SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                  MainAxisAlignment.end,
                                  children: [
                                    ElevatedButton(
                                      style: ElevatedButton
                                          .styleFrom(
                                        backgroundColor:
                                        _primaryColor,
                                        shape:
                                        RoundedRectangleBorder(
                                          borderRadius:
                                          BorderRadius
                                              .circular(8),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize:
                                        MainAxisSize.min,
                                        children: [
                                          Icon(Icons.edit,
                                              size: 16),
                                          SizedBox(width: 4),
                                          Text("Edit Item"),
                                        ],
                                      ),
                                      onPressed: () =>
                                          updateItem(
                                              _selectedItem!),
                                    ),
                                    SizedBox(width: 10),
                                    ElevatedButton(
                                      style: ElevatedButton
                                          .styleFrom(
                                        backgroundColor:
                                        Colors.red,
                                        shape:
                                        RoundedRectangleBorder(
                                          borderRadius:
                                          BorderRadius
                                              .circular(8),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize:
                                        MainAxisSize.min,
                                        children: [
                                          Icon(Icons.delete,
                                              size: 16),
                                          SizedBox(width: 4),
                                          Text("Delete"),
                                        ],
                                      ),
                                      onPressed: () =>
                                          _confirmDelete(
                                              _selectedItem![
                                              'key']),
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

            /// Right Panel
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
                      SizedBox(height: 20),
                      Text("Item Image",
                          style: TextStyle(
                              color: _primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 18)),
                      SizedBox(height: 20),
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
                            borderRadius:
                            BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color:
                                Colors.grey.withOpacity(0.3),
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
                                  size: 60,
                                  color: _secondaryColor),
                              SizedBox(height: 8),
                              Text("No Image",
                                  style: TextStyle(
                                      color: _secondaryColor,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      if (_selectedItem != null)
                        _buildStatCard(
                          "Stock Value",
                          "PKR ${((_selectedItem!['qtyOnHand'] ?? 0) * (_selectedItem!['avgSalePricePerKg'] ?? _selectedItem!['salePrice1kg'] ?? 0)).toStringAsFixed(2)}",
                        ),
                      SizedBox(height: 10),
                      if (_selectedItem != null &&
                          _selectedItem![
                          'lengthBodyCombinations'] !=
                              null)
                        _buildStatCard(
                          "Combinations",
                          "${(_selectedItem!['lengthBodyCombinations'] as List).length}",
                          icon: Icons.layers,
                          color: Colors.purple,
                        ),
                      SizedBox(height: 10),
                      if (_selectedItem != null)
                        _buildStatCard(
                          "Avg Profit %",
                          "${_selectedItem!['profitPercentage1kg']?.toStringAsFixed(1) ?? '0.0'}%",
                          icon: Icons.trending_up,
                          color:
                          (_selectedItem!['profitPercentage1kg'] ??
                              0) >=
                              0
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
          borderRadius: BorderRadius.only(
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
                unselectedLabelColor:
                _textColor.withOpacity(0.6),
                indicatorColor: _primaryColor,
                tabs: [
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
        child: Icon(Icons.add, color: Colors.white),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => RegisterItemPage()),
          ).then((_) => fetchItems());
        },
      ),
    );
  }

  // ── All unchanged methods below ──────────────────────────────────────────

  Widget _buildSalesTab() {
    return FutureBuilder(
      future: _fetchItemSales(_selectedItem?['key']),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
              child: Text("No sales records for this item"));
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
                      title: Text(
                          sale['customerName'] ??
                              'Unknown Customer'),
                      subtitle: Text(DateFormat.yMMMd()
                          .add_jm()
                          .format(DateTime.fromMillisecondsSinceEpoch(
                          sale['date']))),
                      trailing: Column(
                        mainAxisAlignment:
                        MainAxisAlignment.center,
                        crossAxisAlignment:
                        CrossAxisAlignment.end,
                        children: [
                          Text(
                              '${sale['quantity']} @ ${sale['price']}'),
                          Text(
                              '${sale['total'].toStringAsFixed(2)} PKR'),
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
                  "Customer",
                  sale['customerName'] ?? 'Unknown'),
              _buildSaleDetailRow(
                  "Date",
                  DateFormat.yMMMd().add_jm().format(
                      sale['date'] is int
                          ? DateTime.fromMillisecondsSinceEpoch(
                          sale['date'])
                          : DateTime.parse(sale['date']))),
              _buildSaleDetailRow(
                  "Invoice #", sale['filledNumber'] ?? 'N/A'),
              _buildSaleDetailRow(
                  "Item",
                  _selectedItem?['itemName'] ?? 'N/A'),
              _buildSaleDetailRow(
                  "Quantity", sale['quantity'].toString()),
              _buildSaleDetailRow(
                  "Price", sale['price'].toString()),
              _buildSaleDetailRow("Total",
                  '${sale['total'].toStringAsFixed(2)} PKR'),
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
                  style:
                  TextStyle(fontWeight: FontWeight.bold))),
          SizedBox(width: 10),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchItemSales(
      String? itemKey) async {
    if (itemKey == null) return [];
    final database = FirebaseDatabase.instance.ref();
    List<Map<String, dynamic>> sales = [];
    try {
      final salesSnapshot = await database.child('filled').get();
      if (salesSnapshot.exists) {
        final allSales = salesSnapshot.value;
        if (allSales is Map) {
          allSales.forEach(
                  (saleKey, saleData) =>
                  _processSaleData(saleData, sales));
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

  void _processSaleData(dynamic saleData,
      List<Map<String, dynamic>> sales) {
    try {
      final saleMap = saleData is Map
          ? Map<String, dynamic>.from(saleData)
          : {};
      if (saleMap['items'] != null) {
        final items =
        saleMap['items'] is List ? saleMap['items'] : [];
        for (var item in items) {
          if (item is Map &&
              item['itemName'] == _selectedItem!['itemName']) {
            String customerName = 'Unknown Customer';
            if (saleMap['customerName'] != null) {
              customerName = saleMap['customerName'].toString();
            } else if (saleMap['customerId'] != null) {
              customerName =
              "Customer ID: ${saleMap['customerId']}";
            }
            dynamic dateValue =
                saleMap['createdAt'] ?? saleMap['timestamp'];
            DateTime saleDate;
            if (dateValue is int) {
              saleDate =
                  DateTime.fromMillisecondsSinceEpoch(dateValue);
            } else if (dateValue is String) {
              saleDate =
                  DateTime.tryParse(dateValue) ?? DateTime.now();
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
              'filledNumber':
              saleMap['filledNumber']?.toString() ?? '',
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
            Text(
                "Sales Report: ${_selectedItem?['itemName']}",
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
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
                      leading:
                      Icon(Icons.sell, color: Colors.blue),
                      title: Text(sale['customerName'] ??
                          'Unknown Customer'),
                      subtitle: Text(DateFormat.yMMMd()
                          .add_jm()
                          .format(sale['date'] is int
                          ? DateTime.fromMillisecondsSinceEpoch(
                          sale['date'])
                          : DateTime.parse(sale['date']))),
                      trailing: Column(
                        mainAxisAlignment:
                        MainAxisAlignment.center,
                        crossAxisAlignment:
                        CrossAxisAlignment.end,
                        children: [
                          Text(
                              '${sale['quantity']} @ ${sale['price']}'),
                          Text(
                              '${sale['total'].toStringAsFixed(2)} PKR'),
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
              mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
              children: [
                Text("Total Sold:",
                    style:
                    TextStyle(fontWeight: FontWeight.bold)),
                Text(
                    "${sales.fold(0.0, (sum, sale) => sum + (sale['quantity'] as num).toDouble()).toStringAsFixed(2)} units",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ],
            ),
            Row(
              mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
              children: [
                Text("Total Revenue:",
                    style:
                    TextStyle(fontWeight: FontWeight.bold)),
                Text(
                    "${sales.fold(0.0, (sum, sale) => sum + (sale['total'] as num).toDouble()).toStringAsFixed(2)} PKR",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
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
                icon:
                Icon(Icons.details, color: _secondaryColor)),
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
            itemCount:
            min(3, _itemTransactions.length),
            itemBuilder: (context, index) {
              final txn =
              _itemTransactions[index];
              return Card(
                margin: EdgeInsets.symmetric(
                    vertical: 4),
                child: ListTile(
                  contentPadding:
                  EdgeInsets.symmetric(
                      horizontal: 8),
                  leading: Icon(
                      Icons.shopping_cart,
                      color: Colors.green),
                  title: Text(txn['vendor']),
                  subtitle: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(DateFormat('MMM dd, yyyy')
                          .format(DateTime.parse(
                          txn['date']))),
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
                  onTap: () =>
                      _showPurchaseDetails(txn),
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
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
              child: Text("No BOM build records for this item",
                  style: TextStyle(
                      color: _textColor.withOpacity(0.6))));
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
                    onPressed: () =>
                        _showBomBuildReport(builds),
                    icon: Icon(Icons.details,
                        color: _secondaryColor)),
              ],
            ),
            Divider(color: _primaryColor.withOpacity(0.3)),
            Expanded(
              child: ListView.builder(
                itemCount: min(3, builds.length),
                itemBuilder: (context, index) {
                  final build = builds[index];
                  return Card(
                    margin:
                    EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      contentPadding:
                      EdgeInsets.symmetric(horizontal: 8),
                      leading:
                      Icon(Icons.build, color: Colors.blue),
                      title: Text(
                          'Built ${build['quantityBuilt']} units'),
                      subtitle: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
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
                        mainAxisAlignment:
                        MainAxisAlignment.center,
                        crossAxisAlignment:
                        CrossAxisAlignment.end,
                        children: [
                          SizedBox(height: 4),
                          Text('View Details',
                              style: TextStyle(
                                  color: Colors.blue,
                                  fontSize: 10)),
                        ],
                      ),
                      onTap: () =>
                          _showBomBuildDetails(build),
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

  Future<List<Map<String, dynamic>>> _fetchBomBuilds(
      String? itemKey) async {
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
        final data =
        snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          final build = Map<String, dynamic>.from(
              value as Map<dynamic, dynamic>);
          build['key'] = key;
          builds.add(build);
        });
        builds.sort((a, b) =>
            b['timestamp'].compareTo(a['timestamp']));
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
              _buildDetailRow(
                  "Item", build['bomItemName'] ?? 'N/A'),
              _buildDetailRow("Quantity Built",
                  build['quantityBuilt'].toString()),
              _buildDetailRow(
                  "Date",
                  DateFormat.yMMMd().add_jm().format(
                      DateTime.fromMillisecondsSinceEpoch(
                          build['timestamp']))),
              SizedBox(height: 16),
              Text("Components Used:",
                  style:
                  TextStyle(fontWeight: FontWeight.bold)),
              ...(build['components'] as List?)
                  ?.map<Widget>((component) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                          flex: 2,
                          child: Text(
                              component['name'] ??
                                  'Unknown')),
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

  void _showBomBuildReport(
      List<Map<String, dynamic>> builds) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
                "BOM Build Report: ${_selectedItem?['itemName']}",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: builds.length,
                itemBuilder: (context, index) {
                  final build = builds[index];
                  return Card(
                    margin:
                    EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      contentPadding:
                      EdgeInsets.symmetric(horizontal: 12),
                      leading:
                      Icon(Icons.build, color: Colors.blue),
                      title: Text(
                          'Built ${build['quantityBuilt']} units'),
                      subtitle: Text(DateFormat.yMMMd()
                          .add_jm()
                          .format(
                          DateTime.fromMillisecondsSinceEpoch(
                              build['timestamp']))),
                      trailing: Column(
                        mainAxisAlignment:
                        MainAxisAlignment.center,
                        crossAxisAlignment:
                        CrossAxisAlignment.end,
                        children: [
                          Text(
                              '${build['components']?.length ?? 0} components'),
                          Text('View',
                              style: TextStyle(
                                  color: Colors.blue,
                                  fontSize: 10)),
                        ],
                      ),
                      onTap: () =>
                          _showBomBuildDetails(build),
                    ),
                  );
                },
              ),
            ),
            Divider(),
            Row(
              mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
              children: [
                Text("Total Built:",
                    style:
                    TextStyle(fontWeight: FontWeight.bold)),
                Text(
                    "${builds.fold(0, (sum, build) => sum + (build['quantityBuilt'] as num).toInt())} units",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _calculateEffectiveCost(
      Map<String, dynamic> item) {
    if (item['isBOM'] == true && item['components'] != null) {
      double totalCost = 0.0;
      for (var component in item['components']) {
        double quantity = double.tryParse(
            component['quantity'].toString()) ??
            0;
        double price =
            double.tryParse(component['price'].toString()) ??
                0;
        totalCost += quantity * price;
      }
      return totalCost;
    } else {
      return double.tryParse(
          item['avgCostPricePerKg']?.toString() ??
              item['costPrice1kg']?.toString() ??
              '0') ??
          0;
    }
  }

  void _showPurchaseDetails(
      Map<String, dynamic> purchase) {
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
                  DateFormat.yMMMd().add_jm().format(
                      DateTime.parse(purchase['date']))),
              _buildPurchaseDetailRow(
                  "Vendor", purchase['vendor']),
              _buildPurchaseDetailRow(
                  "Item",
                  _selectedItem?['itemName'] ?? ''),
              _buildPurchaseDetailRow("Quantity",
                  purchase['quantity'].toString()),
              _buildPurchaseDetailRow(
                  "Price", purchase['price'].toString()),
              _buildPurchaseDetailRow("Total",
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

  Widget _buildPurchaseDetailRow(
      String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 80,
              child: Text("$label:",
                  style:
                  TextStyle(fontWeight: FontWeight.bold))),
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
            Text(
                "Purchase Report: ${_selectedItem?['itemName']}",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: _itemTransactions.length,
                itemBuilder: (context, index) {
                  final txn = _itemTransactions[index];
                  return Card(
                    margin:
                    EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      contentPadding:
                      EdgeInsets.symmetric(horizontal: 12),
                      leading: Icon(Icons.shopping_cart,
                          color: Colors.green),
                      title: Text(txn['vendor']),
                      subtitle: Text(DateFormat.yMMMd()
                          .add_jm()
                          .format(
                          DateTime.parse(txn['date']))),
                      trailing: Column(
                        mainAxisAlignment:
                        MainAxisAlignment.center,
                        crossAxisAlignment:
                        CrossAxisAlignment.end,
                        children: [
                          Text(
                              '${txn['quantity']} @ ${txn['price']}'),
                          Text(
                              '${txn['total'].toStringAsFixed(2)} PKR'),
                        ],
                      ),
                      onTap: () =>
                          _showPurchaseDetails(txn),
                    ),
                  );
                },
              ),
            ),
            Divider(),
            Row(
              mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
              children: [
                Text("Total Purchases:",
                    style:
                    TextStyle(fontWeight: FontWeight.bold)),
                Text(
                    "${_calculateTotalPurchases().toStringAsFixed(2)} PKR",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
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

  void _showImagePreview(
      BuildContext context, String imageBase64) {
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
                  ? Image.network(
                  'data:image/png;base64,$imageBase64')
                  : Image.memory(base64Decode(imageBase64)),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: Icon(Icons.close,
                    color: Colors.white, size: 30),
                onPressed: () =>
                    Navigator.of(context).pop(),
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
      elevation: 2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            if (icon != null)
              Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color:
                  (color ?? _primaryColor).withOpacity(0.1),
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
                    fontWeight: isBold
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: fontSize)),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(value.isNotEmpty ? value : 'N/A',
                style: TextStyle(
                    color: _textColor.withOpacity(0.8),
                    fontSize: fontSize,
                    fontWeight: isBold
                        ? FontWeight.bold
                        : FontWeight.normal)),
          ),
        ],
      ),
    );
  }

  Future<String?> _getCustomerName(
      String customerId) async {
    final snapshot = await FirebaseDatabase.instance
        .ref()
        .child('customers/$customerId/name')
        .get();
    return snapshot.exists ? snapshot.value.toString() : null;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}