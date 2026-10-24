// mazdoorListPage.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../Customer/addcustomers.dart';
import '../Models/mazdoorModel.dart';
import '../Provider/Mazdoorprovider ·.dart';
import '../Provider/lanprovider.dart';
import 'mazdorijob.dart';
// ── Ledger pages ──
import 'mazdoorLedgerReportPage.dart';
import 'mazdoorItemWiseLedgerPage.dart';
import 'mazdoriledger.dart';
// ── Given / Received record lists ──
import 'mazdoorTransactionsListPage.dart';
// ── Per-Mazdoor unified transactions page ──
import 'mazdoorPersonTransactionsPage.dart';

class MazdoorListPage extends StatefulWidget {
  @override
  _MazdoorListPageState createState() => _MazdoorListPageState();
}

class _MazdoorListPageState extends State<MazdoorListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Map<String, double> _balances = {};
  bool _loadingBalances = false;

  // ── Selection state (for PDF export) ──
  bool _isSelectionMode = false;
  Set<String> _selectedMazdoorIds = {};

  final NumberFormat _money = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final provider = Provider.of<MazdoorProvider>(context, listen: false);
    await provider.fetchMazdoors();
    await _loadBalances(provider.mazdoors);
  }

  Future<void> _loadBalances(List<MazdoorPerson> mazdoors) async {
    setState(() => _loadingBalances = true);
    final provider = Provider.of<MazdoorProvider>(context, listen: false);
    final Map<String, double> balances = {};
    for (final m in mazdoors) {
      balances[m.id] = await provider.getMazdoorBalance(m.id);
    }
    if (!mounted) return;
    setState(() {
      _balances = balances;
      _loadingBalances = false;
    });
  }

  List<MazdoorPerson> _filtered(List<MazdoorPerson> all) {
    if (_searchQuery.isEmpty) return all;
    final q = _searchQuery.toLowerCase();
    return all.where((m) {
      return m.name.toLowerCase().contains(q) ||
          m.phone.toLowerCase().contains(q) ||
          m.city.toLowerCase().contains(q) ||
          m.mazdoorSerial.toLowerCase().contains(q);
    }).toList();
  }

  // ── Totals across the list (header chips) ──
  double get _filteredTotalOwesYou {
    double t = 0;
    for (final b in _balances.values) {
      if (b > 0) t += b;
    }
    return t;
  }

  double get _filteredTotalYouOwe {
    double t = 0;
    for (final b in _balances.values) {
      if (b < 0) t += -b;
    }
    return t;
  }

  // ══════════════════════════════════════════════════════════════════
  // SELECTION HELPERS
  // ══════════════════════════════════════════════════════════════════

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) _selectedMazdoorIds.clear();
    });
  }

  void _toggleMazdoorSelection(String id) {
    setState(() {
      if (_selectedMazdoorIds.contains(id)) {
        _selectedMazdoorIds.remove(id);
      } else {
        _selectedMazdoorIds.add(id);
      }
    });
  }

  /// Selects / deselects everyone currently visible (respects search).
  void _selectAll(List<MazdoorPerson> visible) {
    setState(() {
      final visibleIds = visible.map((m) => m.id).toSet();
      final allVisibleSelected =
          visibleIds.isNotEmpty && visibleIds.every(_selectedMazdoorIds.contains);
      if (allVisibleSelected) {
        _selectedMazdoorIds.removeAll(visibleIds);
      } else {
        _selectedMazdoorIds.addAll(visibleIds);
      }
    });
  }

  List<MazdoorPerson> _selectedMazdoors(List<MazdoorPerson> all) =>
      all.where((m) => _selectedMazdoorIds.contains(m.id)).toList();

  // ══════════════════════════════════════════════════════════════════
  // PDF: PAYMENT COLLECTION SHEET
  // ══════════════════════════════════════════════════════════════════

  // String _balanceCell(double b) =>
  //     b < 0 ? '(${_money.format(-b)})' : _money.format(b);
  /// + = they owe you, - = you owe them
  String _balanceCell(double b) {
    if (b > 0) return '+${_money.format(b)}';
    if (b < 0) return '-${_money.format(-b)}';
    return _money.format(0);
  }

  Future<void> _generateMazdoorPaymentCollectionPdf(
      List<MazdoorPerson> mazdoors) async {
    final lp = Provider.of<LanguageProvider>(context, listen: false);
    final pdf = pw.Document();

    final tableData = mazdoors.asMap().entries.map((entry) {
      final m = entry.value;
      final balance = _balances[m.id] ?? 0.0;
      return [
        '${entry.key + 1}',
        m.mazdoorSerial.isNotEmpty ? m.mazdoorSerial : '-',
        m.name,
        m.phone,
        _balanceCell(balance),
        '', // Description (filled by hand)
        '', // Payment Received (filled by hand)
      ];
    }).toList();

    final totalOutstanding = mazdoors.fold<double>(0.0, (sum, m) {
      final b = _balances[m.id] ?? 0.0;
      return b > 0 ? sum + b : sum;
    });
    final totalYouOwe = mazdoors.fold<double>(0.0, (sum, m) {
      final b = _balances[m.id] ?? 0.0;
      return b < 0 ? sum - b : sum;
    });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (pw.Context ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                'Mazdoor Payment Collection Sheet',
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 11),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 4),
          ],
        ),
        footer: (pw.Context ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Total Mazdoors: ${mazdoors.length}',
                style: const pw.TextStyle(fontSize: 9)),
            pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
        build: (pw.Context ctx) => [
          pw.TableHelper.fromTextArray(
            headers: [
              '#',
              'Serial',
              'Mazdoor Name',
              'Phone',
              'Remaining Balance (Rs)',
              'Description',
              'Payment Received (Rs)',
            ],
            data: tableData,
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
                color: PdfColors.white),
            headerDecoration:
            const pw.BoxDecoration(color: PdfColor.fromInt(0xFF00897B)),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.center,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerLeft,
              6: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(24),
              1: const pw.FixedColumnWidth(40),
              2: const pw.FlexColumnWidth(2.6),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(2.2),
              5: const pw.FlexColumnWidth(2.6),
              6: const pw.FlexColumnWidth(2.2),
            },
            rowDecoration: const pw.BoxDecoration(
                border: pw.Border(
                    bottom:
                    pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
            oddRowDecoration:
            const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE0F2F1)),
            cellPadding:
            const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.teal, width: 1),
                borderRadius:
                const pw.BorderRadius.all(pw.Radius.circular(4))),
            child: pw.Column(
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total Outstanding (They Owe You):',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    pw.Text('Rs. ${_money.format(totalOutstanding)}',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 11,
                            color: PdfColors.red)),
                  ],
                ),
                if (totalYouOwe > 0) ...[
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('You Owe Them (shown with - sign):',
                          style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Rs. ${_money.format(totalYouOwe)}',
                          style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(children: [
                pw.Container(width: 150, height: 1, color: PdfColors.black),
                pw.SizedBox(height: 4),
                pw.Text('Prepared By', style: const pw.TextStyle(fontSize: 9)),
              ]),
              pw.Column(children: [
                pw.Container(width: 150, height: 1, color: PdfColors.black),
                pw.SizedBox(height: 4),
                pw.Text('Verified By', style: const pw.TextStyle(fontSize: 9)),
              ]),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) => pdf.save(),
      name: 'mazdoor_collection_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf',
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // PDF: BALANCE LIST
  // ══════════════════════════════════════════════════════════════════

  Future<void> _generateMazdoorBalanceListPdf(
      List<MazdoorPerson> mazdoors) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context ctx) => [
          pw.Center(
            child: pw.Text('Mazdoor Balance List',
                style: pw.TextStyle(
                    fontSize: 22, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
                'Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 11)),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['#', 'Serial', 'Name', 'Phone', 'City', 'Balance (Rs)'],
            data: mazdoors.asMap().entries.map((e) {
              final m = e.value;
              return [
                '${e.key + 1}',
                m.mazdoorSerial.isNotEmpty ? m.mazdoorSerial : '-',
                m.name,
                m.phone,
                m.city,
                _balanceCell(_balances[m.id] ?? 0.0),
              ];
            }).toList(),
            headerStyle:
            pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {5: pw.Alignment.centerRight},
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  // ── Bottom sheet: choose which PDF to export ──
  void _showPdfOptions(List<MazdoorPerson> mazdoors) {
    final lp = Provider.of<LanguageProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  lp.isEnglish
                      ? 'Export ${mazdoors.length} mazdoor(s) as:'
                      : '${mazdoors.length} مزدور برآمد کریں:',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long, color: Colors.teal),
                title: Text(lp.isEnglish
                    ? 'Payment Collection Sheet'
                    : 'ادائیگی وصولی شیٹ'),
                subtitle: Text(lp.isEnglish
                    ? 'With empty description & payment fields'
                    : 'خالی تفصیل اور ادائیگی خانوں کے ساتھ'),
                onTap: () {
                  Navigator.pop(ctx);
                  _generateMazdoorPaymentCollectionPdf(mazdoors);
                },
              ),
              const Divider(),
              ListTile(
                leading:
                const Icon(Icons.picture_as_pdf, color: Colors.deepOrange),
                title: Text(lp.isEnglish ? 'Balance List' : 'بیلنس فہرست'),
                subtitle: Text(lp.isEnglish
                    ? 'Serial, name, phone, city & balance'
                    : 'سیریل، نام، فون، شہر اور بیلنس'),
                onTap: () {
                  Navigator.pop(ctx);
                  _generateMazdoorBalanceListPdf(mazdoors);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final mazdoorProvider = Provider.of<MazdoorProvider>(context);
    final allMazdoors = mazdoorProvider.mazdoors;
    final list = _filtered(allMazdoors);
    final selected = _selectedMazdoors(allMazdoors);
    final allVisibleSelected = list.isNotEmpty &&
        list.every((m) => _selectedMazdoorIds.contains(m.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelectionMode
              ? (languageProvider.isEnglish
              ? '${_selectedMazdoorIds.length} selected'
              : '${_selectedMazdoorIds.length} منتخب')
              : (languageProvider.isEnglish ? 'Mazdoor Persons' : 'مزدور'),
          style: const TextStyle(color: Colors.white),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF26A69A), Color(0xFF80CBC4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: _isSelectionMode
            ? [
          IconButton(
            icon: Icon(
              allVisibleSelected ? Icons.deselect : Icons.select_all,
              color: Colors.white,
            ),
            tooltip: allVisibleSelected ? 'Deselect All' : 'Select All',
            onPressed: () => _selectAll(list),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            tooltip: 'Export Selected',
            onPressed: selected.isEmpty
                ? null
                : () => _showPdfOptions(selected),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _toggleSelectionMode,
          ),
        ]
            : [
          // ── All Given records ──
          IconButton(
            tooltip: languageProvider.isEnglish
                ? 'All Given Records'
                : 'تمام دیے گئے ریکارڈ',
            icon: const Icon(Icons.outbond, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MazdoorGivenListPage(),
                ),
              ).then((_) => _refresh());
            },
          ),
          // ── All Received records ──
          IconButton(
            tooltip: languageProvider.isEnglish
                ? 'All Received Records'
                : 'تمام وصول شدہ ریکارڈ',
            icon: const Icon(Icons.call_received, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MazdoorReceivedListPage(),
                ),
              ).then((_) => _refresh());
            },
          ),
          // ── Enter selection mode ──
          IconButton(
            icon: const Icon(Icons.checklist, color: Colors.white),
            tooltip: languageProvider.isEnglish
                ? 'Select for PDF'
                : 'پی ڈی ایف کے لیے منتخب کریں',
            onPressed: _toggleSelectionMode,
          ),
          // ── Collection sheet for everyone (respects search) ──
          IconButton(
            icon: const Icon(Icons.receipt_long, color: Colors.white),
            tooltip: languageProvider.isEnglish
                ? 'Payment Collection Sheet (All)'
                : 'ادائیگی وصولی شیٹ (سب)',
            onPressed: list.isEmpty || _loadingBalances
                ? null
                : () => _generateMazdoorPaymentCollectionPdf(list),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                  const AddCustomer(startAsMazdoor: true),
                ),
              ).then((_) => _refresh());
            },
          ),
        ],
      ),

      // ── Floating export button in selection mode ──
      floatingActionButton: _isSelectionMode && selected.isNotEmpty
          ? FloatingActionButton.extended(
        backgroundColor: Colors.teal,
        icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
        label: Text('${selected.length} → PDF',
            style: const TextStyle(color: Colors.white)),
        onPressed: () => _showPdfOptions(selected),
      )
          : null,

      body: Column(
        children: [
          // ── Selection mode banner ──
          if (_isSelectionMode)
            Container(
              width: double.infinity,
              color: Colors.teal.shade50,
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Colors.teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      languageProvider.isEnglish
                          ? 'Tap mazdoors to select them for PDF export'
                          : 'پی ڈی ایف برآمد کے لیے مزدوروں پر ٹیپ کریں',
                      style: TextStyle(color: Colors.teal.shade800),
                    ),
                  ),
                ],
              ),
            ),

          // ── Search bar ──
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: languageProvider.isEnglish
                    ? 'Search Mazdoor'
                    : 'مزدور تلاش کریں',
                prefixIcon: const Icon(Icons.search, color: Colors.teal),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
                    : null,
                border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),

          // ── Totals strip ──
          if (list.isNotEmpty && !_loadingBalances)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: _totalsChip(
                      icon: Icons.arrow_downward,
                      color: Colors.green,
                      label: languageProvider.isEnglish
                          ? 'They Owe You'
                          : 'وہ مقروض',
                      amount: _filteredTotalOwesYou,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _totalsChip(
                      icon: Icons.arrow_upward,
                      color: Colors.red,
                      label: languageProvider.isEnglish
                          ? 'You Owe Them'
                          : 'آپ مقروض',
                      amount: _filteredTotalYouOwe,
                    ),
                  ),
                ],
              ),
            ),

          if (mazdoorProvider.isLoading || _loadingBalances)
            const LinearProgressIndicator(),

          Expanded(
            child: list.isEmpty
                ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline,
                        size: 56, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      languageProvider.isEnglish
                          ? 'No Mazdoor persons yet'
                          : 'ابھی تک کوئی مزدور نہیں',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            )
                : ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, index) {
                final m = list[index];
                final balance = _balances[m.id] ?? 0.0;
                final owesYou = balance > 0;
                final youOwe = balance < 0;
                final isSelected = _selectedMazdoorIds.contains(m.id);

                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  elevation: 2,
                  color: _isSelectionMode && isSelected
                      ? Colors.teal.shade50
                      : null,
                  shape: _isSelectionMode && isSelected
                      ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(
                        color: Colors.teal, width: 2),
                  )
                      : null,
                  child: ListTile(
                    leading: _isSelectionMode
                        ? Checkbox(
                      value: isSelected,
                      activeColor: Colors.teal,
                      onChanged: (_) =>
                          _toggleMazdoorSelection(m.id),
                    )
                        : CircleAvatar(
                      backgroundColor: Colors.teal[300],
                      child: Text(
                        m.mazdoorSerial.isNotEmpty
                            ? m.mazdoorSerial
                            : '?',
                        style:
                        const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(m.name,
                        style:
                        const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (m.phone.isNotEmpty) Text(m.phone),
                        if (m.city.isNotEmpty) Text(m.city),
                        Text(
                          owesYou
                              ? (languageProvider.isEnglish
                              ? 'Owes you: ${balance.toStringAsFixed(2)} PKR'
                              : 'آپ کا مقروض: ${balance.toStringAsFixed(2)} روپے')
                              : youOwe
                              ? (languageProvider.isEnglish
                              ? 'You owe: ${(-balance).toStringAsFixed(2)} PKR'
                              : 'آپ مقروض ہیں: ${(-balance).toStringAsFixed(2)} روپے')
                              : (languageProvider.isEnglish
                              ? 'Settled'
                              : 'حساب برابر'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: owesYou
                                ? Colors.green[700]
                                : youOwe
                                ? Colors.red[700]
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    trailing: _isSelectionMode
                        ? null // hide menu while selecting
                        : PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) => _handleMenu(
                          context, value, m, languageProvider),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'transactions',
                          child: Row(children: [
                            const Icon(Icons.swap_horiz,
                                color: Colors.indigo),
                            const SizedBox(width: 8),
                            Text(languageProvider.isEnglish
                                ? 'Transactions (Given + Received)'
                                : 'لین دین (دیا + وصول)'),
                          ]),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'give_wire',
                          child: Row(children: [
                            const Icon(Icons.outbond,
                                color: Colors.orange),
                            const SizedBox(width: 8),
                            Text(languageProvider.isEnglish
                                ? 'Give'
                                : 'دیں'),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'receive',
                          child: Row(children: [
                            const Icon(Icons.call_received,
                                color: Colors.green),
                            const SizedBox(width: 8),
                            Text(languageProvider.isEnglish
                                ? 'Receive Bolts / Wire / Cash'
                                : 'بولٹس / وائر / نقدی وصول کریں'),
                          ]),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'given_list',
                          child: Row(children: [
                            const Icon(Icons.north_east,
                                color: Colors.deepOrange),
                            const SizedBox(width: 8),
                            Text(languageProvider.isEnglish
                                ? 'Given Records'
                                : 'دیے گئے ریکارڈ'),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'received_list',
                          child: Row(children: [
                            const Icon(Icons.south_west,
                                color: Colors.teal),
                            const SizedBox(width: 8),
                            Text(languageProvider.isEnglish
                                ? 'Received Records'
                                : 'وصول شدہ ریکارڈ'),
                          ]),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'ledger_simple',
                          child: Row(children: [
                            const Icon(Icons.receipt_long,
                                color: Colors.teal),
                            const SizedBox(width: 8),
                            Text(languageProvider.isEnglish
                                ? 'Simple Ledger'
                                : 'سادہ کھاتہ'),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'ledger_items',
                          child: Row(children: [
                            const Icon(Icons.list_alt,
                                color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(languageProvider.isEnglish
                                ? 'Item-Wise Ledger'
                                : 'آئٹم وار کھاتہ'),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'ledger',
                          child: Row(children: [
                            const Icon(Icons.history,
                                color: Colors.teal),
                            const SizedBox(width: 8),
                            Text(languageProvider.isEnglish
                                ? 'Quick Ledger'
                                : 'فوری کھاتہ'),
                          ]),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            const Icon(Icons.delete,
                                color: Colors.red),
                            const SizedBox(width: 8),
                            Text(languageProvider.isEnglish
                                ? 'Delete'
                                : 'حذف کریں'),
                          ]),
                        ),
                      ],
                    ),
                    onTap: () {
                      if (_isSelectionMode) {
                        _toggleMazdoorSelection(m.id);
                      } else {
                        _showLedgerChooser(context, m, languageProvider);
                      }
                    },
                    onLongPress: _isSelectionMode
                        ? null
                        : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MazdoorLedgerReportPage(
                            mazdoorId: m.id,
                            mazdoorName: m.name,
                            mazdoorPhone: m.phone,
                            mazdoorAddress: m.address,
                            mazdoorCity: m.city,
                          ),
                        ),
                      ).then((_) => _refresh());
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Small chip showing totals ──
  Widget _totalsChip({
    required IconData icon,
    required Color color,
    required String label,
    required double amount,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            amount.toStringAsFixed(0),
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ── Popup menu dispatcher ──
  Future<void> _handleMenu(
      BuildContext context,
      String value,
      MazdoorPerson m,
      LanguageProvider lp,
      ) async {
    switch (value) {
      case 'transactions':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MazdoorPersonTransactionsPage(
              mazdoorId: m.id,
              mazdoorName: m.name,
            ),
          ),
        );
        _refresh();
        break;
      case 'give_wire':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MazdoorJobPage(
              mazdoorId: m.id,
              mazdoorName: m.name,
              mazdoorPhone: m.phone,
              mode: MazdoorJobMode.giveWire,
            ),
          ),
        );
        _refresh();
        break;
      case 'receive':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MazdoorJobPage(
              mazdoorId: m.id,
              mazdoorName: m.name,
              mode: MazdoorJobMode.receiveReturn,
            ),
          ),
        );
        _refresh();
        break;
      case 'given_list':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MazdoorGivenListPage(
              mazdoorId: m.id,
              mazdoorName: m.name,
            ),
          ),
        );
        _refresh();
        break;
      case 'received_list':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MazdoorReceivedListPage(
              mazdoorId: m.id,
              mazdoorName: m.name,
            ),
          ),
        );
        _refresh();
        break;
      case 'ledger_simple':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MazdoorLedgerReportPage(
              mazdoorId: m.id,
              mazdoorName: m.name,
              mazdoorPhone: m.phone,
              mazdoorAddress: m.address,
              mazdoorCity: m.city,
            ),
          ),
        );
        _refresh();
        break;
      case 'ledger_items':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MazdoorItemsWiseLedgerPage(
              mazdoorId: m.id,
              mazdoorName: m.name,
              mazdoorPhone: m.phone,
              mazdoorAddress: m.address,
              mazdoorCity: m.city,
            ),
          ),
        );
        _refresh();
        break;
      case 'ledger':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MazdoorLedgerPage(
              mazdoorId: m.id,
              mazdoorName: m.name,
            ),
          ),
        );
        _refresh();
        break;
      case 'delete':
        _confirmDelete(context, m, lp);
        break;
    }
  }

  // ── Bottom sheet to choose which ledger view + quick actions ──
  void _showLedgerChooser(
      BuildContext context, MazdoorPerson m, LanguageProvider lp) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  m.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(height: 8),

              // ── QUICK ACTIONS ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.outbond,
                                size: 18, color: Colors.white),
                            label: Text(
                              lp.isEnglish ? 'Give' : 'دیں',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange[700],
                              padding:
                              const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              Navigator.pop(context);
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MazdoorJobPage(
                                    mazdoorId: m.id,
                                    mazdoorName: m.name,
                                    mode: MazdoorJobMode.giveWire,
                                  ),
                                ),
                              );
                              _refresh();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.call_received,
                                size: 18, color: Colors.white),
                            label: Text(
                              lp.isEnglish ? 'Receive' : 'وصول کریں',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal[400],
                              padding:
                              const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              Navigator.pop(context);
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MazdoorJobPage(
                                    mazdoorId: m.id,
                                    mazdoorName: m.name,
                                    mode: MazdoorJobMode.receiveReturn,
                                  ),
                                ),
                              );
                              _refresh();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.swap_horiz,
                            size: 18, color: Colors.white),
                        label: Text(
                          lp.isEnglish
                              ? 'View All Transactions (Given + Received)'
                              : 'تمام لین دین دیکھیں (دیا + وصول)',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MazdoorPersonTransactionsPage(
                                mazdoorId: m.id,
                                mazdoorName: m.name,
                              ),
                            ),
                          ).then((_) => _refresh());
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),

              // ── GIVEN / RECEIVED RECORD LISTS ──
              ListTile(
                leading:
                const Icon(Icons.north_east, color: Colors.deepOrange),
                title:
                Text(lp.isEnglish ? 'Given Records' : 'دیے گئے ریکارڈ'),
                subtitle: Text(lp.isEnglish
                    ? 'All bolts / wire / cash given'
                    : 'دیے گئے تمام بولٹس / وائر / نقد'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MazdoorGivenListPage(
                        mazdoorId: m.id,
                        mazdoorName: m.name,
                      ),
                    ),
                  ).then((_) => _refresh());
                },
              ),
              ListTile(
                leading: const Icon(Icons.south_west, color: Colors.teal),
                title: Text(
                    lp.isEnglish ? 'Received Records' : 'وصول شدہ ریکارڈ'),
                subtitle: Text(lp.isEnglish
                    ? 'All bolts / wire / cash received'
                    : 'وصول شدہ تمام بولٹس / وائر / نقد'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MazdoorReceivedListPage(
                        mazdoorId: m.id,
                        mazdoorName: m.name,
                      ),
                    ),
                  ).then((_) => _refresh());
                },
              ),
              const Divider(height: 1),

              // ── LEDGER VIEWS ──
              ListTile(
                leading: const Icon(Icons.receipt_long, color: Colors.teal),
                title: Text(lp.isEnglish ? 'Simple Ledger' : 'سادہ کھاتہ'),
                subtitle: Text(lp.isEnglish
                    ? 'Transactions with expandable wire items'
                    : 'لین دین، وائر آئٹمز کے ساتھ'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MazdoorLedgerReportPage(
                        mazdoorId: m.id,
                        mazdoorName: m.name,
                        mazdoorPhone: m.phone,
                        mazdoorAddress: m.address,
                        mazdoorCity: m.city,
                      ),
                    ),
                  ).then((_) => _refresh());
                },
              ),
              ListTile(
                leading: const Icon(Icons.list_alt, color: Colors.blue),
                title: Text(
                    lp.isEnglish ? 'Item-Wise Ledger' : 'آئٹم وار کھاتہ'),
                subtitle: Text(lp.isEnglish
                    ? 'Every wire / bolt / cash movement as a row'
                    : 'ہر وائر / بولٹ / نقد کی حرکت'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MazdoorItemsWiseLedgerPage(
                        mazdoorId: m.id,
                        mazdoorName: m.name,
                        mazdoorPhone: m.phone,
                        mazdoorAddress: m.address,
                        mazdoorCity: m.city,
                      ),
                    ),
                  ).then((_) => _refresh());
                },
              ),
              ListTile(
                leading: const Icon(Icons.history, color: Colors.teal),
                title: Text(lp.isEnglish ? 'Quick Ledger' : 'فوری کھاتہ'),
                subtitle: Text(lp.isEnglish
                    ? 'Original lightweight view'
                    : 'اصل ہلکا منظر'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MazdoorLedgerPage(
                        mazdoorId: m.id,
                        mazdoorName: m.name,
                      ),
                    ),
                  ).then((_) => _refresh());
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, MazdoorPerson m, LanguageProvider lp) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(lp.isEnglish ? 'Delete Mazdoor?' : 'مزدور حذف کریں؟'),
        content: Text(lp.isEnglish
            ? 'Are you sure you want to delete ${m.name}? Ledger history will remain but will be orphaned.'
            : 'کیا آپ واقعی ${m.name} کو حذف کرنا چاہتے ہیں؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(lp.isEnglish ? 'Cancel' : 'منسوخ کریں'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await Provider.of<MazdoorProvider>(context, listen: false)
                  .deleteMazdoor(m.id);
              Navigator.pop(context);
              _refresh();
            },
            child: Text(lp.isEnglish ? 'Delete' : 'حذف کریں'),
          ),
        ],
      ),
    );
  }
}