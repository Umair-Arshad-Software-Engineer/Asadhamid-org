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
  })
  async {
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
  })
  async {
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
    List<Map<String, dynamic>>? wireLines,
    DateTime? date,
  })
  async {
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
  })
  async {
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
          final currentQty = (batchData['quantity'] as num?)?.toDouble() ?? 0.0;
          final updatedQty = (currentQty - weightToDeduct).clamp(0.0, double.infinity);
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
        final currentQty = (itemData['qtyOnHand'] as num?)?.toDouble() ?? 0.0;
        final updatedQty = (currentQty - weightToDeduct).clamp(0.0, double.infinity);
        await _db.child('items').child(itemKey.toString()).update({
          'qtyOnHand': updatedQty,
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // RECEIVE BOLTS: Mazdoor returns finished bolts. Credits the Mazdoor
  // by (qty * rate), reducing their running balance (can go negative,
  // meaning you now owe them). Auto-tags the entry with the most recent
  // wire-given reference for traceability — no picker needed. Adds
  // bolt stock into `items`.
  // ─────────────────────────────────────────────────────────────
  Future<void> receiveBolts({
    required String mazdoorId,
    required String mazdoorName,
    required String boltItemName,
    required double quantity,
    required double rate,
    String? boltItemId,
    String? description,
    DateTime? date,
  })
  async {
    if (quantity <= 0 || rate <= 0) {
      throw Exception('Quantity and rate must be greater than zero.');
    }
    final boltValue = quantity * rate;
    final linkedRef = await _mostRecentWireReference(mazdoorId);

    await _appendLedgerEntry(
      mazdoorId: mazdoorId,
      reference: linkedRef ?? 'RETURN-${DateTime.now().millisecondsSinceEpoch}',
      entryType: 'bolt_return',
      credit: boltValue,
      description: description ?? 'Bolts returned',
      itemName: boltItemName,
      quantity: quantity,
      rate: rate,
      date: date,
    );

    // Add bolt stock into items (create or increment qtyOnHand).
    await _addBoltStock(
      itemId: boltItemId,
      itemName: boltItemName,
      quantity: quantity,
      rate: rate,
    );
  }

  Future<void> _addBoltStock({
    String? itemId,
    required String itemName,
    required double quantity,
    required double rate,
  })
  async {
    DatabaseReference itemRef;

    if (itemId != null && itemId.isNotEmpty) {
      itemRef = _db.child('items').child(itemId);
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
      } else {
        itemRef = _db.child('items').push();
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
  })
  async {
    if (amount <= 0) {
      throw Exception('Amount must be greater than zero.');
    }
    final linkedRef = await _mostRecentWireReference(mazdoorId);

    await _appendLedgerEntry(
      mazdoorId: mazdoorId,
      reference: linkedRef ?? 'RETURN-${DateTime.now().millisecondsSinceEpoch}',
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
  })
  async {
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
}