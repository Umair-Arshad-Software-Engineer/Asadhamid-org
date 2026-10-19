import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
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
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:js_interop';

// Shared Mughal Group PDF design — same one used by ItemPurchasePage.
import '../Purchase/pdf_branding.dart';

// Web-only clipboard helpers (same as ItemPurchasePage)
@JS('copyPngToClipboard')
external JSPromise<JSBoolean> _copyPngToClipboardJs(JSString base64Png);

@JS('sharePngWithText')
external JSPromise<JSBoolean> _sharePngWithTextJs(
    JSString base64Png, JSString text, JSString fileName);

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
    required this.customerCity,
  }) : super(key: key);

  @override
  State<FilledLedgerReportPage> createState() => _FilledLedgerReportPageState();
}

class _FilledLedgerReportPageState extends State<FilledLedgerReportPage> {
  DateTimeRange? selectedDateRange;
  static final Map<String, String> _bankIconMap = _createBankIconMap();

  // ═══════════════════════════════════════════════════════════════════
  // WhatsApp sharing helpers
  // ═══════════════════════════════════════════════════════════════════

  String? _normalizePkNumber(String raw) {
    if (raw.trim().isEmpty) return null;
    var n = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (n.startsWith('+')) n = n.substring(1);
    if (n.startsWith('00')) n = n.substring(2);
    if (n.startsWith('0')) n = '92${n.substring(1)}';
    if (n.startsWith('92') && n.length == 12) return n;
    return null;
  }

  Future<bool> _isWhatsAppAvailable(String number) async {
    if (kIsWeb) return true;
    try {
      return await canLaunchUrl(Uri.parse('whatsapp://send?phone=$number'));
    } catch (_) {
      return false;
    }
  }

  Future<bool> _copyImageToClipboard(Uint8List png) async {
    if (!kIsWeb) return false;
    try {
      final r = await _copyPngToClipboardJs(base64Encode(png).toJS).toDart;
      return r.toDart;
    } catch (e) {
      debugPrint('Clipboard copy failed: $e');
      return false;
    }
  }

  Future<bool> _shareImageWithText(
      Uint8List png, String text, String fileName) async {
    if (kIsWeb) {
      try {
        final r = await _sharePngWithTextJs(
            base64Encode(png).toJS, text.toJS, fileName.toJS)
            .toDart;
        return r.toDart;
      } catch (e) {
        debugPrint('Web share failed: $e');
        return false;
      }
    }
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(png);
      await Share.shareXFiles([XFile(file.path)], text: text);
      return true;
    } catch (e) {
      debugPrint('Share failed: $e');
      return false;
    }
  }

  Future<void> _sendWhatsAppTextOnly(String number, String message) async {
    final link =
        'whatsapp://send?phone=$number&text=${Uri.encodeComponent(message)}';
    if (kIsWeb) {
      final a = html.AnchorElement(href: link)
        ..target = '_self'
        ..style.display = 'none';
      html.document.body?.append(a);
      a.click();
      a.remove();
    } else {
      await launchUrl(Uri.parse(link),
          mode: LaunchMode.externalApplication);
    }
  }

  /// Builds the branded PDF, extracts page 1 as a PNG, then shows a chooser
  /// so the user can send text / PDF / image.
  Future<void> _sharePDFOnWhatsApp(
      FilledCustomerReportProvider provider,
      LanguageProvider languageProvider,
      ) async {
    final number = _normalizePkNumber(widget.customerPhone);
    if (number == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(languageProvider.isEnglish
              ? 'No valid WhatsApp number on file for this customer.'
              : 'اس کسٹمر کا درست واٹس ایپ نمبر موجود نہیں۔'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!await _isWhatsAppAvailable(number)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(languageProvider.isEnglish
              ? 'WhatsApp is not available on this device.'
              : 'اس ڈیوائس پر واٹس ایپ دستیاب نہیں۔'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 1. Build the PDF
    final pdf = await _buildLedgerPdf(provider, languageProvider);
    if (pdf == null) return;
    final bytes = await pdf.save();

    // 2. Rasterize page 1 → PNG (preview used on web)
    Uint8List? pngBytes;
    try {
      await for (final page in Printing.raster(bytes, pages: [0], dpi: 110)) {
        pngBytes = await page.toPng();
        break;
      }
    } catch (e) {
      debugPrint('Raster failed: $e');
    }

    // 3. Compose the message
    final closing = provider.report['balance']?.toDouble() ?? 0.0;
    final periodText = provider.isFiltered && provider.dateRangeFilter != null
        ? '${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.start)}'
        ' – '
        '${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.end)}'
        : 'All Transactions';

    final message = 'Assalam o Alaikum ${widget.customerName},\n'
        'Aap ka ledger statement attached hai.\n'
        'Period: $periodText\n'
        'Closing Balance: Rs ${closing.toStringAsFixed(2)}\n'
        '${DateFormat('dd/MM/yyyy').format(DateTime.now())}\n'
        'Mughal Group of Industries';

    final safeName =
    widget.customerName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileBase = 'Customer_Ledger_${safeName}_$stamp';

    // 4. Chooser
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(languageProvider.isEnglish
            ? 'Send on WhatsApp'
            : 'واٹس ایپ پر بھیجیں'),
        content: Text(languageProvider.isEnglish
            ? 'How would you like to send this statement to '
            '${widget.customerName} (${widget.customerPhone})?'
            : '${widget.customerName} (${widget.customerPhone}) کو یہ اسٹیٹمنٹ کیسے بھیجیں؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.message, size: 18),
            label: Text(languageProvider.isEnglish ? 'Text' : 'پیغام'),
            onPressed: () async {
              Navigator.pop(ctx);
              await _sendWhatsAppTextOnly(number, message);
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: Text(languageProvider.isEnglish ? 'PDF file' : 'پی ڈی ایف'),
            onPressed: () async {
              Navigator.pop(ctx);
              await Printing.sharePdf(
                bytes: bytes,
                filename: '$fileBase.pdf',
              );
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.image, size: 18),
            label: Text(languageProvider.isEnglish
                ? 'Image + Message'
                : 'تصویر + پیغام'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white),
            onPressed: pngBytes == null
                ? null
                : () async {
              Navigator.pop(ctx);
              if (kIsWeb) {
                final copied =
                await _copyImageToClipboard(pngBytes!);
                await _sendWhatsAppTextOnly(number, message);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(copied
                        ? (languageProvider.isEnglish
                        ? 'Image copied. Press Ctrl+V in the chat.'
                        : 'تصویر کاپی ہو گئی۔ چیٹ میں Ctrl+V دبائیں۔')
                        : (languageProvider.isEnglish
                        ? 'Could not copy the image. Use PDF file option.'
                        : 'تصویر کاپی نہیں ہو سکی۔ پی ڈی ایف آپشن استعمال کریں۔')),
                  ),
                );
              } else {
                final ok = await _shareImageWithText(
                    pngBytes!, message, '$fileBase.png');
                if (!ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(languageProvider.isEnglish
                          ? 'Sharing not supported here. Use PDF file.'
                          : 'یہاں شیئرنگ دستیاب نہیں۔ پی ڈی ایف استعمال کریں۔'),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // PDF builder — Mughal Group branded (same as ItemPurchasePage)
  // ═══════════════════════════════════════════════════════════════════
  Future<pw.Document?> _buildLedgerPdf(
      FilledCustomerReportProvider provider,
      LanguageProvider languageProvider,
      ) async {
    try {
      await PdfBranding.ensureAssets();

      final pdf = pw.Document();
      final openingBalance = provider.openingBalance ?? 0;
      final transactions = provider.transactions ?? [];

      final openingBalanceDisplay = provider.displayOpeningBalance;
      final DateTime? openingBalanceDate = provider.displayOpeningBalanceDate;

      final double totalDebit =
          provider.report['debit']?.toDouble() ?? 0.0;
      final double totalCredit =
          openingBalanceDisplay + (provider.report['credit']?.toDouble() ?? 0.0);
      final double finalBalance =
          provider.report['balance']?.toDouble() ?? 0.0;
      final double displayFinalBalance =
      provider.isFiltered && provider.transactions.isEmpty
          ? 0.0
          : finalBalance;

      // ──────────────── Urdu-safe text images ────────────────
      final Map<String, pw.MemoryImage> customerImgs = {};
      final Map<String, pw.MemoryImage> itemNameImgs = {};
      final Map<String, pw.MemoryImage> lengthImgs = {};
      final Map<String, pw.MemoryImage> descImgs = {};
      final jobs = <Future<void>>[];

      void queue(Map<String, pw.MemoryImage> target, String text,
          double fs, double w, double h) {
        if (!PdfBranding.needsImage(text) || target.containsKey(text)) return;
        jobs.add(PdfBranding.textImage(text,
            fontSize: fs, width: w, height: h)
            .then((img) => target[text] = img));
      }

      // Customer / address / city — usually Latin, but handle Urdu too.
      queue(customerImgs, widget.customerName.trim(), 42, 165 * 3, 66);
      queue(customerImgs, widget.customerAddress.trim(), 12, 165 * 3, 20);
      queue(customerImgs, widget.customerCity.trim(), 12, 165 * 3, 20);

      // Items (only if expanded) — mirror the existing render logic.
      for (var t in transactions) {
        final key = t['key']?.toString() ?? '';
        final isInvoice = (t['credit'] ?? 0) != 0;
        final isExpanded = provider.expandedTransactions.contains(key);
        if (isInvoice && isExpanded) {
          final items = provider.invoiceItems[key] ?? [];
          for (final it in items) {
            final name = it['itemName']?.toString() ?? '';
            if (name.isNotEmpty) queue(itemNameImgs, name, 42, 228, 66);
            final len = it['length']?.toString() ?? '';
            if (len.isNotEmpty) queue(lengthImgs, len, 42, 201, 66);
            final desc = it['description']?.toString() ?? '';
            if (desc.isNotEmpty) queue(descImgs, desc, 11, 160, 20);
          }
        }
      }

      await Future.wait(jobs);

      // ──────────────── Section: CUSTOMER DETAILS ────────────────
      pw.Widget customerSection() {
        final nameImg = customerImgs[widget.customerName.trim()];
        final addrImg = customerImgs[widget.customerAddress.trim()];
        final cityImg = customerImgs[widget.customerCity.trim()];

        return pw.Column(children: [
          PdfBranding.sectionHeader('CUSTOMER DETAILS'),
          PdfBranding.sectionBody(pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                    child: pw.Column(children: [
                      PdfBranding.field('Customer Name',
                          img: nameImg, text: widget.customerName),
                      PdfBranding.field('Phone Number',
                          text: widget.customerPhone.isEmpty
                              ? '-'
                              : widget.customerPhone),
                    ])),
                pw.SizedBox(width: 18),
                pw.Expanded(
                    child: pw.Column(children: [
                      PdfBranding.field('Address',
                          img: addrImg,
                          text: widget.customerAddress.isEmpty
                              ? '-'
                              : widget.customerAddress),
                      PdfBranding.field('City',
                          img: cityImg,
                          text: widget.customerCity.isEmpty
                              ? '-'
                              : widget.customerCity),
                    ])),
              ])),
        ]);
      }

      // ──────────────── Product-style transaction table ────────────────
      // Column widths match the purchase page (No./Size/Length/Body/Desc/
      // Rate/Qty/Amount style) so the visual footprint is identical.
      pw.Widget transactionSection() {
        // Header row
        final headers = [
          'Date',
          'Invoice No',
          'Ref No',
          'Details',
          'Type',
          'Payment',
          'Bank',
          'Debit',
          'Credit',
          'Balance',
        ];

        // Sort transactions chronologically
        final sorted = List<Map<String, dynamic>>.from(transactions);
        sorted.sort((a, b) {
          final da = DateTime.tryParse(a['date']?.toString() ?? '') ??
              DateTime(2000);
          final db = DateTime.tryParse(b['date']?.toString() ?? '') ??
              DateTime(2000);
          return da.compareTo(db);
        });

        final rows = <pw.TableRow>[];

        // Opening balance (if present, before transactions)
        bool openingAdded = false;
        if ((openingBalanceDisplay != 0 || !provider.isFiltered) &&
            openingBalanceDate != null) {
          if (sorted.isEmpty ||
              openingBalanceDate.isBefore(
                  DateTime.tryParse(sorted.first['date']?.toString() ?? '') ??
                      DateTime(2000))) {
            rows.add(_openingBalanceTableRow(
                provider, languageProvider, openingBalanceDisplay));
            openingAdded = true;
          }
        }

        for (var t in sorted) {
          final date = DateTime.tryParse(t['date']?.toString() ?? '') ??
              DateTime(2000);

          if (!openingAdded &&
              openingBalanceDate != null &&
              openingBalanceDate.isBefore(date) &&
              (openingBalanceDisplay != 0 || !provider.isFiltered)) {
            rows.add(_openingBalanceTableRow(
                provider, languageProvider, openingBalanceDisplay));
            openingAdded = true;
          }

          final details = t['details']?.toString() ??
              t['referenceNumber']?.toString() ??
              t['filledNumber']?.toString() ??
              '-';
          final isInvoice = (t['credit'] ?? 0) != 0;
          final type =
          isInvoice ? 'Invoice' : 'Payment';
          final paymentMethod = _getPaymentMethodText(
              t['paymentMethod']?.toString() ?? '-', languageProvider);
          final bankName = _getBankName(t);
          final debit = (t['debit'] ?? 0).toDouble();
          final credit = (t['credit'] ?? 0).toDouble();
          final balance = (t['balance'] ?? 0).toDouble();

          rows.add(pw.TableRow(
            decoration: pw.BoxDecoration(
                color: rows.length.isEven
                    ? PdfColors.white
                    : PdfBranding.softBg),
            children: [
              PdfBranding.cell(DateFormat('dd MMM yyyy').format(date)),
              PdfBranding.cell(
                  t['invoiceNumber']?.toString() ??
                      t['filledNumber']?.toString() ??
                      '-',
                  bold: true),
              PdfBranding.cell(t['referenceNumber']?.toString() ?? '-'),
              PdfBranding.cell(details),
              PdfBranding.cell(type),
              PdfBranding.cell(paymentMethod),
              PdfBranding.cell(bankName ?? '-'),
              PdfBranding.cell(
                  debit > 0 ? 'Rs ${debit.toStringAsFixed(2)}' : '-'),
              PdfBranding.cell(
                  credit > 0 ? 'Rs ${credit.toStringAsFixed(2)}' : '-'),
              PdfBranding.cell('Rs ${balance.toStringAsFixed(2)}',
                  bold: true),
            ],
          ));

          // Invoice items sub-table (expanded)
          final key = t['key']?.toString() ?? '';
          final isExpanded =
          provider.expandedTransactions.contains(key);
          if (isInvoice && isExpanded) {
            final items = provider.invoiceItems[key] ?? [];
            if (items.isNotEmpty) {
              rows.add(pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(
                        left: 12, top: 4, bottom: 4, right: 12),
                    child: _invoiceItemsSubTable(
                        items,
                        itemNameImgs,
                        lengthImgs,
                        descImgs,
                        languageProvider),
                  ),
                  for (int k = 0; k < headers.length - 1; k++)
                    pw.SizedBox(),
                ],
              ));
            }
          }
        }

        // Opening balance at end (fallback)
        if (!openingAdded &&
            (openingBalanceDisplay != 0 || !provider.isFiltered) &&
            openingBalanceDate != null) {
          rows.add(_openingBalanceTableRow(
              provider, languageProvider, openingBalanceDisplay));
        }

        // Totals row
        rows.add(pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfBranding.orange),
          children: [
            PdfBranding.headCell('TOTALS'),
            PdfBranding.headCell(''),
            PdfBranding.headCell(''),
            PdfBranding.headCell(''),
            PdfBranding.headCell(''),
            PdfBranding.headCell(''),
            PdfBranding.headCell(''),
            PdfBranding.headCell(
                'Rs ${totalDebit.toStringAsFixed(2)}'),
            PdfBranding.headCell(
                'Rs ${totalCredit.toStringAsFixed(2)}'),
            PdfBranding.headCell(
                'Rs ${displayFinalBalance.toStringAsFixed(2)}'),
          ],
        ));

        return pw.Column(children: [
          PdfBranding.sectionHeader('TRANSACTION DETAILS'),
          pw.Table(
            border: pw.TableBorder(
              left: pw.BorderSide(color: PdfBranding.navy, width: 0.8),
              right: pw.BorderSide(color: PdfBranding.navy, width: 0.8),
              bottom: pw.BorderSide(color: PdfBranding.navy, width: 0.8),
              horizontalInside:
              pw.BorderSide(color: PdfBranding.softLine, width: 0.4),
              verticalInside:
              pw.BorderSide(color: PdfBranding.softLine, width: 0.4),
            ),
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: pw.FlexColumnWidth(1.3), // Date
              1: pw.FlexColumnWidth(1.1), // Invoice No
              2: pw.FlexColumnWidth(1.0), // Ref No
              3: pw.FlexColumnWidth(1.6), // Details
              4: pw.FlexColumnWidth(0.9), // Type
              5: pw.FlexColumnWidth(1.1), // Payment
              6: pw.FlexColumnWidth(1.1), // Bank
              7: pw.FlexColumnWidth(1.1), // Debit
              8: pw.FlexColumnWidth(1.1), // Credit
              9: pw.FlexColumnWidth(1.2), // Balance
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfBranding.navy),
                children: headers.map(PdfBranding.headCell).toList(),
              ),
              ...rows,
            ],
          ),
        ]);
      }

      // ──────────────── Summary boxes ────────────────
      pw.Widget summaryBox() => PdfBranding.framed(pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            PdfBranding.boxTitle('STATEMENT SUMMARY'),
            pw.SizedBox(height: 6),
            pw.Expanded(
              child: pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 8),
                color: PdfBranding.softBg,
                child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      PdfBranding.sumRow(
                          'Total Debit',
                          'Rs ${totalDebit.toStringAsFixed(2)}',
                          bold: true),
                      PdfBranding.sumRow(
                          'Total Credit',
                          'Rs ${totalCredit.toStringAsFixed(2)}',
                          bold: true),
                      PdfBranding.sumRow(
                          'Closing Balance',
                          'Rs ${displayFinalBalance.toStringAsFixed(2)}',
                          big: true,
                          color: PdfBranding.orange),
                    ]),
              ),
            ),
          ]));

      pw.Widget accountBox() => PdfBranding.framed(pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            PdfBranding.boxTitle('CUSTOMER ACCOUNT'),
            pw.SizedBox(height: 6),
            PdfBranding.acctRow('Opening Balance',
                'Rs ${openingBalanceDisplay.toStringAsFixed(2)}'),
            PdfBranding.acctRow('Total Debit',
                'Rs ${totalDebit.toStringAsFixed(2)}'),
            PdfBranding.acctRow('Total Credit',
                'Rs ${totalCredit.toStringAsFixed(2)}'),
            pw.Spacer(),
            pw.Container(
              padding:
              const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: pw.BoxDecoration(
                  color: PdfBranding.orange,
                  borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    PdfBranding.txt('Closing Balance',
                        size: 10, bold: true, color: PdfColors.white),
                    PdfBranding.txt(
                        'Rs ${displayFinalBalance.toStringAsFixed(2)}',
                        size: 11, bold: true, color: PdfColors.white),
                  ]),
            ),
          ]));

      // ──────────────── Compose page ────────────────
      final String dateText =
      DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
      final String periodText =
      provider.isFiltered && provider.dateRangeFilter != null
          ? '${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.start)}'
          ' – '
          '${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.end)}'
          : 'All Transactions';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          header: (ctx) => ctx.pageNumber == 1
              ? PdfBranding.header()
              : pw.SizedBox(height: 18),
          footer: (ctx) => PdfBranding.footer(),
          build: (ctx) => [
            PdfBranding.pad(
                PdfBranding.titleBanner('PARTY STATEMENT'), v: 10),
            PdfBranding.pad(pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  PdfBranding.infoBox('Date Range', periodText),
                  PdfBranding.infoBox('Generated', dateText),
                ])),
            pw.SizedBox(height: 10),
            PdfBranding.pad(customerSection()),
            pw.SizedBox(height: 12),
            PdfBranding.pad(transactionSection()),
            pw.SizedBox(height: 4),
            PdfBranding.pad(PdfBranding.txt(
                'Weight and Amount are calculated automatically.',
                size: 7.5,
                color: PdfBranding.grey)),
            pw.SizedBox(height: 8),
            PdfBranding.pad(pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(child: summaryBox()),
                  pw.SizedBox(width: 12),
                  pw.Expanded(child: accountBox()),
                ])),
          ],
        ),
      );

      return pdf;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }

  /// Opening balance row rendered as a `TableRow` so it fits inside the
  /// branded transaction table.
  pw.TableRow _openingBalanceTableRow(
      FilledCustomerReportProvider provider,
      LanguageProvider languageProvider,
      double openingBalanceDisplay,
      ) {
    final dateStr = provider.displayOpeningBalanceDate != null
        ? DateFormat('dd MMM yyyy')
        .format(provider.displayOpeningBalanceDate!)
        : '-';
    final label = languageProvider.isEnglish
        ? provider.openingBalanceLabel
        : (provider.isFiltered ? 'پچھلا بیلنس' : 'ابتدائی بیلنس');

    return pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfBranding.softBg),
      children: [
        PdfBranding.cell(dateStr),
        PdfBranding.cell('-'),
        PdfBranding.cell('-'),
        PdfBranding.cell(label, bold: true),
        PdfBranding.cell('-'),
        PdfBranding.cell('-'),
        PdfBranding.cell('-'),
        PdfBranding.cell('-'),
        PdfBranding.cell(
            'Rs ${openingBalanceDisplay.toStringAsFixed(2)}',
            bold: true),
        PdfBranding.cell(
            'Rs ${openingBalanceDisplay.toStringAsFixed(2)}',
            bold: true),
      ],
    );
  }

  /// Sub-table used inside an expanded invoice row, styled with PdfBranding.
  pw.Widget _invoiceItemsSubTable(
      List<Map<String, dynamic>> items,
      Map<String, pw.MemoryImage> nameImgs,
      Map<String, pw.MemoryImage> lengthImgs,
      Map<String, pw.MemoryImage> descImgs,
      LanguageProvider lp,
      ) {
    double itemsSubtotal = 0.0;
    double totalQty = 0.0;
    double totalWeight = 0.0;

    final dataRows = <pw.TableRow>[];
    for (final it in items) {
      final qty = (it['quantity'] ?? 0).toDouble();
      final wt = (it['totalWeight'] ?? 0).toDouble();
      final wpu = (it['weightPerUnit'] ?? 0).toDouble();
      final total = (it['total'] ?? 0).toDouble();
      itemsSubtotal += total;
      totalQty += qty;
      if (it['calculationType'] == 'weight' && wt > 0) {
        totalWeight += wt;
      } else if (wpu > 0) {
        totalWeight += wpu * qty;
      }

      final name = it['itemName']?.toString() ?? '';
      final len = it['length']?.toString() ?? '';
      final desc = it['description']?.toString() ?? '';

      dataRows.add(pw.TableRow(
        children: [
          PdfBranding.imgCell(nameImgs[name], name, h: 16),
          PdfBranding.imgCell(lengthImgs[len], len, h: 16),
          PdfBranding.cell(it['bodyType']?.toString() ?? ''),
          PdfBranding.imgCell(descImgs[desc], desc, h: 16),
          PdfBranding.cell(qty.toString()),
          PdfBranding.cell(
              wpu > 0 ? '${wpu.toStringAsFixed(2)} kg' : '-'),
          PdfBranding.cell(
              wt > 0 ? '${wt.toStringAsFixed(2)} kg' : '-'),
          PdfBranding.cell(
              'Rs ${(it['rate'] ?? 0).toStringAsFixed(2)}'),
          PdfBranding.cell('Rs ${total.toStringAsFixed(2)}',
              bold: true),
        ],
      ));
    }

    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            lp.isEnglish ? 'Invoice Items' : 'انوائس آئٹمز',
            style: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(
                color: PdfBranding.softLine, width: 0.3),
            columnWidths: const {
              0: pw.FlexColumnWidth(2.2),
              1: pw.FlexColumnWidth(1.1),
              2: pw.FlexColumnWidth(1.0),
              3: pw.FlexColumnWidth(1.8),
              4: pw.FlexColumnWidth(0.8),
              5: pw.FlexColumnWidth(1.0),
              6: pw.FlexColumnWidth(1.0),
              7: pw.FlexColumnWidth(1.0),
              8: pw.FlexColumnWidth(1.1),
            },
            children: [
              pw.TableRow(
                decoration:
                pw.BoxDecoration(color: PdfBranding.navy),
                children: [
                  PdfBranding.headCell('Item Name'),
                  PdfBranding.headCell('Length'),
                  PdfBranding.headCell('Body'),
                  PdfBranding.headCell('Description'),
                  PdfBranding.headCell('Qty'),
                  PdfBranding.headCell('Wt/Unit'),
                  PdfBranding.headCell('Total Wt'),
                  PdfBranding.headCell('Rate'),
                  PdfBranding.headCell('Total'),
                ],
              ),
              ...dataRows,
              pw.TableRow(
                decoration:
                pw.BoxDecoration(color: PdfBranding.orange),
                children: [
                  PdfBranding.headCell('TOTAL'),
                  PdfBranding.headCell(''),
                  PdfBranding.headCell(''),
                  PdfBranding.headCell(''),
                  PdfBranding.headCell(totalQty.toStringAsFixed(0)),
                  PdfBranding.headCell(''),
                  PdfBranding.headCell(
                      '${totalWeight.toStringAsFixed(2)} kg'),
                  PdfBranding.headCell(''),
                  PdfBranding.headCell(
                      'Rs ${itemsSubtotal.toStringAsFixed(2)}'),
                ],
              ),
            ],
          ),
        ]);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Print / download
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _generateAndPrintPDF(
      FilledCustomerReportProvider provider,
      LanguageProvider languageProvider) async {
    final pdf = await _buildLedgerPdf(provider, languageProvider);
    if (pdf == null) return;
    await _printPDF(pdf);
  }

  Future<void> _printPDF(pw.Document pdf) async {
    try {
      if (kIsWeb) {
        final bytes = await pdf.save();
        final blob = html.Blob([bytes], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor =
        html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download =
              'customer_ledger_${widget.customerName}_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf';
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
          'customer_ledger_${widget.customerName}_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf',
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

  // ═══════════════════════════════════════════════════════════════════
  // Helpers kept as-is
  // ═══════════════════════════════════════════════════════════════════

  static Map<String, String> _createBankIconMap() {
    return {
      for (var bank in pakistaniBanks)
        bank.name.toLowerCase(): bank.iconPath
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

  @override
  Widget build(BuildContext context) {
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);

    return ChangeNotifierProvider(
      create: (_) => FilledCustomerReportProvider()
        ..fetchCustomerReport(widget.customerId),
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
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.print),
                      tooltip: languageProvider.isEnglish
                          ? 'Print / Download PDF'
                          : 'پرنٹ / پی ڈی ایف',
                      onPressed: () =>
                          _generateAndPrintPDF(provider, languageProvider),
                    ),
                    IconButton(
                      icon: const Icon(Icons.share, color: Colors.white),
                      tooltip: languageProvider.isEnglish
                          ? 'Share on WhatsApp'
                          : 'واٹس ایپ پر بھیجیں',
                      onPressed: () =>
                          _sharePDFOnWhatsApp(provider, languageProvider),
                    ),
                  ],
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
                Color(0xFFFFF3E0),
                Color(0xFFFFE0B2),
              ],
            ),
          ),
          child: Consumer<FilledCustomerReportProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading) {
                return const Center(
                    child: CircularProgressIndicator(
                      valueColor:
                      AlwaysStoppedAnimation(Color(0xFFFF8A65)),
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
                        style:
                        Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFFE65100),
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

  // ── Everything below this line is unchanged from your existing file ──

  Widget _buildCustomerInfo(BuildContext context,
      LanguageProvider languageProvider, FilledCustomerReportProvider provider) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Center(
      child: Column(
        children: [
          Text(
            widget.customerName,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: isMobile ? 20 : 24,
              color: const Color(0xFFE65100),
            ),
          ),
          Text(
            '${languageProvider.isEnglish ? 'Phone Number:' : 'فون نمبر:'} ${widget.customerPhone}',
            style: const TextStyle(color: Color(0xFFFF8A65)),
          ),
          Text(
            '${languageProvider.isEnglish ? 'Address:' : 'پتہ:'} ${widget.customerAddress}',
            style: const TextStyle(color: Color(0xFFFF8A65)),
          ),
          Text(
            '${languageProvider.isEnglish ? 'City:' : 'شہر:'} ${widget.customerCity}',
            style: const TextStyle(color: Color(0xFFFF8A65)),
          ),
          const SizedBox(height: 10),
          Text(
            provider.isFiltered && provider.dateRangeFilter != null
                ? '${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.start)} - ${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.end)}'
                : 'All Transactions',
            style: const TextStyle(color: Color(0xFFFF8A65)),
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
              label: Text(languageProvider.isEnglish
                  ? 'Select Date Range'
                  : 'تاریخ منتخب کریں'),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFFFF8A65),
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
    final double openingBalance = provider.displayOpeningBalance;
    final double debit = provider.report['debit']?.toDouble() ?? 0.0;
    final double credit = provider.report['credit']?.toDouble() ?? 0.0;
    final double netBalance = provider.report['balance']?.toDouble() ?? 0.0;
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child:
                    Icon(icon, size: isMobile ? 20 : 24, color: color),
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
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: isMobile ? 12 : 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
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
                      : (value < 0 ? 0.0 : value / 10000),
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

  Widget _buildTransactionTable(LanguageProvider languageProvider) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Consumer<FilledCustomerReportProvider>(
      builder: (context, reportProvider, child) {
        final transactions = reportProvider.transactions ?? [];

        if (transactions.isEmpty && reportProvider.isFiltered) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                languageProvider.isEnglish
                    ? 'No transactions found in the selected date range'
                    : 'منتخب کردہ تاریخ کی حد میں کوئی لین دین نہیں ملا',
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCustomTransactionTable(
                transactions, reportProvider, isMobile, languageProvider),
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
      ) {
    final displayBalance = reportProvider.displayOpeningBalance;

    List<Map<String, dynamic>> sortedTransactions = List.from(transactions);
    sortedTransactions.sort((a, b) {
      final dateA = DateTime.tryParse(a['date']?.toString() ?? '') ??
          DateTime(2000);
      final dateB = DateTime.tryParse(b['date']?.toString() ?? '') ??
          DateTime(2000);
      return dateA.compareTo(dateB);
    });

    DateTime? openingBalanceDate = reportProvider.displayOpeningBalanceDate;
    bool openingBalanceInserted = false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFB74D).withOpacity(0.2),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              _buildExpandedHeaderCell(
                  languageProvider.isEnglish ? 'Date' : 'ڈیٹ', 1),
              _buildExpandedHeaderCell(
                  languageProvider.isEnglish ? 'Invoice No' : 'انوائس نمبر',
                  1),
              _buildExpandedHeaderCell(
                  languageProvider.isEnglish ? 'Ref No' : 'ریف نمبر', 1),
              _buildExpandedHeaderCell(
                  languageProvider.isEnglish ? 'Details' : 'تفصیلات', 2),
              _buildExpandedHeaderCell(
                  languageProvider.isEnglish ? 'Type' : 'قسم', 1),
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
        ...(() {
          List<Widget> rows = [];

          for (int i = 0; i < sortedTransactions.length; i++) {
            final transaction = sortedTransactions[i];
            final transactionDate =
                DateTime.tryParse(transaction['date']?.toString() ?? '') ??
                    DateTime(2000);

            if (!openingBalanceInserted &&
                (displayBalance != 0 || !reportProvider.isFiltered) &&
                openingBalanceDate != null &&
                openingBalanceDate.isBefore(transactionDate)) {
              rows.add(_buildOpeningBalanceRow(
                  reportProvider, languageProvider, isMobile));
              openingBalanceInserted = true;
            }

            rows.add(_buildExpandedTransactionRow(
                transaction, reportProvider, isMobile, languageProvider));

            final isInvoice = (transaction['credit'] ?? 0) != 0;
            final transactionKey = transaction['key']?.toString() ?? '';
            final isExpanded = reportProvider.expandedTransactions
                .contains(transactionKey);

            if (isInvoice && isExpanded) {
              rows.add(_buildInvoiceItems(
                  transactionKey, reportProvider, transactionDate));
            }
          }

          if (!openingBalanceInserted &&
              (displayBalance != 0 || !reportProvider.isFiltered)) {
            if (sortedTransactions.isEmpty) {
              rows.insert(0, _buildOpeningBalanceRow(
                  reportProvider, languageProvider, isMobile));
            } else {
              rows.add(_buildOpeningBalanceRow(
                  reportProvider, languageProvider, isMobile));
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
      ) {
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
                ? DateFormat('dd MMM yyyy')
                .format(reportProvider.displayOpeningBalanceDate!)
                : '-',
            1,
            isMobile,
          ),
          _buildExpandedDataCell('-', 1, isMobile),
          _buildExpandedDataCell('-', 1, isMobile),
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
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: Colors.grey[300]!)),
        ),
        child: Text(
          text,
          style: const TextStyle(
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
      ) {
    final bankName = _getBankName(transaction);
    final bankLogoPath = _getBankLogoPath(bankName);
    final isInvoice = (transaction['credit'] ?? 0) != 0;
    final transactionKey = transaction['key']?.toString() ?? '';
    final isExpanded =
    reportProvider.expandedTransactions.contains(transactionKey);

    final date =
        DateTime.tryParse(transaction['date']?.toString() ?? '') ??
            DateTime(2000);
    final details = transaction['details']?.toString() ??
        transaction['referenceNumber']?.toString() ??
        transaction['filledNumber']?.toString() ??
        '-';
    final paymentMethod =
        transaction['paymentMethod']?.toString() ?? '-';
    final debit = transaction['debit']?.toStringAsFixed(2) ?? '0.00';
    final credit = transaction['credit']?.toStringAsFixed(2) ?? '0.00';
    final balance = transaction['balance']?.toStringAsFixed(2) ?? '0.00';

    return GestureDetector(
      onTap: isInvoice
          ? () {
        reportProvider.toggleTransactionExpansion(transactionKey);
      }
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: isInvoice && isExpanded
              ? const Color(0xFFFFB74D).withOpacity(0.1)
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
                DateFormat('dd MMM yyyy').format(date), 1, isMobile),
            _buildExpandedDataCell(
              transaction['invoiceNumber']?.toString() ??
                  transaction['filledNumber']?.toString() ??
                  '-',
              1,
              isMobile,
              textColor: Colors.blue[700],
              fontWeight: FontWeight.w500,
            ),
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
                    const SizedBox(width: 4),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: const Color(0xFFE65100),
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
                    const SizedBox(width: 4),
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
              textColor: (transaction['debit'] ?? 0) > 0
                  ? Colors.red
                  : Colors.grey,
            ),
            _buildExpandedDataCell(
              (transaction['credit'] ?? 0) > 0 ? 'Rs $credit' : '-',
              1,
              isMobile,
              textColor: (transaction['credit'] ?? 0) > 0
                  ? Colors.green
                  : Colors.grey,
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
      }) {
    return Expanded(
      flex: (flexValue * 10).round(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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

  Widget _buildInvoiceItems(String transactionKey,
      FilledCustomerReportProvider reportProvider, DateTime date) {
    final invoiceItems = reportProvider.invoiceItems[transactionKey] ?? [];
    final isMobile = MediaQuery.of(context).size.width < 600;

    final double subtotal = invoiceItems.fold(
        0.0, (sum, item) => sum + (item['total'] ?? 0));
    final double discount = invoiceItems.fold(
        0.0, (sum, item) => sum + (item['discount'] ?? 0));
    final double grandTotal = subtotal - discount;

    final double totalQty = invoiceItems.fold(
        0.0, (sum, item) => sum + ((item['quantity'] ?? 0).toDouble()));
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
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        border: Border.all(color: const Color(0xFFFFB74D), width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB74D).withOpacity(0.3),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.receipt, color: Color(0xFFE65100), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Invoice Items - ${DateFormat('dd MMM yyyy').format(date)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isMobile ? 12 : 14,
                      color: const Color(0xFFE65100),
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
                        style: TextStyle(
                            fontSize: isMobile ? 10 : 12,
                            color: Colors.red),
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
          Padding(
            padding: const EdgeInsets.all(12),
            child: invoiceItems.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : isMobile
                ? _buildMobileInvoiceTable(invoiceItems, totalQty,
                totalWeight, subtotal)
                : _buildDesktopInvoiceTable(invoiceItems, totalQty,
                totalWeight, subtotal),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileInvoiceTable(List<Map<String, dynamic>> invoiceItems,
      double totalQty, double totalWeight, double subtotal) {
    return Column(
      children: [
        ...invoiceItems.map((item) {
          String weightText = _getWeightText(item);
          String calcType =
          item['calculationType'] == 'weight' ? 'Wt×Rate' : 'Qty×Rate';

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
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
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          if (calcType.isNotEmpty)
                            Text(
                              calcType,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.purple[600],
                                  fontStyle: FontStyle.italic),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      'Rs ${(item['total'] ?? 0).toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700]),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (item['length']?.toString().isNotEmpty ?? false)
                      Text('Length: ${item['length']}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[600])),
                    if (item['bodyType']?.toString().isNotEmpty ?? false)
                      Text('Body: ${item['bodyType']}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[600])),
                  ],
                ),
                if (item['description']?.toString().isNotEmpty ?? false) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Description: ${item['description']}',
                    style:
                    TextStyle(fontSize: 11, color: Colors.grey[600]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Qty: ${item['quantity']?.toString() ?? '0'}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[600])),
                    if (weightText.isNotEmpty)
                      Text('Weight: $weightText',
                          style: TextStyle(
                              fontSize: 11, color: Colors.blue[700])),
                    Text(
                        'Rate: Rs ${(item['rate'] ?? 0).toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.orange[700])),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Qty: ${totalQty.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Wt: ${totalWeight.toStringAsFixed(2)} kg',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Rs ${subtotal.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700])),
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
        weightText =
        '${item['totalWeight'].toStringAsFixed(2)} ${item['weightUnit'] ?? 'kg'}';
      } else if (item['weightPerUnit'] != null &&
          item['weightPerUnit'] > 0) {
        final weight = (item['weightPerUnit'] * (item['quantity'] ?? 1))
            .toStringAsFixed(2);
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
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
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
                          style: const TextStyle(fontSize: 17),
                        ),
                      ),
                    ),
                    DataCell(Text(item['length']?.toString() ?? '',
                        style: const TextStyle(fontSize: 17))),
                    DataCell(Text(item['bodyType']?.toString() ?? '',
                        style: const TextStyle(fontSize: 17))),
                    DataCell(
                      SizedBox(
                        width: 150,
                        child: Text(
                          item['description']?.toString() ?? '',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 17),
                        ),
                      ),
                    ),
                    DataCell(Text(
                      (item['quantity'] ?? 0).toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 17),
                    )),
                    DataCell(Text(
                      item['weightPerUnit'] != null
                          ? '${item['weightPerUnit'].toStringAsFixed(2)} ${item['weightUnit'] ?? 'kg'}'
                          : '-',
                      style: const TextStyle(fontSize: 17),
                    )),
                    DataCell(Text(
                      displayTotalWeight != null
                          ? '${displayTotalWeight.toStringAsFixed(2)} ${item['weightUnit'] ?? 'kg'}'
                          : '-',
                      style: TextStyle(
                          color: Colors.blue[700],
                          fontWeight: FontWeight.bold,
                          fontSize: 17),
                    )),
                    DataCell(Text(
                      calcType,
                      style: TextStyle(
                          fontSize: 14, color: Colors.purple[600]),
                    )),
                    DataCell(Text(
                      'Rs ${(item['rate'] ?? 0).toStringAsFixed(2)}',
                      style: TextStyle(
                          color: Colors.orange[700], fontSize: 17),
                    )),
                    DataCell(Text(
                      'Rs ${(item['total'] ?? 0).toStringAsFixed(2)}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                          fontSize: 17),
                    )),
                  ]);
                }).toList(),
                DataRow(cells: [
                  const DataCell(Text('TOTAL',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15))),
                  const DataCell(Text('')),
                  const DataCell(Text('')),
                  const DataCell(Text('')),
                  DataCell(Text(
                    totalQty.toStringAsFixed(0),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 17),
                  )),
                  const DataCell(Text('')),
                  DataCell(Text(
                    '${totalWeight.toStringAsFixed(2)} kg',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                        fontSize: 17),
                  )),
                  const DataCell(Text('')),
                  const DataCell(Text('')),
                  DataCell(Text(
                    'Rs ${subtotal.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                        fontSize: 17),
                  )),
                ]),
              ],
            ),
          ),
        );
      },
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