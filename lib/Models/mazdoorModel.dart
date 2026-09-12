// mazdoorModel.dart
// Models for Mazdoor (contract labor) persons who receive raw wire and
// return either finished bolts (valued) or cash. There is no "job"
// tracking layer — every give/receive is a plain ledger entry against
// one running balance per Mazdoor.
//
// Ledger sign convention:
//   POSITIVE balance  => Mazdoor owes YOU
//   NEGATIVE balance  => YOU owe the Mazdoor
//
// balance = sum(debitFromMazdoor) - sum(creditToMazdoor)
//   debitFromMazdoor  -> wire given (or manual advance) — increases balance
//   creditToMazdoor   -> bolts returned or cash paid — decreases balance

class MazdoorPerson {
  final String id;
  final String name;
  final String phone;
  final String address;
  final String city;
  final String mazdoorSerial;
  final double openingBalance; // positive = they owed you at start
  final DateTime? openingBalanceDate;

  MazdoorPerson({
    required this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.city = '',
    this.mazdoorSerial = '',
    this.openingBalance = 0.0,
    this.openingBalanceDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      'address': address,
      'city': city,
      'mazdoorSerial': mazdoorSerial,
      'openingBalance': openingBalance,
      'openingBalanceDate': openingBalanceDate?.toIso8601String(),
      'type': 'mazdoor',
    };
  }

  static MazdoorPerson fromSnapshot(String id, Map<dynamic, dynamic> data) {
    return MazdoorPerson(
      id: id,
      name: data['name']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      address: data['address']?.toString() ?? '',
      city: data['city']?.toString() ?? '',
      mazdoorSerial: data['mazdoorSerial']?.toString() ?? '',
      openingBalance: (data['openingBalance'] as num?)?.toDouble() ?? 0.0,
      openingBalanceDate: data['openingBalanceDate'] != null
          ? DateTime.tryParse(data['openingBalanceDate'].toString())
          : null,
    );
  }
}

/// One row in a Mazdoor's ledger.
class MazdoorLedgerEntry {
  final String id;
  final String mazdoorId;

  /// Free-form reference for traceability: an auto-generated tag like
  /// "WG-00001" for a wire-given entry, or the same tag carried onto a
  /// later bolt/cash return so records read as related — purely
  /// informational, not used for any settlement math.
  final String reference;

  final String
  entryType; // 'wire_given' | 'bolt_return' | 'cash_payment' | 'opening_balance' | 'adjustment'
  final double debitFromMazdoor; // increases balance (they owe more)
  final double creditToMazdoor; // decreases balance (settles debt)
  final double remainingBalance; // running balance AFTER this entry
  final String? description;
  final String? itemName; // bolt item name (for bolt_return entries)
  final double? quantity;
  final double? rate;

  /// Wire line details recorded on a 'wire_given' entry, for record
  /// keeping only (item/length/bodyType/qty/weight given out).
  final List<MazdoorWireLine>? wireLines;

  final DateTime createdAt;

  MazdoorLedgerEntry({
    required this.id,
    required this.mazdoorId,
    required this.reference,
    required this.entryType,
    required this.debitFromMazdoor,
    required this.creditToMazdoor,
    required this.remainingBalance,
    this.description,
    this.itemName,
    this.quantity,
    this.rate,
    this.wireLines,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'reference': reference,
      'entryType': entryType,
      'debitFromMazdoor': debitFromMazdoor,
      'creditToMazdoor': creditToMazdoor,
      'remainingBalance': remainingBalance,
      'description': description,
      'itemName': itemName,
      'quantity': quantity,
      'rate': rate,
      if (wireLines != null) 'wireLines': wireLines!.map((w) => w.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static MazdoorLedgerEntry fromMap(String id, String mazdoorId, Map data) {
    double parseD(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    DateTime parseDate(dynamic v) {
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      return DateTime.now();
    }

    List<MazdoorWireLine>? lines;
    if (data['wireLines'] is List) {
      lines = (data['wireLines'] as List)
          .map((e) => MazdoorWireLine.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }

    return MazdoorLedgerEntry(
      id: id,
      mazdoorId: mazdoorId,
      // Back-compat: earlier builds stored 'jobNumber' instead of 'reference'.
      reference: (data['reference'] ?? data['jobNumber'])?.toString() ?? '',
      entryType: data['entryType']?.toString() ?? 'adjustment',
      debitFromMazdoor: parseD(data['debitFromMazdoor']),
      creditToMazdoor: parseD(data['creditToMazdoor']),
      remainingBalance: parseD(data['remainingBalance']),
      description: data['description']?.toString(),
      itemName: data['itemName']?.toString(),
      quantity: data['quantity'] != null ? parseD(data['quantity']) : null,
      rate: data['rate'] != null ? parseD(data['rate']) : null,
      wireLines: lines,
      createdAt: parseDate(data['createdAt']),
    );
  }
}

/// A single wire-item line given out (mirrors the Filled page's row
/// structure so item selection/length-body/qty works the same way).
/// Stored on a ledger entry purely for record-keeping.
class MazdoorWireLine {
  String itemName;
  String length;
  String bodyType;
  double qty;
  double? weightPerUnit;
  String weightUnit;
  double? totalWeight;
  String? batchId;
  String? batchNumber;

  MazdoorWireLine({
    required this.itemName,
    this.length = '',
    this.bodyType = '',
    this.qty = 0.0,
    this.weightPerUnit,
    this.weightUnit = 'kg',
    this.totalWeight,
    this.batchId,
    this.batchNumber,
  });

  Map<String, dynamic> toMap() {
    return {
      'itemName': itemName,
      'length': length,
      'bodyType': bodyType,
      'qty': qty,
      'weightPerUnit': weightPerUnit,
      'weightUnit': weightUnit,
      'totalWeight': totalWeight,
      'batchId': batchId,
      'batchNumber': batchNumber,
    };
  }

  static MazdoorWireLine fromMap(Map data) {
    return MazdoorWireLine(
      itemName: data['itemName']?.toString() ?? '',
      length: data['length']?.toString() ?? '',
      bodyType: data['bodyType']?.toString() ?? '',
      qty: (data['qty'] as num?)?.toDouble() ?? 0.0,
      weightPerUnit: (data['weightPerUnit'] as num?)?.toDouble(),
      weightUnit: data['weightUnit']?.toString() ?? 'kg',
      totalWeight: (data['totalWeight'] as num?)?.toDouble(),
      batchId: data['batchId']?.toString(),
      batchNumber: data['batchNumber']?.toString(),
    );
  }
}