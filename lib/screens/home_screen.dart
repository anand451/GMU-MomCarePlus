import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../services/ai_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../widgets/custom_card.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.userId, required this.profile});

  final String userId;
  final UserModel profile;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _hasCheckedDailySuggestion = false;

  @override
  void initState() {
    super.initState();
    _scheduleDailySuggestionCheck();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userId != oldWidget.userId ||
        widget.profile.updatedAt != oldWidget.profile.updatedAt) {
      _hasCheckedDailySuggestion = false;
      _scheduleDailySuggestionCheck();
    }
  }

  void _scheduleDailySuggestionCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prepareDailySuggestion());
    });
  }

  Future<void> _prepareDailySuggestion() async {
    if (_hasCheckedDailySuggestion || !mounted || !widget.profile.isComplete) {
      return;
    }
    _hasCheckedDailySuggestion = true;

    try {
      final firestore = context.read<FirestoreService>();
      final aiService = context.read<AiService>();

      final existing = await firestore.getTodaySuggestion(widget.userId);
      String suggestion = existing?['suggestion'] as String? ?? '';

      if (suggestion.isEmpty) {
        final todayLog = await firestore.getTodayHealthLog(widget.userId);
        final recentLogs = await firestore.getRecentHealthLogs(
          widget.userId,
          limit: 3,
        );
        suggestion = await aiService.generateDailyDietSuggestion(
          profile: widget.profile,
          todayLog: todayLog,
          recentHealthLogs: recentLogs,
        );
        await firestore.saveDailySuggestion(
          widget.userId,
          suggestion: suggestion,
          title: 'Today\'s pregnancy food focus',
        );
      }

      if (!mounted || suggestion.trim().isEmpty) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Daily food suggestion'),
            content: Text(suggestion),
            actions: <Widget>[
              FilledButton(
                onPressed: () {
                  if (Navigator.of(dialogContext).canPop()) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                child: const Text('Got it'),
              ),
            ],
          );
        },
      );
    } catch (_) {
      // The dashboard still works even if daily suggestion generation fails.
    }
  }

  Future<void> _pushChatScreen() async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('AI Chat')),
          body: SafeArea(
            child: ChatScreen(userId: widget.userId, profile: widget.profile),
          ),
        ),
      ),
    );
  }

  Future<void> _pushProfileScreen() async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Profile')),
          body: SafeArea(
            child: ProfileScreen(
              userId: widget.userId,
              initialProfile: widget.profile,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = <String>['Dashboard', 'AI Chat', 'Profile'];

    return Scaffold(
      appBar: AppBar(title: Text(titles[_currentIndex])),
      body: IndexedStack(
        index: _currentIndex,
        children: <Widget>[
          _DashboardTab(
            userId: widget.userId,
            profile: widget.profile,
            onOpenChat: _pushChatScreen,
            onOpenProfile: _pushProfileScreen,
          ),
          ChatScreen(userId: widget.userId, profile: widget.profile),
          ProfileScreen(userId: widget.userId, initialProfile: widget.profile),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          if (!mounted) {
            return;
          }
          setState(() => _currentIndex = index);
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatefulWidget {
  const _DashboardTab({
    required this.userId,
    required this.profile,
    required this.onOpenChat,
    required this.onOpenProfile,
  });

  final String userId;
  final UserModel profile;
  final Future<void> Function() onOpenChat;
  final Future<void> Function() onOpenProfile;

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  static const int _glassMl = 250;
  static const int _maxGlasses = 8;
  static const int _defaultWaterGoalMl = _glassMl * _maxGlasses;

  bool _isSaving = false;
  bool _isLoadingSteps = true;
  bool _isSyncingSensorSteps = false;
  String? _stepStatusMessage;
  StreamSubscription<StepCount>? _stepCountSubscription;
  Map<String, dynamic> _latestHealthLog = const <String, dynamic>{};
  DateTime? _lastSensorSyncAt;
  int? _liveStepCount;

  @override
  void initState() {
    super.initState();
    unawaited(_initialiseStepTracking());
    unawaited(_prepareReminderPermissions());
  }

  @override
  void dispose() {
    unawaited(_stepCountSubscription?.cancel());
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _closeDialogIfPossible(BuildContext dialogContext) {
    if (Navigator.of(dialogContext).canPop()) {
      Navigator.of(dialogContext).pop();
    }
  }

  Future<void> _prepareReminderPermissions() async {
    try {
      await context.read<NotificationService>().requestPermissions();
    } catch (error) {
      debugPrint('Notification permission request failed: $error');
    }
  }

  Future<void> _withSaveGuard(
    Future<void> Function() action, {
    String successMessage = 'Saved successfully.',
  }) async {
    if (_isSaving || !mounted) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await action();
      if (!mounted) {
        return;
      }
      _showSnack(successMessage);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _initialiseStepTracking() async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.activityRecognition.request();
        if (!mounted) {
          return;
        }
        if (!status.isGranted) {
          setState(() {
            _isLoadingSteps = false;
            _stepStatusMessage =
                'Allow activity recognition to enable live step tracking.';
          });
          return;
        }
      }

      await _stepCountSubscription?.cancel();
      _stepCountSubscription = Pedometer.stepCountStream.listen(
        _handleStepCount,
        onError: _handleStepCountError,
        cancelOnError: false,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingSteps = false;
        _stepStatusMessage = 'Tracking steps from your device sensor.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingSteps = false;
        _stepStatusMessage =
            'Step sensor unavailable on this device. You can still log steps manually.';
      });
      _showSnack(error.toString());
    }
  }

  void _handleStepCount(StepCount event) {
    final baseline = (_latestHealthLog['stepSensorBaseline'] as num?)?.toInt();
    final currentSavedSteps = (_latestHealthLog['steps'] as num?)?.toInt() ?? 0;
    final sensorSteps = event.steps;
    final safeBaseline = baseline == null || sensorSteps < baseline
        ? sensorSteps
        : baseline;
    final todaySteps = (sensorSteps - safeBaseline).clamp(0, 999999);

    if (mounted) {
      setState(() {
        _liveStepCount = todaySteps;
        _isLoadingSteps = false;
        _stepStatusMessage = 'Tracking steps from your device sensor.';
      });
    }

    if (_shouldSyncSensorSteps(
      sensorSteps: sensorSteps,
      todaySteps: todaySteps,
      baseline: baseline,
      currentSavedSteps: currentSavedSteps,
    )) {
      unawaited(
        _syncStepReading(sensorSteps: sensorSteps, baseline: safeBaseline),
      );
    }
  }

  void _handleStepCountError(dynamic error) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoadingSteps = false;
      _stepStatusMessage =
          'Step tracking is unavailable right now. You can still save steps manually.';
    });
  }

  bool _shouldSyncSensorSteps({
    required int sensorSteps,
    required int todaySteps,
    required int? baseline,
    required int currentSavedSteps,
  }) {
    if (_isSyncingSensorSteps) {
      return false;
    }

    final storedRaw = (_latestHealthLog['stepSensorRaw'] as num?)?.toInt();
    if (storedRaw == sensorSteps && currentSavedSteps == todaySteps) {
      return false;
    }

    if (_lastSensorSyncAt != null &&
        DateTime.now().difference(_lastSensorSyncAt!) <
            const Duration(seconds: 12)) {
      return false;
    }

    return storedRaw != sensorSteps || baseline == null;
  }

  Future<void> _syncStepReading({
    required int sensorSteps,
    required int baseline,
  }) async {
    if (_isSyncingSensorSteps || !mounted) {
      return;
    }

    _isSyncingSensorSteps = true;
    try {
      await context.read<FirestoreService>().syncSensorSteps(
        widget.userId,
        sensorSteps: sensorSteps,
        baselineSteps: baseline,
      );
      _lastSensorSyncAt = DateTime.now();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _stepStatusMessage = error.toString();
      });
    } finally {
      _isSyncingSensorSteps = false;
    }
  }

  Future<void> _incrementWaterIntake(Map<String, dynamic> todayLog) async {
    final currentIntake = (todayLog['waterIntakeMl'] as num?)?.toInt() ?? 0;
    final nextIntake = (currentIntake + _glassMl).clamp(0, _defaultWaterGoalMl);
    await _withSaveGuard(
      () => context.read<FirestoreService>().saveWaterLog(
        widget.userId,
        waterIntakeMl: nextIntake,
        waterGoalMl: _defaultWaterGoalMl,
      ),
      successMessage: 'Hydration updated.',
    );
  }

  Future<void> _showWaterDialog(Map<String, dynamic> todayLog) async {
    final firestore = context.read<FirestoreService>();
    final intakeController = TextEditingController(
      text: ((todayLog['waterIntakeMl'] as num?)?.toInt() ?? 0).toString(),
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Water intake'),
          content: TextField(
            controller: intakeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Today intake (ml)'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => _closeDialogIfPossible(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final intake = int.tryParse(intakeController.text.trim());
                if (intake == null || intake < 0) {
                  _showSnack('Enter a valid water amount.');
                  return;
                }

                _closeDialogIfPossible(dialogContext);
                await _withSaveGuard(
                  () => firestore.saveWaterLog(
                    widget.userId,
                    waterIntakeMl: intake.clamp(0, _defaultWaterGoalMl),
                    waterGoalMl: _defaultWaterGoalMl,
                  ),
                  successMessage: 'Hydration updated.',
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    intakeController.dispose();
  }

  Future<void> _showStepsDialog(Map<String, dynamic> todayLog) async {
    final firestore = context.read<FirestoreService>();
    final controller = TextEditingController(
      text: ((_liveStepCount ?? todayLog['steps']) as num? ?? 0)
          .toInt()
          .toString(),
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Today steps'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Step count'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => _closeDialogIfPossible(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final steps = int.tryParse(controller.text.trim());
                if (steps == null || steps < 0) {
                  _showSnack('Enter a valid step count.');
                  return;
                }
                _closeDialogIfPossible(dialogContext);
                await _withSaveGuard(
                  () => firestore.saveSteps(widget.userId, steps: steps),
                  successMessage: 'Steps updated.',
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();
  }

  Future<void> _showBloodPressureDialog(Map<String, dynamic> todayLog) async {
    final firestore = context.read<FirestoreService>();
    final systolicController = TextEditingController(
      text: ((todayLog['systolic'] as num?)?.toInt() ?? 0).toString(),
    );
    final diastolicController = TextEditingController(
      text: ((todayLog['diastolic'] as num?)?.toInt() ?? 0).toString(),
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Blood pressure'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: systolicController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Systolic'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: diastolicController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Diastolic'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => _closeDialogIfPossible(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final systolic = int.tryParse(systolicController.text.trim());
                final diastolic = int.tryParse(diastolicController.text.trim());
                if (systolic == null ||
                    diastolic == null ||
                    systolic < 60 ||
                    diastolic < 40) {
                  _showSnack('Enter valid BP values.');
                  return;
                }

                _closeDialogIfPossible(dialogContext);
                await _withSaveGuard(
                  () => firestore.saveBloodPressure(
                    widget.userId,
                    systolic: systolic,
                    diastolic: diastolic,
                  ),
                  successMessage: 'Blood pressure updated.',
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    systolicController.dispose();
    diastolicController.dispose();
  }

  Future<void> _showConditionDialog(Map<String, dynamic> todayLog) async {
    final firestore = context.read<FirestoreService>();
    final controller = TextEditingController(
      text: todayLog['condition'] as String? ?? '',
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Health condition'),
          content: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'How are you feeling today?',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => _closeDialogIfPossible(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (controller.text.trim().isEmpty) {
                  _showSnack('Enter your current condition.');
                  return;
                }
                _closeDialogIfPossible(dialogContext);
                await _withSaveGuard(
                  () => firestore.saveCondition(
                    widget.userId,
                    condition: controller.text.trim(),
                  ),
                  successMessage: 'Condition updated.',
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();
  }

  Future<void> _showReminderDialog() async {
    final firestore = context.read<FirestoreService>();
    final notificationService = context.read<NotificationService>();
    final controller = TextEditingController();
    TimeOfDay selectedTime = TimeOfDay.now();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogStateContext, setDialogState) {
            return AlertDialog(
              title: const Text('Medicine reminder'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Medicine name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: dialogStateContext,
                        initialTime: selectedTime,
                      );
                      if (picked != null) {
                        setDialogState(() => selectedTime = picked);
                      }
                    },
                    icon: const Icon(Icons.schedule),
                    label: Text(selectedTime.format(dialogStateContext)),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => _closeDialogIfPossible(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (controller.text.trim().isEmpty) {
                      _showSnack('Enter a medicine name.');
                      return;
                    }
                    final notificationId = notificationService
                        .createNotificationId();
                    _closeDialogIfPossible(dialogContext);
                    await _withSaveGuard(() async {
                      final nextTriggerAt = await notificationService
                          .scheduleDailyReminder(
                            notificationId: notificationId,
                            title: 'Medicine reminder',
                            body:
                                'Time to take ${controller.text.trim()} safely.',
                            hour: selectedTime.hour,
                            minute: selectedTime.minute,
                          );
                      await firestore.addReminder(
                        widget.userId,
                        medicineName: controller.text.trim(),
                        hour: selectedTime.hour,
                        minute: selectedTime.minute,
                        notificationId: notificationId,
                        nextTriggerAt: nextTriggerAt,
                      );
                    }, successMessage: 'Reminder added.');
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<Map<String, dynamic>>(
      stream: context.read<FirestoreService>().watchTodayHealthLog(
        widget.userId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.cloud_off_rounded, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Unable to load today\'s health log.',
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () {
                        if (!mounted) {
                          return;
                        }
                        setState(() {});
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final todayLog =
            snapshot.data ??
            <String, dynamic>{
              'waterGoalMl': _defaultWaterGoalMl,
              'waterIntakeMl': 0,
              'steps': 0,
              'systolic': 0,
              'diastolic': 0,
              'condition': '',
            };
        _latestHealthLog = todayLog;

        final waterIntake = ((todayLog['waterIntakeMl'] as num?)?.toInt() ?? 0)
            .clamp(0, _defaultWaterGoalMl);
        final completedGlasses = waterIntake ~/ _glassMl;
        final displayGlasses = (waterIntake / _glassMl).clamp(0, _maxGlasses);
        final fillRatio = (waterIntake / _defaultWaterGoalMl).clamp(0.0, 1.0);
        final savedSteps = (todayLog['steps'] as num?)?.toInt() ?? 0;
        final displayedSteps = _liveStepCount ?? savedSteps;

        return Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      if (!mounted) {
                        return;
                      }
                      setState(() {});
                      await Future<void>.delayed(
                        const Duration(milliseconds: 250),
                      );
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
                      children: <Widget>[
                        Text(
                          'Hello, ${_firstName(widget.profile.name)}',
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Week ${widget.profile.pregnancyWeeks} of pregnancy - ${DateFormat.yMMMMd().format(DateTime.now())}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: <Widget>[
                            OutlinedButton.icon(
                              onPressed: _isSaving ? null : widget.onOpenChat,
                              icon: const Icon(Icons.chat_bubble_outline),
                              label: const Text('Open Chat'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _isSaving
                                  ? null
                                  : widget.onOpenProfile,
                              icon: const Icon(Icons.person_outline),
                              label: const Text('Open Profile'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        CustomCard(
                          title: 'Maternal Snapshot',
                          subtitle:
                              'Your AI doctor uses this Firebase profile context',
                          icon: Icons.favorite_outline,
                          accentColor: const Color(0xFFFF9FB6),
                          onAdd: _isSaving ? null : widget.onOpenProfile,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: <Widget>[
                                  _InfoPill(
                                    label: 'Hb',
                                    value:
                                        '${widget.profile.hemoglobin.toStringAsFixed(1)} g/dL',
                                  ),
                                  _InfoPill(
                                    label: 'WBC',
                                    value: widget.profile.wbc.toStringAsFixed(
                                      1,
                                    ),
                                  ),
                                  _InfoPill(
                                    label: 'BP',
                                    value: widget.profile.bloodPressure,
                                  ),
                                  _InfoPill(
                                    label: 'Sugar',
                                    value:
                                        '${widget.profile.sugarLevel.toStringAsFixed(1)} mg/dL',
                                  ),
                                  _InfoPill(
                                    label: 'Weight',
                                    value:
                                        '${widget.profile.weight.toStringAsFixed(1)} kg',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                widget.profile.symptoms.trim().isEmpty
                                    ? 'No symptoms saved in the profile yet.'
                                    : 'Symptoms: ${widget.profile.symptoms.trim()}',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'This is not a medical diagnosis. Contact your doctor for urgent concerns.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        StreamBuilder<Map<String, dynamic>?>(
                          stream: context
                              .read<FirestoreService>()
                              .watchTodaySuggestion(widget.userId),
                          builder: (context, suggestionSnapshot) {
                            final suggestionData = suggestionSnapshot.data;
                            return CustomCard(
                              title: 'Daily AI Food Suggestion',
                              subtitle: 'Saved in Firebase for today',
                              icon: Icons.restaurant_menu_outlined,
                              accentColor: const Color(0xFF7CE7C5),
                              child:
                                  suggestionSnapshot.connectionState ==
                                          ConnectionState.waiting &&
                                      suggestionData == null
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 20,
                                      ),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                        ),
                                      ),
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          suggestionData?['suggestion']
                                                  as String? ??
                                              'Your daily nutrition suggestion will appear here once generated.',
                                          style: theme.textTheme.bodyLarge,
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Today: ${DateFormat.yMMMMd().format(DateTime.now())}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        CustomCard(
                          title: 'Water Intake',
                          subtitle: 'Animated hydration tracker for today',
                          icon: Icons.water_drop_outlined,
                          accentColor: const Color(0xFF58D7D4),
                          onAdd: _isSaving
                              ? null
                              : () => _showWaterDialog(todayLog),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth >= 620;
                              final glassLabel = displayGlasses % 1 == 0
                                  ? displayGlasses.toInt().toString()
                                  : displayGlasses.toStringAsFixed(1);

                              if (isWide) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: <Widget>[
                                    Expanded(
                                      flex: 5,
                                      child: _HydrationGlass(
                                        fillRatio: fillRatio,
                                        consumedLabel:
                                            '$glassLabel / $_maxGlasses glasses',
                                        intakeLabel: '$waterIntake ml logged',
                                      ),
                                    ),
                                    const SizedBox(width: 20),
                                    Expanded(
                                      flex: 4,
                                      child: _HydrationSummary(
                                        waterIntake: waterIntake,
                                        completedGlasses: completedGlasses,
                                        onDrinkWater:
                                            _isSaving ||
                                                waterIntake >=
                                                    _defaultWaterGoalMl
                                            ? null
                                            : () => _incrementWaterIntake(
                                                todayLog,
                                              ),
                                      ),
                                    ),
                                  ],
                                );
                              }

                              return Column(
                                children: <Widget>[
                                  _HydrationGlass(
                                    fillRatio: fillRatio,
                                    consumedLabel:
                                        '$glassLabel / $_maxGlasses glasses',
                                    intakeLabel: '$waterIntake ml logged',
                                  ),
                                  const SizedBox(height: 20),
                                  _HydrationSummary(
                                    waterIntake: waterIntake,
                                    completedGlasses: completedGlasses,
                                    onDrinkWater:
                                        _isSaving ||
                                            waterIntake >= _defaultWaterGoalMl
                                        ? null
                                        : () => _incrementWaterIntake(todayLog),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        CustomCard(
                          title: 'Steps',
                          subtitle: 'Live sensor tracking with manual backup',
                          icon: Icons.directions_walk_outlined,
                          accentColor: const Color(0xFF7DE88A),
                          onAdd: _isSaving
                              ? null
                              : () => _showStepsDialog(todayLog),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth >= 520;
                              final details = _StepsSummary(
                                steps: displayedSteps,
                                isLoading: _isLoadingSteps,
                                isSyncing: _isSyncingSensorSteps,
                                status: _stepStatusMessage,
                                onRetry: _isLoadingSteps
                                    ? null
                                    : _initialiseStepTracking,
                              );
                              if (isWide) {
                                return Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: _MetricHighlight(
                                        icon: Icons.directions_walk_rounded,
                                        value: NumberFormat.decimalPattern()
                                            .format(displayedSteps),
                                        label: 'Steps today',
                                        accentColor: const Color(0xFF7DE88A),
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    Expanded(child: details),
                                  ],
                                );
                              }

                              return Column(
                                children: <Widget>[
                                  _MetricHighlight(
                                    icon: Icons.directions_walk_rounded,
                                    value: NumberFormat.decimalPattern().format(
                                      displayedSteps,
                                    ),
                                    label: 'Steps today',
                                    accentColor: const Color(0xFF7DE88A),
                                  ),
                                  const SizedBox(height: 18),
                                  details,
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        CustomCard(
                          title: 'Blood Pressure',
                          subtitle: 'Keep a simple daily reading',
                          icon: Icons.monitor_heart_outlined,
                          accentColor: const Color(0xFFFF9C9C),
                          onAdd: _isSaving
                              ? null
                              : () => _showBloodPressureDialog(todayLog),
                          child: _MetricBody(
                            value: (todayLog['systolic'] ?? 0) == 0
                                ? 'No reading saved for today.'
                                : '${todayLog['systolic']}/${todayLog['diastolic']} mmHg',
                            hint: 'Tap + to record a new reading.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        CustomCard(
                          title: 'Health Condition',
                          subtitle: 'Capture symptoms or how you feel today',
                          icon: Icons.health_and_safety_outlined,
                          accentColor: const Color(0xFFFFC857),
                          onAdd: _isSaving
                              ? null
                              : () => _showConditionDialog(todayLog),
                          child: _MetricBody(
                            value:
                                (todayLog['condition'] as String? ?? '').isEmpty
                                ? 'No condition notes saved yet.'
                                : todayLog['condition'] as String,
                            hint:
                                'Use this area for symptoms, energy, or mood.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        CustomCard(
                          title: 'Medicine Reminder',
                          subtitle:
                              'Add medicines and preferred reminder times',
                          icon: Icons.medication_outlined,
                          accentColor: const Color(0xFFD2B7FF),
                          onAdd: _isSaving ? null : _showReminderDialog,
                          child: StreamBuilder<List<Map<String, dynamic>>>(
                            stream: context
                                .read<FirestoreService>()
                                .watchReminders(widget.userId),
                            builder: (context, reminderSnapshot) {
                              final firestore = context
                                  .read<FirestoreService>();
                              final notifications = context
                                  .read<NotificationService>();
                              if (reminderSnapshot.hasError) {
                                return Text(
                                  reminderSnapshot.error.toString(),
                                  style: theme.textTheme.bodyMedium,
                                );
                              }

                              if (reminderSnapshot.connectionState ==
                                      ConnectionState.waiting &&
                                  !reminderSnapshot.hasData) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  ),
                                );
                              }

                              final reminders =
                                  reminderSnapshot.data ??
                                  const <Map<String, dynamic>>[];
                              if (reminders.isEmpty) {
                                return Text(
                                  'No reminders saved yet. Tap the plus button to add one.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                );
                              }

                              return Column(
                                children: reminders.map((reminder) {
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      reminder['medicineName'] as String? ?? '',
                                    ),
                                    subtitle: Text(
                                      _buildReminderSubtitle(reminder),
                                    ),
                                    trailing: IconButton(
                                      onPressed: _isSaving
                                          ? null
                                          : () => _withSaveGuard(
                                              () async {
                                                final notificationId =
                                                    (reminder['notificationId']
                                                            as num?)
                                                        ?.toInt();
                                                if (notificationId != null) {
                                                  await notifications
                                                      .cancelReminder(
                                                        notificationId,
                                                      );
                                                }
                                                await firestore.deleteReminder(
                                                  widget.userId,
                                                  reminder['id'] as String,
                                                );
                                              },
                                              successMessage:
                                                  'Reminder removed.',
                                            ),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_isSaving)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 3),
              ),
          ],
        );
      },
    );
  }

  String _firstName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'Mama';
    }
    return trimmed.split(' ').first;
  }

  String _buildReminderSubtitle(Map<String, dynamic> reminder) {
    final rawNextTrigger = reminder['nextTriggerAt'];
    final nextTrigger = rawNextTrigger is DateTime
        ? rawNextTrigger
        : rawNextTrigger is Timestamp
        ? rawNextTrigger.toDate()
        : null;
    final timeLabel = reminder['timeLabel'] as String? ?? '';
    if (nextTrigger == null) {
      return '$timeLabel • Daily reminder';
    }
    return '$timeLabel • Next ${DateFormat.MMMd().add_jm().format(nextTrigger.toLocal())}';
  }
}

class _HydrationGlass extends StatelessWidget {
  const _HydrationGlass({
    required this.fillRatio,
    required this.consumedLabel,
    required this.intakeLabel,
  });

  final double fillRatio;
  final String consumedLabel;
  final String intakeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: AspectRatio(
          aspectRatio: 0.74,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fillHeight = constraints.maxHeight * fillRatio;
              final bubbleConfigs = <({double dx, double ratio, double size})>[
                (dx: 0.18, ratio: 0.32, size: 10),
                (dx: 0.48, ratio: 0.58, size: 12),
                (dx: 0.68, ratio: 0.25, size: 8),
                (dx: 0.36, ratio: 0.76, size: 6),
              ];

              return Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(34),
                      border: Border.all(
                        color: const Color(0xFF58D7D4),
                        width: 2.5,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: const Color(
                            0xFF58D7D4,
                          ).withValues(alpha: 0.18),
                          blurRadius: 24,
                          offset: const Offset(0, 18),
                        ),
                      ],
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.white.withValues(alpha: 0.18),
                          Colors.white.withValues(alpha: 0.03),
                        ],
                      ),
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(31),
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  Colors.white.withValues(alpha: 0.08),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 850),
                            curve: Curves.easeOutCubic,
                            height: fillHeight,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  Color(0xFF76FFF1),
                                  Color(0xFF2CB9C9),
                                  Color(0xFF1688A0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        for (final bubble in bubbleConfigs)
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 900),
                            curve: Curves.easeOutCubic,
                            left: constraints.maxWidth * bubble.dx,
                            bottom: fillRatio <= 0.02
                                ? -28
                                : (fillHeight * bubble.ratio).clamp(
                                    14.0,
                                    constraints.maxHeight - 34,
                                  ),
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 450),
                              opacity: fillRatio <= 0.08 ? 0 : 0.82,
                              child: Container(
                                width: bubble.size,
                                height: bubble.size,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.48),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        consumedLabel,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        intakeLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HydrationSummary extends StatelessWidget {
  const _HydrationSummary({
    required this.waterIntake,
    required this.completedGlasses,
    required this.onDrinkWater,
  });

  final int waterIntake;
  final int completedGlasses;
  final VoidCallback? onDrinkWater;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remainingMl = (_DashboardTabState._defaultWaterGoalMl - waterIntake)
        .clamp(0, _DashboardTabState._defaultWaterGoalMl);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          completedGlasses >= _DashboardTabState._maxGlasses
              ? 'Hydration goal reached'
              : '$remainingMl ml left for today',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          completedGlasses >= _DashboardTabState._maxGlasses
              ? 'Great work staying hydrated today.'
              : 'Tap the button each time you finish a glass to keep your tracker current.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onDrinkWater,
          icon: const Icon(Icons.local_drink_rounded),
          label: const Text('I Drank Water'),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: List<Widget>.generate(_DashboardTabState._maxGlasses, (
            index,
          ) {
            final filled = index < completedGlasses;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: filled
                    ? const Color(0xFF58D7D4).withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.local_drink_rounded,
                color: filled ? const Color(0xFF7FFFF3) : Colors.grey.shade600,
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _StepsSummary extends StatelessWidget {
  const _StepsSummary({
    required this.steps,
    required this.isLoading,
    required this.isSyncing,
    required this.status,
    required this.onRetry,
  });

  final int steps;
  final bool isLoading;
  final bool isSyncing;
  final String? status;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: isLoading
              ? const Padding(
                  key: ValueKey('steps-loading'),
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : Text(
                  status ?? 'Tracking steps from your device sensor.',
                  key: const ValueKey('steps-status'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
        const SizedBox(height: 14),
        Text(
          steps >= 6000
              ? 'Nice movement today. Keep taking gentle walks when you can.'
              : 'Short walks still count. Manual entry remains available if your sensor pauses.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            if (onRetry != null)
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry Sensor'),
              ),
            if (isSyncing)
              Chip(
                avatar: const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                label: const Text('Syncing'),
                side: BorderSide.none,
              ),
          ],
        ),
      ],
    );
  }
}

class _MetricHighlight extends StatelessWidget {
  const _MetricHighlight({
    required this.icon,
    required this.value,
    required this.label,
    required this.accentColor,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withValues(alpha: 0.05),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accentColor.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: accentColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(value, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBody extends StatelessWidget {
  const _MetricBody({required this.value, required this.hint});

  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(value, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          hint,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}
