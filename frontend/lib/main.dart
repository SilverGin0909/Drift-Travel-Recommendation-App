import 'package:flutter/material.dart';
import 'package:frontend/screens/signup.dart';
import 'package:frontend/screens/chatbot.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load the .env variables
  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  final prefs = await SharedPreferences.getInstance();
  final bool rememberMe = prefs.getBool('remember_me') ?? false;
  final session = Supabase.instance.client.auth.currentSession;

  Widget initialScreen;
  if (rememberMe && session != null) {
    initialScreen = const Chatbot();
  } else {
    // If not remembered, log out from Supabase to prevent auto-login
    if (session != null) {
      await Supabase.instance.client.auth.signOut();
    }
    initialScreen = const SignupPage();
  }

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false, 
      home: initialScreen,
    ),
  );
}
