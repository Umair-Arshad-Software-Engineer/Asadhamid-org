
class AdvanceTransaction {
  String? id;
  String employeeId;
  DateTime dateTime;
  String description;
  double amount;
  String type; // 'credit' or 'debit'
  double balance;

  AdvanceTransaction({
    this.id,
    required this.employeeId,
    required this.dateTime,
    required this.description,
    required this.amount,
    required this.type,
    required this.balance,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employeeId': employeeId,
      'dateTime': dateTime.millisecondsSinceEpoch,
      'description': description,
      'amount': amount,
      'type': type,
      'balance': balance,
    };
  }

  factory AdvanceTransaction.fromJson(Map<String, dynamic> json) {
    // Helper functions for type safety
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    DateTime parseDate(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is String) {
        try {
          return DateTime.parse(value);
        } catch (e) {
          return DateTime.now();
        }
      }
      return DateTime.now();
    }

    String parseString(dynamic value) {
      if (value == null) return '';
      return value.toString();
    }

    return AdvanceTransaction(
      id: parseString(json['id']),
      employeeId: parseString(json['employeeId']),
      dateTime: parseDate(json['dateTime']),
      description: parseString(json['description']),
      amount: parseDouble(json['amount']),
      type: parseString(json['type']),
      balance: parseDouble(json['balance']),
    );
  }
}

class ExpenseTransaction {
  String? id;
  String employeeId;
  DateTime dateTime;
  String description;
  double amount;
  String type; // 'credit' or 'debit' - credit for adding expense, debit for deducting expense
  double balance;

  ExpenseTransaction({
    this.id,
    required this.employeeId,
    required this.dateTime,
    required this.description,
    required this.amount,
    required this.type,
    required this.balance,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employeeId': employeeId,
      'dateTime': dateTime.millisecondsSinceEpoch,
      'description': description,
      'amount': amount,
      'type': type,
      'balance': balance,
    };
  }

  factory ExpenseTransaction.fromJson(Map<String, dynamic> json) {
    // Helper functions for type safety
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    DateTime parseDate(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is String) {
        try {
          return DateTime.parse(value);
        } catch (e) {
          return DateTime.now();
        }
      }
      return DateTime.now();
    }

    String parseString(dynamic value) {
      if (value == null) return '';
      return value.toString();
    }

    return ExpenseTransaction(
      id: parseString(json['id']),
      employeeId: parseString(json['employeeId']),
      dateTime: parseDate(json['dateTime']),
      description: parseString(json['description']),
      amount: parseDouble(json['amount']),
      type: parseString(json['type']),
      balance: parseDouble(json['balance']),
    );
  }
}


// New Model for Contract Work Entry
class ContractWorkEntry {
  String? id;
  String employeeId;
  String employeeName;
  DateTime date;
  double quantity; // Number of units (bags, kg, etc.)
  String unit; // 'bag', 'kg', 'ton', 'meter', 'piece'
  double unitPrice; // Price per unit
  double totalAmount; // quantity * unitPrice
  String? description; // Optional description of work done

  ContractWorkEntry({
    this.id,
    required this.employeeId,
    required this.employeeName,
    required this.date,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.totalAmount,
    this.description,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'date': date.millisecondsSinceEpoch,
      'quantity': quantity,
      'unit': unit,
      'unitPrice': unitPrice,
      'totalAmount': totalAmount,
      'description': description,
    };
  }

  factory ContractWorkEntry.fromJson(Map<String, dynamic> json) {
    // Helper functions for type safety
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    DateTime parseDate(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is String) {
        try {
          return DateTime.parse(value);
        } catch (e) {
          return DateTime.now();
        }
      }
      return DateTime.now();
    }

    String parseString(dynamic value) {
      if (value == null) return '';
      return value.toString();
    }

    return ContractWorkEntry(
      id: parseString(json['id']),
      employeeId: parseString(json['employeeId']),
      employeeName: parseString(json['employeeName']),
      date: parseDate(json['date']),
      quantity: parseDouble(json['quantity']),
      unit: parseString(json['unit']),
      unitPrice: parseDouble(json['unitPrice']),
      totalAmount: parseDouble(json['totalAmount']),
      description: parseString(json['description']),
    );
  }

  // Helper method to get unit text
  String getUnitText(bool isEnglish) {
    switch (unit) {
      case 'bag':
        return isEnglish ? 'bags' : 'بوریاں';
      case 'kg':
        return isEnglish ? 'kg' : 'کلوگرام';
      case 'ton':
        return isEnglish ? 'tons' : 'ٹن';
      case 'meter':
        return isEnglish ? 'meters' : 'میٹر';
      case 'piece':
        return isEnglish ? 'pieces' : 'پی سیز';
      default:
        return unit;
    }
  }
}



// Updated SalaryPayment to support contract employees
class SalaryPayment {
  String? id;
  String employeeId;
  String employeeName;
  DateTime month;
  DateTime paymentDate;
  double baseSalary;
  double attendanceSalary; // For monthly/daily employees
  double contractEarnings; // For contract employees
  double totalContractQuantity; // Total quantity for contract employees
  double totalAdvances;
  double totalExpenses;
  double netSalary;
  List<AdvanceTransaction> deductedAdvances;
  List<ExpenseTransaction> deductedExpenses;
  List<ContractWorkEntry>? contractWorkEntries; // For contract employees
  String salaryType; // To know which type of salary was paid

  SalaryPayment({
    this.id,
    required this.employeeId,
    required this.employeeName,
    required this.month,
    required this.paymentDate,
    required this.baseSalary,
    required this.attendanceSalary,
    required this.contractEarnings,
    required this.totalContractQuantity,
    required this.totalAdvances,
    required this.totalExpenses,
    required this.netSalary,
    required this.deductedAdvances,
    required this.deductedExpenses,
    this.contractWorkEntries,
    required this.salaryType,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'month': month.millisecondsSinceEpoch,
      'paymentDate': paymentDate.millisecondsSinceEpoch,
      'baseSalary': baseSalary,
      'attendanceSalary': attendanceSalary,
      'contractEarnings': contractEarnings,
      'totalContractQuantity': totalContractQuantity,
      'totalAdvances': totalAdvances,
      'totalExpenses': totalExpenses,
      'netSalary': netSalary,
      'deductedAdvances': deductedAdvances.map((advance) => advance.toJson()).toList(),
      'deductedExpenses': deductedExpenses.map((expense) => expense.toJson()).toList(),
      'contractWorkEntries': contractWorkEntries?.map((entry) => entry.toJson()).toList(),
      'salaryType': salaryType,
    };
  }

  factory SalaryPayment.fromJson(Map<String, dynamic> json) {
    // Helper function to safely convert dynamic to appropriate types
    T? safeCast<T>(dynamic value, T? defaultValue) {
      if (value == null) return defaultValue;
      try {
        if (T == String) return value.toString() as T;
        if (T == double) {
          if (value is num) return value.toDouble() as T;
          if (value is String) return double.tryParse(value) as T? ?? defaultValue;
        }
        if (T == int) {
          if (value is num) return value.toInt() as T;
          if (value is String) return int.tryParse(value) as T? ?? defaultValue;
        }
        if (T == DateTime) {
          if (value is int) return DateTime.fromMillisecondsSinceEpoch(value) as T;
          if (value is String) return DateTime.parse(value) as T;
        }
        return value as T;
      } catch (e) {
        return defaultValue;
      }
    }

    // Helper function to safely parse list of transactions
    List<T> safeParseList<T>(dynamic listData, T Function(Map<String, dynamic>) fromJsonFunc) {
      List<T> result = [];
      if (listData == null) return result;

      try {
        if (listData is List) {
          for (var item in listData) {
            try {
              if (item is Map) {
                // Convert Map<dynamic, dynamic> to Map<String, dynamic>
                Map<String, dynamic> castedItem = {};
                item.forEach((key, value) {
                  castedItem[key.toString()] = value;
                });
                result.add(fromJsonFunc(castedItem));
              }
            } catch (e) {
              print('Error parsing list item: $e');
            }
          }
        }
      } catch (e) {
        print('Error parsing list: $e');
      }

      return result;
    }

    // Parse dates safely
    DateTime parseDate(dynamic dateValue) {
      if (dateValue == null) return DateTime.now();
      if (dateValue is int) {
        return DateTime.fromMillisecondsSinceEpoch(dateValue);
      }
      if (dateValue is String) {
        try {
          return DateTime.parse(dateValue);
        } catch (e) {
          return DateTime.now();
        }
      }
      return DateTime.now();
    }

    // Parse double safely
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) {
        return double.tryParse(value) ?? 0.0;
      }
      return 0.0;
    }

    // Parse string safely
    String parseString(dynamic value) {
      if (value == null) return '';
      return value.toString();
    }

    // Parse deductedAdvances
    List<AdvanceTransaction> advances = safeParseList<AdvanceTransaction>(
      json['deductedAdvances'],
          (map) => AdvanceTransaction.fromJson(map),
    );

    // Parse deductedExpenses
    List<ExpenseTransaction> expenses = safeParseList<ExpenseTransaction>(
      json['deductedExpenses'],
          (map) => ExpenseTransaction.fromJson(map),
    );

    // Parse contractWorkEntries
    List<ContractWorkEntry> workEntries = safeParseList<ContractWorkEntry>(
      json['contractWorkEntries'],
          (map) => ContractWorkEntry.fromJson(map),
    );

    return SalaryPayment(
      id: parseString(json['id']),
      employeeId: parseString(json['employeeId']),
      employeeName: parseString(json['employeeName']),
      month: parseDate(json['month']),
      paymentDate: parseDate(json['paymentDate']),
      baseSalary: parseDouble(json['baseSalary']),
      attendanceSalary: parseDouble(json['attendanceSalary']),
      contractEarnings: parseDouble(json['contractEarnings']),
      totalContractQuantity: parseDouble(json['totalContractQuantity']),
      totalAdvances: parseDouble(json['totalAdvances']),
      totalExpenses: parseDouble(json['totalExpenses']),
      netSalary: parseDouble(json['netSalary']),
      deductedAdvances: advances,
      deductedExpenses: expenses,
      contractWorkEntries: workEntries.isNotEmpty ? workEntries : null,
      salaryType: parseString(json['salaryType']),
    );
  }

  // Helper to check if this was a contract payment
  bool get isContractPayment => salaryType == 'contract';
}


// Add to Attendance class
class Attendance {
  String? id;
  String employeeId;
  String employeeName;
  DateTime date;
  String status; // 'present', 'absent', 'half-day'
  double? workingHours; // New field for daily working hours
  double? overtimeHours; // New field for overtime hours
  double? overtimeRate; // New field for overtime rate (optional)

  Attendance({
    this.id,
    required this.employeeId,
    required this.employeeName,
    required this.date,
    required this.status,
    this.workingHours,
    this.overtimeHours,
    this.overtimeRate,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'date': date.millisecondsSinceEpoch,
      'status': status,
      'workingHours': workingHours,
      'overtimeHours': overtimeHours,
      'overtimeRate': overtimeRate,
    };
  }

  factory Attendance.fromJson(Map<String, dynamic> json) {
    return Attendance(
      id: json['id'],
      employeeId: json['employeeId'],
      employeeName: json['employeeName'],
      date: DateTime.fromMillisecondsSinceEpoch(json['date']),
      status: json['status'],
      workingHours: json['workingHours']?.toDouble(),
      overtimeHours: json['overtimeHours']?.toDouble(),
      overtimeRate: json['overtimeRate']?.toDouble(),
    );
  }
}

// Update Employee class to include overtime rate and ensure isContractEmployee is defined
class Employee {
  String? id;
  String name;
  String address;
  double basicSalary;
  String salaryType;
  DateTime joinDate;
  double totalAdvance;
  double totalExpense;
  String? contractUnit;
  double? overtimeRate; // New field: overtime rate (per hour)
  double? standardWorkingHours; // New field: standard working hours per day

  Employee({
    this.id,
    required this.name,
    required this.address,
    required this.basicSalary,
    required this.salaryType,
    required this.joinDate,
    this.totalAdvance = 0.0,
    this.totalExpense = 0.0,
    this.contractUnit,
    this.overtimeRate,
    this.standardWorkingHours = 8, // Default 8 hours per day
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'basicSalary': basicSalary,
      'salaryType': salaryType,
      'joinDate': joinDate.millisecondsSinceEpoch,
      'totalAdvance': totalAdvance,
      'totalExpense': totalExpense,
      'contractUnit': contractUnit,
      'overtimeRate': overtimeRate,
      'standardWorkingHours': standardWorkingHours,
    };
  }

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'],
      name: json['name'],
      address: json['address'],
      basicSalary: json['basicSalary'].toDouble(),
      salaryType: json['salaryType'],
      joinDate: DateTime.fromMillisecondsSinceEpoch(json['joinDate']),
      totalAdvance: json['totalAdvance']?.toDouble() ?? 0.0,
      totalExpense: json['totalExpense']?.toDouble() ?? 0.0,
      contractUnit: json['contractUnit'],
      overtimeRate: json['overtimeRate']?.toDouble(),
      standardWorkingHours: json['standardWorkingHours']?.toDouble() ?? 8,
    );
  }

  // Helper method to check if employee is on contract
  bool get isContractEmployee => salaryType == 'contract';

  // Helper method to get unit text
  String getUnitText(bool isEnglish) {
    if (!isContractEmployee || contractUnit == null) return '';

    switch (contractUnit) {
      case 'bag':
        return isEnglish ? 'bag' : 'بوری';
      case 'kg':
        return isEnglish ? 'kg' : 'کلوگرام';
      case 'ton':
        return isEnglish ? 'ton' : 'ٹن';
      case 'meter':
        return isEnglish ? 'meter' : 'میٹر';
      case 'piece':
        return isEnglish ? 'piece' : 'پی سی';
      default:
        return contractUnit!;
    }
  }
}

// Update SalaryCalculation class to include overtime
class SalaryCalculation {
  final Employee employee;
  final DateTime month;
  final List<Attendance> attendanceRecords;
  final List<AdvanceTransaction> advances;
  final List<ExpenseTransaction> expenses;
  final List<ContractWorkEntry>? contractWorkEntries;
  final double manualAdvanceDeduction;
  final double manualExpenseDeduction;

  SalaryCalculation({
    required this.employee,
    required this.month,
    required this.attendanceRecords,
    required this.advances,
    required this.expenses,
    this.contractWorkEntries,
    this.manualAdvanceDeduction = 0.0,
    this.manualExpenseDeduction = 0.0,
  });

  // Copy with method for manual deductions
  SalaryCalculation copyWith({
    double? manualAdvanceDeduction,
    double? manualExpenseDeduction,
    List<ContractWorkEntry>? contractWorkEntries,
  }) {
    return SalaryCalculation(
      employee: employee,
      month: month,
      attendanceRecords: attendanceRecords,
      advances: advances,
      expenses: expenses,
      contractWorkEntries: contractWorkEntries ?? this.contractWorkEntries,
      manualAdvanceDeduction: manualAdvanceDeduction ?? this.manualAdvanceDeduction,
      manualExpenseDeduction: manualExpenseDeduction ?? this.manualExpenseDeduction,
    );
  }

  // For contract employees
  double get totalContractEarnings {
    if (!employee.isContractEmployee || contractWorkEntries == null) return 0.0;
    return contractWorkEntries!.fold(0.0, (sum, entry) => sum + entry.totalAmount);
  }

  double get totalContractQuantity {
    if (!employee.isContractEmployee || contractWorkEntries == null) return 0.0;
    return contractWorkEntries!.fold(0.0, (sum, entry) => sum + entry.quantity);
  }

  // For monthly/daily employees
  int get totalWorkingDays {
    if (employee.isContractEmployee) return 0;

    // For monthly employees, always use 30 days regardless of actual month length
    if (employee.salaryType == 'monthly') {
      return 30;
    }

    // For daily employees, calculate actual days in the month
    final startDate = DateTime(month.year, month.month, 1);
    final endDate = DateTime(month.year, month.month + 1, 0);
    int days = 0;
    for (var date = startDate; date.isBefore(endDate.add(Duration(days: 1))); date = date.add(Duration(days: 1))) {
      // Include ALL days of the month
      days++;
    }
    return days;
  }

  int get presentDays {
    if (employee.isContractEmployee) return 0;
    return attendanceRecords.where((record) => record.status == 'present').length;
  }

  int get halfDays {
    if (employee.isContractEmployee) return 0;
    return attendanceRecords.where((record) => record.status == 'half-day').length;
  }

  int get absentDays {
    if (employee.isContractEmployee) return 0;
    return totalWorkingDays - presentDays - (halfDays ~/ 2);
  }

  double get effectiveWorkingDays {
    if (employee.isContractEmployee) return 0;
    return presentDays + (halfDays * 0.5);
  }

  // Overtime calculations
  double get totalOvertimeHours {
    if (employee.isContractEmployee) return 0.0;
    return attendanceRecords.fold(0.0, (sum, record) =>
    sum + (record.overtimeHours ?? 0.0));
  }

  double get overtimeEarnings {
    if (employee.isContractEmployee) return 0.0;
    final rate = employee.overtimeRate ?? (employee.basicSalary / 30 / 8); // Default calculation using 30 days
    return totalOvertimeHours * rate;
  }

  double get baseSalary {
    return employee.basicSalary;
  }

  double get perDaySalary {
    if (employee.isContractEmployee) return 0;
    return employee.basicSalary / totalWorkingDays;
  }

  double get perHourRate {
    if (employee.isContractEmployee) return 0;
    return perDaySalary / (employee.standardWorkingHours ?? 8);
  }

  double get presentDaysSalary {
    if (employee.isContractEmployee) return 0;
    return presentDays * perDaySalary;
  }

  double get halfDaysSalary {
    if (employee.isContractEmployee) return 0;
    return halfDays * (perDaySalary / 2);
  }

  double get attendanceSalary {
    if (employee.isContractEmployee) return 0;
    return presentDaysSalary + halfDaysSalary;
  }

  // Gross earnings including overtime
  double get grossEarnings {
    if (employee.isContractEmployee) {
      return totalContractEarnings;
    } else {
      return attendanceSalary + overtimeEarnings;
    }
  }

  // Available amounts for deduction (credit transactions only)
  double get availableAdvances {
    return advances.where((advance) => advance.type == 'credit').fold(0.0, (sum, advance) => sum + advance.amount);
  }

  double get availableExpenses {
    return expenses.where((expense) => expense.type == 'credit').fold(0.0, (sum, expense) => sum + expense.amount);
  }

  // Net salary with manual deductions
  double get netSalaryWithManualDeductions {
    return grossEarnings - manualAdvanceDeduction - manualExpenseDeduction;
  }
}