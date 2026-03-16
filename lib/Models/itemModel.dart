// itemModel.dart - With per-combination stock management and customer-specific prices

import 'package:firebase_database/firebase_database.dart';

class Item {
  final String id;
  final String itemName;
  final double avgCostPricePerKg;
  final double avgSalePricePerKg;
  final String? unit;
  final String? vendor;
  final String? category;
  final Map<String, double>? customerBasePrices;
  final String? imageBase64;
  final String? customerSerial;
  final List<LengthBodyCombination>? lengthBodyCombinations;
  final bool isBOM;
  final List<Map<String, dynamic>>? components;
  final DateTime? createdAt;

  @Deprecated('Use totalCombinationStock for per-combination stock management')
  final double qtyOnHand;

  Item({
    required this.id,
    required this.itemName,
    required this.avgCostPricePerKg,
    required this.avgSalePricePerKg,
    this.unit,
    this.vendor,
    this.category,
    this.customerBasePrices,
    this.imageBase64,
    this.customerSerial,
    this.lengthBodyCombinations,
    this.isBOM = false,
    this.components,
    this.createdAt,
    double? qtyOnHand,
  }) : qtyOnHand = qtyOnHand ?? 0.0;

  factory Item.fromMap(Map<dynamic, dynamic> data, String id) {
    Map<String, double>? customerPrices;
    if (data['customerBasePrices'] != null) {
      customerPrices = {};
      (data['customerBasePrices'] as Map<dynamic, dynamic>).forEach((key, value) {
        customerPrices![key.toString()] = value.toDouble();
      });
    }

    List<LengthBodyCombination>? lengthCombinations;
    if (data['lengthBodyCombinations'] != null && data['lengthBodyCombinations'] is List) {
      lengthCombinations = (data['lengthBodyCombinations'] as List).map((item) {
        if (item is Map) {
          return LengthBodyCombination.fromMap(Map<String, dynamic>.from(item));
        }
        return LengthBodyCombination(
          length: '',
          lengthDecimal: '',
          bodyType: '',
        );
      }).toList();
    }

    List<Map<String, dynamic>>? bomComponents;
    if (data['components'] != null && data['components'] is List) {
      bomComponents = (data['components'] as List).map((component) {
        if (component is Map) {
          return Map<String, dynamic>.from(component);
        }
        return <String, dynamic>{};
      }).toList();
    }

    DateTime? createdAt;
    if (data['createdAt'] != null) {
      if (data['createdAt'] is int) {
        createdAt = DateTime.fromMillisecondsSinceEpoch(data['createdAt']);
      } else if (data['createdAt'] is String) {
        createdAt = DateTime.tryParse(data['createdAt']);
      }
    }

    return Item(
      id: id,
      itemName: data['itemName'] ?? '',
      avgCostPricePerKg: data['avgCostPricePerKg']?.toDouble() ??
          data['costPrice1kg']?.toDouble() ??
          data['costPrice']?.toDouble() ?? 0.0,
      avgSalePricePerKg: data['avgSalePricePerKg']?.toDouble() ??
          data['salePrice1kg']?.toDouble() ??
          data['salePrice']?.toDouble() ?? 0.0,
      unit: data['unit'] ?? 'Kg',
      vendor: data['vendor'],
      category: data['category'],
      customerBasePrices: customerPrices,
      imageBase64: data['image']?.toString(),
      customerSerial: data['customerSerial'],
      lengthBodyCombinations: lengthCombinations,
      isBOM: data['isBOM'] == true,
      components: bomComponents,
      createdAt: createdAt,
      qtyOnHand: data['qtyOnHand']?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'itemName': itemName,
      'avgCostPricePerKg': avgCostPricePerKg,
      'avgSalePricePerKg': avgSalePricePerKg,
      'costPrice1kg': avgCostPricePerKg,
      'salePrice1kg': avgSalePricePerKg,
      'costPrice50kg': avgCostPricePerKg * 50,
      'salePrice50kg': avgSalePricePerKg * 50,
      'unit': unit ?? 'Kg',
      'costPrice': isBOM ? _calculateBOMCost() : avgCostPricePerKg,
      'salePrice': avgSalePricePerKg,
      'qtyOnHand': qtyOnHand,
      'vendor': vendor,
      'category': category,
      'customerBasePrices': customerBasePrices,
      'image': imageBase64,
      'customerSerial': customerSerial,
      'lengthBodyCombinations': lengthBodyCombinations?.map((c) => c.toMap()).toList(),
      'isBOM': isBOM,
      'components': isBOM ? components : null,
      'createdAt': createdAt?.millisecondsSinceEpoch ?? ServerValue.timestamp,
      'hasMultipleLengthPrices': lengthBodyCombinations != null && lengthBodyCombinations!.isNotEmpty,
    };
  }

  double _calculateBOMCost() {
    if (!isBOM || components == null || components!.isEmpty) {
      return avgCostPricePerKg;
    }
    return components!.fold(0.0, (sum, component) {
      final quantity = component['quantity']?.toDouble() ?? 0.0;
      final price = component['price']?.toDouble() ?? 0.0;
      return sum + (quantity * price);
    });
  }

  Item copyWith({
    String? id,
    String? itemName,
    double? avgCostPricePerKg,
    double? avgSalePricePerKg,
    String? unit,
    String? vendor,
    String? category,
    Map<String, double>? customerBasePrices,
    String? imageBase64,
    String? customerSerial,
    List<LengthBodyCombination>? lengthBodyCombinations,
    bool? isBOM,
    List<Map<String, dynamic>>? components,
    DateTime? createdAt,
    double? qtyOnHand,
  }) {
    return Item(
      id: id ?? this.id,
      itemName: itemName ?? this.itemName,
      avgCostPricePerKg: avgCostPricePerKg ?? this.avgCostPricePerKg,
      avgSalePricePerKg: avgSalePricePerKg ?? this.avgSalePricePerKg,
      unit: unit ?? this.unit,
      vendor: vendor ?? this.vendor,
      category: category ?? this.category,
      customerBasePrices: customerBasePrices ?? this.customerBasePrices,
      imageBase64: imageBase64 ?? this.imageBase64,
      customerSerial: customerSerial ?? this.customerSerial,
      lengthBodyCombinations: lengthBodyCombinations ?? this.lengthBodyCombinations,
      isBOM: isBOM ?? this.isBOM,
      components: components ?? this.components,
      createdAt: createdAt ?? this.createdAt,
      qtyOnHand: qtyOnHand ?? this.qtyOnHand,
    );
  }

  double get totalCombinationStock {
    if (lengthBodyCombinations == null || lengthBodyCombinations!.isEmpty) {
      return qtyOnHand;
    }
    return lengthBodyCombinations!.fold(0.0, (sum, combo) => sum + combo.stockQuantity);
  }

  double get totalInventoryValue {
    if (lengthBodyCombinations == null || lengthBodyCombinations!.isEmpty) {
      return qtyOnHand * avgCostPricePerKg;
    }
    return lengthBodyCombinations!.fold(0.0, (sum, combo) {
      if (combo.costPricePerKg != null) {
        return sum + (combo.stockQuantity * combo.costPricePerKg!);
      }
      return sum + (combo.stockQuantity * avgCostPricePerKg);
    });
  }

  StockStatus get overallStockStatus {
    if (totalCombinationStock <= 0) return StockStatus.outOfStock;
    if (lengthBodyCombinations != null) {
      for (var combo in lengthBodyCombinations!) {
        if (combo.isLowStock) return StockStatus.lowStock;
      }
    }
    return StockStatus.inStock;
  }

  double getPriceForCustomer(String? customerId) {
    if (customerId == null || customerBasePrices == null) {
      return avgSalePricePerKg;
    }
    return customerBasePrices![customerId] ?? avgSalePricePerKg;
  }

  List<String> getLengthBodyOptions() {
    if (lengthBodyCombinations == null || lengthBodyCombinations!.isEmpty) {
      return ['Standard'];
    }
    return lengthBodyCombinations!.map((combo) => '${combo.length} - ${combo.bodyType}').toList();
  }

  LengthBodyCombination? getCombinationByIndex(int index) {
    if (lengthBodyCombinations == null || index < 0 || index >= lengthBodyCombinations!.length) {
      return null;
    }
    return lengthBodyCombinations![index];
  }

  LengthBodyCombination? getCombinationByString(String comboStr) {
    if (lengthBodyCombinations == null) return null;
    for (var combo in lengthBodyCombinations!) {
      if ('${combo.length} - ${combo.bodyType}' == comboStr) return combo;
    }
    return null;
  }

  LengthBodyCombination? findCombination(String length, String bodyType) {
    if (lengthBodyCombinations == null) return null;
    return lengthBodyCombinations!.firstWhere(
          (combo) => combo.length == length && combo.bodyType == bodyType,
      orElse: () => LengthBodyCombination(length: '', lengthDecimal: '', bodyType: ''),
    );
  }

  double getStockForCombination(String length, String bodyType) {
    final combo = findCombination(length, bodyType);
    return combo?.stockQuantity ?? 0.0;
  }

  bool hasEnoughStock(String length, String bodyType, double requiredQuantity) {
    final combo = findCombination(length, bodyType);
    return combo != null && combo.stockQuantity >= requiredQuantity;
  }

  void updateCombinationStock({
    required String length,
    required String bodyType,
    required double quantity,
    bool isAddition = true,
  }) {
    final combo = findCombination(length, bodyType);
    if (combo != null) {
      combo.updateStock(quantity, isAddition: isAddition);
    }
  }

  List<LengthBodyCombination> get outOfStockCombinations {
    if (lengthBodyCombinations == null) return [];
    return lengthBodyCombinations!.where((combo) => combo.isOutOfStock).toList();
  }

  List<LengthBodyCombination> get lowStockCombinations {
    if (lengthBodyCombinations == null) return [];
    return lengthBodyCombinations!.where((combo) => combo.isLowStock).toList();
  }

  List<LengthBodyCombination> get inStockCombinations {
    if (lengthBodyCombinations == null) return [];
    return lengthBodyCombinations!.where((combo) => combo.isInStock).toList();
  }

  Map<String, dynamic>? getBOMCostBreakdown() {
    if (!isBOM || components == null) return null;
    double totalCost = 0.0;
    double additions = 0.0;
    double deductions = 0.0;
    for (var component in components!) {
      final quantity = component['quantity']?.toDouble() ?? 0.0;
      final price = component['price']?.toDouble() ?? 0.0;
      final cost = quantity * price;
      totalCost += cost;
      if (quantity > 0) {
        additions += cost;
      } else {
        deductions += cost.abs();
      }
    }
    return {
      'totalCost': totalCost,
      'additions': additions,
      'deductions': deductions,
      'components': components!.length,
    };
  }

  @Deprecated('Use overallStockStatus or totalCombinationStock instead')
  bool get isInStock => totalCombinationStock > 0;

  @Deprecated('Use overallStockStatus instead')
  bool get isLowStock => overallStockStatus == StockStatus.lowStock;
}

enum StockStatus { outOfStock, lowStock, inStock }

class LengthBodyCombination {
  String length;
  String lengthDecimal;
  String bodyType;
  double? costPricePerKg;
  double? salePricePerKg;
  String? id;
  double? weightPerUnit;
  String? weightUnit;
  double stockQuantity;
  double lowStockThreshold;
  String stockUnit;
  String? combinationCode;

  // ─── NEW: per-combination customer-specific sale prices ───
  Map<String, double> customerPrices;

  LengthBodyCombination({
    required this.length,
    required this.lengthDecimal,
    required this.bodyType,
    this.costPricePerKg,
    this.salePricePerKg,
    this.id,
    this.weightPerUnit,
    this.weightUnit = "kg",
    this.stockQuantity = 0.0,
    this.lowStockThreshold = 10.0,
    this.stockUnit = "kg",
    this.combinationCode,
    Map<String, double>? customerPrices,
  }) : customerPrices = customerPrices ?? {} {
    combinationCode ??=
    '${length.replaceAll(RegExp(r'\s+'), '')}_${bodyType.replaceAll(RegExp(r'\s+'), '')}';
  }

  Map<String, dynamic> toMap() {
    return {
      'length': length,
      'lengthDecimal': lengthDecimal,
      'bodyType': bodyType,
      'costPricePerKg': costPricePerKg,
      'salePricePerKg': salePricePerKg,
      'weightPerUnit': weightPerUnit,
      'weightUnit': weightUnit,
      'stockQuantity': stockQuantity,
      'lowStockThreshold': lowStockThreshold,
      'stockUnit': stockUnit,
      'combinationCode': combinationCode,
      'customerPrices': customerPrices, // ← NEW
      if (id != null) 'id': id,
    };
  }

  factory LengthBodyCombination.fromMap(Map<String, dynamic> map) {
    // ─── Parse customerPrices ───
    Map<String, double> parsedCustomerPrices = {};
    if (map['customerPrices'] != null && map['customerPrices'] is Map) {
      (map['customerPrices'] as Map).forEach((key, value) {
        parsedCustomerPrices[key.toString()] = (value as num).toDouble();
      });
    }

    return LengthBodyCombination(
      length: map['length']?.toString() ?? '',
      lengthDecimal: map['lengthDecimal']?.toString() ?? '',
      bodyType: map['bodyType']?.toString() ?? '',
      costPricePerKg: map['costPricePerKg'] != null
          ? double.tryParse(map['costPricePerKg'].toString())
          : null,
      salePricePerKg: map['salePricePerKg'] != null
          ? double.tryParse(map['salePricePerKg'].toString())
          : null,
      weightPerUnit: map['weightPerUnit'] != null
          ? double.tryParse(map['weightPerUnit'].toString())
          : null,
      weightUnit: map['weightUnit']?.toString() ?? 'kg',
      stockQuantity: map['stockQuantity'] != null
          ? double.tryParse(map['stockQuantity'].toString()) ?? 0.0
          : 0.0,
      lowStockThreshold: map['lowStockThreshold'] != null
          ? double.tryParse(map['lowStockThreshold'].toString()) ?? 10.0
          : 10.0,
      stockUnit: map['stockUnit']?.toString() ?? 'kg',
      combinationCode: map['combinationCode']?.toString(),
      id: map['id']?.toString(),
      customerPrices: parsedCustomerPrices, // ← NEW
    );
  }

  bool get isOutOfStock => stockQuantity <= 0;
  bool get isLowStock => stockQuantity > 0 && stockQuantity < lowStockThreshold;
  bool get isInStock => stockQuantity > 0;

  StockStatus get stockStatus {
    if (isOutOfStock) return StockStatus.outOfStock;
    if (isLowStock) return StockStatus.lowStock;
    return StockStatus.inStock;
  }

  StockUpdateResult updateStock(double quantity, {bool isAddition = true}) {
    double oldStock = stockQuantity;
    if (isAddition) {
      stockQuantity += quantity;
    } else {
      if (quantity > stockQuantity) {
        return StockUpdateResult(
          success: false,
          oldStock: oldStock,
          newStock: stockQuantity,
          message:
          'Insufficient stock. Available: ${stockQuantity}${stockUnit}, Requested: ${quantity}${stockUnit}',
        );
      }
      stockQuantity -= quantity;
    }
    if (stockQuantity < 0) stockQuantity = 0;
    return StockUpdateResult(
      success: true,
      oldStock: oldStock,
      newStock: stockQuantity,
      message: 'Stock updated successfully. New stock: ${stockQuantity}${stockUnit}',
    );
  }

  double? get profitMargin {
    if (costPricePerKg == null || salePricePerKg == null) return null;
    return salePricePerKg! - costPricePerKg!;
  }

  double? get profitPercentage {
    if (costPricePerKg == null || salePricePerKg == null || costPricePerKg == 0) return null;
    return ((salePricePerKg! - costPricePerKg!) / costPricePerKg!) * 100;
  }

  double get stockValue {
    if (costPricePerKg == null) return 0.0;
    return stockQuantity * costPricePerKg!;
  }

  /// Returns customer-specific sale price for this combination.
  /// Falls back to the combination's salePricePerKg if no custom price is set.
  double getPriceForCustomer(String? customerId) {
    if (customerId == null || customerPrices.isEmpty) {
      return salePricePerKg ?? 0.0;
    }
    return customerPrices[customerId] ?? salePricePerKg ?? 0.0;
  }

  LengthBodyCombination copyWith({
    String? length,
    String? lengthDecimal,
    String? bodyType,
    double? costPricePerKg,
    double? salePricePerKg,
    String? id,
    double? weightPerUnit,
    String? weightUnit,
    double? stockQuantity,
    double? lowStockThreshold,
    String? stockUnit,
    String? combinationCode,
    Map<String, double>? customerPrices, // ← NEW
  }) {
    return LengthBodyCombination(
      length: length ?? this.length,
      lengthDecimal: lengthDecimal ?? this.lengthDecimal,
      bodyType: bodyType ?? this.bodyType,
      costPricePerKg: costPricePerKg ?? this.costPricePerKg,
      salePricePerKg: salePricePerKg ?? this.salePricePerKg,
      id: id ?? this.id,
      weightPerUnit: weightPerUnit ?? this.weightPerUnit,
      weightUnit: weightUnit ?? this.weightUnit,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      stockUnit: stockUnit ?? this.stockUnit,
      combinationCode: combinationCode ?? this.combinationCode,
      customerPrices: customerPrices ?? Map.from(this.customerPrices), // ← NEW
    );
  }

  @override
  String toString() {
    return '$length $bodyType (Stock: ${stockQuantity.toStringAsFixed(2)}$stockUnit)';
  }

  String get displayName => '$length - $bodyType';

  String get fullDescription {
    String desc = 'Length: $length ($lengthDecimal), Body Type: $bodyType';
    if (costPricePerKg != null) desc += '\nCost: ${costPricePerKg!.toStringAsFixed(2)} PKR/kg';
    if (salePricePerKg != null) desc += '\nSale: ${salePricePerKg!.toStringAsFixed(2)} PKR/kg';
    if (profitMargin != null && profitPercentage != null) {
      desc +=
      '\nProfit: ${profitMargin!.toStringAsFixed(2)} PKR (${profitPercentage!.toStringAsFixed(1)}%)';
    }
    desc += '\nStock: ${stockQuantity.toStringAsFixed(2)}$stockUnit';
    if (isLowStock) {
      desc += ' ⚠️ Low Stock';
    } else if (isOutOfStock) {
      desc += ' ❌ Out of Stock';
    } else {
      desc += ' ✓ In Stock';
    }
    if (customerPrices.isNotEmpty) {
      desc += '\nCustom customer prices: ${customerPrices.length}';
    }
    return desc;
  }

  double? calculateTotalWeight(double quantity) {
    if (weightPerUnit == null) return null;
    return weightPerUnit! * quantity;
  }
}

class StockUpdateResult {
  final bool success;
  final double oldStock;
  final double newStock;
  final String message;

  StockUpdateResult({
    required this.success,
    required this.oldStock,
    required this.newStock,
    required this.message,
  });
}

class StockTransaction {
  final String id;
  final String itemId;
  final String itemName;
  final String? combinationId;
  final String? combinationCode;
  final String? length;
  final String? bodyType;
  final double quantity;
  final String transactionType;
  final String? referenceId;
  final DateTime timestamp;
  final String? notes;
  final String performedBy;
  final double oldStock;
  final double newStock;

  StockTransaction({
    required this.id,
    required this.itemId,
    required this.itemName,
    this.combinationId,
    this.combinationCode,
    this.length,
    this.bodyType,
    required this.quantity,
    required this.transactionType,
    this.referenceId,
    required this.timestamp,
    this.notes,
    required this.performedBy,
    required this.oldStock,
    required this.newStock,
  });

  factory StockTransaction.fromMap(Map<dynamic, dynamic> data, String id) {
    return StockTransaction(
      id: id,
      itemId: data['itemId']?.toString() ?? '',
      itemName: data['itemName']?.toString() ?? '',
      combinationId: data['combinationId']?.toString(),
      combinationCode: data['combinationCode']?.toString(),
      length: data['length']?.toString(),
      bodyType: data['bodyType']?.toString(),
      quantity: data['quantity']?.toDouble() ?? 0.0,
      transactionType: data['transactionType']?.toString() ?? '',
      referenceId: data['referenceId']?.toString(),
      timestamp: data['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['timestamp'])
          : DateTime.now(),
      notes: data['notes']?.toString(),
      performedBy: data['performedBy']?.toString() ?? 'System',
      oldStock: data['oldStock']?.toDouble() ?? 0.0,
      newStock: data['newStock']?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'itemId': itemId,
      'itemName': itemName,
      'combinationId': combinationId,
      'combinationCode': combinationCode,
      'length': length,
      'bodyType': bodyType,
      'quantity': quantity,
      'transactionType': transactionType,
      'referenceId': referenceId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'notes': notes,
      'performedBy': performedBy,
      'oldStock': oldStock,
      'newStock': newStock,
    };
  }
}