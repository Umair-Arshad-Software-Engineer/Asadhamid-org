import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../Models/itemModel.dart';
import '../Provider/lanprovider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class CustomerItemPricesPage extends StatefulWidget {
  final String customerId;
  final String customerName;

  const CustomerItemPricesPage({
    required this.customerId,
    required this.customerName,
    Key? key,
  }) : super(key: key);

  @override
  _CustomerItemPricesPageState createState() => _CustomerItemPricesPageState();
}

class _CustomerItemPricesPageState extends State<CustomerItemPricesPage> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _filteredItems = [];
  bool _isLoading = true;

  String _filterMode = 'all'; // 'all' | 'custom' | 'default'
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchItemsWithCustomerPrices();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchItemsWithCustomerPrices() async {
    setState(() => _isLoading = true);
    try {
      final snapshot =
      await FirebaseDatabase.instance.ref().child('items').get();

      if (snapshot.exists) {
        final raw = snapshot.value as Map<dynamic, dynamic>;
        final List<Map<String, dynamic>> list = [];

        raw.forEach((key, value) {
          final data = Map<String, dynamic>.from(value as Map);
          data['key'] = key;

          // ── Item-level custom price ─────────────────────────────
          double itemCustomerPrice = 0.0;
          bool itemHasCustomPrice = false;
          if (data['customerBasePrices'] != null) {
            final prices =
            Map<String, dynamic>.from(data['customerBasePrices'] as Map);
            if (prices.containsKey(widget.customerId)) {
              itemCustomerPrice =
                  (prices[widget.customerId] as num).toDouble();
              itemHasCustomPrice = true;
            }
          }

          final double defaultItemPrice =
              (data['salePrice'] as num?)?.toDouble() ?? 0.0;

          // ── Per-combination custom prices ───────────────────────
          List<Map<String, dynamic>> combinationRows = [];
          if (data['lengthBodyCombinations'] != null &&
              data['lengthBodyCombinations'] is List) {
            for (final c in data['lengthBodyCombinations'] as List) {
              if (c is! Map) continue;
              final combo = LengthBodyCombination.fromMap(
                  Map<String, dynamic>.from(c));

              final double defaultComboPrice = combo.salePricePerKg ?? 0.0;
              final bool hasComboCustomPrice =
              combo.customerPrices.containsKey(widget.customerId);
              final double comboCustomerPrice = hasComboCustomPrice
                  ? combo.customerPrices[widget.customerId]!
                  : defaultComboPrice;

              combinationRows.add({
                'length': combo.length,
                'bodyType': combo.bodyType,
                'defaultPrice': defaultComboPrice,
                'customerPrice': comboCustomerPrice,
                'hasCustomPrice': hasComboCustomPrice,
              });
            }
          }

          final bool anyCustomPrice = itemHasCustomPrice ||
              combinationRows.any((r) => r['hasCustomPrice'] == true);

          list.add({
            'itemKey': key,
            'itemName': data['itemName'] ?? '',
            'image': data['image'],
            'unit': data['unit'] ?? '',
            // Item-level
            'defaultPrice': defaultItemPrice,
            'customerPrice': itemCustomerPrice,
            'hasCustomPrice': itemHasCustomPrice,
            // Combinations
            'combinations': combinationRows,
            'anyCustomPrice': anyCustomPrice,
            // Keep full raw data for saving back
            '_raw': data,
          });
        });

        list.sort((a, b) {
          if (a['anyCustomPrice'] && !b['anyCustomPrice']) return -1;
          if (!a['anyCustomPrice'] && b['anyCustomPrice']) return 1;
          return (a['itemName'] as String).compareTo(b['itemName'] as String);
        });

        setState(() {
          _items = list;
          _filteredItems = list;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error fetching items: $e')));
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = _items.where((item) {
        final matchesSearch =
        (item['itemName'] as String).toLowerCase().contains(query);
        final matchesMode = _filterMode == 'all' ||
            (_filterMode == 'custom' && item['anyCustomPrice'] == true) ||
            (_filterMode == 'default' && item['anyCustomPrice'] == false);
        return matchesSearch && matchesMode;
      }).toList();
    });
  }

  void _setFilterMode(String mode) {
    setState(() => _filterMode = mode);
    _applyFilters();
  }

  // ── Save a per-combination price to Firebase ──────────────────────────────
  Future<void> _saveCombinationPrice({
    required String itemKey,
    required Map<String, dynamic> rawData,
    required int combinationIndex,
    required double? newPrice, // null = remove custom price
  })
  async {
    try {
      final List<dynamic> rawCombinations =
      List.from(rawData['lengthBodyCombinations'] as List);

      final comboMap =
      Map<String, dynamic>.from(rawCombinations[combinationIndex] as Map);
      Map<String, dynamic> customerPrices = {};
      if (comboMap['customerPrices'] != null) {
        customerPrices =
        Map<String, dynamic>.from(comboMap['customerPrices'] as Map);
      }

      if (newPrice == null) {
        customerPrices.remove(widget.customerId);
      } else {
        customerPrices[widget.customerId] = newPrice;
      }

      comboMap['customerPrices'] = customerPrices;
      rawCombinations[combinationIndex] = comboMap;

      await FirebaseDatabase.instance
          .ref()
          .child('items/$itemKey/lengthBodyCombinations')
          .set(rawCombinations);

      // Refresh data
      await _fetchItemsWithCustomerPrices();
      _applyFilters();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error saving price: $e')));
    }
  }

  // ── Save item-level price to Firebase ────────────────────────────────────
  Future<void> _saveItemLevelPrice({
    required String itemKey,
    required Map<String, dynamic> rawData,
    required double? newPrice, // null = remove
  })
  async {
    try {
      Map<String, dynamic> customerBasePrices = {};
      if (rawData['customerBasePrices'] != null) {
        customerBasePrices =
        Map<String, dynamic>.from(rawData['customerBasePrices'] as Map);
      }

      if (newPrice == null) {
        customerBasePrices.remove(widget.customerId);
      } else {
        customerBasePrices[widget.customerId] = newPrice;
      }

      await FirebaseDatabase.instance
          .ref()
          .child('items/$itemKey/customerBasePrices')
          .set(customerBasePrices);

      await _fetchItemsWithCustomerPrices();
      _applyFilters();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error saving price: $e')));
    }
  }

  // ── Edit dialog ───────────────────────────────────────────────────────────
  void _showEditPriceDialog({
    required String itemName,
    required String? subtitle, // e.g. "3¼ — Half"
    required double defaultPrice,
    required double? currentCustomPrice,
    required Future<void> Function(double? price) onSave,
  })
  {
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    final controller = TextEditingController(
      text: currentCustomPrice != null
          ? currentCustomPrice.toStringAsFixed(2)
          : '',
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                languageProvider.isEnglish
                    ? 'Edit Customer Price'
                    : 'کسٹمر قیمت ترمیم کریں',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(itemName,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFFFF8A65))),
              if (subtitle != null)
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Default price info
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Text(
                      '${languageProvider.isEnglish ? 'Default' : 'ڈیفالٹ'}: ${defaultPrice.toStringAsFixed(2)} PKR/kg',
                      style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: languageProvider.isEnglish
                      ? 'Custom Price (PKR/kg)'
                      : 'کسٹم قیمت (روپے/کلو)',
                  border: const OutlineInputBorder(),
                  prefixText: 'PKR ',
                  focusedBorder: const OutlineInputBorder(
                      borderSide:
                      BorderSide(color: Color(0xFFFF8A65), width: 2)),
                ),
              ),
            ],
          ),
          actions: [
            // Remove custom price
            if (currentCustomPrice != null)
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: Text(
                  languageProvider.isEnglish ? 'Remove' : 'ہٹائیں',
                  style: const TextStyle(color: Colors.red),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await onSave(null);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(languageProvider.isEnglish
                          ? 'Custom price removed'
                          : 'کسٹم قیمت ہٹا دی گئی'),
                    ));
                  }
                },
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8A65),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final p = double.tryParse(controller.text);
                if (p == null || p <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(languageProvider.isEnglish
                        ? 'Please enter a valid price'
                        : 'براہ کرم درست قیمت درج کریں'),
                  ));
                  return;
                }
                Navigator.pop(ctx);
                await onSave(p);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: Colors.green,
                    content: Text(languageProvider.isEnglish
                        ? 'Price saved successfully'
                        : 'قیمت کامیابی سے محفوظ ہو گئی'),
                  ));
                }
              },
              child: Text(
                languageProvider.isEnglish ? 'Save' : 'محفوظ کریں',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<Uint8List> _renderTextAsImage(
      String text, {
        double fontSize = 14,
        double width = 80,
        double height = 24,
      })
  async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final bgPaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF000000),
          fontSize: fontSize,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    );
    textPainter.layout(maxWidth: width - 4);
    textPainter.paint(canvas, Offset(2, (height - textPainter.height) / 2));

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  pw.Widget _buildItemImage(dynamic imageData) {
    if (imageData == null || imageData.toString().isEmpty) {
      return pw.Container(
        width: 32,
        height: 32,
        decoration: const pw.BoxDecoration(
          color: PdfColors.orange100,
          shape: pw.BoxShape.circle,
        ),
      );
    }
    try {
      // Clean the base64 string - remove any data URI prefix if present
      String base64Str = imageData.toString();
      if (base64Str.contains(',')) {
        base64Str = base64Str.split(',').last;
      }
      base64Str = base64Str.trim();
      final bytes = base64Decode(base64Str);
      if (bytes.isEmpty) throw Exception('Empty bytes');
      return pw.Container(
        width: 32,
        height: 32,
        child: pw.ClipOval(
          child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.cover),
        ),
      );
    } catch (_) {
      return pw.Container(
        width: 32,
        height: 32,
        decoration: const pw.BoxDecoration(
          color: PdfColors.orange100,
          shape: pw.BoxShape.circle,
        ),
      );
    }
  }

  Future<void> _generateAndPrintPdf() async {
    final pdf = pw.Document();
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    // ── Pre-render all text that may contain fraction chars as PNG images ──
    final Map<String, Uint8List> nameImages = {};
    final Map<String, Uint8List> lengthImages = {};

    for (final item in _filteredItems) {
      final name = item['itemName'] as String;
      if (!nameImages.containsKey(name)) {
        nameImages[name] = await _renderTextAsImage(name, fontSize: 13, width: 200, height: 22);
      }
      for (final combo in item['combinations'] as List<Map<String, dynamic>>) {
        final length = combo['length'].toString();
        if (!lengthImages.containsKey(length)) {
          lengthImages[length] = await _renderTextAsImage(length, fontSize: 11, width: 80, height: 18);
        }
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        languageProvider.isEnglish ? 'Customer Price List' : 'کسٹمر پرائس لسٹ',
                        style: pw.TextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.deepOrange,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        languageProvider.isEnglish
                            ? 'Customer: ${widget.customerName}'
                            : 'کسٹمر: ${widget.customerName}',
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Text(
                      '${languageProvider.isEnglish ? 'Generated' : 'تیار کردہ'}: ${DateTime.now().toString().split(' ')[0]}',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(color: PdfColors.deepOrange),
              pw.SizedBox(height: 16),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    languageProvider.isEnglish
                        ? 'Page ${context.pageNumber} of ${context.pagesCount}'
                        : 'صفحہ ${context.pageNumber} از ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    languageProvider.isEnglish ? 'All prices in PKR/kg' : 'تمام قیمتیں روپے/کلو میں',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                ],
              ),
            ],
          );
        },
        build: (pw.Context context) {
          final List<pw.Widget> widgets = [];

          final totalItems = _filteredItems.length;
          final customItems = _filteredItems.where((i) => i['anyCustomPrice'] == true).length;
          final defaultItems = totalItems - customItems;

          // ── Summary stats box ──────────────────────────────────────────────
          widgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 20),
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatBox(
                    languageProvider.isEnglish ? 'Total Items' : 'کل اشیاء',
                    totalItems.toString(),
                    PdfColors.deepOrange,
                  ),
                  _buildStatBox(
                    languageProvider.isEnglish ? 'Custom Prices' : 'کسٹم قیمتیں',
                    customItems.toString(),
                    PdfColors.green,
                  ),
                  _buildStatBox(
                    languageProvider.isEnglish ? 'Default Prices' : 'ڈیفالٹ قیمتیں',
                    defaultItems.toString(),
                    PdfColors.blueGrey,
                  ),
                ],
              ),
            ),
          );

          for (final item in _filteredItems) {
            final combos = item['combinations'] as List<Map<String, dynamic>>;

            // ── Item header ──────────────────────────────────────────────────
            widgets.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.deepOrange50,
                  border: pw.Border(
                    left: pw.BorderSide(color: PdfColors.deepOrange, width: 4),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _buildItemImage(item['image']),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          // ── Item name rendered as image to support ½ ¼ ¾ ──
                          pw.Image(
                            pw.MemoryImage(nameImages[item['itemName']]!),
                            width: 180,
                            height: 20,
                            fit: pw.BoxFit.contain,
                          ),
                          if (item['unit'] != null && item['unit'].toString().isNotEmpty)
                            pw.Text(
                              'Unit: ${item['unit']}',
                              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                            ),
                        ],
                      ),
                    ),
                    if (item['anyCustomPrice'] == true)
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.purple50,
                          border: pw.Border.all(color: PdfColors.purple200),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                        ),
                        child: pw.Text(
                          languageProvider.isEnglish ? 'CUSTOM' : 'کسٹم',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.purple700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );

            if (combos.isEmpty) {
              // ── Item-level price table ─────────────────────────────────────
              final hasCustom = item['hasCustomPrice'] as bool;

              List<List<String>> tableData = [
                [
                  languageProvider.isEnglish ? 'Default Price' : 'ڈیفالٹ قیمت',
                  '${(item['defaultPrice'] as double).toStringAsFixed(2)}',
                  '-',
                ]
              ];

              if (hasCustom) {
                tableData.add([
                  languageProvider.isEnglish ? 'Customer Price' : 'کسٹمر قیمت',
                  '${(item['customerPrice'] as double).toStringAsFixed(2)}',
                  _getPriceStatus(
                    item['customerPrice'] as double,
                    item['defaultPrice'] as double,
                    languageProvider,
                  ),
                ]);
              }

              widgets.add(
                pw.Container(
                  margin: const pw.EdgeInsets.only(left: 8, right: 8, bottom: 8),
                  child: pw.Table.fromTextArray(
                    headers: [
                      languageProvider.isEnglish ? 'Price Type' : 'قیمت کی قسم',
                      languageProvider.isEnglish ? 'Amount (PKR/kg)' : 'رقم (روپے/کلو)',
                      languageProvider.isEnglish ? 'Status' : 'حالت',
                    ],
                    data: tableData,
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                    cellStyle: const pw.TextStyle(fontSize: 10),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    border: pw.TableBorder.all(color: PdfColors.grey300, width: 1),
                    columnWidths: const {
                      0: pw.FlexColumnWidth(2),
                      1: pw.FlexColumnWidth(1),
                      2: pw.FlexColumnWidth(1),
                    },
                  ),
                ),
              );
            } else {
              // ── Combinations — manual pw.Table so Length column uses images ─
              // Header row
              final headerCells = [
                languageProvider.isEnglish ? 'Length' : 'لمبائی',
                languageProvider.isEnglish ? 'Body Type' : 'باڈی قسم',
                languageProvider.isEnglish ? 'Default' : 'ڈیفالٹ',
                languageProvider.isEnglish ? 'Customer' : 'کسٹمر',
                languageProvider.isEnglish ? 'Diff' : 'فرق',
              ];

              pw.Widget _pdfCell(String t, {bool bold = false, PdfColor? color}) =>
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(
                      t,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                        color: color,
                      ),
                    ),
                  );

              pw.Widget _pdfImageCell(Uint8List bytes) =>
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Image(
                      pw.MemoryImage(bytes),
                      width: 60,
                      height: 16,
                      fit: pw.BoxFit.contain,
                    ),
                  );

              final tableRows = <pw.TableRow>[
                // Header
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: headerCells
                      .map((h) => _pdfCell(h, bold: true))
                      .toList(),
                ),
                // Data rows
                ...combos.map((c) {
                  final hasCustom = c['hasCustomPrice'] as bool;
                  final defaultPrice = c['defaultPrice'] as double;
                  final customerPrice = c['customerPrice'] as double;

                  String diffText = '-';
                  PdfColor? diffColor;
                  if (hasCustom) {
                    final diff = customerPrice - defaultPrice;
                    final pct = defaultPrice > 0 ? (diff / defaultPrice * 100).abs() : 0.0;
                    final symbol = diff > 0 ? '+' : (diff < 0 ? '-' : '=');

                    diffText = '$symbol ${pct.toStringAsFixed(1)}%';
                    diffColor = diff < 0 ? PdfColors.green700 : diff > 0 ? PdfColors.red700 : null;
                  }

                  final lengthBytes = lengthImages[c['length'].toString()];

                  return pw.TableRow(
                    children: [
                      // Length — image cell to handle ½ ¼ ¾ etc.
                      lengthBytes != null
                          ? _pdfImageCell(lengthBytes)
                          : _pdfCell(c['length'].toString()),
                      _pdfCell(c['bodyType'].toString()),
                      _pdfCell(defaultPrice.toStringAsFixed(2)),
                      _pdfCell(
                        hasCustom ? customerPrice.toStringAsFixed(2) : 'Default',
                        bold: hasCustom,
                        color: hasCustom
                            ? (customerPrice < defaultPrice ? PdfColors.green700 : PdfColors.red700)
                            : PdfColors.grey600,
                      ),
                      _pdfCell(diffText, color: diffColor),
                    ],
                  );
                }).toList(),
              ];

              widgets.add(
                pw.Container(
                  margin: const pw.EdgeInsets.only(left: 8, right: 8, bottom: 8),
                  child: pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                    columnWidths: const {
                      0: pw.FlexColumnWidth(1.2), // Length  ← image
                      1: pw.FlexColumnWidth(1.2), // Body Type
                      2: pw.FlexColumnWidth(1.0), // Default
                      3: pw.FlexColumnWidth(1.0), // Customer
                      4: pw.FlexColumnWidth(0.8), // Diff
                    },
                    children: tableRows,
                  ),
                ),
              );

              final customCombos = combos.where((c) => c['hasCustomPrice'] == true).length;
              if (customCombos > 0) {
                widgets.add(
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 8, right: 8, bottom: 8),
                    child: pw.Text(
                      languageProvider.isEnglish
                          ? '* $customCombos of ${combos.length} combinations have custom prices'

                          : '* ${combos.length} میں سے $customCombos کمبینیشنز کی کسٹم قیمتیں ہیں',
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.green700,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  ),
                );
              }
            }

            widgets.add(pw.Divider(color: PdfColors.grey200));
          }

          // ── Summary footer ───────────────────────────────────────────────
          if (_filteredItems.isNotEmpty) {
            widgets.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 20),
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey50,
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      languageProvider.isEnglish ? 'Summary' : 'خلاصہ',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          languageProvider.isEnglish
                              ? 'Items with custom prices:'
                              : 'کسٹم قیمتوں والی اشیاء:',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.Text(
                          '$customItems/$totalItems',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.deepOrange,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      languageProvider.isEnglish
                          ? 'Note: All prices are in PKR per kilogram (PKR/kg)'
                          : 'نوٹ: تمام قیمتیں روپے فی کلوگرام (روپے/کلو) میں ہیں',
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey600,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return widgets;
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  pw.Widget _buildStatBox(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          label,
          style: const pw.TextStyle(
            fontSize: 10,
            color: PdfColors.grey600,
          ),
        ),
      ],
    );
  }

  String _getPriceStatus(double customerPrice, double defaultPrice, LanguageProvider languageProvider) {
    if (customerPrice < defaultPrice) {
      return languageProvider.isEnglish ? 'DISCOUNT' : 'رعایت';
    } else if (customerPrice > defaultPrice) {
      return languageProvider.isEnglish ? 'PREMIUM' : 'پریمیم';
    } else {
      return languageProvider.isEnglish ? 'SAME' : 'برابر';
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final customCount =
        _items.where((i) => i['anyCustomPrice'] == true).length;
    final defaultCount =
        _items.where((i) => i['anyCustomPrice'] == false).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(
          "${widget.customerName}'s Prices",
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
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
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchItemsWithCustomerPrices,
          ),
          IconButton(
            icon: const Icon(Icons.print, color: Colors.white),
            onPressed: _generateAndPrintPdf,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // ── Header bar ─────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF8A65), Color(0xFFFFB74D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    _SummaryChip(
                        label: languageProvider.isEnglish
                            ? 'Total'
                            : 'کل',
                        count: _items.length,
                        color: Colors.white,
                        textColor: const Color(0xFFFF8A65)),
                    const SizedBox(width: 8),
                    _SummaryChip(
                        label: languageProvider.isEnglish
                            ? 'Custom'
                            : 'کسٹم',
                        count: customCount,
                        color: Colors.green.shade100,
                        textColor: Colors.green.shade800),
                    const SizedBox(width: 8),
                    _SummaryChip(
                        label: languageProvider.isEnglish
                            ? 'Default'
                            : 'ڈیفالٹ',
                        count: defaultCount,
                        color: Colors.orange.shade100,
                        textColor: Colors.orange.shade800),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: languageProvider.isEnglish
                        ? 'Search items...'
                        : 'اشیاء تلاش کریں...',
                    prefixIcon: const Icon(Icons.search,
                        color: Color(0xFFFF8A65)),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: _searchController.clear,
                    )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding:
                    const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _FilterChip(
                      label:
                      languageProvider.isEnglish ? 'All' : 'سب',
                      selected: _filterMode == 'all',
                      onTap: () => _setFilterMode('all'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: languageProvider.isEnglish
                          ? 'Custom Price'
                          : 'کسٹم قیمت',
                      selected: _filterMode == 'custom',
                      onTap: () => _setFilterMode('custom'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: languageProvider.isEnglish
                          ? 'Default Only'
                          : 'صرف ڈیفالٹ',
                      selected: _filterMode == 'default',
                      onTap: () => _setFilterMode('default'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── List ──────────────────────────────────────────
          Expanded(
            child: _filteredItems.isEmpty
                ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off,
                      size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(
                    languageProvider.isEnglish
                        ? 'No items found'
                        : 'کوئی اشیاء نہیں ملیں',
                    style: TextStyle(
                        color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
                : ListView.builder(
              itemCount: _filteredItems.length,
              itemBuilder: (context, index) {
                final item = _filteredItems[index];
                return _ItemPriceCard(
                  item: item,
                  languageProvider: languageProvider,
                  customerId: widget.customerId,
                  onEditCombinationPrice:
                      (combinationIndex, defaultPrice,
                      currentCustomPrice) {
                    final combo = (item['combinations']
                    as List<Map<String, dynamic>>)[combinationIndex];
                    _showEditPriceDialog(
                      itemName: item['itemName'],
                      subtitle:
                      '${combo['length']}  —  ${combo['bodyType']}',
                      defaultPrice: defaultPrice,
                      currentCustomPrice: currentCustomPrice,
                      onSave: (price) =>
                          _saveCombinationPrice(
                            itemKey: item['itemKey'],
                            rawData: item['_raw'],
                            combinationIndex: combinationIndex,
                            newPrice: price,
                          ),
                    );
                  },
                  onEditItemLevelPrice:
                      (defaultPrice, currentCustomPrice) {
                    _showEditPriceDialog(
                      itemName: item['itemName'],
                      subtitle: null,
                      defaultPrice: defaultPrice,
                      currentCustomPrice: currentCustomPrice,
                      onSave: (price) =>
                          _saveItemLevelPrice(
                            itemKey: item['itemKey'],
                            rawData: item['_raw'],
                            newPrice: price,
                          ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Item card ─────────────────────────────────────────────────────────────────
class _ItemPriceCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final LanguageProvider languageProvider;
  final String customerId;
  final void Function(int combinationIndex, double defaultPrice,
      double? currentCustomPrice) onEditCombinationPrice;
  final void Function(double defaultPrice, double? currentCustomPrice)
  onEditItemLevelPrice;

  const _ItemPriceCard({
    required this.item,
    required this.languageProvider,
    required this.customerId,
    required this.onEditCombinationPrice,
    required this.onEditItemLevelPrice,
  });

  @override
  Widget build(BuildContext context) {
    final combos = (item['combinations'] as List<Map<String, dynamic>>)
        .where((c) => c['hasCustomPrice'] == true)
        .toList();
    final bool anyCustom = item['anyCustomPrice'] as bool;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: anyCustom ? 2 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Item header ─────────────────────────────────────────
          ListTile(
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: item['image'] != null
                ? CircleAvatar(
              radius: 22,
              backgroundImage:
              MemoryImage(base64Decode(item['image'])),
            )
                : CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFFFFE0CC),
              child: const Icon(Icons.shopping_bag,
                  size: 20, color: Color(0xFFFF8A65)),
            ),
            title: Text(
              item['itemName'],
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: (item['unit'] as String).isNotEmpty
                ? Text(item['unit'],
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade500))
                : null,
            trailing: anyCustom
                ? Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: Text(
                languageProvider.isEnglish ? 'Custom' : 'کسٹم',
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.purple.shade700,
                    fontWeight: FontWeight.bold),
              ),
            )
                : null,
          ),

          // ── Combinations table ───────────────────────────────────
          if (combos.isNotEmpty) ...[
            const Divider(height: 1, indent: 12, endIndent: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Column(
                children: [
                  // Table header
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                            flex: 2,
                            child: Text(
                              languageProvider.isEnglish
                                  ? 'Length'
                                  : 'لمبائی',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600),
                            )),
                        Expanded(
                            flex: 2,
                            child: Text(
                              languageProvider.isEnglish
                                  ? 'Body Type'
                                  : 'باڈی قسم',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600),
                            )),
                        Expanded(
                            flex: 2,
                            child: Text(
                              languageProvider.isEnglish
                                  ? 'Default'
                                  : 'ڈیفالٹ',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600),
                            )),
                        Expanded(
                            flex: 3,
                            child: Text(
                              languageProvider.isEnglish
                                  ? 'Customer'
                                  : 'کسٹمر',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600),
                            )),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Table rows
                  ...combos.asMap().entries.map((entry) {
                    final i = entry.key;
                    final c = entry.value;
                    return _CombinationRow(
                      combo: c,
                      onEdit: () => onEditCombinationPrice(
                        i,
                        c['defaultPrice'] as double,
                        c['hasCustomPrice'] == true
                            ? c['customerPrice'] as double
                            : null,
                      ),
                    );
                  }),
                ],
              ),
            ),
          ] else if (item['hasCustomPrice'] == true) ...[
            // No combinations: show item-level price
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _ItemLevelPriceRow(
                item: item,
                onEdit: () => onEditItemLevelPrice(
                  item['defaultPrice'] as double,
                  item['hasCustomPrice'] == true
                      ? item['customerPrice'] as double
                      : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Single combination row (now with edit button) ─────────────────────────────
class _CombinationRow extends StatelessWidget {
  final Map<String, dynamic> combo;
  final VoidCallback onEdit;

  const _CombinationRow({required this.combo, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final bool hasCustom = combo['hasCustomPrice'] as bool;
    final double def = combo['defaultPrice'] as double;
    final double cust = combo['customerPrice'] as double;

    PriceDiff diff = PriceDiff.same;
    if (hasCustom) {
      if (cust < def) diff = PriceDiff.discount;
      if (cust > def) diff = PriceDiff.premium;
    }

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
                flex: 2,
                child: Text(combo['length'],
                    style: const TextStyle(fontSize: 12))),
            Expanded(
                flex: 2,
                child: Text(combo['bodyType'],
                    style: const TextStyle(fontSize: 12))),
            Expanded(
              flex: 2,
              child: Text(
                '${def.toStringAsFixed(2)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: hasCustom && diff != PriceDiff.same
                      ? Colors.grey.shade400
                      : Colors.black87,
                  decoration: hasCustom && diff != PriceDiff.same
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (hasCustom)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${cust.toStringAsFixed(2)}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: diff == PriceDiff.discount
                                ? Colors.green.shade700
                                : diff == PriceDiff.premium
                                ? Colors.red.shade600
                                : Colors.black87,
                          ),
                        ),
                        if (diff != PriceDiff.same)
                          _DiffBadge(
                              priceDiff: diff,
                              defaultPrice: def,
                              customerPrice: cust),
                      ],
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Text('Default',
                          style: TextStyle(
                              fontSize: 9, color: Colors.grey)),
                    ),
                  const SizedBox(width: 4),
                  // ── Edit button ──
                  GestureDetector(
                    onTap: onEdit,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border:
                        Border.all(color: Colors.orange.shade200),
                      ),
                      child: Icon(Icons.edit,
                          size: 14, color: Colors.orange.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Item-level price row (with edit button) ───────────────────────────────────
class _ItemLevelPriceRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onEdit;

  const _ItemLevelPriceRow({required this.item, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final bool hasCustom = item['hasCustomPrice'] as bool;
    final double def = item['defaultPrice'] as double;
    final double cust = item['customerPrice'] as double;

    PriceDiff diff = PriceDiff.same;
    if (hasCustom) {
      if (cust < def) diff = PriceDiff.discount;
      if (cust > def) diff = PriceDiff.premium;
    }

    return Row(
      children: [
        Expanded(
          child: Text('Default: ${def.toStringAsFixed(2)} rs',
              style: TextStyle(
                fontSize: 12,
                color: hasCustom ? Colors.grey.shade500 : Colors.black87,
                decoration: hasCustom && diff != PriceDiff.same
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              )),
        ),
        if (hasCustom)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${cust.toStringAsFixed(2)} rs',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: diff == PriceDiff.discount
                      ? Colors.green.shade700
                      : diff == PriceDiff.premium
                      ? Colors.red.shade600
                      : Colors.black87,
                ),
              ),
              if (diff != PriceDiff.same)
                _DiffBadge(
                    priceDiff: diff,
                    defaultPrice: def,
                    customerPrice: cust),
            ],
          )
        else
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Text('Default',
                style: TextStyle(fontSize: 10, color: Colors.grey)),
          ),
        const SizedBox(width: 8),
        // ── Edit button ──
        GestureDetector(
          onTap: onEdit,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit, size: 14, color: Colors.orange.shade700),
                const SizedBox(width: 4),
                Text('Edit',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────
enum PriceDiff { discount, premium, same }

class _DiffBadge extends StatelessWidget {
  final PriceDiff priceDiff;
  final double defaultPrice;
  final double customerPrice;

  const _DiffBadge(
      {required this.priceDiff,
        required this.defaultPrice,
        required this.customerPrice});

  @override
  Widget build(BuildContext context) {
    final diff = customerPrice - defaultPrice;
    final pct =
    defaultPrice > 0 ? (diff / defaultPrice * 100).abs() : 0.0;
    final isDiscount = priceDiff == PriceDiff.discount;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: isDiscount ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDiscount
              ? Colors.green.shade300
              : Colors.red.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDiscount ? Icons.arrow_downward : Icons.arrow_upward,
            size: 9,
            color: isDiscount
                ? Colors.green.shade700
                : Colors.red.shade600,
          ),
          const SizedBox(width: 2),
          Text(
            '${pct.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isDiscount
                  ? Colors.green.shade700
                  : Colors.red.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final Color textColor;

  const _SummaryChip(
      {required this.label,
        required this.count,
        required this.color,
        required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(20)),
      child: Text('$label: $count',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor)),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withOpacity(0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.white : Colors.white54,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? const Color(0xFFFF8A65) : Colors.white,
          ),
        ),
      ),
    );
  }
}