import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/user_model.dart';

class AiService {
  AiService({http.Client? client, String? apiKey, String? model})
    : _client = client ?? http.Client(),
      _apiKey = apiKey ?? const String.fromEnvironment('GEMINI_API_KEY'),
      _model =
          model ??
          const String.fromEnvironment(
            'GEMINI_MODEL',
            defaultValue: 'gemini-2.5-flash',
          );

  final http.Client _client;
  final String _apiKey;
  final String _model;

  Future<String> askPregnancyDoctor({
    required String userMessage,
    required UserModel profile,
    required Map<String, dynamic> todayLog,
    required List<Map<String, dynamic>> recentHealthLogs,
    String? dailySuggestion,
    List<Map<String, dynamic>> recentMessages = const <Map<String, dynamic>>[],
  }) {
    return askGemini(
      _buildDoctorPrompt(
        userMessage: userMessage,
        profile: profile,
        todayLog: todayLog,
        recentHealthLogs: recentHealthLogs,
        dailySuggestion: dailySuggestion,
        recentMessages: recentMessages,
      ),
    );
  }

  Future<String> generateDailyDietSuggestion({
    required UserModel profile,
    required Map<String, dynamic> todayLog,
    required List<Map<String, dynamic>> recentHealthLogs,
  }) {
    return askGemini(
      'You are a maternal healthcare AI nutrition guide.\n'
      'Use the profile and recent health context below to create a short, safe, pregnancy-friendly daily food suggestion.\n'
      'Keep it to 2-3 sentences, mention hydration, one protein source, one iron-rich option, and a caution if symptoms suggest seeing a doctor.\n'
      'Always include this sentence at the end: "This is not a medical diagnosis."\n\n'
      'Profile:\n${profile.toAiSummary()}\n\n'
      'Today log:\n${_formatTodayLog(todayLog)}\n\n'
      'Recent health logs:\n${_formatRecentLogs(recentHealthLogs)}',
    );
  }

  Future<String> askGemini(String message) async {
    if (_apiKey.isEmpty) {
      throw AiServiceException(
        'Gemini API key is not configured. Start the app with '
        '`--dart-define=GEMINI_API_KEY=your_key` to enable AI chat.',
      );
    }

    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey',
            ),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'contents': <Map<String, dynamic>>[
                <String, dynamic>{
                  'parts': <Map<String, String>>[
                    <String, String>{'text': message},
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on SocketException {
      throw AiServiceException(
        'Network error while contacting Gemini. Check your internet connection and try again.',
      );
    } on http.ClientException {
      throw AiServiceException(
        'Unable to reach Gemini right now. Please try again shortly.',
      );
    } on TimeoutException {
      throw AiServiceException(
        'Gemini took too long to respond. Please try again.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiServiceException(
        _extractApiError(response.statusCode, response.body),
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final reply = _extractText(body);
    if (reply == null || reply.trim().isEmpty) {
      throw AiServiceException('Gemini returned an empty response.');
    }

    return reply.trim();
  }

  String _buildDoctorPrompt({
    required String userMessage,
    required UserModel profile,
    required Map<String, dynamic> todayLog,
    required List<Map<String, dynamic>> recentHealthLogs,
    required List<Map<String, dynamic>> recentMessages,
    String? dailySuggestion,
  }) {
    final safeSuggestion = dailySuggestion == null || dailySuggestion.isEmpty
        ? 'No daily suggestion saved yet.'
        : dailySuggestion;
    final riskContext = _buildRiskContext(profile, todayLog);

    return 'You are a maternal healthcare AI doctor.\n'
        'Use the user health data below from Firebase and give safe pregnancy advice only.\n'
        'If the question is unrelated to pregnancy, refuse politely.\n'
        'Detect high-risk pregnancy patterns.\n'
        'If Hb < 10, blood pressure is high, or symptoms are concerning, mark the case as HIGH RISK and strongly advise medical review.\n'
        'Always mention warning signs when appropriate.\n'
        'Never claim this is a diagnosis.\n'
        'End with: "This is not a medical diagnosis. Please contact your doctor for urgent concerns."\n\n'
        'Patient profile:\n${profile.toAiSummary()}\n\n'
        'Today health log:\n${_formatTodayLog(todayLog)}\n\n'
        'Recent health logs:\n${_formatRecentLogs(recentHealthLogs)}\n\n'
        'Automatic risk screen:\n$riskContext\n\n'
        'Today diet suggestion:\n$safeSuggestion\n\n'
        'Recent conversation:\n${_formatRecentMessages(recentMessages)}\n\n'
        'User question:\n$userMessage\n\n'
        'Respond with:\n'
        '1. Risk level (NORMAL RISK or HIGH RISK)\n'
        '2. Safe advice\n'
        '3. Diet plan\n'
        '4. Warning signs / when to see a doctor\n'
        '5. Care tips';
  }

  String _formatTodayLog(Map<String, dynamic> todayLog) {
    return 'Date: ${todayLog['date'] ?? ''}\n'
        'Water intake: ${todayLog['waterIntakeMl'] ?? 0} ml\n'
        'Water goal: ${todayLog['waterGoalMl'] ?? 2000} ml\n'
        'Steps: ${todayLog['steps'] ?? 0}\n'
        'Blood pressure reading: ${todayLog['systolic'] ?? 0}/${todayLog['diastolic'] ?? 0} mmHg\n'
        'Condition: ${todayLog['condition'] ?? 'None'}';
  }

  String _formatRecentLogs(List<Map<String, dynamic>> recentHealthLogs) {
    if (recentHealthLogs.isEmpty) {
      return 'No recent health logs available.';
    }
    return recentHealthLogs
        .map((log) {
          return '- ${log['date'] ?? 'Unknown date'}: '
              '${log['waterIntakeMl'] ?? 0} ml water, '
              '${log['steps'] ?? 0} steps, '
              'BP ${log['systolic'] ?? 0}/${log['diastolic'] ?? 0}, '
              'Condition: ${log['condition'] ?? 'None'}';
        })
        .join('\n');
  }

  String _formatRecentMessages(List<Map<String, dynamic>> recentMessages) {
    if (recentMessages.isEmpty) {
      return 'No previous messages.';
    }
    final safeMessages = recentMessages.length <= 6
        ? recentMessages
        : recentMessages.sublist(recentMessages.length - 6);
    return safeMessages
        .map((entry) {
          final role = (entry['role'] as String? ?? 'user').toLowerCase();
          final label = role == 'user' ? 'User' : 'AI';
          final text = ((entry['message'] ?? entry['text']) as String? ?? '')
              .trim();
          return '$label: $text';
        })
        .join('\n');
  }

  String _buildRiskContext(UserModel profile, Map<String, dynamic> todayLog) {
    final systolic = (todayLog['systolic'] as num?)?.toInt();
    final diastolic = (todayLog['diastolic'] as num?)?.toInt();
    final symptomText = '${profile.symptoms} ${todayLog['condition'] ?? ''}'
        .toLowerCase();
    final warnings = <String>[];

    if (profile.hemoglobin > 0 && profile.hemoglobin < 10) {
      warnings.add('Hemoglobin below 10 g/dL');
    }
    if ((systolic ?? 0) >= 140 || (diastolic ?? 0) >= 90) {
      warnings.add('Today blood pressure is high');
    }
    if (_isHighRiskSymptom(symptomText)) {
      warnings.add('Symptoms mention a potential warning sign');
    }

    if (warnings.isEmpty) {
      return 'No automatic high-risk trigger detected from the saved data.';
    }
    return 'Potential HIGH RISK triggers:\n- ${warnings.join('\n- ')}';
  }

  bool _isHighRiskSymptom(String symptomText) {
    const keywords = <String>[
      'bleeding',
      'severe pain',
      'vision',
      'swelling',
      'reduced fetal movement',
      'reduced movement',
      'breathing trouble',
      'shortness of breath',
      'headache',
      'dizziness',
      'chest pain',
      'contraction',
    ];
    return keywords.any(symptomText.contains);
  }

  String _extractApiError(int statusCode, String responseBody) {
    if (statusCode == 400) {
      return 'Gemini rejected the request. Check the prompt or selected model.';
    }
    if (statusCode == 401 || statusCode == 403) {
      return 'Gemini API key is invalid or not authorized. Check `--dart-define=GEMINI_API_KEY=...`.';
    }
    if (statusCode == 429) {
      return 'Gemini rate limit reached. Please wait a moment and try again.';
    }
    if (statusCode >= 500) {
      return 'Gemini is temporarily unavailable. Please try again later.';
    }

    try {
      final parsed = jsonDecode(responseBody) as Map<String, dynamic>;
      final error = parsed['error'];
      if (error is Map<String, dynamic> && error['message'] is String) {
        return error['message'] as String;
      }
    } catch (_) {
      // Fall through to the generic message below.
    }
    return 'Unable to contact Gemini right now.';
  }

  String? _extractText(Map<String, dynamic> payload) {
    final candidates = payload['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      return null;
    }

    final firstCandidate = candidates.first;
    if (firstCandidate is! Map<String, dynamic>) {
      return null;
    }

    final content = firstCandidate['content'];
    if (content is! Map<String, dynamic>) {
      return null;
    }

    final parts = content['parts'];
    if (parts is! List) {
      return null;
    }

    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is Map<String, dynamic> && part['text'] is String) {
        buffer.writeln(part['text'] as String);
      }
    }

    final text = buffer.toString().trim();
    return text.isEmpty ? null : text;
  }
}

class AiServiceException implements Exception {
  AiServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
