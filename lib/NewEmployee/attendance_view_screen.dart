import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import '../Provider/lanprovider.dart';
import 'dbworking.dart';
import 'model.dart';

class AttendanceViewScreen extends StatefulWidget {
  final Employee employee;
  const AttendanceViewScreen({Key? key, required this.employee}) : super(key: key);
  @override
  _AttendanceViewScreenState createState() => _AttendanceViewScreenState();
}

class _AttendanceViewScreenState extends State<AttendanceViewScreen> {
  final DatabaseService _dbService = DatabaseService();
  List<Employee> _employees = [];
  List<Attendance> _allAttendance = [];
  DateTime _selectedMonth = DateTime.now();
  Employee? _selectedEmployee;
  bool _isLoading = true;
  Map<String, List<Attendance>> _employeeAttendanceMap = {};

  // Localization maps
  final Map<String, String> _englishTexts = {
    'appBarTitle': 'Attendance View',
    'attendanceFor': 'Attendance for',
    'filterByEmployee': 'Filter by Employee (Optional)',
    'allEmployees': 'All Employees',
    'generatePDF': 'Generate PDF',
    'noEmployees': 'No employees found',
    'address': 'Address',
    'salary': 'Salary',
    'present': 'Present',
    'halfDay': 'Half Day',
    'absent': 'Absent',
    'dailyAttendance': 'Daily Attendance',
    'generatePDFReport': 'Generate PDF Report',
    'allEmployeesPDF': 'All Employees',
    'allEmployeesDesc': 'Generate report for all employees',
    'currentEmployee': 'Current Employee',
    'currentEmployeeDesc': 'Generate report for',
    'selectMonth': 'Select Month',
    'pdfGenerated': 'PDF generated successfully!',
    'pdfError': 'Error generating PDF:',
    'generatedOn': 'Generated on',
    'attendanceReport': 'Attendance Report',
    'mon': 'Mon',
    'tue': 'Tue',
    'wed': 'Wed',
    'thu': 'Thu',
    'fri': 'Fri',
    'sat': 'Sat',
    'sun': 'Sun',
    'presentShort': 'P',
    'absentShort': 'A',
    'halfDayShort': 'H',
    'notMarkedShort': '-',
    'summary': 'Summary',
    'selectEmployee': 'Select Employee',
    'workingHours': 'Working Hours',
    'overtimeHours': 'Overtime Hours',
    'totalHours': 'Total Hours',
    'hoursWorked': 'Hours Worked',
    'standardHours': 'Standard Hours',
    'overtimeRate': 'Overtime Rate',
  };

  final Map<String, String> _urduTexts = {
    'appBarTitle': 'حاضری کا نظارہ',
    'attendanceFor': 'کے لیے حاضری',
    'filterByEmployee': 'ملازم کے ذریعے فلٹر کریں (اختیاری)',
    'allEmployees': 'تمام ملازمین',
    'generatePDF': 'پی ڈی ایف بنائیں',
    'noEmployees': 'کوئی ملازم نہیں ملا',
    'address': 'پتہ',
    'salary': 'تنخواہ',
    'present': 'حاضر',
    'halfDay': 'آدھا دن',
    'absent': 'غیر حاضر',
    'dailyAttendance': 'روزانہ حاضری',
    'generatePDFReport': 'پی ڈی ایف رپورٹ بنائیں',
    'allEmployeesPDF': 'تمام ملازمین',
    'allEmployeesDesc': 'تمام ملازمین کے لیے رپورٹ بنائیں',
    'currentEmployee': 'موجودہ ملازم',
    'currentEmployeeDesc': 'کے لیے رپورٹ بنائیں',
    'selectMonth': 'مہینہ منتخب کریں',
    'pdfGenerated': 'پی ڈی ایف کامیابی سے بن گئی!',
    'pdfError': 'پی ڈی ایف بنانے میں خرابی:',
    'generatedOn': 'تاریخ پیدائش',
    'attendanceReport': 'حاضری کی رپورٹ',
    'mon': 'سوموار',
    'tue': 'منگل',
    'wed': 'بدھ',
    'thu': 'جمعرات',
    'fri': 'جمعہ',
    'sat': 'ہفتہ',
    'sun': 'اتوار',
    'presentShort': 'P',
    'absentShort': 'A',
    'halfDayShort': 'H',
    'notMarkedShort': '-',
    'summary': 'خلاصہ',
    'selectEmployee': 'ملازم منتخب کریں',
    'workingHours': 'کام کے گھنٹے',
    'overtimeHours': 'اوور ٹائم گھنٹے',
    'totalHours': 'کل گھنٹے',
    'hoursWorked': 'کام کے گھنٹے',
    'standardHours': 'معیاری گھنٹے',
    'overtimeRate': 'اوور ٹائم ریٹ',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _getText(String key) {
    final languageProvider = context.read<LanguageProvider>();
    return languageProvider.isEnglish ? _englishTexts[key] ?? key : _urduTexts[key] ?? key;
  }

  String _getStatusText(String status) {
    final languageProvider = context.read<LanguageProvider>();
    if (languageProvider.isEnglish) {
      switch (status) {
        case 'present':
          return _getText('presentShort');
        case 'absent':
          return _getText('absentShort');
        case 'half-day':
          return _getText('halfDayShort');
        default:
          return _getText('notMarkedShort');
      }
    } else {
      switch (status) {
        case 'present':
          return _getText('presentShort');
        case 'absent':
          return _getText('absentShort');
        case 'half-day':
          return _getText('halfDayShort');
        default:
          return _getText('notMarkedShort');
      }
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    final employees = await _dbService.getEmployees();
    final startDate = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final endDate = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);

    // Load attendance for all employees
    Map<String, List<Attendance>> attendanceMap = {};

    for (final employee in employees) {
      final attendance = await _dbService.getEmployeeAttendance(
        employee.id!,
        startDate: startDate,
        endDate: endDate,
      );
      attendanceMap[employee.id!] = attendance;
    }

    setState(() {
      _employees = employees;
      _employeeAttendanceMap = attendanceMap;
      _isLoading = false;
    });
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
      });
      _loadData();
    }
  }

  List<Attendance> _getEmployeeAttendance(String employeeId) {
    return _employeeAttendanceMap[employeeId] ?? [];
  }

  Map<DateTime, String> _getAttendanceCalendar(String employeeId) {
    final attendance = _getEmployeeAttendance(employeeId);
    final startDate = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final endDate = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);

    Map<DateTime, String> calendar = {};

    for (var date = startDate; date.isBefore(endDate.add(Duration(days: 1))); date = date.add(Duration(days: 1))) {
      final attendanceForDate = attendance.firstWhere(
            (a) => a.date.year == date.year && a.date.month == date.month && a.date.day == date.day,
        orElse: () => Attendance(
          employeeId: employeeId,
          employeeName: '',
          date: date,
          status: 'not-marked',
        ),
      );
      calendar[date] = attendanceForDate.status;
    }

    return calendar;
  }

  int _getPresentDays(String employeeId) {
    return _getEmployeeAttendance(employeeId).where((a) => a.status == 'present').length;
  }

  int _getHalfDays(String employeeId) {
    return _getEmployeeAttendance(employeeId).where((a) => a.status == 'half-day').length;
  }

  int _getAbsentDays(String employeeId) {
    return _getEmployeeAttendance(employeeId).where((a) => a.status == 'absent').length;
  }

  double _getTotalWorkingHours(String employeeId) {
    return _getEmployeeAttendance(employeeId).fold(0.0, (sum, a) => sum + (a.workingHours ?? 0));
  }

  double _getTotalOvertimeHours(String employeeId) {
    return _getEmployeeAttendance(employeeId).fold(0.0, (sum, a) => sum + (a.overtimeHours ?? 0));
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'present':
        return Colors.green;
      case 'absent':
        return Colors.red;
      case 'half-day':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Future<void> _generatePDF({Employee? singleEmployee}) async {
    try {
      final pdf = pw.Document();
      final languageProvider = context.read<LanguageProvider>();
      final isEnglish = languageProvider.isEnglish;

      // Add header
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(
                  level: 0,
                  child: pw.Text(
                    '${_getText('attendanceReport')} - ${_selectedMonth.month}/${_selectedMonth.year}',
                    style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  '${_getText('generatedOn')}: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                  style: pw.TextStyle(fontSize: 12, color: PdfColors.grey),
                ),
                pw.SizedBox(height: 20),

                if (singleEmployee != null)
                  _buildEmployeePDFSection(pdf, singleEmployee, isEnglish)
                else
                  ..._employees.map((employee) => _buildEmployeePDFSection(pdf, employee, isEnglish)).toList(),
              ],
            );
          },
        ),
      );

      // Save PDF file
      final output = await getTemporaryDirectory();
      final file = File("${output.path}/attendance_report_${_selectedMonth.month}_${_selectedMonth.year}${singleEmployee != null ? '_${singleEmployee.name}' : ''}.pdf");
      await file.writeAsBytes(await pdf.save());

      // Open the PDF file
      await OpenFile.open(file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_getText('pdfGenerated'))),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_getText('pdfError')} $e')),
      );
    }
  }

  pw.Widget _buildEmployeePDFSection(pw.Document pdf, Employee employee, bool isEnglish) {
    final attendance = _getEmployeeAttendance(employee.id!);
    final calendar = _getAttendanceCalendar(employee.id!);
    final presentDays = _getPresentDays(employee.id!);
    final halfDays = _getHalfDays(employee.id!);
    final absentDays = _getAbsentDays(employee.id!);
    final totalHours = _getTotalWorkingHours(employee.id!);
    final totalOT = _getTotalOvertimeHours(employee.id!);

    return pw.Container(
      margin: pw.EdgeInsets.only(bottom: 20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            employee.name,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            '${_getText('address')}: ${employee.address}',
            style: pw.TextStyle(fontSize: 10),
          ),
          pw.Text(
            '${_getText('salary')}: PKR ${employee.basicSalary} (${employee.salaryType})',
            style: pw.TextStyle(fontSize: 10),
          ),
          if (employee.standardWorkingHours != null)
            pw.Text(
              '${_getText('standardHours')}: ${employee.standardWorkingHours} hrs/day',
              style: pw.TextStyle(fontSize: 10),
            ),
          if (employee.overtimeRate != null)
            pw.Text(
              '${_getText('overtimeRate')}: PKR ${employee.overtimeRate!.toStringAsFixed(2)}/hr',
              style: pw.TextStyle(fontSize: 10),
            ),
          pw.SizedBox(height: 10),

          // Summary
          pw.Row(
            children: [
              pw.Text('${_getText('present')}: $presentDays', style: pw.TextStyle(fontSize: 10, color: PdfColors.green)),
              pw.SizedBox(width: 10),
              pw.Text('${_getText('halfDay')}: $halfDays', style: pw.TextStyle(fontSize: 10, color: PdfColors.orange)),
              pw.SizedBox(width: 10),
              pw.Text('${_getText('absent')}: $absentDays', style: pw.TextStyle(fontSize: 10, color: PdfColors.red)),
            ],
          ),

          // Hours Summary
          pw.SizedBox(height: 5),
          pw.Row(
            children: [
              pw.Text('${_getText('totalHours')}: ${totalHours.toStringAsFixed(1)} hrs',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.blue)),
              pw.SizedBox(width: 10),
              if (totalOT > 0)
                pw.Text('${_getText('overtimeHours')}: ${totalOT.toStringAsFixed(1)} hrs',
                    style: pw.TextStyle(fontSize: 10, color: PdfColors.orange)),
            ],
          ),
          pw.SizedBox(height: 10),

          // Calendar view
          pw.Text('${_getText('dailyAttendance')}:', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 5),
          _buildCalendarPDF(calendar, isEnglish),
          pw.SizedBox(height: 10),
          pw.Divider(),
        ],
      ),
    );
  }

  pw.Widget _buildCalendarPDF(Map<DateTime, String> calendar, bool isEnglish) {
    final days = isEnglish
        ? [_getText('mon'), _getText('tue'), _getText('wed'), _getText('thu'), _getText('fri'), _getText('sat'), _getText('sun')]
        : [_getText('mon'), _getText('tue'), _getText('wed'), _getText('thu'), _getText('fri'), _getText('sat'), _getText('sun')];

    return pw.Table(
      border: pw.TableBorder.all(),
      columnWidths: {
        for (int i = 0; i < 7; i++) i: pw.FixedColumnWidth(25.0),
      },
      children: [
        // Header row with day names
        pw.TableRow(
          children: days.map((day) =>
              pw.Container(
                padding: pw.EdgeInsets.all(4),
                child: pw.Text(
                  day,
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
              )
          ).toList(),
        ),

        // Calendar rows
        ..._buildCalendarRowsPDF(calendar),
      ],
    );
  }

  List<pw.TableRow> _buildCalendarRowsPDF(Map<DateTime, String> calendar) {
    List<pw.TableRow> rows = [];
    List<pw.Widget> currentRow = [];

    final startDate = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final firstWeekday = startDate.weekday;

    // Add empty cells for days before the first day of month
    for (int i = 1; i < firstWeekday; i++) {
      currentRow.add(pw.Container(height: 20));
    }

    for (var date = startDate; date.month == _selectedMonth.month; date = date.add(Duration(days: 1))) {
      final status = calendar[date] ?? 'not-marked';

      currentRow.add(
        pw.Container(
          height: 20,
          alignment: pw.Alignment.center,
          child: pw.Text(
            _getStatusText(status),
            style: pw.TextStyle(
              fontSize: 8,
              color: _getPDFStatusColor(status),
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      );

      // Start new row after Sunday
      if (date.weekday == DateTime.sunday) {
        rows.add(pw.TableRow(children: [...currentRow]));
        currentRow = [];
      }
    }

    // Add remaining cells in the last row
    if (currentRow.isNotEmpty) {
      while (currentRow.length < 7) {
        currentRow.add(pw.Container(height: 20));
      }
      rows.add(pw.TableRow(children: currentRow));
    }

    return rows;
  }

  PdfColor _getPDFStatusColor(String status) {
    switch (status) {
      case 'present':
        return PdfColors.green;
      case 'absent':
        return PdfColors.red;
      case 'half-day':
        return PdfColors.orange;
      default:
        return PdfColors.grey;
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
            icon: Icon(Icons.picture_as_pdf),
            onPressed: () => _showPDFOptions(),
            tooltip: _getText('generatePDF'),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Month Selection
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.blue[50],
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_getText('attendanceFor')} ${_selectedMonth.month}/${_selectedMonth.year}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: fontFamily,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.calendar_today),
                  onPressed: () => _selectMonth(context),
                  tooltip: _getText('selectMonth'),
                ),
              ],
            ),
          ),

          // Employee Filter
          Padding(
            padding: EdgeInsets.all(16),
            child: DropdownButtonFormField<Employee>(
              value: _selectedEmployee,
              decoration: InputDecoration(
                labelText: _getText('filterByEmployee'),
                border: OutlineInputBorder(),
                labelStyle: TextStyle(fontFamily: fontFamily),
              ),
              items: [
                DropdownMenuItem<Employee>(
                  value: null,
                  child: Text(
                    _getText('allEmployees'),
                    style: TextStyle(fontFamily: fontFamily),
                  ),
                ),
                ..._employees.map((employee) {
                  return DropdownMenuItem<Employee>(
                    value: employee,
                    child: Text(
                      employee.name,
                      style: TextStyle(fontFamily: fontFamily),
                    ),
                  );
                }).toList(),
              ],
              onChanged: (employee) {
                setState(() {
                  _selectedEmployee = employee;
                });
              },
            ),
          ),

          // Attendance List
          Expanded(
            child: _buildAttendanceList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceList() {
    final languageProvider = context.read<LanguageProvider>();
    final fontFamily = languageProvider.fontFamily;
    final employeesToShow = _selectedEmployee != null ? [_selectedEmployee!] : _employees;

    if (employeesToShow.isEmpty) {
      return Center(
        child: Text(
          _getText('noEmployees'),
          style: TextStyle(fontFamily: fontFamily),
        ),
      );
    }

    return ListView.builder(
      itemCount: employeesToShow.length,
      itemBuilder: (context, index) {
        final employee = employeesToShow[index];
        return _buildEmployeeAttendanceCard(employee);
      },
    );
  }

  Widget _buildEmployeeAttendanceCard(Employee employee) {
    final languageProvider = context.read<LanguageProvider>();
    final fontFamily = languageProvider.fontFamily;
    final isEnglish = languageProvider.isEnglish;

    final attendanceRecords = _getEmployeeAttendance(employee.id!);
    final presentDays = _getPresentDays(employee.id!);
    final halfDays = _getHalfDays(employee.id!);
    final absentDays = _getAbsentDays(employee.id!);
    final calendar = _getAttendanceCalendar(employee.id!);
    final totalHours = _getTotalWorkingHours(employee.id!);
    final totalOT = _getTotalOvertimeHours(employee.id!);

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Employee Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: fontFamily,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        employee.address,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontFamily: fontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.picture_as_pdf, color: Colors.red),
                  onPressed: () => _generatePDF(singleEmployee: employee),
                  tooltip: '${_getText('generatePDF')} ${employee.name}',
                ),
              ],
            ),

            SizedBox(height: 16),

            // Employee Settings (if available)
            if (employee.standardWorkingHours != null || employee.overtimeRate != null)
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    if (employee.standardWorkingHours != null)
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              _getText('standardHours'),
                              style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                            ),
                            Text(
                              '${employee.standardWorkingHours} hrs',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (employee.overtimeRate != null)
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              _getText('overtimeRate'),
                              style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                            ),
                            Text(
                              'PKR ${employee.overtimeRate!.toStringAsFixed(0)}/hr',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

            SizedBox(height: 16),

            // Summary
            Text(
              _getText('summary'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: fontFamily,
              ),
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem(_getText('present'), presentDays, Colors.green, fontFamily),
                _buildSummaryItem(_getText('halfDay'), halfDays, Colors.orange, fontFamily),
                _buildSummaryItem(_getText('absent'), absentDays, Colors.red, fontFamily),
              ],
            ),

            // Hours Summary
            if (totalHours > 0 || totalOT > 0) ...[
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            _getText('totalHours'),
                            style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                          ),
                          Text(
                            '${totalHours.toStringAsFixed(1)} hrs',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (totalOT > 0)
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              _getText('overtimeHours'),
                              style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                            ),
                            Text(
                              '${totalOT.toStringAsFixed(1)} hrs',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],

            SizedBox(height: 16),

            // Calendar View
            Text(
              '${_getText('dailyAttendance')}:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: fontFamily,
              ),
            ),
            SizedBox(height: 8),
            _buildCalendarView(calendar, isEnglish, fontFamily),

            // Detailed Attendance List (Optional)
            if (attendanceRecords.isNotEmpty) ...[
              SizedBox(height: 16),
              Text(
                'Details:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: fontFamily,
                ),
              ),
              SizedBox(height: 8),
              ...attendanceRecords.map((record) => Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${record.date.day}/${record.date.month}:',
                        style: TextStyle(fontSize: 12, fontFamily: fontFamily),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _getStatusText(record.status),
                        style: TextStyle(
                          fontSize: 12,
                          color: _getStatusColor(record.status),
                          fontWeight: FontWeight.bold,
                          fontFamily: fontFamily,
                        ),
                      ),
                    ),
                    if (record.workingHours != null)
                      Expanded(
                        flex: 3,
                        child: Text(
                          '${record.workingHours!.toStringAsFixed(1)} hrs${record.overtimeHours != null && record.overtimeHours! > 0 ? ' (OT: ${record.overtimeHours} hrs)' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                            fontFamily: fontFamily,
                          ),
                        ),
                      ),
                  ],
                ),
              )).toList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, int count, Color color, String fontFamily) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
            fontFamily: fontFamily,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontFamily: fontFamily,
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarView(Map<DateTime, String> calendar, bool isEnglish, String fontFamily) {
    final days = isEnglish
        ? [_getText('mon'), _getText('tue'), _getText('wed'), _getText('thu'), _getText('fri'), _getText('sat'), _getText('sun')]
        : [_getText('mon'), _getText('tue'), _getText('wed'), _getText('thu'), _getText('fri'), _getText('sat'), _getText('sun')];

    return Table(
      border: TableBorder.all(),
      children: [
        // Header row
        TableRow(
          children: days.map((day) =>
              Container(
                padding: EdgeInsets.all(4),
                child: Text(
                  day,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    fontFamily: fontFamily,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
          ).toList(),
        ),

        // Calendar rows
        ..._buildCalendarRows(calendar, fontFamily),
      ],
    );
  }

  List<TableRow> _buildCalendarRows(Map<DateTime, String> calendar, String fontFamily) {
    List<TableRow> rows = [];
    List<Widget> currentRow = [];

    final startDate = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final firstWeekday = startDate.weekday;

    // Add empty cells for days before the first day of month
    for (int i = 1; i < firstWeekday; i++) {
      currentRow.add(Container(height: 20));
    }

    for (var date = startDate; date.month == _selectedMonth.month; date = date.add(Duration(days: 1))) {
      final status = calendar[date] ?? 'not-marked';

      currentRow.add(
        Container(
          height: 20,
          alignment: Alignment.center,
          child: Text(
            _getStatusText(status),
            style: TextStyle(
              fontSize: 10,
              color: _getStatusColor(status),
              fontWeight: FontWeight.bold,
              fontFamily: fontFamily,
            ),
          ),
        ),
      );

      // Start new row after Sunday
      if (date.weekday == DateTime.sunday) {
        rows.add(TableRow(children: [...currentRow]));
        currentRow = [];
      }
    }

    // Add remaining cells in the last row
    if (currentRow.isNotEmpty) {
      while (currentRow.length < 7) {
        currentRow.add(Container(height: 20));
      }
      rows.add(TableRow(children: currentRow));
    }

    return rows;
  }

  void _showPDFOptions() {
    final languageProvider = context.read<LanguageProvider>();
    final fontFamily = languageProvider.fontFamily;

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _getText('generatePDFReport'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: fontFamily,
                ),
              ),
              SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.people, color: Colors.blue),
                title: Text(
                  _getText('allEmployeesPDF'),
                  style: TextStyle(fontFamily: fontFamily),
                ),
                subtitle: Text(
                  _getText('allEmployeesDesc'),
                  style: TextStyle(fontFamily: fontFamily),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _generatePDF();
                },
              ),
              if (_selectedEmployee != null)
                ListTile(
                  leading: Icon(Icons.person, color: Colors.green),
                  title: Text(
                    _getText('currentEmployee'),
                    style: TextStyle(fontFamily: fontFamily),
                  ),
                  subtitle: Text(
                    '${_getText('currentEmployeeDesc')} ${_selectedEmployee!.name}',
                    style: TextStyle(fontFamily: fontFamily),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _generatePDF(singleEmployee: _selectedEmployee);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}