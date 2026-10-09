import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:mughal_group_branch_two/roznamchaPage.dart';
import 'package:mughal_group_branch_two/simplecashbook/simplecashbook.dart';
import 'package:mughal_group_branch_two/userspage.dart';
import 'package:mughal_group_branch_two/vendors/vendorchequepage.dart';
import 'package:mughal_group_branch_two/vendors/viewvendors.dart';
import 'package:provider/provider.dart';
import 'Auth/login.dart';
import 'BatchPages/batch_management_page.dart';
import 'Category/categorylistpage.dart';
import 'Category/categorymanagement.dart';
import 'Customer/customerlist.dart';
import 'DailyExpensesPages/viewexpensepage.dart';
import 'Employee/employeelist.dart';
import 'Filled/filledlist.dart';
import 'Filled/gatepasslist.dart';
import 'Filled/quotelist.dart';
import 'Filled/quotepage.dart';
import 'Mazdoori/Mazdoorlistpage.dart';
import 'NewEmployee/employeemainpage.dart';
import 'Purchase/Purchase Order page.dart';
import 'Purchase/purchaseorderlist.dart';
import 'Reminders/reminderslistpage.dart';
import 'Provider/lanprovider.dart';
import 'Reports/balancesummarypage.dart';
import 'Reports/ledgerselcttion.dart';
import 'Reports/reportselecttionpage.dart';
import 'bankmanagement/addbank.dart';
import 'cashbook/cashbook.dart';
import 'chequeManagement/chequeManagement.dart';
import 'chequePayments/newchequelist.dart';
import 'items/inandoutpage.dart';
import 'Purchase/purchaselistpage.dart';
import 'items/itemslistpage.dart';

// ─── NEW IMPORTS FOR CUSTOMER RETURN ───


class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int _mobileSelectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkReminders(context);
    });
  }

  void _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => LoginPage()),
            (Route<dynamic> route) => false,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logout failed: ${e.toString()}'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          languageProvider.isEnglish ? 'Asad Hamid' : 'ڈیش بورڈ',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: Color(0xFF1E293B),
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A65).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.language, color: Color(0xFFFF8A65)),
              onPressed: languageProvider.toggleLanguage,
              tooltip: languageProvider.isEnglish ? 'Switch to Urdu' : 'انگریزی میں تبدیل کریں',
            ),
          ),
        ],
      ),
      drawer: isDesktop ? null : Drawer(child: _buildSidebar(context, languageProvider)),
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(context, languageProvider),
          if (isDesktop) const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8F0)),
          Expanded(child: _buildContent(context, languageProvider)),
        ],
      ),
      bottomNavigationBar: isDesktop ? null : _buildBottomNavBar(languageProvider),
    );
  }

  Widget _buildBottomNavBar(LanguageProvider languageProvider) {
    return NavigationBar(
      selectedIndex: _mobileSelectedIndex,
      onDestinationSelected: (index) {
        setState(() => _mobileSelectedIndex = index);
        if (index == 1) _navigateTo(context, const LedgerSelection());
        if (index == 2) _navigateTo(context, UsersPage());
      },
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFFFF8A65).withOpacity(0.2),
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home, color: Color(0xFFFF8A65)),
          label: languageProvider.isEnglish ? 'Home' : 'ہوم',
        ),
        NavigationDestination(
          icon: const Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: const Icon(Icons.account_balance_wallet, color: Color(0xFFFF8A65)),
          label: languageProvider.isEnglish ? 'Transactions' : 'لین دین',
        ),
        NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings, color: Color(0xFFFF8A65)),
          label: languageProvider.isEnglish ? 'Settings' : 'ترتیبات',
        ),
      ],
    );
  }

  Widget _buildSidebar(BuildContext context, LanguageProvider languageProvider) {
    return Container(
      width: 280,
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Image.asset('assets/images/logo.png', height: 150, width: 150, fit: BoxFit.fill),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(color: Color(0xFFE2E8F0)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _sidebarItem(Icons.home_rounded, 'Home', 'ہوم', () => _navigateTo(context, const Dashboard()), languageProvider),
                _sidebarItem(Icons.notifications_active_rounded, 'Reminders', 'یاددہانی', () => _navigateTo(context, const ReminderListPage()), languageProvider),
                _sidebarItem(Icons.inventory_2_rounded, 'Items List', 'ٹوٹل آئٹمز', () => _navigateTo(context, ItemsListPage()), languageProvider),
                _sidebarItem(Icons.category_rounded, 'Category Management', 'کیٹاگوری منیجمنٹ', () => _navigateTo(context, ListCategoriesPage()), languageProvider),
                _sidebarItem(Icons.shopping_bag_rounded, 'Batch Management', 'بیچ منیجمنٹ', () => _navigateTo(context, BatchManagementPage()), languageProvider),
                _sidebarItem(Icons.shopping_cart_checkout_rounded, 'Purchase', 'خریداری', () => _navigateTo(context, PurchaseListPage()), languageProvider),
                _sidebarItem(Icons.storefront_rounded, 'Vendors', 'بیچنے والا', () => _navigateTo(context, const ViewVendorsPage()), languageProvider),
                _sidebarItem(Icons.account_balance_wallet_rounded, 'Transactions', 'لین دین', () => _navigateTo(context, const LedgerSelection()), languageProvider),
                _sidebarItem(Icons.account_balance_rounded, 'Bank Management', 'بینک مینجمنٹ', () => _navigateTo(context, BankManagementPage()), languageProvider),
                _sidebarItem(Icons.request_quote_rounded, 'Customer Cheques', 'کسٹمر چیک مینجمنٹ', () => _navigateTo(context, ChequeManagementPage()), languageProvider),
                _sidebarItem(Icons.receipt_long_rounded, 'Vendor Cheques', 'ونڈر چیک مینجمنٹ', () => _navigateTo(context, VendorChequesPage()), languageProvider),
                _sidebarItem(Icons.menu_book_rounded, 'Cash Book', 'کیش بک', () => _navigateTo(context, CashbookPage()), languageProvider),
                _sidebarItem(Icons.book_rounded, 'Simple Cash Book', 'سمپل کیش بک', () => _navigateTo(context, SimpleCashbookPage()), languageProvider),
                _sidebarItem(Icons.assignment_rounded, 'Roznamcha', 'روزنامچہ', () => _navigateTo(context, const Roznamchapage()), languageProvider),
                _sidebarItem(Icons.swap_horiz_rounded, 'Item In & Out', 'سٹاک رپورٹ', () => _navigateTo(context, ItemTransactionReportPage()), languageProvider),
                _sidebarItem(Icons.settings_rounded, 'Settings', 'ترتیبات', () => _navigateTo(context, UsersPage()), languageProvider),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: () => _logout(context),
              icon: const Icon(Icons.logout_rounded, color: Colors.white),
              label: Text(languageProvider.isEnglish ? 'Logout' : 'لاگ آوٹ', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarSectionHeader(String en, String ur, LanguageProvider lang) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Text(
        lang.isEnglish ? en : ur,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _sidebarDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Divider(color: Color(0xFFE2E8F0)),
    );
  }

  Widget _sidebarItem(IconData icon, String en, String ur, VoidCallback onTap, LanguageProvider lang) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        hoverColor: const Color(0xFFF1F5F9),
        leading: Icon(icon, color: const Color(0xFF64748B), size: 22),
        title: Text(
          lang.isEnglish ? en : ur,
          style: const TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w600, fontSize: 14),
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildContent(BuildContext context, LanguageProvider languageProvider) {
    final dashboardItems = [

      // ─── EXISTING CARDS ───
      {'icon': Icons.receipt_long, 'titleEn': 'Gate Pass', 'titleUr': 'گیٹ پاس', 'color': const Color(0xFF8B5CF6), 'page': QuotationListPage()},
      {'icon': Icons.inventory_2, 'titleEn': 'Quotations', 'titleUr': 'Quotations', 'color': const Color(0xFFF59E0B), 'page': QuoteListPageOrg()},
      {'icon': Icons.inventory_2, 'titleEn': 'Invoice', 'titleUr': 'انوائس اندراج', 'color': const Color(0xFFF59E0B), 'page': filledListpage()},
      {'icon': Icons.inventory_2, 'titleEn': 'Mazdoori', 'titleUr': 'مزدوری', 'color': const Color(0xFFF59E0B), 'page': MazdoorListPage()},
      {'icon': Icons.money_off, 'titleEn': 'Expenses', 'titleUr': 'اخراجات', 'color': const Color(0xFFEF4444), 'page': ViewExpensesPage()},
      {'icon': Icons.engineering, 'titleEn': 'Employee', 'titleUr': 'ورکر', 'color': const Color(0xFF10B981), 'page': HomeScreen()},
      {'icon': Icons.groups, 'titleEn': 'Customers', 'titleUr': 'کسٹمرز', 'color': const Color(0xFF3B82F6), 'page': CustomerList()},
      {'icon': Icons.account_balance_wallet, 'titleEn': 'View Ledger', 'titleUr': 'کھاتہ دیکھیں', 'color': const Color(0xFF14B8A6), 'page': const LedgerSelection()},
      {'icon': Icons.analytics, 'titleEn': 'Reports', 'titleUr': 'رپورٹس', 'color': const Color(0xFF6366F1), 'page': const ReportsPage()},
      {'icon': Icons.pie_chart, 'titleEn': 'Balance Summary', 'titleUr': 'بیلنس سمری', 'color': const Color(0xFFEC4899), 'page': EnhancedTransactionsPage()},
      {'icon': Icons.settings, 'titleEn': 'Settings', 'titleUr': 'ترتیبات', 'color': const Color(0xFF64748B), 'page': UsersPage()},
    ];

    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF8A65), Color(0xFFFFB74D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF8A65).withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                languageProvider.isEnglish ? 'Welcome Back!' : 'خوش آمدید!',
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                languageProvider.isEnglish
                    ? 'Manage your business efficiently.'
                    : 'اپنے گیس اپلائنسز کے کاروبار کا مؤثر طریقے سے انتظام کریں۔',
                style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 16),
              ),
            ],
          ),
        ),

        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
              childAspectRatio: 1.1,
            ),
            itemCount: dashboardItems.length,
            itemBuilder: (context, index) {
              final item = dashboardItems[index];
              return _buildDashboardCard(
                item['icon'] as IconData,
                languageProvider.isEnglish ? item['titleEn'] as String : item['titleUr'] as String,
                item['color'] as Color,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => item['page'] as Widget)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardCard(IconData icon, String title, Color color, VoidCallback onTap) {
    return HoverableCard(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF94A3B8).withOpacity(0.15),
              blurRadius: 12,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkReminders(BuildContext context) async {
    final ref = FirebaseDatabase.instance.ref().child('reminders');
    final snapshot = await ref.get();

    if (!snapshot.exists || !mounted) return;

    final today = DateTime.now();
    final Map reminders = snapshot.value as Map;
    List<Map<String, dynamic>> alertsToShow = [];

    for (var entry in reminders.entries) {
      final reminder = entry.value;
      if (reminder['showAlert'] == true) {
        DateTime reminderDate = DateTime.parse(reminder['date']);
        bool isDueOrPast = !reminderDate.isAfter(today);

        if (isDueOrPast) {
          alertsToShow.add({
            'title': reminder['title'],
            'date': reminderDate,
          });
        }
      }
    }

    if (alertsToShow.isNotEmpty && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.notification_important, color: Colors.redAccent, size: 28),
              SizedBox(width: 10),
              Text("Reminders Due", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: alertsToShow.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final reminder = alertsToShow[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(reminder['title'], style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    "Due: ${reminder['date'].toLocal().toString().split(' ')[0]}",
                    style: const TextStyle(color: Colors.grey),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF8A65)),
              child: const Text("Close", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }
}

// Custom Widget to handle smooth Hover scale effect
class HoverableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const HoverableCard({super.key, required this.child, required this.onTap});

  @override
  State<HoverableCard> createState() => _HoverableCardState();
}

class _HoverableCardState extends State<HoverableCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          transform: Matrix4.identity()..scale(_isHovered ? 1.05 : 1.0),
          child: widget.child,
        ),
      ),
    );
  }
}