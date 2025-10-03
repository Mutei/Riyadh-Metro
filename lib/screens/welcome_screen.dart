// import 'package:flutter/material.dart';
// import 'package:lottie/lottie.dart';
//
// import '../localization/language_constants.dart';
// import '../main.dart';
//
// class WelcomeScreen extends StatelessWidget {
//   const WelcomeScreen({super.key});
//
//   Future<void> _toggleLanguage(BuildContext context) async {
//     final currentLocale = Localizations.localeOf(context);
//     final nextCode = isArabic(currentLocale) ? english : arabic;
//     final newLocale = await setLocale(nextCode);
//     MyApp.setLocale(context, newLocale);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final cs = Theme.of(context).colorScheme;
//
//     return Scaffold(
//       appBar: AppBar(
//         backgroundColor: Colors.transparent,
//         surfaceTintColor: Colors.transparent,
//         elevation: 0,
//         leading: IconButton(
//           tooltip: getTranslated(context, 'change_language'),
//           icon: const Icon(Icons.translate),
//           onPressed: () => _toggleLanguage(context),
//         ),
//       ),
//       body: Container(
//         decoration: BoxDecoration(
//           gradient: LinearGradient(
//             colors: [cs.primaryContainer.withOpacity(0.5), cs.surface],
//             begin: Alignment.topCenter,
//             end: Alignment.bottomCenter,
//           ),
//         ),
//         child: SafeArea(
//           child: Center(
//             child: Padding(
//               padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
//               child: ConstrainedBox(
//                 constraints: const BoxConstraints(maxWidth: 520),
//                 child: Column(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     AspectRatio(
//                       aspectRatio: 1.2,
//                       child: Lottie.asset(
//                         'assets/lottie/em_process_hiring.json',
//                         fit: BoxFit.contain,
//                       ),
//                     ),
//                     const SizedBox(height: 16),
//                     Text(
//                       getTranslated(context, "Welcome"),
//                       style:
//                           Theme.of(context).textTheme.headlineMedium?.copyWith(
//                                 fontWeight: FontWeight.w700,
//                               ),
//                       textAlign: TextAlign.center,
//                     ),
//                     const SizedBox(height: 8),
//                     Text(
//                       getTranslated(context, "Let's get you signed in!"),
//                       style: Theme.of(context).textTheme.bodyLarge?.copyWith(
//                             color:
//                                 Theme.of(context).colorScheme.onSurfaceVariant,
//                           ),
//                       textAlign: TextAlign.center,
//                     ),
//                     const SizedBox(height: 28),
//                     FilledButton(
//                       onPressed: () => Navigator.pushNamed(context, '/login'),
//                       child: Text(getTranslated(context, "Sign in!")),
//                     ),
//                     const SizedBox(height: 12),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
