import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Provider/lanprovider.dart';

class AddVendorPage extends StatefulWidget {
  final Map<String, dynamic>? vendorData; // Vendor data for editing
  final bool isEditMode;

  const AddVendorPage({
    super.key,
    this.vendorData,
    this.isEditMode = false,
  });

  @override
  State<AddVendorPage> createState() => _AddVendorPageState();
}

class _AddVendorPageState extends State<AddVendorPage> {
  final TextEditingController _vendorNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref("vendors");

  String? _vendorId; // For edit mode

  @override
  void initState() {
    super.initState();

    // If in edit mode, populate fields with existing data
    if (widget.isEditMode && widget.vendorData != null) {
      _initializeEditData();
    }
  }

  void _initializeEditData() {
    final vendorData = widget.vendorData!;

    setState(() {
      _vendorId = vendorData['id'];
      _vendorNameController.text = vendorData['name'] ?? '';
      _phoneController.text = vendorData['phone'] ?? '';
      _addressController.text = vendorData['address'] ?? '';
    });
  }

  void _addVendor() async {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final vendorName = _vendorNameController.text.trim();

    if (vendorName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(languageProvider.isEnglish
              ? 'Vendor name cannot be empty.'
              : 'وینڈر کا نام خالی نہیں ہو سکتا۔'),
        ),
      );
      return;
    }

    try {
      // Create vendor data object — only name, phone, address
      Map<String, dynamic> vendorData = {
        "name": vendorName,
        "phone": _phoneController.text.trim(),
        "address": _addressController.text.trim(),
        "updatedAt": DateTime.now().millisecondsSinceEpoch,
      };

      // For new vendor, add created date
      if (!widget.isEditMode) {
        vendorData["createdAt"] = DateTime.now().millisecondsSinceEpoch;
        vendorData["openingBalance"] = 0.0;
        vendorData["openingBalanceDate"] = DateTime.now().toIso8601String();
      }

      // Remove empty fields from the data
      vendorData.removeWhere((key, value) => value.toString().isEmpty);

      if (widget.isEditMode && _vendorId != null) {
        // Update existing vendor
        await _databaseRef.child(_vendorId!).update(vendorData);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(languageProvider.isEnglish
                ? 'Vendor updated successfully!'
                : 'وینڈر کامیابی سے اپ ڈیٹ کر دیا گیا!'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.pop(context);
      } else {
        // Add new vendor
        await _databaseRef.push().set(vendorData);

        _clearAllFields();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(languageProvider.isEnglish
                ? 'Vendor added successfully!'
                : 'وینڈر کامیابی سے شامل کر دیا گیا!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(languageProvider.isEnglish
              ? 'Error: $e'
              : 'خرابی: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _clearAllFields() {
    _vendorNameController.clear();
    _phoneController.clear();
    _addressController.clear();
  }

  @override
  void dispose() {
    _vendorNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditMode
              ? (languageProvider.isEnglish ? 'Edit Vendor' : 'وینڈر میں ترمیم کریں')
              : (languageProvider.isEnglish ? 'Add Vendor' : 'وینڈر شامل کریں'),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Required field indicator
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                languageProvider.isEnglish ? '* Required fields' : '* ضروری فیلڈز',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

            // Vendor Name Field (Required)
            _buildLabel('${languageProvider.isEnglish ? 'Vendor Name' : 'وینڈر کا نام'} *'),
            _buildTextField(
              controller: _vendorNameController,
              hintText: languageProvider.isEnglish ? 'Enter vendor name' : 'وینڈر کا نام درج کریں',
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 16),

            // Phone Number Field
            _buildLabel(languageProvider.isEnglish ? 'Phone Number' : 'فون نمبر'),
            _buildTextField(
              controller: _phoneController,
              hintText: languageProvider.isEnglish ? 'Enter phone number' : 'فون نمبر درج کریں',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),

            // Address Field (Multi-line)
            _buildLabel(languageProvider.isEnglish ? 'Address' : 'پتہ'),
            SizedBox(
              height: 100,
              child: TextField(
                controller: _addressController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  hintText: languageProvider.isEnglish ? 'Enter complete address' : 'مکمل پتہ درج کریں',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 16.0,
                  ),
                ),
                maxLines: 4,
                textInputAction: TextInputAction.newline,
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                // Save/Update Button
                Expanded(
                  child: ElevatedButton(
                    onPressed: _addVendor,
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: widget.isEditMode ? Colors.blue : Colors.orange[300],
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      elevation: 5,
                    ),
                    child: Text(
                      widget.isEditMode
                          ? (languageProvider.isEnglish ? 'Update Vendor' : 'وینڈر اپ ڈیٹ کریں')
                          : (languageProvider.isEnglish ? 'Add Vendor' : 'وینڈر شامل کریں'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Clear Button (only for add mode)
                if (!widget.isEditMode)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _clearAllFields,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                        side: BorderSide(color: Colors.grey[300]!),
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                      child: Text(
                        languageProvider.isEnglish ? 'Clear All' : 'سب صاف کریں',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to create labels
  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // Helper method to create text fields
  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required TextInputType keyboardType,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        hintText: hintText,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12.0,
          vertical: 16.0,
        ),
      ),
      keyboardType: keyboardType,
      textInputAction: TextInputAction.next,
    );
  }
}