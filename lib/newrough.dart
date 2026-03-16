// import 'dart:convert';
// import 'dart:typed_data';
// import 'dart:ui' as ui;
// import 'package:firebase_database/firebase_database.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:intl/intl.dart';
// import 'package:pdf/pdf.dart';
// import 'package:pdf/widgets.dart' as pw;
// import 'package:printing/printing.dart';
// import 'package:provider/provider.dart';
// import '../Models/itemModel.dart';
// import '../Provider/customerprovider.dart';
// import '../Provider/lanprovider.dart';
// import '../items/AddItems.dart' hide LengthBodyCombination;
//
// class QuotationPage extends StatefulWidget {
//   final String? quotationId;
//   final Map<dynamic, dynamic>? existingQuotation;
//
//   const QuotationPage({
//     super.key,
//     this.quotationId,
//     this.existingQuotation,
//   });
//   @override
//   _QuotationPageState createState() => _QuotationPageState();
// }
//
// class _QuotationPageState extends State<QuotationPage> {
//   List<Item> _items = [];
//   String? _selectedCustomerName;
//   String? _selectedCustomerId;
//   double _discount = 0.0;
//   TextEditingController _discountController = TextEditingController();
//   List<Map<String, dynamic>> _quotationRows = [];
//   final TextEditingController _customerController = TextEditingController();
//   final TextEditingController _dateController = TextEditingController();
//   TextEditingController _referenceController = TextEditingController();
//   TextEditingController _termsController = TextEditingController();
//   Map<String, Map<String, double>> _customerItemPrices = {};
//
//   @override
//   void initState() {
//     super.initState();
//     _fetchItems();
//     _fetchCustomers();
//
//     // Initialize with 5 rows if empty
//     if (_quotationRows.isEmpty) {
//       for (int i = 0; i < 5; i++) {
//         _quotationRows.add({
//           'total': 0.0,
//           'rate': 0.0,
//           'qty': 0.0,
//           'description': '',
//           'itemName': '',
//           'calculationType': 'quantity', // 'quantity' or 'weight'
//           'itemNameController': TextEditingController(),
//           'rateController': TextEditingController(),
//           'qtyController': TextEditingController(),
//           'descriptionController': TextEditingController(),
//         });
//       }
//     }
//
//     // Initialize with current date and time
//     final now = DateTime.now();
//     _dateController.text = DateFormat('yyyy-MM-dd HH:mm').format(now);
//
//     if (widget.existingQuotation != null) {
//       _loadExistingQuotation();
//     }
//   }
//
//   void _loadExistingQuotation() {
//     final quotation = widget.existingQuotation!;
//     final customer = quotation['customer'] as Map<dynamic, dynamic>;
//     final items = quotation['items'] as List<dynamic>;
//
//     setState(() {
//       _selectedCustomerId = customer['id'];
//       _selectedCustomerName = customer['name'];
//       _dateController.text = quotation['date'] ?? DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
//       _referenceController.text = quotation['reference'];
//       _termsController.text = quotation['terms'];
//       _discount = quotation['discount'];
//       _discountController.text = quotation['discount'].toString();
//
//       _quotationRows.clear();
//
//       for (var item in items) {
//         final itemNameController = TextEditingController(
//             text: item['itemName']);
//         final sizeController = TextEditingController(
//             text: item['size'] ?? '');
//         final lengthController = TextEditingController(
//             text: item['length'] ?? '');
//         final bodyTypeController = TextEditingController(
//             text: item['bodyType'] ?? '');
//         final rateController = TextEditingController(
//             text: item['rate'].toString());
//         final qtyController = TextEditingController(
//             text: item['quantity'].toString());
//         final descriptionController = TextEditingController(
//             text: item['description']);
//         final weightController = TextEditingController(
//             text: item['totalWeight'] != null
//                 ? '${item['totalWeight']} ${item['weightUnit'] ?? 'kg'}'
//                 : '');
//
//         _quotationRows.add({
//           'itemName': item['itemName'],
//           'size': item['size'] ?? '',
//           'length': item['length'] ?? '',
//           'bodyType': item['bodyType'] ?? '',
//           'description': item['description'],
//           'qty': item['quantity'],
//           'rate': item['rate'],
//           'total': item['total'],
//           'calculationType': item['calculationType'] ?? 'quantity',
//           'itemNameController': itemNameController,
//           'sizeController': sizeController,
//           'lengthController': lengthController,
//           'bodyTypeController': bodyTypeController,
//           'rateController': rateController,
//           'qtyController': qtyController,
//           'descriptionController': descriptionController,
//           'weightController': weightController,
//           'lengthBodyCombination': item['lengthBodyCombination'],
//           'weightPerUnit': item['weightPerUnit'],
//           'weightUnit': item['weightUnit'],
//           'totalWeight': item['totalWeight'],
//         });
//       }
//     });
//   }
//
//   Future<void> _fetchCustomers() async {
//     final customerProvider = Provider.of<CustomerProvider>(
//         context, listen: false);
//     await customerProvider.fetchCustomers();
//   }
//
//   void _fetchCustomerPrices(String customerId) async {
//     final DatabaseReference pricesRef = FirebaseDatabase.instance.ref().child(
//         'items');
//     final DatabaseEvent snapshot = await pricesRef.once();
//
//     if (snapshot.snapshot.exists) {
//       final Map<dynamic, dynamic> itemsMap = snapshot.snapshot.value as Map<
//           dynamic,
//           dynamic>;
//       Map<String, Map<String, double>> prices = {};
//
//       itemsMap.forEach((itemId, itemData) {
//         final item = itemData as Map<dynamic, dynamic>;
//         if (item['customerBasePrices'] != null) {
//           final customerPrices = item['customerBasePrices'] as Map<
//               dynamic,
//               dynamic>;
//           if (customerPrices.containsKey(customerId)) {
//             final price = double.tryParse(
//                 customerPrices[customerId].toString()) ?? 0.0;
//             if (!prices.containsKey(itemId)) {
//               prices[itemId] = {};
//             }
//             prices[itemId]![customerId] = price;
//           }
//         }
//       });
//
//       setState(() {
//         _customerItemPrices = prices;
//       });
//     }
//   }
//
//   Future<void> _fetchItems() async {
//     try {
//       print('Fetching items...');
//       final DatabaseReference itemsRef = FirebaseDatabase.instance.ref().child(
//           'items');
//       final DatabaseEvent snapshot = await itemsRef.once();
//       print('Snapshot exists: ${snapshot.snapshot.exists}');
//
//       if (snapshot.snapshot.exists) {
//         final Map<dynamic, dynamic> itemsMap = snapshot.snapshot.value as Map<
//             dynamic,
//             dynamic>;
//         print('Items count: ${itemsMap.length}');
//
//         setState(() {
//           _items = itemsMap.entries.map((entry) {
//             print('Processing item: ${entry.key}');
//             return Item.fromMap(
//                 entry.value as Map<dynamic, dynamic>, entry.key as String);
//           }).toList();
//           print('Items loaded: ${_items.length}');
//         });
//       } else {
//         print('No items found in snapshot');
//         setState(() => _items = []);
//       }
//     } catch (e) {
//       print('Error fetching items: $e');
//       setState(() => _items = []);
//     }
//   }
//
//   void _addNewRow() {
//     setState(() {
//       _quotationRows.add({
//         'total': 0.0,
//         'rate': 0.0,
//         'qty': 0.0,
//         'length': '',
//         'bodyType': '',
//         'description': '',
//         'itemName': '',
//         'calculationType': 'quantity', // Default to quantity-based
//         'itemNameController': TextEditingController(),
//         'lengthController': TextEditingController(),
//         'bodyTypeController': TextEditingController(),
//         'rateController': TextEditingController(),
//         'qtyController': TextEditingController(),
//         'descriptionController': TextEditingController(),
//       });
//     });
//   }
//
//   void _updateRow(int index, String field, dynamic value) {
//     setState(() {
//       _quotationRows[index][field] = value;
//
//       if (field == 'rate' || field == 'qty' || field == 'calculationType') {
//         _calculateTotalForRow(index);
//       }
//     });
//   }
//
//   void _calculateTotalForRow(int index) {
//     double rate = _quotationRows[index]['rate'] ?? 0.0;
//     double qty = _quotationRows[index]['qty'] ?? 0.0;
//     String calculationType = _quotationRows[index]['calculationType'] ?? 'quantity';
//
//     double total = 0.0;
//
//     if (calculationType == 'weight') {
//       // For weight-based calculation, we need to calculate weight first
//       if (_quotationRows[index]['weightPerUnit'] != null) {
//         final weightPerUnit = _quotationRows[index]['weightPerUnit'];
//         _quotationRows[index]['totalWeight'] = weightPerUnit! * qty;
//         total = rate * _quotationRows[index]['totalWeight'];
//
//         // Update weight display
//         final weightUnit = _quotationRows[index]['weightUnit'] ?? 'kg';
//         final weightController = _quotationRows[index]['weightController'];
//         if (weightController != null && weightController is TextEditingController) {
//           weightController.text = '${_quotationRows[index]['totalWeight']?.toStringAsFixed(2)} $weightUnit';
//         }
//       }
//     } else {
//       // Quantity-based calculation
//       total = rate * qty;
//
//       // Update total weight when quantity changes for weight display only
//       if (_quotationRows[index]['weightPerUnit'] != null) {
//         final weightPerUnit = _quotationRows[index]['weightPerUnit'];
//         _quotationRows[index]['totalWeight'] = weightPerUnit! * qty;
//
//         // Update weight display
//         final weightUnit = _quotationRows[index]['weightUnit'] ?? 'kg';
//         final weightController = _quotationRows[index]['weightController'];
//         if (weightController != null && weightController is TextEditingController) {
//           weightController.text = '${_quotationRows[index]['totalWeight']?.toStringAsFixed(2)} $weightUnit';
//         }
//       }
//     }
//
//     _quotationRows[index]['total'] = total;
//   }
//
//   void _deleteRow(int index) {
//     setState(() {
//       final deletedRow = _quotationRows[index];
//       deletedRow['itemNameController']?.dispose();
//       deletedRow['sizeController']?.dispose();
//       deletedRow['lengthController']?.dispose();
//       deletedRow['bodyTypeController']?.dispose();
//       deletedRow['rateController']?.dispose();
//       deletedRow['qtyController']?.dispose();
//       deletedRow['descriptionController']?.dispose();
//       _quotationRows.removeAt(index);
//     });
//   }
//
//   double _calculateSubtotal() {
//     return _quotationRows.fold(0.0, (sum, row) => sum + (row['total'] ?? 0.0));
//   }
//
//   double _calculateGrandTotal() {
//     double subtotal = _calculateSubtotal();
//     return subtotal - _discount;
//   }
//
//   Future<Uint8List> _generateQuotationPDF() async {
//     final pdf = pw.Document();
//     final languageProvider = Provider.of<LanguageProvider>(
//         context, listen: false);
//     final customerProvider = Provider.of<CustomerProvider>(
//         context, listen: false);
//
//     if (_selectedCustomerId == null) {
//       throw Exception("No customer selected");
//     }
//
//     final selectedCustomer = customerProvider.customers.firstWhere(
//             (customer) => customer.id == _selectedCustomerId,
//         orElse: () =>
//             Customer(
//                 id: 'unknown', name: 'Unknown Customer', phone: '', address: '',city: '')
//     );
//
//     // Parse the date from controller
//     DateTime quotationDate;
//     try {
//       quotationDate = DateFormat('yyyy-MM-dd HH:mm').parse(_dateController.text);
//     } catch (e) {
//       quotationDate = DateTime.now();
//     }
//
//     final String formattedDateTime = DateFormat('yyyy-MM-dd HH:mm').format(quotationDate);
//
//     // Load images
//     final ByteData logoBytes = await rootBundle.load('assets/images/logo.png');
//     final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
//
//     // Filter out empty rows
//     final nonEmptyRows = _quotationRows.where((row) {
//       final itemName = row['itemNameController']?.text ?? '';
//       final description = row['description'] ?? '';
//       final qty = row['qty'] ?? 0.0;
//       final rate = row['rate'] ?? 0.0;
//
//       return itemName.isNotEmpty || description.isNotEmpty || qty > 0 || rate > 0;
//     }).toList();
//
//     // Create PDF
//     pdf.addPage(
//       pw.Page(
//         pageFormat: PdfPageFormat.a4,
//         margin: const pw.EdgeInsets.all(20),
//         build: (context) {
//           return pw.Column(
//             crossAxisAlignment: pw.CrossAxisAlignment.start,
//             children: [
//               // Header
//               pw.Row(
//                 mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
//                 children: [
//                   pw.Image(logoImage, width: 80, height: 80),
//                   pw.Column(
//                     crossAxisAlignment: pw.CrossAxisAlignment.end,
//                     children: [
//                       pw.Text('Gate Pass', style: pw.TextStyle(
//                           fontSize: 24, fontWeight: pw.FontWeight.bold)),
//                       pw.Text('Date & Time: $formattedDateTime'),
//                       pw.Text('Ref: ${_referenceController.text}'),
//                     ],
//                   ),
//                 ],
//               ),
//
//               pw.SizedBox(height: 20),
//               pw.Divider(),
//
//               // Customer Info
//               pw.Text('To:', style: pw.TextStyle(
//                   fontSize: 16, fontWeight: pw.FontWeight.bold)),
//               pw.Text(selectedCustomer.name),
//               if (selectedCustomer.address.isNotEmpty) pw.Text(
//                   selectedCustomer.address),
//               if (selectedCustomer.phone.isNotEmpty) pw.Text(
//                   'Phone: ${selectedCustomer.phone}'),
//
//               pw.SizedBox(height: 20),
//
//               // Update the items table in PDF generation
//               pw.TableHelper.fromTextArray(
//                 headers: [
//                   'Item Name',
//                   'Length',
//                   'Body Type',
//                   'Description',
//                   'Quantity',
//                   'Weight',
//                   'Calculation',
//                   'Unit Price',
//                   'Total'
//                 ],
//                 data: nonEmptyRows.map((row) {
//                   final combination = row['lengthBodyCombination'] != null
//                       ? LengthBodyCombination.fromMap(Map<String, dynamic>.from(row['lengthBodyCombination']))
//                       : null;
//
//                   String weightInfo = '';
//                   if (combination?.weightPerUnit != null) {
//                     final totalWeight = combination!.weightPerUnit! * (row['qty'] ?? 0.0);
//                     weightInfo = '${totalWeight.toStringAsFixed(2)} ${combination.weightUnit}';
//                   }
//
//                   String calculationType = row['calculationType'] ?? 'quantity';
//                   String calculationText = calculationType == 'weight' ? 'Weight × Rate' : 'Qty × Rate';
//
//                   return [
//                     row['itemName'] ?? '',
//                     row['length'] ?? '',
//                     row['bodyType'] ?? '',
//                     row['description'] ?? '',
//                     (row['qty'] ?? 0).toString(),
//                     weightInfo,
//                     calculationText,
//                     (row['rate'] ?? 0.0).toStringAsFixed(2),
//                     (row['total'] ?? 0.0).toStringAsFixed(2),
//                   ];
//                 }).toList(),
//                 headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
//                 cellAlignment: pw.Alignment.centerRight,
//                 cellAlignments: {0: pw.Alignment.centerLeft, 3: pw.Alignment.centerLeft},
//               ),
//
//               pw.SizedBox(height: 20),
//
//               // Totals
//               pw.Row(
//                 mainAxisAlignment: pw.MainAxisAlignment.end,
//                 children: [
//                   pw.Column(
//                     crossAxisAlignment: pw.CrossAxisAlignment.end,
//                     children: [
//                       pw.Row(
//                         mainAxisSize: pw.MainAxisSize.min,
//                         children: [
//                           pw.Text(
//                               'Subtotal: ', style: pw.TextStyle(fontWeight: pw
//                               .FontWeight.bold)),
//                           pw.Text(_calculateSubtotal().toStringAsFixed(2)),
//                         ],
//                       ),
//                       pw.Row(
//                         mainAxisSize: pw.MainAxisSize.min,
//                         children: [
//                           pw.Text(
//                               'Discount: ', style: pw.TextStyle(fontWeight: pw
//                               .FontWeight.bold)),
//                           pw.Text(_discount.toStringAsFixed(2)),
//                         ],
//                       ),
//                       pw.Divider(),
//                       pw.Row(
//                         mainAxisSize: pw.MainAxisSize.min,
//                         children: [
//                           pw.Text('TOTAL: ',
//                               style: pw.TextStyle(fontSize: 16, fontWeight: pw
//                                   .FontWeight.bold)),
//                           pw.Text(_calculateGrandTotal().toStringAsFixed(2),
//                               style: const pw.TextStyle(fontSize: 16)),
//                         ],
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//
//               pw.SizedBox(height: 30),
//
//               // Terms & Conditions
//               pw.Text('Terms & Conditions:',
//                   style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
//               pw.Text(_termsController.text),
//
//               pw.SizedBox(height: 30),
//
//               // Signature
//               pw.Row(
//                 mainAxisAlignment: pw.MainAxisAlignment.end,
//                 children: [
//                   pw.Column(
//                     children: [
//                       pw.Text('Authorized Signature'),
//                       pw.Container(
//                         width: 150,
//                         height: 2,
//                         decoration: const pw.BoxDecoration(
//                           border: pw.Border(
//                             bottom: pw.BorderSide(width: 1),
//                           ),
//                         ),
//                       ),
//                       pw.Text('For ${selectedCustomer.name}'),
//                     ],
//                   ),
//                 ],
//               ),
//             ],
//           );
//         },
//       ),
//     );
//
//     return pdf.save();
//   }
//
//   Future<void> _saveQuotation() async {
//     final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
//     final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
//
//     if (_selectedCustomerId == null) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text(languageProvider.isEnglish
//             ? 'Please select a customer'
//             : 'براہ کرم کسٹمر منتخب کریں')),
//       );
//       return;
//     }
//
//     if (_quotationRows.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text(languageProvider.isEnglish
//             ? 'Please add at least one item'
//             : 'براہ کرم کم از کم ایک آئٹم شامل کریں')),
//       );
//       return;
//     }
//
//     try {
//       final selectedCustomer = customerProvider.customers.firstWhere(
//               (customer) => customer.id == _selectedCustomerId,
//           orElse: () => Customer(
//             id: 'unknown',
//             name: 'Unknown Customer',
//             phone: '',
//             address: '',
//             city: '',
//           )
//       );
//
//       DateTime? quotationDateTime;
//       try {
//         quotationDateTime = DateFormat('yyyy-MM-dd HH:mm').parse(_dateController.text);
//       } catch (e) {
//         quotationDateTime = DateTime.now();
//       }
//
//       final quotationData = {
//         'customer': {
//           'id': _selectedCustomerId,
//           'name': selectedCustomer.name,
//           'phone': selectedCustomer.phone,
//           'address': selectedCustomer.address,
//         },
//         'date': _dateController.text,
//         'dateTimestamp': quotationDateTime.millisecondsSinceEpoch,
//         'reference': _referenceController.text,
//         'terms': _termsController.text,
//         'subtotal': _calculateSubtotal(),
//         'discount': _discount,
//         'grandTotal': _calculateGrandTotal(),
//         'updatedAt': ServerValue.timestamp,
//         'items': _quotationRows.map((row) {
//           final quantity = row['qty'] ?? 0.0;
//           final combination = row['lengthBodyCombination'] != null
//               ? LengthBodyCombination.fromMap(Map<String, dynamic>.from(row['lengthBodyCombination']))
//               : null;
//
//           double? totalWeight;
//           if (combination != null && combination.weightPerUnit != null) {
//             totalWeight = combination.weightPerUnit! * quantity;
//           }
//
//           return {
//             'itemName': row['itemName'] ?? '',
//             'size': row['size'] ?? '',
//             'length': row['length'] ?? '',
//             'bodyType': row['bodyType'] ?? '',
//             'description': row['description'] ?? '',
//             'quantity': quantity,
//             'rate': row['rate'] ?? 0.0,
//             'total': row['total'] ?? 0.0,
//             'calculationType': row['calculationType'] ?? 'quantity',
//             'lengthBodyCombination': row['lengthBodyCombination'],
//             'weightPerUnit': combination?.weightPerUnit,
//             'weightUnit': combination?.weightUnit ?? 'kg',
//             'totalWeight': totalWeight,
//           };
//         }).toList(),
//       };
//
//       DatabaseReference ref;
//       if (widget.quotationId != null) {
//         ref = FirebaseDatabase.instance.ref().child('quotations').child(widget.quotationId!);
//         await ref.update(quotationData);
//       } else {
//         ref = FirebaseDatabase.instance.ref().child('quotations').push();
//         quotationData['createdAt'] = ServerValue.timestamp;
//         quotationData['createdAtTimestamp'] = DateTime.now().millisecondsSinceEpoch;
//         await ref.set(quotationData);
//       }
//
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text(languageProvider.isEnglish
//             ? 'Quotation saved successfully'
//             : 'کوٹیشن کامیابی سے محفوظ ہو گئی')),
//       );
//
//       if (widget.quotationId != null) {
//         Navigator.pop(context);
//       } else {
//         _resetForm();
//       }
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text(languageProvider.isEnglish
//             ? 'Error saving quotation: $e'
//             : 'کوٹیشن محفوظ کرنے میں خرابی: $e')),
//       );
//     }
//   }
//
//   void _resetForm() {
//     setState(() {
//       _selectedCustomerId = null;
//       _selectedCustomerName = null;
//       _discount = 0.0;
//       _discountController.clear();
//       _referenceController.clear();
//       _dateController.text = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
//       _termsController.clear();
//       _quotationRows = [{
//         'total': 0.0,
//         'rate': 0.0,
//         'qty': 0.0,
//         'size': '',
//         'length': '',
//         'bodyType': '',
//         'description': '',
//         'itemName': '',
//         'calculationType': 'quantity',
//         'weightPerUnit': null,
//         'weightUnit': 'kg',
//         'totalWeight': 0.0,
//         'itemNameController': TextEditingController(),
//         'sizeController': TextEditingController(),
//         'lengthController': TextEditingController(),
//         'bodyTypeController': TextEditingController(),
//         'rateController': TextEditingController(),
//         'qtyController': TextEditingController(),
//         'descriptionController': TextEditingController(),
//         'weightController': TextEditingController(),
//       }];
//     });
//   }
//
//   void _showLengthCombinationDialogForGallery(Item item) {
//     final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
//
//     showDialog(
//       context: context,
//       builder: (context) {
//         return AlertDialog(
//           title: Text(
//             languageProvider.isEnglish ? 'Select Length-Body Combination' : 'لمبائی-جسم کا مجموعہ منتخب کریں',
//           ),
//           content: Container(
//             width: double.maxFinite,
//             constraints: BoxConstraints(maxHeight: 400),
//             child: ListView.builder(
//               shrinkWrap: true,
//               itemCount: item.lengthBodyCombinations!.length,
//               itemBuilder: (context, index) {
//                 final combination = item.lengthBodyCombinations![index];
//                 return Card(
//                   margin: EdgeInsets.symmetric(vertical: 4),
//                   child: ListTile(
//                     title: Text('${item.itemName} (${combination.length} - ${combination.bodyType})'),
//                     subtitle: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         if (combination.lengthDecimal.isNotEmpty)
//                           Text(
//                             'Decimal: ${combination.lengthDecimal}',
//                             style: TextStyle(fontSize: 12, color: Colors.grey),
//                           ),
//                         if (combination.costPricePerKg != null && combination.salePricePerKg != null)
//                           Text(
//                             'Price/Kg: ${combination.salePricePerKg!.toStringAsFixed(2)} PKR',
//                             style: TextStyle(fontSize: 12, color: Colors.green),
//                           ),
//                       ],
//                     ),
//                     trailing: Icon(Icons.arrow_forward),
//                     onTap: () {
//                       Navigator.pop(context);
//                       _addItemWithSpecificCombination(item, combination);
//                     },
//                   ),
//                 );
//               },
//             ),
//           ),
//           actions: [
//             TextButton(
//               onPressed: () => Navigator.pop(context),
//               child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ'),
//             ),
//             TextButton(
//               onPressed: () {
//                 Navigator.pop(context);
//                 _addItemWithSpecificCombination(item, null);
//               },
//               child: Text(languageProvider.isEnglish ? 'Skip' : 'چھوڑ دیں'),
//             ),
//           ],
//         );
//       },
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final languageProvider = Provider.of<LanguageProvider>(context);
//     final screenWidth = MediaQuery
//         .of(context)
//         .size
//         .width;
//
//     return Scaffold(
//       backgroundColor: Colors.grey[50],
//       appBar: _buildAppBar(context, languageProvider),
//       body: ResponsiveLayout(
//         mobile: _buildMobileLayout(context, languageProvider),
//         tablet: _buildTabletLayout(context, languageProvider),
//         desktop: _buildDesktopLayout(context, languageProvider),
//       ),
//     );
//   }
//
//
//
//   PreferredSizeWidget _buildAppBar(BuildContext context,
//       LanguageProvider languageProvider) {
//     return AppBar(
//       elevation: 0,
//       title: Text(
//         languageProvider.isEnglish ? 'Create Gate Pass' : 'گیٹ پاس بنائیں',
//         style: const TextStyle(
//           color: Colors.white,
//           fontWeight: FontWeight.w600,
//           fontSize: 18,
//         ),
//       ),
//       centerTitle: true,
//       flexibleSpace: Container(
//         decoration: const BoxDecoration(
//           gradient: LinearGradient(
//             colors: [Color(0xFFFF8A65), Color(0xFFFFB74D)],
//             begin: Alignment.topLeft,
//             end: Alignment.bottomRight,
//           ),
//         ),
//       ),
//       actions: [
//         _buildAppBarAction(
//           icon: Icons.print_outlined,
//           onPressed: () async {
//             try {
//               final bytes = await _generateQuotationPDF();
//               await Printing.layoutPdf(onLayout: (_) => bytes);
//             } catch (e) {
//               _showSnackBar(context, 'Printing error: ${e.toString()}');
//             }
//           },
//         ),
//       ],
//     );
//   }
//
//   Widget _buildAppBarAction(
//       {required IconData icon, required VoidCallback onPressed}) {
//     return Container(
//       margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
//       child: Material(
//         color: Colors.white.withOpacity(0.2),
//         borderRadius: BorderRadius.circular(8),
//         child: InkWell(
//           borderRadius: BorderRadius.circular(8),
//           onTap: onPressed,
//           child: Padding(
//             padding: const EdgeInsets.all(8),
//             child: Icon(icon, color: Colors.white, size: 20),
//           ),
//         ),
//       ),
//     );
//   }
//
//   Widget _buildMobileLayout(BuildContext context,
//       LanguageProvider languageProvider) {
//     return SingleChildScrollView(
//       padding: const EdgeInsets.all(16.0),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           _buildHeaderSection(context, languageProvider, isMobile: true),
//           const SizedBox(height: 24),
//           _buildCustomerSection(context, languageProvider),
//           const SizedBox(height: 24),
//           _buildItemsSection(context, languageProvider, isMobile: true),
//           const SizedBox(height: 24),
//           _buildDiscountSection(context, languageProvider),
//           const SizedBox(height: 24),
//           _buildTotalsSection(context, languageProvider),
//           const SizedBox(height: 24),
//           _buildTermsSection(context, languageProvider),
//           const SizedBox(height: 32),
//           _buildSaveButton(context, languageProvider),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildTabletLayout(BuildContext context, LanguageProvider languageProvider) {
//     return SingleChildScrollView(
//       padding: const EdgeInsets.all(24.0),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           _buildHeaderSection(context, languageProvider, isMobile: false),
//           const SizedBox(height: 32),
//           Row(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Expanded(
//                 flex: 2,
//                 child: Column(
//                   children: [
//                     _buildCustomerSection(context, languageProvider),
//                     const SizedBox(height: 24),
//                     _buildItemsSection(context, languageProvider, isMobile: false),
//                   ],
//                 ),
//               ),
//               const SizedBox(width: 24),
//               Expanded(
//                 child: Column(
//                   children: [
//                     _buildDiscountSection(context, languageProvider),
//                     const SizedBox(height: 24),
//                     _buildTotalsSection(context, languageProvider),
//                     const SizedBox(height: 24),
//                     _buildTermsSection(context, languageProvider),
//                     const SizedBox(height: 24),
//                     _buildSaveButton(context, languageProvider),
//                   ],
//                 ),
//               ),
//
//             ],
//           ),
//           const SizedBox(height: 32),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildDesktopLayout(BuildContext context, LanguageProvider languageProvider) {
//     return SingleChildScrollView(
//       padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 24.0),
//       child: Center(
//         child: Container(
//           constraints: const BoxConstraints(maxWidth: 1600),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               _buildHeaderSection(context, languageProvider, isMobile: false),
//               const SizedBox(height: 10),
//               Row(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Expanded(
//                     flex: 2,
//                     child: Column(
//                       children: [
//                         _buildCustomerSection(context, languageProvider),
//                         const SizedBox(height: 10),
//                         _buildItemsSection(context, languageProvider, isMobile: false),
//                       ],
//                     ),
//                   ),
//                   const SizedBox(width: 10),
//                   Expanded(
//                     child: Column(
//                       children: [
//                         _buildDiscountSection(context, languageProvider),
//                         const SizedBox(height: 24),
//                         _buildTotalsSection(context, languageProvider),
//                         const SizedBox(height: 24),
//                         _buildTermsSection(context, languageProvider),
//                         const SizedBox(height: 24),
//                         _buildSaveButton(context, languageProvider),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 40),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
//
//   Widget _buildHeaderSection(BuildContext context, LanguageProvider languageProvider, {required bool isMobile}) {
//     return Card(
//       elevation: 2,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: Container(
//         padding: const EdgeInsets.all(20.0),
//         decoration: BoxDecoration(
//           borderRadius: BorderRadius.circular(12),
//           gradient: LinearGradient(
//             colors: [Colors.orange[50]!, Colors.amber[50]!],
//             begin: Alignment.topLeft,
//             end: Alignment.bottomRight,
//           ),
//         ),
//         child: Column(
//           children: [
//             Row(
//               children: [
//                 Icon(Icons.receipt_long, color: Colors.orange[700], size: 24),
//                 const SizedBox(width: 8),
//                 Text(
//                   languageProvider.isEnglish
//                       ? 'Quotation Details'
//                       : 'کوٹیشن کی تفصیلات',
//                   style: TextStyle(
//                     fontSize: 18,
//                     fontWeight: FontWeight.w600,
//                     color: Colors.orange[800],
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 20),
//             if (isMobile) ...[
//               _buildTextField(
//                 controller: _referenceController,
//                 label: languageProvider.isEnglish
//                     ? 'Reference Number'
//                     : 'ریفرنس نمبر',
//                 icon: Icons.tag,
//               ),
//               const SizedBox(height: 16),
//               _buildTextField(
//                 controller: _dateController,
//                 label: languageProvider.isEnglish ? 'Date & Time' : 'تاریخ اور وقت',
//                 icon: Icons.calendar_today,
//                 readOnly: true,
//                 onTap: () => _selectDate(context),
//               ),
//             ] else
//               ...[
//                 Row(
//                   children: [
//                     Expanded(
//                       child: _buildTextField(
//                         controller: _referenceController,
//                         label: languageProvider.isEnglish
//                             ? 'Reference Number'
//                             : 'ریفرنس نمبر',
//                         icon: Icons.tag,
//                       ),
//                     ),
//                     const SizedBox(width: 16),
//                     Expanded(
//                       child: _buildTextField(
//                         controller: _dateController,
//                         label: languageProvider.isEnglish ? 'Date & Time' : 'تاریخ اور وقت',
//                         icon: Icons.calendar_today,
//                         readOnly: true,
//                         onTap: () => _selectDate(context),
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildCustomerSection(BuildContext context, LanguageProvider languageProvider) {
//     return Card(
//       elevation: 2,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: Padding(
//         padding: const EdgeInsets.all(20.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Row(
//               children: [
//                 Icon(Icons.person_outline, color: Colors.blue[700], size: 24),
//                 const SizedBox(width: 8),
//                 Text(
//                   languageProvider.isEnglish
//                       ? 'Customer Information'
//                       : 'کسٹمر کی معلومات',
//                   style: TextStyle(
//                     fontSize: 18,
//                     fontWeight: FontWeight.w600,
//                     color: Colors.blue[800],
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 16),
//             Consumer<CustomerProvider>(
//               builder: (context, customerProvider, _) {
//                 List<Customer> filteredCustomers = customerProvider.customers;
//                 String? manualCustomerName = _customerController.text.trim();
//
//                 if (manualCustomerName.isNotEmpty &&
//                     !customerProvider.customers.any(
//                             (c) => c.name.toLowerCase() == manualCustomerName.toLowerCase()
//                     )) {
//                   filteredCustomers = List.from(customerProvider.customers);
//                   filteredCustomers.insert(0, Customer(
//                     id: 'manual_entry',
//                     name: 'New: $manualCustomerName',
//                     phone: '',
//                     address: '',
//                     city: '',
//                   ));
//                 }
//
//                 return Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     TextField(
//                       controller: _customerController,
//                       decoration: InputDecoration(
//                         labelText: languageProvider.isEnglish
//                             ? 'Search or Enter Customer Name'
//                             : 'کسٹمر تلاش کریں یا نام درج کریں',
//                         hintText: languageProvider.isEnglish
//                             ? 'Type to search or enter new customer'
//                             : 'تلاش کے لیے ٹائپ کریں یا نیا کسٹمر درج کریں',
//                         prefixIcon: Icon(Icons.search, color: Colors.blue[600]),
//                         suffixIcon: _customerController.text.isNotEmpty
//                             ? IconButton(
//                           icon: Icon(Icons.close, size: 20),
//                           onPressed: () {
//                             setState(() {
//                               _customerController.clear();
//                               _selectedCustomerId = null;
//                               _selectedCustomerName = null;
//                             });
//                           },
//                         )
//                             : null,
//                         border: OutlineInputBorder(
//                           borderRadius: BorderRadius.circular(8),
//                           borderSide: BorderSide(color: Colors.grey[300]!),
//                         ),
//                         filled: true,
//                         fillColor: Colors.grey[50],
//                       ),
//                       onChanged: (value) {
//                         setState(() {
//                           if (value.isEmpty) {
//                             _selectedCustomerId = null;
//                             _selectedCustomerName = null;
//                           }
//                           final matchingCustomer = customerProvider.customers.firstWhere(
//                                 (c) => c.name.toLowerCase() == value.toLowerCase(),
//                             orElse: () => Customer(id: '', name: '', phone: '', address: '', city: ''),
//                           );
//                           if (matchingCustomer.id.isNotEmpty) {
//                             _selectedCustomerId = matchingCustomer.id;
//                             _selectedCustomerName = matchingCustomer.name;
//                             _fetchCustomerPrices(matchingCustomer.id);
//                           } else if (value.isNotEmpty) {
//                             _selectedCustomerId = 'manual_${DateTime.now().millisecondsSinceEpoch}';
//                             _selectedCustomerName = value;
//                             setState(() {
//                               _customerItemPrices = {};
//                             });
//                           }
//                         });
//                       },
//                     ),
//                     const SizedBox(height: 8),
//
//                     if (_customerController.text.isNotEmpty && filteredCustomers.isNotEmpty)
//                       Container(
//                         decoration: BoxDecoration(
//                           borderRadius: BorderRadius.circular(8),
//                           border: Border.all(color: Colors.grey[300]!),
//                           color: Colors.white,
//                         ),
//                         child: ListView.builder(
//                           shrinkWrap: true,
//                           physics: const NeverScrollableScrollPhysics(),
//                           itemCount: filteredCustomers.length,
//                           itemBuilder: (context, index) {
//                             final customer = filteredCustomers[index];
//                             final isManualEntry = customer.id == 'manual_entry';
//
//                             return ListTile(
//                               dense: true,
//                               leading: Icon(
//                                 isManualEntry ? Icons.person_add : Icons.person,
//                                 color: isManualEntry ? Colors.green : Colors.blue,
//                               ),
//                               title: Text(
//                                 customer.name,
//                                 style: TextStyle(
//                                   fontWeight: isManualEntry ? FontWeight.bold : FontWeight.normal,
//                                   color: isManualEntry ? Colors.green[700] : Colors.black,
//                                 ),
//                               ),
//                               subtitle: isManualEntry
//                                   ? Text(
//                                 languageProvider.isEnglish
//                                     ? 'Create new customer'
//                                     : 'نیا کسٹمر بنائیں',
//                                 style: TextStyle(color: Colors.green[600], fontSize: 12),
//                               )
//                                   : customer.phone.isNotEmpty
//                                   ? Text(customer.phone)
//                                   : null,
//                               onTap: () {
//                                 setState(() {
//                                   if (isManualEntry) {
//                                     _selectedCustomerId = 'manual_${DateTime.now().millisecondsSinceEpoch}';
//                                     _selectedCustomerName = _customerController.text.trim();
//                                     _customerItemPrices = {};
//                                   } else {
//                                     _selectedCustomerId = customer.id;
//                                     _selectedCustomerName = customer.name;
//                                     _customerController.text = customer.name;
//                                     _fetchCustomerPrices(customer.id);
//                                   }
//                                 });
//                                 FocusScope.of(context).unfocus();
//                               },
//                             );
//                           },
//                         ),
//                       ),
//
//                     if (_selectedCustomerName != null)
//                       Container(
//                         margin: const EdgeInsets.only(top: 12),
//                         padding: const EdgeInsets.all(12),
//                         decoration: BoxDecoration(
//                           color: Colors.blue[50],
//                           borderRadius: BorderRadius.circular(8),
//                           border: Border.all(color: Colors.blue[100]!),
//                         ),
//                         child: Row(
//                           children: [
//                             Icon(
//                               _selectedCustomerId?.startsWith('manual_') ?? false
//                                   ? Icons.person_add_alt_1
//                                   : Icons.person,
//                               color: _selectedCustomerId?.startsWith('manual_') ?? false
//                                   ? Colors.green[700]
//                                   : Colors.blue[700],
//                               size: 20,
//                             ),
//                             const SizedBox(width: 8),
//                             Expanded(
//                               child: Column(
//                                 crossAxisAlignment: CrossAxisAlignment.start,
//                                 children: [
//                                   Text(
//                                     _selectedCustomerName!,
//                                     style: TextStyle(
//                                       fontWeight: FontWeight.bold,
//                                       color: _selectedCustomerId?.startsWith('manual_') ?? false
//                                           ? Colors.green[800]
//                                           : Colors.blue[800],
//                                     ),
//                                   ),
//                                   if (_selectedCustomerId?.startsWith('manual_') ?? false)
//                                     Text(
//                                       languageProvider.isEnglish
//                                           ? 'New Customer (Manual Entry)'
//                                           : 'نیا کسٹمر (دستی درج شدہ)',
//                                       style: TextStyle(
//                                         fontSize: 12,
//                                         color: Colors.green[600],
//                                       ),
//                                     ),
//                                 ],
//                               ),
//                             ),
//                             IconButton(
//                               icon: Icon(Icons.clear, size: 18, color: Colors.grey[600]),
//                               onPressed: () {
//                                 setState(() {
//                                   _selectedCustomerId = null;
//                                   _selectedCustomerName = null;
//                                   _customerController.clear();
//                                   _customerItemPrices = {};
//                                 });
//                               },
//                             ),
//                           ],
//                         ),
//                       ),
//
//                     if (_customerController.text.isNotEmpty &&
//                         _selectedCustomerName == null &&
//                         filteredCustomers.isEmpty)
//                       Padding(
//                         padding: const EdgeInsets.only(top: 8.0),
//                         child: Text(
//                           languageProvider.isEnglish
//                               ? 'Press Enter to use as new customer'
//                               : 'نیا کسٹمر کے طور پر استعمال کرنے کے لیے انٹر دبائیں',
//                           style: TextStyle(
//                             fontSize: 12,
//                             color: Colors.orange[700],
//                             fontStyle: FontStyle.italic,
//                           ),
//                         ),
//                       ),
//                   ],
//                 );
//               },
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   void _addItemToRow(Item item, int rowIndex, LengthBodyCombination? combination) {
//     final customerPrice = item.getPriceForCustomer(_selectedCustomerId);
//
//     setState(() {
//       // Ensure all controllers exist
//       if (_quotationRows[rowIndex]['sizeController'] == null) {
//         _quotationRows[rowIndex]['sizeController'] = TextEditingController();
//       }
//       if (_quotationRows[rowIndex]['lengthController'] == null) {
//         _quotationRows[rowIndex]['lengthController'] = TextEditingController();
//       }
//       if (_quotationRows[rowIndex]['bodyTypeController'] == null) {
//         _quotationRows[rowIndex]['bodyTypeController'] = TextEditingController();
//       }
//       if (_quotationRows[rowIndex]['weightController'] == null) {
//         _quotationRows[rowIndex]['weightController'] = TextEditingController();
//       }
//
//       _quotationRows[rowIndex]['itemName'] = item.itemName;
//       _quotationRows[rowIndex]['itemNameController'].text = item.itemName;
//
//       if (combination != null) {
//         _quotationRows[rowIndex]['sizeController'].text = combination.length;
//         _quotationRows[rowIndex]['lengthController'].text = combination.length;
//         _quotationRows[rowIndex]['bodyTypeController'].text = combination.bodyType;
//         _quotationRows[rowIndex]['size'] = combination.length;
//         _quotationRows[rowIndex]['length'] = combination.length;
//         _quotationRows[rowIndex]['bodyType'] = combination.bodyType;
//         _quotationRows[rowIndex]['lengthBodyCombination'] = combination.toMap();
//
//         // Set weight per unit if available
//         if (combination.weightPerUnit != null) {
//           _quotationRows[rowIndex]['weightPerUnit'] = combination.weightPerUnit;
//           _quotationRows[rowIndex]['weightUnit'] = combination.weightUnit;
//           // Initialize total weight based on default quantity
//           final qty = _quotationRows[rowIndex]['qty'] ?? 1.0;
//           _quotationRows[rowIndex]['totalWeight'] = combination.weightPerUnit! * qty;
//           _quotationRows[rowIndex]['weightController'].text =
//           '${combination.weightPerUnit} ${combination.weightUnit}';
//         }
//       }
//
//       _quotationRows[rowIndex]['rate'] = customerPrice;
//       _quotationRows[rowIndex]['rateController'].text = customerPrice.toString();
//     });
//   }
//
//   void _showLengthCombinationDialog(Item item, int rowIndex) {
//     final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
//     bool isProcessing = false;
//
//     showDialog(
//       context: context,
//       builder: (context) {
//         return StatefulBuilder(
//           builder: (context, setState) {
//             return AlertDialog(
//               title: Text(
//                 languageProvider.isEnglish ? 'Select Length-Body Combination' : 'لمبائی-جسم کا مجموعہ منتخب کریں',
//               ),
//               content: Container(
//                 width: double.maxFinite,
//                 constraints: BoxConstraints(maxHeight: 400),
//                 child: ListView.builder(
//                   shrinkWrap: true,
//                   itemCount: item.lengthBodyCombinations!.length,
//                   itemBuilder: (context, index) {
//                     final combination = item.lengthBodyCombinations![index];
//                     return Card(
//                       margin: EdgeInsets.symmetric(vertical: 4),
//                       child: ListTile(
//                         title: Text('${item.itemName} (${combination.length} - ${combination.bodyType})'),
//                         subtitle: Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             if (combination.lengthDecimal.isNotEmpty)
//                               Text(
//                                 'Decimal: ${combination.lengthDecimal}',
//                                 style: TextStyle(fontSize: 12, color: Colors.grey),
//                               ),
//                             if (combination.weightPerUnit != null)
//                               Text(
//                                 'Weight/Unit: ${combination.weightPerUnit} ${combination.weightUnit}',
//                                 style: TextStyle(fontSize: 12, color: Colors.blue),
//                               ),
//                             if (combination.costPricePerKg != null && combination.salePricePerKg != null)
//                               Text(
//                                 'Price/Kg: ${combination.salePricePerKg!.toStringAsFixed(2)} PKR',
//                                 style: TextStyle(fontSize: 12, color: Colors.green),
//                               ),
//                           ],
//                         ),
//                         trailing: Icon(Icons.arrow_forward),
//                         onTap: () {
//                           if (isProcessing) return;
//                           setState(() { isProcessing = true; });
//                           Navigator.pop(context);
//                           Future.delayed(Duration(milliseconds: 100), () {
//                             _addItemToRow(item, rowIndex, combination);
//                           });
//                         },
//                       ),
//                     );
//                   },
//                 ),
//               ),
//               actions: [
//                 TextButton(
//                   onPressed: () => Navigator.pop(context),
//                   child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ'),
//                 ),
//                 TextButton(
//                   onPressed: () {
//                     if (isProcessing) return;
//                     setState(() { isProcessing = true; });
//                     Navigator.pop(context);
//                     Future.delayed(Duration(milliseconds: 100), () {
//                       _addItemToRow(item, rowIndex, null);
//                     });
//                   },
//                   child: Text(languageProvider.isEnglish ? 'Skip' : 'چھوڑ دیں'),
//                 ),
//               ],
//             );
//           },
//         );
//       },
//     );
//   }
//
//   Widget _buildItemsSection(BuildContext context, LanguageProvider languageProvider,
//       {required bool isMobile})
//   {
//     return Card(
//       elevation: 2,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: Padding(
//         padding: const EdgeInsets.all(20.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Row(
//                   children: [
//                     Icon(Icons.inventory_2_outlined,
//                         color: Colors.green[700], size: 24),
//                     const SizedBox(width: 8),
//                     Text(
//                       languageProvider.isEnglish ? 'Items' : 'آئٹمز',
//                       style: TextStyle(
//                         fontSize: 18,
//                         fontWeight: FontWeight.w600,
//                         color: Colors.green[800],
//                       ),
//                     ),
//                   ],
//                 ),
//                 ElevatedButton.icon(
//                   onPressed: _addNewRow,
//                   icon: const Icon(Icons.add, size: 18),
//                   label: Text(languageProvider.isEnglish
//                       ? 'Add Item' : 'آئٹم شامل کریں'),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.green[600],
//                     foregroundColor: Colors.white,
//                     shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(8)),
//                     padding: const EdgeInsets.symmetric(
//                         horizontal: 16, vertical: 8),
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 16),
//
//             // Updated header with Calculation Type column
//             Container(
//               padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
//               decoration: BoxDecoration(
//                 color: Colors.blue[50],
//                 borderRadius: BorderRadius.circular(8),
//               ),
//               child: Row(
//                 children: [
//                   Expanded(
//                     flex: 2,
//                     child: Text(
//                       languageProvider.isEnglish ? 'Size' : 'سائز',
//                       style: TextStyle(
//                         fontWeight: FontWeight.bold,
//                         color: Colors.blue[800],
//                       ),
//                     ),
//                   ),
//                   Expanded(
//                     child: Text(
//                       languageProvider.isEnglish ? 'Length' : 'لمبائی',
//                       style: TextStyle(
//                         fontWeight: FontWeight.bold,
//                         color: Colors.blue[800],
//                       ),
//                       textAlign: TextAlign.center,
//                     ),
//                   ),
//                   Expanded(
//                     child: Text(
//                       languageProvider.isEnglish ? 'Body Type' : 'باڈی قسم',
//                       style: TextStyle(
//                         fontWeight: FontWeight.bold,
//                         color: Colors.blue[800],
//                       ),
//                       textAlign: TextAlign.center,
//                     ),
//                   ),
//                   Expanded(
//                     flex: 2,
//                     child: Text(
//                       languageProvider.isEnglish ? 'Description' : 'تفصیل',
//                       style: TextStyle(
//                         fontWeight: FontWeight.bold,
//                         color: Colors.blue[800],
//                       ),
//                     ),
//                   ),
//                   Expanded(
//                     child: Text(
//                       languageProvider.isEnglish ? 'Qty' : 'مقدار',
//                       style: TextStyle(
//                         fontWeight: FontWeight.bold,
//                         color: Colors.blue[800],
//                       ),
//                       textAlign: TextAlign.center,
//                     ),
//                   ),
//                   Expanded(
//                     child: Text(
//                       languageProvider.isEnglish ? 'Weight' : 'وزن',
//                       style: TextStyle(
//                         fontWeight: FontWeight.bold,
//                         color: Colors.blue[800],
//                       ),
//                       textAlign: TextAlign.center,
//                     ),
//                   ),
//                   Expanded(
//                     child: Text(
//                       languageProvider.isEnglish ? 'Calc' : 'حساب',
//                       style: TextStyle(
//                         fontWeight: FontWeight.bold,
//                         color: Colors.blue[800],
//                       ),
//                       textAlign: TextAlign.center,
//                     ),
//                   ),
//                   Expanded(
//                     child: Text(
//                       languageProvider.isEnglish ? 'Rate' : 'ریٹ',
//                       style: TextStyle(
//                         fontWeight: FontWeight.bold,
//                         color: Colors.blue[800],
//                       ),
//                       textAlign: TextAlign.center,
//                     ),
//                   ),
//                   Expanded(
//                     child: Text(
//                       languageProvider.isEnglish ? 'Total' : 'کل',
//                       style: TextStyle(
//                         fontWeight: FontWeight.bold,
//                         color: Colors.blue[800],
//                       ),
//                       textAlign: TextAlign.center,
//                     ),
//                   ),
//                   const SizedBox(width: 40),
//                 ],
//               ),
//             ),
//             const SizedBox(height: 8),
//
//             ListView.builder(
//               shrinkWrap: true,
//               physics: const NeverScrollableScrollPhysics(),
//               itemCount: _quotationRows.length,
//               itemBuilder: (context, index) => Padding(
//                 padding: const EdgeInsets.only(bottom: 8),
//                 child: Row(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     // Item Name field - using CustomAutocomplete
//                     Expanded(
//                       flex: 2,
//                       child: CustomAutocomplete(
//                         items: _items,
//                         controller: _quotationRows[index]['itemNameController'],
//                         onSelected: (Item selectedItem) {
//                           // Fix: Ensure itemName is set correctly
//                           setState(() {
//                             _quotationRows[index]['itemName'] = selectedItem.itemName;
//                           });
//
//                           if (selectedItem.lengthBodyCombinations != null &&
//                               selectedItem.lengthBodyCombinations!.isNotEmpty) {
//                             _showLengthCombinationDialog(selectedItem, index);
//                           } else {
//                             _addItemToRow(selectedItem, index, null);
//                           }
//                         },
//                         selectedCustomerId: _selectedCustomerId,
//                         allowManualEntry: true,
//                       ),
//                     ),
//
//                     // Length field (removed Size field)
//                     Expanded(
//                       child: Padding(
//                         padding: const EdgeInsets.symmetric(horizontal: 4),
//                         child: TextField(
//                           controller: _quotationRows[index]['lengthController'] ?? TextEditingController(),
//                           decoration: InputDecoration(
//                             hintText: languageProvider.isEnglish ? 'Length' : 'لمبائی',
//                             border: OutlineInputBorder(
//                               borderRadius: BorderRadius.circular(8),
//                               borderSide: BorderSide(color: Colors.grey[300]!),
//                             ),
//                             contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
//                           ),
//                           maxLines: 1,
//                           textAlign: TextAlign.center,
//                           onChanged: (value) => _updateRow(index, 'length', value),
//                         ),
//                       ),
//                     ),
//
//                     // Body Type field
//                     Expanded(
//                       child: Padding(
//                         padding: const EdgeInsets.symmetric(horizontal: 4),
//                         child: TextField(
//                           controller: _quotationRows[index]['bodyTypeController'] ?? TextEditingController(),
//                           decoration: InputDecoration(
//                             hintText: languageProvider.isEnglish ? 'Body Type' : 'باڈی قسم',
//                             border: OutlineInputBorder(
//                               borderRadius: BorderRadius.circular(8),
//                               borderSide: BorderSide(color: Colors.grey[300]!),
//                             ),
//                             contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
//                           ),
//                           maxLines: 1,
//                           textAlign: TextAlign.center,
//                           onChanged: (value) => _updateRow(index, 'bodyType', value),
//                         ),
//                       ),
//                     ),
//
//                     // Description field
//                     Expanded(
//                       flex: 2,
//                       child: Padding(
//                         padding: const EdgeInsets.symmetric(horizontal: 4),
//                         child: TextField(
//                           controller: _quotationRows[index]['descriptionController'],
//                           decoration: InputDecoration(
//                             hintText: languageProvider.isEnglish ? 'Description' : 'تفصیل',
//                             border: OutlineInputBorder(
//                               borderRadius: BorderRadius.circular(8),
//                               borderSide: BorderSide(color: Colors.grey[300]!),
//                             ),
//                             contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
//                           ),
//                           maxLines: 1,
//                           onChanged: (value) => _updateRow(index, 'description', value),
//                         ),
//                       ),
//                     ),
//
//                     // Quantity field
//                     Expanded(
//                       child: Padding(
//                         padding: const EdgeInsets.symmetric(horizontal: 4),
//                         child: TextField(
//                           controller: _quotationRows[index]['qtyController'],
//                           decoration: InputDecoration(
//                             hintText: languageProvider.isEnglish ? 'Qty' : 'مقدار',
//                             border: OutlineInputBorder(
//                               borderRadius: BorderRadius.circular(8),
//                               borderSide: BorderSide(color: Colors.grey[300]!),
//                             ),
//                             contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
//                           ),
//                           keyboardType: TextInputType.number,
//                           textAlign: TextAlign.center,
//                           onChanged: (value) => _updateRow(index, 'qty', double.tryParse(value) ?? 0.0),
//                         ),
//                       ),
//                     ),
//                     // Weight field (read-only when weight is auto-calculated)
//                     Expanded(
//                       child: Padding(
//                         padding: const EdgeInsets.symmetric(horizontal: 4),
//                         child: TextField(
//                           controller: _quotationRows[index]['weightController'] ?? TextEditingController(),
//                           decoration: InputDecoration(
//                             hintText: languageProvider.isEnglish ? 'Weight' : 'وزن',
//                             border: OutlineInputBorder(
//                               borderRadius: BorderRadius.circular(8),
//                               borderSide: BorderSide(color: Colors.grey[300]!),
//                             ),
//                             contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
//                           ),
//                           maxLines: 1,
//                           textAlign: TextAlign.center,
//                           readOnly: true, // Weight is calculated automatically
//                         ),
//                       ),
//                     ),
//                     // Calculation Type Dropdown
//                     Expanded(
//                       child: Padding(
//                         padding: const EdgeInsets.symmetric(horizontal: 4),
//                         child: Container(
//                           decoration: BoxDecoration(
//                             border: Border.all(color: Colors.grey[300]!),
//                             borderRadius: BorderRadius.circular(8),
//                           ),
//                           child: DropdownButtonHideUnderline(
//                             child: DropdownButton<String>(
//                               value: _quotationRows[index]['calculationType'] ?? 'quantity',
//                               isExpanded: true,
//                               items: [
//                                 DropdownMenuItem(
//                                   value: 'quantity',
//                                   child: Padding(
//                                     padding: const EdgeInsets.symmetric(horizontal: 8),
//                                     child: Text(
//                                       'Qty×Rate',
//                                       style: TextStyle(fontSize: 12),
//                                       textAlign: TextAlign.center,
//                                     ),
//                                   ),
//                                 ),
//                                 DropdownMenuItem(
//                                   value: 'weight',
//                                   child: Padding(
//                                     padding: const EdgeInsets.symmetric(horizontal: 8),
//                                     child: Text(
//                                       'Wt×Rate',
//                                       style: TextStyle(fontSize: 12),
//                                       textAlign: TextAlign.center,
//                                     ),
//                                   ),
//                                 ),
//                               ],
//                               onChanged: (String? value) {
//                                 if (value != null) {
//                                   // Check if weight-based calculation is selected but no weight info available
//                                   if (value == 'weight' &&
//                                       (_quotationRows[index]['weightPerUnit'] == null ||
//                                           _quotationRows[index]['weightUnit'] == null)) {
//                                     // Show warning
//                                     ScaffoldMessenger.of(context).showSnackBar(
//                                       SnackBar(
//                                         content: Text('Weight information is required for weight-based calculation'),
//                                         duration: Duration(seconds: 2),
//                                       ),
//                                     );
//                                     return;
//                                   }
//                                   _updateRow(index, 'calculationType', value);
//                                 }
//                               },
//                             ),
//                           ),
//                         ),
//                       ),
//                     ),
//                     // Rate field
//                     Expanded(
//                       child: Padding(
//                         padding: const EdgeInsets.symmetric(horizontal: 4),
//                         child: TextField(
//                           controller: _quotationRows[index]['rateController'],
//                           decoration: InputDecoration(
//                             hintText: languageProvider.isEnglish ? 'Rate' : 'ریٹ',
//                             border: OutlineInputBorder(
//                               borderRadius: BorderRadius.circular(8),
//                               borderSide: BorderSide(color: Colors.grey[300]!),
//                             ),
//                             contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
//                           ),
//                           keyboardType: TextInputType.number,
//                           textAlign: TextAlign.center,
//                           onChanged: (value) => _updateRow(index, 'rate', double.tryParse(value) ?? 0.0),
//                         ),
//                       ),
//                     ),
//
//                     // Total field
//                     Expanded(
//                       child: Padding(
//                         padding: const EdgeInsets.symmetric(horizontal: 4),
//                         child: TextField(
//                           controller: TextEditingController(
//                             text: (_quotationRows[index]['total'] ?? 0.0).toStringAsFixed(2),
//                           ),
//                           decoration: InputDecoration(
//                             hintText: languageProvider.isEnglish ? 'Total' : 'کل',
//                             border: OutlineInputBorder(
//                               borderRadius: BorderRadius.circular(8),
//                               borderSide: BorderSide(color: Colors.grey[300]!),
//                             ),
//                             contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
//                           ),
//                           readOnly: true,
//                           textAlign: TextAlign.center,
//                         ),
//                       ),
//                     ),
//
//                     // Delete button
//                     SizedBox(
//                       width: 40,
//                       child: IconButton(
//                         icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
//                         onPressed: () => _deleteRow(index),
//                         padding: EdgeInsets.zero,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//
//             Align(
//               alignment: Alignment.centerRight,
//               child: TextButton.icon(
//                 onPressed: _addNewRow,
//                 icon: const Icon(Icons.add, size: 16),
//                 label: Text(languageProvider.isEnglish ? 'Add More Items' : 'مزید آئٹمز شامل کریں'),
//                 style: TextButton.styleFrom(
//                   foregroundColor: Colors.blue,
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildDiscountSection(BuildContext context,
//       LanguageProvider languageProvider) {
//     return Card(
//       elevation: 2,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: Padding(
//         padding: const EdgeInsets.all(20.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Row(
//               children: [
//                 Icon(Icons.discount_outlined, color: Colors.purple[700],
//                     size: 24),
//                 const SizedBox(width: 8),
//                 Text(
//                   languageProvider.isEnglish ? 'Discount' : 'رعایت',
//                   style: TextStyle(
//                     fontSize: 18,
//                     fontWeight: FontWeight.w600,
//                     color: Colors.purple[800],
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 16),
//             _buildTextField(
//               controller: _discountController,
//               label: languageProvider.isEnglish
//                   ? 'Discount Amount'
//                   : 'رعایت کی رقم',
//               icon: Icons.money_off,
//               keyboardType: TextInputType.number,
//               onChanged: (value) {
//                 setState(() {
//                   _discount = double.tryParse(value) ?? 0.0;
//                 });
//               },
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildTotalsSection(BuildContext context,
//       LanguageProvider languageProvider) {
//     return Card(
//       elevation: 3,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: Container(
//         padding: const EdgeInsets.all(20.0),
//         decoration: BoxDecoration(
//           borderRadius: BorderRadius.circular(12),
//           gradient: LinearGradient(
//             colors: [Colors.indigo[50]!, Colors.blue[50]!],
//             begin: Alignment.topLeft,
//             end: Alignment.bottomRight,
//           ),
//         ),
//         child: Column(
//           children: [
//             Row(
//               children: [
//                 Icon(Icons.calculate_outlined, color: Colors.indigo[700],
//                     size: 24),
//                 const SizedBox(width: 8),
//                 Text(
//                   languageProvider.isEnglish ? 'Summary' : 'خلاصہ',
//                   style: TextStyle(
//                     fontSize: 18,
//                     fontWeight: FontWeight.w600,
//                     color: Colors.indigo[800],
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 16),
//             _buildTotalRow(
//               languageProvider.isEnglish ? 'Subtotal:' : 'سب ٹوٹل:',
//               _calculateSubtotal().toStringAsFixed(2),
//             ),
//             const SizedBox(height: 8),
//             _buildTotalRow(
//               languageProvider.isEnglish ? 'Discount:' : 'رعایت:',
//               _discount.toStringAsFixed(2),
//               color: Colors.red[600],
//             ),
//             const Divider(thickness: 2, height: 24),
//             Container(
//               padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
//               decoration: BoxDecoration(
//                 color: Colors.indigo[100],
//                 borderRadius: BorderRadius.circular(8),
//               ),
//               child: _buildTotalRow(
//                 languageProvider.isEnglish ? 'GRAND TOTAL:' : 'مجموعی کل:',
//                 _calculateGrandTotal().toStringAsFixed(2),
//                 isBold: true,
//                 fontSize: 18,
//                 color: Colors.indigo[800],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildTermsSection(BuildContext context,
//       LanguageProvider languageProvider)
//   {
//     return Card(
//       elevation: 2,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: Padding(
//         padding: const EdgeInsets.all(20.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Row(
//               children: [
//                 Icon(Icons.assignment_outlined, color: Colors.teal[700],
//                     size: 24),
//                 const SizedBox(width: 8),
//                 Text(
//                   languageProvider.isEnglish
//                       ? 'Terms & Conditions'
//                       : 'شرائط و ضوابط',
//                   style: TextStyle(
//                     fontSize: 18,
//                     fontWeight: FontWeight.w600,
//                     color: Colors.teal[800],
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 16),
//             TextField(
//               controller: _termsController,
//               decoration: InputDecoration(
//                 hintText: languageProvider.isEnglish
//                     ? 'Enter terms and conditions...'
//                     : 'شرائط و ضوابط درج کریں...',
//                 border: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(8),
//                   borderSide: BorderSide(color: Colors.grey[300]!),
//                 ),
//                 focusedBorder: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(8),
//                   borderSide: BorderSide(color: Colors.teal[400]!, width: 2),
//                 ),
//                 filled: true,
//                 fillColor: Colors.grey[50],
//               ),
//               maxLines: 4,
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildTextField({
//     required TextEditingController controller,
//     required String label,
//     IconData? icon,
//     bool readOnly = false,
//     TextInputType? keyboardType,
//     int maxLines = 1,
//     Function(String)? onChanged,
//     VoidCallback? onTap,
//   })
//   {
//     return TextField(
//       controller: controller,
//       readOnly: readOnly,
//       keyboardType: keyboardType,
//       maxLines: maxLines,
//       onChanged: onChanged,
//       onTap: onTap,
//       decoration: InputDecoration(
//         labelText: label,
//         prefixIcon: icon != null ? Icon(icon, color: Colors.grey[600]) : null,
//         border: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(8),
//           borderSide: BorderSide(color: Colors.grey[300]!),
//         ),
//         focusedBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(8),
//           borderSide: const BorderSide(color: Colors.orange, width: 2),
//         ),
//         filled: true,
//         fillColor: readOnly ? Colors.grey[100] : Colors.grey[50],
//       ),
//     );
//   }
//
//   Widget _buildTotalRow(String label, String value, {
//     bool isBold = false,
//     double fontSize = 14,
//     Color? color,
//   })
//   {
//     return Row(
//       mainAxisAlignment: MainAxisAlignment.spaceBetween,
//       children: [
//         Text(
//           label,
//           style: TextStyle(
//             fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
//             fontSize: fontSize,
//             color: color,
//           ),
//         ),
//         Text(
//           value,
//           style: TextStyle(
//             fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
//             fontSize: fontSize,
//             color: color ?? Colors.grey[800],
//           ),
//         ),
//       ],
//     );
//   }
//
//   void _addItemToQuotation(Item item) {
//     if (item.lengthBodyCombinations != null && item.lengthBodyCombinations!.isNotEmpty) {
//       _showLengthCombinationDialogForGallery(item);
//     } else {
//       _addItemWithSpecificCombination(item, null);
//     }
//   }
//
//
//   void _addItemWithSpecificCombination(Item item, LengthBodyCombination? combination) {
//     final displayPrice = _selectedCustomerId != null
//         ? item.getPriceForCustomer(_selectedCustomerId)
//         : item.salePrice;
//
//     int emptyRowIndex = _quotationRows.indexWhere((row) =>
//     (row['itemName'] as String).isEmpty &&
//         (row['qty'] as double) == 0.0);
//
//     if (emptyRowIndex == -1) {
//       emptyRowIndex = _quotationRows.length;
//       _addNewRow();
//     }
//
//     setState(() {
//       _quotationRows[emptyRowIndex]['itemName'] = item.itemName;
//       _quotationRows[emptyRowIndex]['itemNameController'].text = item.itemName;
//
//       if (combination != null) {
//         _quotationRows[emptyRowIndex]['sizeController'].text = '';
//         _quotationRows[emptyRowIndex]['lengthController'].text = combination.length;
//         _quotationRows[emptyRowIndex]['bodyTypeController'].text = combination.bodyType;
//         _quotationRows[emptyRowIndex]['size'] = '';
//         _quotationRows[emptyRowIndex]['length'] = combination.length;
//         _quotationRows[emptyRowIndex]['bodyType'] = combination.bodyType;
//
//         // Set weight information
//         if (combination.weightPerUnit != null) {
//           _quotationRows[emptyRowIndex]['weightPerUnit'] = combination.weightPerUnit;
//           _quotationRows[emptyRowIndex]['weightUnit'] = combination.weightUnit;
//           _quotationRows[emptyRowIndex]['totalWeight'] = combination.weightPerUnit! * 1.0;
//           _quotationRows[emptyRowIndex]['weightController'] = TextEditingController(
//               text: '${combination.weightPerUnit} ${combination.weightUnit}'
//           );
//         }
//       } else {
//         _quotationRows[emptyRowIndex]['sizeController'].text = '';
//         _quotationRows[emptyRowIndex]['lengthController'].text = '';
//         _quotationRows[emptyRowIndex]['bodyTypeController'].text = '';
//         _quotationRows[emptyRowIndex]['size'] = '';
//         _quotationRows[emptyRowIndex]['length'] = '';
//         _quotationRows[emptyRowIndex]['bodyType'] = '';
//       }
//
//       _quotationRows[emptyRowIndex]['rate'] = displayPrice;
//       _quotationRows[emptyRowIndex]['rateController'].text = displayPrice.toString();
//       _quotationRows[emptyRowIndex]['qty'] = 1.0;
//       _quotationRows[emptyRowIndex]['qtyController'].text = '1';
//       _quotationRows[emptyRowIndex]['total'] = displayPrice * 1.0;
//
//       _quotationRows[emptyRowIndex]['description'] = '';
//       _quotationRows[emptyRowIndex]['descriptionController'].clear();
//
//       if (combination != null) {
//         _quotationRows[emptyRowIndex]['lengthBodyCombination'] = combination.toMap();
//       }
//     });
//   }
//
//   Widget _buildSaveButton(BuildContext context, LanguageProvider languageProvider) {
//     return Row(
//       children: [
//         Expanded(
//           child: ElevatedButton(
//             onPressed:_saveQuotation,
//             style: ElevatedButton.styleFrom(
//               backgroundColor: Colors.orange[300],
//               padding: const EdgeInsets.symmetric(vertical: 16),
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(12),
//               ),
//             ),
//             child: Text(
//               widget.existingQuotation == null
//                   ? (languageProvider.isEnglish ? 'Save Quotation' : ' محفوظ کریں')
//                   : (languageProvider.isEnglish ? 'Update Quotation' : 'اپ ڈیٹ کریں'),
//               style: const TextStyle(
//                 color: Colors.white,
//                 fontSize: 16,
//                 fontWeight: FontWeight.w600,
//               ),
//             ),
//           ),
//         ),
//       ],
//     );
//   }
//
//   Future<void> _selectDate(BuildContext context) async {
//     final DateTime? picked = await showDatePicker(
//       context: context,
//       initialDate: DateTime.now(),
//       firstDate: DateTime(2000),
//       lastDate: DateTime(2100),
//     );
//
//     if (picked != null) {
//       final TimeOfDay? time = await showTimePicker(
//         context: context,
//         initialTime: TimeOfDay.now(),
//       );
//
//       if (time != null) {
//         final DateTime selectedDateTime = DateTime(
//           picked.year,
//           picked.month,
//           picked.day,
//           time.hour,
//           time.minute,
//         );
//         setState(() {
//           _dateController.text = DateFormat('yyyy-MM-dd HH:mm').format(selectedDateTime);
//         });
//       } else {
//         final DateTime selectedDateTime = DateTime(
//           picked.year,
//           picked.month,
//           picked.day,
//           DateTime.now().hour,
//           DateTime.now().minute,
//         );
//         setState(() {
//           _dateController.text = DateFormat('yyyy-MM-dd HH:mm').format(selectedDateTime);
//         });
//       }
//     }
//   }
//
//   void _showSnackBar(BuildContext context, String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         behavior: SnackBarBehavior.floating,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
//       ),
//     );
//   }
//
//   @override
//   void dispose() {
//     for (var row in _quotationRows) {
//       row['itemNameController']?.dispose();
//       row['sizeController']?.dispose();
//       row['lengthController']?.dispose();
//       row['bodyTypeController']?.dispose();
//       row['rateController']?.dispose();
//       row['qtyController']?.dispose();
//       row['descriptionController']?.dispose();
//     }
//     _discountController.dispose();
//     _customerController.dispose();
//     _dateController.dispose();
//     _referenceController.dispose();
//     _termsController.dispose();
//     super.dispose();
//   }
// }
//
// class ResponsiveLayout extends StatelessWidget {
//   final Widget mobile;
//   final Widget tablet;
//   final Widget desktop;
//
//   const ResponsiveLayout({
//     Key? key,
//     required this.mobile,
//     required this.tablet,
//     required this.desktop,
//   }) : super(key: key);
//
//   static bool isMobile(BuildContext context) =>
//       MediaQuery.of(context).size.width < 650;
//
//   static bool isTablet(BuildContext context) =>
//       MediaQuery.of(context).size.width < 1100 &&
//           MediaQuery.of(context).size.width >= 650;
//
//   static bool isDesktop(BuildContext context) =>
//       MediaQuery.of(context).size.width >= 1100;
//
//   @override
//   Widget build(BuildContext context) {
//     return LayoutBuilder(
//       builder: (context, constraints) {
//         if (constraints.maxWidth >= 1100) {
//           return desktop;
//         } else if (constraints.maxWidth >= 650) {
//           return tablet;
//         } else {
//           return mobile;
//         }
//       },
//     );
//   }
// }
//
// class CustomAutocomplete extends StatefulWidget {
//   final List<Item> items;
//   final TextEditingController controller;
//   final Function(Item) onSelected;
//   final String? selectedCustomerId;
//   final bool allowManualEntry;
//
//   const CustomAutocomplete({
//     required this.items,
//     required this.controller,
//     required this.onSelected,
//     required this.selectedCustomerId,
//     this.allowManualEntry = true,
//   });
//
//   @override
//   _CustomAutocompleteState createState() => _CustomAutocompleteState();
// }
//
// class _CustomAutocompleteState extends State<CustomAutocomplete> {
//   @override
//   Widget build(BuildContext context) {
//     return TextField(
//       controller: widget.controller,
//       decoration: InputDecoration(
//         labelText: 'Item',
//         suffixIcon: IconButton(
//           icon: Icon(Icons.search),
//           onPressed: () => _showItemSearchDialog(context),
//         ),
//       ),
//       onChanged: (value) {
//         // You can optionally handle manual entry here
//         // widget.controller.text = value;
//       },
//     );
//   }
//
//   void _showItemSearchDialog(BuildContext context) {
//     TextEditingController searchController = TextEditingController();
//     List<Item> filteredItems = List.from(widget.items);
//
//     showDialog(
//       context: context,
//       builder: (context) {
//         return StatefulBuilder(
//           builder: (context, setState) {
//             void filterItems(String query) {
//               setState(() {
//                 if (query.isEmpty) {
//                   filteredItems = List.from(widget.items);
//                 } else {
//                   filteredItems = widget.items.where((item) {
//                     return item.itemName.toLowerCase().contains(query.toLowerCase());
//                   }).toList();
//                 }
//               });
//             }
//
//             return Dialog(
//               insetPadding: const EdgeInsets.all(16),
//               child: Container(
//                 width: double.maxFinite,
//                 constraints: BoxConstraints(maxHeight: 500),
//                 padding: const EdgeInsets.all(16),
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     // Search field
//                     TextField(
//                       controller: searchController,
//                       decoration: InputDecoration(
//                         labelText: 'Search Items',
//                         prefixIcon: Icon(Icons.search),
//                         border: OutlineInputBorder(),
//                         suffixIcon: searchController.text.isNotEmpty
//                             ? IconButton(
//                           icon: Icon(Icons.clear),
//                           onPressed: () {
//                             searchController.clear();
//                             filterItems('');
//                           },
//                         )
//                             : null,
//                       ),
//                       autofocus: true,
//                       onChanged: filterItems,
//                     ),
//                     const SizedBox(height: 16),
//
//                     // Items list
//                     Expanded(
//                       child: filteredItems.isEmpty
//                           ? Center(
//                         child: Text(
//                           'No items found',
//                           style: TextStyle(color: Colors.grey),
//                         ),
//                       )
//                           : ListView.builder(
//                         shrinkWrap: true,
//                         itemCount: filteredItems.length,
//                         itemBuilder: (context, index) {
//                           final item = filteredItems[index];
//                           final displayPrice = widget.selectedCustomerId != null
//                               ? item.getPriceForCustomer(widget.selectedCustomerId)
//                               : item.salePrice;
//
//                           final isSpecialPrice = widget.selectedCustomerId != null &&
//                               displayPrice != item.costPrice;
//
//                           return Card(
//                             margin: EdgeInsets.symmetric(vertical: 4, horizontal: 0),
//                             child: ListTile(
//                               leading: GestureDetector(
//                                 onTap: () {
//                                   if (item.imageBase64 != null && item.imageBase64!.isNotEmpty) {
//                                     _showImagePreview(context, item.imageBase64!);
//                                   }
//                                 },
//                                 child: item.imageBase64 != null && item.imageBase64!.isNotEmpty
//                                     ? CircleAvatar(
//                                   backgroundImage: MemoryImage(base64Decode(item.imageBase64!)),
//                                   radius: 20,
//                                 )
//                                     : CircleAvatar(
//                                   backgroundColor: Colors.grey[200],
//                                   radius: 20,
//                                   child: Icon(Icons.inventory, size: 20),
//                                 ),
//                               ),
//                               title: Text(
//                                 item.itemName,
//                                 style: TextStyle(fontWeight: FontWeight.w500),
//                               ),
//                               subtitle: Column(
//                                 crossAxisAlignment: CrossAxisAlignment.start,
//                                 children: [
//                                   if (isSpecialPrice)
//                                     Text(
//                                       'Special Price',
//                                       style: TextStyle(
//                                         fontSize: 12,
//                                         color: Colors.green[700],
//                                         fontWeight: FontWeight.bold,
//                                       ),
//                                     ),
//                                   Text(
//                                     '${displayPrice.toStringAsFixed(2)} PKR',
//                                     style: TextStyle(
//                                       fontSize: 14,
//                                       color: Colors.blue[700],
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                               trailing: ElevatedButton(
//                                 onPressed: () {
//                                   _handleItemSelection(item, context);
//                                 },
//                                 style: ElevatedButton.styleFrom(
//                                   backgroundColor: Colors.orange,
//                                   foregroundColor: Colors.white,
//                                   padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                                 ),
//                                 child: Text('Add'),
//                               ),
//                               onTap: () {
//                                 _handleItemSelection(item, context);
//                               },
//                             ),
//                           );
//                         },
//                       ),
//                     ),
//                     const SizedBox(height: 16),
//                     // Close button
//                     Row(
//                       mainAxisAlignment: MainAxisAlignment.end,
//                       children: [
//                         TextButton(
//                           onPressed: () => Navigator.pop(context),
//                           child: Text('Close'),
//                         ),
//                       ],
//                     ),
//                   ],
//                 ),
//               ),
//             );
//           },
//         );
//       },
//     );
//   }
//
//   void _handleItemSelection(Item item, BuildContext context) {
//     if (item.lengthBodyCombinations != null &&
//         item.lengthBodyCombinations!.isNotEmpty) {
//       Navigator.pop(context); // Close search dialog first
//       _showCombinationDialog(item, context);
//     } else {
//       final selectedPrice = widget.selectedCustomerId != null
//           ? item.getPriceForCustomer(widget.selectedCustomerId)
//           : item.salePrice;
//
//       widget.controller.text = item.itemName;
//       widget.onSelected(item.copyWith(
//         costPrice: selectedPrice,
//         salePrice: selectedPrice,
//       ));
//       Navigator.pop(context); // Close search dialog
//     }
//   }
//
//   void _showCombinationDialog(Item item, BuildContext context) {
//     showDialog(
//       context: context,
//       builder: (context) {
//         return AlertDialog(
//           title: Text('Select Length-Body Combination'),
//           content: Container(
//             width: double.maxFinite,
//             constraints: BoxConstraints(maxHeight: 400),
//             child: ListView.builder(
//               shrinkWrap: true,
//               itemCount: item.lengthBodyCombinations!.length,
//               itemBuilder: (context, index) {
//                 final combination = item.lengthBodyCombinations![index];
//                 return Card(
//                   margin: EdgeInsets.symmetric(vertical: 4),
//                   child: ListTile(
//                     title: Text('${item.itemName} (${combination.length} - ${combination.bodyType})'),
//                     subtitle: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         if (combination.lengthDecimal.isNotEmpty)
//                           Text(
//                             'Decimal: ${combination.lengthDecimal}',
//                             style: TextStyle(fontSize: 12, color: Colors.grey),
//                           ),
//                         if (combination.costPricePerKg != null && combination.salePricePerKg != null)
//                           Text(
//                             'Price/Kg: ${combination.salePricePerKg!.toStringAsFixed(2)} PKR',
//                             style: TextStyle(fontSize: 12, color: Colors.green),
//                           ),
//                       ],
//                     ),
//                     trailing: Icon(Icons.arrow_forward),
//                     onTap: () {
//                       Navigator.pop(context); // Close combination dialog
//
//                       final selectedPrice = widget.selectedCustomerId != null
//                           ? item.getPriceForCustomer(widget.selectedCustomerId)
//                           : item.salePrice;
//
//                       widget.controller.text = '${item.itemName} (${combination.length} - ${combination.bodyType})';
//                       widget.onSelected(item.copyWith(
//                         costPrice: selectedPrice,
//                         salePrice: selectedPrice,
//                       ));
//                     },
//                   ),
//                 );
//               },
//             ),
//           ),
//           actions: [
//             TextButton(
//               onPressed: () => Navigator.pop(context),
//               child: Text('Cancel'),
//             ),
//             TextButton(
//               onPressed: () {
//                 Navigator.pop(context); // Close combination dialog
//                 final selectedPrice = widget.selectedCustomerId != null
//                     ? item.getPriceForCustomer(widget.selectedCustomerId)
//                     : item.salePrice;
//
//                 widget.controller.text = item.itemName;
//                 widget.onSelected(item.copyWith(
//                   costPrice: selectedPrice,
//                   salePrice: selectedPrice,
//                 ));
//               },
//               child: Text('Skip'),
//             ),
//           ],
//         );
//       },
//     );
//   }
//
//   void _showImagePreview(BuildContext context, String base64Image) {
//     try {
//       final decodedImage = base64Decode(base64Image);
//
//       showDialog(
//         context: context,
//         builder: (_) => Dialog(
//           insetPadding: const EdgeInsets.all(16),
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Container(
//                 constraints: BoxConstraints(maxHeight: 400, maxWidth: 400),
//                 padding: const EdgeInsets.all(12),
//                 child: Image.memory(
//                   decodedImage,
//                   fit: BoxFit.contain,
//                   errorBuilder: (context, error, stackTrace) {
//                     return Padding(
//                       padding: const EdgeInsets.all(24.0),
//                       child: Text('Error loading image'),
//                     );
//                   },
//                 ),
//               ),
//               TextButton(
//                 onPressed: () => Navigator.pop(context),
//                 child: const Text('Close'),
//               ),
//             ],
//           ),
//         ),
//       );
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Failed to preview image: $e')),
//       );
//     }
//   }
// }