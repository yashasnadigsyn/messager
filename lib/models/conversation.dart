enum BackendType { litert, gemini, openrouter }

const String defaultSystemPrompt = '''You are a close friend who is humorous and talks using single words or very short phrases (max 4-5 words). However, when asked for help, advice, or an opinion on a photo (like fashion tips), you must be genuinely helpful and give constructive tips, while keeping your response as concise and punchy as possible.
For example:
User: How are you?
You: Functional.
User: Does this white shirt and black pants look good on me?
You: Looks sharp! Great contrast, maybe add a watch.''';

class Conversation {
  final String id;
  final BackendType backendType;
  final String modelIdentifier; // file path, URL, or model name
  String displayName;
  final String? apiKey;
  String systemPrompt;
  final DateTime createdAt;
  DateTime updatedAt;
  String lastMessage;

  Conversation({
    required this.id,
    required this.backendType,
    required this.modelIdentifier,
    required this.displayName,
    this.apiKey,
    this.systemPrompt = '',
    required this.createdAt,
    required this.updatedAt,
    this.lastMessage = '',
  });

  /// Returns the effective system prompt (user-set or default)
  String get effectiveSystemPrompt =>
      systemPrompt.trim().isNotEmpty ? systemPrompt : defaultSystemPrompt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'backendType': backendType.name,
      'modelIdentifier': modelIdentifier,
      'displayName': displayName,
      'apiKey': apiKey,
      'systemPrompt': systemPrompt,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastMessage': lastMessage,
    };
  }

  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      id: map['id'] as String,
      backendType: BackendType.values.byName(map['backendType'] as String),
      modelIdentifier: map['modelIdentifier'] as String,
      displayName: map['displayName'] as String,
      apiKey: map['apiKey'] as String?,
      systemPrompt: (map['systemPrompt'] as String?) ?? '',
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      lastMessage: (map['lastMessage'] as String?) ?? '',
    );
  }
}
