import 'dart:convert';
import 'dart:io';
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../Models/itemModel.dart';
import '../Provider/lanprovider.dart';

class RegisterItemPage extends StatefulWidget {
  final Map<String, dynamic>? itemData;

  RegisterItemPage({this.itemData});

  @override
  _RegisterItemPageState createState() => _RegisterItemPageState();
}

class _RegisterItemPageState extends State<RegisterItemPage> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  XFile? _imageFile;
  String? _imageBase64;
  html.File? _webImageFile;

  bool _isBOM = false;

  late TextEditingController _itemNameController;
  late TextEditingController _descriptionController;
  late TextEditingController _lengthController;
  late TextEditingController _currentLengthCostPriceController;
  late TextEditingController _currentLengthSalePriceController;
  late TextEditingController _sizeQtyController;

  List<LengthBodyCombination> _lengthBodyCombinations = [];
  String? _selectedBodyTypeForCurrent;
  String? _currentLength;
  String? _currentLengthDecimal;

  final TextEditingController _vendorsearchController = TextEditingController();
  final TextEditingController _bomItemSearchController = TextEditingController();
  final TextEditingController _currentStockController = TextEditingController();
  final TextEditingController _lowStockThresholdController =
  TextEditingController(text: '10');

  String? _selectedVendor;

  List<String> _vendors = [];
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _items = [];

  final List<String> _bodyTypes = ['Half', 'Full', 'Half+Full'];

  bool _isLoadingVendors = false;
  bool _isLoadingItems = false;
  List<String> _filteredVendors = [];
  List<Map<String, dynamic>> _filteredItems = [];

  List<Map<String, dynamic>> _bomComponents = [];
  final TextEditingController _componentQtyController = TextEditingController();



  double _profitMargin1kg = 0.0;
  double _profitMargin50kg = 0.0;
  double _profitPercentage1kg = 0.0;
  double _profitPercentage50kg = 0.0;

  double _avgCostPricePerKg = 0.0;
  double _avgSalePricePerKg = 0.0;

  double get totalCost {
    return _bomComponents.fold(0.0, (sum, item) => sum + (item['price'] * item['quantity']));
  }

  @override
  void initState() {
    super.initState();
    _currentLengthCostPriceController = TextEditingController();
    _currentLengthSalePriceController = TextEditingController();
    _sizeQtyController = TextEditingController(text: '0');

    _itemNameController = TextEditingController(text: widget.itemData?['itemName'] ?? '');
    _descriptionController =
        TextEditingController(text: widget.itemData?['description'] ?? '');
    _lengthController = TextEditingController();

    _selectedVendor = widget.itemData?['vendor'];

    if (widget.itemData != null) {
      _sizeQtyController.text = widget.itemData!['qtyOnHand']?.toString() ?? '0';
    }

    if (widget.itemData != null && widget.itemData!['lengthBodyCombinations'] != null) {
      final List<dynamic> rawCombinations = widget.itemData!['lengthBodyCombinations'];
      _lengthBodyCombinations = rawCombinations.map((item) {
        if (item is Map) {
          return LengthBodyCombination.fromMap(Map<String, dynamic>.from(item));
        }
        return LengthBodyCombination(length: '', lengthDecimal: '', bodyType: '');
      }).toList();
      _calculateAveragePrices();
    }

    if (widget.itemData != null) {
      if (widget.itemData!['isBOM'] == true) {
        _isBOM = true;
        final rawComponents = widget.itemData!['components'];
        if (rawComponents != null && rawComponents is List) {
          _bomComponents = rawComponents.map((component) {
            if (component is Map) return Map<String, dynamic>.from(component);
            return <String, dynamic>{};
          }).toList();
        }
      }
    }

    _vendorsearchController.addListener(() => _filterVendors(_vendorsearchController.text));
    _bomItemSearchController.addListener(() => _filterItems(_bomItemSearchController.text));
    _lengthController.addListener(_parseLength);

    fetchDropdownData();
    fetchItems();

    if (widget.itemData != null && widget.itemData!['image'] != null) {
      _imageBase64 = widget.itemData!['image'];
    }
  }

  void _parseLength() {
    setState(() {
      _currentLength = _lengthController.text;
      _currentLengthDecimal =
          parseFractionString(_lengthController.text)?.toString() ?? '';
    });
  }

  void _addLengthBodyCombination() {
    if (_currentLength == null ||
        _currentLength!.isEmpty ||
        _selectedBodyTypeForCurrent == null ||
        _currentLengthCostPriceController.text.isEmpty ||
        _currentLengthSalePriceController.text.isEmpty ||
        _currentStockController.text.isEmpty) {
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(languageProvider.isEnglish
            ? 'Please enter length, body type, prices, and stock quantity'
            : 'براہ کرم لمبائی، جسم کی قسم، قیمتیں، اور اسٹاک مقدار درج کریں'),
      ));
      return;
    }

    final costPrice = double.tryParse(_currentLengthCostPriceController.text);
    final salePrice = double.tryParse(_currentLengthSalePriceController.text);
    final stockQuantity = double.tryParse(_currentStockController.text);
    final lowStockThreshold = double.tryParse(_lowStockThresholdController.text) ?? 10.0;

    if (costPrice == null || salePrice == null || stockQuantity == null) {
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(languageProvider.isEnglish
            ? 'Please enter valid prices and stock quantity'
            : 'براہ کرم درست قیمتیں اور اسٹاک مقدار درج کریں'),
      ));
      return;
    }

    bool combinationExists = _lengthBodyCombinations.any((combo) =>
    combo.length == _currentLength && combo.bodyType == _selectedBodyTypeForCurrent);

    if (combinationExists) {
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(languageProvider.isEnglish
            ? 'This length-body combination already exists'
            : 'یہ لمبائی-جسم کا مجموعہ پہلے سے موجود ہے'),
      ));
      return;
    }

    final combination = LengthBodyCombination(
      length: _currentLength!,
      lengthDecimal: _currentLengthDecimal ?? '',
      bodyType: _selectedBodyTypeForCurrent!,
      costPricePerKg: costPrice,
      salePricePerKg: salePrice,
      stockQuantity: stockQuantity,
      lowStockThreshold: lowStockThreshold,
      stockUnit: 'kg',
    );

    setState(() {
      _lengthBodyCombinations.add(combination);
      _lengthController.clear();
      _currentLengthCostPriceController.clear();
      _currentLengthSalePriceController.clear();
      _currentStockController.clear();
      _selectedBodyTypeForCurrent = null;
      _currentLength = null;
      _currentLengthDecimal = null;
      _calculateAveragePrices();
    });

    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(languageProvider.isEnglish
          ? 'Length-Body combination added with pricing and stock'
          : 'لمبائی-جسم کا مجموعہ قیمتوں اور اسٹاک کے ساتھ شامل کر دیا گیا'),
    ));
  }

  void _removeLengthBodyCombination(int index) {
    setState(() {
      _lengthBodyCombinations.removeAt(index);
      _calculateAveragePrices();
    });
  }

  void _calculateAveragePrices() {
    if (_lengthBodyCombinations.isEmpty) {
      setState(() {
        _avgCostPricePerKg = 0.0;
        _avgSalePricePerKg = 0.0;
        _calculateProfitMargins();
      });
      return;
    }

    double totalCostSum = 0.0;
    double totalSaleSum = 0.0;
    int count = 0;

    for (var combo in _lengthBodyCombinations) {
      if (combo.costPricePerKg != null && combo.salePricePerKg != null) {
        totalCostSum += combo.costPricePerKg!;
        totalSaleSum += combo.salePricePerKg!;
        count++;
      }
    }

    if (count > 0) {
      setState(() {
        _avgCostPricePerKg = totalCostSum / count;
        _avgSalePricePerKg = totalSaleSum / count;
        _calculateProfitMargins();
      });
    }
  }

  void _calculateProfitMargins() {
    setState(() {
      _profitMargin1kg = _avgSalePricePerKg - _avgCostPricePerKg;
      _profitPercentage1kg = _avgCostPricePerKg > 0
          ? (_profitMargin1kg / _avgCostPricePerKg) * 100
          : 0.0;
      _profitMargin50kg = _profitMargin1kg * 50;
      _profitPercentage50kg = _profitPercentage1kg;
    });
  }

  Future<void> fetchItems() async {
    setState(() => _isLoadingItems = true);
    try {
      final DatabaseReference database = FirebaseDatabase.instance.ref();
      final snapshot = await database.child('items').get();
      if (snapshot.exists) {
        final Map<dynamic, dynamic> itemData = snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          _items = itemData.entries.map((entry) {
            return {
              'id': entry.key,
              'name': entry.value['itemName'] as String,
              'unit': 'Pcs',
              'price': entry.value['salePrice1kg'] ?? entry.value['salePrice'] ?? 0.0,
            };
          }).toList();
          _filteredItems = List.from(_items);
        });
      }
    } catch (e) {
      print('Error fetching items: $e');
    } finally {
      setState(() => _isLoadingItems = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      if (kIsWeb) {
        final html.FileUploadInputElement uploadInput = html.FileUploadInputElement();
        uploadInput.accept = 'image/*';
        uploadInput.click();
        uploadInput.onChange.listen((e) {
          final files = uploadInput.files;
          if (files != null && files.isNotEmpty) {
            final file = files[0];
            final reader = html.FileReader();
            reader.onLoadEnd.listen((e) {
              setState(() {
                _webImageFile = file;
                _imageBase64 = reader.result.toString().split(',').last;
              });
            });
            reader.readAsDataUrl(file);
          }
        });
      } else {
        final XFile? pickedFile =
        await _picker.pickImage(source: ImageSource.gallery);
        if (pickedFile != null) {
          final bytes = await File(pickedFile.path).readAsBytes();
          setState(() {
            _imageFile = pickedFile;
            _imageBase64 = base64Encode(bytes);
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
    }
  }

  void _removeImage() {
    setState(() {
      _imageFile = null;
      _imageBase64 = null;
    });
  }

  void _filterVendors(String query) {
    setState(() {
      _filteredVendors = query.isEmpty
          ? List.from(_vendors)
          : _vendors
          .where((v) => v.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  void _filterItems(String query) {
    setState(() {
      _filteredItems = query.isEmpty
          ? List.from(_items)
          : _items
          .where((i) =>
          i['name'].toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  Future<void> fetchDropdownData() async {
    final DatabaseReference database = FirebaseDatabase.instance.ref();
    setState(() => _isLoadingVendors = true);
    try {
      final snapshot = await database.child('vendors').get();
      if (snapshot.exists) {
        final Map<dynamic, dynamic> vendorData =
        snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          _vendors = vendorData.entries
              .map((entry) => entry.value['name'] as String)
              .toList();
          _filteredVendors = List.from(_vendors);
        });
      }
    } catch (e) {
      print('Error fetching vendors: $e');
    } finally {
      setState(() => _isLoadingVendors = false);
    }
    // Fetch customers for combination-level price dialog
    await _fetchCustomers();
  }

  Future<void> _fetchCustomers() async {
    try {
      final DatabaseReference database = FirebaseDatabase.instance.ref();
      final snapshot = await database.child('customers').get();
      if (snapshot.exists) {
        final Map<dynamic, dynamic> customerData =
        snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          _customers = customerData.entries.map((entry) => {
            'id': entry.key,
            'name': entry.value['name'] as String,
            'phone': entry.value['phone'] ?? '',
          }).toList();
        });
      }
    } catch (e) {
      print('Error fetching customers: $e');
    }
  }

  void _addBomComponent(Map<String, dynamic> item, double quantity) {
    setState(() {
      _bomComponents.add({
        'id': item['id'],
        'name': item['name'],
        'unit': 'Pcs',
        'quantity': quantity,
        'price': item['price'],
      });
      _bomItemSearchController.clear();
      _filteredItems = List.from(_items);
    });
  }

  void _removeBomComponent(int index) {
    setState(() => _bomComponents.removeAt(index));
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // NEW: Per-combination customer prices dialog
  // ─────────────────────────────────────────────────────────────────────────────
  void _showCombinationCustomerPricesDialog(int index) {
    final combination = _lengthBodyCombinations[index];
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    // Work on a local copy so Cancel truly cancels
    Map<String, double> localPrices = Map.from(combination.customerPrices);
    final TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> filteredCustomers = List.from(_customers);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    languageProvider.isEnglish
                        ? 'Customer Prices'
                        : 'کسٹمر قیمتیں',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${combination.length}  —  ${combination.bodyType}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Default price banner
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                          const SizedBox(width: 6),
                          Text(
                            languageProvider.isEnglish
                                ? 'Default sale price: ${combination.salePricePerKg?.toStringAsFixed(2) ?? "N/A"} PKR/kg'
                                : 'پہلے سے طے شدہ قیمت: ${combination.salePricePerKg?.toStringAsFixed(2) ?? "N/A"} روپے/کلو',
                            style: TextStyle(
                              color: Colors.blue[700],
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Search field
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: languageProvider.isEnglish
                            ? 'Search customers...'
                            : 'کسٹمر تلاش کریں...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          filteredCustomers = value.isEmpty
                              ? List.from(_customers)
                              : _customers
                              .where((c) => c['name']
                              .toLowerCase()
                              .contains(value.toLowerCase()))
                              .toList();
                        });
                      },
                    ),
                    const SizedBox(height: 8),

                    // Customer list
                    Container(
                      height: 280,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _customers.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
                        itemCount: filteredCustomers.length,
                        itemBuilder: (context, i) {
                          final customer = filteredCustomers[i];
                          final customerId = customer['id'] as String;
                          final hasCustomPrice =
                          localPrices.containsKey(customerId);
                          final currentPrice = localPrices[customerId];

                          return ListTile(
                            dense: true,
                            title: Text(customer['name']),
                            subtitle: hasCustomPrice
                                ? Text(
                              '${currentPrice!.toStringAsFixed(2)} PKR/kg',
                              style: TextStyle(
                                color: Colors.green[700],
                                fontWeight: FontWeight.bold,
                              ),
                            )
                                : Text(
                              languageProvider.isEnglish
                                  ? 'Using default price'
                                  : 'پہلے سے طے شدہ قیمت',
                              style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 11),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Delete custom price
                                if (hasCustomPrice)
                                  IconButton(
                                    icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                        size: 18),
                                    onPressed: () => setDialogState(
                                            () => localPrices
                                            .remove(customerId)),
                                  ),
                                // Add / Edit custom price
                                IconButton(
                                  icon: Icon(
                                    hasCustomPrice
                                        ? Icons.edit
                                        : Icons.add_circle_outline,
                                    color: hasCustomPrice
                                        ? Colors.orange
                                        : Colors.green,
                                    size: 18,
                                  ),
                                  onPressed: () async {
                                    final priceController =
                                    TextEditingController(
                                      text: currentPrice
                                          ?.toStringAsFixed(2) ??
                                          '',
                                    );
                                    final price =
                                    await showDialog<double>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: Text(customer['name']),
                                        content: TextField(
                                          controller: priceController,
                                          keyboardType:
                                          TextInputType.number,
                                          autofocus: true,
                                          decoration: InputDecoration(
                                            labelText: languageProvider
                                                .isEnglish
                                                ? 'Sale Price (PKR/kg)'
                                                : 'فروخت قیمت (روپے/کلو)',
                                            border:
                                            const OutlineInputBorder(),
                                            prefixText: 'PKR ',
                                            helperText:
                                            'Default: ${combination.salePricePerKg?.toStringAsFixed(2)} PKR/kg',
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: Text(languageProvider
                                                .isEnglish
                                                ? 'Cancel'
                                                : 'منسوخ'),
                                          ),
                                          ElevatedButton(
                                            style:
                                            ElevatedButton.styleFrom(
                                              backgroundColor:
                                              Colors.orange[300],
                                            ),
                                            onPressed: () {
                                              final p = double.tryParse(
                                                  priceController.text);
                                              if (p != null && p > 0) {
                                                Navigator.pop(context, p);
                                              }
                                            },
                                            child: Text(
                                              languageProvider.isEnglish
                                                  ? 'Save'
                                                  : 'محفوظ کریں',
                                              style: const TextStyle(
                                                  color: Colors.white),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (price != null) {
                                      setDialogState(() =>
                                      localPrices[customerId] =
                                          price);
                                    }
                                  },
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                      languageProvider.isEnglish ? 'Cancel' : 'منسوخ'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[300]),
                  onPressed: () {
                    setState(() {
                      _lengthBodyCombinations[index] =
                          combination.copyWith(customerPrices: localPrices);
                    });
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(languageProvider.isEnglish
                          ? 'Customer prices saved for this combination'
                          : 'اس مجموعے کے لیے کسٹمر قیمتیں محفوظ ہو گئیں'),
                    ));
                  },
                  child: Text(
                    languageProvider.isEnglish ? 'Save' : 'محفوظ کریں',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddBomComponentDialog(Map<String, dynamic> item) {
    TextEditingController qtyController = TextEditingController();
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(languageProvider.isEnglish
              ? 'Add ${item['name']}'
              : '${item['name']} شامل کریں'),
          content: TextFormField(
            controller: qtyController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: languageProvider.isEnglish ? 'Quantity' : 'مقدار',
              hintText: languageProvider.isEnglish
                  ? 'Enter quantity'
                  : 'مقدار درج کریں',
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ'),
            ),
            TextButton(
              onPressed: () {
                double? qty = double.tryParse(qtyController.text);
                if (qty != null) {
                  _addBomComponent(item, qty);
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(languageProvider.isEnglish
                        ? 'Please enter a valid quantity'
                        : 'براہ کرم درست مقدار درج کریں'),
                  ));
                }
              },
              child: Text(languageProvider.isEnglish ? 'Add' : 'شامل کریں'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> checkIfItemExists(String itemName) async {
    final DatabaseReference database = FirebaseDatabase.instance.ref();
    final snapshot = await database.child('items').get();
    if (snapshot.exists && snapshot.value is Map) {
      Map<dynamic, dynamic> items = snapshot.value as Map<dynamic, dynamic>;
      for (var key in items.keys) {
        if (items[key]['itemName'].toString().toLowerCase() ==
            itemName.toLowerCase()) {
          return true;
        }
      }
    }
    return false;
  }

  void _clearFormFields() {
    setState(() {
      _itemNameController.clear();
      _descriptionController.clear();
      _lengthController.clear();
      _currentLengthCostPriceController.clear();
      _currentLengthSalePriceController.clear();
      _selectedVendor = null;
      _selectedBodyTypeForCurrent = null;
      _bomComponents.clear();
      _lengthBodyCombinations.clear();
      _profitMargin1kg = 0.0;
      _profitMargin50kg = 0.0;
      _profitPercentage1kg = 0.0;
      _profitPercentage50kg = 0.0;
      _currentLength = null;
      _currentLengthDecimal = null;
      _avgCostPricePerKg = 0.0;
      _avgSalePricePerKg = 0.0;
    });
  }

  void saveOrUpdateItem() async {
    if (_formKey.currentState!.validate()) {
      final itemName = _itemNameController.text;

      if (widget.itemData == null) {
        bool itemExists = await checkIfItemExists(itemName);
        if (itemExists) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Item with this name already exists!')),
          );
          return;
        }
      }

      if (_lengthBodyCombinations.isEmpty) {
        final languageProvider =
        Provider.of<LanguageProvider>(context, listen: false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(languageProvider.isEnglish
              ? 'Please add at least one length-body combination with pricing'
              : 'براہ کرم کم از کم ایک لمبائی-جسم کا مجموعہ قیمتوں کے ساتھ شامل کریں'),
        ));
        return;
      }

      final DatabaseReference database = FirebaseDatabase.instance.ref();

      double totalBOMCost = 0.0;
      if (_isBOM) {
        for (var component in _bomComponents) {
          totalBOMCost += (component['price'] * component['quantity']);
        }
      }

      Map<String, double> customerPrices = {};
      final qtyOnHand = double.tryParse(_sizeQtyController.text) ?? 0.0;

      final newItem = {
        'itemName': itemName,
        'description': _descriptionController.text,
        'lengthBodyCombinations':
        _lengthBodyCombinations.map((c) => c.toMap()).toList(),
        'avgCostPricePerKg': _avgCostPricePerKg,
        'avgSalePricePerKg': _avgSalePricePerKg,
        'costPrice1kg': _avgCostPricePerKg,
        'salePrice1kg': _avgSalePricePerKg,
        'costPrice50kg': _avgCostPricePerKg * 50,
        'salePrice50kg': _avgSalePricePerKg * 50,
        'unit': 'Kg',
        'costPrice': _isBOM ? totalBOMCost : _avgCostPricePerKg,
        'salePrice': _avgSalePricePerKg,
        'qtyOnHand': qtyOnHand,
        'vendor': _selectedVendor,
        'customerBasePrices': customerPrices,
        'image': _imageBase64,
        'isBOM': _isBOM,
        'components': _isBOM ? _bomComponents : null,
        'createdAt': ServerValue.timestamp,
        'profitMargin1kg': _profitMargin1kg,
        'profitPercentage1kg': _profitPercentage1kg,
        'profitMargin50kg': _profitMargin50kg,
        'profitPercentage50kg': _profitPercentage50kg,
        'hasMultipleLengthPrices': _lengthBodyCombinations.isNotEmpty,
      };

      if (widget.itemData == null) {
        database.child('items').push().set(newItem).then((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Item registered successfully!')),
          );
          _clearFormFields();
        }).catchError((error) {
          print(error);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to register item: $error')),
          );
        });
      } else {
        database.child('items/${widget.itemData!['key']}').set(newItem).then((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Item updated successfully!')),
          );
        }).catchError((error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update item: $error')),
          );
        });
      }
    }
  }

  Widget _buildImagePreview() {
    if (_imageBase64 != null) {
      return Stack(
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              image: DecorationImage(
                image: kIsWeb
                    ? Image.network('data:image/png;base64,$_imageBase64').image
                    : MemoryImage(base64Decode(_imageBase64!)),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: _removeImage,
            ),
          ),
        ],
      );
    } else {
      return Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.image, size: 50, color: Colors.grey),
      );
    }
  }

  Widget _buildBomComponentsList() {
    if (_bomComponents.isEmpty) {
      return const Center(
        child: Text('No components added yet', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _bomComponents.length,
      itemBuilder: (context, index) {
        final component = _bomComponents[index];
        final isDeduction = component['quantity'] < 0;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: isDeduction ? Colors.red[50] : null,
          child: ListTile(
            title: Text(component['name']),
            subtitle: Text('${component['quantity']} Pcs'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    '${(component['price'] * component['quantity']).toStringAsFixed(2)} PKR'),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeBomComponent(index),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLengthBodyCombinationsList() {
    if (_lengthBodyCombinations.isEmpty) {
      return const Center(
        child: Text('No length-body combinations added yet',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _lengthBodyCombinations.length,
      itemBuilder: (context, index) {
        final combination = _lengthBodyCombinations[index];

        Color stockColor;
        IconData stockIcon;
        String stockStatus;

        if (combination.isOutOfStock) {
          stockColor = Colors.red;
          stockIcon = Icons.remove_circle;
          stockStatus = 'Out of Stock';
        } else if (combination.isLowStock) {
          stockColor = Colors.orange;
          stockIcon = Icons.warning;
          stockStatus = 'Low Stock';
        } else {
          stockColor = Colors.green;
          stockIcon = Icons.check_circle;
          stockStatus = 'In Stock';
        }

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: Container(
              width: 8,
              decoration: BoxDecoration(
                color: stockColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Length: ${combination.length}'),
                Text('Body Type: ${combination.bodyType}'),
                Row(
                  children: [
                    Icon(stockIcon, size: 16, color: stockColor),
                    const SizedBox(width: 4),
                    Text(
                      'Stock: ${combination.stockQuantity.toStringAsFixed(2)}${combination.stockUnit}',
                      style: TextStyle(
                          color: stockColor, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text('($stockStatus)',
                        style: TextStyle(fontSize: 12, color: stockColor)),
                  ],
                ),
                // ─── NEW: Customer price count badge ───
                if (combination.customerPrices.isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.people, size: 14, color: Colors.purple),
                      const SizedBox(width: 4),
                      Text(
                        '${combination.customerPrices.length} custom price(s)',
                        style:
                        const TextStyle(fontSize: 12, color: Colors.purple),
                      ),
                    ],
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (combination.lengthDecimal.isNotEmpty)
                  Text('Length (Decimal): ${combination.lengthDecimal}'),
                if (combination.costPricePerKg != null &&
                    combination.salePricePerKg != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                          'Cost: ${combination.costPricePerKg!.toStringAsFixed(2)} PKR/kg'),
                      Text(
                          'Sale: ${combination.salePricePerKg!.toStringAsFixed(2)} PKR/kg'),
                      Text(
                        'Profit: ${(combination.salePricePerKg! - combination.costPricePerKg!).toStringAsFixed(2)} PKR/kg '
                            '(${((combination.salePricePerKg! - combination.costPricePerKg!) / combination.costPricePerKg! * 100).toStringAsFixed(1)}%)',
                        style: TextStyle(
                          color: combination.salePricePerKg! >
                              combination.costPricePerKg!
                              ? Colors.green
                              : Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ─── NEW: Customer prices button ───
                IconButton(
                  icon: const Icon(Icons.people, color: Colors.purple),
                  tooltip: 'Customer Prices',
                  onPressed: () =>
                      _showCombinationCustomerPricesDialog(index),
                ),
                // Edit stock
                IconButton(
                  icon: const Icon(Icons.inventory, color: Colors.blue),
                  onPressed: () => _editStockForCombination(index),
                ),
                // Edit combination
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _editLengthBodyCombination(index),
                ),
                // Delete
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeLengthBodyCombination(index),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _editStockForCombination(int index) {
    final combination = _lengthBodyCombinations[index];
    TextEditingController stockController =
    TextEditingController(text: combination.stockQuantity.toStringAsFixed(2));
    TextEditingController thresholdController =
    TextEditingController(text: combination.lowStockThreshold.toStringAsFixed(2));
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(languageProvider.isEnglish
              ? 'Update Stock for ${combination.length} - ${combination.bodyType}'
              : 'اسٹاک اپ ڈیٹ کریں: ${combination.length} - ${combination.bodyType}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: stockController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText:
                  languageProvider.isEnglish ? 'Current Stock' : 'موجودہ اسٹاک',
                  suffixText: combination.stockUnit,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: thresholdController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: languageProvider.isEnglish
                      ? 'Low Stock Threshold'
                      : 'کم اسٹاک حد',
                  suffixText: combination.stockUnit,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ'),
            ),
            TextButton(
              onPressed: () {
                final newStock = double.tryParse(stockController.text);
                final newThreshold = double.tryParse(thresholdController.text);
                if (newStock != null && newThreshold != null) {
                  setState(() {
                    _lengthBodyCombinations[index] = combination.copyWith(
                      stockQuantity: newStock,
                      lowStockThreshold: newThreshold,
                    );
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(languageProvider.isEnglish
                        ? 'Stock updated successfully'
                        : 'اسٹاک کامیابی سے اپ ڈیٹ ہو گیا'),
                  ));
                }
              },
              child: Text(languageProvider.isEnglish ? 'Update' : 'اپ ڈیٹ کریں'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProfitMarginDisplay() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Profit Margins (Based on Average Prices)',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700]),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Average 1 Kg Price:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('Cost: ${_avgCostPricePerKg.toStringAsFixed(2)} PKR',
                        style: const TextStyle(color: Colors.blue)),
                    Text('Sale: ${_avgSalePricePerKg.toStringAsFixed(2)} PKR',
                        style: const TextStyle(color: Colors.green)),
                    const SizedBox(height: 8),
                    const Text('Profit (1Kg):',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      '${_profitMargin1kg.toStringAsFixed(2)} PKR',
                      style: TextStyle(
                          color: _profitMargin1kg >= 0
                              ? Colors.green
                              : Colors.red,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${_profitPercentage1kg.toStringAsFixed(1)}%',
                      style: TextStyle(
                          color: _profitPercentage1kg >= 0
                              ? Colors.green
                              : Colors.red,
                          fontSize: 12),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Average 50 Kg Price:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                        'Cost: ${(_avgCostPricePerKg * 50).toStringAsFixed(2)} PKR',
                        style: const TextStyle(color: Colors.blue)),
                    Text(
                        'Sale: ${(_avgSalePricePerKg * 50).toStringAsFixed(2)} PKR',
                        style: const TextStyle(color: Colors.green)),
                    const SizedBox(height: 8),
                    const Text('Profit (50Kg):',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      '${_profitMargin50kg.toStringAsFixed(2)} PKR',
                      style: TextStyle(
                          color: _profitMargin50kg >= 0
                              ? Colors.green
                              : Colors.red,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${_profitPercentage50kg.toStringAsFixed(1)}%',
                      style: TextStyle(
                          color: _profitPercentage50kg >= 0
                              ? Colors.green
                              : Colors.red,
                          fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Based on ${_lengthBodyCombinations.length} length combination(s)',
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDecimalValueDisplay(String label, String? decimalValue,
      {double fontSize = 14.0}) {
    if (decimalValue == null || decimalValue.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.calculate, size: fontSize, color: Colors.blue),
          const SizedBox(width: 8),
          Text('$label = $decimalValue',
              style: TextStyle(fontSize: fontSize, color: Colors.blue[700])),
        ],
      ),
    );
  }

  Widget _buildLengthBodyCombinationsSection() {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              languageProvider.isEnglish
                  ? 'Length-Body Combinations with Pricing and Stock'
                  : 'لمبائی-جسم کے مجموعے قیمتوں اور اسٹاک کے ساتھ',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700]),
            ),
            const SizedBox(height: 16),

            FractionInputField(
              controller: _lengthController,
              labelText: languageProvider.isEnglish ? 'Length' : 'لمبائی',
              hintText: languageProvider.isEnglish
                  ? 'e.g., 3¼ or 3 1/4'
                  : 'مثال: 3¼ یا 3 1/4',
              isEnglish: languageProvider.isEnglish,
              fontSize: 16.0,
              labelFontSize: 16.0,
              onChanged: (value) => _parseLength(),
            ),
            _buildDecimalValueDisplay(
              languageProvider.isEnglish ? 'Length (decimal)' : 'لمبائی (اعشاریہ)',
              _currentLengthDecimal,
              fontSize: 14.0,
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              value: _selectedBodyTypeForCurrent,
              decoration: InputDecoration(
                labelText:
                languageProvider.isEnglish ? 'Body Type' : 'بڈی کی قسم',
                border: const OutlineInputBorder(),
                focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.orange)),
              ),
              items: _bodyTypes.map((String value) {
                return DropdownMenuItem<String>(
                    value: value, child: Text(value));
              }).toList(),
              onChanged: (String? newValue) {
                setState(() => _selectedBodyTypeForCurrent = newValue);
              },
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _currentLengthCostPriceController,
                    decoration: InputDecoration(
                      labelText: languageProvider.isEnglish
                          ? 'Cost Price/Kg'
                          : 'لاگت قیمت/کلو',
                      border: const OutlineInputBorder(),
                      prefixText: 'PKR ',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _currentLengthSalePriceController,
                    decoration: InputDecoration(
                      labelText: languageProvider.isEnglish
                          ? 'Sale Price/Kg'
                          : 'فروخت قیمت/کلو',
                      border: const OutlineInputBorder(),
                      prefixText: 'PKR ',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _currentStockController,
                    decoration: InputDecoration(
                      labelText: languageProvider.isEnglish
                          ? 'Initial Stock'
                          : 'ابتدائی اسٹاک',
                      border: const OutlineInputBorder(),
                      suffixText: 'kg',
                      prefixIcon: const Icon(Icons.inventory),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _lowStockThresholdController,
                    decoration: InputDecoration(
                      labelText: languageProvider.isEnglish
                          ? 'Low Stock Alert'
                          : 'کم اسٹاک الرٹ',
                      border: const OutlineInputBorder(),
                      suffixText: 'kg',
                      prefixIcon: const Icon(Icons.warning),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: _addLengthBodyCombination,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                languageProvider.isEnglish
                    ? 'Add Length Combination'
                    : 'لمبائی کا مجموعہ شامل کریں',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),

            if (_lengthBodyCombinations.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue),
                ),
                child: Row(
                  children: [
                    Icon(Icons.summarize, color: Colors.blue[700]),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            languageProvider.isEnglish
                                ? 'Stock Summary'
                                : 'اسٹاک کا خلاصہ',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[700]),
                          ),
                          Text(
                            languageProvider.isEnglish
                                ? 'Total Stock: ${_calculateTotalStock().toStringAsFixed(2)} kg'
                                : 'کل اسٹاک: ${_calculateTotalStock().toStringAsFixed(2)} کلو',
                          ),
                          Text(
                            '${_lengthBodyCombinations.length} combination(s)',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            Text(
              languageProvider.isEnglish
                  ? 'Added Length Combinations (${_lengthBodyCombinations.length})'
                  : 'شامل کردہ لمبائی کے مجموعے (${_lengthBodyCombinations.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildLengthBodyCombinationsList(),
          ],
        ),
      ),
    );
  }

  double _calculateTotalStock() {
    return _lengthBodyCombinations.fold(
        0.0, (sum, combo) => sum + combo.stockQuantity);
  }

  void _editLengthBodyCombination(int index) {
    final combination = _lengthBodyCombinations[index];
    _lengthController.text = combination.length;
    _selectedBodyTypeForCurrent = combination.bodyType;
    _currentLengthCostPriceController.text =
        combination.costPricePerKg?.toString() ?? '';
    _currentLengthSalePriceController.text =
        combination.salePricePerKg?.toString() ?? '';
    _currentStockController.text =
        combination.stockQuantity.toStringAsFixed(2);
    _lowStockThresholdController.text =
        combination.lowStockThreshold.toStringAsFixed(2);

    _parseLength();
    _lengthBodyCombinations.removeAt(index);
    _calculateAveragePrices();

    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(languageProvider.isEnglish
          ? 'Length combination loaded for editing'
          : 'لمبائی کا مجموعہ ترمیم کے لیے لوڈ کر دیا گیا'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);

    double additions = _bomComponents
        .where((c) => c['quantity'] > 0)
        .fold(0.0, (sum, item) => sum + (item['price'] * item['quantity']));
    double deductions = _bomComponents
        .where((c) => c['quantity'] < 0)
        .fold(
        0.0,
            (sum, item) =>
        sum + (item['price'] * item['quantity']).abs());

    return Scaffold(
      appBar: AppBar(
        title: Text(
          languageProvider.isEnglish
              ? (_isBOM ? 'Create BOM' : 'Register Item')
              : (_isBOM ? 'BOM بنائیں' : 'آئٹم ایڈ کریں'),
          style: const TextStyle(color: Colors.white),
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
        centerTitle: true,
        actions: [
          if (widget.itemData == null)
            IconButton(
              icon: Icon(_isBOM ? Icons.inventory : Icons.assignment),
              tooltip: _isBOM
                  ? (languageProvider.isEnglish
                  ? 'Switch to Item'
                  : 'آئٹم پر سوئچ کریں')
                  : (languageProvider.isEnglish
                  ? 'Switch to BOM'
                  : 'BOM پر سوئچ کریں'),
              onPressed: () {
                setState(() {
                  _isBOM = !_isBOM;
                  if (!_isBOM) _bomComponents.clear();
                });
              },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Card(
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  // Mode indicator
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _isBOM ? Colors.blue[50] : Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _isBOM ? Colors.blue : Colors.orange),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isBOM ? Icons.inventory : Icons.shopping_bag,
                          color: _isBOM ? Colors.blue : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isBOM
                              ? (languageProvider.isEnglish
                              ? 'Creating a Bill of Materials'
                              : 'بل آف میٹیریلز بنانا')
                              : (languageProvider.isEnglish
                              ? 'Registering a Single Item'
                              : 'ایک آئٹم رجسٹر کرنا'),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _isBOM ? Colors.blue : Colors.orange),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Image Upload
                  Column(
                    children: [
                      Text(
                        languageProvider.isEnglish
                            ? 'Item Image'
                            : 'آئٹم کی تصویر',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      _buildImagePreview(),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _pickImage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[300],
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          languageProvider.isEnglish
                              ? 'Upload Image'
                              : 'تصویر اپ لوڈ کریں',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Item Name / Size
                  FractionInputField(
                    controller: _itemNameController,
                    labelText: languageProvider.isEnglish ? 'Size' : 'سائز',
                    hintText: languageProvider.isEnglish
                        ? 'e.g., Steel Bar 2½'
                        : 'مثال: اسٹیل بار 2½',
                    isEnglish: languageProvider.isEnglish,
                    fontSize: 16.0,
                    labelFontSize: 16.0,
                    onChanged: (value) {},
                  ),
                  const SizedBox(height: 16),

                  // Description
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: languageProvider.isEnglish
                          ? 'Description'
                          : 'تفصیل',
                      border: const OutlineInputBorder(),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.orange)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Combinations section
                  _buildLengthBodyCombinationsSection(),
                  const SizedBox(height: 16),

                  if (_lengthBodyCombinations.isNotEmpty)
                    _buildProfitMarginDisplay(),
                  const SizedBox(height: 16),

                  // BOM section
                  if (_isBOM) ...[
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              languageProvider.isEnglish
                                  ? 'BOM Components'
                                  : 'BOM اجزاء',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            if (_isLoadingItems)
                              const Center(child: CircularProgressIndicator())
                            else if (_items.isNotEmpty)
                              Column(
                                children: [
                                  TextField(
                                    controller: _bomItemSearchController,
                                    decoration: InputDecoration(
                                      hintText: languageProvider.isEnglish
                                          ? 'Search items to add...'
                                          : 'آئٹمز کو شامل کرنے کے لیے تلاش کریں...',
                                      border: OutlineInputBorder(
                                          borderRadius:
                                          BorderRadius.circular(8)),
                                      prefixIcon: const Icon(Icons.search),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  if (_bomItemSearchController.text.isNotEmpty)
                                    Container(
                                      height: 150,
                                      decoration: BoxDecoration(
                                        border:
                                        Border.all(color: Colors.grey),
                                        borderRadius:
                                        BorderRadius.circular(8),
                                      ),
                                      child: ListView.builder(
                                        itemCount: _filteredItems.length,
                                        itemBuilder: (context, index) {
                                          final item = _filteredItems[index];
                                          return ListTile(
                                            title: Text(item['name']),
                                            subtitle: Text(
                                                '${item['price']} PKR/Pcs'),
                                            trailing: const Icon(Icons.add,
                                                color: Colors.green),
                                            onTap: () =>
                                                _showAddBomComponentDialog(
                                                    item),
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            const SizedBox(height: 20),
                            Text(
                              languageProvider.isEnglish
                                  ? 'Added Components (${_bomComponents.length})'
                                  : 'شامل کردہ اجزاء (${_bomComponents.length})',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            _buildBomComponentsList(),
                            const SizedBox(height: 10),
                            if (_bomComponents.isNotEmpty)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    languageProvider.isEnglish
                                        ? 'Total Estimated Cost: ${totalCost.toStringAsFixed(2)} PKR'
                                        : 'کل تخمینہ لاگت: ${totalCost.toStringAsFixed(2)} روپے',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Colors.blue),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    languageProvider.isEnglish
                                        ? '(Additions: ${additions.toStringAsFixed(2)} PKR, Deductions: ${deductions.toStringAsFixed(2)} PKR)'
                                        : '(اضافے: ${additions.toStringAsFixed(2)} روپے, کٹوتیاں: ${deductions.toStringAsFixed(2)} روپے)',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Vendor
                  if (!_isBOM) ...[
                    if (_isLoadingVendors)
                      const Center(child: CircularProgressIndicator())
                    else if (_vendors.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            languageProvider.isEnglish
                                ? 'Search Vendor'
                                : 'وینڈر تلاش کریں',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _vendorsearchController,
                            decoration: InputDecoration(
                              hintText: languageProvider.isEnglish
                                  ? 'Type to search vendors...'
                                  : 'وینڈرز کو تلاش کرنے کے لیے ٹائپ کریں...',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              prefixIcon: const Icon(Icons.search),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_vendorsearchController.text.isNotEmpty)
                            Container(
                              height: 200,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.builder(
                                itemCount: _filteredVendors.length,
                                itemBuilder: (context, index) {
                                  final vendor = _filteredVendors[index];
                                  return ListTile(
                                    title: Text(vendor),
                                    onTap: () {
                                      setState(() {
                                        _selectedVendor = vendor;
                                        _vendorsearchController.clear();
                                        _filteredVendors =
                                            List.from(_vendors);
                                      });
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: Text(
                                            '${languageProvider.isEnglish ? 'Selected Vendor: ' : 'منتخب فروش: '}$vendor'),
                                      ));
                                    },
                                  );
                                },
                              ),
                            ),
                          const SizedBox(height: 20),
                          if (_selectedVendor != null)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle,
                                      color: Colors.orange[300]),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${languageProvider.isEnglish ? 'Selected Vendor: ' : 'منتخب فروش: '}$_selectedVendor',
                                      style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.orange[300]),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 20),
                  ],

                  const SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: saveOrUpdateItem,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[300],
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      languageProvider.isEnglish
                          ? (widget.itemData == null
                          ? (_isBOM ? 'Create BOM' : 'Register Item')
                          : 'Update')
                          : (widget.itemData == null
                          ? (_isBOM ? 'BOM بنائیں' : 'آئٹم ایڈ کریں')
                          : 'اپ ڈیٹ کریں'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _currentLengthCostPriceController.dispose();
    _currentLengthSalePriceController.dispose();
    _itemNameController.dispose();
    _descriptionController.dispose();
    _lengthController.dispose();
    _vendorsearchController.dispose();
    _bomItemSearchController.dispose();
    _componentQtyController.dispose();
    _sizeQtyController.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FractionInputField — unchanged from original
// ─────────────────────────────────────────────────────────────────────────────

class FractionInputField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final bool isEnglish;
  final ValueChanged<String>? onChanged;
  final double? fontSize;
  final double? labelFontSize;

  const FractionInputField({
    Key? key,
    required this.controller,
    required this.labelText,
    this.hintText,
    required this.isEnglish,
    this.onChanged,
    this.fontSize,
    this.labelFontSize,
  }) : super(key: key);

  @override
  _FractionInputFieldState createState() => _FractionInputFieldState();
}

class _FractionInputFieldState extends State<FractionInputField> {
  final Map<String, String> _fractionButtons = {
    '½': '0.5',   '⅓': '0.333', '⅔': '0.667', '¼': '0.25',  '¾': '0.75',
    '⅕': '0.2',   '⅖': '0.4',   '⅗': '0.6',   '⅘': '0.8',   '⅙': '0.167',
    '⅚': '0.833', '⅐': '0.143', '⅛': '0.125', '⅜': '0.375', '⅝': '0.625',
    '⅞': '0.875', '⅑': '0.111', '⅒': '0.1',
    '¾"': '0.75',  '1"': '1.0',   '1¼"': '1.25', '1½"': '1.5',
    '2"': '2.0',   '2¼"': '2.25', '2½"': '2.5',  '2¾"': '2.75',
    '3"': '3.0',   '3¼"': '3.25', '3½"': '3.5',  '3¾"': '3.75',
    '4"': '4.0',   '4¼"': '4.25', '5"': '5.0',   '5½"': '5.5',
    '6"': '6.0',
  };

  void _showFractionPopup(BuildContext context) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + renderBox.size.height,
        position.dx + renderBox.size.width,
        position.dy + renderBox.size.height + 200,
      ),
      items: [
        ..._fractionButtons.entries.map((entry) {
          return PopupMenuItem<String>(
            value: entry.key,
            child: SizedBox(
              width: 100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(entry.key, style: const TextStyle(fontSize: 20)),
                  Text('= ${entry.value}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          );
        }).toList(),
        PopupMenuItem<String>(
          value: 'custom',
          child: ListTile(
            leading: const Icon(Icons.more_horiz),
            title: Text(widget.isEnglish
                ? 'Custom fraction...'
                : 'اپنی پسند کا حصہ...'),
            onTap: () => _showCustomFractionDialog(context),
          ),
        ),
      ],
    ).then((selectedFraction) {
      if (selectedFraction != null && selectedFraction != 'custom') {
        final newText = widget.controller.text + selectedFraction;
        widget.controller.text = newText;
        widget.onChanged?.call(newText);
      }
    });
  }

  void _showCustomFractionDialog(BuildContext context) {
    TextEditingController numeratorController = TextEditingController();
    TextEditingController denominatorController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
              widget.isEnglish ? 'Custom Fraction' : 'اپنی پسند کا حصہ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: numeratorController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: widget.isEnglish
                      ? 'Numerator (top number)'
                      : 'اوپر والا نمبر',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: denominatorController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: widget.isEnglish
                      ? 'Denominator (bottom number)'
                      : 'نیچے والا نمبر',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.isEnglish
                    ? 'Example: 1/2 will become 0.5'
                    : 'مثال: 1/2 کو 0.5 بنا دیا جائے گا',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(widget.isEnglish ? 'Cancel' : 'منسوخ'),
            ),
            TextButton(
              onPressed: () {
                final numerator = double.tryParse(numeratorController.text);
                final denominator =
                double.tryParse(denominatorController.text);
                if (numerator != null &&
                    denominator != null &&
                    denominator != 0) {
                  final newText =
                      '${widget.controller.text}$numerator/$denominator';
                  widget.controller.text = newText;
                  widget.onChanged?.call(newText);
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(widget.isEnglish
                        ? 'Please enter valid numbers'
                        : 'براہ کرم درست نمبر درج کریں'),
                  ));
                }
              },
              child: Text(widget.isEnglish ? 'Add' : 'شامل کریں'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          style: TextStyle(fontSize: widget.fontSize ?? 16.0),
          decoration: InputDecoration(
            labelText: widget.labelText,
            labelStyle:
            TextStyle(fontSize: widget.labelFontSize ?? 16.0),
            hintText: widget.hintText ??
                (widget.isEnglish
                    ? 'Enter value like 2½'
                    : 'مقدار درج کریں جیسے 2½'),
            hintStyle: TextStyle(
                fontSize: widget.fontSize != null
                    ? widget.fontSize! * 0.9
                    : 14.4),
            border: const OutlineInputBorder(),
            focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.orange)),
            suffixIcon: IconButton(
              icon: const Icon(Icons.calculate),
              onPressed: () => _showFractionPopup(context),
              tooltip:
              widget.isEnglish ? 'Insert fraction' : 'حصہ شامل کریں',
            ),
          ),
          onChanged: widget.onChanged,
        ),
        const SizedBox(height: 4),
        Text(
          widget.isEnglish
              ? 'Tap the calculator icon to insert fractions'
              : 'حصے شامل کرنے کے لیے کیلکولیٹر آئیکون پر ٹیپ کریں',
          style: TextStyle(
              fontSize: (widget.fontSize ?? 16.0) * 0.75,
              color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: _fractionButtons.entries.map((entry) {
            return ActionChip(
              label: Text(entry.key,
                  style: TextStyle(
                      fontSize: widget.fontSize != null
                          ? widget.fontSize! * 1.2
                          : 19.2)),
              backgroundColor: Colors.orange[50],
              onPressed: () {
                final newText = widget.controller.text + entry.key;
                widget.controller.text = newText;
                widget.onChanged?.call(newText);
              },
              tooltip: '${entry.key} = ${entry.value}',
            );
          }).toList(),
        ),
      ],
    );
  }
}

double? parseFractionString(String text) {
  if (text.isEmpty) return null;
  try {
    final mixedNumberPattern =
    RegExp(r'^(\d+)\s*([¼½¾⅓⅔⅕⅖⅗⅘⅙⅚⅐⅛⅜⅝⅞⅑⅒])$');
    final mixedMatch = mixedNumberPattern.firstMatch(text);
    if (mixedMatch != null) {
      final wholeNumber = double.parse(mixedMatch.group(1)!);
      final fractionChar = mixedMatch.group(2)!;
      const fractionMap = {
        '½': 0.5,   '⅓': 0.333, '⅔': 0.667, '¼': 0.25,  '¾': 0.75,
        '⅕': 0.2,   '⅖': 0.4,   '⅗': 0.6,   '⅘': 0.8,   '⅙': 0.167,
        '⅚': 0.833, '⅐': 0.143, '⅛': 0.125, '⅜': 0.375, '⅝': 0.625,
        '⅞': 0.875, '⅑': 0.111, '⅒': 0.1,
        '¾"': 0.75,  '1"': 1.0,   '1¼"': 1.25, '1½"': 1.5,
        '2"': 2.0,   '2¼"': 2.25, '2½"': 2.5,  '2¾"': 2.75,
        '3"': 3.0,   '3¼"': 3.25, '3½"': 3.5,  '3¾"': 3.75,
        '4"': 4.0,   '4¼"': 4.25, '5"': 5.0,   '5½"': 5.5,
        '6"': 6.0,
        '1': 1.0,    '1¼': 1.25,  '1½': 1.5,
        '2': 2.0,    '2¼': 2.25,  '2½': 2.5,   '2¾': 2.75,
        '3': 3.0,    '3¼': 3.25,  '3½': 3.5,   '3¾': 3.75,
        '4': 4.0,    '4¼': 4.25,  '5': 5.0,    '5½': 5.5,
        '6': 6.0,
      };
      return wholeNumber + (fractionMap[fractionChar] ?? 0);
    }

    final fractionPattern = RegExp(r'^(\d+)\s*\/\s*(\d+)$');
    final fractionMatch = fractionPattern.firstMatch(text);
    if (fractionMatch != null) {
      final numerator = double.parse(fractionMatch.group(1)!);
      final denominator = double.parse(fractionMatch.group(2)!);
      return denominator != 0 ? numerator / denominator : null;
    }

    final mixedFractionPattern = RegExp(r'^(\d+)\s+(\d+)\s*\/\s*(\d+)$');
    final mixedFractionMatch = mixedFractionPattern.firstMatch(text);
    if (mixedFractionMatch != null) {
      final wholeNumber = double.parse(mixedFractionMatch.group(1)!);
      final numerator = double.parse(mixedFractionMatch.group(2)!);
      final denominator = double.parse(mixedFractionMatch.group(3)!);
      return denominator != 0 ? wholeNumber + (numerator / denominator) : null;
    }

    return double.tryParse(text);
  } catch (e) {
    print('Error parsing fraction: $e');
    return null;
  }
}