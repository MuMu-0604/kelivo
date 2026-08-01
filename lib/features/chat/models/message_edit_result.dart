class MessageEditResult {
  final String content;
  final bool shouldSend;

  const MessageEditResult({required this.content, this.shouldSend = false});
}
