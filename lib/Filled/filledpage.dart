import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:url_launcher/url_launcher.dart';
import '../Models/itemModel.dart';
import '../Provider/customerprovider.dart';
import '../Provider/filled provider.dart';
import '../Provider/lanprovider.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:share_plus/share_plus.dart';
import 'dart:html' as html;
import '../bankmanagement/banknames.dart';
import 'gatepasspage.dart';
import 'dart:js_interop';

@JS('copyPngToClipboard')
external JSPromise<JSBoolean> _copyPngToClipboardJs(JSString base64Png);

@JS('sharePngWithText')
external JSPromise<JSBoolean> _sharePngWithTextJs(
    JSString base64Png, JSString text, JSString fileName);

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
  static String? _lastPngSignature;
  static Uint8List? _lastPngBytes;

  static pw.MemoryImage? _pdfLogoImage;
  static pw.Font? _pdfItalicFont;
  static bool _pdfAssetsReady = false;
  static final Map<String, Future<pw.MemoryImage>> _textImageCache = {};
  static String? _lastPdfSignature;
  static Uint8List? _lastPdfBytes;
  static final RegExp _nonLatin = RegExp(r'[^\x00-\xFF]');
  bool _needsImage(String t) => t.isNotEmpty && _nonLatin.hasMatch(t);

  /// 0300-1234567 / +92 300 1234567 -> 923001234567
  String? _normalizePkNumber(String raw) {
    var n = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (n.startsWith('+')) n = n.substring(1);
    if (n.startsWith('00')) n = n.substring(2);
    if (n.startsWith('0')) n = '92${n.substring(1)}';
    if (n.startsWith('92') && n.length == 12) return n;
    return null; // not a valid mobile number
  }

  /// Browsers can't probe for installed apps; mobile/desktop can.
  Future<bool> _isWhatsAppAvailable(String number) async {
    if (kIsWeb) return true;
    try {
      return await canLaunchUrl(Uri.parse('whatsapp://send?phone=$number'));
    } catch (_) {
      return false;
    }
  }

  Future<void> _offerWhatsAppMessage(String invoiceNumber, double grandTotal) async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);

    final customer = customerProvider.customers.firstWhere(
          (c) => c.id == _selectedCustomerId,
      orElse: () => Customer(id: '', name: '', phone: '', address: '', city: '', customerSerial: ''),
    );

    final number = _normalizePkNumber(customer.phone);
    if (number == null) return;
    if (!await _isWhatsAppAvailable(number)) return;
    if (!mounted) return;

    // Spinner right away so the user sees feedback immediately.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // Build PDF + first-page image BEFORE the dialog so the clipboard/share
    // call can run directly inside the button tap (browser needs a user gesture).
    Uint8List? pdfBytes;
    Uint8List? pngBytes;
    try {
      // Also sets _remainingBalance, so no second ledger download is needed.
      pdfBytes = await _generatePDFBytes(invoiceNumber);

      final sig = _lastPdfSignature;
      if (sig != null && _lastPngSignature == sig && _lastPngBytes != null) {
        // Same invoice as last time -> reuse the rendered image instantly.
        pngBytes = _lastPngBytes;
      } else {
        await for (final page in Printing.raster(pdfBytes, pages: [0], dpi: 110)) {
          pngBytes = await page.toPng();
          break;
        }
        if (pngBytes != null) {
          _lastPngSignature = sig;
          _lastPngBytes = pngBytes;
        }
      }
    } catch (e) {
      print('Invoice build failed: $e');
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close spinner

    final message = 'Assalam o Alaikum ${customer.name},\n'
        'Your invoice #$invoiceNumber has been ${widget.filled == null ? 'created' : 'updated'}.\n'
        'Reference: ${_referenceController.text}\n'
        'Total: Rs ${grandTotal.toStringAsFixed(2)}\n'
        'Remaining balance: Rs ${_remainingBalance.toStringAsFixed(2)}\n'
        'Thank you!';

    final isEn = languageProvider.isEnglish;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEn ? 'Send on WhatsApp' : 'واٹس ایپ پر بھیجیں'),
        content: Text(
          isEn
              ? 'Send invoice to ${customer.name} (${customer.phone})?\n\n'
              'Image + Message: the invoice image is copied and WhatsApp opens '
              'this customer\'s chat. Press Ctrl+V to attach the image.\n\n'
              'Share Image: pick WhatsApp from the share sheet, image and text '
              'go together.'
              : '${customer.name} (${customer.phone}) کو انوائس بھیجیں؟\n\n'
              'تصویر + پیغام: تصویر کاپی ہوگی اور واٹس ایپ چیٹ کھلے گی، پھر Ctrl+V دبائیں۔\n\n'
              'شیئر: شیئر مینو سے واٹس ایپ منتخب کریں، تصویر اور پیغام اکٹھے جائیں گے۔',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isEn ? 'Not now' : 'ابھی نہیں'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.message, size: 18),
            label: Text(isEn ? 'Text Only' : 'صرف پیغام'),
            onPressed: () async {
              Navigator.pop(ctx);
              await _sendWhatsAppTextOnly(number, message);
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: Text(isEn ? 'Download PDF' : 'پی ڈی ایف ڈاؤن لوڈ'),
            onPressed: pdfBytes == null
                ? null
                : () => _downloadPDFWeb(pdfBytes!, 'Invoice_$invoiceNumber.pdf'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.share, size: 18),
            label: Text(isEn ? 'Share Image' : 'تصویر شیئر کریں'),
            onPressed: pngBytes == null
                ? null
                : () async {
              Navigator.pop(ctx);
              final shared = await _shareImageWithText(
                  pngBytes!, message, 'Invoice_$invoiceNumber.png');
              if (!shared && mounted) {
                _showSnackBar(
                  context,
                  isEn
                      ? 'Sharing not supported here. Use Image + Message.'
                      : 'یہاں شیئرنگ دستیاب نہیں۔ تصویر + پیغام استعمال کریں۔',
                );
              }
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.image, size: 18),
            label: Text(isEn ? 'Image + Message' : 'تصویر + پیغام'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: pngBytes == null
                ? null
                : () async {
              Navigator.pop(ctx);
              // 1) copy image first (still inside the tap gesture)
              final copied = await _copyImageToClipboard(pngBytes!);
              // 2) open the installed WhatsApp app directly with text pre-filled
              await _sendWhatsAppTextOnly(number, message);
              if (mounted) {
                _showSnackBar(
                  context,
                  copied
                      ? (isEn
                      ? 'Invoice image copied. Press Ctrl+V in the chat.'
                      : 'انوائس کی تصویر کاپی ہو گئی۔ چیٹ میں Ctrl+V دبائیں۔')
                      : (isEn
                      ? 'Could not copy the image. Use Share Image or Download PDF.'
                      : 'تصویر کاپی نہیں ہو سکی۔ شیئر یا پی ڈی ایف استعمال کریں۔'),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  /// Copies a PNG to the system clipboard (web only, needs a user tap + https/localhost)
  Future<bool> _copyImageToClipboard(Uint8List png) async {
    if (!kIsWeb) return false;
    try {
      final result = await _copyPngToClipboardJs(base64Encode(png).toJS).toDart;
      return result.toDart;
    } catch (e) {
      print('Clipboard copy failed: $e');
      return false;
    }
  }

  /// Native share sheet: image + text together (web)
  Future<bool> _shareImageWithText(Uint8List png, String text, String fileName) async {
    if (kIsWeb) {
      try {
        final result = await _sharePngWithTextJs(
          base64Encode(png).toJS,
          text.toJS,
          fileName.toJS,
        ).toDart;
        return result.toDart;
      } catch (e) {
        print('Web share failed: $e');
        return false;
      }
    }
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(png);
      await Share.shareXFiles([XFile(file.path)], text: text);
      return true;
    } catch (e) {
      print('Share failed: $e');
      return false;
    }
  }

  /// Download PDF on web platform
  Future<void> _downloadPDFWeb(Uint8List pdfBytes, String fileName) async {
    try {
      final blob = html.Blob([pdfBytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      print('Error downloading PDF on web: $e');
    }
  }

  /// Opens the INSTALLED WhatsApp app directly (no api.whatsapp.com / wa.me).
  /// Name kept so existing callers don't change.
  Future<void> _sendWhatsAppTextOnly(String number, String message) async {
    final link = 'whatsapp://send?phone=$number&text=${Uri.encodeComponent(message)}';

    if (kIsWeb) {
      // Anchor click triggers the OS protocol handler without leaving the page
      final a = html.AnchorElement(href: link)
        ..target = '_self'
        ..style.display = 'none';
      html.document.body?.append(a);
      a.click();
      a.remove();
    } else {
      await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    }
  }




  Future<void> _cleanupTempPDFs() async {
    if (kIsWeb) return; // no temp directory on web
    try {
      final tempDir = await getTemporaryDirectory();
      final files = tempDir.listSync();
      final now = DateTime.now();

      for (var file in files) {
        if (file is File && file.path.contains('Invoice_') && file.path.endsWith('.pdf')) {
          final stat = file.statSync();
          if (now.difference(stat.modified).inHours > 1) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      print('Error cleaning temp PDFs: $e');
    }
  }



  /// Loads and decodes logos once, then reuses them for every PDF.
  Future<void> _ensurePdfAssets() async {
    if (_pdfAssetsReady) return;

    Future<pw.MemoryImage?> load(String path) async {
      try {
        final data = await rootBundle.load(path);
        return pw.MemoryImage(data.buffer.asUint8List());
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait([
      load('assets/images/logo.png'),
    ]);
    _pdfLogoImage = results[0];
    _pdfItalicFont = pw.Font.timesItalic();
    _pdfAssetsReady = true;
  }

  Future<pw.MemoryImage> _getTextImage(
      String text, {
        required double fontSize,
        required double width,
        required double height,
      }) {
    if (_textImageCache.length > 500) _textImageCache.clear();
    final key = '$fontSize|$width|$height|$text';
    return _textImageCache.putIfAbsent(
      key,
          () async => pw.MemoryImage(await _renderTextAsImage(text,
          fontSize: fontSize, width: width, height: height)),
    );
  }


  void _showLengthCombinationDialog(Item item, int rowIndex) async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    if (item.lengthBodyCombinations == null || item.lengthBodyCombinations!.isEmpty) {
      return;
    }

    LengthBodyCombination? selectedCombination;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                languageProvider.isEnglish
                    ? 'Select Length-Body Combination'
                    : 'لمبائی-جسم کا مجموعہ منتخب کریں',
              ),
              content: Container(
                width: double.maxFinite,
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: item.lengthBodyCombinations!.length,
                  itemBuilder: (context, index) {
                    final combination = item.lengthBodyCombinations![index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text('${item.itemName} (${combination.length} - ${combination.bodyType})'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (combination.lengthDecimal.isNotEmpty)
                              Text(
                                'Decimal: ${combination.lengthDecimal}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            if (combination.weightPerUnit != null)
                              Text(
                                'Weight/Unit: ${combination.weightPerUnit} ${combination.weightUnit}',
                                style: const TextStyle(fontSize: 12, color: Colors.blue),
                              ),
                            if (combination.costPricePerKg != null && combination.salePricePerKg != null)
                              Text(
                                'Price/Kg: ${combination.salePricePerKg!.toStringAsFixed(2)} PKR',
                                style: const TextStyle(fontSize: 12, color: Colors.green),
                              ),
                          ],
                        ),
                        trailing: const Icon(Icons.arrow_forward),
                        onTap: () {
                          setState(() {
                            selectedCombination = combination;
                          });
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
                  child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text(languageProvider.isEnglish ? 'Skip' : 'چھوڑ دیں'),
                ),
              ],
            );
          },
        );
      },
    );

    // After dialog closes, add the item with the selected combination
    if (selectedCombination != null) {
      _addItemToRow(item, rowIndex, selectedCombination);
    } else {
      // If no combination selected, add item without combination
      _addItemToRow(item, rowIndex, null);
    }
  }

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
                    // In the header Container, add after Size:
                    Expanded(
                      child: Text(
                        'Batch',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800]),
                        textAlign: TextAlign.center,
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
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: InkWell(
                            onTap: () {
                              final itemName = _filledRows[index]['itemName'] ?? '';
                              if (itemName.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please select an item first')),
                                );
                                return;
                              }
                              _showBatchSelectionDialog(index, itemName);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _filledRows[index]['batchId'] != null
                                      ? Colors.green
                                      : Colors.grey[300]!,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                color: _filledRows[index]['batchId'] != null
                                    ? Colors.green[50]
                                    : Colors.grey[50],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _filledRows[index]['batchNumber'] ?? 'Select Batch',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _filledRows[index]['batchId'] != null
                                          ? Colors.green[800]
                                          : Colors.grey[600],
                                      fontWeight: _filledRows[index]['batchId'] != null
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  if (_filledRows[index]['availableBatchQty'] != null)
                                    Text(
                                      'Avail: ${(_filledRows[index]['availableBatchQty'] as double).toStringAsFixed(2)} kg',
                                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                    ),
                                ],
                              ),
                            ),
                          ),
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

  // Add to _filledRows map structure
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
        'batchId': null,        // NEW
        'batchNumber': null,    // NEW
        'availableBatches': [], // NEW
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

  Future<List<Map<String, dynamic>>> _fetchBatchesForItem(String itemName) async {
    final database = FirebaseDatabase.instance.ref();
    List<Map<String, dynamic>> batches = [];

    try {
      final snapshot = await database.child('batches').get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          final batch = Map<String, dynamic>.from(value);

          // SAFE numeric parsing - handle nulls properly
          double quantity = 0.0;
          if (batch['quantity'] != null) {
            quantity = (batch['quantity'] as num).toDouble();
          }

          bool isActive = batch['isActive'] == true;

          if (batch['itemName'] == itemName &&
              quantity > 0 &&
              isActive) {
            // SAFE parsing for other numeric fields
            double purchasePrice = 0.0;
            if (batch['purchasePrice'] != null) {
              purchasePrice = (batch['purchasePrice'] as num).toDouble();
            } else if (batch['costPrice'] != null) {
              purchasePrice = (batch['costPrice'] as num).toDouble();
            }

            batches.add({
              'id': key,
              'itemName': batch['itemName'] ?? '',
              'itemKey': batch['itemKey'] ?? '',
              'batchNumber': batch['batchNumber'] ?? 'N/A',
              'quantity': quantity,
              'remainingQty': quantity, // Use quantity as remaining
              'purchasePrice': purchasePrice,
              'costPrice': purchasePrice,
              'purchaseDate': batch['timestamp']?.toString() ?? DateTime.now().toIso8601String(),
              'isActive': isActive,
              'vendorName': batch['vendorName'] ?? 'N/A',
              'length': batch['length']?.toString() ?? '',
              'bodyType': batch['bodyType']?.toString() ?? '',
            });
          }
        });
        // Sort by date (FIFO - oldest first)
        batches.sort((a, b) {
          try {
            return DateTime.parse(a['purchaseDate'])
                .compareTo(DateTime.parse(b['purchaseDate']));
          } catch (e) {
            return 0;
          }
        });
      }
    } catch (e) {
      print('Error fetching batches: $e');
    }
    return batches;
  }

  Future<void> _showBatchSelectionDialog(int index, String itemName) async {
    final batches = await _fetchBatchesForItem(itemName);
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    if (batches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            languageProvider.isEnglish
                ? 'No batches available for $itemName'
                : '$itemName کے لیے کوئی بیچ دستیاب نہیں'
        )),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(languageProvider.isEnglish
            ? 'Select Batch for $itemName'
            : '$itemName کے لیے بیچ منتخب کریں'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: batches.length,
            itemBuilder: (context, i) {
              final batch = batches[i];

              // SAFE numeric extraction - handle nulls with fallbacks
              final qty = (batch['quantity'] as num?)?.toDouble() ?? 0.0;
              final purchasePrice = (batch['purchasePrice'] as num?)?.toDouble() ?? 0.0;

              String purchaseDateStr = batch['purchaseDate']?.toString() ??
                  batch['timestamp']?.toString() ??
                  DateTime.now().toIso8601String();

              DateTime purchaseDate;
              try {
                purchaseDate = DateTime.parse(purchaseDateStr);
              } catch (e) {
                purchaseDate = DateTime.now();
              }

              final batchNumber = batch['batchNumber']?.toString() ?? 'Batch ${i + 1}';
              final vendorName = batch['vendorName']?.toString() ?? 'N/A';
              final length = batch['length']?.toString() ?? '';
              final bodyType = batch['bodyType']?.toString() ?? '';

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(
                    batchNumber,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Available: ${qty.toStringAsFixed(2)} kg',
                        style: TextStyle(
                          color: qty < 100 ? Colors.orange : Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text('Purchase Price: ${purchasePrice.toStringAsFixed(2)} PKR/kg'),
                      Text('Vendor: $vendorName'),
                      if (length.isNotEmpty || bodyType.isNotEmpty)
                        Text('Size: $length - $bodyType'),
                      Text(
                        'Date: ${DateFormat('dd MMM yyyy').format(purchaseDate)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () {
                      setState(() {
                        _filledRows[index]['batchId'] = batch['id'];
                        _filledRows[index]['batchNumber'] = batchNumber;
                        _filledRows[index]['availableBatchQty'] = qty;
                        _filledRows[index]['batchPurchasePrice'] = purchasePrice;
                        // Optionally auto-fill rate with purchase price
                        // _filledRows[index]['rate'] = purchasePrice;
                        // _filledRows[index]['rateController'].text = purchasePrice.toStringAsFixed(2);
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Batch $batchNumber selected'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    child: const Text(
                      'Select',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
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
        ],
      ),
    );
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

  Future<Uint8List> _renderTextAsImage(
      String text, {
        double fontSize = 10,
        double width = 100,
        double height = 20,
      })
  async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bgPaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: const Color(0xFF000000), fontSize: fontSize),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    );
    textPainter.layout(maxWidth: width - 4);
    textPainter.paint(canvas, Offset(2, (height - textPainter.height) / 2));
    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  double _calculateGrandTotal() {
    double subtotal = _calculateSubtotal();
    // Apply discount (subtract from subtotal)
    double afterDiscount = subtotal - _discount;
    // Add labor charges
    return afterDiscount + _mazdoori;
  }


  Future<Uint8List> _generatePDFBytes(String filledNumber) async {
    // ───────────── Providers & data ─────────────
    final customerProvider =
    Provider.of<CustomerProvider>(context, listen: false);
    final filledProvider = Provider.of<FilledProvider>(context, listen: false);

    final filled = widget.filled ?? _currentFilled;
    if (filled == null) throw Exception("No invoice data available");
    if (_selectedCustomerId == null) throw Exception("No customer selected");

    final nonEmptyRows = _filledRows
        .where((row) => (row['itemName'] as String).isNotEmpty)
        .toList();

    // Run Firebase reads + asset loading in parallel
    final balanceFuture = _getRemainingBalance(_selectedCustomerId!);
    final assetsFuture = _ensurePdfAssets();
    final paymentsFuture = () async {
      try {
        final payments =
        await filledProvider.getFilledPayments(filled['filledNumber']);
        return payments.fold<double>(
            0.0, (sum, p) => sum + _parseToDouble(p['amount']));
      } catch (e) {
        print("Payment fetch error: $e");
        return 0.0;
      }
    }();

    final double paidAmount = await paymentsFuture;
    final double totalRemainingBalance = await balanceFuture;
    _remainingBalance = totalRemainingBalance; // reused by the WhatsApp message
    await assetsFuture;

    final double grandTotal = _calculateGrandTotal();
    final double remainingAmount = grandTotal - paidAmount;
    final double previousBalance = totalRemainingBalance - remainingAmount;

    final selectedCustomer = customerProvider.customers.firstWhere(
          (c) => c.id == _selectedCustomerId,
      orElse: () => Customer(
          id: 'unknown', name: 'Unknown', phone: '', address: '', city: ''),
    );

    // ───────────── Date ─────────────
    DateTime filledDate;
    if (widget.filled != null) {
      filledDate = DateTime.parse(widget.filled!['createdAt']);
    } else if (_dateController.text.isNotEmpty) {
      final d = DateTime.parse(_dateController.text);
      final now = DateTime.now();
      filledDate =
          DateTime(d.year, d.month, d.day, now.hour, now.minute, now.second);
    } else {
      filledDate = DateTime.now();
    }
    String two(int n) => n.toString().padLeft(2, '0');
    final dateText =
        '${filledDate.year}-${two(filledDate.month)}-${two(filledDate.day)} '
        '${two(filledDate.hour)}:${two(filledDate.minute)}';

    // ───────────── Whole-PDF cache ─────────────
    // Same content + same payments + same balance => reuse the last PDF.
    final signature = [
      filledNumber,
      _selectedCustomerId,
      selectedCustomer.name,
      selectedCustomer.phone,
      selectedCustomer.address,
      paidAmount,
      totalRemainingBalance,
      _discount,
      _mazdoori,
      dateText,
      _biltiNumberController.text.trim(),
      _transportCompanyController.text.trim(),
      jsonEncode(nonEmptyRows
          .map((r) => [
        r['itemName'],
        r['size'],
        r['length'],
        r['bodyType'],
        r['description'],
        r['qty'],
        r['rate'],
        r['total'],
        r['weightPerUnit'],
        r['totalWeight'],
        r['calculationType'],
      ])
          .toList()),
    ].join('|');

    if (_lastPdfSignature == signature && _lastPdfBytes != null) {
      return _lastPdfBytes!;
    }

    final pdf = pw.Document();

    // ───────────── Cached assets ─────────────
    final logoImage = _pdfLogoImage;
    final italicFont = _pdfItalicFont ?? pw.Font.timesItalic();

    // ───────────── Row calculations ─────────────
    double rowWeight(Map<String, dynamic> r) {
      final qty = _parseToDouble(r['qty']);
      final tw = _parseToDouble(r['totalWeight']);
      final wpu = _parseToDouble(r['weightPerUnit']);
      if (r['calculationType'] == 'weight' && tw > 0) return tw;
      if (wpu > 0) return wpu * qty;
      return 0.0;
    }

    final totalQty = nonEmptyRows.fold<double>(
        0.0, (s, r) => s + _parseToDouble(r['qty']));
    final totalWeight =
    nonEmptyRows.fold<double>(0.0, (s, r) => s + rowWeight(r));

    String fmtQty(double q) =>
        q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);

    // ───────────── Urdu-safe text images (only when needed, cached, parallel) ─────────────
    final Map<String, pw.MemoryImage> sizeImages = {};
    final Map<String, pw.MemoryImage> lengthImages = {};
    final Map<String, pw.MemoryImage> bodyImages = {};
    final Map<String, pw.MemoryImage> descImages = {};

    String sizeOf(Map<String, dynamic> r) {
      final s = (r['size']?.toString() ?? '').trim();
      return s.isNotEmpty ? s : (r['itemName']?.toString() ?? '');
    }

    final jobs = <Future<void>>[];
    void queue(Map<String, pw.MemoryImage> target, String text,
        double fontSize, double w, double h) {
      if (!_needsImage(text) || target.containsKey(text)) return;
      target[text] = _placeholderImage; // reserve key, replaced below
      jobs.add(_getTextImage(text, fontSize: fontSize, width: w, height: h)
          .then((img) => target[text] = img));
    }

    for (final r in nonEmptyRows) {
      queue(sizeImages, sizeOf(r), 42, 228, 66);
      queue(lengthImages, r['length']?.toString() ?? '', 42, 201, 66);
      queue(bodyImages, r['bodyType']?.toString() ?? '', 42, 144, 66);
      queue(descImages, (r['description']?.toString() ?? '').trim(), 11, 110, 20);
    }

    // Customer fields (may contain Urdu)
    pw.MemoryImage? custNameImg;
    pw.MemoryImage? custAddrImg;
    if (_needsImage(selectedCustomer.name)) {
      jobs.add(_getTextImage(selectedCustomer.name,
          fontSize: 42, width: 165 * 3, height: 66)
          .then((img) => custNameImg = img));
    }
    if (_needsImage(selectedCustomer.address)) {
      jobs.add(_getTextImage(selectedCustomer.address,
          fontSize: 42, width: 165 * 3, height: 66)
          .then((img) => custAddrImg = img));
    }

    await Future.wait(jobs);

    // ───────────── Theme ─────────────
    final navy = PdfColor.fromInt(0xFF0B2A5B);
    final navyDark = PdfColor.fromInt(0xFF082247);
    final orange = PdfColor.fromInt(0xFFF26B1D);
    final softBg = PdfColor.fromInt(0xFFEEF3FA);
    final softLine = PdfColor.fromInt(0xFFC9D4E5);
    final grey = PdfColor.fromInt(0xFF5B6678);
    const double pageW = 595.28;
    const double headerH = 138;
    const double footerH = 54;

    // ───────────── Small helpers ─────────────
    pw.Widget pad(pw.Widget w, {double v = 0}) => pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: 22, vertical: v),
        child: w);

    pw.Widget dot() => pw.Container(
      width: 4,
      height: 4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 5),
      decoration:
      pw.BoxDecoration(color: orange, shape: pw.BoxShape.circle),
    );

    pw.Widget txt(String t,
        {double size = 10,
          bool bold = false,
          PdfColor? color,
          pw.TextAlign? align}) =>
        pw.Text(t,
            textAlign: align,
            style: pw.TextStyle(
                fontSize: size,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: color ?? PdfColors.black));

    pw.Widget slant(PdfColor c,
        {double w = 14, double h = 30, bool lean = true}) =>
        pw.CustomPaint(
          size: PdfPoint(w, h),
          painter: (PdfGraphics canvas, PdfPoint size) {
            canvas.setFillColor(c);
            if (lean) {
              canvas.moveTo(0, 0);
              canvas.lineTo(w * 0.55, 0);
              canvas.lineTo(w, h);
              canvas.lineTo(w * 0.45, h);
            } else {
              canvas.moveTo(w * 0.45, 0);
              canvas.lineTo(w, 0);
              canvas.lineTo(w * 0.55, h);
              canvas.lineTo(0, h);
            }
            canvas.closePath();
            canvas.fillPath();
          },
        );

    // ───────────── HEADER ─────────────
    pw.Widget buildHeader() {
      return pw.SizedBox(
        width: pageW,
        height: headerH,
        child: pw.Stack(children: [
          pw.Positioned(
            left: 0,
            top: 0,
            child: pw.CustomPaint(
              size: const PdfPoint(pageW, headerH),
              painter: (PdfGraphics c, PdfPoint s) {
                c.setFillColor(orange);
                c.moveTo(382, 0);
                c.lineTo(410, 0);
                c.lineTo(458, headerH);
                c.lineTo(430, headerH);
                c.closePath();
                c.fillPath();

                c.setFillColor(navy);
                c.moveTo(410, 0);
                c.lineTo(pageW, 0);
                c.lineTo(pageW, headerH);
                c.lineTo(458, headerH);
                c.closePath();
                c.fillPath();
              },
            ),
          ),
          pw.Positioned(
            left: 0,
            bottom: 0,
            child: pw.Container(width: pageW, height: 5, color: navy),
          ),
          pw.Positioned(
            right: 16,
            top: 18,
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  txt('STRENGTH', size: 13, bold: true, color: PdfColors.white),
                  txt('YOU CAN', size: 13, bold: true, color: PdfColors.white),
                  txt('TRUST', size: 13, bold: true, color: PdfColors.white),
                  pw.SizedBox(height: 3),
                  pw.Container(width: 70, height: 1.5, color: orange),
                ]),
          ),
          pw.Positioned(
            right: 14,
            bottom: 16,
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('Mughal Group of Industries',
                      style: pw.TextStyle(
                          font: italicFont,
                          fontSize: 12,
                          color: PdfColors.white)),
                  pw.SizedBox(height: 2),
                  txt('IRON WIRE  -  BOLTS', size: 6.5, color: PdfColors.white),
                ]),
          ),
          pw.Positioned(
            left: 20,
            top: 14,
            child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  logoImage != null
                      ? pw.SizedBox(
                      width: 62,
                      height: 62,
                      child: pw.Image(logoImage,
                          fit: pw.BoxFit.contain))
                      : pw.Container(
                      width: 56,
                      height: 56,
                      decoration: pw.BoxDecoration(
                          color: orange, shape: pw.BoxShape.circle),
                      child: pw.Center(
                          child: txt('MGI',
                              size: 16,
                              bold: true,
                              color: PdfColors.white))),
                  pw.SizedBox(width: 10),
                  pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        txt('MUGHAL GROUP', size: 26, bold: true, color: navy),
                        txt('OF INDUSTRIES', size: 19, bold: true, color: navy),
                        pw.SizedBox(height: 5),
                        pw.Row(children: [
                          pw.Container(width: 24, height: 1, color: orange),
                          pw.SizedBox(width: 6),
                          txt('IRON WIRE', size: 11, bold: true, color: orange),
                          dot(),
                          txt('BOLTS', size: 11, bold: true, color: orange),
                          pw.SizedBox(width: 6),
                          pw.Container(width: 24, height: 1, color: orange),
                        ]),
                        pw.SizedBox(height: 7),
                        pw.Row(children: [
                          txt('HAFIZ ASAD IDREES',
                              size: 8.5, bold: true, color: navy),
                          dot(),
                          txt('M. HAMID KHALIL',
                              size: 8.5, bold: true, color: navy),
                        ]),
                        pw.SizedBox(height: 3),
                        txt('Hafizabad Road, Gujranwala, Pakistan',
                            size: 8.5, color: navy),
                        pw.SizedBox(height: 3),
                        txt('0370-4219219  |  0371-3084600',
                            size: 9.5, bold: true, color: navy),
                      ]),
                ]),
          ),
        ]),
      );
    }

    // ───────────── FOOTER ─────────────
    pw.Widget buildFooter() {
      pw.Widget line(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(children: [
          pw.Container(
              width: 6,
              height: 6,
              decoration: pw.BoxDecoration(
                  color: PdfColors.white, shape: pw.BoxShape.circle)),
          pw.SizedBox(width: 8),
          txt(t, size: 8.5, color: PdfColors.white),
        ]),
      );

      return pw.SizedBox(
        width: pageW,
        height: footerH,
        child: pw.Stack(children: [
          pw.Positioned(
            left: 0,
            top: 0,
            child: pw.CustomPaint(
              size: const PdfPoint(pageW, footerH),
              painter: (PdfGraphics c, PdfPoint s) {
                c.setFillColor(navy);
                c.moveTo(0, 0);
                c.lineTo(pageW, 0);
                c.lineTo(pageW, footerH);
                c.lineTo(0, footerH);
                c.closePath();
                c.fillPath();

                c.setFillColor(navyDark);
                c.moveTo(372, 0);
                c.lineTo(pageW, 0);
                c.lineTo(pageW, footerH);
                c.lineTo(398, footerH);
                c.closePath();
                c.fillPath();

                c.setFillColor(orange);
                c.moveTo(360, 0);
                c.lineTo(372, 0);
                c.lineTo(398, footerH);
                c.lineTo(386, footerH);
                c.closePath();
                c.fillPath();
              },
            ),
          ),
          pw.Positioned(
            left: 22,
            top: 9,
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  line('0370-4219219 | 0371-3084600'),
                  line('mughalgroupofindustrie@gmail.com'),
                  line('Hafizabad Road, Gujranwala, Pakistan'),
                ]),
          ),
          pw.Positioned(
            right: 22,
            top: 7,
            child: pw.SizedBox(
              width: 120,
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  // swittix (SVG logo)
                  pw.SizedBox(
                    width: 120,
                    height: 23, // 120 * 450 / 2378 ≈ 22.7
                    child: pw.SvgImage(
                      svg: _swittixSvgString,
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  // ── Technologies ──
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Expanded(
                        child: pw.Container(
                            height: 1, color: PdfColor.fromInt(0xFF1565FF)),
                      ),
                      pw.SizedBox(width: 4),
                      pw.Text(
                        'TECHNOLOGIES',
                        style: pw.TextStyle(
                          fontSize: 6.5,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 1.2,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.SizedBox(width: 4),
                      pw.Expanded(
                        child: pw.Container(
                            height: 1, color: PdfColor.fromInt(0xFF1565FF)),
                      ),
                    ],
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(
                        'WWW.SWITTIX.COM',
                        style: pw.TextStyle(
                          fontSize: 6.5,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 1.2,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ]),
      );
    }

    // ───────────── Title banner ─────────────
    pw.Widget titleBanner() => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          slant(navy, w: 16),
          pw.SizedBox(width: 3),
          slant(navy, w: 10),
          pw.SizedBox(width: 4),
          pw.Container(
            width: 330,
            height: 30,
            alignment: pw.Alignment.center,
            color: orange,
            child: txt('CUSTOMER SALES INVOICE',
                size: 18, bold: true, color: PdfColors.white),
          ),
          pw.SizedBox(width: 4),
          slant(navy, w: 10, lean: false),
          pw.SizedBox(width: 3),
          slant(navy, w: 16, lean: false),
        ]);

    // ───────────── Invoice no / date boxes ─────────────
    pw.Widget infoBox(String label, String value) => pw.Container(
      width: 175,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
          color: softBg,
          border: pw.Border.all(color: softLine, width: 0.7),
          borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            txt(label, size: 9, color: grey),
            pw.SizedBox(height: 2),
            txt(value, size: 13, bold: true, color: navy),
          ]),
    );

    // ───────────── Section frame ─────────────
    pw.Widget sectionHeader(String title) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: pw.BoxDecoration(
          color: navy,
          borderRadius: const pw.BorderRadius.only(
              topLeft: pw.Radius.circular(8),
              topRight: pw.Radius.circular(8))),
      child: txt(title, size: 11, bold: true, color: PdfColors.white),
    );

    pw.Widget sectionBody(pw.Widget child) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: pw.BoxDecoration(
          border: pw.Border.all(color: navy, width: 0.8),
          borderRadius: const pw.BorderRadius.only(
              bottomLeft: pw.Radius.circular(8),
              bottomRight: pw.Radius.circular(8))),
      child: child,
    );

    // Labeled, underlined field (image only when text is Urdu)
    pw.Widget field(String label, {pw.MemoryImage? img, String text = ''}) {
      final pw.Widget value = img != null
          ? pw.SizedBox(
          height: 22,
          child: pw.Image(img,
              fit: pw.BoxFit.contain, alignment: pw.Alignment.centerLeft))
          : txt(text, size: 10);

      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.SizedBox(width: 78, child: txt(label, size: 10)),
          txt(':  ', size: 10),
          pw.Expanded(
            child: pw.Container(
              height: 24,
              alignment: pw.Alignment.bottomLeft,
              decoration: pw.BoxDecoration(
                  border: pw.Border(
                      bottom: pw.BorderSide(color: navy, width: 0.5))),
              child: value,
            ),
          ),
        ]),
      );
    }

    pw.Widget customerSection() => pw.Column(children: [
      sectionHeader('CUSTOMER DETAILS'),
      sectionBody(pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
                child: pw.Column(children: [
                  field('Customer Name',
                      img: custNameImg, text: selectedCustomer.name),
                ])),
            pw.SizedBox(width: 18),
            pw.Expanded(
                child: pw.Column(children: [
                  field('Phone Number', text: selectedCustomer.phone),
                  field('Address',
                      img: custAddrImg, text: selectedCustomer.address),
                ])),
          ])),
    ]);

    // ───────────── Product table ─────────────
    pw.Widget hc(String t) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      alignment: pw.Alignment.center,
      child: pw.Text(t,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white)),
    );

    pw.Widget cc(String t, {bool bold = false}) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      alignment: pw.Alignment.center,
      child: pw.Text(t,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
              fontSize: 9,
              fontWeight:
              bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );

    pw.Widget imgCell(pw.MemoryImage? image, String fallback,
        {double h = 18}) {
      if (image == null) return cc(fallback);
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: pw.SizedBox(
            height: h, child: pw.Image(image, fit: pw.BoxFit.contain)),
      );
    }

    const int minRows = 10;
    final int rowCount =
    nonEmptyRows.length > minRows ? nonEmptyRows.length : minRows;

    pw.TableRow dataRow(int i) {
      final r = nonEmptyRows[i];
      final qty = _parseToDouble(r['qty']);
      final rate = _parseToDouble(r['rate']);
      final total = _parseToDouble(r['total']);
      final wpu = _parseToDouble(r['weightPerUnit']);
      final tw = rowWeight(r);
      final length = r['length']?.toString() ?? '';
      final body = r['bodyType']?.toString() ?? '';
      final desc = (r['description']?.toString() ?? '').trim();

      return pw.TableRow(
        decoration:
        pw.BoxDecoration(color: i.isEven ? PdfColors.white : softBg),
        children: [
          cc('${i + 1}'),
          imgCell(sizeImages[sizeOf(r)], sizeOf(r), h: 22),
          imgCell(lengthImages[length], length, h: 22),
          imgCell(bodyImages[body], body, h: 22),
          imgCell(descImages[desc], desc),
          cc(rate.toStringAsFixed(2)),
          cc(wpu > 0 ? wpu.toStringAsFixed(2) : '-'),
          cc(fmtQty(qty)),
          cc(tw > 0 ? tw.toStringAsFixed(2) : '-'),
          cc(total.toStringAsFixed(2), bold: true),
        ],
      );
    }

    pw.TableRow emptyRow(int i) => pw.TableRow(
      decoration:
      pw.BoxDecoration(color: i.isEven ? PdfColors.white : softBg),
      children: [
        cc('${i + 1}'),
        for (int k = 0; k < 9; k++) cc(''),
      ],
    );

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: orange),
        children: [
          hc('No.'),
          hc('Size'),
          hc('Length'),
          hc('Body Type'),
          hc('Desc.'),
          hc('Rate\n(PKR)'),
          hc('Wt/Unit\n(KG)'),
          hc('Qty'),
          hc('Tot.Wt\n(KG)'),
          hc('Amount\n(PKR)'),
        ],
      ),
      for (int i = 0; i < rowCount; i++)
        i < nonEmptyRows.length ? dataRow(i) : emptyRow(i),
    ];

    pw.Widget productSection() => pw.Column(children: [
      sectionHeader('PRODUCT DETAILS'),
      pw.Table(
        border: pw.TableBorder(
          left: pw.BorderSide(color: navy, width: 0.8),
          right: pw.BorderSide(color: navy, width: 0.8),
          bottom: pw.BorderSide(color: navy, width: 0.8),
          horizontalInside: pw.BorderSide(color: softLine, width: 0.4),
          verticalInside: pw.BorderSide(color: softLine, width: 0.4),
        ),
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: pw.FlexColumnWidth(0.6),
          1: pw.FlexColumnWidth(1.8),
          2: pw.FlexColumnWidth(1.6),
          3: pw.FlexColumnWidth(1.2),
          4: pw.FlexColumnWidth(1.4),
          5: pw.FlexColumnWidth(1.1),
          6: pw.FlexColumnWidth(1.1),
          7: pw.FlexColumnWidth(0.8),
          8: pw.FlexColumnWidth(1.1),
          9: pw.FlexColumnWidth(1.4),
        },
        children: tableRows,
      ),
    ]);

    final noteText = [
      'Body Type: Full / Half',
      'Weight and Amount are calculated automatically.',
      if (_biltiNumberController.text.trim().isNotEmpty)
        'Bilti #: ${_biltiNumberController.text.trim()}',
      if (_transportCompanyController.text.trim().isNotEmpty)
        'Transport: ${_transportCompanyController.text.trim()}',
    ].join('   |   ');

    // ───────────── Summary + Account boxes ─────────────
    pw.Widget boxTitle(String t) => pw.Row(children: [
      pw.Container(
          width: 16,
          height: 16,
          decoration: pw.BoxDecoration(
              color: orange, borderRadius: pw.BorderRadius.circular(3))),
      pw.SizedBox(width: 8),
      txt(t, size: 11, bold: true, color: navy),
    ]);

    pw.Widget framed(pw.Widget child) => pw.Container(
      height: 122,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
          border: pw.Border.all(color: softLine, width: 1),
          borderRadius: pw.BorderRadius.circular(8)),
      child: child,
    );

    pw.Widget sumRow(String label, String value,
        {bool big = false, PdfColor? color, bool bold = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(children: [
            pw.SizedBox(
                width: 85, child: txt(label, size: big ? 11 : 10, bold: big)),
            txt(':   ', size: 10),
            pw.Expanded(
                child: txt(value,
                    size: big ? 15 : 10.5,
                    bold: big || bold,
                    color: color)),
          ]),
        );

    pw.Widget acctRow(String label, double v) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            txt(label, size: 9.5),
            txt('${v.toStringAsFixed(2)} PKR', size: 9.5),
          ]),
    );

    pw.Widget summaryBox() => framed(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          boxTitle('TOTAL SUMMARY'),
          pw.SizedBox(height: 6),
          pw.Expanded(
            child: pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8),
              color: softBg,
              child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    sumRow('Total Quantity', fmtQty(totalQty), bold: true),
                    sumRow('Total Weight',
                        '${totalWeight.toStringAsFixed(2)} KG',
                        bold: true),
                    if (_discount > 0)
                      sumRow('Discount', _discount.toStringAsFixed(2)),
                    if (_mazdoori > 0)
                      sumRow('Labor Charges', _mazdoori.toStringAsFixed(2)),
                    sumRow('Grand Total',
                        '${grandTotal.toStringAsFixed(2)} PKR',
                        big: true, color: orange),
                  ]),
            ),
          ),
        ]));

    pw.Widget accountBox() => framed(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          boxTitle('CUSTOMER ACCOUNT'),
          pw.SizedBox(height: 6),
          acctRow('Previous Balance', previousBalance),
          acctRow('Current Invoice', grandTotal),
          acctRow('Payment Received', paidAmount),
          pw.Spacer(),
          pw.Container(
            padding:
            const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: pw.BoxDecoration(
                color: orange, borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  txt('Remaining Balance',
                      size: 10, bold: true, color: PdfColors.white),
                  txt('${totalRemainingBalance.toStringAsFixed(2)} PKR',
                      size: 13, bold: true, color: PdfColors.white),
                ]),
          ),
        ]));

    // ───────────── PDF page ─────────────
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        header: (ctx) =>
        ctx.pageNumber == 1 ? buildHeader() : pw.SizedBox(height: 18),
        footer: (ctx) => buildFooter(),
        build: (ctx) => [
          pad(titleBanner(), v: 10),
          pad(pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                infoBox('Invoice No.', filledNumber),
                infoBox('Date & Time', dateText),
              ])),
          pw.SizedBox(height: 10),
          pad(customerSection()),
          pw.SizedBox(height: 12),
          pad(productSection()),
          pw.SizedBox(height: 4),
          pad(txt(noteText, size: 7.5, color: grey)),
          pw.SizedBox(height: 8),
          pad(pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: summaryBox()),
                pw.SizedBox(width: 12),
                pw.Expanded(child: accountBox()),
              ])),
        ],
      ),
    );

    final bytes = await pdf.save();
    _lastPdfSignature = signature;
    _lastPdfBytes = bytes;
    return bytes;
  }

  /// 1x1 transparent placeholder used only to reserve a map key while the
  /// real text image is being rendered in parallel.
  static final pw.MemoryImage _placeholderImage = pw.MemoryImage(
    base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='),
  );

  Future<void> _generateAndPrintPDF() async {
    // Spinner so the user sees immediate feedback
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    Uint8List? bytes;
    try {
      String filledNumber;
      if (widget.filled != null) {
        filledNumber = widget.filled!['filledNumber'];
      } else {
        final filledProvider =
        Provider.of<FilledProvider>(context, listen: false);
        filledNumber = (await filledProvider.getNextFilledNumber()).toString();
      }
      bytes = await _generatePDFBytes(filledNumber);
    } catch (e) {
      print("Error building PDF: $e");
      rethrow; // caller's try/catch shows the snackbar
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    await Printing.layoutPdf(onLayout: (format) async => bytes!);
  }

  /// Swittix logo as SVG for the PDF footer.
  /// letters = text color (white on the navy footer), blue = brand blue.
  static String _swittixSvg({
    String letters = '#FFFFFF',
    String blue = '#1565FF',
    String swoosh = '#5B8CFF',
  })
  {
    const tPath =
        'M1217 120 Q1217 106 1230 92 L1272 50 V170 H1397 L1355 218 H1272 L1270 330 Q1272 362 1290 377 L1360 382 V432 H1320 Q1245 432 1217 380 V218 H1127 L1170 170 H1217 Z';

    return '''
<svg viewBox="0 0 2378 450" xmlns="http://www.w3.org/2000/svg">
  <g fill="{{B}}">
    <rect x="104" y="62" width="25" height="26"/>
    <rect x="45" y="90" width="33" height="34"/>
    <rect x="148" y="91" width="30" height="30"/>
    <rect x="100" y="123" width="40" height="33"/>
    <rect x="55" y="166" width="43" height="43"/>
    <path d="M112 210 L128 214 L140 230 L116 226 Z"/>
  </g>
  <g fill="{{L}}">
    <path d="M255 72 H585 L507 153 H270 Q232 153 232 190 Q236 217 262 217 H440 Q540 222 540 300 Q536 345 520 370 Q482 430 425 432 H97 L187 345 L190 362 H412 Q446 355 445 322 Q440 297 425 297 H225 Q150 285 145 225 Q145 175 185 150 L186 105 Q205 80 255 72 Z"/>
  </g>
  <polygon points="528,152 600,72 656,72 578,152" fill="{{B}}"/>
  <path fill="{{L}}" d="M555 177 H628 L706 322 L780 208 L858 322 L935 177 H1002 L862 432 H858 L780 300 L698 432 H694 Z"/>
  <g fill="{{L}}">
    <rect x="1033" y="76" width="56" height="62"/>
    <path d="M1033 215 L1085 172 H1090 V432 H1033 Z"/>
    <path d="$tPath"/>
    <g transform="translate(265 0)"><path d="$tPath"/></g>
    <rect x="1697" y="76" width="58" height="62"/>
    <path d="M1697 215 L1750 172 H1755 V432 H1697 Z"/>
  </g>
  <path fill="{{L}}" d="M1830 197 H1932 L1996 265 L1932 313 L1882 432 H1797 L1930 315 Z"/>
  <polygon points="1978,365 2050,322 2142,432 2042,432" fill="{{B}}"/>
  <path d="M1995 265 Q2150 130 2330 78 Q2150 172 2000 272 Z" fill="{{S}}"/>
  <path d="M1978 362 Q2085 250 2212 175 Q2130 232 2052 322 Z" fill="{{B}}"/>
</svg>'''
        .replaceAll('{{L}}', letters)
        .replaceAll('{{B}}', blue)
        .replaceAll('{{S}}', swoosh);
  }

  static final String _swittixSvgString = _swittixSvg();


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

  Future<void> _updateQtyOnHand(List<Map<String, dynamic>> validItems) async {
    try {
      for (var item in validItems) {
        final itemName = item['itemName'];
        if (itemName == null || itemName.isEmpty) continue;

        final batchId = item['batchId']?.toString();

        // Calculate quantity to deduct SAFELY
        double weightToDeduct = 0.0;

        if (item['calculationType'] == 'weight') {
          final totalWeight = (item['totalWeight'] as num?)?.toDouble() ?? 0.0;
          final weightUnit = item['weightUnit']?.toString() ?? 'kg';

          if (weightUnit == 'g') {
            weightToDeduct = totalWeight / 1000;
          } else if (weightUnit == 'ton') {
            weightToDeduct = totalWeight * 1000;
          } else if (weightUnit == 'lb') {
            weightToDeduct = totalWeight * 0.453592;
          } else {
            weightToDeduct = totalWeight;
          }
        } else {
          weightToDeduct = (item['qty'] as num?)?.toDouble() ?? 0.0;
        }

        if (weightToDeduct <= 0) continue;

        if (batchId != null && batchId.isNotEmpty) {
          // ✅ BATCH-WISE deduction
          final batchRef = _db.child('batches').child(batchId);
          final batchSnapshot = await batchRef.get();

          if (batchSnapshot.exists) {
            final batchData = Map<String, dynamic>.from(batchSnapshot.value as Map);

            // SAFE numeric extraction
            final currentBatchQty = (batchData['quantity'] as num?)?.toDouble() ?? 0.0;
            final updatedBatchQty = (currentBatchQty - weightToDeduct).clamp(0.0, double.infinity);

            await batchRef.update({
              'quantity': updatedBatchQty,
              'remainingQty': updatedBatchQty,
              'isActive': updatedBatchQty > 0,
            });

            print('Batch $batchId deducted: $weightToDeduct kg, remaining: $updatedBatchQty kg');
          }
        }

        // Also update the item's total qtyOnHand
        final dbItem = _items.firstWhere(
              (i) => i.itemName == itemName,
          orElse: () => Item(
            id: '',
            itemName: '',
            qtyOnHand: 0.0,
            avgCostPricePerKg: 0.0,
            avgSalePricePerKg: 0.0,
          ),
        );

        if (dbItem.id.isNotEmpty) {
          final currentQty = (dbItem.qtyOnHand ?? 0.0).toDouble();
          await _db.child('items/${dbItem.id}').update({
            'qtyOnHand': (currentQty - weightToDeduct).clamp(0.0, double.infinity),
          });
        }
      }
    } catch (e) {
      print("Error updating qty/batch: $e");
    }
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
    _cleanupTempPDFs(); // ← Added: clean up old temp PDFs on page load
    _ensurePdfAssets();
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
    final navigator = Navigator.of(context);

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async => false,
          child: const Center(child: CircularProgressIndicator()),
        ),
      );

      final filledProvider = Provider.of<FilledProvider>(context, listen: false);

      if (widget.filled != null && widget.filled!['filledNumber'] != null) {
        final filledId = widget.filled!['filledNumber']?.toString() ?? '';

        // 1. Restore stock quantities (batch-aware)
        if (_filledRows.isNotEmpty) {
          for (var row in _filledRows) {
            final itemName = row['itemName'];
            if (itemName == null || itemName.isEmpty) continue;

            // Calculate quantity to restore based on calculation type
            double quantityToRestore = 0.0;

            if (row['calculationType'] == 'weight') {
              final totalWeight = (row['totalWeight'] ?? 0.0) as double;
              final weightUnit = row['weightUnit'] ?? 'kg';

              switch (weightUnit) {
                case 'g':
                  quantityToRestore = totalWeight / 1000;
                  break;
                case 'ton':
                  quantityToRestore = totalWeight * 1000;
                  break;
                case 'lb':
                  quantityToRestore = totalWeight * 0.453592;
                  break;
                default:
                  quantityToRestore = totalWeight;
              }
            } else {
              quantityToRestore = (row['qty'] ?? 0.0) as double;
            }

            if (quantityToRestore <= 0) continue;

            final batchId = row['batchId']?.toString();

            // ── Restore batch quantity if batch was selected ──
            if (batchId != null && batchId.isNotEmpty) {
              try {
                final batchRef = _db.child('batches').child(batchId);
                final batchSnap = await batchRef.get();

                if (batchSnap.exists) {
                  final batchData = Map<String, dynamic>.from(
                      batchSnap.value as Map);
                  final currentBatchQty =
                  (batchData['quantity'] as num).toDouble();
                  final restoredBatchQty = currentBatchQty + quantityToRestore;

                  await batchRef.update({
                    'quantity': restoredBatchQty,
                    'isActive': true, // Re-activate batch if it was emptied
                  });

                  print('Batch $batchId restored: '
                      '+$quantityToRestore kg → $restoredBatchQty kg');
                } else {
                  print('Batch $batchId not found, skipping batch restore');
                }
              } catch (e) {
                print('Error restoring batch $batchId: $e');
                // Continue restoring other items even if one batch fails
              }
            }

            // ── Always restore item-level qtyOnHand ──
            final dbItem = _items.firstWhere(
                  (i) => i.itemName == itemName,
              orElse: () => Item(
                id: '',
                itemName: '',
                qtyOnHand: 0.0,
                avgCostPricePerKg: 0.0, avgSalePricePerKg: 0.0,
              ),
            );

            if (dbItem.id.isNotEmpty) {
              final currentQty = dbItem.qtyOnHand ?? 0.0;
              final updatedQty = currentQty + quantityToRestore;

              await _db.child('items/${dbItem.id}').update({
                'qtyOnHand': updatedQty,
              });

              print('Item stock restored for "$itemName": '
                  '+$quantityToRestore → $updatedQty'
                  '${batchId != null ? " (batch: $batchId)" : " (no batch)"}');
            } else {
              print('Item "$itemName" not found in local list, skipping item restore');
            }
          }
        }

        // 2. Delete the invoice from Firebase
        await filledProvider.deleteFilled(filledId);

        // Close loading dialog
        if (navigator.canPop()) navigator.pop();

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

        await Future.delayed(const Duration(milliseconds: 500));

        if (navigator.canPop()) {
          navigator.popUntil((route) => route.isFirst);
        }
      } else {
        if (navigator.canPop()) navigator.pop();

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

      if (navigator.canPop()) navigator.pop();

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

  void _addItemToRow(Item item, int rowIndex, LengthBodyCombination? combination) {
    final customerPrice = item.getPriceForCustomer(_selectedCustomerId);
    double? salePricePerKg = combination?.salePricePerKg;

    // Check if weight was manually entered before resetting
    final wasManualWeight = _filledRows[rowIndex]['weightController']?.text.isNotEmpty == true &&
        _filledRows[rowIndex]['calculationType'] == 'weight';
    final manualWeightText = wasManualWeight
        ? _filledRows[rowIndex]['weightController'].text
        : null;

    // Parse BOM name if it's in the format "Size | Length | Body Type"
    String size = '';
    String length = '';
    String bodyType = '';

    // Improved parsing logic
    if (item.itemName.contains('|')) {
      final parts = item.itemName.split('|').map((part) => part.trim()).toList();

      if (parts.length >= 3) {
        // Assuming format is always: "Size | Length | Body Type"
        size = parts[0];
        length = parts[1];
        bodyType = parts[2];
      } else if (parts.length == 2) {
        // Handle case with only 2 parts
        size = parts[0];
        length = parts[1];
        bodyType = '';
      } else if (parts.length == 1) {
        // Handle case with only 1 part
        size = parts[0];
        length = '';
        bodyType = '';
      }
    } else {
      // If no pipe separator, treat whole name as size
      size = item.itemName;
      length = '';
      bodyType = '';
    }

    setState(() {
      // Ensure all controllers exist
      if (_filledRows[rowIndex]['sizeController'] == null) {
        _filledRows[rowIndex]['sizeController'] = TextEditingController();
      }
      if (_filledRows[rowIndex]['lengthController'] == null) {
        _filledRows[rowIndex]['lengthController'] = TextEditingController();
      }
      if (_filledRows[rowIndex]['bodyTypeController'] == null) {
        _filledRows[rowIndex]['bodyTypeController'] = TextEditingController();
      }
      if (_filledRows[rowIndex]['weightController'] == null) {
        _filledRows[rowIndex]['weightController'] = TextEditingController();
      }
      if (_filledRows[rowIndex]['totalWeightController'] == null) {
        _filledRows[rowIndex]['totalWeightController'] = TextEditingController();
      }

      _filledRows[rowIndex]['itemName'] = item.itemName;
      // IMPORTANT: Set itemNameController to only show SIZE (first part)
      _filledRows[rowIndex]['itemNameController'].text = size;  // Changed from item.itemName to size

      // Set the parsed BOM fields
      _filledRows[rowIndex]['sizeController'].text = size;
      _filledRows[rowIndex]['lengthController'].text = length;
      _filledRows[rowIndex]['bodyTypeController'].text = bodyType;
      _filledRows[rowIndex]['size'] = size;
      _filledRows[rowIndex]['length'] = length;
      _filledRows[rowIndex]['bodyType'] = bodyType;

      if (combination != null) {
        // Override with combination values if available
        _filledRows[rowIndex]['lengthController'].text = combination.length;
        _filledRows[rowIndex]['bodyTypeController'].text = combination.bodyType;
        _filledRows[rowIndex]['length'] = combination.length;
        _filledRows[rowIndex]['bodyType'] = combination.bodyType;
        _filledRows[rowIndex]['lengthBodyCombination'] = combination.toMap();

        // Set weight per unit if available
        if (combination.weightPerUnit != null) {
          final weightPerUnit = combination.weightPerUnit!;
          final weightUnit = combination.weightUnit ?? 'kg';

          _filledRows[rowIndex]['weightPerUnit'] = weightPerUnit;
          _filledRows[rowIndex]['weightUnit'] = weightUnit;

          // Set weight controller with weight per unit
          _filledRows[rowIndex]['weightController'].text = '$weightPerUnit $weightUnit';
        }
      } else {
        _filledRows[rowIndex]['lengthBodyCombination'] = null;
      }

      // Clear previous weight info except if manual entry
      if (!wasManualWeight) {
        _filledRows[rowIndex]['weightPerUnit'] = null;
        _filledRows[rowIndex]['weightUnit'] = 'kg';
      }

      if (combination != null) {
        // If item has price per kg, use that instead of base price
        if (salePricePerKg != null) {
          _filledRows[rowIndex]['rate'] = salePricePerKg;
          _filledRows[rowIndex]['rateController'].text = salePricePerKg.toStringAsFixed(2);

          // Set calculation type to weight automatically if weight per unit exists
          if (combination.weightPerUnit != null) {
            _filledRows[rowIndex]['calculationType'] = 'weight';
          }
        } else {
          _filledRows[rowIndex]['rate'] = customerPrice;
          _filledRows[rowIndex]['rateController'].text = customerPrice.toStringAsFixed(2);
        }
      } else {
        _filledRows[rowIndex]['rate'] = customerPrice;
        _filledRows[rowIndex]['rateController'].text = customerPrice.toStringAsFixed(2);
      }

      // Restore manual weight if existed
      if (wasManualWeight && manualWeightText != null) {
        _filledRows[rowIndex]['weightController'].text = manualWeightText;
        _filledRows[rowIndex]['calculationType'] = 'weight';
      }

      // Initialize quantity if not set
      if (_filledRows[rowIndex]['qty'] == null || _filledRows[rowIndex]['qty'] == 0.0) {
        _filledRows[rowIndex]['qty'] = 1.0;
        _filledRows[rowIndex]['qtyController'].text = '1';
      }

      // Calculate total for this row
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
              setState(() => _isButtonPressed = true);

              try {
                // ── 1. Reference Number ──────────────────────────────
                if (_isAutoReference &&
                    _selectedCustomerId != null &&
                    _selectedCustomerSerial != null) {
                  final autoRef = await _generateNextReferenceNumber(increment: true);
                  _referenceController.text = autoRef;
                } else if (_referenceController.text.isEmpty) {
                  _showSnackBar(
                    context,
                    languageProvider.isEnglish
                        ? 'Please enter a reference number'
                        : 'براہ کرم رفرنس نمبر درج کریں',
                  );
                  setState(() => _isButtonPressed = false);
                  return;
                }

                // ── 2. Customer ──────────────────────────────────────
                if (_selectedCustomerId == null) {
                  _showSnackBar(
                    context,
                    languageProvider.isEnglish
                        ? 'Please select a customer'
                        : 'براہ کرم کسٹمر منتخب کریں',
                  );
                  setState(() => _isButtonPressed = false);
                  return;
                }

                // ── 3. Payment type ──────────────────────────────────
                if (_paymentType.isEmpty) {
                  _showSnackBar(
                    context,
                    languageProvider.isEnglish
                        ? 'Please select a payment type'
                        : 'براہ کرم ادائیگی کی قسم منتخب کریں',
                  );
                  setState(() => _isButtonPressed = false);
                  return;
                }

                if (_paymentType == 'instant' && _instantPaymentMethod == null) {
                  _showSnackBar(
                    context,
                    languageProvider.isEnglish
                        ? 'Please select an instant payment method'
                        : 'براہ کرم فوری ادائیگی کا طریقہ منتخب کریں',
                  );
                  setState(() => _isButtonPressed = false);
                  return;
                }

                // ── 4. Item rates ────────────────────────────────────
                for (var row in _filledRows) {
                  final itemName = row['itemName'] ?? '';
                  if (itemName.isEmpty) continue;

                  final rate = (row['rate'] ?? 0.0) as double;
                  if (rate <= 0) {
                    _showSnackBar(
                      context,
                      languageProvider.isEnglish
                          ? 'Rate cannot be zero or less for "$itemName"'
                          : '"$itemName" کا ریٹ صفر یا اس سے کم نہیں ہو سکتا',
                    );
                    setState(() => _isButtonPressed = false);
                    return;
                  }
                }

                // ── 5. Discount ──────────────────────────────────────
                final subtotal = _calculateSubtotal();
                if (_discount >= subtotal && subtotal > 0) {
                  _showSnackBar(
                    context,
                    languageProvider.isEnglish
                        ? 'Discount cannot be greater than or equal to subtotal'
                        : 'ڈسکاؤنٹ سب ٹوٹل سے زیادہ یا برابر نہیں ہو سکتا',
                  );
                  setState(() => _isButtonPressed = false);
                  return;
                }

                // ── 6. Batch stock validation ────────────────────────
                List<String> batchStockWarnings = [];

                for (var row in _filledRows) {
                  final itemName = row['itemName'] ?? '';
                  if (itemName.isEmpty) continue;

                  final batchId = row['batchId']?.toString();
                  if (batchId == null || batchId.isEmpty) continue;

                  // Calculate requested quantity
                  double requested = 0.0;
                  if (row['calculationType'] == 'weight') {
                    final totalWeight = (row['totalWeight'] ?? 0.0) as double;
                    final weightUnit = row['weightUnit'] ?? 'kg';
                    switch (weightUnit) {
                      case 'g':
                        requested = totalWeight / 1000;
                        break;
                      case 'ton':
                        requested = totalWeight * 1000;
                        break;
                      case 'lb':
                        requested = totalWeight * 0.453592;
                        break;
                      default:
                        requested = totalWeight;
                    }
                  } else {
                    requested = (row['qty'] ?? 0.0) as double;
                  }

                  // Fetch fresh batch quantity from Firebase
                  try {
                    final batchSnap = await _db.child('batches').child(batchId).get();
                    if (batchSnap.exists) {
                      final batchData = Map<String, dynamic>.from(
                          batchSnap.value as Map);
                      final available =
                      (batchData['quantity'] as num).toDouble();

                      // For edit mode, add back the original quantity used
                      double effectiveAvailable = available;
                      if (widget.filled != null &&
                          widget.filled!['filledNumber'] != null) {
                        final initialWeight =
                        (row['initialWeight'] ?? 0.0) as double;
                        final initialQty =
                        (row['initialQty'] ?? 0.0) as double;
                        effectiveAvailable += row['calculationType'] == 'weight'
                            ? initialWeight
                            : initialQty;
                      }

                      if (requested > effectiveAvailable) {
                        batchStockWarnings.add(
                          '• $itemName (${row['batchNumber'] ?? batchId})\n'
                              '  Requested: ${requested.toStringAsFixed(2)} kg  '
                              '  Available: ${effectiveAvailable.toStringAsFixed(2)} kg',
                        );
                      }
                    }
                  } catch (e) {
                    print('Error checking batch $batchId: $e');
                  }
                }

                if (batchStockWarnings.isNotEmpty) {
                  final proceed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange),
                          const SizedBox(width: 8),
                          Text(
                            languageProvider.isEnglish
                                ? 'Batch Stock Warning'
                                : 'بیچ اسٹاک وارننگ',
                          ),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            languageProvider.isEnglish
                                ? 'Insufficient stock in selected batches:'
                                : 'منتخب بیچز میں اسٹاک ناکافی ہے:',
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Text(
                              batchStockWarnings.join('\n\n'),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            languageProvider.isEnglish
                                ? 'Do you want to proceed anyway?'
                                : 'کیا آپ پھر بھی آگے بڑھنا چاہتے ہیں؟',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(
                            languageProvider.isEnglish ? 'Cancel' : 'منسوخ کریں',
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                          ),
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(
                            languageProvider.isEnglish
                                ? 'Proceed Anyway'
                                : 'پھر بھی جاری رکھیں',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ) ?? false;

                  if (!proceed) {
                    setState(() => _isButtonPressed = false);
                    return;
                  }
                }

                // ── 7. Item-level stock check (existing logic) ───────
                final List<Map<String, dynamic>> insufficientItems = [];

                for (var row in _filledRows) {
                  final itemName = row['itemName'] ?? '';
                  if (itemName.isEmpty) continue;

                  final item = _items.firstWhere(
                        (i) => i.itemName == itemName,
                    orElse: () => Item(
                      id: '',
                      itemName: '',
                      qtyOnHand: 0.0,
                      avgCostPricePerKg: 0.0, avgSalePricePerKg: 0.0,
                    ),
                  );
                  if (item.id.isEmpty) continue;

                  final double currentQty = item.qtyOnHand;
                  final double qty = (row['qty'] ?? 0.0) as double;
                  final double initialQty = (row['initialQty'] ?? qty) as double;
                  final double delta =
                  widget.filled != null && widget.filled!['filledNumber'] != null
                      ? (initialQty - qty)
                      : -qty;
                  final double newQty = currentQty + delta;

                  if (newQty < 0) {
                    insufficientItems.add({'item': item, 'delta': delta});
                  }
                }

                if (insufficientItems.isNotEmpty) {
                  final proceed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(
                        languageProvider.isEnglish
                            ? 'Insufficient Stock'
                            : 'اسٹاک ناکافی',
                      ),
                      content: Text(
                        languageProvider.isEnglish
                            ? 'Some items will have negative stock. Proceed?'
                            : 'کچھ اشیاء کا اسٹاک منفی ہو جائے گا۔ جاری رکھیں؟',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(
                            languageProvider.isEnglish ? 'Cancel' : 'منسوخ کریں',
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(
                            languageProvider.isEnglish ? 'Proceed' : 'آگے بڑھیں',
                          ),
                        ),
                      ],
                    ),
                  ) ?? false;

                  if (!proceed) {
                    setState(() => _isButtonPressed = false);
                    return;
                  }
                }

                // ── 8. Build items list ──────────────────────────────
                final grandTotal = _calculateGrandTotal();
                final filledProvider =
                Provider.of<FilledProvider>(context, listen: false);

                final String filledNumber =
                    widget.filled?['filledNumber']?.toString() ??
                        (await filledProvider.getNextFilledNumber()).toString();

                final List<Map<String, dynamic>> items = _filledRows.map((row) {
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
                    'initialQty': row['initialQty'] ?? row['qty'] ?? 0.0,
                    'initialWeight': row['totalWeight'] ?? 0.0,
                    // Batch fields
                    'batchId': row['batchId'],
                    'batchNumber': row['batchNumber'],
                    'batchPurchasePrice': row['batchPurchasePrice'],
                    'availableBatchQty': row['availableBatchQty'],
                    'lengthBodyCombination': row['lengthBodyCombination'],
                  };
                }).toList();

                // ── 9. Prepare date ──────────────────────────────────
                final String createdAt = _dateController.text.isNotEmpty
                    ? DateTime(
                  DateTime.parse(_dateController.text).year,
                  DateTime.parse(_dateController.text).month,
                  DateTime.parse(_dateController.text).day,
                  DateTime.now().hour,
                  DateTime.now().minute,
                  DateTime.now().second,
                ).toIso8601String()
                    : DateTime.now().toIso8601String();

                // ── 10. Save / Update ────────────────────────────────
                if (widget.filled?['isFromQuotation'] == true) {
                  if (_isAutoReference &&
                      _selectedCustomerId != null &&
                      _selectedCustomerSerial != null) {
                    final autoRef =
                    await _generateCustomerSerialReference(increment: true);
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
                } else if (widget.filled != null &&
                    widget.filled!['filledNumber'] != null) {
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
                } else {
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

                // ── 11. Deduct stock (batch-aware) ───────────────────
                await _updateQtyOnHand(_filledRows);

                // ── 12. Update local state ───────────────────────────
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

                _showSnackBar(
                  context,
                  widget.filled == null || widget.filled?['isFromQuotation'] == true
                      ? (languageProvider.isEnglish
                      ? 'Invoice saved successfully'
                      : 'انوائس کامیابی سے محفوظ ہوگئی')
                      : (languageProvider.isEnglish
                      ? 'Invoice updated successfully'
                      : 'انوائس کامیابی سے تبدیل ہوگئی'),
                );
                await _offerWhatsAppMessage(filledNumber, _calculateGrandTotal());
              } catch (e) {
                print('Error saving invoice: $e');
                _showSnackBar(
                  context,
                  languageProvider.isEnglish
                      ? 'Failed to save invoice: ${e.toString()}'
                      : 'انوائس محفوظ کرنے میں ناکام: ${e.toString()}',
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
              widget.filled == null || widget.filled?['isFromQuotation'] == true
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
        // Check if item has length-body combinations
        if (selection.lengthBodyCombinations != null &&
            selection.lengthBodyCombinations!.isNotEmpty) {
          // Store the selection temporarily and show combination dialog
          // You'll need to implement a way to get the current row index
          // For now, we'll just use the item without combinations
          final selectedPrice = selectedCustomerId != null
              ? selection.getPriceForCustomer(selectedCustomerId)
              : selection.avgSalePricePerKg;

          // Parse BOM name to get just the size
          final parsedBOM = _parseBOMName(selection.itemName);
          controller.text = parsedBOM['size'] ?? selection.itemName;

          onSelected(selection.copyWith(
            avgCostPricePerKg: selectedPrice,
            avgSalePricePerKg: selectedPrice,
          ));
        } else {
          // Use customer price if customer is selected, otherwise use sale price
          final selectedPrice = selectedCustomerId != null
              ? selection.getPriceForCustomer(selectedCustomerId)
              : selection.avgSalePricePerKg;

          // Parse BOM name to get just the size
          final parsedBOM = _parseBOMName(selection.itemName);
          controller.text = parsedBOM['size'] ?? selection.itemName;

          onSelected(selection.copyWith(
            avgCostPricePerKg: selectedPrice,
            avgSalePricePerKg: selectedPrice,
          ));
        }
      },
    );
  }

  void _showLengthCombinationDialog(Item item, BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    bool isProcessing = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                languageProvider.isEnglish ? 'Select Length-Body Combination' : 'لمبائی-جسم کا مجموعہ منتخب کریں',
              ),
              content: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(maxHeight: 400),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: item.lengthBodyCombinations!.length,
                  itemBuilder: (context, index) {
                    final combination = item.lengthBodyCombinations![index];
                    return Card(
                      margin: EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text('${item.itemName} (${combination.length} - ${combination.bodyType})'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (combination.lengthDecimal.isNotEmpty)
                              Text(
                                'Decimal: ${combination.lengthDecimal}',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            if (combination.weightPerUnit != null)
                              Text(
                                'Weight/Unit: ${combination.weightPerUnit} ${combination.weightUnit}',
                                style: TextStyle(fontSize: 12, color: Colors.blue),
                              ),
                            if (combination.costPricePerKg != null && combination.salePricePerKg != null)
                              Text(
                                'Price/Kg: ${combination.salePricePerKg!.toStringAsFixed(2)} PKR',
                                style: TextStyle(fontSize: 12, color: Colors.green),
                              ),
                          ],
                        ),
                        trailing: Icon(Icons.arrow_forward),
                        onTap: () {
                          if (isProcessing) return;
                          setState(() { isProcessing = true; });
                          Navigator.pop(context);
                          Future.delayed(Duration(milliseconds: 100), () {
                            // This method should be implemented in the parent widget
                            // You'll need to pass the row index somehow
                            // For now, we'll call onSelected with null combination
                            final selectedPrice = selectedCustomerId != null
                                ? item.getPriceForCustomer(selectedCustomerId)
                                : item.avgSalePricePerKg;

                            // Parse BOM name to get just the size
                            final parsedBOM = _parseBOMName(item.itemName);
                            controller.text = parsedBOM['size'] ?? item.itemName;

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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(languageProvider.isEnglish ? 'Cancel' : 'منسوخ'),
                ),
                TextButton(
                  onPressed: () {
                    if (isProcessing) return;
                    setState(() { isProcessing = true; });
                    Navigator.pop(context);
                    Future.delayed(Duration(milliseconds: 100), () {
                      final selectedPrice = selectedCustomerId != null
                          ? item.getPriceForCustomer(selectedCustomerId)
                          : item.avgSalePricePerKg;

                      // Parse BOM name to get just the size
                      final parsedBOM = _parseBOMName(item.itemName);
                      controller.text = parsedBOM['size'] ?? item.itemName;

                      onSelected(item.copyWith(
                        avgCostPricePerKg: selectedPrice,
                        avgSalePricePerKg: selectedPrice,
                      ));
                    });
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
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (item.itemName.contains('|'))
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Show the full BOM name
                                        Text(
                                          item.itemName,
                                          style: TextStyle(fontWeight: FontWeight.w500),
                                        ),
                                        // Parse and show the individual parts in a smaller font
                                        Text(
                                          _formatBOMName(item.itemName),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600],
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Text(
                                      item.itemName,
                                      style: TextStyle(fontWeight: FontWeight.w500),
                                    ),
                                ],
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
                                    // Check if item has length-body combinations
                                    if (item.lengthBodyCombinations != null &&
                                        item.lengthBodyCombinations!.isNotEmpty) {
                                      // Show combination dialog
                                      _showLengthCombinationDialog(item, context);
                                    } else {
                                      final selectedPrice = selectedCustomerId != null
                                          ? item.getPriceForCustomer(selectedCustomerId)
                                          : item.avgSalePricePerKg;

                                      // Parse BOM name to get just the size
                                      final parsedBOM = _parseBOMName(item.itemName);
                                      controller.text = parsedBOM['size'] ?? item.itemName;

                                      // Find the row index where this item should be added
                                      // This assumes you have a way to get the current row index
                                      // You might need to pass the row index to this method
                                      onSelected(item.copyWith(
                                        avgCostPricePerKg: selectedPrice,
                                        avgSalePricePerKg: selectedPrice,
                                      ));
                                    }
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
                                if (item.lengthBodyCombinations != null &&
                                    item.lengthBodyCombinations!.isNotEmpty) {
                                  Navigator.pop(context);
                                  Future.delayed(Duration(milliseconds: 100), () {
                                    _showLengthCombinationDialog(item, context);
                                  });
                                } else {
                                  Navigator.pop(context);
                                  Future.delayed(Duration(milliseconds: 100), () {
                                    final selectedPrice = selectedCustomerId != null
                                        ? item.getPriceForCustomer(selectedCustomerId)
                                        : item.avgSalePricePerKg;

                                    // Parse BOM name to get just the size
                                    final parsedBOM = _parseBOMName(item.itemName);
                                    controller.text = parsedBOM['size'] ?? item.itemName;

                                    onSelected(item.copyWith(
                                      avgCostPricePerKg: selectedPrice,
                                      avgSalePricePerKg: selectedPrice,
                                    ));
                                  });
                                }
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

// Add this helper method to the CustomAutocomplete class
  String _formatBOMName(String bomName) {
    if (!bomName.contains('|')) return bomName;

    final parts = bomName.split('|');
    if (parts.length >= 3) {
      return 'Size: ${parts[0].trim()} | Length: ${parts[1].trim()} | Body: ${parts[2].trim()}';
    }
    return bomName;
  }

// Add this method to parse BOM names
  Map<String, String> _parseBOMName(String bomName) {
    Map<String, String> result = {
      'size': '',
      'length': '',
      'bodyType': '',
      'fullName': bomName
    };

    if (bomName.contains('|')) {
      final parts = bomName.split('|').map((part) => part.trim()).toList();

      if (parts.length >= 3) {
        result['size'] = parts[0];
        result['length'] = parts[1];
        result['bodyType'] = parts[2];
      } else if (parts.length == 2) {
        result['size'] = parts[0];
        result['length'] = parts[1];
      } else if (parts.length == 1) {
        result['size'] = parts[0];
      }
    } else {
      result['size'] = bomName;
    }

    return result;
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

