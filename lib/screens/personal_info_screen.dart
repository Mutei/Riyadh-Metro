import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import '../constants/colors.dart';
import '../localization/language_constants.dart';

class PersonalInfoScreen extends StatefulWidget {
  const PersonalInfoScreen({super.key});

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  final _db = FirebaseDatabase.instance.ref();
  final _auth = FirebaseAuth.instance;

  bool _loading = true;
  Map<String, dynamic> _data = {};

  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  DateTime? _dob;
  String _gender = 'Male';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  String t(String key) {
    final s = getTranslated(context, key);
    return (s == null || s.isEmpty) ? key : s;
  }

  Future<void> _load() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('Not signed in'))));
        Navigator.of(context).pop();
        return;
      }

      final snap = await _db.child('App/User/$uid').get();
      final raw = (snap.value as Map?)?.map((k, v) => MapEntry('$k', v)) ?? {};

      setState(() {
        _data = Map<String, dynamic>.from(raw);
        _firstCtrl.text = (_data['FirstName'] ?? '').toString();
        _lastCtrl.text = (_data['LastName'] ?? '').toString();
        _phoneCtrl.text = (_data['PhoneNumber'] ?? '').toString();
        final dobStr = (_data['DateOfBirth'] ?? '').toString();
        _dob = _parseDob(dobStr);
        _gender = (_data['Gender'] ?? 'Male').toString();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${t('Failed to load')}: $e')));
    }
  }

  DateTime? _parseDob(String s) {
    if (s.isEmpty) return null;
    try {
      return DateTime.tryParse(s) ??
          DateFormat('yyyy-MM-dd').parse(s, true).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _fmtDob(DateTime? d) {
    if (d == null) return t('Not set');
    return DateFormat('d MMM yyyy').format(d);
  }

  Future<void> _pickDob() async {
    final initial = _dob ?? DateTime(2000, 1, 1);
    final first = DateTime(1950, 1, 1);
    final last = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: t('Select date of birth'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppColors.kPrimaryColor,
                  onPrimary: Colors.white,
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _dob = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _save() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    if (_firstCtrl.text.trim().isEmpty || _lastCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('Please enter your first and last name'))),
      );
      return;
    }
    if (_phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('Please enter your phone number'))),
      );
      return;
    }

    final update = <String, dynamic>{
      'FirstName': _firstCtrl.text.trim(),
      'LastName': _lastCtrl.text.trim(),
      'PhoneNumber': _phoneCtrl.text.trim(),
      'Gender': _gender,
      if (_dob != null)
        'DateOfBirth': DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS").format(
          DateTime(_dob!.year, _dob!.month, _dob!.day),
        ),
    };

    try {
      setState(() => _loading = true);
      await _db.child('App/User/$uid').update(update);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('Changes saved'))));
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${t('Failed to save')}: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom; // keyboard
    final sysBottom = MediaQuery.of(context).padding.bottom;

    // Space so items scroll above button/keyboard
    final listExtraBottom = (viewInsets > 0 ? viewInsets : sysBottom) + 84;

    return Scaffold(
      backgroundColor: AppColors.kBackGroundColor,
      appBar: AppBar(
        title: Text(t('Account')),
        backgroundColor: AppColors.kBackGroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(16, 12, 16, listExtraBottom),
            children: [
              _groupTitle(text, t('Name')),
              _card(children: [
                _editableTile(
                  title: t('First name'),
                  value: _firstCtrl.text,
                  onTap: () => _openTextEditor(
                    label: t('First name'),
                    controller: _firstCtrl,
                  ),
                ),
                const Divider(height: 1),
                _editableTile(
                  title: t('Last name'),
                  value: _lastCtrl.text,
                  onTap: () => _openTextEditor(
                    label: t('Last name'),
                    controller: _lastCtrl,
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _groupTitle(text, t('Phone number')),
              _card(children: [
                _editableTile(
                  title: t('Phone number'),
                  value: _phoneCtrl.text.isEmpty ? '—' : _phoneCtrl.text,
                  onTap: _openPhoneEditor,
                ),
              ]),
              const SizedBox(height: 12),
              _groupTitle(text, t('Date of Birth')),
              _card(children: [
                _editableTile(
                  title: t('Date of Birth'),
                  value: _fmtDob(_dob),
                  onTap: _pickDob,
                ),
              ]),
              const SizedBox(height: 12),
              _groupTitle(text, t('Gender')),
              _card(children: [
                _editableTile(
                  title: t('Gender'),
                  value: _gender,
                  onTap: _openGenderPicker,
                ),
              ]),
              const SizedBox(height: 12),
              _groupTitle(text, t('Email')),
              _card(children: [
                ListTile(
                  title: Text(
                    (_data['Email'] ?? '').toString(),
                    style: text.bodyLarge,
                  ),
                  subtitle: Text(
                    t('Email is not editable'),
                    style: text.bodySmall?.copyWith(color: Colors.black54),
                  ),
                  trailing: const Icon(Icons.lock_outline_rounded),
                ),
              ]),
              const SizedBox(height: 20),
              if (_data['CustomerId'] != null || _data['SerialNumber'] != null)
                _card(children: [
                  if (_data['CustomerId'] != null)
                    ListTile(
                      title: Text(
                        '${t('Customer ID')}: ${_data['CustomerId']}',
                        style: text.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (_data['SerialNumber'] != null)
                    ListTile(
                      title: Text(
                        '${t('Serial number')}: ${_data['SerialNumber']}',
                        style: text.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                ]),
            ],
          ),

          // Floating save button that clears the keyboard area
          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            left: 16,
            right: 16,
            bottom: 16 + (viewInsets > 0 ? viewInsets : sysBottom),
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.kPrimaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                onPressed: _loading ? null : _save,
                child: Text(
                  t('Save changes'),
                  style: text.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),

          if (_loading)
            const Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: ColoredBox(
                  color: Colors.transparent,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- UI helpers ----------
  Widget _groupTitle(TextTheme text, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 6),
      child: Text(
        title,
        style: text.titleMedium?.copyWith(
          color: Colors.black54,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: children),
    );
  }

  Widget _editableTile({
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(value.isEmpty ? '—' : value),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  Future<void> _openTextEditor({
    required String label,
    required TextEditingController controller,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true, // keyboard-aware
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final text = Theme.of(ctx).textTheme;
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style:
                        text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => Navigator.of(ctx).pop(),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF8F8F8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.black12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.kPrimaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(t('Done')),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    setState(() {}); // refresh visible value
  }

  Future<void> _openPhoneEditor() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true, // keyboard-aware
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final text = Theme.of(ctx).textTheme;
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t('Phone number'),
                    style:
                        text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => Navigator.of(ctx).pop(),
                  decoration: InputDecoration(
                    prefixText: '+966 ',
                    filled: true,
                    fillColor: const Color(0xFFF8F8F8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.black12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.kPrimaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(t('Done')),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    setState(() {});
  }

  Future<void> _openGenderPicker() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final items = ['Male', 'Female'];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              const SizedBox(height: 10),
              ...items.map(
                (g) => ListTile(
                  title: Text(t(g)),
                  trailing: _gender == g
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(g),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      setState(() => _gender = picked);
    }
  }
}
