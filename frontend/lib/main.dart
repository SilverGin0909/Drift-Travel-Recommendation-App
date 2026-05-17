import 'package:flutter/material.dart';
import 'package:frontend/screens/signup.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: '[REDACTED_SECRET]',
    anonKey: '[REDACTED_SECRET]',
  );

  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: SignupPage()),
  );
}
