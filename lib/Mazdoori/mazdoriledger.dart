import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../Models/mazdoorModel.dart';
import '../Provider/Mazdoorprovider ·.dart';
import '../Provider/lanprovider.dart';
import 'mazdorijob.dart';


class MazdoorLedgerPage extends StatefulWidget {
  final String mazdoorId;
  final String mazdoorName;

  const MazdoorLedgerPage({
    Key? key,
    required this.mazdoorId,
    required this.mazdoorName,
  }) : super(key: key);

  @override
  _MazdoorLedgerPageState createState() => _MazdoorLedgerPageState();
}

class _MazdoorLedgerPageState extends State<MazdoorLedgerPage> {
  List<MazdoorLedgerEntry> _entries = [];
  double _balance = 0.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final provider = Provider.of<MazdoorProvider>(context, listen: false);
    final entries = await provider.getMazdoorLedger(widget.mazdoorId);
    final balance = await provider.getMazdoorBalance(widget.mazdoorId);
    setState(() {
      _entries = entries.reversed.toList(); // newest first
      _balance = balance;
      _isLoading = false;
    });
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'wire_given':
        return Icons.outbond;
      case 'bolt_return':
        return Icons.settings_input_component;
      case 'cash_payment':
        return Icons.payments;
      case 'opening_balance':
        return Icons.flag;
      default:
        return Icons.receipt_long;
    }
  }

  String _labelFor(String type, LanguageProvider lp) {
    switch (type) {
      case 'wire_given':
        return lp.isEnglish ? 'Wire Given' : 'وائر دیا گیا';
      case 'bolt_return':
        return lp.isEnglish ? 'Bolts Returned' : 'بولٹس واپس';
      case 'cash_payment':
        return lp.isEnglish ? 'Cash Payment' : 'نقد ادائیگی';
      case 'opening_balance':
        return lp.isEnglish ? 'Opening Balance' : 'ابتدائی بیلنس';
      default:
        return lp.isEnglish ? 'Adjustment' : 'ایڈجسٹمنٹ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final lp = Provider.of<LanguageProvider>(context);
    final owesYou = _balance > 0;
    final youOwe = _balance < 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.mazdoorName} — ${lp.isEnglish ? 'Ledger' : 'کھاتہ'}',
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
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'give_wire',
            backgroundColor: Colors.orange,
            icon: const Icon(Icons.outbond),
            label: Text(lp.isEnglish ? 'Give Wire' : 'وائر دیں'),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MazdoorJobPage(
                    mazdoorId: widget.mazdoorId,
                    mazdoorName: widget.mazdoorName,
                    mode: MazdoorJobMode.giveWire,
                  ),
                ),
              );
              _load();
            },
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'receive',
            backgroundColor: Colors.teal,
            icon: const Icon(Icons.call_received),
            label: Text(lp.isEnglish ? 'Receive' : 'وصول کریں'),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MazdoorJobPage(
                    mazdoorId: widget.mazdoorId,
                    mazdoorName: widget.mazdoorName,
                    mode: MazdoorJobMode.receiveReturn,
                  ),
                ),
              );
              _load();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: owesYou
                  ? Colors.green[50]
                  : youOwe
                  ? Colors.red[50]
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: owesYou
                    ? Colors.green
                    : youOwe
                    ? Colors.red
                    : Colors.grey,
              ),
            ),
            child: Column(
              children: [
                Text(
                  owesYou
                      ? (lp.isEnglish ? 'Owes You' : 'آپ کا مقروض ہے')
                      : youOwe
                      ? (lp.isEnglish ? 'You Owe' : 'آپ مقروض ہیں')
                      : (lp.isEnglish ? 'Settled' : 'حساب برابر'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: owesYou
                        ? Colors.green[800]
                        : youOwe
                        ? Colors.red[800]
                        : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_balance.abs().toStringAsFixed(2)} PKR',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: owesYou
                        ? Colors.green[800]
                        : youOwe
                        ? Colors.red[800]
                        : Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _entries.isEmpty
                ? Center(
              child: Text(
                lp.isEnglish ? 'No transactions yet' : 'ابھی تک کوئی لین دین نہیں',
                style: TextStyle(color: Colors.grey[600]),
              ),
            )
                : ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final entry = _entries[index];
                final isDebit = entry.debitFromMazdoor > 0;
                return Card(
                  margin:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                      isDebit ? Colors.orange[100] : Colors.teal[100],
                      child: Icon(
                        _iconFor(entry.entryType),
                        color: isDebit ? Colors.orange[800] : Colors.teal[800],
                        size: 20,
                      ),
                    ),
                    title: Text(_labelFor(entry.entryType, lp)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (entry.itemName != null)
                          Text(
                              '${entry.itemName} — ${entry.quantity?.toStringAsFixed(2) ?? ''} @ ${entry.rate?.toStringAsFixed(2) ?? ''}'),
                        if (entry.description != null &&
                            entry.description!.isNotEmpty)
                          Text(entry.description!,
                              style: const TextStyle(fontStyle: FontStyle.italic)),
                        Text(
                          DateFormat('yyyy-MM-dd – HH:mm')
                              .format(entry.createdAt),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          isDebit
                              ? '+${entry.debitFromMazdoor.toStringAsFixed(2)}'
                              : '-${entry.creditToMazdoor.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDebit ? Colors.orange[800] : Colors.teal[800],
                          ),
                        ),
                        Text(
                          'Bal: ${entry.remainingBalance.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}