import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Provider/lanprovider.dart';
import 'dbworking.dart';
import 'model.dart';

class ExpenseManagementScreen extends StatefulWidget {
  final Employee employee;

  const ExpenseManagementScreen({Key? key, required this.employee}) : super(key: key);

  @override
  _ExpenseManagementScreenState createState() => _ExpenseManagementScreenState();
}

class _ExpenseManagementScreenState extends State<ExpenseManagementScreen> {
  final DatabaseService _dbService = DatabaseService();
  List<ExpenseTransaction> _transactions = [];
  late Employee _currentEmployee;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // Localization maps
  final Map<String, String> _englishTexts = {
    'appBarTitle': 'Expense Management',
    'totalExpenseBalance': 'Total Expense Balance',
    'addExpense': 'Add Expense',
    'deductExpense': 'Deduct Expense',
    'dateTime': 'Date & Time',
    'description': 'Description',
    'credit': 'Credit',
    'debit': 'Debit',
    'balance': 'Balance',
    'delete': 'Delete',
    'addExpenseDialogTitle': 'Add Expense',
    'deductExpenseDialogTitle': 'Deduct Expense',
    'amount': 'Amount',
    'descriptionHintAdd': 'Expense for...',
    'descriptionHintDeduct': 'Expense deduction for...',
    'cancel': 'Cancel',
    'add': 'Add',
    'deduct': 'Deduct',
    'validAmount': 'Please enter a valid amount',
    'validDescription': 'Please enter a description',
    'deductionExceed': 'Deduction amount cannot exceed total expense',
    'expenseAdded': 'Expense added successfully!',
    'expenseDeducted': 'Expense deducted successfully!',
    'errorAdding': 'Error adding expense:',
    'errorDeducting': 'Error deducting expense:',
    'deleteTransaction': 'Delete Expense Transaction',
    'confirmDelete': 'Are you sure you want to delete this expense transaction?',
    'deleteButton': 'Delete',
    'transactionDeleted': 'Expense transaction deleted successfully!',
    'errorDeleting': 'Error deleting expense transaction:',
    'noTransactions': 'No expense transactions found',
    'positiveBalance': 'Positive balance indicates expense due from employee',
    'negativeBalance': 'Negative balance indicates expense advance to employee',
  };

  final Map<String, String> _urduTexts = {
    'appBarTitle': 'خرچہ انتظام',
    'totalExpenseBalance': 'کل خرچہ بیلنس',
    'addExpense': 'خرچہ شامل کریں',
    'deductExpense': 'خرچہ کٹوتی کریں',
    'dateTime': 'تاریخ و وقت',
    'description': 'تفصیل',
    'credit': 'کریڈٹ',
    'debit': 'ڈیبٹ',
    'balance': 'بیلنس',
    'delete': 'حذف کریں',
    'addExpenseDialogTitle': 'خرچہ شامل کریں',
    'deductExpenseDialogTitle': 'خرچہ کٹوتی کریں',
    'amount': 'رقم',
    'descriptionHintAdd': 'خرچہ کے لیے...',
    'descriptionHintDeduct': 'خرچہ کٹوتی کے لیے...',
    'cancel': 'منسوخ کریں',
    'add': 'شامل کریں',
    'deduct': 'کٹوتی کریں',
    'validAmount': 'براہ کرم درست رقم درج کریں',
    'validDescription': 'براہ کرم تفصیل درج کریں',
    'deductionExceed': 'کٹوتی کی رقم کل خرچہ سے زیادہ نہیں ہو سکتی',
    'expenseAdded': 'خرچہ کامیابی سے شامل ہوگیا!',
    'expenseDeducted': 'خرچہ کامیابی سے کٹوتی ہوگیا!',
    'errorAdding': 'خرچہ شامل کرنے میں خرابی:',
    'errorDeducting': 'خرچہ کٹوتی میں خرابی:',
    'deleteTransaction': 'خرچہ ٹرانزیکشن حذف کریں',
    'confirmDelete': 'کیا آپ واقعی یہ خرچہ ٹرانزیکشن حذف کرنا چاہتے ہیں؟',
    'deleteButton': 'حذف کریں',
    'transactionDeleted': 'خرچہ ٹرانزیکشن کامیابی سے حذف ہوگیا!',
    'errorDeleting': 'خرچہ ٹرانزیکشن حذف کرنے میں خرابی:',
    'noTransactions': 'کوئی خرچہ ٹرانزیکشن نہیں ملا',
    'positiveBalance': 'مثبت بیلنس سے مراد ہے کہ ملازم سے خرچہ واجب الادا ہے',
    'negativeBalance': 'منفی بیلنس سے مراد ہے کہ ملازم کو خرچہ پیشگی دیا گیا ہے',
  };

  @override
  void initState() {
    super.initState();
    _currentEmployee = widget.employee;
    _loadTransactions();
  }

  String _getText(String key) {
    final languageProvider = context.read<LanguageProvider>();
    return languageProvider.isEnglish ? _englishTexts[key] ?? key : _urduTexts[key] ?? key;
  }

  Future<void> _loadTransactions() async {
    final transactions = await _dbService.getExpenseTransactions(_currentEmployee.id!);
    final updatedEmployee = await _dbService.getEmployee(_currentEmployee.id!);

    setState(() {
      _transactions = transactions;
      if (updatedEmployee != null) {
        _currentEmployee = updatedEmployee;
      }
    });
  }

  void _showAddExpenseDialog(bool isCredit) {
    final languageProvider = context.read<LanguageProvider>();
    final fontFamily = languageProvider.fontFamily;
    final isEnglish = languageProvider.isEnglish;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isCredit ? _getText('addExpenseDialogTitle') : _getText('deductExpenseDialogTitle'),
          style: TextStyle(fontFamily: fontFamily),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              textDirection: isEnglish ? TextDirection.ltr : TextDirection.rtl,
              textAlign: isEnglish ? TextAlign.left : TextAlign.right,
              decoration: InputDecoration(
                labelText: _getText('amount'),
                prefixText: 'PKR ',
                labelStyle: TextStyle(fontFamily: fontFamily),
              ),
              style: TextStyle(fontFamily: fontFamily),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              textDirection: isEnglish ? TextDirection.ltr : TextDirection.rtl,
              textAlign: isEnglish ? TextAlign.left : TextAlign.right,
              decoration: InputDecoration(
                labelText: _getText('description'),
                hintText: isCredit ? _getText('descriptionHintAdd') : _getText('descriptionHintDeduct'),
                labelStyle: TextStyle(fontFamily: fontFamily),
                hintStyle: TextStyle(fontFamily: fontFamily),
              ),
              style: TextStyle(fontFamily: fontFamily),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _getText('cancel'),
              style: TextStyle(fontFamily: fontFamily),
            ),
          ),
          TextButton(
            onPressed: () => _addTransaction(isCredit),
            child: Text(
              isCredit ? _getText('add') : _getText('deduct'),
              style: TextStyle(fontFamily: fontFamily),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addTransaction(bool isCredit) async {
    final amount = double.tryParse(_amountController.text);
    final description = _descriptionController.text.trim();

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_getText('validAmount'))),
      );
      return;
    }

    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_getText('validDescription'))),
      );
      return;
    }

    // For debit transactions, check if deduction amount doesn't exceed total expense
    if (!isCredit && amount > _currentEmployee.totalExpense) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_getText('deductionExceed'))),
      );
      return;
    }

    try {
      final transaction = ExpenseTransaction(
        employeeId: _currentEmployee.id!,
        dateTime: DateTime.now(),
        description: description,
        amount: amount,
        type: isCredit ? 'credit' : 'debit',
        balance: 0.0,
      );

      await _dbService.addExpenseTransaction(transaction);

      _amountController.clear();
      _descriptionController.clear();
      Navigator.pop(context);
      await _loadTransactions();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isCredit ? _getText('expenseAdded') : _getText('expenseDeducted'))),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${isCredit ? _getText('errorAdding') : _getText('errorDeducting')} $e')),
      );
    }
  }

  Future<void> _deleteTransaction(ExpenseTransaction transaction) async {
    final languageProvider = context.read<LanguageProvider>();
    final fontFamily = languageProvider.fontFamily;

    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _getText('deleteTransaction'),
          style: TextStyle(fontFamily: fontFamily),
        ),
        content: Text(
          _getText('confirmDelete'),
          style: TextStyle(fontFamily: fontFamily),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              _getText('cancel'),
              style: TextStyle(fontFamily: fontFamily),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              _getText('deleteButton'),
              style: TextStyle(fontFamily: fontFamily),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _dbService.deleteExpenseTransaction(
          transaction.employeeId,
          transaction.id!,
        );
        await _loadTransactions();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_getText('transactionDeleted'))),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_getText('errorDeleting')} $e')),
        );
      }
    }
  }

  // Calculate running balances for expenses
  List<double> _calculateRunningBalances() {
    List<double> balances = [];
    double runningBalance = 0.0;

    for (var transaction in _transactions) {
      if (transaction.type == 'credit') {
        runningBalance += transaction.amount;
      } else {
        runningBalance -= transaction.amount;
      }
      balances.add(runningBalance);
    }

    return balances;
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = context.watch<LanguageProvider>();
    final fontFamily = languageProvider.fontFamily;
    final isEnglish = languageProvider.isEnglish;
    final balances = _calculateRunningBalances();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_getText('appBarTitle')} - ${_currentEmployee.name}',
          style: TextStyle(fontFamily: fontFamily),
        ),
      ),
      body: Column(
        children: [
          // Summary Card
          Card(
            margin: EdgeInsets.all(16),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    _getText('totalExpenseBalance'),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontFamily: fontFamily,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'PKR ${_currentEmployee.totalExpense.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _currentEmployee.totalExpense > 0 ? Colors.purple : Colors.green,
                      fontFamily: fontFamily,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _currentEmployee.totalExpense > 0
                        ? _getText('positiveBalance')
                        : _getText('negativeBalance'),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                      fontFamily: fontFamily,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

          // Action Buttons
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showAddExpenseDialog(true),
                    icon: Icon(Icons.add),
                    label: Text(
                      _getText('addExpense'),
                      style: TextStyle(fontFamily: fontFamily),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _currentEmployee.totalExpense > 0
                        ? () => _showAddExpenseDialog(false)
                        : null,
                    icon: Icon(Icons.remove),
                    label: Text(
                      _getText('deductExpense'),
                      style: TextStyle(fontFamily: fontFamily),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 16),

          // Transactions Table Header with new columns
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    _getText('dateTime'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: fontFamily,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    _getText('description'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: fontFamily,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    _getText('credit'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: fontFamily,
                    ),
                    textAlign: isEnglish ? TextAlign.right : TextAlign.left,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    _getText('debit'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: fontFamily,
                    ),
                    textAlign: isEnglish ? TextAlign.right : TextAlign.left,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    _getText('balance'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: fontFamily,
                    ),
                    textAlign: isEnglish ? TextAlign.right : TextAlign.left,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    _getText('delete'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: fontFamily,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _transactions.isEmpty
                ? Center(
              child: Text(
                _getText('noTransactions'),
                style: TextStyle(
                  color: Colors.grey,
                  fontFamily: fontFamily,
                ),
              ),
            )
                : ListView.builder(
              itemCount: _transactions.length,
              itemBuilder: (context, index) {
                final transaction = _transactions[index];
                final balance = balances[index];

                return Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
                  ),
                  child: Row(
                    children: [
                      // Date & Time
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${transaction.dateTime.day}/${transaction.dateTime.month}/${transaction.dateTime.year}',
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: fontFamily,
                              ),
                            ),
                            Text(
                              '${transaction.dateTime.hour}:${transaction.dateTime.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontFamily: fontFamily,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Description
                      Expanded(
                        flex: 2,
                        child: Text(
                          transaction.description,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: fontFamily,
                          ),
                        ),
                      ),

                      // Credit Column
                      Expanded(
                        flex: 1,
                        child: Text(
                          transaction.type == 'credit'
                              ? 'PKR ${transaction.amount.toStringAsFixed(2)}'
                              : '-',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.purple,
                            fontWeight: FontWeight.bold,
                            fontFamily: fontFamily,
                          ),
                          textAlign: isEnglish ? TextAlign.right : TextAlign.left,
                        ),
                      ),

                      // Debit Column
                      Expanded(
                        flex: 1,
                        child: Text(
                          transaction.type == 'debit'
                              ? 'PKR ${transaction.amount.toStringAsFixed(2)}'
                              : '-',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.deepOrange,
                            fontWeight: FontWeight.bold,
                            fontFamily: fontFamily,
                          ),
                          textAlign: isEnglish ? TextAlign.right : TextAlign.left,
                        ),
                      ),

                      // Balance
                      Expanded(
                        flex: 1,
                        child: Text(
                          'PKR ${balance.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: balance > 0 ? Colors.purple : balance < 0 ? Colors.green : Colors.black,
                            fontFamily: fontFamily,
                          ),
                          textAlign: isEnglish ? TextAlign.right : TextAlign.left,
                        ),
                      ),

                      // Delete Action
                      Expanded(
                        flex: 1,
                        child: IconButton(
                          icon: Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () => _deleteTransaction(transaction),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}