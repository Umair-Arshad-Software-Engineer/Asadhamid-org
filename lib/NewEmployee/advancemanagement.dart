import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Provider/lanprovider.dart';
import 'dbworking.dart';
import 'model.dart';

class AdvanceManagementScreen extends StatefulWidget {
  final Employee employee;

  const AdvanceManagementScreen({Key? key, required this.employee}) : super(key: key);

  @override
  _AdvanceManagementScreenState createState() => _AdvanceManagementScreenState();
}

class _AdvanceManagementScreenState extends State<AdvanceManagementScreen> {
  final DatabaseService _dbService = DatabaseService();
  List<AdvanceTransaction> _transactions = [];
  late Employee _currentEmployee;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // Localization maps
  final Map<String, String> _englishTexts = {
    'appBarTitle': 'Advance Management',
    'totalAdvanceBalance': 'Total Advance Balance',
    'addAdvance': 'Add Advance',
    'deductAdvance': 'Deduct Advance',
    'dateTime': 'Date & Time',
    'description': 'Description',
    'amount': 'Amount',
    'balance': 'Balance',
    'action': 'Action',
    'addAdvanceDialogTitle': 'Add Advance',
    'deductAdvanceDialogTitle': 'Deduct Advance',
    'descriptionHintAdd': 'Advance given for...',
    'descriptionHintDeduct': 'Advance deducted for...',
    'cancel': 'Cancel',
    'add': 'Add',
    'deduct': 'Deduct',
    'validAmount': 'Please enter a valid amount',
    'validDescription': 'Please enter a description',
    'deductionExceed': 'Deduction amount cannot exceed total advance',
    'transactionAdded': 'Transaction added successfully!',
    'errorAdding': 'Error adding transaction:',
    'deleteTransaction': 'Delete Transaction',
    'confirmDelete': 'Are you sure you want to delete this transaction?',
    'deleteButton': 'Delete',
    'transactionDeleted': 'Transaction deleted successfully!',
    'errorDeleting': 'Error deleting transaction:',
    'noTransactions': 'No transactions found',
    'positiveBalance': 'Positive balance indicates advance due from employee',
    'negativeBalance': 'Negative balance indicates advance given to employee',
    'credit': 'Credit',
    'debit': 'Debit',
  };

  final Map<String, String> _urduTexts = {
    'appBarTitle': 'پیشگی انتظام',
    'totalAdvanceBalance': 'کل پیشگی بیلنس',
    'addAdvance': 'پیشگی شامل کریں',
    'deductAdvance': 'پیشگی کٹوتی کریں',
    'dateTime': 'تاریخ و وقت',
    'description': 'تفصیل',
    'amount': 'رقم',
    'balance': 'بیلنس',
    'action': 'عمل',
    'addAdvanceDialogTitle': 'پیشگی شامل کریں',
    'deductAdvanceDialogTitle': 'پیشگی کٹوتی کریں',
    'descriptionHintAdd': 'پیشگی دی گئی کے لیے...',
    'descriptionHintDeduct': 'پیشگی کٹوتی کے لیے...',
    'cancel': 'منسوخ کریں',
    'add': 'شامل کریں',
    'deduct': 'کٹوتی کریں',
    'validAmount': 'براہ کرم درست رقم درج کریں',
    'validDescription': 'براہ کرم تفصیل درج کریں',
    'deductionExceed': 'کٹوتی کی رقم کل پیشگی سے زیادہ نہیں ہو سکتی',
    'transactionAdded': 'ٹرانزیکشن کامیابی سے شامل ہوگیا!',
    'errorAdding': 'ٹرانزیکشن شامل کرنے میں خرابی:',
    'deleteTransaction': 'ٹرانزیکشن حذف کریں',
    'confirmDelete': 'کیا آپ واقعی یہ ٹرانزیکشن حذف کرنا چاہتے ہیں؟',
    'deleteButton': 'حذف کریں',
    'transactionDeleted': 'ٹرانزیکشن کامیابی سے حذف ہوگیا!',
    'errorDeleting': 'ٹرانزیکشن حذف کرنے میں خرابی:',
    'noTransactions': 'کوئی ٹرانزیکشن نہیں ملا',
    'positiveBalance': 'مثبت بیلنس سے مراد ہے کہ ملازم سے پیشگی واجب الادا ہے',
    'negativeBalance': 'منفی بیلنس سے مراد ہے کہ ملازم کو پیشگی دی گئی ہے',
    'credit': 'کریڈٹ',
    'debit': 'ڈیبٹ',
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

  String _getTransactionTypeText(String type) {
    final languageProvider = context.read<LanguageProvider>();
    if (type == 'credit') {
      return languageProvider.isEnglish ? 'Credit' : _getText('credit');
    } else {
      return languageProvider.isEnglish ? 'Debit' : _getText('debit');
    }
  }

  Future<void> _loadTransactions() async {
    final transactions = await _dbService.getAdvanceTransactions(_currentEmployee.id!);
    final updatedEmployee = await _dbService.getEmployee(_currentEmployee.id!);

    setState(() {
      _transactions = transactions;
      if (updatedEmployee != null) {
        _currentEmployee = updatedEmployee;
      }
    });
  }

  void _showAddAdvanceDialog(bool isCredit) {
    final languageProvider = context.read<LanguageProvider>();
    final fontFamily = languageProvider.fontFamily;
    final isEnglish = languageProvider.isEnglish;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isCredit ? _getText('addAdvanceDialogTitle') : _getText('deductAdvanceDialogTitle'),
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

    if (!isCredit && amount > _currentEmployee.totalAdvance) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_getText('deductionExceed'))),
      );
      return;
    }

    try {
      final transaction = AdvanceTransaction(
        employeeId: _currentEmployee.id!,
        dateTime: DateTime.now(),
        description: description,
        amount: amount,
        type: isCredit ? 'credit' : 'debit',
        balance: 0.0,
      );

      await _dbService.addAdvanceTransaction(transaction);

      _amountController.clear();
      _descriptionController.clear();
      Navigator.pop(context);
      await _loadTransactions();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_getText('transactionAdded'))),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_getText('errorAdding')} $e')),
      );
    }
  }

  Future<void> _deleteTransaction(AdvanceTransaction transaction) async {
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
        await _dbService.deleteAdvanceTransaction(
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

  // Corrected balance calculation method
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
                    _getText('totalAdvanceBalance'),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontFamily: fontFamily,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'PKR ${_currentEmployee.totalAdvance.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _currentEmployee.totalAdvance > 0 ? Colors.red : Colors.green,
                      fontFamily: fontFamily,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _currentEmployee.totalAdvance > 0
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
                    onPressed: () => _showAddAdvanceDialog(true),
                    icon: Icon(Icons.add),
                    label: Text(
                      _getText('addAdvance'),
                      style: TextStyle(fontFamily: fontFamily),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _currentEmployee.totalAdvance > 0
                        ? () => _showAddAdvanceDialog(false)
                        : null,
                    icon: Icon(Icons.remove),
                    label: Text(
                      _getText('deductAdvance'),
                      style: TextStyle(fontFamily: fontFamily),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 16),

          // Improved Transactions Table Header
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
                    _getText('amount'),
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
                    _getText('action'),
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
                final typeText = _getTransactionTypeText(transaction.type);

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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              transaction.description,
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: fontFamily,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '($typeText)',
                              style: TextStyle(
                                fontSize: 10,
                                color: transaction.type == 'credit' ? Colors.red : Colors.green,
                                fontFamily: fontFamily,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Amount
                      Expanded(
                        flex: 1,
                        child: Text(
                          'PKR ${transaction.amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: transaction.type == 'credit' ? Colors.red : Colors.green,
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
                            color: balance > 0 ? Colors.red : balance < 0 ? Colors.green : Colors.black,
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
                          tooltip: _getText('deleteButton'),
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