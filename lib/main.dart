  import 'package:firebase_core/firebase_core.dart';
  import 'package:flutter/material.dart';
import 'package:mughal_group_branch_two/Auth/login.dart';
import 'package:mughal_group_branch_two/Auth/register.dart';
  import 'package:provider/provider.dart';
  import 'Provider/bankprovider.dart';
  import 'Provider/customerprovider.dart';
  import 'Provider/employeeprovider.dart';
  import 'Provider/expenseprovider.dart';
  import 'Provider/filled provider.dart';
  import 'Provider/filleditemwiseledgerprovider.dart';
  import 'Provider/filledreportprovider.dart';
  import 'Provider/invoice provider.dart';
  import 'Provider/lanprovider.dart';
  import 'Provider/purchaseprovider.dart';
  import 'Provider/quotationPageprovider.dart';
import 'Provider/reportprovider.dart';
  import 'chequePayments/listofchequePayments.dart';
  import 'chequePayments/newchequelist.dart';
  import 'dashboard.dart';
  import 'firebase_options.dart';
  
  void main() async{
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => EmployeeProvider()),
          ChangeNotifierProvider(create: (_) => FilledProvider()),
          ChangeNotifierProvider(create: (_) => FilledCustomerReportProvider()),
          ChangeNotifierProvider(create: (_) => InvoiceProvider()),
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ChangeNotifierProvider(create: (_) => CustomerProvider()),
          ChangeNotifierProvider(create: (_) => ExpenseProvider()),
          ChangeNotifierProvider(create: (_) => BankProvider()),
          ChangeNotifierProvider(create: (_) => PurchaseProvider()),
          ChangeNotifierProvider(create: (_) => CheckPaymentProvider()),
          ChangeNotifierProvider(create: (_) => PaymentProvider()),
          ChangeNotifierProvider(create: (_) => CustomerReportProvider()),
          ChangeNotifierProvider(create: (_) => ItemsWiseLedgerProvider()),
          ChangeNotifierProvider(create: (_) => QuoteProvider()),
        ],
        child: const MyApp(),
      ),
    );
  }
  
  class MyApp extends StatelessWidget {
    const MyApp({super.key});
  
    @override
    Widget build(BuildContext context) {
  
      return Consumer<LanguageProvider>(
        builder: (context, languageProvider, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Dashboard(),
            theme: ThemeData(
              fontFamily: languageProvider.isEnglish ? 'Roboto' : 'JameelNoori',
            ),
          );
        },
      );
    }
  }