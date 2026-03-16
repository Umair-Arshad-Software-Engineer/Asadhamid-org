import 'package:flutter/material.dart';
import 'package:mughal_group_branch_two/NewEmployee/salary_list_screen.dart';
import 'package:provider/provider.dart';
import '../Provider/lanprovider.dart';
import 'dbworking.dart';
import 'model.dart';

class SalaryCalculationScreen extends StatefulWidget {
  final Employee employee;
  const SalaryCalculationScreen({Key? key, required this.employee}) : super(key: key);
  @override
  _SalaryCalculationScreenState createState() => _SalaryCalculationScreenState();
}

class _SalaryCalculationScreenState extends State<SalaryCalculationScreen> {
  final DatabaseService _dbService = DatabaseService();
  List<Employee> _employees = [];
  Employee? _selectedEmployee;
  DateTime _selectedMonth = DateTime.now();
  SalaryCalculation? _salaryCalculation;
  bool _isLoading = false;
  bool _hasExistingPayment = false;

  // Manual deduction controllers
  final TextEditingController _advanceDeductionController = TextEditingController();
  final TextEditingController _expenseDeductionController = TextEditingController();

  // Localization maps
  final Map<String, String> _englishTexts = {
    'appBarTitle': 'Salary Calculation',
    'selectEmployee': 'Select Employee',
    'month': 'Month',
    'calculate': 'Calculate',
    'salaryHistory': 'View Salary History',
    'salarySummary': 'Salary Summary',
    'totalWorkingDays': 'Total Working Days',
    'presentDaysFull': 'Present Days (Full)',
    'halfDays': 'Half Days',
    'absentDays': 'Absent Days',
    'effectiveWorkingDays': 'Effective Working Days',
    'baseSalary': 'Base Salary',
    'perDaySalary': 'Per Day Salary',
    'presentDaysSalary': 'Present Days Salary',
    'halfDaysSalary': 'Half Days Salary',
    'grossSalary': 'Gross Salary',
    'contractEarnings': 'Contract Earnings',
    'contractQuantity': 'Total Quantity',
    'unitRate': 'Rate per Unit',
    'workEntries': 'Work Entries',
    'noWorkEntries': 'No work entries for this month',
    'availableForDeduction': 'Available for Deduction:',
    'availableAdvances': 'Available Advances',
    'availableExpenses': 'Available Expenses',
    'availableAdvancesCredit': 'Available Advances (Credit)',
    'availableExpensesCredit': 'Available Expenses (Credit)',
    'manualDeductions': 'Manual Deductions',
    'advanceDeduction': 'Advance Deduction',
    'expenseDeduction': 'Expense Deduction',
    'update': 'Update',
    'max': 'Max',
    'clear': 'Clear',
    'advanceDeductionLabel': 'Advance Deduction',
    'expenseDeductionLabel': 'Expense Deduction',
    'netSalary': 'Net Salary',
    'paySalary': 'Pay Salary',
    'salaryAlreadyPaid': 'Salary Already Paid',
    'mustBePositive': 'Net salary must be positive to process payment',
    'days': 'days',
    'errorCalculating': 'Error calculating salary:',
    'advanceExceed': 'Advance deduction cannot exceed available advances',
    'expenseExceed': 'Expense deduction cannot exceed available expenses',
    'deductionsUpdated': 'Deductions updated successfully!',
    'confirmPayment': 'Confirm Salary Payment',
    'processPayment': 'Process salary payment for',
    'advanceDeductionConfirm': 'Advance Deduction:',
    'expenseDeductionConfirm': 'Expense Deduction:',
    'netSalaryConfirm': 'Net Salary:',
    'cancel': 'Cancel',
    'confirm': 'Confirm',
    'salaryPaid': 'Salary paid successfully!',
    'errorPaying': 'Error paying salary:',
    'salaryPaidWarning': 'Salary already paid for {month}/{year}. Go to Salary History to view or edit.',
    'employeeType': 'Employee Type',
    'contract': 'Contract',
    'monthly': 'Monthly',
    'daily': 'Daily',
    'overtimeHours': 'Overtime Hours',
    'overtimeEarnings': 'Overtime Earnings',
    'totalOvertime': 'Total Overtime',
    'overtimeRate': 'Overtime Rate',
    'workingHours': 'Working Hours',
    'standardHours': 'Standard Hours',
    'overtimeDetails': 'Overtime Details',
  };

  final Map<String, String> _urduTexts = {
    'appBarTitle': 'تنخواہ کا حساب',
    'selectEmployee': 'ملازم منتخب کریں',
    'month': 'مہینہ',
    'calculate': 'حساب کریں',
    'salaryHistory': 'تنخواہ کی تاریخ دیکھیں',
    'salarySummary': 'تنخواہ کا خلاصہ',
    'totalWorkingDays': 'کل کام کے دن',
    'presentDaysFull': 'حاضری کے دن (مکمل)',
    'halfDays': 'آدھے دن',
    'absentDays': 'غیر حاضر دن',
    'effectiveWorkingDays': 'موثر کام کے دن',
    'baseSalary': 'بنیادی تنخواہ',
    'perDaySalary': 'فی دن تنخواہ',
    'presentDaysSalary': 'حاضری کے دنوں کی تنخواہ',
    'halfDaysSalary': 'آدھے دنوں کی تنخواہ',
    'grossSalary': 'کل تنخواہ',
    'contractEarnings': 'کنٹریکٹ آمدنی',
    'contractQuantity': 'کل مقدار',
    'unitRate': 'فی اکائی قیمت',
    'workEntries': 'کام کے اندراجات',
    'noWorkEntries': 'اس مہینے کوئی کام نہیں ملا',
    'availableForDeduction': 'کٹوتی کے لیے دستیاب:',
    'availableAdvances': 'دستیاب پیشگی',
    'availableExpenses': 'دستیاب اخراجات',
    'availableAdvancesCredit': 'دستیاب پیشگی (کریڈٹ)',
    'availableExpensesCredit': 'دستیاب اخراجات (کریڈٹ)',
    'manualDeductions': 'دستی کٹوتیاں',
    'advanceDeduction': 'پیشگی کٹوتی',
    'expenseDeduction': 'خرچہ کٹوتی',
    'update': 'اپ ڈیٹ کریں',
    'max': 'زیادہ سے زیادہ',
    'clear': 'صاف کریں',
    'advanceDeductionLabel': 'پیشگی کٹوتی',
    'expenseDeductionLabel': 'خرچہ کٹوتی',
    'netSalary': 'خالص تنخواہ',
    'paySalary': 'تنخواہ ادا کریں',
    'salaryAlreadyPaid': 'تنخواہ پہلے ہی ادا ہوچکی ہے',
    'mustBePositive': 'ادائیگی کے لیے خالص تنخواہ مثبت ہونی چاہیے',
    'days': 'دن',
    'errorCalculating': 'تنخواہ حساب کرنے میں خرابی:',
    'advanceExceed': 'پیشگی کٹوتی دستیاب پیشگی سے زیادہ نہیں ہو سکتی',
    'expenseExceed': 'خرچہ کٹوتی دستیاب اخراجات سے زیادہ نہیں ہو سکتی',
    'deductionsUpdated': 'کٹوتیاں کامیابی سے اپ ڈیٹ ہوگئیں!',
    'confirmPayment': 'تنخواہ کی ادائیگی کی تصدیق کریں',
    'processPayment': 'کے لیے تنخواہ کی ادائیگی کریں',
    'advanceDeductionConfirm': 'پیشگی کٹوتی:',
    'expenseDeductionConfirm': 'خرچہ کٹوتی:',
    'netSalaryConfirm': 'خالص تنخواہ:',
    'cancel': 'منسوخ کریں',
    'confirm': 'تصدیق کریں',
    'salaryPaid': 'تنخواہ کامیابی سے ادا ہوگئی!',
    'errorPaying': 'تنخواہ ادا کرنے میں خرابی:',
    'salaryPaidWarning': 'تنخواہ پہلے ہی {month}/{year} کے لیے ادا ہوچکی ہے۔ دیکھنے یا ترمیم کے لیے تنخواہ کی تاریخ پر جائیں۔',
    'employeeType': 'ملازم کی قسم',
    'contract': 'کنٹریکٹ',
    'monthly': 'ماہانہ',
    'daily': 'یومیہ',
    'overtimeHours': 'اوور ٹائم گھنٹے',
    'overtimeEarnings': 'اوور ٹائم آمدنی',
    'totalOvertime': 'کل اوور ٹائم',
    'overtimeRate': 'اوور ٹائم ریٹ',
    'workingHours': 'کام کے گھنٹے',
    'standardHours': 'معیاری گھنٹے',
    'overtimeDetails': 'اوور ٹائم کی تفصیلات',
  };

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _selectedEmployee = widget.employee;
    _calculateSalary(); // Auto-calculate when screen opens
  }

  @override
  void dispose() {
    _advanceDeductionController.dispose();
    _expenseDeductionController.dispose();
    super.dispose();
  }

  String _getText(String key) {
    final languageProvider = context.read<LanguageProvider>();
    return languageProvider.isEnglish ? _englishTexts[key] ?? key : _urduTexts[key] ?? key;
  }

  String _getFormattedWarning(String month, String year) {
    final warningText = _getText('salaryPaidWarning');
    return warningText.replaceAll('{month}', month).replaceAll('{year}', year);
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

  Future<void> _loadEmployees() async {
    final employees = await _dbService.getEmployees();
    setState(() {
      _employees = employees;
    });
  }

  Future<void> _calculateSalary() async {
    if (_selectedEmployee == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final calculation = await _dbService.calculateSalary(
        _selectedEmployee!.id!,
        _selectedMonth,
      );

      // Check if salary already paid for this month
      final hasPayment = await _dbService.hasSalaryPayment(
        _selectedEmployee!.id!,
        _selectedMonth,
      );

      setState(() {
        _salaryCalculation = calculation;
        _hasExistingPayment = hasPayment;
        _isLoading = false;

        // Pre-fill deduction fields with available amounts
        _advanceDeductionController.text = calculation.availableAdvances.toStringAsFixed(2);
        _expenseDeductionController.text = calculation.availableExpenses.toStringAsFixed(2);
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_getText('errorCalculating')} $e')),
      );
    }
  }

  void _updateDeductions() {
    if (_salaryCalculation == null) return;

    final advanceDeduction = double.tryParse(_advanceDeductionController.text) ?? 0.0;
    final expenseDeduction = double.tryParse(_expenseDeductionController.text) ?? 0.0;

    // Validate deductions don't exceed available amounts
    if (advanceDeduction > _salaryCalculation!.availableAdvances) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_getText('advanceExceed'))),
      );
      return;
    }

    if (expenseDeduction > _salaryCalculation!.availableExpenses) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_getText('expenseExceed'))),
      );
      return;
    }

    setState(() {
      _salaryCalculation = _salaryCalculation!.copyWith(
        manualAdvanceDeduction: advanceDeduction,
        manualExpenseDeduction: expenseDeduction,
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_getText('deductionsUpdated'))),
    );
  }

  void _setMaxDeductions() {
    if (_salaryCalculation == null) return;

    setState(() {
      _advanceDeductionController.text = _salaryCalculation!.availableAdvances.toStringAsFixed(2);
      _expenseDeductionController.text = _salaryCalculation!.availableExpenses.toStringAsFixed(2);
      _salaryCalculation = _salaryCalculation!.copyWith(
        manualAdvanceDeduction: _salaryCalculation!.availableAdvances,
        manualExpenseDeduction: _salaryCalculation!.availableExpenses,
      );
    });
  }

  void _clearDeductions() {
    setState(() {
      _advanceDeductionController.clear();
      _expenseDeductionController.clear();
      _salaryCalculation = _salaryCalculation!.copyWith(
        manualAdvanceDeduction: 0.0,
        manualExpenseDeduction: 0.0,
      );
    });
  }

  Future<void> _paySalary() async {
    if (_salaryCalculation == null || _hasExistingPayment) return;

    final calc = _salaryCalculation!;
    final isContract = calc.employee.isContractEmployee;

    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_getText('confirmPayment')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_getText('processPayment')} ${calc.employee.name}?'),
            const SizedBox(height: 16),

            // Show different summary based on employee type
            if (isContract) ...[
              _buildDialogRow('${_getText('contractQuantity')}:',
                  '${calc.totalContractQuantity.toStringAsFixed(1)} ${_getUnitText(calc.employee.contractUnit ?? 'bag', true)}'),
              _buildDialogRow('${_getText('contractEarnings')}:',
                  'PKR ${calc.totalContractEarnings.toStringAsFixed(2)}'),
            ] else ...[
              _buildDialogRow('${_getText('presentDaysFull')}:', '${calc.presentDays} ${_getText('days')}'),
              _buildDialogRow('${_getText('halfDays')}:', '${calc.halfDays} ${_getText('days')}'),
              _buildDialogRow('Regular Salary:', 'PKR ${calc.attendanceSalary.toStringAsFixed(2)}'),
              if (calc.totalOvertimeHours > 0) ...[
                _buildDialogRow('Overtime Hours:', '${calc.totalOvertimeHours.toStringAsFixed(1)} hrs'),
                _buildDialogRow('Overtime Pay:', 'PKR ${calc.overtimeEarnings.toStringAsFixed(2)}'),
              ],
              _buildDialogRow('${_getText('grossSalary')}:', 'PKR ${calc.grossEarnings.toStringAsFixed(2)}'),
            ],

            const Divider(),

            if (calc.manualAdvanceDeduction > 0)
              _buildDialogRow(_getText('advanceDeductionConfirm'),
                  '- PKR ${calc.manualAdvanceDeduction.toStringAsFixed(2)}'),
            if (calc.manualExpenseDeduction > 0)
              _buildDialogRow(_getText('expenseDeductionConfirm'),
                  '- PKR ${calc.manualExpenseDeduction.toStringAsFixed(2)}'),

            const Divider(),

            _buildDialogRow(_getText('netSalaryConfirm'),
                'PKR ${calc.netSalaryWithManualDeductions.toStringAsFixed(2)}',
                isBold: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_getText('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: Text(_getText('confirm')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Create salary payment record
        final payment = SalaryPayment(
          employeeId: calc.employee.id!,
          employeeName: calc.employee.name,
          month: _selectedMonth,
          paymentDate: DateTime.now(),
          baseSalary: calc.baseSalary,
          attendanceSalary: isContract ? 0 : calc.attendanceSalary,
          contractEarnings: isContract ? calc.totalContractEarnings : 0,
          totalContractQuantity: isContract ? calc.totalContractQuantity : 0,
          totalAdvances: calc.manualAdvanceDeduction,
          totalExpenses: calc.manualExpenseDeduction,
          netSalary: calc.netSalaryWithManualDeductions,
          deductedAdvances: [],
          deductedExpenses: [],
          contractWorkEntries: isContract ? calc.contractWorkEntries : null,
          salaryType: calc.employee.salaryType,
        );

        await _dbService.paySalary(payment);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_getText('salaryPaid'))),
        );

        // Recalculate to refresh data
        _calculateSalary();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_getText('errorPaying')} $e')),
        );
      }
    }
  }

  Widget _buildDialogRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isBold ? Colors.green : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectMonth(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null && picked != _selectedMonth) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month, 1);
        _salaryCalculation = null;
        _hasExistingPayment = false;
        _advanceDeductionController.clear();
        _expenseDeductionController.clear();
      });

      // Auto-calculate when month changes
      if (_selectedEmployee != null) {
        _calculateSalary();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = context.watch<LanguageProvider>();
    final isEnglish = languageProvider.isEnglish;
    final fontFamily = languageProvider.fontFamily;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _getText('appBarTitle'),
          style: TextStyle(fontFamily: fontFamily),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SalaryListScreen()),
              );
            },
            tooltip: _getText('salaryHistory'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Employee info card (since we already have the employee)
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedEmployee?.name ?? '',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: fontFamily,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _selectedEmployee?.isContractEmployee == true
                                      ? Colors.orange.shade100
                                      : Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _selectedEmployee?.isContractEmployee == true
                                      ? _getText('contract')
                                      : _selectedEmployee?.salaryType == 'monthly'
                                      ? _getText('monthly')
                                      : _getText('daily'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _selectedEmployee?.isContractEmployee == true
                                        ? Colors.orange.shade800
                                        : Colors.green.shade800,
                                    fontFamily: fontFamily,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (_selectedEmployee?.isContractEmployee == true)
                                Text(
                                  'PKR ${_selectedEmployee?.basicSalary.toStringAsFixed(0)} / ${_getUnitText(_selectedEmployee?.contractUnit ?? 'bag', isEnglish)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontFamily: fontFamily,
                                  ),
                                )
                              else
                                Text(
                                  'PKR ${_selectedEmployee?.basicSalary.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontFamily: fontFamily,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Month Selection
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: _getText('month'),
                      border: const OutlineInputBorder(),
                      suffixIcon: const Icon(Icons.calendar_today),
                      labelStyle: TextStyle(fontFamily: fontFamily),
                    ),
                    controller: TextEditingController(
                      text: '${_selectedMonth.month}/${_selectedMonth.year}',
                    ),
                    style: TextStyle(fontFamily: fontFamily),
                    onTap: () => _selectMonth(context),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _selectedEmployee != null ? _calculateSalary : null,
                  child: Text(
                    _getText('calculate'),
                    style: TextStyle(fontFamily: fontFamily),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_salaryCalculation != null)
              Expanded(
                child: _buildSalaryDetails(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalaryDetails() {
    final calc = _salaryCalculation!;
    final isContract = calc.employee.isContractEmployee;
    final canPaySalary = calc.netSalaryWithManualDeductions > 0 && !_hasExistingPayment;
    final languageProvider = context.read<LanguageProvider>();
    final fontFamily = languageProvider.fontFamily;
    final isEnglish = languageProvider.isEnglish;

    return SingleChildScrollView(
      child: Column(
        children: [
          // Existing Payment Warning
          if (_hasExistingPayment)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                border: Border.all(color: Colors.orange),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getFormattedWarning(
                        _selectedMonth.month.toString(),
                        _selectedMonth.year.toString(),
                      ),
                      style: TextStyle(
                        color: Colors.orange[800],
                        fontFamily: fontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Salary Summary Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    '${_getText('salarySummary')} - ${calc.month.month}/${calc.month.year}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: fontFamily,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Different summary based on employee type
                  if (isContract) ...[
                    // Contract employee summary
                    _buildSummaryRow(
                      _getText('contractQuantity'),
                      '${calc.totalContractQuantity.toStringAsFixed(1)} ${_getUnitText(calc.employee.contractUnit ?? 'bag', isEnglish)}',
                      fontFamily: fontFamily,
                    ),
                    const Divider(),

                    // Show individual work entries if available
                    if (calc.contractWorkEntries != null && calc.contractWorkEntries!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _getText('workEntries'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                          fontFamily: fontFamily,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // List of work entries
                      ...calc.contractWorkEntries!.map((entry) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${entry.date.day}/${entry.date.month}',
                                style: TextStyle(fontFamily: fontFamily, fontSize: 12),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '${entry.quantity.toStringAsFixed(1)} ${_getUnitText(entry.unit, isEnglish)}',
                                style: TextStyle(fontFamily: fontFamily, fontSize: 12),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'PKR ${entry.totalAmount.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontFamily: fontFamily,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      )).toList(),

                      const Divider(),
                    ] else ...[
                      _buildSummaryRow(
                        _getText('noWorkEntries'),
                        '',
                        fontFamily: fontFamily,
                        color: Colors.grey,
                      ),
                    ],

                    _buildSummaryRow(
                      _getText('contractEarnings'),
                      'PKR ${calc.totalContractEarnings.toStringAsFixed(2)}',
                      isBold: true,
                      fontFamily: fontFamily,
                    ),
                  ]// In the regular employee section of _buildSalaryDetails, replace the existing section with:

                  else ...[
                    // Regular employee summary
                    _buildSummaryRow(
                      _getText('totalWorkingDays'),
                      '${calc.totalWorkingDays} ${_getText('days')}',
                      fontFamily: fontFamily,
                    ),
                    _buildSummaryRow(
                      _getText('presentDaysFull'),
                      '${calc.presentDays} ${_getText('days')}',
                      fontFamily: fontFamily,
                    ),
                    _buildSummaryRow(
                      _getText('halfDays'),
                      '${calc.halfDays} ${_getText('days')}',
                      fontFamily: fontFamily,
                    ),
                    _buildSummaryRow(
                      _getText('absentDays'),
                      '${calc.absentDays} ${_getText('days')}',
                      fontFamily: fontFamily,
                    ),
                    _buildSummaryRow(
                      _getText('effectiveWorkingDays'),
                      '${calc.effectiveWorkingDays.toStringAsFixed(1)} ${_getText('days')}',
                      fontFamily: fontFamily,
                    ),

                    const SizedBox(height: 8),
                    _buildSummaryRow(
                      _getText('baseSalary'),
                      'PKR ${calc.baseSalary.toStringAsFixed(2)}',
                      fontFamily: fontFamily,
                    ),
                    _buildSummaryRow(
                      _getText('perDaySalary'),
                      'PKR ${calc.perDaySalary.toStringAsFixed(2)}',
                      fontFamily: fontFamily,
                    ),
                    if (calc.employee.standardWorkingHours != null)
                      _buildSummaryRow(
                        _getText('standardHours'),
                        '${calc.employee.standardWorkingHours} hrs/day',
                        fontFamily: fontFamily,
                      ),
                    if (calc.employee.overtimeRate != null)
                      _buildSummaryRow(
                        _getText('overtimeRate'),
                        'PKR ${calc.employee.overtimeRate!.toStringAsFixed(2)}/hr',
                        fontFamily: fontFamily,
                      ),
                    const Divider(),

                    _buildSummaryRow(
                      _getText('presentDaysSalary'),
                      'PKR ${calc.presentDaysSalary.toStringAsFixed(2)}',
                      fontFamily: fontFamily,
                    ),
                    _buildSummaryRow(
                      _getText('halfDaysSalary'),
                      'PKR ${calc.halfDaysSalary.toStringAsFixed(2)}',
                      fontFamily: fontFamily,
                    ),

                    // Add overtime section if there is overtime
                    if (calc.totalOvertimeHours > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _getText('overtimeDetails'),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade800,
                                fontFamily: fontFamily,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildSummaryRow(
                              _getText('overtimeHours'),
                              '${calc.totalOvertimeHours.toStringAsFixed(1)} hrs',
                              fontFamily: fontFamily,
                            ),
                            _buildSummaryRow(
                              _getText('overtimeEarnings'),
                              'PKR ${calc.overtimeEarnings.toStringAsFixed(2)}',
                              fontFamily: fontFamily,
                              color: Colors.orange.shade700,
                            ),
                          ],
                        ),
                      ),
                    ],

                    _buildSummaryRow(
                      _getText('grossSalary'),
                      'PKR ${calc.grossEarnings.toStringAsFixed(2)}',
                      isBold: true,
                      fontFamily: fontFamily,
                      color: Colors.green.shade700,
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Available for deduction section
                  if (calc.availableAdvances > 0 || calc.availableExpenses > 0) ...[
                    Text(
                      _getText('availableForDeduction'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                        fontFamily: fontFamily,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (calc.availableAdvances > 0)
                      _buildSummaryRow(
                        _getText('availableAdvances'),
                        'PKR ${calc.availableAdvances.toStringAsFixed(2)}',
                        fontFamily: fontFamily,
                      ),
                    if (calc.availableExpenses > 0)
                      _buildSummaryRow(
                        _getText('availableExpenses'),
                        'PKR ${calc.availableExpenses.toStringAsFixed(2)}',
                        fontFamily: fontFamily,
                      ),
                  ],
                ],
              ),
            ),
          ),

          // Only show deduction controls if no existing payment
          if (!_hasExistingPayment && (calc.availableAdvances > 0 || calc.availableExpenses > 0)) ...[
            const SizedBox(height: 16),
            _buildDeductionControls(calc),
            const SizedBox(height: 16),
          ],

          // Pay Salary Button (disabled if existing payment)
          ElevatedButton(
            onPressed: canPaySalary ? _paySalary : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: canPaySalary ? Colors.green : Colors.grey,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
            ),
            child: Text(
              _hasExistingPayment
                  ? _getText('salaryAlreadyPaid')
                  : '${_getText('paySalary')} - PKR ${calc.netSalaryWithManualDeductions.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: fontFamily,
              ),
            ),
          ),

          if (!canPaySalary && !_hasExistingPayment)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _getText('mustBePositive'),
                style: TextStyle(
                  color: Colors.red,
                  fontFamily: fontFamily,
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Available Advances & Expenses Breakdown
          if (calc.advances.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getText('availableAdvancesCredit'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: fontFamily,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...calc.advances.where((a) => a.type == 'credit').map((advance) =>
                        _buildTransactionRow(
                          advance.dateTime,
                          advance.description,
                          advance.amount,
                          Colors.blue,
                          fontFamily: fontFamily,
                        ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          if (calc.expenses.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getText('availableExpensesCredit'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: fontFamily,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...calc.expenses.where((e) => e.type == 'credit').map((expense) =>
                        _buildTransactionRow(
                          expense.dateTime,
                          expense.description,
                          expense.amount,
                          Colors.blue,
                          fontFamily: fontFamily,
                        ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDeductionControls(SalaryCalculation calc) {
    final languageProvider = context.read<LanguageProvider>();
    final fontFamily = languageProvider.fontFamily;
    final isEnglish = languageProvider.isEnglish;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              _getText('manualDeductions'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
                fontFamily: fontFamily,
              ),
            ),
            const SizedBox(height: 16),

            // Advance Deduction
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _advanceDeductionController,
                    keyboardType: TextInputType.number,
                    textDirection: isEnglish ? TextDirection.ltr : TextDirection.rtl,
                    textAlign: isEnglish ? TextAlign.left : TextAlign.right,
                    decoration: InputDecoration(
                      labelText: _getText('advanceDeductionLabel'),
                      prefixText: 'PKR ',
                      hintText: '0.00',
                      border: const OutlineInputBorder(),
                      labelStyle: TextStyle(fontFamily: fontFamily),
                    ),
                    style: TextStyle(fontFamily: fontFamily),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '/ ${calc.availableAdvances.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Colors.grey,
                    fontFamily: fontFamily,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Expense Deduction
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _expenseDeductionController,
                    keyboardType: TextInputType.number,
                    textDirection: isEnglish ? TextDirection.ltr : TextDirection.rtl,
                    textAlign: isEnglish ? TextAlign.left : TextAlign.right,
                    decoration: InputDecoration(
                      labelText: _getText('expenseDeductionLabel'),
                      prefixText: 'PKR ',
                      hintText: '0.00',
                      border: const OutlineInputBorder(),
                      labelStyle: TextStyle(fontFamily: fontFamily),
                    ),
                    style: TextStyle(fontFamily: fontFamily),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '/ ${calc.availableExpenses.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Colors.grey,
                    fontFamily: fontFamily,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Deduction Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _updateDeductions,
                    child: Text(
                      _getText('update'),
                      style: TextStyle(fontFamily: fontFamily),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _setMaxDeductions,
                    child: Text(
                      _getText('max'),
                      style: TextStyle(fontFamily: fontFamily),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clearDeductions,
                    child: Text(
                      _getText('clear'),
                      style: TextStyle(fontFamily: fontFamily),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(),

            // Final Calculation
            _buildSummaryRow(
              _getText('advanceDeduction'),
              '- PKR ${calc.manualAdvanceDeduction.toStringAsFixed(2)}',
              color: Colors.red,
              fontFamily: fontFamily,
            ),
            _buildSummaryRow(
              _getText('expenseDeduction'),
              '- PKR ${calc.manualExpenseDeduction.toStringAsFixed(2)}',
              color: Colors.red,
              fontFamily: fontFamily,
            ),
            const Divider(),
            _buildSummaryRow(
              _getText('netSalary'),
              'PKR ${calc.netSalaryWithManualDeductions.toStringAsFixed(2)}',
              isBold: true,
              color: calc.netSalaryWithManualDeductions > 0 ? Colors.green : Colors.red,
              fontFamily: fontFamily,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {
    bool isBold = false,
    Color? color,
    required String fontFamily,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontFamily: fontFamily,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
              fontFamily: fontFamily,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(DateTime date, String description, double amount, Color color, {
    required String fontFamily,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '${date.day}/${date.month}/${date.year}',
              style: TextStyle(
                fontSize: 12,
                fontFamily: fontFamily,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              description,
              style: TextStyle(
                fontSize: 12,
                fontFamily: fontFamily,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'PKR ${amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.bold,
                fontFamily: fontFamily,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}