// items_wise_ledger_page.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
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
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:js_interop';

// Shared Mughal Group PDF design — same one used by ItemPurchasePage
// and FilledLedgerReportPage.
import '../Purchase/pdf_branding.dart';

// Web-only clipboard helpers (same as ItemPurchasePage)
@JS('copyPngToClipboard')
external JSPromise<JSBoolean> _copyPngToClipboardJs(JSString base64Png);

@JS('sharePngWithText')
external JSPromise<JSBoolean> _sharePngWithTextJs(
    JSString base64Png, JSString text, JSString fileName);

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

  // ═══════════════════════════════════════════════════════════════════
  // WhatsApp sharing helpers (same shape as FilledLedgerReportPage)
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

  Future<void> _sharePDFOnWhatsApp(
      ItemsWiseLedgerProvider provider,
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

    final pdf = await _buildItemsWisePdf(provider, languageProvider);
    if (pdf == null) return;
    final bytes = await pdf.save();

    Uint8List? pngBytes;
    try {
      await for (final page in Printing.raster(bytes, pages: [0], dpi: 110)) {
        pngBytes = await page.toPng();
        break;
      }
    } catch (e) {
      debugPrint('Raster failed: $e');
    }

    final closing = provider.report['balance']?.toDouble() ?? 0.0;
    final periodText = provider.isFiltered && provider.dateRangeFilter != null
        ? '${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.start)}'
        ' – '
        '${DateFormat('dd MMM yy').format(provider.dateRangeFilter!.end)}'
        : 'All Transactions';

    final message = 'Assalam o Alaikum ${widget.customerName},\n'
        'Aap ka items-wise ledger statement attached hai.\n'
        'Period: $periodText\n'
        'Closing Balance: Rs ${closing.toStringAsFixed(2)}\n'
        '${DateFormat('dd/MM/yyyy').format(DateTime.now())}\n'
        'Mughal Group of Industries';

    final safeName =
    widget.customerName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileBase = 'ItemsWise_Ledger_${safeName}_$stamp';

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(languageProvider.isEnglish
            ? 'Send on WhatsApp'
            : 'واٹس ایپ پر بھیجیں'),
        content: Text(languageProvider.isEnglish
            ? 'How would you like to send this items-wise statement to '
            '${widget.customerName} (${widget.customerPhone})?'
            : '${widget.customerName} (${widget.customerPhone}) کو یہ آئٹم وار اسٹیٹمنٹ کیسے بھیجیں؟'),
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
  // PDF — Mughal Group branded (matches FilledLedgerReportPage)
  // ═══════════════════════════════════════════════════════════════════
  Future<pw.Document?> _buildItemsWisePdf(
      ItemsWiseLedgerProvider provider,
      LanguageProvider languageProvider,
      ) async {
    try {
      await PdfBranding.ensureAssets();

      final pdf = pw.Document();
      final openingBalanceDisplay = provider.displayOpeningBalance;
      final DateTime? openingBalanceDate = provider.displayOpeningBalanceDate;
      final transactions = provider.transactions ?? [];

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
      final Map<String, pw.MemoryImage> bankNameImgs = {};
      final jobs = <Future<void>>[];

      void queue(Map<String, pw.MemoryImage> target, String text,
          double fs, double w, double h) {
        if (!PdfBranding.needsImage(text) || target.containsKey(text)) return;
        jobs.add(PdfBranding.textImage(text,
            fontSize: fs, width: w, height: h)
            .then((img) => target[text] = img));
      }

      // Customer fields
      queue(customerImgs, widget.customerName.trim(), 42, 165 * 3, 66);
      queue(customerImgs, widget.customerAddress.trim(), 12, 165 * 3, 20);
      queue(customerImgs, widget.customerCity.trim(), 12, 165 * 3, 20);

      // Item + bank names
      for (final t in transactions) {
        final itemName = t['itemName']?.toString() ??
            t['details']?.toString() ??
            '';
        if (itemName.isNotEmpty) queue(itemNameImgs, itemName, 42, 228, 66);
        final bName = _getBankName(t) ?? '';
        if (bName.isNotEmpty) queue(bankNameImgs, bName, 42, 165 * 3, 66);
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

      // ──────────────── Branded transaction table ────────────────
      pw.Widget transactionSection() {
        final headers = [
          'Date',
          'Invoice No',
          'Item Name',
          'Type',
          'Qty',
          'Unit Price',
          'Payment',
          'Bank',
          'Debit',
          'Credit',
          'Balance',
        ];

        final sorted = List<Map<String, dynamic>>.from(transactions);
        sorted.sort((a, b) {
          final da = DateTime.tryParse(a['date']?.toString() ?? '') ??
              DateTime(2000);
          final db = DateTime.tryParse(b['date']?.toString() ?? '') ??
              DateTime(2000);
          return da.compareTo(db);
        });

        final rows = <pw.TableRow>[];

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

        for (final t in sorted) {
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

          final isItem = t['isItem'] == true;
          final invoiceNumber = t['invoiceNumber']?.toString() ?? '-';
          final itemName = t['itemName']?.toString() ??
              t['details']?.toString() ??
              '-';

          final type = isItem
              ? (languageProvider.isEnglish ? 'Item' : 'آئٹم')
              : (languageProvider.isEnglish ? 'Payment' : 'ادائیگی');

          final quantity = isItem
              ? (t['quantity'] ?? 0).toStringAsFixed(2)
              : '-';
          final unitPrice = isItem
              ? (t['unitPrice'] ?? 0).toStringAsFixed(2)
              : '-';
          final paymentMethod = _getPaymentMethodText(
              t['paymentMethod']?.toString() ?? '-', languageProvider);
          final bankName = _getBankName(t) ?? '-';
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
              PdfBranding.cell(invoiceNumber, bold: true),
              PdfBranding.imgCell(itemNameImgs[itemName], itemName, h: 18),
              PdfBranding.cell(type),
              PdfBranding.cell(quantity),
              PdfBranding.cell(
                  isItem ? 'Rs $unitPrice' : '-'),
              PdfBranding.cell(paymentMethod),
              PdfBranding.imgCell(bankNameImgs[bankName], bankName, h: 18),
              PdfBranding.cell(
                  debit > 0 ? 'Rs ${debit.toStringAsFixed(2)}' : '-'),
              PdfBranding.cell(
                  credit > 0 ? 'Rs ${credit.toStringAsFixed(2)}' : '-'),
              PdfBranding.cell('Rs ${balance.toStringAsFixed(2)}',
                  bold: true),
            ],
          ));
        }

        if (!openingAdded &&
            (openingBalanceDisplay != 0 || !provider.isFiltered) &&
            openingBalanceDate != null) {
          rows.add(_openingBalanceTableRow(
              provider, languageProvider, openingBalanceDisplay));
        }

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
          PdfBranding.sectionHeader('ITEMS WISE TRANSACTION DETAILS'),
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
              0: pw.FlexColumnWidth(1.2), // Date
              1: pw.FlexColumnWidth(1.0), // Invoice No
              2: pw.FlexColumnWidth(2.0), // Item Name
              3: pw.FlexColumnWidth(0.9), // Type
              4: pw.FlexColumnWidth(0.7), // Qty
              5: pw.FlexColumnWidth(1.0), // Unit Price
              6: pw.FlexColumnWidth(1.2), // Payment
              7: pw.FlexColumnWidth(1.2), // Bank
              8: pw.FlexColumnWidth(1.1), // Debit
              9: pw.FlexColumnWidth(1.1), // Credit
              10: pw.FlexColumnWidth(1.2), // Balance
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
                PdfBranding.titleBanner('ITEMS WISE STATEMENT'), v: 10),
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

  pw.TableRow _openingBalanceTableRow(
      ItemsWiseLedgerProvider provider,
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
        PdfBranding.cell(label, bold: true),
        PdfBranding.cell('-'),
        PdfBranding.cell('-'),
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

  // ═══════════════════════════════════════════════════════════════════
  // Print / download
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _generateAndPrintPDF(
      ItemsWiseLedgerProvider provider,
      LanguageProvider languageProvider) async {
    final pdf = await _buildItemsWisePdf(provider, languageProvider);
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

  // ═══════════════════════════════════════════════════════════════════
  // In-page UI (unchanged layout — just adds the WhatsApp button)
  // ═══════════════════════════════════════════════════════════════════

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

  // ── In-page helpers unchanged ──────────────────────────────────────

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
          _buildExpandedDataCell('-', 1, isMobile), // Invoice No
          _buildExpandedDataCell(
            languageProvider.isEnglish
                ? provider.openingBalanceLabel
                : (provider.isFiltered
                ? 'پچھلا بیلنس'
                : 'ابتدائی بیلنس'),
            2,
            isMobile,
          ),
          _buildExpandedDataCell('-', 1, isMobile), // Type
          _buildExpandedDataCell('-', 0.8, isMobile), // Qty
          _buildExpandedDataCell('-', 1.2, isMobile), // Unit Price
          _buildExpandedDataCell('-', 1.5, isMobile), // Payment Method
          _buildExpandedDataCell('-', 2, isMobile), // Bank
          _buildExpandedDataCell('-', 1, isMobile), // Debit
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
                    style:
                    TextStyle(fontSize: isMobile ? 10 : 12),
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