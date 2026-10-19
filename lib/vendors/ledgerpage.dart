// vendor_ledger_page.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

class VendorLedgerPage extends StatefulWidget {
  final String vendorId;
  final String vendorName;

  const VendorLedgerPage({
    super.key,
    required this.vendorId,
    required this.vendorName,
  });

  @override
  State<VendorLedgerPage> createState() => _VendorLedgerPageState();
}

class _VendorLedgerPageState extends State<VendorLedgerPage> {
  List<Map<String, dynamic>> _ledgerEntries = [];
  List<Map<String, dynamic>> _filteredLedgerEntries = [];
  bool _isLoading = true;
  double _totalCredit = 0.0;
  double _totalDebit = 0.0;
  double _currentBalance = 0.0;
  DateTimeRange? _selectedDateRange;
  Set<String> _expandedPurchases = {};
  Map<String, List<Map<String, dynamic>>> _purchaseItems = {};

  static final Map<String, String> _bankIconMap = _createBankIconMap();

  static Map<String, String> _createBankIconMap() {
    return {
      for (var bank in pakistaniBanks)
        bank.name.toLowerCase(): bank.iconPath
    };
  }

  @override
  void initState() {
    super.initState();
    _fetchLedgerData();
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
    // Vendor phone is not stored on the page; use a generic share.
    // If the vendor has a phone number in Firebase, fetch it first.
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

    final pdf = await _buildVendorLedgerPdf();
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
        'Aap ka vendor ledger statement attached hai.\n'
        'Period: $periodText\n'
        'Closing Balance: Rs ${_currentBalance.toStringAsFixed(2)}\n'
        '${DateFormat('dd/MM/yyyy').format(DateTime.now())}\n'
        'Mughal Group of Industries';

    final safeName =
    widget.vendorName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileBase = 'Vendor_Ledger_${safeName}_$stamp';

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send on WhatsApp'),
        content: Text(
            'How would you like to send this statement to ${widget.vendorName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
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
  Future<pw.Document?> _buildVendorLedgerPdf() async {
    try {
      await PdfBranding.ensureAssets();

      final pdf = pw.Document();

      // ─── Totals ───
      double totalDebit = 0.0;
      double totalCredit = 0.0;
      double finalBalance = 0.0;
      double openingBalance = 0.0;
      for (final e in _filteredLedgerEntries) {
        final d = (e['debit'] ?? 0).toDouble();
        final c = (e['credit'] ?? 0).toDouble();
        totalDebit += d;
        totalCredit += c;
        finalBalance = (e['balance'] ?? 0).toDouble();
        if (e['description'] == 'Opening Balance') openingBalance = c;
      }

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
        final desc = (entry['description2'] ?? entry['description'] ?? '')
            .toString();
        if (desc.isNotEmpty) queue(descImgs, desc, 11, 160, 20);

        final bName = _getBankName(entry) ?? '';
        if (bName.isNotEmpty) queue(bankImgs, bName, 42, 165 * 3, 66);

        if (entry['description'] == 'Purchase' &&
            _isPurchaseExpanded(entry['purchaseId'])) {
          for (final it in _purchaseItems[entry['purchaseId']] ?? []) {
            final n = it['itemName']?.toString() ?? '';
            if (n.isNotEmpty) queue(itemImgs, n, 42, 228, 66);
          }
        }
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
          'Type',
          'Description',
          'Method',
          'Bank',
          'Qty',
          'Weight',
          'Debit',
          'Credit',
          'Balance',
        ];

        final sorted = List<Map<String, dynamic>>.from(_filteredLedgerEntries);
        sorted.sort((a, b) {
          final da = DateTime.tryParse(_getDisplayDate(a)) ?? DateTime(2000);
          final db = DateTime.tryParse(_getDisplayDate(b)) ?? DateTime(2000);
          return da.compareTo(db);
        });

        final rows = <pw.TableRow>[];

        for (int i = 0; i < sorted.length; i++) {
          final entry = sorted[i];
          final isOpening = entry['description'] == 'Opening Balance';
          final isPayment =
          entry['description'].toString().contains('Payment');
          final isPurchase =
          entry['description'].toString().contains('Purchase');

          final displayDate = _getFormattedDate(
              _getDisplayDate(entry), isOpening);
          final transactionType = isPurchase
              ? 'Purchase'
              : (isPayment ? 'Payment' : 'Balance');
          final descText =
          (entry['description2'] ?? entry['description'] ?? '').toString();
          final method = isPayment ? (entry['method'] ?? '-') : '-';
          final bName = _getBankName(entry) ?? '-';

          double qty = 0.0;
          double wt = 0.0;
          if (isPurchase && _isPurchaseExpanded(entry['purchaseId'])) {
            final items = _purchaseItems[entry['purchaseId']] ?? [];
            qty = items.fold(0.0, (s, it) => s + ((it['quantity'] ?? 0) as num).toDouble());
            wt = items.fold(0.0, (s, it) => s + ((it['weight'] ?? 0) as num).toDouble());
          }

          final debit = (entry['debit'] ?? 0).toDouble();
          final credit = (entry['credit'] ?? 0).toDouble();
          final balance = (entry['balance'] ?? 0).toDouble();

          rows.add(pw.TableRow(
            decoration: pw.BoxDecoration(
                color: i.isEven ? PdfColors.white : PdfBranding.softBg),
            children: [
              PdfBranding.cell(displayDate),
              PdfBranding.cell(transactionType, bold: true),
              PdfBranding.imgCell(descImgs[descText], descText, h: 16),
              PdfBranding.cell(method),
              PdfBranding.imgCell(bankImgs[bName], bName, h: 16),
              PdfBranding.cell(
                  isPurchase ? qty.toStringAsFixed(2) : '-'),
              PdfBranding.cell(
                  isPurchase ? wt.toStringAsFixed(2) : '-'),
              PdfBranding.cell(
                  debit > 0 ? 'Rs ${debit.toStringAsFixed(2)}' : '-'),
              PdfBranding.cell(
                  credit > 0 ? 'Rs ${credit.toStringAsFixed(2)}' : '-'),
              PdfBranding.cell(
                  'Rs ${balance.toStringAsFixed(2)}',
                  bold: true),
            ],
          ));

          // Expanded purchase items sub-table
          if (isPurchase && _isPurchaseExpanded(entry['purchaseId'])) {
            final items = _purchaseItems[entry['purchaseId']] ?? [];
            if (items.isNotEmpty) {
              rows.add(pw.TableRow(children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.only(
                      left: 12, top: 4, bottom: 4, right: 12),
                  child: _purchaseItemsSubTable(items, itemImgs),
                ),
                for (int k = 0; k < headers.length - 1; k++)
                  pw.SizedBox(),
              ]));
            }
          }
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
                'Rs ${finalBalance.toStringAsFixed(2)}'),
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
              0: pw.FlexColumnWidth(1.2),
              1: pw.FlexColumnWidth(1.0),
              2: pw.FlexColumnWidth(2.0),
              3: pw.FlexColumnWidth(1.0),
              4: pw.FlexColumnWidth(1.2),
              5: pw.FlexColumnWidth(0.8),
              6: pw.FlexColumnWidth(0.9),
              7: pw.FlexColumnWidth(1.1),
              8: pw.FlexColumnWidth(1.1),
              9: pw.FlexColumnWidth(1.2),
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
                          'Rs ${finalBalance.toStringAsFixed(2)}',
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
                        'Rs ${finalBalance.toStringAsFixed(2)}',
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
                PdfBranding.titleBanner('VENDOR LEDGER'), v: 10),
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
      debugPrint('Vendor Ledger PDF error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }

  pw.Widget _purchaseItemsSubTable(
      List<Map<String, dynamic>> items,
      Map<String, pw.MemoryImage> nameImgs) {
    double totalQty = 0.0;
    double totalWt = 0.0;
    double totalAmt = 0.0;

    final dataRows = <pw.TableRow>[];
    for (final it in items) {
      final q = (it['quantity'] ?? 0).toDouble();
      final w = (it['weight'] ?? 0).toDouble();
      final p = (it['price'] ?? it['purchasePrice'] ?? 0).toDouble();
      final tw = q * w;
      final ta = tw * p;
      totalQty += q;
      totalWt += tw;
      totalAmt += ta;

      final name = it['itemName']?.toString() ?? '';
      final desc = it['description']?.toString() ?? '';

      dataRows.add(pw.TableRow(
        children: [
          PdfBranding.imgCell(nameImgs[name], name, h: 16),
          PdfBranding.cell(desc),
          PdfBranding.cell('Rs ${p.toStringAsFixed(2)}'),
          PdfBranding.cell('${w.toStringAsFixed(2)} kg'),
          PdfBranding.cell(q.toStringAsFixed(2)),
          PdfBranding.cell('${tw.toStringAsFixed(2)} kg'),
          PdfBranding.cell('Rs ${ta.toStringAsFixed(2)}', bold: true),
        ],
      ));
    }

    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Purchase Items',
              style: pw.TextStyle(
                  fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(
                color: PdfBranding.softLine, width: 0.3),
            columnWidths: const {
              0: pw.FlexColumnWidth(2.2),
              1: pw.FlexColumnWidth(1.6),
              2: pw.FlexColumnWidth(1.0),
              3: pw.FlexColumnWidth(1.0),
              4: pw.FlexColumnWidth(0.8),
              5: pw.FlexColumnWidth(1.0),
              6: pw.FlexColumnWidth(1.2),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfBranding.navy),
                children: [
                  PdfBranding.headCell('Item Name'),
                  PdfBranding.headCell('Description'),
                  PdfBranding.headCell('Rate'),
                  PdfBranding.headCell('Wt/Unit'),
                  PdfBranding.headCell('Qty'),
                  PdfBranding.headCell('Total Wt'),
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
                  PdfBranding.headCell(totalQty.toStringAsFixed(2)),
                  PdfBranding.headCell(
                      '${totalWt.toStringAsFixed(2)} kg'),
                  PdfBranding.headCell(
                      'Rs ${totalAmt.toStringAsFixed(2)}'),
                ],
              ),
            ],
          ),
        ]);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Print
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _printLedger() async {
    final pdf = await _buildVendorLedgerPdf();
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
              'vendor_ledger_${widget.vendorName}_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf';
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
          'vendor_ledger_${widget.vendorName}_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf',
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
        transaction['paymentMethod']?.toString().toLowerCase() ?? '';
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
      final List<Map<String, dynamic>> purchases = [];

      if (purchasesSnapshot.exists) {
        final purchasesMap =
        purchasesSnapshot.value as Map<dynamic, dynamic>;
        purchasesMap.forEach((purchaseKey, purchaseValue) {
          if (purchaseValue is Map) {
            final purchaseData = {
              'date': purchaseValue['timestamp'] ?? 'Unknown Date',
              'description': 'Purchase',
              'credit': (purchaseValue['grandTotal'] ?? 0.0).toDouble(),
              'debit': 0.0,
              'type': 'credit',
              'purchaseId': purchaseKey,
              'purchaseNumber':
              purchaseValue['purchaseNumber'] ?? purchaseKey,
              'refNo': purchaseValue['refNo'] ?? '',
              'items': purchaseValue['items'] ?? [],
              'grandTotal': purchaseValue['grandTotal'] ?? 0.0,
            };
            purchases.add(purchaseData);

            if (purchaseValue['items'] != null) {
              List<Map<String, dynamic>> itemsList = [];
              if (purchaseValue['items'] is Map) {
                final itemsMap =
                purchaseValue['items'] as Map<dynamic, dynamic>;
                itemsList = itemsMap.entries.map((entry) {
                  final d = entry.value;
                  return {
                    'itemName': d['itemName'] ?? 'Unknown Item',
                    'description': d['description'] ?? '',
                    'quantity': (d['quantity'] ?? 0).toDouble(),
                    'weight': (d['weight'] ?? d['weightPerUnit'] ?? 0)
                        .toDouble(),
                    'price': (d['purchasePrice'] ?? d['price'] ?? 0.0)
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
                      'description': item['description'] ?? '',
                      'quantity': (item['quantity'] ?? 0).toDouble(),
                      'weight': (item['weight'] ??
                          item['weightPerUnit'] ??
                          0)
                          .toDouble(),
                      'price': (item['purchasePrice'] ??
                          item['price'] ??
                          0.0)
                          .toDouble(),
                    };
                  }
                  return {
                    'itemName': 'Unknown Item',
                    'description': '',
                    'quantity': 0.0,
                    'weight': 0.0,
                    'price': 0.0,
                  };
                }).toList();
              }
              _purchaseItems[purchaseKey] = itemsList;
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
              'description': 'Payment via $pm',
              'credit': 0.0,
              'description2': paymentValue['description'],
              'debit': (paymentValue['amount'] ?? 0.0).toDouble(),
              'type': 'debit',
              'method': pm,
              'bankName': paymentValue['bankName'] ??
                  paymentValue['chequeBankName'],
              'paymentId': paymentKey,
            });
          }
        });
      }

      final combinedEntries = [...purchases, ...payments];
      combinedEntries.sort((a, b) {
        final dateA =
            DateTime.tryParse(_getDisplayDate(a)) ?? DateTime(1970);
        final dateB =
            DateTime.tryParse(_getDisplayDate(b)) ?? DateTime(1970);
        return dateA.compareTo(dateB);
      });

      final openingBalanceEntry = {
        'date': openingBalanceDate,
        'description': 'Opening Balance',
        'credit': openingBalance,
        'debit': 0.0,
        'balance': openingBalance,
      };
      combinedEntries.insert(0, openingBalanceEntry);

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

  void _togglePurchaseExpansion(String purchaseId) {
    setState(() {
      if (_expandedPurchases.contains(purchaseId)) {
        _expandedPurchases.remove(purchaseId);
      } else {
        _expandedPurchases.add(purchaseId);
      }
    });
  }

  bool _isPurchaseExpanded(String purchaseId) =>
      _expandedPurchases.contains(purchaseId);

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
        title: Text('${widget.vendorName} Ledger'),
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
                ? _buildMobileLedgerView()
                : _buildDesktopLedgerView(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLedgerView() {
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
                flex: 2,
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
        ..._filteredLedgerEntries.expand((entry) {
          final rows = <Widget>[];
          final isOpening = entry['description'] == 'Opening Balance';
          final isPurchase = entry['description'] == 'Purchase';
          final dateText = isOpening
              ? entry['date']
              : _getFormattedDate(_getDisplayDate(entry), false);

          rows.add(Container(
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
                  flex: 2,
                  child: Container(
                    decoration: const BoxDecoration(
                        border: Border(
                            right: BorderSide(
                                color: Colors.black, width: 1))),
                    child: Row(children: [
                      if (isPurchase)
                        IconButton(
                          icon: Icon(
                            _isPurchaseExpanded(entry['purchaseId'])
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 16,
                          ),
                          onPressed: () => _togglePurchaseExpansion(
                              entry['purchaseId']),
                        ),
                      Expanded(
                        child: Text(entry['description'],
                            style: TextStyle(
                                fontWeight: isOpening
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: fontSize)),
                      ),
                    ]),
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
                    (entry['balance'] as num)
                        .toStringAsFixed(2),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: fontSize)),
              ),
            ]),
          ));

          if (isPurchase && _isPurchaseExpanded(entry['purchaseId'])) {
            rows.add(_buildPurchaseItems(
                entry['purchaseId'], entry));
          }
          return rows;
        }).toList(),
        Container(
          color: Colors.grey[300],
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
                  child: const Text('',
                      style: TextStyle(fontSize: fontSize)),
                )),
            Expanded(
                flex: 2,
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

  Widget _buildDesktopLedgerView() {
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
            _buildEnhancedHeaderCell('Transaction', 2.0),
            _buildEnhancedHeaderCell('Description', 2.5),
            _buildEnhancedHeaderCell('Method', 1.2),
            _buildEnhancedHeaderCell('Bank', 1.8),
            _buildEnhancedHeaderCell('Qty', 0.8),
            _buildEnhancedHeaderCell('Weight', 0.8),
            _buildEnhancedHeaderCell('Debit (Rs)', 1.3),
            _buildEnhancedHeaderCell('Credit (Rs)', 1.3),
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
                ..._filteredLedgerEntries.asMap().entries.expand(
                      (entryWithIndex) {
                    final index = entryWithIndex.key;
                    final entry = entryWithIndex.value;
                    final rows = <Widget>[];
                    final isOpening =
                        entry['description'] == 'Opening Balance';
                    final isPurchase =
                        entry['description'] == 'Purchase';
                    final isEvenRow = index % 2 == 0;

                    rows.add(_buildEnhancedTransactionRow(
                        entry,
                        isOpening,
                        isPurchase,
                        isEvenRow
                            ? Colors.white
                            : Colors.grey[50]!));

                    if (isPurchase &&
                        _isPurchaseExpanded(entry['purchaseId'])) {
                      rows.add(Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: isEvenRow
                              ? Colors.orange[25]
                              : Colors.orange[50],
                          border: Border(
                              bottom: BorderSide(
                                  color: Colors.grey[300]!,
                                  width: 1)),
                        ),
                        child: _buildPurchaseItems(
                            entry['purchaseId'], entry),
                      ));
                    }
                    return rows;
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
                    _buildEnhancedDataCell('', 2.0, false,
                        backgroundColor: Colors.transparent),
                    _buildEnhancedDataCell('', 2.5, false,
                        backgroundColor: Colors.transparent),
                    _buildEnhancedDataCell('', 1.2, false,
                        backgroundColor: Colors.transparent),
                    _buildEnhancedDataCell('', 1.8, false,
                        backgroundColor: Colors.transparent),
                    _buildEnhancedDataCell('', 0.8, false,
                        backgroundColor: Colors.transparent),
                    _buildEnhancedDataCell('', 0.8, false,
                        backgroundColor: Colors.transparent),
                    _buildEnhancedDataCell(
                        'Rs ${_totalDebit.toStringAsFixed(2)}',
                        1.3,
                        false,
                        fontWeight: FontWeight.bold,
                        textColor: Colors.red[800],
                        backgroundColor: Colors.transparent),
                    _buildEnhancedDataCell(
                        'Rs ${_totalCredit.toStringAsFixed(2)}',
                        1.3,
                        false,
                        fontWeight: FontWeight.bold,
                        textColor: Colors.green[800],
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

  Widget _buildPurchaseItems(
      String purchaseId, Map<String, dynamic> entry) {
    final purchaseItems = _purchaseItems[purchaseId] ?? [];
    final refNo = entry['refNo']?.toString() ?? '';

    if (purchaseItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text('No items found for this purchase',
              style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(8),
              border:
              Border.all(color: const Color(0xFFFFB74D), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE65100),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shopping_cart,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('PURCHASE ITEMS DETAIL',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFFE65100),
                            letterSpacing: 0.5)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green[300]!),
                    ),
                    child: Text(
                        'Total: Rs ${entry['grandTotal']?.toStringAsFixed(2) ?? '0.00'}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.green[800])),
                  ),
                ]),
                if (refNo.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.confirmation_number,
                            size: 16, color: Colors.blue[700]),
                        const SizedBox(width: 6),
                        Text('Reference No: $refNo',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.blue[800],
                                fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: _buildEnhancedDesktopPurchaseTable(purchaseItems),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedDesktopPurchaseTable(
      List<Map<String, dynamic>> purchaseItems) {
    double totalQuantity = purchaseItems.fold(
        0.0, (s, it) => s + ((it['quantity'] ?? 0) as num).toDouble());
    double totalWeight = purchaseItems.fold(
        0.0,
            (s, it) =>
        s +
            ((it['quantity'] ?? 0) as num).toDouble() *
                ((it['weight'] ?? 0) as num).toDouble());
    double totalAmount = purchaseItems.fold(0.0, (s, it) {
      final q = ((it['quantity'] ?? 0) as num).toDouble();
      final w = ((it['weight'] ?? 0) as num).toDouble();
      final p = ((it['price'] ?? 0) as num).toDouble();
      return s + q * w * p;
    });

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        constraints: const BoxConstraints(minWidth: 1000),
        child: DataTable(
          columnSpacing: 20,
          dataRowHeight: 50,
          headingRowHeight: 48,
          headingRowColor:
          MaterialStateProperty.all(const Color(0xFFF5F5F5)),
          border: TableBorder.all(
              color: Colors.grey[300]!,
              borderRadius: BorderRadius.circular(4)),
          headingTextStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFFE65100),
              fontSize: 14,
              letterSpacing: 0.3),
          dataTextStyle:
          const TextStyle(fontSize: 13, color: Colors.black87),
          columns: const [
            DataColumn(
                label: SizedBox(
                    width: 150,
                    child: Text('Size (Item Name)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold)))),
            DataColumn(
                label: SizedBox(
                    width: 200,
                    child: Text('Description',
                        style: TextStyle(
                            fontWeight: FontWeight.bold)))),
            DataColumn(label: Text('Rate'), numeric: true),
            DataColumn(label: Text('Wt/Unit'), numeric: true),
            DataColumn(label: Text('Qty'), numeric: true),
            DataColumn(label: Text('Total Weight'), numeric: true),
            DataColumn(label: Text('Total Amount'), numeric: true),
          ],
          rows: [
            ...purchaseItems.map((item) {
              final q = ((item['quantity'] ?? 0) as num).toDouble();
              final w = ((item['weight'] ?? 0) as num).toDouble();
              final p = ((item['price'] ?? 0) as num).toDouble();
              final tw = q * w;
              final ta = tw * p;
              return DataRow(cells: [
                DataCell(SizedBox(
                    width: 150,
                    child: Text(
                        item['itemName']?.toString() ?? '-',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        style: const TextStyle(
                            fontWeight: FontWeight.w500)))),
                DataCell(SizedBox(
                    width: 200,
                    child: Text(
                        item['description']?.toString() ?? '-',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        style:
                        TextStyle(color: Colors.grey[700])))),
                DataCell(Text('Rs ${p.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500))),
                DataCell(Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.purple[50],
                      borderRadius: BorderRadius.circular(4)),
                  child: Text('${w.toStringAsFixed(2)} kg',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.purple[800])),
                )),
                DataCell(Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(q.toStringAsFixed(2),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[800])),
                )),
                DataCell(Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(4)),
                  child: Text('${tw.toStringAsFixed(2)} kg',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.orange[800])),
                )),
                DataCell(Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(4)),
                  child: Text('Rs ${ta.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800])),
                )),
              ]);
            }).toList(),
            DataRow(
              color: MaterialStateProperty.all(Colors.grey[100]),
              cells: [
                const DataCell(SizedBox(
                    width: 150,
                    child: Text('TOTAL',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE65100),
                            fontSize: 13)))),
                const DataCell(SizedBox(
                    width: 200, child: Text('-'))),
                const DataCell(Text('-')),
                DataCell(Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.purple[100],
                      borderRadius: BorderRadius.circular(4),
                      border:
                      Border.all(color: Colors.purple[300]!)),
                  child: Text('-',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.purple[900],
                          fontSize: 13)),
                )),
                DataCell(Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.blue[100],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue[300]!)),
                  child: Text(totalQuantity.toStringAsFixed(2),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[900],
                          fontSize: 13)),
                )),
                DataCell(Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange[300]!)),
                  child: Text(totalWeight.toStringAsFixed(2),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                          fontSize: 13)),
                )),
                DataCell(Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.green[300]!)),
                  child: Text('Rs ${totalAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[900],
                          fontSize: 13)),
                )),
              ],
            ),
          ],
        ),
      ),
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

  Widget _buildEnhancedTransactionRow(
      Map<String, dynamic> entry,
      bool isOpeningBalance,
      bool isPurchase,
      Color backgroundColor,
      ) {
    final dateText = isOpeningBalance
        ? entry['date']
        : _getFormattedDate(_getDisplayDate(entry), false);

    final bankName = _getBankName(entry);
    final bankLogoPath = _getBankLogoPath(bankName);
    final isExpanded = isPurchase && _isPurchaseExpanded(entry['purchaseId']);

    double quantity = 0.0;
    double weight = 0.0;
    if (isPurchase && _isPurchaseExpanded(entry['purchaseId'])) {
      final items = _purchaseItems[entry['purchaseId']] ?? [];
      quantity = items.fold(
          0.0, (s, it) => s + ((it['quantity'] ?? 0) as num).toDouble());
      weight = items.fold(
          0.0,
              (s, it) =>
          s +
              ((it['quantity'] ?? 0) as num).toDouble() *
                  ((it['weight'] ?? 0) as num).toDouble());
    }

    final credit = (entry['credit'] ?? 0) as num;
    final debit = (entry['debit'] ?? 0) as num;
    final balance = (entry['balance'] ?? 0) as num;

    return GestureDetector(
      onTap: isPurchase
          ? () => _togglePurchaseExpansion(entry['purchaseId'])
          : null,
      child: MouseRegion(
        cursor: isPurchase
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: Container(
          decoration: BoxDecoration(
            color: isOpeningBalance
                ? Colors.amber[50]
                : (isPurchase && isExpanded
                ? const Color(0xFFFFB74D).withOpacity(0.15)
                : backgroundColor),
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
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  if (isPurchase)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        icon: Icon(
                            isExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 18,
                            color: const Color(0xFFE65100)),
                        onPressed: () => _togglePurchaseExpansion(
                            entry['purchaseId']),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry['description'],
                            style: TextStyle(
                                fontWeight: isOpeningBalance
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isOpeningBalance
                                    ? Colors.orange[800]
                                    : Colors.black87),
                            overflow: TextOverflow.ellipsis),
                        if (isPurchase &&
                            entry['refNo'] != null &&
                            entry['refNo'].toString().isNotEmpty)
                          Text('Ref: ${entry['refNo']}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue[600],
                                  fontStyle: FontStyle.italic),
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              2.0,
              false,
            ),
            _buildEnhancedDataCell(
                entry['description2'] ?? '-', 2.5, false,
                textColor: Colors.grey[700]),
            _buildEnhancedDataCell(entry['method'] ?? '-', 1.2, false,
                textColor: Colors.grey[700]),
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
                        border:
                        Border.all(color: Colors.grey[300]!),
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
              1.8,
              false,
            ),
            _buildEnhancedDataCell(
                isPurchase ? quantity.toStringAsFixed(2) : '-',
                0.8, false,
                fontWeight:
                isPurchase ? FontWeight.w600 : FontWeight.normal,
                textColor: isPurchase
                    ? Colors.blue[700]
                    : Colors.grey[500]),
            _buildEnhancedDataCell(
                isPurchase ? weight.toStringAsFixed(2) : '-',
                0.8, false,
                fontWeight:
                isPurchase ? FontWeight.w600 : FontWeight.normal,
                textColor: isPurchase
                    ? Colors.orange[700]
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
                credit > 0 ? 'Rs ${credit.toStringAsFixed(2)}' : '-',
                1.3, false,
                fontWeight:
                credit > 0 ? FontWeight.w600 : FontWeight.normal,
                textColor: credit > 0
                    ? Colors.green[700]
                    : Colors.grey[500]),
            _buildEnhancedDataCell(
                'Rs ${balance.toStringAsFixed(2)}', 1.5, false,
                fontWeight: FontWeight.bold,
                textColor: balance >= 0
                    ? Colors.blue[700]
                    : Colors.orange[700]),
          ]),
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
        padding:
        const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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