
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:mughal_group_branch_two/Provider/lanprovider.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

class EnhancedTransactionsPage extends StatefulWidget {
  @override
  _EnhancedTransactionsPageState createState() => _EnhancedTransactionsPageState();
}

class _EnhancedTransactionsPageState extends State<EnhancedTransactionsPage> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  // Data storage
  List<Map<String, dynamic>> _allPayments = [];
  List<Map<String, dynamic>> _allInvoices = [];
  List<Map<String, dynamic>> _allPurchases = [];
  List<Map<String, dynamic>> _allVendorPayments = [];

  // Filtered data
  List<Map<String, dynamic>> _filteredPayments = [];
  List<Map<String, dynamic>> _filteredInvoices = [];
  List<Map<String, dynamic>> _filteredPurchases = [];
  List<Map<String, dynamic>> _filteredVendorPayments = [];

  // Names mapping
  Map<String, String> _customerNames = {};
  Map<String, String> _vendorNames = {};

  // Filtering variables
  DateTime? _startDate;
  DateTime? _endDate;
  String _searchQuery = '';
  bool _isLoading = false;

  // Summary statistics
  double _totalPayments = 0.0;
  double _totalInvoices = 0.0;
  double _totalPurchasesAmount = 0.0;
  double _totalVendorPayments = 0.0;

  // Tabs control
  int _selectedTab = 0; // 0: All, 1: Customer Payments, 2: Invoices, 3: Purchases, 4: Vendor Payments

// Add this method to your class to group vendor payments
  Map<String, List<Map<String, dynamic>>> _groupVendorPayments(List<Map<String, dynamic>> payments) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final payment in payments) {
      final vendorName = payment['vendorName'] as String;
      if (!grouped.containsKey(vendorName)) {
        grouped[vendorName] = [];
      }
      grouped[vendorName]!.add(payment);
    }

    // Sort payments within each group by date (newest first)
    grouped.forEach((vendor, paymentsList) {
      paymentsList.sort((a, b) => b['date'].compareTo(a['date']));
    });

    return grouped;
  }

  Future<Uint8List> _generatePdfReport() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final pdf = pw.Document();

    // Load logo from assets
    final logo = await _loadLogo();

    // Calculate filtered totals for summary
    double filteredInvoiceTotal = _filteredInvoices.fold(0.0, (sum, inv) => sum + (inv['grandTotal'] as double));
    double filteredPaymentTotal = _filteredPayments.fold(0.0, (sum, pay) => sum + (pay['amount'] as double));
    double filteredPurchaseTotal = _filteredPurchases.fold(0.0, (sum, purchase) => sum + (purchase['grandTotal'] as double));
    double filteredVendorPaymentTotal = _filteredVendorPayments.fold(0.0, (sum, payment) => sum + (payment['amount'] as double));

    // Add single page with all content
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Cover/Header Section
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null)
                  pw.Image(logo, width: 80, height: 80),

                pw.SizedBox(height: 16),
                pw.Text(
                  languageProvider.isEnglish ? 'TRANSACTIONS REPORT' : 'لین دین کی رپورٹ',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue,
                  ),
                ),

                pw.SizedBox(height: 8),
                pw.Text(
                  languageProvider.isEnglish ? 'Comprehensive Transaction Analysis' : 'جامع لین دین کا تجزیہ',
                  style: pw.TextStyle(
                    fontSize: 12,
                    color: PdfColors.grey,
                  ),
                ),

                pw.SizedBox(height: 24),
                pw.Container(
                  width: double.infinity,
                  padding: pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.blue, width: 1),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        languageProvider.isEnglish ? 'Report Details' : 'رپورٹ کی تفصیلات',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      _buildReportInfoRow(
                        languageProvider.isEnglish ? 'Report Date:' : 'رپورٹ کی تاریخ:',
                        DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
                      ),
                      _buildReportInfoRow(
                        languageProvider.isEnglish ? 'Period:' : 'مدت:',
                        _startDate != null && _endDate != null
                            ? '${DateFormat('dd/MM/yyyy').format(_startDate!)} - ${DateFormat('dd/MM/yyyy').format(_endDate!)}'
                            : languageProvider.isEnglish ? 'All Time' : 'تمام وقت',
                      ),
                      _buildReportInfoRow(
                        languageProvider.isEnglish ? 'Total Transactions:' : 'کل لین دین:',
                        '${_filteredPayments.length + _filteredInvoices.length + _filteredPurchases.length + _groupVendorPayments(_filteredVendorPayments).length}',
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 24),
              ],
            ),

            // Summary Section
            pw.Header(
              level: 1,
              text: languageProvider.isEnglish ? 'SUMMARY' : 'خلاصہ',
            ),
            pw.SizedBox(height: 12),
            _buildSummaryTable(languageProvider),
            pw.SizedBox(height: 16),
            _buildFinancialSummary(languageProvider),
            pw.SizedBox(height: 24),

            // Detailed Sections - Only show if there are transactions
            if (_filteredPayments.isNotEmpty) ...[
              pw.Header(
                level: 1,
                text: languageProvider.isEnglish ? 'CUSTOMER PAYMENTS' : 'کسٹمر ادائیگیاں',
              ),
              pw.SizedBox(height: 8),
              _buildPaymentsTable(languageProvider, compact: true),
              pw.SizedBox(height: 24),
            ],

            if (_filteredInvoices.isNotEmpty) ...[
              pw.Header(
                level: 1,
                text: languageProvider.isEnglish ? 'SALES INVOICES' : 'فروخت کے بل',
              ),
              pw.SizedBox(height: 8),
              _buildInvoicesTable(languageProvider, compact: true),
              pw.SizedBox(height: 24),
            ],

            if (_filteredPurchases.isNotEmpty) ...[
              pw.Header(
                level: 1,
                text: languageProvider.isEnglish ? 'PURCHASES' : 'خریداری',
              ),
              pw.SizedBox(height: 8),
              _buildPurchasesTable(languageProvider, compact: true),
              pw.SizedBox(height: 24),
            ],

            if (_filteredVendorPayments.isNotEmpty) ...[
              pw.Header(
                level: 1,
                text: languageProvider.isEnglish ? 'VENDOR PAYMENTS' : 'وینڈر ادائیگیاں',
              ),
              pw.SizedBox(height: 8),
              _buildVendorPaymentsTable(languageProvider, compact: true),
              pw.SizedBox(height: 24),
            ],

            // Footer
            pw.Container(
              alignment: pw.Alignment.center,
              child: pw.Text(
                languageProvider.isEnglish
                    ? 'Generated by Onex Gas Appliances'
                    : 'Onex Gas Appliances کی طرف سے تیار کردہ',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey,
                ),
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

// Update table methods to accept compact parameter for smaller text
  pw.Widget _buildPaymentsTable(LanguageProvider languageProvider, {bool compact = false}) {
    final headers = [
      languageProvider.isEnglish ? 'Date' : 'تاریخ',
      languageProvider.isEnglish ? 'Customer' : 'کسٹمر',
      languageProvider.isEnglish ? 'Method' : 'طریقہ',
      languageProvider.isEnglish ? 'Amount (Rs)' : 'رقم (روپیے)',
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.green50),
          children: headers.map((header) =>
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  header,
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: compact ? 9 : 11,
                  ),
                ),
              )
          ).toList(),
        ),
        ..._filteredPayments.map((payment) {
          final customerId = payment['customerId'] as String;
          final customerName = _customerNames[customerId] ?? customerId;

          return pw.TableRow(
            children: [
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  DateFormat('dd/MM/yy').format(payment['date']),
                  style: pw.TextStyle(fontSize: compact ? 8 : 10),
                ),
              ),
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  _truncateText(customerName, maxLength: 20),
                  style: pw.TextStyle(fontSize: compact ? 8 : 10),
                ),
              ),
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  payment['paymentMethod'].toString(),
                  style: pw.TextStyle(fontSize: compact ? 8 : 10),
                ),
              ),
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  payment['amount'].toStringAsFixed(2),
                  style: pw.TextStyle(fontSize: compact ? 8 : 10),
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          );
        }).toList(),
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            pw.Padding(
              padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
              child: pw.Text(
                languageProvider.isEnglish ? 'Total:' : 'کل:',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: compact ? 9 : 11,
                ),
              ),
            ),
            pw.Padding(padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6), child: pw.Text('')),
            pw.Padding(padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6), child: pw.Text('')),
            pw.Padding(
              padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
              child: pw.Text(
                _filteredPayments.fold(0.0, (sum, p) => sum + p['amount']).toStringAsFixed(2),
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: compact ? 9 : 11,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }

// Update other table methods similarly with compact parameter
  pw.Widget _buildInvoicesTable(LanguageProvider languageProvider, {bool compact = false}) {
    final headers = [
      languageProvider.isEnglish ? 'Date' : 'تاریخ',
      languageProvider.isEnglish ? 'Customer' : 'کسٹمر',
      languageProvider.isEnglish ? 'Invoice #' : 'بل نمبر',
      languageProvider.isEnglish ? 'Amount (Rs)' : 'رقم (روپیے)',
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.blue50),
          children: headers.map((header) =>
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  header,
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: compact ? 9 : 11,
                  ),
                ),
              )
          ).toList(),
        ),
        ..._filteredInvoices.map((invoice) {
          return pw.TableRow(
            children: [
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  DateFormat('dd/MM/yy').format(invoice['date']),
                  style: pw.TextStyle(fontSize: compact ? 8 : 10),
                ),
              ),
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  _truncateText(invoice['customerName'].toString(), maxLength: 20),
                  style: pw.TextStyle(fontSize: compact ? 8 : 10),
                ),
              ),
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  invoice['filledNumber'].toString(),
                  style: pw.TextStyle(fontSize: compact ? 8 : 10),
                ),
              ),
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  invoice['grandTotal'].toStringAsFixed(2),
                  style: pw.TextStyle(fontSize: compact ? 8 : 10),
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          );
        }).toList(),
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            pw.Padding(
              padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
              child: pw.Text(
                languageProvider.isEnglish ? 'Total:' : 'کل:',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: compact ? 9 : 11,
                ),
              ),
            ),
            pw.Padding(padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6), child: pw.Text('')),
            pw.Padding(padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6), child: pw.Text('')),
            pw.Padding(
              padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
              child: pw.Text(
                _filteredInvoices.fold(0.0, (sum, i) => sum + i['grandTotal']).toStringAsFixed(2),
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: compact ? 9 : 11,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }

// Add this helper method to truncate long text
  String _truncateText(String text, {int maxLength = 20}) {
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength - 3) + '...';
  }

// Remove the _addDetailedPages method since it's no longer needed
// Also remove the separate page creation for each transaction type





  pw.Widget _buildReportInfoRow(String label, String value) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(value),
        ],
      ),
    );
  }

  pw.Widget _buildSummaryTable(LanguageProvider languageProvider) {
    // Calculate filtered totals
    double filteredInvoiceTotal = _filteredInvoices.fold(0.0, (sum, inv) => sum + (inv['grandTotal'] as double));
    double filteredPaymentTotal = _filteredPayments.fold(0.0, (sum, pay) => sum + (pay['amount'] as double));
    double filteredPurchaseTotal = _filteredPurchases.fold(0.0, (sum, purchase) => sum + (purchase['grandTotal'] as double));
    double filteredVendorPaymentTotal = _filteredVendorPayments.fold(0.0, (sum, payment) => sum + (payment['amount'] as double));
    double netCashFlow = filteredPaymentTotal - filteredVendorPaymentTotal;

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 1),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.blue50),
          children: [
            pw.Padding(
              padding: pw.EdgeInsets.all(8),
              child: pw.Text(
                languageProvider.isEnglish ? 'Transaction Type' : 'لین دین کی قسم',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(8),
              child: pw.Text(
                languageProvider.isEnglish ? 'Count' : 'تعداد',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(8),
              child: pw.Text(
                languageProvider.isEnglish ? 'Total Amount (Rs)' : 'کل رقم (روپیے)',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
        _buildTableRow(
          languageProvider.isEnglish ? 'Customer Payments' : 'کسٹمر ادائیگیاں',
          _filteredPayments.length.toString(),
          filteredPaymentTotal,
        ),
        _buildTableRow(
          languageProvider.isEnglish ? 'Sales Invoices' : 'فروخت کے بل',
          _filteredInvoices.length.toString(),
          filteredInvoiceTotal,
        ),
        _buildTableRow(
          languageProvider.isEnglish ? 'Purchases' : 'خریداری',
          _filteredPurchases.length.toString(),
          filteredPurchaseTotal,
        ),
        _buildTableRow(
          languageProvider.isEnglish ? 'Vendor Payments' : 'وینڈر ادائیگیاں',
          _groupVendorPayments(_filteredVendorPayments).length.toString(),
          filteredVendorPaymentTotal,
        ),
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            pw.Padding(
              padding: pw.EdgeInsets.all(8),
              child: pw.Text(
                languageProvider.isEnglish ? 'Net Cash Flow' : 'خالص نقد بہاؤ',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Padding(padding: pw.EdgeInsets.all(8), child: pw.Text('')),
            pw.Padding(
              padding: pw.EdgeInsets.all(8),
              child: pw.Text(
                '${netCashFlow.toStringAsFixed(2)} Rs',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: netCashFlow >= 0 ? PdfColors.green : PdfColors.red,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.TableRow _buildTableRow(String type, String count, double amount) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: pw.EdgeInsets.all(8),
          child: pw.Text(type),
        ),
        pw.Padding(
          padding: pw.EdgeInsets.all(8),
          child: pw.Text(count, textAlign: pw.TextAlign.center),
        ),
        pw.Padding(
          padding: pw.EdgeInsets.all(8),
          child: pw.Text(
            '${amount.toStringAsFixed(2)}',
            textAlign: pw.TextAlign.right,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildFinancialSummary(LanguageProvider languageProvider) {
    double filteredInvoiceTotal = _filteredInvoices.fold(0.0, (sum, inv) => sum + (inv['grandTotal'] as double));
    double filteredPaymentTotal = _filteredPayments.fold(0.0, (sum, pay) => sum + (pay['amount'] as double));
    double filteredPurchaseTotal = _filteredPurchases.fold(0.0, (sum, purchase) => sum + (purchase['grandTotal'] as double));
    double filteredVendorPaymentTotal = _filteredVendorPayments.fold(0.0, (sum, payment) => sum + (payment['amount'] as double));

    return pw.Container(
      padding: pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue, width: 1),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            languageProvider.isEnglish ? 'Financial Summary' : 'مالی خلاصہ',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue,
            ),
          ),
          pw.SizedBox(height: 16),
          _buildFinancialRow(
            languageProvider.isEnglish ? 'Total Income (Customer Payments)' : 'کل آمدنی (کسٹمر ادائیگیاں)',
            filteredPaymentTotal,
            PdfColors.green,
          ),
          pw.SizedBox(height: 8),
          _buildFinancialRow(
            languageProvider.isEnglish ? 'Total Sales (Invoices)' : 'کل فروخت (بل)',
            filteredInvoiceTotal,
            PdfColors.blue,
          ),
          pw.SizedBox(height: 8),
          _buildFinancialRow(
            languageProvider.isEnglish ? 'Total Purchases' : 'کل خریداری',
            filteredPurchaseTotal,
            PdfColors.orange,
          ),
          pw.SizedBox(height: 8),
          _buildFinancialRow(
            languageProvider.isEnglish ? 'Total Expenses (Vendor Payments)' : 'کل اخراجات (وینڈر ادائیگیاں)',
            filteredVendorPaymentTotal,
            PdfColors.red,
          ),
          pw.Divider(),
          pw.SizedBox(height: 8),
          _buildFinancialRow(
            languageProvider.isEnglish ? 'Net Cash Position' : 'خالص نقد پوزیشن',
            filteredPaymentTotal - filteredVendorPaymentTotal,
            filteredPaymentTotal - filteredVendorPaymentTotal >= 0
                ? PdfColors.green
                : PdfColors.red,
            isBold: true,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFinancialRow(String label, double amount, PdfColor color, {bool isBold = false}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: isBold
              ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
              : null,
        ),
        pw.Text(
          '${amount.toStringAsFixed(2)} Rs',
          style: pw.TextStyle(
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPurchasesTable(LanguageProvider languageProvider, {bool compact = false}) {
    final headers = [
      languageProvider.isEnglish ? 'Date' : 'تاریخ',
      languageProvider.isEnglish ? 'Vendor' : 'وینڈر',
      languageProvider.isEnglish ? 'Ref #' : 'ریف نمبر',
      languageProvider.isEnglish ? 'Amount (Rs)' : 'رقم (روپیے)',
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.orange50),
          children: headers.map((header) =>
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  header,
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: compact ? 9 : 11,
                  ),
                ),
              )
          ).toList(),
        ),
        ..._filteredPurchases.map((purchase) {
          return pw.TableRow(
            children: [
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  DateFormat('dd/MM/yy').format(purchase['date']),
                  style: pw.TextStyle(fontSize: compact ? 8 : 10),
                ),
              ),
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  _truncateText(purchase['vendorName'].toString(), maxLength: 20),
                  style: pw.TextStyle(fontSize: compact ? 8 : 10),
                ),
              ),
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  purchase['refNo'].toString(),
                  style: pw.TextStyle(fontSize: compact ? 8 : 10),
                ),
              ),
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  purchase['grandTotal'].toStringAsFixed(2),
                  style: pw.TextStyle(fontSize: compact ? 8 : 10),
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          );
        }).toList(),
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            pw.Padding(
              padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
              child: pw.Text(
                languageProvider.isEnglish ? 'Total:' : 'کل:',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: compact ? 9 : 11,
                ),
              ),
            ),
            pw.Padding(padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6), child: pw.Text('')),
            pw.Padding(padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6), child: pw.Text('')),
            pw.Padding(
              padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
              child: pw.Text(
                _filteredPurchases.fold(0.0, (sum, p) => sum + p['grandTotal']).toStringAsFixed(2),
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: compact ? 9 : 11,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildVendorPaymentsTable(LanguageProvider languageProvider, {bool compact = false}) {
    final headers = [
      languageProvider.isEnglish ? 'Date' : 'تاریخ',
      languageProvider.isEnglish ? 'Vendor' : 'وینڈر',
      languageProvider.isEnglish ? 'Method' : 'طریقہ',
      languageProvider.isEnglish ? 'Amount (Rs)' : 'رقم (روپیے)',
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.red50),
          children: headers.map((header) =>
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  header,
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: compact ? 9 : 11,
                  ),
                ),
              )
          ).toList(),
        ),
        ..._filteredVendorPayments.map((payment) {
          final dateToShow = payment['method'].toLowerCase() == 'cheque' && payment['chequeDate'] != null
              ? payment['chequeDate'] as DateTime
              : payment['date'] as DateTime;

          return pw.TableRow(
            children: [
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  DateFormat('dd/MM/yy').format(dateToShow),
                  style: pw.TextStyle(fontSize: compact ? 8 : 10),
                ),
              ),
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  _truncateText(payment['vendorName'].toString(), maxLength: 20),
                  style: pw.TextStyle(fontSize: compact ? 8 : 10),
                ),
              ),
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  payment['method'].toString(),
                  style: pw.TextStyle(fontSize: compact ? 8 : 10),
                ),
              ),
              pw.Padding(
                padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
                child: pw.Text(
                  payment['amount'].toStringAsFixed(2),
                  style: pw.TextStyle(fontSize: compact ? 8 : 10),
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          );
        }).toList(),
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            pw.Padding(
              padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
              child: pw.Text(
                languageProvider.isEnglish ? 'Total:' : 'کل:',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: compact ? 9 : 11,
                ),
              ),
            ),
            pw.Padding(padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6), child: pw.Text('')),
            pw.Padding(padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6), child: pw.Text('')),
            pw.Padding(
              padding: compact ? pw.EdgeInsets.all(4) : pw.EdgeInsets.all(6),
              child: pw.Text(
                _filteredVendorPayments.fold(0.0, (sum, p) => sum + p['amount']).toStringAsFixed(2),
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: compact ? 9 : 11,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<pw.MemoryImage?> _loadLogo() async {
    try {
      final ByteData data = await rootBundle.load('assets/logo.png');
      final Uint8List bytes = data.buffer.asUint8List();
      final img.Image? image = img.decodeImage(bytes);

      if (image != null) {
        return pw.MemoryImage(bytes);
      }
    } catch (e) {
      print('Error loading logo: $e');
    }
    return null;
  }

  Future<void> _generateAndSharePdf() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    // Check if we have data to generate report
    if (_filteredPayments.isEmpty &&
        _filteredInvoices.isEmpty &&
        _filteredPurchases.isEmpty &&
        _filteredVendorPayments.isEmpty) {

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            languageProvider.isEnglish
                ? 'No transactions found to generate report'
                : 'رپورٹ بنانے کے لیے کوئی لین دین نہیں ملا',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      setState(() => _isLoading = true);

      // Generate PDF
      final pdfBytes = await _generatePdfReport();

      // Save to temporary directory
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/transactions_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(await pdfBytes);

      // Share or preview the PDF
      await Printing.sharePdf(
        bytes: await file.readAsBytes(),
        filename: 'transactions_report_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            languageProvider.isEnglish
                ? 'PDF report generated successfully!'
                : 'PDF رپورٹ کامیابی سے تیار ہو گئی!',
          ),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      print('Error generating PDF: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            languageProvider.isEnglish
                ? 'Error generating PDF: $e'
                : 'PDF بنانے میں خرابی: $e',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _previewPdf() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    if (_filteredPayments.isEmpty &&
        _filteredInvoices.isEmpty &&
        _filteredPurchases.isEmpty &&
        _filteredVendorPayments.isEmpty) {

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            languageProvider.isEnglish
                ? 'No transactions found to preview'
                : 'پیش نظارہ کے لیے کوئی لین دین نہیں ملا',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      setState(() => _isLoading = true);

      final pdfBytes = await _generatePdfReport();

      await Printing.layoutPdf(
        onLayout: (format) => pdfBytes,
        name: 'Transactions Report',
      );

    } catch (e) {
      print('Error previewing PDF: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            languageProvider.isEnglish
                ? 'Error previewing PDF: $e'
                : 'PDF کا پیش نظارہ کرنے میں خرابی: $e',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Add this method to add PDF button in your UI
  Widget _buildPdfButton() {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: ElevatedButton.icon(
        icon: Icon(Icons.picture_as_pdf),
        label: Text(languageProvider.isEnglish ? 'PDF Report' : 'PDF رپورٹ'),
        onPressed: _isLoading ? null : () => _showPdfOptionsDialog(),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          minimumSize: Size(double.infinity, 45),
        ),
      ),
    );
  }

  Future<void> _showPdfOptionsDialog() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(languageProvider.isEnglish ? 'PDF Report Options' : 'PDF رپورٹ کے اختیارات'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(Icons.visibility, color: Colors.blue),
              title: Text(languageProvider.isEnglish ? 'Preview Report' : 'رپورٹ کا پیش نظارہ کریں'),
              subtitle: Text(languageProvider.isEnglish
                  ? 'View the report before sharing'
                  : 'شیئر کرنے سے پہلے رپورٹ دیکھیں'),
              onTap: () {
                Navigator.pop(context);
                _previewPdf();
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.share, color: Colors.green),
              title: Text(languageProvider.isEnglish ? 'Share/Download Report' : 'رپورٹ شیئر/ڈاؤن لوڈ کریں'),
              subtitle: Text(languageProvider.isEnglish
                  ? 'Share via apps or save to device'
                  : 'ایپس کے ذریعے شیئر کریں یا ڈیوائس پر محفوظ کریں'),
              onTap: () {
                Navigator.pop(context);
                _generateAndSharePdf();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ کریں'),
          ),
        ],
      ),
    );
  }




  Widget _buildVendorPaymentsList() {
    final languageProvider = Provider.of<LanguageProvider>(context);

    if (_filteredVendorPayments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.money_off, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                languageProvider.isEnglish
                    ? 'No vendor payments found'
                    : 'کوئی وینڈر ادائیگی نہیں ملی',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Group payments by vendor
    final groupedPayments = _groupVendorPayments(_filteredVendorPayments);

    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: groupedPayments.length,
      itemBuilder: (context, index) {
        final vendorName = groupedPayments.keys.elementAt(index);
        final vendorPayments = groupedPayments[vendorName]!;

        return _buildVendorGroupCard(vendorName, vendorPayments);
      },
    );
  }

// New method to build vendor group card
  Widget _buildVendorGroupCard(String vendorName, List<Map<String, dynamic>> payments) {
    // Calculate total for this vendor
    final totalAmount = payments.fold(0.0, (sum, payment) => sum + (payment['amount'] as double));

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.red.withOpacity(0.2),
          child: Icon(Icons.store, color: Colors.red),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                vendorName,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${payments.length} ${payments.length == 1 ? 'Payment' : 'Payments'}',
                style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total:',
                  style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey[600]),
                ),
                Text(
                  '${totalAmount.toStringAsFixed(2)} Rs',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Icon(Icons.expand_more, color: Colors.grey),
        children: [
          Divider(height: 1, indent: 16, endIndent: 16),
          ...payments.map((payment) => _buildVendorPaymentItemCard(payment)).toList(),
        ],
        tilePadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

// Updated vendor payment item card for inside the expansion tile
  Widget _buildVendorPaymentItemCard(Map<String, dynamic> payment) {
    final paymentDate = payment['date'] as DateTime;
    final amount = payment['amount'] as double;
    final method = payment['method'] as String;
    final chequeDate = payment['chequeDate'] as DateTime?;
    final isCheque = method.toLowerCase() == 'cheque';
    final bankName = payment['bankName'] as String?;
    final chequeNumber = payment['chequeNumber'] as String?;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Card(
        elevation: 0,
        color: Colors.grey[50],
        child: ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCheque ? Colors.blue.withOpacity(0.1) : Colors.green.withOpacity(0.1),
            ),
            child: Icon(
              isCheque ? Icons.account_balance_wallet : Icons.money,
              size: 20,
              color: isCheque ? Colors.blue : Colors.green,
            ),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('dd/MM/yyyy').format(paymentDate),
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                '${amount.toStringAsFixed(2)} Rs',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isCheque ? Colors.blue.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: isCheque ? Colors.blue : Colors.green,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      method,
                      style: TextStyle(
                        fontSize: 10,
                        color: isCheque ? Colors.blue : Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (isCheque && chequeDate != null) ...[
                    SizedBox(width: 8),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 10, color: Colors.blue),
                        SizedBox(width: 2),
                        Text(
                          DateFormat('dd/MM/yy').format(chequeDate),
                          style: TextStyle(fontSize: 10, color: Colors.blue),
                        ),
                      ],
                    ),
                  ],
                ],
              ),

              // Show cheque details if available
              if (isCheque && (bankName != null || chequeNumber != null)) ...[
                SizedBox(height: 4),
                Row(
                  children: [
                    if (chequeNumber != null && chequeNumber.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Row(
                          children: [
                            Icon(Icons.numbers, size: 10, color: Colors.grey),
                            SizedBox(width: 2),
                            Text(
                              chequeNumber,
                              style: TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),

                    if (bankName != null && bankName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Row(
                          children: [
                            Icon(Icons.account_balance, size: 10, color: Colors.grey),
                            SizedBox(width: 2),
                            Text(
                              bankName,
                              style: TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
          trailing: Icon(Icons.chevron_right, size: 20, color: Colors.grey),
          onTap: () => _showVendorPaymentDetails(payment),
        ),
      ),
    );
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);

    try {
      // Fetch all data in parallel
      await Future.wait([
        _fetchAllPayments(),
        _fetchAllInvoices(),
        _fetchAllPurchases(),
        _fetchAllVendorPayments(),
        _fetchCustomerNames(),
        _fetchVendorNames(),
      ]);

      // Calculate summary statistics
      _calculateSummaries();

      // Apply initial filters
      _applyFilters();

    } catch (e) {
      print("Error fetching data: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching data: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchAllVendorPayments() async {
    try {
      final vendorsRef = _db.child('vendors');
      final snapshot = await vendorsRef.get();

      _allVendorPayments.clear();

      if (snapshot.exists) {
        final Map<dynamic, dynamic> vendors = snapshot.value as Map<dynamic, dynamic>;

        for (final vendorEntry in vendors.entries) {
          final vendorId = vendorEntry.key.toString();
          final vendorData = vendorEntry.value as Map<dynamic, dynamic>;
          final vendorName = vendorData['name']?.toString() ?? 'Unknown Vendor';

          // Get payments for this vendor
          final payments = vendorData['payments'] as Map<dynamic, dynamic>?;

          if (payments != null) {
            payments.forEach((paymentId, paymentData) {
              if (paymentData != null && paymentData is Map) {
                final amount = (paymentData['amount'] ?? 0.0).toDouble();
                final dateStr = paymentData['date']?.toString();
                final method = paymentData['method']?.toString() ?? 'Unknown';
                final description = paymentData['description']?.toString() ?? '';
                final chequeDateStr = paymentData['chequeDate']?.toString();
                final chequeStatus = paymentData['status']?.toString() ?? 'cleared';
                final bankName = paymentData['bankName']?.toString();
                final chequeNumber = paymentData['chequeNumber']?.toString();

                // For cheque payments, only include cleared cheques
                if (method.toLowerCase() == 'cheque') {
                  if (chequeStatus.toLowerCase() != 'cleared') {
                    return; // Skip pending or bounced cheques
                  }
                }

                // Parse dates
                DateTime paymentDate;
                DateTime? chequeDate;

                try {
                  paymentDate = DateTime.parse(dateStr ?? DateTime.now().toIso8601String());
                } catch (e) {
                  paymentDate = DateTime.now();
                }

                if (chequeDateStr != null && chequeDateStr.isNotEmpty) {
                  try {
                    chequeDate = DateTime.parse(chequeDateStr);
                  } catch (e) {
                    chequeDate = null;
                  }
                }

                _allVendorPayments.add({
                  'id': paymentId,
                  'vendorId': vendorId,
                  'vendorName': vendorName,
                  'amount': amount,
                  'method': method,
                  'description': description,
                  'type': 'Vendor Payment',
                  'date': paymentDate,
                  'chequeDate': chequeDate,
                  'chequeStatus': chequeStatus,
                  'bankName': bankName,
                  'chequeNumber': chequeNumber,
                  'image': paymentData['image']?.toString() ?? '',
                });
              }
            });
          }
        }
      }

      // Sort by date (newest first)
      _allVendorPayments.sort((a, b) => b['date'].compareTo(a['date']));

    } catch (e) {
      print("Error fetching vendor payments: $e");
    }
  }


  Future<void> _fetchAllPurchases() async {
    try {
      final purchasesRef = _db.child('purchases');
      final snapshot = await purchasesRef.get();

      _allPurchases.clear();

      if (snapshot.exists) {
        final Map<dynamic, dynamic> allPurchases = snapshot.value as Map<dynamic, dynamic>;

        allPurchases.forEach((purchaseId, purchaseData) {
          if (purchaseData != null && purchaseData is Map) {
            final grandTotal = (purchaseData['grandTotal'] ?? 0.0).toDouble();
            final vendorId = purchaseData['vendorId']?.toString() ?? '';
            final vendorName = purchaseData['vendorName']?.toString() ?? '';
            final timestamp = purchaseData['timestamp']?.toString();
            final refNo = purchaseData['refNo']?.toString() ?? '';
            final items = purchaseData['items'] as List<dynamic>? ?? [];

            // Calculate total items
            int totalItems = items.length;

            _allPurchases.add({
              'id': purchaseId,
              'vendorId': vendorId,
              'vendorName': vendorName,
              'grandTotal': grandTotal,
              'refNo': refNo,
              'totalItems': totalItems,
              'items': items,
              'type': 'Purchase',
              'date': DateTime.parse(timestamp ?? DateTime.now().toIso8601String()),
              'timestamp': timestamp,
            });
          }
        });
      }

      // Sort by date (newest first)
      _allPurchases.sort((a, b) => b['date'].compareTo(a['date']));

    } catch (e) {
      print("Error fetching purchases: $e");
    }
  }

  Future<void> _fetchVendorNames() async {
    try {
      final vendorsRef = _db.child('vendors');
      final snapshot = await vendorsRef.get();

      if (snapshot.exists) {
        final Map<dynamic, dynamic> vendors = snapshot.value as Map<dynamic, dynamic>;

        vendors.forEach((id, data) {
          if (data != null && data is Map) {
            _vendorNames[id] = data['name']?.toString() ?? 'Unknown Vendor';
          }
        });
      }
    } catch (e) {
      print("Error fetching vendor names: $e");
    }
  }

  Future<void> _fetchAllInvoices() async {
    try {
      final filledRef = _db.child('filled');
      final snapshot = await filledRef.get();

      _allInvoices.clear();

      if (snapshot.exists) {
        final Map<dynamic, dynamic> allFilled = snapshot.value as Map<dynamic, dynamic>;

        allFilled.forEach((filledId, filledData) {
          if (filledData != null && filledData is Map) {
            final grandTotal = (filledData['grandTotal'] ?? 0.0).toDouble();
            final discount = (filledData['discount'] ?? 0.0).toDouble();
            final subtotal = (filledData['subtotal'] ?? 0.0).toDouble();
            final customerId = filledData['customerId']?.toString() ?? '';
            final customerName = filledData['customerName']?.toString() ?? '';
            final createdAt = filledData['createdAt']?.toString();

            _allInvoices.add({
              'id': filledId,
              'filledNumber': filledData['filledNumber']?.toString() ?? '',
              'customerId': customerId,
              'customerName': customerName,
              'grandTotal': grandTotal,
              'subtotal': subtotal,
              'discount': discount,
              'mazdoori': (filledData['mazdoori'] ?? 0.0).toDouble(),
              'referenceNumber': filledData['referenceNumber']?.toString() ?? '',
              'biltiNumber': filledData['biltiNumber']?.toString() ?? '',
              'transportCompany': filledData['transportCompany']?.toString() ?? '',
              'type': 'Invoice',
              'date': DateTime.parse(createdAt ?? DateTime.now().toIso8601String()),
              'paymentType': filledData['paymentType']?.toString() ?? '',
            });
          }
        });
      }

      // Sort by date (newest first)
      _allInvoices.sort((a, b) => b['date'].compareTo(a['date']));

    } catch (e) {
      print("Error fetching invoices: $e");
    }
  }

  Future<void> _fetchAllPayments() async {
    try {
      final ledgerRef = _db.child('filledledger');
      final snapshot = await ledgerRef.get();

      _allPayments.clear();

      if (snapshot.exists) {
        final Map<dynamic, dynamic> allLedgers = snapshot.value as Map<dynamic, dynamic>;

        allLedgers.forEach((customerId, ledgerEntries) {
          if (ledgerEntries != null && ledgerEntries is Map) {
            ledgerEntries.forEach((entryId, entryData) {
              if (entryData != null && entryData is Map) {
                final debitAmount = (entryData['debitAmount'] ?? 0.0).toDouble();

                // Only include debit entries (payments)
                if (debitAmount > 0) {
                  final paymentMethod = entryData['paymentMethod']?.toString() ?? 'Unknown';
                  final chequeStatus = entryData['status']?.toString();

                  // For cheque payments, only include cleared cheques
                  if (paymentMethod.toLowerCase() == 'cheque') {
                    if (chequeStatus != 'cleared') {
                      return; // Skip pending or bounced cheques
                    }
                  }

                  _allPayments.add({
                    'customerId': customerId,
                    'entryId': entryId,
                    'amount': debitAmount,
                    'paymentMethod': paymentMethod,
                    'bankName': entryData['bankName']?.toString(),
                    'chequeNumber': entryData['chequeNumber']?.toString(),
                    'description': entryData['description']?.toString() ?? '',
                    'date': DateTime.parse(entryData['createdAt']?.toString() ?? DateTime.now().toIso8601String()),
                    'referenceNumber': entryData['referenceNumber']?.toString(),
                    'filledNumber': entryData['filledNumber']?.toString(),
                    'type': 'Customer Payment',
                  });
                }
              }
            });
          }
        });
      }

      // Sort by date (newest first)
      _allPayments.sort((a, b) => b['date'].compareTo(a['date']));

    } catch (e) {
      print("Error fetching payments: $e");
    }
  }

  Future<void> _fetchCustomerNames() async {
    try {
      final customersRef = _db.child('customers');
      final snapshot = await customersRef.get();

      if (snapshot.exists) {
        final Map<dynamic, dynamic> customers = snapshot.value as Map<dynamic, dynamic>;

        customers.forEach((id, data) {
          if (data != null && data is Map) {
            _customerNames[id] = data['name']?.toString() ?? 'Unknown Customer';
          }
        });
      }
    } catch (e) {
      print("Error fetching customer names: $e");
    }
  }

  void _calculateSummaries() {
    // Calculate total customer payments
    _totalPayments = _allPayments.fold(0.0, (sum, payment) => sum + (payment['amount'] as double));

    // Calculate total invoices
    _totalInvoices = _allInvoices.fold(0.0, (sum, invoice) => sum + (invoice['grandTotal'] as double));

    // Calculate total purchases
    _totalPurchasesAmount = _allPurchases.fold(0.0, (sum, purchase) => sum + (purchase['grandTotal'] as double));

    // Calculate total vendor payments
    _totalVendorPayments = _allVendorPayments.fold(0.0, (sum, payment) => sum + (payment['amount'] as double));
  }

  // void _applyFilters() {
  //   // Apply filters to payments
  //   List<Map<String, dynamic>> filteredPayments = _allPayments;
  //   List<Map<String, dynamic>> filteredInvoices = _allInvoices;
  //   List<Map<String, dynamic>> filteredPurchases = _allPurchases;
  //   List<Map<String, dynamic>> filteredVendorPayments = _allVendorPayments;
  //
  //   // Apply date filter
  //   if (_startDate != null && _endDate != null) {
  //     filteredPayments = filteredPayments.where((payment) {
  //       final paymentDate = payment['date'] as DateTime;
  //       return paymentDate.isAfter(_startDate!.subtract(Duration(seconds: 1))) &&
  //           paymentDate.isBefore(_endDate!.add(Duration(days: 1)));
  //     }).toList();
  //
  //     filteredInvoices = filteredInvoices.where((invoice) {
  //       final invoiceDate = invoice['date'] as DateTime;
  //       return invoiceDate.isAfter(_startDate!.subtract(Duration(seconds: 1))) &&
  //           invoiceDate.isBefore(_endDate!.add(Duration(days: 1)));
  //     }).toList();
  //
  //     filteredPurchases = filteredPurchases.where((purchase) {
  //       final purchaseDate = purchase['date'] as DateTime;
  //       return purchaseDate.isAfter(_startDate!.subtract(Duration(seconds: 1))) &&
  //           purchaseDate.isBefore(_endDate!.add(Duration(days: 1)));
  //     }).toList();
  //
  //     filteredVendorPayments = filteredVendorPayments.where((payment) {
  //       final paymentDate = payment['date'] as DateTime;
  //       return paymentDate.isAfter(_startDate!.subtract(Duration(seconds: 1))) &&
  //           paymentDate.isBefore(_endDate!.add(Duration(days: 1)));
  //     }).toList();
  //   }
  //
  //   // Apply search filter
  //   if (_searchQuery.isNotEmpty) {
  //     filteredPayments = filteredPayments.where((payment) {
  //       final customerId = payment['customerId'] as String;
  //       final customerName = _customerNames[customerId] ?? '';
  //       final amount = payment['amount'].toString();
  //       final method = payment['paymentMethod'].toString();
  //       final description = payment['description'].toString();
  //       final reference = payment['referenceNumber'].toString();
  //
  //       return customerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
  //           amount.contains(_searchQuery) ||
  //           method.toLowerCase().contains(_searchQuery.toLowerCase()) ||
  //           description.toLowerCase().contains(_searchQuery.toLowerCase()) ||
  //           reference.toLowerCase().contains(_searchQuery.toLowerCase());
  //     }).toList();
  //
  //     filteredInvoices = filteredInvoices.where((invoice) {
  //       final customerName = invoice['customerName'].toString();
  //       final filledNumber = invoice['filledNumber'].toString();
  //       final reference = invoice['referenceNumber'].toString();
  //       final amount = invoice['grandTotal'].toString();
  //
  //       return customerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
  //           filledNumber.contains(_searchQuery) ||
  //           reference.toLowerCase().contains(_searchQuery.toLowerCase()) ||
  //           amount.contains(_searchQuery);
  //     }).toList();
  //
  //     filteredPurchases = filteredPurchases.where((purchase) {
  //       final vendorName = purchase['vendorName'].toString();
  //       final refNo = purchase['refNo'].toString();
  //       final amount = purchase['grandTotal'].toString();
  //
  //       return vendorName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
  //           refNo.contains(_searchQuery) ||
  //           amount.contains(_searchQuery);
  //     }).toList();
  //
  //     // filteredVendorPayments = filteredVendorPayments.where((payment) {
  //     //   final vendorName = payment['vendorName'].toString();
  //     //   final amount = payment['amount'].toString();
  //     //   final method = payment['method'].toString();
  //     //   final description = payment['description'].toString();
  //     //
  //     //   return vendorName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
  //     //       amount.contains(_searchQuery) ||
  //     //       method.toLowerCase().contains(_searchQuery.toLowerCase()) ||
  //     //       description.toLowerCase().contains(_searchQuery.toLowerCase());
  //     // }).toList();
  //     // Inside the vendor payments search section in _applyFilters()
  //     filteredVendorPayments = filteredVendorPayments.where((payment) {
  //       final vendorName = payment['vendorName'].toString();
  //       final amount = payment['amount'].toString();
  //       final method = payment['method'].toString();
  //       final description = payment['description'].toString();
  //       final chequeNumber = payment['chequeNumber']?.toString() ?? '';
  //       final bankName = payment['bankName']?.toString() ?? '';
  //
  //       return vendorName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
  //           amount.contains(_searchQuery) ||
  //           method.toLowerCase().contains(_searchQuery.toLowerCase()) ||
  //           description.toLowerCase().contains(_searchQuery.toLowerCase()) ||
  //           chequeNumber.toLowerCase().contains(_searchQuery.toLowerCase()) ||
  //           bankName.toLowerCase().contains(_searchQuery.toLowerCase());
  //     }).toList();
  //   }
  //
  //   setState(() {
  //     _filteredPayments = filteredPayments;
  //     _filteredInvoices = filteredInvoices;
  //     _filteredPurchases = filteredPurchases;
  //     _filteredVendorPayments = filteredVendorPayments;
  //   });
  // }

  void _applyFilters() {
    // Apply filters to payments
    List<Map<String, dynamic>> filteredPayments = _allPayments;
    List<Map<String, dynamic>> filteredInvoices = _allInvoices;
    List<Map<String, dynamic>> filteredPurchases = _allPurchases;
    List<Map<String, dynamic>> filteredVendorPayments = _allVendorPayments;

    // Apply date filter
    if (_startDate != null && _endDate != null) {
      filteredPayments = filteredPayments.where((payment) {
        final paymentDate = payment['date'] as DateTime;
        return paymentDate.isAfter(_startDate!.subtract(Duration(seconds: 1))) &&
            paymentDate.isBefore(_endDate!.add(Duration(days: 1)));
      }).toList();

      filteredInvoices = filteredInvoices.where((invoice) {
        final invoiceDate = invoice['date'] as DateTime;
        return invoiceDate.isAfter(_startDate!.subtract(Duration(seconds: 1))) &&
            invoiceDate.isBefore(_endDate!.add(Duration(days: 1)));
      }).toList();

      filteredPurchases = filteredPurchases.where((purchase) {
        final purchaseDate = purchase['date'] as DateTime;
        return purchaseDate.isAfter(_startDate!.subtract(Duration(seconds: 1))) &&
            purchaseDate.isBefore(_endDate!.add(Duration(days: 1)));
      }).toList();

      // UPDATED: For vendor payments, use chequeDate for cheque payments, otherwise use date
      filteredVendorPayments = filteredVendorPayments.where((payment) {
        final method = payment['method'] as String;
        DateTime dateToCompare;

        // For cheque payments, use chequeDate; for other methods, use payment date
        if (method.toLowerCase() == 'cheque' && payment['chequeDate'] != null) {
          dateToCompare = payment['chequeDate'] as DateTime;
        } else {
          dateToCompare = payment['date'] as DateTime;
        }

        return dateToCompare.isAfter(_startDate!.subtract(Duration(seconds: 1))) &&
            dateToCompare.isBefore(_endDate!.add(Duration(days: 1)));
      }).toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filteredPayments = filteredPayments.where((payment) {
        final customerId = payment['customerId'] as String;
        final customerName = _customerNames[customerId] ?? '';
        final amount = payment['amount'].toString();
        final method = payment['paymentMethod'].toString();
        final description = payment['description'].toString();
        final reference = payment['referenceNumber'].toString();

        return customerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            amount.contains(_searchQuery) ||
            method.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            description.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            reference.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();

      filteredInvoices = filteredInvoices.where((invoice) {
        final customerName = invoice['customerName'].toString();
        final filledNumber = invoice['filledNumber'].toString();
        final reference = invoice['referenceNumber'].toString();
        final amount = invoice['grandTotal'].toString();

        return customerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            filledNumber.contains(_searchQuery) ||
            reference.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            amount.contains(_searchQuery);
      }).toList();

      filteredPurchases = filteredPurchases.where((purchase) {
        final vendorName = purchase['vendorName'].toString();
        final refNo = purchase['refNo'].toString();
        final amount = purchase['grandTotal'].toString();

        return vendorName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            refNo.contains(_searchQuery) ||
            amount.contains(_searchQuery);
      }).toList();

      filteredVendorPayments = filteredVendorPayments.where((payment) {
        final vendorName = payment['vendorName'].toString();
        final amount = payment['amount'].toString();
        final method = payment['method'].toString();
        final description = payment['description'].toString();
        final chequeNumber = payment['chequeNumber']?.toString() ?? '';
        final bankName = payment['bankName']?.toString() ?? '';

        return vendorName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            amount.contains(_searchQuery) ||
            method.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            description.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            chequeNumber.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            bankName.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    setState(() {
      _filteredPayments = filteredPayments;
      _filteredInvoices = filteredInvoices;
      _filteredPurchases = filteredPurchases;
      _filteredVendorPayments = filteredVendorPayments;
    });
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    DateTimeRange? pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : DateTimeRange(
        start: DateTime.now().subtract(Duration(days: 30)),
        end: DateTime.now(),
      ),
      helpText: languageProvider.isEnglish ? 'Select Date Range' : 'تاریخ کی حد منتخب کریں',
    );

    if (pickedRange != null) {
      setState(() {
        _startDate = pickedRange.start;
        _endDate = pickedRange.end;
      });
    }
  }

  void _clearDateFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
  }

  void _generateReport() {
    if (_startDate == null || _endDate == null) {
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            languageProvider.isEnglish
                ? 'Please select a date range first'
                : 'پہلے تاریخ کی حد منتخب کریں',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    _fetchData();
  }

  // Build overall summary card
  Widget _buildOverallSummaryCard() {
    final languageProvider = Provider.of<LanguageProvider>(context);

    double filteredInvoiceTotal = _filteredInvoices.fold(0.0, (sum, inv) => sum + (inv['grandTotal'] as double));
    double filteredPaymentTotal = _filteredPayments.fold(0.0, (sum, pay) => sum + (pay['amount'] as double));
    double filteredPurchaseTotal = _filteredPurchases.fold(0.0, (sum, purchase) => sum + (purchase['grandTotal'] as double));
    double filteredVendorPaymentTotal = _filteredVendorPayments.fold(0.0, (sum, payment) => sum + (payment['amount'] as double));

    double netCashFlow = filteredPaymentTotal - filteredVendorPaymentTotal;
    double remainingBalance = filteredInvoiceTotal - filteredPaymentTotal;

    return Card(
      elevation: 4,
      margin: EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.purple, size: 24),
                SizedBox(width: 8),
                Text(
                  languageProvider.isEnglish ? 'Overall Summary' : 'مجموعی خلاصہ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple),
                ),
              ],
            ),
            SizedBox(height: 16),

            // Income (Customer Payments received)
            _buildSummaryRow(
              icon: Icons.payment,
              label: languageProvider.isEnglish ? 'Customer Payments:' : 'کسٹمر کی ادائیگیاں:',
              amount: filteredPaymentTotal,
              color: Colors.green,
            ),

            SizedBox(height: 8),

            // Expenses (Vendor Payments)
            _buildSummaryRow(
              icon: Icons.money_off,
              label: languageProvider.isEnglish ? 'Vendor Payments:' : 'وینڈر کی ادائیگیاں:',
              amount: filteredVendorPaymentTotal,
              color: Colors.red,
            ),

            SizedBox(height: 8),

            // Expenses (Purchases)
            _buildSummaryRow(
              icon: Icons.shopping_cart,
              label: languageProvider.isEnglish ? 'Purchases:' : 'خریداری:',
              amount: filteredPurchaseTotal,
              color: Colors.orange,
            ),

            SizedBox(height: 8),

            // Invoices (Sales)
            _buildSummaryRow(
              icon: Icons.receipt,
              label: languageProvider.isEnglish ? 'Sales Invoices:' : 'فروخت کے بل:',
              amount: filteredInvoiceTotal,
              color: Colors.blue,
            ),

            SizedBox(height: 8),
            Divider(),
            SizedBox(height: 8),

            // Net Cash Flow
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: netCashFlow >= 0 ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: netCashFlow >= 0 ? Colors.green : Colors.red,
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        netCashFlow >= 0 ? Icons.trending_up : Icons.trending_down,
                        color: netCashFlow >= 0 ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        languageProvider.isEnglish ? 'Net Cash Flow:' : 'خالص نقد بہاؤ:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  Text(
                    '${netCashFlow.toStringAsFixed(2)} Rs',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: netCashFlow >= 0 ? Colors.green : Colors.red,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 8),

            // Remaining Balance
            _buildSummaryRow(
              icon: Icons.account_balance_wallet,
              label: languageProvider.isEnglish ? 'Pending Invoices:' : 'زیر التواء بل:',
              amount: remainingBalance,
              color: remainingBalance > 0 ? Colors.orange : Colors.blue,
            ),

            SizedBox(height: 8),

            // Total Records
            // In _buildOverallSummaryCard, update the total records line:
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.list, color: Colors.grey, size: 20),
                    SizedBox(width: 8),
                    Text(
                      languageProvider.isEnglish ? 'Total Records:' : 'کل ریکارڈز:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                Text(
                  '${_filteredPayments.length + _filteredInvoices.length + _filteredPurchases.length + _groupVendorPayments(_filteredVendorPayments).length}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 16),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow({required IconData icon, required String label, required double amount, required Color color}) {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          Text(
            '${amount.toStringAsFixed(2)} Rs',
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersSection() {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Card(
      margin: EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // Date range selector
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      _startDate == null
                          ? languageProvider.isEnglish ? 'Select Date Range' : 'تاریخ منتخب کریں'
                          : '${DateFormat('dd/MM/yy').format(_startDate!)} - ${DateFormat('dd/MM/yy').format(_endDate!)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => _selectDateRange(context),
                  ),
                ),
                if (_startDate != null)
                  IconButton(
                    icon: Icon(Icons.clear, color: Colors.red),
                    onPressed: _clearDateFilter,
                    tooltip: languageProvider.isEnglish ? 'Clear date filter' : 'تاریخ فلٹر صاف کریں',
                  ),
              ],
            ),

            SizedBox(height: 12),

            // Generate Report button
            ElevatedButton.icon(
              icon: Icon(Icons.analytics),
              label: Text(languageProvider.isEnglish ? 'Generate Report' : 'رپورٹ بنائیں'),
              onPressed: _generateReport,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                minimumSize: Size(double.infinity, 45),
              ),
            ),

            if (_filteredPayments.isNotEmpty ||
                _filteredInvoices.isNotEmpty ||
                _filteredPurchases.isNotEmpty ||
                _filteredVendorPayments.isNotEmpty) ...[
              SizedBox(height: 12),

              // Search bar (only show after report is generated)
              TextField(
                decoration: InputDecoration(
                  labelText: languageProvider.isEnglish ? 'Search Transactions' : 'لین دین تلاش کریں',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  suffixIcon: _searchQuery.isNotEmpty ? IconButton(
                    icon: Icon(Icons.clear),
                    onPressed: () {
                      setState(() => _searchQuery = '');
                      _applyFilters();
                    },
                  ) : null,
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                  _applyFilters();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              isScrollable: true,
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.blue,
              tabs: [
                Tab(
                  icon: Icon(Icons.dashboard),
                  text: languageProvider.isEnglish ? 'All' : 'سب',
                ),
                Tab(
                  icon: Icon(Icons.payment),
                  text: languageProvider.isEnglish ? 'Cust. Payments' : 'کسٹمر ادائیگیاں',
                ),
                Tab(
                  icon: Icon(Icons.receipt),
                  text: languageProvider.isEnglish ? 'Invoices' : 'بل',
                ),
                Tab(
                  icon: Icon(Icons.shopping_cart),
                  text: languageProvider.isEnglish ? 'Purchases' : 'خریداری',
                ),
                Tab(
                  icon: Icon(Icons.money_off),
                  text: languageProvider.isEnglish ? 'Vendor Payments' : 'وینڈر ادائیگیاں',
                ),
              ],
              onTap: (index) {
                setState(() {
                  _selectedTab = index;
                });
              },
            ),
          ),
          SizedBox(height: 8),
          _buildSelectedTabContent(),
        ],
      ),
    );
  }

  Widget _buildSelectedTabContent() {
    switch (_selectedTab) {
      case 0: // All
        return _buildAllTransactionsList();
      case 1: // Customer Payments
        return _buildPaymentsList();
      case 2: // Invoices
        return _buildInvoicesList();
      case 3: // Purchases
        return _buildPurchasesList();
      case 4: // Vendor Payments
        return _buildVendorPaymentsList();
      default:
        return _buildAllTransactionsList();
    }
  }

  Widget _buildAllTransactionsList() {
    final languageProvider = Provider.of<LanguageProvider>(context);

    // For vendor payments, we'll show grouped
    final groupedVendorPayments = _groupVendorPayments(_filteredVendorPayments);

    // Combine other transactions
    List<Map<String, dynamic>> otherTransactions = [
      ..._filteredPayments.map((p) => {...p, 'transactionType': 'Customer Payment'}),
      ..._filteredInvoices.map((i) => {...i, 'transactionType': 'Invoice'}),
      ..._filteredPurchases.map((p) => {...p, 'transactionType': 'Purchase'}),
    ];

    otherTransactions.sort((a, b) => b['date'].compareTo(a['date']));

    if (otherTransactions.isEmpty && groupedVendorPayments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                languageProvider.isEnglish
                    ? 'No transactions found. Click "Generate Report" to view data.'
                    : 'کوئی لین دین نہیں ملا۔ ڈیٹا دیکھنے کے لیے "رپورٹ بنائیں" پر کلک کریں۔',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: otherTransactions.length + groupedVendorPayments.length,
      itemBuilder: (context, index) {
        // First show all grouped vendor payments
        if (index < groupedVendorPayments.length) {
          final vendorName = groupedVendorPayments.keys.elementAt(index);
          final vendorPayments = groupedVendorPayments[vendorName]!;
          return _buildVendorGroupCard(vendorName, vendorPayments);
        }

        // Then show other transactions
        final transactionIndex = index - groupedVendorPayments.length;
        final transaction = otherTransactions[transactionIndex];
        final type = transaction['transactionType'] as String;

        switch (type) {
          case 'Customer Payment':
            return _buildPaymentCard(transaction);
          case 'Invoice':
            return _buildInvoiceCard(transaction);
          case 'Purchase':
            return _buildPurchaseCard(transaction);
          default:
            return Container();
        }
      },
    );
  }


  Widget _buildVendorPaymentCard(Map<String, dynamic> payment) {
    final vendorName = payment['vendorName'] as String;
    final paymentDate = payment['date'] as DateTime;
    final amount = payment['amount'] as double;
    final method = payment['method'] as String;
    final chequeDate = payment['chequeDate'] as DateTime?;
    final isCheque = method.toLowerCase() == 'cheque';

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.red.withOpacity(0.2),
          child: Icon(
            isCheque ? Icons.account_balance_wallet : Icons.money_off,
            color: Colors.red,
          ),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                vendorName,
                style: TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isCheque ? 'Cheque Payment' : 'Vendor Payment',
                style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 12, color: Colors.grey),
                SizedBox(width: 4),
                Text(
                  DateFormat('dd/MM/yyyy - HH:mm').format(paymentDate),
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),

            if (isCheque && chequeDate != null) ...[
              SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.calendar_month, size: 12, color: Colors.blue),
                  SizedBox(width: 4),
                  Text(
                    'Cheque Date: ${DateFormat('dd/MM/yyyy').format(chequeDate)}',
                    style: TextStyle(fontSize: 11, color: Colors.blue),
                  ),
                ],
              ),
            ],

            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: isCheque ? Colors.blue.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isCheque ? Colors.blue : Colors.red,
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    method,
                    style: TextStyle(
                      fontSize: 10,
                      color: isCheque ? Colors.blue : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '${amount.toStringAsFixed(2)} Rs',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => _showVendorPaymentDetails(payment),
      ),
    );
  }

  Widget _buildPaymentCard(Map<String, dynamic> payment) {
    final customerId = payment['customerId'] as String;
    final customerName = _customerNames[customerId] ?? payment['customerId'];
    final paymentDate = payment['date'] as DateTime;
    final amount = payment['amount'] as double;
    final method = payment['paymentMethod'] as String;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.withOpacity(0.2),
          child: Icon(Icons.payment, color: Colors.green),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                customerName,
                style: TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Customer Payment',
                style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 12, color: Colors.grey),
                SizedBox(width: 4),
                Text(
                  DateFormat('dd/MM/yyyy - HH:mm').format(paymentDate),
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  method,
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
                ),
                Text(
                  '${amount.toStringAsFixed(2)} Rs',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => _showPaymentDetails(payment, customerName),
      ),
    );
  }

  Widget _buildInvoiceCard(Map<String, dynamic> invoice) {
    final customerName = invoice['customerName'] as String;
    final invoiceDate = invoice['date'] as DateTime;
    final amount = invoice['grandTotal'] as double;
    final filledNumber = invoice['filledNumber'] as String;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withOpacity(0.2),
          child: Icon(Icons.receipt, color: Colors.blue),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                customerName,
                style: TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Invoice',
                style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 12, color: Colors.grey),
                SizedBox(width: 4),
                Text(
                  DateFormat('dd/MM/yyyy - HH:mm').format(invoiceDate),
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (filledNumber.isNotEmpty)
                  Text(
                    'Invoice #$filledNumber',
                    style: TextStyle(color: Colors.blueGrey, fontSize: 11),
                  ),
                Text(
                  '${amount.toStringAsFixed(2)} Rs',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => _showInvoiceDetails(invoice),
      ),
    );
  }

  Widget _buildPurchaseCard(Map<String, dynamic> purchase) {
    final vendorName = purchase['vendorName'] as String;
    final purchaseDate = purchase['date'] as DateTime;
    final amount = purchase['grandTotal'] as double;
    final refNo = purchase['refNo'] as String;
    final totalItems = purchase['totalItems'] as int;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.withOpacity(0.2),
          child: Icon(Icons.shopping_cart, color: Colors.orange),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                vendorName,
                style: TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Purchase',
                style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 12, color: Colors.grey),
                SizedBox(width: 4),
                Text(
                  DateFormat('dd/MM/yyyy - HH:mm').format(purchaseDate),
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (refNo.isNotEmpty)
                      Text(
                        'Ref: $refNo',
                        style: TextStyle(color: Colors.blueGrey, fontSize: 11),
                      ),
                    Text(
                      '$totalItems items',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
                Text(
                  '${amount.toStringAsFixed(2)} Rs',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => _showPurchaseDetails(purchase),
      ),
    );
  }

  Widget _buildPaymentsList() {
    final languageProvider = Provider.of<LanguageProvider>(context);

    if (_filteredPayments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.payment, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                languageProvider.isEnglish
                    ? 'No customer payments found'
                    : 'کوئی کسٹمر ادائیگی نہیں ملی',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: _filteredPayments.length,
      itemBuilder: (context, index) {
        final payment = _filteredPayments[index];
        return _buildPaymentCard(payment);
      },
    );
  }

  Widget _buildInvoicesList() {
    final languageProvider = Provider.of<LanguageProvider>(context);

    if (_filteredInvoices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                languageProvider.isEnglish
                    ? 'No invoices found'
                    : 'کوئی بل نہیں ملا',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: _filteredInvoices.length,
      itemBuilder: (context, index) {
        final invoice = _filteredInvoices[index];
        return _buildInvoiceCard(invoice);
      },
    );
  }

  Widget _buildPurchasesList() {
    final languageProvider = Provider.of<LanguageProvider>(context);

    if (_filteredPurchases.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shopping_cart, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                languageProvider.isEnglish
                    ? 'No purchases found'
                    : 'کوئی خریداری نہیں ملی',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: _filteredPurchases.length,
      itemBuilder: (context, index) {
        final purchase = _filteredPurchases[index];
        return _buildPurchaseCard(purchase);
      },
    );
  }

  void _showVendorPaymentDetails(Map<String, dynamic> payment) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final vendorName = payment['vendorName'] as String;
    final date = payment['date'] as DateTime;
    final amount = payment['amount'] as double;
    final method = payment['method'] as String;
    final description = payment['description'] as String;
    final bankName = payment['bankName'] as String?;
    final chequeNumber = payment['chequeNumber'] as String?;
    final chequeStatus = payment['chequeStatus'] as String?;
    final chequeDate = payment['chequeDate'] as DateTime?;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(languageProvider.isEnglish ? 'Vendor Payment Details' : 'وینڈر ادائیگی کی تفصیلات'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow(Icons.store, languageProvider.isEnglish ? 'Vendor' : 'وینڈر', vendorName),
              _buildDetailRow(Icons.money, languageProvider.isEnglish ? 'Amount' : 'رقم', '${amount.toStringAsFixed(2)} Rs'),
              _buildDetailRow(Icons.date_range, languageProvider.isEnglish ? 'Date & Time' : 'تاریخ اور وقت', DateFormat('dd/MM/yyyy - HH:mm').format(date)),
              _buildDetailRow(Icons.payment, languageProvider.isEnglish ? 'Payment Method' : 'ادائیگی کا طریقہ', method),

              if (method.toLowerCase() == 'cheque') ...[
                if (chequeDate != null)
                  _buildDetailRow(Icons.calendar_today, languageProvider.isEnglish ? 'Cheque Date' : 'چیک کی تاریخ', DateFormat('dd/MM/yyyy').format(chequeDate)),

                if (bankName != null && bankName.isNotEmpty)
                  _buildDetailRow(Icons.account_balance, languageProvider.isEnglish ? 'Bank Name' : 'بینک کا نام', bankName),

                if (chequeNumber != null && chequeNumber.isNotEmpty)
                  _buildDetailRow(Icons.numbers, languageProvider.isEnglish ? 'Cheque Number' : 'چیک نمبر', chequeNumber),

                if (chequeStatus != null)
                  _buildDetailRow(
                      Icons.info,
                      languageProvider.isEnglish ? 'Cheque Status' : 'چیک کی حالت',
                      chequeStatus,
                      color: chequeStatus.toLowerCase() == 'cleared' ? Colors.green : Colors.orange
                  ),
              ],

              if (description.isNotEmpty)
                _buildDetailRow(Icons.description, languageProvider.isEnglish ? 'Description' : 'تفصیل', description),
            ],
          ),
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

  void _showPaymentDetails(Map<String, dynamic> payment, String customerName) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final date = payment['date'] as DateTime;
    final amount = payment['amount'] as double;
    final method = payment['paymentMethod'] as String;
    final bankName = payment['bankName'] as String?;
    final chequeNo = payment['chequeNumber'] as String?;
    final description = payment['description'] as String;
    final reference = payment['referenceNumber'] as String;
    final filledNumber = payment['filledNumber'] as String;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(languageProvider.isEnglish ? 'Payment Details' : 'ادائیگی کی تفصیلات'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow(Icons.person, languageProvider.isEnglish ? 'Customer' : 'کسٹمر', customerName),
              _buildDetailRow(Icons.money, languageProvider.isEnglish ? 'Amount' : 'رقم', '${amount.toStringAsFixed(2)} Rs'),
              _buildDetailRow(Icons.date_range, languageProvider.isEnglish ? 'Date & Time' : 'تاریخ اور وقت', DateFormat('dd/MM/yyyy - HH:mm').format(date)),
              _buildDetailRow(Icons.payment, languageProvider.isEnglish ? 'Payment Method' : 'ادائیگی کا طریقہ', method),

              if (bankName != null)
                _buildDetailRow(Icons.account_balance, languageProvider.isEnglish ? 'Bank Name' : 'بینک کا نام', bankName),

              if (chequeNo != null)
                _buildDetailRow(Icons.description, languageProvider.isEnglish ? 'Cheque Number' : 'چیک نمبر', chequeNo),

              if (reference.isNotEmpty)
                _buildDetailRow(Icons.receipt, languageProvider.isEnglish ? 'Reference Number' : 'حوالہ نمبر', reference),

              if (filledNumber.isNotEmpty)
                _buildDetailRow(Icons.list_alt, languageProvider.isEnglish ? 'Filled Number' : 'فِلڈ نمبر', filledNumber),

              if (description.isNotEmpty)
                _buildDetailRow(Icons.description, languageProvider.isEnglish ? 'Description' : 'تفصیل', description),
            ],
          ),
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

  void _showInvoiceDetails(Map<String, dynamic> invoice) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final customerName = invoice['customerName'] as String;
    final date = invoice['date'] as DateTime;
    final grandTotal = invoice['grandTotal'] as double;
    final subtotal = invoice['subtotal'] as double;
    final discount = invoice['discount'] as double;
    final filledNumber = invoice['filledNumber'] as String;
    final reference = invoice['referenceNumber'] as String;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(languageProvider.isEnglish ? 'Invoice Details' : 'بل کی تفصیلات'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow(Icons.person, languageProvider.isEnglish ? 'Customer' : 'کسٹمر', customerName),
              _buildDetailRow(Icons.receipt, languageProvider.isEnglish ? 'Invoice Number' : 'بل نمبر', filledNumber),
              _buildDetailRow(Icons.date_range, languageProvider.isEnglish ? 'Date & Time' : 'تاریخ اور وقت', DateFormat('dd/MM/yyyy - HH:mm').format(date)),
              _buildDetailRow(Icons.money, languageProvider.isEnglish ? 'Subtotal' : 'ذیلی کل', '${subtotal.toStringAsFixed(2)} Rs'),
              _buildDetailRow(Icons.discount, languageProvider.isEnglish ? 'Discount' : 'ڈسکاؤنٹ', '${discount.toStringAsFixed(2)} Rs'),
              _buildDetailRow(Icons.attach_money, languageProvider.isEnglish ? 'Grand Total' : 'کل رقم', '${grandTotal.toStringAsFixed(2)} Rs'),

              if (reference.isNotEmpty)
                _buildDetailRow(Icons.receipt, languageProvider.isEnglish ? 'Reference Number' : 'حوالہ نمبر', reference),
            ],
          ),
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

  void _showPurchaseDetails(Map<String, dynamic> purchase) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final vendorName = purchase['vendorName'] as String;
    final date = purchase['date'] as DateTime;
    final grandTotal = purchase['grandTotal'] as double;
    final refNo = purchase['refNo'] as String;
    final totalItems = purchase['totalItems'] as int;
    final items = purchase['items'] as List<dynamic>?;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(languageProvider.isEnglish ? 'Purchase Details' : 'خریداری کی تفصیلات'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow(Icons.store, languageProvider.isEnglish ? 'Vendor' : 'فروش', vendorName),
              _buildDetailRow(Icons.date_range, languageProvider.isEnglish ? 'Date & Time' : 'تاریخ اور وقت', DateFormat('dd/MM/yyyy - HH:mm').format(date)),
              _buildDetailRow(Icons.money, languageProvider.isEnglish ? 'Total Amount' : 'کل رقم', '${grandTotal.toStringAsFixed(2)} Rs'),
              _buildDetailRow(Icons.receipt, languageProvider.isEnglish ? 'Reference No' : 'ریفیرنس نمبر', refNo.isNotEmpty ? refNo : 'N/A'),
              _buildDetailRow(Icons.list, languageProvider.isEnglish ? 'Total Items' : 'کل آئٹمز', totalItems.toString()),

              SizedBox(height: 16),
              Divider(),
              Text(
                languageProvider.isEnglish ? 'Purchased Items:' : 'خریدے گئے آئٹمز:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 8),

              if (items != null && items.isNotEmpty)
                ...items.asMap().entries.map((entry) {
                  final item = entry.value as Map<dynamic, dynamic>;
                  final index = entry.key;
                  final itemName = item['itemName']?.toString() ?? 'Unknown Item';
                  final quantity = item['quantity']?.toString() ?? '0';
                  final price = item['purchasePrice']?.toString() ?? '0';
                  final total = (double.tryParse(quantity) ?? 0) * (double.tryParse(price) ?? 0);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${index + 1}. $itemName',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        Text(
                          '${total.toStringAsFixed(2)} Rs',
                          style: TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ],
                    ),
                  );
                }).toList()
              else
                Text(
                  languageProvider.isEnglish ? 'No items details available' : 'آئٹمز کی تفصیلات دستیاب نہیں',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
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

  Widget _buildDetailRow(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color ?? Colors.blue),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                ),
                Text(
                  value,
                  style: TextStyle(fontSize: 14, color: color ?? Colors.black),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          languageProvider.isEnglish ? 'All Transactions' : 'تمام لین دین',
          style: TextStyle(color: Colors.white),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1976D2), Color(0xFF64B5F6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          if (_filteredPayments.isNotEmpty ||
              _filteredInvoices.isNotEmpty ||
              _filteredPurchases.isNotEmpty ||
              _filteredVendorPayments.isNotEmpty)
            IconButton(
              icon: Icon(Icons.picture_as_pdf),
              onPressed: _isLoading ? null : () => _showPdfOptionsDialog(),
              tooltip: languageProvider.isEnglish ? 'Generate PDF Report' : 'PDF رپورٹ بنائیں',
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Filters section
            _buildFiltersSection(),
            // Add PDF button below filters
            if (_filteredPayments.isNotEmpty ||
                _filteredInvoices.isNotEmpty ||
                _filteredPurchases.isNotEmpty ||
                _filteredVendorPayments.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: _buildPdfButton(),
              ),
              SizedBox(height: 8),
            ],
            // Show summary and data only after report is generated
            if (_filteredPayments.isNotEmpty ||
                _filteredInvoices.isNotEmpty ||
                _filteredPurchases.isNotEmpty ||
                _filteredVendorPayments.isNotEmpty) ...[
              // Overall summary card
              _buildOverallSummaryCard(),

              // Tabs for different transaction types
              _buildTabs(),
            ],

            // Space at the bottom
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}