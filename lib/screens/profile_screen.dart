import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.userId,
    required this.initialProfile,
    this.isInitialSetup = false,
  });

  final String userId;
  final UserModel? initialProfile;
  final bool isInitialSetup;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  late final TextEditingController _weeksController;
  late final TextEditingController _bloodGroupController;
  late final TextEditingController _hbController;
  late final TextEditingController _wbcController;
  late final TextEditingController _bloodPressureController;
  late final TextEditingController _sugarController;
  late final TextEditingController _weightController;
  late final TextEditingController _medicalHistoryController;
  late final TextEditingController _symptomsController;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  bool _isSigningOut = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _ageController = TextEditingController();
    _weeksController = TextEditingController();
    _bloodGroupController = TextEditingController();
    _hbController = TextEditingController();
    _wbcController = TextEditingController();
    _bloodPressureController = TextEditingController();
    _sugarController = TextEditingController();
    _weightController = TextEditingController();
    _medicalHistoryController = TextEditingController();
    _symptomsController = TextEditingController();
    _fillControllers(widget.initialProfile);
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialProfile?.updatedAt !=
        oldWidget.initialProfile?.updatedAt) {
      _fillControllers(widget.initialProfile);
    }
  }

  void _fillControllers(UserModel? profile) {
    _nameController.text = profile?.name ?? '';
    _ageController.text = profile != null && profile.age > 0
        ? profile.age.toString()
        : '';
    _weeksController.text = profile != null && profile.pregnancyWeeks >= 0
        ? profile.pregnancyWeeks.toString()
        : '';
    _bloodGroupController.text = profile?.bloodGroup ?? '';
    _hbController.text = _formatDouble(profile?.hemoglobin);
    _wbcController.text = _formatDouble(profile?.wbc);
    _bloodPressureController.text = profile?.bloodPressure ?? '';
    _sugarController.text = _formatDouble(profile?.sugarLevel);
    _weightController.text = _formatDouble(profile?.weight);
    _medicalHistoryController.text = profile?.medicalHistory ?? '';
    _symptomsController.text = profile?.symptoms ?? '';
  }

  String _formatDouble(double? value) {
    if (value == null || value <= 0) {
      return '';
    }
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _weeksController.dispose();
    _bloodGroupController.dispose();
    _hbController.dispose();
    _wbcController.dispose();
    _bloodPressureController.dispose();
    _sugarController.dispose();
    _weightController.dispose();
    _medicalHistoryController.dispose();
    _symptomsController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() => _isSaving = true);
    final firestore = context.read<FirestoreService>();
    try {
      final current = widget.initialProfile;
      final user = UserModel(
        uid: widget.userId,
        email: current?.email ?? '',
        name: _nameController.text.trim(),
        age: int.parse(_ageController.text.trim()),
        pregnancyWeeks: int.parse(_weeksController.text.trim()),
        bloodGroup: _bloodGroupController.text.trim(),
        hemoglobin: double.parse(_hbController.text.trim()),
        wbc: double.parse(_wbcController.text.trim()),
        bloodPressure: _bloodPressureController.text.trim(),
        sugarLevel: double.parse(_sugarController.text.trim()),
        weight: double.parse(_weightController.text.trim()),
        symptoms: _symptomsController.text.trim(),
        medicalHistory: _medicalHistoryController.text.trim(),
        updatedAt: DateTime.now().toUtc(),
      );

      await firestore.saveUserProfile(widget.userId, user);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved successfully.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to save profile: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _signOut() async {
    if (_isSigningOut || !mounted) {
      return;
    }
    setState(() => _isSigningOut = true);
    final authService = context.read<AuthService>();
    try {
      await authService.signOut();
    } finally {
      if (mounted) {
        setState(() => _isSigningOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final content = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!widget.isInitialSetup) ...<Widget>[
              Text('Medical Profile', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Keep your pregnancy record updated for better AI guidance, daily food suggestions, and safer reminders.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
            ],
            _sectionTitle(context, 'Basic details'),
            const SizedBox(height: 14),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Name is required.' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Age'),
                    validator: (value) {
                      final age = int.tryParse((value ?? '').trim());
                      if (age == null || age < 16 || age > 60) {
                        return 'Valid age only';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TextFormField(
                    controller: _weeksController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'What is your pregnancy week?',
                    ),
                    validator: (value) {
                      final weeks = int.tryParse((value ?? '').trim());
                      if (weeks == null || weeks < 0 || weeks > 42) {
                        return '0 to 42 only';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bloodGroupController,
              decoration: const InputDecoration(labelText: 'Blood group'),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Blood group is required.'
                  : null,
            ),
            const SizedBox(height: 24),
            _sectionTitle(context, 'Clinical details'),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: _decimalField(
                    controller: _hbController,
                    label: 'Hemoglobin (Hb)',
                    hint: 'g/dL',
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _decimalField(
                    controller: _wbcController,
                    label: 'White Blood Cells',
                    hint: 'count',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: _bloodPressureController,
                    decoration: const InputDecoration(
                      labelText: 'Blood pressure',
                    ),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _decimalField(
                    controller: _sugarController,
                    label: 'Sugar level',
                    hint: 'mg/dL',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _decimalField(
              controller: _weightController,
              label: 'Weight',
              hint: 'kg',
            ),
            const SizedBox(height: 24),
            _sectionTitle(context, 'Current pregnancy notes'),
            const SizedBox(height: 14),
            TextFormField(
              controller: _symptomsController,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Symptoms'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _medicalHistoryController,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Medical history'),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Text(
                'This is not a medical diagnosis. Always contact your doctor for urgent symptoms, bleeding, severe pain, high blood pressure, reduced fetal movement, or breathing trouble.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (widget.initialProfile?.updatedAt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Last updated ${DateFormat.yMMMd().add_jm().format(widget.initialProfile!.updatedAt!.toLocal())}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSaving ? null : _saveProfile,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Text(
                        widget.isInitialSetup
                            ? 'Save and continue'
                            : 'Save medical profile',
                      ),
              ),
            ),
            if (!widget.isInitialSetup) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isSigningOut ? null : _signOut,
                  icon: _isSigningOut
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (!widget.isInitialSetup) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Complete profile')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Tell us about your pregnancy journey so the dashboard, voice assistant, and AI doctor can personalize your care.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  Widget _decimalField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: (value) {
        final parsed = double.tryParse((value ?? '').trim());
        if (parsed == null || parsed <= 0) {
          return 'Required';
        }
        return null;
      },
    );
  }
}
