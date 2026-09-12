// mazdoorItemsWiseLedgerPage.dart
//
// Items-wise Mazdoor ledger report. Same visual design as
// ItemsWiseLedgerReportPage (customer version), but each "item row" is
// either a wire line given out (debit-side) or a bolt-return line
// (credit-side), plus interleaved non-item rows (cash payments,
// opening balance) so the running balance stays readable.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;

import '../Provider/lanprovider.dart';
import '../Provider/mazdoorreportprovider.dart';

class MazdoorItemsWiseLedgerPage extends StatefulWidget {
  final String mazdoorId;
  final String mazdoorName;
  final String mazdoorPhone;
  final String mazdoorAddress;
  final String mazdoorCity;

  const MazdoorItemsWiseLedgerPage({
    Key? key,
    required this.mazdoorId,
    required this.mazdoorName,
    this.mazdoorPhone = '',
    this.mazdoorAddress = '',
    this.mazdoorCity = '',
  }) : super(key: key);

  @override
  State<MazdoorItemsWiseLedgerPage> createState() =>
      _MazdoorItemsWiseLedgerPageState();
}

class _MazdoorItemsWiseLedgerPageState
    extends State<MazdoorItemsWiseLedgerPage> {
  DateTimeRange? selectedDateRange;

  String _kindLabel(String? kind, LanguageProvider lp) {
    switch (kind) {
      case 'wire_given':
        return lp.isEnglish ? 'Wire Given' : 'وائر';
      case 'bolt_return':
        return lp.isEnglish ? 'Bolts' : 'بولٹس';
      case 'cash_payment':
        return lp.isEnglish ? 'Cash Payment' : 'نقد ادائیگی';
      default:
        return lp.isEnglish ? 'Adjustment' : 'ایڈجسٹمنٹ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    return ChangeNotifierProvider(
      create: (_) => MazdoorLedgerReportProvider(widget.mazdoorId)
        ..fetchMazdoorReport(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            languageProvider.isEnglish ? 'Mazdoor Items Wise Ledger' : 'مزدور آئٹم وار کھاتہ',
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
            Consumer<MazdoorLedgerReportProvider>(
              builder: (context, provider, child) {
                return IconButton(
                  icon: const Icon(Icons.print),
                  onPressed: () => _generateAndPrintPDF(provider, languageProvider),
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
          child: Consumer<MazdoorLedgerReportProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading) {
                return Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(const Color(0xFF2196F3)),
                  ),
                );
              }
              if (provider.error.isNotEmpty) {
                return Center(child: Text(provider.error));
              }

              final rows = provider.itemWiseRows;
              final totalItems = rows.where((r) => r['isItem'] == true).length;
              final totalPayments = rows.where((r) => r['isItem'] == false && (r['debit'] as double) == 0 && (r['credit'] as double) > 0).length;

              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMazdoorInfo(context, languageProvider, provider),
                      _buildDateRangeSelector(languageProvider),
                      _buildSummaryCards(provider),
                      Text(
                        'No. of Entries: ${rows.length + (provider.openingBalance != 0 ? 1 : 0)} (Filtered)',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF1976D2),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total Items: $totalItems | Total Payments: $totalPayments',
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
      MazdoorLedgerReportProvider provider, LanguageProvider languageProvider) async {
    try {
      final pdf = pw.Document();

      Uint8List? logoBytes;
      try {
        final ByteData bytes = await rootBundle.load('assets/images/logo.png');
        logoBytes = bytes.buffer.asUint8List();
      } catch (_) {}

      final itemsTableWidget = _buildPDFItemsWiseTable(provider, languageProvider);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 20),
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  children: [
                    if (logoBytes != null)
                      pw.Image(pw.MemoryImage(logoBytes), width: 150, height: 100),
                    pw.Spacer(),
                    pw.Text(
                      'Mazdoor Items Wise Statement',
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
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
                        pw.Text('Mazdoor: ${widget.mazdoorName}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        if (widget.mazdoorPhone.isNotEmpty) pw.Text('Phone: ${widget.mazdoorPhone}'),
                        if (widget.mazdoorAddress.isNotEmpty) pw.Text('Address: ${widget.mazdoorAddress}'),
                        if (widget.mazdoorCity.isNotEmpty) pw.Text('City: ${widget.mazdoorCity}'),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                            'Date Range: ${provider.isFiltered && provider.dateRangeFilter != null ? '${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.start)} - ${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.end)}' : 'All Transactions'}'),
                        pw.Text('Generated: ${DateFormat('dd MMM yyyy hh:mm a').format(DateTime.now())}'),
                      ],
                    ),
                  ),
                ],
              ),
              pw.Header(level: 1, child: pw.Text('Items Wise Transaction Details')),
              itemsTableWidget,
            ];
          },
        ),
      );

      await _printPDF(pdf);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e'), backgroundColor: Colors.red),
      );
    }
  }

  pw.Widget _buildPDFItemsWiseTable(
      MazdoorLedgerReportProvider provider, LanguageProvider languageProvider) {
    final openingBalanceDisplay = provider.displayOpeningBalance;
    final rows = provider.itemWiseRows;

    final report = provider.report;
    final totalDebit = report['debit'] ?? 0.0;
    final totalCredit = openingBalanceDisplay + (report['credit'] ?? 0.0);
    final finalBalance = report['balance'] ?? 0.0;
    final displayFinalBalance =
    provider.isFiltered && rows.isEmpty ? openingBalanceDisplay : finalBalance;

    List<pw.Widget> pdfRows = [];

    pdfRows.add(
      pw.Container(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Date' : 'ڈیٹ', 55),
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Job No.' : 'کام نمبر', 50),
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Item Name' : 'آئٹم کا نام', 110),
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Type' : 'قسم', 55),
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Qty' : 'مقدار', 35),
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Unit Price' : 'یونٹ قیمت', 50),
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Debit' : 'ڈیبٹ', 50),
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Credit' : 'کریڈٹ', 50),
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Balance' : 'بیلنس', 55),
          ],
        ),
      ),
    );

    bool openingBalanceAdded = false;
    final openingBalanceDate = provider.displayOpeningBalanceDate;

    if ((openingBalanceDisplay != 0 || !provider.isFiltered) && openingBalanceDate != null) {
      if (rows.isEmpty || openingBalanceDate.isBefore(rows.first['date'] as DateTime)) {
        pdfRows.add(_buildOpeningBalancePdfRow(provider, languageProvider, openingBalanceDisplay));
        openingBalanceAdded = true;
      }
    }

    for (var r in rows) {
      final date = r['date'] as DateTime;

      if (!openingBalanceAdded &&
          openingBalanceDate != null &&
          openingBalanceDate.isBefore(date) &&
          (openingBalanceDisplay != 0 || !provider.isFiltered)) {
        pdfRows.add(_buildOpeningBalancePdfRow(provider, languageProvider, openingBalanceDisplay));
        openingBalanceAdded = true;
      }

      final isItem = r['isItem'] == true;
      final itemName = r['itemName']?.toString() ?? '-';
      final kind = _kindLabel(r['itemKind']?.toString(), languageProvider);
      final quantity = isItem ? (r['quantity'] as double? ?? 0.0).toStringAsFixed(2) : '-';
      final unitPrice = isItem && (r['unitPrice'] as double? ?? 0.0) > 0
          ? 'Rs ${(r['unitPrice'] as double).toStringAsFixed(2)}'
          : '-';
      final debit = (r['debit'] as double?) ?? 0.0;
      final credit = (r['credit'] as double?) ?? 0.0;
      final balance = (r['balance'] as double?) ?? 0.0;

      pdfRows.add(
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildPdfDataCell(DateFormat('dd MMM yyyy').format(date), 55),
              _buildPdfDataCell(r['invoiceNumber']?.toString() ?? '-', 50,
                  textColor: PdfColors.blue800, fontWeight: pw.FontWeight.bold),
              _buildPdfDataCell(itemName, 110),
              _buildPdfDataCell(kind, 55),
              _buildPdfDataCell(quantity, 35),
              _buildPdfDataCell(unitPrice, 50, textAlign: pw.TextAlign.right),
              _buildPdfDataCell(
                debit > 0 ? 'Rs ${debit.toStringAsFixed(2)}' : '-',
                50,
                textColor: debit > 0 ? PdfColors.orange800 : PdfColors.black,
                textAlign: pw.TextAlign.right,
              ),
              _buildPdfDataCell(
                credit > 0 ? 'Rs ${credit.toStringAsFixed(2)}' : '-',
                50,
                textColor: credit > 0 ? PdfColors.green800 : PdfColors.black,
                textAlign: pw.TextAlign.right,
              ),
              _buildPdfDataCell(
                'Rs ${balance.toStringAsFixed(2)}',
                55,
                fontWeight: pw.FontWeight.bold,
                textColor: PdfColors.teal800,
                textAlign: pw.TextAlign.right,
              ),
            ],
          ),
        ),
      );
    }

    if (!openingBalanceAdded &&
        (openingBalanceDisplay != 0 || !provider.isFiltered) &&
        openingBalanceDate != null) {
      pdfRows.add(_buildOpeningBalancePdfRow(provider, languageProvider, openingBalanceDisplay));
    }

    pdfRows.add(
      pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: PdfColors.blue, width: 1.5)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _buildPdfDataCell(languageProvider.isEnglish ? 'TOTALS' : 'کل', 55,
                fontWeight: pw.FontWeight.bold),
            _buildPdfDataCell('', 50),
            _buildPdfDataCell('', 110),
            _buildPdfDataCell('', 55),
            _buildPdfDataCell('', 35),
            _buildPdfDataCell('', 50),
            _buildPdfDataCell(
              'Rs ${totalDebit.toStringAsFixed(2)}',
              50,
              fontWeight: pw.FontWeight.bold,
              textColor: PdfColors.orange800,
              textAlign: pw.TextAlign.right,
            ),
            _buildPdfDataCell(
              'Rs ${totalCredit.toStringAsFixed(2)}',
              50,
              fontWeight: pw.FontWeight.bold,
              textColor: PdfColors.green800,
              textAlign: pw.TextAlign.right,
            ),
            _buildPdfDataCell(
              'Rs ${displayFinalBalance.toStringAsFixed(2)}',
              55,
              fontWeight: pw.FontWeight.bold,
              textColor: displayFinalBalance >= 0 ? PdfColors.green : PdfColors.red,
              textAlign: pw.TextAlign.right,
            ),
          ],
        ),
      ),
    );

    return pw.Column(children: pdfRows);
  }

  pw.Widget _buildOpeningBalancePdfRow(
      MazdoorLedgerReportProvider provider, LanguageProvider languageProvider, double displayValue) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _buildPdfDataCell(
            provider.displayOpeningBalanceDate != null
                ? DateFormat('dd MMM yyyy').format(provider.displayOpeningBalanceDate!)
                : '-',
            55,
          ),
          _buildPdfDataCell('-', 50),
          _buildPdfDataCell(
            languageProvider.isEnglish
                ? provider.openingBalanceLabel
                : (provider.isFiltered ? 'پچھلا بیلنس' : 'ابتدائی بیلنس'),
            110,
          ),
          _buildPdfDataCell('-', 55),
          _buildPdfDataCell('-', 35),
          _buildPdfDataCell('-', 50),
          _buildPdfDataCell('-', 50),
          _buildPdfDataCell(
            'Rs ${displayValue.toStringAsFixed(2)}',
            50,
            textColor: displayValue >= 0 ? PdfColors.green : PdfColors.red,
            fontWeight: pw.FontWeight.bold,
            textAlign: pw.TextAlign.right,
          ),
          _buildPdfDataCell(
            'Rs ${displayValue.toStringAsFixed(2)}',
            55,
            textColor: displayValue >= 0 ? PdfColors.green : PdfColors.red,
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
        border: pw.Border(right: pw.BorderSide(color: PdfColors.grey300)),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.blue800, fontSize: 9),
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
        border: pw.Border(right: pw.BorderSide(color: PdfColors.grey300)),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8, color: textColor ?? PdfColors.black, fontWeight: fontWeight),
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
          ..download = 'mazdoor_items_wise_${widget.mazdoorName}_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf';
        html.document.body?.children.add(anchor);
        anchor.click();
        html.document.body?.children.remove(anchor);
        html.Url.revokeObjectUrl(url);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF downloaded successfully!'), backgroundColor: Colors.green),
        );
      } else {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdf.save(),
          name: 'mazdoor_items_wise_${widget.mazdoorName}_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf',
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error printing PDF: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────────

  Widget _buildMazdoorInfo(
      BuildContext context, LanguageProvider languageProvider, MazdoorLedgerReportProvider provider) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Center(
      child: Column(
        children: [
          Text(
            widget.mazdoorName,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: isMobile ? 20 : 24,
              color: const Color(0xFF1976D2),
            ),
          ),
          if (widget.mazdoorPhone.isNotEmpty)
            Text('${languageProvider.isEnglish ? 'Phone Number:' : 'فون نمبر:'} ${widget.mazdoorPhone}',
                style: const TextStyle(color: Color(0xFF2196F3))),
          if (widget.mazdoorAddress.isNotEmpty)
            Text('${languageProvider.isEnglish ? 'Address:' : 'پتہ:'} ${widget.mazdoorAddress}',
                style: const TextStyle(color: Color(0xFF2196F3))),
          if (widget.mazdoorCity.isNotEmpty)
            Text('${languageProvider.isEnglish ? 'City:' : 'شہر:'} ${widget.mazdoorCity}',
                style: const TextStyle(color: Color(0xFF2196F3))),
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
    return Consumer<MazdoorLedgerReportProvider>(
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
              label: Text(languageProvider.isEnglish ? 'Select Date Range' : 'تاریخ منتخب کریں'),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF2196F3),
              ),
            ),
            if (provider.isFiltered)
              TextButton(
                onPressed: () => provider.setDateRangeFilter(null),
                child: Text(
                  languageProvider.isEnglish ? 'Clear Filter' : 'فلٹر صاف کریں',
                  style: const TextStyle(color: Color(0xFF2196F3)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCards(MazdoorLedgerReportProvider provider) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final report = provider.report;
    final debit = report['debit'] ?? 0.0;
    final credit = report['credit'] ?? 0.0;
    final balance = report['balance'] ?? 0.0;
    final displayBalance =
    provider.isFiltered && provider.itemWiseRows.isEmpty ? provider.displayOpeningBalance : balance;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildModernSummaryCard(
            title: 'Wire Given (Debit)',
            value: debit,
            icon: Icons.outbond,
            color: const Color(0xFFE57373),
            isMobile: isMobile,
          ),
          _buildModernSummaryCard(
            title: 'Returned (Credit)',
            value: credit,
            icon: Icons.call_received,
            color: const Color(0xFF81C784),
            isMobile: isMobile,
          ),
          _buildModernSummaryCard(
            title: displayBalance >= 0 ? 'Owes You' : 'You Owe',
            value: displayBalance.abs(),
            icon: Icons.account_balance_wallet,
            color: displayBalance >= 0 ? const Color(0xFF64B5F6) : const Color(0xFFFFB74D),
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
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
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
                    decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
                    child: Icon(icon, size: isMobile ? 20 : 24, color: color),
                  ),
                  Text(
                    'Rs ${value.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: isMobile ? 14 : 18, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(title, style: TextStyle(fontSize: isMobile ? 12 : 14, color: Colors.grey[600])),
              const SizedBox(height: 4),
              Container(
                height: 4,
                width: double.infinity,
                decoration:
                BoxDecoration(color: color.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value > 10000 ? 1.0 : (value < 0 ? 0.0 : value / 10000),
                  child: Container(
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                  ),
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

    return Consumer<MazdoorLedgerReportProvider>(
      builder: (context, provider, child) {
        final rows = provider.itemWiseRows;

        if (rows.isEmpty && provider.isFiltered) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                languageProvider.isEnglish
                    ? 'No items found in the selected date range'
                    : 'منتخب کردہ تاریخ کی حد میں کوئی آئٹم نہیں ملا',
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCustomItemsWiseTable(rows, provider, isMobile, languageProvider),
          ],
        );
      },
    );
  }

  Widget _buildCustomItemsWiseTable(
      List<Map<String, dynamic>> rows,
      MazdoorLedgerReportProvider provider,
      bool isMobile,
      LanguageProvider languageProvider,
      ) {
    final displayBalance = provider.displayOpeningBalance;
    DateTime? openingBalanceDate = provider.displayOpeningBalanceDate;
    bool openingBalanceInserted = false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3).withOpacity(0.2),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Date' : 'ڈیٹ', 1),
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Job No.' : 'کام نمبر', 1),
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Item Name' : 'آئٹم کا نام', 2),
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Type' : 'قسم', 1),
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Qty' : 'مقدار', 0.8),
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Unit Price' : 'یونٹ قیمت', 1.2),
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Debit' : 'ڈیبٹ', 1),
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Credit' : 'کریڈٹ', 1),
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Balance' : 'بیلنس', 1),
            ],
          ),
        ),
        ...(() {
          List<Widget> widgetRows = [];

          for (int i = 0; i < rows.length; i++) {
            final r = rows[i];
            final date = r['date'] as DateTime;

            if (!openingBalanceInserted &&
                (displayBalance != 0 || !provider.isFiltered) &&
                openingBalanceDate != null &&
                openingBalanceDate.isBefore(date)) {
              widgetRows.add(_buildOpeningBalanceRow(provider, languageProvider, isMobile));
              openingBalanceInserted = true;
            }

            widgetRows.add(_buildExpandedItemRow(r, isMobile, languageProvider));
          }

          if (!openingBalanceInserted && (displayBalance != 0 || !provider.isFiltered)) {
            if (rows.isEmpty) {
              widgetRows.insert(0, _buildOpeningBalanceRow(provider, languageProvider, isMobile));
            } else {
              widgetRows.add(_buildOpeningBalanceRow(provider, languageProvider, isMobile));
            }
          }

          return widgetRows;
        })(),
      ],
    );
  }

  Widget _buildOpeningBalanceRow(
      MazdoorLedgerReportProvider provider, LanguageProvider languageProvider, bool isMobile) {
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
                ? DateFormat('dd MMM yyyy').format(provider.displayOpeningBalanceDate!)
                : '-',
            1,
            isMobile,
          ),
          _buildExpandedDataCell('-', 1, isMobile),
          _buildExpandedDataCell(
            languageProvider.isEnglish
                ? provider.openingBalanceLabel
                : (provider.isFiltered ? 'پچھلا بیلنس' : 'ابتدائی بیلنس'),
            2,
            isMobile,
          ),
          _buildExpandedDataCell('-', 1, isMobile),
          _buildExpandedDataCell('-', 0.8, isMobile),
          _buildExpandedDataCell('-', 1.2, isMobile),
          _buildExpandedDataCell('-', 1, isMobile),
          _buildExpandedDataCell(
            'Rs ${displayBalance.toStringAsFixed(2)}',
            1,
            isMobile,
            fontWeight: FontWeight.bold,
            textColor: displayBalance >= 0 ? Colors.green : Colors.red,
          ),
          _buildExpandedDataCell(
            'Rs ${displayBalance.toStringAsFixed(2)}',
            1,
            isMobile,
            fontWeight: FontWeight.bold,
            textColor: displayBalance >= 0 ? Colors.green : Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedHeaderCell(String text, double flexValue) {
    return Expanded(
      flex: (flexValue * 10).round(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey[300]!))),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1976D2), fontSize: 12),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildExpandedItemRow(
      Map<String, dynamic> r,
      bool isMobile,
      LanguageProvider languageProvider,
      ) {
    final isItem = r['isItem'] == true;
    final date = r['date'] as DateTime;
    final invoiceNumber = r['invoiceNumber']?.toString() ?? '-';
    final itemName = r['itemName']?.toString() ?? '-';
    final quantity = isItem ? (r['quantity'] as double? ?? 0.0).toStringAsFixed(2) : '-';
    final unitPrice = isItem && (r['unitPrice'] as double? ?? 0.0) > 0
        ? 'Rs ${(r['unitPrice'] as double).toStringAsFixed(2)}'
        : '-';
    final debit = (r['debit'] as double?) ?? 0.0;
    final credit = (r['credit'] as double?) ?? 0.0;
    final balance = (r['balance'] as double?) ?? 0.0;

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
          _buildExpandedDataCell(DateFormat('dd MMM yyyy').format(date), 1, isMobile),
          _buildExpandedDataCell(
            invoiceNumber,
            1,
            isMobile,
            textColor: Colors.blue[700],
            fontWeight: FontWeight.w500,
          ),
          _buildExpandedDataCell(itemName, 2, isMobile),
          _buildExpandedDataCell(_kindLabel(r['itemKind']?.toString(), languageProvider), 1, isMobile),
          _buildExpandedDataCell(quantity, 0.8, isMobile),
          _buildExpandedDataCell(unitPrice, 1.2, isMobile, textAlign: TextAlign.right),
          _buildExpandedDataCell(
            debit > 0 ? 'Rs ${debit.toStringAsFixed(2)}' : '-',
            1,
            isMobile,
            textColor: debit > 0 ? Colors.orange[800] : Colors.grey,
            textAlign: TextAlign.right,
          ),
          _buildExpandedDataCell(
            credit > 0 ? 'Rs ${credit.toStringAsFixed(2)}' : '-',
            1,
            isMobile,
            textColor: credit > 0 ? Colors.green : Colors.grey,
            textAlign: TextAlign.right,
          ),
          _buildExpandedDataCell(
            'Rs ${balance.toStringAsFixed(2)}',
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
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey[300]!))),
        child: content is Widget
            ? Center(child: content)
            : Text(
          content.toString(),
          style: TextStyle(fontSize: isMobile ? 10 : 12, color: textColor ?? Colors.black87, fontWeight: fontWeight),
          textAlign: textAlign,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}