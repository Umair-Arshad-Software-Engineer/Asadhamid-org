import 'package:firebase_database/firebase_database.dart';
import 'model.dart';

class DatabaseService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Employee operations
  Future<void> addEmployee(Employee employee) async {
    final ref = _database.child('employees').push();
    employee.id = ref.key;
    await ref.set(employee.toJson());
  }

  Future<List<Employee>> getEmployees() async {
    final snapshot = await _database.child('employees').get();
    if (snapshot.exists) {
      Map<dynamic, dynamic> employeesMap = snapshot.value as Map<dynamic, dynamic>;
      return employeesMap.entries.map((entry) {
        return Employee.fromJson({
          'id': entry.key,
          ...Map<String, dynamic>.from(entry.value),
        });
      }).toList();
    }
    return [];
  }

  Future<void> updateEmployee(Employee employee) async {
    await _database.child('employees').child(employee.id!).update(employee.toJson());
  }

  Future<void> deleteEmployee(String employeeId) async {
    await _database.child('employees').child(employeeId).remove();
    // Delete related advance and expense transactions
    await _database.child('advanceTransactions').child(employeeId).remove();
    await _database.child('expenseTransactions').child(employeeId).remove();
  }

  // Advance Transactions operations
  Future<void> addAdvanceTransaction(AdvanceTransaction transaction) async {
    final ref = _database.child('advanceTransactions').child(transaction.employeeId).push();
    transaction.id = ref.key;
    await ref.set(transaction.toJson());

    // Update employee's total advance
    final employee = await getEmployee(transaction.employeeId);
    if (employee != null) {
      if (transaction.type == 'credit') {
        employee.totalAdvance += transaction.amount;
      } else {
        employee.totalAdvance -= transaction.amount;
      }
      await updateEmployee(employee);
    }
  }

  Future<Employee?> getEmployee(String employeeId) async {
    final snapshot = await _database.child('employees').child(employeeId).get();
    if (snapshot.exists) {
      return Employee.fromJson({
        'id': employeeId,
        ...Map<String, dynamic>.from(snapshot.value as Map),
      });
    }
    return null;
  }

  Future<List<AdvanceTransaction>> getAdvanceTransactions(String employeeId) async {
    final snapshot = await _database.child('advanceTransactions').child(employeeId).get();
    if (snapshot.exists) {
      Map<dynamic, dynamic> transactionsMap = snapshot.value as Map<dynamic, dynamic>;
      List<AdvanceTransaction> transactions = transactionsMap.entries.map((entry) {
        return AdvanceTransaction.fromJson({
          'id': entry.key,
          ...Map<String, dynamic>.from(entry.value),
        });
      }).toList();

      // Sort by date (oldest first) for correct balance calculation
      transactions.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      return transactions;
    }
    return [];
  }

  Future<void> deleteAdvanceTransaction(String employeeId, String transactionId) async {
    final transaction = await getAdvanceTransaction(employeeId, transactionId);
    if (transaction != null) {
      // Remove transaction
      await _database.child('advanceTransactions').child(employeeId).child(transactionId).remove();

      // Update employee's total advance (reverse the effect)
      final employee = await getEmployee(employeeId);
      if (employee != null) {
        if (transaction.type == 'credit') {
          employee.totalAdvance -= transaction.amount;
        } else {
          employee.totalAdvance += transaction.amount;
        }
        await updateEmployee(employee);
      }
    }
  }

  Future<AdvanceTransaction?> getAdvanceTransaction(String employeeId, String transactionId) async {
    final snapshot = await _database.child('advanceTransactions').child(employeeId).child(transactionId).get();
    if (snapshot.exists) {
      return AdvanceTransaction.fromJson({
        'id': transactionId,
        ...Map<String, dynamic>.from(snapshot.value as Map),
      });
    }
    return null;
  }

// Expense Transactions operations (now with credit/debit like advance)
  Future<void> addExpenseTransaction(ExpenseTransaction transaction) async {
    final ref = _database.child('expenseTransactions').child(transaction.employeeId).push();
    transaction.id = ref.key;
    await ref.set(transaction.toJson());

    // Update employee's total expense
    final employee = await getEmployee(transaction.employeeId);
    if (employee != null) {
      if (transaction.type == 'credit') {
        employee.totalExpense += transaction.amount;
      } else {
        employee.totalExpense -= transaction.amount;
      }
      await updateEmployee(employee);
    }
  }

  Future<List<ExpenseTransaction>> getExpenseTransactions(String employeeId) async {
    final snapshot = await _database.child('expenseTransactions').child(employeeId).get();
    if (snapshot.exists) {
      Map<dynamic, dynamic> transactionsMap = snapshot.value as Map<dynamic, dynamic>;
      List<ExpenseTransaction> transactions = transactionsMap.entries.map((entry) {
        return ExpenseTransaction.fromJson({
          'id': entry.key,
          ...Map<String, dynamic>.from(entry.value),
        });
      }).toList();

      // Sort by date (oldest first) for correct balance calculation
      transactions.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      return transactions;
    }
    return [];
  }

  Future<void> deleteExpenseTransaction(String employeeId, String transactionId) async {
    final transaction = await getExpenseTransaction(employeeId, transactionId);
    if (transaction != null) {
      // Remove transaction
      await _database.child('expenseTransactions').child(employeeId).child(transactionId).remove();

      // Update employee's total expense (reverse the effect)
      final employee = await getEmployee(employeeId);
      if (employee != null) {
        if (transaction.type == 'credit') {
          employee.totalExpense -= transaction.amount;
        } else {
          employee.totalExpense += transaction.amount;
        }
        await updateEmployee(employee);
      }
    }
  }

  Future<ExpenseTransaction?> getExpenseTransaction(String employeeId, String transactionId) async {
    final snapshot = await _database.child('expenseTransactions').child(employeeId).child(transactionId).get();
    if (snapshot.exists) {
      return ExpenseTransaction.fromJson({
        'id': transactionId,
        ...Map<String, dynamic>.from(snapshot.value as Map),
      });
    }
    return null;
  }

// In markAttendance method, make sure it's clean:
  Future<void> markAttendance(Attendance attendance) async {
    final dateKey = '${attendance.date.year}-${attendance.date.month}-${attendance.date.day}';
    final ref = _database.child('attendance').child(dateKey).child(attendance.employeeId);
    attendance.id = ref.key;
    await ref.set(attendance.toJson());
  }

  Future<List<Attendance>> getAttendanceForDate(DateTime date) async {
    final dateKey = '${date.year}-${date.month}-${date.day}';
    final snapshot = await _database.child('attendance').child(dateKey).get();

    if (snapshot.exists) {
      Map<dynamic, dynamic> attendanceMap = snapshot.value as Map<dynamic, dynamic>;
      return attendanceMap.entries.map((entry) {
        return Attendance.fromJson({
          'id': entry.key,
          ...Map<String, dynamic>.from(entry.value),
        });
      }).toList();
    }
    return [];
  }

  Future<List<Attendance>> getEmployeeAttendance(String employeeId, {DateTime? startDate, DateTime? endDate}) async {
    // This is a simplified version - in production you might want to query by date range
    final snapshot = await _database.child('attendance').get();
    List<Attendance> allAttendance = [];

    if (snapshot.exists) {
      Map<dynamic, dynamic> datesMap = snapshot.value as Map<dynamic, dynamic>;

      datesMap.forEach((dateKey, employeesMap) {
        if (employeesMap is Map) {
          employeesMap.forEach((employeeKey, attendanceData) {
            if (employeeKey == employeeId) {
              allAttendance.add(Attendance.fromJson({
                'id': employeeKey,
                ...Map<String, dynamic>.from(attendanceData),
              }));
            }
          });
        }
      });
    }

    // Filter by date range if provided
    if (startDate != null && endDate != null) {
      allAttendance = allAttendance.where((attendance) {
        return attendance.date.isAfter(startDate.subtract(Duration(days: 1))) &&
            attendance.date.isBefore(endDate.add(Duration(days: 1)));
      }).toList();
    }

    // Sort by date (newest first)
    allAttendance.sort((a, b) => b.date.compareTo(a.date));
    return allAttendance;
  }

  Future<void> updateAttendance(Attendance attendance) async {
    final dateKey = '${attendance.date.year}-${attendance.date.month}-${attendance.date.day}';
    await _database.child('attendance').child(dateKey).child(attendance.employeeId).update(attendance.toJson());
  }

  Future<void> deleteAttendance(String employeeId, DateTime date) async {
    final dateKey = '${date.year}-${date.month}-${date.day}';
    await _database.child('attendance').child(dateKey).child(employeeId).remove();
  }

  Future<SalaryCalculation> calculateSalary(String employeeId, DateTime month) async {
    final employee = await getEmployee(employeeId);
    if (employee == null) throw Exception('Employee not found');

    // Get attendance for the month (for non-contract employees)
    final startDate = DateTime(month.year, month.month, 1);
    final endDate = DateTime(month.year, month.month + 1, 0);

    List<Attendance> attendanceRecords = [];
    if (!employee.isContractEmployee) {
      attendanceRecords = await getEmployeeAttendance(employeeId,
          startDate: startDate, endDate: endDate);
    }

    // Get advances and expenses for the month
    final advances = await getAdvanceTransactions(employeeId);
    final expenses = await getExpenseTransactions(employeeId);

    // Filter transactions for current month
    final monthAdvances = advances.where((advance) =>
    advance.dateTime.isAfter(startDate.subtract(Duration(days: 1))) &&
        advance.dateTime.isBefore(endDate.add(Duration(days: 1)))
    ).toList();

    final monthExpenses = expenses.where((expense) =>
    expense.dateTime.isAfter(startDate.subtract(Duration(days: 1))) &&
        expense.dateTime.isBefore(endDate.add(Duration(days: 1)))
    ).toList();

    // Get contract work entries for contract employees
    List<ContractWorkEntry>? contractEntries;
    if (employee.isContractEmployee) {
      contractEntries = await getContractWorkEntries(employeeId, month: month);
    }

    return SalaryCalculation(
      employee: employee,
      month: month,
      attendanceRecords: attendanceRecords,
      advances: monthAdvances,
      expenses: monthExpenses,
      contractWorkEntries: contractEntries,
    );
  }

  Future<void> paySalary(SalaryPayment payment) async {
    final ref = _database.child('salaryPayments').push();
    payment.id = ref.key;
    await ref.set(payment.toJson());

    // Only create debit transactions if there are actual deductions
    if (payment.totalAdvances > 0) {
      final debitTransaction = AdvanceTransaction(
        employeeId: payment.employeeId,
        dateTime: DateTime.now(),
        description: 'Salary deduction - ${payment.month.month}/${payment.month.year}',
        amount: payment.totalAdvances,
        type: 'debit',
        balance: 0.0, // Balance will be calculated separately
      );
      await addAdvanceTransaction(debitTransaction);
    }

    if (payment.totalExpenses > 0) {
      final debitTransaction = ExpenseTransaction(
        employeeId: payment.employeeId,
        dateTime: DateTime.now(),
        description: 'Salary deduction - ${payment.month.month}/${payment.month.year}',
        amount: payment.totalExpenses,
        type: 'debit',
        balance: 0.0, // Balance will be calculated separately
      );
      await addExpenseTransaction(debitTransaction);
    }

    // Note: Contract work entries are not deleted when salary is paid
    // They remain for historical records
  }

  Future<List<SalaryPayment>> getSalaryPayments() async {
    final snapshot = await _database.child('salaryPayments').get();
    if (snapshot.exists) {
      Map<dynamic, dynamic> paymentsMap = snapshot.value as Map<dynamic, dynamic>;
      List<SalaryPayment> payments = [];

      paymentsMap.forEach((key, value) {
        try {
          final payment = SalaryPayment.fromJson({
            'id': key,
            ...Map<String, dynamic>.from(value),
          });
          payments.add(payment);
        } catch (e) {
          print('Error parsing salary payment $key: $e');
        }
      });

      return payments;
    }
    return [];
  }

  Future<List<SalaryPayment>> getSalaryPaymentsByEmployee(String employeeId) async {
    final allPayments = await getSalaryPayments();
    return allPayments.where((payment) => payment.employeeId == employeeId).toList();
  }

  Future<bool> hasSalaryPayment(String employeeId, DateTime month) async {
    final employeePayments = await getSalaryPaymentsByEmployee(employeeId);
    return employeePayments.any((payment) =>
    payment.month.year == month.year && payment.month.month == month.month
    );
  }

  Future<void> updateSalaryPayment(SalaryPayment payment) async {
    await _database.child('salaryPayments').child(payment.id!).update(payment.toJson());
  }

  Future<void> deleteSalaryPayment(String paymentId) async {
    await _database.child('salaryPayments').child(paymentId).remove();
  }

  // Add to DatabaseService class in dbworking.dart

// Contract Work Entries operations
  Future<void> addContractWorkEntry(ContractWorkEntry entry) async {
    final ref = _database.child('contractWork').child(entry.employeeId).push();
    entry.id = ref.key;
    await ref.set(entry.toJson());
  }

  Future<List<ContractWorkEntry>> getContractWorkEntries(String employeeId, {DateTime? month}) async {
    final snapshot = await _database.child('contractWork').child(employeeId).get();

    if (snapshot.exists) {
      Map<dynamic, dynamic> entriesMap = snapshot.value as Map<dynamic, dynamic>;
      List<ContractWorkEntry> entries = entriesMap.entries.map((entry) {
        return ContractWorkEntry.fromJson({
          'id': entry.key,
          ...Map<String, dynamic>.from(entry.value),
        });
      }).toList();

      // Sort by date (newest first)
      entries.sort((a, b) => b.date.compareTo(a.date));

      // Filter by month if provided
      if (month != null) {
        entries = entries.where((entry) =>
        entry.date.year == month.year && entry.date.month == month.month
        ).toList();
      }

      return entries;
    }
    return [];
  }

  Future<void> deleteContractWorkEntry(String employeeId, String entryId) async {
    await _database.child('contractWork').child(employeeId).child(entryId).remove();
  }

  Future<ContractWorkEntry?> getContractWorkEntry(String employeeId, String entryId) async {
    final snapshot = await _database.child('contractWork').child(employeeId).child(entryId).get();
    if (snapshot.exists) {
      return ContractWorkEntry.fromJson({
        'id': entryId,
        ...Map<String, dynamic>.from(snapshot.value as Map),
      });
    }
    return null;
  }

// Get all contract work entries across employees (for reporting)
  Future<List<ContractWorkEntry>> getAllContractWorkEntries({DateTime? month}) async {
    final snapshot = await _database.child('contractWork').get();
    List<ContractWorkEntry> allEntries = [];

    if (snapshot.exists) {
      Map<dynamic, dynamic> employeesMap = snapshot.value as Map<dynamic, dynamic>;

      employeesMap.forEach((employeeId, entriesMap) {
        if (entriesMap is Map) {
          entriesMap.forEach((entryId, entryData) {
            try {
              final entry = ContractWorkEntry.fromJson({
                'id': entryId,
                ...Map<String, dynamic>.from(entryData),
              });

              // Filter by month if provided
              if (month == null ||
                  (entry.date.year == month.year && entry.date.month == month.month)) {
                allEntries.add(entry);
              }
            } catch (e) {
              print('Error parsing contract work entry: $e');
            }
          });
        }
      });
    }

    // Sort by date (newest first)
    allEntries.sort((a, b) => b.date.compareTo(a.date));
    return allEntries;
  }

// Get contract work summary for an employee in a month
  Future<Map<String, double>> getContractWorkSummary(String employeeId, DateTime month) async {
    final entries = await getContractWorkEntries(employeeId, month: month);

    double totalQuantity = 0;
    double totalEarnings = 0;

    for (var entry in entries) {
      totalQuantity += entry.quantity;
      totalEarnings += entry.totalAmount;
    }

    return {
      'totalQuantity': totalQuantity,
      'totalEarnings': totalEarnings,
    };
  }


}