import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../Provider/filledreportprovider.dart';
import '../Provider/lanprovider.dart';
import '../bankmanagement/banknames.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;

class FilledLedgerReportPage extends StatefulWidget {
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final String customerCity;

  const FilledLedgerReportPage({
    Key? key,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.customerCity
  }) : super(key: key);

  @override
  State<FilledLedgerReportPage> createState() => _FilledLedgerReportPageState();
}

class _FilledLedgerReportPageState extends State<FilledLedgerReportPage> {
  DateTimeRange? selectedDateRange;
  static final Map<String, String> _bankIconMap = _createBankIconMap();

  static Map<String, String> _createBankIconMap() {
    return {
      for (var bank in pakistaniBanks)
        bank.name.toLowerCase(): bank.iconPath
    };
  }

  String? _getBankName(Map<String, dynamic> transaction) {
    if (transaction['bankName'] != null && transaction['bankName'].toString().isNotEmpty) {
      return transaction['bankName'].toString();
    }

    String paymentMethod = transaction['paymentMethod']?.toString().toLowerCase() ?? '';
    if (paymentMethod == 'cheque' || paymentMethod == 'check') {
      if (transaction['chequeBankName'] != null && transaction['chequeBankName'].toString().isNotEmpty) {
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

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    return ChangeNotifierProvider(
      create: (_) => FilledCustomerReportProvider()..fetchCustomerReport(widget.customerId),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            languageProvider.isEnglish ? 'Customer Ledger' : 'کسٹمر لیجر',
            style: const TextStyle(color: Colors.white),
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
          actions: [
            Consumer<FilledCustomerReportProvider>(
              builder: (context, provider, child) {
                return IconButton(
                  icon: Icon(Icons.print),
                  onPressed: () => _generateAndPrintPDF(provider, languageProvider),
                );
              },
            ),
          ],
        ),
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
          child: Consumer<FilledCustomerReportProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading) {
                return Center(child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Color(0xFFFF8A65)),
                ));
              }
              if (provider.error.isNotEmpty) {
                return Center(child: Text(provider.error));
              }

              final transactions = provider.transactions;

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
                          color: Color(0xFFE65100), // Dark orange
                          fontSize: 12,
                        ),
                      ),
                      _buildTransactionTable(languageProvider),
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

  Future<void> _generateAndPrintPDF(FilledCustomerReportProvider provider, LanguageProvider languageProvider) async {
    try {
      final pdf = pw.Document();
      final openingBalance = provider.openingBalance ?? 0;
      final transactions = provider.transactions ?? [];

      // ✅ Load images
      final ByteData bytes = await rootBundle.load('assets/images/logo.png');
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

      // ✅ Build transaction table BEFORE pdf.addPage (since it's async)
      final transactionTableWidget = await _buildPDFTransactionTable(provider, languageProvider);

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
                    pw.Image(image, width: 200, height: 150),
                    pw.Spacer(),
                    pw.Text(
                      'Party Statement',
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
                        pw.Text('Customer: ${widget.customerName}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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
                        pw.Text('Date Range: ${provider.isFiltered && provider.dateRangeFilter != null
                            ? '${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.start)} - ${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.end)}'
                            : 'All Transactions'}'),
                        pw.Text('Generated: ${DateFormat('dd MMM yyyy hh:mm a').format(DateTime.now())}'),
                      ],
                    ),
                  ),
                ],
              ),
              pw.Header(
                level: 1,
                child: pw.Text('Transaction Details'),
              ),
              // ✅ Use the pre-built widget here (no await needed)
              transactionTableWidget,
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


  pw.Widget _buildPdfTableCell(String text, {bool isHeader = false, bool isBold = false, PdfColor? textColor}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: (isHeader || isBold) ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: textColor,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }


  Future<pw.Widget> _buildPDFTransactionTable(
      FilledCustomerReportProvider provider,
      LanguageProvider languageProvider,
      )
  async {
    final openingBalanceDisplay = provider.displayOpeningBalance;
    final transactions = provider.transactions ?? [];
    final DateTime? openingBalanceDate = provider.displayOpeningBalanceDate;

    double totalDebit = provider.report['debit']?.toDouble() ?? 0.0;
    double totalCredit = openingBalanceDisplay + (provider.report['credit']?.toDouble() ?? 0.0);
    double finalBalance = provider.report['balance']?.toDouble() ?? 0.0;

    final displayFinalBalance = provider.isFiltered && provider.transactions.isEmpty ? 0.0 : finalBalance;

    // ── Pre-render item names and lengths as images (handles ½ ¼ ¾ etc.) ──
    final Map<String, Uint8List> itemNameImages = {};
    final Map<String, Uint8List> lengthImages = {};

    for (var transaction in transactions) {
      final transactionKey = transaction['key']?.toString() ?? '';
      final isInvoice = (transaction['credit'] ?? 0) != 0;
      final isExpanded = provider.expandedTransactions.contains(transactionKey);

      if (isInvoice && isExpanded) {
        final invoiceItems = provider.invoiceItems[transactionKey] ?? [];
        for (var item in invoiceItems) {
          final name = item['itemName']?.toString() ?? '-';
          if (!itemNameImages.containsKey(name)) {
            itemNameImages[name] = await _renderTextAsImageForPdf(
              name, fontSize: 9, width: 150, height: 22,
            );
          }
          final length = item['length']?.toString() ?? '';
          if (length.isNotEmpty && !lengthImages.containsKey(length)) {
            lengthImages[length] = await _renderTextAsImageForPdf(
              length, fontSize: 9, width: 80, height: 22,
            );
          }
        }
      }
    }

    List<pw.Widget> rows = [];

    // ── Table header ──
    rows.add(
      pw.Container(
        decoration: pw.BoxDecoration(color: PdfColors.grey200),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Date' : 'ڈیٹ', 60),
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Invoice No' : 'انوائس نمبر', 40),
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Ref No' : 'ریف نمبر', 40),
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Details' : 'تفصیلات', 80),
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Type' : 'قسم', 50),
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Payment Method' : 'ادائیگی کا طریقہ', 60),
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Bank' : 'بینک', 70),
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Debit' : 'ڈیبٹ', 50),
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Credit' : 'کریڈٹ', 50),
            _buildPdfHeaderCell(languageProvider.isEnglish ? 'Balance' : 'بیلنس', 60),
          ],
        ),
      ),
    );

    // ── Sort transactions by date ──
    List<Map<String, dynamic>> sortedTransactions = List.from(transactions);
    sortedTransactions.sort((a, b) {
      final dateA = DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(2000);
      final dateB = DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(2000);
      return dateA.compareTo(dateB);
    });

    bool openingBalanceAdded = false;

    // ── Opening balance (chronological position) ──
    if ((openingBalanceDisplay != 0 || !provider.isFiltered) && openingBalanceDate != null) {
      if (sortedTransactions.isEmpty ||
          openingBalanceDate.isBefore(
              DateTime.tryParse(sortedTransactions.first['date']?.toString() ?? '') ?? DateTime(2000))) {
        rows.add(_buildOpeningBalancePdfRow(provider, languageProvider, openingBalanceDisplay));
        openingBalanceAdded = true;
      }
    }

    // ── Transaction rows ──
    for (var transaction in sortedTransactions) {
      final date = DateTime.tryParse(transaction['date']?.toString() ?? '') ?? DateTime(2000);

      if (!openingBalanceAdded &&
          openingBalanceDate != null &&
          openingBalanceDate.isBefore(date) &&
          (openingBalanceDisplay != 0 || !provider.isFiltered)) {
        rows.add(_buildOpeningBalancePdfRow(provider, languageProvider, openingBalanceDisplay));
        openingBalanceAdded = true;
      }

      final details = transaction['details']?.toString() ??
          transaction['referenceNumber']?.toString() ??
          transaction['filledNumber']?.toString() ??
          '-';

      final isInvoice = (transaction['credit'] ?? 0) != 0;
      final type = isInvoice
          ? (languageProvider.isEnglish ? 'Invoice' : 'انوائس')
          : (languageProvider.isEnglish ? 'Payment' : 'ادائیگی');

      final paymentMethod = transaction['paymentMethod']?.toString() ?? '-';
      final paymentMethodText = _getPaymentMethodText(paymentMethod, languageProvider);
      final bankName = _getBankName(transaction);
      final debit = (transaction['debit'] ?? 0).toDouble();
      final credit = (transaction['credit'] ?? 0).toDouble();
      final balance = (transaction['balance'] ?? 0).toDouble();

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
              _buildPdfDataCell(DateFormat('dd MMM yyyy').format(date), 50),
              _buildPdfDataCell(
                transaction['invoiceNumber']?.toString() ??
                    transaction['filledNumber']?.toString() ?? '-',
                40,
                textColor: PdfColors.blue800,
                fontWeight: pw.FontWeight.bold,
              ),
              _buildPdfDataCell(
                transaction['referenceNumber']?.toString() ?? '-',
                40,
                textColor: PdfColors.purple800,
              ),
              _buildPdfDataCell(details, 70),
              _buildPdfDataCell(type, 40),
              _buildPdfDataCell(paymentMethodText, 50),
              _buildPdfDataCell(bankName ?? '-', 60),
              _buildPdfDataCell(
                debit > 0 ? 'Rs ${debit.toStringAsFixed(2)}' : '-',
                40,
                textColor: debit > 0 ? PdfColors.red : PdfColors.black,
              ),
              _buildPdfDataCell(
                credit > 0 ? 'Rs ${credit.toStringAsFixed(2)}' : '-',
                40,
                textColor: credit > 0 ? PdfColors.green800 : PdfColors.black,
              ),
              _buildPdfDataCell(
                'Rs ${balance.toStringAsFixed(2)}',
                50,
                fontWeight: pw.FontWeight.bold,
                textColor: PdfColors.blue800,
              ),
            ],
          ),
        ),
      );

      // ── Invoice items (expanded) ──
      final transactionKey = transaction['key']?.toString() ?? '';
      final isExpanded = provider.expandedTransactions.contains(transactionKey);

      if (isInvoice && isExpanded) {
        final invoiceItems = provider.invoiceItems[transactionKey] ?? [];
        if (invoiceItems.isNotEmpty) {
          final double itemsSubtotal = invoiceItems.fold(0.0, (sum, item) => sum + (item['total'] ?? 0));
          final double totalQty = invoiceItems.fold(0.0, (sum, item) => sum + ((item['quantity'] ?? 0).toDouble()));
          final double totalWeight = invoiceItems.fold(0.0, (sum, item) {
            final weight = item['totalWeight'] ?? 0.0;
            final qty = item['quantity'] ?? 0.0;
            final weightPerUnit = item['weightPerUnit'] ?? 0.0;
            if (item['calculationType'] == 'weight' && weight > 0) {
              return sum + weight;
            } else if (weightPerUnit > 0) {
              return sum + (weightPerUnit * qty);
            }
            return sum;
          });

          // ── Build table rows using pre-rendered images for name & length ──
          final dataRows = invoiceItems.map<pw.TableRow>((item) {
            String weightPerUnitText = '';
            String totalWeightText = '';
            String calcType = item['calculationType'] == 'weight' ? 'Wt×Rt' : 'Qty×Rt';

            if (item['weightPerUnit'] != null && item['weightPerUnit'] > 0) {
              weightPerUnitText = '${item['weightPerUnit'].toStringAsFixed(2)} ${item['weightUnit'] ?? 'kg'}';
            }

            if (item['calculationType'] == 'weight') {
              if (item['totalWeight'] != null && item['totalWeight'] > 0) {
                totalWeightText = '${item['totalWeight'].toStringAsFixed(2)} ${item['weightUnit'] ?? 'kg'}';
              } else if (item['weightPerUnit'] != null && item['quantity'] != null) {
                final totalWt = (item['weightPerUnit'] * item['quantity']).toStringAsFixed(2);
                totalWeightText = '$totalWt ${item['weightUnit'] ?? 'kg'}';
              }
            }

            final itemName = item['itemName']?.toString() ?? '-';
            final lengthStr = item['length']?.toString() ?? '';

            // Item name cell
            final pw.Widget nameCell = itemNameImages.containsKey(itemName)
                ? pw.Padding(
              padding: const pw.EdgeInsets.all(2),
              child: pw.Image(
                pw.MemoryImage(itemNameImages[itemName]!),
                width: 110,   // logical width in PDF points
                height: 18,   // logical height in PDF points
                fit: pw.BoxFit.contain,
              ),
            )
                : _buildPdfTableCell(itemName);

            final pw.Widget lengthCell = lengthImages.containsKey(lengthStr)
                ? pw.Padding(
              padding: const pw.EdgeInsets.all(2),
              child: pw.Image(
                pw.MemoryImage(lengthImages[lengthStr]!),
                width: 65,    // logical width in PDF points
                height: 18,   // logical height in PDF points
                fit: pw.BoxFit.contain,
              ),
            )
                : _buildPdfTableCell(lengthStr);

            return pw.TableRow(
              children: [
                nameCell,
                lengthCell,
                _buildPdfTableCell(item['bodyType']?.toString() ?? ''),
                _buildPdfTableCell(item['description']?.toString() ?? ''),
                _buildPdfTableCell((item['quantity'] ?? 0).toString()),
                _buildPdfTableCell(weightPerUnitText),
                _buildPdfTableCell(totalWeightText, textColor: PdfColors.blue800),
                _buildPdfTableCell(calcType, textColor: PdfColors.purple800),
                _buildPdfTableCell(
                  'Rs ${(item['rate'] ?? 0).toStringAsFixed(2)}',
                  textColor: PdfColors.orange800,
                ),
                _buildPdfTableCell(
                  'Rs ${(item['total'] ?? 0).toStringAsFixed(2)}',
                  isBold: true,
                  textColor: PdfColors.green800,
                ),
              ],
            );
          }).toList();

          rows.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(left: 20, top: 4, bottom: 4),
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                borderRadius: pw.BorderRadius.circular(4),
                color: PdfColors.grey100,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    languageProvider.isEnglish ? "Invoice Items" : "انوائس آئٹمز",
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.3),
                    columnWidths: const {
                      0: pw.FlexColumnWidth(2),   // Item Name
                      1: pw.FlexColumnWidth(1),   // Length
                      2: pw.FlexColumnWidth(1),   // Body Type
                      3: pw.FlexColumnWidth(2),   // Description
                      4: pw.FlexColumnWidth(0.8), // Qty
                      5: pw.FlexColumnWidth(1),   // Weight/Unit
                      6: pw.FlexColumnWidth(1),   // Total Wt
                      7: pw.FlexColumnWidth(0.8), // Calc
                      8: pw.FlexColumnWidth(1),   // Rate
                      9: pw.FlexColumnWidth(1),   // Total
                    },
                    children: [
                      // Header row
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                        children: [
                          _buildPdfTableCell("Item Name", isHeader: true),
                          _buildPdfTableCell("Length", isHeader: true),
                          _buildPdfTableCell("Body Type", isHeader: true),
                          _buildPdfTableCell("Description", isHeader: true),
                          _buildPdfTableCell("Qty", isHeader: true),
                          _buildPdfTableCell("Wt/Unit", isHeader: true),
                          _buildPdfTableCell("Total Wt", isHeader: true),
                          _buildPdfTableCell("Calc", isHeader: true),
                          _buildPdfTableCell("Rate", isHeader: true),
                          _buildPdfTableCell("Total", isHeader: true),
                        ],
                      ),
                      // Data rows
                      ...dataRows,
                      // Total row
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                        children: [
                          _buildPdfTableCell("TOTAL", isHeader: true),
                          _buildPdfTableCell(""),
                          _buildPdfTableCell(""),
                          _buildPdfTableCell(""),
                          _buildPdfTableCell(totalQty.toStringAsFixed(0), isHeader: true),
                          _buildPdfTableCell(""),
                          _buildPdfTableCell(
                            "${totalWeight.toStringAsFixed(2)} kg",
                            isHeader: true,
                            textColor: PdfColors.blue800,
                          ),
                          _buildPdfTableCell(""),
                          _buildPdfTableCell(""),
                          _buildPdfTableCell(
                            "Rs ${itemsSubtotal.toStringAsFixed(2)}",
                            isHeader: true,
                            textColor: PdfColors.green800,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }
      }
    }

    // ── Opening balance at end if not yet inserted ──
    if (!openingBalanceAdded &&
        (openingBalanceDisplay != 0 || !provider.isFiltered) &&
        openingBalanceDate != null) {
      rows.add(_buildOpeningBalancePdfRow(provider, languageProvider, openingBalanceDisplay));
    }

    // ── Summary / totals row ──
    rows.add(
      pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: PdfColors.orange, width: 1.5),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _buildPdfDataCell(
              languageProvider.isEnglish ? 'TOTALS' : 'کل',
              50,
              fontWeight: pw.FontWeight.bold,
            ),
            _buildPdfDataCell('', 40),
            _buildPdfDataCell('', 40),
            _buildPdfDataCell('', 70),
            _buildPdfDataCell('', 40),
            _buildPdfDataCell('', 50),
            _buildPdfDataCell('', 60),
            _buildPdfDataCell(
              'Rs ${totalDebit.toStringAsFixed(2)}',
              40,
              fontWeight: pw.FontWeight.bold,
              textColor: PdfColors.red,
            ),
            _buildPdfDataCell(
              'Rs ${totalCredit.toStringAsFixed(2)}',
              40,
              fontWeight: pw.FontWeight.bold,
              textColor: PdfColors.green800,
            ),
            _buildPdfDataCell(
              'Rs ${displayFinalBalance.toStringAsFixed(2)}',
              50,
              fontWeight: pw.FontWeight.bold,
              textColor: displayFinalBalance > 0 ? PdfColors.green : PdfColors.red,
            ),
          ],
        ),
      ),
    );

    return pw.Column(children: rows);
  }

  Future<Uint8List> _renderTextAsImageForPdf(
      String text, {
        double fontSize = 9,
        double width = 80,
        double height = 20,
      }) async {
    // ✅ Use 3x scale for sharp, high-resolution output
    const double scale = 3.0;
    final double scaledWidth = width * scale;
    final double scaledHeight = height * scale;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Scale everything up
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
    // ✅ Render at scaled resolution
    final img = await picture.toImage(scaledWidth.toInt(), scaledHeight.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  pw.Widget _buildOpeningBalancePdfRow(
      FilledCustomerReportProvider provider,
      LanguageProvider languageProvider,
      double openingBalanceDisplay)
  {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(color: PdfColors.grey100),
      child: // In _buildOpeningBalancePdfRow method:
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _buildPdfDataCell(
            provider.displayOpeningBalanceDate != null
                ? DateFormat('dd MMM yyyy').format(provider.displayOpeningBalanceDate!)
                : '-',
            50,
          ),
          _buildPdfDataCell('-', 40), // Invoice No
          _buildPdfDataCell('-', 40), // Ref No
          _buildPdfDataCell(
            languageProvider.isEnglish
                ? provider.openingBalanceLabel
                : (provider.isFiltered ? 'پچھلا بیلنس' : 'ابتدائی بیلنس'),
            70,
          ),
          _buildPdfDataCell('-', 40),
          _buildPdfDataCell('-', 50),
          _buildPdfDataCell('-', 60),
          _buildPdfDataCell('-', 40),
          _buildPdfDataCell(
            'Rs ${openingBalanceDisplay.toStringAsFixed(2)}',
            40,
            textColor: openingBalanceDisplay > 0 ? PdfColors.green : PdfColors.red,
            fontWeight: pw.FontWeight.bold,
          ),
          _buildPdfDataCell(
            'Rs ${openingBalanceDisplay.toStringAsFixed(2)}',
            50,
            textColor: openingBalanceDisplay > 0 ? PdfColors.green : PdfColors.red,
            fontWeight: pw.FontWeight.bold,
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
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.orange800,
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
      })
  {
    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.all(6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(right: pw.BorderSide(color: PdfColors.grey300)),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          color: textColor ?? PdfColors.black,
          fontWeight: fontWeight,
        ),
        textAlign: pw.TextAlign.center,
        maxLines: 2,
      ),
    );
  }

  Future<void> _printPDF(pw.Document pdf) async {
    try {
      if (kIsWeb) {
        // Web platform - download PDF
        final bytes = await pdf.save();
        final blob = html.Blob([bytes], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download = 'customer_ledger_${widget.customerName}_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf';
        html.document.body?.children.add(anchor);
        anchor.click();
        html.document.body?.children.remove(anchor);
        html.Url.revokeObjectUrl(url);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF downloaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Mobile/Desktop platform - use printing package
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdf.save(),
          name: 'customer_ledger_${widget.customerName}_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf',
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

  Widget _buildCustomerInfo(BuildContext context, LanguageProvider languageProvider, FilledCustomerReportProvider provider) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Center(
      child: Column(
        children: [
          Text(
            widget.customerName,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: isMobile ? 20 : 24,
              color: Color(0xFFE65100), // Dark orange
            ),
          ),
          Text(
            '${languageProvider.isEnglish ? 'Phone Number:' : 'فون نمبر:'} ${widget.customerPhone}',
            style: TextStyle(color: Color(0xFFFF8A65)),
          ),
          Text(
            '${languageProvider.isEnglish ? 'Address:' : 'پتہ:'} ${widget.customerAddress}',
            style: TextStyle(color: Color(0xFFFF8A65)),
          ),
          Text(
            '${languageProvider.isEnglish ? 'City:' : 'شہر:'} ${widget.customerCity}',
            style: TextStyle(color: Color(0xFFFF8A65)),
          ),
          const SizedBox(height: 10),
          Text(
            provider.isFiltered && provider.dateRangeFilter != null
                ? '${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.start)} - ${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.end)}'
                : 'All Transactions',
            style: TextStyle(color: Color(0xFFFF8A65)),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeSelector(LanguageProvider languageProvider) {
    return Consumer<FilledCustomerReportProvider>(
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
                backgroundColor: Color(0xFFFF8A65),
              ),
            ),
            if (provider.isFiltered)
              TextButton(
                onPressed: () {
                  provider.setDateRangeFilter(null);
                },
                child: Text(
                  languageProvider.isEnglish ? 'Clear Filter' : 'فلٹر صاف کریں',
                  style: const TextStyle(color: Color(0xFFFF8A65)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCards(FilledCustomerReportProvider provider) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    // Get values from the report which now has correct calculations
    final double openingBalance = provider.displayOpeningBalance;
    final double debit = provider.report['debit']?.toDouble() ?? 0.0;
    final double credit = provider.report['credit']?.toDouble() ?? 0.0; // Transaction credits only
    final double netBalance = provider.report['balance']?.toDouble() ?? 0.0; // Final net balance

    // For filtered views with no transactions, show the opening balance as net balance
    final displayNetBalance = provider.isFiltered && provider.transactions.isEmpty
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
              color: Color(0xFFE57373),
              isMobile: isMobile,
            ),
            _buildModernSummaryCard(
              title: 'Total Credit',
              value: credit, // Just transaction credits
              icon: Icons.trending_up,
              color: Color(0xFF81C784),
              isMobile: isMobile,
            ),
            _buildModernSummaryCard(
              title: provider.isFiltered ? 'Closing Balance' : 'Net Balance',
              value: displayNetBalance,
              icon: Icons.account_balance_wallet,
              color: displayNetBalance >= 0 ? Color(0xFF64B5F6) : Color(0xFFFFB74D),
              isMobile: isMobile,
            ),
          ],
        )
    );
  }

  Widget _buildModernSummaryCard({
    required String title,
    required double value,
    required IconData icon,
    required Color color,
    required bool isMobile,
  })
  {
    return Expanded(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
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
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: isMobile ? 20 : 24, color: color),
                  ),
                  Text(
                    'Rs ${value.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: isMobile ? 14 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: isMobile ? 12 : 14,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: 4),
              Container(
                height: 4,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value > 10000
                      ? 1.0
                      : (value < 0 ? 0.0 : value / 10000), // Handle negative values
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInvoiceItems(String transactionKey, FilledCustomerReportProvider reportProvider, DateTime date) {
    final invoiceItems = reportProvider.invoiceItems[transactionKey] ?? [];
    final isMobile = MediaQuery.of(context).size.width < 600;

    // Calculate totals
    final double subtotal = invoiceItems.fold(0.0, (sum, item) => sum + (item['total'] ?? 0));
    final double discount = invoiceItems.fold(0.0, (sum, item) => sum + (item['discount'] ?? 0));
    final double grandTotal = subtotal - discount;

    // Calculate total quantities and weights
    final double totalQty = invoiceItems.fold(0.0, (sum, item) => sum + ((item['quantity'] ?? 0).toDouble()));
    final double totalWeight = invoiceItems.fold(0.0, (sum, item) {
      final weight = item['totalWeight'] ?? 0.0;
      final qty = item['quantity'] ?? 0.0;
      final weightPerUnit = item['weightPerUnit'] ?? 0.0;

      if (item['calculationType'] == 'weight' && weight > 0) {
        return sum + weight;
      } else if (weightPerUnit > 0) {
        return sum + (weightPerUnit * qty);
      }
      return sum;
    });

    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        border: Border.all(color: Color(0xFFFFB74D), width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color(0xFFFFB74D).withOpacity(0.3),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.receipt, color: Color(0xFFE65100), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Invoice Items - ${DateFormat('dd MMM yyyy').format(date)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isMobile ? 12 : 14,
                      color: Color(0xFFE65100),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Subtotal: Rs ${subtotal.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: isMobile ? 10 : 12),
                    ),
                    if (discount > 0)
                      Text(
                        'Discount: Rs ${discount.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: isMobile ? 10 : 12, color: Colors.red),
                      ),
                    Text(
                      'Grand Total: Rs ${grandTotal.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 12 : 14,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Items content
          Padding(
            padding: EdgeInsets.all(12),
            child: invoiceItems.isEmpty
                ? Center(child: CircularProgressIndicator())
                : isMobile
                ? _buildMobileInvoiceTable(invoiceItems, totalQty, totalWeight, subtotal)
                : _buildDesktopInvoiceTable(invoiceItems, totalQty, totalWeight, subtotal),
          ),
        ],
      ),
    );
  }
  Widget _buildMobileInvoiceTable(List<Map<String, dynamic>> invoiceItems, double totalQty, double totalWeight, double subtotal) {
    return Column(
      children: [
        ...invoiceItems.map((item) {
          String weightText = _getWeightText(item);
          String calcType = item['calculationType'] == 'weight' ? 'Wt×Rate' : 'Qty×Rate';

          return Container(
            margin: EdgeInsets.only(bottom: 8),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['itemName']?.toString() ?? '-',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          if (calcType.isNotEmpty)
                            Text(
                              calcType,
                              style: TextStyle(fontSize: 10, color: Colors.purple[600], fontStyle: FontStyle.italic),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      'Rs ${(item['total'] ?? 0).toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green[700]),
                    ),
                  ],
                ),
                SizedBox(height: 8),

                // Length and Body Type
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (item['length']?.toString().isNotEmpty ?? false)
                      Text('Length: ${item['length']}', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    if (item['bodyType']?.toString().isNotEmpty ?? false)
                      Text('Body: ${item['bodyType']}', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ],
                ),

                // Description
                if (item['description']?.toString().isNotEmpty ?? false) ...[
                  SizedBox(height: 4),
                  Text(
                    'Description: ${item['description']}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                SizedBox(height: 4),

                // Qty, Weight, Rate
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Qty: ${item['quantity']?.toString() ?? '0'}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    if (weightText.isNotEmpty)
                      Text('Weight: $weightText',
                          style: TextStyle(fontSize: 11, color: Colors.blue[700])),
                    Text('Rate: Rs ${(item['rate'] ?? 0).toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 11, color: Colors.orange[700])),
                  ],
                ),
              ],
            ),
          );
        }).toList(),

        // Total row
        Container(
          margin: EdgeInsets.only(top: 8),
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Qty: ${totalQty.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Wt: ${totalWeight.toStringAsFixed(2)} kg', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Rs ${subtotal.toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[700])),
            ],
          ),
        ),
      ],
    );
  }

  String _getWeightText(Map<String, dynamic> item) {
    String weightText = '';
    if (item['calculationType'] == 'weight') {
      if (item['totalWeight'] != null && item['totalWeight'] > 0) {
        weightText = '${item['totalWeight'].toStringAsFixed(2)} ${item['weightUnit'] ?? 'kg'}';
      } else if (item['weightPerUnit'] != null && item['weightPerUnit'] > 0) {
        final weight = (item['weightPerUnit'] * (item['quantity'] ?? 1)).toStringAsFixed(2);
        weightText = '$weight ${item['weightUnit'] ?? 'kg'}';
      }
    }
    return weightText;
  }

  Widget _buildDesktopInvoiceTable(
      List<Map<String, dynamic>> invoiceItems,
      double totalQty,
      double totalWeight,
      double subtotal,
      ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth, // 👈 FULL WIDTH
            ),
            child: DataTable(
              columnSpacing: 16,
              dataRowHeight: 56,
              headingRowHeight: 40,
              headingRowColor:
              MaterialStateProperty.all(Colors.grey[100]),
              border: TableBorder.all(color: Colors.grey[300]!),
              headingTextStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFFE65100),
                fontSize: 12,
              ),
              dataTextStyle:
              const TextStyle(fontSize: 11, color: Colors.black87),

              columns: const [
                DataColumn(label: Text('Item Name')),
                DataColumn(label: Text('Length'), numeric: true),
                DataColumn(label: Text('Body Type')),
                DataColumn(label: Text('Description')),
                DataColumn(label: Text('Qty'), numeric: true),
                DataColumn(label: Text('Weight/Unit')),
                DataColumn(label: Text('Total Wt'), numeric: true),
                DataColumn(label: Text('Calc')),
                DataColumn(label: Text('Rate'), numeric: true),
                DataColumn(label: Text('Total'), numeric: true),
              ],

              rows: [
                ...invoiceItems.map((item) {
                  String weightText = _getWeightText(item);
                  String calcType = item['calculationType'] == 'weight'
                      ? 'Wt×Rate'
                      : 'Qty×Rate';

                  double? displayTotalWeight;
                  if (item['totalWeight'] != null &&
                      item['totalWeight'] > 0) {
                    displayTotalWeight = item['totalWeight'];
                  } else if (item['weightPerUnit'] != null &&
                      item['quantity'] != null) {
                    displayTotalWeight =
                        item['weightPerUnit'] * item['quantity'];
                  }

                  return DataRow(cells: [
                    DataCell(
                      SizedBox(
                        width: 150,
                        child: Text(
                          item['itemName']?.toString() ?? '-',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                          style: TextStyle(fontSize: 17),
                        ),
                      ),
                    ),
                    DataCell(
                        Text(
                            item['length']?.toString() ?? '',style: TextStyle(fontSize: 17),
                        ),
                    ),
                    DataCell(Text(item['bodyType']?.toString() ?? '',style: TextStyle(fontSize: 17),)),
                    DataCell(
                      SizedBox(
                        width: 150,
                        child: Text(
                          item['description']?.toString() ?? '',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                          style: TextStyle(fontSize: 17),
                        ),
                      ),
                    ),
                    DataCell(Text(
                      (item['quantity'] ?? 0).toString(),
                      style: const TextStyle(fontWeight: FontWeight.w500,fontSize: 17),
                    )),
                    DataCell(Text(
                      item['weightPerUnit'] != null
                          ? '${item['weightPerUnit'].toStringAsFixed(2)} ${item['weightUnit'] ?? 'kg'}'
                          : '-',
                      style: TextStyle(fontSize: 17),
                    )),
                    DataCell(Text(
                      displayTotalWeight != null
                          ? '${displayTotalWeight.toStringAsFixed(2)} ${item['weightUnit'] ?? 'kg'}'
                          : '-',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontWeight: FontWeight.bold,
                        fontSize: 17
                      ),
                    )),
                    DataCell(Text(
                      calcType,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.purple[600],

                      ),
                    )),
                    DataCell(Text(
                      'Rs ${(item['rate'] ?? 0).toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.orange[700],fontSize: 17),
                    )),
                    DataCell(Text(
                      'Rs ${(item['total'] ?? 0).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                        fontSize: 17
                      ),
                    )),
                  ]);
                }).toList(),

                // TOTAL ROW
                DataRow(cells: [
                  const DataCell(Text(
                    'TOTAL',
                    style: TextStyle(fontWeight: FontWeight.bold,fontSize: 15),
                  )),
                  const DataCell(Text('')),
                  const DataCell(Text('')),
                  const DataCell(Text('')),
                  DataCell(Text(
                    totalQty.toStringAsFixed(0),
                    style: const TextStyle(fontWeight: FontWeight.bold,fontSize: 17),
                  )),
                  const DataCell(Text('')),
                  DataCell(Text(
                    '${totalWeight.toStringAsFixed(2)} kg',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                      fontSize: 17
                    ),
                  )),
                  const DataCell(Text('')),
                  const DataCell(Text('')),
                  DataCell(Text(
                    'Rs ${subtotal.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                      fontSize: 17
                    ),
                  )),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTransactionTable(LanguageProvider languageProvider) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Consumer<FilledCustomerReportProvider>(
      builder: (context, reportProvider, child) {
        final openingBalance = reportProvider.openingBalance ?? 0;
        final transactions = reportProvider.transactions ?? [];

        if (transactions.isEmpty && reportProvider.isFiltered) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                languageProvider.isEnglish
                    ? 'No transactions found in the selected date range'
                    : 'منتخب کردہ تاریخ کی حد میں کوئی لین دین نہیں ملا',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCustomTransactionTable(transactions, reportProvider, isMobile, languageProvider),
          ],
        );
      },
    );
  }

  Widget _buildCustomTransactionTable(
      List<Map<String, dynamic>> transactions,
      FilledCustomerReportProvider reportProvider,
      bool isMobile,
      LanguageProvider languageProvider,
      )
  {
    final displayBalance = reportProvider.displayOpeningBalance;

    // Create a list to hold all rows (opening balance + transactions)
    List<Widget> allRows = [];

    // Sort transactions by date to ensure proper chronological order
    List<Map<String, dynamic>> sortedTransactions = List.from(transactions);
    sortedTransactions.sort((a, b) {
      final dateA = DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(2000);
      final dateB = DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(2000);
      return dateA.compareTo(dateB);
    });

    // Find the position where opening balance should be inserted
    DateTime? openingBalanceDate = reportProvider.displayOpeningBalanceDate;
    bool openingBalanceInserted = false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Table Header
        Container(
          decoration: BoxDecoration(
            color: Color(0xFFFFB74D).withOpacity(0.2),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Date' : 'ڈیٹ', 1),
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Invoice No' : 'انوائس نمبر', 1),
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Ref No' : 'ریف نمبر', 1),
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Details' : 'تفصیلات', 2),
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Type' : 'قسم', 1),
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Payment Method' : 'ادائیگی کا طریقہ', 1.5),
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Bank' : 'بینک', 2),
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Debit' : 'ڈیبٹ', 1),
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Credit' : 'کریڈٹ', 1),
              _buildExpandedHeaderCell(languageProvider.isEnglish ? 'Balance' : 'بیلنس', 1),
            ],
          ),
        ),

        // Build rows with opening balance inserted at correct chronological position
        ...(() {
          List<Widget> rows = [];

          for (int i = 0; i < sortedTransactions.length; i++) {
            final transaction = sortedTransactions[i];
            final transactionDate = DateTime.tryParse(transaction['date']?.toString() ?? '') ?? DateTime(2000);

            // Insert opening balance row if it should come before this transaction
            if (!openingBalanceInserted &&
                (displayBalance != 0 || !reportProvider.isFiltered) &&
                openingBalanceDate != null &&
                openingBalanceDate.isBefore(transactionDate)) {

              rows.add(_buildOpeningBalanceRow(reportProvider, languageProvider, isMobile));
              openingBalanceInserted = true;
            }

            // Add the transaction row
            rows.add(_buildExpandedTransactionRow(transaction, reportProvider, isMobile, languageProvider));

            // Add invoice items if expanded
            final isInvoice = (transaction['credit'] ?? 0) != 0;
            final transactionKey = transaction['key']?.toString() ?? '';
            final isExpanded = reportProvider.expandedTransactions.contains(transactionKey);

            if (isInvoice && isExpanded) {

              rows.add(_buildInvoiceItems(transactionKey, reportProvider, transactionDate));
            }
          }

          // If opening balance hasn't been inserted yet, add it at the end
          // This handles cases where opening balance date is after all transactions
          // or when there are no transactions
          if (!openingBalanceInserted && (displayBalance != 0 || !reportProvider.isFiltered)) {
            if (sortedTransactions.isEmpty) {
              // No transactions, so opening balance goes first
              rows.insert(0, _buildOpeningBalanceRow(reportProvider, languageProvider, isMobile));
            } else {
              // Opening balance date is after all transactions
              rows.add(_buildOpeningBalanceRow(reportProvider, languageProvider, isMobile));
            }
          }

          return rows;
        })(),
      ],
    );
  }

  Widget _buildOpeningBalanceRow(
      FilledCustomerReportProvider reportProvider,
      LanguageProvider languageProvider,
      bool isMobile,
      )
    {
    final displayBalance = reportProvider.displayOpeningBalance;

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
            reportProvider.displayOpeningBalanceDate != null
                ? DateFormat('dd MMM yyyy').format(reportProvider.displayOpeningBalanceDate!)
                : '-',
            1,
            isMobile,
          ),
          _buildExpandedDataCell('-', 1, isMobile), // Invoice No
          _buildExpandedDataCell('-', 1, isMobile), // Ref No
          _buildExpandedDataCell(
            languageProvider.isEnglish
                ? reportProvider.openingBalanceLabel
                : (reportProvider.isFiltered ? 'پچھلا بیلنس' : 'ابتدائی بیلنس'),
            2,
            isMobile,
          ),
          _buildExpandedDataCell('-', 1, isMobile),
          _buildExpandedDataCell('-', 1.5, isMobile),
          _buildExpandedDataCell('-', 2, isMobile),
          _buildExpandedDataCell('-', 1, isMobile),
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
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: Colors.grey[300]!)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFFE65100),
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildExpandedTransactionRow(
      Map<String, dynamic> transaction,
      FilledCustomerReportProvider reportProvider,
      bool isMobile,
      LanguageProvider languageProvider,
      )
  {
    final bankName = _getBankName(transaction);
    final bankLogoPath = _getBankLogoPath(bankName);
    final isInvoice = (transaction['credit'] ?? 0) != 0;
    final transactionKey = transaction['key']?.toString() ?? '';
    final isExpanded = reportProvider.expandedTransactions.contains(transactionKey);

    final date = DateTime.tryParse(transaction['date']?.toString() ?? '') ?? DateTime(2000);
    final details = transaction['details']?.toString() ??
        transaction['referenceNumber']?.toString() ??
        transaction['filledNumber']?.toString() ??
        '-';
    final paymentMethod = transaction['paymentMethod']?.toString() ?? '-';
    final debit = transaction['debit']?.toStringAsFixed(2) ?? '0.00';
    final credit = transaction['credit']?.toStringAsFixed(2) ?? '0.00';
    final balance = transaction['balance']?.toStringAsFixed(2) ?? '0.00';

    return GestureDetector(
      onTap: isInvoice ? () {
        reportProvider.toggleTransactionExpansion(transactionKey);
      } : null,
      child: Container(
        decoration: BoxDecoration(
          color: isInvoice && isExpanded
              ? Color(0xFFFFB74D).withOpacity(0.1)
              : Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey[300]!),
            left: BorderSide(color: Colors.grey[300]!),
            right: BorderSide(color: Colors.grey[300]!),
          ),
        ),
        child: Row(
          children: [
            _buildExpandedDataCell(
              DateFormat('dd MMM yyyy').format(date),
              1,
              isMobile,
            ),
            // Invoice Number cell
            _buildExpandedDataCell(
              transaction['invoiceNumber']?.toString() ??
                  transaction['filledNumber']?.toString() ?? '-',
              1,
              isMobile,
              textColor: Colors.blue[700],
              fontWeight: FontWeight.w500,
            ),
            // Reference Number cell
            _buildExpandedDataCell(
              transaction['referenceNumber']?.toString() ?? '-',
              1,
              isMobile,
              textColor: Colors.purple[700],
            ),
            _buildExpandedDataCell(details, 2, isMobile),
            _buildExpandedDataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isInvoice ? 'Invoice' : 'Payment',
                    style: TextStyle(fontSize: isMobile ? 10 : 12),
                  ),
                  if (isInvoice) ...[
                    SizedBox(width: 4),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: Color(0xFFE65100),
                    ),
                  ],
                ],
              ),
              1,
              isMobile,
            ),
            _buildExpandedDataCell(
              _getPaymentMethodText(paymentMethod, languageProvider),
              1.5,
              isMobile,
            ),
            _buildExpandedDataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (bankLogoPath != null) ...[
                    Image.asset(bankLogoPath, width: 24, height: 24),
                    SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      bankName ?? '-',
                      style: TextStyle(fontSize: isMobile ? 10 : 12),
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
              textColor: (transaction['debit'] ?? 0) > 0 ? Colors.red : Colors.grey,
            ),
            _buildExpandedDataCell(
              (transaction['credit'] ?? 0) > 0 ? 'Rs $credit' : '-',
              1,
              isMobile,
              textColor: (transaction['credit'] ?? 0) > 0 ? Colors.green : Colors.grey,
            ),
            _buildExpandedDataCell(
              'Rs $balance',
              1,
              isMobile,
              fontWeight: FontWeight.bold,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedDataCell(
      dynamic content,
      double flexValue,
      bool isMobile, {
        Color? textColor,
        FontWeight? fontWeight,
      })
  {
    return Expanded(
      flex: (flexValue * 10).round(),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: Colors.grey[300]!)),
        ),
        child: content is Widget
            ? Center(child: content)
            : Text(
          content.toString(),
          style: TextStyle(
            fontSize: isMobile ? 10 : 12,
            color: textColor ?? Colors.black87,
            fontWeight: fontWeight,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  String _getPaymentMethodText(String? method, LanguageProvider languageProvider) {
    if (method == null) return '-';
    switch (method.toLowerCase()) {
      case 'cash': return languageProvider.isEnglish ? 'Cash' : 'نقد';
      case 'online': return languageProvider.isEnglish ? 'Online' : 'آن لائن';
      case 'check':
      case 'cheque': return languageProvider.isEnglish ? 'Cheque' : 'چیک';
      case 'bank': return languageProvider.isEnglish ? 'Bank Transfer' : 'بینک ٹرانسفر';
      case 'slip': return languageProvider.isEnglish ? 'Slip' : 'پرچی';
      case 'udhaar': return languageProvider.isEnglish ? 'Udhaar' : 'ادھار';
      default: return method;
    }
  }

}