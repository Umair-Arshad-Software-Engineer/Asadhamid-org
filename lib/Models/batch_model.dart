// models/batch_model.dart

class Batch {
  final String id;
  final String itemKey;
  final String itemName;
  final String length;       // e.g. "6 meter"
  final String bodyType;     // e.g. "Heavy"
  final String batchNumber;
  final double quantity;
  final double remainingQty;
  final double purchasePrice; // rate / cost price per kg
  final DateTime purchaseDate;
  final String vendorId;
  final String vendorName;
  final String purchaseId;
  final bool isActive;
  final double? salePrice;
  final DateTime? expiryDate;

  Batch({
    required this.id,
    required this.itemKey,
    required this.itemName,
    required this.length,
    required this.bodyType,
    required this.batchNumber,
    required this.quantity,
    required this.remainingQty,
    required this.purchasePrice,
    required this.purchaseDate,
    required this.vendorId,
    required this.vendorName,
    required this.purchaseId,
    this.isActive = true,
    this.expiryDate,
    this.salePrice,

  });

  /// Combination label shown in UI
  String get combinationLabel {
    if (length.isEmpty && bodyType.isEmpty) return itemName;
    if (length.isEmpty) return '$itemName — $bodyType';
    if (bodyType.isEmpty) return '$itemName — $length';
    return '$itemName — $length / $bodyType';
  }

  bool get isExpired => false; // no expiry in this system; keep for compatibility

  double get usedQty => quantity - remainingQty;

  factory Batch.fromMap(Map<String, dynamic> map, String id) {
    // ── Parse purchaseDate tolerantly ──────────────────────────────────────
    DateTime purchaseDate;
    final rawDate = map['timestamp'] ?? map['purchaseDate'] ?? '';
    try {
      purchaseDate = DateTime.parse(rawDate.toString());
    } catch (_) {
      purchaseDate = DateTime.now();
    }

    return Batch(
      id: id,
      itemKey:       map['itemKey']?.toString()       ?? '',
      itemName:      map['itemName']?.toString()      ?? '',
      length:        map['length']?.toString()        ?? '',
      bodyType:      map['bodyType']?.toString()      ?? '',
      batchNumber:   map['batchNumber']?.toString()   ?? id,
      quantity:      (map['quantity']      as num?)?.toDouble() ?? 0.0,
      remainingQty:  (map['remainingQty']  as num?)?.toDouble() ??
          (map['quantity']      as num?)?.toDouble() ?? 0.0,
      purchasePrice: (map['costPrice']     as num?)?.toDouble() ??
          (map['purchasePrice'] as num?)?.toDouble() ?? 0.0,
      purchaseDate:  purchaseDate,
      vendorId:      map['vendorId']?.toString()      ?? '',
      vendorName:    map['vendorName']?.toString()    ?? '',
      purchaseId:    map['purchaseId']?.toString()    ?? '',
      isActive:      map['isActive'] as bool?         ?? true,
      salePrice: (map['salePrice'] as num?)?.toDouble(),
      expiryDate: map['expiryDate'] != null ? DateTime.parse(map['expiryDate']) : null,

    );
  }

  Map<String, dynamic> toMap() {
    return {
      'itemKey':       itemKey,
      'itemName':      itemName,
      'length':        length,
      'bodyType':      bodyType,
      'batchNumber':   batchNumber,
      'quantity':      quantity,
      'remainingQty':  remainingQty,
      'costPrice':     purchasePrice,
      'timestamp':     purchaseDate.toIso8601String(),
      'vendorId':      vendorId,
      'vendorName':    vendorName,
      'purchaseId':    purchaseId,
      'isActive':      isActive,
      'salePrice': salePrice,
      'purchaseDate': purchaseDate.toIso8601String(),
      'expiryDate': expiryDate?.toIso8601String(),
    };
  }

  Batch copyWith({double? remainingQty, bool? isActive}) {
    return Batch(
      id:            id,
      itemKey:       itemKey,
      itemName:      itemName,
      length:        length,
      bodyType:      bodyType,
      batchNumber:   batchNumber,
      quantity:      quantity,
      remainingQty:  remainingQty ?? this.remainingQty,
      purchasePrice: purchasePrice,
      purchaseDate:  purchaseDate,
      salePrice: salePrice,
      expiryDate: expiryDate,

      vendorId:      vendorId,
      vendorName:    vendorName,
      purchaseId:    purchaseId,
      isActive:      isActive ?? this.isActive,
    );
  }
}