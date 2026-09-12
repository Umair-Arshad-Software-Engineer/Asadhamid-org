import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../Provider/Mazdoorprovider ·.dart';
import '../Provider/customerprovider.dart';
import '../Provider/lanprovider.dart';

class AddCustomer extends StatefulWidget {
  final Customer? customer;

  // NEW: when true, the form opens directly in "Mazdoor Person" mode.
  // Existing call sites (AddCustomer(), AddCustomer(customer: c)) are
  // unaffected since this defaults to false.
  final bool startAsMazdoor;

  const AddCustomer({Key? key, this.customer, this.startAsMazdoor = false})
      : super(key: key);

  @override
  State<AddCustomer> createState() => _AddCustomerState();
}

// NEW: which kind of person this form is creating/editing.
enum _PersonType { customer, mazdoor }

class _AddCustomerState extends State<AddCustomer> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _balanceController = TextEditingController(text: '0.00');
  bool _isEditing = false;

  // NEW: type toggle state. Editing an existing Customer always stays
  // Customer (Mazdoor persons are edited via their own list for now).
  _PersonType _personType = _PersonType.customer;

  DateTime _openingBalanceDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Initialize with customer data if provided
    if (widget.customer != null) {
      _isEditing = true;
      _personType = _PersonType.customer;
      _nameController.text = widget.customer!.name;
      _addressController.text = widget.customer!.address;
      _phoneController.text = widget.customer!.phone;
      _cityController.text = widget.customer!.city;
      _balanceController.text =
          widget.customer!.openingBalance?.toStringAsFixed(2) ?? '0.00';
      _openingBalanceDate =
          widget.customer!.openingBalanceDate ?? DateTime.now();
    } else if (widget.startAsMazdoor) {
      _personType = _PersonType.mazdoor;
    }
  }

  Future<void> _selectDateTime(BuildContext context) async {
    // First pick date
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _openingBalanceDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (pickedDate != null) {
      // Then pick time
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_openingBalanceDate),
      );

      if (pickedTime != null) {
        setState(() {
          _openingBalanceDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isMazdoor = _personType == _PersonType.mazdoor;
    // Mazdoor accent color kept visually distinct from Customer's orange.
    final accentColor = isMazdoor ? Colors.teal[400]! : Colors.orange[300]!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
            _isEditing
                ? (languageProvider.isEnglish
                ? 'Edit Customer'
                : 'کسٹمر میں ترمیم کریں')
                : (isMazdoor
                ? (languageProvider.isEnglish
                ? 'Add Mazdoor Person'
                : 'مزدور شامل کریں')
                : (languageProvider.isEnglish
                ? 'Add Customer'
                : 'کسٹمر شامل کریں۔')),
            style: TextStyle(color: Colors.white)),
        backgroundColor: accentColor,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEditing
                      ? (languageProvider.isEnglish
                      ? 'Edit Customer Details'
                      : 'کسٹمر کی تفصیلات میں ترمیم کریں')
                      : (isMazdoor
                      ? (languageProvider.isEnglish
                      ? 'Mazdoor Person Details'
                      : 'مزدور کی تفصیلات')
                      : (languageProvider.isEnglish
                      ? 'Customer Details'
                      : 'کسٹمر کی تفصیلات')),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
                SizedBox(height: 16),

                // ── NEW: Customer / Mazdoor type toggle ──
                // Hidden while editing an existing Customer, since type
                // switching mid-edit would be ambiguous (different
                // Firebase nodes / ledgers entirely).
                if (!_isEditing)
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
                                setState(() => _personType = _PersonType.customer),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: !isMazdoor
                                    ? Colors.orange[300]
                                    : Colors.transparent,
                                borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(7)),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.person,
                                      color: !isMazdoor
                                          ? Colors.white
                                          : Colors.grey[600]),
                                  Text(
                                    languageProvider.isEnglish
                                        ? 'Customer'
                                        : 'کسٹمر',
                                    style: TextStyle(
                                      color: !isMazdoor
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
                            onTap: () =>
                                setState(() => _personType = _PersonType.mazdoor),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isMazdoor
                                    ? Colors.teal[400]
                                    : Colors.transparent,
                                borderRadius: const BorderRadius.horizontal(
                                    right: Radius.circular(7)),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.engineering,
                                      color: isMazdoor
                                          ? Colors.white
                                          : Colors.grey[600]),
                                  Text(
                                    languageProvider.isEnglish
                                        ? 'Mazdoor Person'
                                        : 'مزدور',
                                    style: TextStyle(
                                      color: isMazdoor
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
                if (isMazdoor && !_isEditing)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.teal[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: Colors.teal[700]),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              languageProvider.isEnglish
                                  ? 'Mazdoor persons receive wire and return bolts or cash against fixed job values. Manage their jobs from the Mazdoor list.'
                                  : 'مزدور وائر لیتے ہیں اور اس کے بدلے بولٹس یا نقدی واپس دیتے ہیں۔ ان کے کام مزدور کی فہرست سے دیکھیں۔',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.teal[700]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                SizedBox(height: 20),
                // Name Field
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: languageProvider.isEnglish ? 'Name' : 'نام',
                    labelStyle: TextStyle(color: accentColor),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: accentColor),
                    ),
                  ),
                  validator: (value) => value!.isEmpty
                      ? languageProvider.isEnglish
                      ? 'Please enter the name'
                      : 'براہ کرم نام درج کریں'
                      : null,
                ),
                SizedBox(height: 16),
                // Address Field
                TextFormField(
                  controller: _addressController,
                  decoration: InputDecoration(
                    labelText: languageProvider.isEnglish ? 'Address' : 'پتہ',
                    labelStyle: TextStyle(color: accentColor),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: accentColor),
                    ),
                  ),
                  validator: (value) => value!.isEmpty
                      ? languageProvider.isEnglish
                      ? 'Please enter the address'
                      : 'براہ کرم پتہ درج کریں'
                      : null,
                ),
                SizedBox(height: 16),
                // City Field
                TextFormField(
                  controller: _cityController,
                  decoration: InputDecoration(
                    labelText: languageProvider.isEnglish ? 'City' : 'شہر',
                    labelStyle: TextStyle(color: accentColor),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: accentColor),
                    ),
                  ),
                  validator: (value) => value!.isEmpty
                      ? languageProvider.isEnglish
                      ? 'Please enter the city'
                      : 'براہ کرم شہر درج کریں'
                      : null,
                ),
                SizedBox(height: 16),
                // Phone Field
                TextFormField(
                  controller: _phoneController,
                  decoration: InputDecoration(
                    labelText:
                    languageProvider.isEnglish ? 'Phone Number' : 'موبائل نمبر',
                    labelStyle: TextStyle(color: accentColor),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: accentColor),
                    ),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value!.isEmpty) {
                      return languageProvider.isEnglish
                          ? 'Please enter the phone number'
                          : 'براہ کرم فون نمبر درج کریں';
                    }
                    if (!RegExp(r'^[0-9]{10,15}$').hasMatch(value)) {
                      return languageProvider.isEnglish
                          ? 'Please enter a valid phone number'
                          : 'براہ کرم درست فون نمبر درج کریں';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),
                // Opening Balance Field
                TextFormField(
                  controller: _balanceController,
                  decoration: InputDecoration(
                    labelText: languageProvider.isEnglish
                        ? 'Opening Balance'
                        : 'ابتدائی بیلنس',
                    labelStyle: TextStyle(color: accentColor),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: accentColor),
                    ),
                    helperText: isMazdoor
                        ? (languageProvider.isEnglish
                        ? 'Positive = Mazdoor owes you, Negative = you owe Mazdoor'
                        : 'مثبت = مزدور آپ کا مقروض ہے، منفی = آپ مزدور کے مقروض ہیں'
                    )
                        : null,
                  ),
                  keyboardType:
                  TextInputType.numberWithOptions(decimal: true, signed: true),
                  validator: (value) {
                    if (value!.isEmpty) {
                      return languageProvider.isEnglish
                          ? 'Please enter opening balance (0 if none)'
                          : 'براہ کرم ابتدائی بیلنس درج کریں (اگر کوئی نہیں تو 0)';
                    }
                    if (double.tryParse(value) == null) {
                      return languageProvider.isEnglish
                          ? 'Please enter a valid number'
                          : 'براہ کرم درست نمبر درج کریں';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Opening Balance Date/Time Field
                Card(
                  elevation: 2,
                  child: ListTile(
                    leading: Icon(Icons.calendar_today, color: accentColor),
                    title: Text(
                      languageProvider.isEnglish
                          ? 'Opening Balance Date & Time'
                          : 'ابتدائی بیلنس کی تاریخ اور وقت',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: accentColor,
                      ),
                    ),
                    subtitle: Text(
                      DateFormat('dd/MM/yyyy - HH:mm').format(_openingBalanceDate),
                      style: TextStyle(
                        fontSize: 16,
                        color: accentColor,
                      ),
                    ),
                    trailing: Icon(Icons.edit, color: accentColor),
                    onTap: () => _selectDateTime(context),
                  ),
                ),

                SizedBox(height: 20),
                // Save Button
                Align(
                  alignment: Alignment.center,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _save(context),
                    child: Text(
                      _isEditing
                          ? (languageProvider.isEnglish ? 'Update' : 'اپ ڈیٹ کریں')
                          : (languageProvider.isEnglish ? 'Save' : 'محفوظ کریں۔'),
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _save(BuildContext context) {
    if (!_formKey.currentState!.validate()) return;

    final openingBalance = double.tryParse(_balanceController.text) ?? 0.0;

    if (_isEditing) {
      // Editing always applies to a Customer (Mazdoor edits happen from
      // the Mazdoor list screen).
      final customerProvider =
      Provider.of<CustomerProvider>(context, listen: false);
      customerProvider.updateCustomer(
        widget.customer!.id,
        _nameController.text,
        _addressController.text,
        _phoneController.text,
        _cityController.text,
        openingBalance,
        _openingBalanceDate,
      );
      Navigator.pop(context);
      return;
    }

    if (_personType == _PersonType.mazdoor) {
      final mazdoorProvider =
      Provider.of<MazdoorProvider>(context, listen: false);
      mazdoorProvider
          .addMazdoor(
        name: _nameController.text,
        phone: _phoneController.text,
        address: _addressController.text,
        city: _cityController.text,
        openingBalance: openingBalance,
        openingBalanceDate: _openingBalanceDate,
      )
          .then((_) => Navigator.pop(context))
          .catchError((e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add Mazdoor: $e')),
        );
      });
      return;
    }

    // New Customer
    final customerProvider =
    Provider.of<CustomerProvider>(context, listen: false);
    customerProvider.addCustomerWithSerial(
      _nameController.text,
      _addressController.text,
      _phoneController.text,
      _cityController.text,
      openingBalance,
      _openingBalanceDate,
    );
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _balanceController.dispose();
    super.dispose();
  }
}