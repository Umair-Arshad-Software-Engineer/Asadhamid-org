import 'dart:convert';
import 'dart:io';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mughal_group_branch_two/Filled/quotepage.dart';
import 'package:provider/provider.dart';
import '../Provider/quotationPageprovider.dart';
import '../Provider/lanprovider.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';


class QuoteListPageOrg extends StatefulWidget {
  @override
  _QuoteListPageOrgState createState() => _QuoteListPageOrgState();
}

class _QuoteListPageOrgState extends State<QuoteListPageOrg> {
  TextEditingController _searchController = TextEditingController();
  final TextEditingController _paymentController = TextEditingController();
  DateTimeRange? _selectedDateRange;
  List<Map<String, dynamic>> _filteredFilled = [];
  String? _selectedBankId;
  String? _selectedBankName;

  // Scroll controller for ListView
  final ScrollController _scrollController = ScrollController();

  // Flag to prevent multiple requests
  bool _isLoadingMore = false;
  bool _isGeneratingReport = false;


  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {}); // Trigger rebuild on text change
    });
    // Add scroll listener for pagination
    _scrollController.addListener(_scrollListener);

    // Initial data load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final filledProvider = Provider.of<QuoteProvider>(context, listen: false);
      filledProvider.resetPagination(); // Clear any previous data
      filledProvider.fetchQuote(); // Fetch first page
    });
  }

  // Scroll listener to detect when user reaches bottom
  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200 && !_isLoadingMore) {
      _loadMoreData();
    }
  }

  // Load more data when user scrolls to bottom
  Future<void> _loadMoreData() async {
    final filledProvider = Provider.of<QuoteProvider>(context, listen: false);

    if (!filledProvider.isLoading && filledProvider.hasMoreData) {
      setState(() {
        _isLoadingMore = true;
      });

      await filledProvider.loadMoreQuote();

      setState(() {
        _isLoadingMore = false;
        _filteredFilled = _filterFilled(filledProvider.quote);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _searchController.dispose();
    _paymentController.dispose();
    super.dispose();
  }

  Future<void> _fetchFilteredDataFromDatabase() async {
    setState(() {
      _isGeneratingReport = true;
    });

    final filledProvider = Provider.of<QuoteProvider>(context, listen: false);

    try {
      filledProvider.resetPagination();

      final searchQuery = _searchController.text.toLowerCase();

      DateTime? startDate;
      DateTime? endDate;
      if (_selectedDateRange != null) {
        startDate = _selectedDateRange!.start;
        endDate = _selectedDateRange!.end;
      }

      await filledProvider.fetchQuoteWithFilters(
        searchQuery: searchQuery,
        startDate: startDate,
        endDate: endDate,
      );

      setState(() {
        _filteredFilled = filledProvider.quote;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating report: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isGeneratingReport = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final filledProvider = Provider.of<QuoteProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: _buildAppBar(context, languageProvider, filledProvider),
      body: Column(
        children: [
          SearchAndFilterSection(
            searchController: _searchController,
            selectedDateRange: _selectedDateRange,
            onDateRangeSelected: (range) {
              setState(() {
                _selectedDateRange = range;
              });
              final filledProvider = Provider.of<QuoteProvider>(
                  context, listen: false);
              filledProvider.resetPagination();
              filledProvider.fetchQuote();
            },
            onClearDateFilter: () {
              setState(() {
                _selectedDateRange = null;
              });
              final filledProvider = Provider.of<QuoteProvider>(
                  context, listen: false);
              filledProvider.resetPagination();
              filledProvider.fetchQuote();
            },
            onGenerateReport: _fetchFilteredDataFromDatabase,
            languageProvider: languageProvider,
          ),
          // Filled List
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                // Refresh data by resetting pagination and fetching first page
                final filledProvider = Provider.of<QuoteProvider>(
                    context, listen: false);
                filledProvider.resetPagination();
                await filledProvider.fetchQuote();
                setState(() {
                  _filteredFilled = _filterFilled(filledProvider.quote);
                });
              },
              child: Builder(
                builder: (context) {
                  _filteredFilled = _filterFilled(filledProvider.quote);

                  if (filledProvider.isLoading && _filteredFilled.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (_filteredFilled.isEmpty) {
                    return Center(
                      child: Text(
                        languageProvider.isEnglish
                            ? 'No Filled Found'
                            : 'کوئی انوائس موجود نہیں',
                      ),
                    );
                  }

                  return Column(
                    children: [
                      Expanded(
                        child: FilledList(
                          scrollController: _scrollController,
                          filteredFilled: _filteredFilled,
                          languageProvider: languageProvider,
                          filledProvider: filledProvider,

                          onFilledTap: (filled) {
                            // Create a new map with all filled data and explicitly set isFromQuotation to false
                            final filledToEdit = Map<String, dynamic>.from(
                                filled);
                            filledToEdit['isFromQuotation'] = false;

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    QuotepageOrg(filled: filledToEdit),
                              ),
                            );
                          },
                          onFilledLongPress: (quote) async {
                            print('Button pressed');
                            await _showDeleteConfirmationDialog(
                              context,
                              quote,
                              filledProvider,
                              languageProvider,
                            );
                          },
                          onPaymentPressed: (filled) {
                            // _showFilledPaymentDialog(
                            //     filled, filledProvider, languageProvider);
                          },
                          onViewPayments: (filled) {

                          }
                        ),
                      ),

                      // Loading indicator at the bottom
                      if (filledProvider.isLoading &&
                          _filteredFilled.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Center(
                            child: SizedBox(
                              height: 30,
                              width: 30,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        ),

                      // No more data indicator
                      if (!filledProvider.hasMoreData &&
                          _filteredFilled.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            languageProvider.isEnglish
                                ? 'No more records'
                                : 'مزید ریکارڈز نہیں ہیں',
                            style: TextStyle(fontStyle: FontStyle.italic,
                                color: Colors.grey),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }


  // Build AppBar
  AppBar _buildAppBar(BuildContext context, LanguageProvider languageProvider,
      QuoteProvider filledProvider) {
    return AppBar(
      title: Text(
        languageProvider.isEnglish ? 'Quotation List' : 'کوٹیشن لسٹ',
        style: const TextStyle(color: Colors.white),
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
      ), actions: [
      IconButton(
        icon: const Icon(Icons.add, color: Colors.white),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => QuotepageOrg()),
          );
        },
      ),
      IconButton(
        icon: const Icon(Icons.print, color: Colors.white),
        onPressed: _printFilled,
      ),
    ],
    );
  }

  // Filter filled based on search and date range
  List<Map<String, dynamic>> _filterFilled(List<Map<String, dynamic>> filled) {
    return filled.where((filled) {
      final searchQuery = _searchController.text.toLowerCase();
      final filledNumber = (filled['filledNumber'] ?? '')
          .toString()
          .toLowerCase();
      final customerName = (filled['customerName'] ?? '')
          .toString()
          .toLowerCase();
      final matchesSearch = filledNumber.contains(searchQuery) ||
          customerName.contains(searchQuery);

      if (_selectedDateRange != null) {
        final filledDateStr = filled['createdAt'];
        DateTime? filledDate;
        try {
          filledDate = DateTime.tryParse(filledDateStr) ??
              DateTime.fromMillisecondsSinceEpoch(int.parse(filledDateStr));
        } catch (e) {
          print('Error parsing date: $e');
          return false;
        }
        final isInDateRange = (filledDate.isAfter(_selectedDateRange!.start) ||
            filledDate.isAtSameMomentAs(_selectedDateRange!.start)) &&
            (filledDate.isBefore(_selectedDateRange!.end) ||
                filledDate.isAtSameMomentAs(_selectedDateRange!.end));
        return matchesSearch && isInDateRange;
      }
      return matchesSearch;
    }).toList();
    // ..sort((a, b) {
    //   final dateA = DateTime.tryParse(a['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(int.parse(a['createdAt']));
    //   final dateB = DateTime.tryParse(b['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(int.parse(b['createdAt']));
    //   return dateB.compareTo(dateA); // Newest first
    // });
  }

  // Show delete confirmation dialog
  Future<void> _showDeleteConfirmationDialog(BuildContext context,
      Map<String, dynamic> filled,
      QuoteProvider filledProvider,
      LanguageProvider languageProvider,) async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(languageProvider.isEnglish
              ? 'Delete Filled'
              : 'انوائس ڈلیٹ کریں'),
          content: Text(languageProvider.isEnglish
              ? 'Are you sure you want to delete this filled?'
              : 'کیاآپ واقعی اس انوائس کو ڈیلیٹ کرنا چاہتے ہیں'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(languageProvider.isEnglish ? 'Cancel' : 'ردکریں'),
            ),
            TextButton(
              onPressed: () async {
                await filledProvider.deleteQuote(filled['id']);
                Navigator.of(context).pop();
              },
              child: Text(languageProvider.isEnglish ? 'Delete' : 'ڈیلیٹ کریں'),
            ),
          ],
        );
      },
    );
  }


  Future<void> _printFilled() async {
    final pdf = pw.Document();
    final headers = [
      'Filled Number',
      'Customer Name',
      'Date',
      'Grand Total',
      'Remaining Amount'
    ];
    final List<List<dynamic>> tableData = [];

    for (var filled in _filteredFilled) {
      final customerName = filled['customerName'] ?? 'N/A';
      final customerNameImage = await _createTextImage(customerName);
      tableData.add([
        filled['filledNumber'] ?? 'N/A',
        pw.Image(customerNameImage),
        filled['createdAt'] ?? 'N/A',
        'Rs ${filled['grandTotal']}',
        'Rs ${(filled['grandTotal'] - filled['debitAmount']).toStringAsFixed(
            2)}',
      ]);
    }

    // Load the image asset for the logo
    final ByteData bytes = await rootBundle.load('assets/images/logo.png');
    final buffer = bytes.buffer.asUint8List();
    final image = pw.MemoryImage(buffer);

    final ByteData footerBytes = await rootBundle.load(
        'assets/images/devlogo.png');
    final footerBuffer = footerBytes.buffer.asUint8List();
    final footerLogo = pw.MemoryImage(footerBuffer);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(15),
        // Reduced margins for more content space
        header: (pw.Context context) =>
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Invoice List',
                  style: pw.TextStyle(
                      fontSize: 26, fontWeight: pw.FontWeight.bold),
                ),
                pw.Column(
                  children: [
                    pw.Image(image, width: 70, height: 70, dpi: 1000),
                    // Display the logo at the top
                    pw.SizedBox(height: 10)
                  ],
                )
              ],
            ),
        footer: (pw.Context context) =>
            pw.Column(
              children: [
                pw.Divider(),
                // Adds a horizontal line above the footer content
                pw.SizedBox(height: 5),
                // Adds spacing between divider and footer content
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Image(footerLogo, width: 50, height: 50),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          'Developed By: Umair Arshad',
                          style: pw.TextStyle(
                              fontSize: 10, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          'Contact: 0307-6455926',
                          style: pw.TextStyle(
                              fontSize: 10, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
        build: (pw.Context context) =>
        [
          pw.Table.fromTextArray(
            headers: headers,
            data: tableData,
            border: pw.TableBorder.all(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(5), // Reduced cell padding
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  // Create text image for PDF
  Future<pw.MemoryImage> _createTextImage(String text) async {
    const double scaleFactor = 1.5;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromPoints(
        const Offset(0, 0),
        const Offset(500 * scaleFactor, 50 * scaleFactor),
      ),
    );

    final paint = Paint()
      ..color = Colors.black;
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



}
class FilledList extends StatelessWidget {
  final ScrollController scrollController;
  final List<Map<String, dynamic>> filteredFilled;
  final LanguageProvider languageProvider;
  final QuoteProvider filledProvider;
  final Function(Map<String, dynamic>) onFilledTap;
  final Function(Map<String, dynamic>) onFilledLongPress;
  final Function(Map<String, dynamic>) onPaymentPressed;
  final Function(Map<String, dynamic>) onViewPayments;

  const FilledList({
    required this.scrollController,
    required this.filteredFilled,
    required this.languageProvider,
    required this.filledProvider,
    required this.onFilledTap,
    required this.onFilledLongPress,
    required this.onPaymentPressed,
    required this.onViewPayments,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWideScreen = constraints.maxWidth > 600;

        return ListView.builder(
          controller: scrollController,
          itemCount: filteredFilled.length,
          itemBuilder: (context, index) {
            final filled = Map<String, dynamic>.from(filteredFilled[index]);
            final grandTotal = (filled['grandTotal'] ?? 0.0).toDouble();
            final debitAmount = (filled['debitAmount'] ?? 0.0).toDouble();
            final remainingAmount = (grandTotal - debitAmount).toDouble();

            // Extract additional fields
            final referenceNumber = filled['referenceNumber'] ?? 'N/A';
            final biltiNumber = filled['biltiNumber'] ?? '';
            final transportCompany = filled['transportCompany'] ?? '';
            final discount = (filled['discount'] ?? 0.0).toDouble();
            final mazdoori = (filled['mazdoori'] ?? 0.0).toDouble();
            final items = filled['items'] ?? [];
            final subtotal = (filled['subtotal'] ?? 0.0).toDouble();
            final paymentType = filled['paymentType'] ?? '';
            final paymentMethod = filled['paymentMethod'] ?? '';
            final customerId = filled['customerId'] ?? '';
            final customerName = filled['customerName'] ?? 'N/A';
            final customerSerial = filled['customerSerial'] ?? '';

            return Card(
              margin: EdgeInsets.symmetric(
                horizontal: isWideScreen ? 16.0 : 8.0,
                vertical: 4.0,
              ),
              elevation: 2,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                contentPadding: const EdgeInsets.all(8),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${languageProvider.isEnglish ? 'Reference #' : 'ریفیرنس نمبر'} $referenceNumber',
                      style: TextStyle(
                        fontSize: isWideScreen ? 18 : 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (biltiNumber.isNotEmpty)
                      Text(
                        '${languageProvider.isEnglish ? 'Bilti #' : 'بلٹی نمبر'} $biltiNumber',
                        style: TextStyle(
                          fontSize: isWideScreen ? 14 : 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    if (transportCompany.isNotEmpty)
                      Text(
                        '${languageProvider.isEnglish ? 'Transport' : 'ٹرانسپورٹ'} $transportCompany',
                        style: TextStyle(
                          fontSize: isWideScreen ? 14 : 12,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      '${languageProvider.isEnglish ? 'Customer' : 'کسٹمر'} $customerName',
                      style: TextStyle(
                        fontSize: isWideScreen ? 16 : 14,
                      ),
                    ),
                    Text(
                      '${languageProvider.isEnglish ? 'Date' : 'تاریخ'}: ${filled['createdAt']}',
                      style: TextStyle(
                        fontSize: isWideScreen ? 14 : 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      '${languageProvider.isEnglish ? 'Invoice #' : 'انوائس نمبر'} ${filled['quoteNumber']}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (items.isNotEmpty)
                      Text(
                        '${languageProvider.isEnglish ? 'Items' : 'آئٹمز'}: ${items.length}',
                        style: TextStyle(
                          fontSize: isWideScreen ? 12 : 10,
                          color: Colors.blue[600],
                        ),
                      ),
                  ],
                ),
                trailing: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${languageProvider.isEnglish ? 'Rs ' : ''}${grandTotal.toStringAsFixed(2)}${languageProvider.isEnglish ? '' : ' روپے'}',
                      style: TextStyle(
                        fontSize: isWideScreen ? 16 : 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (discount > 0)
                      Text(
                        '${languageProvider.isEnglish ? 'Discount' : 'رعایت'}: ${discount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: isWideScreen ? 12 : 10,
                          color: Colors.green,
                        ),
                      ),
                    if (mazdoori > 0)
                      Text(
                        '${languageProvider.isEnglish ? 'Labor' : 'مزدوری'}: ${mazdoori.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: isWideScreen ? 12 : 10,
                          color: Colors.orange,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '${languageProvider.isEnglish ? 'Remaining: ' : 'بقیہ: '}${remainingAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: isWideScreen ? 14 : 12,
                        color: remainingAmount > 0 ? Colors.red : Colors.green,
                      ),
                    ),
                  ],
                ),
                onTap: () => onFilledTap(filled),
                // onLongPress: () => onFilledLongPress(filled),
                // Add action buttons
                isThreeLine: true,
              ),
            );
          },
        );
      },
    );
  }
}


class SearchAndFilterSection extends StatelessWidget {
  final TextEditingController searchController;
  final DateTimeRange? selectedDateRange;
  final Function(DateTimeRange?) onDateRangeSelected;
  final VoidCallback onClearDateFilter;
  final LanguageProvider languageProvider;
  final VoidCallback onGenerateReport;

  const SearchAndFilterSection({
    required this.searchController,
    required this.selectedDateRange,
    required this.onDateRangeSelected,
    required this.onClearDateFilter,
    required this.languageProvider,
    required this.onGenerateReport,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              labelText: languageProvider.isEnglish
                  ? 'Search by Filled ID or Customer Name'
                  : 'فلڈ آئی ڈی یا کسٹمر کے نام سے تلاش کریں',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchController.text.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => searchController.clear(),
              )
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onClearDateFilter,
                  child: Text(languageProvider.isEnglish
                      ? 'Clear Filters'
                      : 'فلٹرز صاف کریں'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.teal.shade400,
                  ),
                ),
              ),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    DateTimeRange? pickedDateRange = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2101),
                      initialDateRange: selectedDateRange,
                    );
                    if (pickedDateRange != null) {
                      onDateRangeSelected(pickedDateRange);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.teal.shade400,
                  ),
                  icon: const Icon(Icons.date_range, color: Colors.white),
                  label: Text(
                    selectedDateRange == null
                        ? languageProvider.isEnglish
                        ? 'Select Date Range'
                        : 'تاریخ کی حد منتخب کریں'
                        : 'From: ${DateFormat('yyyy-MM-dd').format(selectedDateRange!.start)} - To: ${DateFormat('yyyy-MM-dd').format(selectedDateRange!.end)}',
                  ),
                ),
              ),
              Expanded(
                child: ElevatedButton(
                  onPressed: onGenerateReport,
                  child: Text(languageProvider.isEnglish
                      ? 'Generate Report'
                      : 'رپورٹ بنائیں'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.teal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}