import 'package:flutter/material.dart';
import 'package:mughal_group_branch_two/NewEmployee/salary_calculation_screen.dart';
import 'package:provider/provider.dart';
import '../Provider/lanprovider.dart';
import 'ContractWorkScreen.dart';
import 'advancemanagement.dart';
import 'attendance_screen.dart';
import 'attendance_view_screen.dart';
import 'dbworking.dart';
import 'expensemanagement.dart';
import 'model.dart';

class EmployeeListScreen extends StatefulWidget {
  @override
  _EmployeeListScreenState createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends State<EmployeeListScreen> {
  final DatabaseService _dbService = DatabaseService();
  List<Employee> _employees = [];

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    final employees = await _dbService.getEmployees();
    setState(() {
      _employees = employees;
    });
  }

  String _getSalaryTypeText(String type, bool isEnglish) {
    switch (type) {
      case 'monthly':
        return isEnglish ? 'Monthly' : 'ماہانہ';
      case 'daily':
        return isEnglish ? 'Daily' : 'یومیہ';
      case 'contract':
        return isEnglish ? 'Contract' : 'کنٹریکٹ';
      default:
        return type;
    }
  }

  String _getUnitText(String unit, bool isEnglish) {
    switch (unit) {
      case 'bag':
        return isEnglish ? 'per bag' : 'فی بوری';
      case 'kg':
        return isEnglish ? 'per kg' : 'فی کلوگرام';
      case 'ton':
        return isEnglish ? 'per ton' : 'فی ٹن';
      case 'meter':
        return isEnglish ? 'per meter' : 'فی میٹر';
      case 'piece':
        return isEnglish ? 'per piece' : 'فی پیس';
      default:
        return unit;
    }
  }

  void _showEmployeeOptions(Employee employee) {
    final lang = Provider.of<LanguageProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),

              // Employee name at top
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  employee.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const Divider(height: 1),

              // Calculate Salary - NOW AVAILABLE FOR ALL EMPLOYEE TYPES
              ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.purple.shade100,
                  child: Icon(Icons.calculate, color: Colors.purple),
                ),
                title: Text(
                  lang.isEnglish ? 'Calculate Salary' : 'تنخواہ کیلکولیٹ کریں',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SalaryCalculationScreen(employee: employee),
                    ),
                  );
                },
              ),

              // Mark Attendance (only for non-contract employees)
              if (employee.salaryType != 'contract')
                ListTile(
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.green.shade100,
                    child: Icon(Icons.calendar_today, color: Colors.green),
                  ),
                  title: Text(
                    lang.isEnglish ? 'Mark Attendance' : 'حاضری لگائیں',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AttendanceScreen(employee: employee),
                      ),
                    );
                  },
                ),

              // View Attendance (only for non-contract employees)
              if (employee.salaryType != 'contract')
                ListTile(
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.blue.shade100,
                    child: Icon(Icons.calendar_view_month, color: Colors.blue),
                  ),
                  title: Text(
                    lang.isEnglish ? 'View Attendance' : 'حاضری دیکھیں',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AttendanceViewScreen(employee: employee),
                      ),
                    );
                  },
                ),

              // For contract employees - Show work entry option
              if (employee.salaryType == 'contract')
                ListTile(
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.orange.shade100,
                    child: Icon(Icons.work, color: Colors.orange),
                  ),
                  title: Text(
                    lang.isEnglish ? 'Add Work Entry' : 'کام کا اندراج کریں',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ContractWorkScreen(employee: employee),
                      ),
                    );
                  },
                ),

              // Manage Expenses - Available for all
              ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.red.shade100,
                  child: Icon(Icons.money_off, color: Colors.red),
                ),
                title: Text(
                  lang.isEnglish ? 'Manage Expenses' : 'اخراجات منظم کریں',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ExpenseManagementScreen(employee: employee),
                    ),
                  );
                },
              ),

              // Manage Advance - Available for all
              ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.teal.shade100,
                  child: Icon(Icons.attach_money, color: Colors.teal),
                ),
                title: Text(
                  lang.isEnglish ? 'Manage Advance' : 'ایڈوانس منظم کریں',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          AdvanceManagementScreen(employee: employee),
                    ),
                  );
                },
              ),

              const Divider(height: 1),

              // Delete Employee
              ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey.shade200,
                  child: Icon(Icons.delete, color: Colors.red),
                ),
                title: Text(
                  lang.isEnglish ? 'Delete Employee' : 'ملازم حذف کریں',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteEmployee(employee);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteEmployee(Employee employee) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);

    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(lang.isEnglish ? 'Delete Employee' : 'ملازم حذف کریں'),
        content: Text(
          lang.isEnglish
              ? 'Are you sure you want to delete ${employee.name}?'
              : 'کیا آپ واقعی ${employee.name} کو حذف کرنا چاہتے ہیں؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(lang.isEnglish ? 'Cancel' : 'منسوخ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(lang.isEnglish ? 'Delete' : 'حذف کریں'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _dbService.deleteEmployee(employee.id!);
        _loadEmployees();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                lang.isEnglish
                    ? 'Employee deleted successfully!'
                    : 'ملازم کامیابی سے حذف ہو گیا',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                lang.isEnglish
                    ? 'Error deleting employee: $e'
                    : 'ملازم حذف کرنے میں مسئلہ: $e',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.isEnglish ? 'Employee List' : 'ملازمین کی فہرست'),
        actions: [
          // Refresh button
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadEmployees,
          ),
        ],
      ),
      body: _employees.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              lang.isEnglish
                  ? 'No employees found'
                  : 'کوئی ملازم موجود نہیں',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      )
          : ListView.builder(
        itemCount: _employees.length,
        padding: EdgeInsets.all(8),
        itemBuilder: (context, index) {
          final employee = _employees[index];

          // Determine salary display based on type
          String salaryDisplay;
          if (employee.salaryType == 'contract') {
            salaryDisplay = lang.isEnglish
                ? 'PKR ${employee.basicSalary} ${_getUnitText(employee.contractUnit ?? 'bag', true)}'
                : '${employee.basicSalary} روپے ${_getUnitText(employee.contractUnit ?? 'bag', false)}';
          } else {
            salaryDisplay = lang.isEnglish
                ? 'PKR ${employee.basicSalary} (${_getSalaryTypeText(employee.salaryType, true)})'
                : '${employee.basicSalary} روپے (${_getSalaryTypeText(employee.salaryType, false)})';
          }

          return Card(
            margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: () => _showEmployeeOptions(employee),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name and Type Badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            employee.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: employee.salaryType == 'contract'
                                ? Colors.orange.shade100
                                : employee.salaryType == 'daily'
                                ? Colors.blue.shade100
                                : Colors.green.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _getSalaryTypeText(employee.salaryType, lang.isEnglish),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: employee.salaryType == 'contract'
                                  ? Colors.orange.shade900
                                  : employee.salaryType == 'daily'
                                  ? Colors.blue.shade900
                                  : Colors.green.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 4),

                    // Address
                    Text(
                      employee.address,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),

                    SizedBox(height: 8),

                    // Salary Info
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.attach_money,
                            size: 16,
                            color: Colors.green.shade700,
                          ),
                          SizedBox(width: 4),
                          Text(
                            salaryDisplay,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 8),

                    // Join Date
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: Colors.grey,
                        ),
                        SizedBox(width: 4),
                        Text(
                          lang.isEnglish
                              ? 'Joined: ${_formatDate(employee.joinDate)}'
                              : 'شمولیت: ${_formatDate(employee.joinDate)}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 8),

                    // Financial Summary
                    Row(
                      children: [
                        // Advance
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lang.isEnglish ? 'Advance' : 'ایڈوانس',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                                Text(
                                  'PKR ${employee.totalAdvance.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        SizedBox(width: 8),

                        // Expense
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lang.isEnglish ? 'Expense' : 'اخراجات',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                                Text(
                                  'PKR ${employee.totalExpense.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/addEmployee');
        },
        child: Icon(Icons.add),
        tooltip: lang.isEnglish ? 'Add Employee' : 'ملازم شامل کریں',
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}