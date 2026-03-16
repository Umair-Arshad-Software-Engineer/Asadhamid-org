import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Provider/lanprovider.dart';
import 'dbworking.dart';
import 'model.dart'; // This imports all the model classes including ContractWorkEntry

class ContractWorkScreen extends StatefulWidget {
  final Employee employee;

  const ContractWorkScreen({Key? key, required this.employee}) : super(key: key);

  @override
  _ContractWorkScreenState createState() => _ContractWorkScreenState();
}

class _ContractWorkScreenState extends State<ContractWorkScreen> {
  final DatabaseService _dbService = DatabaseService();

  // Use the ContractWorkEntry from model.dart
  List<ContractWorkEntry> _entries = [];
  bool _isLoading = false;
  DateTime _selectedMonth = DateTime.now();

  // Form controllers
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  // Localization
  final Map<String, String> _en = {
    'title': 'Work Entries',
    'addEntry': 'Add Work Entry',
    'date': 'Date',
    'quantity': 'Quantity',
    'unit': 'Unit',
    'ratePerUnit': 'Rate per Unit',
    'totalAmount': 'Total Amount',
    'notes': 'Description (Optional)',
    'save': 'Save',
    'cancel': 'Cancel',
    'noEntries': 'No work entries found for this month',
    'selectDate': 'Select Date',
    'delete': 'Delete',
    'deleteConfirm': 'Delete this entry?',
    'yes': 'Yes',
    'no': 'No',
    'summary': 'Monthly Summary',
    'totalUnits': 'Total Units',
    'totalEarnings': 'Total Earnings',
    'selectMonth': 'Select Month',
    'quantityHint': 'Enter quantity made',
    'notesHint': 'Any additional description',
    'entryAdded': 'Work entry added!',
    'entryDeleted': 'Entry deleted!',
    'fillQuantity': 'Please enter quantity',
    'monthlyEntries': 'Entries this month',
  };

  final Map<String, String> _ur = {
    'title': 'کام کے اندراجات',
    'addEntry': 'کام کا اندراج کریں',
    'date': 'تاریخ',
    'quantity': 'مقدار',
    'unit': 'اکائی',
    'ratePerUnit': 'فی اکائی قیمت',
    'totalAmount': 'کل رقم',
    'notes': 'وضاحت (اختیاری)',
    'save': 'محفوظ کریں',
    'cancel': 'منسوخ کریں',
    'noEntries': 'اس مہینے کوئی اندراج نہیں ملا',
    'selectDate': 'تاریخ منتخب کریں',
    'delete': 'حذف کریں',
    'deleteConfirm': 'یہ اندراج حذف کریں؟',
    'yes': 'ہاں',
    'no': 'نہیں',
    'summary': 'ماہانہ خلاصہ',
    'totalUnits': 'کل اکائیاں',
    'totalEarnings': 'کل آمدنی',
    'selectMonth': 'مہینہ منتخب کریں',
    'quantityHint': 'بنائی گئی مقدار درج کریں',
    'notesHint': 'کوئی اضافی وضاحت',
    'entryAdded': 'کام کا اندراج ہو گیا!',
    'entryDeleted': 'اندراج حذف ہو گیا!',
    'fillQuantity': 'براہ کرم مقدار درج کریں',
    'monthlyEntries': 'اس مہینے کے اندراجات',
  };

  String _t(String key) {
    final lang = context.read<LanguageProvider>();
    return lang.isEnglish ? (_en[key] ?? key) : (_ur[key] ?? key);
  }

  String _getUnitText(String unit, bool isEnglish) {
    switch (unit) {
      case 'bag': return isEnglish ? 'Bag' : 'بوری';
      case 'kg': return isEnglish ? 'KG' : 'کلوگرام';
      case 'ton': return isEnglish ? 'Ton' : 'ٹن';
      case 'meter': return isEnglish ? 'Meter' : 'میٹر';
      case 'piece': return isEnglish ? 'Piece' : 'پیس';
      default: return unit;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    setState(() => _isLoading = true);
    try {
      final entries = await _dbService.getContractWorkEntries(
        widget.employee.id!,
        month: _selectedMonth,
      );
      setState(() {
        _entries = entries;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading entries: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveEntry(ContractWorkEntry entry) async {
    try {
      await _dbService.addContractWorkEntry(entry);
      await _loadEntries(); // Reload to get the updated list

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t('entryAdded')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving entry: $e')),
        );
      }
    }
  }

  Future<void> _deleteEntry(ContractWorkEntry entry) async {
    try {
      await _dbService.deleteContractWorkEntry(widget.employee.id!, entry.id!);
      await _loadEntries(); // Reload to get updated list

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t('entryDeleted')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting entry: $e')),
        );
      }
    }
  }

  List<ContractWorkEntry> get _filteredEntries => _entries.where((e) =>
  e.date.year == _selectedMonth.year && e.date.month == _selectedMonth.month
  ).toList();

  double get _totalUnits => _filteredEntries.fold(0, (s, e) => s + e.quantity);
  double get _totalEarnings => _filteredEntries.fold(0, (s, e) => s + e.totalAmount);

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() => _selectedMonth = DateTime(picked.year, picked.month, 1));
      _loadEntries();
    }
  }

  void _showAddEntrySheet() {
    final lang = context.read<LanguageProvider>();
    _quantityController.clear();
    _notesController.clear();
    _selectedDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  _t('addEntry'),
                  style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold,
                    fontFamily: lang.fontFamily,
                  ),
                ),
                const SizedBox(height: 20),

                // Date picker row
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setSheetState(() => _selectedDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, size: 18, color: Colors.blue),
                        const SizedBox(width: 10),
                        Text(
                          '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                          style: TextStyle(
                            fontSize: 15,
                            fontFamily: lang.fontFamily,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _t('selectDate'),
                          style: TextStyle(color: Colors.blue, fontSize: 13, fontFamily: lang.fontFamily),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Quantity + Unit info row
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _quantityController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: _t('quantity'),
                          hintText: _t('quantityHint'),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          labelStyle: TextStyle(fontFamily: lang.fontFamily),
                          hintStyle: TextStyle(fontFamily: lang.fontFamily, fontSize: 12),
                        ),
                        style: TextStyle(fontFamily: lang.fontFamily),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        border: Border.all(color: Colors.orange.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _getUnitText(widget.employee.contractUnit ?? 'bag', lang.isEnglish),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                              fontFamily: lang.fontFamily,
                            ),
                          ),
                          Text(
                            'PKR ${widget.employee.basicSalary.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade700,
                              fontFamily: lang.fontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Description/Notes
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: _t('notes'),
                    hintText: _t('notesHint'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    labelStyle: TextStyle(fontFamily: lang.fontFamily),
                    hintStyle: TextStyle(fontFamily: lang.fontFamily, fontSize: 12),
                  ),
                  style: TextStyle(fontFamily: lang.fontFamily),
                ),
                const SizedBox(height: 20),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(_t('cancel'), style: TextStyle(fontFamily: lang.fontFamily)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () async {
                          final qty = double.tryParse(_quantityController.text.trim());
                          if (qty == null || qty <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(_t('fillQuantity'))),
                            );
                            return;
                          }
                          final rate = widget.employee.basicSalary;

                          // Create entry using the model class from model.dart
                          final entry = ContractWorkEntry(
                            employeeId: widget.employee.id!,
                            employeeName: widget.employee.name,
                            date: _selectedDate,
                            quantity: qty,
                            unit: widget.employee.contractUnit ?? 'bag',
                            unitPrice: rate,
                            totalAmount: qty * rate,
                            description: _notesController.text.trim().isEmpty
                                ? null
                                : _notesController.text.trim(),
                          );

                          await _saveEntry(entry);
                          if (mounted) {
                            Navigator.pop(context);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          _t('save'),
                          style: TextStyle(fontWeight: FontWeight.bold, fontFamily: lang.fontFamily),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(ContractWorkEntry entry) async {
    final lang = context.read<LanguageProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('delete'), style: TextStyle(fontFamily: lang.fontFamily)),
        content: Text(_t('deleteConfirm'), style: TextStyle(fontFamily: lang.fontFamily)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('no'), style: TextStyle(fontFamily: lang.fontFamily)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(_t('yes'), style: TextStyle(fontFamily: lang.fontFamily)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _deleteEntry(entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final entries = _filteredEntries;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_t('title'), style: TextStyle(fontFamily: lang.fontFamily)),
            Text(
              widget.employee.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
                fontFamily: lang.fontFamily,
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Month selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.orange.shade50,
            child: Row(
              children: [
                Icon(Icons.calendar_month, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_selectedMonth.month}/${_selectedMonth.year}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: lang.fontFamily,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickMonth,
                  icon: const Icon(Icons.edit_calendar, size: 18),
                  label: Text(_t('selectMonth'), style: TextStyle(fontFamily: lang.fontFamily)),
                ),
              ],
            ),
          ),

          // Summary card
          Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Employee info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.employee.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              fontFamily: lang.fontFamily,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  lang.isEnglish ? 'Contract' : 'کنٹریکٹ',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange.shade800,
                                    fontFamily: lang.fontFamily,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'PKR ${widget.employee.basicSalary.toStringAsFixed(0)} / ${_getUnitText(widget.employee.contractUnit ?? 'bag', lang.isEnglish)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontFamily: lang.fontFamily,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Stats
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _statChip(
                          _t('totalUnits'),
                          '${_totalUnits.toStringAsFixed(1)} ${_getUnitText(widget.employee.contractUnit ?? 'bag', lang.isEnglish)}',
                          Colors.blue,
                          lang.fontFamily,
                        ),
                        const SizedBox(height: 6),
                        _statChip(
                          _t('totalEarnings'),
                          'PKR ${_totalEarnings.toStringAsFixed(0)}',
                          Colors.green,
                          lang.fontFamily,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Entries header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  '${_t('monthlyEntries')} (${entries.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                    fontFamily: lang.fontFamily,
                  ),
                ),
              ],
            ),
          ),

          // Entry list
          Expanded(
            child: entries.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.work_off_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text(
                    _t('noEntries'),
                    style: TextStyle(
                      color: Colors.grey,
                      fontFamily: lang.fontFamily,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _buildEntryCard(entry, lang);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddEntrySheet,
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.add),
        label: Text(
          _t('addEntry'),
          style: TextStyle(fontFamily: lang.fontFamily),
        ),
      ),
    );
  }

  Widget _buildEntryCard(ContractWorkEntry entry, LanguageProvider lang) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Date badge
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                children: [
                  Text(
                    entry.date.day.toString(),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade800,
                    ),
                  ),
                  Text(
                    '${entry.date.month}/${entry.date.year % 100}',
                    style: TextStyle(fontSize: 11, color: Colors.orange.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${entry.quantity.toStringAsFixed(entry.quantity % 1 == 0 ? 0 : 1)} ${_getUnitText(entry.unit, lang.isEnglish)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          fontFamily: lang.fontFamily,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '× PKR ${entry.unitPrice.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                          fontFamily: lang.fontFamily,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (entry.description != null && entry.description!.isNotEmpty)
                    Text(
                      entry.description!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                        fontFamily: lang.fontFamily,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Total + delete
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'PKR ${entry.totalAmount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.green.shade700,
                    fontFamily: lang.fontFamily,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _confirmDelete(entry),
                  child: Icon(Icons.delete_outline, color: Colors.red.shade300, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, String value, Color color, String fontFamily) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 14,
            fontFamily: fontFamily,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[500],
            fontFamily: fontFamily,
          ),
        ),
      ],
    );
  }
}