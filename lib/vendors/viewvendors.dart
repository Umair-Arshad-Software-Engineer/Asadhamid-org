import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import '../Provider/lanprovider.dart';
import '../bankmanagement/banknames.dart';
import 'addvendors.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'itemwise ledger.dart';
import 'ledgerpage.dart';
import 'dart:convert';
import 'dart:ui' as ui;


class ViewVendorsPage extends StatefulWidget {
  const ViewVendorsPage({super.key});

  @override
  State<ViewVendorsPage> createState() => _ViewVendorsPageState();
}

class _ViewVendorsPageState extends State<ViewVendorsPage> {
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref("vendors");
  List<Map<String, dynamic>> _vendors = [];
  List<Map<String, dynamic>> _filteredVendors = [];
  bool _isLoading = true;
  TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _cachedBanks = [];

  // ── NEW: selection state ──
  bool _isSelectionMode = false;
  Set<String> _selectedVendorIds = {};

  @override
  void initState() {
    super.initState();
    _fetchVendors();
    _searchController.addListener(_filterVendors);
  }

  // ── Selection helpers ──
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) _selectedVendorIds.clear();
    });
  }

  void _toggleVendorSelection(String vendorId) {
    setState(() {
      if (_selectedVendorIds.contains(vendorId)) {
        _selectedVendorIds.remove(vendorId);
      } else {
        _selectedVendorIds.add(vendorId);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedVendorIds.length == _filteredVendors.length) {
        _selectedVendorIds.clear();
      } else {
        _selectedVendorIds = _filteredVendors.map((v) => v["id"] as String).toSet();
      }
    });
  }

  List<Map<String, dynamic>> get _selectedVendors =>
      _filteredVendors.where((v) => _selectedVendorIds.contains(v["id"])).toList();

  void _fetchVendors() {
    _databaseRef.onValue.listen((event) async {
      if (!mounted) return;

      final data = event.snapshot.value;

      if (data == null) {
        setState(() {
          _vendors = [];
          _filteredVendors = [];
          _isLoading = false;
        });
        return;
      }

      if (data is! Map<dynamic, dynamic>) {
        setState(() {
          _vendors = [];
          _filteredVendors = [];
          _isLoading = false;
        });
        return;
      }

      final List<Map<String, dynamic>> vendors = [];

      for (final entry in (data as Map<dynamic, dynamic>).entries) {
        // Get all payments for this vendor
        final paymentsSnapshot = await FirebaseDatabase.instance
            .ref('vendors/${entry.key}/payments')
            .get();

        double actualPaidAmount = 0.0;
        double totalPurchases = 0.0;

        // Get all purchases for this vendor to calculate correct balance
        final purchasesSnapshot = await FirebaseDatabase.instance
            .ref('purchases')
            .orderByChild('vendorId')
            .equalTo(entry.key)
            .get();

        if (purchasesSnapshot.exists) {
          final purchasesMap = purchasesSnapshot.value as Map<dynamic, dynamic>;
          for (final purchase in purchasesMap.values) {
            if (purchase is Map) {
              totalPurchases += (purchase['grandTotal'] ?? 0.0).toDouble();
            }
          }
        }

        // Calculate actual paid amount excluding pending cheques
        if (paymentsSnapshot.value != null) {
          final payments = paymentsSnapshot.value as Map<dynamic, dynamic>;

          for (final payment in payments.values) {
            if (payment is Map) {
              // Only include cleared cheques in paid amount
              if (payment['method'] != 'Cheque' ||
                  (payment['method'] == 'Cheque' && payment['status'] == 'cleared')) {
                actualPaidAmount += (payment['amount'] ?? 0.0).toDouble();
              }
            }
          }
        }

        final openingBalance = (entry.value["openingBalance"] ?? 0.0).toDouble();

        // Calculate actual remaining balance
        // Opening Balance + Total Purchases - Actual Paid Amount
        final remainingBalance = openingBalance + totalPurchases - actualPaidAmount;

        vendors.add({
          "id": entry.key.toString(),
          "name": entry.value["name"] ?? "Unknown Vendor",
          "paidAmount": actualPaidAmount,
          "totalPurchases": totalPurchases,
          "openingBalance": openingBalance,
          "remainingBalance": remainingBalance, // Add this
          "openingBalanceDate": entry.value["openingBalanceDate"] ?? "Unknown Date",
          "description": entry.value["description"] ?? "",
        });
      }

      setState(() {
        _vendors = vendors;
        _filteredVendors = vendors;
        _isLoading = false;
      });
    }, onError: (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching vendors: $error')),
      );
    });
  }

  void _filterVendors() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredVendors = _vendors
          .where((vendor) =>
          vendor["name"].toLowerCase().contains(query)) // Filter by vendor name
          .toList();
    });
  }

  void _confirmDelete(String id) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(languageProvider.isEnglish
              ? "Confirm Delete"
              : "حذف کرنے کی تصدیق کریں"),
          content: Text(languageProvider.isEnglish
              ? "Are you sure you want to delete this vendor?"
              : "کیا آپ واقعی یہ فروش حذف کرنا چاہتے ہیں؟"),
          actions: <Widget>[
            TextButton(
              child: Text(languageProvider.isEnglish ? "Cancel" : "منسوخ کریں",
                  style: TextStyle(color: Colors.teal)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text(languageProvider.isEnglish ? "Delete" : "حذف کریں",
                  style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                _deleteVendor(id); // Proceed with deletion
              },
            ),
          ],
        );
      },
    );
  }

  void _deleteVendor(String id) async {
    try {
      await _databaseRef.child(id).remove();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vendor deleted successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting vendor: $e')),
      );
    }
  }

  Future<String?> _pickImage() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final ImagePicker _picker = ImagePicker();
    Uint8List? imageBytes;

    // Show source selection dialog
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(languageProvider.isEnglish ? 'Select Source' : 'ذریعہ منتخب کریں'),
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

    // Capture image
    XFile? pickedFile = await _picker.pickImage(
      source: source,
      imageQuality: 50, // Reduce quality for compression
      maxWidth: 800,    // Limit dimensions
      maxHeight: 800,
    );

    if (pickedFile != null) {
      // Compress and convert to Base64
      imageBytes = await pickedFile.readAsBytes();
      return await _compressAndConvertToBase64(imageBytes);
    }
    return null;
  }

  Future<String> _compressAndConvertToBase64(Uint8List imageBytes) async {
    // First compression pass
    final codec = await ui.instantiateImageCodec(
      imageBytes,
      targetWidth: 400, // Further reduce size
      targetHeight: 400,
    );

    final frame = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);

    // Convert to Base64
    return base64Encode(byteData!.buffer.asUint8List());
  }

  // ── NEW: show PDF type selection bottom sheet for selected vendors ──
  void _showPdfOptions(List<Map<String, dynamic>> vendors) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                languageProvider.isEnglish
                    ? 'Export ${vendors.length} vendor(s) as:'
                    : '${vendors.length} وینڈر(ز) برآمد کریں:',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.orange),
              title: Text(languageProvider.isEnglish
                  ? 'Payment Collection Sheet'
                  : 'ادائیگی وصولی شیٹ'),
              subtitle: Text(languageProvider.isEnglish
                  ? 'With opening balance, paid amount & empty payment fields'
                  : 'اوپننگ بیلنس، ادا شدہ رقم اور خالی ادائیگی خانوں کے ساتھ'),
              onTap: () {
                Navigator.pop(ctx);
                _generateVendorPaymentCollectionPdf(vendors);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.deepOrange),
              title: Text(languageProvider.isEnglish
                  ? 'Vendor List'
                  : 'وینڈر کی فہرست'),
              subtitle: Text(languageProvider.isEnglish
                  ? 'Basic vendor information with balances'
                  : 'بیلنس کے ساتھ بنیادی وینڈر معلومات'),
              onTap: () {
                Navigator.pop(ctx);
                _generateBasicVendorListPdf(vendors);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateVendorPaymentCollectionPdf(List<Map<String, dynamic>> vendors) async {
    final pdf = pw.Document();
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    // Get remaining balance for each vendor (opening balance + purchases - paid amount)
    List<Map<String, dynamic>> vendorData = vendors.map((vendor) {
      // Use the pre-calculated remainingBalance from _vendors
      final remainingBalance = vendor["remainingBalance"] ??
          (vendor["openingBalance"] + (vendor["totalPurchases"] ?? 0) - vendor["paidAmount"]);

      return {
        'name': vendor["name"],
        'openingBalance': vendor["openingBalance"],
        'totalPurchases': vendor["totalPurchases"] ?? 0,
        'paidAmount': vendor["paidAmount"],
        'remainingBalance': remainingBalance,
      };
    }).toList();

    // Sort by remaining balance (highest first)
    vendorData.sort((a, b) => b['remainingBalance'].compareTo(a['remainingBalance']));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (pw.Context ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                languageProvider.isEnglish
                    ? 'Vendor Payment Collection Sheet'
                    : 'وینڈر ادائیگی وصولی شیٹ',
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 11),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 4),
          ],
        ),
        footer: (pw.Context ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              languageProvider.isEnglish
                  ? 'Total Vendors: ${vendors.length}'
                  : 'کل وینڈرز: ${vendors.length}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
        build: (pw.Context ctx) => [
          pw.TableHelper.fromTextArray(
            headers: [
              '#',
              languageProvider.isEnglish ? 'Vendor Name' : 'وینڈر کا نام',
              languageProvider.isEnglish ? 'Opening Balance (Rs)' : 'اوپننگ بیلنس (روپے)',
              languageProvider.isEnglish ? 'Total Purchases (Rs)' : 'کل خریداری (روپے)',
              languageProvider.isEnglish ? 'Paid Amount (Rs)' : 'ادا شدہ رقم (روپے)',
              languageProvider.isEnglish ? 'Remaining Balance (Rs)' : 'باقی بیلنس (روپے)',
              languageProvider.isEnglish ? 'Description' : 'تفصیل',
              languageProvider.isEnglish ? 'Payment Received (Rs)' : 'وصول شدہ ادائیگی (روپے)',
            ],
            data: vendorData.asMap().entries.map((entry) {
              final index = entry.key + 1;
              final vendor = entry.value;
              return [
                index.toString(),
                vendor['name'],
                vendor['openingBalance'].toStringAsFixed(2),
                vendor['totalPurchases'].toStringAsFixed(2),
                vendor['paidAmount'].toStringAsFixed(2),
                vendor['remainingBalance'].toStringAsFixed(2),
                '',
                '',
              ];
            }).toList(),
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
                color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFE65100)),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerLeft,
              7: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(30),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(1.5),
              3: const pw.FlexColumnWidth(1.5),
              4: const pw.FlexColumnWidth(1.5),
              5: const pw.FlexColumnWidth(1.5),
              6: const pw.FlexColumnWidth(3),
              7: const pw.FlexColumnWidth(2),
            },
            rowDecoration: const pw.BoxDecoration(
                border: pw.Border(
                    bottom: pw.BorderSide(
                        color: PdfColors.grey300, width: 0.5))),
            oddRowDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFFFF3E0)),
            cellPadding:
            const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.orange, width: 1),
                borderRadius:
                const pw.BorderRadius.all(pw.Radius.circular(4))),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  languageProvider.isEnglish
                      ? 'Total Outstanding Balance:'
                      : 'کل واجب الادا بیلنس:',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 11),
                ),
                pw.Text(
                  'Rs. ${vendorData.fold<double>(0.0, (sum, v) => sum + v['remainingBalance']).toStringAsFixed(2)}',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 11,
                      color: PdfColors.red),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                pw.Container(width: 150, height: 1, color: PdfColors.black),
                pw.SizedBox(height: 4),
                pw.Text(
                    languageProvider.isEnglish ? 'Prepared By' : 'تیار کردہ',
                    style: const pw.TextStyle(fontSize: 9)),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                pw.Container(width: 150, height: 1, color: PdfColors.black),
                pw.SizedBox(height: 4),
                pw.Text(
                    languageProvider.isEnglish ? 'Verified By' : 'تصدیق کردہ',
                    style: const pw.TextStyle(fontSize: 9)),
              ]),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  Future<void> _generateBasicVendorListPdf(List<Map<String, dynamic>> vendors) async {
    final pdf = pw.Document();
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return [
            pw.Center(
              child: pw.Text(
                languageProvider.isEnglish ? 'Vendors List' : 'فروشوں کی فہرست',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 30),
            pw.TableHelper.fromTextArray(
              headers: [
                '#',
                languageProvider.isEnglish ? 'Vendor Name' : 'وینڈر کا نام',
                languageProvider.isEnglish ? 'Opening Balance' : 'اوپننگ بیلنس',
                languageProvider.isEnglish ? 'Total Purchases' : 'کل خریداری',
                languageProvider.isEnglish ? 'Paid Amount' : 'ادا شدہ رقم',
                languageProvider.isEnglish ? 'Opening Date' : 'تاریخ افتتاح',
                languageProvider.isEnglish ? 'Remaining Balance' : 'باقی بیلنس',
              ],
              data: vendors.asMap().entries.map((entry) {
                final index = entry.key + 1;
                final vendor = entry.value;
                final remainingBalance = vendor["remainingBalance"] ??
                    (vendor["openingBalance"] + (vendor["totalPurchases"] ?? 0) - vendor["paidAmount"]);

                return [
                  index.toString(),
                  vendor["name"],
                  '${vendor["openingBalance"].toStringAsFixed(2)} Rs',
                  '${(vendor["totalPurchases"] ?? 0).toStringAsFixed(2)} Rs',
                  '${vendor["paidAmount"].toStringAsFixed(2)} Rs',
                  _formatDate(vendor["openingBalanceDate"]),
                  '${remainingBalance.toStringAsFixed(2)} Rs',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                  color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFE65100)),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.center,
                6: pw.Alignment.centerRight,
              },
              columnWidths: {
                0: const pw.FixedColumnWidth(30),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FlexColumnWidth(1.5),
                3: const pw.FlexColumnWidth(1.5),
                4: const pw.FlexColumnWidth(1.5),
                5: const pw.FlexColumnWidth(1.5),
                6: const pw.FlexColumnWidth(1.5),
              },
            ),
            pw.SizedBox(height: 20),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.orange, width: 1),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    languageProvider.isEnglish
                        ? 'Total Outstanding Balance:'
                        : 'کل واجب الادا بیلنس:',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 11),
                  ),
                  pw.Text(
                    'Rs. ${vendors.fold<double>(0.0, (sum, v) => sum + (v["remainingBalance"] ?? (v["openingBalance"] + (v["totalPurchases"] ?? 0) - v["paidAmount"]))).toStringAsFixed(2)}',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 11,
                        color: PdfColors.red),
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  // Update the existing _generatePDF method to show options
  Future<void> _generatePDF() async {
    _showPdfOptions(_filteredVendors);
  }

  void _showPaymentHistory(String vendorId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentHistoryPage(vendorId: vendorId),
      ),
    );
  }

  void _editOpeningBalance(String vendorId, double currentBalance, String currentDate) {
    TextEditingController _balanceController = TextEditingController(text: currentBalance.toString());
    DateTime _selectedDate = DateTime.now(); // Default to current date

    // Parse the current date if it exists
    try {
      if (currentDate != null && currentDate.isNotEmpty && currentDate != "Unknown Date") {
        _selectedDate = DateTime.parse(currentDate);
      }
    } catch (e) {
      print("Error parsing date: $e");
      _selectedDate = DateTime.now();
    }

    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                  languageProvider.isEnglish ? 'Edit Opening Balance' : 'اوپننگ بیلنس میں ترمیم کریں۔'
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _balanceController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: languageProvider.isEnglish ? 'New Opening Balance' : 'نیا اوپننگ بیلنس',
                      prefixIcon: Icon(Icons.account_balance),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: Text(
                      languageProvider.isEnglish ? 'Date' : 'تاریخ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      DateFormat('yyyy-MM-dd').format(_selectedDate),
                      style: TextStyle(fontSize: 16),
                    ),
                    trailing: Icon(Icons.calendar_today, color: Colors.teal),
                    onTap: () async {
                      final DateTime? pickedDate = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: Colors.teal,
                                onPrimary: Colors.white,
                                onSurface: Colors.black,
                              ),
                              textButtonTheme: TextButtonThemeData(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.teal,
                                ),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );

                      if (pickedDate != null && pickedDate != _selectedDate) {
                        setState(() {
                          _selectedDate = pickedDate;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    languageProvider.isEnglish
                        ? 'Select the date for this opening balance'
                        : 'اس اوپننگ بیلنس کے لیے تاریخ منتخب کریں',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                      languageProvider.isEnglish ? 'Cancel' : 'منسوخ کریں۔'
                  ),
                ),
                TextButton(
                  onPressed: () {
                    double newBalance = double.tryParse(_balanceController.text.trim()) ?? 0.0;

                    if (newBalance >= 0) {
                      String formattedDate = _selectedDate.toIso8601String();

                      _databaseRef.child(vendorId).update({
                        'openingBalance': newBalance,
                        'openingBalanceDate': formattedDate,
                      });

                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              languageProvider.isEnglish
                                  ? 'Opening balance updated successfully!'
                                  : 'اوپننگ بیلنس کامیابی کے ساتھ اپ ڈیٹ ہو گیا!'
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              languageProvider.isEnglish
                                  ? 'Please enter a valid balance.'
                                  : 'براہ کرم ایک درست بیلنس درج کریں۔'
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  child: Text(
                    languageProvider.isEnglish ? 'Save' : 'محفوظ کریں۔',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _selectBank(BuildContext context) async {
    if (_cachedBanks.isEmpty) {
      final bankSnapshot = await FirebaseDatabase.instance.ref('banks').once();
      if (bankSnapshot.snapshot.value == null) return null;

      final banks = bankSnapshot.snapshot.value as Map<dynamic, dynamic>;
      _cachedBanks = banks.entries.map((e) => {
        'id': e.key,
        'name': e.value['name'],
        'balance': e.value['balance']
      }).toList();
    }

    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    Map<String, dynamic>? selectedBank;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(languageProvider.isEnglish ? 'Select Bank' : 'بینک منتخب کریں'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _cachedBanks.length,
            itemBuilder: (context, index) {
              final bankData = _cachedBanks[index];
              final bankName = bankData['name'];

              // Find matching bank from pakistaniBanks list
              Bank? matchedBank = pakistaniBanks.firstWhere(
                    (b) => b.name.toLowerCase() == bankName.toLowerCase(),
                orElse: () => Bank(
                    name: bankName,
                    iconPath: 'assets/default_bank.png'
                ),
              );

              return Card(
                margin: EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: Image.asset(
                    matchedBank.iconPath,
                    width: 40,
                    height: 40,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(Icons.account_balance, size: 40);
                    },
                  ),
                  title: Text(
                    bankName,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  // subtitle: Text(
                  //   '${languageProvider.isEnglish ? "Balance" : "بیلنس"}: ${bankData['balance']} Rs',
                  // ),
                  onTap: () {
                    selectedBank = {
                      'id': bankData['id'],
                      'name': bankName,
                      'balance': bankData['balance']
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

  void _payVendor(String vendorId, String vendorName) async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final DatabaseReference vendorRef = FirebaseDatabase.instance.ref('vendors/$vendorId');

    // Variables for payment details
    String? selectedPaymentMethod;
    double paymentAmount = 0.0;
    String? description;
    Uint8List? imageBytes;
    DateTime paymentDate = DateTime.now();
    String? bankId;
    String? bankName;
    String? chequeNumber;
    DateTime? chequeDate;
    String? chequeBankId;
    String? chequeBankName;

    // Controllers
    TextEditingController amountController = TextEditingController();
    TextEditingController descriptionController = TextEditingController();
    TextEditingController chequeNumberController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(languageProvider.isEnglish ? 'Pay Vendor' : 'وینڈر کو ادائیگی کریں'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Payment amount
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: languageProvider.isEnglish ? 'Amount' : 'رقم',
                      ),
                      onChanged: (value) {
                        paymentAmount = double.tryParse(value) ?? 0.0;
                      },
                    ),
                    const SizedBox(height: 10),

                    // Description
                    TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        labelText: languageProvider.isEnglish ? 'Description' : 'تفصیل',
                      ),
                      onChanged: (value) {
                        description = value;
                      },
                    ),
                    const SizedBox(height: 10),

                    // Payment date
                    ListTile(
                      title: Text(
                        languageProvider.isEnglish
                            ? 'Date: ${DateFormat('yyyy-MM-dd HH:mm').format(paymentDate)}'
                            : 'تاریخ: ${DateFormat('yyyy-MM-dd HH:mm').format(paymentDate)}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: paymentDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (pickedDate != null) {
                          final pickedTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(paymentDate),
                          );
                          if (pickedTime != null) {
                            setState(() {
                              paymentDate = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                pickedTime.hour,
                                pickedTime.minute,
                              );
                            });
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 10),

                    // Payment method selection
                    DropdownButtonFormField<String>(
                      value: selectedPaymentMethod,
                      items: [
                        DropdownMenuItem(
                          value: 'Cash',
                          child: Text(languageProvider.isEnglish ? 'Cash' : 'نقد'),
                        ),
                        DropdownMenuItem(
                          value: 'Online',
                          child: Text(languageProvider.isEnglish ? 'Online' : 'آن لائن'),
                        ),
                        DropdownMenuItem(
                          value: 'Bank',
                          child: Text(languageProvider.isEnglish ? 'Bank' : 'بینک'),
                        ),
                        DropdownMenuItem(
                          value: 'Cheque',
                          child: Text(languageProvider.isEnglish ? 'Cheque' : 'چیک'),
                        ),
                        DropdownMenuItem(
                          value: 'Slip',
                          child: Text(languageProvider.isEnglish ? 'Slip' : 'پرچی'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          selectedPaymentMethod = value;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: languageProvider.isEnglish ? 'Payment Method' : 'ادائیگی کا طریقہ',
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Bank selection (for Bank and Cheque payments)
                    if (selectedPaymentMethod == 'Bank' || selectedPaymentMethod == 'Cheque')
                      Card(
                        child: ListTile(
                          title: Text(
                            bankName ?? (languageProvider.isEnglish ? 'Select Bank' : 'بینک منتخب کریں'),
                          ),
                          trailing: const Icon(Icons.arrow_drop_down),
                          onTap: () async {
                            final selectedBank = await _selectBank(context);
                            if (selectedBank != null) {
                              setState(() {
                                bankId = selectedBank['id'];
                                bankName = selectedBank['name'];
                                if (selectedPaymentMethod == 'Cheque') {
                                  chequeBankId = selectedBank['id'];
                                  chequeBankName = selectedBank['name'];
                                }
                              });
                            }
                          },
                        ),
                      ),

                    // Cheque details (for Cheque payments only)
                    if (selectedPaymentMethod == 'Cheque') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: chequeNumberController,
                        decoration: InputDecoration(
                          labelText: languageProvider.isEnglish ? 'Cheque Number' : 'چیک نمبر',
                        ),
                        onChanged: (value) {
                          chequeNumber = value;
                        },
                      ),
                      const SizedBox(height: 10),
                      ListTile(
                        title: Text(
                          chequeDate == null
                              ? (languageProvider.isEnglish ? 'Select Cheque Date' : 'چیک کی تاریخ منتخب کریں')
                              : DateFormat('yyyy-MM-dd').format(chequeDate!),
                        ),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (pickedDate != null) {
                            setState(() {
                              chequeDate = pickedDate;
                            });
                          }
                        },
                      ),
                    ],

                    // Image upload
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () async {
                        final image = await _pickImage();
                        if (image != null) {
                          setState(() {
                            imageBytes = base64Decode(image);
                          });
                        }
                      },
                      child: Text(languageProvider.isEnglish ? 'Upload Receipt' : 'رسید اپ لوڈ کریں'),
                    ),
                    if (imageBytes != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: GestureDetector(
                          onTap: () => _showFullScreenImage(imageBytes!),
                          child: Image.memory(
                            imageBytes!,
                            height: 100,
                            width: 100,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ کریں'),
                ),
                TextButton(
                  onPressed: () async {
                    if (selectedPaymentMethod == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(languageProvider.isEnglish
                            ? 'Please select a payment method'
                            : 'براہ کرم ادائیگی کا طریقہ منتخب کریں')),
                      );
                      return;
                    }

                    if (paymentAmount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(languageProvider.isEnglish
                            ? 'Please enter a valid amount'
                            : 'براہ کرم درست رقم درج کریں')),
                      );
                      return;
                    }

                    if (selectedPaymentMethod == 'Bank' && bankId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(languageProvider.isEnglish
                            ? 'Please select a bank'
                            : 'براہ کرم بینک منتخب کریں')),
                      );
                      return;
                    }

                    if (selectedPaymentMethod == 'Cheque') {
                      if (chequeBankId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(languageProvider.isEnglish
                              ? 'Please select a bank for the cheque'
                              : 'براہ کرم چیک کے لیے بینک منتخب کریں')),
                        );
                        return;
                      }

                      if (chequeNumber == null || chequeNumber!.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(languageProvider.isEnglish
                              ? 'Please enter cheque number'
                              : 'براہ کرم چیک نمبر درج کریں')),
                        );
                        return;
                      }

                      if (chequeDate == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(languageProvider.isEnglish
                              ? 'Please select cheque date'
                              : 'براہ کرم چیک کی تاریخ منتخب کریں')),
                        );
                        return;
                      }
                    }

                    try {
                      // Create payment data
                      final paymentData = {
                        'amount': paymentAmount,
                        'date': paymentDate.toIso8601String(),
                        'method': selectedPaymentMethod,
                        'description': description ?? '',
                        'vendorId': vendorId,
                        'vendorName': vendorName,
                        if (imageBytes != null) 'image': base64Encode(imageBytes!),
                      };

                      // Handle different payment methods
                      switch (selectedPaymentMethod) {
                        case 'Cash':
                          await _handleCashPayment(vendorRef, paymentData);
                          break;
                        case 'Online':
                          await _handleOnlinePayment(vendorRef, paymentData);
                          break;
                        case 'Bank':
                          await _handleBankPayment(
                            vendorRef,
                            paymentData,
                            bankId!,
                            bankName!,
                            paymentAmount,
                          );
                          break;
                        case 'Cheque':
                          await _handleChequePayment(
                            vendorRef,
                            paymentData,
                            chequeBankId!,
                            chequeBankName!,
                            chequeNumber!,
                            chequeDate!,
                            paymentAmount,
                          );
                          break;
                        case 'Slip':
                          await _handleSlipPayment(vendorRef, paymentData);
                          break;
                      }

                      // Update vendor's paid amount
                      await vendorRef.child('paidAmount')
                          .set(ServerValue.increment(paymentAmount));

                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(languageProvider.isEnglish
                            ? 'Payment recorded successfully!'
                            : 'ادائیگی کامیابی سے ریکارڈ ہو گئی!')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(languageProvider.isEnglish
                            ? 'Error recording payment: $e'
                            : 'ادائیگی ریکارڈ کرنے میں خرابی: $e')),
                      );
                    }
                  },
                  child: Text(languageProvider.isEnglish ? 'Save' : 'محفوظ کریں'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleCashPayment(
      DatabaseReference vendorRef,
      Map<String, dynamic> paymentData,
      )
  async {
    // Add to cashbook
    final cashbookRef = FirebaseDatabase.instance.ref('cashbook').push();
    final cashbookEntry = {
      'amount': paymentData['amount'],
      'description': paymentData['description'] ?? 'Vendor Payment',
      'date': paymentData['date'],
      'type': 'cash_out',
      'vendorId': paymentData['vendorId'],
      'vendorName': paymentData['vendorName'],
    };
    await cashbookRef.set(cashbookEntry);

    // Add payment ID to payment data
    paymentData['cashbookId'] = cashbookRef.key;

    // Save payment to vendor's payments
    await vendorRef.child('payments').push().set(paymentData);
  }

  Future<void> _handleOnlinePayment(
      DatabaseReference vendorRef,
      Map<String, dynamic> paymentData,
      )
  async {
    // Save payment to vendor's payments
    await vendorRef.child('payments').push().set(paymentData);

    // You might want to add additional online payment processing here
  }

  Future<void> _handleBankPayment(
      DatabaseReference vendorRef,
      Map<String, dynamic> paymentData,
      String bankId,
      String bankName,
      double amount,
      )
  async {
    // Add to bank transactions
    final bankRef = FirebaseDatabase.instance.ref('banks/$bankId/transactions').push();
    final bankTransaction = {
      'amount': amount,
      'description': paymentData['description'] ?? 'Vendor Payment',
      'date': paymentData['date'],
      'type': 'cash_out',
      'vendorId': paymentData['vendorId'],
      'vendorName': paymentData['vendorName'],
    };
    await bankRef.set(bankTransaction);

    // Update bank balance
    final bankBalanceRef = FirebaseDatabase.instance.ref('banks/$bankId/balance');
    final currentBalance = (await bankBalanceRef.get()).value as num? ?? 0.0;
    await bankBalanceRef.set(currentBalance - amount);

    // Add bank info to payment data
    paymentData['bankId'] = bankId;
    paymentData['bankName'] = bankName;
    paymentData['bankTransactionId'] = bankRef.key;

    // Save payment to vendor's payments
    await vendorRef.child('payments').push().set(paymentData);
  }

  Future<void> _handleChequePayment(
      DatabaseReference vendorRef,
      Map<String, dynamic> paymentData,
      String bankId,
      String bankName,
      String chequeNumber,
      DateTime chequeDate,
      double amount,
      )
  async {
    // First save to vendorCheques node
    final chequeRef = FirebaseDatabase.instance.ref('vendorCheques').push();
    final chequeData = {
      'vendorId': paymentData['vendorId'],
      'vendorName': paymentData['vendorName'],
      'amount': amount,
      'chequeNumber': chequeNumber,
      'chequeDate': chequeDate.toIso8601String(),
      'bankId': bankId,
      'bankName': bankName,
      'status': 'pending', // Initial status is pending
      'dateIssued': DateTime.now().toIso8601String(),
      'description': paymentData['description'] ?? 'Vendor Payment',
      if (paymentData['image'] != null) 'image': paymentData['image'],
      'vendorPaymentId': '', // Will be filled when cheque is cleared
    };
    await chequeRef.set(chequeData);

    // Don't add to vendor payments yet - wait for cheque to clear
    // Just show success message
    Navigator.pop(context);
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(languageProvider.isEnglish
          ? 'Cheque issued successfully! Payment will be recorded when cheque clears.'
          : 'چیک کامیابی سے جاری ہو گیا ہے! ادائیگی ریکارڈ کی جائے گی جب چیک کلئیر ہو جائے گا۔')),
    );
  }

  Future<void> _handleSlipPayment(
      DatabaseReference vendorRef,
      Map<String, dynamic> paymentData,
      )
  async {
    // Save payment to vendor's payments
    await vendorRef.child('payments').push().set(paymentData);

    // You might want to add additional slip payment processing here
  }

  Future<void> _showFullScreenImage(Uint8List imageBytes) async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(imageBytes),
        ),
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      if (dateString == "Unknown Date" || dateString.isEmpty) {
        return "Unknown Date";
      }
      DateTime date = DateTime.parse(dateString);
      return DateFormat('yyyy-MM-dd').format(date);
    } catch (e) {
      return "Invalid Date";
    }
  }

  void _navigateToEditVendor(String vendorId) async {
    try {
      // Fetch complete vendor data from Firebase
      final vendorSnapshot = await _databaseRef.child(vendorId).get();

      if (vendorSnapshot.value != null) {
        final vendorData = Map<String, dynamic>.from(vendorSnapshot.value as Map<dynamic, dynamic>);

        // Add the vendor ID to the data
        vendorData['id'] = vendorId;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddVendorPage(
              vendorData: vendorData,
              isEditMode: true,
            ),
          ),
        );
      }
    } catch (e) {
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(languageProvider.isEnglish
              ? 'Error loading vendor data: $e'
              : 'وینڈر کے ڈیٹا لوڈ کرنے میں خرابی: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  // Add this method to fetch actual remaining balance for vendors
  Future<double> _getVendorRemainingBalance(String vendorId) async {
    try {
      final vendorRef = FirebaseDatabase.instance.ref('vendors/$vendorId');
      final purchasesRef = FirebaseDatabase.instance.ref('purchases');
      final paymentsRef = vendorRef.child('payments');

      // Get opening balance
      final vendorSnapshot = await vendorRef.get();
      double openingBalance = 0.0;
      if (vendorSnapshot.exists) {
        final vendorData = vendorSnapshot.value as Map<dynamic, dynamic>;
        openingBalance = (vendorData['openingBalance'] ?? 0.0).toDouble();
      }

      // Get all purchases (credit - amount owed to vendor)
      final purchasesSnapshot = await purchasesRef
          .orderByChild('vendorId')
          .equalTo(vendorId)
          .get();

      double totalPurchases = 0.0;
      if (purchasesSnapshot.exists) {
        final purchasesMap = purchasesSnapshot.value as Map<dynamic, dynamic>;
        for (final purchase in purchasesMap.values) {
          if (purchase is Map) {
            totalPurchases += (purchase['grandTotal'] ?? 0.0).toDouble();
          }
        }
      }

      // Get all payments (debit - amount paid to vendor)
      final paymentsSnapshot = await paymentsRef.get();
      double totalPayments = 0.0;
      if (paymentsSnapshot.exists) {
        final paymentsMap = paymentsSnapshot.value as Map<dynamic, dynamic>;
        for (final payment in paymentsMap.values) {
          if (payment is Map) {
            // Only include cleared payments (for cheques)
            if (payment['method'] != 'Cheque' ||
                (payment['method'] == 'Cheque' && payment['status'] == 'cleared')) {
              totalPayments += (payment['amount'] ?? 0.0).toDouble();
            }
          }
        }
      }

      // Remaining balance = Opening Balance + Total Purchases - Total Payments
      // Opening Balance is what vendor owes us (if positive) or we owe vendor (if negative)
      // Purchases increase what we owe the vendor (credit)
      // Payments decrease what we owe the vendor (debit)
      final remainingBalance = openingBalance + totalPurchases - totalPayments;

      return remainingBalance;
    } catch (e) {
      print('Error calculating vendor balance: $e');
      return 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final bool allSelected = _selectedVendorIds.length == _filteredVendors.length &&
        _filteredVendors.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text(
          '${_selectedVendorIds.length} selected',
          style: const TextStyle(color: Colors.white),
        )
            : Text(
          languageProvider.isEnglish ? 'Vendors' : 'فروش',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
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
        actions: _isSelectionMode
            ? [
          IconButton(
            icon: Icon(
              allSelected ? Icons.deselect : Icons.select_all,
              color: Colors.white,
            ),
            tooltip: allSelected ? 'Deselect All' : 'Select All',
            onPressed: _selectAll,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            tooltip: 'Export Selected',
            onPressed: _selectedVendorIds.isEmpty
                ? null
                : () => _showPdfOptions(_selectedVendors),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _toggleSelectionMode,
          ),
        ]
            : [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddVendorPage()),
              );
            },
            icon: const Icon(Icons.add, color: Colors.white),
          ),
          IconButton(
            icon: const Icon(Icons.checklist, color: Colors.white),
            tooltip: languageProvider.isEnglish
                ? 'Select for PDF'
                : 'پی ڈی ایف کے لیے منتخب کریں',
            onPressed: _toggleSelectionMode,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            onPressed: () => _showPdfOptions(_filteredVendors),
          ),
        ],
      ),

      // ── NEW: floating action button shown only in selection mode ──
      floatingActionButton: _isSelectionMode && _selectedVendorIds.isNotEmpty
          ? FloatingActionButton.extended(
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.picture_as_pdf),
        label: Text('${_selectedVendorIds.length} → PDF'),
        onPressed: () => _showPdfOptions(_selectedVendors),
      )
          : null,

      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFF3E0), // Light orange
              Color(0xFFFFE0B2), // Lighter orange
            ],
          ),
        ),
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // ── Selection mode banner ──
            if (_isSelectionMode)
              Container(
                color: Colors.orange.shade100,
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                margin: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 18, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        languageProvider.isEnglish
                            ? 'Tap vendors to select them for PDF export'
                            : 'پی ڈی ایف برآمد کے لیے وینڈرز پر ٹیپ کریں',
                        style: TextStyle(color: Colors.orange.shade800),
                      ),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: languageProvider.isEnglish ? 'Search Vendors' : 'دکانداروں کو تلاش کریں',
                prefixIcon: Icon(Icons.search, color: Color(0xFFFF8A65)),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFF8A65)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFF8A65)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _isLoading
                ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Color(0xFFFF8A65)),
              ),
            )
                : _filteredVendors.isEmpty
                ? Center(
              child: Text(
                languageProvider.isEnglish
                    ? 'No vendors added yet'
                    : 'ابھی تک کوئی وینڈر شامل نہیں کیا گیا۔',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFFE65100), // Dark orange
                ),
              ),
            )
                : Expanded(
              child: ListView.builder(
                itemCount: _filteredVendors.length,
                itemBuilder: (context, index) {
                  final vendor = _filteredVendors[index];
                  final isSelected = _selectedVendorIds.contains(vendor["id"]);

                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    elevation: 6,
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    // ── highlight selected cards ──
                    color: _isSelectionMode && isSelected
                        ? Colors.orange.shade100
                        : null,
                    // shape: _isSelectionMode && isSelected
                    //     ? RoundedRectangleBorder(
                    //     borderRadius: BorderRadius.circular(8),
                    //     side: const BorderSide(color: Colors.orange, width: 2))
                    //     : null,
                    child: InkWell(
                      onTap: _isSelectionMode
                          ? () => _toggleVendorSelection(vendor["id"])
                          : () => _navigateToEditVendor(vendor["id"]),
                      borderRadius: BorderRadius.circular(12.0),
                      child: ListTile(
                        // ── NEW: leading checkbox in selection mode ──
                        leading: _isSelectionMode
                            ? Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleVendorSelection(vendor["id"]),
                          activeColor: Colors.orange,
                        )
                            : CircleAvatar(
                          backgroundColor: Colors.orange,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          vendor["name"],
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE65100), // Dark orange
                          ),
                        ),
                        // Update the subtitle section in ListTile (around line 1135)
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${languageProvider.isEnglish ? 'Vendor' : 'وینڈر'} #${index + 1}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                            ),
                            Text(
                              '${languageProvider.isEnglish ? 'Opening Balance' : 'اوپننگ بیلنس'}: ${vendor["openingBalance"].toStringAsFixed(2)} Rs',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF8A65),
                              ),
                            ),
                            Text(
                              '${languageProvider.isEnglish ? 'Total Purchases' : 'کل خریداری'}: ${(vendor["totalPurchases"] ?? 0).toStringAsFixed(2)} Rs',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[700],
                              ),
                            ),
                            Text(
                              '${languageProvider.isEnglish ? 'Paid' : 'ادائیگی'}: ${vendor["paidAmount"].toStringAsFixed(2)} Rs',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green[700],
                              ),
                            ),
                            Text(
                              '${languageProvider.isEnglish ? 'Remaining Balance' : 'باقی بیلنس'}: ${(vendor["remainingBalance"] ?? (vendor["openingBalance"] + (vendor["totalPurchases"] ?? 0) - vendor["paidAmount"])).toStringAsFixed(2)} Rs',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: (vendor["remainingBalance"] ?? 0) >= 0 ? Colors.orange[800] : Colors.red[800],
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '${languageProvider.isEnglish ? 'Opening Date' : 'تاریخ افتتاح'}: ${_formatDate(vendor["openingBalanceDate"])}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            // Only show edit/delete buttons when not in selection mode
                            if (!_isSelectionMode)
                              Row(
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.edit, color: Color(0xFFFF8A65)),
                                    onPressed: () => _editOpeningBalance(
                                        vendor["id"],
                                        vendor["openingBalance"],
                                        vendor["openingBalanceDate"] // Pass the current date
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _confirmDelete(vendor["id"]),
                                  ),
                                ],
                              )
                          ],
                        ),
                        // Only show trailing icons when not in selection mode
                        trailing: _isSelectionMode
                            ? null
                            : SizedBox(
                          width: 170,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                icon: Icon(Icons.list_alt, color: Color(0xFFFF8A65)),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => VendorItemWiseLedgerPage(
                                      vendorId: vendor["id"],
                                      vendorName: vendor["name"],
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.payment, color: Color(0xFFFF8A65)),
                                onPressed: () => _payVendor(vendor["id"], vendor["name"]),
                              ),
                              IconButton(
                                icon: Icon(Icons.history, color: Color(0xFFFF8A65)),
                                onPressed: () => _showPaymentHistory(vendor["id"]),
                              ),
                              IconButton(
                                icon: Icon(Icons.account_balance_wallet, color: Color(0xFFFF8A65)),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => VendorLedgerPage(
                                      vendorId: vendor["id"],
                                      vendorName: vendor["name"],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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

class PaymentHistoryPage extends StatefulWidget {
  final String vendorId;

  const PaymentHistoryPage({super.key, required this.vendorId});

  @override
  State<PaymentHistoryPage> createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
  late List<Map<String, dynamic>> payments;

  @override
  void initState() {
    super.initState();
    payments = [];
    _fetchPaymentHistory();
  }


  void _deletePayment(String paymentId, double amount) async {

    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    // Show confirmation dialog
    bool confirmDelete = await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(languageProvider.isEnglish ? 'Confirm Delete' : 'حذف کی تصدیق کریں'),
          content: Text(languageProvider.isEnglish
              ? 'Are you sure you want to delete this payment?'
              : 'کیا آپ واقعی اس ادائیگی کو حذف کرنا چاہتے ہیں؟'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false); // Return false if "No" is pressed
              },
              child: Text(languageProvider.isEnglish ? 'No' : 'نہیں'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true); // Return true if "Yes" is pressed
              },
              child: Text(languageProvider.isEnglish ? 'Yes' : 'ہاں'),
            ),
          ],
        );
      },
    );

    // If the user confirms deletion, proceed with deleting the payment
    if (confirmDelete == true) {
      try {
        // Delete the payment from Firebase
        await FirebaseDatabase.instance
            .ref('vendors/${widget.vendorId}/payments/$paymentId')
            .remove();

        // Update the total paid amount by subtracting the deleted payment amount
        await FirebaseDatabase.instance
            .ref('vendors/${widget.vendorId}/paidAmount')
            .set(ServerValue.increment(-amount));

        // Refresh the payment list
        _fetchPaymentHistory();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content:Text(languageProvider.isEnglish ? 'Payment deleted successfully!' : 'ادائیگی کامیابی سے حذف ہو گئی!')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(languageProvider.isEnglish ? 'Error deleting payment: $e' : 'ادائیگی حذف کرنے میں خرابی: $e')),
        );
      }
    }
  }

  @override
  Future<void> _fetchPaymentHistory() async {
    final DatabaseReference paymentsRef = FirebaseDatabase.instance
        .ref('vendors/${widget.vendorId}/payments');
    final snapshot = await paymentsRef.get();

    final data = snapshot.value as Map<dynamic, dynamic>?;
    if (data == null) {
      setState(() => payments = []);
      return;
    }

    setState(() {
      payments = data.entries.map((entry) {
        return {
          'id': entry.key,
          'amount': (entry.value['amount'] as num).toDouble(),
          'description': entry.value['description'] ?? '',
          'date': entry.value['date'] ?? '',
          'method': entry.value['method'] ?? 'Unknown', // Changed from 'paymentMethod' to 'method'
          'image': entry.value['image'] ?? '', // Changed from 'imageBase64' to 'image'
        };
      }).toList();
    });
  }


  void _editPayment(String paymentId, double existingAmount, String existingDescription, String existingMethod) {
    TextEditingController amountController = TextEditingController(text: existingAmount.toString());
    TextEditingController descriptionController = TextEditingController(text: existingDescription);

    // Map the existing method to a valid dropdown value
    String mapToValidMethod(String method) {
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

      if (languageProvider.isEnglish) {
        if (method.toLowerCase().contains('cash')) return 'Cash';
        if (method.toLowerCase().contains('online')) return 'Online';
        if (method.toLowerCase().contains('bank')) return 'Bank';
        if (method.toLowerCase().contains('cheque') || method.toLowerCase().contains('check')) return 'Cheque';
        if (method.toLowerCase().contains('slip')) return 'Slip';
        return 'Cash'; // default fallback
      } else {
        if (method.contains('نقد')) return 'نقد';
        if (method.contains('آن لائن')) return 'آن لائن';
        if (method.contains('بینک')) return 'بینک';
        if (method.contains('چیک')) return 'چیک';
        if (method.contains('پرچی')) return 'پرچی';
        return 'نقد'; // default fallback
      }
    }

    String selectedPaymentMethod = mapToValidMethod(existingMethod);
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    String? _base64Image;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(languageProvider.isEnglish ? 'Edit Payment' : 'ادائیگی میں ترمیم کریں'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: languageProvider.isEnglish ? 'Amount' : 'رقم',
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        labelText: languageProvider.isEnglish ? 'Description' : 'تفصیل',
                        prefixIcon: Icon(Icons.description),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedPaymentMethod,
                      decoration: InputDecoration(
                        labelText: languageProvider.isEnglish ? 'Payment Method' : 'ادائیگی کا طریقہ',
                        prefixIcon: Icon(Icons.payment),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: languageProvider.isEnglish ? "Cash" : "نقد",
                          child: Text(languageProvider.isEnglish ? "Cash" : "نقد"),
                        ),
                        DropdownMenuItem(
                          value: languageProvider.isEnglish ? "Online" : "آن لائن",
                          child: Text(languageProvider.isEnglish ? "Online" : "آن لائن"),
                        ),
                        DropdownMenuItem(
                          value: languageProvider.isEnglish ? "Bank" : "بینک",
                          child: Text(languageProvider.isEnglish ? "Bank" : "بینک"),
                        ),
                        DropdownMenuItem(
                          value: languageProvider.isEnglish ? "Cheque" : "چیک",
                          child: Text(languageProvider.isEnglish ? "Cheque" : "چیک"),
                        ),
                        DropdownMenuItem(
                          value: languageProvider.isEnglish ? "Slip" : "پرچی",
                          child: Text(languageProvider.isEnglish ? "Slip" : "پرچی"),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            selectedPaymentMethod = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () async {
                        String? base64 = await _pickImage();
                        if (base64 != null) {
                          setState(() => _base64Image = base64);
                        }
                      },
                      child: Text(languageProvider.isEnglish ? 'Change Image' : 'تصویر تبدیل کریں'),
                    ),
                    if (_base64Image != null)
                      GestureDetector(
                        onTap: () => _showImagePreview(_base64Image!),
                        child: Image.memory(
                          base64Decode(_base64Image!),
                          height: 100,
                          width: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    double newAmount = double.tryParse(amountController.text.trim()) ?? 0.0;
                    String newDescription = descriptionController.text.trim();

                    if (newAmount > 0) {
                      final difference = newAmount - existingAmount;

                      final updateData = {
                        'amount': newAmount,
                        'description': newDescription,
                        'method': selectedPaymentMethod, // Use 'method' instead of 'paymentMethod'
                      };

                      // Add image only if changed
                      if (_base64Image != null) {
                        updateData['image'] = _base64Image!; // Use 'image' instead of 'imageBase64'
                      }

                      FirebaseDatabase.instance
                          .ref('vendors/${widget.vendorId}/payments/$paymentId')
                          .update(updateData);

                      FirebaseDatabase.instance
                          .ref('vendors/${widget.vendorId}/paidAmount')
                          .set(ServerValue.increment(difference));

                      Navigator.pop(context);
                      _fetchPaymentHistory();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(languageProvider.isEnglish ? 'Payment updated successfully!' : 'ادائیگی کامیابی سے اپ ڈیٹ ہو گئی!')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(languageProvider.isEnglish ? 'Please enter a valid amount.' : 'براہ کرم درست رقم درج کریں۔')),
                      );
                    }
                  },
                  child: Text(languageProvider.isEnglish ? 'Save' : 'محفوظ کریں'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ کریں'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showImagePreview(String base64Image) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(languageProvider.isEnglish ? 'Payment Receipt' : 'ادائیگی کی رسید'),
        content: InteractiveViewer(
          minScale: 0.1,
          maxScale: 4.0,
          child: Image.memory(base64Decode(base64Image)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(languageProvider.isEnglish ? 'Close' : 'بند کریں'),
          ),
        ],
      ),
    );
  }


  // Add this method to fix '_pickImage' error
  Future<String?> _pickImage() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final ImagePicker _picker = ImagePicker();
    Uint8List? imageBytes;

    // Capture image
    XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
      maxWidth: 800,
      maxHeight: 800,
    );

    if (pickedFile != null) {
      // Compress and convert to Base64
      imageBytes = await pickedFile.readAsBytes();
      return await _compressAndConvertToBase64(imageBytes);
    }
    return null;
  }

  // Add this helper method
  Future<String> _compressAndConvertToBase64(Uint8List imageBytes) async {
    final codec = await ui.instantiateImageCodec(
      imageBytes,
      targetWidth: 400,
      targetHeight: 400,
    );

    final frame = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return base64Encode(byteData!.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(languageProvider.isEnglish ? 'Payment History' : 'ادائیگی کی تاریخ'),
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
      body: payments.isEmpty
          ? Center(child: Text(
        languageProvider.isEnglish ? 'No payments recorded for this vendor.' : 'اس وینڈر کے لیے کوئی ادائیگی ریکارڈ نہیں کی گئی۔',
      ))
          : ListView.builder(
        itemCount: payments.length,
        itemBuilder: (context, index) {
          final payment = payments[index];
          // Use 'image' instead of 'imageBase64'
          final hasImage = payment['image'] != null && payment['image'].isNotEmpty;

          return ListTile(
            leading: hasImage
                ? GestureDetector(
              onTap: () => _showImagePreview(payment['image']),
              child: Image.memory(
                base64Decode(payment['image']),
                width: 50,
                height: 50,
                fit: BoxFit.cover,
              ),
            )
                : const Icon(Icons.receipt, size: 40),
            title: Text("${languageProvider.isEnglish ? 'Amount' : 'رقم'}: ${payment['amount']}Rs"),
            subtitle: Text(
              "${languageProvider.isEnglish ? 'Description' : 'تفصیل'}: ${payment['description']}\n"
                  "${languageProvider.isEnglish ? 'Date' : 'تاریخ'}: ${payment['date']}\n"
                  "${languageProvider.isEnglish ? 'Payment Method' : 'ادائیگی کا طریقہ'}: ${payment['method']}", // Use 'method' instead of 'paymentMethod'
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.orange),
                  onPressed: () => _editPayment(
                    payment['id'],
                    payment['amount'],
                    payment['description'],
                    payment['method'], // Use 'method' instead of 'paymentMethod'
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deletePayment(payment['id'], payment['amount']),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}