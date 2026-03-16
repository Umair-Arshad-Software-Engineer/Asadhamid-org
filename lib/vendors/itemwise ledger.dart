import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

import '../Provider/lanprovider.dart';
import '../bankmanagement/banknames.dart';

class VendorItemWiseLedgerPage extends StatefulWidget {
  final String vendorId;
  final String vendorName;

  const VendorItemWiseLedgerPage({
    super.key,
    required this.vendorId,
    required this.vendorName,
  });

  @override
  State<VendorItemWiseLedgerPage> createState() => _VendorItemWiseLedgerPageState();
}

class _VendorItemWiseLedgerPageState extends State<VendorItemWiseLedgerPage> {
  List<Map<String, dynamic>> _ledgerEntries = [];
  List<Map<String, dynamic>> _filteredLedgerEntries = [];
  bool _isLoading = true;
  double _totalCredit = 0.0;
  double _totalDebit = 0.0;
  double _currentBalance = 0.0;
  DateTimeRange? _selectedDateRange;
  Map<String, String> _bankIconMap = {};

  @override
  void initState() {
    super.initState();
    _initializeBankIcons();
    _fetchLedgerData();
  }

  void _initializeBankIcons() {
    _bankIconMap = {
      for (var bank in pakistaniBanks)
        bank.name.toLowerCase(): bank.iconPath
    };
  }

  Future<void> _fetchLedgerData() async {
    try {
      final DatabaseReference vendorRef = FirebaseDatabase.instance.ref('vendors/${widget.vendorId}');
      final DatabaseReference purchasesRef = FirebaseDatabase.instance.ref('purchases');
      final DatabaseReference paymentsRef = FirebaseDatabase.instance.ref('vendors/${widget.vendorId}/payments');

      // Fetch vendor data to get Opening Balance
      final vendorSnapshot = await vendorRef.get();
      double openingBalance = 0.0;
      String openingBalanceDate = "Unknown Date";

      if (vendorSnapshot.exists) {
        final vendorData = vendorSnapshot.value as Map<dynamic, dynamic>;
        openingBalance = (vendorData['openingBalance'] ?? 0.0).toDouble();

        final rawDate = vendorData['openingBalanceDate'] ?? "Unknown Date";
        final parsedDate = DateTime.tryParse(rawDate);
        openingBalanceDate = parsedDate != null
            ? "${parsedDate.month}/${parsedDate.day}/${parsedDate.year % 100}"
            : "Unknown Date";
      }

      // Fetch purchases data and extract individual items
      final purchasesSnapshot = await purchasesRef
          .orderByChild('vendorId')
          .equalTo(widget.vendorId)
          .get();

      final List<Map<String, dynamic>> itemEntries = [];

      if (purchasesSnapshot.exists) {
        final purchasesMap = purchasesSnapshot.value as Map<dynamic, dynamic>;

        purchasesMap.forEach((purchaseKey, purchaseValue) {
          if (purchaseValue is Map) {
            final purchaseDate = purchaseValue['timestamp'] ?? 'Unknown Date';
            final purchaseNumber = purchaseValue['purchaseNumber'] ?? purchaseKey;
            final refNo = purchaseValue['refNo'] ?? '';

            // Process each item individually
            if (purchaseValue['items'] != null) {
              List<Map<String, dynamic>> itemsList = [];

              if (purchaseValue['items'] is Map) {
                // Handle map format
                final itemsMap = purchaseValue['items'] as Map<dynamic, dynamic>;
                itemsList = itemsMap.entries.map((entry) {
                  final itemData = entry.value;
                  return {
                    'itemName': itemData['itemName'] ?? 'Unknown Item',
                    'quantity': (itemData['quantity'] ?? 0).toDouble(),
                    'weight': (itemData['weight'] ?? 0).toDouble(),
                    'price': (itemData['purchasePrice'] ?? itemData['price'] ?? 0.0).toDouble(),
                    'total': (itemData['total'] ?? ((itemData['weight'] ?? 0) * (itemData['purchasePrice'] ?? itemData['price'] ?? 0.0))).toDouble(),
                  };
                }).toList();
              } else if (purchaseValue['items'] is List) {
                // Handle list format
                final itemsListData = purchaseValue['items'] as List<dynamic>;
                itemsList = itemsListData.map((item) {
                  if (item is Map) {
                    return {
                      'itemName': item['itemName'] ?? 'Unknown Item',
                      'quantity': (item['quantity'] ?? 0).toDouble(),
                      'weight': (item['weight'] ?? 0).toDouble(),
                      'price': (item['purchasePrice'] ?? item['price'] ?? 0.0).toDouble(),
                      'total': (item['total'] ?? ((item['weight'] ?? 0) * (item['purchasePrice'] ?? item['price'] ?? 0.0))).toDouble(),
                    };
                  }
                  return {
                    'itemName': 'Unknown Item',
                    'quantity': 0.0,
                    'weight': 0.0,
                    'price': 0.0,
                    'total': 0.0,
                  };
                }).toList();
              }

              // Create individual entries for each item
              for (final item in itemsList) {
                itemEntries.add({
                  'date': purchaseDate,
                  // 'description': 'Purchase - ${item['itemName']}',
                  'description': 'Ref. No ${refNo}',
                  'credit': item['total'],
                  'debit': 0.0,
                  'type': 'credit',
                  'purchaseId': purchaseKey,
                  'purchaseNumber': purchaseNumber,
                  'refNo': refNo,
                  'itemName': item['itemName'],
                  'quantity': item['quantity'],
                  'weight': item['weight'],
                  'unitPrice': item['price'],
                  'itemTotal': item['total'],
                  'isItem': true,
                });
              }
            }
          }
        });
      }

      // Fetch payments data
      final paymentsSnapshot = await paymentsRef.get();
      final List<Map<String, dynamic>> payments = [];

      if (paymentsSnapshot.exists) {
        final paymentsMap = paymentsSnapshot.value as Map<dynamic, dynamic>;

        paymentsMap.forEach((paymentKey, paymentValue) {
          if (paymentValue is Map) {
            final paymentMethod = paymentValue['method'] ??
                paymentValue['paymentMethod'] ??
                'Unknown Method';

            payments.add({
              'date': paymentValue['date'] ?? 'Unknown Date',
              'chequeDate': paymentValue['chequeDate'],
              // 'description': 'Payment via $paymentMethod',
              'description': paymentValue['description'],
              'credit': 0.0,
              'debit': (paymentValue['amount'] ?? 0.0).toDouble(),
              'type': 'debit',
              'method': paymentMethod,
              'bankName': paymentValue['bankName'] ?? paymentValue['chequeBankName'],
              'paymentId': paymentKey,
              'isItem': false,
            });
          }
        });
      }

      // Combine entries
      final combinedEntries = [...itemEntries, ...payments];

      // Add Opening Balance as the first row
      final openingBalanceEntry = {
        'date': openingBalanceDate,
        'description': 'Opening Balance',
        'credit': openingBalance,
        'debit': 0.0,
        'balance': openingBalance,
        'isItem': false,
      };

      combinedEntries.insert(0, openingBalanceEntry);

      // Sort entries by date
      combinedEntries.sort((a, b) {
        final dateA = DateTime.tryParse(_getDisplayDate(a)) ?? DateTime(1970);
        final dateB = DateTime.tryParse(_getDisplayDate(b)) ?? DateTime(1970);
        return dateA.compareTo(dateB);
      });

      // Calculate running balance
      double balance = openingBalance;
      double totalCredit = openingBalance;
      double totalDebit = 0.0;

      for (final entry in combinedEntries.skip(1)) {
        balance += entry['credit'] - entry['debit'];
        totalCredit += entry['credit'];
        totalDebit += entry['debit'];
        entry['balance'] = balance;
      }

      setState(() {
        _ledgerEntries = combinedEntries;
        _filteredLedgerEntries = combinedEntries;
        _totalCredit = totalCredit;
        _totalDebit = totalDebit;
        _currentBalance = balance;
        _isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading ledger: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  String _getDisplayDate(Map<String, dynamic> transaction) {
    final paymentMethod = transaction['method']?.toString().toLowerCase() ?? '';
    if (paymentMethod == 'cheque' || paymentMethod == 'check') {
      if (transaction['chequeDate'] != null && transaction['chequeDate'].toString().isNotEmpty) {
        return transaction['chequeDate'].toString();
      }
    }
    return transaction['date'] ?? 'Unknown Date';
  }

  String _getFormattedDate(String dateString, bool isOpeningBalance) {
    if (isOpeningBalance) {
      return dateString;
    }

    final DateTime? parsedDate = DateTime.tryParse(dateString);
    if (parsedDate != null) {
      return "${parsedDate.month}/${parsedDate.day}/${parsedDate.year % 100}";
    }
    return "Unknown Date";
  }

  String? _getBankName(Map<String, dynamic> transaction) {
    if (transaction['bankName'] != null && transaction['bankName'].toString().isNotEmpty) {
      return transaction['bankName'].toString();
    }

    String paymentMethod = transaction['method']?.toString().toLowerCase() ?? '';
    if (paymentMethod == 'cheque' || paymentMethod == 'check') {
      if (transaction['chequeBankName'] != null && transaction['chequeBankName'].toString().isNotEmpty) {
        return transaction['chequeBankName'].toString();
      }
    }

    return null;
  }

  Future<void> _printLedger() async {
    try {
      final pdf = pw.Document();

      // Load the logo image
      final logoImage = await rootBundle.load('assets/images/logo.png');
      final logo = pw.MemoryImage(logoImage.buffer.asUint8List());

      // Load the footer logo if different
      final ByteData footerBytes = await rootBundle.load('assets/images/devlogo.png');
      final footerBuffer = footerBytes.buffer.asUint8List();
      final footerLogo = pw.MemoryImage(footerBuffer);

      // Load bank logos
      Map<String, pw.MemoryImage> bankLogoImages = {};
      for (var bank in pakistaniBanks) {
        try {
          final logoBytes = await rootBundle.load(bank.iconPath);
          final logoBuffer = logoBytes.buffer.asUint8List();
          bankLogoImages[bank.name.toLowerCase()] = pw.MemoryImage(logoBuffer);
        } catch (e) {
          print('Error loading bank logo: ${bank.iconPath} - $e');
        }
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 20),
          build: (pw.Context context) {
            return [
              // Header
              pw.Header(
                  level: 0,
                  child: pw.Row(
                      children: [
                        pw.Image(logo, width: 200, height: 150),
                        pw.Spacer(),
                        // pw.Text(
                        //   'Item-Wise Vendor Ledger',
                        //   style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                        // ),
                      ]
                  )
              ),
              pw.SizedBox(height: 8),

              // Vendor Info
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Vendor: ${widget.vendorName}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        if (_selectedDateRange != null)
                          pw.Text(
                              'Date Range: ${DateFormat('dd MMM yy').format(_selectedDateRange!.start)} - ${DateFormat('dd MMM yy').format(_selectedDateRange!.end)}'
                          ),
                        pw.Text('Generated: ${DateFormat('dd MMM yyyy hh:mm a').format(DateTime.now())}'),
                      ],
                    ),
                  ),
                ],
              ),

              pw.Header(
                level: 1,
                child: pw.Text('Item-Wise Transaction Details'),
              ),

              // Item-Wise Ledger Table
              _buildPDFItemWiseTable(bankLogoImages),
              pw.Spacer(),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Image(footerLogo, width: 20, height: 20), // Footer logo
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        'Umair Arshad',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Row(
                        children: [
                          pw.Text(
                            'Contact: 0341-6426617',
                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text(
                            '   0307-6455926',
                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                          ),
                        ]
                      )
                    ],
                  ),
                ],
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(onLayout: (format) => pdf.save());
    } catch (e) {
      print('Error generating PDF: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  String? _getBankLogoPath(String? bankName) {
    if (bankName == null) return null;
    final key = bankName.toLowerCase();
    return _bankIconMap[key];
  }


  pw.Widget _buildPDFItemWiseTable(Map<String, pw.MemoryImage> bankLogoImages) {
    List<pw.Widget> rows = [];

    // Table header
    rows.add(
      pw.Container(
        decoration: pw.BoxDecoration(color: PdfColors.grey200),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _buildPdfHeaderCell('Date', 50),
            _buildPdfHeaderCell('Description', 50),
            _buildPdfHeaderCell('Item Name', 80),
            _buildPdfHeaderCell('Qty', 35),
            _buildPdfHeaderCell('Weight', 40),
            _buildPdfHeaderCell('Unit Price', 45),
            _buildPdfHeaderCell('Payment Method', 60),
            _buildPdfHeaderCell('Bank', 55),
            _buildPdfHeaderCell('Debit', 45),
            _buildPdfHeaderCell('Credit', 45),
            _buildPdfHeaderCell('Balance', 55),
          ],
        ),
      ),
    );

    // Sort entries by date
    List<Map<String, dynamic>> sortedEntries = List.from(_filteredLedgerEntries);
    sortedEntries.sort((a, b) {
      final dateA = DateTime.tryParse(_getDisplayDate(a)) ?? DateTime(2000);
      final dateB = DateTime.tryParse(_getDisplayDate(b)) ?? DateTime(2000);
      return dateA.compareTo(dateB);
    });

    // Add ledger entries
    for (var entry in sortedEntries) {
      final isOpeningBalance = entry['description'] == 'Opening Balance';
      final isItem = entry['isItem'] == true;
      final isPayment = !isOpeningBalance && !isItem;

      final displayDate = _getFormattedDate(_getDisplayDate(entry), isOpeningBalance);
      final bankName = _getBankName(entry);
      final bankLogo = bankName != null ? bankLogoImages[bankName.toLowerCase()] : null;

      String description = entry['description'];
      String itemName = isItem ? (entry['itemName'] ?? '-') : '-';
      String quantity = isItem ? (entry['quantity']?.toStringAsFixed(2) ?? '-') : '-';
      String weight = isItem ? (entry['weight']?.toStringAsFixed(2) ?? '-') : '-';
      String unitPrice = isItem ? 'Rs ${(entry['unitPrice'] ?? 0).toStringAsFixed(2)}' : '-';
      String paymentMethod = isPayment ? (entry['method'] ?? '-') : '-';

      final debit = (entry['debit'] ?? 0).toDouble();
      final credit = (entry['credit'] ?? 0).toDouble();
      final balance = (entry['balance'] ?? 0).toDouble();

      // Main transaction row
      rows.add(
        pw.Container(
          padding: const pw.EdgeInsets.all(4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildPdfDataCell(displayDate, 50),
              _buildPdfDataCell(description, 50),
              _buildPdfDataCell(itemName, 80),
              _buildPdfDataCell(quantity, 35),
              _buildPdfDataCell(weight, 40),
              _buildPdfDataCell(unitPrice, 45),
              _buildPdfDataCell(paymentMethod, 60),
              _buildBankCell(bankName, bankLogo, 55),
              _buildPdfDataCell(
                debit > 0 ? 'Rs ${debit.toStringAsFixed(2)}' : '-',
                45,
                textColor: debit > 0 ? PdfColors.red : PdfColors.black,
              ),
              _buildPdfDataCell(
                credit > 0 ? 'Rs ${credit.toStringAsFixed(2)}' : '-',
                45,
                textColor: credit > 0 ? PdfColors.green800 : PdfColors.black,
              ),
              _buildPdfDataCell(
                'Rs ${balance.toStringAsFixed(2)}',
                55,
                fontWeight: pw.FontWeight.bold,
                textColor: PdfColors.blue800,
              ),
            ],
          ),
        ),
      );
    }

    // Add summary row
    rows.add(
      pw.Container(
        padding: const pw.EdgeInsets.all(4),
        decoration: pw.BoxDecoration(
          border: const pw.Border(
            top: pw.BorderSide(color: PdfColors.orange, width: 1.5),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _buildPdfDataCell('TOTALS', 50, fontWeight: pw.FontWeight.bold),
            _buildPdfDataCell('', 50),
            _buildPdfDataCell('', 80),
            _buildPdfDataCell('', 35),
            _buildPdfDataCell('', 40),
            _buildPdfDataCell('', 45),
            _buildPdfDataCell('', 60),
            _buildPdfDataCell('', 55),
            _buildPdfDataCell(
              'Rs ${_totalDebit.toStringAsFixed(2)}',
              45,
              fontWeight: pw.FontWeight.bold,
              textColor: PdfColors.red,
            ),
            _buildPdfDataCell(
              'Rs ${_totalCredit.toStringAsFixed(2)}',
              45,
              fontWeight: pw.FontWeight.bold,
              textColor: PdfColors.green800,
            ),
            _buildPdfDataCell(
              'Rs ${_currentBalance.toStringAsFixed(2)}',
              55,
              fontWeight: pw.FontWeight.bold,
              textColor: _currentBalance > 0 ? PdfColors.green : PdfColors.red,
            ),
          ],
        ),
      ),
    );

    return pw.Column(children: rows);
  }

  pw.Widget _buildBankCell(String? bankName, pw.MemoryImage? bankLogo, double width) {
    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.all(4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(right: pw.BorderSide(color: PdfColors.grey300)),
      ),
      child: bankName != null && bankLogo != null
          ? pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Container(
            width: 12,
            height: 12,
            margin: const pw.EdgeInsets.only(right: 3),
            child: pw.Image(bankLogo),
          ),
          pw.Expanded(
            child: pw.Text(
              bankName,
              style: const pw.TextStyle(fontSize: 7),
              textAlign: pw.TextAlign.center,
              maxLines: 2,
            ),
          ),
        ],
      )
          : pw.Text(
        bankName ?? '-',
        style: const pw.TextStyle(fontSize: 7),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _buildPdfHeaderCell(String text, double width) {
    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.all(4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(right: pw.BorderSide(color: PdfColors.grey300)),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.orange800,
          fontSize: 8,
        ),
        textAlign: pw.TextAlign.center,
        maxLines: 2,
      ),
    );
  }

  pw.Widget _buildPdfDataCell(
      String text,
      double width, {
        PdfColor? textColor,
        pw.FontWeight? fontWeight,
      })
  {
    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.all(4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(right: pw.BorderSide(color: PdfColors.grey300)),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 7,
          color: textColor ?? PdfColors.black,
          fontWeight: fontWeight,
        ),
        textAlign: pw.TextAlign.center,
        maxLines: 2,
      ),
    );
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;

        // Filter entries by date range
        final List<Map<String, dynamic>> filtered = _ledgerEntries.where((entry) {
          final entryDate = DateTime.tryParse(_getDisplayDate(entry)) ?? DateTime(1970);
          return entryDate.isAfter(picked.start.subtract(const Duration(days: 1))) &&
              entryDate.isBefore(picked.end.add(const Duration(days: 1)));
        }).toList();

        // Add opening balance if missing
        final openingBalanceIndex = filtered.indexWhere((e) => e['description'] == 'Opening Balance');
        if (openingBalanceIndex == -1) {
          final openingBalanceEntry = _ledgerEntries.firstWhere(
                (e) => e['description'] == 'Opening Balance',
            orElse: () => {},
          );
          if (openingBalanceEntry.isNotEmpty) {
            filtered.insert(0, openingBalanceEntry);
          }
        }

        _filteredLedgerEntries = filtered;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.vendorName} - Item-Wise Ledger'),
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
            icon: const Icon(Icons.calendar_today, color: Colors.white),
            onPressed: () => _selectDateRange(context),
          ),
          IconButton(
            icon: const Icon(Icons.print, color: Colors.white),
            onPressed: _printLedger,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _buildSummaryCards(),
          Expanded(
            child: isMobile ? _buildMobileItemWiseView() : _buildDesktopItemWiseView(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileItemWiseView() {
    const double fontSize = 10.0;

    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        // Table header
        Container(
          color: Colors.blue[100],
          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black, width: 1))),
                  child: const Text('Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize)),
                ),
              ),
              Expanded(
                flex: 3,
                child: Container(
                  decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black, width: 1))),
                  child: const Text('Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Container(
                  decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black, width: 1))),
                  child: const Text('Credit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize), textAlign: TextAlign.right),
                ),
              ),
              Expanded(
                flex: 2,
                child: Container(
                  decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black, width: 1))),
                  child: const Text('Debit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize), textAlign: TextAlign.right),
                ),
              ),
              const Expanded(
                flex: 2,
                child: Text('Balance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize), textAlign: TextAlign.right),
              ),
            ],
          ),
        ),

        // Table rows
        ..._filteredLedgerEntries.map((entry) {
          final isOpeningBalance = entry['description'] == 'Opening Balance';
          final isItem = entry['isItem'] == true;
          final dateText = isOpeningBalance
              ? entry['date']
              : _getFormattedDate(_getDisplayDate(entry), false);

          return Container(
            color: isOpeningBalance ? Colors.yellow[100] : Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black, width: 1))),
                    child: Text(dateText, style: TextStyle(fontWeight: isOpeningBalance ? FontWeight.bold : FontWeight.normal, fontSize: fontSize)),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black, width: 1))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry['description'],
                          style: TextStyle(fontWeight: isOpeningBalance ? FontWeight.bold : FontWeight.normal, fontSize: fontSize),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isItem && entry['itemName'] != null)
                          Text(
                            'Item: ${entry['itemName']}',
                            style: TextStyle(fontSize: 8, color: Colors.grey[700]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black, width: 1))),
                    child: Text(entry['credit'].toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(fontSize: fontSize)),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black, width: 1))),
                    child: Text(entry['debit'].toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(fontSize: fontSize)),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(entry['balance'].toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(fontSize: fontSize)),
                ),
              ],
            ),
          );
        }).toList(),

        // Total row
        Container(
          color: Colors.grey[300],
          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
          child: Row(
            children: [
              // Expanded(
              //   flex: 2,
              //   child: Container(
              //     decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black, width: 1))),
              //     child: const Text('', style: TextStyle(fontSize: fontSize)),
              //   ),
              // ),
              Expanded(
                flex: 3,
                child: Container(
                  decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black, width: 1))),
                  child: const Text('Totals', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Container(
                  decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black, width: 1))),
                  child: Text(_totalCredit.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Container(
                  decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black, width: 1))),
                  child: Text(_totalDebit.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(_currentBalance.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopItemWiseView() {
    return Column(
      children: [
        // Header section
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF8A65), Color(0xFFFFB74D)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              _buildEnhancedHeaderCell('Date', 1.2),
              _buildEnhancedHeaderCell('Description', 1.5),
              _buildEnhancedHeaderCell('Item Name', 3),
              _buildEnhancedHeaderCell('Qty', 1),
              _buildEnhancedHeaderCell('Weight', 1),
              _buildEnhancedHeaderCell('Unit Price', 1.2),
              _buildEnhancedHeaderCell('Method', 1.2),
              _buildEnhancedHeaderCell('Bank', 1.5),
              _buildEnhancedHeaderCell('Credit (Rs)', 1.3),
              _buildEnhancedHeaderCell('Debit (Rs)', 1.3),
              _buildEnhancedHeaderCell('Balance (Rs)', 1.5),
            ],
          ),
        ),

        // Table Content
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Data Rows
                  ..._filteredLedgerEntries.asMap().entries.map((entryWithIndex) {
                    final index = entryWithIndex.key;
                    final entry = entryWithIndex.value;
                    final isOpeningBalance = entry['description'] == 'Opening Balance';
                    final isItem = entry['isItem'] == true;
                    final isPayment = !isOpeningBalance && !isItem;
                    final bool isEvenRow = index % 2 == 0;

                    return _buildEnhancedItemWiseRow(
                      entry,
                      isOpeningBalance,
                      isItem,
                      isPayment,
                      isEvenRow ? Colors.white : Colors.grey[50]!,
                    );
                  }).toList(),

                  // Enhanced Total Row
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.grey[100]!, Colors.grey[200]!],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      border: Border(
                        top: BorderSide(color: Colors.grey[400]!, width: 2),
                      ),
                    ),
                    child: Row(
                      children: [
                        _buildEnhancedDataCell(
                          'GRAND TOTAL',
                          1.2,
                          false,
                          fontWeight: FontWeight.bold,
                          backgroundColor: Colors.transparent,
                        ),
                        _buildEnhancedDataCell('', 1.5, false, backgroundColor: Colors.transparent),
                        _buildEnhancedDataCell('', 3, false, backgroundColor: Colors.transparent),
                        _buildEnhancedDataCell('', 1, false, backgroundColor: Colors.transparent),
                        _buildEnhancedDataCell('', 1, false, backgroundColor: Colors.transparent),
                        _buildEnhancedDataCell('', 1.2, false, backgroundColor: Colors.transparent),
                        _buildEnhancedDataCell('', 1.2, false, backgroundColor: Colors.transparent),
                        _buildEnhancedDataCell('', 1.5, false, backgroundColor: Colors.transparent),
                        _buildEnhancedDataCell(
                          'Rs ${_totalCredit.toStringAsFixed(2)}',
                          1.3,
                          false,
                          fontWeight: FontWeight.bold,
                          textColor: Colors.green[800],
                          backgroundColor: Colors.transparent,
                        ),
                        _buildEnhancedDataCell(
                          'Rs ${_totalDebit.toStringAsFixed(2)}',
                          1.3,
                          false,
                          fontWeight: FontWeight.bold,
                          textColor: Colors.red[800],
                          backgroundColor: Colors.transparent,
                        ),
                        _buildEnhancedDataCell(
                          'Rs ${_currentBalance.toStringAsFixed(2)}',
                          1.5,
                          false,
                          fontWeight: FontWeight.bold,
                          textColor: _currentBalance >= 0 ? Colors.blue[800] : Colors.orange[800],
                          backgroundColor: Colors.transparent,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEnhancedItemWiseRow(
      Map<String, dynamic> entry,
      bool isOpeningBalance,
      bool isItem,
      bool isPayment,
      Color backgroundColor,
      )
  {
    final dateText = isOpeningBalance
        ? entry['date']
        : _getFormattedDate(_getDisplayDate(entry), false);

    final bankName = _getBankName(entry);
    final bankLogoPath = _getBankLogoPath(bankName);

    return Container(
      decoration: BoxDecoration(
        color: isOpeningBalance
            ? Colors.amber[50]
            : backgroundColor,
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          _buildEnhancedDataCell(dateText, 1.2, false,
            fontWeight: isOpeningBalance ? FontWeight.bold : FontWeight.normal,
            textColor: isOpeningBalance ? Colors.orange[800] : Colors.black87,
          ),
          _buildEnhancedDataCell(
            entry['description'],
            1.5,
            false,
            fontWeight: isOpeningBalance ? FontWeight.bold : FontWeight.normal,
            textColor: isOpeningBalance ? Colors.orange[800] : Colors.black87,
          ),
          _buildEnhancedDataCell(
            isItem ? (entry['itemName'] ?? '-') : '-',
            3,
            false,
            textColor: isItem ? Colors.blue[800] : Colors.grey[500],
          ),
          _buildEnhancedDataCell(
            isItem ? (entry['quantity']?.toStringAsFixed(2) ?? '-') : '-',
            1,
            false,
            textColor: isItem ? Colors.purple[800] : Colors.grey[500],
          ),
          _buildEnhancedDataCell(
            isItem ? (entry['weight']?.toStringAsFixed(2) ?? '-') : '-',
            1,
            false,
            textColor: isItem ? Colors.purple[800] : Colors.grey[500],
          ),
          _buildEnhancedDataCell(
            isItem ? 'Rs ${(entry['unitPrice'] ?? 0).toStringAsFixed(2)}' : '-',
            1.2,
            false,
            textColor: isItem ? Colors.green[800] : Colors.grey[500],
          ),
          _buildEnhancedDataCell(
            isPayment ? (entry['method'] ?? '-') : '-',
            1.2,
            false,
            textColor: isPayment ? Colors.orange[800] : Colors.grey[500],
          ),
          _buildEnhancedDataCell(
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (bankLogoPath != null) ...[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Image.asset(bankLogoPath),
                  ),
                  SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    bankName ?? '-',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[800],
                      fontWeight: bankName != null ? FontWeight.w500 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            1.5,
            false,
          ),
          _buildEnhancedDataCell(
            entry['credit'] > 0 ? 'Rs ${entry['credit'].toStringAsFixed(2)}' : '-',
            1.3,
            false,
            fontWeight: entry['credit'] > 0 ? FontWeight.w600 : FontWeight.normal,
            textColor: entry['credit'] > 0 ? Colors.green[700] : Colors.grey[500],
          ),
          _buildEnhancedDataCell(
            entry['debit'] > 0 ? 'Rs ${entry['debit'].toStringAsFixed(2)}' : '-',
            1.3,
            false,
            fontWeight: entry['debit'] > 0 ? FontWeight.w600 : FontWeight.normal,
            textColor: entry['debit'] > 0 ? Colors.red[700] : Colors.grey[500],
          ),
          _buildEnhancedDataCell(
            'Rs ${entry['balance'].toStringAsFixed(2)}',
            1.5,
            false,
            fontWeight: FontWeight.bold,
            textColor: entry['balance'] >= 0 ? Colors.blue[700] : Colors.orange[700],
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedHeaderCell(String text, double flexValue) {
    return Expanded(
      flex: (flexValue * 10).round(),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: Colors.white.withOpacity(0.3))),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildEnhancedDataCell(
      dynamic content,
      double flexValue,
      bool isMobile, {
        Color? textColor,
        FontWeight? fontWeight,
        Color backgroundColor = Colors.transparent,
      }) {
    return Expanded(
      flex: (flexValue * 10).round(),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border(right: BorderSide(color: Colors.grey[200]!)),
        ),
        child: content is Widget
            ? content
            : Text(
          content.toString(),
          style: TextStyle(
            fontSize: 13,
            color: textColor ?? Colors.black87,
            fontWeight: fontWeight ?? FontWeight.normal,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final bool isMobile = MediaQuery.of(context).size.width < 600;

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Wrap(
        spacing: 8.0,
        runSpacing: 8.0,
        alignment: WrapAlignment.center,
        children: [
          _buildSummaryCard(
            title: 'Total Credit',
            value: _totalCredit,
            color: Colors.green,
            icon: Icons.arrow_upward,
            isMobile: isMobile,
          ),
          _buildSummaryCard(
            title: 'Total Debit',
            value: _totalDebit,
            color: Colors.red,
            icon: Icons.arrow_downward,
            isMobile: isMobile,
          ),
          _buildSummaryCard(
            title: 'Current Balance',
            value: _currentBalance,
            color: _currentBalance >= 0 ? Colors.blue : Colors.orange,
            icon: Icons.account_balance_wallet,
            isMobile: isMobile,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required double value,
    required Color color,
    required IconData icon,
    required bool isMobile,
  })
  {
    final double fontSize = isMobile ? 12.0 : 18.0;
    final double valueSize = isMobile ? 14.0 : 20.0;
    final double iconSize = isMobile ? 20.0 : 30.0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: iconSize, color: color),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: fontSize,
                color: color,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Rs ${value.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: valueSize,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

}