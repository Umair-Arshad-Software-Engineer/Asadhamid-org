// mazdoorListPage.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../Customer/addcustomers.dart';
import '../Models/mazdoorModel.dart';
import '../Provider/Mazdoorprovider ·.dart';
import '../Provider/lanprovider.dart';
import 'mazdorijob.dart';
// ── NEW: import the two new ledger pages ──
import 'mazdoorLedgerReportPage.dart';
import 'mazdoorItemWiseLedgerPage.dart';
import 'mazdoriledger.dart';


class MazdoorListPage extends StatefulWidget {
  @override
  _MazdoorListPageState createState() => _MazdoorListPageState();
}

class _MazdoorListPageState extends State<MazdoorListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Map<String, double> _balances = {};
  bool _loadingBalances = false;

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

  // ── Totals across the *filtered* list (nice for a header chip) ──
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

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final mazdoorProvider = Provider.of<MazdoorProvider>(context);
    final list = _filtered(mazdoorProvider.mazdoors);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          languageProvider.isEnglish ? 'Mazdoor Persons' : 'مزدور',
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
        actions: [
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
                  builder: (_) => const AddCustomer(startAsMazdoor: true),
                ),
              ).then((_) => _refresh());
            },
          ),
        ],
      ),
      body: Column(
        children: [
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
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
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

                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  elevation: 2,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.teal[300],
                      child: Text(
                        m.mazdoorSerial.isNotEmpty
                            ? m.mazdoorSerial
                            : '?',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(m.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold)),
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
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) =>
                          _handleMenu(context, value, m, languageProvider),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'give_wire',
                          child: Row(children: [
                            const Icon(Icons.outbond,
                                color: Colors.orange),
                            const SizedBox(width: 8),
                            Text(languageProvider.isEnglish
                                ? 'Give Wire (New Job)'
                                : 'وائر دیں (نیا کام)'),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'receive',
                          child: Row(children: [
                            const Icon(Icons.call_received,
                                color: Colors.green),
                            const SizedBox(width: 8),
                            Text(languageProvider.isEnglish
                                ? 'Receive Bolts / Cash'
                                : 'بولٹس / نقدی وصول کریں'),
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
                            const Icon(Icons.delete, color: Colors.red),
                            const SizedBox(width: 8),
                            Text(languageProvider.isEnglish
                                ? 'Delete'
                                : 'حذف کریں'),
                          ]),
                        ),
                      ],
                    ),
                    onTap: () {
                      // Tapping the tile opens the modal chooser
                      _showLedgerChooser(context, m, languageProvider);
                    },
                    onLongPress: () {
                      // Long-press goes straight to the simple ledger
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
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            amount.toStringAsFixed(0),
            style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.bold),
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
      case 'give_wire':
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
      // "Quick Ledger" → the original lightweight ledger page
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

  // ── Bottom sheet to choose which ledger view ──
  void _showLedgerChooser(
      BuildContext context, MazdoorPerson m, LanguageProvider lp) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
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
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.teal),
              title: Text(lp.isEnglish
                  ? 'Simple Ledger'
                  : 'سادہ کھاتہ'),
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
              title: Text(lp.isEnglish
                  ? 'Item-Wise Ledger'
                  : 'آئٹم وار کھاتہ'),
              subtitle: Text(lp.isEnglish
                  ? 'Every wire / bolt movement as a row'
                  : 'ہر وائر / بولٹ کی حرکت'),
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
              title: Text(lp.isEnglish
                  ? 'Quick Ledger'
                  : 'فوری کھاتہ'),
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