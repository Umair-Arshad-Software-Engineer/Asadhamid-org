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
    return {'debit': debit, 'credit': credit, 'balance': balance};
  }

  /// Opening balance to display for the current filter: if a date range
  /// is active, this becomes "balance carried forward" as of the filter
  /// start (previous balance), else the account's true opening balance.
  double get displayOpeningBalance {
    if (!isFiltered) return openingBalance;
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

  /// Item-wise rows: wire lines given (debit-side) and bolt / wire returns
  /// (credit-side), each flattened into its own row like invoice items.
  /// Non-item rows (cash, adjustments, opening balance) are also included
  /// so the running balance stays readable.
  List<Map<String, dynamic>> get itemWiseRows {
    final rows = <Map<String, dynamic>>[];
    for (final e in transactions) {
      final entryType = e['entryType']?.toString() ?? '';

      if (entryType == 'wire_given') {
        final wireLines = e['wireLines'];
        if (wireLines is List && wireLines.isNotEmpty) {
          for (final line in wireLines) {
            if (line is! Map) continue;
            final l = Map<String, dynamic>.from(line);

            final size = (l['itemName'] ?? '').toString();
            final length = (l['length'] ?? '').toString();
            final bodyType = (l['bodyType'] ?? '').toString();
            final qty = (l['qty'] as num?)?.toDouble() ?? 0.0;
            final wtPerUnit =
                (l['weightPerUnit'] as num?)?.toDouble() ?? 0.0;
            final totalWeight = (l['totalWeight'] as num?)?.toDouble() ??
                (wtPerUnit > 0 ? wtPerUnit * qty : qty);
            final weightUnit = (l['weightUnit'] ?? 'kg').toString();

            rows.add({
              'date': e['date'],
              'invoiceNumber': e['jobNumber'],
              'size': size,
              'length': length,
              'bodyType': bodyType,
              'itemName': _composeItemLabel(size, length, bodyType),
              'isItem': true,
              'itemKind': 'wire_given',
              'quantity': qty,
              'totalWeight': totalWeight,
              'weightUnit': weightUnit,
              'unitPrice': 0.0,
              'debit': 0.0,
              'credit': 0.0,
              'balance': e['balance'],
              'paymentMethod': '-',
              'entryKey': e['key'],
            });
          }
        } else {
          // Fallback: no wire lines stored — show a single summary row
          rows.add({
            'date': e['date'],
            'invoiceNumber': e['jobNumber'],
            'size': '-',
            'length': '',
            'bodyType': '',
            'itemName': e['description'] ?? 'Wire Given',
            'isItem': true,
            'itemKind': 'wire_given',
            'quantity': 0.0,
            'totalWeight': 0.0,
            'weightUnit': 'kg',
            'unitPrice': 0.0,
            'debit': 0.0,
            'credit': 0.0,
            'balance': e['balance'],
            'paymentMethod': '-',
            'entryKey': e['key'],
          });
        }
      } else if (entryType == 'bolt_return') {
        final qty = (e['quantity'] as num?)?.toDouble() ?? 0.0;
        final rate = (e['unitPrice'] as num?)?.toDouble() ?? 0.0;

        rows.add({
          'date': e['date'],
          'invoiceNumber': e['jobNumber'],
          'size': e['itemName'] ?? '-',
          'length': '',
          'bodyType': '',
          'itemName': e['itemName'] ?? '-',
          'isItem': true,
          'itemKind': 'bolt_return',
          'quantity': qty,
          'totalWeight': qty,
          'weightUnit': 'kg',
          'unitPrice': rate,
          'debit': 0.0,
          'credit': e['credit'],
          'balance': e['balance'],
          'paymentMethod': '-',
          'entryKey': e['key'],
        });
      } else if (entryType == 'wire_return') {
        final qty = (e['quantity'] as num?)?.toDouble() ?? 0.0;
        final wt = (e['totalWeight'] as num?)?.toDouble() ?? qty;
        final rate = (e['unitPrice'] as num?)?.toDouble() ?? 0.0;

        rows.add({
          'date': e['date'],
          'invoiceNumber': e['jobNumber'],
          'size': e['itemName'] ?? '-',
          'length': '',
          'bodyType': '',
          'itemName': e['itemName'] ?? '-',
          'isItem': true,
          'itemKind': 'wire_return',
          'quantity': qty,
          'totalWeight': wt,
          'weightUnit': 'kg',
          'unitPrice': rate,
          'debit': 0.0,
          'credit': e['credit'],
          'balance': e['balance'],
          'paymentMethod': '-',
          'entryKey': e['key'],
        });
      } else {
        // Non-item rows (cash payment, adjustment)
        rows.add({
          'date': e['date'],
          'invoiceNumber': e['jobNumber'],
          'size': '-',
          'length': '',
          'bodyType': '',
          'itemName': e['description'] ?? _labelForType(entryType),
          'isItem': false,
          'itemKind': entryType,
          'quantity': 0.0,
          'totalWeight': 0.0,
          'weightUnit': 'kg',
          'unitPrice': 0.0,
          'debit': e['debit'],
          'credit': e['credit'],
          'balance': e['balance'],
          'paymentMethod': entryType == 'cash_payment' ? 'Cash' : '-',
          'entryKey': e['key'],
        });
      }
    }
    return rows;
  }

  /// Compose a display label for the item name column, e.g.
  /// "Wire 2.5mm (3½ - Full)".
  String _composeItemLabel(String size, String length, String bodyType) {
    final parts = <String>[];
    if (size.isNotEmpty) parts.add(size);
    if (length.isNotEmpty || bodyType.isNotEmpty) {
      final sub = <String>[];
      if (length.isNotEmpty) sub.add(length);
      if (bodyType.isNotEmpty) sub.add(bodyType);
      parts.add('(${sub.join(' - ')})');
    }
    return parts.isEmpty ? '-' : parts.join(' ');
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
      final snapshot =
      await _db.child('mazdoorLedger').child(mazdoorId).get();

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
        final reference =
            (entry['reference'] ?? entry['jobNumber'])?.toString() ?? '';

        if (entryType == 'opening_balance') {
          openingBalance = parseD(entry['debitFromMazdoor']) -
              parseD(entry['creditToMazdoor']);
          openingBalanceDate = parseDate(entry['createdAt']);
          return;
        }

        entries.add({
          'key': key.toString(),
          'date': parseDate(entry['createdAt']),
          'jobNumber': reference,
          'entryType': entryType,
          'debit': parseD(entry['debitFromMazdoor']),
          'credit': parseD(entry['creditToMazdoor']),
          'balance': parseD(entry['remainingBalance']),
          'description': entry['description']?.toString(),
          'itemName': entry['itemName']?.toString(),
          'quantity': entry['quantity'] != null
              ? parseD(entry['quantity'])
              : null,
          'unitPrice':
          entry['rate'] != null ? parseD(entry['rate']) : null,
          'wireLines':
          entry['wireLines'] is List ? entry['wireLines'] as List : null,
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