// mazdoorLedgerReportProvider.dart
//
// Feeds both Mazdoor report pages (transaction-wise and items-wise),
// mirroring the shape FilledCustomerReportProvider / ItemsWiseLedgerProvider
// expose for the Customer side, so the report UI can be a near-identical
// copy of those pages.
//
// Ledger sign convention (see mazdoorModel.dart / mazdoorProvider.dart):
//   debitFromMazdoor  -> Mazdoor owes you MORE (wire given, or manual
//                        adjustment/advance). Shown in the Debit column.
//   creditToMazdoor   -> Mazdoor owes you LESS / you now owe them
//                        (bolts returned, cash payment). Shown in Credit.
//   balance = sum(debit) - sum(credit)
//     positive => Mazdoor owes you
//     negative => you owe Mazdoor

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class MazdoorLedgerReportProvider with ChangeNotifier {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final String mazdoorId;

  MazdoorLedgerReportProvider(this.mazdoorId);

  bool isLoading = true;
  String error = '';

  double openingBalance = 0.0;
  DateTime? openingBalanceDate;

  /// Every ledger row, chronologically sorted, each normalized to:
  /// { key, date, debit, credit, balance, entryType, jobNumber,
  ///   description, itemName, quantity, unitPrice, isItem, paymentMethod }
  List<Map<String, dynamic>> _allEntries = [];

  DateTimeRange? dateRangeFilter;
  bool get isFiltered => dateRangeFilter != null;

  final Set<String> expandedTransactions = {};

  /// Filtered, display-ready transaction list (excludes opening balance —
  /// that's surfaced separately via displayOpeningBalance, matching the
  /// Customer report pages' pattern).
  List<Map<String, dynamic>> get transactions {
    if (dateRangeFilter == null) return _allEntries;
    return _allEntries.where((e) {
      final date = e['date'] as DateTime;
      return !date.isBefore(dateRangeFilter!.start) &&
          !date.isAfter(dateRangeFilter!.end.add(const Duration(days: 1)));
    }).toList();
  }

  /// Aggregate debit/credit/balance for the current filter, matching
  /// provider.report['debit'/'credit'/'balance'] usage in the report UI.
  Map<String, double> get report {
    final list = transactions;
    double debit = 0.0;
    double credit = 0.0;
    for (final e in list) {
      debit += (e['debit'] as double? ?? 0.0);
      credit += (e['credit'] as double? ?? 0.0);
    }
    final balance = displayOpeningBalance + credit - debit;
    // NOTE: for the Mazdoor ledger, "balance" here is expressed in the
    // same polarity as the running ledger balance (positive = they owe
    // you), so credit reduces debt and debit increases it — the report
    // cards below handle the visual framing (green=in your favor, etc).
    return {'debit': debit, 'credit': credit, 'balance': balance};
  }

  /// Opening balance to display for the current filter: if a date range
  /// is active, this becomes "balance carried forward" as of the filter
  /// start (previous balance), else the account's true opening balance.
  double get displayOpeningBalance {
    if (!isFiltered) return openingBalance;
    // Sum everything before the filter start.
    double debit = 0.0, credit = 0.0;
    for (final e in _allEntries) {
      final date = e['date'] as DateTime;
      if (date.isBefore(dateRangeFilter!.start)) {
        debit += (e['debit'] as double? ?? 0.0);
        credit += (e['credit'] as double? ?? 0.0);
      }
    }
    return openingBalance + credit - debit;
  }

  DateTime? get displayOpeningBalanceDate {
    if (!isFiltered) return openingBalanceDate;
    return dateRangeFilter!.start;
  }

  String get openingBalanceLabel =>
      isFiltered ? 'Previous Balance' : 'Opening Balance';

  /// Item-wise rows: wire lines given (debit-side) and bolt returns
  /// (credit-side), each flattened into its own row like invoice items.
  List<Map<String, dynamic>> get itemWiseRows {
    final rows = <Map<String, dynamic>>[];
    for (final e in transactions) {
      if (e['entryType'] == 'wire_given' &&
          e['wireLines'] != null &&
          (e['wireLines'] as List).isNotEmpty) {
        for (final line in (e['wireLines'] as List)) {
          rows.add({
            'date': e['date'],
            'invoiceNumber': e['jobNumber'],
            'itemName':
            '${line['itemName']}${(line['length'] ?? '').toString().isNotEmpty ? ' (${line['length']} - ${line['bodyType'] ?? ''})' : ''}',
            'isItem': true,
            'itemKind': 'wire_given',
            'quantity': (line['qty'] as num?)?.toDouble() ?? 0.0,
            'unitPrice': 0.0, // wire lines don't carry a per-unit price
            'debit': 0.0,
            'credit': 0.0,
            'balance': e['balance'],
            'paymentMethod': '-',
          });
        }
      } else if (e['entryType'] == 'bolt_return') {
        rows.add({
          'date': e['date'],
          'invoiceNumber': e['jobNumber'],
          'itemName': e['itemName'] ?? '-',
          'isItem': true,
          'itemKind': 'bolt_return',
          'quantity': e['quantity'] ?? 0.0,
          'unitPrice': e['unitPrice'] ?? 0.0,
          'debit': 0.0,
          'credit': e['credit'],
          'balance': e['balance'],
          'paymentMethod': '-',
        });
      } else {
        // Non-item rows (cash payment, opening balance, adjustment) still
        // appear so the running balance stays readable, same as the
        // Customer items-wise report keeps payment rows interleaved.
        rows.add({
          'date': e['date'],
          'invoiceNumber': e['jobNumber'],
          'itemName': e['description'] ?? _labelForType(e['entryType']),
          'isItem': false,
          'itemKind': e['entryType'],
          'quantity': 0.0,
          'unitPrice': 0.0,
          'debit': e['debit'],
          'credit': e['credit'],
          'balance': e['balance'],
          'paymentMethod': e['entryType'] == 'cash_payment' ? 'Cash' : '-',
        });
      }
    }
    return rows;
  }

  String _labelForType(String type) {
    switch (type) {
      case 'cash_payment':
        return 'Cash Payment';
      case 'opening_balance':
        return 'Opening Balance';
      default:
        return 'Adjustment';
    }
  }

  void setDateRangeFilter(DateTimeRange? range) {
    dateRangeFilter = range;
    notifyListeners();
  }

  void toggleTransactionExpansion(String key) {
    if (expandedTransactions.contains(key)) {
      expandedTransactions.remove(key);
    } else {
      expandedTransactions.add(key);
    }
    notifyListeners();
  }

  Future<void> fetchMazdoorReport() async {
    isLoading = true;
    error = '';
    notifyListeners();

    try {
      // Opening balance comes from the ledger's own 'opening_balance' row
      // if present; otherwise 0.
      final snapshot = await _db.child('mazdoorLedger').child(mazdoorId).get();

      if (!snapshot.exists || snapshot.value == null) {
        _allEntries = [];
        openingBalance = 0.0;
        openingBalanceDate = null;
        isLoading = false;
        notifyListeners();
        return;
      }

      final data = snapshot.value as Map<dynamic, dynamic>;
      final List<Map<String, dynamic>> entries = [];

      data.forEach((key, value) {
        if (value == null) return;
        final entry = Map<String, dynamic>.from(value);

        DateTime parseDate(dynamic v) {
          if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
          if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
          return DateTime.now();
        }

        double parseD(dynamic v) {
          if (v == null) return 0.0;
          if (v is num) return v.toDouble();
          return double.tryParse(v.toString()) ?? 0.0;
        }

        final entryType = entry['entryType']?.toString() ?? 'adjustment';
        // Back-compat: earlier builds stored 'jobNumber' instead of 'reference'.
        final reference = (entry['reference'] ?? entry['jobNumber'])?.toString() ?? '';

        if (entryType == 'opening_balance') {
          openingBalance = parseD(entry['debitFromMazdoor']) -
              parseD(entry['creditToMazdoor']);
          openingBalanceDate = parseDate(entry['createdAt']);
          return; // not included as a regular transaction row
        }

        entries.add({
          'key': key.toString(),
          'date': parseDate(entry['createdAt']),
          'jobNumber': reference, // kept as 'jobNumber' key for UI compatibility
          'entryType': entryType,
          'debit': parseD(entry['debitFromMazdoor']),
          'credit': parseD(entry['creditToMazdoor']),
          'balance': parseD(entry['remainingBalance']),
          'description': entry['description']?.toString(),
          'itemName': entry['itemName']?.toString(),
          'quantity': entry['quantity'] != null ? parseD(entry['quantity']) : null,
          'unitPrice': entry['rate'] != null ? parseD(entry['rate']) : null,
          // wireLines now live directly on the ledger entry itself.
          'wireLines': entry['wireLines'] is List ? entry['wireLines'] as List : null,
        });
      });

      entries.sort((a, b) =>
          (a['date'] as DateTime).compareTo(b['date'] as DateTime));

      _allEntries = entries;
    } catch (e) {
      error = 'Failed to load Mazdoor ledger: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}