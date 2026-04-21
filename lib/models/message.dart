class Message {
  final String id;
  final String conversationId;
  final String role; // 'user' or 'ai'
  final String content;
  final String? imagePath;
  final String? audioPath;
  final DateTime timestamp;
  final String? reaction;
  final String? replyToId;
  final String? replyToContent;
  final String status; // 'sent', 'delivered', 'read'

  Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.imagePath,
    this.audioPath,
    required this.timestamp,
    this.reaction,
    this.replyToId,
    this.replyToContent,
    this.status = 'sent',
  });

  bool get isVoiceMessage => audioPath != null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversationId': conversationId,
      'role': role,
      'content': content,
      'imagePath': imagePath,
      'audioPath': audioPath,
      'timestamp': timestamp.toIso8601String(),
      'reaction': reaction,
      'replyToId': replyToId,
      'replyToContent': replyToContent,
      'status': status,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      conversationId: map['conversationId'] as String,
      role: map['role'] as String,
      content: map['content'] as String,
      imagePath: map['imagePath'] as String?,
      audioPath: map['audioPath'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      reaction: map['reaction'] as String?,
      replyToId: map['replyToId'] as String?,
      replyToContent: map['replyToContent'] as String?,
      status: (map['status'] as String?) ?? 'sent',
    );
  }

  Message copyWith({
    String? id,
    String? conversationId,
    String? role,
    String? content,
    String? imagePath,
    String? audioPath,
    DateTime? timestamp,
    String? reaction,
    String? replyToId,
    String? replyToContent,
    String? status,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      imagePath: imagePath ?? this.imagePath,
      audioPath: audioPath ?? this.audioPath,
      timestamp: timestamp ?? this.timestamp,
      reaction: reaction ?? this.reaction,
      replyToId: replyToId ?? this.replyToId,
      replyToContent: replyToContent ?? this.replyToContent,
      status: status ?? this.status,
    );
  }
}
