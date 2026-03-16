class ItemStock {
  String itemId;
  String combinationId;
  String length;
  String lengthDecimal;
  String bodyType;
  double costPricePerKg;
  double salePricePerKg;
  double quantityInKg;
  DateTime? lastUpdated;
  String? location;
  double minStockLevel;
  double maxStockLevel;

  ItemStock({
    required this.itemId,
    required this.combinationId,
    required this.length,
    required this.lengthDecimal,
    required this.bodyType,
    required this.costPricePerKg,
    required this.salePricePerKg,
    required this.quantityInKg,
    this.lastUpdated,
    this.location,
    this.minStockLevel = 0,
    this.maxStockLevel = 1000,
  });

  Map<String, dynamic> toMap() {
    return {
      'itemId': itemId,
      'combinationId': combinationId,
      'length': length,
      'lengthDecimal': lengthDecimal,
      'bodyType': bodyType,
      'costPricePerKg': costPricePerKg,
      'salePricePerKg': salePricePerKg,
      'quantityInKg': quantityInKg,
      'lastUpdated': lastUpdated?.toIso8601String(),
      'location': location,
      'minStockLevel': minStockLevel,
      'maxStockLevel': maxStockLevel,
    };
  }

  factory ItemStock.fromMap(Map<String, dynamic> map) {
    return ItemStock(
      itemId: map['itemId'] ?? '',
      combinationId: map['combinationId'] ?? '',
      length: map['length'] ?? '',
      lengthDecimal: map['lengthDecimal'] ?? '',
      bodyType: map['bodyType'] ?? '',
      costPricePerKg: map['costPricePerKg'] != null
          ? double.tryParse(map['costPricePerKg'].toString()) ?? 0
          : 0,
      salePricePerKg: map['salePricePerKg'] != null
          ? double.tryParse(map['salePricePerKg'].toString()) ?? 0
          : 0,
      quantityInKg: map['quantityInKg'] != null
          ? double.tryParse(map['quantityInKg'].toString()) ?? 0
          : 0,
      lastUpdated: map['lastUpdated'] != null
          ? DateTime.tryParse(map['lastUpdated'])
          : null,
      location: map['location'],
      minStockLevel: map['minStockLevel'] != null
          ? double.tryParse(map['minStockLevel'].toString()) ?? 0
          : 0,
      maxStockLevel: map['maxStockLevel'] != null
          ? double.tryParse(map['maxStockLevel'].toString()) ?? 1000
          : 1000,
    );
  }
}