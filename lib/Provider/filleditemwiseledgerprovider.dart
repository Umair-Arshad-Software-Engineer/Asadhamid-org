// items_wise_ledger_provider.dart
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class ItemsWiseLedgerProvider with ChangeNotifier {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  bool isLoading = false;
  String error = '';
  Map<String, dynamic> report = {};
  double openingBalance = 0.0;
  List<Map<String, dynamic>> _allItemTransactions = [];
  List<Map<String, dynamic>> _filteredItemTransactions = [];
  DateTimeRange? _dateRangeFilter;
  DateTimeRange? get dateRangeFilter => _dateRangeFilter;
  bool get isFiltered => _dateRangeFilter != null;
  List<Map<String, dynamic>> get transactions =>
      _dateRangeFilter == null ? _allItemTransactions : _filteredItemTransactions;
  DateTime? openingBalanceDate;
  Map<String, dynamic>? _openingBalanceTransaction;

  double get displayOpeningBalance {
    if (!isFiltered || _dateRangeFilter == null) {
      return openingBalance;
    }

    if (_allItemTransactions.isEmpty) {
      return openingBalance;
    }

    double cumulativeBalance = openingBalance;
    final dayBeforeFilterStart = _dateRangeFilter!.start.subtract(Duration(days: 1));
    final dayBeforeFilterStartOnly = DateTime(
        dayBeforeFilterStart.year,
        dayBeforeFilterStart.month,
        dayBeforeFilterStart.day
    );

    bool foundTransactionsBeforeFilter = false;

    for (var transaction in _allItemTransactions) {
      final transactionDate = _parseFirebaseDate(transaction['date']);
      if (transactionDate != null) {
        final transactionDateOnly = DateTime(
            transactionDate.year,
            transactionDate.month,
            transactionDate.day
        );

        if (transactionDateOnly.isBefore(dayBeforeFilterStartOnly) ||
            transactionDateOnly.isAtSameMomentAs(dayBeforeFilterStartOnly)) {
          foundTransactionsBeforeFilter = true;
          final debit = (transaction['debit'] ?? 0.0).toDouble();
          final credit = (transaction['credit'] ?? 0.0).toDouble();
          cumulativeBalance = cumulativeBalance + credit - debit;
        }
      }
    }

    if (!foundTransactionsBeforeFilter) {
      return openingBalance;
    }

    return cumulativeBalance;
  }

  DateTime? get displayOpeningBalanceDate {
    if (!isFiltered || _dateRangeFilter == null) {
      return openingBalanceDate;
    }

    bool hasTransactionsBeforeFilter = _allItemTransactions.any((transaction) {
      final transactionDate = _parseFirebaseDate(transaction['date']);
      if (transactionDate == null) return false;

      final transactionDateOnly = DateTime(
          transactionDate.year,
          transactionDate.month,
          transactionDate.day
      );
      final filterStartOnly = DateTime(
          _dateRangeFilter!.start.year,
          _dateRangeFilter!.start.month,
          _dateRangeFilter!.start.day
      );

      return transactionDateOnly.isBefore(filterStartOnly);
    });

    if (!hasTransactionsBeforeFilter && openingBalanceDate != null) {
      return openingBalanceDate;
    }

    return _dateRangeFilter!.start.subtract(Duration(days: 1));
  }

  String get openingBalanceLabel {
    if (!isFiltered || _dateRangeFilter == null) {
      return 'Opening Balance';
    }
    return 'Previous Balance';
  }

  void setDateRangeFilter(DateTimeRange? range) {
    _dateRangeFilter = range;
    if (range != null) {
      _applyDateFilter(range);
    } else {
      _filteredItemTransactions.clear();
      _calculateReport(_allItemTransactions);
    }
    notifyListeners();
  }

  void _applyDateFilter(DateTimeRange dateRange) {
    final startDate = DateTime(
        dateRange.start.year,
        dateRange.start.month,
        dateRange.start.day
    );
    final endDate = DateTime(
        dateRange.end.year,
        dateRange.end.month,
        dateRange.end.day,
        23, 59, 59
    );

    _filteredItemTransactions = _allItemTransactions.where((transaction) {
      final transactionDate = _parseFirebaseDate(transaction['date']);
      if (transactionDate == null) return false;

      return transactionDate.isAfter(startDate.subtract(const Duration(days: 1))) &&
          transactionDate.isBefore(endDate.add(const Duration(days: 1)));
    }).toList();

    double filteredOpeningBalance = openingBalance;

    final preFilterTransactions = _allItemTransactions.where((transaction) {
      final transactionDate = _parseFirebaseDate(transaction['date']);
      if (transactionDate == null) return false;
      return transactionDate.isBefore(startDate);
    }).toList();

    for (final transaction in preFilterTransactions) {
      final debit = (transaction['debit'] ?? 0.0).toDouble();
      final credit = (transaction['credit'] ?? 0.0).toDouble();
      filteredOpeningBalance = filteredOpeningBalance + credit - debit;
    }

    double runningBalance = filteredOpeningBalance;
    for (int i = 0; i < _filteredItemTransactions.length; i++) {
      final debit = (_filteredItemTransactions[i]['debit'] ?? 0.0).toDouble();
      final credit = (_filteredItemTransactions[i]['credit'] ?? 0.0).toDouble();
      runningBalance = runningBalance + credit - debit;
      _filteredItemTransactions[i]['balance'] = runningBalance;
    }

    _calculateReport(_filteredItemTransactions);
  }

  DateTime? _parseFirebaseDate(dynamic dateValue) {
    if (dateValue == null) return null;

    try {
      if (dateValue is String) {
        String cleanDate = dateValue.trim();

        if (cleanDate.contains('T')) {
          return DateTime.parse(cleanDate);
        } else if (cleanDate.contains('-')) {
          if (cleanDate.contains(' ')) {
            return DateTime.parse(cleanDate);
          } else {
            return DateTime.parse('$cleanDate 00:00:00');
          }
        }
      } else if (dateValue is int) {
        if (dateValue > 1000000000000) {
          return DateTime.fromMillisecondsSinceEpoch(dateValue);
        } else {
          return DateTime.fromMillisecondsSinceEpoch(dateValue * 1000);
        }
      }
    } catch (e) {
      print('Error parsing date "$dateValue": $e');
    }
    return null;
  }

  void _calculateReport(List<Map<String, dynamic>> transactions) {
    double totalDebit = 0.0;
    double totalCredit = 0.0;

    for (var transaction in transactions) {
      totalDebit += (transaction['debit'] ?? 0.0).toDouble();
      totalCredit += (transaction['credit'] ?? 0.0).toDouble();
    }

    double finalBalance = displayOpeningBalance + totalCredit - totalDebit;

    report = {
      'debit': totalDebit,
      'credit': totalCredit,
      'balance': finalBalance,
      'openingBalance': displayOpeningBalance,
    };
  }

  Future<void> fetchItemsWiseLedger(String customerId) async {
    try {
      isLoading = true;
      error = '';
      notifyListeners();

      report = {};
      _allItemTransactions = [];
      _filteredItemTransactions = [];

      await fetchOpeningBalance(customerId);

      final snapshot = await _db.child('filledledger/$customerId').once();

      if (snapshot.snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.snapshot.value as Map);

        List<Map<String, dynamic>> invoices = [];
        List<Map<String, dynamic>> payments = [];

        for (var entry in data.entries) {
          final transaction = Map<String, dynamic>.from(entry.value);

          final isOpeningBalance = transaction['filledNumber'] == 'OPENING_BAL' ||
              transaction['referenceNumber'] == 'Opening Balance' ||
              transaction['description']?.toString().toLowerCase().contains('opening balance') == true;

          if (isOpeningBalance) {
            _openingBalanceTransaction = {
              'id': entry.key,
              'key': entry.key,
              'date': transaction['createdAt'],
              'details': 'Opening Balance',
              'debit': 0.0,
              'credit': (transaction['creditAmount'] ?? 0.0).toDouble(),
              'balance': (transaction['creditAmount'] ?? 0.0).toDouble(),
              'isOpeningBalance': true,
            };
            continue;
          }

          final credit = (transaction['creditAmount'] ?? 0.0).toDouble();
          final debit = (transaction['debitAmount'] ?? 0.0).toDouble();

          // Collect invoices (credit transactions)
          if (credit > 0) {
            final filledId = transaction['filledId'] ??
                transaction['referenceNumber'] ??
                transaction['filledNumber'] ?? '';

            if (filledId.isNotEmpty) {
              invoices.add({
                'invoiceId': entry.key,
                'filledId': filledId,
                'date': transaction['createdAt'],
                'invoiceDate': transaction['date'] ?? transaction['createdAt'],
                'invoiceNumber': transaction['filledNumber'] ?? '',
                'customerName': transaction['customerName'] ?? '',
                'paymentMethod': transaction['paymentMethod'] ?? '',
                'bankName': transaction['bankName'] ?? '',
                'grandTotal': credit,
                'transactionData': transaction, // Store full transaction for matching
              });
            }
          }

          // Collect payments (debit transactions)
          if (debit > 0) {
            final paymentMethod = transaction['paymentMethod']?.toString().toLowerCase();
            final status = transaction['status']?.toString().toLowerCase();

            if (paymentMethod == 'cheque' && status != 'cleared') {
              continue;
            }

            final parsedDate = _parseFirebaseDate(transaction['createdAt']);
            final dateString = parsedDate != null ? parsedDate.toIso8601String() :
            transaction['createdAt']?.toString() ?? '';

            payments.add({
              'id': entry.key,
              'key': entry.key,
              'date': dateString,
              'details': transaction['description'] ?? transaction['details'] ?? 'Payment',
              'referenceNumber': transaction['referenceNumber'] ?? '',
              'bankName': transaction['bankName'] ?? '',
              'paymentMethod': transaction['paymentMethod'] ?? '',
              'chequeNumber': transaction['chequeNumber'] ?? '',
              'chequeStatus': transaction['status'] ?? '',
              'debit': debit,
              'credit': 0.0,
              'type': 'Payment',
              'isItem': false,
            });
          }
        }

        print('Found ${invoices.length} invoices to process');

        // Fetch items for each invoice
        List<Map<String, dynamic>> allItems = [];

        for (var invoice in invoices) {
          print('Processing invoice: ${invoice['filledId']}');
          final items = await _fetchInvoiceItems(
              invoice['filledId'],
              invoice['transactionData']
          );

          print('Found ${items.length} items for invoice ${invoice['invoiceNumber']}');

          for (var item in items) {
            allItems.add({
              'id': '${invoice['invoiceId']}_${item['itemName']}',
              'key': invoice['invoiceId'],
              'date': invoice['date'],
              'invoiceDate': invoice['invoiceDate'],
              'invoiceNumber': invoice['invoiceNumber'],
              'itemName': item['itemName'],
              'quantity': item['quantity'],
              'unitPrice': item['price'],
              'total': item['total'],
              'credit': item['total'],
              'debit': 0.0,
              'type': 'Invoice Item',
              'paymentMethod': invoice['paymentMethod'],
              'bankName': invoice['bankName'],
              'isItem': true,
              'details': '${item['itemName']} (Invoice: ${invoice['invoiceNumber']})',
            });
          }
        }

        // Add all payments
        allItems.addAll(payments);

        print('Total items + payments: ${allItems.length}');

        // Sort by date
        allItems.sort((a, b) {
          final dateA = _parseFirebaseDate(a['date']) ?? DateTime(2000);
          final dateB = _parseFirebaseDate(b['date']) ?? DateTime(2000);
          return dateA.compareTo(dateB);
        });

        // Calculate running balance
        double runningBalance = openingBalance;

        if (_openingBalanceTransaction != null && _dateRangeFilter == null) {
          _openingBalanceTransaction!['balance'] = runningBalance;
        }

        for (int i = 0; i < allItems.length; i++) {
          final debit = allItems[i]['debit'] as double;
          final credit = allItems[i]['credit'] as double;
          runningBalance = runningBalance + credit - debit;
          allItems[i]['balance'] = runningBalance;
        }

        _allItemTransactions = allItems;

        if (_dateRangeFilter != null) {
          _applyDateFilter(_dateRangeFilter!);
        } else {
          _calculateReport(_allItemTransactions);
        }

      } else {
        report = {
          'debit': 0.0,
          'credit': 0.0,
          'balance': openingBalance,
          'openingBalance': openingBalance,
        };
        _allItemTransactions = [];
      }
    } catch (e) {
      error = 'Failed to fetch items-wise ledger: $e';
      print('Error fetching items-wise ledger: $e');
      report = {
        'debit': 0.0,
        'credit': 0.0,
        'balance': openingBalance,
        'openingBalance': openingBalance,
      };
      _allItemTransactions = [];
      _filteredItemTransactions = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchInvoiceItems(
      String filledId,
      Map<String, dynamic>? transactionData
      ) async {
    try {
      if (filledId.isEmpty) {
        print('Empty filledId provided');
        return [];
      }

      print('Fetching items for filledId: $filledId');

      // Try direct path first
      var itemsSnapshot = await _db.child('filled/$filledId/items').get();

      if (itemsSnapshot.exists) {
        print('Found items at direct path: filled/$filledId/items');
        return _processItemsData(itemsSnapshot.value);
      }

      // Check if filled record exists
      final filledSnapshot = await _db.child('filled/$filledId').get();
      if (filledSnapshot.exists) {
        final filledData = Map<String, dynamic>.from(filledSnapshot.value as Map);
        print('Found filled record, keys: ${filledData.keys.toList()}');

        if (filledData.containsKey('items')) {
          print('Found items in filled record');
          return _processItemsData(filledData['items']);
        }
      }

      // Search all filled records
      print('Searching all filled records for match...');
      return await _searchAllFilledRecords(filledId, transactionData);
    } catch (e) {
      print('Error fetching invoice items: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _searchAllFilledRecords(
      String searchId,
      Map<String, dynamic>? transactionData
      ) async {
    try {
      print('Searching all filled records...');
      final allFilledSnapshot = await _db.child('filled').get();

      if (!allFilledSnapshot.exists) {
        print('No filled records found');
        return [];
      }

      dynamic allFilledData = allFilledSnapshot.value;
      Map<String, dynamic> allFilled = {};

      if (allFilledData is Map) {
        allFilled = Map<String, dynamic>.from(allFilledData);
      } else if (allFilledData is List) {
        allFilled = {for (var i = 0; i < allFilledData.length; i++) i.toString(): allFilledData[i]};
      } else {
        print('Unexpected data type: ${allFilledData.runtimeType}');
        return [];
      }

      print('Found ${allFilled.keys.length} filled records');

      // First try exact match
      for (var filledEntry in allFilled.entries) {
        try {
          dynamic filledValue = filledEntry.value;
          Map<String, dynamic> filledData = {};

          if (filledValue is Map) {
            filledData = Map<String, dynamic>.from(filledValue);
          } else {
            continue;
          }

          final filledIdFromData = filledEntry.key;
          final filledNumber = filledData['filledNumber']?.toString() ?? '';
          final referenceNumber = filledData['referenceNumber']?.toString() ?? '';

          if (filledIdFromData == searchId ||
              filledNumber == searchId ||
              referenceNumber == searchId) {
            print('Found exact match at filled/${filledEntry.key}');

            if (filledData.containsKey('items')) {
              return _processItemsData(filledData['items']);
            }
          }
        } catch (e) {
          continue;
        }
      }

      // If no exact match and we have transaction data, try matching by criteria
      if (transactionData != null) {
        final transactionDate = transactionData['createdAt']?.toString();
        final customerName = transactionData['customerName']?.toString();
        final grandTotal = transactionData['creditAmount']?.toString() ??
            transactionData['grandTotal']?.toString();

        print('Trying to match by criteria - date: $transactionDate, customer: $customerName, total: $grandTotal');

        for (var filledEntry in allFilled.entries) {
          try {
            dynamic filledValue = filledEntry.value;
            Map<String, dynamic> filledData = {};

            if (filledValue is Map) {
              filledData = Map<String, dynamic>.from(filledValue);
            } else {
              continue;
            }

            final filledDate = filledData['createdAt']?.toString();
            final filledCustomer = filledData['customerName']?.toString();
            final filledTotal = filledData['grandTotal']?.toString();

            bool dateMatch = transactionDate != null && filledDate != null &&
                transactionDate.length >= 10 && filledDate.length >= 10 &&
                transactionDate.substring(0, 10) == filledDate.substring(0, 10);

            bool customerMatch = customerName != null && filledCustomer != null &&
                customerName.toLowerCase() == filledCustomer.toLowerCase();

            bool totalMatch = grandTotal != null && filledTotal != null &&
                grandTotal == filledTotal;

            if ((dateMatch && customerMatch) || (dateMatch && totalMatch) || (customerMatch && totalMatch)) {
              print('Found match by criteria at filled/${filledEntry.key}');

              if (filledData.containsKey('items')) {
                return _processItemsData(filledData['items']);
              }
            }
          } catch (e) {
            continue;
          }
        }
      }

      print('No matching filled record found');
      return [];

    } catch (e) {
      print('Error searching filled records: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> _processItemsData(dynamic itemsData) {
    List<Map<String, dynamic>> items = [];

    print('Processing items data type: ${itemsData.runtimeType}');

    try {
      if (itemsData == null) return items;

      if (itemsData is Map) {
        items = (itemsData as Map<dynamic, dynamic>).entries.map((entry) {
          try {
            dynamic entryValue = entry.value;
            Map<String, dynamic> itemData = {};

            if (entryValue is Map) {
              itemData = Map<String, dynamic>.from(entryValue);
            } else {
              return {
                'itemName': 'Unknown Item',
                'quantity': 0.0,
                'price': 0.0,
                'total': 0.0,
              };
            }

            final quantity = _parseDouble(itemData['qty'] ?? itemData['quantity'] ?? 0);
            final price = _parseDouble(itemData['rate'] ?? itemData['price'] ?? 0);
            final total = _parseDouble(itemData['total'] ?? (quantity * price));

            return {
              'itemName': itemData['itemName']?.toString() ??
                  itemData['description']?.toString() ?? 'Unknown Item',
              'quantity': quantity,
              'price': price,
              'total': total,
            };
          } catch (e) {
            print('Error processing item entry: $e');
            return {
              'itemName': 'Unknown Item',
              'quantity': 0.0,
              'price': 0.0,
              'total': 0.0,
            };
          }
        }).toList();
      } else if (itemsData is List) {
        items = (itemsData as List<dynamic>).map((item) {
          try {
            Map<String, dynamic> itemMap = {};

            if (item is Map) {
              itemMap = Map<String, dynamic>.from(item);
            } else {
              return {
                'itemName': 'Unknown Item',
                'quantity': 0.0,
                'price': 0.0,
                'total': 0.0,
              };
            }

            final quantity = _parseDouble(itemMap['qty'] ?? itemMap['quantity'] ?? 0);
            final price = _parseDouble(itemMap['rate'] ?? itemMap['price'] ?? 0);
            final total = _parseDouble(itemMap['total'] ?? (quantity * price));

            return {
              'itemName': itemMap['itemName']?.toString() ??
                  itemMap['description']?.toString() ?? 'Unknown Item',
              'quantity': quantity,
              'price': price,
              'total': total,
            };
          } catch (e) {
            print('Error processing list item: $e');
            return {
              'itemName': 'Unknown Item',
              'quantity': 0.0,
              'price': 0.0,
              'total': 0.0,
            };
          }
        }).toList();
      }
    } catch (e) {
      print('Error in _processItemsData: $e');
    }

    print('Processed ${items.length} items');
    return items;
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  Future<void> fetchOpeningBalance(String customerId) async {
    try {
      openingBalance = 0.0;
      openingBalanceDate = null;

      final ledgerSnapshot = await _db.child('filledledger/$customerId').once();

      if (ledgerSnapshot.snapshot.exists) {
        final data = Map<String, dynamic>.from(ledgerSnapshot.snapshot.value as Map);

        for (var entry in data.entries) {
          final transaction = Map<String, dynamic>.from(entry.value);

          final isOpeningBalance =
              transaction['filledNumber'] == 'OPENING_BAL' ||
                  transaction['referenceNumber'] == 'Opening Balance' ||
                  transaction['paymentMethod'] == 'Opening Balance' ||
                  transaction['description']?.toString().toLowerCase().contains('opening balance') == true;

          if (isOpeningBalance) {
            openingBalance = (transaction['creditAmount'] ?? 0).toDouble();

            if (transaction['createdAt'] != null) {
              final createdAtValue = transaction['createdAt'].toString();
              openingBalanceDate = _parseFirebaseDate(createdAtValue) ??
                  DateTime.tryParse(createdAtValue);
            } else if (transaction['date'] != null) {
              openingBalanceDate = _parseFirebaseDate(transaction['date']);
            }

            print('Found opening balance: $openingBalance on $openingBalanceDate');
            break;
          }
        }
      }

      openingBalanceDate ??= DateTime.now().subtract(Duration(days: 365));
    } catch (e) {
      print('Error fetching opening balance: $e');
      openingBalance = 0.0;
      openingBalanceDate = DateTime.now().subtract(Duration(days: 365));
    }
  }
}