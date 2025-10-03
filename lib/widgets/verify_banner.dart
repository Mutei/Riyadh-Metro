import 'package:flutter/material.dart';

class VerifyBanner extends StatelessWidget {
  final VoidCallback onResend;
  const VerifyBanner({required this.onResend});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.yellow.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.yellow.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Please verify your email to activate your account.',
              style: TextStyle(fontSize: 13.5),
            ),
          ),
          TextButton(
            onPressed: onResend,
            child: const Text('Resend'),
          ),
        ],
      ),
    );
  }
}
