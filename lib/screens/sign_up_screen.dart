import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../authentication_methods/sign_up_service.dart';
import '../constants/colors.dart';
import '../localization/language_constants.dart';

import 'main_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _svc = SignUpService();

  // Controllers
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  // Optional
  String? _gender; // Male / Female
  DateTime? _dob;

  bool _obscure = true;
  bool _agreeTerms = false;
  bool _busy = false;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    return _formKey.currentState?.validate() == true && _agreeTerms;
  }

  InputDecoration _dec(BuildContext ctx, String hintKey) =>
      InputDecoration(hintText: getTranslated(ctx, hintKey));

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 100, now.month, now.day);
    final lastDate = DateTime(now.year - 10, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 20),
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            dialogTheme: const DialogTheme(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _submit() async {
    if (!_isFormValid || _busy) return;
    setState(() => _busy = true);

    try {
      final cred = await _svc.signUpAndSave(
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        phoneNumber: _phoneCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        gender: _gender,
        dateOfBirth: _dob,
      );

      final firstName = _firstNameCtrl.text.trim();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => MainScreen(
              firstName: firstName,
              emailVerified: cred.user?.emailVerified ?? false,
            ),
          ),
          (_) => false,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(getTranslated(context, 'signup.verificationNotice')),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      final msg = _mapAuthError(e.code, e.message);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${getTranslated(context, 'signup.failed')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _mapAuthError(String code, String? message) {
    switch (code) {
      case 'username-already-in-use':
        return getTranslated(context, 'signup.err.usernameInUse');
      case 'phone-already-in-use':
        return getTranslated(context, 'signup.err.phoneInUse');
      case 'email-already-in-use':
        return getTranslated(context, 'signup.err.emailInUse');
      case 'weak-password':
        return getTranslated(context, 'signup.err.weakPassword');
      default:
        return message ??
            '${getTranslated(context, 'signup.err.generic')} ($code).';
    }
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.kBackGroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Form(
                    key: _formKey,
                    onChanged: () => setState(() {}),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          onPressed:
                              _busy ? null : () => Navigator.pop(context),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Image.asset('assets/logo/darb_logo.jpeg',
                              width: 84, height: 84),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          getTranslated(context, 'signup.title'),
                          style: const TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 20),

                        // First Name
                        Text(getTranslated(context, 'signup.firstName.label'),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _firstNameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: _dec(context, 'signup.firstName.hint'),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? getTranslated(context, 'common.required')
                              : null,
                        ),
                        const SizedBox(height: 16),

                        // Last Name
                        Text(getTranslated(context, 'signup.lastName.label'),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _lastNameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: _dec(context, 'signup.lastName.hint'),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? getTranslated(context, 'common.required')
                              : null,
                        ),
                        const SizedBox(height: 16),

                        // Phone
                        Text(getTranslated(context, 'signup.phone.label'),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: _dec(context, 'signup.phone.hint'),
                          validator: (v) {
                            final t = v?.trim() ?? "";
                            if (t.isEmpty) {
                              return getTranslated(context, 'common.required');
                            }
                            if (t.length < 8) {
                              return getTranslated(
                                  context, 'signup.phone.invalid');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Username
                        Text(getTranslated(context, 'signup.username.label'),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _usernameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: _dec(context, 'signup.username.hint'),
                          validator: (v) {
                            final t = v?.trim() ?? "";
                            if (t.isEmpty) {
                              return getTranslated(context, 'common.required');
                            }
                            if (!RegExp(r'^[a-zA-Z0-9_\.]{3,}$').hasMatch(t)) {
                              return getTranslated(
                                  context, 'signup.username.rule');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Email (for verification)
                        Text(getTranslated(context, 'signup.email.label'),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: _dec(context, 'signup.email.hint'),
                          validator: (v) {
                            final t = v?.trim() ?? "";
                            if (t.isEmpty) {
                              return getTranslated(context, 'common.required');
                            }
                            final ok = RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
                                .hasMatch(t);
                            return ok
                                ? null
                                : getTranslated(
                                    context, 'signup.email.invalid');
                          },
                        ),
                        const SizedBox(height: 16),

                        // Gender (optional)
                        Text(getTranslated(context, 'signup.gender.label'),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _gender,
                          decoration: _dec(context, 'signup.gender.hint'),
                          items: [
                            DropdownMenuItem(
                                value: "Male",
                                child: Text(getTranslated(
                                    context, 'signup.gender.male'))),
                            DropdownMenuItem(
                                value: "Female",
                                child: Text(getTranslated(
                                    context, 'signup.gender.female'))),
                          ],
                          onChanged: (v) => setState(() => _gender = v),
                        ),
                        const SizedBox(height: 16),

                        // DOB (optional)
                        Text(getTranslated(context, 'signup.dob.label'),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: _pickDob,
                          borderRadius:
                              const BorderRadius.all(Radius.circular(14)),
                          child: InputDecorator(
                            decoration: _dec(context, 'signup.dob.hint'),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _dob == null
                                      ? getTranslated(
                                          context, 'signup.dob.hint')
                                      : "${_dob!.year}-${_two(_dob!.month)}-${_two(_dob!.day)}",
                                  style: TextStyle(
                                    color: _dob == null
                                        ? Colors.black45
                                        : Colors.black87,
                                  ),
                                ),
                                const Icon(Icons.calendar_today_outlined),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password
                        Text(getTranslated(context, 'signup.password.label'),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          decoration:
                              _dec(context, 'signup.password.hint').copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) {
                            final t = v ?? "";
                            if (t.isEmpty) {
                              return getTranslated(context, 'common.required');
                            }
                            if (t.length < 8) {
                              return getTranslated(
                                  context, 'signup.password.rule.length');
                            }
                            if (!RegExp(r'[A-Z]').hasMatch(t)) {
                              return getTranslated(
                                  context, 'signup.password.rule.upper');
                            }
                            if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]')
                                .hasMatch(t)) {
                              return getTranslated(
                                  context, 'signup.password.rule.special');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // Terms
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: _agreeTerms,
                              activeColor: AppColors.kPrimaryColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              onChanged: (v) =>
                                  setState(() => _agreeTerms = v ?? false),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                getTranslated(context, 'signup.terms'),
                                style: const TextStyle(fontSize: 13.5),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Button
                        FilledButton(
                          onPressed: (_isFormValid && !_busy) ? _submit : null,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            backgroundColor: AppColors.kPrimaryColor,
                            disabledBackgroundColor:
                                Colors.black.withOpacity(0.08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  getTranslated(
                                      context, 'signup.createAccount'),
                                  style: const TextStyle(fontSize: 16),
                                ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
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
