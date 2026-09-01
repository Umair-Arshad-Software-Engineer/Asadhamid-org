import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mughal_group_branch_two/Customer/paymenthistorypage.dart';
import 'package:pdf/pdf.dart';
import 'package:provider/provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../Provider/customerprovider.dart';
import '../Provider/filled provider.dart';
import '../Provider/lanprovider.dart';
import '../bankmanagement/banknames.dart';
import 'addcustomers.dart';
import 'customerratelistpage.dart';

class CustomerList extends StatefulWidget {
  @override
  _CustomerListState createState() => _CustomerListState();
}

class _CustomerListState extends State<CustomerList> {
  TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  Map<String, double> _customerBalances = {};
  Map<String, Map<String, dynamic>> _ledgerCache = {};
  TextEditingController _paymentAmountController = TextEditingController();
  String? _selectedPaymentMethod;
  String? _paymentDescription;
  DateTime _selectedPaymentDate = DateTime.now();
  String? _selectedBankId;
  String? _selectedBankName;
  TextEditingController _chequeNumberController = TextEditingController();
  DateTime? _selectedChequeDate;
  Uint8List? _paymentImage;
  List<Map<String, dynamic>> _cachedBanks = [];
  ScrollController _scrollController = ScrollController();
  bool _isRecordingPayment = false;

  // ── NEW: selection state ──
  bool _isSelectionMode = false;
  Set<String> _selectedCustomerIds = {};

  // Pagination variables
  int _currentPage = 1;
  int _itemsPerPage = 20;
  int _totalCustomers = 0;
  List<Customer> _allCustomers = [];
  List<Customer> _paginatedCustomers = [];
  bool _isLoading = false;
  bool _isSearchingDatabase = false;



  String _receiveMode = 'Cash'; // 'Cash' or 'ItemReturn'
  List<Map<String, dynamic>> _availableItems = []; // fetched from 'items' node
  String? _selectedReturnItemId;
  String? _selectedReturnItemName;
  TextEditingController _returnQtyController = TextEditingController();
  TextEditingController _returnRateController = TextEditingController();
  double get _returnItemTotal {
    final qty = double.tryParse(_returnQtyController.text) ?? 0.0;
    final rate = double.tryParse(_returnRateController.text) ?? 0.0;
    return qty * rate;
  }


  @override
  void initState() {
    super.initState();
    _fetchAllCustomers();
  }

  // ── Selection helpers ──
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) _selectedCustomerIds.clear();
    });
  }

  void _toggleCustomerSelection(String customerId) {
    setState(() {
      if (_selectedCustomerIds.contains(customerId)) {
        _selectedCustomerIds.remove(customerId);
      } else {
        _selectedCustomerIds.add(customerId);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedCustomerIds.length == _allCustomers.length) {
        _selectedCustomerIds.clear();
      } else {
        _selectedCustomerIds = _allCustomers.map((c) => c.id).toSet();
      }
    });
  }

  Future<void> _fetchAvailableItems() async {
    if (_availableItems.isNotEmpty) return; // cache
    try {
      final snapshot = await _db.child('items').get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        _availableItems = data.entries.map((e) {
          final item = e.value as Map<dynamic, dynamic>;
          return {
            'id': e.key.toString(),
            'itemName': item['itemName']?.toString() ?? '',
            'qtyOnHand': (item['qtyOnHand'] as num?)?.toDouble() ?? 0.0,
            'avgSalePricePerKg':
            (item['avgSalePricePerKg'] as num?)?.toDouble() ?? 0.0,
          };
        }).toList();
      }
    } catch (e) {
      print("Error fetching items for return: $e");
    }
  }

  Future<Map<String, dynamic>?> _selectReturnItem(BuildContext context) async {
    await _fetchAvailableItems();
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    Map<String, dynamic>? selected;
    final TextEditingController searchController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final query = searchController.text.toLowerCase();
            final filtered = query.isEmpty
                ? _availableItems
                : _availableItems
                .where((it) => (it['itemName'] as String)
                .toLowerCase()
                .contains(query))
                .toList();
            return AlertDialog(
              title: Text(languageProvider.isEnglish
                  ? 'Select Item to Return'
                  : 'واپس آنے والا آئٹم منتخب کریں'),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: languageProvider.isEnglish
                            ? 'Search item...'
                            : 'آئٹم تلاش کریں...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                          child: Text(languageProvider.isEnglish
                              ? 'No items found'
                              : 'کوئی آئٹم نہیں ملا'))
                          : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return Card(
                            margin:
                            EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text(item['itemName'],
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  'Stock: ${(item['qtyOnHand'] as double).toStringAsFixed(2)} | Rate: ${(item['avgSalePricePerKg'] as double).toStringAsFixed(2)}'),
                              onTap: () {
                                selected = item;
                                Navigator.pop(context);
                              },
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
                  onPressed: () => Navigator.pop(context),
                  child: Text(languageProvider.isEnglish
                      ? 'Cancel'
                      : 'منسوخ کریں'),
                ),
              ],
            );
          },
        );
      },
    );
    return selected;
  }

  List<Customer> get _selectedCustomers =>
      _allCustomers.where((c) => _selectedCustomerIds.contains(c.id)).toList();

  Future<void> _fetchAllCustomers() async {
    setState(() => _isLoading = true);
    try {
      final customerProvider =
      Provider.of<CustomerProvider>(context, listen: false);
      await customerProvider.fetchCustomers();
      _allCustomers = customerProvider.customers;
      _totalCustomers = _allCustomers.length;
      if (_searchQuery.isNotEmpty) {
        _applySearchFilter();
      } else {
        _updatePaginatedCustomers();
      }
      await _loadBalancesForCustomers(_allCustomers);
    } catch (e) {
      print("Error fetching customers: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _searchCustomersFromDatabase() async {
    if (_searchController.text.isEmpty) {
      await _fetchAllCustomers();
      return;
    }
    setState(() {
      _isSearchingDatabase = true;
      _isLoading = true;
    });
    try {
      final customersRef = _db.child('customers');
      final snapshot = await customersRef.get();
      if (snapshot.exists) {
        final allCustomersMap = snapshot.value as Map<dynamic, dynamic>;
        List<Customer> searchResults = [];
        final searchTerm = _searchController.text.toLowerCase();
        allCustomersMap.forEach((key, value) {
          if (value != null && value is Map) {
            final customerName = value['name']?.toString().toLowerCase() ?? '';
            final customerPhone =
                value['phone']?.toString().toLowerCase() ?? '';
            final customerCity = value['city']?.toString().toLowerCase() ?? '';
            final customerAddress =
                value['address']?.toString().toLowerCase() ?? '';
            final customerSerial =
                value['customerSerial']?.toString().toLowerCase() ?? '';
            if (customerName.contains(searchTerm) ||
                customerPhone.contains(searchTerm) ||
                customerCity.contains(searchTerm) ||
                customerAddress.contains(searchTerm) ||
                customerSerial.contains(searchTerm)) {
              searchResults
                  .add(Customer.fromSnapshot(key.toString(), value));
            }
          }
        });
        searchResults.sort((a, b) {
          if (a.customerSerial.isEmpty && b.customerSerial.isEmpty) return 0;
          if (a.customerSerial.isEmpty) return 1;
          if (b.customerSerial.isEmpty) return -1;
          return a.serialNumberValue.compareTo(b.serialNumberValue);
        });
        setState(() {
          _allCustomers = searchResults;
          _totalCustomers = searchResults.length;
          _currentPage = 1;
          _updatePaginatedCustomers();
        });
        await _loadBalancesForCustomers(searchResults);
      }
    } catch (e) {
      print("Error searching customers from database: $e");
    } finally {
      setState(() {
        _isSearchingDatabase = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadBalancesForCustomers(List<Customer> customers) async {
    for (final customer in customers) {
      final balance = await _getRemainingFillesBalance(customer.id);
      _customerBalances[customer.id] = balance;
    }
    setState(() {});
  }

  void _applySearchFilter() {
    if (_searchQuery.isEmpty) {
      _allCustomers =
          Provider.of<CustomerProvider>(context, listen: false).customers;
    } else {
      _allCustomers = Provider.of<CustomerProvider>(context, listen: false)
          .customers
          .where((customer) {
        final name = customer.name.toLowerCase();
        final phone = customer.phone.toLowerCase();
        final address = customer.address.toLowerCase();
        final city = customer.city.toLowerCase();
        final serial = customer.customerSerial.toLowerCase();
        return name.contains(_searchQuery) ||
            phone.contains(_searchQuery) ||
            address.contains(_searchQuery) ||
            city.contains(_searchQuery) ||
            serial.contains(_searchQuery);
      }).toList();
    }
    _totalCustomers = _allCustomers.length;
    _currentPage = 1;
    _updatePaginatedCustomers();
  }

  void _updatePaginatedCustomers() {
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = startIndex + _itemsPerPage;
    setState(() {
      _paginatedCustomers = _allCustomers.sublist(
        startIndex,
        endIndex < _totalCustomers ? endIndex : _totalCustomers,
      );
    });
  }

  void _goToPage(int page) {
    if (page < 1 || page > _totalPages) return;
    setState(() {
      _currentPage = page;
      _updatePaginatedCustomers();
    });
  }

  int get _totalPages => (_totalCustomers / _itemsPerPage).ceil();

  Future<void> _loadCustomerBalances() async {
    await _loadBalancesForCustomers(_allCustomers);
  }

  Future<void> _generateAndPrintCustomerBalances(
      List<Customer> customers) async {
    final pdf = pw.Document();
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    pdf.addPage(
      pw.MultiPage(
        build: (pw.Context context) => [
          pw.Center(
            child: pw.Text(
              languageProvider.isEnglish
                  ? 'Customer Balance List'
                  : 'کسٹمر بیلنس کی فہرست',
              style:
              pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Table.fromTextArray(
            headers: [
              '#',
              languageProvider.isEnglish ? 'Name' : 'نام',
              languageProvider.isEnglish ? 'Phone' : 'فون',
              languageProvider.isEnglish ? 'Address' : 'پتہ',
              languageProvider.isEnglish ? 'City' : 'شہر',
              languageProvider.isEnglish ? 'Balance (Rs)' : 'بیلنس (روپے)',
            ],
            data: customers.asMap().entries.map((entry) {
              final index = entry.key + 1;
              final customer = entry.value;
              final balance =
                  _customerBalances[customer.id]?.toStringAsFixed(2) ?? '0.00';
              return [
                index.toString(),
                customer.name,
                customer.phone,
                customer.address,
                customer.city,
                balance,
              ];
            }).toList(),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  Future<void> _generateCustomerPaymentCollectionPdf(
      List<Customer> customers) async {
    final pdf = pw.Document();
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);

    List<List<String>> tableData = customers.asMap().entries.map((entry) {
      final index = entry.key + 1;
      final customer = entry.value;
      final balance =
          _customerBalances[customer.id]?.toStringAsFixed(2) ?? '0.00';
      return [
        index.toString(),
        customer.name,
        balance,
        '',
        '',
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (pw.Context ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                languageProvider.isEnglish
                    ? 'Customer Payment Collection Sheet'
                    : 'کسٹمر ادائیگی وصولی شیٹ',
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 11),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 4),
          ],
        ),
        footer: (pw.Context ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              languageProvider.isEnglish
                  ? 'Total Customers: ${customers.length}'
                  : 'کل کسٹمرز: ${customers.length}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
        build: (pw.Context ctx) => [
          pw.TableHelper.fromTextArray(
            headers: [
              '#',
              languageProvider.isEnglish ? 'Customer Name' : 'کسٹمر کا نام',
              languageProvider.isEnglish
                  ? 'Remaining Balance (Rs)'
                  : 'باقی بیلنس (روپے)',
              languageProvider.isEnglish ? 'Description' : 'تفصیل',
              languageProvider.isEnglish
                  ? 'Payment Received (Rs)'
                  : 'وصول شدہ ادائیگی (روپے)',
            ],
            data: tableData,
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
                color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFE65100)),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(30),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(2.5),
              3: const pw.FlexColumnWidth(3),
              4: const pw.FlexColumnWidth(2.5),
            },
            rowDecoration: const pw.BoxDecoration(
                border: pw.Border(
                    bottom: pw.BorderSide(
                        color: PdfColors.grey300, width: 0.5))),
            oddRowDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFFFF3E0)),
            cellPadding:
            const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.orange, width: 1),
                borderRadius:
                const pw.BorderRadius.all(pw.Radius.circular(4))),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  languageProvider.isEnglish
                      ? 'Total Outstanding Balance:'
                      : 'کل واجب الادا بیلنس:',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 11),
                ),
                pw.Text(
                  'Rs. ${customers.fold<double>(0.0, (sum, c) => sum + (_customerBalances[c.id] ?? 0.0)).toStringAsFixed(2)}',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 11,
                      color: PdfColors.red),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                pw.Container(width: 150, height: 1, color: PdfColors.black),
                pw.SizedBox(height: 4),
                pw.Text(
                    languageProvider.isEnglish ? 'Prepared By' : 'تیار کردہ',
                    style: const pw.TextStyle(fontSize: 9)),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                pw.Container(width: 150, height: 1, color: PdfColors.black),
                pw.SizedBox(height: 4),
                pw.Text(
                    languageProvider.isEnglish ? 'Verified By' : 'تصدیق کردہ',
                    style: const pw.TextStyle(fontSize: 9)),
              ]),
            ],
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  // ── NEW: show PDF type selection bottom sheet ──
  void _showPdfOptions(List<Customer> customers) {
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                languageProvider.isEnglish
                    ? 'Export ${customers.length} customer(s) as:'
                    : '${customers.length} کسٹمر(ز) برآمد کریں:',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ListTile(
              leading:
              const Icon(Icons.receipt_long, color: Colors.orange),
              title: Text(languageProvider.isEnglish
                  ? 'Payment Collection Sheet'
                  : 'ادائیگی وصولی شیٹ'),
              subtitle: Text(languageProvider.isEnglish
                  ? 'With empty description & payment fields'
                  : 'خالی تفصیل اور ادائیگی خانوں کے ساتھ'),
              onTap: () {
                Navigator.pop(ctx);
                _generateCustomerPaymentCollectionPdf(customers);
              },
            ),
            const Divider(),
            ListTile(
              leading:
              const Icon(Icons.picture_as_pdf, color: Colors.deepOrange),
              title: Text(languageProvider.isEnglish
                  ? 'Balance List'
                  : 'بیلنس فہرست'),
              subtitle: Text(languageProvider.isEnglish
                  ? 'Name, phone, address, city & balance'
                  : 'نام، فون، پتہ، شہر اور بیلنس'),
              onTap: () {
                Navigator.pop(ctx);
                _generateAndPrintCustomerBalances(customers);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<double> _getRemainingFillesBalance(String customerId) async {
    try {
      final customerLedgerRef = _db.child('filledledger').child(customerId);
      final DatabaseEvent snapshot =
      await customerLedgerRef.orderByChild('createdAt').once();
      double remainingBalance = 0.0;
      if (snapshot.snapshot.exists) {
        final Map<dynamic, dynamic> ledgerEntries =
        snapshot.snapshot.value as Map<dynamic, dynamic>;
        ledgerEntries.forEach((key, value) {
          if (value != null && value is Map) {
            final debitAmount = (value['debitAmount'] ?? 0.0).toDouble();
            final creditAmount = (value['creditAmount'] ?? 0.0).toDouble();
            final paymentMethod = value['paymentMethod']?.toString() ?? '';
            final chequeStatus = value['status']?.toString();
            if (paymentMethod.toLowerCase() == 'cheque') {
              if (chequeStatus == 'cleared') {
                remainingBalance =
                    remainingBalance + creditAmount - debitAmount;
              }
            } else {
              remainingBalance =
                  remainingBalance + creditAmount - debitAmount;
            }
          }
        });
      }
      if (_ledgerCache.containsKey(customerId)) {
        _ledgerCache[customerId]!['filledBalance'] = remainingBalance;
      } else {
        _ledgerCache[customerId] = {'filledBalance': remainingBalance};
      }
      return remainingBalance;
    } catch (e) {
      print("Error calculating balance: $e");
      return 0.0;
    }
  }

  Future<Map<String, dynamic>?> _selectBank(BuildContext context) async {
    if (_cachedBanks.isEmpty) {
      final bankSnapshot =
      await FirebaseDatabase.instance.ref('banks').once();
      if (bankSnapshot.snapshot.value == null) return null;
      final banks = bankSnapshot.snapshot.value as Map<dynamic, dynamic>;
      _cachedBanks = banks.entries
          .map((e) => {
        'id': e.key,
        'name': e.value['name'],
        'balance': e.value['balance']
      })
          .toList();
    }
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    Map<String, dynamic>? selectedBank;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(languageProvider.isEnglish
            ? 'Select Bank'
            : 'بینک منتخب کریں'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _cachedBanks.length,
            itemBuilder: (context, index) {
              final bankData = _cachedBanks[index];
              final bankName = bankData['name'];
              Bank? matchedBank = pakistaniBanks.firstWhere(
                    (b) => b.name.toLowerCase() == bankName.toLowerCase(),
                orElse: () =>
                    Bank(name: bankName, iconPath: 'assets/default_bank.png'),
              );
              return Card(
                margin: EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: Image.asset(matchedBank.iconPath,
                      width: 40,
                      height: 40,
                      errorBuilder: (context, error, stackTrace) =>
                          Icon(Icons.account_balance, size: 40)),
                  title: Text(bankName,
                      style: TextStyle(fontWeight: FontWeight.bold)),
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
            child: Text(languageProvider.isEnglish
                ? 'Cancel'
                : 'منسوخ کریں'),
          ),
        ],
      ),
    );
    return selectedBank;
  }

  Future<Uint8List?> _pickImage(BuildContext context) async {
    Uint8List? imageBytes;
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    if (kIsWeb) {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.image, allowMultiple: false);
      if (result != null && result.files.isNotEmpty) {
        imageBytes = result.files.first.bytes;
      }
    } else {
      final ImagePicker _picker = ImagePicker();
      final ImageSource? source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(languageProvider.isEnglish
              ? 'Select Source'
              : 'ذریعہ منتخب کریں'),
          actions: [
            TextButton(
              child: Text(
                  languageProvider.isEnglish ? 'Camera' : 'کیمرہ'),
              onPressed: () =>
                  Navigator.pop(context, ImageSource.camera),
            ),
            TextButton(
              child: Text(
                  languageProvider.isEnglish ? 'Gallery' : 'گیلری'),
              onPressed: () =>
                  Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      );
      if (source == null) return null;
      XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        final file = File(pickedFile.path);
        imageBytes = await file.readAsBytes();
      }
    }
    return imageBytes;
  }

  Future<void> _showPaymentDialog(
      BuildContext context, Customer customer) async {
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    final filledProvider =
    Provider.of<FilledProvider>(context, listen: false);

    // Reset transient state each time dialog opens
    _receiveMode = 'Cash';
    _selectedReturnItemId = null;
    _selectedReturnItemName = null;
    _returnQtyController.clear();
    _returnRateController.clear();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(languageProvider.isEnglish
                  ? 'Receive from Customer'
                  : 'کسٹمر سے وصولی'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── NEW: Cash vs Item Return toggle ──
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _receiveMode = 'Cash'),
                              child: Container(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _receiveMode == 'Cash'
                                      ? Colors.orange
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.horizontal(
                                      left: Radius.circular(7)),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.payments,
                                        color: _receiveMode == 'Cash'
                                            ? Colors.white
                                            : Colors.grey[600]),
                                    Text(
                                      languageProvider.isEnglish
                                          ? 'Payment'
                                          : 'ادائیگی',
                                      style: TextStyle(
                                        color: _receiveMode == 'Cash'
                                            ? Colors.white
                                            : Colors.grey[600],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                await _fetchAvailableItems();
                                setState(() => _receiveMode = 'ItemReturn');
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _receiveMode == 'ItemReturn'
                                      ? Colors.teal
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.horizontal(
                                      right: Radius.circular(7)),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.assignment_return,
                                        color: _receiveMode == 'ItemReturn'
                                            ? Colors.white
                                            : Colors.grey[600]),
                                    Text(
                                      languageProvider.isEnglish
                                          ? 'Item Return'
                                          : 'آئٹم واپسی',
                                      style: TextStyle(
                                        color: _receiveMode == 'ItemReturn'
                                            ? Colors.white
                                            : Colors.grey[600],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Date picker (used by both modes)
                    ListTile(
                      title: Text(languageProvider.isEnglish
                          ? 'Date: ${DateFormat('yyyy-MM-dd – HH:mm').format(_selectedPaymentDate)}'
                          : 'تاریخ: ${DateFormat('yyyy-MM-dd – HH:mm').format(_selectedPaymentDate)}'),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: _selectedPaymentDate,
                          firstDate: DateTime(2000),
                          lastDate:
                          DateTime.now().add(const Duration(days: 365)),
                        );
                        if (pickedDate != null) {
                          final pickedTime = await showTimePicker(
                            context: context,
                            initialTime:
                            TimeOfDay.fromDateTime(_selectedPaymentDate),
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

                    // ============================================
                    // CASH PAYMENT SECTION
                    // ============================================
                    if (_receiveMode == 'Cash') ...[
                      DropdownButtonFormField<String>(
                        value: _selectedPaymentMethod,
                        items: [
                          DropdownMenuItem(
                              value: 'Cash',
                              child: Text(languageProvider.isEnglish
                                  ? 'Cash'
                                  : 'نقدی')),
                          DropdownMenuItem(
                              value: 'Online',
                              child: Text(languageProvider.isEnglish
                                  ? 'Online'
                                  : 'آن لائن')),
                          DropdownMenuItem(
                              value: 'Cheque',
                              child: Text(languageProvider.isEnglish
                                  ? 'Cheque'
                                  : 'چیک')),
                          DropdownMenuItem(
                              value: 'Bank',
                              child: Text(languageProvider.isEnglish
                                  ? 'Bank'
                                  : 'بینک')),
                          DropdownMenuItem(
                              value: 'Slip',
                              child: Text(languageProvider.isEnglish
                                  ? 'Slip'
                                  : 'پرچی')),
                        ],
                        onChanged: (value) =>
                            setState(() => _selectedPaymentMethod = value),
                        decoration: InputDecoration(
                          labelText: languageProvider.isEnglish
                              ? 'Select Payment Method'
                              : 'ادائیگی کا طریقہ منتخب کریں',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      if (_selectedPaymentMethod == 'Cheque') ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _chequeNumberController,
                          decoration: InputDecoration(
                            labelText: languageProvider.isEnglish
                                ? 'Cheque Number'
                                : 'چیک نمبر',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          title: Text(_selectedChequeDate == null
                              ? (languageProvider.isEnglish
                              ? 'Select Cheque Date'
                              : 'چیک کی تاریخ منتخب کریں')
                              : DateFormat('yyyy-MM-dd')
                              .format(_selectedChequeDate!)),
                          trailing: const Icon(Icons.calendar_today),
                          onTap: () async {
                            final pickedDate = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (pickedDate != null)
                              setState(
                                      () => _selectedChequeDate = pickedDate);
                          },
                        ),
                        const SizedBox(height: 8),
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
                      if (_selectedPaymentMethod == 'Bank') ...[
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
                      const SizedBox(height: 16),
                      TextField(
                        controller: _paymentAmountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: languageProvider.isEnglish
                              ? 'Payment Amount'
                              : 'ادائیگی کی رقم',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        onChanged: (value) => _paymentDescription = value,
                        decoration: InputDecoration(
                          labelText: languageProvider.isEnglish
                              ? 'Description'
                              : 'تفصیل',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          final image = await _pickImage(context);
                          if (image != null)
                            setState(() => _paymentImage = image);
                        },
                        child: Text(languageProvider.isEnglish
                            ? 'Upload Receipt'
                            : 'رسید اپ لوڈ کریں'),
                      ),
                      if (_paymentImage != null)
                        Container(
                          margin: const EdgeInsets.only(top: 16),
                          height: 100,
                          width: 100,
                          child: Image.memory(_paymentImage!),
                        ),
                    ],

                    // ============================================
                    // ITEM RETURN SECTION
                    // ============================================
                    if (_receiveMode == 'ItemReturn') ...[
                      const SizedBox(height: 8),
                      Card(
                        color: Colors.teal.shade50,
                        child: ListTile(
                          leading:
                          Icon(Icons.inventory_2, color: Colors.teal),
                          title: Text(_selectedReturnItemName ??
                              (languageProvider.isEnglish
                                  ? 'Select Item'
                                  : 'آئٹم منتخب کریں')),
                          trailing: const Icon(Icons.arrow_drop_down),
                          onTap: () async {
                            final item = await _selectReturnItem(context);
                            if (item != null) {
                              setState(() {
                                _selectedReturnItemId = item['id'];
                                _selectedReturnItemName = item['itemName'];
                                _returnRateController.text =
                                    (item['avgSalePricePerKg'] as double)
                                        .toStringAsFixed(2);
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _returnQtyController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: languageProvider.isEnglish
                                    ? 'Qty'
                                    : 'مقدار',
                                border: const OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _returnRateController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: languageProvider.isEnglish
                                    ? 'Rate'
                                    : 'ریٹ',
                                border: const OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              languageProvider.isEnglish
                                  ? 'Credit Value:'
                                  : 'کریڈٹ ویلیو:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Rs. ${_returnItemTotal.toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal.shade800,
                                  fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        onChanged: (value) => _paymentDescription = value,
                        decoration: InputDecoration(
                          labelText: languageProvider.isEnglish
                              ? 'Description (optional)'
                              : 'تفصیل (اختیاری)',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(languageProvider.isEnglish
                      ? 'Cancel'
                      : 'منسوخ کریں'),
                ),
                // ElevatedButton(
                //   onPressed: _isRecordingPayment
                //       ? null
                //       : () async {
                //     setState(() => _isRecordingPayment = true);
                //
                //     // ============================================
                //     // BRANCH: ITEM RETURN
                //     // ============================================
                //     if (_receiveMode == 'ItemReturn') {
                //       if (_selectedReturnItemId == null) {
                //         ScaffoldMessenger.of(context).showSnackBar(
                //             SnackBar(
                //                 content: Text(languageProvider
                //                     .isEnglish
                //                     ? 'Please select an item'
                //                     : 'براہ کرم آئٹم منتخب کریں')));
                //         setState(() => _isRecordingPayment = false);
                //         return;
                //       }
                //       final qty =
                //       double.tryParse(_returnQtyController.text);
                //       final rate =
                //       double.tryParse(_returnRateController.text);
                //       if (qty == null || qty <= 0) {
                //         ScaffoldMessenger.of(context).showSnackBar(
                //             SnackBar(
                //                 content: Text(languageProvider
                //                     .isEnglish
                //                     ? 'Please enter a valid quantity'
                //                     : 'براہ کرم درست مقدار درج کریں')));
                //         setState(() => _isRecordingPayment = false);
                //         return;
                //       }
                //       if (rate == null || rate <= 0) {
                //         ScaffoldMessenger.of(context).showSnackBar(
                //             SnackBar(
                //                 content: Text(languageProvider
                //                     .isEnglish
                //                     ? 'Please enter a valid rate'
                //                     : 'براہ کرم درست ریٹ درج کریں')));
                //         setState(() => _isRecordingPayment = false);
                //         return;
                //       }
                //
                //       final creditValue = qty * rate;
                //
                //       try {
                //         // 1. Ledger entry — acts like a payment
                //         //    (debitAmount reduces customer balance)
                //         await filledProvider.updateCustomerLedger(
                //           customer.id,
                //           creditAmount: 0.0,
                //           debitAmount: creditValue,
                //           remainingBalance:
                //           (_customerBalances[customer.id] ?? 0.0) -
                //               creditValue,
                //           filledNumber: DateTime.now()
                //               .millisecondsSinceEpoch
                //               .toString(),
                //           referenceNumber: 'Item Return',
                //           transactionDate: _selectedPaymentDate,
                //           paymentMethod: 'Item Return',
                //           description: _paymentDescription ??
                //               'Item return: $_selectedReturnItemName x$qty @ $rate',
                //           chequeNumber: null,
                //           bankId: null,
                //           bankName: null,
                //         );
                //
                //         // 2. Record extra return-specific details in the
                //         //    same ledger entry (item name/qty/rate) so
                //         //    payment history can display them.
                //         final ledgerQuery = await _db
                //             .child('filledledger')
                //             .child(customer.id)
                //             .orderByChild('referenceNumber')
                //             .equalTo('Item Return')
                //             .limitToLast(1)
                //             .get();
                //         if (ledgerQuery.exists) {
                //           final entries = ledgerQuery.value
                //           as Map<dynamic, dynamic>;
                //           final entryKey = entries.keys.last;
                //           await _db
                //               .child('filledledger')
                //               .child(customer.id)
                //               .child(entryKey)
                //               .update({
                //             'itemName': _selectedReturnItemName,
                //             'itemQty': qty,
                //             'itemRate': rate,
                //           });
                //         }
                //
                //         // 3. Restore stock (qtyOnHand)
                //         final itemRef = _db
                //             .child('items')
                //             .child(_selectedReturnItemId!);
                //         final itemSnap = await itemRef.get();
                //         if (itemSnap.exists) {
                //           final currentQty = ((itemSnap.value
                //           as Map)['qtyOnHand'] as num?)
                //               ?.toDouble() ??
                //               0.0;
                //           await itemRef.update({
                //             'qtyOnHand': currentQty + qty,
                //           });
                //         }
                //
                //         setState(() {
                //           _customerBalances[customer.id] =
                //               (_customerBalances[customer.id] ?? 0.0) -
                //                   creditValue;
                //         });
                //
                //         Navigator.pop(context);
                //         ScaffoldMessenger.of(context)
                //             .showSnackBar(SnackBar(
                //           content: Text(languageProvider.isEnglish
                //               ? 'Item return of Rs. ${creditValue.toStringAsFixed(2)} recorded successfully'
                //               : 'آئٹم واپسی $creditValue روپے کامیابی سے ریکارڈ ہو گئی'),
                //           backgroundColor: Colors.green,
                //         ));
                //       } catch (e) {
                //         ScaffoldMessenger.of(context).showSnackBar(
                //             SnackBar(
                //                 content:
                //                 Text('Error: ${e.toString()}')));
                //       } finally {
                //         if (mounted)
                //           setState(
                //                   () => _isRecordingPayment = false);
                //       }
                //       return;
                //     }
                //
                //     // ============================================
                //     // BRANCH: CASH PAYMENT (original logic, unchanged)
                //     // ============================================
                //     if (_selectedPaymentMethod == null) {
                //       ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                //           content: Text(languageProvider.isEnglish
                //               ? 'Please select a payment method'
                //               : 'براہ کرم ادائیگی کا طریقہ منتخب کریں')));
                //       setState(() => _isRecordingPayment = false);
                //       return;
                //     }
                //     final amount = double.tryParse(
                //         _paymentAmountController.text);
                //     if (amount == null || amount <= 0) {
                //       ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                //           content: Text(languageProvider.isEnglish
                //               ? 'Please enter a valid amount'
                //               : 'براہ کرم درست رقم درج کریں')));
                //       setState(() => _isRecordingPayment = false);
                //       return;
                //     }
                //     try {
                //       final filledNumber = DateTime.now()
                //           .millisecondsSinceEpoch
                //           .toString();
                //       await filledProvider.updateCustomerLedger(
                //         customer.id,
                //         creditAmount: 0.0,
                //         debitAmount: amount,
                //         remainingBalance:
                //         (_customerBalances[customer.id] ?? 0.0) -
                //             amount,
                //         filledNumber: filledNumber,
                //         referenceNumber: 'Direct Payment',
                //         transactionDate: _selectedPaymentDate,
                //         paymentMethod: _selectedPaymentMethod,
                //         bankId: _selectedPaymentMethod == 'Bank'
                //             ? _selectedBankId
                //             : (_selectedPaymentMethod == 'Cheque'
                //             ? _selectedBankId
                //             : null),
                //         bankName: _selectedPaymentMethod == 'Bank'
                //             ? _selectedBankName
                //             : (_selectedPaymentMethod == 'Cheque'
                //             ? _selectedBankName
                //             : null),
                //         chequeNumber:
                //         _selectedPaymentMethod == 'Cheque'
                //             ? _chequeNumberController.text
                //             : null,
                //         description: _paymentDescription ??
                //             'Payment from ${customer.name}',
                //       );
                //       if (_selectedPaymentMethod == 'Cash') {
                //         await filledProvider.addCashBookEntry(
                //           description: _paymentDescription ??
                //               'Payment from ${customer.name}',
                //           amount: amount,
                //           dateTime: _selectedPaymentDate,
                //           type: 'cash_in',
                //         );
                //       } else if (_selectedPaymentMethod == 'Cheque') {
                //         if (_selectedBankId == null ||
                //             _selectedBankName == null)
                //           throw Exception(
                //               "Bank not selected for cheque payment");
                //         if (_chequeNumberController.text.isEmpty)
                //           throw Exception("Cheque number is required");
                //         if (_selectedChequeDate == null)
                //           throw Exception("Cheque date is required");
                //         await _db
                //             .child(
                //             'banks/${_selectedBankId}/cheques')
                //             .push()
                //             .set({
                //           'customerId': customer.id,
                //           'customerName': customer.name,
                //           'amount': amount,
                //           'chequeNumber':
                //           _chequeNumberController.text,
                //           'chequeDate':
                //           _selectedChequeDate!.toIso8601String(),
                //           'status': 'pending',
                //           'createdAt':
                //           _selectedPaymentDate.toIso8601String(),
                //           'bankName': _selectedBankName,
                //         });
                //       } else if (_selectedPaymentMethod == 'Bank' &&
                //           _selectedBankId != null) {
                //         await _db
                //             .child(
                //             'banks/${_selectedBankId}/transactions')
                //             .push()
                //             .set({
                //           'amount': amount,
                //           'description': _paymentDescription ??
                //               'Payment from ${customer.name}',
                //           'type': 'cash_in',
                //           'timestamp': _selectedPaymentDate
                //               .millisecondsSinceEpoch,
                //           'customerId': customer.id,
                //           'bankName': _selectedBankName,
                //           'createdAt':
                //           _selectedPaymentDate.toIso8601String(),
                //         });
                //         final bankBalanceRef = _db.child(
                //             'banks/${_selectedBankId}/balance');
                //         final currentBalance =
                //             (await bankBalanceRef.get()).value
                //             as num? ??
                //                 0.0;
                //         await bankBalanceRef
                //             .set(currentBalance + amount);
                //       }
                //       setState(() {
                //         _customerBalances[customer.id] =
                //             (_customerBalances[customer.id] ?? 0.0) -
                //                 amount;
                //       });
                //       Navigator.pop(context);
                //       ScaffoldMessenger.of(context)
                //           .showSnackBar(SnackBar(
                //         content: Text(languageProvider.isEnglish
                //             ? 'Payment of Rs. $amount recorded successfully'
                //             : 'ادائیگی کی رقم $amount کامیابی سے ریکارڈ ہو گئی'),
                //       ));
                //     } catch (e) {
                //
                //       ScaffoldMessenger.of(context).showSnackBar(
                //           SnackBar(
                //               content:
                //               Text('Error: ${e.toString()}')));
                //     } finally {
                //       if (mounted)
                //         setState(() => _isRecordingPayment = false);
                //     }
                //   },
                //   child: _isRecordingPayment
                //       ? SizedBox(
                //       height: 20,
                //       width: 20,
                //       child: CircularProgressIndicator(
                //           strokeWidth: 2,
                //           valueColor: AlwaysStoppedAnimation<Color>(
                //               Colors.white)))
                //       : Text(_receiveMode == 'ItemReturn'
                //       ? (languageProvider.isEnglish
                //       ? 'Record Return'
                //       : 'واپسی ریکارڈ کریں')
                //       : (languageProvider.isEnglish
                //       ? 'Record Payment'
                //       : 'ادائیگی ریکارڈ کریں')),
                // ),
                ElevatedButton(
                  onPressed: _isRecordingPayment
                      ? null
                      : () async {
                    print('🔵 [DEBUG] Button pressed - _isRecordingPayment set to true');
                    setState(() => _isRecordingPayment = true);

                    // ============================================
                    // BRANCH: ITEM RETURN
                    // ============================================
                    if (_receiveMode == 'ItemReturn') {
                      print('🟢 [DEBUG] Entering ITEM RETURN branch');
                      print('📦 [DEBUG] _selectedReturnItemId: $_selectedReturnItemId');

                      if (_selectedReturnItemId == null) {
                        print('❌ [DEBUG] No item selected - showing error');
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(languageProvider
                                    .isEnglish
                                    ? 'Please select an item'
                                    : 'براہ کرم آئٹم منتخب کریں')));
                        setState(() => _isRecordingPayment = false);
                        print('🔴 [DEBUG] _isRecordingPayment reset to false (no item)');
                        return;
                      }

                      final qty = double.tryParse(_returnQtyController.text);
                      final rate = double.tryParse(_returnRateController.text);
                      print('📊 [DEBUG] Qty: $qty, Rate: $rate');

                      if (qty == null || qty <= 0) {
                        print('❌ [DEBUG] Invalid quantity: $qty');
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(languageProvider
                                    .isEnglish
                                    ? 'Please enter a valid quantity'
                                    : 'براہ کرم درست مقدار درج کریں')));
                        setState(() => _isRecordingPayment = false);
                        print('🔴 [DEBUG] _isRecordingPayment reset to false (invalid qty)');
                        return;
                      }
                      if (rate == null || rate <= 0) {
                        print('❌ [DEBUG] Invalid rate: $rate');
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(languageProvider
                                    .isEnglish
                                    ? 'Please enter a valid rate'
                                    : 'براہ کرم درست ریٹ درج کریں')));
                        setState(() => _isRecordingPayment = false);
                        print('🔴 [DEBUG] _isRecordingPayment reset to false (invalid rate)');
                        return;
                      }

                      final creditValue = qty * rate;
                      print('💰 [DEBUG] Credit value calculated: $creditValue (qty: $qty × rate: $rate)');
                      print('👤 [DEBUG] Customer ID: ${customer.id}, Current balance: ${_customerBalances[customer.id] ?? 0.0}');

                      try {
                        print('📝 [DEBUG] STEP 1: Updating customer ledger...');
                        await filledProvider.updateCustomerLedger(
                          customer.id,
                          creditAmount: 0.0,
                          debitAmount: creditValue,
                          remainingBalance:
                          (_customerBalances[customer.id] ?? 0.0) -
                              creditValue,
                          filledNumber: DateTime.now()
                              .millisecondsSinceEpoch
                              .toString(),
                          referenceNumber: 'Item Return',
                          transactionDate: _selectedPaymentDate,
                          paymentMethod: 'Item Return',
                          description: _paymentDescription ??
                              'Item return: $_selectedReturnItemName x$qty @ $rate',
                          chequeNumber: null,
                          bankId: null,
                          bankName: null,
                        );
                        print('✅ [DEBUG] Ledger update complete');

                        // 2. Record extra return-specific details
                        print('📝 [DEBUG] STEP 2: Adding return details to ledger entry...');

// Get ALL entries for this customer (no orderBy)
                        final ledgerSnap = await _db
                            .child('filledledger')
                            .child(customer.id)
                            .get();

                        if (ledgerSnap.exists) {
                          final entries = ledgerSnap.value as Map<dynamic, dynamic>?;
                          if (entries != null && entries.isNotEmpty) {
                            // Get the last entry key (most recently added)
                            final entryKeys = entries.keys.toList();
                            final lastKey = entryKeys.last;

                            print('🔑 [DEBUG] Last entry key: $lastKey');
                            await _db
                                .child('filledledger')
                                .child(customer.id)
                                .child(lastKey)
                                .update({
                              'itemName': _selectedReturnItemName,
                              'itemQty': qty,
                              'itemRate': rate,
                            });
                            print('✅ [DEBUG] Return details added successfully');
                          } else {
                            print('⚠️ [DEBUG] No entries found in ledger');
                          }
                        } else {
                          print('⚠️ [DEBUG] No ledger data found for customer');
                        }

                        // 3. Restore stock (qtyOnHand)
                        print('📝 [DEBUG] STEP 3: Updating stock quantity...');
                        final itemRef = _db
                            .child('items')
                            .child(_selectedReturnItemId!);
                        final itemSnap = await itemRef.get();
                        print('🔍 [DEBUG] Item snapshot exists: ${itemSnap.exists}');

                        if (itemSnap.exists) {
                          final currentQty = ((itemSnap.value as Map)['qtyOnHand'] as num?)
                              ?.toDouble() ?? 0.0;
                          final newQty = currentQty + qty;
                          print('📦 [DEBUG] Stock update: $currentQty → $newQty (+$qty)');
                          await itemRef.update({
                            'qtyOnHand': newQty,
                          });
                          print('✅ [DEBUG] Stock updated successfully');
                        } else {
                          print('⚠️ [DEBUG] Item not found in database: ${_selectedReturnItemId}');
                        }

                        print('📝 [DEBUG] STEP 4: Updating local customer balance...');
                        setState(() {
                          _customerBalances[customer.id] =
                              (_customerBalances[customer.id] ?? 0.0) -
                                  creditValue;
                        });
                        print('💰 [DEBUG] New balance: ${_customerBalances[customer.id]}');

                        print('✅ [DEBUG] All steps complete - closing dialog');
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(
                          content: Text(languageProvider.isEnglish
                              ? 'Item return of Rs. ${creditValue.toStringAsFixed(2)} recorded successfully'
                              : 'آئٹم واپسی $creditValue روپے کامیابی سے ریکارڈ ہو گئی'),
                          backgroundColor: Colors.green,
                        ));
                        print('🎉 [DEBUG] Item return completed successfully!');

                      } catch (e) {
                        print('❌ [ERROR] Exception occurred: ${e.toString()}');
                        print('📋 [ERROR] Stack trace: ${StackTrace.current}');
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                Text('Error: ${e.toString()}')));
                      } finally {
                        if (mounted) {
                          setState(() => _isRecordingPayment = false);
                          print('🔴 [DEBUG] _isRecordingPayment reset to false (finally block)');
                        }
                      }
                      return;
                    }

                    // ============================================
                    // BRANCH: CASH PAYMENT (original logic, unchanged)
                    // ============================================
                    print('🟢 [DEBUG] Entering CASH PAYMENT branch');
                    print('💳 [DEBUG] Selected payment method: $_selectedPaymentMethod');

                    if (_selectedPaymentMethod == null) {
                      print('❌ [DEBUG] No payment method selected');
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(languageProvider.isEnglish
                              ? 'Please select a payment method'
                              : 'براہ کرم ادائیگی کا طریقہ منتخب کریں')));
                      setState(() => _isRecordingPayment = false);
                      print('🔴 [DEBUG] _isRecordingPayment reset to false (no payment method)');
                      return;
                    }

                    final amount = double.tryParse(
                        _paymentAmountController.text);
                    print('💵 [DEBUG] Payment amount: $amount');

                    if (amount == null || amount <= 0) {
                      print('❌ [DEBUG] Invalid amount: $amount');
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(languageProvider.isEnglish
                              ? 'Please enter a valid amount'
                              : 'براہ کرم درست رقم درج کریں')));
                      setState(() => _isRecordingPayment = false);
                      print('🔴 [DEBUG] _isRecordingPayment reset to false (invalid amount)');
                      return;
                    }

                    print('👤 [DEBUG] Customer ID: ${customer.id}, Current balance: ${_customerBalances[customer.id] ?? 0.0}');

                    try {
                      final filledNumber = DateTime.now()
                          .millisecondsSinceEpoch
                          .toString();
                      print('📝 [DEBUG] Generated filledNumber: $filledNumber');

                      print('📝 [DEBUG] STEP 1: Updating customer ledger...');
                      await filledProvider.updateCustomerLedger(
                        customer.id,
                        creditAmount: 0.0,
                        debitAmount: amount,
                        remainingBalance:
                        (_customerBalances[customer.id] ?? 0.0) -
                            amount,
                        filledNumber: filledNumber,
                        referenceNumber: 'Direct Payment',
                        transactionDate: _selectedPaymentDate,
                        paymentMethod: _selectedPaymentMethod,
                        bankId: _selectedPaymentMethod == 'Bank'
                            ? _selectedBankId
                            : (_selectedPaymentMethod == 'Cheque'
                            ? _selectedBankId
                            : null),
                        bankName: _selectedPaymentMethod == 'Bank'
                            ? _selectedBankName
                            : (_selectedPaymentMethod == 'Cheque'
                            ? _selectedBankName
                            : null),
                        chequeNumber:
                        _selectedPaymentMethod == 'Cheque'
                            ? _chequeNumberController.text
                            : null,
                        description: _paymentDescription ??
                            'Payment from ${customer.name}',
                      );
                      print('✅ [DEBUG] Ledger update complete');

                      if (_selectedPaymentMethod == 'Cash') {
                        print('💵 [DEBUG] STEP 2a: Adding cash book entry...');
                        await filledProvider.addCashBookEntry(
                          description: _paymentDescription ??
                              'Payment from ${customer.name}',
                          amount: amount,
                          dateTime: _selectedPaymentDate,
                          type: 'cash_in',
                        );
                        print('✅ [DEBUG] Cash book entry added');

                      } else if (_selectedPaymentMethod == 'Cheque') {
                        print('📝 [DEBUG] STEP 2b: Processing Cheque payment...');
                        print('🏦 [DEBUG] Bank ID: $_selectedBankId, Bank Name: $_selectedBankName');
                        print('📄 [DEBUG] Cheque Number: ${_chequeNumberController.text}');
                        print('📅 [DEBUG] Cheque Date: $_selectedChequeDate');

                        if (_selectedBankId == null ||
                            _selectedBankName == null) {
                          print('❌ [ERROR] Bank not selected for cheque payment');
                          throw Exception("Bank not selected for cheque payment");
                        }
                        if (_chequeNumberController.text.isEmpty) {
                          print('❌ [ERROR] Cheque number is required');
                          throw Exception("Cheque number is required");
                        }
                        if (_selectedChequeDate == null) {
                          print('❌ [ERROR] Cheque date is required');
                          throw Exception("Cheque date is required");
                        }

                        print('📝 [DEBUG] Saving cheque to database...');
                        await _db
                            .child('banks/${_selectedBankId}/cheques')
                            .push()
                            .set({
                          'customerId': customer.id,
                          'customerName': customer.name,
                          'amount': amount,
                          'chequeNumber':
                          _chequeNumberController.text,
                          'chequeDate':
                          _selectedChequeDate!.toIso8601String(),
                          'status': 'pending',
                          'createdAt':
                          _selectedPaymentDate.toIso8601String(),
                          'bankName': _selectedBankName,
                        });
                        print('✅ [DEBUG] Cheque saved successfully');

                      } else if (_selectedPaymentMethod == 'Bank' &&
                          _selectedBankId != null) {
                        print('🏦 [DEBUG] STEP 2c: Processing Bank payment...');
                        print('📝 [DEBUG] Saving bank transaction...');
                        await _db
                            .child('banks/${_selectedBankId}/transactions')
                            .push()
                            .set({
                          'amount': amount,
                          'description': _paymentDescription ??
                              'Payment from ${customer.name}',
                          'type': 'cash_in',
                          'timestamp': _selectedPaymentDate
                              .millisecondsSinceEpoch,
                          'customerId': customer.id,
                          'bankName': _selectedBankName,
                          'createdAt':
                          _selectedPaymentDate.toIso8601String(),
                        });
                        print('✅ [DEBUG] Bank transaction saved');

                        print('📝 [DEBUG] Updating bank balance...');
                        final bankBalanceRef = _db.child(
                            'banks/${_selectedBankId}/balance');
                        final currentBalance =
                            (await bankBalanceRef.get()).value as num? ?? 0.0;
                        final newBalance = currentBalance + amount;
                        print('🏦 [DEBUG] Bank balance: $currentBalance → $newBalance (+$amount)');
                        await bankBalanceRef.set(newBalance);
                        print('✅ [DEBUG] Bank balance updated');
                      }

                      print('📝 [DEBUG] STEP 3: Updating local customer balance...');
                      setState(() {
                        _customerBalances[customer.id] =
                            (_customerBalances[customer.id] ?? 0.0) -
                                amount;
                      });
                      print('💰 [DEBUG] New balance: ${_customerBalances[customer.id]}');

                      print('✅ [DEBUG] All steps complete - closing dialog');
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(
                        content: Text(languageProvider.isEnglish
                            ? 'Payment of Rs. $amount recorded successfully'
                            : 'ادائیگی کی رقم $amount کامیابی سے ریکارڈ ہو گئی'),
                      ));
                      print('🎉 [DEBUG] Payment completed successfully!');

                    } catch (e) {
                      print('❌ [ERROR] Exception occurred: ${e.toString()}');
                      print('📋 [ERROR] Stack trace: ${StackTrace.current}');
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                              Text('Error: ${e.toString()}')));
                    } finally {
                      if (mounted) {
                        setState(() => _isRecordingPayment = false);
                        print('🔴 [DEBUG] _isRecordingPayment reset to false (finally block)');
                      }
                    }
                  },
                  child: _isRecordingPayment
                      ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white)))
                      : Text(_receiveMode == 'ItemReturn'
                      ? (languageProvider.isEnglish
                      ? 'Record Return'
                      : 'واپسی ریکارڈ کریں')
                      : (languageProvider.isEnglish
                      ? 'Record Payment'
                      : 'ادائیگی ریکارڈ کریں')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final bool allSelected =
        _selectedCustomerIds.length == _allCustomers.length &&
            _allCustomers.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text(
          '${_selectedCustomerIds.length} selected',
          style: const TextStyle(color: Colors.white),
        )
            : Text(
          languageProvider.isEnglish
              ? 'Customer List'
              : 'کسٹمر کی فہرست',
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
        actions: _isSelectionMode
            ? [
          // Select all toggle
          IconButton(
            icon: Icon(
              allSelected
                  ? Icons.deselect
                  : Icons.select_all,
              color: Colors.white,
            ),
            tooltip: allSelected ? 'Deselect All' : 'Select All',
            onPressed: _selectAll,
          ),
          // Generate PDF for selected
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            tooltip: 'Export Selected',
            onPressed: _selectedCustomerIds.isEmpty
                ? null
                : () => _showPdfOptions(_selectedCustomers),
          ),
          // Cancel selection
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _toggleSelectionMode,
          ),
        ]
            : [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              _loadCustomerBalances();
              _fetchAllCustomers();
            },
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => AddCustomer()),
              ).then((_) => _fetchAllCustomers());
            },
          ),
          // ── NEW: enter selection mode ──
          IconButton(
            icon: const Icon(Icons.checklist, color: Colors.white),
            tooltip: languageProvider.isEnglish
                ? 'Select for PDF'
                : 'پی ڈی ایف کے لیے منتخب کریں',
            onPressed: _toggleSelectionMode,
          ),
          IconButton(
            icon: Icon(Icons.receipt_long, color: Colors.white),
            tooltip: 'Payment Collection Sheet (All)',
            onPressed: () async {
              final customerProvider = Provider.of<CustomerProvider>(
                  context,
                  listen: false);
              await _generateCustomerPaymentCollectionPdf(
                  customerProvider.customers);
            },
          ),
          IconButton(
            icon: Icon(Icons.picture_as_pdf, color: Colors.white),
            tooltip: languageProvider.isEnglish
                ? 'Export PDF (All)'
                : 'پی ڈی ایف ایکسپورٹ کریں',
            onPressed: () async {
              final customerProvider = Provider.of<CustomerProvider>(
                  context,
                  listen: false);
              await _generateAndPrintCustomerBalances(
                  customerProvider.customers);
            },
          ),
        ],
      ),

      // ── NEW: floating action button shown only in selection mode ──
      floatingActionButton: _isSelectionMode && _selectedCustomerIds.isNotEmpty
          ? FloatingActionButton.extended(
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.picture_as_pdf),
        label: Text(
            '${_selectedCustomerIds.length} → PDF'),
        onPressed: () => _showPdfOptions(_selectedCustomers),
      )
          : null,

      body: Column(
        children: [
          // ── Selection mode banner ──
          if (_isSelectionMode)
            Container(
              color: Colors.orange.shade100,
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      languageProvider.isEnglish
                          ? 'Tap customers to select them for PDF export'
                          : 'پی ڈی ایف برآمد کے لیے کسٹمرز پر ٹیپ کریں',
                      style: TextStyle(color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: languageProvider.isEnglish
                            ? 'Search Customers'
                            : 'کسٹمر تلاش کریں',
                        prefixIcon: Icon(Icons.search,
                            color: Colors.orange[300]),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(16),
                        suffixIcon: _isSearchingDatabase
                            ? Padding(
                          padding: EdgeInsets.all(8.0),
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2)),
                        )
                            : null,
                      ),
                      onChanged: (value) {
                        setState(() => _searchQuery = value.toLowerCase());
                        _applySearchFilter();
                      },
                      onSubmitted: (value) =>
                          _searchCustomersFromDatabase(),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: Icon(Icons.search),
                  label: Text(languageProvider.isEnglish
                      ? 'Database'
                      : 'ڈیٹا بیس'),
                  onPressed: _isSearchingDatabase
                      ? null
                      : _searchCustomersFromDatabase,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                  ),
                ),
              ],
            ),
          ),

          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          languageProvider.isEnglish
                              ? 'Showing ${_paginatedCustomers.length} of $_totalCustomers customers'
                              : '$_totalCustomers کسٹمرز میں سے ${_paginatedCustomers.length} دکھائے جا رہے ہیں',
                          style: TextStyle(
                              color: Colors.orange[700],
                              fontWeight: FontWeight.bold),
                        ),
                        if (_searchController.text.isNotEmpty)
                          TextButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                              _fetchAllCustomers();
                            },
                            child: Text(
                              languageProvider.isEnglish
                                  ? 'Clear Search'
                                  : 'سرچ صاف کریں',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth > 600) {
                          return _buildWebLayout();
                        } else {
                          return _buildMobileLayout();
                        }
                      },
                    ),
                  ),
                  if (_totalPages > 1)
                    _buildPaginationControls(languageProvider),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWebLayout() {
    return SingleChildScrollView(
      controller: _scrollController,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: DataTable(
          columns: [
            // ── NEW: checkbox column header ──
            DataColumn(
              label: _isSelectionMode
                  ? Checkbox(
                value: _selectedCustomerIds.length ==
                    _allCustomers.length &&
                    _allCustomers.isNotEmpty,
                onChanged: (_) => _selectAll(),
                activeColor: Colors.orange,
              )
                  : const Text('#'),
            ),
            DataColumn(label: Text('Serial')),
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Address')),
            DataColumn(label: Text('City')),
            DataColumn(label: Text('Phone')),
            DataColumn(label: Text('Balance')),
            DataColumn(label: Text('Receive')),
            DataColumn(label: Text('Actions')),
            DataColumn(label: Text('Prices')),
            DataColumn(label: Text('Payments')),
          ],
          rows: _paginatedCustomers.asMap().entries.map((entry) {
            final index =
                entry.key + 1 + ((_currentPage - 1) * _itemsPerPage);
            final customer = entry.value;
            final isSelected =
            _selectedCustomerIds.contains(customer.id);
            return DataRow(
              key: ValueKey(customer.id),
              selected: isSelected,
              color: _isSelectionMode && isSelected
                  ? MaterialStateProperty.all(Colors.orange.shade50)
                  : null,
              onSelectChanged: _isSelectionMode
                  ? (_) => _toggleCustomerSelection(customer.id)
                  : null,
              cells: [
                // ── NEW: checkbox cell ──
                DataCell(
                  _isSelectionMode
                      ? Checkbox(
                    value: isSelected,
                    onChanged: (_) =>
                        _toggleCustomerSelection(customer.id),
                    activeColor: Colors.orange,
                  )
                      : Text('$index'),
                ),
                DataCell(Text(customer.customerSerial.isNotEmpty
                    ? customer.customerSerial
                    : '-')),
                DataCell(Text(customer.name)),
                DataCell(Text(customer.address)),
                DataCell(Text(customer.city)),
                DataCell(Text(customer.phone)),
                DataCell(
                  Text(
                    '${_customerBalances[customer.id]?.toStringAsFixed(2) ?? "0.00"}',
                    style: TextStyle(
                      color: (_customerBalances[customer.id] ?? 0.0) >= 0
                          ? Colors.green
                          : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                DataCell(IconButton(
                  icon: Icon(Icons.payment, color: Colors.green),
                  onPressed: () =>
                      _showPaymentDialog(context, customer),
                )),
                DataCell(Row(children: [
                  IconButton(
                    icon: Icon(Icons.edit, color: Colors.orange),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              AddCustomer(customer: customer),
                        ),
                      ).then((_) => _fetchAllCustomers());
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _showDeleteConfirmationDialog(
                        context, customer),
                  ),
                ])),
                DataCell(ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                  ),
                  icon: Icon(Icons.price_check),
                  label: Text('Rates'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CustomerItemPricesPage(
                          customerId: customer.id,
                          customerName: customer.name,
                        ),
                      ),
                    );
                  },
                )),
                DataCell(IconButton(
                  icon: Icon(Icons.history, color: Colors.blue),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            CustomerPaymentHistoryPage(customer: customer),
                      ),
                    );
                  },
                )),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return ListView.builder(
      controller: _scrollController,
      itemCount: _paginatedCustomers.length,
      itemBuilder: (context, index) {
        final customer = _paginatedCustomers[index];
        final displayIndex =
            index + 1 + ((_currentPage - 1) * _itemsPerPage);
        final isSelected = _selectedCustomerIds.contains(customer.id);

        return Card(
          key: ValueKey(customer.id),
          elevation: 4,
          margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          // ── highlight selected cards ──
          color: _isSelectionMode && isSelected
              ? Colors.orange.shade100
              : Colors.orange.shade50,
          shape: _isSelectionMode && isSelected
              ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Colors.orange, width: 2))
              : null,
          child: InkWell(
            // tap entire card to toggle when in selection mode
            onTap: _isSelectionMode
                ? () => _toggleCustomerSelection(customer.id)
                : null,
            borderRadius: BorderRadius.circular(8),
            child: ListTile(
              // ── NEW: leading checkbox in selection mode ──
              leading: _isSelectionMode
                  ? Checkbox(
                value: isSelected,
                onChanged: (_) =>
                    _toggleCustomerSelection(customer.id),
                activeColor: Colors.orange,
              )
                  : CircleAvatar(
                backgroundColor: Colors.orange,
                child: Text('$displayIndex',
                    style: TextStyle(color: Colors.white)),
              ),
              title: Text(customer.name,
                  style: TextStyle(color: Colors.orange[300])),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Serial: ${customer.customerSerial.isNotEmpty ? customer.customerSerial : 'N/A'}',
                    style: TextStyle(color: Colors.orange[300]),
                  ),
                  Text(customer.address,
                      style: TextStyle(color: Colors.orange[300])),
                  Text(customer.city,
                      style: TextStyle(color: Colors.orange[300])),
                  SizedBox(height: 4),
                  Text(customer.phone,
                      style: TextStyle(color: Colors.orange[300])),
                  Text(
                    'Balance: ${_customerBalances[customer.id]?.toStringAsFixed(2) ?? "0.00"}',
                    style: TextStyle(
                      color: (_customerBalances[customer.id] ?? 0.0) >= 0
                          ? Colors.green
                          : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (!_isSelectionMode)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CustomerItemPricesPage(
                              customerId: customer.id,
                              customerName: customer.name,
                            ),
                          ),
                        );
                      },
                      icon: Icon(Icons.list_alt,
                          size: 18, color: Colors.teal),
                      label: Text('View Item Rates',
                          style: TextStyle(color: Colors.teal)),
                    ),
                ],
              ),
              trailing: _isSelectionMode
                  ? null // hide action buttons in selection mode
                  : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.payment, color: Colors.green),
                    onPressed: () =>
                        _showPaymentDialog(context, customer),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, color: Colors.teal),
                    onPressed: () =>
                        _showEditDialog(context, customer),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete, color: Colors.red),
                    onPressed: () =>
                        _showDeleteConfirmationDialog(
                            context, customer),
                  ),
                  IconButton(
                    icon: Icon(Icons.history, color: Colors.blue),
                    onPressed: () =>
                        _showPaymentHistory(context, customer),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaginationControls(LanguageProvider languageProvider) {
    return Container(
      padding: EdgeInsets.all(8.0),
      color: Colors.grey[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(Icons.first_page),
            onPressed:
            _currentPage > 1 ? () => _goToPage(1) : null,
            color: _currentPage > 1 ? Colors.orange : Colors.grey,
          ),
          IconButton(
            icon: Icon(Icons.navigate_before),
            onPressed: _currentPage > 1
                ? () => _goToPage(_currentPage - 1)
                : null,
            color: _currentPage > 1 ? Colors.orange : Colors.grey,
          ),
          for (int i = 1; i <= _totalPages; i++)
            if (i == 1 ||
                i == _totalPages ||
                (i >= _currentPage - 2 && i <= _currentPage + 2))
              Container(
                margin: EdgeInsets.symmetric(horizontal: 2),
                child: TextButton(
                  onPressed: () => _goToPage(i),
                  style: TextButton.styleFrom(
                    backgroundColor: _currentPage == i
                        ? Colors.orange
                        : Colors.transparent,
                    shape: CircleBorder(),
                  ),
                  child: Text(
                    '$i',
                    style: TextStyle(
                      color: _currentPage == i
                          ? Colors.white
                          : Colors.orange,
                      fontWeight: _currentPage == i
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              )
            else if (i == _currentPage - 3 || i == _currentPage + 3)
              Container(
                margin: EdgeInsets.symmetric(horizontal: 2),
                child: Text('...',
                    style: TextStyle(color: Colors.grey)),
              ),
          IconButton(
            icon: Icon(Icons.navigate_next),
            onPressed: _currentPage < _totalPages
                ? () => _goToPage(_currentPage + 1)
                : null,
            color:
            _currentPage < _totalPages ? Colors.orange : Colors.grey,
          ),
          IconButton(
            icon: Icon(Icons.last_page),
            onPressed: _currentPage < _totalPages
                ? () => _goToPage(_totalPages)
                : null,
            color:
            _currentPage < _totalPages ? Colors.orange : Colors.grey,
          ),
          PopupMenuButton<int>(
            icon: Icon(Icons.settings, color: Colors.orange),
            itemBuilder: (context) => [
              PopupMenuItem(
                  value: 10,
                  child: Text(
                      '10 ${languageProvider.isEnglish ? 'items' : 'آئٹمز'}')),
              PopupMenuItem(
                  value: 20,
                  child: Text(
                      '20 ${languageProvider.isEnglish ? 'items' : 'آئٹمز'}')),
              PopupMenuItem(
                  value: 50,
                  child: Text(
                      '50 ${languageProvider.isEnglish ? 'items' : 'آئٹمز'}')),
              PopupMenuItem(
                  value: 100,
                  child: Text(
                      '100 ${languageProvider.isEnglish ? 'items' : 'آئٹمز'}')),
            ],
            onSelected: (value) {
              setState(() {
                _itemsPerPage = value;
                _currentPage = 1;
                _updatePaginatedCustomers();
              });
            },
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmationDialog(
      BuildContext context, Customer customer) {
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    final customerProvider =
    Provider.of<CustomerProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(languageProvider.isEnglish
            ? 'Delete Customer?'
            : 'کسٹمر حذف کریں؟'),
        content: Text(languageProvider.isEnglish
            ? 'Are you sure you want to delete ${customer.name}?'
            : 'کیا آپ واقعی ${customer.name} کو حذف کرنا چاہتے ہیں؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(languageProvider.isEnglish
                ? 'Cancel'
                : 'منسوخ کریں'),
          ),
          ElevatedButton(
            style:
            ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await customerProvider.deleteCustomer(customer.id);
                Navigator.pop(context);
                await _fetchAllCustomers();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(languageProvider.isEnglish
                      ? 'Customer deleted successfully'
                      : 'کسٹمر کامیابی سے حذف ہو گیا'),
                  backgroundColor: Colors.green,
                ));
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(languageProvider.isEnglish
                      ? 'Error deleting customer: $e'
                      : 'کسٹمر کو حذف کرنے میں خرابی: $e'),
                  backgroundColor: Colors.red,
                ));
              }
            },
            child: Text(
                languageProvider.isEnglish ? 'Delete' : 'حذف کریں'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, Customer customer) {
    final customerProvider =
    Provider.of<CustomerProvider>(context, listen: false);
    final nameController =
    TextEditingController(text: customer.name);
    final addressController =
    TextEditingController(text: customer.address);
    final phoneController =
    TextEditingController(text: customer.phone);
    final cityController =
    TextEditingController(text: customer.city);
    final balanceController = TextEditingController(
        text: customer.openingBalance!.toStringAsFixed(2));
    DateTime editOpeningBalanceDate =
        customer.openingBalanceDate ?? DateTime.now();
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                languageProvider.isEnglish
                    ? 'Edit Customer'
                    : 'کسٹمر میں ترمیم کریں',
                style: TextStyle(color: Colors.orange.shade800),
              ),
              backgroundColor: Colors.orange.shade50,
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                          labelText: languageProvider.isEnglish
                              ? 'Name'
                              : 'نام',
                          labelStyle:
                          TextStyle(color: Colors.orange.shade600)),
                    ),
                    TextField(
                      controller: addressController,
                      decoration: InputDecoration(
                          labelText: languageProvider.isEnglish
                              ? 'Address'
                              : 'پتہ',
                          labelStyle:
                          TextStyle(color: Colors.orange.shade600)),
                    ),
                    TextField(
                      controller: cityController,
                      decoration: InputDecoration(
                          labelText: languageProvider.isEnglish
                              ? 'City'
                              : 'شہر',
                          labelStyle:
                          TextStyle(color: Colors.orange.shade600)),
                    ),
                    TextField(
                      controller: phoneController,
                      decoration: InputDecoration(
                          labelText: languageProvider.isEnglish
                              ? 'Phone'
                              : 'فون',
                          labelStyle:
                          TextStyle(color: Colors.orange.shade600)),
                      keyboardType: TextInputType.phone,
                    ),
                    TextField(
                      controller: balanceController,
                      decoration: InputDecoration(
                          labelText: languageProvider.isEnglish
                              ? 'Opening Balance'
                              : 'ابتدائی بیلنس',
                          labelStyle:
                          TextStyle(color: Colors.orange.shade600)),
                      keyboardType: TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                    SizedBox(height: 16),
                    Card(
                      elevation: 2,
                      child: ListTile(
                        leading: Icon(Icons.calendar_today,
                            color: Colors.orange.shade600),
                        title: Text(
                          languageProvider.isEnglish
                              ? 'Opening Balance Date & Time'
                              : 'ابتدائی بیلنس کی تاریخ اور وقت',
                          style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Colors.orange.shade600),
                        ),
                        subtitle: Text(
                          DateFormat('dd/MM/yyyy - HH:mm')
                              .format(editOpeningBalanceDate),
                          style: TextStyle(
                              fontSize: 16,
                              color: Colors.orange.shade800),
                        ),
                        trailing: Icon(Icons.edit,
                            color: Colors.orange.shade600),
                        onTap: () async {
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: editOpeningBalanceDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now()
                                .add(const Duration(days: 365)),
                          );
                          if (pickedDate != null) {
                            final pickedTime = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(
                                  editOpeningBalanceDate),
                            );
                            if (pickedTime != null) {
                              setState(() {
                                editOpeningBalanceDate = DateTime(
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
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                      languageProvider.isEnglish
                          ? 'Cancel'
                          : 'منسوخ کریں',
                      style: TextStyle(color: Colors.orange.shade800)),
                ),
                ElevatedButton(
                  onPressed: () {
                    final openingBalance =
                        double.tryParse(balanceController.text) ?? 0.0;
                    customerProvider.updateCustomer(
                        customer.id,
                        nameController.text,
                        addressController.text,
                        phoneController.text,
                        cityController.text,
                        openingBalance,
                        editOpeningBalanceDate);
                    Navigator.pop(context);
                  },
                  child: Text(
                    languageProvider.isEnglish ? 'Save' : 'محفوظ کریں',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade300),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showPaymentHistory(
      BuildContext context, Customer customer) async {
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    try {
      final customerLedgerRef =
      _db.child('filledledger').child(customer.id);
      final DatabaseEvent snapshot = await customerLedgerRef
          .orderByChild('createdAt')
          .once();
      if (!snapshot.snapshot.exists) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(languageProvider.isEnglish
              ? 'No payment history found'
              : 'کوئی ادائیگی کی تاریخ نہیں ملی'),
        ));
        return;
      }
      final Map<dynamic, dynamic> ledgerEntries =
      snapshot.snapshot.value as Map<dynamic, dynamic>;
      final List<Map<String, dynamic>> payments = [];
      ledgerEntries.forEach((key, value) {
        if (value != null && value is Map) {
          final debitAmount = (value['debitAmount'] ?? 0.0).toDouble();
          if (debitAmount > 0) {
            payments.add({
              'key': key,
              'amount': debitAmount,
              'date': value['createdAt'] ?? '',
              'method': value['paymentMethod'] ?? '',
              'description': value['description'] ?? '',
              'bankName': value['bankName'] ?? '',
              'chequeNumber': value['chequeNumber'] ?? '',
            });
          }
        }
      });
      payments.sort((a, b) => b['date'].compareTo(a['date']));
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(languageProvider.isEnglish
              ? 'Payment History - ${customer.name}'
              : 'ادائیگی کی تاریخ - ${customer.name}'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: payments.isEmpty
                ? Center(
                child: Text(languageProvider.isEnglish
                    ? 'No payments found'
                    : 'کوئی ادائیگی نہیں ملی'))
                : ListView.builder(
              itemCount: payments.length,
              itemBuilder: (context, index) {
                final payment = payments[index];
                return Card(
                  margin: EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text('${payment['amount']} Rs',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${payment['method']}'),
                        if (payment['bankName'] != null &&
                            payment['bankName'].isNotEmpty)
                          Text('Bank: ${payment['bankName']}'),
                        if (payment['chequeNumber'] != null &&
                            payment['chequeNumber'].isNotEmpty)
                          Text(
                              'Cheque: ${payment['chequeNumber']}'),
                        Text(DateFormat('yyyy-MM-dd HH:mm').format(
                            DateTime.parse(payment['date']))),
                        if (payment['description'] != null &&
                            payment['description'].isNotEmpty)
                          Text('Desc: ${payment['description']}'),
                      ],
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deletePayment(
                          context,
                          customer,
                          payment['key'],
                          payment['amount'],
                          payment['method'],
                          payment['bankName'],
                          payment['chequeNumber']),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(languageProvider.isEnglish
                  ? 'Close'
                  : 'بند کریں'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')));
    }
  }

  Future<void> _deletePayment(
      BuildContext context,
      Customer customer,
      String paymentKey,
      double amount,
      String paymentMethod,
      String? bankName,
      String? chequeNumber) async {
    final languageProvider =
    Provider.of<LanguageProvider>(context, listen: false);
    final filledProvider =
    Provider.of<FilledProvider>(context, listen: false);
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(languageProvider.isEnglish
            ? 'Delete Payment?'
            : 'ادائیگی حذف کریں؟'),
        content: Text(languageProvider.isEnglish
            ? 'Are you sure you want to delete this payment of Rs. $amount?'
            : 'کیا آپ واقعی اس $amount روپے کی ادائیگی کو حذف کرنا چاہتے ہیں؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(languageProvider.isEnglish
                ? 'Cancel'
                : 'منسوخ کریں'),
          ),
          ElevatedButton(
            style:
            ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
                languageProvider.isEnglish ? 'Delete' : 'حذف کریں'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _db
            .child('filledledger')
            .child(customer.id)
            .child(paymentKey)
            .remove();
        if (paymentMethod == 'Cash') {
          await filledProvider.addCashBookEntry(
            description: 'Payment deletion - ${customer.name}',
            amount: amount,
            dateTime: DateTime.now(),
            type: 'cash_out',
          );
        } else if (paymentMethod == 'Cheque' && chequeNumber != null) {
          final chequesRef = _db.child('banks');
          final chequesSnapshot = await chequesRef
              .orderByChild('chequeNumber')
              .equalTo(chequeNumber)
              .once();
          if (chequesSnapshot.snapshot.exists) {
            final cheques = chequesSnapshot.snapshot.value
            as Map<dynamic, dynamic>;
            final chequeKey = cheques.keys.first;
            await chequesRef.child(chequeKey).remove();
          }
        } else if (paymentMethod == 'Bank' && bankName != null) {
          final banksRef = _db.child('banks');
          final banksSnapshot = await banksRef.once();
          if (banksSnapshot.snapshot.exists) {
            final banks = banksSnapshot.snapshot.value
            as Map<dynamic, dynamic>;
            for (var bankEntry in banks.entries) {
              final bankId = bankEntry.key;
              final bankData =
              bankEntry.value as Map<dynamic, dynamic>;
              if (bankData['name'] == bankName) {
                final transactionsRef =
                _db.child('banks/$bankId/transactions');
                final transactionsSnapshot = await transactionsRef
                    .orderByChild('amount')
                    .equalTo(amount)
                    .once();
                if (transactionsSnapshot.snapshot.exists) {
                  final transactions = transactionsSnapshot
                      .snapshot.value as Map<dynamic, dynamic>;
                  final transactionKey = transactions.keys.first;
                  await transactionsRef
                      .child(transactionKey)
                      .remove();
                  final currentBalance =
                  (bankData['balance'] ?? 0.0).toDouble();
                  await _db
                      .child('banks/$bankId/balance')
                      .set(currentBalance - amount);
                }
                break;
              }
            }
          }
        }
        setState(() {
          _customerBalances[customer.id] =
              (_customerBalances[customer.id] ?? 0.0) + amount;
        });
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(languageProvider.isEnglish
              ? 'Payment deleted successfully'
              : 'ادائیگی کامیابی سے حذف ہو گئی'),
          backgroundColor: Colors.green,
        ));
        _showPaymentHistory(context, customer);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error deleting payment: ${e.toString()}'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }
}