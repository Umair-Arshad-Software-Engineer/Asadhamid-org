import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../Models/itemModel.dart';
import '../Provider/customerprovider.dart';
import '../Provider/lanprovider.dart';
import 'package:flutter/rendering.dart';



class QuotationPage extends StatefulWidget {
  final String? quotationId;
  final Map<dynamic, dynamic>? existingQuotation;

  const QuotationPage({
    Key? key,
    this.quotationId,
    this.existingQuotation,
  });

  @override
  _QuotationPageState createState() => _QuotationPageState();
}

class _QuotationPageState extends State<QuotationPage> {
  List<Item> _items = [];
  String? _selectedCustomerName;
  String? _selectedCustomerId;
  double _discount = 0.0;
  TextEditingController _discountController = TextEditingController();
  List<Map<String, dynamic>> _quotationRows = [];
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  TextEditingController _referenceController = TextEditingController();
  TextEditingController _termsController = TextEditingController();
  Map<String, Map<String, double>> _customerItemPrices = {};
  TextEditingController _biltiNumberController = TextEditingController();
  TextEditingController _transportCompanyController = TextEditingController();
// Add these alongside _driverNameController and _signatureController
  TextEditingController _driverPhoneController = TextEditingController();
  TextEditingController _deliveryCarNumberController = TextEditingController();
  // Auto-reference variables
  bool _isAutoReference = true;
  String _prefix = 'A';
  int _lastNumber = 0;
  final TextEditingController _autoReferenceController = TextEditingController();
  String? _selectedCustomerSerial;
  Map<String, int> _customerLastNumbers = {};
  String? _lastReferenceNumber;

  // Add these with the other controllers
  TextEditingController _totalQtyController = TextEditingController();
  TextEditingController _driverNameController = TextEditingController();
  TextEditingController _signatureController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchItems();
    _fetchCustomers();

    // Initialize with 5 rows if empty
    if (_quotationRows.isEmpty) {
      for (int i = 0; i < 5; i++) {
        _quotationRows.add({
          'total': 0.0,
          'rate': 0.0,
          'qty': 0.0,
          'description': '',
          'itemName': '',
          'size': '',
          'calculationType': 'quantity',
          'weightPerUnit': null,
          'weightUnit': 'kg',
          'totalWeight': 0.0,
          'manualWeightEntry': false,
          'itemNameController': TextEditingController(),
          'rateController': TextEditingController(),
          'qtyController': TextEditingController(),
          'descriptionController': TextEditingController(),
          'sizeController': TextEditingController(),
          'lengthController': TextEditingController(),
          'bodyTypeController': TextEditingController(),
          'weightController': TextEditingController(),
        });
      }
    }

    final now = DateTime.now();
    _dateController.text = DateFormat('yyyy-MM-dd HH:mm').format(now);

    // Initialize new fields
    _biltiNumberController.clear();
    _transportCompanyController.clear();

    if (widget.existingQuotation != null) {
      _loadExistingQuotation();
    } else {
      _initializeReferenceNumber();
    }
  }


  // ============================================================
// STEP 1: Add this import at the top of your file (already there)
//
// ============================================================

// ============================================================
// STEP 2: Add this helper method inside _QuotationPageState
// ============================================================

  Future<Uint8List> _renderTextAsImage(
      String text, {
        double fontSize = 18,
        double width = 80,
        double height = 26,
      })
  async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // White background
    final bgPaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

    // Draw text
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF000000),
          fontSize: fontSize,
          fontFamily: null, // uses system font which supports Unicode fractions
        ),
      ),
      textDirection: ui.TextDirection.ltr,  // <-- use ui. prefix here
      maxLines: 1,
    );
    textPainter.layout(maxWidth: width - 4);
    textPainter.paint(
      canvas,
      Offset(2, (height - textPainter.height) / 2),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

// ============================================================
// STEP 3: Replace your entire _generateQuotationPDF() with this
// ============================================================

  Future<Uint8List> _generateQuotationPDF() async {
    final pdf = pw.Document();

    // Get company logo
    Uint8List? logoBytes;
    try {
      final ByteData logoData = await rootBundle.load('assets/images/logo.png');
      logoBytes = logoData.buffer.asUint8List();
    } catch (e) {
      // Logo not found, will use text fallback
    }

    final footerLogo = pw.MemoryImage(
      (await rootBundle.load('assets/images/devlogo.png')).buffer.asUint8List(),
    );

    // ── Pre-filter valid rows BEFORE building page ──────────────
    final validRows = _quotationRows.where((row) {
      final itemName = row['itemName'] ?? '';
      return itemName.toString().trim().isNotEmpty;
    }).toList();

    // ── Pre-render Size & Length cells as PNG images ─────────────
    // This is the key fix: Flutter's own text engine handles ½ ¼ ¾ etc.
    final List<Uint8List> sizeImages = [];
    final List<Uint8List> lengthImages = [];

    for (final row in validRows) {
      final sizeText = row['size']?.toString() ?? '';
      final lengthText = row['length']?.toString() ?? '';

      final sizeImg = await _renderTextAsImage(
        sizeText.isNotEmpty ? sizeText : '-',
        width: 70,
        height: 26,
      );
      final lengthImg = await _renderTextAsImage(
        lengthText.isNotEmpty ? lengthText : '-',
        width: 70,
        height: 26,
      );

      sizeImages.add(sizeImg);
      lengthImages.add(lengthImg);
    }

    // Get customer details
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    Customer pdfCustomer = customerProvider.customers.firstWhere(
          (c) => c.id == _selectedCustomerId,
      orElse: () => Customer(
        id: 'unknown',
        name: _selectedCustomerName ?? 'No Customer Selected',
        phone: '',
        address: '',
        city: '',
      ),
    );

    // ── Build PDF ────────────────────────────────────────────────
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),

        // ── HEADER ──────────────────────────────────────────────
        header: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 20),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                // Logo
                logoBytes != null
                    ? pw.Container(
                  width: 80,
                  height: 80,
                  child: pw.Image(pw.MemoryImage(logoBytes)),
                )
                    : pw.Container(
                  width: 80,
                  height: 80,
                  decoration: pw.BoxDecoration(
                    color: PdfColors.orangeAccent,
                    borderRadius: pw.BorderRadius.circular(40),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      'MGI',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                ),

                // Company Info
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'MUGHAL GROUP OF INDUSTRIES',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Specialist in Bolt, Nut, Washer & Soft/Hard Steel Wire.\n'
                          ' All Sizes Available | Custom Manufacturing | Factory Rate',
                      style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Address:  Gujranwala, Pakistan',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Phone:  03704219219 // 03713084600 | Email: mughalgroupofindustrie@gmil.com',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                    ),
                  ],
                ),

                // Gate Pass label
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.orangeAccent,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'Gate Pass',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        '#${_referenceController.text.isNotEmpty ? _referenceController.text : 'Q${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}'}',
                        style: pw.TextStyle(fontSize: 12, color: PdfColors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },

        // ── FOOTER ──────────────────────────────────────────────
        footer: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 20),
            padding: const pw.EdgeInsets.all(10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  children: [
                    pw.Text(
                      'Developed By: Tech Soft',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      '0341-6426617',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.Image(footerLogo, width: 50, height: 40),
              ],
            ),
          );
        },

        // ── BODY ────────────────────────────────────────────────
        build: (pw.Context context) {
          if (validRows.isEmpty) {
            return [
              pw.Center(
                child: pw.Text(
                  'No items to display',
                  style: pw.TextStyle(fontSize: 16, color: PdfColors.grey600),
                ),
              ),
            ];
          }

          return [
            // ── Customer / Quotation details block ───────────────
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 20),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey300),
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Bill To:',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue800,
                            ),
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text(
                            pdfCustomer.name,
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          if (pdfCustomer.address.isNotEmpty ||
                              pdfCustomer.city.isNotEmpty ||
                              pdfCustomer.phone.isNotEmpty)
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                if (pdfCustomer.address.isNotEmpty)
                                  pw.Text(pdfCustomer.address,
                                      style: pw.TextStyle(
                                          fontSize: 11,
                                          color: PdfColors.grey700)),
                                if (pdfCustomer.city.isNotEmpty)
                                  pw.Text(pdfCustomer.city,
                                      style: pw.TextStyle(
                                          fontSize: 11,
                                          color: PdfColors.grey700)),
                                if (pdfCustomer.phone.isNotEmpty)
                                  pw.Text('Phone: ${pdfCustomer.phone}',
                                      style: pw.TextStyle(
                                          fontSize: 11,
                                          color: PdfColors.grey700)),
                              ],
                            ),
                          if (_selectedCustomerId != null &&
                              _selectedCustomerId!.startsWith('manual_'))
                            pw.Text(
                              '(New Customer)',
                              style: pw.TextStyle(
                                  fontSize: 10, color: PdfColors.green700),
                            ),
                          pw.SizedBox(height: 8),
                          pw.Text(
                            'Date: ${_dateController.text}',
                            style: pw.TextStyle(
                                fontSize: 11, color: PdfColors.grey700),
                          ),
                          if (_referenceController.text.isNotEmpty)
                            pw.Text(
                              'Reference: ${_referenceController.text}',
                              style: pw.TextStyle(
                                  fontSize: 11, color: PdfColors.grey700),
                            ),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 20),
                ],
              ),
            ),

            // ── Items table ──────────────────────────────────────
            // We build the table manually using pw.Table so we can put
            // pw.Image widgets inside cells for Size and Length columns.
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 20),
              child: pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: {
                  0: const pw.FlexColumnWidth(0.7),  // Sr#
                  1: const pw.FlexColumnWidth(1.8),  // Description
                  2: const pw.FlexColumnWidth(1.0),  // Size   ← image
                  3: const pw.FlexColumnWidth(1.0),  // Length ← image
                  4: const pw.FlexColumnWidth(1.6),  // Body Type
                  5: const pw.FlexColumnWidth(0.8),  // Qty
                  6: const pw.FlexColumnWidth(1.2),  // Weight
                },
                children: [
                  // Header row
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColors.blue50),
                    children: [
                      'Sr#',
                      'Description',
                      'Size',
                      'Length',
                      'Body Type',
                      'Qty',
                      'Weight',
                    ].map((header) {
                      return pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6, vertical: 8),
                        child: pw.Text(
                          header,
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue800,
                            fontSize: 10,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      );
                    }).toList(),
                  ),

                  // Data rows
                  ...List.generate(validRows.length, (index) {
                    final row = validRows[index];
                    final description = row['description']?.toString() ?? '';
                    final bodyType = row['bodyType']?.toString() ?? '';
                    final qty = (row['qty'] ?? 0.0).toStringAsFixed(2);
                    final weight =
                        row['weightController']?.text?.toString() ?? 'N/A';

                    // Alternate row background
                    final bg =
                    index % 2 == 0 ? PdfColors.white : PdfColors.grey100;

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(color: bg),
                      children: [
                        // Sr#
                        _pdfCell((index + 1).toString()),

                        // Description
                        _pdfCell(
                            description.isNotEmpty ? description : '-'),

                        // ── SIZE as image ──────────────────────
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(3),
                          child: pw.Image(
                            pw.MemoryImage(sizeImages[index]),
                            width: 60,
                            height: 22,
                            fit: pw.BoxFit.contain,
                          ),
                        ),

                        // ── LENGTH as image ────────────────────
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(3),
                          child: pw.Image(
                            pw.MemoryImage(lengthImages[index]),
                            width: 60,
                            height: 22,
                            fit: pw.BoxFit.contain,
                          ),
                        ),

                        // Body Type
                        _pdfCell(bodyType.isNotEmpty ? bodyType : '-'),

                        // Qty
                        _pdfCell(qty, align: pw.TextAlign.center),

                        // Weight
                        _pdfCell(weight, align: pw.TextAlign.center),
                      ],
                    );
                  }),
                ],
              ),
            ),

            // ── Total Qty & Total Weight summary boxes ───────────
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 20),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _pdfSummaryBox(
                      'Total Qty:',
                      _calculateTotalQuantity().toStringAsFixed(2)),
                  _pdfSummaryBox(
                      'Total Weight:',
                      '${_calculateTotalWeight().toStringAsFixed(2)} KG'),
                ],
              ),
            ),

            // ── Driver / Signature ───────────────────────────────
            // ── Driver / Signature / Car ─────────────────────────────
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 20),
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // ── Row 1: Driver Name | Driver Phone | Car Number ──
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Driver Name
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Driver Name:',
                              style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey700,
                              ),
                            ),
                            pw.SizedBox(height: 6),
                            pw.Text(
                              _driverNameController.text.isNotEmpty
                                  ? _driverNameController.text
                                  : '____________________',
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      // Driver Phone  ← NEW
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Driver Phone:',
                              style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey700,
                              ),
                            ),
                            pw.SizedBox(height: 6),
                            pw.Text(
                              _driverPhoneController.text.isNotEmpty
                                  ? _driverPhoneController.text
                                  : '____________________',
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      // Car / Vehicle Number  ← NEW
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Vehicle No:',
                              style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey700,
                              ),
                            ),
                            pw.SizedBox(height: 6),
                            pw.Text(
                              _deliveryCarNumberController.text.isNotEmpty
                                  ? _deliveryCarNumberController.text
                                  : '____________________',
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 16),
                  pw.Divider(color: PdfColors.grey200),
                  pw.SizedBox(height: 10),

                  // ── Row 2: Signature ──────────────────────────────────
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Signature:',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.SizedBox(height: 20),
                      pw.Text(
                        _signatureController.text.isNotEmpty
                            ? _signatureController.text
                            : '____________________',
                        style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Terms ────────────────────────────────────────────
            if (_termsController.text.isNotEmpty)
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 20),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Terms & Conditions:',
                      style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey800),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      _termsController.text,
                      style: pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ),

            pw.Spacer(),

            // ── Thank-you footer note ────────────────────────────
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.orange50,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'Thank you for your business!',
                        style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.orange800),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'For any queries, please contact us at  03000450050 / 03000450020\n'
                            'or email at mughalgroupofindustrie@gmil.com',
                        style: pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey700),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

// ============================================================
// STEP 4: Add these two tiny private helper methods
//         anywhere inside _QuotationPageState
// ============================================================

  /// Plain text cell for the PDF table
  pw.Widget _pdfCell(String text,
      {pw.TextAlign align = pw.TextAlign.left})
  {
    return pw.Padding(
      padding:
      const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 10),
        textAlign: align,
      ),
    );
  }

  /// Small summary box (Total Qty / Total Weight)
  pw.Widget _pdfSummaryBox(String label, String value) {
    return pw.Container(
      width: 150,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 16, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }








  Future<void> _initializeReferenceNumber() async {
    if (_selectedCustomerId != null && _selectedCustomerSerial != null) {
      // Get the last reference number for this customer
      final lastRef = await _getLastReferenceNumber(_selectedCustomerId!);

      setState(() {
        _lastReferenceNumber = lastRef;
      });

      if (_isAutoReference) {
        // Generate the next reference number without saving it yet
        final nextRef = await _generateNextReferenceNumber(increment: false);
        _autoReferenceController.text = nextRef;
        _referenceController.text = nextRef;
      }
    }
  }

  Future<String> _generateCustomerSerialReference({bool increment = true}) async {
    if (_selectedCustomerId == null || _selectedCustomerSerial == null) {
      return 'Unknown-0001';
    }

    // Get the last used number for this customer from Firebase
    final counterRef = FirebaseDatabase.instance.ref()
        .child('quotationReferenceCounters')
        .child(_selectedCustomerId!);
    final snapshot = await counterRef.get();

    int lastNumber = 0;
    if (snapshot.exists) {
      final data = snapshot.value;
      lastNumber = (data is int) ? data : (data as Map?)?['lastNumber'] ?? 0;
    }

    if (increment) {
      lastNumber++;
    }

    // Save the new counter value only if incrementing
    if (increment) {
      await counterRef.set({
        'lastNumber': lastNumber,
        'customerSerial': _selectedCustomerSerial,
        'lastUpdated': DateTime.now().toIso8601String(),
      });
    }

    return '${_selectedCustomerSerial}-${lastNumber.toString().padLeft(4, '0')}';
  }

  Future<void> _toggleReferenceMode(bool isAuto) async {
    setState(() {
      _isAutoReference = isAuto;
    });

    if (isAuto && _selectedCustomerId != null && _selectedCustomerSerial != null) {
      // Generate without incrementing the counter
      final autoRef = await _generateNextReferenceNumber(increment: false);
      _autoReferenceController.text = autoRef;
      _referenceController.text = autoRef;
    } else if (!isAuto) {
      _referenceController.text = '';
    }
  }

  Future<String> _generateNextReferenceNumber({bool increment = true}) async {
    if (_selectedCustomerId == null || _selectedCustomerSerial == null) {
      return 'Unknown-0001';
    }

    if (increment) {
      // Get and increment the reference number
      final nextNumber = await _getNextReferenceNumber(
          _selectedCustomerId!,
          _selectedCustomerSerial!
      );
      return '${_selectedCustomerSerial}-${nextNumber.toString().padLeft(4, '0')}';
    } else {
      // Just get the current number without incrementing
      final lastRef = await _getLastReferenceNumber(_selectedCustomerId!);

      if (lastRef.isNotEmpty) {
        // Extract the number from the last reference and increment by 1 for display
        final parts = lastRef.split('-');
        if (parts.length == 2) {
          final lastNumber = int.tryParse(parts[1]) ?? 0;
          return '${_selectedCustomerSerial}-${(lastNumber + 1).toString().padLeft(4, '0')}';
        }
      }

      // No previous reference found, start from 1
      return '${_selectedCustomerSerial}-0001';
    }
  }

  Widget _buildAdditionalInfoSection(BuildContext context, LanguageProvider languageProvider) {
    double totalQty = _quotationRows.fold(0.0, (sum, row) => sum + (row['qty'] ?? 0.0));
    _totalQtyController.text = totalQty.toStringAsFixed(2);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.cyan[700], size: 24),
                const SizedBox(width: 8),
                Text(
                  languageProvider.isEnglish ? 'Additional Information' : 'اضافی معلومات',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.cyan[800]),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Total Quantity (read-only)
            _buildTextField(
              controller: _totalQtyController,
              label: languageProvider.isEnglish ? 'Total Quantity' : 'کل مقدار',
              icon: Icons.calculate,
              readOnly: true,
            ),
            const SizedBox(height: 16),

            // Driver Name
            _buildTextField(
              controller: _driverNameController,
              label: languageProvider.isEnglish ? 'Driver Name' : 'ڈرائیور کا نام',
              icon: Icons.person,
            ),
            const SizedBox(height: 16),

            // Driver Phone  ← NEW
            _buildTextField(
              controller: _driverPhoneController,
              label: languageProvider.isEnglish ? 'Driver Phone' : 'ڈرائیور فون',
              icon: Icons.phone,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),

            // Delivery Car Number  ← NEW
            _buildTextField(
              controller: _deliveryCarNumberController,
              label: languageProvider.isEnglish ? 'Car / Vehicle Number' : 'گاڑی نمبر',
              icon: Icons.directions_car,
            ),
            const SizedBox(height: 16),

            // Signature
            _buildTextField(
              controller: _signatureController,
              label: languageProvider.isEnglish ? 'Signature' : 'دستخط',
              icon: Icons.draw,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Future<int> _getNextReferenceNumber(String customerId, String customerSerial) async {
    try {
      // Get or create the counter for this customer
      final counterRef = FirebaseDatabase.instance.ref()
          .child('quotationReferenceCounters')
          .child(customerId);
      final snapshot = await counterRef.get();

      int lastNumber = 0;
      if (snapshot.exists) {
        final data = snapshot.value;
        lastNumber = (data is int) ? data : (data as Map?)?['lastNumber'] ?? 0;
      }

      // Increment the counter
      lastNumber++;

      // Save the new counter value
      await counterRef.set({
        'lastNumber': lastNumber,
        'customerSerial': customerSerial,
        'lastUpdated': DateTime.now().toIso8601String(),
      });

      return lastNumber;
    } catch (e) {
      print('Error getting next reference number: $e');
      return 1; // Fallback to 1
    }
  }

  Future<String> _getLastReferenceNumber(String customerId) async {
    try {
      final counterRef = FirebaseDatabase.instance.ref()
          .child('quotationReferenceCounters')
          .child(customerId);
      final snapshot = await counterRef.get();

      if (snapshot.exists) {
        final data = snapshot.value;
        final lastNumber = (data is int) ? data : (data as Map?)?['lastNumber'] ?? 0;
        final customerSerial = (data is Map) ? data['customerSerial']?.toString() : null;

        if (lastNumber > 0 && customerSerial != null && customerSerial.isNotEmpty) {
          return '$customerSerial-${lastNumber.toString().padLeft(4, '0')}';
        }
      }

      return ''; // No previous reference found
    } catch (e) {
      print('Error getting last reference number: $e');
      return '';
    }
  }

  void _fetchCustomerSerial(String customerId) async {
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    final customer = customerProvider.customers.firstWhere(
          (c) => c.id == customerId,
      orElse: () => Customer(
        id: '',
        name: 'N/A',
        phone: '',
        address: '',
        city: '',
      ),
    );

    if (customer.id.isNotEmpty) {
      setState(() {
        _selectedCustomerSerial = customer.customerSerial;
      });
      _onCustomerChanged();
    }
  }

  Future<void> _onCustomerChanged() async {
    if (_isAutoReference && _selectedCustomerId != null && _selectedCustomerSerial != null) {
      final autoRef = await _generateNextReferenceNumber(increment: false);
      setState(() {
        _autoReferenceController.text = autoRef;
        _referenceController.text = autoRef;
      });
    }
    // Fetch last reference number for display
    if (_selectedCustomerId != null) {
      final lastRef = await _getLastReferenceNumber(_selectedCustomerId!);
      setState(() {
        _lastReferenceNumber = lastRef;
      });
    }
  }

  void _loadExistingQuotation() {
    final quotation = widget.existingQuotation!;
    final customer = quotation['customer'] as Map<dynamic, dynamic>;
    final items = quotation['items'] as List<dynamic>;

    setState(() {
      _selectedCustomerId = customer['id'];
      _selectedCustomerName = customer['name'];
      _dateController.text = quotation['date'] ?? DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

      // Load reference number - if it exists and matches customer serial pattern, set auto mode to false
      final refNumber = quotation['reference'] ?? '';
      if (refNumber.isNotEmpty) {
        _referenceController.text = refNumber;
        _autoReferenceController.text = refNumber;
        // Check if reference matches customer serial pattern
        if (_selectedCustomerSerial != null && refNumber.startsWith(_selectedCustomerSerial!)) {
          _isAutoReference = true;
        } else {
          _isAutoReference = false;
        }
      } else {
        _isAutoReference = true;
      }

      _termsController.text = quotation['terms'] ?? '';
      _discount = quotation['discount'] ?? 0.0;
      _discountController.text = (quotation['discount'] ?? 0.0).toString();
      _biltiNumberController.text = quotation['biltiNumber'] ?? '';
      _transportCompanyController.text = quotation['transportCompany'] ?? '';
      _driverPhoneController.text = quotation['driverPhone'] ?? '';
      _deliveryCarNumberController.text = quotation['deliveryCarNumber'] ?? '';
      _driverNameController.text = quotation['driverName'] ?? '';
      _signatureController.text = quotation['signature'] ?? '';
      _quotationRows.clear();

      for (var item in items) {
        final itemName = item['itemName'] ?? '';
        final parsedBOM = _parseBOMName(itemName);

        final sizeController = TextEditingController(text: item['size'] ?? parsedBOM['size'] ?? '');
        final lengthController = TextEditingController(text: item['length'] ?? parsedBOM['length'] ?? '');
        final bodyTypeController = TextEditingController(text: item['bodyType'] ?? parsedBOM['bodyType'] ?? '');
        final itemNameController = TextEditingController(text: itemName);
        final rateController = TextEditingController(text: (item['rate'] ?? 0.0).toString());
        final qtyController = TextEditingController(text: (item['quantity'] ?? 0.0).toString());
        final descriptionController = TextEditingController(text: item['description'] ?? '');
        final weightController = TextEditingController();

        // Calculate and set weight display
        double? totalWeight = item['totalWeight'];
        String? weightUnit = item['weightUnit'] ?? 'kg';
        double? weightPerUnit = item['weightPerUnit'];

        if (weightPerUnit != null && weightPerUnit > 0) {
          double qty = (item['quantity'] ?? 0.0).toDouble();
          weightController.text = '${weightPerUnit.toStringAsFixed(2)} $weightUnit';
        } else if (totalWeight != null && totalWeight > 0) {
          weightController.text = '${totalWeight.toStringAsFixed(2)} $weightUnit';
        }

        _quotationRows.add({
          'itemName': itemName,
          'size': item['size'] ?? parsedBOM['size'] ?? '',
          'length': item['length'] ?? parsedBOM['length'] ?? '',
          'bodyType': item['bodyType'] ?? parsedBOM['bodyType'] ?? '',
          'description': item['description'] ?? '',
          'qty': (item['quantity'] ?? 0.0).toDouble(),
          'rate': (item['rate'] ?? 0.0).toDouble(),
          'total': (item['total'] ?? 0.0).toDouble(),
          'calculationType': item['calculationType'] ?? 'quantity',
          'weightPerUnit': item['weightPerUnit'],
          'weightUnit': item['weightUnit'] ?? 'kg',
          'totalWeight': totalWeight,
          'itemNameController': itemNameController,
          'sizeController': sizeController,
          'lengthController': lengthController,
          'bodyTypeController': bodyTypeController,
          'rateController': rateController,
          'qtyController': qtyController,
          'descriptionController': descriptionController,
          'weightController': weightController,
          'lengthBodyCombination': item['lengthBodyCombination'],
        });
      }

      // Add empty rows if needed
      if (_quotationRows.length < 5) {
        for (int i = _quotationRows.length; i < 5; i++) {
          _addNewRow();
        }
      }

      // Fetch customer serial if available
      if (_selectedCustomerId != null) {
        _fetchCustomerSerial(_selectedCustomerId!);
      }
    });
  }

  Map<String, String> _parseBOMName(String bomName) {
    Map<String, String> result = {
      'size': '',
      'length': '',
      'bodyType': '',
      'fullName': bomName
    };

    if (bomName.contains('|')) {
      final parts = bomName.split('|').map((part) => part.trim()).toList();

      if (parts.length >= 3) {
        result['size'] = parts[0];
        result['length'] = parts[1];
        result['bodyType'] = parts[2];
      } else if (parts.length == 2) {
        result['size'] = parts[0];
        result['length'] = parts[1];
      } else if (parts.length == 1) {
        result['size'] = parts[0];
      }
    } else {
      result['size'] = bomName;
    }

    return result;
  }

  Future<void> _fetchCustomers() async {
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    await customerProvider.fetchCustomers();
  }

  void _fetchCustomerPrices(String customerId) async {
    final DatabaseReference pricesRef = FirebaseDatabase.instance.ref().child('items');
    final DatabaseEvent snapshot = await pricesRef.once();

    if (snapshot.snapshot.exists) {
      final Map<dynamic, dynamic> itemsMap = snapshot.snapshot.value as Map<dynamic, dynamic>;
      Map<String, Map<String, double>> prices = {};

      itemsMap.forEach((itemId, itemData) {
        final item = itemData as Map<dynamic, dynamic>;
        if (item['customerBasePrices'] != null) {
          final customerPrices = item['customerBasePrices'] as Map<dynamic, dynamic>;
          if (customerPrices.containsKey(customerId)) {
            final price = double.tryParse(customerPrices[customerId].toString()) ?? 0.0;
            if (!prices.containsKey(itemId)) {
              prices[itemId] = {};
            }
            prices[itemId]![customerId] = price;
          }
        }
      });

      setState(() {
        _customerItemPrices = prices;
      });
    }
  }

  Future<void> _fetchItems() async {
    try {
      print('Fetching items...');
      final DatabaseReference itemsRef = FirebaseDatabase.instance.ref().child('items');
      final DatabaseEvent snapshot = await itemsRef.once();
      print('Snapshot exists: ${snapshot.snapshot.exists}');

      if (snapshot.snapshot.exists) {
        final Map<dynamic, dynamic> itemsMap = snapshot.snapshot.value as Map<dynamic, dynamic>;
        print('Items count: ${itemsMap.length}');

        setState(() {
          _items = itemsMap.entries.map((entry) {
            print('Processing item: ${entry.key}');
            return Item.fromMap(entry.value as Map<dynamic, dynamic>, entry.key as String);
          }).toList();
          print('Items loaded: ${_items.length}');
        });
      } else {
        print('No items found in snapshot');
        setState(() => _items = []);
      }
    } catch (e) {
      print('Error fetching items: $e');
      setState(() => _items = []);
    }
  }

  void _addNewRow() {
    setState(() {
      _quotationRows.add({
        'total': 0.0,
        'rate': 0.0,
        'qty': 0.0,
        'size': '',
        'length': '',
        'bodyType': '',
        'description': '',
        'itemName': '',
        'calculationType': 'quantity',
        'weightPerUnit': null,
        'weightUnit': 'kg',
        'totalWeight': 0.0,
        'manualWeightEntry': false,
        'itemNameController': TextEditingController(),
        'sizeController': TextEditingController(),
        'lengthController': TextEditingController(),
        'bodyTypeController': TextEditingController(),
        'rateController': TextEditingController(),
        'qtyController': TextEditingController(),
        'descriptionController': TextEditingController(),
        'weightController': TextEditingController(),
      });
    });
  }

  void _updateRow(int index, String field, dynamic value) {
    setState(() {
      _quotationRows[index][field] = value;

      // Update the corresponding controller text
      if (field == 'size' && _quotationRows[index]['sizeController'] != null) {
        _quotationRows[index]['sizeController'].text = value.toString();
      } else if (field == 'length' && _quotationRows[index]['lengthController'] != null) {
        _quotationRows[index]['lengthController'].text = value.toString();
      } else if (field == 'bodyType' && _quotationRows[index]['bodyTypeController'] != null) {
        _quotationRows[index]['bodyTypeController'].text = value.toString();
      }

      // Recalculate total when any of these fields change
      if (field == 'rate' || field == 'qty' || field == 'calculationType' ||
          field == 'weightPerUnit' || field == 'lengthBodyCombination') {
        _calculateTotalForRow(index);
      }
    });
  }

  void _calculateTotalForRow(int index) {
    double rate = _quotationRows[index]['rate'] ?? 0.0;
    double qty = _quotationRows[index]['qty'] ?? 0.0;
    String calculationType = _quotationRows[index]['calculationType'] ?? 'quantity';
    double? weightPerUnit = _quotationRows[index]['weightPerUnit'];
    String weightUnit = _quotationRows[index]['weightUnit'] ?? 'kg';

    // Calculate total weight (Qty × Weight per Unit)
    double? totalWeight;
    if (weightPerUnit != null && weightPerUnit > 0 && qty > 0) {
      totalWeight = weightPerUnit * qty;
      _quotationRows[index]['totalWeight'] = totalWeight;
    } else {
      totalWeight = _quotationRows[index]['totalWeight'];
    }

    double total = 0.0;

    if (calculationType == 'weight') {
      // Weight-based calculation: Use Total Weight × Rate
      if (totalWeight != null && totalWeight > 0) {
        total = rate * totalWeight;
      } else {
        // Fallback to quantity if no weight available
        total = rate * qty;
      }
    } else {
      // Quantity-based calculation: Qty × Rate
      total = rate * qty;
    }

    _quotationRows[index]['total'] = total;
    setState(() {});
  }

  String _calculateDisplayTotalWeight(int index) {
    double qty = _quotationRows[index]['qty'] ?? 0.0;
    String weightPerUnitText = _quotationRows[index]['weightController']?.text ?? '';

    // Parse weight per unit (could include unit like "10 kg")
    double weightPerUnit = 0.0;
    if (weightPerUnitText.isNotEmpty) {
      final parts = weightPerUnitText.trim().split(' ');
      weightPerUnit = double.tryParse(parts[0]) ?? 0.0;
    }

    if (qty > 0 && weightPerUnit > 0) {
      double totalWeight = qty * weightPerUnit;
      String unit = _quotationRows[index]['weightUnit'] ?? 'kg';
      return '${totalWeight.toStringAsFixed(2)} $unit';
    }

    return 'N/A';
  }

  void _handleWeightPerUnitInput(int index, String value) {
    if (value.isEmpty) {
      setState(() {
        _quotationRows[index]['weightPerUnit'] = null;
        _quotationRows[index]['totalWeight'] = null;
      });
      _calculateTotalForRow(index);
      return;
    }

    // Parse weight value and unit
    final parts = value.trim().split(' ');
    double? weightValue;
    String weightUnit = _quotationRows[index]['weightUnit'] ?? 'kg';

    if (parts.isNotEmpty) {
      weightValue = double.tryParse(parts[0]);

      // Try to extract unit if provided
      if (parts.length > 1) {
        final unit = parts.sublist(1).join(' ').toLowerCase();
        if (unit.contains('kg') || unit.contains('kilogram')) {
          weightUnit = 'kg';
        } else if (unit.contains('g') || unit.contains('gram')) {
          weightUnit = 'g';
        } else if (unit.contains('lb') || unit.contains('pound')) {
          weightUnit = 'lb';
        } else if (unit.contains('ton')) {
          weightUnit = 'ton';
        }
      }
    }

    if (weightValue != null && weightValue > 0) {
      // Calculate total weight
      double qty = _quotationRows[index]['qty'] ?? 0.0;
      double calculatedTotalWeight = weightValue * qty;

      setState(() {
        _quotationRows[index]['weightPerUnit'] = weightValue;
        _quotationRows[index]['weightUnit'] = weightUnit;
        _quotationRows[index]['totalWeight'] = calculatedTotalWeight;
      });

      _calculateTotalForRow(index);
    } else {
      setState(() {
        _quotationRows[index]['weightPerUnit'] = null;
        _quotationRows[index]['totalWeight'] = null;
      });
      _calculateTotalForRow(index);
    }
  }

  void _deleteRow(int index) {
    setState(() {
      final deletedRow = _quotationRows[index];
      deletedRow['itemNameController']?.dispose();
      deletedRow['sizeController']?.dispose();
      deletedRow['lengthController']?.dispose();
      deletedRow['bodyTypeController']?.dispose();
      deletedRow['rateController']?.dispose();
      deletedRow['qtyController']?.dispose();
      deletedRow['descriptionController']?.dispose();
      deletedRow['weightController']?.dispose();
      _quotationRows.removeAt(index);
    });
  }

  double _calculateSubtotal() {
    return _quotationRows.fold(0.0, (sum, row) => sum + (row['total'] ?? 0.0));
  }

  double _calculateGrandTotal() {
    double subtotal = _calculateSubtotal();
    return subtotal - _discount;
  }

  double _calculateTotalQuantity() {
    return _quotationRows.fold(0.0, (sum, row) => sum + (row['qty'] ?? 0.0));
  }

  Future<void> _saveQuotation() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);

    // Validate auto-reference
    if (_isAutoReference && (_selectedCustomerId == null || _selectedCustomerSerial == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(languageProvider.isEnglish
            ? 'Customer serial is required for auto reference'
            : 'آٹو ریفرنس کے لیے کسٹمر سیریل ضروری ہے')),
      );
      return;
    }

    if (_selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(languageProvider.isEnglish
            ? 'Please select a customer'
            : 'براہ کرم کسٹمر منتخب کریں')),
      );
      return;
    }

    if (_quotationRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(languageProvider.isEnglish
            ? 'Please add at least one item'
            : 'براہ کرم کم از کم ایک آئٹم شامل کریں')),
      );
      return;
    }

    try {
      // Generate auto reference if enabled
      String reference = _referenceController.text;
      if (_isAutoReference && _selectedCustomerId != null && _selectedCustomerSerial != null) {
        reference = await _generateCustomerSerialReference(increment: true);
      }

      final selectedCustomer = customerProvider.customers.firstWhere(
              (customer) => customer.id == _selectedCustomerId,
          orElse: () => Customer(
            id: 'unknown',
            name: 'Unknown Customer',
            phone: '',
            address: '',
            city: '',
          )
      );

      DateTime? quotationDateTime;
      try {
        quotationDateTime = DateFormat('yyyy-MM-dd HH:mm').parse(_dateController.text);
      } catch (e) {
        quotationDateTime = DateTime.now();
      }

      final quotationData = {
        'customer': {
          'id': _selectedCustomerId,
          'name': selectedCustomer.name,
          'phone': selectedCustomer.phone,
          'address': selectedCustomer.address,
        },
        'driverName': _driverNameController.text,
        'driverPhone': _driverPhoneController.text,       // ← NEW
        'deliveryCarNumber': _deliveryCarNumberController.text, // ← NEW
        'signature': _signatureController.text,
        'date': _dateController.text,
        'totalQuantity': _calculateTotalQuantity(), // Add this
        'dateTimestamp': quotationDateTime.millisecondsSinceEpoch,
        'reference': reference,
        'terms': _termsController.text,
        'biltiNumber': _biltiNumberController.text,
        'transportCompany': _transportCompanyController.text,
        'subtotal': _calculateSubtotal(),
        'discount': _discount,
        'grandTotal': _calculateGrandTotal(),
        'updatedAt': ServerValue.timestamp,
        'items': _quotationRows.map((row) {
          final quantity = row['qty'] ?? 0.0;
          final calculationType = row['calculationType'] ?? 'quantity';
          double? totalWeight = row['totalWeight'];
          String weightUnit = row['weightUnit'] ?? 'kg';

          // For manual weight entries, use the totalWeight directly
          // For auto-calculated, use weightPerUnit * quantity
          double? finalTotalWeight = totalWeight;
          if (calculationType == 'weight' && finalTotalWeight == null) {
            final weightPerUnit = row['weightPerUnit'];
            if (weightPerUnit != null) {
              finalTotalWeight = weightPerUnit * quantity;
            }
          }

          return {
            'itemName': row['itemName'] ?? '',
            'size': row['size'] ?? '',
            'length': row['length'] ?? '',
            'bodyType': row['bodyType'] ?? '',
            'description': row['description'] ?? '',
            'quantity': quantity,
            'rate': row['rate'] ?? 0.0,
            'total': row['total'] ?? 0.0,
            'calculationType': calculationType,
            'lengthBodyCombination': row['lengthBodyCombination'],
            'weightPerUnit': row['weightPerUnit'],
            'weightUnit': weightUnit,
            'totalWeight': finalTotalWeight,
            'weightInput': row['weightController']?.text ?? '', // Save manual input
          };
        }).toList(),
      };

      DatabaseReference ref;
      if (widget.quotationId != null) {
        ref = FirebaseDatabase.instance.ref().child('quotations').child(widget.quotationId!);
        await ref.update(quotationData);
      } else {
        ref = FirebaseDatabase.instance.ref().child('quotations').push();
        quotationData['createdAt'] = ServerValue.timestamp;
        quotationData['createdAtTimestamp'] = DateTime.now().millisecondsSinceEpoch;
        await ref.set(quotationData);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(languageProvider.isEnglish
            ? 'Quotation saved successfully'
            : 'کوٹیشن کامیابی سے محفوظ ہو گئی')),
      );

      if (widget.quotationId != null) {
        Navigator.pop(context);
      } else {
        _resetForm();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(languageProvider.isEnglish
            ? 'Error saving quotation: $e'
            : 'کوٹیشن محفوظ کرنے میں خرابی: $e')),
      );
    }
  }

  void _resetForm() {
    setState(() {
      _selectedCustomerId = null;
      _selectedCustomerName = null;
      _discount = 0.0;
      _discountController.clear();
      _referenceController.clear();
      _autoReferenceController.clear();
      _biltiNumberController.clear();
      _transportCompanyController.clear();
      _driverPhoneController.clear();
      _deliveryCarNumberController.clear();
      _dateController.text = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
      _termsController.clear();
      _quotationRows = [{
        'total': 0.0,
        'rate': 0.0,
        'qty': 0.0,
        'size': '',
        'length': '',
        'bodyType': '',
        'description': '',
        'itemName': '',
        'calculationType': 'quantity',
        'weightPerUnit': null,
        'weightUnit': 'kg',
        'totalWeight': 0.0,
        'itemNameController': TextEditingController(),
        'sizeController': TextEditingController(),
        'lengthController': TextEditingController(),
        'bodyTypeController': TextEditingController(),
        'rateController': TextEditingController(),
        'qtyController': TextEditingController(),
        'descriptionController': TextEditingController(),
        'weightController': TextEditingController(),
      }];
    });
  }

  double _calculateTotalWeight() {
    double totalWeight = 0.0;

    for (var row in _quotationRows) {
      // Try to get total weight from stored value first
      double? rowTotalWeight = row['totalWeight'];

      if (rowTotalWeight != null && rowTotalWeight > 0) {
        totalWeight += rowTotalWeight;
      } else {
        // Calculate from weight per unit and quantity
        double qty = row['qty'] ?? 0.0;
        double? weightPerUnit = row['weightPerUnit'];

        if (weightPerUnit != null && weightPerUnit > 0 && qty > 0) {
          totalWeight += weightPerUnit * qty;
        } else {
          // Try to parse from weight controller
          final controller = row['weightController'];
          if (controller != null && controller.text.isNotEmpty) {
            final parts = controller.text.trim().split(' ');
            totalWeight += double.tryParse(parts[0]) ?? 0.0;
          }
        }
      }
    }

    return totalWeight;
  }

  void _addItemToRow(Item item, int rowIndex, LengthBodyCombination? combination) {
    // ── Item-level customer-aware price (fallback) ────────────────────────
    final double customerPrice = item.getPriceForCustomer(_selectedCustomerId);

    // Check if weight was manually entered before resetting
    final wasManualWeight =
        _quotationRows[rowIndex]['weightController']?.text.isNotEmpty == true &&
            _quotationRows[rowIndex]['calculationType'] == 'weight';
    final manualWeightText =
    wasManualWeight ? _quotationRows[rowIndex]['weightController'].text : null;

    // Parse BOM name if it's in the format "Size | Length | Body Type"
    String size = '';
    String length = '';
    String bodyType = '';

    if (item.itemName.contains('|')) {
      final parts =
      item.itemName.split('|').map((part) => part.trim()).toList();
      if (parts.length >= 3) {
        size = parts[0];
        length = parts[1];
        bodyType = parts[2];
      } else if (parts.length == 2) {
        size = parts[0];
        length = parts[1];
      } else if (parts.length == 1) {
        size = parts[0];
      }
    } else {
      size = item.itemName;
    }

    setState(() {
      // Ensure all controllers exist
      _quotationRows[rowIndex]['sizeController'] ??= TextEditingController();
      _quotationRows[rowIndex]['lengthController'] ??= TextEditingController();
      _quotationRows[rowIndex]['bodyTypeController'] ??= TextEditingController();
      _quotationRows[rowIndex]['weightController'] ??= TextEditingController();

      _quotationRows[rowIndex]['itemName'] = item.itemName;
      // Show only SIZE in the item name field
      _quotationRows[rowIndex]['itemNameController'].text = size;

      // Set parsed BOM fields
      _quotationRows[rowIndex]['sizeController'].text = size;
      _quotationRows[rowIndex]['lengthController'].text = length;
      _quotationRows[rowIndex]['bodyTypeController'].text = bodyType;
      _quotationRows[rowIndex]['size'] = size;
      _quotationRows[rowIndex]['length'] = length;
      _quotationRows[rowIndex]['bodyType'] = bodyType;

      // Reset weight info (unless manual entry was present)
      if (!wasManualWeight) {
        _quotationRows[rowIndex]['weightPerUnit'] = null;
        _quotationRows[rowIndex]['weightUnit'] = 'kg';
      }
      _quotationRows[rowIndex]['lengthBodyCombination'] = null;

      if (combination != null) {
        // ── Combination-level customer-aware price ────────────────────────
        // Returns customer-specific price if set, otherwise falls back to
        // salePricePerKg (default rate).
        final double effectiveRate =
        combination.getPriceForCustomer(_selectedCustomerId);

        // Override length / bodyType with combination values
        _quotationRows[rowIndex]['lengthController'].text = combination.length;
        _quotationRows[rowIndex]['bodyTypeController'].text = combination.bodyType;
        _quotationRows[rowIndex]['length'] = combination.length;
        _quotationRows[rowIndex]['bodyType'] = combination.bodyType;
        _quotationRows[rowIndex]['lengthBodyCombination'] = combination.toMap();

        if (combination.weightPerUnit != null) {
          final double weightPerUnit = combination.weightPerUnit!;
          final String weightUnit = combination.weightUnit ?? 'kg';

          _quotationRows[rowIndex]['weightPerUnit'] = weightPerUnit;
          _quotationRows[rowIndex]['weightUnit'] = weightUnit;
          _quotationRows[rowIndex]['weightController'].text =
          '$weightPerUnit $weightUnit';

          // Always use the customer-aware effective rate
          _quotationRows[rowIndex]['rate'] = effectiveRate;
          _quotationRows[rowIndex]['rateController'].text =
              effectiveRate.toStringAsFixed(2);

          // Auto-switch to weight-based calculation
          _quotationRows[rowIndex]['calculationType'] = 'weight';
        } else {
          // No weight data — still apply customer-aware rate
          _quotationRows[rowIndex]['rate'] = effectiveRate;
          _quotationRows[rowIndex]['rateController'].text =
              effectiveRate.toStringAsFixed(2);
          _quotationRows[rowIndex]['calculationType'] = 'quantity';
        }
      } else {
        // No combination — use item-level customer price
        _quotationRows[rowIndex]['rate'] = customerPrice;
        _quotationRows[rowIndex]['rateController'].text =
            customerPrice.toStringAsFixed(2);
        _quotationRows[rowIndex]['calculationType'] = 'quantity';
      }

      // Restore manual weight if it existed before
      if (wasManualWeight && manualWeightText != null) {
        _quotationRows[rowIndex]['weightController'].text = manualWeightText;
        _quotationRows[rowIndex]['calculationType'] = 'weight';
      }

      // Default qty to 1 if not already set
      if ((_quotationRows[rowIndex]['qty'] ?? 0.0) == 0.0) {
        _quotationRows[rowIndex]['qty'] = 1.0;
        _quotationRows[rowIndex]['qtyController'].text = '1';
      }

      _calculateTotalForRow(rowIndex);
    });
  }

  void _showLengthCombinationDialog(Item item, int rowIndex) {
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    bool isProcessing = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                languageProvider.isEnglish
                    ? 'Select Length-Body Combination'
                    : 'لمبائی-جسم کا مجموعہ منتخب کریں',
              ),
              content: Container(
                width: double.maxFinite,
                constraints: const BoxConstraints(maxHeight: 450),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: item.lengthBodyCombinations!.length,
                  itemBuilder: (context, index) {
                    final combination = item.lengthBodyCombinations![index];

                    // ── Customer-aware price ──────────────────────────────
                    final double effectiveRate =
                    combination.getPriceForCustomer(_selectedCustomerId);
                    final bool hasCustomerPrice = _selectedCustomerId != null &&
                        combination.customerPrices
                            .containsKey(_selectedCustomerId);
                    final double defaultRate =
                        combination.salePricePerKg ?? 0.0;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: hasCustomerPrice
                            ? const BorderSide(
                            color: Colors.purple, width: 1.5)
                            : BorderSide.none,
                      ),
                      child: ListTile(
                        title: Text(
                          '${item.itemName} '
                              '(${combination.length} — ${combination.bodyType})',
                          style:
                          const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (combination.lengthDecimal.isNotEmpty)
                              Text(
                                'Decimal: ${combination.lengthDecimal}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600]),
                              ),
                            if (combination.weightPerUnit != null)
                              Text(
                                'Weight/Unit: ${combination.weightPerUnit}'
                                    ' ${combination.weightUnit}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.blue[700]),
                              ),

                            // ── Rate display ──────────────────────────
                            const SizedBox(height: 4),
                            if (hasCustomerPrice) ...[
                              // Show customer-specific rate prominently
                              Row(
                                children: [
                                  Icon(Icons.person,
                                      size: 14, color: Colors.purple[700]),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Your Rate: '
                                        '${effectiveRate.toStringAsFixed(2)} PKR/kg',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.purple[700],
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'Default: '
                                    '${defaultRate.toStringAsFixed(2)} PKR/kg',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ] else ...[
                              // No customer price — show sale rate normally
                              if (combination.salePricePerKg != null)
                                Row(
                                  children: [
                                    Icon(Icons.sell,
                                        size: 14, color: Colors.green[700]),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Rate: '
                                          '${defaultRate.toStringAsFixed(2)} PKR/kg',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.green[700],
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (hasCustomerPrice)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.purple[50],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Custom',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.purple[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 4),
                            const Icon(Icons.arrow_forward),
                          ],
                        ),
                        onTap: () {
                          if (isProcessing) return;
                          setDialogState(() => isProcessing = true);
                          Navigator.pop(context);
                          Future.delayed(
                            const Duration(milliseconds: 100),
                                () => _addItemToRow(item, rowIndex, combination),
                          );
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
                TextButton(
                  onPressed: () {
                    if (isProcessing) return;
                    setDialogState(() => isProcessing = true);
                    Navigator.pop(context);
                    Future.delayed(
                      const Duration(milliseconds: 100),
                          () => _addItemToRow(item, rowIndex, null),
                    );
                  },
                  child: Text(
                      languageProvider.isEnglish ? 'Skip' : 'چھوڑ دیں'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildItemsSection(BuildContext context, LanguageProvider languageProvider,
      {required bool isMobile}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        color: Colors.green[700], size: 24),
                    const SizedBox(width: 8),
                    Text(
                      languageProvider.isEnglish ? 'Items' : 'آئٹمز',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.green[800],
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _addNewRow,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(languageProvider.isEnglish
                      ? 'Add Item' : 'آئٹم شامل کریں'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Updated header with Total Weight column
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: Text(
                      languageProvider.isEnglish ? 'Size' : 'سائز',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      languageProvider.isEnglish ? 'Length' : 'لمبائی',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      languageProvider.isEnglish ? 'Body Type' : 'باڈی قسم',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      languageProvider.isEnglish ? 'Description' : 'تفصیل',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      languageProvider.isEnglish ? 'Qty' : 'مقدار',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      languageProvider.isEnglish ? 'Weight/Unit' : 'وزن/یونٹ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      languageProvider.isEnglish ? 'Total Wt' : 'کل وزن',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      languageProvider.isEnglish ? 'Calc' : 'حساب',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      languageProvider.isEnglish ? 'Rate' : 'ریٹ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      languageProvider.isEnglish ? 'Total' : 'کل',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            const SizedBox(height: 8),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _quotationRows.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Item Name field
                    Expanded(
                      flex: 1,
                      child: CustomAutocomplete(
                        items: _items,
                        controller: _quotationRows[index]['itemNameController'],
                        onSelected: (Item selectedItem) {
                          setState(() {
                            _quotationRows[index]['itemName'] = selectedItem.itemName;
                          });

                          if (selectedItem.lengthBodyCombinations != null &&
                              selectedItem.lengthBodyCombinations!.isNotEmpty) {
                            _showLengthCombinationDialog(selectedItem, index);
                          } else {
                            _addItemToRow(selectedItem, index, null);
                          }
                        },
                        selectedCustomerId: _selectedCustomerId,
                        allowManualEntry: true,
                      ),
                    ),

                    // Length field
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TextField(
                          controller: _quotationRows[index]['lengthController'] ?? TextEditingController(),
                          decoration: InputDecoration(
                            hintText: languageProvider.isEnglish ? 'Length' : 'لمبائی',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          onChanged: (value) => _updateRow(index, 'length', value),
                        ),
                      ),
                    ),

                    // Body Type field
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TextField(
                          controller: _quotationRows[index]['bodyTypeController'] ?? TextEditingController(),
                          decoration: InputDecoration(
                            hintText: languageProvider.isEnglish ? 'Body Type' : 'باڈی قسم',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                          ),
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          onChanged: (value) => _updateRow(index, 'bodyType', value),
                        ),
                      ),
                    ),

                    // Description field
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TextField(
                          controller: _quotationRows[index]['descriptionController'],
                          decoration: InputDecoration(
                            hintText: languageProvider.isEnglish ? 'Description' : 'تفصیل',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          maxLines: 1,
                          onChanged: (value) => _updateRow(index, 'description', value),
                        ),
                      ),
                    ),

                    // Quantity field
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TextField(
                          controller: _quotationRows[index]['qtyController'],
                          decoration: InputDecoration(
                            hintText: languageProvider.isEnglish ? 'Qty' : 'مقدار',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          onChanged: (value) {
                            double qtyValue = double.tryParse(value) ?? 0.0;
                            _updateRow(index, 'qty', qtyValue);
                          },
                        ),
                      ),
                    ),

                    // Weight per Unit field (editable)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TextField(
                          controller: _quotationRows[index]['weightController'] ?? TextEditingController(),
                          decoration: InputDecoration(
                            hintText: languageProvider.isEnglish ? 'Wt/Unit' : 'وزن/یونٹ',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          keyboardType: TextInputType.number,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          onChanged: (value) {
                            _handleWeightPerUnitInput(index, value);
                          },
                        ),
                      ),
                    ),

                    // NEW FIELD - Total Weight (auto-calculated, read-only)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TextField(
                          controller: TextEditingController(
                            text: _calculateDisplayTotalWeight(index),
                          ),
                          decoration: InputDecoration(
                            hintText: 'Total',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          readOnly: true,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ),
                    ),

                    // Calculation Type dropdown
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _quotationRows[index]['calculationType'] ?? 'quantity',
                              isExpanded: true,
                              items: [
                                DropdownMenuItem(
                                  value: 'quantity',
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Text(
                                      'Qty×Rate',
                                      style: TextStyle(fontSize: 12),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'weight',
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Text(
                                      'TotalWt×Rate',
                                      style: TextStyle(fontSize: 12),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (String? value) {
                                if (value != null) {
                                  _updateRow(index, 'calculationType', value);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Rate field
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TextField(
                          controller: _quotationRows[index]['rateController'],
                          decoration: InputDecoration(
                            hintText: languageProvider.isEnglish ? 'Rate' : 'ریٹ',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          onChanged: (value) {
                            double rateValue = double.tryParse(value) ?? 0.0;
                            _updateRow(index, 'rate', rateValue);
                          },
                        ),
                      ),
                    ),

                    // Total field
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TextField(
                          controller: TextEditingController(
                            text: (_quotationRows[index]['total'] ?? 0.0).toStringAsFixed(2),
                          ),
                          decoration: InputDecoration(
                            hintText: languageProvider.isEnglish ? 'Total' : 'کل',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          readOnly: true,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                    // Delete button
                    SizedBox(
                      width: 40,
                      child: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        onPressed: () => _deleteRow(index),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _addNewRow,
                icon: const Icon(Icons.add, size: 16),
                label: Text(languageProvider.isEnglish ? 'Add More Items' : 'مزید آئٹمز شامل کریں'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.blue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSection(BuildContext context, LanguageProvider languageProvider,
      {required bool isMobile}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(20.0),
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
                Icon(Icons.receipt_long, color: Colors.orange[700], size: 24),
                const SizedBox(width: 8),
                Text(
                  languageProvider.isEnglish
                      ? 'Quotation Details'
                      : 'کوٹیشن کی تفصیلات',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (isMobile) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _isAutoReference ? _autoReferenceController : _referenceController,
                      label: _isAutoReference
                          ? (languageProvider.isEnglish ? 'Auto Reference (Customer-Serial)' : 'آٹو ریفرنس (کسٹمر-سیریل)')
                          : (languageProvider.isEnglish ? 'Manual Reference Number' : 'دستی ریفرنس نمبر'),
                      icon: Icons.tag,
                      readOnly: _isAutoReference,
                    ),
                  ),
                  Switch(
                    value: _isAutoReference,
                    onChanged: (value) => _toggleReferenceMode(value),
                    activeColor: Colors.green,
                  ),
                  Text(
                    _isAutoReference
                        ? (languageProvider.isEnglish ? 'Auto' : 'آٹو')
                        : (languageProvider.isEnglish ? 'Manual' : 'مینوئل'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _biltiNumberController,
                label: languageProvider.isEnglish
                    ? 'Bilti Number'
                    : 'بلٹی نمبر',
                icon: Icons.numbers,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _transportCompanyController,
                label: languageProvider.isEnglish
                    ? 'Transport Company'
                    : 'ٹرانسپورٹ کمپنی',
                icon: Icons.local_shipping,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _dateController,
                label: languageProvider.isEnglish ? 'Date & Time' : 'تاریخ اور وقت',
                icon: Icons.calendar_today,
                readOnly: true,
                onTap: () => _selectDate(context),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _isAutoReference ? _autoReferenceController : _referenceController,
                            label: _isAutoReference
                                ? (languageProvider.isEnglish ? 'Auto Reference' : 'آٹو ریفرنس')
                                : (languageProvider.isEnglish ? 'Manual Reference' : 'دستی ریفرنس'),
                            icon: Icons.tag,
                            readOnly: _isAutoReference,
                          ),
                        ),
                        Switch(
                          value: _isAutoReference,
                          onChanged: (value) => _toggleReferenceMode(value),
                          activeColor: Colors.green,
                        ),
                        Text(
                          _isAutoReference
                              ? (languageProvider.isEnglish ? 'Auto' : 'آٹو')
                              : (languageProvider.isEnglish ? 'Manual' : 'مینوئل'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      controller: _biltiNumberController,
                      label: languageProvider.isEnglish
                          ? 'Bilti Number'
                          : 'بلٹی نمبر',
                      icon: Icons.numbers,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _transportCompanyController,
                      label: languageProvider.isEnglish
                          ? 'Transport Company'
                          : 'ٹرانسپورٹ کمپنی',
                      icon: Icons.local_shipping,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      controller: _dateController,
                      label: languageProvider.isEnglish ? 'Date & Time' : 'تاریخ اور وقت',
                      icon: Icons.calendar_today,
                      readOnly: true,
                      onTap: () => _selectDate(context),
                    ),
                  ),
                ],
              ),
            ],
            if (_selectedCustomerSerial != null && _lastReferenceNumber != null && _lastReferenceNumber!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    languageProvider.isEnglish
                        ? 'Last Reference: $_lastReferenceNumber'
                        : 'آخری ریفرنس: $_lastReferenceNumber',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerSection(BuildContext context, LanguageProvider languageProvider) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_outline, color: Colors.blue[700], size: 24),
                const SizedBox(width: 8),
                Text(
                  languageProvider.isEnglish
                      ? 'Customer Information'
                      : 'کسٹمر کی معلومات',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Consumer<CustomerProvider>(
              builder: (context, customerProvider, _) {
                if (customerProvider.customers.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Autocomplete search field ──────────────────────
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Autocomplete<Customer>(
                        initialValue: TextEditingValue(
                            text: _selectedCustomerName ?? ''),
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Customer>.empty();
                          }
                          return customerProvider.customers.where((Customer c) {
                            return c.name.toLowerCase().contains(
                                textEditingValue.text.toLowerCase());
                          });
                        },
                        displayStringForOption: (Customer c) => c.name,
                        fieldViewBuilder: (
                            BuildContext context,
                            TextEditingController textEditingController,
                            FocusNode focusNode,
                            VoidCallback onFieldSubmitted,
                            ) {
                          // Sync controller when customer already selected
                          if (_selectedCustomerName != null &&
                              textEditingController.text.isEmpty) {
                            textEditingController.text = _selectedCustomerName!;
                          }

                          return TextField(
                            controller: textEditingController,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: languageProvider.isEnglish
                                  ? 'Search or Enter Customer Name'
                                  : 'کسٹمر تلاش کریں یا نام درج کریں',
                              hintText: languageProvider.isEnglish
                                  ? 'Type to search...'
                                  : 'تلاش کے لیے ٹائپ کریں...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                              prefixIcon:
                              Icon(Icons.search, color: Colors.blue[600]),
                              suffixIcon: textEditingController.text.isNotEmpty
                                  ? IconButton(
                                icon: const Icon(Icons.close, size: 20),
                                onPressed: () {
                                  textEditingController.clear();
                                  setState(() {
                                    _selectedCustomerId = null;
                                    _selectedCustomerName = null;
                                    _selectedCustomerSerial = null;
                                    _lastReferenceNumber = null;
                                    _customerItemPrices = {};
                                  });
                                },
                              )
                                  : null,
                            ),
                            onChanged: (value) {
                              // Clear selection when user edits the field
                              if (_selectedCustomerName != null &&
                                  value != _selectedCustomerName) {
                                setState(() {
                                  _selectedCustomerId = null;
                                  _selectedCustomerName = null;
                                  _selectedCustomerSerial = null;
                                  _lastReferenceNumber = null;
                                  _customerItemPrices = {};
                                });
                              }
                            },
                          );
                        },
                        onSelected: (Customer selectedCustomer) {
                          setState(() {
                            _selectedCustomerId = selectedCustomer.id;
                            _selectedCustomerName = selectedCustomer.name;
                            _selectedCustomerSerial =
                                selectedCustomer.customerSerial;
                            _customerController.text = selectedCustomer.name;
                          });
                          _fetchCustomerPrices(selectedCustomer.id);
                          _fetchCustomerSerial(selectedCustomer.id);
                          _onCustomerChanged();
                          FocusScope.of(context).unfocus();
                        },
                        optionsViewBuilder: (
                            BuildContext context,
                            AutocompleteOnSelected<Customer> onSelected,
                            Iterable<Customer> options,
                            ) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4.0,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                constraints: const BoxConstraints(maxHeight: 220),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                  Border.all(color: Colors.grey[200]!),
                                ),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (BuildContext context, int index) {
                                    final Customer customer =
                                    options.elementAt(index);
                                    return ListTile(
                                      dense: true,
                                      leading: Icon(Icons.person,
                                          color: Colors.blue[400], size: 20),
                                      title: Text(customer.name),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          if (customer.phone.isNotEmpty)
                                            Text(customer.phone,
                                                style: const TextStyle(
                                                    fontSize: 11)),
                                          if (customer.customerSerial != null &&
                                              customer
                                                  .customerSerial!.isNotEmpty)
                                            Text(
                                              'Serial: ${customer.customerSerial}',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey[600]),
                                            ),
                                          if (customer.city.isNotEmpty)
                                            Text(customer.city,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[600])),
                                        ],
                                      ),
                                      onTap: () => onSelected(customer),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // ── Selected customer info box ─────────────────────
                    if (_selectedCustomerName != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[100]!),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _selectedCustomerId
                                      ?.startsWith('manual_') ??
                                      false
                                      ? Icons.person_add_alt_1
                                      : Icons.person,
                                  color: _selectedCustomerId
                                      ?.startsWith('manual_') ??
                                      false
                                      ? Colors.green[700]
                                      : Colors.blue[700],
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedCustomerName!,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: _selectedCustomerId
                                              ?.startsWith('manual_') ??
                                              false
                                              ? Colors.green[800]
                                              : Colors.blue[800],
                                        ),
                                      ),
                                      if (_selectedCustomerSerial != null &&
                                          _selectedCustomerSerial!.isNotEmpty)
                                        Text(
                                          'Serial: $_selectedCustomerSerial',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.blue[600]),
                                        ),
                                      if (_selectedCustomerId
                                          ?.startsWith('manual_') ??
                                          false)
                                        Text(
                                          languageProvider.isEnglish
                                              ? 'New Customer (Manual Entry)'
                                              : 'نیا کسٹمر (دستی درج شدہ)',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.green[600]),
                                        ),
                                    ],
                                  ),
                                ),
                                // Clear selection button
                                IconButton(
                                  icon: Icon(Icons.clear,
                                      size: 18, color: Colors.grey[600]),
                                  onPressed: () {
                                    setState(() {
                                      _selectedCustomerId = null;
                                      _selectedCustomerName = null;
                                      _selectedCustomerSerial = null;
                                      _customerController.clear();
                                      _customerItemPrices = {};
                                      _lastReferenceNumber = null;
                                    });
                                  },
                                ),
                              ],
                            ),
                            if (_lastReferenceNumber != null &&
                                _lastReferenceNumber!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Row(
                                  children: [
                                    Icon(Icons.history,
                                        size: 16, color: Colors.blueGrey),
                                    const SizedBox(width: 8),
                                    Text(
                                      languageProvider.isEnglish
                                          ? 'Last Reference: $_lastReferenceNumber'
                                          : 'آخری ریفرنس: $_lastReferenceNumber',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blueGrey,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscountSection(BuildContext context, LanguageProvider languageProvider) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.discount_outlined, color: Colors.purple[700], size: 24),
                const SizedBox(width: 8),
                Text(
                  languageProvider.isEnglish ? 'Discount' : 'رعایت',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.purple[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _discountController,
              label: languageProvider.isEnglish
                  ? 'Discount Amount'
                  : 'رعایت کی رقم',
              icon: Icons.money_off,
              keyboardType: TextInputType.number,
              onChanged: (value) {
                setState(() {
                  _discount = double.tryParse(value) ?? 0.0;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsSection(BuildContext context, LanguageProvider languageProvider) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.indigo[50]!, Colors.blue[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.calculate_outlined, color: Colors.indigo[700], size: 24),
                const SizedBox(width: 8),
                Text(
                  languageProvider.isEnglish ? 'Summary' : 'خلاصہ',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.indigo[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildTotalRow(
              languageProvider.isEnglish ? 'Subtotal:' : 'سب ٹوٹل:',
              _calculateSubtotal().toStringAsFixed(2),
            ),
            const SizedBox(height: 8),
            _buildTotalRow(
              languageProvider.isEnglish ? 'Discount:' : 'رعایت:',
              _discount.toStringAsFixed(2),
              color: Colors.red[600],
            ),
            const Divider(thickness: 2, height: 24),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.indigo[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: _buildTotalRow(
                languageProvider.isEnglish ? 'GRAND TOTAL:' : 'مجموعی کل:',
                _calculateGrandTotal().toStringAsFixed(2),
                isBold: true,
                fontSize: 18,
                color: Colors.indigo[800],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTermsSection(BuildContext context, LanguageProvider languageProvider) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_outlined, color: Colors.teal[700], size: 24),
                const SizedBox(width: 8),
                Text(
                  languageProvider.isEnglish
                      ? 'Terms & Conditions'
                      : 'شرائط و ضوابط',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.teal[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _termsController,
              decoration: InputDecoration(
                hintText: languageProvider.isEnglish
                    ? 'Enter terms and conditions...'
                    : 'شرائط و ضوابط درج کریں...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.teal[400]!, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              maxLines: 4,
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
    TextInputType? keyboardType,
    int maxLines = 1,
    Function(String)? onChanged,
    VoidCallback? onTap,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: Colors.grey[600]) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.orange, width: 2),
        ),
        filled: true,
        fillColor: readOnly ? Colors.grey[100] : Colors.grey[50],
      ),
    );
  }

  Widget _buildTotalRow(String label, String value, {
    bool isBold = false,
    double fontSize = 14,
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            fontSize: fontSize,
            color: color,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: fontSize,
            color: color ?? Colors.grey[800],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {IconData? icon, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color ?? Colors.grey[600]),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color ?? Colors.teal[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(BuildContext context, LanguageProvider languageProvider) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _saveQuotation,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[300],
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              widget.existingQuotation == null
                  ? (languageProvider.isEnglish ? 'Save Quotation' : 'محفوظ کریں')
                  : (languageProvider.isEnglish ? 'Update Quotation' : 'اپ ڈیٹ کریں'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }


  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );

      if (time != null) {
        final DateTime selectedDateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          time.hour,
          time.minute,
        );
        setState(() {
          _dateController.text = DateFormat('yyyy-MM-dd HH:mm').format(selectedDateTime);
        });
      } else {
        final DateTime selectedDateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          DateTime.now().hour,
          DateTime.now().minute,
        );
        setState(() {
          _dateController.text = DateFormat('yyyy-MM-dd HH:mm').format(selectedDateTime);
        });
      }
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(context, languageProvider),
      body: ResponsiveLayout(
        mobile: _buildMobileLayout(context, languageProvider),
        tablet: _buildTabletLayout(context, languageProvider),
        desktop: _buildDesktopLayout(context, languageProvider),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, LanguageProvider languageProvider) {
    return AppBar(
      elevation: 0,
      title: Text(
        languageProvider.isEnglish ? 'Create Gate Pass' : 'گیٹ پاس بنائیں',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
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
        _buildAppBarAction(
          icon: Icons.print_outlined,
          onPressed: () async {
            try {
              final bytes = await _generateQuotationPDF();
              await Printing.layoutPdf(onLayout: (_) => bytes);
            } catch (e) {
              _showSnackBar(context, 'Printing error: ${e.toString()}');
            }
          },
        ),
      ],
    );
  }

  Widget _buildAppBarAction({required IconData icon, required VoidCallback onPressed}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Material(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context, LanguageProvider languageProvider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderSection(context, languageProvider, isMobile: true),
          const SizedBox(height: 24),
          _buildCustomerSection(context, languageProvider),
          const SizedBox(height: 24),
          _buildItemsSection(context, languageProvider, isMobile: true),
          const SizedBox(height: 24),
          _buildDiscountSection(context, languageProvider),
          const SizedBox(height: 24),
          _buildTotalsSection(context, languageProvider),
          const SizedBox(height: 24),
          _buildAdditionalInfoSection(context, languageProvider), // Add this line
          const SizedBox(height: 24),
          _buildTermsSection(context, languageProvider),
          const SizedBox(height: 32),
          _buildSaveButton(context, languageProvider),
        ],
      ),
    );
  }

  Widget _buildTabletLayout(BuildContext context, LanguageProvider languageProvider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderSection(context, languageProvider, isMobile: false),
          const SizedBox(height: 32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    _buildCustomerSection(context, languageProvider),
                    const SizedBox(height: 24),
                    _buildItemsSection(context, languageProvider, isMobile: false),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    _buildDiscountSection(context, languageProvider),
                    const SizedBox(height: 24),
                    _buildTotalsSection(context, languageProvider),
                    const SizedBox(height: 24),
                    _buildAdditionalInfoSection(context, languageProvider), // Add this line
                    const SizedBox(height: 24),
                    _buildTermsSection(context, languageProvider),
                    const SizedBox(height: 24),
                    _buildSaveButton(context, languageProvider),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, LanguageProvider languageProvider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 24.0),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderSection(context, languageProvider, isMobile: false),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        _buildCustomerSection(context, languageProvider),
                        const SizedBox(height: 10),
                        _buildItemsSection(context, languageProvider, isMobile: false),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      children: [
                        _buildDiscountSection(context, languageProvider),
                        const SizedBox(height: 24),
                        _buildTotalsSection(context, languageProvider),
                        const SizedBox(height: 24),
                        _buildAdditionalInfoSection(context, languageProvider), // Add this line
                        const SizedBox(height: 24),
                        _buildTermsSection(context, languageProvider),
                        const SizedBox(height: 24),
                        _buildSaveButton(context, languageProvider),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (var row in _quotationRows) {
      row['itemNameController']?.dispose();
      row['sizeController']?.dispose();
      row['lengthController']?.dispose();
      row['bodyTypeController']?.dispose();
      row['rateController']?.dispose();
      row['qtyController']?.dispose();
      row['descriptionController']?.dispose();
      row['weightController']?.dispose();
    }
    _discountController.dispose();
    _driverPhoneController.dispose();
    _deliveryCarNumberController.dispose();
    _customerController.dispose();
    _dateController.dispose();
    _referenceController.dispose();
    _autoReferenceController.dispose();
    _biltiNumberController.dispose();
    _totalQtyController.dispose();
    _driverNameController.dispose();
    _signatureController.dispose();
    _transportCompanyController.dispose();
    _termsController.dispose();
    super.dispose();
  }
}

class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget tablet;
  final Widget desktop;

  const ResponsiveLayout({
    Key? key,
    required this.mobile,
    required this.tablet,
    required this.desktop,
  }) : super(key: key);

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 650;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width < 1100 &&
          MediaQuery.of(context).size.width >= 650;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1100;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1100) {
          return desktop;
        } else if (constraints.maxWidth >= 650) {
          return tablet;
        } else {
          return mobile;
        }
      },
    );
  }
}

class CustomAutocomplete extends StatefulWidget {
  final List<Item> items;
  final TextEditingController controller;
  final Function(Item) onSelected;
  final String? selectedCustomerId;
  final bool allowManualEntry;

  const CustomAutocomplete({
    required this.items,
    required this.controller,
    required this.onSelected,
    required this.selectedCustomerId,
    this.allowManualEntry = true,
  });

  @override
  _CustomAutocompleteState createState() => _CustomAutocompleteState();
}

class _CustomAutocompleteState extends State<CustomAutocomplete> {
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      decoration: InputDecoration(
        labelText: 'Size',
        suffixIcon: IconButton(
          icon: Icon(Icons.search),
          onPressed: () => _showItemSearchDialog(context),
        ),
      ),
      onChanged: (value) {
        // Handle manual entry if needed
      },
    );
  }

  void _showItemSearchDialog(BuildContext context) {
    TextEditingController searchController = TextEditingController();
    List<Item> filteredItems = List.from(widget.items);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            void filterItems(String query) {
              setState(() {
                if (query.isEmpty) {
                  filteredItems = List.from(widget.items);
                } else {
                  filteredItems = widget.items.where((item) {
                    return item.itemName.toLowerCase().contains(query.toLowerCase());
                  }).toList();
                }
              });
            }

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              child: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(maxHeight: 500),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Search field
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        labelText: 'Search Items',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                          icon: Icon(Icons.clear),
                          onPressed: () {
                            searchController.clear();
                            filterItems('');
                          },
                        )
                            : null,
                      ),
                      autofocus: true,
                      onChanged: filterItems,
                    ),
                    const SizedBox(height: 16),

                    // Items list
                    Expanded(
                      child: filteredItems.isEmpty
                          ? Center(
                        child: Text(
                          'No items found',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                          : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          final displayPrice = widget.selectedCustomerId != null
                              ? item.getPriceForCustomer(widget.selectedCustomerId)
                              : item.avgSalePricePerKg;

                          final isSpecialPrice = widget.selectedCustomerId != null &&
                              displayPrice != item.avgCostPricePerKg;

                          return Card(
                            margin: EdgeInsets.symmetric(vertical: 4, horizontal: 0),
                            child: ListTile(
                              leading: GestureDetector(
                                onTap: () {
                                  if (item.imageBase64 != null && item.imageBase64!.isNotEmpty) {
                                    _showImagePreview(context, item.imageBase64!);
                                  }
                                },
                                child: item.imageBase64 != null && item.imageBase64!.isNotEmpty
                                    ? CircleAvatar(
                                  backgroundImage: MemoryImage(base64Decode(item.imageBase64!)),
                                  radius: 20,
                                )
                                    : CircleAvatar(
                                  backgroundColor: Colors.grey[200],
                                  radius: 20,
                                  child: Icon(Icons.inventory, size: 20),
                                ),
                              ),
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (item.itemName.contains('|'))
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Show the full BOM name
                                        Text(
                                          item.itemName,
                                          style: TextStyle(fontWeight: FontWeight.w500),
                                        ),
                                        // Parse and show the individual parts in a smaller font
                                        Text(
                                          _formatBOMName(item.itemName),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600],
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Text(
                                      item.itemName,
                                      style: TextStyle(fontWeight: FontWeight.w500),
                                    ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (item.customerSerial != null && item.customerSerial!.isNotEmpty)
                                    Text(
                                      'Serial: ${item.customerSerial}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  if (isSpecialPrice)
                                    Text(
                                      'Special Price',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  Text(
                                    '${displayPrice.toStringAsFixed(2)} PKR',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                ],
                              ),
                              trailing: ElevatedButton(
                                onPressed: () {
                                  _handleItemSelection(item, context);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                ),
                                child: Text('Add'),
                              ),
                              onTap: () {
                                _handleItemSelection(item, context);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Close button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Close'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatBOMName(String bomName) {
    if (!bomName.contains('|')) return bomName;

    final parts = bomName.split('|');
    if (parts.length >= 3) {
      return 'Size: ${parts[0].trim()} | Length: ${parts[1].trim()} | Body: ${parts[2].trim()}';
    }
    return bomName;
  }

  Map<String, String> _parseBOMName(String bomName) {
    Map<String, String> result = {
      'size': '',
      'length': '',
      'bodyType': '',
      'fullName': bomName
    };

    if (bomName.contains('|')) {
      final parts = bomName.split('|').map((part) => part.trim()).toList();

      if (parts.length >= 3) {
        result['size'] = parts[0];
        result['length'] = parts[1];
        result['bodyType'] = parts[2];
      } else if (parts.length == 2) {
        result['size'] = parts[0];
        result['length'] = parts[1];
      } else if (parts.length == 1) {
        result['size'] = parts[0];
      }
    } else {
      result['size'] = bomName;
    }

    return result;
  }

  void _handleItemSelection(Item item, BuildContext context) {
    if (item.lengthBodyCombinations != null &&
        item.lengthBodyCombinations!.isNotEmpty) {
      Navigator.pop(context); // Close search dialog first
      _showCombinationDialog(item, context);
    } else {
      final selectedPrice = widget.selectedCustomerId != null
          ? item.getPriceForCustomer(widget.selectedCustomerId)
          : item.avgSalePricePerKg;

      // Parse the BOM name and set only the size
      final parsedBOM = _parseBOMName(item.itemName);
      widget.controller.text = parsedBOM['size']!;

      widget.onSelected(item.copyWith(
        avgCostPricePerKg: selectedPrice,
        avgSalePricePerKg: selectedPrice,
      ));
      Navigator.pop(context); // Close search dialog
    }
  }

  void _showCombinationDialog(Item item, BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Select Length-Body Combination'),
          content: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(maxHeight: 400),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: item.lengthBodyCombinations!.length,
              itemBuilder: (context, index) {
                final combination = item.lengthBodyCombinations![index];
                return Card(
                  margin: EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text('${item.itemName} (${combination.length} - ${combination.bodyType})'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (combination.lengthDecimal.isNotEmpty)
                          Text(
                            'Decimal: ${combination.lengthDecimal}',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        if (combination.costPricePerKg != null && combination.salePricePerKg != null)
                          Text(
                            'Price/Kg: ${combination.salePricePerKg!.toStringAsFixed(2)} PKR',
                            style: TextStyle(fontSize: 12, color: Colors.green),
                          ),
                      ],
                    ),
                    trailing: Icon(Icons.arrow_forward),
                    onTap: () {
                      Navigator.pop(context); // Close combination dialog

                      final selectedPrice = widget.selectedCustomerId != null
                          ? item.getPriceForCustomer(widget.selectedCustomerId)
                          : item.avgSalePricePerKg;

                      widget.controller.text = '${item.itemName} (${combination.length} - ${combination.bodyType})';
                      widget.onSelected(item.copyWith(
                        avgCostPricePerKg: selectedPrice,
                        avgSalePricePerKg: selectedPrice,
                      ));
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close combination dialog
                final selectedPrice = widget.selectedCustomerId != null
                    ? item.getPriceForCustomer(widget.selectedCustomerId)
                    : item.avgSalePricePerKg;

                widget.controller.text = item.itemName;
                widget.onSelected(item.copyWith(
                  avgCostPricePerKg: selectedPrice,
                  avgSalePricePerKg: selectedPrice,
                ));
              },
              child: Text('Skip'),
            ),
          ],
        );
      },
    );
  }

  void _showImagePreview(BuildContext context, String base64Image) {
    try {
      final decodedImage = base64Decode(base64Image);

      showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: BoxConstraints(maxHeight: 400, maxWidth: 400),
                padding: const EdgeInsets.all(12),
                child: Image.memory(
                  decodedImage,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text('Error loading image'),
                    );
                  },
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to preview image: $e')),
      );
    }
  }
}