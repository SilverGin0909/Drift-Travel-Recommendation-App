import 'package:frontend/screens/chatbot.dart';
import 'package:frontend/screens/login.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:frontend/widgets/custom_toast.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final TextEditingController username = TextEditingController();
  final TextEditingController email = TextEditingController();
  final TextEditingController password = TextEditingController();
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFFAFAFA),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Create Account',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),

                const SizedBox(height: 40),

                TextField(
                  controller: username,
                  decoration: InputDecoration(
                    hintText: 'Enter your name',
                    hintStyle: GoogleFonts.poppins(
                      color: const Color(0x90000000),
                      fontSize: 15,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(
                        color: Color(0xFF03A6FF),
                        width: 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(
                        color: Color(0xFF03A6FF),
                        width: 2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                TextField(
                  controller: email,
                  decoration: InputDecoration(
                    hintText: 'Enter your email',
                    hintStyle: GoogleFonts.poppins(
                      color: const Color(0x90000000),
                      fontSize: 15,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(5),
                      borderSide: const BorderSide(
                        color: Color(0xFF03A6FF),
                        width: 2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(
                        color: Color(0xFF03A6FF),
                        width: 2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                TextField(
                  controller: password,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: 'Enter your password',
                    hintStyle: GoogleFonts.poppins(
                      color: const Color(0x90000000),
                      fontSize: 15,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    suffixIcon: Listener(
                      onPointerDown: (_) {
                        setState(() {
                          _obscurePassword = false;
                        });
                      },
                      onPointerUp: (_) {
                        setState(() {
                          _obscurePassword = true;
                        });
                      },
                      onPointerCancel: (_) {
                        setState(() {
                          _obscurePassword = true;
                        });
                      },
                      child: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: const Color(0x90000000),
                        ),
                        onPressed: () {},
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(5),
                      borderSide: const BorderSide(
                        color: Color(0xFF03A6FF),
                        width: 2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(
                        color: Color(0xFF03A6FF),
                        width: 2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Color(0xFF03A6FF),
                      padding: EdgeInsets.symmetric(
                        horizontal: 90,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadiusGeometry.circular(16),
                        side: BorderSide(color: Color(0xFF03A6FF), width: 1.5),
                      ),
                    ),
                    onPressed: () {
                      signUpUser();
                    },
                    child: Text(
                      'Register',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 4),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Already have an account?",
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.black87,
                      ),
                    ),

                    SizedBox(width: 8),

                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => LoginPage()),
                        );
                      },
                      child: Text(
                        'Sign In',
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF0079DD),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.underline,
                          decorationThickness: 1.7,
                          height: 4,
                          decorationColor: const Color(0xFF0079DD),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> signUpUser() async {
    final localContext = context;
    final usernameText = username.text.trim();
    final emailText = email.text.trim();
    final passwordText = password.text;

    if (usernameText.isEmpty) {
      CustomToast.show(context, "Username cannot be empty");
      return;
    }

    if (emailText.isEmpty) {
      CustomToast.show(context, "Email cannot be empty");
      return;
    }

    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@gmail\.com$');
    if (!emailRegex.hasMatch(emailText)) {
      CustomToast.show(context, "Please enter a valid Gmail address (ending in @gmail.com)");
      return;
    }

    if (passwordText.isEmpty) {
      CustomToast.show(context, "Password cannot be empty");
      return;
    }

    if (passwordText.length < 8) {
      CustomToast.show(context, "Password must be at least 8 characters long");
      return;
    }

    if (!passwordText.contains(RegExp(r'[A-Z]'))) {
      CustomToast.show(context, "Password must contain at least one uppercase letter");
      return;
    }

    if (!passwordText.contains(RegExp(r'[a-z]'))) {
      CustomToast.show(context, "Password must contain at least one lowercase letter");
      return;
    }

    if (!passwordText.contains(RegExp(r'[^a-zA-Z0-9]'))) {
      CustomToast.show(context, "Password must contain at least one symbol");
      return;
    }

    if (!passwordText.contains(RegExp(r'[0-9]'))) {
      CustomToast.show(context, "Password must contain at least one number");
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: emailText,
        password: passwordText,
        data: {'username': usernameText},
      );

      if (localContext.mounted) Navigator.pop(localContext);

      if (response.user != null) {
        if (localContext.mounted) {
          CustomToast.show(localContext, "Signup successful! Please check your email for confirmation.");
          Navigator.pushReplacement(
            localContext,
            MaterialPageRoute(builder: (context) => const Chatbot()),
          );
        }
      }
    } catch (e) {
      if (localContext.mounted) {
        Navigator.pop(localContext); // Remove loading indicator
        CustomToast.show(localContext, "Signup failed: ${e.toString()}");
      }
    }
  }
}
