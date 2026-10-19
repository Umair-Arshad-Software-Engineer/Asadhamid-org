// mazdoorTransactionsListPage.dart
// Lists every saved "Given" and "Received" record from mazdoorLedger.
import 'dart:typed_data';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

import '../Provider/Mazdoorprovider ·.dart';
import '../Provider/lanprovider.dart';
import 'MazdoorPdfReceipt.dart';

enum MazdoorTxnMode { given, received }

class MazdoorGivenListPage extends StatelessWidget {
  final String? mazdoorId;
  final String? mazdoorName;
  const MazdoorGivenListPage({Key? key, this.mazdoorId, this.mazdoorName})
      : super(key: key);

  @override
  Widget build(BuildContext context) => MazdoorTransactionsPage(
    mode: MazdoorTxnMode.given,
    mazdoorId: mazdoorId,
    mazdoorName: mazdoorName,
  );
}

class MazdoorReceivedListPage extends StatelessWidget {
  final String? mazdoorId;
  final String? mazdoorName;
  const MazdoorReceivedListPage({Key? key, this.mazdoorId, this.mazdoorName})
      : super(key: key);

  @override
  Widget build(BuildContext context) => MazdoorTransactionsPage(
    mode: MazdoorTxnMode.received,
    mazdoorId: mazdoorId,
    mazdoorName: mazdoorName,
  );
}

class _Txn {
  final String id;
  final String mazdoorId;
  final String mazdoorName;
  final String entryType;
  final String reference;
  final double amount;
  final String description;
  final String itemName;
  final double? qty;
  final double? rate;
  final double? weightPerUnit;
  final double? totalWeight;
  final String batch;
  final List<Map<String, dynamic>> wireLines;
  final DateTime date;
  final Map<String, dynamic> rawEntry; // full raw ledger row

  _Txn({
    required this.id,
    required this.mazdoorId,
    required this.mazdoorName,
    required this.entryType,
    required this.reference,
    required this.amount,
    required this.description,
    required this.itemName,
    required this.qty,
    required this.rate,
    required this.weightPerUnit,
    required this.totalWeight,
    required this.batch,
    required this.wireLines,
    required this.date,
    required this.rawEntry,
  });

  String get kind {
    if (entryType.startsWith('bolt')) return 'bolt';
    if (entryType.startsWith('wire')) return 'wire';
    return 'cash';
  }
}

const _givenTypes = {'wire_given', 'bolt_given', 'cash_given', 'adjustment'};
const _receivedTypes = {'wire_return', 'bolt_return', 'cash_payment'};

class MazdoorTransactionsPage extends StatefulWidget {
  final MazdoorTxnMode mode;
  final String? mazdoorId;
  final String? mazdoorName;
  final bool embedded;

  const MazdoorTransactionsPage({
    Key? key,
    required this.mode,
    this.mazdoorId,
    this.mazdoorName,
    this.embedded = false,
  }) : super(key: key);

  @override
  State<MazdoorTransactionsPage> createState() =>
      _MazdoorTransactionsPageState();
}

class _MazdoorTransactionsPageState extends State<MazdoorTransactionsPage> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final TextEditingController _searchCtrl = TextEditingController();

  List<_Txn> _all = [];
  bool _loading = true;
  String? _error;

  String _query = '';
  String _kind = 'all';
  DateTimeRange? _range;

  bool get _isGiven => widget.mode == MazdoorTxnMode.given;
  Color get _accent =>
      _isGiven ? const Color(0xFFE65100) : const Color(0xFF00897B);
  List<Color> get _gradient => _isGiven
      ? const [Color(0xFFFF8A65), Color(0xFFFFB74D)]
      : const [Color(0xFF26A69A), Color(0xFF80CBC4)];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  double _num(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  double? _numOrNull(dynamic v) => v == null ? null : _num(v);

  DateTime _date(dynamic v) {
    if (v is String) return DateTime.tryParse(v) ?? DateTime(2000);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return DateTime(2000);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final provider = Provider.of<MazdoorProvider>(context, listen: false);
      if (provider.mazdoors.isEmpty) await provider.fetchMazdoors();
      final names = {for (final m in provider.mazdoors) m.id: m.name};

      final wanted = _isGiven ? _givenTypes : _receivedTypes;
      final List<_Txn> out = [];

      void parseMazdoor(String mid, Map data) {
        data.forEach((key, value) {
          if (value == null || value is! Map) return;
          final type = value['entryType']?.toString() ?? '';
          if (!wanted.contains(type)) return;

          final debit = _num(value['debitFromMazdoor']);
          final credit = _num(value['creditToMazdoor']);
          final lines = <Map<String, dynamic>>[];
          if (value['wireLines'] is List) {
            for (final l in value['wireLines'] as List) {
              if (l is Map) lines.add(Map<String, dynamic>.from(l));
            }
          }
          String item = value['itemName']?.toString() ?? '';
          if (item.isEmpty && lines.isNotEmpty) {
            item =
                lines.map((l) => l['itemName']?.toString() ?? '').join(', ');
          }
          String batch = '';
          if (lines.isNotEmpty) {
            batch = lines
                .map((l) => l['batchNumber']?.toString() ?? '')
                .where((b) => b.isNotEmpty && b != 'null')
                .toSet()
                .join(', ');
          }

          out.add(_Txn(
            id: key.toString(),
            mazdoorId: mid,
            mazdoorName: names[mid] ?? '—',
            entryType: type,
            reference:
            (value['reference'] ?? value['jobNumber'])?.toString() ?? '',
            amount: _isGiven ? debit : credit,
            description: value['description']?.toString() ?? '',
            itemName: item,
            qty: _numOrNull(value['quantity']),
            rate: _numOrNull(value['rate']),
            weightPerUnit: _numOrNull(value['weightPerUnit']),
            totalWeight: _numOrNull(value['totalWeight']),
            batch: batch,
            wireLines: lines,
            date: _date(value['createdAt']),
            rawEntry: Map<String, dynamic>.from(value),
          ));
        });
      }

      if (widget.mazdoorId != null) {
        final snap =
        await _db.child('mazdoorLedger').child(widget.mazdoorId!).get();
        if (snap.exists && snap.value is Map) {
          parseMazdoor(widget.mazdoorId!, snap.value as Map);
        }
      } else {
        final snap = await _db.child('mazdoorLedger').get();
        if (snap.exists && snap.value is Map) {
          (snap.value as Map).forEach((mid, data) {
            if (data is Map) parseMazdoor(mid.toString(), data);
          });
        }
      }

      out.sort((a, b) => b.date.compareTo(a.date));
      if (!mounted) return;
      setState(() {
        _all = out;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<_Txn> get _filtered {
    final q = _query.trim().toLowerCase();
    return _all.where((t) {
      if (_kind != 'all' && t.kind != _kind) return false;
      if (_range != null) {
        final start = DateTime(
            _range!.start.year, _range!.start.month, _range!.start.day);
        final end = DateTime(
            _range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59);
        if (t.date.isBefore(start) || t.date.isAfter(end)) return false;
      }
      if (q.isEmpty) return true;
      return t.mazdoorName.toLowerCase().contains(q) ||
          t.itemName.toLowerCase().contains(q) ||
          t.reference.toLowerCase().contains(q) ||
          t.description.toLowerCase().contains(q) ||
          t.batch.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _confirmDelete(_Txn t, LanguageProvider lp) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lp.isEnglish ? 'Delete record?' : 'ریکارڈ حذف کریں؟'),
        content: Text(lp.isEnglish
            ? 'This removes the entry for ${t.mazdoorName}, reverses its stock effect and recalculates the balance.'
            : 'یہ ${t.mazdoorName} کا اندراج حذف کرے گا، اسٹاک واپس کرے گا اور بیلنس دوبارہ نکالے گا۔'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(lp.isEnglish ? 'Cancel' : 'منسوخ کریں')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lp.isEnglish ? 'Delete' : 'حذف کریں',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Provider.of<MazdoorProvider>(context, listen: false)
          .deleteLedgerEntry(mazdoorId: t.mazdoorId, entryKey: t.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // ── PDF helpers ──────────────────────────────────────────────

  Future<Uint8List> _buildPdf(_Txn t) async {
    final data = await MazdoorPdfReceipt.fromLedgerEntry(
      db: _db,
      mazdoorId: t.mazdoorId,
      entry: t.rawEntry,
    );
    return MazdoorPdfReceipt.build(data);
  }

  Future<void> _printPdf(_Txn t, LanguageProvider lp) async {
    try {
      final bytes = await _buildPdf(t);
      await Printing.layoutPdf(onLayout: (format) async => bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e')));
    }
  }

  Future<void> _downloadPdf(_Txn t) async {
    try {
      final bytes = await _buildPdf(t);
      await Printing.sharePdf(
        bytes: bytes,
        filename:
        'Mazdoor_${t.mazdoorName.replaceAll(RegExp(r"[^A-Za-z0-9]"), "_")}_'
            '${DateFormat("yyyyMMdd_HHmm").format(t.date)}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e')));
    }
  }

  // ── display helpers ──
  String _typeLabel(String type, bool en) {
    switch (type) {
      case 'wire_given':
        return en ? 'Wire Given' : 'وائر دی';
      case 'bolt_given':
        return en ? 'Bolts Given' : 'بولٹس دیے';
      case 'cash_given':
        return en ? 'Cash Given' : 'نقد دیے';
      case 'adjustment':
        return en ? 'Advance Given' : 'ایڈوانس دیا';
      case 'wire_return':
        return en ? 'Wire Received' : 'وائر وصول';
      case 'bolt_return':
        return en ? 'Bolts Received' : 'بولٹس وصول';
      case 'cash_payment':
        return en ? 'Cash Received' : 'نقد وصول';
    }
    return type;
  }

  IconData _kindIcon(String k) {
    switch (k) {
      case 'bolt':
        return Icons.hardware;
      case 'wire':
        return Icons.cable;
      default:
        return Icons.payments;
    }
  }

  String _fmt(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final lp = Provider.of<LanguageProvider>(context);
    final en = lp.isEnglish;
    final list = _filtered;
    final total = list.fold<double>(0, (s, t) => s + t.amount);

    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              labelText: en
                  ? 'Search name, item, reference...'
                  : 'نام، آئٹم، حوالہ تلاش کریں...',
              prefixIcon: Icon(Icons.search, color: _accent),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.clear, color: Colors.grey),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _query = '');
                },
              )
                  : null,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final k in const ['all', 'bolt', 'wire', 'cash'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      k == 'all'
                          ? (en ? 'All' : 'سب')
                          : k == 'bolt'
                          ? (en ? 'Bolts' : 'بولٹس')
                          : k == 'wire'
                          ? (en ? 'Wire' : 'وائر')
                          : (en ? 'Cash' : 'نقد'),
                    ),
                    selected: _kind == k,
                    selectedColor: _accent.withOpacity(0.2),
                    onSelected: (_) => setState(() => _kind = k),
                  ),
                ),
              if (_range != null)
                InputChip(
                  avatar: const Icon(Icons.date_range, size: 16),
                  label: Text(
                      '${DateFormat('dd/MM/yy').format(_range!.start)} - ${DateFormat('dd/MM/yy').format(_range!.end)}'),
                  onDeleted: () => setState(() => _range = null),
                ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _accent.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${list.length} ${en ? 'records' : 'ریکارڈ'}',
                  style: TextStyle(
                      color: _accent, fontWeight: FontWeight.w600)),
              Text(
                '${en ? 'Total' : 'کل'}: ${total.toStringAsFixed(2)} PKR',
                style: TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _error != null
              ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $_error',
                  style: const TextStyle(color: Colors.red)),
            ),
          )
              : list.isEmpty && !_loading
              ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_outlined,
                    size: 56, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  en ? 'No records found' : 'کوئی ریکارڈ نہیں ملا',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          )
              : RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) => _tile(list[i], lp),
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) return body;

    final baseTitle = _isGiven
        ? (en ? 'Given Records' : 'دیے گئے ریکارڈ')
        : (en ? 'Received Records' : 'وصول شدہ ریکارڈ');
    final title = widget.mazdoorName != null
        ? '$baseTitle — ${widget.mazdoorName}'
        : baseTitle;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range, color: Colors.white),
            onPressed: _pickRange,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _tile(_Txn t, LanguageProvider lp) {
    final en = lp.isEnglish;
    final showMazdoor = widget.mazdoorId == null;

    String subtitle = t.itemName.isNotEmpty ? t.itemName : t.description;
    final bits = <String>[];
    if (t.kind == 'wire' && (t.totalWeight ?? 0) > 0) {
      bits.add('${t.totalWeight!.toStringAsFixed(2)} kg');
    } else if (t.qty != null && t.qty! > 0 && t.kind != 'cash') {
      bits.add('${en ? 'Qty' : 'مقدار'} ${_fmt(t.qty!)}');
    }
    if (t.rate != null && t.rate! > 0) {
      bits.add('@ ${t.rate!.toStringAsFixed(2)}');
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      elevation: 2,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: _accent.withOpacity(0.15),
          child: Icon(_kindIcon(t.kind), color: _accent, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                showMazdoor ? t.mazdoorName : _typeLabel(t.entryType, en),
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${t.amount.toStringAsFixed(2)}',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: _accent, fontSize: 15),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showMazdoor)
              Text(_typeLabel(t.entryType, en),
                  style: TextStyle(
                      color: _accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            if (subtitle.isNotEmpty)
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (bits.isNotEmpty)
              Text(bits.join('  |  '),
                  style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            Text(DateFormat('dd/MM/yyyy  HH:mm').format(t.date),
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 8),
          _detail(en ? 'Mazdoor' : 'مزدور', t.mazdoorName),
          if (t.reference.isNotEmpty)
            _detail(en ? 'Reference' : 'حوالہ', t.reference),
          if (t.itemName.isNotEmpty)
            _detail(en ? 'Item' : 'آئٹم', t.itemName),
          if (t.qty != null && t.kind != 'cash')
            _detail(en ? 'Quantity' : 'مقدار', _fmt(t.qty!)),
          if ((t.weightPerUnit ?? 0) > 0)
            _detail(en ? 'Weight / Unit' : 'وزن/یونٹ',
                '${t.weightPerUnit!.toStringAsFixed(2)} kg'),
          if ((t.totalWeight ?? 0) > 0)
            _detail(en ? 'Total Weight' : 'کل وزن',
                '${t.totalWeight!.toStringAsFixed(2)} kg'),
          if (t.rate != null && t.rate! > 0)
            _detail(en ? 'Rate' : 'ریٹ', t.rate!.toStringAsFixed(2)),
          if (t.batch.isNotEmpty) _detail(en ? 'Batch' : 'بیچ', t.batch),
          if (t.description.isNotEmpty)
            _detail(en ? 'Description' : 'تفصیل', t.description),
          _detail(en ? 'Amount' : 'رقم',
              '${t.amount.toStringAsFixed(2)} PKR',
              bold: true),
          if (t.wireLines.length > 1) ...[
            const SizedBox(height: 6),
            Text(en ? 'Wire lines' : 'وائر لائنیں',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: _accent)),
            for (final l in t.wireLines)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '• ${l['itemName'] ?? ''}'
                      '${(l['length'] ?? '').toString().isNotEmpty ? ' | ${l['length']}' : ''}'
                      '${(l['bodyType'] ?? '').toString().isNotEmpty ? ' | ${l['bodyType']}' : ''}'
                      '  —  ${_fmt(_num(l['qty']))}'
                      '${_num(l['totalWeight']) > 0 ? '  (${_num(l['totalWeight']).toStringAsFixed(2)} kg)' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.print, color: Colors.teal, size: 18),
                label: Text(en ? 'Print' : 'پرنٹ',
                    style: const TextStyle(color: Colors.teal)),
                onPressed: () => _printPdf(t, lp),
              ),
              TextButton.icon(
                icon: const Icon(Icons.picture_as_pdf,
                    color: Colors.indigo, size: 18),
                label: Text(en ? 'PDF' : 'پی ڈی ایف',
                    style: const TextStyle(color: Colors.indigo)),
                onPressed: () => _downloadPdf(t),
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                label: Text(en ? 'Delete' : 'حذف کریں',
                    style: const TextStyle(color: Colors.red)),
                onPressed: () => _confirmDelete(t, lp),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(color: Colors.grey[700], fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ),
        ],
      ),
    );
  }
}