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
import '../Provider/lanprovider.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:share_plus/share_plus.dart';
import 'dart:html' as html;
import '../Provider/quotationPageprovider.dart';
import '../bankmanagement/banknames.dart';


class QuotepageOrg extends StatefulWidget {
  final Map<String, dynamic>? filled;
  final bool isFromQuotation;

  const QuotepageOrg({
    Key? key,
    this.filled,
    this.isFromQuotation = false,
  }) : super(key: key);

  @override
  _QuotepageOrgState createState() => _QuotepageOrgState();
}


class _QuotepageOrgState extends State<QuotepageOrg> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  List<Item> _items = [];
  String? _selectedItemName;
  String? _selectedItemId;
  double _selectedItemRate = 0.0;
  String? _selectedCustomerName;
  String? _selectedCustomerId;
  double _discount = 0.0;
  String _paymentType = 'udhaar';
  String? _instantPaymentMethod;
  TextEditingController _discountController = TextEditingController();
  List<Map<String, dynamic>> _filledRows = [];
  String? _filledId;
  bool _isReadOnly = false;
  bool _isButtonPressed = false;
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _rateController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  double _remainingBalance = 0.0;
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

                      Expanded(
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

  String _calculateDisplayTotalWeight(int index) {
    double qty = _filledRows[index]['qty'] ?? 0.0;
    double? weightPerUnit = _filledRows[index]['weightPerUnit'];
    String weightUnit = _filledRows[index]['weightUnit']?.toString() ?? 'kg';

    if (qty > 0 && weightPerUnit != null && weightPerUnit > 0) {
      double totalWeight = qty * weightPerUnit;
      return '${totalWeight.toStringAsFixed(2)} $weightUnit';
    }

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

    final parts = value.trim().split(' ');
    double? weightValue;
    String weightUnit = _filledRows[index]['weightUnit']?.toString() ?? 'kg';

    if (parts.isNotEmpty) {
      weightValue = double.tryParse(parts[0]);

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
      double qty = _filledRows[index]['qty'] ?? 0.0;
      double calculatedTotalWeight = weightValue * qty;

      setState(() {
        _filledRows[index]['weightPerUnit'] = weightValue;
        _filledRows[index]['weightUnit'] = weightUnit;
        _filledRows[index]['totalWeight'] = calculatedTotalWeight;

        if (_filledRows[index]['totalWeightController'] == null) {
          _filledRows[index]['totalWeightController'] = TextEditingController();
        }
        _filledRows[index]['totalWeightController']?.text =
        '${calculatedTotalWeight.toStringAsFixed(2)} $weightUnit';
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
    String calculationType = _filledRows[index]['calculationType']?.toString() ?? 'quantity';
    double? weightPerUnit = _filledRows[index]['weightPerUnit'];

    double? totalWeight;
    if (weightPerUnit != null && weightPerUnit > 0 && qty > 0) {
      totalWeight = weightPerUnit * qty;
      _filledRows[index]['totalWeight'] = totalWeight;
    } else {
      totalWeight = _filledRows[index]['totalWeight'];
    }

    double total = 0.0;

    if (calculationType == 'weight') {
      if (totalWeight != null && totalWeight > 0) {
        total = rate * totalWeight;
      } else {
        total = rate * qty;
      }
    } else {
      total = rate * qty;
    }

    _filledRows[index]['total'] = total;
    setState(() {});
  }

  Future<String> _generateCustomerSerialReference({bool increment = true}) async {
    if (_selectedCustomerId == null || _selectedCustomerSerial == null) {
      return 'Unknown-0001';
    }

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

      if (field == 'rate' || field == 'qty' || field == 'calculationType' ||
          field == 'weightPerUnit' || field == 'lengthBodyCombination') {
        _calculateTotalForRow(index);
      }
    });
  }

  void _deleteRow(int index) {
    setState(() {
      final deletedRow = _filledRows[index];
      deletedRow['itemNameController']?.dispose();
      deletedRow['sizeController']?.dispose();
      deletedRow['lengthController']?.dispose();
      deletedRow['bodyTypeController']?.dispose();
      deletedRow['rateController']?.dispose();
      deletedRow['qtyController']?.dispose();
      deletedRow['descriptionController']?.dispose();
      deletedRow['weightController']?.dispose();
      deletedRow['totalWeightController']?.dispose();
      _filledRows.removeAt(index);
    });
  }

  double _calculateSubtotal() {
    return _filledRows.fold(0.0, (sum, row) => sum + (row['total'] ?? 0.0));
  }

  double _calculateGrandTotal() {
    double subtotal = _calculateSubtotal();
    double afterDiscount = subtotal - _discount;
    return afterDiscount + _mazdoori;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // FIXED: _generatePDFBytes — full null safety throughout
  // ─────────────────────────────────────────────────────────────────────────────
  Future<Uint8List> _generatePDFBytes(String quoteNumber) async {
    final pdf = pw.Document();

    final customerProvider =
    Provider.of<CustomerProvider>(context, listen: false);
    final filledProvider =
    Provider.of<QuoteProvider>(context, listen: false);

    final filled = widget.filled ?? _currentFilled;
    if (filled == null) throw Exception('No invoice data available');

    // Filter empty rows — guard itemName being null
    final nonEmptyRows = _filledRows
        .where((row) => ((row['itemName'] as String?) ?? '').isNotEmpty)
        .toList();

    // Pre-render Size & Length as PNG images
    final List<Uint8List> sizeImages = [];
    final List<Uint8List> lengthImages = [];

    for (final row in nonEmptyRows) {
      final sizeText   = (row['size']?.toString()   ?? '').trim();
      final lengthText = (row['length']?.toString() ?? '').trim();

      sizeImages.add(await _renderTextAsImage(
        sizeText.isNotEmpty ? sizeText : '-',
        width: 70, height: 24,
      ));
      lengthImages.add(await _renderTextAsImage(
        lengthText.isNotEmpty ? lengthText : '-',
        width: 70, height: 24,
      ));
    }

    if (_selectedCustomerId == null) throw Exception('No customer selected');

    final selectedCustomer = customerProvider.customers.firstWhere(
          (c) => c.id == _selectedCustomerId,
      orElse: () => Customer(
        id: 'unknown', name: 'Unknown', phone: '', address: '', city: '',
      ),
    );

    // Safe string accessors for customer fields
    final customerName    = selectedCustomer.name    ?? 'N/A';
    final customerAddress = selectedCustomer.address ?? 'N/A';
    final customerPhone   = selectedCustomer.phone   ?? 'N/A';

    // Date
    DateTime filledDate;
    try {
      if (widget.filled != null && widget.filled!['createdAt'] != null) {
        filledDate = DateTime.parse(widget.filled!['createdAt'].toString());
      } else if (_dateController.text.isNotEmpty) {
        final d   = DateTime.parse(_dateController.text);
        final now = DateTime.now();
        filledDate = DateTime(d.year, d.month, d.day, now.hour, now.minute, now.second);
      } else {
        filledDate = DateTime.now();
      }
    } catch (_) {
      filledDate = DateTime.now();
    }

    final formattedDate =
        '${filledDate.day}/${filledDate.month}/${filledDate.year}';
    final formattedTime =
        '${filledDate.hour}:${filledDate.minute.toString().padLeft(2, '0')}';

    // Safe reference number
    final referenceNumber = _referenceController.text.isNotEmpty
        ? _referenceController.text
        : 'Q${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';

    // Safe bilti / transport
    final biltiNumber       = _biltiNumberController.text.isNotEmpty
        ? _biltiNumberController.text
        : 'N/A';
    final transportCompany  = _transportCompanyController.text.isNotEmpty
        ? _transportCompanyController.text
        : 'N/A';

    // Safe invoice number
    final safeQuoteNumber  = (quoteNumber.isNotEmpty) ? quoteNumber : 'N/A';

    // Assets
    Uint8List? logoBytes;
    try {
      final ByteData logoData =
      await rootBundle.load('assets/images/logo.png');
      logoBytes = logoData.buffer.asUint8List();
    } catch (_) {}

    pw.MemoryImage? lineImage;
    pw.MemoryImage? footerLogo;
    pw.MemoryImage? jazzcashLogo;
    pw.MemoryImage? ublLogo;

    try {
      lineImage = pw.MemoryImage(
          (await rootBundle.load('assets/images/line.png'))
              .buffer.asUint8List());
    } catch (_) {}

    try {
      footerLogo = pw.MemoryImage(
          (await rootBundle.load('assets/images/devlogo.png'))
              .buffer.asUint8List());
    } catch (_) {}

    try {
      jazzcashLogo = pw.MemoryImage(
          (await rootBundle.load('assets/images/jazzcashlogo.png'))
              .buffer.asUint8List());
    } catch (_) {}

    try {
      ublLogo = pw.MemoryImage(
          (await rootBundle.load('assets/images/ubl.png'))
              .buffer.asUint8List());
    } catch (_) {}

    // Totals
    final totalQty = nonEmptyRows.fold<double>(
        0.0, (s, r) => s + _parseToDouble(r['qty'] ?? 0));

    final totalWeight = nonEmptyRows.fold<double>(0.0, (s, r) {
      final weight        = _parseToDouble(r['totalWeight']    ?? 0);
      final qty           = _parseToDouble(r['qty']            ?? 0);
      final weightPerUnit = _parseToDouble(r['weightPerUnit']  ?? 0);
      final calcType      = r['calculationType']?.toString()   ?? 'quantity';
      if (calcType == 'weight' && weight > 0) return s + weight;
      if (weightPerUnit > 0) return s + (weightPerUnit * qty);
      return s;
    });

    // Build PDF
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
                          'Address: St# 2 Kotli Rustom Road Hafizabad Road Gujranwala, Pakistan',
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
                          '#$referenceNumber',
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
                          'For any queries, please contact us at 03704219219 / 03713084600',
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
                  if (lineImage != null)
                    pw.Image(lineImage, width: 150, height: 50)
                  else
                    pw.SizedBox(width: 150, height: 50),
                  if (footerLogo != null)
                    pw.Image(footerLogo, width: 50, height: 40)
                  else
                    pw.SizedBox(width: 50, height: 40),
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
                  pw.Text('Customer Name: $customerName',
                      style: const pw.TextStyle(fontSize: 11)),
                  pw.Text('Customer Address: $customerAddress',
                      style: const pw.TextStyle(fontSize: 11)),
                  pw.Text('Customer Number: $customerPhone',
                      style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
              pw.Column(children: [
                pw.Text('Date: $formattedDate $formattedTime',
                    style: const pw.TextStyle(fontSize: 10)),
                pw.Text('Quote #: $safeQuoteNumber',
                    style: const pw.TextStyle(fontSize: 12)),
                pw.Text('Bilti Number: $biltiNumber',
                    style: const pw.TextStyle(fontSize: 11)),
                pw.Text('Transport Company: $transportCompany',
                    style: const pw.TextStyle(fontSize: 11)),
              ]),
            ],
          ),
          pw.Divider(),
          pw.SizedBox(height: 10),

          // Items table
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.8), // Size
              1: pw.FlexColumnWidth(1.8), // Length
              2: pw.FlexColumnWidth(1.5), // Body Type
              3: pw.FlexColumnWidth(2.5), // Description
              4: pw.FlexColumnWidth(1.0), // Qty
              5: pw.FlexColumnWidth(1.5), // Weight
              6: pw.FlexColumnWidth(1.5), // Rate
              7: pw.FlexColumnWidth(1.5), // Total
            },
            children: [
              // Header row
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
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

              // Data rows
              ...List.generate(nonEmptyRows.length, (i) {
                final r = nonEmptyRows[i];

                // Safe weight text — fully null-safe
                String weightText = '';
                final calcType     = r['calculationType']?.toString() ?? 'quantity';
                final weightUnit   = r['weightUnit']?.toString()      ?? 'kg';
                final tw           = r['totalWeight'];
                final wu           = r['weightPerUnit'];
                final rowQty       = _parseToDouble(r['qty'] ?? 0);

                if (calcType == 'weight') {
                  if (tw != null && _parseToDouble(tw) > 0) {
                    weightText = '${_parseToDouble(tw).toStringAsFixed(2)} $weightUnit';
                  } else if (wu != null && _parseToDouble(wu) > 0) {
                    final w = (_parseToDouble(wu) * rowQty).toStringAsFixed(2);
                    weightText = '$w $weightUnit';
                  }
                }

                // Safe rate & total
                final rowRate  = _parseToDouble(r['rate']  ?? 0);
                final rowTotal = _parseToDouble(r['total'] ?? 0);

                // Safe body type & description
                final bodyType    = r['bodyType']?.toString()    ?? '';
                final description = r['description']?.toString() ?? '';

                final bg = i % 2 == 0 ? PdfColors.white : PdfColors.grey100;

                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: bg),
                  children: [
                    // SIZE as image
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Image(
                        pw.MemoryImage(sizeImages[i]),
                        width: 60, height: 20,
                        fit: pw.BoxFit.contain,
                      ),
                    ),

                    // LENGTH as image
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Image(
                        pw.MemoryImage(lengthImages[i]),
                        width: 60, height: 20,
                        fit: pw.BoxFit.contain,
                      ),
                    ),

                    _cell(bodyType),
                    _cell(description),
                    _cell(rowQty.toStringAsFixed(0)),
                    _cell(weightText),
                    _cell(rowRate.toStringAsFixed(2),
                        align: pw.Alignment.centerRight),
                    _cell(rowTotal.toStringAsFixed(2),
                        align: pw.Alignment.centerRight),
                  ],
                );
              }),

              // Totals row
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _hcell('Total'),
                  _hcell(''),
                  _hcell(''),
                  _hcell(''),
                  _hcell(totalQty.toStringAsFixed(0)),
                  _hcell('${totalWeight.toStringAsFixed(2)} kg'),
                  _hcell(''),
                  _hcell(_calculateSubtotal().toStringAsFixed(2)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // FIXED: _generateAndPrintPDF — detailed error logging + null-safe filledNumber
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _generateAndPrintPDF() async {
    try {
      String quoteNumber;

      if (widget.filled != null) {
        // Get the quote number from the filled data
        quoteNumber = widget.filled!['quoteNumber']?.toString() ??
            widget.filled!['quoteCounter']?.toString() ??
            'N/A';
      } else {
        // Generate a new quote number
        final filledProvider = Provider.of<QuoteProvider>(context, listen: false);
        quoteNumber = (await filledProvider.getNextQuoteNumber()).toString();
      }

      // Ensure we have a valid quote number
      if (quoteNumber.isEmpty || quoteNumber == 'N/A') {
        // Generate a fallback number if needed
        quoteNumber = 'Q${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
      }

      final bytes = await _generatePDFBytes(quoteNumber);
      await Printing.layoutPdf(onLayout: (format) => bytes);

    } catch (e, stackTrace) {
      print("Error printing: $e");
      print("Stack trace: $stackTrace");
      if (mounted) {
        _showSnackBar(context, 'Print error: ${e.toString()}');
      }
    }
  }

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
      }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final bgPaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF000000),
          fontSize: fontSize,
          fontFamily: null,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
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

  @override
  void initState() {
    super.initState();

    _fetchItems();
    _initializeReferenceNumber();

    _biltiNumberController = TextEditingController();
    _transportCompanyController = TextEditingController();

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
      _selectedCustomerId = quotation['customerId']?.toString();
      _selectedCustomerName = quotation['customerName']?.toString();
      _selectedCustomerSerial = quotation['customerSerial']?.toString();

      if (quotation['createdAt'] != null) {
        try {
          DateTime quotationDate = DateTime.parse(quotation['createdAt'].toString());
          _dateController.text = DateFormat('yyyy-MM-dd').format(quotationDate);
        } catch (e) {
          _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
        }
      } else {
        _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
      }

      _referenceController.text = quotation['referenceNumber']?.toString() ?? '';
      _isAutoReference = false;

      _biltiNumberController.text = quotation['biltiNumber']?.toString() ?? '';
      _transportCompanyController.text = quotation['transportCompany']?.toString() ?? '';
      _discountController.text = (quotation['discount'] ?? 0.0).toString();
      _discount = double.tryParse(_discountController.text) ?? 0.0;

      _paymentType = 'udhaar';

      _initializeQuotationItems(quotation['items'] ?? []);
    });

    if (_selectedCustomerId != null) {
      _fetchCustomerPrices(_selectedCustomerId!);
      _fetchCustomerSerial(_selectedCustomerId!);
      _onCustomerChanged();
    }
  }

  void _initializeQuotationItems(List<dynamic> items) {
    _filledRows.clear();

    for (var item in items) {
      final itemMap = item as Map? ?? {};

      final itemNameController = TextEditingController(text: itemMap['itemName']?.toString() ?? '');
      final sizeController = TextEditingController(text: itemMap['size']?.toString() ?? '');
      final lengthController = TextEditingController(text: itemMap['length']?.toString() ?? '');
      final bodyTypeController = TextEditingController(text: itemMap['bodyType']?.toString() ?? '');
      final rateController = TextEditingController(text: (itemMap['rate'] ?? 0.0).toString());
      final qtyController = TextEditingController(text: (itemMap['quantity'] ?? 0.0).toString());
      final descriptionController = TextEditingController(text: itemMap['description']?.toString() ?? '');
      final weightController = TextEditingController();

      if (itemMap['totalWeight'] != null && _parseToDouble(itemMap['totalWeight']) > 0) {
        final totalWeight = _parseToDouble(itemMap['totalWeight']);
        final weightUnit = itemMap['weightUnit']?.toString() ?? 'kg';
        weightController.text = '$totalWeight $weightUnit';
      } else if (itemMap['weightPerUnit'] != null && _parseToDouble(itemMap['weightPerUnit']) > 0) {
        final weightPerUnit = _parseToDouble(itemMap['weightPerUnit']);
        final weightUnit = itemMap['weightUnit']?.toString() ?? 'kg';
        weightController.text = '$weightPerUnit $weightUnit';
      }

      double qty = _parseToDouble(itemMap['quantity'] ?? 0);
      double rate = _parseToDouble(itemMap['rate'] ?? 0);
      String calculationType = itemMap['calculationType']?.toString() ?? 'quantity';

      double total = 0.0;
      if (calculationType == 'weight' && itemMap['totalWeight'] != null) {
        total = rate * _parseToDouble(itemMap['totalWeight']);
      } else {
        total = qty * rate;
      }

      _filledRows.add({
        'itemName': itemMap['itemName']?.toString() ?? '',
        'description': itemMap['description']?.toString() ?? '',
        'size': itemMap['size']?.toString() ?? '',
        'length': itemMap['length']?.toString() ?? '',
        'bodyType': itemMap['bodyType']?.toString() ?? '',
        'rate': rate,
        'qty': qty,
        'initialQty': qty,
        'total': total,
        'calculationType': calculationType,
        'weightPerUnit': itemMap['weightPerUnit'] != null ? _parseToDouble(itemMap['weightPerUnit']) : null,
        'weightUnit': itemMap['weightUnit']?.toString() ?? 'kg',
        'totalWeight': itemMap['totalWeight'] != null ? _parseToDouble(itemMap['totalWeight']) : null,
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
      });
    }

    if (_filledRows.isEmpty) {
      for (int i = 0; i < 5; i++) {
        _filledRows.add(_createEmptyRow());
      }
    }

    _calculateInitialTotals();
  }

  void _initializeRegularInvoice() {
    _currentFilled = widget.filled ?? {
      'quoteNumber': null,
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

    _filledId = _currentFilled!['quoteNumber']?.toString() ?? '';
    _isReadOnly = widget.filled != null && widget.filled!['quoteNumber'] != null;

    if (widget.filled != null && widget.filled!['createdAt'] != null) {
      try {
        DateTime filledDate = DateTime.parse(widget.filled!['createdAt'].toString());
        _dateController.text = DateFormat('yyyy-MM-dd').format(filledDate);
      } catch (e) {
        _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
      }
    } else {
      _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    }

    if (widget.filled != null) {
      _biltiNumberController.text = widget.filled!['biltiNumber']?.toString() ?? '';
      _transportCompanyController.text = widget.filled!['transportCompany']?.toString() ?? '';
    }

    _mazdooriController.text = (_currentFilled!['mazdoori'] as num?)?.toStringAsFixed(2) ?? '0.00';
    _mazdoori = double.tryParse(_mazdooriController.text) ?? 0.0;

    _discountController.text = (_currentFilled!['discount'] as num?)?.toStringAsFixed(2) ?? '0.00';
    _discount = double.tryParse(_discountController.text) ?? 0.0;

    if (widget.filled != null &&
        widget.filled!['referenceNumber'] != null &&
        widget.filled!['referenceNumber'].toString().isNotEmpty) {
      _referenceController.text = widget.filled!['referenceNumber'].toString();
      _autoReferenceController.text = widget.filled!['referenceNumber'].toString();
      _isAutoReference = false;
    } else {
      _isAutoReference = true;
    }

    _paymentType = _currentFilled!['paymentType']?.toString() ?? 'udhaar';
    _instantPaymentMethod = _currentFilled!['paymentMethod']?.toString();

    if (widget.filled != null && widget.filled!['customerId'] != null) {
      final customerId = widget.filled!['customerId'].toString();
      final customerName = widget.filled!['customerName']?.toString() ?? '';
      final customerSerial = widget.filled!['customerSerial']?.toString() ?? '';

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
          _fetchCustomerSerial(customerId);
          _onCustomerChanged();
        }
      });
    }

    _initializeRows();
  }

  Future<void> _initializeReferenceNumber() async {
    if (_selectedCustomerId != null && _selectedCustomerSerial != null) {
      final lastRef = await Provider.of<QuoteProvider>(context, listen: false)
          .getLastReferenceNumber(_selectedCustomerId!);

      setState(() {
        _lastReferenceNumber = lastRef;
      });

      if (_isAutoReference) {
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

    final filledProvider = Provider.of<QuoteProvider>(context, listen: false);

    if (increment) {
      final nextNumber = await filledProvider.getNextReferenceNumber(
          _selectedCustomerId!,
          _selectedCustomerSerial!
      );
      return '${_selectedCustomerSerial}-${nextNumber.toString().padLeft(4, '0')}';
    } else {
      final lastRef = await filledProvider.getLastReferenceNumber(_selectedCustomerId!);

      if (lastRef.isNotEmpty) {
        final parts = lastRef.split('-');
        if (parts.length == 2) {
          final lastNumber = int.tryParse(parts[1]) ?? 0;
          return '${_selectedCustomerSerial}-${(lastNumber + 1).toString().padLeft(4, '0')}';
        }
      }

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
      _filledRows = items.map((item) {
        final itemMap = item as Map? ?? {};

        final itemNameController = TextEditingController(text: itemMap['itemName']?.toString() ?? '');
        final sizeController = TextEditingController(text: itemMap['size']?.toString() ?? '');
        final lengthController = TextEditingController(text: itemMap['length']?.toString() ?? '');
        final bodyTypeController = TextEditingController(text: itemMap['bodyType']?.toString() ?? '');
        final rateController = TextEditingController(text: (itemMap['rate'] as num?)?.toString() ?? '0.0');
        final qtyController = TextEditingController(text: (itemMap['qty'] as num?)?.toString() ?? '0.0');
        final descriptionController = TextEditingController(text: itemMap['description']?.toString() ?? '');
        final weightController = TextEditingController();

        String weightText = '';
        final weightPerUnit = (itemMap['weightPerUnit'] as num?)?.toDouble();
        final weightUnit = itemMap['weightUnit']?.toString() ?? 'kg';
        final totalWeight = (itemMap['totalWeight'] as num?)?.toDouble();
        final qty = (itemMap['qty'] as num?)?.toDouble() ?? 1.0;

        if (weightPerUnit != null && weightPerUnit > 0) {
          weightText = '$weightPerUnit $weightUnit';
        } else if (totalWeight != null && totalWeight > 0 && qty > 0) {
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
      _filledRows = List.generate(10, (index) => _createEmptyRow());
    } else {
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
      'totalWeightController': TextEditingController(),
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
      row['totalWeightController']?.dispose();
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
        if (widget.filled != null && widget.filled!['quoteNumber'] != null)
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
            } catch (e, st) {
              print('Print error: $e\n$st');
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
    final navigator = Navigator.of(context);

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async => false,
          child: const Center(child: CircularProgressIndicator()),
        ),
      );

      final filledProvider = Provider.of<QuoteProvider>(context, listen: false);

      if (widget.filled != null && widget.filled!['quoteNumber'] != null) {
        final filledId = widget.filled!['quoteNumber']?.toString() ?? '';

        if (_filledRows.isNotEmpty) {
          for (var row in _filledRows) {
            final itemName = row['itemName']?.toString() ?? '';
            if (itemName.isEmpty) continue;

            final dbItem = _items.firstWhere(
                  (i) => i.itemName == itemName,
              orElse: () => Item(
                  id: '', itemName: '', qtyOnHand: 0.0,
                  avgCostPricePerKg: 0.0, avgSalePricePerKg: 0.0),
            );

            if (dbItem.id.isNotEmpty) {
              final String itemId = dbItem.id;
              final double currentQty = dbItem.qtyOnHand ?? 0.0;

              double quantityToRestore = 0.0;

              if (row['calculationType']?.toString() == 'weight') {
                final totalWeight = _parseToDouble(row['totalWeight'] ?? 0);
                final weightUnit = row['weightUnit']?.toString() ?? 'kg';

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
                quantityToRestore = _parseToDouble(row['qty'] ?? 0);
              }

              double updatedQty = currentQty + quantityToRestore;
              await _db.child('items/$itemId').update({'qtyOnHand': updatedQty});
            }
          }
        }

        await filledProvider.deleteQuote(filledId);

        if (navigator.canPop()) navigator.pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(languageProvider.isEnglish
                ? 'Invoice deleted successfully'
                : 'انوائس کامیابی سے ڈیلیٹ ہو گئی'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 500));

        if (navigator.canPop()) {
          navigator.popUntil((route) => route.isFirst);
        }
      } else {
        if (navigator.canPop()) navigator.pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(languageProvider.isEnglish
                ? 'Cannot delete - no invoice data found'
                : 'ڈیلیٹ نہیں کر سکتے - کوئی انوائس ڈیٹا نہیں ملا'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Error deleting invoice: $e');
      if (navigator.canPop()) navigator.pop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(languageProvider.isEnglish
                ? 'Failed to delete invoice: ${e.toString()}'
                : 'انوائس ڈیلیٹ کرنے میں ناکامی: ${e.toString()}'),
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
  }) {
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

                if (widget.filled != null &&
                    widget.filled!['customerId'] != null &&
                    _selectedCustomerId == null) {
                  final customerId = widget.filled!['customerId'].toString();
                  final customerName = widget.filled!['customerName']?.toString() ?? '';

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

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _selectedCustomerId = customerId;
                        _selectedCustomerName = customerName;
                        _selectedCustomerSerial = customer.customerSerial;
                        _customerController.text = customerName;
                      });
                      _fetchCustomerPrices(customerId);
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
                            return customer.name.toLowerCase()
                                .contains(textEditingValue.text.toLowerCase());
                          });
                        },
                        displayStringForOption: (Customer customer) => customer.name,
                        fieldViewBuilder: (BuildContext context,
                            TextEditingController textEditingController,
                            FocusNode focusNode, VoidCallback onFieldSubmitted) {
                          if (_selectedCustomerName != null &&
                              textEditingController.text.isEmpty) {
                            textEditingController.text = _selectedCustomerName!;
                          }

                          return TextField(
                            controller: textEditingController,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: languageProvider.isEnglish
                                  ? 'Choose a customer'
                                  : 'ایک کسٹمر منتخب کریں',
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
                          _fetchCustomerSerial(selectedCustomer.id);
                          _onCustomerChanged();
                        },
                        optionsViewBuilder: (BuildContext context,
                            AutocompleteOnSelected<Customer> onSelected,
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
                          if (_selectedCustomerSerial != null &&
                              _selectedCustomerSerial!.isNotEmpty)
                            _buildInfoRow(
                              languageProvider.isEnglish ? 'Customer Serial:' : 'کسٹمر سیریل:',
                              _selectedCustomerSerial!,
                              icon: Icons.confirmation_number,
                              color: Colors.blue[700],
                            ),
                          if (_lastReferenceNumber != null &&
                              _lastReferenceNumber!.isNotEmpty)
                            _buildInfoRow(
                              languageProvider.isEnglish ? 'Last Reference:' : 'آخری ریفرنس:',
                              _lastReferenceNumber!,
                              icon: Icons.history,
                              color: Colors.blueGrey,
                            ),
                        ],
                      ),
                    _buildInfoRow(
                      languageProvider.isEnglish ? 'Remaining Balance:' : 'بقایا رقم:',
                      _remainingBalance.toStringAsFixed(2),
                      icon: Icons.account_balance_wallet,
                      color: _remainingBalance > 0 ? Colors.red : Colors.green,
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

  void _showLengthCombinationDialog(Item item, int rowIndex) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
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

                    final double effectiveRate =
                    combination.getPriceForCustomer(_selectedCustomerId);
                    final bool hasCustomerPrice = _selectedCustomerId != null &&
                        combination.customerPrices.containsKey(_selectedCustomerId);
                    final double defaultRate = combination.salePricePerKg ?? 0.0;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: hasCustomerPrice
                            ? const BorderSide(color: Colors.purple, width: 1.5)
                            : BorderSide.none,
                      ),
                      child: ListTile(
                        title: Text(
                          '${item.itemName} (${combination.length} — ${combination.bodyType})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (combination.lengthDecimal.isNotEmpty)
                              Text('Decimal: ${combination.lengthDecimal}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            if (combination.weightPerUnit != null)
                              Text(
                                  'Weight/Unit: ${combination.weightPerUnit} ${combination.weightUnit}',
                                  style: TextStyle(fontSize: 12, color: Colors.blue[700])),
                            const SizedBox(height: 4),
                            if (hasCustomerPrice) ...[
                              Row(children: [
                                Icon(Icons.person, size: 14, color: Colors.purple[700]),
                                const SizedBox(width: 4),
                                Text('Your Rate: ${effectiveRate.toStringAsFixed(2)} PKR/kg',
                                    style: TextStyle(fontSize: 13,
                                        fontWeight: FontWeight.bold, color: Colors.purple[700])),
                              ]),
                              Text('Default: ${defaultRate.toStringAsFixed(2)} PKR/kg',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[500],
                                      decoration: TextDecoration.lineThrough)),
                            ] else ...[
                              if (combination.salePricePerKg != null)
                                Row(children: [
                                  Icon(Icons.sell, size: 14, color: Colors.green[700]),
                                  const SizedBox(width: 4),
                                  Text('Rate: ${defaultRate.toStringAsFixed(2)} PKR/kg',
                                      style: TextStyle(fontSize: 13,
                                          fontWeight: FontWeight.w500, color: Colors.green[700])),
                                ]),
                            ],
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (hasCustomerPrice)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.purple[50],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('Custom',
                                    style: TextStyle(fontSize: 10,
                                        color: Colors.purple[700], fontWeight: FontWeight.bold)),
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
                  child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ'),
                ),
                TextButton(
                  onPressed: () {
                    if (isProcessing) return;
                    setDialogState(() => isProcessing = true);
                    Navigator.pop(context);
                    Future.delayed(const Duration(milliseconds: 100),
                            () => _addItemToRow(item, rowIndex, null));
                  },
                  child: Text(languageProvider.isEnglish ? 'Skip' : 'چھوڑ دیں'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _addItemToRow(Item item, int rowIndex, LengthBodyCombination? combination) {
    final double customerPrice = item.getPriceForCustomer(_selectedCustomerId);

    setState(() {
      _filledRows[rowIndex]['sizeController'] ??= TextEditingController();
      _filledRows[rowIndex]['lengthController'] ??= TextEditingController();
      _filledRows[rowIndex]['bodyTypeController'] ??= TextEditingController();
      _filledRows[rowIndex]['weightController'] ??= TextEditingController();
      _filledRows[rowIndex]['totalWeightController'] ??= TextEditingController();

      _filledRows[rowIndex]['itemName'] = item.itemName;
      _filledRows[rowIndex]['itemNameController'].text = item.itemName;

      _filledRows[rowIndex]['weightPerUnit'] = null;
      _filledRows[rowIndex]['weightUnit'] = 'kg';
      _filledRows[rowIndex]['lengthBodyCombination'] = null;

      if (combination != null) {
        final double effectiveRate = combination.getPriceForCustomer(_selectedCustomerId);

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
          _filledRows[rowIndex]['weightController'].text = '$weightPerUnit $weightUnit';
          _filledRows[rowIndex]['rate'] = effectiveRate;
          _filledRows[rowIndex]['rateController'].text = effectiveRate.toStringAsFixed(2);
          _filledRows[rowIndex]['calculationType'] = 'weight';
        } else {
          _filledRows[rowIndex]['rate'] = effectiveRate;
          _filledRows[rowIndex]['rateController'].text = effectiveRate.toStringAsFixed(2);
          _filledRows[rowIndex]['calculationType'] = 'quantity';
        }
      } else {
        _filledRows[rowIndex]['sizeController'].text = '';
        _filledRows[rowIndex]['lengthController'].text = '';
        _filledRows[rowIndex]['bodyTypeController'].text = '';
        _filledRows[rowIndex]['size'] = '';
        _filledRows[rowIndex]['length'] = '';
        _filledRows[rowIndex]['bodyType'] = '';
        _filledRows[rowIndex]['rate'] = customerPrice;
        _filledRows[rowIndex]['rateController'].text = customerPrice.toStringAsFixed(2);
        _filledRows[rowIndex]['calculationType'] = 'quantity';
      }

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
                  _calculateInitialTotals();
                });
                double parsedDiscount = double.tryParse(value) ?? 0.0;
                if (parsedDiscount > _calculateSubtotal()) {
                  _discount = _calculateSubtotal();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(languageProvider.isEnglish
                          ? 'Discount cannot be greater than subtotal'
                          : 'رعایت کل رقم سے زیادہ نہیں ہو سکتی'),
                    ),
                  );
                } else {
                  _discount = parsedDiscount;
                }
              },
            ),
            const SizedBox(height: 16),
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
                if (_isAutoReference &&
                    (_selectedCustomerId != null && _selectedCustomerSerial != null)) {
                  final autoRef = await _generateNextReferenceNumber(increment: true);
                  _referenceController.text = autoRef;
                } else if (_referenceController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(languageProvider.isEnglish
                          ? 'Please enter a reference number'
                          : 'براہ کرم رفرنس نمبر درج کریں'),
                    ),
                  );
                  setState(() => _isButtonPressed = false);
                  return;
                }

                if (_selectedCustomerId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(languageProvider.isEnglish
                          ? 'Please select a customer'
                          : 'براہ کرم کسٹمر منتخب کریں'),
                    ),
                  );
                  setState(() => _isButtonPressed = false);
                  return;
                }

                for (var row in _filledRows) {
                  final itemName = row['itemName']?.toString() ?? '';
                  final rate = _parseToDouble(row['rate'] ?? 0);

                  if (itemName.isEmpty) continue;

                  if (rate <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(languageProvider.isEnglish
                            ? 'Rate cannot be zero or less'
                            : 'ریٹ صفر یا اس سے کم نہیں ہو سکتا'),
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
                      content: Text(languageProvider.isEnglish
                          ? 'Discount amount cannot be greater than or equal to the subtotal'
                          : 'ڈسکاؤنٹ کی رقم سب ٹوٹل سے زیادہ یا اس کے برابر نہیں ہو سکتی'),
                    ),
                  );
                  setState(() => _isButtonPressed = false);
                  return;
                }

                final grandTotal = _calculateGrandTotal();
                final filledProvider = Provider.of<QuoteProvider>(context, listen: false);

                String filledNumber = widget.filled?['quoteNumber']?.toString() ??
                    (await filledProvider.getNextQuoteNumber()).toString();

                final items = _filledRows.map((row) {
                  return {
                    'itemName': row['itemName']?.toString() ?? '',
                    'rate': _parseToDouble(row['rate'] ?? 0),
                    'qty': _parseToDouble(row['qty'] ?? 0),
                    'size': row['size']?.toString() ?? '',
                    'length': row['length']?.toString() ?? '',
                    'bodyType': row['bodyType']?.toString() ?? '',
                    'description': row['description']?.toString() ?? '',
                    'total': _parseToDouble(row['total'] ?? 0),
                    'calculationType': row['calculationType']?.toString() ?? 'quantity',
                    'weightPerUnit': row['weightPerUnit'],
                    'weightUnit': row['weightUnit']?.toString() ?? 'kg',
                    'totalWeight': row['totalWeight'],
                    'initialQty': _parseToDouble(row['initialQty'] ?? row['qty'] ?? 0),
                    'initialWeight': _parseToDouble(row['totalWeight'] ?? 0),
                    'lengthBodyCombination': row['lengthBodyCombination'],
                  };
                }).toList();

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

                if (widget.filled?['isFromQuotation'] ?? false) {
                  if (_isAutoReference &&
                      (_selectedCustomerId != null && _selectedCustomerSerial != null)) {
                    final autoRef =
                    await _generateCustomerSerialReference(increment: true);
                    _referenceController.text = autoRef;
                  }

                  await filledProvider.saveQuote(
                    quoteId: filledNumber,
                    quoteNumber: filledNumber,
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
                } else if (widget.filled != null &&
                    widget.filled!['quoteNumber'] != null) {
                  await filledProvider.updateQuote(
                    quoteId: filledNumber,
                    quoteNumber: filledNumber,
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
                } else {
                  await filledProvider.saveQuote(
                    quoteId: filledNumber,
                    quoteNumber: filledNumber,
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

                setState(() {
                  _currentFilled = {
                    'id': filledNumber,
                    'quoteNumber': filledNumber,
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
                      widget.filled == null || (widget.filled!['isFromQuotation'] ?? false)
                          ? (languageProvider.isEnglish
                          ? 'Invoice saved successfully'
                          : 'انوائس کامیابی سے محفوظ ہوگئی')
                          : (languageProvider.isEnglish
                          ? 'Invoice updated successfully'
                          : 'انوائس کامیابی سے تبدیل ہوگئی'),
                    ),
                  ),
                );
              } catch (e, st) {
                print('Error saving invoice: $e\n$st');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(languageProvider.isEnglish
                        ? 'Failed to save invoice: ${e.toString()}'
                        : 'انوائس محفوظ کرنے میں ناکام: ${e.toString()}'),
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
              widget.filled == null || (widget.filled?['isFromQuotation'] ?? false)
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
  }) {
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
    for (var row in _filledRows) {
      double rate = _parseToDouble(row['rate'] ?? 0);
      double qty = _parseToDouble(row['qty'] ?? 0);
      String calculationType = row['calculationType']?.toString() ?? 'quantity';
      double? totalWeight = row['totalWeight'] != null ? _parseToDouble(row['totalWeight']) : null;
      double? weightPerUnit = row['weightPerUnit'] != null ? _parseToDouble(row['weightPerUnit']) : null;

      if (calculationType == 'weight' && totalWeight != null && totalWeight > 0) {
        row['total'] = rate * totalWeight;
      } else if (calculationType == 'weight' && weightPerUnit != null && weightPerUnit > 0) {
        double calculatedWeight = weightPerUnit * qty;
        row['totalWeight'] = calculatedWeight;
        row['total'] = rate * calculatedWeight;
      } else {
        row['total'] = rate * qty;
      }
    }

    _discount = double.tryParse(_discountController.text) ?? 0.0;
    _mazdoori = double.tryParse(_mazdooriController.text) ?? 0.0;
  }

  Widget _buildTotalRow(String label, String value, {
    bool isBold = false,
    double fontSize = 14,
    Color? color,
  }) {
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
          Text(label,
              style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey[700])),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(fontWeight: FontWeight.w600, color: color ?? Colors.teal[700])),
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
              onSelected(Item(
                id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
                itemName: value,
                qtyOnHand: 0, avgCostPricePerKg: 0.0, avgSalePricePerKg: 0.0,
              ));
            }
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Material(
          elevation: 4,
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: options.length,
            separatorBuilder: (context, index) => Divider(height: 1),
            itemBuilder: (context, index) {
              final option = options.elementAt(index);
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
                    if (option.customerSerial != null &&
                        option.customerSerial!.isNotEmpty)
                      Text('Serial: ${option.customerSerial}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    if (isSpecialPrice) Text('Special Price for Customer'),
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
            final filteredItems = searchQuery.isEmpty
                ? items
                : items.where((item) {
              return item.itemName.toLowerCase()
                  .contains(searchQuery.toLowerCase());
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Select Item',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Search Items',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
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
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('${filteredItems.length} items found',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filteredItems.isEmpty
                          ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('No items found',
                                style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                          ],
                        ),
                      )
                          : ListView.separated(
                        shrinkWrap: true,
                        itemCount: filteredItems.length,
                        separatorBuilder: (context, index) => Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];

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
                                  horizontal: 12, vertical: 8),
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
                                  width: 50, height: 50,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    image: DecorationImage(
                                      image: MemoryImage(base64Decode(item.imageBase64!)),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                )
                                    : Container(
                                  width: 50, height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.inventory, size: 24, color: Colors.grey[600]),
                                ),
                              ),
                              title: Text(item.itemName,
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (item.customerSerial != null &&
                                      item.customerSerial!.isNotEmpty)
                                    Text('Serial: ${item.customerSerial}',
                                        style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                  Text('Rs ${displayPrice.toStringAsFixed(2)}',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSpecialPrice
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: isSpecialPrice ? Colors.green : Colors.blue[700])),
                                  if (isSpecialPrice)
                                    Text('Special Price',
                                        style: TextStyle(fontSize: 10, color: Colors.green,
                                            fontStyle: FontStyle.italic)),
                                ],
                              ),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () {
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
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
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
                              Icon(Icons.error_outline, color: Colors.white, size: 48),
                              SizedBox(height: 16),
                              Text('Error loading image',
                                  style: TextStyle(color: Colors.white)),
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