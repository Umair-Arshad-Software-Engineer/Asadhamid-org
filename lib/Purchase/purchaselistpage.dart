import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../Provider/lanprovider.dart';
import 'BuildBOM.dart';
import 'itemPurchasePage.dart';

class PurchaseListPage extends StatefulWidget {
  @override
  State<PurchaseListPage> createState() => _PurchaseListPageState();
}

class _PurchaseListPageState extends State<PurchaseListPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _filteredPurchases = [];
  List<Map<String, dynamic>> _items = []; // Add this to store inventory items
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchItems(); // Fetch items first
    fetchPurchases();
  }

  // Add this method to fetch inventory items
  Future<void> fetchItems() async {
    final database = FirebaseDatabase.instance.ref();
    try {
      final snapshot = await database.child('items').get();
      if (snapshot.exists) {
        dynamic itemData = snapshot.value;
        Map<dynamic, dynamic> itemsMap = {};

        if (itemData is Map) {
          itemsMap = itemData;
        } else if (itemData is List) {
          itemsMap = {for (var i = 0; i < itemData.length; i++) i.toString(): itemData[i]};
        }

        setState(() {
          _items = itemsMap.entries.map((entry) {
            return {
              'key': entry.key,
              'itemName': entry.value['itemName']?.toString() ?? '',
              'qtyOnHand': (entry.value['qtyOnHand'] as num?)?.toDouble() ?? 0.0,
              'costPrice': (entry.value['costPrice'] as num?)?.toDouble() ?? 0.0,
              'isBOM': entry.value['isBOM'] == true,
              'components': entry.value['components'],
              'unit': entry.value['unit']?.toString() ?? 'kg',
            };
          }).toList();
        });
      }
    } catch (e) {
      print('Error fetching items: $e');
    }
  }

  void deletePurchase(String key, Map<String, dynamic> purchase) async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(languageProvider.isEnglish ? 'Confirm Delete' : 'حذف کی تصدیق کریں'),
          content: Text(languageProvider.isEnglish
              ? 'Are you sure you want to delete this purchase? This will also deduct item quantities from inventory.'
              : 'کیا آپ واقعی اس خریداری کو حذف کرنا چاہتے ہیں؟ اس سے انوینٹری سے اشیاء کی مقدار بھی کم ہو جائے گی۔'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ کریں'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text(languageProvider.isEnglish ? 'Delete' : 'حذف کریں'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        // Reverse inventory for all items in the purchase
        await _reverseInventoryForPurchase(purchase);

        // Delete the purchase from Firebase
        await FirebaseDatabase.instance.ref('purchases/$key').remove();

        // Also delete any component consumption records if they exist
        try {
          await FirebaseDatabase.instance.ref('componentConsumption/$key').remove();
        } catch (e) {
          // Ignore if component consumption record doesn't exist
          print('No component consumption record to delete: $e');
        }

        // Close loading dialog
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(languageProvider.isEnglish
                  ? 'Purchase deleted successfully and inventory updated'
                  : 'خریداری کامیابی سے حذف ہو گئی اور انوینٹری اپ ڈیٹ ہو گئی'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (error) {
        // Close loading dialog
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(languageProvider.isEnglish
                  ? 'Failed to delete purchase: $error'
                  : 'خریداری کو حذف کرنے میں ناکامی: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // NEW: Main method to reverse inventory when deleting a purchase
  Future<void> _reverseInventoryForPurchase(Map<String, dynamic> purchase) async {
    final database = FirebaseDatabase.instance.ref();
    final items = purchase['items'] as List<Map<String, dynamic>>? ?? [];

    for (final purchaseItem in items) {
      final itemName = purchaseItem['itemName']?.toString() ?? '';

      // Get the total weight that was added during purchase
      // This matches how you add inventory in _updateInventoryQuantities
      double totalWeightToDeduct = 0.0;

      // Check if totalWeight is directly available
      if (purchaseItem['totalWeight'] != null) {
        totalWeightToDeduct = (purchaseItem['totalWeight'] as num).toDouble();
      } else {
        // Calculate from quantity × weight per unit (same as purchase logic)
        final quantity = (purchaseItem['quantity'] as num?)?.toDouble() ?? 0.0;
        final weightPerUnit = (purchaseItem['weight'] as num?)?.toDouble() ??
            (purchaseItem['weightPerUnit'] as num?)?.toDouble() ?? 0.0;
        totalWeightToDeduct = quantity * weightPerUnit;
      }

      if (itemName.isNotEmpty && totalWeightToDeduct > 0) {
        // Find the item in inventory by name
        final existingItem = _items.firstWhere(
              (invItem) => invItem['itemName'].toLowerCase() == itemName.toLowerCase(),
          orElse: () => {},
        );

        if (existingItem.isNotEmpty) {
          final itemKey = existingItem['key'];
          final currentQty = existingItem['qtyOnHand']?.toDouble() ?? 0.0;

          // Deduct the total weight from inventory
          final newQty = currentQty - totalWeightToDeduct;

          // Ensure quantity doesn't go below zero
          final updatedQty = newQty < 0 ? 0.0 : newQty;

          await database.child('items').child(itemKey).update({
            'qtyOnHand': updatedQty,
          });

          // Update local cache
          existingItem['qtyOnHand'] = updatedQty;

          print('Reversed inventory for $itemName: $currentQty -> $updatedQty (deducted $totalWeightToDeduct)');

          // Handle BOM components reversal if this was a BOM item
          if (purchaseItem['isBOM'] == true || existingItem['isBOM'] == true) {
            await _reverseBomComponents(existingItem, purchaseItem, database);
          }
        } else {
          print('Warning: Item "$itemName" not found in inventory for reversal');
        }
      }
    }

    // Refresh items list after updates
    await fetchItems();
  }

  // NEW: Reverse BOM component deductions
  Future<void> _reverseBomComponents(
      Map<String, dynamic> bomItem,
      Map<String, dynamic> purchaseItem,
      DatabaseReference database,
      ) async {
    final quantity = (purchaseItem['quantity'] as num?)?.toDouble() ?? 0.0;

    dynamic componentsData = bomItem['components'];
    Map<String, dynamic> components = {};

    if (componentsData is Map) {
      components = componentsData.cast<String, dynamic>();
    } else if (componentsData is List) {
      for (int i = 0; i < componentsData.length; i += 2) {
        if (i + 1 < componentsData.length) {
          components[componentsData[i].toString()] = componentsData[i + 1];
        }
      }
    }

    // Restore components that were deducted during purchase
    for (var componentEntry in components.entries) {
      String componentName = componentEntry.key;
      double qtyPerUnit = 0.0;

      if (componentEntry.value is num) {
        qtyPerUnit = (componentEntry.value as num).toDouble();
      } else if (componentEntry.value is String) {
        qtyPerUnit = double.tryParse(componentEntry.value as String) ?? 0.0;
      }

      double totalQtyToRestore = qtyPerUnit * quantity;

      // Find the component in inventory
      var componentItem = _items.firstWhere(
            (item) => item['itemName'].toLowerCase() == componentName.toLowerCase(),
        orElse: () => {},
      );

      if (componentItem.isNotEmpty) {
        String componentKey = componentItem['key'];
        double currentQty = componentItem['qtyOnHand']?.toDouble() ?? 0.0;

        // Add back the component quantity
        await database.child('items').child(componentKey).update({
          'qtyOnHand': currentQty + totalQtyToRestore,
        });

        print('Restored BOM component $componentName: $currentQty -> ${currentQty + totalQtyToRestore}');
      }
    }
  }

  // In PurchaseListPage, modify the editPurchase method:
  void editPurchase(Map<String, dynamic> purchase) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ItemPurchasePage(
          initialVendorId: purchase['vendorId'],
          initialVendorName: purchase['vendorName'],
          initialItems: List<Map<String, dynamic>>.from(purchase['items']),
          isEditMode: true,
          purchaseKey: purchase['key'],
        ),
      ),
    ).then((_) {
      // Refresh items after returning from edit
      fetchItems();
    });
  }

  void fetchPurchases() {
    setState(() => _isLoading = true);
    FirebaseDatabase.instance.ref('purchases').onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        List<Map<String, dynamic>> purchases = [];

        data.forEach((key, value) {
          final purchase = Map<String, dynamic>.from(value as Map<dynamic, dynamic>);
          purchase['key'] = key;

          // Handle items if they exist (assuming items is a List)
          if (purchase['items'] != null) {
            final items = List<Map<String, dynamic>>.from(
                (purchase['items'] as List<dynamic>).map(
                        (item) => Map<String, dynamic>.from(item as Map<dynamic, dynamic>)
                )
            );
            purchase['items'] = items;
          }

          purchases.add(purchase);
        });

        // Sort by timestamp (newest first)
        purchases.sort((a, b) {
          final timestampA = a['timestamp']?.toString() ?? '';
          final timestampB = b['timestamp']?.toString() ?? '';
          return timestampB.compareTo(timestampA);
        });

        setState(() {
          _purchases = purchases;
          _filteredPurchases = purchases;
          _isLoading = false;
        });
      } else {
        setState(() {
          _purchases = [];
          _filteredPurchases = [];
          _isLoading = false;
        });
      }
    }, onError: (error) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching purchases: $error')),
      );
    });
  }

  void searchPurchases(String query) {
    setState(() {
      _filteredPurchases = _purchases.where((purchase) {
        final vendorName = purchase['vendorName']?.toString().toLowerCase() ?? '';
        final refNo = purchase['refNo']?.toString().toLowerCase() ?? '';
        final items = purchase['items'] as List<Map<String, dynamic>>? ?? [];

        // Search in vendor name, ref no, or any item name
        return vendorName.contains(query.toLowerCase()) ||
            refNo.contains(query.toLowerCase()) ||
            items.any((item) =>
            item['itemName']?.toString().toLowerCase().contains(query.toLowerCase()) ?? false);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          languageProvider.isEnglish ? 'Purchase List' : 'خریداری کی فہرست',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF8A65), Color(0xFFFFB74D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => BuildBomPage()),
              );
            },
            icon: Icon(Icons.build, color: Colors.white),
            tooltip: languageProvider.isEnglish ? 'Build BOM' : 'BOM بنائیں',
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ItemPurchasePage()),
              ).then((_) {
                // Refresh items after returning
                fetchItems();
              });
            },
            icon: const Icon(Icons.add, color: Colors.white),
            tooltip: languageProvider.isEnglish ? 'New Purchase' : 'نئی خریداری',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: searchPurchases,
              decoration: InputDecoration(
                labelText: languageProvider.isEnglish
                    ? 'Search by Item, Vendor or Ref No'
                    : 'آئٹم، وینڈر یا ریف نمبر کے ذریعہ تلاش کریں',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    searchPurchases('');
                  },
                )
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _filteredPurchases.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      languageProvider.isEnglish
                          ? 'No purchases found'
                          : 'کوئی خریداری نہیں ملی',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                itemCount: _filteredPurchases.length,
                itemBuilder: (context, index) {
                  final purchase = _filteredPurchases[index];
                  final items = purchase['items'] as List<Map<String, dynamic>>? ?? [];
                  final timestamp = purchase['timestamp']?.toString();
                  final date = timestamp != null
                      ? dateFormat.format(DateTime.parse(timestamp))
                      : 'N/A';
                  final refNo = purchase['refNo']?.toString() ?? '';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 2,
                    child: ExpansionTile(
                      leading: CircleAvatar(
                        backgroundColor: Color(0xFFFF8A65),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              purchase['vendorName'] ?? 'Unknown Vendor',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (refNo.isNotEmpty)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                refNo,
                                style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${languageProvider.isEnglish ? 'Total' : 'کل'}: ${purchase['grandTotal']?.toStringAsFixed(2) ?? '0.00'} PKR',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            date,
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            children: [
                              // Items list
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: items.map((item) {
                                    final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
                                    final weight = (item['weight'] as num?)?.toDouble() ??
                                        (item['weightPerUnit'] as num?)?.toDouble() ?? 0;
                                    final totalWeight = (item['totalWeight'] as num?)?.toDouble() ??
                                        (quantity * weight);
                                    final price = (item['purchasePrice'] as num?)?.toDouble() ?? 0;
                                    final itemTotal = totalWeight * price;

                                    return ListTile(
                                      title: Text(
                                        item['itemName'] ?? 'Unknown Item',
                                        style: TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (item['description']?.toString().isNotEmpty ?? false)
                                            Text(
                                              item['description'].toString(),
                                              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                                            ),
                                          Text(
                                            '${languageProvider.isEnglish ? 'Qty' : 'مقدار'}: ${quantity.toStringAsFixed(2)} × '
                                                '${languageProvider.isEnglish ? 'Wt' : 'وزن'}: ${weight.toStringAsFixed(2)} kg = '
                                                '${languageProvider.isEnglish ? 'Total Wt' : 'کل وزن'}: ${totalWeight.toStringAsFixed(2)} kg',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                          Text(
                                            '${languageProvider.isEnglish ? 'Rate' : 'ریٹ'}: ${price.toStringAsFixed(2)} PKR/kg | '
                                                '${languageProvider.isEnglish ? 'Amount' : 'رقم'}: ${itemTotal.toStringAsFixed(2)} PKR',
                                            style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                                          ),
                                        ],
                                      ),
                                      trailing: item['isBOM'] == true
                                          ? Icon(Icons.build, color: Colors.orange, size: 20)
                                          : null,
                                    );
                                  }).toList(),
                                ),
                              ),
                              const Divider(),
                              // Action buttons
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                    label: Text(
                                      languageProvider.isEnglish ? 'Edit' : 'ترمیم',
                                      style: TextStyle(color: Colors.blue),
                                    ),
                                    onPressed: () => editPurchase(purchase),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                    label: Text(
                                      languageProvider.isEnglish ? 'Delete' : 'حذف',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                    onPressed: () => deletePurchase(purchase['key'], purchase),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}