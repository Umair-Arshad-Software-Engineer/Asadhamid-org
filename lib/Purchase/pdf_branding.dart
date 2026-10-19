import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shared Mughal Group PDF design (header, footer, banner, boxes) + caches.
class PdfBranding {
  PdfBranding._();

  // ───────────── Theme ─────────────
  static final navy = PdfColor.fromInt(0xFF0B2A5B);
  static final navyDark = PdfColor.fromInt(0xFF082247);
  static final orange = PdfColor.fromInt(0xFFF26B1D);
  static final softBg = PdfColor.fromInt(0xFFEEF3FA);
  static final softLine = PdfColor.fromInt(0xFFC9D4E5);
  static final grey = PdfColor.fromInt(0xFF5B6678);
  static const double pageW = 595.28;
  static const double headerH = 138;
  static const double footerH = 54;

  // ───────────── Caches ─────────────
  static pw.MemoryImage? _logo;
  static pw.Font? _italic;
  static bool _ready = false;
  static final Map<String, Future<pw.MemoryImage>> _textCache = {};
  static final RegExp _nonLatin = RegExp(r'[^\x00-\xFF]');

  /// Anything outside Latin-1 (e.g. Urdu) can't use the built-in PDF fonts.
  static bool needsImage(String t) => t.isNotEmpty && _nonLatin.hasMatch(t);

  /// Loads and decodes the logo once.
  static Future<void> ensureAssets() async {
    if (_ready) return;
    try {
      final data = await rootBundle.load('assets/images/logo.png');
      _logo = pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      _logo = null;
    }
    _italic = pw.Font.timesItalic();
    _ready = true;
  }

  /// Urdu-safe text rendered once as an image and cached by text + size.
  static Future<pw.MemoryImage> textImage(
      String text, {
        required double fontSize,
        required double width,
        required double height,
      }) {
    if (_textCache.length > 500) _textCache.clear();
    final key = '$fontSize|$width|$height|$text';
    return _textCache.putIfAbsent(key, () async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(Rect.fromLTWH(0, 0, width, height),
          Paint()..color = const Color(0xFFFFFFFF));
      final tp = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(color: const Color(0xFF000000), fontSize: fontSize)),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      );
      tp.layout(maxWidth: width - 4);
      tp.paint(canvas, Offset(2, (height - tp.height) / 2));
      final img =
      await recorder.endRecording().toImage(width.toInt(), height.toInt());
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      return pw.MemoryImage(bd!.buffer.asUint8List());
    });
  }

  // ───────────── Small helpers ─────────────
  static pw.Widget pad(pw.Widget w, {double v = 0}) => pw.Padding(
      padding: pw.EdgeInsets.symmetric(horizontal: 22, vertical: v), child: w);

  static pw.Widget txt(String t,
      {double size = 10,
        bool bold = false,
        PdfColor? color,
        pw.TextAlign? align}) =>
      pw.Text(t,
          textAlign: align,
          style: pw.TextStyle(
              fontSize: size,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color ?? PdfColors.black));

  static pw.Widget _dot() => pw.Container(
    width: 4,
    height: 4,
    margin: const pw.EdgeInsets.symmetric(horizontal: 5),
    decoration: pw.BoxDecoration(color: orange, shape: pw.BoxShape.circle),
  );

  static pw.Widget _slant(PdfColor c,
      {double w = 14, double h = 30, bool lean = true}) =>
      pw.CustomPaint(
        size: PdfPoint(w, h),
        painter: (PdfGraphics canvas, PdfPoint size) {
          canvas.setFillColor(c);
          if (lean) {
            canvas.moveTo(0, 0);
            canvas.lineTo(w * 0.55, 0);
            canvas.lineTo(w, h);
            canvas.lineTo(w * 0.45, h);
          } else {
            canvas.moveTo(w * 0.45, 0);
            canvas.lineTo(w, 0);
            canvas.lineTo(w * 0.55, h);
            canvas.lineTo(0, h);
          }
          canvas.closePath();
          canvas.fillPath();
        },
      );

  // ───────────── HEADER ─────────────
  static pw.Widget header() {
    final logoImage = _logo;
    return pw.SizedBox(
      width: pageW,
      height: headerH,
      child: pw.Stack(children: [
        pw.Positioned(
          left: 0,
          top: 0,
          child: pw.CustomPaint(
            size: const PdfPoint(pageW, headerH),
            painter: (PdfGraphics c, PdfPoint s) {
              c.setFillColor(orange);
              c.moveTo(382, 0);
              c.lineTo(410, 0);
              c.lineTo(458, headerH);
              c.lineTo(430, headerH);
              c.closePath();
              c.fillPath();

              c.setFillColor(navy);
              c.moveTo(410, 0);
              c.lineTo(pageW, 0);
              c.lineTo(pageW, headerH);
              c.lineTo(458, headerH);
              c.closePath();
              c.fillPath();
            },
          ),
        ),
        pw.Positioned(
          left: 0,
          bottom: 0,
          child: pw.Container(width: pageW, height: 5, color: navy),
        ),
        pw.Positioned(
          right: 16,
          top: 18,
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                txt('STRENGTH', size: 13, bold: true, color: PdfColors.white),
                txt('YOU CAN', size: 13, bold: true, color: PdfColors.white),
                txt('TRUST', size: 13, bold: true, color: PdfColors.white),
                pw.SizedBox(height: 3),
                pw.Container(width: 70, height: 1.5, color: orange),
              ]),
        ),
        pw.Positioned(
          right: 14,
          bottom: 16,
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('Mughal Group of Industries',
                    style: pw.TextStyle(
                        font: _italic ?? pw.Font.timesItalic(),
                        fontSize: 12,
                        color: PdfColors.white)),
                pw.SizedBox(height: 2),
                txt('IRON WIRE  -  BOLTS', size: 6.5, color: PdfColors.white),
              ]),
        ),
        pw.Positioned(
          left: 20,
          top: 14,
          child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                logoImage != null
                    ? pw.SizedBox(
                    width: 62,
                    height: 62,
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain))
                    : pw.Container(
                    width: 56,
                    height: 56,
                    decoration: pw.BoxDecoration(
                        color: orange, shape: pw.BoxShape.circle),
                    child: pw.Center(
                        child: txt('MGI',
                            size: 16, bold: true, color: PdfColors.white))),
                pw.SizedBox(width: 10),
                pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      txt('MUGHAL GROUP', size: 26, bold: true, color: navy),
                      txt('OF INDUSTRIES', size: 19, bold: true, color: navy),
                      pw.SizedBox(height: 5),
                      pw.Row(children: [
                        pw.Container(width: 24, height: 1, color: orange),
                        pw.SizedBox(width: 6),
                        txt('IRON WIRE', size: 11, bold: true, color: orange),
                        _dot(),
                        txt('BOLTS', size: 11, bold: true, color: orange),
                        pw.SizedBox(width: 6),
                        pw.Container(width: 24, height: 1, color: orange),
                      ]),
                      pw.SizedBox(height: 7),
                      pw.Row(children: [
                        txt('HAFIZ ASAD IDREES',
                            size: 8.5, bold: true, color: navy),
                        _dot(),
                        txt('M. HAMID KHALIL',
                            size: 8.5, bold: true, color: navy),
                      ]),
                      pw.SizedBox(height: 3),
                      txt('Hafizabad Road, Gujranwala, Pakistan',
                          size: 8.5, color: navy),
                      pw.SizedBox(height: 3),
                      txt('0370-4219219  |  0371-3084600',
                          size: 9.5, bold: true, color: navy),
                    ]),
              ]),
        ),
      ]),
    );
  }

  // ───────────── FOOTER ─────────────
  static pw.Widget footer() {
    pw.Widget line(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(children: [
        pw.Container(
            width: 6,
            height: 6,
            decoration: pw.BoxDecoration(
                color: PdfColors.white, shape: pw.BoxShape.circle)),
        pw.SizedBox(width: 8),
        txt(t, size: 8.5, color: PdfColors.white),
      ]),
    );

    final blue = PdfColor.fromInt(0xFF1565FF);

    return pw.SizedBox(
      width: pageW,
      height: footerH,
      child: pw.Stack(children: [
        pw.Positioned(
          left: 0,
          top: 0,
          child: pw.CustomPaint(
            size: const PdfPoint(pageW, footerH),
            painter: (PdfGraphics c, PdfPoint s) {
              c.setFillColor(navy);
              c.moveTo(0, 0);
              c.lineTo(pageW, 0);
              c.lineTo(pageW, footerH);
              c.lineTo(0, footerH);
              c.closePath();
              c.fillPath();

              c.setFillColor(navyDark);
              c.moveTo(372, 0);
              c.lineTo(pageW, 0);
              c.lineTo(pageW, footerH);
              c.lineTo(398, footerH);
              c.closePath();
              c.fillPath();

              c.setFillColor(orange);
              c.moveTo(360, 0);
              c.lineTo(372, 0);
              c.lineTo(398, footerH);
              c.lineTo(386, footerH);
              c.closePath();
              c.fillPath();
            },
          ),
        ),
        pw.Positioned(
          left: 22,
          top: 9,
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                line('0370-4219219 | 0371-3084600'),
                line('mughalgroupofindustrie@gmail.com'),
                line('Hafizabad Road, Gujranwala, Pakistan'),
              ]),
        ),
        pw.Positioned(
          right: 22,
          top: 7,
          child: pw.SizedBox(
            width: 120,
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.SizedBox(
                  width: 120,
                  height: 23,
                  child: pw.SvgImage(
                      svg: swittixSvgString, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Expanded(child: pw.Container(height: 1, color: blue)),
                    pw.SizedBox(width: 4),
                    pw.Text('TECHNOLOGIES',
                        style: pw.TextStyle(
                            fontSize: 6.5,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 1.2,
                            color: PdfColors.white)),
                    pw.SizedBox(width: 4),
                    pw.Expanded(child: pw.Container(height: 1, color: blue)),
                  ],
                ),
                pw.Text('WWW.SWITTIX.COM',
                    style: pw.TextStyle(
                        fontSize: 6.5,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1.2,
                        color: PdfColors.white)),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ───────────── Title banner ─────────────
  static pw.Widget titleBanner(String title) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        _slant(navy, w: 16),
        pw.SizedBox(width: 3),
        _slant(navy, w: 10),
        pw.SizedBox(width: 4),
        pw.Container(
          width: 330,
          height: 30,
          alignment: pw.Alignment.center,
          color: orange,
          child: txt(title, size: 18, bold: true, color: PdfColors.white),
        ),
        pw.SizedBox(width: 4),
        _slant(navy, w: 10, lean: false),
        pw.SizedBox(width: 3),
        _slant(navy, w: 16, lean: false),
      ]);

  // ───────────── Boxes / sections ─────────────
  static pw.Widget infoBox(String label, String value) => pw.Container(
    width: 175,
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: pw.BoxDecoration(
        color: softBg,
        border: pw.Border.all(color: softLine, width: 0.7),
        borderRadius: pw.BorderRadius.circular(6)),
    child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          txt(label, size: 9, color: grey),
          pw.SizedBox(height: 2),
          txt(value, size: 13, bold: true, color: navy),
        ]),
  );

  static pw.Widget sectionHeader(String title) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: pw.BoxDecoration(
        color: navy,
        borderRadius: const pw.BorderRadius.only(
            topLeft: pw.Radius.circular(8), topRight: pw.Radius.circular(8))),
    child: txt(title, size: 11, bold: true, color: PdfColors.white),
  );

  static pw.Widget sectionBody(pw.Widget child) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: pw.BoxDecoration(
        border: pw.Border.all(color: navy, width: 0.8),
        borderRadius: const pw.BorderRadius.only(
            bottomLeft: pw.Radius.circular(8),
            bottomRight: pw.Radius.circular(8))),
    child: child,
  );

  /// Labeled, underlined field (uses an image only when the text is Urdu).
  static pw.Widget field(String label,
      {pw.MemoryImage? img, String text = ''}) {
    final pw.Widget value = img != null
        ? pw.SizedBox(
        height: 22,
        child: pw.Image(img,
            fit: pw.BoxFit.contain, alignment: pw.Alignment.centerLeft))
        : txt(text, size: 10);

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.SizedBox(width: 78, child: txt(label, size: 10)),
        txt(':  ', size: 10),
        pw.Expanded(
          child: pw.Container(
            height: 24,
            alignment: pw.Alignment.bottomLeft,
            decoration: pw.BoxDecoration(
                border:
                pw.Border(bottom: pw.BorderSide(color: navy, width: 0.5))),
            child: value,
          ),
        ),
      ]),
    );
  }

  static pw.Widget boxTitle(String t) => pw.Row(children: [
    pw.Container(
        width: 16,
        height: 16,
        decoration: pw.BoxDecoration(
            color: orange, borderRadius: pw.BorderRadius.circular(3))),
    pw.SizedBox(width: 8),
    txt(t, size: 11, bold: true, color: navy),
  ]);

  static pw.Widget framed(pw.Widget child) => pw.Container(
    height: 122,
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
        border: pw.Border.all(color: softLine, width: 1),
        borderRadius: pw.BorderRadius.circular(8)),
    child: child,
  );

  static pw.Widget sumRow(String label, String value,
      {bool big = false, PdfColor? color, bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(children: [
          pw.SizedBox(
              width: 85, child: txt(label, size: big ? 11 : 10, bold: big)),
          txt(':   ', size: 10),
          pw.Expanded(
              child: txt(value,
                  size: big ? 15 : 10.5, bold: big || bold, color: color)),
        ]),
      );

  static pw.Widget acctRow(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
    child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [txt(label, size: 9.5), txt(value, size: 9.5)]),
  );

  // ───────────── Table cells ─────────────
  static pw.Widget headCell(String t) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 2),
    alignment: pw.Alignment.center,
    child: pw.Text(t,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white)),
  );

  static pw.Widget cell(String t, {bool bold = false}) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 2),
    alignment: pw.Alignment.center,
    child: pw.Text(t,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
            fontSize: 9,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
  );

  static pw.Widget imgCell(pw.MemoryImage? image, String fallback,
      {double h = 18}) {
    if (image == null) return cell(fallback);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: pw.SizedBox(
          height: h, child: pw.Image(image, fit: pw.BoxFit.contain)),
    );
  }

  // ───────────── Swittix SVG logo ─────────────
  static String _swittixSvg({
    String letters = '#FFFFFF',
    String blue = '#1565FF',
    String swoosh = '#5B8CFF',
  }) {
    const tPath =
        'M1217 120 Q1217 106 1230 92 L1272 50 V170 H1397 L1355 218 H1272 L1270 330 Q1272 362 1290 377 L1360 382 V432 H1320 Q1245 432 1217 380 V218 H1127 L1170 170 H1217 Z';

    return '''
<svg viewBox="0 0 2378 450" xmlns="http://www.w3.org/2000/svg">
  <g fill="{{B}}">
    <rect x="104" y="62" width="25" height="26"/>
    <rect x="45" y="90" width="33" height="34"/>
    <rect x="148" y="91" width="30" height="30"/>
    <rect x="100" y="123" width="40" height="33"/>
    <rect x="55" y="166" width="43" height="43"/>
    <path d="M112 210 L128 214 L140 230 L116 226 Z"/>
  </g>
  <g fill="{{L}}">
    <path d="M255 72 H585 L507 153 H270 Q232 153 232 190 Q236 217 262 217 H440 Q540 222 540 300 Q536 345 520 370 Q482 430 425 432 H97 L187 345 L190 362 H412 Q446 355 445 322 Q440 297 425 297 H225 Q150 285 145 225 Q145 175 185 150 L186 105 Q205 80 255 72 Z"/>
  </g>
  <polygon points="528,152 600,72 656,72 578,152" fill="{{B}}"/>
  <path fill="{{L}}" d="M555 177 H628 L706 322 L780 208 L858 322 L935 177 H1002 L862 432 H858 L780 300 L698 432 H694 Z"/>
  <g fill="{{L}}">
    <rect x="1033" y="76" width="56" height="62"/>
    <path d="M1033 215 L1085 172 H1090 V432 H1033 Z"/>
    <path d="$tPath"/>
    <g transform="translate(265 0)"><path d="$tPath"/></g>
    <rect x="1697" y="76" width="58" height="62"/>
    <path d="M1697 215 L1750 172 H1755 V432 H1697 Z"/>
  </g>
  <path fill="{{L}}" d="M1830 197 H1932 L1996 265 L1932 313 L1882 432 H1797 L1930 315 Z"/>
  <polygon points="1978,365 2050,322 2142,432 2042,432" fill="{{B}}"/>
  <path d="M1995 265 Q2150 130 2330 78 Q2150 172 2000 272 Z" fill="{{S}}"/>
  <path d="M1978 362 Q2085 250 2212 175 Q2130 232 2052 322 Z" fill="{{B}}"/>
</svg>'''
        .replaceAll('{{L}}', letters)
        .replaceAll('{{B}}', blue)
        .replaceAll('{{S}}', swoosh);
  }

  static final String swittixSvgString = _swittixSvg();
}