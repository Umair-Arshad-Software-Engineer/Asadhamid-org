import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Provider/lanprovider.dart';
import 'dbworking.dart';
import 'model.dart';

class AttendanceScreen extends StatefulWidget {
  final Employee employee;
  const AttendanceScreen({Key? key, required this.employee}) : super(key: key);

  @override
  _AttendanceScreenState createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final DatabaseService _dbService = DatabaseService();
  List<Employee> _employees = [];
  List<Attendance> _todayAttendance = [];
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;

  // New controllers for hours
  final _workingHoursController = TextEditingController();
  final _overtimeHoursController = TextEditingController();
  String? _selectedStatus;
  double? _workingHours;
  double? _overtimeHours;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _workingHoursController.dispose();
    _overtimeHoursController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    List<Employee> employees;

    if (widget.employee != null) {
      employees = [widget.employee!];
    } else {
      employees = await _dbService.getEmployees();
    }

    final todayAttendance = await _dbService.getAttendanceForDate(_selectedDate);

    setState(() {
      _employees = employees;
      _todayAttendance = todayAttendance;
      _isLoading = false;
      _selectedStatus = null;
      _workingHoursController.clear();
      _overtimeHoursController.clear();
    });
  }

  Attendance? _getAttendanceForEmployee(String employeeId) {
    try {
      return _todayAttendance.firstWhere(
            (a) => a.employeeId == employeeId,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _markAttendance(Employee employee) async {
    if (_selectedStatus == null) return;

    // Validate working hours for present status
    if (_selectedStatus == 'present') {
      if (_workingHoursController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEnglish
                  ? 'Please enter working hours'
                  : 'براہ کرم کام کے گھنٹے درج کریں',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      _workingHours = double.tryParse(_workingHoursController.text);
      if (_workingHours == null || _workingHours! <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEnglish
                  ? 'Please enter valid working hours'
                  : 'درست کام کے گھنٹے درج کریں',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Parse overtime if entered
      if (_overtimeHoursController.text.isNotEmpty) {
        _overtimeHours = double.tryParse(_overtimeHoursController.text);
        if (_overtimeHours == null || _overtimeHours! < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isEnglish
                    ? 'Please enter valid overtime hours'
                    : 'درست اوور ٹائم گھنٹے درج کریں',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
      }
    }

    final oldAttendance = _getAttendanceForEmployee(employee.id!);

    final attendance = oldAttendance ??
        Attendance(
          employeeId: employee.id!,
          employeeName: employee.name,
          date: _selectedDate,
          status: _selectedStatus!,
        );

    attendance.status = _selectedStatus!;

    // Set working hours and overtime for present status
    if (_selectedStatus == 'present') {
      attendance.workingHours = _workingHours;
      attendance.overtimeHours = _overtimeHours;
      attendance.overtimeRate = employee.overtimeRate;
    } else {
      attendance.workingHours = null;
      attendance.overtimeHours = null;
    }

    await _dbService.markAttendance(attendance);
    await _loadData();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isEnglish
              ? "${_getStatusText(_selectedStatus!)} marked for ${employee.name}"
              : "${employee.name} کے لیے ${_getStatusText(_selectedStatus!)} نشان زد ہو گیا",
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadData();
    }
  }

  void _updateStatus(String? status) {
    setState(() {
      _selectedStatus = status;
      if (status != 'present') {
        _workingHoursController.clear();
        _overtimeHoursController.clear();
      }
    });
  }

  // ---------- LANGUAGE HELPERS ----------
  bool get _isEnglish => Provider.of<LanguageProvider>(context, listen: false).isEnglish;

  String _text(String eng, String urdu) {
    return _isEnglish ? eng : urdu;
  }

  TextStyle _style({double size = 14, FontWeight weight = FontWeight.normal}) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      fontFamily: Provider.of<LanguageProvider>(context, listen: false).fontFamily,
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'present':
        return _text('Present', 'حاضر');
      case 'absent':
        return _text('Absent', 'غیر حاضر');
      case 'half-day':
        return _text('Half Day', 'نصف دن');
      default:
        return _text('Not Marked', 'نشان زد نہیں');
    }
  }

  // ---------- ATTENDANCE CARD ----------
  Widget _buildAttendanceCard(Employee employee) {
    final attendance = _getAttendanceForEmployee(employee.id!);
    final current = attendance?.status ?? 'not-marked';

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(employee.name, style: _style(size: 18, weight: FontWeight.bold)),
            Text(employee.address, style: _style(size: 13)),
            Text(
              _text("Salary", "تنخواہ") + ": PKR ${employee.basicSalary}",
              style: _style(size: 13),
            ),

            // Show standard hours and overtime rate if available
            if (employee.standardWorkingHours != null)
              Text(
                _text("Standard Hours", "معیاری گھنٹے") + ": ${employee.standardWorkingHours}",
                style: _style(size: 12, weight: FontWeight.w500),
              ),

            if (attendance != null && attendance.workingHours != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 4),
                  Text(
                    _text("Worked: ", "کام کیا: ") +
                        "${attendance.workingHours!.toStringAsFixed(1)} hrs",
                    style: _style(size: 12, weight: FontWeight.w500),
                  ),
                  if (attendance.overtimeHours != null && attendance.overtimeHours! > 0)
                    Text(
                      _text("Overtime: ", "اوور ٹائم: ") +
                          "${attendance.overtimeHours!.toStringAsFixed(1)} hrs",
                      style: _style(size: 12, weight: FontWeight.w500,),
                    ),
                ],
              ),

            const SizedBox(height: 12),

            Text(
              _getStatusText(current),
              style: _style(weight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            // Status buttons
            Row(
              children: [
                _buildStatusButton(
                  label: "Present",
                  urdu: "حاضر",
                  status: "present",
                  current: current,
                  employee: employee,
                ),
                const SizedBox(width: 6),
                _buildStatusButton(
                  label: "Absent",
                  urdu: "غیر حاضر",
                  status: "absent",
                  current: current,
                  employee: employee,
                ),
                const SizedBox(width: 6),
                _buildStatusButton(
                  label: "Half Day",
                  urdu: "نصف دن",
                  status: "half-day",
                  current: current,
                  employee: employee,
                ),
              ],
            ),

            // Hours input for present status
            if (_selectedStatus == 'present' && current != 'present')
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  children: [
                    TextField(
                      controller: _workingHoursController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _text("Working Hours", "کام کے گھنٹے"),
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.access_time),
                      ),
                      autofocus: true,
                    ),
                    SizedBox(height: 8),
                    TextField(
                      controller: _overtimeHoursController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _text("Overtime Hours (Optional)", "اوور ٹائم گھنٹے (اختیاری)"),
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.timer),
                      ),
                    ),
                    if (employee.overtimeRate != null)
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          _text(
                            'Overtime Rate: PKR ${employee.overtimeRate!.toStringAsFixed(2)}/hour',
                            'اوور ٹائم ریٹ: ${employee.overtimeRate!.toStringAsFixed(2)} روپے/گھنٹہ',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => _markAttendance(employee),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        minimumSize: Size(double.infinity, 45),
                      ),
                      child: Text(
                        _text("Submit", "جمع کروائیں"),
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusButton({
    required String label,
    required String urdu,
    required String status,
    required String current,
    required Employee employee,
  }) {
    final selected = status == current;

    return Expanded(
      child: ElevatedButton(
        onPressed: () {
          if (status == 'present') {
            _updateStatus(status);
          } else {
            _selectedStatus = status;
            _markAttendance(employee);
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: selected ? Colors.white : Colors.white.withOpacity(0.1),
          foregroundColor: Colors.black,
        ),
        child: Text(
          _text(label, urdu),
          style: _style(weight: selected ? FontWeight.bold : FontWeight.normal),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.employee != null
              ? _text("${widget.employee!.name} - Attendance", "${widget.employee!.name} - حاضری")
              : _text("Employee Attendance", "ملازمین کی حاضری"),
          style: _style(weight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.calendar_today),
            onPressed: _selectDate,
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _employees.isEmpty
          ? Center(
        child: Text(
          _text("No employees found", "کوئی ملازم نہیں ملا"),
          style: TextStyle(fontSize: 16),
        ),
      )
          : ListView.builder(
        itemCount: _employees.length,
        itemBuilder: (_, i) => _buildAttendanceCard(_employees[i]),
      ),
    );
  }
}