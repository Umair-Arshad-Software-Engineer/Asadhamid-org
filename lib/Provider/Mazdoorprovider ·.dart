// mazdoorProvider.dart
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../Models/itemModel.dart';
import '../Models/mazdoorModel.dart';

class MazdoorProvider with ChangeNotifier {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  List<MazdoorPerson> _mazdoors = [];
  List<MazdoorPerson> get mazdoors => _mazdoors;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // ─────────────────────────────────────────────────────────────
  // Serial numbers (A, B, C ... same alphabetical scheme as Customer)
  // ─────────────────────────────────────────────────────────────
  String _numberToAlphabetical(int number) {
    String result = '';
    while (number > 0) {
      number--;
      result = String.fromCharCode(65 + (number % 26)) + result;
      number = number ~/ 26;
    }
    return result.isEmpty ? 'A' : result;
  }

  Future<String> _generateMazdoorSerial() async {
    final counterRef = _db.child('mazdoorSerialCounter');
    final snapshot = await counterRef.get();
    int lastNumber = 0;
    if (snapshot.exists) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      lastNumber = (data['lastNumber'] as int?) ?? 0;
    }
    lastNumber++;
    await counterRef.set({
      'lastNumber': lastNumber,
      'lastUpdated': DateTime.now().toIso8601String(),
    });
    return _numberToAlphabetical(lastNumber);
  }

  /// Auto-generated reference for a "wire given" ledger entry, purely
  /// for record-keeping / display (e.g. "WG-00001"). Not a trackable
  /// job — there's no outstanding-balance concept tied to it.
  Future<String> _nextWireReference() async {
    final counterRef = _db.child('mazdoorWireRefCounter');
    final result = await counterRef.runTransaction((currentData) {
      int current = (currentData ?? 0) as int;
      current++;
      return Transaction.success(current);
    });
    if (result.committed) {
      return 'WG-${(result.snapshot!.value as int).toString().padLeft(5, '0')}';
    }
    throw Exception('Failed to generate wire reference.');
  }

  // ─────────────────────────────────────────────────────────────
  // CRUD: Mazdoor persons
  // ─────────────────────────────────────────────────────────────
  Future<void> fetchMazdoors() async {
    _isLoading = true;
    notifyListeners();
    try {
      final snapshot = await _db.child('mazdoors').get();
      if (snapshot.exists && snapshot.value != null) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        _mazdoors = data.entries
            .map((e) => MazdoorPerson.fromSnapshot(
            e.key.toString(), e.value as Map<dynamic, dynamic>))
            .toList();
        _mazdoors.sort((a, b) => a.name.compareTo(b.name));
      } else {
        _mazdoors = [];
      }
    } catch (e) {
      print('Error fetching mazdoors: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String> addMazdoor({
    required String name,
    String phone = '',
    String address = '',
    String city = '',
    double openingBalance = 0.0,
    DateTime? openingBalanceDate,
  }) async {
    final serial = await _generateMazdoorSerial();
    final ref = _db.child('mazdoors').push();
    final id = ref.key!;

    await ref.set({
      'name': name,
      'phone': phone,
      'address': address,
      'city': city,
      'mazdoorSerial': serial,
      'openingBalance': openingBalance,
      'openingBalanceDate':
      (openingBalanceDate ?? DateTime.now()).toIso8601String(),
      'type': 'mazdoor',
      'createdAt': DateTime.now().toIso8601String(),
    });

    if (openingBalance != 0.0) {
      // Positive opening balance = mazdoor owes you => debit entry
      await _appendLedgerEntry(
        mazdoorId: id,
        reference: 'OPENING_BAL',
        entryType: 'opening_balance',
        debit: openingBalance > 0 ? openingBalance : 0.0,
        credit: openingBalance < 0 ? -openingBalance : 0.0,
        description: 'Opening Balance',
        date: openingBalanceDate ?? DateTime.now(),
      );
    }

    await fetchMazdoors();
    return id;
  }

  Future<void> updateMazdoor({
    required String id,
    required String name,
    String phone = '',
    String address = '',
    String city = '',
  }) async {
    await _db.child('mazdoors').child(id).update({
      'name': name,
      'phone': phone,
      'address': address,
      'city': city,
    });
    await fetchMazdoors();
  }

  Future<void> deleteMazdoor(String id) async {
    await _db.child('mazdoors').child(id).remove();
    await fetchMazdoors();
  }

  // ─────────────────────────────────────────────────────────────
  // Ledger balance
  // ─────────────────────────────────────────────────────────────
  /// Positive => Mazdoor owes you. Negative => you owe the Mazdoor.
  Future<double> getMazdoorBalance(String mazdoorId) async {
    final snapshot = await _db.child('mazdoorLedger').child(mazdoorId).get();
    if (!snapshot.exists || snapshot.value == null) return 0.0;
    final data = snapshot.value as Map<dynamic, dynamic>;
    double totalDebit = 0.0;
    double totalCredit = 0.0;
    data.forEach((key, value) {
      if (value == null) return;
      final entry = value as Map<dynamic, dynamic>;
      totalDebit += (entry['debitFromMazdoor'] as num?)?.toDouble() ?? 0.0;
      totalCredit += (entry['creditToMazdoor'] as num?)?.toDouble() ?? 0.0;
    });
    return totalDebit - totalCredit;
  }

  Future<List<MazdoorLedgerEntry>> getMazdoorLedger(String mazdoorId) async {
    final snapshot = await _db.child('mazdoorLedger').child(mazdoorId).get();
    if (!snapshot.exists || snapshot.value == null) return [];
    final data = snapshot.value as Map<dynamic, dynamic>;
    final entries = data.entries
        .where((e) => e.value != null)
        .map((e) => MazdoorLedgerEntry.fromMap(
        e.key.toString(), mazdoorId, e.value as Map))
        .toList();
    entries.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return entries;
  }

  /// Most recent 'wire_given' ledger entry's reference, used to loosely
  /// tag a bolt/cash return so records stay traceable without asking
  /// the user to pick anything. Purely informational — no outstanding
  /// balance or settlement math depends on this.
  Future<String?> _mostRecentWireReference(String mazdoorId) async {
    final snapshot = await _db.child('mazdoorLedger').child(mazdoorId).get();
    if (!snapshot.exists || snapshot.value == null) return null;
    final data = snapshot.value as Map<dynamic, dynamic>;

    String? latestRef;
    DateTime? latestDate;

    data.forEach((key, value) {
      if (value == null) return;
      final entry = value as Map<dynamic, dynamic>;
      if (entry['entryType'] != 'wire_given') return;
      final dateStr = entry['createdAt']?.toString();
      final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
      if (date == null) return;
      if (latestDate == null || date.isAfter(latestDate!)) {
        latestDate = date;
        latestRef = entry['reference']?.toString();
      }
    });

    return latestRef;
  }

  /// Internal helper: appends one ledger row and returns the new running
  /// balance. `debit` increases balance (mazdoor owes more), `credit`
  /// decreases it (settles debt, can go negative -> you owe them).
  Future<double> _appendLedgerEntry({
    required String mazdoorId,
    required String reference,
    required String entryType,
    double debit = 0.0,
    double credit = 0.0,
    String? description,
    String? itemName,
    double? quantity,
    double? rate,
    double? weightPerUnit,
    String? weightUnit,
    double? totalWeight,
    String? batchId,
    String? batchNumber,
    List<Map<String, dynamic>>? wireLines,
    DateTime? date,
  }) async {
    final currentBalance = await getMazdoorBalance(mazdoorId);
    final newBalance = currentBalance + debit - credit;

    final ledgerRef = _db.child('mazdoorLedger').child(mazdoorId).push();
    await ledgerRef.set({
      'reference': reference,
      'entryType': entryType,
      'debitFromMazdoor': debit,
      'creditToMazdoor': credit,
      'remainingBalance': newBalance,
      'description': description,
      'itemName': itemName,
      'quantity': quantity,
      'rate': rate,
      'weightPerUnit': weightPerUnit,
      'weightUnit': weightUnit ?? 'kg',
      'totalWeight': totalWeight,
      'batchId': batchId,
      'batchNumber': batchNumber,
      if (wireLines != null) 'wireLines': wireLines,
      'createdAt': (date ?? DateTime.now()).toIso8601String(),
    });

    return newBalance;
  }

  // ─────────────────────────────────────────────────────────────
  // GIVE WIRE: debits the Mazdoor by the given value and deducts wire
  // stock. Wire line details are stored on the ledger entry purely for
  // record-keeping — there's no separate "job" to track or settle.
  // ─────────────────────────────────────────────────────────────
  Future<String> giveWire({
    required String mazdoorId,
    required String mazdoorName,
    required List<MazdoorWireLine> wireLines,
    required double value,
    String? notes,
    DateTime? date,
  }) async {
    if (wireLines.isEmpty) {
      throw Exception('At least one wire item line is required.');
    }
    if (value <= 0) {
      throw Exception('Value must be greater than zero.');
    }

    final reference = await _nextWireReference();

    // Debit the Mazdoor: they now owe you this value.
    await _appendLedgerEntry(
      mazdoorId: mazdoorId,
      reference: reference,
      entryType: 'wire_given',
      debit: value,
      description: notes ?? 'Wire given ($reference)',
      wireLines: wireLines.map((w) => w.toMap()).toList(),
      date: date,
    );

    // Deduct wire stock (batch-aware, mirrors Filled page logic).
    await _deductWireStock(wireLines);

    return reference;
  }

  // ─────────────────────────────────────────────────────────────
  // GIVE WIRE (single item, rate based) — mirror of receiveWire.
  // Debits the Mazdoor by `overrideValue` if provided (the exact
  // amount the UI table shows in the Total column), otherwise by
  // (totalWeight × rate/kg). Deducts stock and stores length/body.
  // ─────────────────────────────────────────────────────────────
  Future<String> giveWireItem({
    required String mazdoorId,
    required String mazdoorName,
    required String wireItemName,
    required double quantity,
    required double rate,
    double? weightPerUnit,
    String? weightUnit,
    double? totalWeight,
    double? overrideValue,
    String? length,
    String? bodyType,
    String? batchId,
    String? batchNumber,
    String? description,
    DateTime? date,
  }) async {
    if (quantity <= 0 || rate <= 0) {
      throw Exception('Quantity and rate must be greater than zero.');
    }
    final double wt = totalWeight ??
        ((weightPerUnit != null && weightPerUnit > 0)
            ? weightPerUnit * quantity
            : quantity);
    final double wireValue = overrideValue ?? (wt * rate);
    final reference = await _nextWireReference();

    final line = MazdoorWireLine(
      itemName: wireItemName,
      length: length ?? '',
      bodyType: bodyType ?? '',
      qty: quantity,
      weightPerUnit: weightPerUnit,
      weightUnit: weightUnit ?? 'kg',
      totalWeight: wt,
      batchId: batchId,
      batchNumber: batchNumber,
    );

    await _appendLedgerEntry(
      mazdoorId: mazdoorId,
      reference: reference,
      entryType: 'wire_given',
      debit: wireValue,
      description: description ?? 'Wire given ($reference)',
      itemName: wireItemName,
      quantity: quantity,
      rate: rate,
      weightPerUnit: weightPerUnit,
      weightUnit: weightUnit ?? 'kg',
      totalWeight: wt,
      batchId: batchId,
      batchNumber: batchNumber,
      wireLines: [line.toMap()],
      date: date,
    );

    await _deductWireStock([line]);
    return reference;
  }

  // ─────────────────────────────────────────────────────────────
  // GIVE BOLTS — Mazdoor is given finished bolts (qty × rate).
  // Debits the Mazdoor and deducts bolt stock from items.
  // `overrideValue` (from UI Total column) wins when provided.
  // ─────────────────────────────────────────────────────────────
  Future<String> giveBolts({
    required String mazdoorId,
    required String mazdoorName,
    required String boltItemName,
    required double quantity,
    required double rate,
    double? overrideValue,
    String? description,
    DateTime? date,
  }) async {
    if (quantity <= 0 || rate <= 0) {
      throw Exception('Quantity and rate must be greater than zero.');
    }
    final double value = overrideValue ?? (quantity * rate);
    final reference = await _nextWireReference();

    await _appendLedgerEntry(
      mazdoorId: mazdoorId,
      reference: reference,
      entryType: 'bolt_given',
      debit: value,
      description: description ?? 'Bolts given ($reference)',
      itemName: boltItemName,
      quantity: quantity,
      rate: rate,
      date: date,
    );

    final itemSnapshot = await _db
        .child('items')
        .orderByChild('itemName')
        .equalTo(boltItemName)
        .get();
    if (itemSnapshot.exists) {
      final itemsMap = itemSnapshot.value as Map<dynamic, dynamic>;
      final itemKey = itemsMap.keys.first;
      final itemData = itemsMap[itemKey] as Map<dynamic, dynamic>;
      final currentQty = (itemData['qtyOnHand'] as num?)?.toDouble() ?? 0.0;
      await _db.child('items').child(itemKey.toString()).update({
        'qtyOnHand': (currentQty - quantity).clamp(0.0, double.infinity),
      });
    }
    return reference;
  }

  // ─────────────────────────────────────────────────────────────
  // GIVE CASH — money paid out to the Mazdoor (advance/payment).
  // Debits the Mazdoor. No stock effect.
  // ─────────────────────────────────────────────────────────────
  Future<void> giveCashPayment({
    required String mazdoorId,
    required String mazdoorName,
    required double amount,
    String? description,
    DateTime? date,
  }) async {
    if (amount <= 0) {
      throw Exception('Amount must be greater than zero.');
    }
    await _appendLedgerEntry(
      mazdoorId: mazdoorId,
      reference: 'CASHOUT-${DateTime.now().millisecondsSinceEpoch}',
      entryType: 'cash_given',
      debit: amount,
      description: description ?? 'Cash given',
      date: date,
    );
  }

  Future<void> _deductWireStock(List<MazdoorWireLine> lines) async {
    for (final line in lines) {
      if (line.itemName.isEmpty) continue;

      double weightToDeduct;
      if (line.totalWeight != null && line.totalWeight! > 0) {
        weightToDeduct = line.totalWeight!;
      } else {
        weightToDeduct = line.qty;
      }
      if (weightToDeduct <= 0) continue;

      // Batch-wise deduction if a batch was selected.
      if (line.batchId != null && line.batchId!.isNotEmpty) {
        final batchRef = _db.child('batches').child(line.batchId!);
        final batchSnap = await batchRef.get();
        if (batchSnap.exists) {
          final batchData = Map<String, dynamic>.from(batchSnap.value as Map);
          final currentQty =
              (batchData['quantity'] as num?)?.toDouble() ?? 0.0;
          final updatedQty =
          (currentQty - weightToDeduct).clamp(0.0, double.infinity);
          await batchRef.update({
            'quantity': updatedQty,
            'remainingQty': updatedQty,
            'isActive': updatedQty > 0,
          });
        }
      }

      // Item-level qtyOnHand deduction.
      final itemSnapshot = await _db
          .child('items')
          .orderByChild('itemName')
          .equalTo(line.itemName)
          .get();
      if (itemSnapshot.exists) {
        final itemsMap = itemSnapshot.value as Map<dynamic, dynamic>;
        final itemKey = itemsMap.keys.first;
        final itemData = itemsMap[itemKey] as Map<dynamic, dynamic>;
        final currentQty =
            (itemData['qtyOnHand'] as num?)?.toDouble() ?? 0.0;
        final updatedQty =
        (currentQty - weightToDeduct).clamp(0.0, double.infinity);
        await _db.child('items').child(itemKey.toString()).update({
          'qtyOnHand': updatedQty,
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // RECEIVE BOLTS: Mazdoor returns finished bolts. Credits the Mazdoor
  // by `overrideValue` if provided, otherwise (qty * rate), reducing
  // their running balance (can go negative, meaning you now owe them).
  // Auto-tags the entry with the most recent wire-given reference for
  // traceability. Adds bolt stock into `items`.
  // ─────────────────────────────────────────────────────────────
  Future<void> receiveBolts({
    required String mazdoorId,
    required String mazdoorName,
    required String boltItemName,
    required double quantity,
    required double rate,
    String? boltItemId,
    double? overrideValue,
    String? description,
    DateTime? date,
  }) async {
    if (quantity <= 0 || rate <= 0) {
      throw Exception('Quantity and rate must be greater than zero.');
    }
    final double boltValue = overrideValue ?? (quantity * rate);
    final linkedRef = await _mostRecentWireReference(mazdoorId);
    final entryRef =
        linkedRef ?? 'RETURN-${DateTime.now().millisecondsSinceEpoch}';

    await _appendLedgerEntry(
      mazdoorId: mazdoorId,
      reference: entryRef,
      entryType: 'bolt_return',
      credit: boltValue,
      description: description ?? 'Bolts returned',
      itemName: boltItemName,
      quantity: quantity,
      rate: rate,
      date: date,
    );

    // Add bolt stock into items (create or increment qtyOnHand).
    final String itemKey = await _addItemStock(
      itemId: boltItemId,
      itemName: boltItemName,
      quantity: quantity,
      rate: rate,
    );

    // Create a batch for this return so it flows through the same
    // batch-tracking pipeline as normal purchases.
    if (itemKey.isNotEmpty) {
      await _createReturnBatch(
        itemName: boltItemName,
        itemKey: itemKey,
        length: '',
        bodyType: '',
        totalWeight: quantity,
        ratePerKg: rate,
        entryType: 'bolt_return',
        ledgerReference: entryRef,
      );
    }
  }

  /// Ensures the item exists and increments its qtyOnHand.
  /// Returns the resolved item key (empty if it could not be resolved).
  Future<String> _addItemStock({
    String? itemId,
    required String itemName,
    required double quantity,
    required double rate,
  }) async {
    DatabaseReference itemRef;
    String resolvedKey = '';

    if (itemId != null && itemId.isNotEmpty) {
      itemRef = _db.child('items').child(itemId);
      resolvedKey = itemId;
    } else {
      final existing = await _db
          .child('items')
          .orderByChild('itemName')
          .equalTo(itemName)
          .get();
      if (existing.exists) {
        final itemsMap = existing.value as Map<dynamic, dynamic>;
        final key = itemsMap.keys.first;
        itemRef = _db.child('items').child(key.toString());
        resolvedKey = key.toString();
      } else {
        itemRef = _db.child('items').push();
        resolvedKey = itemRef.key ?? '';
        await itemRef.set({
          'itemName': itemName,
          'avgCostPricePerKg': rate,
          'avgSalePricePerKg': rate,
          'costPrice': rate,
          'salePrice': rate,
          'unit': 'Kg',
          'qtyOnHand': 0.0,
          'createdAt': ServerValue.timestamp,
        });
      }
    }

    final snap = await itemRef.get();
    final currentQty = snap.exists
        ? ((snap.value as Map)['qtyOnHand'] as num?)?.toDouble() ?? 0.0
        : 0.0;
    await itemRef.update({'qtyOnHand': currentQty + quantity});

    return resolvedKey;
  }

  // ─────────────────────────────────────────────────────────────
  // RECEIVE WIRE: Mazdoor returns raw wire. Credits the Mazdoor by
  // `overrideValue` if provided, otherwise (weight × rate/kg). Also
  // auto-tags with the most recent wire-given reference. Adds wire
  // stock back into `items` and, if a batch was chosen, restores that
  // batch's quantity. Stores length/body/weightUnit on the entry.
  // ─────────────────────────────────────────────────────────────
  Future<void> receiveWire({
    required String mazdoorId,
    required String mazdoorName,
    required String wireItemName,
    String? wireItemId,
    required double quantity,
    required double rate,
    double? weightPerUnit,
    String? weightUnit,
    double? totalWeight,
    double? overrideValue,
    String? length,
    String? bodyType,
    String? batchId,
    String? description,
    DateTime? date,
  }) async {
    if (quantity <= 0 || rate <= 0) {
      throw Exception('Quantity and rate must be greater than zero.');
    }

    // Resolve total weight in kg
    final double wt = totalWeight ??
        ((weightPerUnit != null && weightPerUnit > 0)
            ? weightPerUnit * quantity
            : quantity);

    final double wireValue = overrideValue ?? (wt * rate);
    final linkedRef = await _mostRecentWireReference(mazdoorId);
    final entryRef =
        linkedRef ?? 'RETURN-${DateTime.now().millisecondsSinceEpoch}';

    // Store wire lines so item-wise ledger can show each row cleanly.
    final line = MazdoorWireLine(
      itemName: wireItemName,
      length: length ?? '',
      bodyType: bodyType ?? '',
      qty: quantity,
      weightPerUnit: weightPerUnit,
      weightUnit: weightUnit ?? 'kg',
      totalWeight: wt,
      batchId: batchId,
    );

    await _appendLedgerEntry(
      mazdoorId: mazdoorId,
      reference: entryRef,
      entryType: 'wire_return',
      credit: wireValue,
      description: description ?? 'Wire returned',
      itemName: wireItemName,
      quantity: quantity,
      rate: rate,
      weightPerUnit: weightPerUnit,
      weightUnit: weightUnit ?? 'kg',
      totalWeight: wt,
      batchId: batchId,
      wireLines: [line.toMap()],
      date: date,
    );

    // Restore wire stock back into items (create if needed).
    final String itemKey = await _addItemStock(
      itemId: wireItemId,
      itemName: wireItemName,
      quantity: wt,
      rate: rate,
    );

    // Create a batch for this wire return.
    if (itemKey.isNotEmpty) {
      await _createReturnBatch(
        itemName: wireItemName,
        itemKey: itemKey,
        length: length ?? '',
        bodyType: bodyType ?? '',
        totalWeight: wt,
        ratePerKg: rate,
        entryType: 'wire_return',
        ledgerReference: entryRef,
      );
    }

    // If a batch was selected on the form, ALSO restore that original
    // batch's quantity (the wire was physically put back into it).
    if (batchId != null && batchId.isNotEmpty && wt > 0) {
      try {
        final batchRef = _db.child('batches').child(batchId);
        final batchSnap = await batchRef.get();
        if (batchSnap.exists) {
          final batchData =
          Map<String, dynamic>.from(batchSnap.value as Map);
          final currentQty =
              (batchData['quantity'] as num?)?.toDouble() ?? 0.0;
          final updatedQty = currentQty + wt;
          await batchRef.update({
            'quantity': updatedQty,
            'remainingQty': updatedQty,
            'isActive': true,
          });
        }
      } catch (e) {
        print('receiveWire: failed to restore batch: $e');
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // RECEIVE CASH: straightforward credit, no stock effect. Same
  // auto-tagging as receiveBolts, purely for traceability.
  // ─────────────────────────────────────────────────────────────
  Future<void> receiveCashPayment({
    required String mazdoorId,
    required String mazdoorName,
    required double amount,
    String? description,
    DateTime? date,
  }) async {
    if (amount <= 0) {
      throw Exception('Amount must be greater than zero.');
    }
    final linkedRef = await _mostRecentWireReference(mazdoorId);

    await _appendLedgerEntry(
      mazdoorId: mazdoorId,
      reference:
      linkedRef ?? 'RETURN-${DateTime.now().millisecondsSinceEpoch}',
      entryType: 'cash_payment',
      credit: amount,
      description: description ?? 'Cash payment',
      date: date,
    );
  }

  /// A plain advance/adjustment with no wire or item context.
  Future<void> giveAdvance({
    required String mazdoorId,
    required double amount,
    String? description,
    DateTime? date,
  }) async {
    if (amount <= 0) throw Exception('Amount must be greater than zero.');
    await _appendLedgerEntry(
      mazdoorId: mazdoorId,
      reference: 'ADVANCE-${DateTime.now().millisecondsSinceEpoch}',
      entryType: 'adjustment',
      debit: amount,
      description: description ?? 'Advance given',
      date: date,
    );
  }

  // ═════════════════════════════════════════════════════════════
  // DELETE a ledger entry: reverses stock/batch effects, removes the
  // row, then recomputes the running balances of all remaining rows.
  // ═════════════════════════════════════════════════════════════
  Future<void> deleteLedgerEntry({
    required String mazdoorId,
    required String entryKey,
  }) async {
    final ledgerRef = _db.child('mazdoorLedger').child(mazdoorId);
    final entryRef = ledgerRef.child(entryKey);

    // 1. Read the entry we're about to delete
    final snap = await entryRef.get();
    if (!snap.exists) return;
    final entry = Map<String, dynamic>.from(snap.value as Map);
    final entryType = entry['entryType']?.toString() ?? '';
    final reference = entry['reference']?.toString() ?? '';

    // 2. Reverse stock effects based on entry type
    try {
      if (entryType == 'bolt_return') {
        // Bolt return originally ADDED qty to the item and created a
        // batch → we must SUBTRACT qty from item and deactivate the batch.
        final itemName = entry['itemName']?.toString() ?? '';
        final qty = (entry['quantity'] as num?)?.toDouble() ?? 0.0;
        if (itemName.isNotEmpty && qty > 0) {
          await _reverseItemStockAddition(itemName, qty);
        }
        await _deactivateReturnBatch(reference);
      } else if (entryType == 'wire_return') {
        // Wire return originally ADDED totalWeight kg to the item and
        // created a batch → we must SUBTRACT kg from item and deactivate.
        // It may ALSO have topped up an existing batch (batchId).
        final itemName = entry['itemName']?.toString() ?? '';
        final qty = (entry['quantity'] as num?)?.toDouble() ?? 0.0;
        final wt = (entry['totalWeight'] as num?)?.toDouble() ?? qty;

        if (itemName.isNotEmpty && wt > 0) {
          await _reverseItemStockAddition(itemName, wt);
        }

        // If a batch was topped up at return time, subtract back
        final batchId = entry['batchId']?.toString();
        if (batchId != null && batchId.isNotEmpty && wt > 0) {
          await _subtractFromBatch(batchId, wt);
        }

        await _deactivateReturnBatch(reference);
      } else if (entryType == 'bolt_given') {
        // Bolts given originally DEDUCTED qty from the item → add back.
        final itemName = entry['itemName']?.toString() ?? '';
        final qty = (entry['quantity'] as num?)?.toDouble() ?? 0.0;
        if (itemName.isNotEmpty && qty > 0) {
          await _addItemStock(
            itemId: null,
            itemName: itemName,
            quantity: qty,
            rate: 0.0,
          );
        }
      } else if (entryType == 'wire_given') {
        // Wire given originally DEDUCTED stock → we must ADD it back
        // for each wire line, and restore the original batch if used.
        final wireLines = entry['wireLines'];
        if (wireLines is List) {
          for (final l in wireLines) {
            if (l is! Map) continue;
            final itemName = l['itemName']?.toString() ?? '';
            final totalWeight =
                (l['totalWeight'] as num?)?.toDouble() ?? 0.0;
            final qty = (l['qty'] as num?)?.toDouble() ?? 0.0;
            final addBack = totalWeight > 0 ? totalWeight : qty;
            if (itemName.isNotEmpty && addBack > 0) {
              await _addItemStock(
                itemId: null,
                itemName: itemName,
                quantity: addBack,
                rate: 0.0,
              );
            }
            final batchId = l['batchId']?.toString();
            if (batchId != null && batchId.isNotEmpty && addBack > 0) {
              await _addToBatch(batchId, addBack);
            }
          }
        }
      }
      // cash_payment and adjustment: no stock effect
    } catch (e) {
      debugPrint('deleteLedgerEntry: stock reversal error: $e');
      // Continue anyway — the user explicitly wants the row gone
    }

    // 3. Remove the entry
    await entryRef.remove();

    // 4. Recompute running balances on all remaining entries
    await _recomputeRunningBalances(mazdoorId);
  }

  /// Subtracts `weight` from the given item's `qtyOnHand` (floored at 0).
  /// Used to reverse a previous stock ADDITION (bolt/wire returns).
  Future<void> _reverseItemStockAddition(
      String itemName, double weight) async {
    final snap = await _db
        .child('items')
        .orderByChild('itemName')
        .equalTo(itemName)
        .get();
    if (!snap.exists) return;
    final itemsMap = snap.value as Map<dynamic, dynamic>;
    final itemKey = itemsMap.keys.first.toString();
    final itemData = itemsMap[itemKey] as Map<dynamic, dynamic>;
    final currentQty = (itemData['qtyOnHand'] as num?)?.toDouble() ?? 0.0;
    final newQty = (currentQty - weight).clamp(0.0, double.infinity);
    await _db.child('items').child(itemKey).update({'qtyOnHand': newQty});
  }

  /// Adds `weight` back to a batch's qty (used when reversing a wire_given
  /// entry, since giving wire had previously deducted from the batch).
  Future<void> _addToBatch(String batchId, double weight) async {
    final batchRef = _db.child('batches').child(batchId);
    final snap = await batchRef.get();
    if (!snap.exists) return;
    final data = Map<String, dynamic>.from(snap.value as Map);
    final currentQty = (data['quantity'] as num?)?.toDouble() ?? 0.0;
    final newQty = currentQty + weight;
    await batchRef.update({
      'quantity': newQty,
      'remainingQty': newQty,
      'isActive': true,
    });
  }

  /// Subtracts `weight` from a batch (used when reversing a wire_return
  /// that had previously topped up an existing batch).
  Future<void> _subtractFromBatch(String batchId, double weight) async {
    final batchRef = _db.child('batches').child(batchId);
    final snap = await batchRef.get();
    if (!snap.exists) return;
    final data = Map<String, dynamic>.from(snap.value as Map);
    final currentQty = (data['quantity'] as num?)?.toDouble() ?? 0.0;
    final newQty = (currentQty - weight).clamp(0.0, double.infinity);
    await batchRef.update({
      'quantity': newQty,
      'remainingQty': newQty,
      'isActive': newQty > 0,
    });
  }

  /// Deactivates the auto-created return batch tied to a ledger reference.
  Future<void> _deactivateReturnBatch(String ledgerReference) async {
    if (ledgerReference.isEmpty) return;
    final purchaseIdTag = 'MAZDOOR-$ledgerReference';
    final snap = await _db
        .child('batches')
        .orderByChild('purchaseId')
        .equalTo(purchaseIdTag)
        .get();
    if (!snap.exists) return;
    final data = snap.value as Map<dynamic, dynamic>;
    for (final k in data.keys) {
      await _db.child('batches').child(k.toString()).update({
        'isActive': false,
        'deletedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  /// Recomputes remainingBalance on every ledger row after deletion.
  Future<void> _recomputeRunningBalances(String mazdoorId) async {
    final ledgerRef = _db.child('mazdoorLedger').child(mazdoorId);
    final snap = await ledgerRef.get();
    if (!snap.exists) return;
    final data = snap.value as Map<dynamic, dynamic>;

    // Load all entries with parsed date, sort chronologically
    final List<MapEntry<String, Map<String, dynamic>>> sorted = [];
    double openingBal = 0.0;

    data.forEach((k, v) {
      if (v == null) return;
      final entry = Map<String, dynamic>.from(v as Map);

      DateTime dt;
      final ts = entry['createdAt']?.toString();
      dt = (ts != null ? DateTime.tryParse(ts) : null) ?? DateTime.now();

      final entryType = entry['entryType']?.toString() ?? '';
      final debit = (entry['debitFromMazdoor'] as num?)?.toDouble() ?? 0.0;
      final credit = (entry['creditToMazdoor'] as num?)?.toDouble() ?? 0.0;

      if (entryType == 'opening_balance') {
        openingBal = debit - credit;
        return;
      }

      sorted.add(MapEntry(k.toString(), {
        'date': dt,
        'debit': debit,
        'credit': credit,
      }));
    });

    sorted.sort((a, b) {
      final cmp = (a.value['date'] as DateTime)
          .compareTo(b.value['date'] as DateTime);
      if (cmp != 0) return cmp;
      // Fallback: sort by push key so identical timestamps stay stable
      return a.key.compareTo(b.key);
    });

    double running = openingBal;
    for (final e in sorted) {
      running = running +
          (e.value['debit'] as double) -
          (e.value['credit'] as double);
      await ledgerRef.child(e.key).update({'remainingBalance': running});
    }
  }

  /// Creates a batch document for a Mazdoor return. Mirrors the shape
  /// used by purchases so downstream logic (Item List, Profit & Loss,
  /// Sales batch pickers) treats these batches identically.
  Future<void> _createReturnBatch({
    required String itemName,
    required String itemKey,
    required String length,
    required String bodyType,
    required double totalWeight,
    required double ratePerKg,
    required String entryType, // 'bolt_return' | 'wire_return'
    required String ledgerReference,
  }) async {
    if (totalWeight <= 0) return;

    final db = FirebaseDatabase.instance.ref();

    // Generate a readable batch number: BATCH-MZ-<short>-<ts-tail>
    final String shortId = ledgerReference.length >= 6
        ? ledgerReference.substring(0, 6).toUpperCase()
        : ledgerReference.toUpperCase();
    final String tsTail =
    DateTime.now().millisecondsSinceEpoch.toString().substring(8);
    final String batchNumber = 'BATCH-MZ-$shortId-$tsTail';

    final Map<String, dynamic> batchData = {
      'batchNumber': batchNumber,
      'purchaseId': 'MAZDOOR-$ledgerReference',
      'itemKey': itemKey,
      'itemName': itemName,
      'length': length,
      'bodyType': bodyType,
      'quantity': totalWeight,
      'remainingQty': totalWeight,
      'costPrice': ratePerKg,
      'purchasePrice': ratePerKg,
      'vendorId': '',
      'vendorName': 'Mazdoor Return',
      'timestamp': DateTime.now().toIso8601String(),
      'isActive': true,
      'source': entryType,
    };

    await db.child('batches').push().set(batchData);
  }
}