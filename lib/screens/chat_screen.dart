import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';

import '../data/database_helper.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../backends/chat_backend.dart';
import '../backends/litert_backend.dart';
import '../backends/gemini_backend.dart';
import '../backends/openrouter_backend.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

class ChatScreen extends StatefulWidget {
  final Conversation conversation;
  const ChatScreen({super.key, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Message> _messages = [];
  String? _selectedImagePath;
  String? _selectedTextFileContent;
  String? _selectedTextFileName;

  // Voice recording state
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _speechEnabled = false;
  bool _isRecording = false;
  String _transcribedWords = '';

  // Text-to-Speech
  final FlutterTts _flutterTts = FlutterTts();
  bool _lastInputWasVoice = false;

  ChatBackend? _backend;
  bool _isInitializing = true;
  bool _isGenerating = false;
  String? _initError;

  // Reply state
  Message? _replyingTo;

  // Fake status timers
  final List<Timer> _statusTimers = [];

  // Typing persona
  int _typingPersonaIndex = 0;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initializeBackend();
  }

  Future<void> _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize();
    } catch (e) {
      debugPrint('Speech init failed: $e');
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // Stop recording
      setState(() => _isRecording = false);
      await _speechToText.stop();
      if (_transcribedWords.isNotEmpty) {
        _sendMessage(
          overrideText: _transcribedWords,
          audioPath: 'voice_message',
        );
        _transcribedWords = '';
      }
    } else {
      // Start recording
      setState(() {
        _isRecording = true;
        _transcribedWords = '';
      });
      if (_speechEnabled) {
        await _speechToText.listen(onResult: _onSpeechResult);
      } else {
        setState(() => _isRecording = false);
      }
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (mounted) {
      setState(() {
        _transcribedWords = result.recognizedWords;
      });
    }
  }

  Future<void> _initializeBackend() async {
    // Load messages from DB
    final messages = await _db.getMessages(widget.conversation.id);
    if (mounted) {
      setState(() {
        _messages.addAll(messages);
      });
    }

    // Create the appropriate backend
    _backend = _createBackend();

    try {
      await _backend!.initialize();
      if (mounted) setState(() => _isInitializing = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _initError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }

    _scrollToBottom();
  }

  ChatBackend _createBackend() {
    final prompt = widget.conversation.effectiveSystemPrompt;
    switch (widget.conversation.backendType) {
      case BackendType.litert:
        return LiteRTBackend(
          modelSource: widget.conversation.modelIdentifier,
          systemPrompt: prompt,
        );
      case BackendType.gemini:
        return GeminiBackend(
          apiKey: widget.conversation.apiKey!,
          modelName: widget.conversation.modelIdentifier,
          systemPrompt: prompt,
        );
      case BackendType.openrouter:
        return OpenRouterBackend(
          apiKey: widget.conversation.apiKey!,
          modelName: widget.conversation.modelIdentifier,
          systemPrompt: prompt,
        );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _typingStatusText() {
    final name = widget.conversation.displayName;
    final options = [
      '$name is thinking...',
      '$name is pondering...',
      '$name is connecting neurons...',
      '$name is consulting the void...',
      '$name is brewing a response...',
      '$name is computing...',
      '$name is waking up...',
    ];
    return options[_typingPersonaIndex % options.length];
  }

  Future<void> _sendMessage({String? overrideText, String? audioPath}) async {
    final baseText = overrideText ?? _controller.text.trim();
    if ((baseText.isEmpty && audioPath == null) ||
        _isGenerating ||
        _backend == null ||
        _initError != null) {
      return;
    }

    _controller.clear();

    String finalContextText = baseText;
    if (_selectedTextFileContent != null && audioPath == null) {
      finalContextText =
          '[Attached file: $_selectedTextFileName]\n$_selectedTextFileContent\n\n$baseText';
    }

    // Prepend reply context
    if (_replyingTo != null) {
      final quoted = _replyingTo!.content.length > 100
          ? '${_replyingTo!.content.substring(0, 100)}...'
          : _replyingTo!.content;
      finalContextText = '> $quoted\n\n$finalContextText';
    }

    final userMessage = Message(
      id: const Uuid().v4(),
      conversationId: widget.conversation.id,
      role: 'user',
      content: baseText.isEmpty && audioPath != null
          ? (audioPath == 'voice_message' ? 'Voice Message' : 'Audio File')
          : baseText,
      imagePath: _selectedImagePath,
      audioPath: audioPath,
      timestamp: DateTime.now(),
      replyToId: _replyingTo?.id,
      replyToContent: _replyingTo?.content,
    );

    _lastInputWasVoice = audioPath == 'voice_message';

    setState(() {
      _messages.add(userMessage);
      _isGenerating = true;
      _selectedImagePath = null;
      _selectedTextFileContent = null;
      _selectedTextFileName = null;
      _replyingTo = null;
      _typingPersonaIndex = Random().nextInt(7);
    });

    await _db.insertMessage(userMessage);
    _scrollToBottom();

    // Fake status transitions
    _scheduleStatusUpdate(
      userMessage.id,
      'delivered',
      const Duration(milliseconds: 600),
    );

    // Get AI response
    try {
      final response = await _backend!.sendMessage(
        finalContextText,
        _messages.where((m) => m.id != userMessage.id).toList(),
        imagePath: userMessage.imagePath,
        audioPath: userMessage.audioPath == 'voice_message'
            ? null
            : userMessage.audioPath,
      );

      // Mark as read when AI responds
      _updateMessageStatus(userMessage.id, 'read');

      final aiMessage = Message(
        id: const Uuid().v4(),
        conversationId: widget.conversation.id,
        role: 'ai',
        content: response,
        timestamp: DateTime.now(),
      );

      setState(() {
        _messages.add(aiMessage);
        _isGenerating = false;
      });

      await _db.insertMessage(aiMessage);

      // Speak the response if user sent a voice message
      if (_lastInputWasVoice) {
        await _flutterTts.speak(response);
      }

      // Update conversation preview
      widget.conversation.lastMessage = response.length > 80
          ? '${response.substring(0, 80)}...'
          : response;
      widget.conversation.updatedAt = DateTime.now();
      await _db.updateConversation(widget.conversation);
    } catch (e) {
      _updateMessageStatus(userMessage.id, 'read');
      final errorMessage = Message(
        id: const Uuid().v4(),
        conversationId: widget.conversation.id,
        role: 'ai',
        content: '⚠️ Error: ${e.toString().replaceFirst("Exception: ", "")}',
        timestamp: DateTime.now(),
      );

      setState(() {
        _messages.add(errorMessage);
        _isGenerating = false;
      });

      await _db.insertMessage(errorMessage);
    }

    _scrollToBottom();
  }

  void _scheduleStatusUpdate(String messageId, String status, Duration delay) {
    final timer = Timer(delay, () => _updateMessageStatus(messageId, status));
    _statusTimers.add(timer);
  }

  Future<void> _updateMessageStatus(String messageId, String status) async {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    final updated = _messages[index].copyWith(status: status);
    setState(() {
      _messages[index] = updated;
    });
    await _db.updateMessage(updated);
  }

  void _setReply(Message message) {
    setState(() {
      _replyingTo = message;
    });
  }

  void _clearReply() {
    setState(() {
      _replyingTo = null;
    });
  }

  void _showReactionPicker(Message message) {
    final emojis = ['❤️', '😂', '👍', '🔥', '😮', '👏', '🎉', '💯'];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2332),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text(
                  'Add Reaction',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: emojis.map((emoji) {
                    return GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        await _setReaction(message, emoji);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D1520),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                if (message.reaction != null)
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _setReaction(message, null);
                    },
                    child: const Text(
                      'Remove reaction',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _setReaction(Message message, String? reaction) async {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index == -1) return;
    final updated = _messages[index].copyWith(reaction: reaction);
    setState(() {
      _messages[index] = updated;
    });
    await _db.updateMessage(updated);
  }

  void _showOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2332),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.white70),
                title: const Text(
                  'Rename',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _renameDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.psychology, color: Colors.white70),
                title: const Text(
                  'System Prompt',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  widget.conversation.systemPrompt.isEmpty
                      ? 'Using default'
                      : 'Custom',
                  style: const TextStyle(color: Colors.white30, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _systemPromptDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep, color: Colors.white70),
                title: const Text(
                  'Clear all messages',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _db.deleteMessages(widget.conversation.id);
                  widget.conversation.lastMessage = '';
                  widget.conversation.updatedAt = DateTime.now();
                  await _db.updateConversation(widget.conversation);
                  setState(() => _messages.clear());
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_forever,
                  color: Color(0xFFEF5350),
                ),
                title: const Text(
                  'Delete conversation',
                  style: TextStyle(color: Color(0xFFEF5350)),
                ),
                onTap: () async {
                  final nav = Navigator.of(context);
                  nav.pop();
                  await _db.deleteConversation(widget.conversation.id);
                  if (mounted) nav.pop();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _renameDialog() {
    final controller = TextEditingController(
      text: widget.conversation.displayName,
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A2332),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Rename', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Display name',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF0D1520),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E88E5),
              ),
              onPressed: () async {
                final newName = controller.text.trim();
                if (newName.isNotEmpty) {
                  widget.conversation.displayName = newName;
                  await _db.updateConversation(widget.conversation);
                  setState(() {});
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _systemPromptDialog() {
    final controller = TextEditingController(
      text: widget.conversation.systemPrompt,
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A2332),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'System Prompt',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Leave empty to use the default prompt. Changes take effect on new conversations or after clearing messages.',
                  style: TextStyle(color: Colors.white30, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 8,
                  minLines: 4,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Enter custom system prompt...',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: const Color(0xFF0D1520),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                controller.text = '';
              },
              child: const Text(
                'Reset to Default',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E88E5),
              ),
              onPressed: () async {
                widget.conversation.systemPrompt = controller.text;
                await _db.updateConversation(widget.conversation);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  String _backendLabel(BackendType type) {
    switch (type) {
      case BackendType.litert:
        return 'LiteRT (Local)';
      case BackendType.gemini:
        return 'Gemini API';
      case BackendType.openrouter:
        return 'OpenRouter';
    }
  }

  @override
  void dispose() {
    for (final t in _statusTimers) {
      t.cancel();
    }
    _flutterTts.stop();
    _backend?.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _speechToText.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1520),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.conversation.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              _backendLabel(widget.conversation.backendType),
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: _showOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          // Init error banner
          if (_initError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF3E1E1E),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Color(0xFFEF5350), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _initError!,
                      style: const TextStyle(
                        color: Color(0xFFEF5350),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Messages
          Expanded(
            child: _isInitializing
                ? _buildInitializingView()
                : _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(_messages[index], index);
                    },
                  ),
          ),

          // Typing indicator
          if (_isGenerating)
            Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 24, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF1E88E5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _typingStatusText(),
                    style: const TextStyle(color: Colors.white30, fontSize: 13),
                  ),
                ],
              ),
            ),

          // Selected Text File Preview
          if (_selectedTextFileName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              alignment: Alignment.centerLeft,
              child: InputChip(
                backgroundColor: const Color(0xFF1E88E5).withValues(alpha: 0.2),
                label: Text(
                  _selectedTextFileName!,
                  style: const TextStyle(color: Colors.white70),
                ),
                onDeleted: () => setState(() {
                  _selectedTextFileName = null;
                  _selectedTextFileContent = null;
                }),
                deleteIconColor: Colors.white54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),

          // Selected Image Preview
          if (_selectedImagePath != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(_selectedImagePath!),
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedImagePath = null),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Reply preview
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF1A2332),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E88E5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _replyingTo!.role == 'user'
                              ? 'You'
                              : widget.conversation.displayName,
                          style: const TextStyle(
                            color: Color(0xFF1E88E5),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _replyingTo!.content.length > 60
                              ? '${_replyingTo!.content.substring(0, 60)}...'
                              : _replyingTo!.content,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white54,
                      size: 18,
                    ),
                    onPressed: _clearReply,
                  ),
                ],
              ),
            ),

          // Recording Indicator
          if (_isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mic, color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Text(
                    _transcribedWords.isNotEmpty
                        ? _transcribedWords
                        : 'Listening...',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),

          // Input row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2332),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.add_circle_outline,
                            color: Colors.white70,
                          ),
                          onPressed: _pickTextFile,
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            style: const TextStyle(color: Colors.white),
                            maxLines: 4,
                            minLines: 1,
                            onChanged: (text) => setState(() {}),
                            decoration: const InputDecoration(
                              hintText: 'Text message',
                              hintStyle: TextStyle(color: Colors.white30),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.image_outlined,
                            color: Colors.white70,
                          ),
                          onPressed: _pickImage,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Send or Mic button
                _controller.text.trim().isNotEmpty ||
                        _selectedImagePath != null ||
                        _selectedTextFileName != null
                    ? GestureDetector(
                        onTap: _sendMessage,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Color(0xFF1E88E5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.send,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: _toggleRecording,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _isRecording
                                ? Colors.redAccent
                                : const Color(0xFF1A2332),
                            shape: BoxShape.circle,
                          ),
                          child: _isRecording
                              ? const Icon(
                                  Icons.stop,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : const Icon(
                                  Icons.mic,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTextFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      setState(() {
        _selectedTextFileName = result.files.single.name;
        _selectedTextFileContent = content;
      });
    }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedImagePath = result.files.single.path;
      });
    }
  }

  Widget _buildMessageBubble(Message message, int index) {
    final isUser = message.role == 'user';
    final time = DateFormat('h:mm a').format(message.timestamp);

    // Show date header if first message or day changed
    Widget? dateHeader;
    if (index == 0 ||
        _messages[index - 1].timestamp.day != message.timestamp.day) {
      final dateStr = _formatDateHeader(message.timestamp);
      dateHeader = Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2332),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            dateStr,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      );
    }

    Widget bubble = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF1E88E5) : const Color(0xFF1A2332),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Reply preview inside bubble
            if (message.replyToContent != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  message.replyToContent!,
                  style: TextStyle(
                    color: isUser
                        ? Colors.white.withValues(alpha: 0.85)
                        : Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (message.imagePath != null &&
                File(message.imagePath!).existsSync())
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(message.imagePath!),
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            // Message text / voice visualization
            SizedBox(
              width: double.infinity,
              child: message.isVoiceMessage
                  ? VoiceMessagePlayer(message: message, isUser: isUser)
                  : SelectableText(
                      message.content,
                      style: TextStyle(
                        color: isUser
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.87),
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    color: isUser ? Colors.white54 : Colors.white30,
                    fontSize: 11,
                  ),
                ),
                if (isUser) ...[
                  const SizedBox(width: 4),
                  _buildStatusTicks(message.status),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    // Swipe to reply
    bubble = Dismissible(
      key: Key('reply_${message.id}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        _setReply(message);
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        child: const Icon(Icons.reply, color: Color(0xFF1E88E5), size: 28),
      ),
      child: bubble,
    );

    // Long press reaction for AI messages
    if (!isUser) {
      bubble = GestureDetector(
        onLongPress: () => _showReactionPicker(message),
        child: bubble,
      );
    }

    return Column(
      crossAxisAlignment: isUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        ?dateHeader,
        bubble,
        if (message.reaction != null)
          Padding(
            padding: EdgeInsets.only(
              left: isUser ? 0 : 12,
              right: isUser ? 12 : 0,
              top: 2,
            ),
            child: GestureDetector(
              onTap: () => _showReactionPicker(message),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2332),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF243447)),
                ),
                child: Text(
                  message.reaction!,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusTicks(String status) {
    IconData icon;
    Color color;
    switch (status) {
      case 'sent':
        icon = Icons.done;
        color = Colors.white38;
        break;
      case 'delivered':
        icon = Icons.done_all;
        color = Colors.white38;
        break;
      case 'read':
        icon = Icons.done_all;
        color = const Color(0xFF4FC3F7);
        break;
      default:
        icon = Icons.done;
        color = Colors.white38;
    }
    return Icon(icon, size: 14, color: color);
  }

  String _formatDateHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(dt.year, dt.month, dt.day);

    if (msgDate == today) return 'Today';
    if (msgDate == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('MMMM d, yyyy').format(dt);
  }

  Widget _buildEmptyState() {
    final starters = [
      'Ask me to roast your code',
      'Explain quantum physics like I\'m 5',
      'Write a haiku about debugging',
      'Give me a workout plan for today',
      'Tell me a dad joke',
      'Help me plan a surprise party',
      'Summarize Romeo and Juliet in 3 sentences',
      'What should I cook with eggs and cheese?',
    ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Colors.white12,
            ),
            const SizedBox(height: 20),
            const Text(
              'Send a message to start',
              style: TextStyle(color: Colors.white24, fontSize: 16),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: starters.map((text) {
                return ActionChip(
                  backgroundColor: const Color(0xFF1A2332),
                  side: const BorderSide(color: Color(0xFF243447)),
                  label: Text(
                    text,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  onPressed: () {
                    _controller.text = text;
                    setState(() {});
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitializingView() {
    // For LiteRT backend, show download progress
    if (_backend is LiteRTBackend) {
      final litert = _backend as LiteRTBackend;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: litert.progress,
                builder: (context, progress, _) {
                  if (progress >= 0 && progress <= 1.0) {
                    // Download progress
                    return SizedBox(
                      width: 80,
                      height: 80,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: progress,
                            color: const Color(0xFF1E88E5),
                            strokeWidth: 4,
                          ),
                          Text(
                            '${(progress * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  } else {
                    // Indeterminate (loading model into memory)
                    return const CircularProgressIndicator(
                      color: Color(0xFF1E88E5),
                    );
                  }
                },
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder<String>(
                valueListenable: litert.statusText,
                builder: (context, status, _) {
                  return Text(
                    status,
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                    textAlign: TextAlign.center,
                  );
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Please be on this screen until the model is downloaded',
                style: TextStyle(color: Colors.white24, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // For API backends, simple spinner
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFF1E88E5)),
          SizedBox(height: 16),
          Text('Connecting...', style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }
}

class VoiceMessagePlayer extends StatefulWidget {
  final Message message;
  final bool isUser;

  const VoiceMessagePlayer({
    super.key,
    required this.message,
    required this.isUser,
  });

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
        if (_isPlaying) {
          _waveController.repeat(reverse: true);
        } else {
          _waveController.stop();
        }
      }
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
        });
        _waveController.stop();
      }
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _togglePlay() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      if (widget.message.audioPath != null &&
          widget.message.audioPath != 'voice_message') {
        if (File(widget.message.audioPath!).existsSync()) {
          await _audioPlayer.play(DeviceFileSource(widget.message.audioPath!));
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Audio file not found')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No actual audio file available for this message'),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _togglePlay,
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: widget.isUser
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.87),
                size: 28,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedBuilder(
              animation: _waveController,
              builder: (context, child) {
                return _buildWaveform();
              },
            ),
          ],
        ),
        if (widget.message.content != 'Voice Message' &&
            widget.message.content != 'Audio File') ...[
          const SizedBox(height: 8),
          SelectableText(
            widget.message.content,
            style: TextStyle(
              color: widget.isUser
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.87),
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWaveform() {
    final color = widget.isUser
        ? Colors.white
        : Colors.white.withValues(alpha: 0.87);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(16, (i) {
        final animValue = _isPlaying
            ? 0.5 + 0.5 * sin(_waveController.value * 2 * pi + i * 0.5)
            : 0.5;
        final height = 4 + 18 * animValue;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          width: 3,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
