import 'package:flutter/material.dart';
import 'models/chat.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/colors.dart';
import 'utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.restore();
  runApp(const TalkOutApp());
}

class TalkOutApp extends StatelessWidget {
  const TalkOutApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'TalkOut',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: kPrimary, primary: kPrimary),
          scaffoldBackgroundColor: Colors.white,
        ),
        home: store.loggedIn ? const HomeScreen() : const SplashScreen(),
      );
}