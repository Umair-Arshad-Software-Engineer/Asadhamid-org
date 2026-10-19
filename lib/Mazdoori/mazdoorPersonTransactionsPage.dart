// mazdoorPersonTransactionsPage.dart
// Per-Mazdoor unified transactions page: tabs for Given / Received,
// scoped to a single Mazdoor, with a live balance header, plus
// a combined "Print / PDF statement" action.
import 'dart:typed_data';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../Provider/Mazdoorprovider ·.dart';
import '../Provider/lanprovider.dart';
import 'MazdoorPdfReceipt.dart';
import 'mazdoorTransactionsListPage.dart';

class MazdoorPersonTransactionsPage extends StatefulWidget {
  final String mazdoorId;
  final String mazdoorName;
  final int initialTab; // 0 = Given, 1 = Received

  const MazdoorPersonTransactionsPage({
    Key? key,
    required this.mazdoorId,
    required this.mazdoorName,
    this.initialTab = 0,
  }) : super(key: key);

  @override
  State<MazdoorPersonTransactionsPage> createState() =>
      _MazdoorPersonTransactionsPageState();
}

class _MazdoorPersonTransactionsPageState
    extends State<MazdoorPersonTransactionsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  double _balance = 0.0;
  bool _loadingBalance = true;
  bool _busyPdf = false;

  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _tab.addListener(_onTabChanged);
    _loadBalance();
  }

  void _onTabChanged() {
    // Refresh the balance header when switching tabs so the printed
    // statement is based on the latest snapshot.
    if (_tab.indexIsChanging) return;
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    setState(() => _loadingBalance = true);
    try {
      final provider =
      Provider.of<MazdoorProvider>(context, listen: false);
      final b = await provider.getMazdoorBalance(widget.mazdoorId);
      if (!mounted) return;
      setState(() {
        _balance = b;
        _loadingBalance = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingBalance = false);
    }
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Load this Mazdoor's full ledger and build the statement PDF.
  // ─────────────────────────────────────────────────────────────
  Future<Uint8List> _buildStatementPdf() async {
    // 1. Load person details
    Map<String, dynamic> person = {};
    try {
      final snap =
      await _db.child('mazdoors').child(widget.mazdoorId).get();
      if (snap.exists && snap.value is Map) {
        person = Map<String, dynamic>.from(snap.value as Map);
      }
    } catch (_) {}

    // 2. Load all ledger entries
    final List<Map<String, dynamic>> entries = [];
    double openingBalance = 0.0;
    try {
      final snap =
      await _db.child('mazdoorLedger').child(widget.mazdoorId).get();
      if (snap.exists && snap.value is Map) {
        final data = snap.value as Map;
        data.forEach((k, v) {
          if (v is! Map) return;
          final m = Map<String, dynamic>.from(v);
          m['__key'] = k.toString();
          if (m['entryType']?.toString() == 'opening_balance') {
            final debit =
                (m['debitFromMazdoor'] as num?)?.toDouble() ?? 0.0;
            final credit =
                (m['creditToMazdoor'] as num?)?.toDouble() ?? 0.0;
            openingBalance = debit - credit;
            return;
          }
          entries.add(m);
        });
      }
    } catch (_) {}

    // 3. Compute current balance
    final currentBalance =
    await Provider.of<MazdoorProvider>(context, listen: false)
        .getMazdoorBalance(widget.mazdoorId);

    // 4. Build
    return MazdoorPdfReceipt.buildStatement(
      mazdoorName: person['name']?.toString() ?? widget.mazdoorName,
      mazdoorPhone: person['phone']?.toString() ?? '',
      mazdoorAddress: person['address']?.toString() ?? '',
      mazdoorCity: person['city']?.toString() ?? '',
      mazdoorSerial: person['mazdoorSerial']?.toString() ?? '',
      openingBalance: openingBalance,
      currentBalance: currentBalance,
      entries: entries,
    );
  }

  Future<void> _printStatement() async {
    if (_busyPdf) return;
    setState(() => _busyPdf = true);
    try {
      final bytes = await _buildStatementPdf();
      await Printing.layoutPdf(onLayout: (format) async => bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _busyPdf = false);
    }
  }

  Future<void> _shareStatement() async {
    if (_busyPdf) return;
    setState(() => _busyPdf = true);
    try {
      final bytes = await _buildStatementPdf();
      final safe =
      widget.mazdoorName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Mazdoor_Statement_${safe}_$stamp.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _busyPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lp = Provider.of<LanguageProvider>(context);
    final en = lp.isEnglish;

    final owesYou = _balance > 0;
    final youOwe = _balance < 0;
    final balText = _loadingBalance
        ? '…'
        : _balance.abs() < 0.005
        ? (en ? 'Settled' : 'حساب برابر')
        : owesYou
        ? (en
        ? 'Owes you: ${_balance.toStringAsFixed(2)} PKR'
        : 'آپ کا مقروض: ${_balance.toStringAsFixed(2)} روپے')
        : (en
        ? 'You owe: ${(-_balance).toStringAsFixed(2)} PKR'
        : 'آپ مقروض: ${(-_balance).toStringAsFixed(2)} روپے');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.mazdoorName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            Text(balText,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: owesYou
                  ? const [Color(0xFF26A69A), Color(0xFF80CBC4)]
                  : youOwe
                  ? const [Color(0xFFEF5350), Color(0xFFFF8A80)]
                  : const [Color(0xFF78909C), Color(0xFFB0BEC5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          if (_busyPdf)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              ),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              tooltip:
              en ? 'Statement PDF' : 'اسٹیٹمنٹ پی ڈی ایف',
              onSelected: (v) {
                if (v == 'print') _printStatement();
                if (v == 'share') _shareStatement();
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'print',
                  child: Row(children: [
                    const Icon(Icons.print, color: Colors.teal),
                    const SizedBox(width: 8),
                    Text(en ? 'Print statement' : 'اسٹیٹمنٹ پرنٹ کریں'),
                  ]),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: Row(children: [
                    const Icon(Icons.picture_as_pdf,
                        color: Colors.indigo),
                    const SizedBox(width: 8),
                    Text(en ? 'Download / Share PDF' : 'پی ڈی ایف ڈاؤن لوڈ'),
                  ]),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadBalance,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
              icon: const Icon(Icons.outbond, size: 18),
              text: en ? 'Given' : 'دیا',
            ),
            Tab(
              icon: const Icon(Icons.call_received, size: 18),
              text: en ? 'Received' : 'وصول',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          MazdoorTransactionsPage(
            mode: MazdoorTxnMode.given,
            mazdoorId: widget.mazdoorId,
            mazdoorName: widget.mazdoorName,
            embedded: true,
          ),
          MazdoorTransactionsPage(
            mode: MazdoorTxnMode.received,
            mazdoorId: widget.mazdoorId,
            mazdoorName: widget.mazdoorName,
            embedded: true,
          ),
        ],
      ),
    );
  }
}