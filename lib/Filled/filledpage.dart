import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mughal_group_branch_two/Filled/gatepasspage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../Models/itemModel.dart';
import '../Provider/customerprovider.dart';
import '../Provider/filled provider.dart';
import '../Provider/lanprovider.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:share_plus/share_plus.dart';
import 'dart:html' as html;
import '../bankmanagement/banknames.dart';


class filledpage extends StatefulWidget {
  final Map<String, dynamic>? filled;
  final bool isFromQuotation;

  const filledpage({
    Key? key,
    this.filled,
    this.isFromQuotation = false,
  }) : super(key: key);

  @override
  _filledpageState createState() => _filledpageState();
}


class _filledpageState extends State<filledpage> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  List<Item> _items = [];
  String? _selectedItemName;
  String? _selectedItemId;
  double _selectedItemRate = 0.0;
  String? _selectedCustomerName; // This should hold the name of the selected customer
  String? _selectedCustomerId;
  double _discount = 0.0; // Discount amount or percentage
  String _paymentType = 'udhaar';
  String? _instantPaymentMethod;
  TextEditingController _discountController = TextEditingController();
  List<Map<String, dynamic>> _filledRows = [];
  String? _filledId; // For editing existing filled
  bool _isReadOnly = false; // Initialize with default value
  bool _isButtonPressed = false;
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _rateController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  double _remainingBalance = 0.0; // Add this variable to store the remaining balance
  TextEditingController _paymentController = TextEditingController();
  TextEditingController _referenceController = TextEditingController();
  bool _isSaved = false;
  Map<String, dynamic>? _currentFilled;
  List<Map<String, dynamic>> _cachedBanks = [];
  double _mazdoori = 0.0;
  TextEditingController _mazdooriController = TextEditingController();
  String? _selectedBankId;
  String? _selectedBankName;
  TextEditingController _chequeNumberController = TextEditingController();
  DateTime? _selectedChequeDate;
  Map<String, Map<String, double>> _customerItemPrices = {};
  bool _isAutoReference = false;
  String _prefix = 'A';
  int _lastNumber = 0;
  final TextEditingController _autoReferenceController = TextEditingController();
  TextEditingController _biltiNumberController = TextEditingController();
  TextEditingController _transportCompanyController = TextEditingController();
  String? _selectedCustomerSerial;
  Map<String, int> _customerLastNumbers = {};
  String? _lastReferenceNumber;



  // Replace the _buildItemsSection method with this updated version:
  Widget _buildItemsSection(BuildContext context, LanguageProvider languageProvider,
      {required bool isMobile})
  {
    return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          color: Colors.green[700], size: 24),
                      const SizedBox(width: 8),
                      Text(
                        languageProvider.isEnglish ? 'Items' : 'آئٹمز',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.green[800],
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: _addNewRow,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(languageProvider.isEnglish
                        ? 'Add Item' : 'آئٹم شامل کریں'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Updated header with Total Weight column
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: Text(
                        languageProvider.isEnglish ? 'Size' : 'سائز',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                      ),
                    ),
                    Expanded(
                      // flex: 2,
                      child: Text(
                        languageProvider.isEnglish ? 'Length' : 'لمبائی',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        languageProvider.isEnglish ? 'Body Type' : 'باڈی قسم',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        languageProvider.isEnglish ? 'Description' : 'تفصیل',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        languageProvider.isEnglish ? 'Qty' : 'مقدار',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        languageProvider.isEnglish ? 'Weight/Unit' : 'وزن/یونٹ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // NEW COLUMN - Total Weight
                    Expanded(
                      child: Text(
                        languageProvider.isEnglish ? 'Total Wt' : 'کل وزن',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        languageProvider.isEnglish ? 'Calc' : 'حساب',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        languageProvider.isEnglish ? 'Rate' : 'ریٹ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        languageProvider.isEnglish ? 'Total' : 'کل',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _filledRows.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Item Name field
                      Expanded(
                        flex: 1,
                        child: CustomAutocomplete(
                          items: _items,
                          controller: _filledRows[index]['itemNameController'],
                          onSelected: (Item selectedItem) {
                            setState(() {
                              _filledRows[index]['itemName'] = selectedItem.itemName;
                            });

                            if (selectedItem.lengthBodyCombinations != null &&
                                selectedItem.lengthBodyCombinations!.isNotEmpty) {
                              _showLengthCombinationDialog(selectedItem, index);
                            } else {
                              _addItemToRow(selectedItem, index, null);
                            }
                          },
                          selectedCustomerId: _selectedCustomerId,
                          allowManualEntry: true,
                        ),
                      ),

                      // Length field
                      Expanded(
                        // flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: TextField(
                            controller: _filledRows[index]['lengthController'] ?? TextEditingController(),
                            decoration: InputDecoration(
                              hintText: languageProvider.isEnglish ? 'Length' : 'لمبائی',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            onChanged: (value) => _updateRow(index, 'length', value),
                          ),
                        ),
                      ),

                      // Body Type field
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: TextField(
                            controller: _filledRows[index]['bodyTypeController'] ?? TextEditingController(),
                            decoration: InputDecoration(
                              hintText: languageProvider.isEnglish ? 'Body Type' : 'باڈی قسم',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                            ),
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            onChanged: (value) => _updateRow(index, 'bodyType', value),
                          ),
                        ),
                      ),

                      // Description field
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: TextField(
                            controller: _filledRows[index]['descriptionController'],
                            decoration: InputDecoration(
                              hintText: languageProvider.isEnglish ? 'Description' : 'تفصیل',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            maxLines: 1,
                            onChanged: (value) => _updateRow(index, 'description', value),
                          ),
                        ),
                      ),

                      // Quantity field
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: TextField(
                            controller: _filledRows[index]['qtyController'],
                            decoration: InputDecoration(
                              hintText: languageProvider.isEnglish ? 'Qty' : 'مقدار',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            onChanged: (value) {
                              double qtyValue = double.tryParse(value) ?? 0.0;
                              _updateRow(index, 'qty', qtyValue);
                            },
                          ),
                        ),
                      ),

                      // Weight per Unit field (editable)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: TextField(
                            controller: _filledRows[index]['weightController'] ?? TextEditingController(),
                            decoration: InputDecoration(
                              hintText: languageProvider.isEnglish ? 'Wt/Unit' : 'وزن/یونٹ',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            keyboardType: TextInputType.number,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            onChanged: (value) {
                              _handleWeightPerUnitInput(index, value);
                            },
                          ),
                        ),
                      ),

                      // Total Weight (auto-calculated, read-only)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: TextField(
                            controller: TextEditingController(
                              text: _calculateDisplayTotalWeight(index),
                            ),
                            decoration: InputDecoration(
                              hintText: 'Total',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              filled: true,
                              fillColor: Colors.grey[100],
                            ),
                            readOnly: true,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[700],
                            ),
                          ),
                        ),
                      ),

                      // Calculation Type dropdown
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _filledRows[index]['calculationType'] ?? 'quantity',
                                isExpanded: true,
                                items: [
                                  DropdownMenuItem(
                                    value: 'quantity',
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text(
                                        'Qty×Rate',
                                        style: TextStyle(fontSize: 12),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'weight',
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text(
                                        'TotalWt×Rate',
                                        style: TextStyle(fontSize: 12),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (String? value) {
                                  if (value != null) {
                                    _updateRow(index, 'calculationType', value);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Rate field
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: TextField(
                            controller: _filledRows[index]['rateController'],
                            decoration: InputDecoration(
                              hintText: languageProvider.isEnglish ? 'Rate' : 'ریٹ',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            onChanged: (value) {
                              double rateValue = double.tryParse(value) ?? 0.0;
                              _updateRow(index, 'rate', rateValue);
                            },
                          ),
                        ),
                      ),

                      // Total field
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: TextField(
                            controller: TextEditingController(
                              text: (_filledRows[index]['total'] ?? 0.0).toStringAsFixed(2),
                            ),
                            decoration: InputDecoration(
                              hintText: languageProvider.isEnglish ? 'Total' : 'کل',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            readOnly: true,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),

                      // Delete button
                      SizedBox(
                        width: 40,
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () => _deleteRow(index),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _addNewRow,
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(languageProvider.isEnglish ? 'Add More Items' : 'مزید آئٹمز شامل کریں'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
        )
    );
  }

// NEW HELPER METHOD - Add this to your _QuotationPageState class
  String _calculateDisplayTotalWeight(int index) {
    double qty = _filledRows[index]['qty'] ?? 0.0;
    double? weightPerUnit = _filledRows[index]['weightPerUnit'];
    String weightUnit = _filledRows[index]['weightUnit'] ?? 'kg';

    if (qty > 0 && weightPerUnit != null && weightPerUnit > 0) {
      double totalWeight = qty * weightPerUnit;
      return '${totalWeight.toStringAsFixed(2)} $weightUnit';
    }

    // Check if we have a pre-calculated total weight
    double? totalWeight = _filledRows[index]['totalWeight'];
    if (totalWeight != null && totalWeight > 0) {
      return '${totalWeight.toStringAsFixed(2)} $weightUnit';
    }

    return 'N/A';
  }

  void _handleWeightPerUnitInput(int index, String value) {
    if (value.isEmpty) {
      setState(() {
        _filledRows[index]['weightPerUnit'] = null;
        _filledRows[index]['totalWeight'] = null;
      });
      _calculateTotalForRow(index);
      return;
    }

    // Parse weight value and unit
    final parts = value.trim().split(' ');
    double? weightValue;
    String weightUnit = _filledRows[index]['weightUnit'] ?? 'kg';

    if (parts.isNotEmpty) {
      weightValue = double.tryParse(parts[0]);

      // Try to extract unit if provided
      if (parts.length > 1) {
        final unit = parts.sublist(1).join(' ').toLowerCase();
        if (unit.contains('kg') || unit.contains('kilogram')) {
          weightUnit = 'kg';
        } else if (unit.contains('g') || unit.contains('gram')) {
          weightUnit = 'g';
        } else if (unit.contains('lb') || unit.contains('pound')) {
          weightUnit = 'lb';
        } else if (unit.contains('ton')) {
          weightUnit = 'ton';
        }
      }
    }

    if (weightValue != null && weightValue > 0) {
      // Calculate total weight
      double qty = _filledRows[index]['qty'] ?? 0.0;
      double calculatedTotalWeight = weightValue * qty;

      setState(() {
        _filledRows[index]['weightPerUnit'] = weightValue;
        _filledRows[index]['weightUnit'] = weightUnit;
        _filledRows[index]['totalWeight'] = calculatedTotalWeight;

        // Update the total weight display
        if (_filledRows[index]['totalWeightController'] == null) {
          _filledRows[index]['totalWeightController'] = TextEditingController();
        }
        _filledRows[index]['totalWeightController']?.text = '${calculatedTotalWeight.toStringAsFixed(2)} $weightUnit';
      });

      _calculateTotalForRow(index);
    } else {
      setState(() {
        _filledRows[index]['weightPerUnit'] = null;
        _filledRows[index]['totalWeight'] = null;
      });
      _calculateTotalForRow(index);
    }
  }

  void _calculateTotalForRow(int index) {
    double rate = _filledRows[index]['rate'] ?? 0.0;
    double qty = _filledRows[index]['qty'] ?? 0.0;
    String calculationType = _filledRows[index]['calculationType'] ?? 'quantity';
    double? weightPerUnit = _filledRows[index]['weightPerUnit'];
    String weightUnit = _filledRows[index]['weightUnit'] ?? 'kg';

    // Calculate total weight (Qty × Weight per Unit)
    double? totalWeight;
    if (weightPerUnit != null && weightPerUnit > 0 && qty > 0) {
      totalWeight = weightPerUnit * qty;
      _filledRows[index]['totalWeight'] = totalWeight;
    } else {
      // Try to preserve existing totalWeight if it exists
      totalWeight = _filledRows[index]['totalWeight'];
    }

    double total = 0.0;

    if (calculationType == 'weight') {
      // Weight-based calculation: Use Total Weight × Rate
      if (totalWeight != null && totalWeight > 0) {
        total = rate * totalWeight;
      } else {
        // Fallback to quantity if no weight available
        total = rate * qty;
      }
    } else {
      // Quantity-based calculation: Qty × Rate
      total = rate * qty;
    }

    _filledRows[index]['total'] = total;
    setState(() {});
  }

  Future<String> _generateCustomerSerialReference({bool increment = true}) async {
    if (_selectedCustomerId == null || _selectedCustomerSerial == null) {
      return 'Unknown-0001';
    }

    // Get the last used number for this customer from Firebase
    final counterRef = _db.child('customerReferenceCounters').child(_selectedCustomerId!);
    final snapshot = await counterRef.get();

    int lastNumber = 0;
    if (snapshot.exists) {
      final data = snapshot.value;
      lastNumber = (data is int) ? data : (data as Map?)?['lastNumber'] ?? 0;
    }

    if (increment) {
      lastNumber++;
    }

    // Save the new counter value only if incrementing
    if (increment) {
      await counterRef.set(lastNumber);
    }

    return '${_selectedCustomerSerial}-${lastNumber.toString().padLeft(4, '0')}';
  }

  Future<void> _toggleReferenceMode(bool isAuto) async {
    setState(() {
      _isAutoReference = isAuto;
    });

    if (isAuto && _selectedCustomerId != null && _selectedCustomerSerial != null) {
      // Generate without incrementing the counter
      final autoRef = await _generateNextReferenceNumber(increment: false);
      _autoReferenceController.text = autoRef;
      _referenceController.text = autoRef;
    } else if (!isAuto) {
      _referenceController.text = '';
    }
  }

  Future<void> _onCustomerChanged() async {
    if (_isAutoReference && _selectedCustomerId != null && _selectedCustomerSerial != null) {
      final autoRef = await _generateNextReferenceNumber(increment: false);
      setState(() {
        _autoReferenceController.text = autoRef;
        _referenceController.text = autoRef;
      });
    }
  }

  void _fetchCustomerPrices(String customerId) async {
    final DatabaseReference pricesRef = FirebaseDatabase.instance.ref().child('items');
    final DatabaseEvent snapshot = await pricesRef.once();

    if (snapshot.snapshot.exists) {
      final Map<dynamic, dynamic> itemsMap = snapshot.snapshot.value as Map<dynamic, dynamic>;
      Map<String, Map<String, double>> prices = {};

      itemsMap.forEach((itemId, itemData) {
        final item = itemData as Map<dynamic, dynamic>;
        if (item['customerBasePrices'] != null) {
          final customerPrices = item['customerBasePrices'] as Map<dynamic, dynamic>;
          if (customerPrices.containsKey(customerId)) {
            final price = double.tryParse(customerPrices[customerId].toString()) ?? 0.0;
            if (!prices.containsKey(itemId)) {
              prices[itemId] = {};
            }
            prices[itemId]![customerId] = price;
          }
        }
      });

      setState(() {
        _customerItemPrices = prices;
      });
    }
  }

  Future<void> _fetchRemainingBalance() async {
    if (_selectedCustomerId != null) {
      try {
        final balance = await _getRemainingBalance(_selectedCustomerId!);
        setState(() {
          _remainingBalance = balance;
        });
      } catch (e) {
        setState(() {
          _remainingBalance = 0.0; // Set a default value in case of error
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch remaining balance: $e')),
        );
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dateController.text.isNotEmpty
          ? DateTime.parse(_dateController.text)
          : DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  void _addNewRow() {
    setState(() {
      _filledRows.add({
        'total': 0.0,
        'rate': 0.0,
        'qty': 0.0,
        'size': '',
        'length': '',
        'bodyType': '',
        'description': '',
        'itemName': '',
        'calculationType': 'quantity',
        'weightPerUnit': null,
        'weightUnit': 'kg',
        'totalWeight': 0.0,
        'manualWeightEntry': false,
        'itemNameController': TextEditingController(),
        'sizeController': TextEditingController(),
        'lengthController': TextEditingController(),
        'bodyTypeController': TextEditingController(),
        'rateController': TextEditingController(),
        'qtyController': TextEditingController(),
        'descriptionController': TextEditingController(),
        'weightController': TextEditingController(),
      });
    });
  }

  void _updateRow(int index, String field, dynamic value) {
    setState(() {
      _filledRows[index][field] = value;

      // Recalculate total when any of these fields change
      if (field == 'rate' || field == 'qty' || field == 'calculationType' ||
          field == 'weightPerUnit' || field == 'lengthBodyCombination') {
        _calculateTotalForRow(index);
      }
    });
  }


  void _deleteRow(int index) {
    setState(() {
      final deletedRow = _filledRows[index];
      // Dispose all controllers for the deleted row
      deletedRow['itemNameController']?.dispose();
      deletedRow['sizeController']?.dispose();
      deletedRow['lengthController']?.dispose();
      deletedRow['bodyTypeController']?.dispose();
      deletedRow['rateController']?.dispose();
      deletedRow['qtyController']?.dispose();
      deletedRow['descriptionController']?.dispose();
      deletedRow['weightController']?.dispose();
      deletedRow['totalWeightController']?.dispose(); // Add this line
      _filledRows.removeAt(index);
    });
  }

  double _calculateSubtotal() {
    return _filledRows.fold(0.0, (sum, row) => sum + (row['total'] ?? 0.0));
  }

  double _calculateGrandTotal() {
    double subtotal = _calculateSubtotal();
    // Apply discount (subtract from subtotal)
    double afterDiscount = subtotal - _discount;
    // Add labor charges
    return afterDiscount + _mazdoori;
  }

  Future<Uint8List> _generatePDFBytes(String filledNumber) async {
    final pdf = pw.Document();

    // ── Providers ────────────────────────────────────────────────
    final customerProvider =
    Provider.of<CustomerProvider>(context, listen: false);
    final filledProvider =
    Provider.of<FilledProvider>(context, listen: false);

    final filled = widget.filled ?? _currentFilled;
    if (filled == null) throw Exception('No invoice data available');

    // ── Filter empty rows ─────────────────────────────────────────
    final nonEmptyRows = _filledRows
        .where((row) => (row['itemName'] as String).isNotEmpty)
        .toList();

    // ── Pre-render Size & Length as PNG images ────────────────────
    // Flutter's own canvas handles ½ ¼ ¾ etc. perfectly — the PDF
    // renderer just sees opaque PNG images, no font issues at all.
    final List<Uint8List> sizeImages = [];
    final List<Uint8List> lengthImages = [];

    for (final row in nonEmptyRows) {
      final sizeText   = row['size']?.toString()   ?? '';
      final lengthText = row['length']?.toString() ?? '';

      sizeImages.add(await _renderTextAsImage(
        sizeText.isNotEmpty ? sizeText : '-',
        width: 70, height: 24,
      ));
      lengthImages.add(await _renderTextAsImage(
        lengthText.isNotEmpty ? lengthText : '-',
        width: 70, height: 24,
      ));
    }

    // ── Payments ──────────────────────────────────────────────────
    double paidAmount = 0.0;
    try {
      final payments =
      await filledProvider.getFilledPayments(filled['filledNumber']);
      paidAmount = payments.fold(
          0.0, (sum, p) => sum + (_parseToDouble(p['amount']) ?? 0.0));
    } catch (e) {
      print('Payment fetch error: $e');
    }

    final double grandTotal = _calculateGrandTotal();
    final double remainingAmount = grandTotal - paidAmount;

    // ── Ledger balance ────────────────────────────────────────────
    double totalRemainingBalance = 0.0;
    if (_selectedCustomerId != null) {
      try {
        totalRemainingBalance =
        await _getRemainingBalance(_selectedCustomerId!);
      } catch (e) {
        print('Balance fetch error: $e');
      }
    }
    final double previousBalance = totalRemainingBalance - remainingAmount;

    if (_selectedCustomerId == null) throw Exception('No customer selected');

    final selectedCustomer = customerProvider.customers.firstWhere(
          (c) => c.id == _selectedCustomerId,
      orElse: () => Customer(
        id: 'unknown', name: 'Unknown', phone: '', address: '', city: '',
      ),
    );

    // ── Date ──────────────────────────────────────────────────────
    DateTime filledDate;
    if (widget.filled != null) {
      filledDate = DateTime.parse(widget.filled!['createdAt']);
    } else if (_dateController.text.isNotEmpty) {
      final d   = DateTime.parse(_dateController.text);
      final now = DateTime.now();
      filledDate = DateTime(d.year, d.month, d.day, now.hour, now.minute, now.second);
    } else {
      filledDate = DateTime.now();
    }

    final formattedDate =
        '${filledDate.day}/${filledDate.month}/${filledDate.year}';
    final formattedTime =
        '${filledDate.hour}:${filledDate.minute.toString().padLeft(2, '0')}';

    // ── Assets ───────────────────────────────────────────────────
    Uint8List? logoBytes;
    try {
      final ByteData logoData =
      await rootBundle.load('assets/images/logo.png');
      logoBytes = logoData.buffer.asUint8List();
    } catch (_) {}

    final lineImage = pw.MemoryImage(
        (await rootBundle.load('assets/images/line.png'))
            .buffer.asUint8List());
    final footerLogo = pw.MemoryImage(
        (await rootBundle.load('assets/images/devlogo.png'))
            .buffer.asUint8List());
    final jazzcashLogo = pw.MemoryImage(
        (await rootBundle.load('assets/images/jazzcashlogo.png'))
            .buffer.asUint8List());
    final ublLogo = pw.MemoryImage(
        (await rootBundle.load('assets/images/ubl.png'))
            .buffer.asUint8List());

    // ── Totals ────────────────────────────────────────────────────
    final totalQty = nonEmptyRows.fold<double>(
        0.0, (s, r) => s + (_parseToDouble(r['qty']) ?? 0.0));

    final totalWeight = nonEmptyRows.fold<double>(0.0, (s, r) {
      final weight      = r['totalWeight']   ?? 0.0;
      final qty         = r['qty']           ?? 0.0;
      final weightPerUnit = r['weightPerUnit'] ?? 0.0;
      if (r['calculationType'] == 'weight' && weight > 0) return s + weight;
      if (weightPerUnit > 0) return s + (weightPerUnit * qty);
      return s;
    });

    // ── Build PDF ─────────────────────────────────────────────────
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(10),

        // ── HEADER (first page only) ─────────────────────────────
        header: (context) {
          if (context.pageNumber != 1) return pw.SizedBox();
          return pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  // Logo
                  logoBytes != null
                      ? pw.Container(
                    width: 80, height: 80,
                    child: pw.Image(pw.MemoryImage(logoBytes)),
                  )
                      : pw.Container(
                    width: 80, height: 80,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.orangeAccent,
                      borderRadius: pw.BorderRadius.circular(40),
                    ),
                    child: pw.Center(
                      child: pw.Text('MGI',
                          style: pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white)),
                    ),
                  ),

                  // Company info
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('MUGHAL GROUP OF INDUSTRIES',
                          style: pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue800)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                          'Specialist in Bolt, Nut, Washer & Soft/Hard Steel Wire.\n All Sizes Available | Custom Manufacturing | Factory Rate',
                          style: pw.TextStyle(
                              fontSize: 12, color: PdfColors.grey700)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                          'Address: Gujranwala, Pakistan',
                          style: pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey600)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                          'Phone: 03704219219 / 03713084600 | Email: mughalgroupofindustrie@gmil.com',
                          style: pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey600)),
                    ],
                  ),

                  // Ref box
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.orangeAccent,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(children: [
                      pw.Text('Ref #',
                          style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                          '#${_referenceController.text.isNotEmpty ? _referenceController.text : 'Q${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}'}',
                          style: pw.TextStyle(
                              fontSize: 12, color: PdfColors.white)),
                    ]),
                  ),
                ],
              ),
              pw.Divider(),
            ],
          );
        },

        // ── FOOTER (last page only) ──────────────────────────────
        footer: (context) {
          if (context.pageNumber != context.pagesCount) return pw.SizedBox();

          return pw.Column(
            children: [
              // Footer Note
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Container(
                    padding: pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.orange50,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          'Thank you for your business!',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.orange800,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'For any queries, please contact us at 03704219219 / 03713084600 or email at mughalgroupofindustrie@gmil.com',
                          style: pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey700,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.Divider(),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Text(
                        'Developed By: Tech Soft',
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        '0341-6426617',
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                  pw.Image(lineImage, width: 150, height: 50),

                  pw.Image(footerLogo, width: 50, height: 40),

                ],
              ),
            ],
          );
        },

        // ── BODY ─────────────────────────────────────────────────
        build: (context) => [
          // Customer + invoice meta
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Customer Name: ${selectedCustomer.name}',
                      style: const pw.TextStyle(fontSize: 11)),
                  pw.Text('Customer Address: ${selectedCustomer.address}',
                      style: const pw.TextStyle(fontSize: 11)),
                  pw.Text('Customer Number: ${selectedCustomer.phone}',
                      style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
              pw.Column(children: [
                pw.Text('Date: $formattedDate $formattedTime',
                    style: const pw.TextStyle(fontSize: 10)),
                pw.Text('Invoice #: $filledNumber',
                    style: const pw.TextStyle(fontSize: 12)),
                pw.Text('Bilti Number: ${_biltiNumberController.text}',
                    style: const pw.TextStyle(fontSize: 11)),
                pw.Text(
                    'Transport Company: ${_transportCompanyController.text}',
                    style: const pw.TextStyle(fontSize: 11)),
              ]),
            ],
          ),
          pw.Divider(),
          pw.SizedBox(height: 10),

          // ── Items table (manual pw.Table so we can embed images) ──
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: const {
              // 0: pw.FlexColumnWidth(2.5), // Item Name
              0: pw.FlexColumnWidth(1.8), // Size   ← image
              1: pw.FlexColumnWidth(1.8), // Length ← image
              2: pw.FlexColumnWidth(1.5), // Body Type
              3: pw.FlexColumnWidth(2.5), // Description
              4: pw.FlexColumnWidth(1.0), // Qty
              5: pw.FlexColumnWidth(1.5), // Weight
              6: pw.FlexColumnWidth(1.5), // Rate
              7: pw.FlexColumnWidth(1.5), // Total
            },
            children: [
              // ── Header row ──────────────────────────────────────
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  // 'Item Name',
                  'Size',
                  'Length',
                  'Body Type',
                  'Description',
                  'Qty',
                  'Weight',
                  'Rate',
                  'Total',
                ].map(_hcell).toList(),
              ),

              // ── Data rows ───────────────────────────────────────
              ...List.generate(nonEmptyRows.length, (i) {
                final r = nonEmptyRows[i];

                // Weight display text
                String weightText = '';
                if (r['calculationType'] == 'weight') {
                  if ((r['totalWeight'] ?? 0.0) > 0) {
                    weightText =
                    '${(r['totalWeight'] as double).toStringAsFixed(2)} ${r['weightUnit'] ?? 'kg'}';
                  } else if ((r['weightPerUnit'] ?? 0.0) > 0) {
                    final w =
                    (r['weightPerUnit'] * (r['qty'] ?? 1)).toStringAsFixed(2);
                    weightText = '$w ${r['weightUnit'] ?? 'kg'}';
                  }
                }

                // Alternate row shading
                final bg = i % 2 == 0 ? PdfColors.white : PdfColors.grey100;

                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: bg),
                  children: [
                    // Item Name — plain text (no fraction chars expected)
                    // _cell(r['itemName'] ?? ''),

                    // ── SIZE as image ──────────────────────────────
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Image(
                        pw.MemoryImage(sizeImages[i]),
                        width: 60, height: 20,
                        fit: pw.BoxFit.contain,
                      ),
                    ),

                    // ── LENGTH as image ────────────────────────────
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Image(
                        pw.MemoryImage(lengthImages[i]),
                        width: 60, height: 20,
                        fit: pw.BoxFit.contain,
                      ),
                    ),

                    // Body Type — plain text
                    _cell(r['bodyType']?.toString() ?? ''),

                    // Description — plain text
                    _cell(r['description']?.toString() ?? ''),

                    // Qty
                    _cell((r['qty'] ?? '0').toString()),

                    // Weight
                    _cell(weightText),

                    // Rate
                    _cell((r['rate'] ?? 0).toStringAsFixed(2),
                        align: pw.Alignment.centerRight),

                    // Total
                    _cell((r['total'] ?? 0).toStringAsFixed(2),
                        align: pw.Alignment.centerRight),
                  ],
                );
              }),

              // ── Totals row ──────────────────────────────────────
              pw.TableRow(
                decoration:
                const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _hcell('Total'),
                  // _hcell(''), // Size (image col)
                  _hcell(''), // Length (image col)
                  _hcell(''), // Body Type
                  _hcell(''), // Description
                  _hcell(totalQty.toStringAsFixed(0)),
                  _hcell('${totalWeight.toStringAsFixed(2)} kg'),
                  _hcell(''),
                  _hcell(_calculateSubtotal().toStringAsFixed(2)),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 10),

          // ── Financial summary rows ────────────────────────────
          _totalRow('Invoice Amount', grandTotal),
          _totalRow('Previous Balance', previousBalance,
              highlight: previousBalance > 0),
          _totalRow('Discount', _discount),
          // _totalRow('Labor Charges', _mazdoori),
          _totalRow('Total Remaining Balance', totalRemainingBalance,
              highlight: totalRemainingBalance > 0),

          if (paidAmount > 0) ...[
            pw.SizedBox(height: 10),
            _totalRow('Paid Amount', paidAmount, highlight: true),
            _totalRow('Balance Due', remainingAmount,
                highlight: remainingAmount > 0),
          ],
        ],
      ),
    );

    return pdf.save();
  }


// Helper methods remain the same
  pw.Widget _hcell(String t) => pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Text(t,
        style:
        pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
  );

  pw.Widget _cell(String t,
      {pw.Alignment align = pw.Alignment.centerLeft}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Align(
            alignment: align,
            child: pw.Text(t, style: const pw.TextStyle(fontSize: 10))),
      );

  pw.Widget _totalRow(String label, double value,
      {bool highlight = false}) =>
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style:
              pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Text(value.toStringAsFixed(2),
              style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: highlight ? PdfColors.red : PdfColors.black)),
        ],
      );


  Future<Uint8List> _renderTextAsImage(
      String text, {
        double fontSize = 18,
        double width = 80,
        double height = 26,
      })
  async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // White background
    final bgPaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

    // Draw text using ui.TextDirection to avoid conflict with material TextDirection
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF000000),
          fontSize: fontSize,
          fontFamily: null, // system font — supports Unicode fractions
        ),
      ),
      textDirection: ui.TextDirection.ltr, // <-- ui. prefix avoids the conflict
      maxLines: 1,
    );
    textPainter.layout(maxWidth: width - 4);
    textPainter.paint(
      canvas,
      Offset(2, (height - textPainter.height) / 2),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _generateAndPrintPDF() async {
    String filledNumber;
    if (widget.filled != null) {
      filledNumber = widget.filled!['filledNumber'];
    } else {
      final filledProvider = Provider.of<FilledProvider>(context, listen: false);
      filledNumber = (await filledProvider.getNextFilledNumber()).toString();
    }

    try {
      final bytes = await _generatePDFBytes(filledNumber);
      await Printing.layoutPdf(onLayout: (format) => bytes);
    } catch (e) {
      print("Error printing: $e");
    }
  }

  Future<double> _getRemainingBalance(String customerId) async {
    try {
      double totalCredit = 0.0;
      double totalDebit = 0.0;

      final filledLedgerRef = _db.child('filledledger').child(customerId);
      final snapshot = await filledLedgerRef.get();

      if (!snapshot.exists) {
        return 0.0; // No transactions yet
      }

      final Map<dynamic, dynamic> ledgerData = snapshot.value as Map<dynamic, dynamic>;

      // Iterate through all ledger entries and sum credits and debits
      ledgerData.forEach((key, value) {
        if (value != null) {
          final entry = value as Map<dynamic, dynamic>;
          final credit = _parseToDouble(entry['creditAmount']);
          final debit = _parseToDouble(entry['debitAmount']);

          totalCredit += credit;
          totalDebit += debit;
        }
      });

      // Remaining balance = Total Credit - Total Debit
      final remainingBalance = totalCredit - totalDebit;

      print('Balance Calculation for Customer $customerId:');
      print('Total Credit: $totalCredit');
      print('Total Debit: $totalDebit');
      print('Remaining Balance: $remainingBalance');

      return remainingBalance;
    } catch (e) {
      print("Error calculating remaining balance: $e");
      return 0.0;
    }
  }

  Future<List<Item>> fetchItems() async {
    final DatabaseReference itemsRef = FirebaseDatabase.instance.ref().child('items');
    final DatabaseEvent snapshot = await itemsRef.once();

    if (snapshot.snapshot.exists) {
      final Map<dynamic, dynamic> itemsMap = snapshot.snapshot.value as Map<dynamic, dynamic>;
      return itemsMap.entries.map((entry) {
        return Item.fromMap(entry.value as Map<dynamic, dynamic>, entry.key as String);
      }).toList();
    } else {
      return [];
    }
  }

  Future<void> _fetchItems() async {
    final items = await fetchItems();
    setState(() {
      _items = items;
    });
  }


  Future<void> _updateQtyOnHand(List<Map<String, dynamic>> rows) async {
    try {
      for (var row in rows) {
        final String itemName = row['itemName'] ?? '';
        if (itemName.isEmpty) continue;

        final dbItem = _items.firstWhere(
              (i) => i.itemName == itemName,
          orElse: () => Item(
              id: '',
              itemName: '',
              qtyOnHand: 0.0,
              avgCostPricePerKg: 0.0,
              avgSalePricePerKg: 0.0),
        );
        if (dbItem.id.isEmpty) continue;

        // ── How much weight to deduct (top-level) ──────────────────────────
        double weightToDeduct = 0.0;
        if (row['calculationType'] == 'weight') {
          final double tw = (row['totalWeight'] ?? 0.0) as double;
          final String unit = row['weightUnit'] ?? 'kg';
          weightToDeduct = unit == 'g'
              ? tw / 1000
              : unit == 'ton'
              ? tw * 1000
              : unit == 'lb'
              ? tw * 0.453592
              : tw;
        } else {
          weightToDeduct = (row['qty'] ?? 0.0) as double;
        }

        final double initialWeight =
        (row['initialWeight'] ?? weightToDeduct) as double;

        // delta > 0  → restore stock (editing/deleting)
        // delta < 0  → deduct stock (new invoice)
        double delta = initialWeight - weightToDeduct;
        final bool isExistingInvoice = widget.filled != null &&
            widget.filled!['filledNumber'] != null &&
            !(widget.filled!['isFromQuotation'] ?? false);
        if (isExistingInvoice) delta = -delta;

        // ── 1. Top-level qtyOnHand ──────────────────────────────────────────
        final double updatedQty = dbItem.qtyOnHand + delta;
        await _db
            .child('items/${dbItem.id}')
            .update({'qtyOnHand': updatedQty});

        // ── 2. Per-combination stockQuantity ───────────────────────────────
        final String rowLength = (row['length'] ?? '').toString().trim();
        final String rowBodyType = (row['bodyType'] ?? '').toString().trim();

        if (rowLength.isNotEmpty && rowBodyType.isNotEmpty) {
          await _updateCombinationStockInDb(
              dbItem.id, rowLength, rowBodyType, delta);
        }
      }
    } catch (e) {
      print('Error updating qtyOnHand: $e');
    }
  }

// ─── SHARED HELPER ──────────────────────────────────────────────────────────
  Future<void> _updateCombinationStockInDb(
      String itemId, String length, String bodyType, double delta) async {
    final snap =
    await _db.child('items/$itemId/lengthBodyCombinations').get();
    if (!snap.exists) return;

    final List<dynamic> raw = snap.value as List<dynamic>;
    for (int i = 0; i < raw.length; i++) {
      if (raw[i] == null) continue;
      final combo = Map<String, dynamic>.from(raw[i]);
      if (combo['length']?.toString().trim() == length &&
          combo['bodyType']?.toString().trim() == bodyType) {
        final double current =
            (combo['stockQuantity'] as num?)?.toDouble() ?? 0.0;
        await _db
            .child('items/$itemId/lengthBodyCombinations/$i')
            .update({'stockQuantity': current + delta});
        return;
      }
    }
    print('⚠️ Combination "$length/$bodyType" not found for item $itemId');
  }


  Future<void> _showDeletePaymentConfirmationDialog(
      BuildContext context,
      String filledId,
      String paymentKey,
      String paymentMethod,
      double paymentAmount,
      )
  async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(languageProvider.isEnglish ? 'Delete Payment' : 'ادائیگی ڈیلیٹ کریں'),
          content: Text(languageProvider.isEnglish
              ? 'Are you sure you want to delete this payment?'
              : 'کیا آپ واقعی اس ادائیگی کو ڈیلیٹ کرنا چاہتے ہیں؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(languageProvider.isEnglish ? 'Cancel' : 'رد کریں'),
            ),
            TextButton(
              onPressed: () async {
                print('Deleting');
                try {
                  await Provider.of<FilledProvider>(context, listen: false).deletePaymentEntry(
                    context: context, // Pass the context here
                    filledId: filledId,
                    paymentKey: paymentKey,
                    paymentMethod: paymentMethod,
                    paymentAmount: paymentAmount,
                  );
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Payment deleted successfully.')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete payment: ${e.toString()}')),
                  );
                }
              },
              child: Text(languageProvider.isEnglish ? 'Delete' : 'ڈیلیٹ کریں'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showFullScreenImage(Uint8List imageBytes) async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.memory(imageBytes, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  double _parseToDouble(dynamic value) {
    if (value is int) {
      return value.toDouble();
    } else if (value is double) {
      return value;
    } else if (value is String) {
      return double.tryParse(value) ?? 0.0;
    } else {
      return 0.0;
    }
  }

  DateTime _parsePaymentDate(dynamic date) {
    if (date is String) {
      // If the date is a string, try parsing it directly
      return DateTime.tryParse(date) ?? DateTime.now();
    } else if (date is int) {
      // If the date is a timestamp (in milliseconds), convert it to DateTime
      return DateTime.fromMillisecondsSinceEpoch(date);
    } else if (date is DateTime) {
      // If the date is already a DateTime object, return it directly
      return date;
    } else {
      // Fallback to the current date if the format is unknown
      return DateTime.now();
    }
  }

  Future<void> _showPaymentDetails(Map<String, dynamic> filled) async {
    final filledProvider = Provider.of<FilledProvider>(context, listen: false);
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    try {
      final payments = await filledProvider.getFilledPayments(filled['filledNumber']);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(languageProvider.isEnglish ? 'Payment History' : 'ادائیگی کی تاریخ'),
          content: Container(
            width: double.maxFinite,
            child: payments.isEmpty
                ? Text(languageProvider.isEnglish
                ? 'No payments found'
                : 'کوئی ادائیگی نہیں ملی')
                : ListView.builder(
              shrinkWrap: true,
              itemCount: payments.length,
              itemBuilder: (context, index) {
                final payment = payments[index];
                Uint8List? imageBytes;
                if (payment['image'] != null) {
                  imageBytes = base64Decode(payment['image']);
                }

                // Determine payment method display text
                String paymentMethodText;
                if (payment['method'] == 'Bank') {
                  paymentMethodText = '${payment['bankName'] ?? 'Bank'}';
                }
                else if (payment['method'] == 'Cheque') {
                  paymentMethodText = 'Cheque (${payment['status'] ?? 'pending'})';
                }
                else {
                  paymentMethodText = payment['method'];
                }

                return Card(
                  child: ListTile(
                    title: Text(
                      '$paymentMethodText: Rs ${payment['amount']}',
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(DateFormat('yyyy-MM-dd – HH:mm')
                            .format(payment['date'])),
                        if (payment['description'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(payment['description']),
                          ),
                        if (payment['method'] == 'Cheque')
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Cheque #${payment['chequeNumber']} - ${payment['status']}',
                              style: TextStyle(
                                color: payment['status'] == 'cleared'
                                    ? Colors.green
                                    : payment['status'] == 'bounced'
                                    ? Colors.red
                                    : Colors.orange,
                              ),
                            ),
                          ),
                        if (imageBytes != null)
                          Column(
                            children: [
                              GestureDetector(
                                onTap: () => _showFullScreenImage(imageBytes!),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Hero(
                                    tag: 'paymentImage$index',
                                    child: Image.memory(
                                      imageBytes,
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => _showFullScreenImage(imageBytes!),
                                child: Text(
                                  Provider.of<LanguageProvider>(context, listen: false)
                                      .isEnglish
                                      ? 'View Full Image'
                                      : 'مکمل تصویر دیکھیں',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    trailing: payment['method'] != 'Cheque' || payment['status'] != 'cleared'
                        ? null
                        : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _showDeletePaymentConfirmationDialog(
                            context,
                            filled['filledNumber'],
                            payment['key'],
                            payment['method'],
                            payment['amount'],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => _printPaymentHistoryPDF(payments, context),
              child: Text(languageProvider.isEnglish ? 'Print Payment History' : 'ادائیگی کی تاریخ پرنٹ کریں'),
            ),
            TextButton(
              child: Text(languageProvider.isEnglish ? 'Close' : 'بند کریں'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading payments: ${e.toString()}')),
      );
    }
  }

  Future<void> _printPaymentHistoryPDF(List<Map<String, dynamic>> payments, BuildContext context) async {
    final pdf = pw.Document();
    // Load the image asset for the logo
    final ByteData bytes = await rootBundle.load('assets/images/logo.png');
    final buffer = bytes.buffer.asUint8List();
    final image = pw.MemoryImage(buffer);

    // Load the footer logo if different
    final ByteData footerBytes = await rootBundle.load('assets/images/devlogo.png');
    final footerBuffer = footerBytes.buffer.asUint8List();
    final footerLogo = pw.MemoryImage(footerBuffer);

    // Generate all description images asynchronously
    final List<List<dynamic>> tableData = await Future.wait(
      payments.map((payment) async {
        final paymentAmount = _parseToDouble(payment['amount']);
        final paymentDate = _parsePaymentDate(payment['date']);
        final description = payment['description'] ?? 'N/A';
        // DateFormat('yyyy-MM-dd – HH:mm').format(paymentDate);

        // Generate image from description text
        final descriptionImage = await _createTexttoImage(description);

        return [
          payment['method'],
          'Rs ${paymentAmount.toStringAsFixed(2)}',
          DateFormat('yyyy-MM-dd – HH:mm').format(paymentDate),
          pw.Image(descriptionImage), // Use the generated image
        ];
      }),
    );

    // Add a multi-page layout to handle multiple payments
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) => [
          // Header section
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Image(image, width: 80, height: 80), // Adjust logo size
              pw.Text('Payment History',
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            ],
          ),

          // Table with payment history
          pw.Table.fromTextArray(
            headers: ['Method', 'Amount', 'Date', 'Description'],
            // data: tableData,
            data: payments.map((payment) {
              return [
                payment['method'] == 'Bank'
                    ? 'Bank: ${payment['bankName'] ?? 'Bank'}'
                    : payment['method'],
                'Rs ${_parseToDouble(payment['amount']).toStringAsFixed(2)}',
                DateFormat('yyyy-MM-dd – HH:mm').format(_parsePaymentDate(payment['date'])),
                payment['description'] ?? 'N/A',
              ];
            }).toList(),
            border: pw.TableBorder.all(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 14, // Increased header font size
            ),
            cellStyle: const pw.TextStyle(
              fontSize: 12, // Increased cell font size from 10 to 12
            ),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(6),
          ),

          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.Spacer(),
          // Footer section
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    'Umair Arshad',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    '0341-6426617 - 0307-6455926',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.Image(footerLogo, width: 20, height: 20), // Footer logo
            ],
          ),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
          ),
        ],
      ),
    );

    // Print the PDF
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  Future<Uint8List?> _pickImage(BuildContext context) async {
    Uint8List? imageBytes;
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    if (kIsWeb) {
      // For web, use file_picker
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        imageBytes = result.files.first.bytes;
      }
    } else {
      // For mobile, show source selection dialog
      final ImagePicker _picker = ImagePicker();

      // Show dialog to choose camera or gallery
      final ImageSource? source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(languageProvider.isEnglish ? 'Select Source' : 'ذریعہ منتخب کریں'),
          actions: [
            TextButton(
              child: Text(languageProvider.isEnglish ? 'Camera' : 'کیمرہ'),
              onPressed: () => Navigator.pop(context, ImageSource.camera),
            ),
            TextButton(
              child: Text(languageProvider.isEnglish ? 'Gallery' : 'گیلری'),
              onPressed: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      );

      if (source == null) return null; // User canceled

      XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        final file = File(pickedFile.path);
        imageBytes = await file.readAsBytes();
      }
    }

    return imageBytes;
  }

  Future<Map<String, dynamic>?> _selectBank(BuildContext context) async {
    if (_cachedBanks.isEmpty) {
      final bankSnapshot = await FirebaseDatabase.instance.ref('banks').once();
      if (bankSnapshot.snapshot.value == null) return null;

      final banks = bankSnapshot.snapshot.value as Map<dynamic, dynamic>;
      _cachedBanks = banks.entries.map((e) => {
        'id': e.key,
        'name': e.value['name'],
        'balance': e.value['balance']
      }).toList();
    }

    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    Map<String, dynamic>? selectedBank;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(languageProvider.isEnglish ? 'Select Bank' : 'بینک منتخب کریں'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _cachedBanks.length,
            itemBuilder: (context, index) {
              final bankData = _cachedBanks[index];
              final bankName = bankData['name'];

              // Find matching bank from pakistaniBanks list
              Bank? matchedBank = pakistaniBanks.firstWhere(
                    (b) => b.name.toLowerCase() == bankName.toLowerCase(),
                orElse: () => Bank(
                    name: bankName,
                    iconPath: 'assets/default_bank.png'
                ),
              );

              return Card(
                margin: EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: Image.asset(
                    matchedBank.iconPath,
                    width: 40,
                    height: 40,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(Icons.account_balance, size: 40);
                    },
                  ),
                  title: Text(
                    bankName,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  // subtitle: Text(
                  //   '${languageProvider.isEnglish ? "Balance" : "بیلنس"}: ${bankData['balance']} Rs',
                  // ),
                  onTap: () {
                    selectedBank = {
                      'id': bankData['id'],
                      'name': bankName,
                      'balance': bankData['balance']
                    };
                    Navigator.pop(context);
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ کریں'),
          ),
        ],
      ),
    );

    return selectedBank;
  }

  Future<void> _showFilledPaymentDialog(
      Map<String, dynamic> filled,
      FilledProvider filledProvider,
      LanguageProvider languageProvider,
      )
  async {
    String? selectedPaymentMethod;
    _paymentController.clear();
    bool _isPaymentButtonPressed = false;
    String? _description;
    Uint8List? _imageBytes;
    DateTime _selectedPaymentDate = DateTime.now();

    // Add these controllers and variables for cheque payments
    TextEditingController _chequeNumberController = TextEditingController();
    DateTime? _selectedChequeDate;
    String? _selectedChequeBankId;
    String? _selectedChequeBankName;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(languageProvider.isEnglish ? 'Pay Filled' : 'انوائس کی رقم ادا کریں'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Payment date selection
                    ListTile(
                      title: Text(languageProvider.isEnglish
                          ? 'Payment Date: ${DateFormat('yyyy-MM-dd – HH:mm').format(_selectedPaymentDate)}'
                          : 'ادائیگی کی تاریخ: ${DateFormat('yyyy-MM-dd – HH:mm').format(_selectedPaymentDate)}'),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: _selectedPaymentDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (pickedDate != null) {
                          final pickedTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(_selectedPaymentDate),
                          );
                          if (pickedTime != null) {
                            setState(() {
                              _selectedPaymentDate = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                pickedTime.hour,
                                pickedTime.minute,
                              );
                            });
                          }
                        }
                      },
                    ),

                    // Payment method dropdown
                    DropdownButtonFormField<String>(
                      value: selectedPaymentMethod,
                      items: [
                        DropdownMenuItem(
                          value: 'Cash',
                          child: Text(languageProvider.isEnglish ? 'Cash' : 'نقدی'),
                        ),
                        DropdownMenuItem(
                          value: 'Online',
                          child: Text(languageProvider.isEnglish ? 'Online' : 'آن لائن'),
                        ),
                        // DropdownMenuItem(
                        //   value: 'Check',
                        //   child: Text(languageProvider.isEnglish ? 'Check' : 'چیک'),
                        // ),
                        DropdownMenuItem(
                          value: 'Cheque', // Changed from 'Check'
                          child: Text(languageProvider.isEnglish ? 'Cheque' : 'چیک'),
                        ),
                        DropdownMenuItem(
                          value: 'Bank',
                          child: Text(languageProvider.isEnglish ? 'Bank' : 'بینک'),
                        ),
                        DropdownMenuItem(
                          value: 'Slip',
                          child: Text(languageProvider.isEnglish ? 'Slip' : 'پرچی'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          selectedPaymentMethod = value;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: languageProvider.isEnglish ? 'Select Payment Method' : 'ادائیگی کا طریقہ منتخب کریں',
                        border: const OutlineInputBorder(),
                      ),
                    ),

                    // Cheque payment fields (only shown when Check is selected)
                    if (selectedPaymentMethod == 'Cheque') ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _chequeNumberController,
                        decoration: InputDecoration(
                          labelText: languageProvider.isEnglish ? 'Cheque Number' : 'چیک نمبر',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        title: Text(
                          _selectedChequeDate == null
                              ? (languageProvider.isEnglish
                              ? 'Select Cheque Date'
                              : 'چیک کی تاریخ منتخب کریں')
                              : DateFormat('yyyy-MM-dd').format(_selectedChequeDate!),
                        ),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (pickedDate != null) {
                            setState(() => _selectedChequeDate = pickedDate);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: ListTile(
                          title: Text(_selectedChequeBankName ??
                              (languageProvider.isEnglish
                                  ? 'Select Bank'
                                  : 'بینک منتخب کریں')),
                          trailing: const Icon(Icons.arrow_drop_down),
                          onTap: () async {
                            final selectedBank = await _selectBank(context);
                            if (selectedBank != null) {
                              setState(() {
                                _selectedChequeBankId = selectedBank['id'];
                                _selectedChequeBankName = selectedBank['name'];
                              });
                            }
                          },
                        ),
                      ),
                    ],

                    // Bank payment fields (only shown when Bank is selected)
                    if (selectedPaymentMethod == 'Bank') ...[
                      const SizedBox(height: 16),
                      Card(
                        child: ListTile(
                          title: Text(_selectedBankName ??
                              (languageProvider.isEnglish
                                  ? 'Select Bank'
                                  : 'بینک منتخب کریں')),
                          trailing: const Icon(Icons.arrow_drop_down),
                          onTap: () async {
                            final selectedBank = await _selectBank(context);
                            if (selectedBank != null) {
                              setState(() {
                                _selectedBankId = selectedBank['id'];
                                _selectedBankName = selectedBank['name'];
                              });
                            }
                          },
                        ),
                      ),
                    ],

                    // Common fields for all payment methods
                    const SizedBox(height: 16),
                    TextField(
                      controller: _paymentController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: languageProvider.isEnglish ? 'Enter Payment Amount' : 'رقم لکھیں',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (value) => _description = value,
                      decoration: InputDecoration(
                        labelText: languageProvider.isEnglish ? 'Description' : 'تفصیل',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        Uint8List? imageBytes = await _pickImage(context);
                        if (imageBytes != null) {
                          setState(() => _imageBytes = imageBytes);
                        }
                      },
                      child: Text(languageProvider.isEnglish ? 'Pick Image' : 'تصویر اپ لوڈ کریں'),
                    ),
                    if (_imageBytes != null)
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        height: 100,
                        width: 100,
                        child: Image.memory(_imageBytes!),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(languageProvider.isEnglish ? 'Cancel' : 'انکار'),
                ),
                TextButton(
                  onPressed: _isPaymentButtonPressed
                      ? null
                      : () async {
                    setState(() => _isPaymentButtonPressed = true);

                    // Validate inputs
                    if (selectedPaymentMethod == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(languageProvider.isEnglish
                            ? 'Please select a payment method.'
                            : 'براہ کرم ادائیگی کا طریقہ منتخب کریں۔')),
                      );
                      setState(() => _isPaymentButtonPressed = false);
                      return;
                    }

                    final amount = double.tryParse(_paymentController.text);
                    if (amount == null || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(languageProvider.isEnglish
                            ? 'Please enter a valid payment amount.'
                            : 'براہ کرم ایک درست رقم درج کریں۔')),
                      );
                      setState(() => _isPaymentButtonPressed = false);
                      return;
                    }

                    // Validate cheque-specific fields
                    if (selectedPaymentMethod == 'Cheque') {
                      if (_selectedChequeBankId == null || _selectedChequeBankName == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(languageProvider.isEnglish
                              ? 'Please select a bank for the cheque'
                              : 'براہ کرم چیک کے لیے بینک منتخب کریں')),
                        );
                        setState(() => _isPaymentButtonPressed = false);
                        return;
                      }
                      if (_chequeNumberController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(languageProvider.isEnglish
                              ? 'Please enter cheque number'
                              : 'براہ کرم چیک نمبر درج کریں')),
                        );
                        setState(() => _isPaymentButtonPressed = false);
                        return;
                      }
                      if (_selectedChequeDate == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(languageProvider.isEnglish
                              ? 'Please select cheque date'
                              : 'براہ کرم چیک کی تاریخ منتخب کریں')),
                        );
                        setState(() => _isPaymentButtonPressed = false);
                        return;
                      }
                    }

                    // Validate bank-specific fields
                    if (selectedPaymentMethod == 'Bank' && (_selectedBankId == null || _selectedBankName == null)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(languageProvider.isEnglish
                            ? 'Please select a bank'
                            : 'براہ کرم بینک منتخب کریں')),
                      );
                      setState(() => _isPaymentButtonPressed = false);
                      return;
                    }

                    try {
                      await filledProvider.payFilledWithSeparateMethod(
                        context,
                        filled['filledNumber'],
                        amount,
                        selectedPaymentMethod!,
                        description: _description,
                        imageBytes: _imageBytes,
                        paymentDate: _selectedPaymentDate,
                        bankId: _selectedBankId,
                        bankName: _selectedBankName,
                        chequeNumber: _chequeNumberController.text,
                        chequeDate: _selectedChequeDate,
                        chequeBankId: _selectedChequeBankId,
                        chequeBankName: _selectedChequeBankName,
                      );
                      Navigator.of(context).pop();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: ${e.toString()}')),
                      );
                    } finally {
                      setState(() => _isPaymentButtonPressed = false);
                    }
                  },
                  child: Text(languageProvider.isEnglish ? 'Pay' : 'رقم ادا کریں'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void onPaymentPressed(Map<String, dynamic> filled) {
    // At the start of both methods
    // if (filled == null) return;
    if (filled['filledNumber'] == null || filled['customerId'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot process payment - invalid filled data')),
      );
      return;
    }
    final filledProvider = Provider.of<FilledProvider>(context, listen: false);
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    _showFilledPaymentDialog(filled, filledProvider, languageProvider);
  }

  void onViewPayments(Map<String, dynamic> filled) {
    // At the start of both methods
    // if (filled == null) return;
    // Similar null check
    if (filled == null || filled['filledNumber'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot view payments - invalid filled data')),
      );
      return;
    }
    _showPaymentDetails(filled);
  }

  Future<pw.MemoryImage> _createTexttoImage(String text) async {
    const double scaleFactor = 1.5;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromPoints(
        const Offset(0, 0),
        const Offset(500 * scaleFactor, 50 * scaleFactor),
      ),
    );

    final paint = Paint()..color = Colors.black;
    final textStyle = const TextStyle(
      fontSize: 13 * scaleFactor,
      fontFamily: 'JameelNoori',
      color: Colors.black,
      fontWeight: FontWeight.bold,
    );

    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.left,
      textDirection: ui.TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(canvas, const Offset(0, 0));

    final picture = recorder.endRecording();
    final img = await picture.toImage(
      (textPainter.width * scaleFactor).toInt(),
      (textPainter.height * scaleFactor).toInt(),
    );

    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final buffer = byteData!.buffer.asUint8List();

    return pw.MemoryImage(buffer);
  }

  @override
  void initState() {
    super.initState();

    _fetchItems();
    _initializeReferenceNumber();

    _biltiNumberController = TextEditingController();
    _transportCompanyController = TextEditingController();

    // Fix: Safe boolean check that handles null values
    final isFromQuotation = widget.isFromQuotation == true ||
        (widget.filled != null &&
            widget.filled!['isFromQuotation'] == true);

    if (isFromQuotation) {
      _initializeFromQuotation();
    } else {
      _initializeRegularInvoice();
    }
  }

  void _initializeFromQuotation() {
    if (widget.filled == null) {
      _initializeRegularInvoice();
      return;
    }
    final quotation = widget.filled!;

    setState(() {
      // Initialize customer data
      _selectedCustomerId = quotation['customerId']?.toString();
      _selectedCustomerName = quotation['customerName']?.toString();
      _selectedCustomerSerial = quotation['customerSerial']?.toString();

      // Initialize dates
      if (quotation['createdAt'] != null) {
        try {
          DateTime quotationDate = DateTime.parse(quotation['createdAt']);
          _dateController.text = DateFormat('yyyy-MM-dd').format(quotationDate);
        } catch (e) {
          _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
        }
      } else {
        _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
      }

      // Initialize reference number
      _referenceController.text = quotation['referenceNumber']?.toString() ?? '';
      _isAutoReference = false; // Manual reference from quotation

      // Initialize additional fields
      _biltiNumberController.text = quotation['biltiNumber']?.toString() ?? '';
      _transportCompanyController.text = quotation['transportCompany']?.toString() ?? '';
      _discountController.text = (quotation['discount'] ?? 0.0).toStringAsFixed(2);
      _discount = double.tryParse(_discountController.text) ?? 0.0;

      // Payment type - default to udhaar for quotation conversions
      _paymentType = 'udhaar';

      // Initialize items
      _initializeQuotationItems(quotation['items'] ?? []);
    });

    // Fetch customer-specific data if customer ID is available
    if (_selectedCustomerId != null) {
      _fetchCustomerPrices(_selectedCustomerId!);
      _fetchRemainingBalance();
      _fetchCustomerSerial(_selectedCustomerId!);
      _onCustomerChanged();
    }
  }

  void _initializeQuotationItems(List<dynamic> items) {
    _filledRows.clear();

    for (var item in items) {
      final itemNameController = TextEditingController(text: item['itemName']?.toString() ?? '');
      final sizeController = TextEditingController(text: item['size']?.toString() ?? '');
      final lengthController = TextEditingController(text: item['length']?.toString() ?? '');
      final bodyTypeController = TextEditingController(text: item['bodyType']?.toString() ?? '');
      final rateController = TextEditingController(text: (item['rate'] ?? 0.0).toString());
      final qtyController = TextEditingController(text: (item['quantity'] ?? 0.0).toString());
      final descriptionController = TextEditingController(text: item['description']?.toString() ?? '');
      final weightController = TextEditingController();

      // Initialize weight controller for quotation items
      if (item['totalWeight'] != null && item['totalWeight'] > 0) {
        final totalWeight = (item['totalWeight'] as num).toDouble();
        final weightUnit = item['weightUnit']?.toString() ?? 'kg';
        weightController.text = '$totalWeight $weightUnit';
      } else if (item['weightPerUnit'] != null && item['weightPerUnit'] > 0) {
        final weightPerUnit = (item['weightPerUnit'] as num).toDouble();
        final weightUnit = item['weightUnit']?.toString() ?? 'kg';
        weightController.text = '$weightPerUnit $weightUnit';
      }

      double qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      double rate = (item['rate'] as num?)?.toDouble() ?? 0.0;

      // Get calculation type from the item, default to 'quantity'
      String calculationType = item['calculationType']?.toString() ?? 'quantity';

      // Calculate total based on calculation type
      double total = 0.0;
      if (calculationType == 'weight' && item['totalWeight'] != null) {
        total = rate * (item['totalWeight'] as num).toDouble();
      } else {
        total = qty * rate;
      }

      _filledRows.add({
        'itemName': item['itemName']?.toString() ?? '',
        'description': item['description']?.toString() ?? '',
        'size': item['size']?.toString() ?? '',
        'length': item['length']?.toString() ?? '',
        'bodyType': item['bodyType']?.toString() ?? '',
        'rate': rate,
        'qty': qty,
        'initialQty': qty,
        'total': total,
        'calculationType': calculationType,
        'weightPerUnit': (item['weightPerUnit'] as num?)?.toDouble(),
        'weightUnit': item['weightUnit']?.toString() ?? 'kg',
        'totalWeight': (item['totalWeight'] as num?)?.toDouble(),
        'manualWeightEntry': false,
        'lengthBodyCombination': item['lengthBodyCombination'],
        'itemNameController': itemNameController,
        'sizeController': sizeController,
        'lengthController': lengthController,
        'bodyTypeController': bodyTypeController,
        'rateController': rateController,
        'qtyController': qtyController,
        'descriptionController': descriptionController,
        'weightController': weightController,
      });
    }

    // If no items, add 5 empty rows like QuotationPage
    if (_filledRows.isEmpty) {
      for (int i = 0; i < 5; i++) {
        _filledRows.add(_createEmptyRow());
      }
    }

    _calculateInitialTotals();
  }

  void _initializeRegularInvoice() {
    // Original initialization logic for regular invoices
    _currentFilled = widget.filled ?? {
      'filledNumber': null,
      'customerId': '',
      'customerName': '',
      'customerSerial': '',
      'referenceNumber': '',
      'biltiNumber': '',
      'transportCompany': '',
      'items': [],
      'subtotal': 0.0,
      'discount': 0.0,
      'grandTotal': 0.0,
      'mazdoori': 0.0,
      'paymentType': 'udhaar',
      'paymentMethod': null,
      'isFromQuotation': false,
      'createdAt': DateTime.now().toIso8601String(),
    };

    _filledId = _currentFilled!['filledNumber']?.toString() ?? '';
    _isReadOnly = widget.filled != null && widget.filled!['filledNumber'] != null;

    // Initialize date controller
    if (widget.filled != null && widget.filled!['createdAt'] != null) {
      try {
        DateTime filledDate = DateTime.parse(widget.filled!['createdAt']);
        _dateController.text = DateFormat('yyyy-MM-dd').format(filledDate);
      } catch (e) {
        _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
      }
    } else {
      _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    }

    // Initialize bilti and transport fields
    if (widget.filled != null) {
      _biltiNumberController.text = widget.filled!['biltiNumber']?.toString() ?? '';
      _transportCompanyController.text = widget.filled!['transportCompany']?.toString() ?? '';
    }

    // Initialize mazdoori (labor charges)
    _mazdooriController.text = (_currentFilled!['mazdoori'] as num?)?.toStringAsFixed(2) ?? '0.00';
    _mazdoori = double.tryParse(_mazdooriController.text) ?? 0.0;

    // Initialize discount
    _discountController.text = (_currentFilled!['discount'] as num?)?.toStringAsFixed(2) ?? '0.00';
    _discount = double.tryParse(_discountController.text) ?? 0.0;

    // Initialize reference number handling
    if (widget.filled != null && widget.filled!['referenceNumber'] != null && widget.filled!['referenceNumber'].toString().isNotEmpty) {
      _referenceController.text = widget.filled!['referenceNumber'];
      _autoReferenceController.text = widget.filled!['referenceNumber'];
      _isAutoReference = false; // Set to false since it's existing data
    } else {
      _isAutoReference = true;
    }

    // Payment type handling
    _paymentType = _currentFilled!['paymentType']?.toString() ?? 'udhaar';
    _instantPaymentMethod = _currentFilled!['paymentMethod']?.toString();

    // Initialize customer data if editing existing invoice
    if (widget.filled != null && widget.filled!['customerId'] != null) {
      final customerId = widget.filled!['customerId'].toString();
      final customerName = widget.filled!['customerName']?.toString() ?? '';
      final customerSerial = widget.filled!['customerSerial']?.toString() ?? '';

      // Use a post-frame callback to ensure customer provider is ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
        final customer = customerProvider.customers.firstWhere(
              (c) => c.id == customerId,
          orElse: () => Customer(
            id: customerId,
            name: customerName,
            phone: '',
            address: '',
            city: '',
            customerSerial: customerSerial,
          ),
        );

        if (mounted) {
          setState(() {
            _selectedCustomerId = customerId;
            _selectedCustomerName = customerName;
            _selectedCustomerSerial = customer.customerSerial ?? customerSerial;
            _customerController.text = customerName;
          });
          _fetchCustomerPrices(customerId);
          _fetchRemainingBalance();
          _fetchCustomerSerial(customerId);
          _onCustomerChanged();
        }
      });
    }

    // Initialize rows safely
    _initializeRows();
  }

  Future<void> _initializeReferenceNumber() async {
    if (_selectedCustomerId != null && _selectedCustomerSerial != null) {
      // Get the last reference number for this customer
      final lastRef = await Provider.of<FilledProvider>(context, listen: false)
          .getLastReferenceNumber(_selectedCustomerId!);

      setState(() {
        _lastReferenceNumber = lastRef;
      });

      if (_isAutoReference) {
        // Generate the next reference number without saving it yet
        final nextRef = await _generateNextReferenceNumber(increment: false);
        _autoReferenceController.text = nextRef;
        _referenceController.text = nextRef;
      }
    }
  }

  Future<String> _generateNextReferenceNumber({bool increment = true}) async {
    if (_selectedCustomerId == null || _selectedCustomerSerial == null) {
      return 'Unknown-0001';
    }

    final filledProvider = Provider.of<FilledProvider>(context, listen: false);

    if (increment) {
      // Get and increment the reference number
      final nextNumber = await filledProvider.getNextReferenceNumber(
          _selectedCustomerId!,
          _selectedCustomerSerial!
      );
      return '${_selectedCustomerSerial}-${nextNumber.toString().padLeft(4, '0')}';
    } else {
      // Just get the current number without incrementing
      final lastRef = await filledProvider.getLastReferenceNumber(_selectedCustomerId!);

      if (lastRef.isNotEmpty) {
        // Extract the number from the last reference and increment by 1 for display
        final parts = lastRef.split('-');
        if (parts.length == 2) {
          final lastNumber = int.tryParse(parts[1]) ?? 0;
          return '${_selectedCustomerSerial}-${(lastNumber + 1).toString().padLeft(4, '0')}';
        }
      }

      // No previous reference found, start from 1
      return '${_selectedCustomerSerial}-0001';
    }
  }

  void _fetchCustomerSerial(String customerId) async {
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    final customer = customerProvider.customers.firstWhere(
          (c) => c.id == customerId,
      orElse: () => Customer(id: '', name: 'N/A', phone: '', address: '', city: ''),
    );

    if (customer.id.isNotEmpty) {
      setState(() {
        _selectedCustomerSerial = customer.customerSerial;
      });
    }
  }

  void _initializeRows() {
    final items = _currentFilled!['items'] as List?;

    if (items != null && items.isNotEmpty) {
      // Load existing items from the invoice
      _filledRows = items.map((item) {
        final itemMap = item as Map? ?? {};

        // Create controllers and initialize with existing data
        final itemNameController = TextEditingController(text: itemMap['itemName']?.toString() ?? '');
        final sizeController = TextEditingController(text: itemMap['size']?.toString() ?? '');
        final lengthController = TextEditingController(text: itemMap['length']?.toString() ?? '');
        final bodyTypeController = TextEditingController(text: itemMap['bodyType']?.toString() ?? '');
        final rateController = TextEditingController(text: (itemMap['rate'] as num?)?.toString() ?? '0.0');
        final qtyController = TextEditingController(text: (itemMap['qty'] as num?)?.toString() ?? '0.0');
        final descriptionController = TextEditingController(text: itemMap['description']?.toString() ?? '');
        final weightController = TextEditingController();

        // FIX: Initialize weight controller properly - check for weightPerUnit first
        String weightText = '';
        final weightPerUnit = (itemMap['weightPerUnit'] as num?)?.toDouble();
        final weightUnit = itemMap['weightUnit']?.toString() ?? 'kg';
        final totalWeight = (itemMap['totalWeight'] as num?)?.toDouble();
        final qty = (itemMap['qty'] as num?)?.toDouble() ?? 1.0;

        if (weightPerUnit != null && weightPerUnit > 0) {
          // Use weight per unit if available
          weightText = '$weightPerUnit $weightUnit';
        } else if (totalWeight != null && totalWeight > 0 && qty > 0) {
          // Calculate weight per unit from total weight and quantity
          final calculatedWeightPerUnit = totalWeight / qty;
          weightText = '${calculatedWeightPerUnit.toStringAsFixed(2)} $weightUnit';
        }

        if (weightText.isNotEmpty) {
          weightController.text = weightText;
        }

        return {
          'itemName': itemMap['itemName']?.toString() ?? '',
          'rate': (itemMap['rate'] as num?)?.toDouble() ?? 0.0,
          'qty': (itemMap['qty'] as num?)?.toDouble() ?? 0.0,
          'initialQty': (itemMap['initialQty'] as num?)?.toDouble() ?? (itemMap['qty'] as num?)?.toDouble() ?? 0.0,
          'description': itemMap['description']?.toString() ?? '',
          'size': itemMap['size']?.toString() ?? '',
          'length': itemMap['length']?.toString() ?? '',
          'bodyType': itemMap['bodyType']?.toString() ?? '',
          'total': (itemMap['total'] as num?)?.toDouble() ?? 0.0,
          'calculationType': itemMap['calculationType']?.toString() ?? 'quantity',
          'weightPerUnit': weightPerUnit ?? ((totalWeight != null && qty > 0) ? totalWeight / qty : null),
          'weightUnit': weightUnit,
          'totalWeight': totalWeight,
          'manualWeightEntry': false,
          'lengthBodyCombination': itemMap['lengthBodyCombination'],
          'itemNameController': itemNameController,
          'sizeController': sizeController,
          'lengthController': lengthController,
          'bodyTypeController': bodyTypeController,
          'rateController': rateController,
          'qtyController': qtyController,
          'descriptionController': descriptionController,
          'weightController': weightController,
          'initialWeight': itemMap['totalWeight'] ?? 0.0,
        };
      }).toList();
    } else if (widget.filled == null) {
      // Initialize with 10 empty rows for new invoices
      _filledRows = List.generate(10, (index) => _createEmptyRow());
    } else {
      // For empty existing invoices (shouldn't normally happen), initialize with 1 row
      _filledRows = [_createEmptyRow()];
    }

    _calculateInitialTotals();
  }

  Map<String, dynamic> _createEmptyRow() {
    return {
      'total': 0.0,
      'rate': 0.0,
      'qty': 0.0,
      'size': '',
      'length': '',
      'bodyType': '',
      'description': '',
      'itemName': '',
      'calculationType': 'quantity',
      'weightPerUnit': null,
      'weightUnit': 'kg',
      'totalWeight': 0.0,
      'manualWeightEntry': false,
      'initialQty': 0.0,
      'initialWeight': 0.0,
      'itemNameController': TextEditingController(),
      'sizeController': TextEditingController(),
      'lengthController': TextEditingController(),
      'bodyTypeController': TextEditingController(),
      'rateController': TextEditingController(),
      'qtyController': TextEditingController(),
      'descriptionController': TextEditingController(),
      'weightController': TextEditingController(),
      'totalWeightController': TextEditingController(), // Add this line
    };
  }

  @override
  void dispose() {
    for (var row in _filledRows) {
      row['itemNameController']?.dispose();
      row['sizeController']?.dispose();
      row['lengthController']?.dispose();
      row['bodyTypeController']?.dispose();
      row['rateController']?.dispose();
      row['qtyController']?.dispose();
      row['descriptionController']?.dispose();
      row['weightController']?.dispose();
      row['totalWeightController']?.dispose(); // Add this line
    }
    _discountController.dispose();
    _customerController.dispose();
    _dateController.dispose();
    _mazdooriController.dispose();
    _referenceController.dispose();
    _biltiNumberController.dispose();
    _transportCompanyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 768;
    final isTablet = screenWidth > 480 && screenWidth <= 768;

    return FutureBuilder(
      future: Provider.of<CustomerProvider>(context, listen: false).fetchCustomers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          return const Center(child: CircularProgressIndicator());
        }

        return Scaffold(
          backgroundColor: Colors.grey[50],
          appBar: _buildAppBar(context, languageProvider),
          body: ResponsiveLayout(
            mobile: _buildMobileLayout(context, languageProvider),
            tablet: _buildTabletLayout(context, languageProvider),
            desktop: _buildDesktopLayout(context, languageProvider),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, LanguageProvider languageProvider) {
    return AppBar(
      elevation: 0,
      title: Text(
        _isReadOnly
            ? (languageProvider.isEnglish ? 'Update Invoice' : 'انوائس کو اپ ڈیٹ کریں')
            : (languageProvider.isEnglish ? 'Create Invoice' : 'انوائس بنائیں'),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
      centerTitle: true,
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
        // Show delete button only for existing invoices
        if (widget.filled != null && widget.filled!['filledNumber'] != null)
          _buildAppBarAction(
            icon: Icons.delete_outline,
            onPressed: () => _showDeleteConfirmationDialog(context, languageProvider),
          ),
        _buildAppBarAction(
          icon: Icons.print_outlined,
          onPressed: () async {
            try {
              if (_selectedCustomerId == null) {
                _showSnackBar(
                    context,
                    languageProvider.isEnglish
                        ? 'Please select a customer first'
                        : 'براہ کرم پہلے ایک گاہک منتخب کریں'
                );
                return;
              }
              await _generateAndPrintPDF();
            } catch (e) {
              _showSnackBar(
                  context,
                  languageProvider.isEnglish
                      ? 'Printing error: ${e.toString()}'
                      : 'پرنٹنگ کی خرابی: ${e.toString()}'
              );
            }
          },
        ),
      ],
    );
  }

  Future<void> _showDeleteConfirmationDialog(BuildContext context, LanguageProvider languageProvider) async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(languageProvider.isEnglish ? 'Delete Invoice' : 'انوائس ڈیلیٹ کریں'),
          content: Text(
            languageProvider.isEnglish
                ? 'Are you sure you want to delete this invoice?\n\nThis action cannot be undone.'
                : 'کیا آپ واقعی اس انوائس کو ڈیلیٹ کرنا چاہتے ہیں؟\n\nیہ عمل واپس نہیں ہو سکتا۔',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ کریں'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _deleteInvoice(context, languageProvider);
              },
              child: Text(
                languageProvider.isEnglish ? 'Delete' : 'ڈیلیٹ کریں',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteInvoice(BuildContext context, LanguageProvider languageProvider) async {
    // Store the navigator before async operations
    final navigator = Navigator.of(context);

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async => false,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );

      final filledProvider = Provider.of<FilledProvider>(context, listen: false);

      if (widget.filled != null && widget.filled!['filledNumber'] != null) {
        final filledId = widget.filled!['filledNumber']?.toString() ?? '';

        // 1. Restore stock quantities
        if (_filledRows.isNotEmpty) {
          for (var row in _filledRows) {
            final itemName = row['itemName'];
            if (itemName == null || itemName.isEmpty) continue;

            final dbItem = _items.firstWhere(
                  (i) => i.itemName == itemName,
              orElse: () => Item(
                  id: '',
                  itemName: '',
                  qtyOnHand: 0.0,
                  avgCostPricePerKg: 0.0,
                  avgSalePricePerKg: 0.0
              ),
            );

            if (dbItem.id.isNotEmpty) {
              final String itemId = dbItem.id;
              final double currentQty = dbItem.qtyOnHand ?? 0.0;

              // Determine what to restore based on calculation type
              double quantityToRestore = 0.0;

              if (row['calculationType'] == 'weight') {
                // For weight-based items, restore total weight
                final totalWeight = row['totalWeight'] ?? 0.0;
                final weightUnit = row['weightUnit'] ?? 'kg';

                // Convert to kg if needed
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
                quantityToRestore = row['qty'] ?? 0.0;
              }

              double updatedQty = currentQty + quantityToRestore;

              await _db.child('items/$itemId').update({'qtyOnHand': updatedQty});

              final String delLength = (row['length'] ?? '').toString().trim();
              final String delBodyType = (row['bodyType'] ?? '').toString().trim();
              if (delLength.isNotEmpty && delBodyType.isNotEmpty) {
                await _updateCombinationStockInDb(
                    itemId, delLength, delBodyType, quantityToRestore);
              }

              print('Stock restored for $itemName:');
              print('  Quantity restored: $quantityToRestore');
              print('  Updated stock: $updatedQty');
            }
          }
        }

        // 2. Delete the invoice from Firebase
        await filledProvider.deleteFilled(filledId);

        // Close loading dialog if still showing
        if (navigator.canPop()) {
          navigator.pop();
        }

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              languageProvider.isEnglish
                  ? 'Invoice deleted successfully'
                  : 'انوائس کامیابی سے ڈیلیٹ ہو گئی',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        // Wait a moment for the snackbar to be visible
        await Future.delayed(const Duration(milliseconds: 500));

        // Navigate back and clear all previous routes to filled list page
        // This ensures we go back to the filled list without keeping the deleted invoice in the stack
        if (navigator.canPop()) {
          // Pop all routes and go back to the filled list
          navigator.popUntil((route) => route.isFirst);

          // Alternative: If you want to explicitly navigate to filled list page
          // navigator.pushAndRemoveUntil(
          //   MaterialPageRoute(builder: (context) => FilledListPage()),
          //   (route) => false,
          // );
        }

      } else {
        // Close loading dialog
        if (navigator.canPop()) {
          navigator.pop();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              languageProvider.isEnglish
                  ? 'Cannot delete - no invoice data found'
                  : 'ڈیلیٹ نہیں کر سکتے - کوئی انوائس ڈیٹا نہیں ملا',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Error deleting invoice: $e');

      // Close loading dialog if still showing
      if (navigator.canPop()) {
        navigator.pop();
      }

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              languageProvider.isEnglish
                  ? 'Failed to delete invoice: ${e.toString()}'
                  : 'انوائس ڈیلیٹ کرنے میں ناکامی: ${e.toString()}',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Widget _buildAppBarAction({
    required IconData icon,
    required VoidCallback onPressed,
  })
  {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Material(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context, LanguageProvider languageProvider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderSection(context, languageProvider, isMobile: true),
          const SizedBox(height: 24),
          _buildCustomerSection(context, languageProvider),
          const SizedBox(height: 24),
          _buildItemsSection(context, languageProvider, isMobile: true),
          const SizedBox(height: 24),
          _buildPaymentSection(context, languageProvider),
          const SizedBox(height: 24),
          _buildTotalsSection(context, languageProvider),
          const SizedBox(height: 24),
          _buildSaveButton(context, languageProvider),
        ],
      ),
    );
  }

  Widget _buildTabletLayout(BuildContext context, LanguageProvider languageProvider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderSection(context, languageProvider, isMobile: false),
          const SizedBox(height: 32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    _buildCustomerSection(context, languageProvider),
                    const SizedBox(height: 24),
                    _buildItemsSection(context, languageProvider, isMobile: false),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Expanded(

                child: Column(
                  children: [
                    _buildPaymentSection(context, languageProvider),
                    const SizedBox(height: 24),
                    _buildTotalsSection(context, languageProvider),
                    const SizedBox(height: 24),
                    _buildSaveButton(context, languageProvider),
                  ],
                ),
              ),
              // const SizedBox(width: 24),
              // Expanded(
              //   child: _buildItemsGallery(context, languageProvider),
              // ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, LanguageProvider languageProvider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 10.0),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderSection(context, languageProvider, isMobile: false),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        _buildCustomerSection(context, languageProvider),
                        const SizedBox(height: 10),
                        _buildItemsSection(context, languageProvider, isMobile: false),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Column(
                      children: [
                        _buildPaymentSection(context, languageProvider),
                        const SizedBox(height: 10),
                        _buildTotalsSection(context, languageProvider),
                      ],
                    ),
                  ),

                ],
              ),
              const SizedBox(height: 10),
              _buildSaveButton(context, languageProvider),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection(BuildContext context, LanguageProvider languageProvider, {required bool isMobile}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.orange[50]!, Colors.amber[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long, color: Colors.orange[700], size: 24),
                const SizedBox(width: 8),
                Text(
                  languageProvider.isEnglish ? 'Invoice Details' : 'انوائس کی تفصیلات',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _biltiNumberController,
                    label: languageProvider.isEnglish ? 'Bilti Number' : 'بلٹی نمبر',
                    icon: Icons.confirmation_number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildTextField(
                    controller: _transportCompanyController,
                    label: languageProvider.isEnglish ? 'Transport Company' : 'ٹرانسپورٹ کمپنی',
                    icon: Icons.local_shipping,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isMobile) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _isAutoReference ? _autoReferenceController : _referenceController,
                      label: _isAutoReference
                          ? (languageProvider.isEnglish ? 'Auto Reference (Customer-Serial)' : 'آٹو ریفرنس (کسٹمر-سیریل)')
                          : (languageProvider.isEnglish ? 'Manual Reference Number' : 'دستی ریفرنس نمبر'),
                      icon: Icons.tag,
                      readOnly: _isAutoReference,
                    ),
                  ),
                  Switch(
                    value: _isAutoReference,
                    onChanged: (value) => _toggleReferenceMode(value),
                    activeColor: Colors.green,
                  ),
                  Text(
                    _isAutoReference
                        ? (languageProvider.isEnglish ? 'Auto' : 'آٹو')
                        : (languageProvider.isEnglish ? 'Manual' : 'مینوئل'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _dateController,
                label: languageProvider.isEnglish ? 'Date' : 'تاریخ',
                icon: Icons.calendar_today,
                readOnly: true,
                onTap: () => _selectDate(context),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _isAutoReference ? _autoReferenceController : _referenceController,
                            label: languageProvider.isEnglish ? 'Reference Number' : 'ریفرنس نمبر',
                            icon: Icons.tag,
                            readOnly: _isAutoReference,
                          ),
                        ),
                        Switch(
                          value: _isAutoReference,
                          onChanged: (value) => _toggleReferenceMode(value),
                          activeColor: Colors.green,
                        ),
                        Text(
                          _isAutoReference
                              ? (languageProvider.isEnglish ? 'Auto' : 'آٹو')
                              : (languageProvider.isEnglish ? 'Manual' : 'مینوئل'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _dateController,
                      label: languageProvider.isEnglish ? 'Date' : 'تاریخ',
                      icon: Icons.calendar_today,
                      readOnly: true,
                      onTap: () => _selectDate(context),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerSection(BuildContext context, LanguageProvider languageProvider) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_outline, color: Colors.blue[700], size: 24),
                const SizedBox(width: 8),
                Text(
                  languageProvider.isEnglish ? 'Customer Information' : 'کسٹمر کی معلومات',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Consumer<CustomerProvider>(
              builder: (context, customerProvider, _) {
                if (customerProvider.customers.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Initialize customer data if editing existing invoice
                if (widget.filled != null &&
                    widget.filled!['customerId'] != null &&
                    _selectedCustomerId == null) {
                  final customerId = widget.filled!['customerId'].toString();
                  final customerName = widget.filled!['customerName']?.toString() ?? '';

                  // Find the customer in the provider
                  final customer = customerProvider.customers.firstWhere(
                        (c) => c.id == customerId,
                    orElse: () => Customer(
                      id: customerId,
                      name: customerName,
                      phone: '',
                      address: '',
                      city: '',
                      customerSerial: widget.filled!['customerSerial']?.toString() ?? '',
                    ),
                  );

                  // Set the selected customer data
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _selectedCustomerId = customerId;
                        _selectedCustomerName = customerName;
                        _selectedCustomerSerial = customer.customerSerial;
                        _customerController.text = customerName;
                      });
                      _fetchCustomerPrices(customerId);
                      _fetchRemainingBalance();
                      _fetchCustomerSerial(customerId);
                      _onCustomerChanged();
                    }
                  });
                }

                return Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Autocomplete<Customer>(
                        initialValue: TextEditingValue(text: _selectedCustomerName ?? ''),
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Customer>.empty();
                          }
                          return customerProvider.customers.where((Customer customer) {
                            return customer.name.toLowerCase().contains(textEditingValue.text.toLowerCase());
                          });
                        },
                        displayStringForOption: (Customer customer) => customer.name,
                        fieldViewBuilder: (BuildContext context, TextEditingController textEditingController,
                            FocusNode focusNode, VoidCallback onFieldSubmitted) {

                          // Initialize the controller with selected customer name
                          if (_selectedCustomerName != null && textEditingController.text.isEmpty) {
                            textEditingController.text = _selectedCustomerName!;
                          }

                          return TextField(
                            controller: textEditingController,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: languageProvider.isEnglish ? 'Choose a customer' : 'ایک کسٹمر منتخب کریں',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                              prefixIcon: Icon(Icons.search, color: Colors.blue[600]),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _selectedCustomerId = null;
                                _selectedCustomerName = value;
                              });
                            },
                          );
                        },
                        onSelected: (Customer selectedCustomer) {
                          setState(() {
                            _selectedCustomerId = selectedCustomer.id;
                            _selectedCustomerName = selectedCustomer.name;
                            _selectedCustomerSerial = selectedCustomer.customerSerial;
                            _customerController.text = selectedCustomer.name;
                          });
                          _fetchCustomerPrices(selectedCustomer.id);
                          _fetchRemainingBalance();
                          _fetchCustomerSerial(selectedCustomer.id);
                          _onCustomerChanged();
                        },
                        optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<Customer> onSelected,
                            Iterable<Customer> options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4.0,
                              child: Container(
                                width: MediaQuery.of(context).size.width * 0.9,
                                constraints: const BoxConstraints(maxHeight: 200),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: options.length,
                                  itemBuilder: (BuildContext context, int index) {
                                    final Customer customer = options.elementAt(index);
                                    return ListTile(
                                      title: Text(customer.name),
                                      subtitle: customer.phone.isNotEmpty
                                          ? Text(customer.phone)
                                          : null,
                                      onTap: () => onSelected(customer),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_selectedCustomerName != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow(
                            languageProvider.isEnglish ? 'Selected Customer:' : 'منتخب کسٹمر:',
                            _selectedCustomerName!,
                            icon: Icons.person,
                          ),
                          if (_selectedCustomerSerial != null && _selectedCustomerSerial!.isNotEmpty)
                            _buildInfoRow(
                              languageProvider.isEnglish ? 'Customer Serial:' : 'کسٹمر سیریل:',
                              _selectedCustomerSerial!,
                              icon: Icons.confirmation_number,
                              color: Colors.blue[700],
                            ),
                          if (_lastReferenceNumber != null && _lastReferenceNumber!.isNotEmpty)
                            _buildInfoRow(
                              languageProvider.isEnglish ? 'Last Reference:' : 'آخری ریفرنس:',
                              _lastReferenceNumber!,
                              icon: Icons.history,
                              color: Colors.blueGrey,
                            )
                        ],
                      ),
                    if (_remainingBalance != null)
                      _buildInfoRow(
                        languageProvider.isEnglish ? 'Remaining Balance:' : 'بقایا رقم:',
                        _remainingBalance!.toStringAsFixed(2),
                        icon: Icons.account_balance_wallet,
                        color: _remainingBalance! > 0 ? Colors.red : Colors.green,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleWeightInput(int index, String value) {
    if (value.isEmpty) {
      setState(() {
        _filledRows[index]['totalWeight'] = null;
      });
      _calculateTotalForRow(index);
      return;
    }

    // Parse weight value and unit
    final parts = value.trim().split(' ');
    double? weightValue;
    String weightUnit = _filledRows[index]['weightUnit'] ?? 'kg'; // Use existing unit as default

    if (parts.isNotEmpty) {
      weightValue = double.tryParse(parts[0]);

      // Try to extract unit if provided
      if (parts.length > 1) {
        final unit = parts.sublist(1).join(' ').toLowerCase();
        if (unit.contains('kg') || unit.contains('kilogram')) {
          weightUnit = 'kg';
        } else if (unit.contains('g') || unit.contains('gram')) {
          weightUnit = 'g';
        } else if (unit.contains('lb') || unit.contains('pound')) {
          weightUnit = 'lb';
        } else if (unit.contains('ton')) {
          weightUnit = 'ton';
        }
      }
    }

    if (weightValue != null && weightValue > 0) {
      setState(() {
        _filledRows[index]['totalWeight'] = weightValue;
        _filledRows[index]['weightUnit'] = weightUnit;

        // Mark as manually entered weight
        _filledRows[index]['manualWeightEntry'] = true;

        // Automatically switch to weight calculation when weight is manually entered
        _filledRows[index]['calculationType'] = 'weight';
      });

      _calculateTotalForRow(index);
    }
  }

  void _showLengthCombinationDialog(Item item, int rowIndex) {
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    bool isProcessing = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                languageProvider.isEnglish
                    ? 'Select Length-Body Combination'
                    : 'لمبائی-جسم کا مجموعہ منتخب کریں',
              ),
              content: Container(
                width: double.maxFinite,
                constraints: const BoxConstraints(maxHeight: 450),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: item.lengthBodyCombinations!.length,
                  itemBuilder: (context, index) {
                    final combination = item.lengthBodyCombinations![index];

                    // ── Customer-aware price ──────────────────────────────
                    final double effectiveRate =
                    combination.getPriceForCustomer(_selectedCustomerId);
                    final bool hasCustomerPrice = _selectedCustomerId != null &&
                        combination.customerPrices
                            .containsKey(_selectedCustomerId);
                    final double defaultRate =
                        combination.salePricePerKg ?? 0.0;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: hasCustomerPrice
                            ? const BorderSide(
                            color: Colors.purple, width: 1.5)
                            : BorderSide.none,
                      ),
                      child: ListTile(
                        title: Text(
                          '${item.itemName} '
                              '(${combination.length} — ${combination.bodyType})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (combination.lengthDecimal.isNotEmpty)
                              Text(
                                'Decimal: ${combination.lengthDecimal}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600]),
                              ),
                            if (combination.weightPerUnit != null)
                              Text(
                                'Weight/Unit: ${combination.weightPerUnit}'
                                    ' ${combination.weightUnit}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.blue[700]),
                              ),

                            // ── Rate display ──────────────────────────────
                            const SizedBox(height: 4),
                            if (hasCustomerPrice) ...[
                              // Show customer-specific rate prominently
                              Row(
                                children: [
                                  Icon(Icons.person,
                                      size: 14, color: Colors.purple[700]),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Your Rate: '
                                        '${effectiveRate.toStringAsFixed(2)} PKR/kg',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.purple[700],
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'Default: '
                                    '${defaultRate.toStringAsFixed(2)} PKR/kg',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ] else ...[
                              // No customer price — show sale rate normally
                              if (combination.salePricePerKg != null)
                                Row(
                                  children: [
                                    Icon(Icons.sell,
                                        size: 14, color: Colors.green[700]),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Rate: '
                                          '${defaultRate.toStringAsFixed(2)} PKR/kg',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.green[700],
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (hasCustomerPrice)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.purple[50],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Custom',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.purple[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 4),
                            const Icon(Icons.arrow_forward),
                          ],
                        ),
                        onTap: () {
                          if (isProcessing) return;
                          setDialogState(() => isProcessing = true);
                          Navigator.pop(context);
                          Future.delayed(const Duration(milliseconds: 100),
                                  () => _addItemToRow(item, rowIndex, combination));
                        },
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                      languageProvider.isEnglish ? 'Cancel' : 'منسوخ'),
                ),
                TextButton(
                  onPressed: () {
                    if (isProcessing) return;
                    setDialogState(() => isProcessing = true);
                    Navigator.pop(context);
                    Future.delayed(const Duration(milliseconds: 100),
                            () => _addItemToRow(item, rowIndex, null));
                  },
                  child: Text(
                      languageProvider.isEnglish ? 'Skip' : 'چھوڑ دیں'),
                ),
              ],
            );
          },
        );
      },
    );
  }


  void _addItemToRow(
      Item item, int rowIndex, LengthBodyCombination? combination) {
    // Item-level customer price (fallback when no combination is chosen)
    final double customerPrice = item.getPriceForCustomer(_selectedCustomerId);

    setState(() {
      // Ensure controllers exist
      _filledRows[rowIndex]['sizeController'] ??= TextEditingController();
      _filledRows[rowIndex]['lengthController'] ??= TextEditingController();
      _filledRows[rowIndex]['bodyTypeController'] ??= TextEditingController();
      _filledRows[rowIndex]['weightController'] ??= TextEditingController();
      _filledRows[rowIndex]['totalWeightController'] ??=
          TextEditingController();

      _filledRows[rowIndex]['itemName'] = item.itemName;
      _filledRows[rowIndex]['itemNameController'].text = item.itemName;

      // Reset weight info
      _filledRows[rowIndex]['weightPerUnit'] = null;
      _filledRows[rowIndex]['weightUnit'] = 'kg';
      _filledRows[rowIndex]['lengthBodyCombination'] = null;

      if (combination != null) {
        // ── Combination-level customer price ─────────────────────────────
        // getPriceForCustomer returns the customer-specific price if set,
        // otherwise falls back to salePricePerKg.
        final double effectiveRate =
        combination.getPriceForCustomer(_selectedCustomerId);

        _filledRows[rowIndex]['sizeController'].text = combination.length;
        _filledRows[rowIndex]['lengthController'].text = combination.length;
        _filledRows[rowIndex]['bodyTypeController'].text = combination.bodyType;
        _filledRows[rowIndex]['size'] = combination.length;
        _filledRows[rowIndex]['length'] = combination.length;
        _filledRows[rowIndex]['bodyType'] = combination.bodyType;
        _filledRows[rowIndex]['lengthBodyCombination'] = combination.toMap();

        if (combination.weightPerUnit != null) {
          final double weightPerUnit = combination.weightPerUnit!;
          final String weightUnit = combination.weightUnit ?? 'kg';

          _filledRows[rowIndex]['weightPerUnit'] = weightPerUnit;
          _filledRows[rowIndex]['weightUnit'] = weightUnit;
          _filledRows[rowIndex]['weightController'].text =
          '$weightPerUnit $weightUnit';

          // Always use effective (customer-aware) rate when a rate is set
          _filledRows[rowIndex]['rate'] = effectiveRate;
          _filledRows[rowIndex]['rateController'].text =
              effectiveRate.toStringAsFixed(2);

          // Auto-switch to weight-based calculation when weight info exists
          _filledRows[rowIndex]['calculationType'] = 'weight';
        } else {
          // No weight data — still apply the customer-aware rate
          _filledRows[rowIndex]['rate'] = effectiveRate;
          _filledRows[rowIndex]['rateController'].text =
              effectiveRate.toStringAsFixed(2);
          _filledRows[rowIndex]['calculationType'] = 'quantity';
        }
      } else {
        // No combination selected — use item-level customer price
        _filledRows[rowIndex]['sizeController'].text = '';
        _filledRows[rowIndex]['lengthController'].text = '';
        _filledRows[rowIndex]['bodyTypeController'].text = '';
        _filledRows[rowIndex]['size'] = '';
        _filledRows[rowIndex]['length'] = '';
        _filledRows[rowIndex]['bodyType'] = '';
        _filledRows[rowIndex]['rate'] = customerPrice;
        _filledRows[rowIndex]['rateController'].text =
            customerPrice.toStringAsFixed(2);
        _filledRows[rowIndex]['calculationType'] = 'quantity';
      }

      // Default qty to 1 if not already set
      if ((_filledRows[rowIndex]['qty'] ?? 0.0) == 0.0) {
        _filledRows[rowIndex]['qty'] = 1.0;
        _filledRows[rowIndex]['qtyController'].text = '1';
      }

      _calculateTotalForRow(rowIndex);
    });
  }


  Widget _buildPaymentSection(BuildContext context, LanguageProvider languageProvider) {
    final _formKey = GlobalKey<FormState>();

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payment_outlined, color: Colors.purple[700], size: 24),
                const SizedBox(width: 8),
                Text(
                  languageProvider.isEnglish ? 'Payment & Discount' : 'ادائیگی اور رعایت',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.purple[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _discountController,
              label: languageProvider.isEnglish ? 'Discount Amount' : 'رعایت کی رقم',
              icon: Icons.money_off,
              keyboardType: TextInputType.number,
              onChanged: (value) {
                setState(() {
                  _discount = double.tryParse(value) ?? 0.0;
                  _calculateInitialTotals(); // Add this
                });
                double parsedDiscount = double.tryParse(value) ?? 0.0;
                if (parsedDiscount > _calculateSubtotal()) {
                  _discount = _calculateSubtotal();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          languageProvider.isEnglish
                              ? 'Discount cannot be greater than subtotal'
                              : 'رعایت کل رقم سے زیادہ نہیں ہو سکتی'
                      ),
                    ),
                  );
                } else {
                  _discount = parsedDiscount;
                }

              },
            ),
            const SizedBox(height: 16),
            // _buildTextField(
            //   controller: _mazdooriController,
            //   label: languageProvider.isEnglish ? 'Labour Charges' : 'مزدوری کی فیس',
            //   icon: Icons.construction,
            //   keyboardType: TextInputType.number,
            //   onChanged: (value) {
            //     setState(() {
            //       _mazdoori = double.tryParse(value) ?? 0.0;
            //       _calculateInitialTotals(); // Add this
            //
            //     });
            //   },
            // ),
            const SizedBox(height: 16),
            // Form(
            //   key: _formKey,
            //   child: Column(
            //     crossAxisAlignment: CrossAxisAlignment.start,
            //     children: [
            //       Text(
            //         languageProvider.isEnglish ? 'Payment Type:' : 'ادائیگی کی قسم:',
            //         style: TextStyle(
            //           fontSize: 16,
            //           fontWeight: FontWeight.w500,
            //           color: Colors.grey[800],
            //         ),
            //       ),
            //       const SizedBox(height: 8),
            //       Row(
            //         children: [
            //           Expanded(
            //             child: Column(
            //               children: [
            //                 RadioListTile<String>(
            //                   value: 'instant',
            //                   groupValue: _paymentType,
            //                   title: Text(languageProvider.isEnglish ? 'Instant Payment' : 'فوری ادائیگی'),
            //                   onChanged: (value) {
            //                     setState(() {
            //                       _paymentType = value!;
            //                       _instantPaymentMethod = null;
            //                     });
            //                   },
            //                 ),
            //                 RadioListTile<String>(
            //                   value: 'udhaar',
            //                   groupValue: _paymentType,
            //                   title: Text(languageProvider.isEnglish ? 'Udhaar Payment' : 'ادھار ادائیگی'),
            //                   onChanged: (value) {
            //                     setState(() {
            //                       _paymentType = value!;
            //                     });
            //                   },
            //                 ),
            //               ],
            //             ),
            //           ),
            //           if (_paymentType == 'instant')
            //             Expanded(
            //               child: Column(
            //                 children: [
            //                   RadioListTile<String>(
            //                     value: 'cash',
            //                     groupValue: _instantPaymentMethod,
            //                     title: Text(languageProvider.isEnglish ? 'Cash Payment' : 'نقد ادائیگی'),
            //                     onChanged: (value) {
            //                       setState(() {
            //                         _instantPaymentMethod = value!;
            //                       });
            //                     },
            //                   ),
            //                   RadioListTile<String>(
            //                     value: 'online',
            //                     groupValue: _instantPaymentMethod,
            //                     title: Text(languageProvider.isEnglish ? 'Online Transfer' : 'آن لائن ٹرانسفر'),
            //                     onChanged: (value) {
            //                       setState(() {
            //                         _instantPaymentMethod = value!;
            //                       });
            //                     },
            //                   ),
            //                 ],
            //               ),
            //             ),
            //         ],
            //       ),
            //       if (_paymentType.isEmpty)
            //         Text(
            //           languageProvider.isEnglish
            //               ? 'Please select a payment type'
            //               : 'براہ کرم ادائیگی کی قسم منتخب کریں',
            //           style: const TextStyle(color: Colors.red),
            //         ),
            //       if (_paymentType == 'instant' && (_instantPaymentMethod == null || _instantPaymentMethod!.isEmpty))
            //         Text(
            //           languageProvider.isEnglish
            //               ? 'Please select an instant payment method'
            //               : 'براہ کرم فوری ادائیگی کا طریقہ منتخب کریں',
            //           style: const TextStyle(color: Colors.red),
            //         ),
            //     ],
            //   ),
            // ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsSection(BuildContext context, LanguageProvider languageProvider) {
    double subtotal = _calculateSubtotal();
    double grandTotal = _calculateGrandTotal();

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.indigo[50]!, Colors.blue[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.calculate_outlined, color: Colors.indigo[700], size: 24),
                const SizedBox(width: 8),
                Text(
                  languageProvider.isEnglish ? 'Summary' : 'خلاصہ',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.indigo[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildTotalRow(
              languageProvider.isEnglish ? 'Subtotal:' : 'سب ٹوٹل:',
              subtotal.toStringAsFixed(2),
            ),
            const SizedBox(height: 8),
            _buildTotalRow(
              languageProvider.isEnglish ? 'Discount:' : 'رعایت:',
              '- ${_discount.toStringAsFixed(2)}',
              color: Colors.red[600],
            ),
            const SizedBox(height: 8),
            _buildTotalRow(
              languageProvider.isEnglish ? 'After Discount:' : 'رعایت کے بعد:',
              (subtotal - _discount).toStringAsFixed(2),
            ),
            // const SizedBox(height: 8),
            // _buildTotalRow(
            //   languageProvider.isEnglish ? 'Labour:' : 'مزدوری:',
            //   '+ ${_mazdoori.toStringAsFixed(2)}',
            //   color: Colors.green[600],
            // ),
            const Divider(thickness: 2, height: 10),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.indigo[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: _buildTotalRow(
                languageProvider.isEnglish ? 'GRAND TOTAL:' : 'مجموعی کل:',
                grandTotal.toStringAsFixed(2),
                isBold: true,
                fontSize: 18,
                color: Colors.indigo[800],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton(BuildContext context, LanguageProvider languageProvider) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _isButtonPressed
                ? null
                : () async {
              setState(() {
                _isButtonPressed = true;
              });

              try {
                // Validate reference number
                // if (_referenceController.text.isEmpty) {
                //   ScaffoldMessenger.of(context).showSnackBar(
                //     SnackBar(
                //       content: Text(
                //         languageProvider.isEnglish
                //             ? 'Please enter a reference number'
                //             : 'براہ کرم رفرنس نمبر درج کریں',
                //       ),
                //     ),
                //   );
                //   setState(() => _isButtonPressed = false);
                //   return;
                // }
                // In your save button onPressed method
                if (_isAutoReference && (_selectedCustomerId != null && _selectedCustomerSerial != null)) {
                  // Generate and use the auto reference number
                  final autoRef = await _generateNextReferenceNumber(increment: true);
                  _referenceController.text = autoRef;
                } else if (_referenceController.text.isEmpty) {
                  // Manual mode but no reference entered
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        languageProvider.isEnglish
                            ? 'Please enter a reference number'
                            : 'براہ کرم رفرنس نمبر درج کریں',
                      ),
                    ),
                  );
                  setState(() => _isButtonPressed = false);
                  return;
                }

                // Validate customer selection
                if (_selectedCustomerId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        languageProvider.isEnglish
                            ? 'Please select a customer'
                            : 'براہ کرم کسٹمر منتخب کریں',
                      ),
                    ),
                  );
                  setState(() => _isButtonPressed = false);
                  return;
                }

                // Validate payment type
                if (_paymentType == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        languageProvider.isEnglish
                            ? 'Please select a payment type'
                            : 'براہ کرم ادائیگی کی قسم منتخب کریں',
                      ),
                    ),
                  );
                  setState(() => _isButtonPressed = false);
                  return;
                }

                // Validate instant payment method
                if (_paymentType == 'instant' && _instantPaymentMethod == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        languageProvider.isEnglish
                            ? 'Please select an instant payment method'
                            : 'براہ کرم فوری ادائیگی کا طریقہ منتخب کریں',
                      ),
                    ),
                  );
                  setState(() => _isButtonPressed = false);
                  return;
                }

                // // Validate item rates
                // for (var row in _filledRows) {
                //   if ((row['rate'] ?? 0.0) <= 0) {
                //     ScaffoldMessenger.of(context).showSnackBar(
                //       SnackBar(
                //         content: Text(
                //           languageProvider.isEnglish
                //               ? 'Rate cannot be zero or less'
                //               : 'ریٹ صفر یا اس سے کم نہیں ہو سکتا',
                //         ),
                //       ),
                //     );
                //     setState(() => _isButtonPressed = false);
                //     return;
                //   }
                // }

                // Validate discount amount
                // Validate item rates (only for rows that have items)
                for (var row in _filledRows) {
                  final itemName = row['itemName'] ?? '';
                  final rate = row['rate'] ?? 0.0;

                  // Skip validation if the row is empty (no item name)
                  if (itemName.isEmpty) continue;

                  if (rate <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          languageProvider.isEnglish
                              ? 'Rate cannot be zero or less'
                              : 'ریٹ صفر یا اس سے کم نہیں ہو سکتا',
                        ),
                      ),
                    );
                    setState(() => _isButtonPressed = false);
                    return;
                  }
                }
                final subtotal = _calculateSubtotal();
                if (_discount >= subtotal) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        languageProvider.isEnglish
                            ? 'Discount amount cannot be greater than or equal to the subtotal'
                            : 'ڈسکاؤنٹ کی رقم سب ٹوٹل سے زیادہ یا اس کے برابر نہیں ہو سکتی',
                      ),
                    ),
                  );
                  setState(() => _isButtonPressed = false);
                  return;
                }

                // Check stock
                List<Map<String, dynamic>> insufficientItems = [];
                for (var row in _filledRows) {
                  String itemName = row['itemName'] ?? '';
                  if (itemName.isEmpty) continue;

                  Item? item = _items.firstWhere(
                        (i) => i.itemName == itemName,
                    orElse: () => Item(id: '', itemName: '',qtyOnHand: 0.0,avgCostPricePerKg: 0.0, avgSalePricePerKg: 0.0),
                  );

                  if (item.id.isEmpty) continue;

                  double currentQty = item.qtyOnHand;
                  double qty = row['qty'] ?? 0.0;
                  double initialQty = row['initialQty'] ?? qty;
                  double delta = widget.filled != null && widget.filled!['filledNumber'] != null
                      ? (initialQty - qty)
                      : -qty;
                  double newQty = currentQty + delta;

                  if (newQty < 0) {
                    insufficientItems.add({'item': item, 'delta': delta});
                  }
                }

                if (insufficientItems.isNotEmpty) {
                  bool proceed = await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(Provider.of<LanguageProvider>(context, listen: false).isEnglish
                          ? 'Insufficient Stock'
                          : 'اسٹاک ناکافی'),
                      content: Text(
                        Provider.of<LanguageProvider>(context, listen: false).isEnglish
                            ? 'The following items will have negative stock. Do you want to proceed?'
                            : 'مندرجہ ذیل اشیاء کا اسٹاک منفی ہو جائے گا۔ کیا آپ آگے بڑھنا چاہتے ہیں؟',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(Provider.of<LanguageProvider>(context, listen: false).isEnglish
                              ? 'Cancel'
                              : 'منسوخ کریں'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(Provider.of<LanguageProvider>(context, listen: false).isEnglish
                              ? 'Proceed'
                              : 'آگے بڑھیں'),
                        ),
                      ],
                    ),
                  );

                  if (!proceed) {
                    setState(() => _isButtonPressed = false);
                    return;
                  }
                }

                final grandTotal = _calculateGrandTotal();
                final filledProvider = Provider.of<FilledProvider>(context, listen: false);

                // Generate filled number for new fills
                String filledNumber = widget.filled?['filledNumber']?.toString() ??
                    (await filledProvider.getNextFilledNumber()).toString();

                // Prepare items with ALL details
                final items = _filledRows.map((row) {
                  return {
                    'itemName': row['itemName'] ?? '',
                    'rate': row['rate'] ?? 0.0,
                    'qty': row['qty'] ?? 0.0,
                    'size': row['size']?.toString() ?? '',
                    'length': row['length']?.toString() ?? '',
                    'bodyType': row['bodyType']?.toString() ?? '',
                    'description': row['description']?.toString() ?? '',
                    'total': row['total'] ?? 0.0,
                    'calculationType': row['calculationType'] ?? 'quantity',
                    'weightPerUnit': row['weightPerUnit'],
                    'weightUnit': row['weightUnit'] ?? 'kg',
                    'totalWeight': row['totalWeight'],
                    'initialQty': row['initialQty'] ?? row['qty'] ?? 0.0, // For stock tracking
                    'initialWeight': row['totalWeight'] ?? 0.0, // ADD THIS LINE
                    'lengthBodyCombination': row['lengthBodyCombination'], // Store combination if exists
                  };
                }).toList();

                // Prepare date
                final createdAt = _dateController.text.isNotEmpty
                    ? DateTime(
                  DateTime.parse(_dateController.text).year,
                  DateTime.parse(_dateController.text).month,
                  DateTime.parse(_dateController.text).day,
                  DateTime.now().hour,
                  DateTime.now().minute,
                  DateTime.now().second,
                ).toIso8601String()
                    : DateTime.now().toIso8601String();

                // Always save as new fill when coming from quotation
                if (widget.filled?['isFromQuotation'] ?? false) {
                  // Only increment when saving a new invoice
                  if (_isAutoReference && (_selectedCustomerId != null && _selectedCustomerSerial != null)) {
                    final autoRef = await _generateCustomerSerialReference(increment: true);
                    _referenceController.text = autoRef;
                  }

                  await filledProvider.saveFilled(
                    filledId: filledNumber,
                    filledNumber: filledNumber,
                    customerId: _selectedCustomerId!,
                    customerName: _selectedCustomerName ?? 'Unknown Customer',
                    subtotal: subtotal,
                    discount: _discount,
                    grandTotal: grandTotal,
                    mazdoori: _mazdoori,
                    paymentType: _paymentType,
                    paymentMethod: _instantPaymentMethod,
                    referenceNumber: _referenceController.text,
                    biltiNumber: _biltiNumberController.text,
                    transportCompany: _transportCompanyController.text,
                    createdAt: createdAt,
                    items: items,
                  );
                }
                // Update existing fill if it has a filledNumber
                else if (widget.filled != null && widget.filled!['filledNumber'] != null) {
                  await filledProvider.updateFilled(
                    filledId: filledNumber,
                    filledNumber: filledNumber,
                    customerId: _selectedCustomerId!,
                    customerName: _selectedCustomerName ?? 'Unknown Customer',
                    subtotal: subtotal,
                    discount: _discount,
                    grandTotal: grandTotal,
                    mazdoori: _mazdoori,
                    paymentType: _paymentType,
                    referenceNumber: _referenceController.text,
                    biltiNumber: _biltiNumberController.text,
                    transportCompany: _transportCompanyController.text,
                    paymentMethod: _instantPaymentMethod,
                    items: items,
                    createdAt: createdAt,
                  );
                }
                // Otherwise save as new fill
                else {
                  await filledProvider.saveFilled(
                    filledId: filledNumber,
                    filledNumber: filledNumber,
                    customerId: _selectedCustomerId!,
                    customerName: _selectedCustomerName ?? 'Unknown Customer',
                    subtotal: subtotal,
                    discount: _discount,
                    grandTotal: grandTotal,
                    mazdoori: _mazdoori,
                    paymentType: _paymentType,
                    paymentMethod: _instantPaymentMethod,
                    referenceNumber: _referenceController.text,
                    biltiNumber: _biltiNumberController.text,
                    transportCompany: _transportCompanyController.text,
                    createdAt: createdAt,
                    items: items,
                  );
                }

                // Update stock
                _updateQtyOnHand(_filledRows);

                // Update state
                setState(() {
                  _currentFilled = {
                    'id': filledNumber,
                    'filledNumber': filledNumber,
                    'grandTotal': grandTotal,
                    'customerId': _selectedCustomerId!,
                    'customerName': _selectedCustomerName ?? 'Unknown Customer',
                    'referenceNumber': _referenceController.text,
                    'createdAt': createdAt,
                    'items': _filledRows,
                    'paymentType': _paymentType,
                  };
                  _isSaved = true;
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      widget.filled == null || widget.filled!['isFromQuotation'] ?? false
                          ? (languageProvider.isEnglish
                          ? 'Invoice saved successfully'
                          : 'انوائس کامیابی سے محفوظ ہوگئی')
                          : (languageProvider.isEnglish
                          ? 'Iilled updated successfully'
                          : 'انوائس کامیابی سے تبدیل ہوگئی'),
                    ),
                  ),
                );
              } catch (e) {
                print('Error saving invoice: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      languageProvider.isEnglish
                          ? 'Failed to save invoice: ${e.toString()}'
                          : 'انوائس محفوظ کرنے میں ناکام: ${e.toString()}',
                    ),
                  ),
                );
              } finally {
                setState(() => _isButtonPressed = false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[300],
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              widget.filled == null || widget.filled?['isFromQuotation'] ?? false
                  ? (languageProvider.isEnglish ? 'Save Invoice' : 'انوائس محفوظ کریں')
                  : (languageProvider.isEnglish ? 'Update Invoice' : 'انوائس کو اپ ڈیٹ کریں'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    bool readOnly = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    Function(String)? onChanged,
    VoidCallback? onTap,
  })
  {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: Colors.grey[600]) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.teal, width: 2),
        ),
        filled: true,
        fillColor: readOnly ? Colors.grey[100] : Colors.grey[50],
      ),
    );
  }

  void _calculateInitialTotals() {
    // Calculate subtotal and grand total when initializing rows
    for (var row in _filledRows) {
      double rate = row['rate'] ?? 0.0;
      double qty = row['qty'] ?? 0.0;
      String calculationType = row['calculationType'] ?? 'quantity';
      double? totalWeight = row['totalWeight'];
      double? weightPerUnit = row['weightPerUnit'];

      // Calculate total based on calculation type
      if (calculationType == 'weight' && totalWeight != null && totalWeight > 0) {
        row['total'] = rate * totalWeight;
      } else if (calculationType == 'weight' && weightPerUnit != null && weightPerUnit > 0) {
        double calculatedWeight = weightPerUnit * qty;
        row['totalWeight'] = calculatedWeight;
        row['total'] = rate * calculatedWeight;
      } else {
        // Default to quantity calculation
        row['total'] = rate * qty;
      }
    }

    // Update discount and mazdoori from controllers
    _discount = double.tryParse(_discountController.text) ?? 0.0;
    _mazdoori = double.tryParse(_mazdooriController.text) ?? 0.0;
  }

  Widget _buildTotalRow(String label, String value, {
    bool isBold = false,
    double fontSize = 14,
    Color? color,
  })
  {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            fontSize: fontSize,
            color: color,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: fontSize,
            color: color ?? Colors.grey[800],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {IconData? icon, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color ?? Colors.grey[600]),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color ?? Colors.teal[700],
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

}

class CustomAutocomplete extends StatelessWidget {
  final List<Item> items;
  final TextEditingController controller;
  final Function(Item) onSelected;
  final String? selectedCustomerId;
  final bool allowManualEntry;

  const CustomAutocomplete({
    required this.items,
    required this.controller,
    required this.onSelected,
    required this.selectedCustomerId,
    this.allowManualEntry = true,
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Item>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<Item>.empty();
        }
        return items.where((item) {
          return item.itemName.toLowerCase().contains(
            textEditingValue.text.toLowerCase(),
          );
        });
      },
      displayStringForOption: (Item item) => item.itemName,
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
        // Sync the parent controller with the autocomplete controller
        if (controller.text != textEditingController.text) {
          textEditingController.text = controller.text;
        }

        return TextField(
          controller: textEditingController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'Item',
            suffixIcon: IconButton(
              icon: Icon(Icons.search),
              onPressed: () => _showItemSearchDialog(context),
            ),
          ),
          onChanged: (value) {
            controller.text = value;
            if (allowManualEntry && value.isNotEmpty) {
              // Create a temporary item for manual entry
              onSelected(Item(
                id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
                itemName: value,
                qtyOnHand: 0, avgCostPricePerKg: 0.0, avgSalePricePerKg: 0.0,
              ));
            }
          },
        );
      },
      // In the CustomAutocomplete widget, update the optionsViewBuilder to show serial numbers:
      optionsViewBuilder: (context, onSelected, options) {
        return Material(
          elevation: 4,
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: options.length,
            separatorBuilder: (context, index) => Divider(height: 1),
            itemBuilder: (context, index) {
              final option = options.elementAt(index);
              // Show customer price if customer is selected, otherwise show sale price
              final displayPrice = selectedCustomerId != null
                  ? option.getPriceForCustomer(selectedCustomerId)
                  : option.avgSalePricePerKg;

              final isSpecialPrice = selectedCustomerId != null &&
                  displayPrice != option.avgCostPricePerKg;

              return ListTile(
                title: Text(option.itemName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (option.customerSerial != null && option.customerSerial!.isNotEmpty)
                      Text(
                        'Serial: ${option.customerSerial}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    if (isSpecialPrice)
                      Text('Special Price for Customer'),
                  ],
                ),
                trailing: Text(
                  '${displayPrice.toStringAsFixed(2)}rs',
                  style: TextStyle(
                    fontWeight: isSpecialPrice ? FontWeight.bold : FontWeight.normal,
                    color: isSpecialPrice ? Colors.green : Colors.black,
                  ),
                ),
                onTap: () {
                  onSelected(option);
                  FocusManager.instance.primaryFocus?.unfocus();
                },
              );
            },
          ),
        );
      },
      onSelected: (Item selection) {
        // Use customer price if customer is selected, otherwise use sale price
        final selectedPrice = selectedCustomerId != null
            ? selection.getPriceForCustomer(selectedCustomerId)
            : selection.avgSalePricePerKg;

        controller.text = selection.itemName;
        onSelected(selection.copyWith(
          avgCostPricePerKg: selectedPrice,
          avgSalePricePerKg: selectedPrice,
        ));
      },
    );
  }

  void _showItemSearchDialog(BuildContext context) {
    String searchQuery = '';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Filter items based on search query
            final filteredItems = searchQuery.isEmpty
                ? items
                : items.where((item) {
              return item.itemName.toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              child: Container(
                width: double.maxFinite,
                height: MediaQuery.of(context).size.height * 0.7,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Select Item',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Search Field
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Search Items',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      onChanged: (value) {
                        setState(() {
                          searchQuery = value;
                        });
                      },
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),

                    // Items count
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${filteredItems.length} items found',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Items List
                    Expanded(
                      child: filteredItems.isEmpty
                          ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No items found',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                          : ListView.separated(
                        shrinkWrap: true,
                        itemCount: filteredItems.length,
                        separatorBuilder: (context, index) => Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];

                          // Determine which price to show
                          final displayPrice = selectedCustomerId != null
                              ? item.getPriceForCustomer(selectedCustomerId)
                              : item.avgSalePricePerKg;

                          final isSpecialPrice = selectedCustomerId != null &&
                              displayPrice != item.avgSalePricePerKg;

                          return Card(
                            margin: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                            elevation: 1,
                            child: ListTile(
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              leading: GestureDetector(
                                onTap: () {
                                  if (item.imageBase64 != null &&
                                      item.imageBase64!.isNotEmpty) {
                                    _showImagePreview(context, item.imageBase64!);
                                  }
                                },
                                child: item.imageBase64 != null &&
                                    item.imageBase64!.isNotEmpty
                                    ? Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    image: DecorationImage(
                                      image: MemoryImage(
                                        base64Decode(item.imageBase64!),
                                      ),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                )
                                    : Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.inventory,
                                    size: 24,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                              title: Text(
                                item.itemName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (item.customerSerial != null &&
                                      item.customerSerial!.isNotEmpty)
                                    Text(
                                      'Serial: ${item.customerSerial}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  Text(
                                    'Rs ${displayPrice.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSpecialPrice
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isSpecialPrice
                                          ? Colors.green
                                          : Colors.blue[700],
                                    ),
                                  ),
                                  if (isSpecialPrice)
                                    Text(
                                      'Special Price',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.green,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: () {
                                  // First close the dialog
                                  Navigator.pop(context);

                                  // Then trigger the selection after a small delay
                                  Future.delayed(Duration(milliseconds: 100), () {
                                    final selectedPrice = selectedCustomerId != null
                                        ? item.getPriceForCustomer(selectedCustomerId)
                                        : item.avgSalePricePerKg;

                                    controller.text = item.itemName;
                                    onSelected(item.copyWith(
                                      avgCostPricePerKg: selectedPrice,
                                      avgSalePricePerKg: selectedPrice,
                                    ));
                                  });
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add, size: 18),
                                    SizedBox(width: 4),
                                    Text('Add'),
                                  ],
                                ),
                              ),
                              onTap: () {
                                // Alternative: tap anywhere on the tile to select
                                Navigator.pop(context);

                                Future.delayed(Duration(milliseconds: 100), () {
                                  final selectedPrice = selectedCustomerId != null
                                      ? item.getPriceForCustomer(selectedCustomerId)
                                      : item.avgSalePricePerKg;

                                  controller.text = item.itemName;
                                  onSelected(item.copyWith(
                                    avgCostPricePerKg: selectedPrice,
                                    avgSalePricePerKg: selectedPrice,
                                  ));
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showImagePreview(BuildContext context, String base64Image) {
    try {
      final decodedImage = base64Decode(base64Image);

      showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          backgroundColor: Colors.black87,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Close button
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              // Image
              Expanded(
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.7,
                    maxWidth: MediaQuery.of(context).size.width * 0.9,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.memory(
                      decodedImage,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.white,
                                size: 48,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Error loading image',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to preview image: $e')),
      );
    }
  }
}

