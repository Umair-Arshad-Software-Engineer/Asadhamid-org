// import 'package:flutter/material.dart';
// import 'package:firebase_database/firebase_database.dart';
// import 'package:intl/intl.dart';
// import 'package:provider/provider.dart';
// import '../Provider/lanprovider.dart';
// import 'package:printing/printing.dart';
// import 'package:pdf/pdf.dart';
// import 'package:pdf/widgets.dart' as pw;
// import 'dart:typed_data';
// import 'package:flutter/services.dart';
//
// class ProfitAnalysisPage extends StatefulWidget {
//   const ProfitAnalysisPage({Key? key}) : super(key: key);
//
//   @override
//   _ProfitAnalysisPageState createState() => _ProfitAnalysisPageState();
// }
//
// class _ProfitAnalysisPageState extends State<ProfitAnalysisPage> {
//   final DatabaseReference _db = FirebaseDatabase.instance.ref();
//
//   // Date range for filtering
//   DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
//   DateTime _endDate = DateTime.now();
//
//   // Data structures
//   List<ProfitItem> _profitItems = [];
//   List<Map<String, dynamic>> _purchases = [];
//   List<Map<String, dynamic>> _sales = [];
//
//   bool _isLoading = true;
//   String _selectedFilter = 'All Items'; // All Items, By Item, By Date Range
//   String _selectedItemFilter = '';
//   List<String> _itemNames = [];
//
//   // Summary statistics
//   double _totalPurchaseAmount = 0.0;
//   double _totalSaleAmount = 0.0;
//   double _totalProfit = 0.0;
//   double _profitMargin = 0.0;
//
//   @override
//   void initState() {
//     super.initState();
//     _loadData();
//   }
//
//   Future<void> _loadData() async {
//     setState(() => _isLoading = true);
//
//     try {
//       await Future.wait([
//         _loadPurchases(),
//         _loadSales(),
//       ]);
//
//       _processProfitData();
//       _extractItemNames();
//     } catch (e) {
//       print('Error loading profit data: $e');
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Error loading data: $e')),
//       );
//     } finally {
//       setState(() => _isLoading = false);
//     }
//   }
//
//   Future<void> _loadPurchases() async {
//     final snapshot = await _db.child('purchases').get();
//     if (!snapshot.exists) return;
//
//     final Map<dynamic, dynamic> purchasesMap = snapshot.value as Map<dynamic, dynamic>;
//     _purchases = purchasesMap.entries.map((entry) {
//       final purchase = Map<String, dynamic>.from(entry.value as Map);
//       purchase['key'] = entry.key;
//
//       // Parse timestamp
//       if (purchase['timestamp'] is String) {
//         purchase['date'] = DateTime.parse(purchase['timestamp']);
//       } else {
//         purchase['date'] = DateTime.now();
//       }
//
//       return purchase;
//     }).toList();
//   }
//
//   Future<void> _loadSales() async {
//     // Load from filled (sales/invoices)
//     final snapshot = await _db.child('filled').get();
//     if (!snapshot.exists) return;
//
//     final Map<dynamic, dynamic> salesMap = snapshot.value as Map<dynamic, dynamic>;
//     _sales = salesMap.entries.map((entry) {
//       final sale = Map<String, dynamic>.from(entry.value as Map);
//       sale['key'] = entry.key;
//
//       // Parse createdAt
//       if (sale['createdAt'] is String) {
//         sale['date'] = DateTime.parse(sale['createdAt']);
//       } else {
//         sale['date'] = DateTime.now();
//       }
//
//       return sale;
//     }).toList();
//   }
//
//   void _processProfitData() {
//     // Group by item name and calculate profit
//     Map<String, ProfitItem> profitMap = {};
//
//     // Process purchases
//     for (var purchase in _purchases) {
//       if (!_isWithinDateRange(purchase['date'])) continue;
//
//       final items = purchase['items'] as List<dynamic>? ?? [];
//       for (var item in items) {
//         final itemName = item['itemName']?.toString() ?? '';
//         if (itemName.isEmpty) continue;
//
//         if (_selectedItemFilter.isNotEmpty && itemName != _selectedItemFilter) continue;
//
//         final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
//         final weightPerUnit = (item['weight'] as num?)?.toDouble() ??
//             (item['weightPerUnit'] as num?)?.toDouble() ?? 1.0;
//         final totalWeight = weightPerUnit * quantity;
//         final purchasePrice = (item['purchasePrice'] as num?)?.toDouble() ?? 0.0;
//         final totalCost = totalWeight * purchasePrice; // Weight × Price per kg
//
//         if (!profitMap.containsKey(itemName)) {
//           profitMap[itemName] = ProfitItem(itemName: itemName);
//         }
//
//         profitMap[itemName]!.addPurchase(
//           quantity: quantity,
//           weightPerUnit: weightPerUnit,
//           totalWeight: totalWeight,
//           purchasePrice: purchasePrice,
//           totalCost: totalCost,
//         );
//       }
//     }
//
//     // Process sales
//     for (var sale in _sales) {
//       if (!_isWithinDateRange(sale['date'])) continue;
//
//       final items = sale['items'] as List<dynamic>? ?? [];
//       for (var item in items) {
//         final itemName = item['itemName']?.toString() ?? '';
//         if (itemName.isEmpty) continue;
//
//         if (_selectedItemFilter.isNotEmpty && itemName != _selectedItemFilter) continue;
//
//         final quantity = (item['qty'] as num?)?.toDouble() ?? 0.0;
//         final weightPerUnit = (item['weightPerUnit'] as num?)?.toDouble() ?? 1.0;
//         final totalWeight = (item['totalWeight'] as num?)?.toDouble() ?? (weightPerUnit * quantity);
//         final salePrice = (item['rate'] as num?)?.toDouble() ?? 0.0;
//         final calculationType = item['calculationType']?.toString() ?? 'quantity';
//
//         double totalRevenue;
//         if (calculationType == 'weight') {
//           totalRevenue = salePrice * totalWeight; // Rate × Total Weight
//         } else {
//           totalRevenue = salePrice * quantity; // Rate × Quantity
//         }
//
//         if (!profitMap.containsKey(itemName)) {
//           profitMap[itemName] = ProfitItem(itemName: itemName);
//         }
//
//         profitMap[itemName]!.addSale(
//           quantity: quantity,
//           weightPerUnit: weightPerUnit,
//           totalWeight: totalWeight,
//           salePrice: salePrice,
//           totalRevenue: totalRevenue,
//           calculationType: calculationType,
//         );
//       }
//     }
//
//     // Convert map to list and calculate profits
//     _profitItems = profitMap.values.toList();
//
//     // Calculate totals
//     _totalPurchaseAmount = _profitItems.fold(0.0, (sum, item) => sum + item.totalPurchaseCost);
//     _totalSaleAmount = _profitItems.fold(0.0, (sum, item) => sum + item.totalSaleRevenue);
//     _totalProfit = _totalSaleAmount - _totalPurchaseAmount;
//     _profitMargin = _totalPurchaseAmount > 0 ? (_totalProfit / _totalPurchaseAmount) * 100 : 0.0;
//   }
//
//   void _extractItemNames() {
//     Set<String> names = {};
//
//     for (var purchase in _purchases) {
//       final items = purchase['items'] as List<dynamic>? ?? [];
//       for (var item in items) {
//         final name = item['itemName']?.toString();
//         if (name != null && name.isNotEmpty) names.add(name);
//       }
//     }
//
//     for (var sale in _sales) {
//       final items = sale['items'] as List<dynamic>? ?? [];
//       for (var item in items) {
//         final name = item['itemName']?.toString();
//         if (name != null && name.isNotEmpty) names.add(name);
//       }
//     }
//
//     _itemNames = names.toList()..sort();
//   }
//
//   bool _isWithinDateRange(DateTime date) {
//     return date.isAfter(_startDate.subtract(const Duration(days: 1))) &&
//         date.isBefore(_endDate.add(const Duration(days: 1)));
//   }
//
//   Future<void> _selectDateRange(BuildContext context) async {
//     final DateTimeRange? picked = await showDateRangePicker(
//       context: context,
//       firstDate: DateTime(2000),
//       lastDate: DateTime.now(),
//       initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
//     );
//
//     if (picked != null) {
//       setState(() {
//         _startDate = picked.start;
//         _endDate = picked.end;
//       });
//       _loadData();
//     }
//   }
//
//   Future<Uint8List> _generateProfitReportPDF() async {
//     final pdf = pw.Document();
//     final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
//
//     // Load logo
//     final ByteData logoData = await rootBundle.load('assets/images/logo.png');
//     final Uint8List logoBytes = logoData.buffer.asUint8List();
//     final pw.MemoryImage logoImage = pw.MemoryImage(logoBytes);
//
//     // Load dev logo
//     final ByteData devLogoData = await rootBundle.load('assets/images/devlogo.png');
//     final Uint8List devLogoBytes = devLogoData.buffer.asUint8List();
//     final pw.MemoryImage devLogoImage = pw.MemoryImage(devLogoBytes);
//
//     pdf.addPage(
//       pw.MultiPage(
//         pageFormat: PdfPageFormat.a4,
//         margin: const pw.EdgeInsets.all(20),
//         header: (pw.Context context) {
//           if (context.pageNumber == 1) {
//             return pw.Row(
//               mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
//               children: [
//                 pw.Container(
//                   width: 60,
//                   height: 60,
//                   child: pw.Image(logoImage),
//                 ),
//                 pw.Column(
//                   children: [
//                     pw.Text(
//                       languageProvider.isEnglish ? 'Profit Analysis Report' : 'منافع کا تجزیہ رپورٹ',
//                       style: pw.TextStyle(
//                         fontSize: 20,
//                         fontWeight: pw.FontWeight.bold,
//                         color: PdfColors.blue800,
//                       ),
//                     ),
//                     pw.SizedBox(height: 5),
//                     pw.Text(
//                       '${DateFormat('yyyy-MM-dd').format(_startDate)} to ${DateFormat('yyyy-MM-dd').format(_endDate)}',
//                       style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
//                     ),
//                   ],
//                 ),
//                 pw.Container(width: 60),
//               ],
//             );
//           }
//           return pw.SizedBox();
//         },
//         footer: (pw.Context context) {
//           return pw.Container(
//             decoration: pw.BoxDecoration(
//               border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 1)),
//             ),
//             padding: const pw.EdgeInsets.only(top: 10),
//             child: pw.Row(
//               mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
//               crossAxisAlignment: pw.CrossAxisAlignment.center,
//               children: [
//                 pw.Column(
//                   crossAxisAlignment: pw.CrossAxisAlignment.start,
//                   children: [
//                     pw.Text(
//                       'Umair Arshad',
//                       style: pw.TextStyle(
//                         fontSize: 10,
//                         fontWeight: pw.FontWeight.bold,
//                       ),
//                     ),
//                     pw.Text(
//                       '0341-6426617',
//                       style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
//                     ),
//                   ],
//                 ),
//                 pw.Container(
//                   width: 30,
//                   height: 30,
//                   child: pw.Image(devLogoImage),
//                 ),
//               ],
//             ),
//           );
//         },
//         build: (pw.Context context) => [
//           // Summary Section
//           pw.Container(
//             padding: const pw.EdgeInsets.all(10),
//             decoration: pw.BoxDecoration(
//               border: pw.Border.all(color: PdfColors.blue800, width: 1),
//               borderRadius: pw.BorderRadius.circular(5),
//             ),
//             child: pw.Column(
//               crossAxisAlignment: pw.CrossAxisAlignment.start,
//               children: [
//                 pw.Text(
//                   languageProvider.isEnglish ? 'Summary' : 'خلاصہ',
//                   style: pw.TextStyle(
//                     fontSize: 14,
//                     fontWeight: pw.FontWeight.bold,
//                     color: PdfColors.blue800,
//                   ),
//                 ),
//                 pw.SizedBox(height: 8),
//                 pw.Row(
//                   mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
//                   children: [
//                     pw.Text(
//                       languageProvider.isEnglish ? 'Total Purchase:' : 'کل خریداری:',
//                       style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
//                     ),
//                     pw.Text(
//                       'Rs ${_totalPurchaseAmount.toStringAsFixed(2)}',
//                       style: pw.TextStyle(color: PdfColors.red),
//                     ),
//                   ],
//                 ),
//                 pw.SizedBox(height: 4),
//                 pw.Row(
//                   mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
//                   children: [
//                     pw.Text(
//                       languageProvider.isEnglish ? 'Total Sales:' : 'کل فروخت:',
//                       style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
//                     ),
//                     pw.Text(
//                       'Rs ${_totalSaleAmount.toStringAsFixed(2)}',
//                       style: pw.TextStyle(color: PdfColors.green),
//                     ),
//                   ],
//                 ),
//                 pw.SizedBox(height: 4),
//                 pw.Divider(),
//                 pw.Row(
//                   mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
//                   children: [
//                     pw.Text(
//                       languageProvider.isEnglish ? 'Total Profit:' : 'کل منافع:',
//                       style: pw.TextStyle(
//                         fontWeight: pw.FontWeight.bold,
//                         fontSize: 12,
//                       ),
//                     ),
//                     pw.Text(
//                       'Rs ${_totalProfit.toStringAsFixed(2)}',
//                       style: pw.TextStyle(
//                         fontWeight: pw.FontWeight.bold,
//                         color: _totalProfit >= 0 ? PdfColors.green : PdfColors.red,
//                         fontSize: 12,
//                       ),
//                     ),
//                   ],
//                 ),
//                 pw.SizedBox(height: 4),
//                 pw.Row(
//                   mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
//                   children: [
//                     pw.Text(
//                       languageProvider.isEnglish ? 'Profit Margin:' : 'منافع کا مارجن:',
//                       style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
//                     ),
//                     pw.Text(
//                       '${_profitMargin.toStringAsFixed(2)}%',
//                       style: pw.TextStyle(
//                         color: _profitMargin >= 0 ? PdfColors.green : PdfColors.red,
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//
//           pw.SizedBox(height: 20),
//
//           // Profit by Item Table
//           pw.Text(
//             languageProvider.isEnglish ? 'Profit by Item' : 'آئٹم کے لحاظ سے منافع',
//             style: pw.TextStyle(
//               fontSize: 14,
//               fontWeight: pw.FontWeight.bold,
//               color: PdfColors.blue800,
//             ),
//           ),
//           pw.SizedBox(height: 10),
//
//           pw.TableHelper.fromTextArray(
//             context: context,
//             border: pw.TableBorder.all(),
//             headerDecoration: pw.BoxDecoration(
//               color: PdfColor.fromHex('#FF8A65'),
//             ),
//             headerStyle: pw.TextStyle(
//               color: PdfColors.white,
//               fontWeight: pw.FontWeight.bold,
//               fontSize: 10,
//             ),
//             headers: [
//               languageProvider.isEnglish ? 'Item' : 'آئٹم',
//               languageProvider.isEnglish ? 'Purchase Qty' : 'خریداری مقدار',
//               languageProvider.isEnglish ? 'Purchase Wt' : 'خریداری وزن',
//               languageProvider.isEnglish ? 'Purchase Amt' : 'خریداری رقم',
//               languageProvider.isEnglish ? 'Sale Qty' : 'فروخت مقدار',
//               languageProvider.isEnglish ? 'Sale Wt' : 'فروخت وزن',
//               languageProvider.isEnglish ? 'Sale Amt' : 'فروخت رقم',
//               languageProvider.isEnglish ? 'Profit' : 'منافع',
//               languageProvider.isEnglish ? 'Margin %' : 'مارجن %',
//             ],
//             data: _profitItems.where((item) =>
//             item.totalPurchaseQuantity > 0 || item.totalSaleQuantity > 0
//             ).map((item) {
//               final profit = item.totalSaleRevenue - item.totalPurchaseCost;
//               final margin = item.totalPurchaseCost > 0
//                   ? (profit / item.totalPurchaseCost) * 100
//                   : 0.0;
//
//               return [
//                 item.itemName,
//                 item.totalPurchaseQuantity.toStringAsFixed(2),
//                 item.totalPurchaseWeight.toStringAsFixed(2),
//                 item.totalPurchaseCost.toStringAsFixed(2),
//                 item.totalSaleQuantity.toStringAsFixed(2),
//                 item.totalSaleWeight.toStringAsFixed(2),
//                 item.totalSaleRevenue.toStringAsFixed(2),
//                 profit.toStringAsFixed(2),
//                 '${margin.toStringAsFixed(1)}%',
//               ];
//             }).toList(),
//           ),
//         ],
//       ),
//     );
//
//     return pdf.save();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final languageProvider = Provider.of<LanguageProvider>(context);
//
//     return Scaffold(
//       appBar: AppBar(
//         title: Text(
//           languageProvider.isEnglish ? 'Profit Analysis' : 'منافع کا تجزیہ',
//           style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
//         ),
//         flexibleSpace: Container(
//           decoration: const BoxDecoration(
//             gradient: LinearGradient(
//               colors: [Color(0xFFFF8A65), Color(0xFFFFB74D)],
//               begin: Alignment.topLeft,
//               end: Alignment.bottomRight,
//             ),
//           ),
//         ),
//         centerTitle: true,
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.calendar_today, color: Colors.white),
//             onPressed: () => _selectDateRange(context),
//             tooltip: languageProvider.isEnglish ? 'Select Date Range' : 'تاریخ کی حد منتخب کریں',
//           ),
//           IconButton(
//             icon: const Icon(Icons.refresh, color: Colors.white),
//             onPressed: _loadData,
//             tooltip: languageProvider.isEnglish ? 'Refresh' : 'تازہ کریں',
//           ),
//           IconButton(
//             icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
//             onPressed: () async {
//               try {
//                 final pdfBytes = await _generateProfitReportPDF();
//                 await Printing.layoutPdf(onLayout: (format) => pdfBytes);
//               } catch (e) {
//                 ScaffoldMessenger.of(context).showSnackBar(
//                   SnackBar(content: Text('Error generating PDF: $e')),
//                 );
//               }
//             },
//             tooltip: languageProvider.isEnglish ? 'Print Report' : 'رپورٹ پرنٹ کریں',
//           ),
//         ],
//       ),
//       body: Container(
//         decoration: BoxDecoration(
//           gradient: LinearGradient(
//             begin: Alignment.topCenter,
//             end: Alignment.bottomCenter,
//             colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
//           ),
//         ),
//         child: Column(
//           children: [
//             // Filter Bar
//             Container(
//               padding: const EdgeInsets.all(12),
//               color: Colors.white.withOpacity(0.9),
//               child: Row(
//                 children: [
//                   Expanded(
//                     child: DropdownButtonFormField<String>(
//                       value: _selectedFilter,
//                       decoration: InputDecoration(
//                         labelText: languageProvider.isEnglish ? 'Filter By' : 'فلٹر کریں',
//                         border: OutlineInputBorder(
//                           borderRadius: BorderRadius.circular(8),
//                         ),
//                         contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//                       ),
//                       items: [
//                         DropdownMenuItem(
//                           value: 'All Items',
//                           child: Text(languageProvider.isEnglish ? 'All Items' : 'تمام آئٹمز'),
//                         ),
//                         DropdownMenuItem(
//                           value: 'By Item',
//                           child: Text(languageProvider.isEnglish ? 'By Item' : 'آئٹم کے مطابق'),
//                         ),
//                       ],
//                       onChanged: (value) {
//                         setState(() {
//                           _selectedFilter = value!;
//                           if (_selectedFilter == 'All Items') {
//                             _selectedItemFilter = '';
//                           }
//                         });
//                         _loadData();
//                       },
//                     ),
//                   ),
//                   const SizedBox(width: 12),
//                   if (_selectedFilter == 'By Item')
//                     Expanded(
//                       child: DropdownButtonFormField<String>(
//                         value: _selectedItemFilter.isNotEmpty ? _selectedItemFilter : null,
//                         decoration: InputDecoration(
//                           labelText: languageProvider.isEnglish ? 'Select Item' : 'آئٹم منتخب کریں',
//                           border: OutlineInputBorder(
//                             borderRadius: BorderRadius.circular(8),
//                           ),
//                           contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//                         ),
//                         items: [
//                           ..._itemNames.map((name) => DropdownMenuItem(
//                             value: name,
//                             child: Text(name),
//                           )),
//                         ],
//                         onChanged: (value) {
//                           setState(() {
//                             _selectedItemFilter = value!;
//                           });
//                           _loadData();
//                         },
//                       ),
//                     ),
//                 ],
//               ),
//             ),
//
//             // Date Range Display
//             Container(
//               padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//               color: Colors.orange.shade50,
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Text(
//                     '${DateFormat('yyyy-MM-dd').format(_startDate)} - ${DateFormat('yyyy-MM-dd').format(_endDate)}',
//                     style: TextStyle(
//                       fontWeight: FontWeight.bold,
//                       color: Colors.orange.shade800,
//                     ),
//                   ),
//                   TextButton.icon(
//                     onPressed: () => _selectDateRange(context),
//                     icon: const Icon(Icons.edit_calendar, size: 16),
//                     label: Text(
//                       languageProvider.isEnglish ? 'Change' : 'تبدیل کریں',
//                       style: const TextStyle(fontSize: 12),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//
//             // Summary Cards
//             Container(
//               padding: const EdgeInsets.all(16),
//               child: Row(
//                 children: [
//                   Expanded(
//                     child: _buildSummaryCard(
//                       title: languageProvider.isEnglish ? 'Purchase' : 'خریداری',
//                       amount: _totalPurchaseAmount,
//                       color: Colors.red,
//                       icon: Icons.shopping_cart,
//                     ),
//                   ),
//                   const SizedBox(width: 12),
//                   Expanded(
//                     child: _buildSummaryCard(
//                       title: languageProvider.isEnglish ? 'Sales' : 'فروخت',
//                       amount: _totalSaleAmount,
//                       color: Colors.green,
//                       icon: Icons.attach_money,
//                     ),
//                   ),
//                   const SizedBox(width: 12),
//                   Expanded(
//                     child: _buildSummaryCard(
//                       title: languageProvider.isEnglish ? 'Profit' : 'منافع',
//                       amount: _totalProfit,
//                       color: _totalProfit >= 0 ? Colors.blue : Colors.red,
//                       icon: Icons.trending_up,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//
//             // Profit Margin
//             Container(
//               margin: const EdgeInsets.symmetric(horizontal: 16),
//               padding: const EdgeInsets.all(12),
//               decoration: BoxDecoration(
//                 color: Colors.white,
//                 borderRadius: BorderRadius.circular(12),
//                 boxShadow: [
//                   BoxShadow(
//                     color: Colors.grey.withOpacity(0.3),
//                     blurRadius: 5,
//                     offset: const Offset(0, 2),
//                   ),
//                 ],
//               ),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Text(
//                     languageProvider.isEnglish ? 'Profit Margin:' : 'منافع کا مارجن:',
//                     style: const TextStyle(
//                       fontWeight: FontWeight.bold,
//                       fontSize: 16,
//                     ),
//                   ),
//                   Text(
//                     '${_profitMargin.toStringAsFixed(2)}%',
//                     style: TextStyle(
//                       fontWeight: FontWeight.bold,
//                       fontSize: 18,
//                       color: _profitMargin >= 0 ? Colors.green : Colors.red,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//
//             const SizedBox(height: 16),
//
//             // Profit Items Table
//             Expanded(
//               child: _isLoading
//                   ? const Center(child: CircularProgressIndicator())
//                   : _profitItems.isEmpty
//                   ? Center(
//                 child: Column(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Icon(
//                       Icons.show_chart,
//                       size: 64,
//                       color: Colors.grey.shade400,
//                     ),
//                     const SizedBox(height: 16),
//                     Text(
//                       languageProvider.isEnglish
//                           ? 'No profit data available'
//                           : 'کوئی منافع کا ڈیٹا دستیاب نہیں',
//                       style: TextStyle(
//                         fontSize: 16,
//                         color: Colors.grey.shade600,
//                       ),
//                     ),
//                   ],
//                 ),
//               )
//                   : ListView.builder(
//                 padding: const EdgeInsets.all(16),
//                 itemCount: _profitItems.length,
//                 itemBuilder: (context, index) {
//                   final item = _profitItems[index];
//                   final profit = item.totalSaleRevenue - item.totalPurchaseCost;
//                   final margin = item.totalPurchaseCost > 0
//                       ? (profit / item.totalPurchaseCost) * 100
//                       : 0.0;
//
//                   return Card(
//                     margin: const EdgeInsets.only(bottom: 8),
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(12),
//                     ),
//                     child: ExpansionTile(
//                       leading: CircleAvatar(
//                         backgroundColor: profit >= 0
//                             ? Colors.green.shade100
//                             : Colors.red.shade100,
//                         child: Icon(
//                           profit >= 0
//                               ? Icons.trending_up
//                               : Icons.trending_down,
//                           color: profit >= 0
//                               ? Colors.green
//                               : Colors.red,
//                         ),
//                       ),
//                       title: Text(
//                         item.itemName,
//                         style: const TextStyle(
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                       subtitle: Row(
//                         children: [
//                           Text(
//                             '${languageProvider.isEnglish ? 'Profit' : 'منافع'}: ',
//                             style: const TextStyle(fontSize: 12),
//                           ),
//                           Text(
//                             'Rs ${profit.toStringAsFixed(2)}',
//                             style: TextStyle(
//                               fontSize: 12,
//                               fontWeight: FontWeight.bold,
//                               color: profit >= 0 ? Colors.green : Colors.red,
//                             ),
//                           ),
//                           const SizedBox(width: 8),
//                           Text(
//                             '(${margin.toStringAsFixed(1)}%)',
//                             style: TextStyle(
//                               fontSize: 11,
//                               color: profit >= 0 ? Colors.green : Colors.red,
//                             ),
//                           ),
//                         ],
//                       ),
//                       children: [
//                         Container(
//                           padding: const EdgeInsets.all(16),
//                           decoration: BoxDecoration(
//                             color: Colors.grey.shade50,
//                             borderRadius: const BorderRadius.only(
//                               bottomLeft: Radius.circular(12),
//                               bottomRight: Radius.circular(12),
//                             ),
//                           ),
//                           child: Column(
//                             children: [
//                               // Purchase Details
//                               _buildDetailRow(
//                                 label: languageProvider.isEnglish ? 'Purchase' : 'خریداری',
//                                 color: Colors.red,
//                                 children: [
//                                   _buildDetailItem(
//                                     label: languageProvider.isEnglish ? 'Quantity' : 'مقدار',
//                                     value: '${item.totalPurchaseQuantity.toStringAsFixed(2)}',
//                                   ),
//                                   _buildDetailItem(
//                                     label: languageProvider.isEnglish ? 'Weight' : 'وزن',
//                                     value: '${item.totalPurchaseWeight.toStringAsFixed(2)} kg',
//                                   ),
//                                   _buildDetailItem(
//                                     label: languageProvider.isEnglish ? 'Amount' : 'رقم',
//                                     value: 'Rs ${item.totalPurchaseCost.toStringAsFixed(2)}',
//                                     isBold: true,
//                                   ),
//                                 ],
//                               ),
//                               const Divider(),
//
//                               // Sale Details
//                               _buildDetailRow(
//                                 label: languageProvider.isEnglish ? 'Sale' : 'فروخت',
//                                 color: Colors.green,
//                                 children: [
//                                   _buildDetailItem(
//                                     label: languageProvider.isEnglish ? 'Quantity' : 'مقدار',
//                                     value: '${item.totalSaleQuantity.toStringAsFixed(2)}',
//                                   ),
//                                   _buildDetailItem(
//                                     label: languageProvider.isEnglish ? 'Weight' : 'وزن',
//                                     value: '${item.totalSaleWeight.toStringAsFixed(2)} kg',
//                                   ),
//                                   _buildDetailItem(
//                                     label: languageProvider.isEnglish ? 'Amount' : 'رقم',
//                                     value: 'Rs ${item.totalSaleRevenue.toStringAsFixed(2)}',
//                                     isBold: true,
//                                   ),
//                                 ],
//                               ),
//                               const Divider(),
//
//                               // Profit Details
//                               Container(
//                                 padding: const EdgeInsets.all(12),
//                                 decoration: BoxDecoration(
//                                   color: profit >= 0
//                                       ? Colors.green.shade50
//                                       : Colors.red.shade50,
//                                   borderRadius: BorderRadius.circular(8),
//                                 ),
//                                 child: Row(
//                                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                                   children: [
//                                     Text(
//                                       languageProvider.isEnglish ? 'Profit' : 'منافع',
//                                       style: TextStyle(
//                                         fontWeight: FontWeight.bold,
//                                         color: profit >= 0 ? Colors.green : Colors.red,
//                                       ),
//                                     ),
//                                     Column(
//                                       crossAxisAlignment: CrossAxisAlignment.end,
//                                       children: [
//                                         Text(
//                                           'Rs ${profit.toStringAsFixed(2)}',
//                                           style: TextStyle(
//                                             fontWeight: FontWeight.bold,
//                                             fontSize: 16,
//                                             color: profit >= 0 ? Colors.green : Colors.red,
//                                           ),
//                                         ),
//                                         Text(
//                                           '${margin.toStringAsFixed(1)}%',
//                                           style: TextStyle(
//                                             fontSize: 12,
//                                             color: profit >= 0 ? Colors.green : Colors.red,
//                                           ),
//                                         ),
//                                       ],
//                                     ),
//                                   ],
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                       ],
//                     ),
//                   );
//                 },
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildSummaryCard({
//     required String title,
//     required double amount,
//     required Color color,
//     required IconData icon,
//   }) {
//     return Container(
//       padding: const EdgeInsets.all(12),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.grey.withOpacity(0.3),
//             blurRadius: 5,
//             offset: const Offset(0, 2),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Icon(icon, color: color, size: 20),
//               const SizedBox(width: 4),
//               Text(
//                 title,
//                 style: TextStyle(
//                   fontSize: 12,
//                   color: Colors.grey.shade600,
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 8),
//           Text(
//             'Rs ${amount.toStringAsFixed(2)}',
//             style: TextStyle(
//               fontWeight: FontWeight.bold,
//               fontSize: 14,
//               color: color,
//             ),
//             overflow: TextOverflow.ellipsis,
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildDetailRow({
//     required String label,
//     required Color color,
//     required List<Widget> children,
//   }) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           label,
//           style: TextStyle(
//             fontWeight: FontWeight.bold,
//             color: color,
//             fontSize: 14,
//           ),
//         ),
//         const SizedBox(height: 8),
//         Row(
//           mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//           children: children,
//         ),
//       ],
//     );
//   }
//
//   Widget _buildDetailItem({
//     required String label,
//     required String value,
//     bool isBold = false,
//   }) {
//     return Expanded(
//       child: Column(
//         children: [
//           Text(
//             label,
//             style: TextStyle(
//               fontSize: 10,
//               color: Colors.grey.shade600,
//             ),
//           ),
//           const SizedBox(height: 2),
//           Text(
//             value,
//             style: TextStyle(
//               fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
//               fontSize: 12,
//             ),
//             overflow: TextOverflow.ellipsis,
//           ),
//         ],
//       ),
//     );
//   }
// }
//
// class ProfitItem {
//   final String itemName;
//
//   // Purchase totals
//   double totalPurchaseQuantity = 0.0;
//   double totalPurchaseWeight = 0.0;
//   double totalPurchaseCost = 0.0;
//
//   // Sale totals
//   double totalSaleQuantity = 0.0;
//   double totalSaleWeight = 0.0;
//   double totalSaleRevenue = 0.0;
//
//   ProfitItem({required this.itemName});
//
//   void addPurchase({
//     required double quantity,
//     required double weightPerUnit,
//     required double totalWeight,
//     required double purchasePrice,
//     required double totalCost,
//   }) {
//     totalPurchaseQuantity += quantity;
//     totalPurchaseWeight += totalWeight;
//     totalPurchaseCost += totalCost;
//   }
//
//   void addSale({
//     required double quantity,
//     required double weightPerUnit,
//     required double totalWeight,
//     required double salePrice,
//     required double totalRevenue,
//     required String calculationType,
//   }) {
//     totalSaleQuantity += quantity;
//     totalSaleWeight += totalWeight;
//     totalSaleRevenue += totalRevenue;
//   }
// }