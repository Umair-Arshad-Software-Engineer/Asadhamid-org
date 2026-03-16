import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Provider/lanprovider.dart';
import 'addemployee.dart';
import 'employeelistpage.dart';


class HomeScreen extends StatelessWidget {

  @override
  Widget build(BuildContext context) {

    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.isEnglish ? 'Employee Management' : 'ملازمین کی منجمنٹ'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 5,
          childAspectRatio: 1,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            _buildMenuCard(
              context,
              // 'Add Employee',
              lang.isEnglish ? 'Add Employee' : 'ملازمین کو ایڈ کریں',
              Icons.person_add,
              Colors.green,
                  () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AddEmployeeScreen()),
              ),
            ),
            _buildMenuCard(
              context,
              // 'Employee List',
              lang.isEnglish ? 'Employee ؒList' : 'ملازمین فہرست',
              Icons.people,
              Colors.blue,
                  () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => EmployeeListScreen()),
              ),
            ),
            // _buildMenuCard(
            //   context,
            //   'Mark Attendance',
            //   Icons.calendar_today,
            //   Colors.orange,
            //       () => Navigator.push(
            //     context,
            //     MaterialPageRoute(builder: (context) => AttendanceScreen()),
            //   ),
            // ),
            // _buildMenuCard(
            //   context,
            //   'Calculate Salary',
            //   Icons.calculate,
            //   Colors.purple,
            //       () => Navigator.push(
            //     context,
            //     MaterialPageRoute(builder: (context) => SalaryCalculationScreen()),
            //   ),
            // ),
            // Add this to your GridView in HomeScreen
            // _buildMenuCard(
            //   context,
            //   'Salary History',
            //   Icons.history,
            //   Colors.brown,
            //       () => Navigator.push(
            //     context,
            //     MaterialPageRoute(builder: (context) => SalaryHistoryScreen()),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(
      BuildContext context,
      String title,
      IconData icon,
      Color color,
      VoidCallback onTap,
      ) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 50, color: color),
            SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}