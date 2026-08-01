/// Common interface for Kelivo's built-in in-memory MCP servers.
abstract class KelivoInMemoryMcpServerEngine {
  Future<dynamic> handleMessage(dynamic message);

  void close();
}
