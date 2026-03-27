import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/user_model.dart';
import '../services/ai_service.dart';
import '../services/firestore_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.userId, required this.profile});

  final String userId;
  final UserModel profile;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

  bool _isLoading = false;
  bool _speechEnabled = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  List<Map<String, dynamic>> _latestMessages = const <Map<String, dynamic>>[];
  int _lastRenderedMessageCount = 0;
  DateTime? _lastSendAt;
  String? _pendingDraft;

  @override
  void initState() {
    super.initState();
    unawaited(_initSpeech());
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    unawaited(_speechToText.cancel());
    unawaited(_flutterTts.stop());
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    await _flutterTts.awaitSpeakCompletion(true);
    _flutterTts.setStartHandler(() {
      if (!mounted) {
        return;
      }
      setState(() => _isSpeaking = true);
    });
    _flutterTts.setCompletionHandler(() {
      if (!mounted) {
        return;
      }
      setState(() => _isSpeaking = false);
    });
    _flutterTts.setCancelHandler(() {
      if (!mounted) {
        return;
      }
      setState(() => _isSpeaking = false);
    });
    _flutterTts.setErrorHandler((_) {
      if (!mounted) {
        return;
      }
      setState(() => _isSpeaking = false);
    });
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.46);

    final enabled = await _speechToText.initialize(
      onStatus: _handleSpeechStatus,
      onError: (error) {
        if (!mounted) {
          return;
        }
        setState(() => _isListening = false);
        _showError(error.errorMsg);
      },
    );
    if (!mounted) {
      return;
    }
    setState(() => _speechEnabled = enabled);
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isListening = _speechToText.isListening;
    });
  }

  Future<void> _toggleListening() async {
    if (_isLoading) {
      return;
    }

    if (_speechToText.isListening) {
      await _speechToText.stop();
      if (!mounted) {
        return;
      }
      setState(() => _isListening = false);
      return;
    }

    if (!_speechEnabled) {
      await _initSpeech();
      if (!mounted) {
        return;
      }
      if (!_speechEnabled) {
        _showError('Speech recognition is not available on this device.');
        return;
      }
    }

    await _speechToText.listen(
      onResult: _handleSpeechResult,
      listenOptions: SpeechListenOptions(partialResults: true),
      listenFor: const Duration(seconds: 35),
      pauseFor: const Duration(seconds: 4),
    );
    if (!mounted) {
      return;
    }
    setState(() => _isListening = true);
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords.trim();
    if (!mounted || words.isEmpty) {
      return;
    }
    _messageController.value = TextEditingValue(
      text: words,
      selection: TextSelection.collapsed(offset: words.length),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final now = DateTime.now();
    if (text.isEmpty || _isLoading) {
      return;
    }
    if (_lastSendAt != null &&
        now.difference(_lastSendAt!) < const Duration(milliseconds: 800)) {
      return;
    }
    if (_pendingDraft == text) {
      return;
    }

    _lastSendAt = now;
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = true;
      _pendingDraft = text;
    });
    final firestore = context.read<FirestoreService>();
    final aiService = context.read<AiService>();
    _messageFocusNode.unfocus();
    if (_speechToText.isListening) {
      await _speechToText.stop();
    }
    if (_isSpeaking) {
      await _flutterTts.stop();
      if (!mounted) {
        return;
      }
      setState(() => _isSpeaking = false);
    }
    _messageController.clear();

    try {
      final liveProfile =
          await firestore.getUserProfile(widget.userId) ?? widget.profile;
      final aiContext = await firestore.getAiDoctorContext(widget.userId);

      await firestore.addChatMessage(widget.userId, role: 'user', text: text);
      final aiReply = await aiService.askPregnancyDoctor(
        userMessage: text,
        profile: liveProfile,
        todayLog:
            (aiContext['todayLog'] as Map<String, dynamic>? ??
            <String, dynamic>{}),
        recentHealthLogs:
            (aiContext['recentHealthLogs'] as List<dynamic>? ??
                    const <dynamic>[])
                .whereType<Map<String, dynamic>>()
                .toList(),
        dailySuggestion:
            (aiContext['dailySuggestion']
                    as Map<String, dynamic>?)?['suggestion']
                as String?,
        recentMessages: _latestMessages,
      );
      await firestore.addChatMessage(widget.userId, role: 'ai', text: aiReply);
      await _flutterTts.speak(aiReply);
      _scrollToBottom();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _messageController.text = text;
      _messageController.selection = TextSelection.collapsed(
        offset: _messageController.text.length,
      );
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _pendingDraft = null;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _isListening
                  ? const Color(0xFF58D7D4).withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Text(
              _isListening
                  ? 'Listening for your pregnancy question...'
                  : _isSpeaking
                  ? 'Speaking the AI doctor reply...'
                  : 'Maternal healthcare AI only. This is not a medical diagnosis. For bleeding, severe pain, high blood pressure, reduced fetal movement, or breathing trouble, contact your doctor immediately.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: context.read<FirestoreService>().watchChatMessages(
              widget.userId,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Unable to load chat history.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final messages = snapshot.data ?? <Map<String, dynamic>>[];
              _latestMessages = messages;
              if (messages.length != _lastRenderedMessageCount) {
                _lastRenderedMessageCount = messages.length;
                _scrollToBottom();
              }

              if (snapshot.connectionState == ConnectionState.waiting &&
                  messages.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (messages.isEmpty && !_isLoading) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Ask about diet, symptoms, warning signs, supplements, sleep, walking, hydration, or daily pregnancy care. You can type or use the mic button.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }

              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                itemCount: messages.length + (_isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_isLoading && index == messages.length) {
                    return const _TypingBubble();
                  }

                  final message = messages[index];
                  final role = (message['role'] as String? ?? 'user')
                      .toLowerCase();
                  final isUser = role == 'user';
                  final rawTimestamp =
                      message['timestamp'] ?? message['createdAt'];
                  final sentAt = rawTimestamp is Timestamp
                      ? rawTimestamp.toDate()
                      : rawTimestamp is DateTime
                      ? rawTimestamp
                      : DateTime.now();

                  return _ChatBubble(
                    message:
                        (message['message'] ?? message['text']) as String? ??
                        '',
                    sentAt: sentAt,
                    isUser: isUser,
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF101010),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _messageFocusNode,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: _isListening
                            ? 'Listening...'
                            : 'Ask your pregnancy health question...',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 50,
                    width: 50,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: _isListening
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: const Color(
                                    0xFF58D7D4,
                                  ).withValues(alpha: 0.35),
                                  blurRadius: 18,
                                  spreadRadius: 1,
                                ),
                              ]
                            : const <BoxShadow>[],
                      ),
                      child: FilledButton(
                        onPressed: _isLoading ? null : _toggleListening,
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor: _isListening
                              ? const Color(0xFF58D7D4)
                              : Colors.white.withValues(alpha: 0.08),
                          foregroundColor: _isListening
                              ? Colors.black
                              : Colors.white,
                          minimumSize: const Size.square(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Icon(
                          _isListening ? Icons.mic : Icons.mic_none_rounded,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 50,
                    width: 50,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _sendMessage,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size.square(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.sentAt,
    required this.isUser,
  });

  final String message;
  final DateTime sentAt;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: isUser
                ? const <Color>[Color(0xFFFFC857), Color(0xFFFFB547)]
                : const <Color>[Color(0xFF202833), Color(0xFF11171F)],
          ),
        ),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              message,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: isUser ? Colors.black : Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              DateFormat.jm().format(sentAt.toLocal()),
              style: theme.textTheme.bodySmall?.copyWith(
                color: isUser
                    ? Colors.black54
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFF202833), Color(0xFF11171F)],
          ),
        ),
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      ),
    );
  }
}
