import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../Provider/lanprovider.dart';
import 'dbworking.dart';
import 'model.dart';

class AddEmployeeScreen extends StatefulWidget {
  @override
  _AddEmployeeScreenState createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends State<AddEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _salaryController = TextEditingController();
  final _unitPriceController = TextEditingController();
  final _overtimeRateController = TextEditingController();
  final _standardHoursController = TextEditingController(text: '8');

  String _salaryType = 'monthly';
  String _contractUnit = 'bag';
  DateTime _joinDate = DateTime.now();
  final DatabaseService _dbService = DatabaseService();

  Future<void> _selectJoinDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _joinDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _joinDate = picked;
      });
    }
  }

  Future<void> _addEmployee() async {
    if (_formKey.currentState!.validate()) {
      try {
        double salary;
        double? overtimeRate;
        double? standardHours;

        if (_salaryType == 'contract') {
          salary = double.parse(_unitPriceController.text);
        } else {
          salary = double.parse(_salaryController.text);
          // Parse overtime fields for non-contract employees
          if (_overtimeRateController.text.isNotEmpty) {
            overtimeRate = double.tryParse(_overtimeRateController.text);
          }
          standardHours = double.tryParse(_standardHoursController.text) ?? 8;
        }

        Employee employee = Employee(
          name: _nameController.text,
          address: _addressController.text,
          basicSalary: salary,
          salaryType: _salaryType,
          joinDate: _joinDate,
          contractUnit: _salaryType == 'contract' ? _contractUnit : null,
          overtimeRate: overtimeRate,
          standardWorkingHours: standardHours,
        );

        await _dbService.addEmployee(employee);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  Provider.of<LanguageProvider>(context, listen: false).isEnglish
                      ? 'Employee added successfully!'
                      : 'ملازم کامیابی سے شامل ہو گیا ہے!'
              ),
              backgroundColor: Colors.green,
            ),
          );

          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error adding employee: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(language.isEnglish ? "Add Employee" : "ملازم شامل کریں"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name Field
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: language.isEnglish ? "Employee Name" : "ملازم کا نام",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return language.isEnglish
                          ? "Please enter employee name"
                          : "نام درج کریں";
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Address Field
                TextFormField(
                  controller: _addressController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: language.isEnglish ? "Address" : "پتہ",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return language.isEnglish
                          ? "Please enter address"
                          : "پتہ درج کریں";
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Salary Type Dropdown
                DropdownButtonFormField<String>(
                  value: _salaryType,
                  decoration: InputDecoration(
                    labelText: language.isEnglish ? "Salary Type" : "تنخواہ کی قسم",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'monthly',
                      child: Text(language.isEnglish ? 'Monthly' : 'ماہانہ'),
                    ),
                    DropdownMenuItem(
                      value: 'daily',
                      child: Text(language.isEnglish ? 'Daily' : 'یومیہ'),
                    ),
                    DropdownMenuItem(
                      value: 'contract',
                      child: Text(language.isEnglish ? 'Contract' : 'کنٹریکٹ'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _salaryType = value!;
                    });
                  },
                ),
                SizedBox(height: 16),

                // Conditional Fields based on Salary Type
                if (_salaryType != 'contract') ...[
                  // Monthly/Daily Salary Field
                  TextFormField(
                    controller: _salaryController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _salaryType == 'monthly'
                          ? (language.isEnglish ? "Monthly Salary" : "ماہانہ تنخواہ")
                          : (language.isEnglish ? "Daily Salary" : "یومیہ تنخواہ"),
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.currency_rupee),
                      hintText: language.isEnglish ? "Enter amount" : "رقم درج کریں",
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return language.isEnglish
                            ? "Please enter salary"
                            : "تنخواہ درج کریں";
                      }
                      if (double.tryParse(value) == null) {
                        return language.isEnglish
                            ? "Please enter a valid number"
                            : "درست نمبر درج کریں";
                      }
                      if (double.parse(value) <= 0) {
                        return language.isEnglish
                            ? "Salary must be greater than 0"
                            : "تنخواہ صفر سے زیادہ ہونی چاہیے";
                      }
                      return null;
                    },
                  ),

                  SizedBox(height: 16),

                  // Standard Working Hours
                  TextFormField(
                    controller: _standardHoursController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: language.isEnglish
                          ? "Standard Working Hours/Day"
                          : "معیاری کام کے گھنٹے/دن",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.timer),
                      hintText: language.isEnglish ? "Default: 8 hours" : "طے شدہ: 8 گھنٹے",
                    ),
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        if (double.tryParse(value) == null) {
                          return language.isEnglish
                              ? "Please enter a valid number"
                              : "درست نمبر درج کریں";
                        }
                        if (double.parse(value) <= 0) {
                          return language.isEnglish
                              ? "Hours must be greater than 0"
                              : "گھنٹے صفر سے زیادہ ہونے چاہئیں";
                        }
                      }
                      return null;
                    },
                  ),

                  SizedBox(height: 16),

                  // Overtime Rate (Optional)
                  TextFormField(
                    controller: _overtimeRateController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: language.isEnglish
                          ? "Overtime Rate (per hour) - Optional"
                          : "اوور ٹائم ریٹ (فی گھنٹہ) - اختیاری",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.timer_off),
                      hintText: language.isEnglish
                          ? "Leave empty to auto-calculate"
                          : "خالی چھوڑیں خودکار حساب کے لیے",
                    ),
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        if (double.tryParse(value) == null) {
                          return language.isEnglish
                              ? "Please enter a valid number"
                              : "درست نمبر درج کریں";
                        }
                        if (double.parse(value) < 0) {
                          return language.isEnglish
                              ? "Rate cannot be negative"
                              : "ریٹ منفی نہیں ہو سکتا";
                        }
                      }
                      return null;
                    },
                  ),
                ] else ...[
                  // Contract Unit Dropdown
                  DropdownButtonFormField<String>(
                    value: _contractUnit,
                    decoration: InputDecoration(
                      labelText: language.isEnglish ? "Contract Unit" : "کنٹریکٹ کی اکائی",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.scale),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'bag',
                        child: Text(language.isEnglish ? 'Per Bag' : 'فی بوری'),
                      ),
                      DropdownMenuItem(
                        value: 'kg',
                        child: Text(language.isEnglish ? 'Per Kg' : 'فی کلوگرام'),
                      ),
                      DropdownMenuItem(
                        value: 'ton',
                        child: Text(language.isEnglish ? 'Per Ton' : 'فی ٹن'),
                      ),
                      DropdownMenuItem(
                        value: 'meter',
                        child: Text(language.isEnglish ? 'Per Meter' : 'فی میٹر'),
                      ),
                      DropdownMenuItem(
                        value: 'piece',
                        child: Text(language.isEnglish ? 'Per Piece' : 'فی پیس'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _contractUnit = value!;
                      });
                    },
                  ),
                  SizedBox(height: 16),

                  // Unit Price Field
                  TextFormField(
                    controller: _unitPriceController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: language.isEnglish
                          ? "Price per ${_getUnitText(_contractUnit, true)}"
                          : "قیمت فی ${_getUnitText(_contractUnit, false)}",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.currency_rupee),
                      hintText: language.isEnglish
                          ? "Enter amount"
                          : "رقم درج کریں",
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return language.isEnglish
                            ? "Please enter price per ${_getUnitText(_contractUnit, true)}"
                            : "فی ${_getUnitText(_contractUnit, false)} قیمت درج کریں";
                      }
                      if (double.tryParse(value) == null) {
                        return language.isEnglish
                            ? "Please enter a valid number"
                            : "درست نمبر درج کریں";
                      }
                      if (double.parse(value) <= 0) {
                        return language.isEnglish
                            ? "Price must be greater than 0"
                            : "قیمت صفر سے زیادہ ہونی چاہیے";
                      }
                      return null;
                    },
                  ),
                ],

                SizedBox(height: 16),

                // Join Date Picker
                InkWell(
                  onTap: _selectJoinDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: language.isEnglish ? "Join Date" : "شمولیت کی تاریخ",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat('dd MMMM yyyy').format(_joinDate),
                          style: TextStyle(fontSize: 16),
                        ),
                        Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 24),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _addEmployee,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      language.isEnglish ? "Add Employee" : "ملازم شامل کریں",
                      style: TextStyle(fontSize: 16),
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

  // Helper method to get unit text in appropriate language
  String _getUnitText(String unit, bool isEnglish) {
    switch (unit) {
      case 'bag':
        return isEnglish ? 'bag' : 'بوری';
      case 'kg':
        return isEnglish ? 'kg' : 'کلوگرام';
      case 'ton':
        return isEnglish ? 'ton' : 'ٹن';
      case 'meter':
        return isEnglish ? 'meter' : 'میٹر';
      case 'piece':
        return isEnglish ? 'piece' : 'پیس';
      default:
        return unit;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _salaryController.dispose();
    _unitPriceController.dispose();
    _overtimeRateController.dispose();
    _standardHoursController.dispose();
    super.dispose();
  }
}