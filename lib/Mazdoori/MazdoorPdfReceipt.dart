// MazdoorPdfReceipt.dart
// Builds Mazdoor receipt / statement PDFs using the same Mughal Group
// design (PdfBranding) as the purchase page.
import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../Purchase/pdf_branding.dart'; // adjust path if needed

/// Plain data the single-receipt builder needs.
class MazdoorReceiptData {
  final String mazdoorName;
  final String mazdoorPhone;
  final String mazdoorAddress;
  final String mazdoorCity;
  final String mazdoorSerial;

  final String entryType;
  final String reference;
  final String description;
  final DateTime when;

  final String itemName;
  final double? quantity;
  final double? rate;
  final double? weightPerUnit;
  final double? totalWeight;
  final String batch;

  /// 'bolt' | 'wire' | 'cash'
  final String kind;

  final double amount;
  final double previousBalance;
  final double currentBalance;

  final List<Map<String, dynamic>> wireLines;

  MazdoorReceiptData({
    required this.mazdoorName,
    required this.mazdoorPhone,
    required this.mazdoorAddress,
    required this.mazdoorCity,
    required this.mazdoorSerial,
    required this.entryType,
    required this.reference,
    required this.description,
    required this.when,
    required this.itemName,
    required this.quantity,
    required this.rate,
    required this.weightPerUnit,
    required this.totalWeight,
    required this.batch,
    required this.kind,
    required this.amount,
    required this.previousBalance,
    required this.currentBalance,
    required this.wireLines,
  });
}

class MazdoorPdfReceipt {
  MazdoorPdfReceipt._();

  // ── Global caches ──
  static String? _lastSig;
  static Uint8List? _lastBytes;

  static String _fmtQty(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);

  static String _balanceText(double b) {
    if (b.abs() < 0.005) return 'Settled';
    return b > 0
        ? '${b.toStringAsFixed(2)} PKR (owes you)'
        : '${(-b).toStringAsFixed(2)} PKR (you owe)';
  }

  static String _titleFor(String entryType) {
    switch (entryType) {
      case 'wire_given':
        return 'WIRE GIVEN';
      case 'bolt_given':
        return 'BOLTS GIVEN';
      case 'cash_given':
        return 'CASH GIVEN';
      case 'adjustment':
        return 'ADVANCE GIVEN';
      case 'wire_return':
        return 'WIRE RECEIVED';
      case 'bolt_return':
        return 'BOLTS RECEIVED';
      case 'cash_payment':
        return 'CASH RECEIVED';
    }
    return 'MAZDOOR TRANSACTION';
  }

  static bool _isGiven(String entryType) =>
      entryType == 'wire_given' ||
          entryType == 'bolt_given' ||
          entryType == 'cash_given' ||
          entryType == 'adjustment';

  // ═════════════════════════════════════════════════════════════
  // SINGLE RECEIPT
  // ═════════════════════════════════════════════════════════════
  static Future<Uint8List> build(MazdoorReceiptData d) async {
    await PdfBranding.ensureAssets();

    final isWire = d.kind == 'wire';
    final isCash = d.kind == 'cash';
    final isGive = _isGiven(d.entryType);
    final title = _titleFor(d.entryType);

    final signature = '${d.reference}|${d.entryType}|${d.amount}|'
        '${d.when.toIso8601String()}|${d.previousBalance}|'
        '${d.currentBalance}|${d.itemName}|${d.quantity}|${d.rate}|'
        '${d.wireLines.length}';
    if (_lastSig == signature && _lastBytes != null) return _lastBytes!;

    String two(int n) => n.toString().padLeft(2, '0');
    final w = d.when;
    final dateText = '${w.year}-${two(w.month)}-${two(w.day)} '
        '${two(w.hour)}:${two(w.minute)}';

    final name = d.mazdoorName.trim();
    final address = [
      d.mazdoorAddress.trim(),
      d.mazdoorCity.trim(),
    ].where((s) => s.isNotEmpty).join(', ');

    final jobs = <Future<void>>[];
    Map<String, pw.MemoryImage> prepare(
        Iterable<String> texts, double fs, double w, double h) {
      final m = <String, pw.MemoryImage>{};
      for (final raw in texts) {
        final t = raw.trim();
        if (!PdfBranding.needsImage(t) || m.containsKey(t)) continue;
        jobs.add(PdfBranding.textImage(t, fontSize: fs, width: w, height: h)
            .then((img) => m[t] = img));
      }
      return m;
    }

    final rowSizeImgs = prepare(
        d.wireLines.isNotEmpty
            ? d.wireLines.map((l) => l['itemName']?.toString() ?? '')
            : [d.itemName],
        42,
        228,
        66);
    final rowLengthImgs = prepare(
        d.wireLines.map((l) => l['length']?.toString() ?? ''),
        42,
        201,
        66);
    final rowBodyImgs = prepare(
        d.wireLines.map((l) => l['bodyType']?.toString() ?? ''),
        42,
        144,
        66);
    final rowDescImgs = prepare([d.description], 11, 110, 20);
    final fieldImgs =
    prepare([name, address, d.description], 42, 165 * 3, 66);
    await Future.wait(jobs);

    pw.Widget fieldFor(String label, String text) =>
        PdfBranding.field(label, img: fieldImgs[text.trim()], text: text);

    pw.Widget mazdoorSection() => pw.Column(children: [
      PdfBranding.sectionHeader('MAZDOOR DETAILS'),
      PdfBranding.sectionBody(pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
                child: pw.Column(children: [
                  fieldFor('Mazdoor Name', name),
                  PdfBranding.field('Mazdoor #',
                      text: d.mazdoorSerial.isEmpty ? '-' : d.mazdoorSerial),
                  PdfBranding.field('Transaction',
                      text: isGive
                          ? 'Given to Mazdoor'
                          : 'Received from Mazdoor'),
                ])),
            pw.SizedBox(width: 18),
            pw.Expanded(
                child: pw.Column(children: [
                  PdfBranding.field('Phone Number',
                      text: d.mazdoorPhone.isEmpty ? '-' : d.mazdoorPhone),
                  fieldFor('Address', address.isEmpty ? '-' : address),
                  PdfBranding.field('Reference',
                      text: d.reference.isEmpty ? '-' : d.reference),
                ])),
          ])),
    ]);

    pw.Widget itemsSection() {
      final headers = isWire
          ? [
        'No.',
        'Size',
        'Length',
        'Body Type',
        'Desc.',
        'Rate\n(PKR/KG)',
        'Wt/Unit\n(KG)',
        'Qty',
        'Tot.Wt\n(KG)',
        'Amount\n(PKR)',
      ]
          : [
        'No.',
        'Size',
        'Length',
        'Body Type',
        'Desc.',
        'Rate\n(PKR)',
        'Qty',
        'Amount\n(PKR)',
      ];

      final widths = isWire
          ? const {
        0: pw.FlexColumnWidth(0.6),
        1: pw.FlexColumnWidth(1.8),
        2: pw.FlexColumnWidth(1.6),
        3: pw.FlexColumnWidth(1.2),
        4: pw.FlexColumnWidth(1.4),
        5: pw.FlexColumnWidth(1.1),
        6: pw.FlexColumnWidth(1.1),
        7: pw.FlexColumnWidth(0.8),
        8: pw.FlexColumnWidth(1.1),
        9: pw.FlexColumnWidth(1.4),
      }
          : const {
        0: pw.FlexColumnWidth(0.6),
        1: pw.FlexColumnWidth(2.2),
        2: pw.FlexColumnWidth(1.6),
        3: pw.FlexColumnWidth(1.3),
        4: pw.FlexColumnWidth(1.8),
        5: pw.FlexColumnWidth(1.2),
        6: pw.FlexColumnWidth(0.9),
        7: pw.FlexColumnWidth(1.5),
      };

      final rows = <Map<String, dynamic>>[];
      if (isWire && d.wireLines.isNotEmpty) {
        for (final l in d.wireLines) {
          rows.add({
            'item': l['itemName']?.toString() ?? '',
            'length': l['length']?.toString() ?? '',
            'body': l['bodyType']?.toString() ?? '',
            'desc': d.description,
            'rate': (l['rate'] as num?)?.toDouble() ?? (d.rate ?? 0.0),
            'wpu': (l['weightPerUnit'] as num?)?.toDouble() ?? 0.0,
            'qty': (l['qty'] as num?)?.toDouble() ?? 0.0,
            'tw': (l['totalWeight'] as num?)?.toDouble() ?? 0.0,
            'amt': 0.0,
          });
        }
      } else {
        rows.add({
          'item': d.itemName,
          'length': '',
          'body': '',
          'desc': d.description,
          'rate': d.rate ?? 0.0,
          'wpu': d.weightPerUnit ?? 0.0,
          'qty': d.quantity ?? 0.0,
          'tw': d.totalWeight ?? 0.0,
          'amt': d.amount,
        });
      }

      double running = 0;
      for (int i = 0; i < rows.length; i++) {
        final r = rows[i];
        double amt;
        if (i == rows.length - 1) {
          amt = d.amount - running;
        } else {
          final rate = r['rate'] as double;
          final qty = r['qty'] as double;
          final tw = r['tw'] as double;
          amt = isWire ? (tw > 0 ? tw * rate : qty * rate) : qty * rate;
          running += amt;
        }
        r['amt'] = amt;
      }

      const minRows = 8;
      final rowCount = rows.length > minRows ? rows.length : minRows;

      pw.TableRow dataRow(int i) {
        final r = rows[i];
        final item = r['item'] as String;
        final length = r['length'] as String;
        final body = r['body'] as String;
        final desc = r['desc'] as String;
        final rate = r['rate'] as double;
        final wpu = r['wpu'] as double;
        final qty = r['qty'] as double;
        final tw = r['tw'] as double;
        final amt = r['amt'] as double;

        return pw.TableRow(
          decoration: pw.BoxDecoration(
              color: i.isEven ? PdfColors.white : PdfBranding.softBg),
          children: [
            PdfBranding.cell('${i + 1}'),
            PdfBranding.imgCell(rowSizeImgs[item.trim()], item, h: 22),
            PdfBranding.imgCell(rowLengthImgs[length.trim()], length, h: 22),
            PdfBranding.imgCell(rowBodyImgs[body.trim()], body, h: 22),
            PdfBranding.imgCell(rowDescImgs[desc.trim()], desc),
            PdfBranding.cell(rate.toStringAsFixed(2)),
            if (isWire)
              PdfBranding.cell(wpu > 0 ? wpu.toStringAsFixed(2) : '-'),
            PdfBranding.cell(_fmtQty(qty)),
            if (isWire)
              PdfBranding.cell(tw > 0 ? tw.toStringAsFixed(2) : '-'),
            PdfBranding.cell(amt.toStringAsFixed(2), bold: true),
          ],
        );
      }

      pw.TableRow emptyRow(int i) => pw.TableRow(
        decoration: pw.BoxDecoration(
            color: i.isEven ? PdfColors.white : PdfBranding.softBg),
        children: [
          PdfBranding.cell('${i + 1}'),
          for (int k = 0; k < headers.length - 1; k++)
            PdfBranding.cell(''),
        ],
      );

      return pw.Column(children: [
        PdfBranding.sectionHeader(
            isWire ? 'WIRE DETAILS' : 'BOLT DETAILS'),
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
          columnWidths: widths,
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfBranding.orange),
              children: headers.map(PdfBranding.headCell).toList(),
            ),
            for (int i = 0; i < rowCount; i++)
              i < rows.length ? dataRow(i) : emptyRow(i),
          ],
        ),
      ]);
    }

    pw.Widget cashSection() => pw.Column(children: [
      PdfBranding.sectionHeader('PAYMENT DETAILS'),
      PdfBranding.sectionBody(pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
                child: pw.Column(children: [
                  PdfBranding.field('Date & Time', text: dateText),
                  fieldFor('Description',
                      d.description.isEmpty ? '-' : d.description),
                ])),
            pw.SizedBox(width: 18),
            pw.Expanded(
                child: pw.Column(children: [
                  PdfBranding.field('Amount',
                      text: '${d.amount.toStringAsFixed(2)} PKR'),
                  PdfBranding.field('Transaction',
                      text: isGive ? 'Cash Given' : 'Cash Received'),
                ])),
          ])),
    ]);

    final totalQty = d.quantity ?? 0.0;
    final totalWt = d.totalWeight ?? 0.0;

    pw.Widget summaryBox() => PdfBranding.framed(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          PdfBranding.boxTitle('TOTAL SUMMARY'),
          pw.SizedBox(height: 6),
          pw.Expanded(
            child: pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8),
              color: PdfBranding.softBg,
              child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: isCash
                      ? [
                    PdfBranding.sumRow(
                        'Amount', '${d.amount.toStringAsFixed(2)} PKR',
                        big: true, color: PdfBranding.orange),
                  ]
                      : [
                    PdfBranding.sumRow('Total Items', '1',
                        bold: true),
                    if (isWire)
                      PdfBranding.sumRow(
                          'Total Weight',
                          '${totalWt.toStringAsFixed(2)} KG',
                          bold: true)
                    else
                      PdfBranding.sumRow(
                          'Total Quantity', _fmtQty(totalQty),
                          bold: true),
                    PdfBranding.sumRow(
                        'Total Value',
                        '${d.amount.toStringAsFixed(2)} PKR',
                        big: true,
                        color: PdfBranding.orange),
                  ]),
            ),
          ),
        ]));

    pw.Widget accountBox() => PdfBranding.framed(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          PdfBranding.boxTitle('MAZDOOR ACCOUNT'),
          pw.SizedBox(height: 6),
          PdfBranding.acctRow(
              'Previous Balance', _balanceText(d.previousBalance)),
          PdfBranding.acctRow(
              title, '${d.amount.toStringAsFixed(2)} PKR'),
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
                  PdfBranding.txt('Current Balance',
                      size: 10, bold: true, color: PdfColors.white),
                  PdfBranding.txt(_balanceText(d.currentBalance),
                      size: 10.5, bold: true, color: PdfColors.white),
                ]),
          ),
        ]));

    final noteText = [
      if (!isCash) 'Weight and Amount are calculated automatically.',
      if (d.batch.isNotEmpty) 'Batch: ${d.batch}',
    ].join('   |   ');

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        header: (ctx) => ctx.pageNumber == 1
            ? PdfBranding.header()
            : pw.SizedBox(height: 18),
        footer: (ctx) => PdfBranding.footer(),
        build: (ctx) => [
          PdfBranding.pad(PdfBranding.titleBanner(title), v: 10),
          PdfBranding.pad(pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                PdfBranding.infoBox('Transaction', title),
                PdfBranding.infoBox('Date & Time', dateText),
              ])),
          pw.SizedBox(height: 10),
          PdfBranding.pad(mazdoorSection()),
          pw.SizedBox(height: 12),
          PdfBranding.pad(isCash ? cashSection() : itemsSection()),
          if (noteText.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            PdfBranding.pad(PdfBranding.txt(noteText,
                size: 7.5, color: PdfBranding.grey)),
          ],
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

    final bytes = await pdf.save();
    _lastSig = signature;
    _lastBytes = bytes;
    return bytes;
  }

  /// Loads a Mazdoor person + the balance snapshot for a ledger entry
  /// and returns ready-to-use [MazdoorReceiptData].
  static Future<MazdoorReceiptData> fromLedgerEntry({
    required DatabaseReference db,
    required String mazdoorId,
    required Map<String, dynamic> entry,
  }) async {
    Map<String, dynamic> person = {};
    try {
      final snap = await db.child('mazdoors').child(mazdoorId).get();
      if (snap.exists && snap.value is Map) {
        person = Map<String, dynamic>.from(snap.value as Map);
      }
    } catch (_) {}

    final double debit =
        (entry['debitFromMazdoor'] as num?)?.toDouble() ?? 0.0;
    final double credit =
        (entry['creditToMazdoor'] as num?)?.toDouble() ?? 0.0;
    final double currentBal =
        (entry['remainingBalance'] as num?)?.toDouble() ?? 0.0;
    final double previousBal = currentBal - debit + credit;

    final entryType = entry['entryType']?.toString() ?? 'adjustment';
    final kind = entryType.startsWith('bolt')
        ? 'bolt'
        : entryType.startsWith('wire')
        ? 'wire'
        : 'cash';

    final isGiven = _isGiven(entryType);
    final amount = isGiven ? debit : credit;

    final lines = <Map<String, dynamic>>[];
    if (entry['wireLines'] is List) {
      for (final l in entry['wireLines'] as List) {
        if (l is Map) lines.add(Map<String, dynamic>.from(l));
      }
    }

    final batch = lines
        .map((l) => l['batchNumber']?.toString() ?? '')
        .where((b) => b.isNotEmpty && b != 'null')
        .toSet()
        .join(', ');

    DateTime when;
    final ts = entry['createdAt']?.toString();
    when = (ts != null ? DateTime.tryParse(ts) : null) ?? DateTime.now();

    return MazdoorReceiptData(
      mazdoorName: person['name']?.toString() ?? '',
      mazdoorPhone: person['phone']?.toString() ?? '',
      mazdoorAddress: person['address']?.toString() ?? '',
      mazdoorCity: person['city']?.toString() ?? '',
      mazdoorSerial: person['mazdoorSerial']?.toString() ?? '',
      entryType: entryType,
      reference: (entry['reference'] ?? entry['jobNumber'])?.toString() ?? '',
      description: entry['description']?.toString() ?? '',
      when: when,
      itemName: entry['itemName']?.toString() ?? '',
      quantity: (entry['quantity'] as num?)?.toDouble(),
      rate: (entry['rate'] as num?)?.toDouble(),
      weightPerUnit: (entry['weightPerUnit'] as num?)?.toDouble(),
      totalWeight: (entry['totalWeight'] as num?)?.toDouble(),
      batch: batch,
      kind: kind,
      amount: amount,
      previousBalance: previousBal,
      currentBalance: currentBal,
      wireLines: lines,
    );
  }

  // ═════════════════════════════════════════════════════════════
  // STATEMENT (all Given + Received for one Mazdoor)
  // ═════════════════════════════════════════════════════════════
  static Future<Uint8List> buildStatement({
    required String mazdoorName,
    required String mazdoorPhone,
    required String mazdoorAddress,
    required String mazdoorCity,
    required String mazdoorSerial,
    required double openingBalance,
    required double currentBalance,
    required List<Map<String, dynamic>> entries,
    DateTime? asOf,
  }) async {
    await PdfBranding.ensureAssets();

    final when = asOf ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final dateText =
        '${when.year}-${two(when.month)}-${two(when.day)} '
        '${two(when.hour)}:${two(when.minute)}';

    final sorted = List<Map<String, dynamic>>.from(entries);
    DateTime dtOf(Map m) {
      final s = m['createdAt']?.toString();
      return (s != null ? DateTime.tryParse(s) : null) ?? DateTime(2000);
    }

    sorted.sort((a, b) => dtOf(a).compareTo(dtOf(b)));

    final name = mazdoorName.trim();
    final address = [
      mazdoorAddress.trim(),
      mazdoorCity.trim(),
    ].where((s) => s.isNotEmpty).join(', ');

    final jobs = <Future<void>>[];
    Map<String, pw.MemoryImage> prepare(
        Iterable<String> texts, double fs, double w, double h) {
      final m = <String, pw.MemoryImage>{};
      for (final raw in texts) {
        final t = raw.trim();
        if (!PdfBranding.needsImage(t) || m.containsKey(t)) continue;
        jobs.add(PdfBranding.textImage(t, fontSize: fs, width: w, height: h)
            .then((img) => m[t] = img));
      }
      return m;
    }

    final itemImgs = prepare(
        sorted.map((e) => e['itemName']?.toString() ?? ''), 42, 228, 66);
    final fieldImgs = prepare([name, address], 42, 165 * 3, 66);
    await Future.wait(jobs);

    pw.Widget fieldFor(String label, String text) =>
        PdfBranding.field(label, img: fieldImgs[text.trim()], text: text);

    pw.Widget mazdoorSection() => pw.Column(children: [
      PdfBranding.sectionHeader('MAZDOOR DETAILS'),
      PdfBranding.sectionBody(pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
                child: pw.Column(children: [
                  fieldFor('Mazdoor Name', name),
                  PdfBranding.field('Mazdoor #',
                      text: mazdoorSerial.isEmpty ? '-' : mazdoorSerial),
                ])),
            pw.SizedBox(width: 18),
            pw.Expanded(
                child: pw.Column(children: [
                  PdfBranding.field('Phone Number',
                      text: mazdoorPhone.isEmpty ? '-' : mazdoorPhone),
                  fieldFor('Address', address.isEmpty ? '-' : address),
                ])),
          ])),
    ]);

    pw.Widget statementSection() {
      const headers = [
        'Date',
        'Type',
        'Reference',
        'Item',
        'Qty',
        'Rate',
        'Amount\n(PKR)',
        'Balance\n(PKR)',
      ];
      final widths = const {
        0: pw.FlexColumnWidth(1.6),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(1.4),
        3: pw.FlexColumnWidth(2.4),
        4: pw.FlexColumnWidth(0.8),
        5: pw.FlexColumnWidth(1.0),
        6: pw.FlexColumnWidth(1.2),
        7: pw.FlexColumnWidth(1.3),
      };

      String typeLabel(String t) {
        switch (t) {
          case 'wire_given':
            return 'Wire Given';
          case 'bolt_given':
            return 'Bolts Given';
          case 'cash_given':
            return 'Cash Given';
          case 'adjustment':
            return 'Advance';
          case 'wire_return':
            return 'Wire Received';
          case 'bolt_return':
            return 'Bolts Received';
          case 'cash_payment':
            return 'Cash Received';
          case 'opening_balance':
            return 'Opening';
        }
        return t;
      }

      final rows = <pw.TableRow>[];
      if (openingBalance.abs() > 0.005) {
        rows.add(pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfBranding.softBg),
          children: [
            PdfBranding.cell('-'),
            PdfBranding.cell('Opening'),
            PdfBranding.cell('-'),
            PdfBranding.cell('Opening Balance'),
            PdfBranding.cell('-'),
            PdfBranding.cell('-'),
            PdfBranding.cell(openingBalance.toStringAsFixed(2)),
            PdfBranding.cell(openingBalance.toStringAsFixed(2),
                bold: true),
          ],
        ));
      }

      for (int i = 0; i < sorted.length; i++) {
        final e = sorted[i];
        final entryType = e['entryType']?.toString() ?? '';
        final isGiven = entryType == 'wire_given' ||
            entryType == 'bolt_given' ||
            entryType == 'cash_given' ||
            entryType == 'adjustment';
        final debit = (e['debitFromMazdoor'] as num?)?.toDouble() ?? 0.0;
        final credit =
            (e['creditToMazdoor'] as num?)?.toDouble() ?? 0.0;
        final amount = isGiven ? debit : credit;
        final bal = (e['remainingBalance'] as num?)?.toDouble() ?? 0.0;

        final dateStr = DateFormat('dd/MM/yy').format(dtOf(e));
        final itemName = e['itemName']?.toString() ?? '';
        final desc = e['description']?.toString() ?? '';
        final itemText = itemName.isNotEmpty ? itemName : desc;

        final qty = (e['quantity'] as num?)?.toDouble();
        final rate = (e['rate'] as num?)?.toDouble();
        final tw = (e['totalWeight'] as num?)?.toDouble();

        String qtyText = '-';
        if (tw != null && tw > 0) {
          qtyText = '${tw.toStringAsFixed(2)} kg';
        } else if (qty != null && qty > 0) {
          qtyText = _fmtQty(qty);
        }

        rows.add(pw.TableRow(
          decoration: pw.BoxDecoration(
              color: i.isEven ? PdfColors.white : PdfBranding.softBg),
          children: [
            PdfBranding.cell(dateStr),
            PdfBranding.cell(typeLabel(entryType)),
            PdfBranding.cell(
                (e['reference'] ?? e['jobNumber'])?.toString() ?? ''),
            PdfBranding.imgCell(
                itemImgs[itemText.trim()], itemText,
                h: 18),
            PdfBranding.cell(qtyText),
            PdfBranding.cell(
                rate != null && rate > 0 ? rate.toStringAsFixed(2) : '-'),
            PdfBranding.cell(
                '${isGiven ? '+' : '-'}${amount.toStringAsFixed(2)}',
                bold: true),
            PdfBranding.cell(bal.toStringAsFixed(2), bold: true),
          ],
        ));
      }

      return pw.Column(children: [
        PdfBranding.sectionHeader('TRANSACTIONS STATEMENT'),
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
          columnWidths: widths,
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfBranding.orange),
              children: headers.map(PdfBranding.headCell).toList(),
            ),
            ...rows,
          ],
        ),
      ]);
    }

    final totalGiven = sorted.fold<double>(0.0, (s, e) {
      final t = e['entryType']?.toString() ?? '';
      if (t == 'wire_given' ||
          t == 'bolt_given' ||
          t == 'cash_given' ||
          t == 'adjustment') {
        return s + ((e['debitFromMazdoor'] as num?)?.toDouble() ?? 0.0);
      }
      return s;
    });
    final totalReceived = sorted.fold<double>(0.0, (s, e) {
      final t = e['entryType']?.toString() ?? '';
      if (t == 'wire_return' ||
          t == 'bolt_return' ||
          t == 'cash_payment') {
        return s + ((e['creditToMazdoor'] as num?)?.toDouble() ?? 0.0);
      }
      return s;
    });

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
                        'Total Entries', '${sorted.length}',
                        bold: true),
                    PdfBranding.sumRow(
                        'Total Given',
                        '${totalGiven.toStringAsFixed(2)} PKR',
                        bold: true),
                    PdfBranding.sumRow(
                        'Total Received',
                        '${totalReceived.toStringAsFixed(2)} PKR',
                        bold: true),
                  ]),
            ),
          ),
        ]));

    pw.Widget balanceBox() => PdfBranding.framed(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          PdfBranding.boxTitle('MAZDOOR ACCOUNT'),
          pw.SizedBox(height: 6),
          PdfBranding.acctRow(
              'Opening Balance', _balanceText(openingBalance)),
          PdfBranding.acctRow(
              'Total Given', '${totalGiven.toStringAsFixed(2)} PKR'),
          PdfBranding.acctRow(
              'Total Received', '${totalReceived.toStringAsFixed(2)} PKR'),
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
                  PdfBranding.txt(_balanceText(currentBalance),
                      size: 10.5, bold: true, color: PdfColors.white),
                ]),
          ),
        ]));

    final pdf = pw.Document();
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
              PdfBranding.titleBanner('MAZDOOR STATEMENT'), v: 10),
          PdfBranding.pad(pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                PdfBranding.infoBox('Mazdoor', name),
                PdfBranding.infoBox('Date & Time', dateText),
              ])),
          pw.SizedBox(height: 10),
          PdfBranding.pad(mazdoorSection()),
          pw.SizedBox(height: 12),
          PdfBranding.pad(statementSection()),
          pw.SizedBox(height: 8),
          PdfBranding.pad(pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: summaryBox()),
                pw.SizedBox(width: 12),
                pw.Expanded(child: balanceBox()),
              ])),
        ],
      ),
    );

    return pdf.save();
  }
}