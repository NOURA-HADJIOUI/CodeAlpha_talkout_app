import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';
import 'auth_screen.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    void enter(bool signup) => Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => AuthScreen(signup: signup)));
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFFE9E3FF), Color(0xFFD4C8FA)],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            const Spacer(flex: 3),
            const Logo(size: 84),
            const SizedBox(height: 16),
            const Brand(size: 34),
            const SizedBox(height: 6),
            const Text('Connect  •  Chat  •  Share', style: TextStyle(color: kGrey, fontSize: 13)),
            const Spacer(flex: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kPrimary, shape: const StadiumBorder()),
                  onPressed: () => enter(true),
                  child: const Text('Get Started', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            TextButton(
              onPressed: () => enter(false),
              child: const Text('Log In', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}