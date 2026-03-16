// items_wise_ledger_page.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../Provider/filleditemwiseledgerprovider.dart';
import '../Provider/lanprovider.dart';
import '../bankmanagement/banknames.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;

class ItemsWiseLedgerReportPage extends StatefulWidget {
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final String customerCity;

  const ItemsWiseLedgerReportPage({
    Key? key,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.customerCity,
  }) : super(key: key);

  @override
  State<ItemsWiseLedgerReportPage> createState() =>
      _ItemsWiseLedgerReportPageState();
}

class _ItemsWiseLedgerReportPageState
    extends State<ItemsWiseLedgerReportPage> {
  DateTimeRange? selectedDateRange;
  static final Map<String, String> _bankIconMap = _createBankIconMap();

  static Map<String, String> _createBankIconMap() {
    return {
      for (var bank in pakistaniBanks) bank.name.toLowerCase(): bank.iconPath
    };
  }

  String? _getBankName(Map<String, dynamic> transaction) {
    if (transaction['bankName'] != null &&
        transaction['bankName'].toString().isNotEmpty) {
      return transaction['bankName'].toString();
    }
    String paymentMethod =
        transaction['paymentMethod']?.toString().toLowerCase() ?? '';
    if (paymentMethod == 'cheque' || paymentMethod == 'check') {
      if (transaction['chequeBankName'] != null &&
          transaction['chequeBankName'].toString().isNotEmpty) {
        return transaction['chequeBankName'].toString();
      }
    }
    return null;
  }

  String? _getBankLogoPath(String? bankName) {
    if (bankName == null) return null;
    final key = bankName.toLowerCase();
    return _bankIconMap[key];
  }

  // ── High-resolution text-to-image renderer (3× scale for crisp PDF output) ──
  Future<Uint8List> _renderTextAsImageForPdf(
      String text, {
        double fontSize = 9,
        double width = 80,
        double height = 20,
      }) async {
    const double scale = 3.0;
    final double scaledWidth = width * scale;
    final double scaledHeight = height * scale;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale, scale);

    final bgPaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF000000),
          fontSize: fontSize,
          decoration: TextDecoration.none,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    );
    textPainter.layout(maxWidth: width - 4);
    textPainter.paint(canvas, Offset(2, (height - textPainter.height) / 2));

    final picture = recorder.endRecording();
    final img =
    await picture.toImage(scaledWidth.toInt(), scaledHeight.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);

    return ChangeNotifierProvider(
      create: (_) =>
      ItemsWiseLedgerProvider()..fetchItemsWiseLedger(widget.customerId),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            languageProvider.isEnglish ? 'Items Wise Ledger' : 'آئٹم وار لیجر',
            style: const TextStyle(color: Colors.white),
          ),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          actions: [
            Consumer<ItemsWiseLedgerProvider>(
              builder: (context, provider, child) {
                return IconButton(
                  icon: const Icon(Icons.print),
                  onPressed: () =>
                      _generateAndPrintPDF(provider, languageProvider),
                );
              },
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFE3F2FD),
                Color(0xFFBBDEFB),
              ],
            ),
          ),
          child: Consumer<ItemsWiseLedgerProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading) {
                return Center(
                  child: CircularProgressIndicator(
                    valueColor:
                    AlwaysStoppedAnimation(const Color(0xFF2196F3)),
                  ),
                );
              }
              if (provider.error.isNotEmpty) {
                return Center(child: Text(provider.error));
              }

              final transactions = provider.transactions;
              final totalItems =
                  transactions.where((t) => t['isItem'] == true).length;

              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCustomerInfo(context, languageProvider, provider),
                      _buildDateRangeSelector(languageProvider),
                      _buildSummaryCards(provider),
                      Text(
                        'No. of Entries: ${transactions.length + (provider.openingBalance != 0 ? 1 : 0)} (Filtered)',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF1976D2),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total Items: $totalItems | Total Payments: ${transactions.where((t) => t['isItem'] == false && t['debit'] > 0).length}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF1976D2),
                          fontSize: 12,
                        ),
                      ),
                      _buildItemsWiseTable(languageProvider),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // PDF GENERATION
  // ─────────────────────────────────────────────────────────────

  Future<void> _generateAndPrintPDF(
      ItemsWiseLedgerProvider provider,
      LanguageProvider languageProvider) async {
    try {
      final pdf = pw.Document();
      final openingBalance = provider.displayOpeningBalance;
      final transactions = provider.transactions ?? [];

      final ByteData bytes =
      await rootBundle.load('assets/images/logo.png');
      final image = pw.MemoryImage(bytes.buffer.asUint8List());

      double totalDebit = 0;
      double totalCredit = 0;
      double finalBalance = openingBalance;

      if (openingBalance > 0) {
        totalCredit += openingBalance;
      } else if (openingBalance < 0) {
        totalDebit += openingBalance.abs();
      }

      for (var transaction in transactions) {
        final debit = (transaction['debit'] ?? 0).toDouble();
        final credit = (transaction['credit'] ?? 0).toDouble();
        totalDebit += debit;
        totalCredit += credit;
        finalBalance += credit;
        finalBalance -= debit;
      }

      // ✅ Build async table BEFORE pdf.addPage
      final itemsTableWidget =
      await _buildPDFItemsWiseTable(provider, languageProvider);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin:
          const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 20),
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  children: [
                    pw.Image(image, width: 200, height: 150),
                    pw.Spacer(),
                    pw.Text(
                      'Items Wise Statement',
                      style: pw.TextStyle(
                          fontSize: 20, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Customer: ${widget.customerName}',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold)),
                        pw.Text('Phone: ${widget.customerPhone}'),
                        pw.Text('Address: ${widget.customerAddress}'),
                        pw.Text('City: ${widget.customerCity}'),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                            'Date Range: ${provider.isFiltered && provider.dateRangeFilter != null ? '${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.start)} - ${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.end)}' : 'All Transactions'}'),
                        pw.Text(
                            'Generated: ${DateFormat('dd MMM yyyy hh:mm a').format(DateTime.now())}'),
                      ],
                    ),
                  ),
                ],
              ),
              pw.Header(
                level: 1,
                child: pw.Text('Items Wise Transaction Details'),
              ),
              // ✅ Use pre-built widget — no await needed here
              itemsTableWidget,
            ];
          },
        ),
      );

      await _printPDF(pdf);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ✅ Now async — pre-renders item names & bank names as high-res images
  Future<pw.Widget> _buildPDFItemsWiseTable(
      ItemsWiseLedgerProvider provider,
      LanguageProvider languageProvider,
      ) async {
    final openingBalanceDisplay = provider.displayOpeningBalance;
    final transactions = provider.transactions ?? [];

    double totalDebit = provider.report['debit']?.toDouble() ?? 0.0;
    double totalCredit =
        openingBalanceDisplay + (provider.report['credit']?.toDouble() ?? 0.0);
    double finalBalance = provider.report['balance']?.toDouble() ?? 0.0;

    final displayFinalBalance =
    provider.isFiltered && provider.transactions.isEmpty
        ? 0.0
        : finalBalance;

    // ── Pre-render item names and bank names as high-resolution images ──
    final Map<String, Uint8List> itemNameImages = {};
    final Map<String, Uint8List> bankNameImages = {};

    for (var transaction in transactions) {
      final itemName = transaction['itemName']?.toString() ??
          transaction['details']?.toString() ??
          '-';
      if (!itemNameImages.containsKey(itemName)) {
        itemNameImages[itemName] = await _renderTextAsImageForPdf(
          itemName,
          fontSize: 9,
          width: 150,
          height: 22,
        );
      }

      final bName = _getBankName(transaction) ?? '-';
      if (!bankNameImages.containsKey(bName)) {
        bankNameImages[bName] = await _renderTextAsImageForPdf(
          bName,
          fontSize: 9,
          width: 80,
          height: 22,
        );
      }
    }

    List<pw.Widget> rows = [];

    // ── Table header (matches customer ledger style) ──
    rows.add(
      pw.Container(
        decoration: pw.BoxDecoration(color: PdfColors.grey200),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _buildPdfHeaderCell(
                languageProvider.isEnglish ? 'Date' : 'ڈیٹ', 55),
            _buildPdfHeaderCell(
                languageProvider.isEnglish ? 'Invoice No.' : 'انوائس نمبر',
                45),
            _buildPdfHeaderCell(
                languageProvider.isEnglish ? 'Item Name' : 'آئٹم کا نام',
                90),
            _buildPdfHeaderCell(
                languageProvider.isEnglish ? 'Type' : 'قسم', 40),
            _buildPdfHeaderCell(
                languageProvider.isEnglish ? 'Qty' : 'مقدار', 28),
            _buildPdfHeaderCell(
                languageProvider.isEnglish ? 'Unit Price' : 'یونٹ قیمت',
                45),
            _buildPdfHeaderCell(
                languageProvider.isEnglish
                    ? 'Payment Method'
                    : 'ادائیگی کا طریقہ',
                55),
            _buildPdfHeaderCell(
                languageProvider.isEnglish ? 'Bank' : 'بینک', 55),
            _buildPdfHeaderCell(
                languageProvider.isEnglish ? 'Debit' : 'ڈیبٹ', 45),
            _buildPdfHeaderCell(
                languageProvider.isEnglish ? 'Credit' : 'کریڈٹ', 45),
            _buildPdfHeaderCell(
                languageProvider.isEnglish ? 'Balance' : 'بیلنس', 55),
          ],
        ),
      ),
    );

    // ── Sort transactions ──
    List<Map<String, dynamic>> sortedTransactions =
    List.from(transactions);
    sortedTransactions.sort((a, b) {
      final dateA =
          DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(2000);
      final dateB =
          DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(2000);
      return dateA.compareTo(dateB);
    });

    bool openingBalanceAdded = false;
    DateTime? openingBalanceDate = provider.displayOpeningBalanceDate;

    // ── Opening balance at chronological position ──
    if ((openingBalanceDisplay != 0 || !provider.isFiltered) &&
        openingBalanceDate != null) {
      if (sortedTransactions.isEmpty ||
          openingBalanceDate.isBefore(
              DateTime.tryParse(
                  sortedTransactions.first['date']?.toString() ?? '') ??
                  DateTime(2000))) {
        rows.add(_buildOpeningBalancePdfRow(
            provider, languageProvider, openingBalanceDisplay));
        openingBalanceAdded = true;
      }
    }

    // ── Transaction rows ──
    for (var transaction in sortedTransactions) {
      final date =
          DateTime.tryParse(transaction['date']?.toString() ?? '') ??
              DateTime(2000);

      if (!openingBalanceAdded &&
          openingBalanceDate != null &&
          openingBalanceDate.isBefore(date) &&
          (openingBalanceDisplay != 0 || !provider.isFiltered)) {
        rows.add(_buildOpeningBalancePdfRow(
            provider, languageProvider, openingBalanceDisplay));
        openingBalanceAdded = true;
      }

      final isItem = transaction['isItem'] == true;
      final invoiceNumber =
          transaction['invoiceNumber']?.toString() ?? '-';
      final itemName = transaction['itemName']?.toString() ??
          transaction['details']?.toString() ??
          '-';

      final type = isItem
          ? (languageProvider.isEnglish ? 'Item' : 'آئٹم')
          : (languageProvider.isEnglish ? 'Payment' : 'ادائیگی');

      final quantity =
      isItem ? (transaction['quantity'] ?? 0).toStringAsFixed(2) : '-';
      final unitPrice =
      isItem ? (transaction['unitPrice'] ?? 0).toStringAsFixed(2) : '-';
      final paymentMethod =
          transaction['paymentMethod']?.toString() ?? '-';
      final paymentMethodText =
      _getPaymentMethodText(paymentMethod, languageProvider);
      final bankNameStr = _getBankName(transaction) ?? '-';
      final debit = (transaction['debit'] ?? 0).toDouble();
      final credit = (transaction['credit'] ?? 0).toDouble();
      final balance = (transaction['balance'] ?? 0).toDouble();

      // ── Item name cell: pre-rendered image for crisp output ──
      final pw.Widget itemNameCell = itemNameImages.containsKey(itemName)
          ? pw.Padding(
        padding: const pw.EdgeInsets.all(2),
        child: pw.Image(
          pw.MemoryImage(itemNameImages[itemName]!),
          width: 83,
          height: 18,
          fit: pw.BoxFit.contain,
        ),
      )
          : _buildPdfDataCell(itemName, 90);

      // ── Bank name cell: pre-rendered image ──
      final pw.Widget bankCell = bankNameImages.containsKey(bankNameStr)
          ? pw.Padding(
        padding: const pw.EdgeInsets.all(2),
        child: pw.Image(
          pw.MemoryImage(bankNameImages[bankNameStr]!),
          width: 48,
          height: 18,
          fit: pw.BoxFit.contain,
        ),
      )
          : _buildPdfDataCell(bankNameStr, 55);

      rows.add(
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildPdfDataCell(
                  DateFormat('dd MMM yyyy').format(date), 55),
              _buildPdfDataCell(
                invoiceNumber,
                45,
                textColor: PdfColors.blue800,
                fontWeight: pw.FontWeight.bold,
              ),
              pw.SizedBox(width: 90, child: itemNameCell),
              _buildPdfDataCell(type, 40),
              _buildPdfDataCell(quantity, 28),
              _buildPdfDataCell(
                isItem ? 'Rs $unitPrice' : '-',
                45,
                textAlign: pw.TextAlign.right,
              ),
              _buildPdfDataCell(paymentMethodText, 55),
              pw.SizedBox(width: 55, child: bankCell),
              _buildPdfDataCell(
                debit > 0 ? 'Rs ${debit.toStringAsFixed(2)}' : '-',
                45,
                textColor:
                debit > 0 ? PdfColors.red : PdfColors.black,
                textAlign: pw.TextAlign.right,
              ),
              _buildPdfDataCell(
                credit > 0 ? 'Rs ${credit.toStringAsFixed(2)}' : '-',
                45,
                textColor:
                credit > 0 ? PdfColors.green800 : PdfColors.black,
                textAlign: pw.TextAlign.right,
              ),
              _buildPdfDataCell(
                'Rs ${balance.toStringAsFixed(2)}',
                55,
                fontWeight: pw.FontWeight.bold,
                textColor: PdfColors.blue800,
                textAlign: pw.TextAlign.right,
              ),
            ],
          ),
        ),
      );
    }

    // ── Opening balance at end if not yet inserted ──
    if (!openingBalanceAdded &&
        (openingBalanceDisplay != 0 || !provider.isFiltered) &&
        openingBalanceDate != null) {
      rows.add(_buildOpeningBalancePdfRow(
          provider, languageProvider, openingBalanceDisplay));
    }

    // ── Totals row ──
    rows.add(
      pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: PdfColors.blue, width: 1.5),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _buildPdfDataCell(
              languageProvider.isEnglish ? 'TOTALS' : 'کل',
              55,
              fontWeight: pw.FontWeight.bold,
            ),
            _buildPdfDataCell('', 45),
            _buildPdfDataCell('', 90),
            _buildPdfDataCell('', 40),
            _buildPdfDataCell('', 28),
            _buildPdfDataCell('', 45),
            _buildPdfDataCell('', 55),
            _buildPdfDataCell('', 55),
            _buildPdfDataCell(
              'Rs ${totalDebit.toStringAsFixed(2)}',
              45,
              fontWeight: pw.FontWeight.bold,
              textColor: PdfColors.red,
              textAlign: pw.TextAlign.right,
            ),
            _buildPdfDataCell(
              'Rs ${totalCredit.toStringAsFixed(2)}',
              45,
              fontWeight: pw.FontWeight.bold,
              textColor: PdfColors.green800,
              textAlign: pw.TextAlign.right,
            ),
            _buildPdfDataCell(
              'Rs ${displayFinalBalance.toStringAsFixed(2)}',
              55,
              fontWeight: pw.FontWeight.bold,
              textColor:
              displayFinalBalance > 0 ? PdfColors.green : PdfColors.red,
              textAlign: pw.TextAlign.right,
            ),
          ],
        ),
      ),
    );

    return pw.Column(children: rows);
  }

  pw.Widget _buildOpeningBalancePdfRow(
      ItemsWiseLedgerProvider provider,
      LanguageProvider languageProvider,
      double openingBalanceDisplay,
      ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(color: PdfColors.grey100),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _buildPdfDataCell(
            provider.displayOpeningBalanceDate != null
                ? DateFormat('dd MMM yyyy')
                .format(provider.displayOpeningBalanceDate!)
                : '-',
            55,
          ),
          _buildPdfDataCell('-', 45), // Invoice No
          _buildPdfDataCell(
            languageProvider.isEnglish
                ? provider.openingBalanceLabel
                : (provider.isFiltered ? 'پچھلا بیلنس' : 'ابتدائی بیلنس'),
            90,
          ),
          _buildPdfDataCell('-', 40), // Type
          _buildPdfDataCell('-', 28), // Qty
          _buildPdfDataCell('-', 45), // Unit Price
          _buildPdfDataCell('-', 55), // Payment Method
          _buildPdfDataCell('-', 55), // Bank
          _buildPdfDataCell('-', 45), // Debit
          _buildPdfDataCell(
            'Rs ${openingBalanceDisplay.toStringAsFixed(2)}',
            45,
            textColor:
            openingBalanceDisplay > 0 ? PdfColors.green : PdfColors.red,
            fontWeight: pw.FontWeight.bold,
            textAlign: pw.TextAlign.right,
          ),
          _buildPdfDataCell(
            'Rs ${openingBalanceDisplay.toStringAsFixed(2)}',
            55,
            textColor:
            openingBalanceDisplay > 0 ? PdfColors.green : PdfColors.red,
            fontWeight: pw.FontWeight.bold,
            textAlign: pw.TextAlign.right,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfHeaderCell(String text, double width) {
    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.all(6),
      decoration: const pw.BoxDecoration(
        border:
        pw.Border(right: pw.BorderSide(color: PdfColors.grey300)),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.blue800,
          fontSize: 9,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _buildPdfDataCell(
      String text,
      double width, {
        PdfColor? textColor,
        pw.FontWeight? fontWeight,
        pw.TextAlign textAlign = pw.TextAlign.center,
      }) {
    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.all(6),
      decoration: const pw.BoxDecoration(
        border:
        pw.Border(right: pw.BorderSide(color: PdfColors.grey300)),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          color: textColor ?? PdfColors.black,
          fontWeight: fontWeight,
        ),
        textAlign: textAlign,
        maxLines: 2,
      ),
    );
  }

  Future<void> _printPDF(pw.Document pdf) async {
    try {
      if (kIsWeb) {
        final bytes = await pdf.save();
        final blob = html.Blob([bytes], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download =
              'items_wise_ledger_${widget.customerName}_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf';
        html.document.body?.children.add(anchor);
        anchor.click();
        html.document.body?.children.remove(anchor);
        html.Url.revokeObjectUrl(url);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF downloaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdf.save(),
          name:
          'items_wise_ledger_${widget.customerName}_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf',
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error printing PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // UI WIDGETS
  // ─────────────────────────────────────────────────────────────

  Widget _buildCustomerInfo(
      BuildContext context,
      LanguageProvider languageProvider,
      ItemsWiseLedgerProvider provider,
      ) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Center(
      child: Column(
        children: [
          Text(
            widget.customerName,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: isMobile ? 20 : 24,
              color: const Color(0xFF1976D2),
            ),
          ),
          Text(
            '${languageProvider.isEnglish ? 'Phone Number:' : 'فون نمبر:'} ${widget.customerPhone}',
            style: const TextStyle(color: Color(0xFF2196F3)),
          ),
          Text(
            '${languageProvider.isEnglish ? 'Address:' : 'پتہ:'} ${widget.customerAddress}',
            style: const TextStyle(color: Color(0xFF2196F3)),
          ),
          Text(
            '${languageProvider.isEnglish ? 'City:' : 'شہر:'} ${widget.customerCity}',
            style: const TextStyle(color: Color(0xFF2196F3)),
          ),
          const SizedBox(height: 10),
          Text(
            provider.isFiltered && provider.dateRangeFilter != null
                ? '${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.start)} - ${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.end)}'
                : 'All Transactions',
            style: const TextStyle(color: Color(0xFF2196F3)),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeSelector(LanguageProvider languageProvider) {
    return Consumer<ItemsWiseLedgerProvider>(
      builder: (context, provider, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: () async {
                final pickedDateRange = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                  initialDateRange: provider.dateRangeFilter,
                );
                if (pickedDateRange != null) {
                  provider.setDateRangeFilter(pickedDateRange);
                }
              },
              icon: const Icon(Icons.date_range),
              label: Text(languageProvider.isEnglish
                  ? 'Select Date Range'
                  : 'تاریخ منتخب کریں'),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF2196F3),
              ),
            ),
            if (provider.isFiltered)
              TextButton(
                onPressed: () => provider.setDateRangeFilter(null),
                child: Text(
                  languageProvider.isEnglish
                      ? 'Clear Filter'
                      : 'فلٹر صاف کریں',
                  style: const TextStyle(color: Color(0xFF2196F3)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCards(ItemsWiseLedgerProvider provider) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    final double openingBalance = provider.displayOpeningBalance;
    final double debit = provider.report['debit']?.toDouble() ?? 0.0;
    final double credit = provider.report['credit']?.toDouble() ?? 0.0;
    final double netBalance =
        provider.report['balance']?.toDouble() ?? 0.0;

    final displayNetBalance =
    provider.isFiltered && provider.transactions.isEmpty
        ? openingBalance
        : netBalance;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildModernSummaryCard(
            title: 'Total Debit',
            value: debit,
            icon: Icons.trending_down,
            color: const Color(0xFFE57373),
            isMobile: isMobile,
          ),
          _buildModernSummaryCard(
            title: 'Total Credit',
            value: credit,
            icon: Icons.trending_up,
            color: const Color(0xFF81C784),
            isMobile: isMobile,
          ),
          _buildModernSummaryCard(
            title: provider.isFiltered ? 'Closing Balance' : 'Net Balance',
            value: displayNetBalance,
            icon: Icons.account_balance_wallet,
            color: displayNetBalance >= 0
                ? const Color(0xFF64B5F6)
                : const Color(0xFFFFB74D),
            isMobile: isMobile,
          ),
        ],
      ),
    );
  }

  Widget _buildModernSummaryCard({
    required String title,
    required double value,
    required IconData icon,
    required Color color,
    required bool isMobile,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
                color: Colors.black12,
                blurRadius: 6,
                offset: Offset(0, 2))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        shape: BoxShape.circle),
                    child: Icon(icon,
                        size: isMobile ? 20 : 24, color: color),
                  ),
                  Text(
                    'Rs ${value.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: isMobile ? 14 : 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(title,
                  style: TextStyle(
                      fontSize: isMobile ? 12 : 14,
                      color: Colors.grey[600])),
              const SizedBox(height: 4),
              Container(
                height: 4,
                width: double.infinity,
                decoration: BoxDecoration(
                    color: color.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2)),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value > 10000
                      ? 1.0
                      : (value < 0 ? 0.0 : value / 10000),
                  child: Container(
                      decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemsWiseTable(LanguageProvider languageProvider) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Consumer<ItemsWiseLedgerProvider>(
      builder: (context, provider, child) {
        final transactions = provider.transactions ?? [];

        if (transactions.isEmpty && provider.isFiltered) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                languageProvider.isEnglish
                    ? 'No items found in the selected date range'
                    : 'منتخب کردہ تاریخ کی حد میں کوئی آئٹم نہیں ملا',
                style:
                TextStyle(color: Colors.grey[600], fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCustomItemsWiseTable(
                transactions, provider, isMobile, languageProvider),
          ],
        );
      },
    );
  }

  Widget _buildCustomItemsWiseTable(
      List<Map<String, dynamic>> transactions,
      ItemsWiseLedgerProvider provider,
      bool isMobile,
      LanguageProvider languageProvider,
      ) {
    final displayBalance = provider.displayOpeningBalance;
    List<Map<String, dynamic>> sortedTransactions =
    List.from(transactions);
    sortedTransactions.sort((a, b) {
      final dateA =
          DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(2000);
      final dateB =
          DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(2000);
      return dateA.compareTo(dateB);
    });

    DateTime? openingBalanceDate = provider.displayOpeningBalanceDate;
    bool openingBalanceInserted = false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Table Header (matches customer ledger columns) ──
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3).withOpacity(0.2),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              _buildExpandedHeaderCell(
                  languageProvider.isEnglish ? 'Date' : 'ڈیٹ', 1),
              _buildExpandedHeaderCell(
                  languageProvider.isEnglish
                      ? 'Invoice No.'
                      : 'انوائس نمبر',
                  1),
              _buildExpandedHeaderCell(
                  languageProvider.isEnglish
                      ? 'Item Name'
                      : 'آئٹم کا نام',
                  2),
              _buildExpandedHeaderCell(
                  languageProvider.isEnglish ? 'Type' : 'قسم', 1),
              _buildExpandedHeaderCell(
                  languageProvider.isEnglish ? 'Qty' : 'مقدار', 0.8),
              _buildExpandedHeaderCell(
                  languageProvider.isEnglish
                      ? 'Unit Price'
                      : 'یونٹ قیمت',
                  1.2),
              _buildExpandedHeaderCell(
                  languageProvider.isEnglish
                      ? 'Payment Method'
                      : 'ادائیگی کا طریقہ',
                  1.5),
              _buildExpandedHeaderCell(
                  languageProvider.isEnglish ? 'Bank' : 'بینک', 2),
              _buildExpandedHeaderCell(
                  languageProvider.isEnglish ? 'Debit' : 'ڈیبٹ', 1),
              _buildExpandedHeaderCell(
                  languageProvider.isEnglish ? 'Credit' : 'کریڈٹ', 1),
              _buildExpandedHeaderCell(
                  languageProvider.isEnglish ? 'Balance' : 'بیلنس', 1),
            ],
          ),
        ),

        // ── Rows ──
        ...(() {
          List<Widget> rows = [];

          for (int i = 0; i < sortedTransactions.length; i++) {
            final transaction = sortedTransactions[i];
            final transactionDate =
                DateTime.tryParse(transaction['date']?.toString() ?? '') ??
                    DateTime(2000);

            if (!openingBalanceInserted &&
                (displayBalance != 0 || !provider.isFiltered) &&
                openingBalanceDate != null &&
                openingBalanceDate.isBefore(transactionDate)) {
              rows.add(_buildOpeningBalanceRow(
                  provider, languageProvider, isMobile));
              openingBalanceInserted = true;
            }

            rows.add(_buildExpandedItemRow(
                transaction, provider, isMobile, languageProvider));
          }

          if (!openingBalanceInserted &&
              (displayBalance != 0 || !provider.isFiltered)) {
            if (sortedTransactions.isEmpty) {
              rows.insert(
                  0,
                  _buildOpeningBalanceRow(
                      provider, languageProvider, isMobile));
            } else {
              rows.add(_buildOpeningBalanceRow(
                  provider, languageProvider, isMobile));
            }
          }

          return rows;
        })(),
      ],
    );
  }

  Widget _buildOpeningBalanceRow(
      ItemsWiseLedgerProvider provider,
      LanguageProvider languageProvider,
      bool isMobile,
      ) {
    final displayBalance = provider.displayOpeningBalance;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
          left: BorderSide(color: Colors.grey[300]!),
          right: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Row(
        children: [
          _buildExpandedDataCell(
            provider.displayOpeningBalanceDate != null
                ? DateFormat('dd MMM yyyy')
                .format(provider.displayOpeningBalanceDate!)
                : '-',
            1,
            isMobile,
          ),
          _buildExpandedDataCell('-', 1, isMobile),   // Invoice No
          _buildExpandedDataCell(
            languageProvider.isEnglish
                ? provider.openingBalanceLabel
                : (provider.isFiltered
                ? 'پچھلا بیلنس'
                : 'ابتدائی بیلنس'),
            2,
            isMobile,
          ),
          _buildExpandedDataCell('-', 1, isMobile),   // Type
          _buildExpandedDataCell('-', 0.8, isMobile), // Qty
          _buildExpandedDataCell('-', 1.2, isMobile), // Unit Price
          _buildExpandedDataCell('-', 1.5, isMobile), // Payment Method
          _buildExpandedDataCell('-', 2, isMobile),   // Bank
          _buildExpandedDataCell('-', 1, isMobile),   // Debit
          _buildExpandedDataCell(
            'Rs ${displayBalance.toStringAsFixed(2)}',
            1,
            isMobile,
            fontWeight: FontWeight.bold,
            textColor: displayBalance > 0 ? Colors.green : Colors.red,
          ),
          _buildExpandedDataCell(
            'Rs ${displayBalance.toStringAsFixed(2)}',
            1,
            isMobile,
            fontWeight: FontWeight.bold,
            textColor: displayBalance > 0 ? Colors.green : Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedHeaderCell(String text, double flexValue) {
    return Expanded(
      flex: (flexValue * 10).round(),
      child: Container(
        padding:
        const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
            border:
            Border(right: BorderSide(color: Colors.grey[300]!))),
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1976D2),
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildExpandedItemRow(
      Map<String, dynamic> transaction,
      ItemsWiseLedgerProvider provider,
      bool isMobile,
      LanguageProvider languageProvider,
      ) {
    final isItem = transaction['isItem'] == true;
    final bankName = _getBankName(transaction);
    final bankLogoPath = _getBankLogoPath(bankName);

    final date =
        DateTime.tryParse(transaction['date']?.toString() ?? '') ??
            DateTime(2000);
    final invoiceNumber =
        transaction['invoiceNumber']?.toString() ?? '-';
    final itemName = transaction['itemName']?.toString() ??
        transaction['details']?.toString() ??
        '-';
    final quantity =
    isItem ? (transaction['quantity'] ?? 0).toStringAsFixed(2) : '-';
    final unitPrice = isItem
        ? 'Rs ${(transaction['unitPrice'] ?? 0).toStringAsFixed(2)}'
        : '-';
    final paymentMethod =
        transaction['paymentMethod']?.toString() ?? '-';
    final debit = transaction['debit']?.toStringAsFixed(2) ?? '0.00';
    final credit = transaction['credit']?.toStringAsFixed(2) ?? '0.00';
    final balance =
        transaction['balance']?.toStringAsFixed(2) ?? '0.00';

    return Container(
      decoration: BoxDecoration(
        color: isItem ? Colors.white : const Color(0xFFF5F5F5),
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
          left: BorderSide(color: Colors.grey[300]!),
          right: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Row(
        children: [
          _buildExpandedDataCell(
              DateFormat('dd MMM yyyy').format(date), 1, isMobile),
          _buildExpandedDataCell(
            invoiceNumber,
            1,
            isMobile,
            textColor: Colors.blue[700],
            fontWeight: FontWeight.w500,
          ),
          _buildExpandedDataCell(itemName, 2, isMobile),
          _buildExpandedDataCell(
            isItem
                ? (languageProvider.isEnglish ? 'Item' : 'آئٹم')
                : (languageProvider.isEnglish ? 'Payment' : 'ادائیگی'),
            1,
            isMobile,
          ),
          _buildExpandedDataCell(quantity, 0.8, isMobile),
          _buildExpandedDataCell(unitPrice, 1.2, isMobile,
              textAlign: TextAlign.right),
          _buildExpandedDataCell(
            _getPaymentMethodText(paymentMethod, languageProvider),
            1.5,
            isMobile,
          ),
          // Bank cell with logo
          _buildExpandedDataCell(
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (bankLogoPath != null) ...[
                  Image.asset(bankLogoPath, width: 24, height: 24),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    bankName ?? '-',
                    style: TextStyle(
                        fontSize: isMobile ? 10 : 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            2,
            isMobile,
          ),
          _buildExpandedDataCell(
            (transaction['debit'] ?? 0) > 0 ? 'Rs $debit' : '-',
            1,
            isMobile,
            textColor: (transaction['debit'] ?? 0) > 0
                ? Colors.red
                : Colors.grey,
            textAlign: TextAlign.right,
          ),
          _buildExpandedDataCell(
            (transaction['credit'] ?? 0) > 0 ? 'Rs $credit' : '-',
            1,
            isMobile,
            textColor: (transaction['credit'] ?? 0) > 0
                ? Colors.green
                : Colors.grey,
            textAlign: TextAlign.right,
          ),
          _buildExpandedDataCell(
            'Rs $balance',
            1,
            isMobile,
            fontWeight: FontWeight.bold,
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedDataCell(
      dynamic content,
      double flexValue,
      bool isMobile, {
        Color? textColor,
        FontWeight? fontWeight,
        TextAlign textAlign = TextAlign.center,
      }) {
    return Expanded(
      flex: (flexValue * 10).round(),
      child: Container(
        padding:
        const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
            border:
            Border(right: BorderSide(color: Colors.grey[300]!))),
        child: content is Widget
            ? Center(child: content)
            : Text(
          content.toString(),
          style: TextStyle(
            fontSize: isMobile ? 10 : 12,
            color: textColor ?? Colors.black87,
            fontWeight: fontWeight,
          ),
          textAlign: textAlign,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  String _getPaymentMethodText(
      String? method, LanguageProvider languageProvider) {
    if (method == null) return '-';
    switch (method.toLowerCase()) {
      case 'cash':
        return languageProvider.isEnglish ? 'Cash' : 'نقد';
      case 'online':
        return languageProvider.isEnglish ? 'Online' : 'آن لائن';
      case 'check':
      case 'cheque':
        return languageProvider.isEnglish ? 'Cheque' : 'چیک';
      case 'bank':
        return languageProvider.isEnglish ? 'Bank Transfer' : 'بینک ٹرانسفر';
      case 'slip':
        return languageProvider.isEnglish ? 'Slip' : 'پرچی';
      case 'udhaar':
        return languageProvider.isEnglish ? 'Udhaar' : 'ادھار';
      default:
        return method;
    }
  }
}