import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  final bool signup;
  const AuthScreen({super.key, this.signup = true});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool signup = widget.signup;
  bool busy = false;
  String? error;
  final user = TextEditingController();
  final name = TextEditingController();
  final pass = TextEditingController();
  late final server = TextEditingController(text: store.serverUrl);

  Future<void> _submit() async {
    final u = user.text.trim(), p = pass.text, n = name.text.trim();
    if (u.isEmpty || p.isEmpty || (signup && n.isEmpty)) {
      setState(() => error = 'Please fill in all fields');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    store.serverUrl = server.text.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      await store.auth(signup, u, p, n);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false);
      return;
    } catch (e) {
      if (mounted) {
        setState(() => error = e is String ? e : 'Cannot reach the server. Check the server address below.');
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _field(TextEditingController c, String label, {bool obscure = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: obscure,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: kBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(children: [
              const SizedBox(height: 24),
              const Logo(size: 64),
              const SizedBox(height: 12),
              const Brand(size: 28),
              const SizedBox(height: 6),
              Text(signup ? 'Create your account' : 'Welcome back', style: const TextStyle(color: kGrey)),
              const SizedBox(height: 28),
              if (signup) _field(name, 'Your name'),
              _field(user, 'Username'),
              _field(pass, 'Password', obscure: true),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(error!, style: const TextStyle(color: Color(0xFFDC2626))),
                ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kPrimary, shape: const StadiumBorder()),
                  onPressed: busy ? null : _submit,
                  child: busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Text(signup ? 'Sign up' : 'Log in', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  signup = !signup;
                  error = null;
                }),
                child: Text(signup ? 'Already have an account? Log in' : 'New here? Create an account',
                    style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600)),
              ),
              ExpansionTile(
                title: const Text('Server settings', style: TextStyle(fontSize: 14, color: kGrey)),
                shape: const Border(),
                children: [
                  _field(server, 'Server address (e.g. http://192.168.1.20:3000)'),
                ],
              ),
            ]),
          ),
        ),
      );
}