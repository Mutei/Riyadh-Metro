import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../authentication_methods/login_method.dart';
import '../constants/colors.dart';
import '../extension/sized_box_extension.dart';
import '../localization/language_constants.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController identifierController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final _login = LoginService();

  bool obscurePassword = true;
  bool _busy = false;

  @override
  void dispose() {
    identifierController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final id = identifierController.text.trim();
    final pw = passwordController.text;

    if (id.isEmpty || pw.isEmpty) {
      _toast(getTranslated(context, 'login.emptyFields'));
      return;
    }

    setState(() => _busy = true);
    try {
      final cred = await _login.loginWithIdentifier(
        identifier: id,
        password: pw,
      );

      // Enforce email verification before proceeding
      await cred.user?.reload();
      final verified = cred.user?.emailVerified ?? false;

      if (!verified) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(getTranslated(context, 'login.verifyEmailTitle')),
            content: Text(getTranslated(context, 'login.verifyEmailBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(getTranslated(context, 'common.close')),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await FirebaseAuth.instance
                        .createUserWithEmailAndPassword(
                          email: cred.user!.email!,
                          password: pw,
                        )
                        .catchError((_) {});
                  } catch (_) {}
                  try {
                    await cred.user?.sendEmailVerification();
                  } catch (_) {}
                  if (ctx.mounted) Navigator.pop(ctx);
                  _toast(getTranslated(context, 'login.verificationSent'));
                },
                child: Text(getTranslated(context, 'common.resend')),
              ),
            ],
          ),
        );
        return;
      }

      // Success → navigate
      if (!mounted) return;

      final firstNameGuess =
          (cred.user?.displayName?.split(' ').first ?? '').isNotEmpty
              ? cred.user!.displayName!.split(' ').first
              : (cred.user?.email?.split('@').first ??
                  getTranslated(context, 'common.user'));

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => MainScreen(
            firstName: firstNameGuess,
            emailVerified: true,
          ),
        ),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      _toast(_mapAuthError(e));
    } catch (e) {
      _toast('${getTranslated(context, 'login.failed')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-input':
        return getTranslated(context, 'login.err.invalidInput');
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return getTranslated(context, 'login.err.incorrect');
      case 'too-many-requests':
        return getTranslated(context, 'login.err.tooMany');
      case 'user-disabled':
        return getTranslated(context, 'login.err.disabled');
      default:
        return '${getTranslated(context, 'login.err.generic')} (${e.code}).';
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: theme.textTheme.bodyLarge?.color,
    );
    final titleStyle = TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w600,
      color: theme.textTheme.headlineSmall?.color,
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor, // theme-aware
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      10.kH,
                      Center(
                        child: Image.asset(
                          'assets/logo/darb_logo.jpeg',
                          width: 100,
                          height: 100,
                        ),
                      ),
                      10.kH,
                      Text(
                        getTranslated(context, 'login.title'),
                        style: titleStyle,
                      ),
                      24.kH,
                      Text(
                        getTranslated(context, 'login.identifier.label'),
                        style: labelStyle,
                      ),
                      8.kH,
                      TextField(
                        controller: identifierController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          hintText:
                              getTranslated(context, 'login.identifier.hint'),
                        ),
                      ),
                      16.kH,
                      Text(
                        getTranslated(context, 'login.password.label'),
                        style: labelStyle,
                      ),
                      8.kH,
                      TextField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _busy ? null : _handleLogin(),
                        decoration: InputDecoration(
                          hintText:
                              getTranslated(context, 'login.password.hint'),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () => setState(
                                () => obscurePassword = !obscurePassword),
                          ),
                        ),
                      ),
                      8.kH,
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : () {}, // TODO
                          child: Text(
                            getTranslated(context, 'login.forgotPassword'),
                          ),
                        ),
                      ),
                      16.kH,
                      ElevatedButton(
                        onPressed: _busy ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.kPrimaryColor,
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                getTranslated(context, 'login.signIn'),
                                // White text works well on brand green in both themes
                                style: const TextStyle(color: Colors.white),
                              ),
                      ),
                      Center(
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.pushNamed(context, '/register'),
                          child: Text.rich(
                            TextSpan(
                              text: getTranslated(context, 'login.noAccountQ'),
                              children: [
                                TextSpan(
                                  text: getTranslated(context, 'login.newUser'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
