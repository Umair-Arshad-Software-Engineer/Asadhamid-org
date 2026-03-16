
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

import '../Models/cashbookModel.dart';
import '../Models/itemModel.dart';

class QuoteProvider with ChangeNotifier {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  List<Map<String, dynamic>> _quote = [];
  List<Item> _items = []; // Initialize the _items list
  List<Item> get items => _items; // Add a getter for _items
  List<Map<String, dynamic>> get quote => _quote;
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  bool _hasMoreData = true;
  bool get hasMoreData => _hasMoreData;
  int _lastLoadedIndex = 0;
  String? _lastKey;
  // Page size for pagination
  final int _pageSize = 20;
  String? _selectedChequeBankId;
  String? _selectedChequeBankName;
  TextEditingController _chequeNumberController = TextEditingController();
  DateTime? _selectedChequeDate;
  final DatabaseReference _referenceCounterRef = FirebaseDatabase.instance.ref().child('customerReferenceCounters');
  bool _mounted = true;




  bool get mounted => _mounted;


  Future<int> getNextReferenceNumber(String customerId, String customerSerial) async {
    try {
      // Get or create the counter for this customer
      final counterRef = _referenceCounterRef.child(customerId);
      final snapshot = await counterRef.get();

      int lastNumber = 0;
      if (snapshot.exists) {
        final data = snapshot.value;
        lastNumber = (data is int) ? data : (data as Map?)?['lastNumber'] ?? 0;
      }

      // Increment the counter
      lastNumber++;

      // Save the new counter value
      await counterRef.set({
        'lastNumber': lastNumber,
        'customerSerial': customerSerial,
        'lastUpdated': DateTime.now().toIso8601String(),
      });

      return lastNumber;
    } catch (e) {
      print('Error getting next reference number: $e');
      return 1; // Fallback to 1
    }
  }

  Future<String> getLastReferenceNumber(String customerId) async {
    try {
      final counterRef = _referenceCounterRef.child(customerId);
      final snapshot = await counterRef.get();

      if (snapshot.exists) {
        final data = snapshot.value;
        final lastNumber = (data is int) ? data : (data as Map?)?['lastNumber'] ?? 0;
        final customerSerial = (data is Map) ? data['customerSerial']?.toString() : '';

        if (lastNumber > 0 && customerSerial!.isNotEmpty) {
          return '$customerSerial-${lastNumber.toString().padLeft(4, '0')}';
        }
      }

      return ''; // No previous reference found
    } catch (e) {
      print('Error getting last reference number: $e');
      return '';
    }
  }

  // Clear all loaded data and reset pagination
  void resetPagination() {
    _quote = [];
    _hasMoreData = true;
    _lastLoadedIndex = 0;
    _lastKey = null;
    notifyListeners();
  }

  Future<void> fetchQuote() async {
    try {
      _isLoading = true;
      notifyListeners();

      _quote.clear();

      final snapshot = await _db.child('quote')
          .orderByChild('createdAt')
          .limitToLast(_pageSize)
          .get();

      // Add explicit null check
      if (!snapshot.exists || snapshot.value == null) {
        _hasMoreData = false;
        return;
      }

      _processQuoteData(snapshot.value!);
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to fetch quote: ${e.toString()}');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _processQuoteData(dynamic data) {
    if (data == null) return;

    List<MapEntry<dynamic, dynamic>> entries = [];

    if (data is Map<dynamic, dynamic>) {
      entries = data.entries.toList();
    } else if (data is List<dynamic>) {
      entries = data.asMap().entries.map((entry) {
        return MapEntry(entry.key.toString(), entry.value);
      }).toList();
    }

    // Add null check for entry values
    entries = entries.where((entry) => entry.value != null).toList();

    entries.sort((a, b) {
      final dateA = _parseDateTime(a.value['createdAt']);
      final dateB = _parseDateTime(b.value['createdAt']);
      return dateB.compareTo(dateA);
    });

    for (var entry in entries) {
      if (entry.value != null) {
        _processQuoteEntry(entry.key.toString(), entry.value);
      }
    }
  }

  DateTime _parseDateTime(dynamic dateValue) {
    if (dateValue is String) return DateTime.parse(dateValue);
    if (dateValue is int) return DateTime.fromMillisecondsSinceEpoch(dateValue);
    return DateTime.now();
  }

  Future<void> loadMoreQuote() async {
    if (_isLoading || !_hasMoreData) return;

    try {
      _isLoading = true;
      notifyListeners();

      final lastCreatedAt = _quote.isNotEmpty
          ? _quote.last['createdAt']
          : null;

      if (lastCreatedAt == null) {
        _hasMoreData = false;
        return;
      }

      final snapshot = await _db.child('quote')
          .orderByChild('createdAt')
          .endBefore(lastCreatedAt)
          .limitToLast(_pageSize)
          .get();

      // Add null check
      if (!snapshot.exists || snapshot.value == null) {
        _hasMoreData = false;
        return;
      }

      _processQuoteData(snapshot.value!);
      notifyListeners();
    } catch (e) {
      print('Error loading more quote: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<int> getNextQuoteNumber() async {
    final counterRef = _db.child('quoteCounter');
    final transactionResult = await counterRef.runTransaction((currentData) {
      int currentCount = (currentData ?? 0) as int;
      currentCount++;
      return Transaction.success(currentCount);
    });

    if (transactionResult.committed) {
      return transactionResult.snapshot!.value as int;
    } else {
      throw Exception('Failed to increment quote counter.');
    }
  }

  bool _isTimestampNumber(String number) {
    // Only consider numbers longer than 10 digits as timestamps
    return number.length > 10 && int.tryParse(number) != null;
  }

  Future<void> saveQuote({
    required String quoteId, // Accepts the quote ID (instead of using push)
    required String quoteNumber, // Can be timestamp or sequential
    required String customerId,
    required String customerName, // Accept the customer name as a parameter
    required double subtotal,
    required double discount,
    required double mazdoori, // Add this parameter
    required double grandTotal,
    required String paymentType,
    required String referenceNumber, // Add this
    required String biltiNumber, // Add this
    required String transportCompany, // Add this
    String? paymentMethod, // For instant payments
    required String createdAt, // Add this parameter

    required List<Map<String, dynamic>> items,
  })
  async {
    try {
      if (quoteId.isEmpty || quoteNumber.isEmpty) {
        throw Exception('Quote ID and number cannot be empty');
      }
      // Filter out empty rows (where itemName is empty)
      final cleanedItems = items.where((item) =>
      (item['itemName'] as String).isNotEmpty
      ).map((item) {
        return {
          'itemName': item['itemName'],
          'rate': item['rate'] ?? 0.0,
          'qty': item['qty'] ?? 0.0,
          'size': item['size'] ?? '',
          'length': item['length'] ?? '',
          'bodyType': item['bodyType'] ?? '',
          'description': item['description'] ?? '',
          'total': item['total'] ?? 0.0,
          'calculationType': item['calculationType'] ?? 'quantity',
          'weightPerUnit': item['weightPerUnit'],
          'weightUnit': item['weightUnit'] ?? 'kg',
          'totalWeight': item['totalWeight'],
          'initialQty': item['initialQty'] ?? item['qty'] ?? 0.0,
          'lengthBodyCombination': item['lengthBodyCombination'],
          'createdAt': DateTime.now().toIso8601String(),
        };
      }).toList();

      final quoteData = {
        'referenceNumber': referenceNumber, // Add this
        'biltiNumber': biltiNumber, // Add this
        'transportCompany': transportCompany, // Add this
        'quoteNumber': quoteNumber,
        'customerId': customerId,
        'customerName': customerName, // Save customer name here
        'subtotal': subtotal,
        'discount': discount,
        'grandTotal': grandTotal,
        'paymentType': paymentType,
        'paymentMethod': paymentMethod ?? '',
        'items': cleanedItems,
        'createdAt': createdAt, // Use the provided date
        'mazdoori': mazdoori, // Add this line
        'numberType': _isTimestampNumber(quoteNumber) ? 'timestamp' : 'sequential',

      };
      // Save the quote at the specified quoteId path
      await _db.child('quote').child(quoteId).set(quoteData);
      print('quote saved');

    } catch (e) {
      throw Exception('Failed to save quote: $e');
    }
  }

  Future<void> fetchQuoteWithFilters({
    String searchQuery = '',
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
  })
  async {
    try {
      _isLoading = true;
      notifyListeners();

      Query query = _db.child('quote').orderByChild('createdAt');

      // Apply date filter if provided
      if (startDate != null && endDate != null) {
        query = query.startAt(startDate.toIso8601String()).endAt(
            endDate.toIso8601String());
      }

      final snapshot = await query.get();

      if (snapshot.exists) {
        _quote.clear();

        if (snapshot.value is Map) {
          final Map<dynamic, dynamic> values = snapshot.value as Map<
              dynamic,
              dynamic>;
          _processAndFilterQuoteData(values, searchQuery);
        } else if (snapshot.value is List) {
          final List<dynamic> values = snapshot.value as List<dynamic>;
          final Map<dynamic, dynamic> valuesMap = {};
          for (int i = 0; i < values.length; i++) {
            if (values[i] != null) {
              valuesMap[i.toString()] = values[i];
            }
          }
          _processAndFilterQuoteData(valuesMap, searchQuery);
        }
      }

      notifyListeners();
    } catch (e) {
      print('Error fetching filtered quote: ${e.toString()}');
      throw Exception('Failed to fetch filtered quote: ${e.toString()}');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool _quoteMatchesSearch(Map<dynamic, dynamic> quote, String searchQuery) {
    if (searchQuery.isEmpty) return true;

    final quoteNumber = (quote['quoteNumber'] ?? '').toString().toLowerCase();
    final referenceNumber = (quote['referenceNumber'] ?? '').toString().toLowerCase();
    final customerName = (quote['customerName'] ?? '').toString().toLowerCase();

    return quoteNumber.contains(searchQuery) ||
        customerName.contains(searchQuery) ||
        referenceNumber.contains(searchQuery);
  }


  void _processAndFilterQuoteData(Map<dynamic, dynamic> values, String searchQuery) {
    List<MapEntry<dynamic, dynamic>> sortedEntries = values.entries
        .where((entry) => entry.value != null)
        .toList()
      ..sort((a, b) {
        dynamic dateA = a.value['createdAt'];
        dynamic dateB = b.value['createdAt'];
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return _parseDateTime(dateB).compareTo(_parseDateTime(dateA));
      });

    for (var entry in sortedEntries) {
      final quote = entry.value;
      final matchesSearch = _quoteMatchesSearch(quote, searchQuery);
      if (matchesSearch) {
        _processQuoteEntry(entry.key.toString(), quote);
      }
    }
  }


  Future<Map<String, dynamic>?> getQuoteById(String quoteId) async {
    try {
      final snapshot = await _db.child('quote').child(quoteId).get();
      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to fetch quote: $e');

    }
  }

  Future<void> updateQuote({
    required String quoteId,
    required String quoteNumber,
    required String customerId,
    required String customerName,
    required double subtotal,
    required double discount,
    required double mazdoori,
    required double grandTotal,
    required String paymentType,
    String? paymentMethod,
    required String referenceNumber,
    required String biltiNumber,
    required String transportCompany,
    required List<Map<String, dynamic>> items,
    required String createdAt,
  }) async {
    try {
      // Fetch the old quote data
      final oldquote = await getQuoteById(quoteId);
      if (oldquote == null) {
        throw Exception('Quote not found.');
      }
      final isTimestamp = oldquote['numberType'] == 'timestamp';

      // Get the old grand total and date
      final double oldGrandTotal = (oldquote['grandTotal'] as num).toDouble();
      final String oldCreatedAt = oldquote['createdAt']?.toString() ?? '';

      // Calculate the difference between the old and new grand totals
      final double difference = grandTotal - oldGrandTotal;

      // Filter out empty rows
      final cleanedItems = items.where((item) =>
      (item['itemName'] as String).isNotEmpty
      ).map((item) {
        return {
          'itemName': item['itemName'],
          'rate': item['rate'] ?? 0.0,
          'qty': item['qty'] ?? 0.0,
          'size': item['size'] ?? '',
          'length': item['length'] ?? '',
          'bodyType': item['bodyType'] ?? '',
          'description': item['description'] ?? '',
          'total': item['total'] ?? 0.0,
          'calculationType': item['calculationType'] ?? 'quantity',
          'weightPerUnit': item['weightPerUnit'],
          'weightUnit': item['weightUnit'] ?? 'kg',
          'totalWeight': item['totalWeight'],
          'initialQty': item['initialQty'] ?? item['qty'] ?? 0.0,
          'lengthBodyCombination': item['lengthBodyCombination'],
          'updatedAt': DateTime.now().toIso8601String(),
        };
      }).toList();

      // Prepare the updated quote data
      final quoteData = {
        'referenceNumber': referenceNumber,
        'biltiNumber': biltiNumber,
        'transportCompany': transportCompany,
        'quoteNumber': quoteNumber,
        'customerId': customerId,
        'customerName': customerName,
        'mazdoori': mazdoori,
        'subtotal': subtotal,
        'discount': discount,
        'grandTotal': grandTotal,
        'paymentType': paymentType,
        'paymentMethod': paymentMethod ?? '',
        'items': cleanedItems,
        'updatedAt': DateTime.now().toIso8601String(),
        'createdAt': createdAt, // Use the new date
        'numberType': isTimestamp ? 'timestamp' : 'sequential',
      };

      // Update the quote in the database
      await _db.child('quote').child(quoteId).update(quoteData);

      // Step 1: Find the existing ledger entry for this quote
      final customerLedgerRef = _db.child('quoteledger').child(customerId);
      final query = customerLedgerRef.orderByChild('quoteNumber').equalTo(quoteNumber);
      final snapshot = await query.get();

      if (snapshot.exists) {
        final Map<dynamic, dynamic> entries = snapshot.value as Map<dynamic, dynamic>;
        if (entries.isNotEmpty) {
          String entryKey = entries.keys.first;
          Map<String, dynamic> entry = Map<String, dynamic>.from(entries[entryKey]);

          // Step 2: Update the existing entry with the difference AND new date
          double currentCredit = (entry['creditAmount'] as num).toDouble();
          double newCredit = currentCredit + difference;

          double currentRemaining = (entry['remainingBalance'] as num).toDouble();
          double newRemaining = currentRemaining + difference;

          await customerLedgerRef.child(entryKey).update({
            'creditAmount': newCredit,
            'remainingBalance': newRemaining,
            'createdAt': createdAt, // Update the ledger date to match quote date
            'updatedAt': DateTime.now().toIso8601String(),
          });

          print('✅ Ledger entry updated with new date: $createdAt');
        }
      }

      // Update the stock (qtyOnHand) for each item
      for (var item in items) {
        final itemName = item['itemName'];
        if (itemName == null || itemName.isEmpty) continue;

        // Find the item in the _items list
        final dbItem = _items.firstWhere(
              (i) => i.itemName == itemName,
          orElse: () => Item(id: '', itemName: '', qtyOnHand: 0.0, avgCostPricePerKg: 0.0, avgSalePricePerKg: 0.0),
        );

        if (dbItem.id.isNotEmpty) {
          final String itemId = dbItem.id;
          final double currentQty = dbItem.qtyOnHand;
          final double newQty = item['qty'] ?? 0.0;
          final double initialQty = item['initialQty'] ?? 0.0;

          // Calculate the difference between the initial quantity and the new quantity
          double delta = initialQty - newQty;

          // Update the qtyOnHand in the database
          double updatedQty = currentQty + delta;

          await _db.child('items/$itemId').update({'qtyOnHand': updatedQty});
        }
      }

      // Refresh the quote list
      await fetchQuote();

      notifyListeners();
    } catch (e) {
      throw Exception('Failed to update quote: $e');
    }
  }

  void _processQuoteEntry(String key, dynamic value) {
    // Add null check for value
    if (value == null) return;

    if (value is! Map<dynamic, dynamic>) return;

    final quoteData = Map<String, dynamic>.from(value);

    // Helper function to safely parse dates
    DateTime parseDateTime(dynamic dateValue) {
      try {
        if (dateValue is String) return DateTime.parse(dateValue);
        if (dateValue is int) return DateTime.fromMillisecondsSinceEpoch(dateValue);
        if (dateValue is DateTime) return dateValue;
      } catch (e) {
        print("Error parsing date: $e");
      }
      return DateTime.now();
    }

    // Helper function to safely parse numeric values
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    // Safely process items list
    List<Map<String, dynamic>> processItems(dynamic itemsData) {
      if (itemsData is List) {
        return itemsData.map<Map<String, dynamic>>((item) {
          if (item is Map<dynamic, dynamic>) {
            return {
              'itemName': item['itemName']?.toString() ?? '',
              'rate': parseDouble(item['rate']),
              'qty': parseDouble(item['qty']),
              'size': item['size']?.toString() ?? '',
              'length': item['length']?.toString() ?? '',
              'bodyType': item['bodyType']?.toString() ?? '',
              'description': item['description']?.toString() ?? '',
              'total': parseDouble(item['total']),
              'calculationType': item['calculationType']?.toString() ?? 'quantity',
              'weightPerUnit': item['weightPerUnit'] != null ? parseDouble(item['weightPerUnit']) : null,
              'weightUnit': item['weightUnit']?.toString() ?? 'kg',
              'totalWeight': item['totalWeight'] != null ? parseDouble(item['totalWeight']) : null,
              'initialQty': parseDouble(item['initialQty'] ?? item['qty']),
              'lengthBodyCombination': item['lengthBodyCombination'],
            };
          }
          return {};
        }).toList();
      }
      return [];
    }

    _quote.add({
      'id': key,
      'quoteNumber': quoteData['quoteNumber']?.toString() ?? 'N/A',
      'biltiNumber': quoteData['biltiNumber']?.toString() ?? '', // Add this
      'transportCompany': quoteData['transportCompany']?.toString() ?? '', // Add this
      'customerId': quoteData['customerId']?.toString() ?? '',
      'customerName': quoteData['customerName']?.toString() ?? 'N/A',
      'subtotal': parseDouble(quoteData['subtotal']),
      'discount': parseDouble(quoteData['discount']),
      'mazdoori': parseDouble(quoteData['mazdoori'] ?? 0.0), // Add this line
      'grandTotal': parseDouble(quoteData['grandTotal']),
      'paymentType': quoteData['paymentType']?.toString() ?? '',
      'paymentMethod': quoteData['paymentMethod']?.toString() ?? '',
      'cashPaidAmount': parseDouble(quoteData['cashPaidAmount']),
      'onlinePaidAmount': parseDouble(quoteData['onlinePaidAmount']),
      'chequePaidAmount': parseDouble(quoteData['chequePaidAmount'] ?? 0.0),
      'slipPaidAmount': parseDouble(quoteData['slipPaidAmount'] ?? 0.0),
      'debitAmount': parseDouble(quoteData['debitAmount']),
      'debitAt': quoteData['debitAt']?.toString() ?? '',
      'items': processItems(quoteData['items']),
      'createdAt': parseDateTime(quoteData['createdAt']).toIso8601String(),
      'remainingBalance': parseDouble(quoteData['remainingBalance']),
      'referenceNumber': quoteData['referenceNumber']?.toString() ?? '',
    });
  }

  Future<void> deleteQuote(String quoteId) async {
    try {
      // Store reference to context before async operations
      BuildContext? currentContext;

      // ✅ Correct
      final quote = _quote.firstWhere(
            (inv) => inv['id'] == quoteId,
        orElse: () => {},
      );
      if (quote.isEmpty) throw Exception("Quote not found.");

      final customerId = quote['customerId'] as String;
      final quoteNumber = quote['quoteNumber'] as String;

      // Get the items from the quote
      final List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(quote['items']);

      // Reverse the deduction for each item based on calculation type
      for (var item in items) {
        final itemName = item['itemName'] as String;

        // Determine what to restore based on calculation type
        double quantityToRestore = 0.0;

        if (item['calculationType'] == 'weight') {
          // For weight-based items, restore total weight
          final totalWeight = (item['totalWeight'] as num?)?.toDouble() ?? 0.0;
          final weightUnit = item['weightUnit']?.toString() ?? 'kg';

          // Convert to kg for storage
          if (weightUnit == 'g') {
            quantityToRestore = totalWeight / 1000;
          } else if (weightUnit == 'ton') {
            quantityToRestore = totalWeight * 1000;
          } else if (weightUnit == 'lb') {
            quantityToRestore = totalWeight * 0.453592;
          } else {
            quantityToRestore = totalWeight;
          }
        } else {
          // For quantity-based items, restore quantity
          quantityToRestore = (item['qty'] as num?)?.toDouble() ?? 0.0;
        }

        // Fetch the item from the database
        final itemSnapshot = await _db.child('items').orderByChild('itemName').equalTo(itemName).get();

        if (itemSnapshot.exists) {
          final itemData = itemSnapshot.value as Map<dynamic, dynamic>;
          final itemKey = itemData.keys.first;
          final currentItem = itemData[itemKey] as Map<dynamic, dynamic>;

          // Get the current qtyOnHand
          double currentQtyOnHand = (currentItem['qtyOnHand'] as num).toDouble();

          // Add back the quantity/weight to qtyOnHand
          double updatedQtyOnHand = currentQtyOnHand + quantityToRestore;

          // Update the item in the database
          await _db.child('items').child(itemKey).update({'qtyOnHand': updatedQtyOnHand});

          print('Stock restored for $itemName: $quantityToRestore (updated: $updatedQtyOnHand)');
        }
      }

      // Delete the quote from the database
      await _db.child('quote').child(quoteId).remove();

      _quote.removeWhere((inv) => inv['id'] == quoteId);

      // Only notify listeners if we're still mounted
      notifyListeners();

    } catch (e) {
      // Don't throw if we're not mounted - just log the error
      print('Failed to delete quote and ledger entries: $e');
      if (mounted) {
        throw Exception('Failed to delete quote and ledger entries: $e');
      }
    }
  }




  List<Map<String, dynamic>> getQuoteByPaymentMethod(String paymentMethod) {
    return _quote.where((quote) {
      final method = quote['paymentMethod'] ?? '';
      return method.toLowerCase() == paymentMethod.toLowerCase();
    }).toList();
  }

  double _parseToDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) {
      try {
        return double.parse(value);
      } catch (e) {
        return 0.0;
      }
    }
    return 0.0;
  }

  Future<List<Map<String, dynamic>>> getChequesByBank(String bankId) async {
    final snapshot = await _db.child('cheques')
        .orderByChild('bankId')
        .equalTo(bankId)
        .get();
    try {

      if (!snapshot.exists) return [];

      final cheques = <Map<String, dynamic>>[];
      final data = snapshot.value as Map<dynamic, dynamic>;

      data.forEach((key, value) {
        cheques.add({
          'id': key,
          ...Map<String, dynamic>.from(value),
        });
      });

      // Sort by date (newest first)
      cheques.sort((a, b) {
        final dateA = DateTime.parse(a['createdAt']);
        final dateB = DateTime.parse(b['createdAt']);
        return dateB.compareTo(dateA);
      });

      return cheques;
    } catch (e) {
      throw Exception('Failed to fetch cheques: $e');
    }
  }

  Future<void> updateChequeStatus({
    required String chequeId,
    required String status,
    String? bankId,
  })
  async {
    await _db.child('cheques').child(chequeId).update({
      'status': status,
      'updatedAt': DateTime.now().toIso8601String(),
    });

    if (status == 'cleared' && bankId != null) {
      // Update bank balance
      final chequeSnapshot = await _db.child('cheques').child(chequeId).get();
      if (chequeSnapshot.exists) {
        final cheque = Map<String, dynamic>.from(chequeSnapshot.value as Map);
        final amount = (cheque['amount'] as num).toDouble();

        final bankBalanceRef = _db.child('banks/$bankId/balance');
        final currentBalance = (await bankBalanceRef.get()).value as num? ?? 0.0;
        await bankBalanceRef.set(currentBalance + amount);
      }
    }
  }

  Future<List<Map<String, dynamic>>> getAllCheques() async {
    try {
      final snapshot = await _db.child('cheques').get();


      if (!snapshot.exists) return [];

      final cheques = <Map<String, dynamic>>[];
      final data = snapshot.value as Map<dynamic, dynamic>;

      data.forEach((key, value) {
        cheques.add({
          'id': key,
          ...Map<String, dynamic>.from(value),
        });
      });

      // Sort by date (newest first)
      cheques.sort((a, b) {
        final dateA = DateTime.parse(a['createdAt']);
        final dateB = DateTime.parse(b['createdAt']);
        return dateB.compareTo(dateA);
      });

      return cheques;
    } catch (e) {
      throw Exception('Failed to fetch cheques: $e');
    }
  }








  List<Map<String, dynamic>> getTodaysQuote() {
    final today = DateTime.now();
    // final startOfDay = DateTime(today.year, today.month, today.day - 1); // Include yesterday
    final startOfDay = DateTime(today.year, today.month, today.day ); // Include yesterdays

    final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);

    return _quote.where((quote) {
      final quoteDate = DateTime.tryParse(quote['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(int.parse(quote['createdAt']));
      return quoteDate.isAfter(startOfDay) && quoteDate.isBefore(endOfDay);
    }).toList();
  }

  double getTotalAmountquote(List<Map<String, dynamic>> quote) {
    return quote.fold(0.0, (sum, quote) => sum + (quote['grandTotal'] ?? 0.0));
  }

  double getTotalPaidAmountquote(List<Map<String, dynamic>> quote) {
    return quote.fold(0.0, (sum, quote) => sum + (quote['debitAmount'] ?? 0.0));
  }


  @override
  void dispose() {
    _mounted = false;
    super.dispose();
  }
}