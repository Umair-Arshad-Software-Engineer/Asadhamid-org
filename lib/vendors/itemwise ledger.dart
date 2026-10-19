// vendor_item_wise_ledger_page.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;
import 'dart:js_interop';

import '../Provider/lanprovider.dart';
import '../bankmanagement/banknames.dart';
import '../Purchase/pdf_branding.dart';

// Web-only clipboard helpers (same as ItemPurchasePage)
@JS('copyPngToClipboard')
external JSPromise<JSBoolean> _copyPngToClipboardJs(JSString base64Png);

@JS('sharePngWithText')
external JSPromise<JSBoolean> _sharePngWithTextJs(
    JSString base64Png, JSString text, JSString fileName);

class VendorItemWiseLedgerPage extends StatefulWidget {
  final String vendorId;
  final String vendorName;

  const VendorItemWiseLedgerPage({
    super.key,
    required this.vendorId,
    required this.vendorName,
  });

  @override
  State<VendorItemWiseLedgerPage> createState() =>
      _VendorItemWiseLedgerPageState();
}

class _VendorItemWiseLedgerPageState
    extends State<VendorItemWiseLedgerPage> {
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

  // ═══════════════════════════════════════════════════════════════════
  // WhatsApp helpers
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

  Future<void> _shareWhatsApp() async {
    String phone = '';
    try {
      final snap = await FirebaseDatabase.instance
          .ref('vendors/${widget.vendorId}/phone')
          .get();
      if (snap.exists) phone = snap.value?.toString() ?? '';
    } catch (_) {}

    final number = _normalizePkNumber(phone);
    if (number == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No valid WhatsApp number on file for this vendor. Please add a phone number in the vendor profile.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!await _isWhatsAppAvailable(number)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WhatsApp is not available on this device.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final pdf = await _buildItemWisePdf();
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

    final periodText = _selectedDateRange != null
        ? '${DateFormat('dd MMM yy').format(_selectedDateRange!.start)} – '
        '${DateFormat('dd MMM yy').format(_selectedDateRange!.end)}'
        : 'All Transactions';

    final message = 'Assalam o Alaikum ${widget.vendorName},\n'
        'Aap ka item-wise vendor statement attached hai.\n'
        'Period: $periodText\n'
        'Closing Balance: Rs ${_currentBalance.toStringAsFixed(2)}\n'
        '${DateFormat('dd/MM/yyyy').format(DateTime.now())}\n'
        'Mughal Group of Industries';

    final safeName =
    widget.vendorName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileBase = 'Vendor_ItemWise_${safeName}_$stamp';

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send on WhatsApp'),
        content: Text(
            'How would you like to send this items-wise statement to ${widget.vendorName}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          OutlinedButton.icon(
            icon: const Icon(Icons.message, size: 18),
            label: const Text('Text'),
            onPressed: () async {
              Navigator.pop(ctx);
              await _sendWhatsAppTextOnly(number, message);
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: const Text('PDF file'),
            onPressed: () async {
              Navigator.pop(ctx);
              await Printing.sharePdf(
                  bytes: bytes, filename: '$fileBase.pdf');
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.image, size: 18),
            label: const Text('Image + Message'),
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
                        ? 'Image copied. Press Ctrl+V in the chat.'
                        : 'Could not copy the image. Use PDF file option.'),
                  ),
                );
              } else {
                final ok = await _shareImageWithText(
                    pngBytes!, message, '$fileBase.png');
                if (!ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Sharing not supported here. Use PDF file.'),
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
  // PDF — Mughal Group branded
  // ═══════════════════════════════════════════════════════════════════
  Future<pw.Document?> _buildItemWisePdf() async {
    try {
      await PdfBranding.ensureAssets();

      final pdf = pw.Document();

      // ─── Urdu-safe images ───
      final jobs = <Future<void>>[];
      final Map<String, pw.MemoryImage> vendorImgs = {};
      final Map<String, pw.MemoryImage> itemImgs = {};
      final Map<String, pw.MemoryImage> descImgs = {};
      final Map<String, pw.MemoryImage> bankImgs = {};

      void queue(Map<String, pw.MemoryImage> target, String text,
          double fs, double w, double h) {
        if (!PdfBranding.needsImage(text) || target.containsKey(text)) return;
        jobs.add(PdfBranding.textImage(text,
            fontSize: fs, width: w, height: h)
            .then((img) => target[text] = img));
      }

      queue(vendorImgs, widget.vendorName.trim(), 42, 165 * 3, 66);

      for (final entry in _filteredLedgerEntries) {
        final desc =
        (entry['description'] ?? '').toString();
        if (desc.isNotEmpty) queue(descImgs, desc, 11, 160, 20);

        final itemName = entry['itemName']?.toString() ?? '';
        if (itemName.isNotEmpty) queue(itemImgs, itemName, 42, 228, 66);

        final bName = _getBankName(entry) ?? '';
        if (bName.isNotEmpty) queue(bankImgs, bName, 42, 165 * 3, 66);
      }
      await Future.wait(jobs);

      // ─── Vendor details ───
      pw.Widget vendorSection() => pw.Column(children: [
        PdfBranding.sectionHeader('VENDOR DETAILS'),
        PdfBranding.sectionBody(pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                  child: pw.Column(children: [
                    PdfBranding.field('Vendor Name',
                        img: vendorImgs[widget.vendorName.trim()],
                        text: widget.vendorName),
                  ])),
              pw.SizedBox(width: 18),
              pw.Expanded(
                  child: pw.Column(children: [
                    PdfBranding.field(
                        'Date Range',
                        text: _selectedDateRange != null
                            ? '${DateFormat('dd MMM yy').format(_selectedDateRange!.start)} – ${DateFormat('dd MMM yy').format(_selectedDateRange!.end)}'
                            : 'All Transactions'),
                  ])),
            ])),
      ]);

      // ─── Transactions table ───
      pw.Widget transactionsSection() {
        final headers = [
          'Date',
          'Description',
          'Item Name',
          'Qty',
          'Weight',
          'Unit Price',
          'Method',
          'Bank',
          'Debit',
          'Credit',
          'Balance',
        ];

        final sorted =
        List<Map<String, dynamic>>.from(_filteredLedgerEntries);
        sorted.sort((a, b) {
          final da =
              DateTime.tryParse(_getDisplayDate(a)) ?? DateTime(2000);
          final db =
              DateTime.tryParse(_getDisplayDate(b)) ?? DateTime(2000);
          return da.compareTo(db);
        });

        final rows = <pw.TableRow>[];
        for (int i = 0; i < sorted.length; i++) {
          final entry = sorted[i];
          final isOpening = entry['description'] == 'Opening Balance';
          final isItem = entry['isItem'] == true;
          final isPayment = !isOpening && !isItem;

          final displayDate =
          _getFormattedDate(_getDisplayDate(entry), isOpening);
          final bName = _getBankName(entry) ?? '-';
          final desc = entry['description']?.toString() ?? '';
          final itemName = isItem ? (entry['itemName'] ?? '-').toString() : '-';
          final qty = isItem
              ? ((entry['quantity'] ?? 0) as num).toStringAsFixed(2)
              : '-';
          final wt = isItem
              ? ((entry['weight'] ?? 0) as num).toStringAsFixed(2)
              : '-';
          final up = isItem
              ? 'Rs ${((entry['unitPrice'] ?? 0) as num).toStringAsFixed(2)}'
              : '-';
          final method = isPayment ? (entry['method'] ?? '-') : '-';

          final credit = (entry['credit'] ?? 0) as num;
          final debit = (entry['debit'] ?? 0) as num;
          final balance = (entry['balance'] ?? 0) as num;

          rows.add(pw.TableRow(
            decoration: pw.BoxDecoration(
                color: i.isEven ? PdfColors.white : PdfBranding.softBg),
            children: [
              PdfBranding.cell(displayDate),
              PdfBranding.imgCell(descImgs[desc], desc, h: 16),
              PdfBranding.imgCell(itemImgs[itemName], itemName, h: 16),
              PdfBranding.cell(qty),
              PdfBranding.cell(wt),
              PdfBranding.cell(up),
              PdfBranding.cell(method),
              PdfBranding.imgCell(bankImgs[bName], bName, h: 16),
              PdfBranding.cell(
                  debit > 0 ? 'Rs ${debit.toStringAsFixed(2)}' : '-'),
              PdfBranding.cell(
                  credit > 0 ? 'Rs ${credit.toStringAsFixed(2)}' : '-'),
              PdfBranding.cell('Rs ${balance.toStringAsFixed(2)}',
                  bold: true),
            ],
          ));
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
                'Rs ${_totalDebit.toStringAsFixed(2)}'),
            PdfBranding.headCell(
                'Rs ${_totalCredit.toStringAsFixed(2)}'),
            PdfBranding.headCell(
                'Rs ${_currentBalance.toStringAsFixed(2)}'),
          ],
        ));

        return pw.Column(children: [
          PdfBranding.sectionHeader('ITEM-WISE TRANSACTION DETAILS'),
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
              0: pw.FlexColumnWidth(1.0),
              1: pw.FlexColumnWidth(1.4),
              2: pw.FlexColumnWidth(2.0),
              3: pw.FlexColumnWidth(0.7),
              4: pw.FlexColumnWidth(0.8),
              5: pw.FlexColumnWidth(1.0),
              6: pw.FlexColumnWidth(0.9),
              7: pw.FlexColumnWidth(1.2),
              8: pw.FlexColumnWidth(1.1),
              9: pw.FlexColumnWidth(1.1),
              10: pw.FlexColumnWidth(1.2),
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

      // ─── Summary boxes ───
      double openingBalance = 0.0;
      for (final e in _filteredLedgerEntries) {
        if (e['description'] == 'Opening Balance') {
          openingBalance = (e['credit'] ?? 0).toDouble();
        }
      }

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
                          'Rs ${_totalDebit.toStringAsFixed(2)}',
                          bold: true),
                      PdfBranding.sumRow(
                          'Total Credit',
                          'Rs ${_totalCredit.toStringAsFixed(2)}',
                          bold: true),
                      PdfBranding.sumRow(
                          'Closing Balance',
                          'Rs ${_currentBalance.toStringAsFixed(2)}',
                          big: true,
                          color: PdfBranding.orange),
                    ]),
              ),
            ),
          ]));

      pw.Widget accountBox() => PdfBranding.framed(pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            PdfBranding.boxTitle('VENDOR ACCOUNT'),
            pw.SizedBox(height: 6),
            PdfBranding.acctRow('Opening Balance',
                'Rs ${openingBalance.toStringAsFixed(2)}'),
            PdfBranding.acctRow('Total Debit',
                'Rs ${_totalDebit.toStringAsFixed(2)}'),
            PdfBranding.acctRow('Total Credit',
                'Rs ${_totalCredit.toStringAsFixed(2)}'),
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
                        'Rs ${_currentBalance.toStringAsFixed(2)}',
                        size: 11, bold: true, color: PdfColors.white),
                  ]),
            ),
          ]));

      final String dateText =
      DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
      final String periodText = _selectedDateRange != null
          ? '${DateFormat('dd MMM yy').format(_selectedDateRange!.start)} – '
          '${DateFormat('dd MMM yy').format(_selectedDateRange!.end)}'
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
                PdfBranding.titleBanner('VENDOR ITEM-WISE LEDGER'), v: 10),
            PdfBranding.pad(pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  PdfBranding.infoBox('Date Range', periodText),
                  PdfBranding.infoBox('Generated', dateText),
                ])),
            pw.SizedBox(height: 10),
            PdfBranding.pad(vendorSection()),
            pw.SizedBox(height: 12),
            PdfBranding.pad(transactionsSection()),
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
      debugPrint('Item-Wise Vendor PDF error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Print
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _printLedger() async {
    final pdf = await _buildItemWisePdf();
    if (pdf == null) return;
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
              'vendor_itemwise_ledger_${widget.vendorName}_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf';
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
          onLayout: (format) async => pdf.save(),
          name:
          'vendor_itemwise_ledger_${widget.vendorName}_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf',
        );
      }
    } catch (e) {
      debugPrint('Print error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Data load & helpers
  // ═══════════════════════════════════════════════════════════════════
  String? _getBankName(Map<String, dynamic> transaction) {
    if (transaction['bankName'] != null &&
        transaction['bankName'].toString().isNotEmpty) {
      return transaction['bankName'].toString();
    }
    String pm =
        transaction['method']?.toString().toLowerCase() ?? '';
    if (pm == 'cheque' || pm == 'check') {
      if (transaction['chequeBankName'] != null &&
          transaction['chequeBankName'].toString().isNotEmpty) {
        return transaction['chequeBankName'].toString();
      }
    }
    return null;
  }

  String? _getBankLogoPath(String? bankName) {
    if (bankName == null) return null;
    return _bankIconMap[bankName.toLowerCase()];
  }

  String _getDisplayDate(Map<String, dynamic> transaction) {
    final pm = transaction['method']?.toString().toLowerCase() ?? '';
    if (pm == 'cheque' || pm == 'check') {
      if (transaction['chequeDate'] != null &&
          transaction['chequeDate'].toString().isNotEmpty) {
        return transaction['chequeDate'].toString();
      }
    }
    return transaction['date'] ?? 'Unknown Date';
  }

  String _getFormattedDate(String dateString, bool isOpeningBalance) {
    if (isOpeningBalance) return dateString;
    final parsed = DateTime.tryParse(dateString);
    if (parsed != null) {
      return "${parsed.month}/${parsed.day}/${parsed.year % 100}";
    }
    return "Unknown Date";
  }

  Future<void> _fetchLedgerData() async {
    try {
      final vendorRef =
      FirebaseDatabase.instance.ref('vendors/${widget.vendorId}');
      final purchasesRef = FirebaseDatabase.instance.ref('purchases');
      final paymentsRef = FirebaseDatabase.instance
          .ref('vendors/${widget.vendorId}/payments');

      final vendorSnapshot = await vendorRef.get();
      double openingBalance = 0.0;
      String openingBalanceDate = "Unknown Date";
      if (vendorSnapshot.exists) {
        final vendorData = vendorSnapshot.value as Map<dynamic, dynamic>;
        openingBalance =
            (vendorData['openingBalance'] ?? 0.0).toDouble();
        final rawDate =
            vendorData['openingBalanceDate'] ?? "Unknown Date";
        final parsedDate = DateTime.tryParse(rawDate);
        openingBalanceDate = parsedDate != null
            ? "${parsedDate.month}/${parsedDate.day}/${parsedDate.year % 100}"
            : "Unknown Date";
      }

      final purchasesSnapshot = await purchasesRef
          .orderByChild('vendorId')
          .equalTo(widget.vendorId)
          .get();
      final List<Map<String, dynamic>> itemEntries = [];

      if (purchasesSnapshot.exists) {
        final purchasesMap =
        purchasesSnapshot.value as Map<dynamic, dynamic>;
        purchasesMap.forEach((purchaseKey, purchaseValue) {
          if (purchaseValue is Map) {
            final purchaseDate =
                purchaseValue['timestamp'] ?? 'Unknown Date';
            final purchaseNumber =
                purchaseValue['purchaseNumber'] ?? purchaseKey;
            final refNo = purchaseValue['refNo'] ?? '';

            if (purchaseValue['items'] != null) {
              List<Map<String, dynamic>> itemsList = [];
              if (purchaseValue['items'] is Map) {
                final itemsMap =
                purchaseValue['items'] as Map<dynamic, dynamic>;
                itemsList = itemsMap.entries.map((entry) {
                  final d = entry.value;
                  return {
                    'itemName': d['itemName'] ?? 'Unknown Item',
                    'quantity': (d['quantity'] ?? 0).toDouble(),
                    'weight': (d['weight'] ?? 0).toDouble(),
                    'price': (d['purchasePrice'] ?? d['price'] ?? 0.0)
                        .toDouble(),
                    'total': (d['total'] ??
                        ((d['weight'] ?? 0) *
                            (d['purchasePrice'] ?? d['price'] ?? 0.0)))
                        .toDouble(),
                  };
                }).toList();
              } else if (purchaseValue['items'] is List) {
                final list =
                purchaseValue['items'] as List<dynamic>;
                itemsList = list.map((item) {
                  if (item is Map) {
                    return {
                      'itemName': item['itemName'] ?? 'Unknown Item',
                      'quantity': (item['quantity'] ?? 0).toDouble(),
                      'weight': (item['weight'] ?? 0).toDouble(),
                      'price':
                      (item['purchasePrice'] ?? item['price'] ?? 0.0)
                          .toDouble(),
                      'total': (item['total'] ??
                          ((item['weight'] ?? 0) *
                              (item['purchasePrice'] ??
                                  item['price'] ??
                                  0.0)))
                          .toDouble(),
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

              for (final item in itemsList) {
                itemEntries.add({
                  'date': purchaseDate,
                  'description': 'Ref. No $refNo',
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

      final paymentsSnapshot = await paymentsRef.get();
      final List<Map<String, dynamic>> payments = [];
      if (paymentsSnapshot.exists) {
        final paymentsMap =
        paymentsSnapshot.value as Map<dynamic, dynamic>;
        paymentsMap.forEach((paymentKey, paymentValue) {
          if (paymentValue is Map) {
            final pm = paymentValue['method'] ??
                paymentValue['paymentMethod'] ??
                'Unknown Method';
            payments.add({
              'date': paymentValue['date'] ?? 'Unknown Date',
              'chequeDate': paymentValue['chequeDate'],
              'description': paymentValue['description'],
              'credit': 0.0,
              'debit': (paymentValue['amount'] ?? 0.0).toDouble(),
              'type': 'debit',
              'method': pm,
              'bankName': paymentValue['bankName'] ??
                  paymentValue['chequeBankName'],
              'paymentId': paymentKey,
              'isItem': false,
            });
          }
        });
      }

      final combinedEntries = [...itemEntries, ...payments];
      final openingBalanceEntry = {
        'date': openingBalanceDate,
        'description': 'Opening Balance',
        'credit': openingBalance,
        'debit': 0.0,
        'balance': openingBalance,
        'isItem': false,
      };
      combinedEntries.insert(0, openingBalanceEntry);

      combinedEntries.sort((a, b) {
        final dateA =
            DateTime.tryParse(_getDisplayDate(a)) ?? DateTime(1970);
        final dateB =
            DateTime.tryParse(_getDisplayDate(b)) ?? DateTime(1970);
        return dateA.compareTo(dateB);
      });

      double balance = openingBalance;
      double totalCredit = openingBalance;
      double totalDebit = 0.0;
      for (final entry in combinedEntries.skip(1)) {
        balance += entry['credit'] - entry['debit'];
        totalCredit += entry['credit'];
        totalDebit += entry['debit'];
        entry['balance'] = balance;
      }

      if (!mounted) return;
      setState(() {
        _ledgerEntries = combinedEntries;
        _filteredLedgerEntries = combinedEntries;
        _totalCredit = totalCredit;
        _totalDebit = totalDebit;
        _currentBalance = balance;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading ledger: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
        final filtered = _ledgerEntries.where((entry) {
          final entryDate =
              DateTime.tryParse(_getDisplayDate(entry)) ?? DateTime(1970);
          return entryDate.isAfter(
              picked.start.subtract(const Duration(days: 1))) &&
              entryDate.isBefore(
                  picked.end.add(const Duration(days: 1)));
        }).toList();

        final idx = filtered.indexWhere(
                (e) => e['description'] == 'Opening Balance');
        if (idx == -1) {
          final ob = _ledgerEntries.firstWhere(
                (e) => e['description'] == 'Opening Balance',
            orElse: () => {},
          );
          if (ob.isNotEmpty) filtered.insert(0, ob);
        }
        _filteredLedgerEntries = filtered;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // UI (unchanged look, new AppBar actions)
  // ═══════════════════════════════════════════════════════════════════
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
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: _shareWhatsApp,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _buildSummaryCards(),
          Expanded(
            child: isMobile
                ? _buildMobileItemWiseView()
                : _buildDesktopItemWiseView(),
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
        Container(
          color: Colors.blue[100],
          padding:
          const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
          child: Row(children: [
            Expanded(
                flex: 2,
                child: Container(
                  decoration: const BoxDecoration(
                      border: Border(
                          right: BorderSide(
                              color: Colors.black, width: 1))),
                  child: const Text('Date',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: fontSize)),
                )),
            Expanded(
                flex: 3,
                child: Container(
                  decoration: const BoxDecoration(
                      border: Border(
                          right: BorderSide(
                              color: Colors.black, width: 1))),
                  child: const Text('Description',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: fontSize)),
                )),
            Expanded(
                flex: 2,
                child: Container(
                  decoration: const BoxDecoration(
                      border: Border(
                          right: BorderSide(
                              color: Colors.black, width: 1))),
                  child: const Text('Credit',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: fontSize),
                      textAlign: TextAlign.right),
                )),
            Expanded(
                flex: 2,
                child: Container(
                  decoration: const BoxDecoration(
                      border: Border(
                          right: BorderSide(
                              color: Colors.black, width: 1))),
                  child: const Text('Debit',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: fontSize),
                      textAlign: TextAlign.right),
                )),
            const Expanded(
                flex: 2,
                child: Text('Balance',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: fontSize),
                    textAlign: TextAlign.right)),
          ]),
        ),
        ..._filteredLedgerEntries.map((entry) {
          final isOpening = entry['description'] == 'Opening Balance';
          final isItem = entry['isItem'] == true;
          final dateText = isOpening
              ? entry['date']
              : _getFormattedDate(_getDisplayDate(entry), false);

          return Container(
            color: isOpening ? Colors.yellow[100] : Colors.white,
            padding: const EdgeInsets.symmetric(
                vertical: 6.0, horizontal: 4.0),
            child: Row(children: [
              Expanded(
                  flex: 2,
                  child: Container(
                    decoration: const BoxDecoration(
                        border: Border(
                            right: BorderSide(
                                color: Colors.black, width: 1))),
                    child: Text(dateText,
                        style: TextStyle(
                            fontWeight: isOpening
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: fontSize)),
                  )),
              Expanded(
                  flex: 3,
                  child: Container(
                    decoration: const BoxDecoration(
                        border: Border(
                            right: BorderSide(
                                color: Colors.black, width: 1))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry['description'],
                            style: TextStyle(
                                fontWeight: isOpening
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: fontSize),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        if (isItem && entry['itemName'] != null)
                          Text('Item: ${entry['itemName']}',
                              style: TextStyle(
                                  fontSize: 8,
                                  color: Colors.grey[700]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  )),
              Expanded(
                  flex: 2,
                  child: Container(
                    decoration: const BoxDecoration(
                        border: Border(
                            right: BorderSide(
                                color: Colors.black, width: 1))),
                    child: Text(
                        (entry['credit'] as num)
                            .toStringAsFixed(2),
                        textAlign: TextAlign.right,
                        style:
                        const TextStyle(fontSize: fontSize)),
                  )),
              Expanded(
                  flex: 2,
                  child: Container(
                    decoration: const BoxDecoration(
                        border: Border(
                            right: BorderSide(
                                color: Colors.black, width: 1))),
                    child: Text(
                        (entry['debit'] as num).toStringAsFixed(2),
                        textAlign: TextAlign.right,
                        style:
                        const TextStyle(fontSize: fontSize)),
                  )),
              Expanded(
                flex: 2,
                child: Text(
                    (entry['balance'] as num).toStringAsFixed(2),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: fontSize)),
              ),
            ]),
          );
        }).toList(),
        Container(
          color: Colors.grey[300],
          padding:
          const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
          child: Row(children: [
            Expanded(
                flex: 3,
                child: Container(
                  decoration: const BoxDecoration(
                      border: Border(
                          right: BorderSide(
                              color: Colors.black, width: 1))),
                  child: const Text('Totals',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: fontSize)),
                )),
            Expanded(
                flex: 2,
                child: Container(
                  decoration: const BoxDecoration(
                      border: Border(
                          right: BorderSide(
                              color: Colors.black, width: 1))),
                  child: Text(_totalCredit.toStringAsFixed(2),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: fontSize)),
                )),
            Expanded(
                flex: 2,
                child: Container(
                  decoration: const BoxDecoration(
                      border: Border(
                          right: BorderSide(
                              color: Colors.black, width: 1))),
                  child: Text(_totalDebit.toStringAsFixed(2),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: fontSize)),
                )),
            Expanded(
              flex: 2,
              child: Text(_currentBalance.toStringAsFixed(2),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: fontSize)),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildDesktopItemWiseView() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF8A65), Color(0xFFFFB74D)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2)),
            ],
          ),
          child: Row(children: [
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
          ]),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(children: [
                ..._filteredLedgerEntries.asMap().entries.map(
                      (entryWithIndex) {
                    final index = entryWithIndex.key;
                    final entry = entryWithIndex.value;
                    final isOpening =
                        entry['description'] == 'Opening Balance';
                    final isItem = entry['isItem'] == true;
                    final isPayment = !isOpening && !isItem;
                    final isEvenRow = index % 2 == 0;

                    return _buildEnhancedItemWiseRow(
                        entry,
                        isOpening,
                        isItem,
                        isPayment,
                        isEvenRow ? Colors.white : Colors.grey[50]!);
                  },
                ).toList(),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.grey[100]!, Colors.grey[200]!],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    border: Border(
                        top: BorderSide(
                            color: Colors.grey[400]!, width: 2)),
                  ),
                  child: Row(children: [
                    _buildEnhancedDataCell('GRAND TOTAL', 1.2, false,
                        fontWeight: FontWeight.bold,
                        backgroundColor: Colors.transparent),
                    _buildEnhancedDataCell('', 1.5, false,
                        backgroundColor: Colors.transparent),
                    _buildEnhancedDataCell('', 3, false,
                        backgroundColor: Colors.transparent),
                    _buildEnhancedDataCell('', 1, false,
                        backgroundColor: Colors.transparent),
                    _buildEnhancedDataCell('', 1, false,
                        backgroundColor: Colors.transparent),
                    _buildEnhancedDataCell('', 1.2, false,
                        backgroundColor: Colors.transparent),
                    _buildEnhancedDataCell('', 1.2, false,
                        backgroundColor: Colors.transparent),
                    _buildEnhancedDataCell('', 1.5, false,
                        backgroundColor: Colors.transparent),
                    _buildEnhancedDataCell(
                        'Rs ${_totalCredit.toStringAsFixed(2)}',
                        1.3,
                        false,
                        fontWeight: FontWeight.bold,
                        textColor: Colors.green[800],
                        backgroundColor: Colors.transparent),
                    _buildEnhancedDataCell(
                        'Rs ${_totalDebit.toStringAsFixed(2)}',
                        1.3,
                        false,
                        fontWeight: FontWeight.bold,
                        textColor: Colors.red[800],
                        backgroundColor: Colors.transparent),
                    _buildEnhancedDataCell(
                        'Rs ${_currentBalance.toStringAsFixed(2)}',
                        1.5,
                        false,
                        fontWeight: FontWeight.bold,
                        textColor: _currentBalance >= 0
                            ? Colors.blue[800]
                            : Colors.orange[800],
                        backgroundColor: Colors.transparent),
                  ]),
                ),
              ]),
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
      ) {
    final dateText = isOpeningBalance
        ? entry['date']
        : _getFormattedDate(_getDisplayDate(entry), false);

    final bankName = _getBankName(entry);
    final bankLogoPath = _getBankLogoPath(bankName);

    final credit = (entry['credit'] ?? 0) as num;
    final debit = (entry['debit'] ?? 0) as num;
    final balance = (entry['balance'] ?? 0) as num;

    return Container(
      decoration: BoxDecoration(
        color: isOpeningBalance ? Colors.amber[50] : backgroundColor,
        border: Border(
            bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(children: [
        _buildEnhancedDataCell(dateText, 1.2, false,
            fontWeight: isOpeningBalance
                ? FontWeight.bold
                : FontWeight.normal,
            textColor: isOpeningBalance
                ? Colors.orange[800]
                : Colors.black87),
        _buildEnhancedDataCell(
            entry['description'], 1.5, false,
            fontWeight: isOpeningBalance
                ? FontWeight.bold
                : FontWeight.normal,
            textColor: isOpeningBalance
                ? Colors.orange[800]
                : Colors.black87),
        _buildEnhancedDataCell(
            isItem ? (entry['itemName'] ?? '-') : '-', 3, false,
            textColor:
            isItem ? Colors.blue[800] : Colors.grey[500]),
        _buildEnhancedDataCell(
            isItem
                ? ((entry['quantity'] ?? 0) as num)
                .toStringAsFixed(2)
                : '-',
            1,
            false,
            textColor:
            isItem ? Colors.purple[800] : Colors.grey[500]),
        _buildEnhancedDataCell(
            isItem
                ? ((entry['weight'] ?? 0) as num)
                .toStringAsFixed(2)
                : '-',
            1,
            false,
            textColor:
            isItem ? Colors.purple[800] : Colors.grey[500]),
        _buildEnhancedDataCell(
            isItem
                ? 'Rs ${((entry['unitPrice'] ?? 0) as num).toStringAsFixed(2)}'
                : '-',
            1.2,
            false,
            textColor:
            isItem ? Colors.green[800] : Colors.grey[500]),
        _buildEnhancedDataCell(
            isPayment ? (entry['method'] ?? '-') : '-', 1.2, false,
            textColor:
            isPayment ? Colors.orange[800] : Colors.grey[500]),
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
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(bankName ?? '-',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[800],
                        fontWeight: bankName != null
                            ? FontWeight.w500
                            : FontWeight.normal),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          1.5,
          false,
        ),
        _buildEnhancedDataCell(
            credit > 0 ? 'Rs ${credit.toStringAsFixed(2)}' : '-',
            1.3, false,
            fontWeight:
            credit > 0 ? FontWeight.w600 : FontWeight.normal,
            textColor: credit > 0
                ? Colors.green[700]
                : Colors.grey[500]),
        _buildEnhancedDataCell(
            debit > 0 ? 'Rs ${debit.toStringAsFixed(2)}' : '-',
            1.3, false,
            fontWeight:
            debit > 0 ? FontWeight.w600 : FontWeight.normal,
            textColor: debit > 0
                ? Colors.red[700]
                : Colors.grey[500]),
        _buildEnhancedDataCell(
            'Rs ${balance.toStringAsFixed(2)}', 1.5, false,
            fontWeight: FontWeight.bold,
            textColor: balance >= 0
                ? Colors.blue[700]
                : Colors.orange[700]),
      ]),
    );
  }

  Widget _buildEnhancedHeaderCell(String text, double flexValue) {
    return Expanded(
      flex: (flexValue * 10).round(),
      child: Container(
        padding:
        const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          border: Border(
              right: BorderSide(
                  color: Colors.white.withOpacity(0.3))),
        ),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 13,
                letterSpacing: 0.5),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis),
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
        padding:
        const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border(
              right: BorderSide(color: Colors.grey[200]!)),
        ),
        child: content is Widget
            ? content
            : Text(content.toString(),
            style: TextStyle(
                fontSize: 13,
                color: textColor ?? Colors.black87,
                fontWeight: fontWeight ?? FontWeight.normal),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis),
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
              isMobile: isMobile),
          _buildSummaryCard(
              title: 'Total Debit',
              value: _totalDebit,
              color: Colors.red,
              icon: Icons.arrow_downward,
              isMobile: isMobile),
          _buildSummaryCard(
              title: 'Current Balance',
              value: _currentBalance,
              color:
              _currentBalance >= 0 ? Colors.blue : Colors.orange,
              icon: Icons.account_balance_wallet,
              isMobile: isMobile),
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
  }) {
    final fontSize = isMobile ? 12.0 : 18.0;
    final valueSize = isMobile ? 14.0 : 20.0;
    final iconSize = isMobile ? 20.0 : 30.0;

    return Card(
      elevation: 4,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: iconSize, color: color),
            const SizedBox(height: 6),
            Text(title,
                style: TextStyle(
                    fontSize: fontSize,
                    color: color,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('Rs ${value.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: valueSize,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}