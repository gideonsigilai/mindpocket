enum ChatMode { local, remote }

enum MessageRole { user, assistant }

class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  final MessageRole role;
  final String content;

  ChatMessage copyWith({String? content}) =>
      ChatMessage(role: role, content: content ?? this.content);
}
