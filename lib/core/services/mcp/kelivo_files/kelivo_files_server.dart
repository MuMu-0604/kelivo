import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../../../../utils/app_directories.dart';
import '../in_memory_mcp_server.dart';

typedef KelivoFileWorkspaceRootsProvider =
    Future<Map<String, Directory>> Function();

/// Built-in MCP server that lets the model operate on Kelivo files.
///
/// Built-in app workspaces accept relative paths. The `phone_storage` workspace
/// maps to Android external storage and also accepts absolute paths under that
/// root, such as `/storage/emulated/0/Download/a.txt`.
class KelivoFilesMcpServerEngine implements KelivoInMemoryMcpServerEngine {
  KelivoFilesMcpServerEngine({
    KelivoFileWorkspaceRootsProvider? workspaceRootsProvider,
  }) : _workspaceRootsProvider =
           workspaceRootsProvider ?? _defaultWorkspaceRoots;

  static const defaultReadLength = 8000;
  static const maximumReadLength = 50000;
  static const maximumReadBytes = 1024 * 1024;
  static const maximumBinaryReadBytes = 10 * 1024 * 1024;
  static const maximumSearchFileBytes = 1024 * 1024;
  static const defaultListLimit = 200;
  static const maximumListLimit = 1000;
  static const defaultSearchLimit = 100;
  static const defaultRecentScanLimit = 5000;
  static const maximumRecentScanLimit = 20000;
  static const defaultPreviewLength = 4000;
  static const maximumPreviewLength = 20000;
  static const maximumArchiveInputBytes = 100 * 1024 * 1024;
  static const maximumArchiveEntries = 5000;
  static const phoneStorageWorkspace = 'phone_storage';

  final KelivoFileWorkspaceRootsProvider _workspaceRootsProvider;
  bool _closed = false;
  static String _rememberedCurrentWorkspace = phoneStorageWorkspace;
  static bool _rememberedCurrentWorkspaceWasExplicit = false;
  String _currentWorkspace = _rememberedCurrentWorkspace;

  @override
  Future<dynamic> handleMessage(dynamic message) async {
    if (_closed) return null;

    if (message is List) {
      final out = <dynamic>[];
      for (final m in message) {
        out.add(await _handleSingle(m));
      }
      return out;
    }
    return await _handleSingle(message);
  }

  Future<Map<String, dynamic>> _handleSingle(dynamic raw) async {
    try {
      if (raw is! Map) {
        return _error(null, code: -32600, message: 'Invalid Request');
      }
      final req = raw.cast<String, dynamic>();
      final id = req['id'];
      final method = (req['method'] ?? '').toString();
      final params = (req['params'] is Map)
          ? (req['params'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      switch (method) {
        case mcp.McpProtocol.methodInitialize:
          return _ok(
            id,
            result: {
              'serverInfo': {'name': '@kelivo/files', 'version': '0.1.0'},
              'protocolVersion': mcp.McpProtocol.defaultVersion,
              'capabilities': {
                'tools': {'listChanged': false},
              },
            },
          );

        case mcp.McpProtocol.methodListTools:
          return _ok(id, result: {'tools': _toolDefinitions()});

        case mcp.McpProtocol.methodCallTool:
          final name = (params['name'] ?? '').toString();
          final arguments = (params['arguments'] is Map)
              ? (params['arguments'] as Map).cast<String, dynamic>()
              : <String, dynamic>{};
          return _ok(id, result: await _callTool(name, arguments));

        default:
          if (id == null) return _noop();
          return _error(id, code: -32601, message: 'Method not found: $method');
      }
    } catch (e) {
      return _error(null, code: -32603, message: 'Internal error: $e');
    }
  }

  Future<Map<String, dynamic>> _callTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      switch (name) {
        case 'kelivo_list_file_workspaces':
          return _okText(await _listWorkspaces());
        case 'kelivo_get_current_file_workspace':
          return _okText(await _getCurrentWorkspace());
        case 'kelivo_set_current_file_workspace':
          return _okText(await _setCurrentWorkspace(args));
        case 'kelivo_list_files':
          return _okText(await _listFiles(args));
        case 'kelivo_list_recent_files':
          return _okText(await _listRecentFiles(args));
        case 'kelivo_stat_file':
          return _okText(await _statFile(args));
        case 'kelivo_detect_mime_type':
          return _okText(await _detectMimeType(args));
        case 'kelivo_preview_file':
          return _okText(await _previewFile(args));
        case 'kelivo_hash_file':
          return _okText(await _hashFile(args));
        case 'kelivo_read_text_file':
          return _okText(await _readTextFile(args));
        case 'kelivo_read_file_base64':
          return _okText(await _readFileBase64(args));
        case 'kelivo_create_directory':
          return _okText(await _createDirectory(args));
        case 'kelivo_create_text_file':
          return _okText(await _writeTextFile(args, createMode: true));
        case 'kelivo_write_text_file':
          return _okText(await _writeTextFile(args, createMode: false));
        case 'kelivo_write_file_base64':
          return _okText(await _writeFileBase64(args));
        case 'kelivo_append_text_file':
          return _okText(await _appendTextFile(args));
        case 'kelivo_delete_file':
          return _okText(await _deleteFile(args));
        case 'kelivo_delete_files':
          return _okText(await _deleteFiles(args));
        case 'kelivo_move_file':
          return _okText(await _moveFile(args));
        case 'kelivo_copy_file':
          return _okText(await _copyFile(args));
        case 'kelivo_zip_files':
          return _okText(await _zipFiles(args));
        case 'kelivo_unzip_file':
          return _okText(await _unzipFile(args));
        case 'kelivo_search_files':
          return _okText(await _searchFiles(args));
        case 'kelivo_search_text':
          return _okText(await _searchText(args));
        default:
          return _err('Tool not found: $name');
      }
    } catch (e) {
      return _err(e.toString());
    }
  }

  Future<String> _listWorkspaces() async {
    final roots = await _workspaceRoots();
    _syncCurrentWorkspace(roots);
    final items = <Map<String, dynamic>>[];
    for (final entry in roots.entries) {
      if (entry.key != phoneStorageWorkspace) {
        await entry.value.create(recursive: true);
      }
      items.add({
        'name': entry.key,
        'active': entry.key == _currentWorkspace,
        'default': entry.key == phoneStorageWorkspace,
        'absolute_path': entry.value.path,
        'description': _workspaceDescription(entry.key),
      });
    }
    return _json({'current_workspace': _currentWorkspace, 'workspaces': items});
  }

  Future<String> _getCurrentWorkspace() async {
    final roots = await _workspaceRoots();
    _syncCurrentWorkspace(roots);
    return _json({
      'current_workspace': _currentWorkspace,
      'available_workspaces': roots.keys.toList()..sort(),
    });
  }

  Future<String> _setCurrentWorkspace(Map<String, dynamic> args) async {
    final workspace = _workspaceArg(args, requiredValue: true);
    final roots = await _workspaceRoots();
    final root = roots[workspace];
    if (root == null) {
      throw ArgumentError(
        'Unknown workspace "$workspace". Use kelivo_list_file_workspaces first.',
      );
    }
    if (workspace != phoneStorageWorkspace) {
      await root.create(recursive: true);
    }
    _currentWorkspace = workspace;
    _rememberedCurrentWorkspace = workspace;
    _rememberedCurrentWorkspaceWasExplicit = true;
    return _json({
      'ok': true,
      'current_workspace': _currentWorkspace,
      'absolute_path': root.path,
    });
  }

  Future<String> _listFiles(Map<String, dynamic> args) async {
    final resolved = await _resolvePath(args, allowRootPath: true);
    final type = await FileSystemEntity.type(resolved.path, followLinks: false);
    if (type != FileSystemEntityType.directory) {
      throw ArgumentError('Path is not a directory: ${resolved.relativePath}');
    }
    final recursive = _boolArg(args, 'recursive', defaultValue: false);
    final limit = _intArg(
      args,
      'limit',
      defaultValue: defaultListLimit,
      min: 1,
      max: maximumListLimit,
    );
    final typeFilter = _stringArg(
      args,
      'type',
      defaultValue: 'any',
    ).toLowerCase();
    if (!const {'any', 'file', 'directory'}.contains(typeFilter)) {
      throw ArgumentError('Invalid type: expected any, file, or directory.');
    }
    final extensionFilter = _extensionFilter(args['extension']);
    final sortBy = _stringArg(
      args,
      'sort_by',
      defaultValue: 'path',
    ).toLowerCase();
    if (!const {'path', 'modified', 'size', 'type'}.contains(sortBy)) {
      throw ArgumentError(
        'Invalid sort_by: expected path, modified, size, or type.',
      );
    }
    final descending = _boolArg(args, 'descending', defaultValue: false);
    final dir = Directory(resolved.path);
    final entries = <Map<String, dynamic>>[];
    await for (final entity in dir.list(
      recursive: recursive,
      followLinks: false,
    )) {
      final info = await _entityInfo(entity, resolved.rootPath);
      if (!_matchesInfoFilters(
        info,
        typeFilter: typeFilter,
        extensionFilter: extensionFilter,
      )) {
        continue;
      }
      entries.add(info);
    }
    _sortEntityInfos(entries, sortBy: sortBy, descending: descending);
    final limited = entries.take(limit).toList(growable: false);
    return _json({
      'workspace': resolved.workspace,
      'path': resolved.relativePath,
      'recursive': recursive,
      'type': typeFilter,
      if (extensionFilter != null) 'extension': extensionFilter,
      'sort_by': sortBy,
      'descending': descending,
      'limit': limit,
      'entries': limited,
      'truncated': entries.length > limit,
    });
  }

  Future<String> _listRecentFiles(Map<String, dynamic> args) async {
    final resolved = await _resolvePath(args, allowRootPath: true);
    final type = await FileSystemEntity.type(resolved.path, followLinks: false);
    if (type != FileSystemEntityType.directory) {
      throw ArgumentError('Path is not a directory: ${resolved.relativePath}');
    }
    final recursive = _boolArg(args, 'recursive', defaultValue: true);
    final limit = _intArg(
      args,
      'limit',
      defaultValue: 50,
      min: 1,
      max: maximumListLimit,
    );
    final scanLimit = _intArg(
      args,
      'scan_limit',
      defaultValue: defaultRecentScanLimit,
      min: 1,
      max: maximumRecentScanLimit,
    );
    final extensionFilter = _extensionFilter(args['extension']);
    final results = <Map<String, dynamic>>[];
    var scanned = 0;
    await for (final entity in Directory(
      resolved.path,
    ).list(recursive: recursive, followLinks: false)) {
      if (scanned >= scanLimit) break;
      scanned += 1;
      final info = await _entityInfo(entity, resolved.rootPath);
      if (!_matchesInfoFilters(
        info,
        typeFilter: 'file',
        extensionFilter: extensionFilter,
      )) {
        continue;
      }
      results.add(info);
    }
    _sortEntityInfos(results, sortBy: 'modified', descending: true);
    return _json({
      'workspace': resolved.workspace,
      'path': resolved.displayPath,
      'recursive': recursive,
      if (extensionFilter != null) 'extension': extensionFilter,
      'limit': limit,
      'scan_limit': scanLimit,
      'scanned': scanned,
      'entries': results.take(limit).toList(growable: false),
      'truncated': results.length > limit || scanned >= scanLimit,
    });
  }

  Future<String> _statFile(Map<String, dynamic> args) async {
    final resolved = await _resolvePath(args, allowRootPath: true);
    final type = await FileSystemEntity.type(resolved.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return _json({
        'exists': false,
        'workspace': resolved.workspace,
        'path': resolved.relativePath,
      });
    }
    return _json(
      await _entityInfo(_entityForType(type, resolved.path), resolved.rootPath),
    );
  }

  Future<String> _detectMimeType(Map<String, dynamic> args) async {
    final resolved = await _resolvePath(args);
    final type = await FileSystemEntity.type(resolved.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw ArgumentError('Path not found: ${resolved.displayPath}');
    }
    if (type == FileSystemEntityType.directory) {
      return _json({
        'workspace': resolved.workspace,
        'path': resolved.displayPath,
        'absolute_path': resolved.path,
        'type': 'directory',
        'mime_type': 'inode/directory',
        'source': 'filesystem',
      });
    }
    final mime = await _inferMimeType(File(resolved.path));
    return _json({
      'workspace': resolved.workspace,
      'path': resolved.displayPath,
      'absolute_path': resolved.path,
      'type': 'file',
      'mime_type': mime.mimeType,
      'source': mime.source,
      'extension': p.extension(resolved.path).toLowerCase(),
      'size_bytes': await File(resolved.path).length(),
    });
  }

  Future<String> _previewFile(Map<String, dynamic> args) async {
    final resolved = await _resolvePath(args, allowRootPath: true);
    final type = await FileSystemEntity.type(resolved.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw ArgumentError('Path not found: ${resolved.displayPath}');
    }
    if (type == FileSystemEntityType.directory) {
      final limit = _intArg(args, 'limit', defaultValue: 20, min: 1, max: 100);
      final entries = <Map<String, dynamic>>[];
      await for (final entity in Directory(
        resolved.path,
      ).list(recursive: false, followLinks: false)) {
        if (entries.length >= limit) break;
        entries.add(await _entityInfo(entity, resolved.rootPath));
      }
      _sortEntityInfos(entries, sortBy: 'path', descending: false);
      return _json({
        'workspace': resolved.workspace,
        'path': resolved.displayPath,
        'absolute_path': resolved.path,
        'kind': 'directory',
        'mime_type': 'inode/directory',
        'entry_preview_limit': limit,
        'entries': entries,
        'truncated': entries.length >= limit,
      });
    }

    final file = File(resolved.path);
    final bytes = await file.length();
    final mime = await _inferMimeType(file);
    final maxLength = _intArg(
      args,
      'max_length',
      defaultValue: defaultPreviewLength,
      min: 1,
      max: maximumPreviewLength,
    );
    if (_isTextualMime(mime.mimeType) && bytes <= maximumReadBytes) {
      try {
        final text = await file.readAsString(encoding: utf8);
        final bounded = _bounded(text, startIndex: 0, maxLength: maxLength);
        return _json({
          'workspace': resolved.workspace,
          'path': resolved.displayPath,
          'absolute_path': resolved.path,
          'kind': 'text',
          'mime_type': mime.mimeType,
          'size_bytes': bytes,
          'preview': bounded.content,
          'truncated': bounded.truncated,
          'total_characters': text.length,
        });
      } catch (_) {
        // Fall through to binary summary when UTF-8 decoding fails.
      }
    }

    if (_isZipPath(resolved.path) && bytes <= maximumArchiveInputBytes) {
      final entries = <Map<String, dynamic>>[];
      try {
        final input = InputFileStream(resolved.path);
        try {
          ZipDecoder().decodeStream(
            input,
            callback: (entry) {
              if (entries.length >= 50) return;
              entries.add({
                'path': entry.name,
                'type': entry.isDirectory ? 'directory' : 'file',
                'size_bytes': entry.isFile ? entry.size : null,
              });
            },
          );
        } finally {
          await input.close();
        }
        return _json({
          'workspace': resolved.workspace,
          'path': resolved.displayPath,
          'absolute_path': resolved.path,
          'kind': 'archive',
          'mime_type': mime.mimeType,
          'size_bytes': bytes,
          'entry_preview_limit': 50,
          'entries': entries,
          'truncated': entries.length >= 50,
        });
      } catch (_) {
        // Fall through to binary summary for damaged or encrypted zips.
      }
    }

    final header = await _readHeaderBytes(file, maxBytes: 32);
    return _json({
      'workspace': resolved.workspace,
      'path': resolved.displayPath,
      'absolute_path': resolved.path,
      'kind': 'binary',
      'mime_type': mime.mimeType,
      'size_bytes': bytes,
      'summary': _binarySummary(mime.mimeType, bytes),
      'header_hex': header
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
    });
  }

  Future<String> _hashFile(Map<String, dynamic> args) async {
    final resolved = await _resolvePath(args);
    final algorithm = _stringArg(
      args,
      'algorithm',
      defaultValue: 'sha256',
    ).toLowerCase();
    final type = await FileSystemEntity.type(resolved.path, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw ArgumentError('Path is not a file: ${resolved.displayPath}');
    }
    final digest = switch (algorithm) {
      'md5' => await crypto.md5.bind(File(resolved.path).openRead()).first,
      'sha1' => await crypto.sha1.bind(File(resolved.path).openRead()).first,
      'sha256' =>
        await crypto.sha256.bind(File(resolved.path).openRead()).first,
      _ => throw ArgumentError(
        'Invalid algorithm: expected sha256, sha1, or md5.',
      ),
    };
    return _json({
      'workspace': resolved.workspace,
      'path': resolved.displayPath,
      'absolute_path': resolved.path,
      'algorithm': algorithm,
      'hash': digest.toString(),
      'bytes': await File(resolved.path).length(),
    });
  }

  Future<String> _readTextFile(Map<String, dynamic> args) async {
    final resolved = await _resolvePath(args);
    final file = File(resolved.path);
    if (!await file.exists()) {
      throw ArgumentError('File not found: ${resolved.relativePath}');
    }
    final bytes = await file.length();
    if (bytes > maximumReadBytes) {
      throw ArgumentError(
        'File is too large to read as text ($bytes bytes, max $maximumReadBytes).',
      );
    }
    final maxLength = _intArg(
      args,
      'max_length',
      defaultValue: defaultReadLength,
      min: 1,
      max: maximumReadLength,
    );
    final startIndex = _intArg(args, 'start_index', defaultValue: 0, min: 0);
    final text = await file.readAsString(encoding: utf8);
    final bounded = _bounded(
      text,
      startIndex: startIndex,
      maxLength: maxLength,
    );
    return _json({
      'workspace': resolved.workspace,
      'path': resolved.relativePath,
      'absolute_path': resolved.path,
      'content': bounded.content,
      'start_index': bounded.start,
      'next_start_index': bounded.nextStartIndex,
      'truncated': bounded.truncated,
      'total_characters': text.length,
    });
  }

  Future<String> _readFileBase64(Map<String, dynamic> args) async {
    final resolved = await _resolvePath(args);
    final file = File(resolved.path);
    if (!await file.exists()) {
      throw ArgumentError('File not found: ${resolved.displayPath}');
    }
    final bytes = await file.length();
    if (bytes > maximumBinaryReadBytes) {
      throw ArgumentError(
        'File is too large to read as base64 ($bytes bytes, max $maximumBinaryReadBytes).',
      );
    }
    return _json({
      'workspace': resolved.workspace,
      'path': resolved.displayPath,
      'absolute_path': resolved.path,
      'encoding': 'base64',
      'bytes': bytes,
      'content_base64': base64Encode(await file.readAsBytes()),
    });
  }

  Future<String> _createDirectory(Map<String, dynamic> args) async {
    final resolved = await _resolvePath(args);
    final dir = Directory(resolved.path);
    final existed = await dir.exists();
    if (!existed) await dir.create(recursive: true);
    return _json({
      'ok': true,
      'action': existed ? 'already_exists' : 'created_directory',
      'workspace': resolved.workspace,
      'path': resolved.relativePath,
      'absolute_path': resolved.path,
    });
  }

  Future<String> _writeTextFile(
    Map<String, dynamic> args, {
    required bool createMode,
  }) async {
    final resolved = await _resolvePath(args);
    final content = _requiredString(args, 'content');
    final overwrite = _boolArg(
      args,
      'overwrite',
      defaultValue: createMode ? false : true,
    );
    final createParents = _boolArg(
      args,
      'create_parent_dirs',
      defaultValue: true,
    );
    final file = File(resolved.path);
    final exists = await file.exists();
    if (exists && !overwrite) {
      throw ArgumentError(
        'File already exists: ${resolved.relativePath}. Set overwrite=true to replace it.',
      );
    }
    await _ensureParent(file, createParents: createParents);
    await file.writeAsString(content, encoding: utf8, flush: true);
    return _json({
      'ok': true,
      'action': exists ? 'overwritten_text_file' : 'created_text_file',
      'workspace': resolved.workspace,
      'path': resolved.relativePath,
      'absolute_path': resolved.path,
      'characters': content.length,
      'bytes': await file.length(),
    });
  }

  Future<String> _appendTextFile(Map<String, dynamic> args) async {
    final resolved = await _resolvePath(args);
    final content = _requiredString(args, 'content');
    final createParents = _boolArg(
      args,
      'create_parent_dirs',
      defaultValue: true,
    );
    final file = File(resolved.path);
    final existed = await file.exists();
    await _ensureParent(file, createParents: createParents);
    await file.writeAsString(
      content,
      encoding: utf8,
      mode: FileMode.append,
      flush: true,
    );
    return _json({
      'ok': true,
      'action': existed ? 'appended_text_file' : 'created_text_file',
      'workspace': resolved.workspace,
      'path': resolved.relativePath,
      'absolute_path': resolved.path,
      'appended_characters': content.length,
      'bytes': await file.length(),
    });
  }

  Future<String> _writeFileBase64(Map<String, dynamic> args) async {
    final resolved = await _resolvePath(args);
    final content = _requiredString(args, 'content_base64');
    final overwrite = _boolArg(args, 'overwrite', defaultValue: true);
    final createParents = _boolArg(
      args,
      'create_parent_dirs',
      defaultValue: true,
    );
    final file = File(resolved.path);
    final exists = await file.exists();
    if (exists && !overwrite) {
      throw ArgumentError(
        'File already exists: ${resolved.displayPath}. Set overwrite=true to replace it.',
      );
    }
    final bytes = base64Decode(content.replaceAll(RegExp(r'\s'), ''));
    await _ensureParent(file, createParents: createParents);
    await file.writeAsBytes(bytes, flush: true);
    return _json({
      'ok': true,
      'action': exists ? 'overwritten_binary_file' : 'created_binary_file',
      'workspace': resolved.workspace,
      'path': resolved.displayPath,
      'absolute_path': resolved.path,
      'bytes': bytes.length,
    });
  }

  Future<String> _deleteFile(Map<String, dynamic> args) async {
    final resolved = await _resolvePath(args);
    final recursive = _boolArg(args, 'recursive', defaultValue: false);
    final type = await FileSystemEntity.type(resolved.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw ArgumentError('Path not found: ${resolved.relativePath}');
    }
    if (type == FileSystemEntityType.directory) {
      final dir = Directory(resolved.path);
      if (!recursive && !(await dir.list(followLinks: false).isEmpty)) {
        throw ArgumentError(
          'Directory is not empty: ${resolved.relativePath}. Set recursive=true to delete it.',
        );
      }
      await dir.delete(recursive: recursive);
      return _json({
        'ok': true,
        'action': 'deleted_directory',
        'workspace': resolved.workspace,
        'path': resolved.relativePath,
        'recursive': recursive,
      });
    }
    await File(resolved.path).delete();
    return _json({
      'ok': true,
      'action': 'deleted_file',
      'workspace': resolved.workspace,
      'path': resolved.relativePath,
    });
  }

  Future<String> _deleteFiles(Map<String, dynamic> args) async {
    final pathsAny = args['paths'];
    if (pathsAny is! List || pathsAny.isEmpty) {
      throw ArgumentError('Missing required argument: paths.');
    }
    final recursive = _boolArg(args, 'recursive', defaultValue: false);
    final continueOnError = _boolArg(
      args,
      'continue_on_error',
      defaultValue: true,
    );
    final results = <Map<String, dynamic>>[];
    for (final rawPath in pathsAny) {
      final path = rawPath.toString();
      try {
        final resolved = await _resolvePath({...args, 'path': path});
        final type = await FileSystemEntity.type(
          resolved.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.notFound) {
          throw ArgumentError('Path not found: ${resolved.displayPath}');
        }
        if (type == FileSystemEntityType.directory) {
          final dir = Directory(resolved.path);
          if (!recursive && !(await dir.list(followLinks: false).isEmpty)) {
            throw ArgumentError(
              'Directory is not empty: ${resolved.displayPath}. Set recursive=true to delete it.',
            );
          }
          await dir.delete(recursive: recursive);
          results.add({
            'ok': true,
            'path': resolved.displayPath,
            'action': 'deleted_directory',
          });
        } else {
          await File(resolved.path).delete();
          results.add({
            'ok': true,
            'path': resolved.displayPath,
            'action': 'deleted_file',
          });
        }
      } catch (e) {
        results.add({'ok': false, 'path': path, 'error': e.toString()});
        if (!continueOnError) break;
      }
    }
    return _json({
      'ok': results.every((item) => item['ok'] == true),
      'recursive': recursive,
      'continue_on_error': continueOnError,
      'deleted_count': results.where((item) => item['ok'] == true).length,
      'failed_count': results.where((item) => item['ok'] != true).length,
      'results': results,
    });
  }

  Future<String> _moveFile(Map<String, dynamic> args) async {
    final from = await _resolvePath(
      args,
      pathKey: 'from_path',
      workspaceKey: args.containsKey('from_workspace')
          ? 'from_workspace'
          : 'workspace',
    );
    final to = await _resolvePath(
      args,
      pathKey: 'to_path',
      workspaceKey: args.containsKey('to_workspace') ? 'to_workspace' : null,
      fallbackWorkspace: from.workspace,
    );
    final fromType = await FileSystemEntity.type(from.path, followLinks: false);
    if (fromType == FileSystemEntityType.notFound) {
      throw ArgumentError('Source path not found: ${from.relativePath}');
    }
    final toType = await FileSystemEntity.type(to.path, followLinks: false);
    final overwrite = _boolArg(args, 'overwrite', defaultValue: false);
    if (toType != FileSystemEntityType.notFound) {
      if (!overwrite) {
        throw ArgumentError(
          'Destination already exists: ${to.relativePath}. Set overwrite=true to replace a file.',
        );
      }
      if (toType == FileSystemEntityType.directory) {
        throw ArgumentError('Cannot overwrite a directory: ${to.relativePath}');
      }
      await File(to.path).delete();
    }
    final createParents = _boolArg(
      args,
      'create_parent_dirs',
      defaultValue: true,
    );
    await _ensureParent(File(to.path), createParents: createParents);
    if (fromType == FileSystemEntityType.directory) {
      await Directory(from.path).rename(to.path);
    } else {
      await File(from.path).rename(to.path);
    }
    return _json({
      'ok': true,
      'action': 'moved',
      'from_workspace': from.workspace,
      'to_workspace': to.workspace,
      'from_path': from.relativePath,
      'to_path': to.relativePath,
      'absolute_path': to.path,
    });
  }

  Future<String> _copyFile(Map<String, dynamic> args) async {
    final from = await _resolvePath(
      args,
      pathKey: 'from_path',
      workspaceKey: args.containsKey('from_workspace')
          ? 'from_workspace'
          : 'workspace',
    );
    final to = await _resolvePath(
      args,
      pathKey: 'to_path',
      workspaceKey: args.containsKey('to_workspace') ? 'to_workspace' : null,
      fallbackWorkspace: from.workspace,
    );
    final fromType = await FileSystemEntity.type(from.path, followLinks: false);
    if (fromType == FileSystemEntityType.notFound) {
      throw ArgumentError('Source path not found: ${from.displayPath}');
    }
    final toType = await FileSystemEntity.type(to.path, followLinks: false);
    final overwrite = _boolArg(args, 'overwrite', defaultValue: false);
    if (toType != FileSystemEntityType.notFound) {
      if (!overwrite) {
        throw ArgumentError(
          'Destination already exists: ${to.displayPath}. Set overwrite=true to replace a file.',
        );
      }
      if (toType == FileSystemEntityType.directory) {
        throw ArgumentError('Cannot overwrite a directory: ${to.displayPath}');
      }
      await File(to.path).delete();
    }
    final createParents = _boolArg(
      args,
      'create_parent_dirs',
      defaultValue: true,
    );
    await _ensureParent(File(to.path), createParents: createParents);
    if (fromType == FileSystemEntityType.directory) {
      await _copyDirectory(Directory(from.path), Directory(to.path));
    } else {
      await File(from.path).copy(to.path);
    }
    final copiedType = await FileSystemEntity.type(to.path, followLinks: false);
    final stat = copiedType == FileSystemEntityType.directory
        ? await Directory(to.path).stat()
        : await File(to.path).stat();
    return _json({
      'ok': true,
      'action': 'copied',
      'from_workspace': from.workspace,
      'to_workspace': to.workspace,
      'from_path': from.displayPath,
      'to_path': to.displayPath,
      'absolute_path': to.path,
      'type': copiedType == FileSystemEntityType.directory
          ? 'directory'
          : 'file',
      'size_bytes': copiedType == FileSystemEntityType.file ? stat.size : null,
    });
  }

  Future<String> _zipFiles(Map<String, dynamic> args) async {
    final pathsAny = args['paths'];
    if (pathsAny is! List || pathsAny.isEmpty) {
      throw ArgumentError('Missing required argument: paths.');
    }
    final destination = await _resolvePath(
      args,
      pathKey: 'destination_path',
      workspaceKey: args.containsKey('destination_workspace')
          ? 'destination_workspace'
          : 'workspace',
    );
    if (!_isZipPath(destination.path)) {
      throw ArgumentError('destination_path must end with .zip.');
    }
    final overwrite = _boolArg(args, 'overwrite', defaultValue: false);
    final createParents = _boolArg(
      args,
      'create_parent_dirs',
      defaultValue: true,
    );
    final includeRootDir = _boolArg(
      args,
      'include_root_dir',
      defaultValue: false,
    );
    final destinationFile = File(destination.path);
    if (await destinationFile.exists()) {
      if (!overwrite) {
        throw ArgumentError(
          'Destination already exists: ${destination.displayPath}. Set overwrite=true to replace it.',
        );
      }
      await destinationFile.delete();
    }
    await _ensureParent(destinationFile, createParents: createParents);

    final sources = <_ResolvedKelivoPath>[];
    for (final rawPath in pathsAny) {
      final source = await _resolvePath({...args, 'path': rawPath.toString()});
      if (p.equals(source.path, destination.path)) {
        throw ArgumentError('Cannot include destination zip in itself.');
      }
      final type = await FileSystemEntity.type(source.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        throw ArgumentError('Source path not found: ${source.displayPath}');
      }
      sources.add(source);
    }

    final encoder = ZipFileEncoder();
    var addedFiles = 0;
    var addedDirectories = 0;
    encoder.create(destination.path);
    try {
      for (final source in sources) {
        final type = await FileSystemEntity.type(
          source.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.directory) {
          final before = addedFiles;
          await encoder.addDirectory(
            Directory(source.path),
            includeDirName: includeRootDir,
            followLinks: false,
            filter: (entity, progress) {
              final entityType = FileSystemEntity.typeSync(
                entity.path,
                followLinks: false,
              );
              if (entityType == FileSystemEntityType.file) {
                addedFiles += 1;
              } else if (entityType == FileSystemEntityType.directory) {
                addedDirectories += 1;
              }
              if (addedFiles + addedDirectories > maximumArchiveEntries) {
                return ZipFileOperation.cancel;
              }
              return ZipFileOperation.include;
            },
          );
          if (addedFiles == before && includeRootDir) addedDirectories += 1;
        } else {
          final archiveName = p.posix.fromUri(
            p.toUri(p.basename(source.relativePath)),
          );
          await encoder.addFile(File(source.path), archiveName);
          addedFiles += 1;
        }
        if (addedFiles + addedDirectories > maximumArchiveEntries) {
          throw ArgumentError(
            'Too many archive entries, max $maximumArchiveEntries.',
          );
        }
      }
    } finally {
      await encoder.close();
    }

    return _json({
      'ok': true,
      'action': 'created_zip',
      'workspace': destination.workspace,
      'path': destination.displayPath,
      'absolute_path': destination.path,
      'source_count': sources.length,
      'files': addedFiles,
      'directories': addedDirectories,
      'bytes': await destinationFile.length(),
    });
  }

  Future<String> _unzipFile(Map<String, dynamic> args) async {
    final source = await _resolvePath(
      args,
      pathKey: 'zip_path',
      workspaceKey: args.containsKey('zip_workspace')
          ? 'zip_workspace'
          : 'workspace',
    );
    final destination = await _resolvePath(
      args,
      pathKey: 'destination_path',
      workspaceKey: args.containsKey('destination_workspace')
          ? 'destination_workspace'
          : 'workspace',
      allowRootPath: true,
    );
    if (!_isZipPath(source.path)) {
      throw ArgumentError('zip_path must end with .zip.');
    }
    final zipFile = File(source.path);
    if (!await zipFile.exists()) {
      throw ArgumentError('Zip file not found: ${source.displayPath}');
    }
    final zipBytes = await zipFile.length();
    if (zipBytes > maximumArchiveInputBytes) {
      throw ArgumentError(
        'Zip file is too large ($zipBytes bytes, max $maximumArchiveInputBytes).',
      );
    }
    final overwrite = _boolArg(args, 'overwrite', defaultValue: false);
    await Directory(destination.path).create(recursive: true);

    final input = InputFileStream(source.path);
    final archive = ZipDecoder().decodeStream(input);
    if (archive.length > maximumArchiveEntries) {
      await input.close();
      throw ArgumentError(
        'Zip has too many entries (${archive.length}, max $maximumArchiveEntries).',
      );
    }

    var extractedFiles = 0;
    var extractedDirectories = 0;
    final skipped = <String>[];
    final destinationRoot = p.normalize(destination.path);
    try {
      for (final entry in archive) {
        final safeName = _safeArchiveEntryName(entry.name);
        if (safeName == null) {
          skipped.add(entry.name);
          continue;
        }
        final outPath = p.normalize(p.join(destinationRoot, safeName));
        if (outPath != destinationRoot &&
            !p.isWithin(destinationRoot, outPath)) {
          skipped.add(entry.name);
          continue;
        }
        if (entry.isDirectory) {
          await Directory(outPath).create(recursive: true);
          extractedDirectories += 1;
          continue;
        }
        if (!entry.isFile || entry.isSymbolicLink) {
          skipped.add(entry.name);
          continue;
        }
        final outFile = File(outPath);
        if (await outFile.exists() && !overwrite) {
          skipped.add(entry.name);
          continue;
        }
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(
          entry.readBytes() ?? const <int>[],
          flush: true,
        );
        extractedFiles += 1;
      }
    } finally {
      for (final entry in archive) {
        await entry.close();
      }
      await input.close();
    }

    return _json({
      'ok': true,
      'action': 'unzipped',
      'zip_workspace': source.workspace,
      'zip_path': source.displayPath,
      'destination_workspace': destination.workspace,
      'destination_path': destination.displayPath,
      'absolute_path': destination.path,
      'entries': archive.length,
      'files': extractedFiles,
      'directories': extractedDirectories,
      'skipped_count': skipped.length,
      'skipped': skipped.take(50).toList(growable: false),
      'overwrite': overwrite,
    });
  }

  Future<String> _searchFiles(Map<String, dynamic> args) async {
    final resolved = await _resolvePath(args, allowRootPath: true);
    final query = _requiredString(args, 'query').toLowerCase();
    final recursive = _boolArg(args, 'recursive', defaultValue: true);
    final limit = _intArg(
      args,
      'limit',
      defaultValue: defaultSearchLimit,
      min: 1,
      max: maximumListLimit,
    );
    final results = <Map<String, dynamic>>[];
    await for (final entity in Directory(
      resolved.path,
    ).list(recursive: recursive, followLinks: false)) {
      if (results.length >= limit) break;
      final relative = p
          .relative(entity.path, from: resolved.rootPath)
          .replaceAll('\\', '/');
      if (p.basename(entity.path).toLowerCase().contains(query) ||
          relative.toLowerCase().contains(query)) {
        results.add(await _entityInfo(entity, resolved.rootPath));
      }
    }
    return _json({
      'workspace': resolved.workspace,
      'path': resolved.displayPath,
      'query': query,
      'recursive': recursive,
      'limit': limit,
      'matches': results,
      'truncated': results.length >= limit,
    });
  }

  Future<String> _searchText(Map<String, dynamic> args) async {
    final resolved = await _resolvePath(args, allowRootPath: true);
    final query = _requiredString(args, 'query');
    final caseSensitive = _boolArg(args, 'case_sensitive', defaultValue: false);
    final recursive = _boolArg(args, 'recursive', defaultValue: true);
    final limit = _intArg(
      args,
      'limit',
      defaultValue: defaultSearchLimit,
      min: 1,
      max: maximumListLimit,
    );
    final needle = caseSensitive ? query : query.toLowerCase();
    final matches = <Map<String, dynamic>>[];
    await for (final entity in Directory(
      resolved.path,
    ).list(recursive: recursive, followLinks: false)) {
      if (matches.length >= limit) break;
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type != FileSystemEntityType.file) continue;
      final file = File(entity.path);
      if (await file.length() > maximumSearchFileBytes) continue;
      String text;
      try {
        text = await file.readAsString(encoding: utf8);
      } catch (_) {
        continue;
      }
      final haystack = caseSensitive ? text : text.toLowerCase();
      final index = haystack.indexOf(needle);
      if (index < 0) continue;
      final line = '\n'.allMatches(text.substring(0, index)).length + 1;
      matches.add({
        ...(await _entityInfo(file, resolved.rootPath)),
        'line': line,
        'preview': _previewAround(text, index, query.length),
      });
    }
    return _json({
      'workspace': resolved.workspace,
      'path': resolved.displayPath,
      'query': query,
      'case_sensitive': caseSensitive,
      'recursive': recursive,
      'limit': limit,
      'matches': matches,
      'truncated': matches.length >= limit,
    });
  }

  Future<_ResolvedKelivoPath> _resolvePath(
    Map<String, dynamic> args, {
    String pathKey = 'path',
    String? workspaceKey = 'workspace',
    String? fallbackWorkspace,
    bool allowRootPath = false,
  }) async {
    await _ensureCurrentWorkspaceIsAvailable();
    final workspace = workspaceKey == null
        ? (fallbackWorkspace ?? _currentWorkspace)
        : _workspaceArg(
            args,
            key: workspaceKey,
            fallback: fallbackWorkspace ?? _currentWorkspace,
          );
    final roots = await _workspaceRoots();
    final root = roots[workspace];
    if (root == null) {
      throw ArgumentError(
        'Unknown workspace "$workspace". Use kelivo_list_file_workspaces first.',
      );
    }
    if (workspace != phoneStorageWorkspace) {
      await root.create(recursive: true);
    }

    final rawPath = (args[pathKey] ?? '').toString().trim();
    final rootNorm = p.normalize(root.path);
    if (workspace == phoneStorageWorkspace &&
        rootNorm == p.normalize('/storage/emulated/0')) {
      await _ensurePhoneStoragePermission();
    }
    final absolute = workspace == phoneStorageWorkspace
        ? _phoneStoragePath(rootNorm, rawPath, allowRootPath: allowRootPath)
        : _workspacePath(rootNorm, rawPath, allowRootPath: allowRootPath);
    final absoluteNorm = p.normalize(absolute);
    if (absoluteNorm != rootNorm && !p.isWithin(rootNorm, absoluteNorm)) {
      throw ArgumentError('Path escapes workspace: $rawPath');
    }
    await _rejectLinksInExistingAncestors(rootNorm, absoluteNorm);
    final relativePath = absoluteNorm == rootNorm
        ? ''
        : p.relative(absoluteNorm, from: rootNorm).replaceAll('\\', '/');
    return _ResolvedKelivoPath(
      workspace: workspace,
      rootPath: rootNorm,
      path: absoluteNorm,
      relativePath: relativePath,
      displayPath: workspace == phoneStorageWorkspace
          ? p.join('/storage/emulated/0', relativePath).replaceAll('\\', '/')
          : relativePath,
    );
  }

  Future<Map<String, Directory>> _workspaceRoots() async {
    final raw = await _workspaceRootsProvider();
    final out = <String, Directory>{};
    for (final entry in raw.entries) {
      out[_normalizeWorkspace(entry.key)] = entry.value;
    }
    return out;
  }

  Future<void> _ensureCurrentWorkspaceIsAvailable() async {
    final roots = await _workspaceRoots();
    _syncCurrentWorkspace(roots);
  }

  void _syncCurrentWorkspace(Map<String, Directory> roots) {
    if (roots.isEmpty) return;
    if (!roots.containsKey(_currentWorkspace)) {
      _currentWorkspace = _fallbackWorkspace(roots);
      _rememberedCurrentWorkspace = _currentWorkspace;
      _rememberedCurrentWorkspaceWasExplicit = false;
      return;
    }
    if (!_rememberedCurrentWorkspaceWasExplicit &&
        roots.containsKey(phoneStorageWorkspace) &&
        _currentWorkspace != phoneStorageWorkspace) {
      _currentWorkspace = phoneStorageWorkspace;
      _rememberedCurrentWorkspace = _currentWorkspace;
    }
  }

  static void resetRememberedWorkspaceForTests() {
    _rememberedCurrentWorkspace = phoneStorageWorkspace;
    _rememberedCurrentWorkspaceWasExplicit = false;
  }

  static String _fallbackWorkspace(Map<String, Directory> roots) {
    if (roots.containsKey(phoneStorageWorkspace)) return phoneStorageWorkspace;
    if (roots.containsKey('documents')) return 'documents';
    return roots.keys.first;
  }

  static Future<Map<String, Directory>> _defaultWorkspaceRoots() async {
    final appData = await AppDirectories.getAppDataDirectory();
    final managedRoot = Directory(p.join(appData.path, 'mcp_files'));
    final cacheRoot = await AppDirectories.getCacheDirectory();
    final roots = {
      'documents': Directory(p.join(managedRoot.path, 'documents')),
      'exports': Directory(p.join(managedRoot.path, 'exports')),
      'scratch': Directory(p.join(managedRoot.path, 'scratch')),
      'uploads': await AppDirectories.getUploadDirectory(),
      'images': await AppDirectories.getImagesDirectory(),
      'cache': Directory(p.join(cacheRoot.path, 'mcp_files')),
      'fonts': await AppDirectories.getFontsDirectory(),
    };
    final phoneRoot = _defaultPhoneStorageRoot();
    if (phoneRoot != null) roots[phoneStorageWorkspace] = phoneRoot;
    return roots;
  }

  static Directory? _defaultPhoneStorageRoot() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return Directory('/storage/emulated/0');
    }
    return null;
  }

  static Future<void> _ensurePhoneStoragePermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final manage = await Permission.manageExternalStorage.status;
    if (manage.isGranted) return;
    final requested = await Permission.manageExternalStorage.request();
    if (requested.isGranted) return;
    final storage = await Permission.storage.status;
    if (storage.isGranted) return;
    final storageRequested = await Permission.storage.request();
    if (storageRequested.isGranted) return;
    throw StateError('未获得手机存储访问权限。请在系统设置中允许 Kelivo 的“所有文件访问权限”。');
  }

  static String _workspacePath(
    String rootPath,
    String rawPath, {
    required bool allowRootPath,
  }) {
    final parts = _safeRelativeParts(rawPath, allowRootPath: allowRootPath);
    return parts.isEmpty ? rootPath : p.joinAll([rootPath, ...parts]);
  }

  static String _phoneStoragePath(
    String rootPath,
    String rawPath, {
    required bool allowRootPath,
  }) {
    if (rawPath.contains('\u0000')) {
      throw ArgumentError('Path contains a null byte.');
    }
    var normalized = rawPath.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) {
      if (allowRootPath) return rootPath;
      throw ArgumentError('Path must not be empty.');
    }
    if (RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(normalized)) {
      throw ArgumentError('Path must not include a URI scheme: $rawPath');
    }
    normalized = _stripPhoneStoragePrefix(normalized);
    final parts = _safeRelativeParts(normalized, allowRootPath: allowRootPath);
    return parts.isEmpty ? rootPath : p.joinAll([rootPath, ...parts]);
  }

  static String _stripPhoneStoragePrefix(String path) {
    var value = path;
    for (final prefix in const [
      '/storage/emulated/0',
      '/sdcard',
      '/mnt/sdcard',
    ]) {
      if (value == prefix) {
        return '';
      }
      if (value.startsWith('$prefix/')) {
        return value.substring(prefix.length + 1);
      }
    }
    if (value.startsWith('/')) {
      throw ArgumentError(
        'phone_storage only allows paths under /storage/emulated/0 or /sdcard: $path',
      );
    }
    return value;
  }

  String _workspaceArg(
    Map<String, dynamic> args, {
    String key = 'workspace',
    String? fallback,
    bool requiredValue = false,
  }) {
    final value = args[key];
    if (value == null || value.toString().trim().isEmpty) {
      if (requiredValue) throw ArgumentError('Missing required argument: $key');
      return _normalizeWorkspace(fallback ?? _currentWorkspace);
    }
    final raw = value.toString();
    return _normalizeWorkspace(raw);
  }

  static String _normalizeWorkspace(String raw) {
    final value = raw.trim().toLowerCase().replaceAll('-', '_');
    switch (value) {
      case '':
      case 'doc':
      case 'docs':
      case 'document':
      case 'documents':
        return 'documents';
      case 'export':
      case 'exports':
        return 'exports';
      case 'tmp':
      case 'temp':
      case 'scratch':
        return 'scratch';
      case 'upload':
      case 'uploads':
        return 'uploads';
      default:
        return value;
    }
  }

  static List<String> _safeRelativeParts(
    String rawPath, {
    required bool allowRootPath,
  }) {
    if (rawPath.contains('\u0000')) {
      throw ArgumentError('Path contains a null byte.');
    }
    final normalized = rawPath.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) {
      if (allowRootPath) return const <String>[];
      throw ArgumentError('Path must not be empty.');
    }
    if (normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:/').hasMatch(normalized)) {
      throw ArgumentError('Path must be relative, not absolute: $rawPath');
    }
    if (RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(normalized)) {
      throw ArgumentError('Path must not include a URI scheme: $rawPath');
    }
    final parts = <String>[];
    for (final part in normalized.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') throw ArgumentError('Path must not contain "..".');
      parts.add(part);
    }
    if (parts.isEmpty && !allowRootPath) {
      throw ArgumentError('Path must not be empty.');
    }
    return parts;
  }

  static Future<void> _ensureParent(
    File file, {
    required bool createParents,
  }) async {
    final parent = file.parent;
    if (await parent.exists()) return;
    if (!createParents) {
      throw ArgumentError('Parent directory does not exist: ${parent.path}');
    }
    await parent.create(recursive: true);
  }

  static Future<void> _copyDirectory(Directory source, Directory target) async {
    if (!await target.exists()) await target.create(recursive: true);
    await for (final entity in source.list(
      recursive: false,
      followLinks: false,
    )) {
      final name = p.basename(entity.path);
      final targetPath = p.join(target.path, name);
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await _copyDirectory(Directory(entity.path), Directory(targetPath));
      } else if (type == FileSystemEntityType.file) {
        await File(entity.path).copy(targetPath);
      }
    }
  }

  static Future<_MimeDetection> _inferMimeType(File file) async {
    final name = p.basename(file.path).toLowerCase();
    final header = await _readHeaderBytes(file, maxBytes: 16);
    final magic = _mimeFromHeader(header);
    if (magic != null) return _MimeDetection(magic, 'magic');
    final extension = _mimeFromExtension(name);
    if (extension != null) return _MimeDetection(extension, 'extension');
    return const _MimeDetection('application/octet-stream', 'fallback');
  }

  static Future<List<int>> _readHeaderBytes(
    File file, {
    required int maxBytes,
  }) async {
    if (!await file.exists()) return const <int>[];
    final length = await file.length();
    if (length <= 0) return const <int>[];
    final raf = await file.open();
    try {
      return await raf.read(math.min(length, maxBytes).toInt());
    } finally {
      await raf.close();
    }
  }

  static String? _mimeFromHeader(List<int> bytes) {
    bool hasPrefix(List<int> prefix) {
      if (bytes.length < prefix.length) return false;
      for (var i = 0; i < prefix.length; i++) {
        if (bytes[i] != prefix[i]) return false;
      }
      return true;
    }

    if (hasPrefix(const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (hasPrefix(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (hasPrefix(const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
    if (hasPrefix(const [0x25, 0x50, 0x44, 0x46])) return 'application/pdf';
    if (hasPrefix(const [0x50, 0x4B, 0x03, 0x04]) ||
        hasPrefix(const [0x50, 0x4B, 0x05, 0x06]) ||
        hasPrefix(const [0x50, 0x4B, 0x07, 0x08])) {
      return 'application/zip';
    }
    if (hasPrefix(const [0x1F, 0x8B])) return 'application/gzip';
    if (hasPrefix(const [0x52, 0x61, 0x72, 0x21])) {
      return 'application/vnd.rar';
    }
    if (hasPrefix(const [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])) {
      return 'application/x-7z-compressed';
    }
    if (hasPrefix(const [0x42, 0x4D])) return 'image/bmp';
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }

  static String? _mimeFromExtension(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.txt') ||
        lower.endsWith('.log') ||
        lower.endsWith('.md') ||
        lower.endsWith('.markdown')) {
      return 'text/plain';
    }
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.jsonl')) return 'application/x-ndjson';
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    if (lower.endsWith('.xml')) return 'application/xml';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return 'application/yaml';
    }
    if (lower.endsWith('.dart') ||
        lower.endsWith('.kt') ||
        lower.endsWith('.java') ||
        lower.endsWith('.js') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.tsx') ||
        lower.endsWith('.jsx') ||
        lower.endsWith('.py') ||
        lower.endsWith('.sh') ||
        lower.endsWith('.css')) {
      return 'text/plain';
    }
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.zip')) return 'application/zip';
    if (lower.endsWith('.gz')) return 'application/gzip';
    if (lower.endsWith('.apk')) {
      return 'application/vnd.android.package-archive';
    }
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.webm')) return 'video/webm';
    return null;
  }

  static bool _isTextualMime(String mimeType) {
    return mimeType.startsWith('text/') ||
        const {
          'application/json',
          'application/xml',
          'application/yaml',
          'application/x-ndjson',
          'application/javascript',
        }.contains(mimeType);
  }

  static bool _isZipPath(String path) => path.toLowerCase().endsWith('.zip');

  static String _binarySummary(String mimeType, int bytes) {
    if (mimeType.startsWith('image/')) return '图片文件，建议按 base64 读取或作为图片附件使用。';
    if (mimeType.startsWith('audio/')) return '音频文件，适合转写、播放或作为附件处理。';
    if (mimeType.startsWith('video/')) return '视频文件，当前仅返回元信息摘要。';
    if (mimeType == 'application/pdf') return 'PDF 文件，当前返回元信息摘要，可作为文档附件处理。';
    if (mimeType == 'application/zip') {
      return 'ZIP 压缩包，可用 kelivo_unzip_file 解压或预览条目。';
    }
    return '二进制文件，当前返回类型、大小和文件头摘要。';
  }

  static String? _safeArchiveEntryName(String rawName) {
    final normalized = rawName.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) return null;
    if (normalized.startsWith('/') || normalized.contains('://')) return null;
    final parts = p.posix.split(p.posix.normalize(normalized));
    if (parts.any((part) => part == '..')) return null;
    final joined = p.posix.joinAll(parts.where((part) => part != '.'));
    return joined.isEmpty ? null : joined;
  }

  static Future<void> _rejectLinksInExistingAncestors(
    String rootPath,
    String targetPath,
  ) async {
    final rootParts = p.split(rootPath);
    final targetParts = p.split(targetPath);
    if (targetParts.length < rootParts.length) return;

    var current = p.joinAll(rootParts);
    for (var i = rootParts.length; i < targetParts.length; i++) {
      current = p.join(current, targetParts[i]);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.notFound) break;
      if (type == FileSystemEntityType.link) {
        throw ArgumentError('Path contains a symbolic link: $current');
      }
    }
  }

  static Future<Map<String, dynamic>> _entityInfo(
    FileSystemEntity entity,
    String rootPath,
  ) async {
    final stat = await entity.stat();
    final type = stat.type == FileSystemEntityType.directory
        ? 'directory'
        : stat.type == FileSystemEntityType.file
        ? 'file'
        : 'other';
    return {
      'path': p.relative(entity.path, from: rootPath).replaceAll('\\', '/'),
      'absolute_path': p.normalize(entity.path),
      'type': type,
      'size_bytes': type == 'file' ? stat.size : null,
      'modified': stat.modified.toIso8601String(),
    };
  }

  static bool _matchesInfoFilters(
    Map<String, dynamic> info, {
    required String typeFilter,
    required String? extensionFilter,
  }) {
    if (typeFilter != 'any' && info['type'] != typeFilter) return false;
    if (extensionFilter == null) return true;
    if (info['type'] != 'file') return false;
    final ext = p.extension(info['path'].toString()).toLowerCase();
    return ext == extensionFilter;
  }

  static void _sortEntityInfos(
    List<Map<String, dynamic>> entries, {
    required String sortBy,
    required bool descending,
  }) {
    int compareValues(dynamic a, dynamic b) {
      if (a is num && b is num) return a.compareTo(b);
      return a.toString().compareTo(b.toString());
    }

    dynamic value(Map<String, dynamic> item) {
      return switch (sortBy) {
        'modified' => item['modified'] ?? '',
        'size' => item['size_bytes'] ?? -1,
        'type' => item['type'] ?? '',
        _ => item['path'] ?? '',
      };
    }

    entries.sort((a, b) {
      final cmp = compareValues(value(a), value(b));
      if (cmp == 0) {
        return (a['path'] ?? '').toString().compareTo(
          (b['path'] ?? '').toString(),
        );
      }
      return descending ? -cmp : cmp;
    });
  }

  static FileSystemEntity _entityForType(
    FileSystemEntityType type,
    String path,
  ) {
    if (type == FileSystemEntityType.directory) return Directory(path);
    return File(path);
  }

  static String _previewAround(String text, int index, int length) {
    final start = math.max(0, index - 80).toInt();
    final end = math
        .min(text.length, index + math.max(length, 1).toInt() + 80)
        .toInt();
    return text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static _BoundedText _bounded(
    String text, {
    required int startIndex,
    required int maxLength,
  }) {
    if (startIndex >= text.length) {
      return _BoundedText(
        content: '',
        start: startIndex,
        nextStartIndex: null,
        truncated: false,
      );
    }

    var start = startIndex;
    if (start > 0 && _isLowSurrogate(text.codeUnitAt(start))) {
      start -= 1;
    }
    var end = math.min(start + maxLength, text.length);
    if (end < text.length &&
        end > start &&
        _isHighSurrogate(text.codeUnitAt(end - 1)) &&
        _isLowSurrogate(text.codeUnitAt(end))) {
      end = end - start == 1 ? end + 1 : end - 1;
    }
    return _BoundedText(
      content: text.substring(start, end),
      start: start,
      nextStartIndex: end < text.length ? end : null,
      truncated: end < text.length,
    );
  }

  static bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  static bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

  static String _requiredString(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value == null) throw ArgumentError('Missing required argument: $key');
    return value.toString();
  }

  static String _stringArg(
    Map<String, dynamic> args,
    String key, {
    required String defaultValue,
  }) {
    final value = args[key];
    if (value == null) return defaultValue;
    final text = value.toString().trim();
    return text.isEmpty ? defaultValue : text;
  }

  static String? _extensionFilter(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty || text == '*') return null;
    final ext = text.startsWith('.') ? text : '.$text';
    if (ext.contains('/') || ext.contains('\\') || ext.contains('..')) {
      throw ArgumentError('Invalid extension filter: $value');
    }
    return ext;
  }

  static bool _boolArg(
    Map<String, dynamic> args,
    String key, {
    required bool defaultValue,
  }) {
    final value = args[key];
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is String) {
      final s = value.toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
    }
    throw ArgumentError('Invalid $key: expected a boolean.');
  }

  static int _intArg(
    Map<String, dynamic> args,
    String key, {
    required int defaultValue,
    int? min,
    int? max,
  }) {
    final value = args[key];
    int parsed;
    if (value == null) {
      parsed = defaultValue;
    } else if (value is int) {
      parsed = value;
    } else if (value is num &&
        value.isFinite &&
        value == value.roundToDouble()) {
      parsed = value.toInt();
    } else if (value is String && int.tryParse(value) != null) {
      parsed = int.parse(value);
    } else {
      throw ArgumentError('Invalid $key: expected an integer.');
    }
    if (min != null && parsed < min) {
      throw ArgumentError('Invalid $key: expected at least $min.');
    }
    if (max != null && parsed > max) {
      throw ArgumentError('Invalid $key: expected at most $max.');
    }
    return parsed;
  }

  static String _workspaceDescription(String workspace) {
    switch (workspace) {
      case 'documents':
        return 'Kelivo 管理的默认文档工作区，适合保存用户创建的文件。';
      case 'exports':
        return 'Kelivo 管理的导出工作区，适合保存准备分享或导出的文件。';
      case 'scratch':
        return 'Kelivo 管理的草稿工作区，适合临时文件和中间产物。';
      case 'uploads':
        return 'Kelivo 导入或上传文件所在的工作区。';
      case 'images':
        return 'Kelivo 保存图片的工作区。';
      case 'cache':
        return 'Kelivo 管理的缓存文件工作区。';
      case 'fonts':
        return '用户导入字体文件所在的工作区。';
      case phoneStorageWorkspace:
        return '手机共享存储根目录。Android 需要授予“所有文件访问权限”。';
      default:
        return 'Kelivo 文件工作区。';
    }
  }

  static String _json(Map<String, dynamic> value) =>
      const JsonEncoder.withIndent('  ').convert(value);

  static Map<String, dynamic> _okText(String text) => {
    'content': [
      {'type': 'text', 'text': text},
    ],
    'isStreaming': false,
    'isError': false,
  };

  static Map<String, dynamic> _err(String message) => {
    'content': [
      {'type': 'text', 'text': message},
    ],
    'isStreaming': false,
    'isError': true,
  };

  Map<String, dynamic> _ok(dynamic id, {required Map<String, dynamic> result}) {
    return {'jsonrpc': '2.0', if (id != null) 'id': id, 'result': result};
  }

  Map<String, dynamic> _error(
    dynamic id, {
    required int code,
    required String message,
  }) {
    return {
      'jsonrpc': '2.0',
      if (id != null) 'id': id,
      'error': {'code': code, 'message': message},
    };
  }

  Map<String, dynamic> _noop() => {'jsonrpc': '2.0'};

  List<Map<String, dynamic>> _toolDefinitions() => [
    {
      'name': 'kelivo_list_file_workspaces',
      'description':
          '列出 Kelivo 文件工具可访问的工作区。默认工作区是手机可见目录 /storage/emulated/0；只有用户明确要求切换位置时才需要查看其它工作区。',
      'inputSchema': _emptySchema(),
    },
    {
      'name': 'kelivo_get_current_file_workspace',
      'description': '返回当前默认文件工作区。通常应保持为 phone_storage，即 /storage/emulated/0。',
      'inputSchema': _emptySchema(),
    },
    {
      'name': 'kelivo_set_current_file_workspace',
      'description':
          '切换当前默认文件工作区。只有用户明确要求切换到其它工作区时才调用；日常文件操作默认使用 phone_storage。',
      'inputSchema': {
        'type': 'object',
        'properties': _workspaceProperty(),
        'required': ['workspace'],
      },
    },
    {
      'name': 'kelivo_list_files',
      'description':
          '列出目录内容。默认在手机可见目录 /storage/emulated/0 下操作；支持按类型/后缀过滤，并按路径、修改时间、大小或类型排序。',
      'inputSchema': _workspacePathSchema(
        requiredPath: false,
        extraProperties: {
          'recursive': {
            'type': 'boolean',
            'description': '是否递归列出子目录。',
            'default': false,
          },
          'limit': {
            'type': 'integer',
            'description': '最多返回多少个条目。',
            'default': defaultListLimit,
          },
          'type': {
            'type': 'string',
            'description': '只返回指定类型：any、file 或 directory。',
            'enum': ['any', 'file', 'directory'],
            'default': 'any',
          },
          'extension': {
            'type': 'string',
            'description': '可选文件后缀过滤，例如 txt、.jpg。仅对文件生效。',
          },
          'sort_by': {
            'type': 'string',
            'description': '排序字段：path、modified、size 或 type。',
            'enum': ['path', 'modified', 'size', 'type'],
            'default': 'path',
          },
          'descending': {
            'type': 'boolean',
            'description': '是否倒序排序。',
            'default': false,
          },
        },
      ),
    },
    {
      'name': 'kelivo_list_recent_files',
      'description': '按修改时间倒序列出最近文件，适合快速找到下载、截图、文档等新文件。',
      'inputSchema': _workspacePathSchema(
        requiredPath: false,
        extraProperties: {
          'recursive': {
            'type': 'boolean',
            'description': '是否递归扫描子目录。',
            'default': true,
          },
          'limit': {
            'type': 'integer',
            'description': '最多返回多少个最近文件。',
            'default': 50,
          },
          'scan_limit': {
            'type': 'integer',
            'description': '最多扫描多少个条目，避免在手机大目录里耗时过久。',
            'default': defaultRecentScanLimit,
          },
          'extension': {
            'type': 'string',
            'description': '可选文件后缀过滤，例如 txt、.jpg、pdf。',
          },
        },
      ),
    },
    {
      'name': 'kelivo_stat_file',
      'description': '查看文件或目录元数据，例如是否存在、类型、大小和修改时间。',
      'inputSchema': _workspacePathSchema(),
    },
    {
      'name': 'kelivo_detect_mime_type',
      'description': '识别文件 MIME 类型。优先根据文件头判断，无法判断时回退到扩展名。',
      'inputSchema': _workspacePathSchema(),
    },
    {
      'name': 'kelivo_preview_file',
      'description':
          '生成文件预览摘要。文本返回开头内容，目录返回部分条目，ZIP 返回压缩包条目预览，二进制返回类型、大小和文件头摘要。',
      'inputSchema': _workspacePathSchema(
        extraProperties: {
          'max_length': {
            'type': 'integer',
            'description': '文本预览最多返回多少个字符。',
            'default': defaultPreviewLength,
          },
          'limit': {
            'type': 'integer',
            'description': '目录预览最多返回多少个条目。',
            'default': 20,
          },
        },
      ),
    },
    {
      'name': 'kelivo_hash_file',
      'description': '计算文件哈希，支持 sha256、sha1、md5，适合校验下载文件或 APK。',
      'inputSchema': _workspacePathSchema(
        extraProperties: {
          'algorithm': {
            'type': 'string',
            'description': '哈希算法。',
            'enum': ['sha256', 'sha1', 'md5'],
            'default': 'sha256',
          },
        },
      ),
    },
    {
      'name': 'kelivo_read_text_file',
      'description': '读取 UTF-8 文本文件。长文件可用 start_index 和 max_length 分页读取。',
      'inputSchema': _workspacePathSchema(
        extraProperties: {
          'max_length': {
            'type': 'integer',
            'description': '本次最多返回多少个字符。',
            'default': defaultReadLength,
          },
          'start_index': {
            'type': 'integer',
            'description': '从哪个字符位置开始读取，用于继续读取被截断的内容。',
            'default': 0,
          },
        },
      ),
    },
    {
      'name': 'kelivo_read_file_base64',
      'description': '读取二进制文件并返回 base64，适合图片、压缩包等非文本文件。',
      'inputSchema': _workspacePathSchema(),
    },
    {
      'name': 'kelivo_create_directory',
      'description': '创建目录，父目录默认自动创建。',
      'inputSchema': _workspacePathSchema(),
    },
    {
      'name': 'kelivo_create_text_file',
      'description': '创建新的 UTF-8 文本文件。默认不覆盖已存在文件；需要覆盖时传 overwrite=true。',
      'inputSchema': _textWriteSchema(overwriteDefault: false),
    },
    {
      'name': 'kelivo_write_text_file',
      'description': '写入或整体替换 UTF-8 文本文件；适合用户明确要求覆盖或重写整个文件。',
      'inputSchema': _textWriteSchema(overwriteDefault: true),
    },
    {
      'name': 'kelivo_write_file_base64',
      'description': '写入 base64 编码的二进制文件。默认覆盖已存在文件。',
      'inputSchema': _binaryWriteSchema(),
    },
    {
      'name': 'kelivo_append_text_file',
      'description': '向 UTF-8 文本文件末尾追加内容；文件不存在时会创建。',
      'inputSchema': _textWriteSchema(
        overwriteDefault: false,
        includeOverwrite: false,
      ),
    },
    {
      'name': 'kelivo_delete_file',
      'description': '删除文件或目录。目录默认只允许删除空目录；删除非空目录需传 recursive=true。',
      'inputSchema': _workspacePathSchema(
        extraProperties: {
          'recursive': {
            'type': 'boolean',
            'description': '是否递归删除非空目录。',
            'default': false,
          },
        },
      ),
    },
    {
      'name': 'kelivo_delete_files',
      'description': '批量删除多个文件或目录。默认遇到单个失败继续处理其它路径，并返回逐项结果。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          ..._workspaceProperty(),
          'paths': {
            'type': 'array',
            'description':
                '要删除的路径列表。默认工作区是 phone_storage（/storage/emulated/0）。',
            'items': {'type': 'string'},
          },
          'recursive': {
            'type': 'boolean',
            'description': '是否递归删除非空目录。',
            'default': false,
          },
          'continue_on_error': {
            'type': 'boolean',
            'description': '单个路径删除失败时是否继续处理后续路径。',
            'default': true,
          },
        },
        'required': ['paths'],
      },
    },
    {
      'name': 'kelivo_move_file',
      'description': '移动或重命名文件/目录，支持跨工作区移动。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          ..._workspaceProperty(),
          'from_path': _pathProperty('源路径。'),
          'to_path': _pathProperty('目标路径。'),
          'from_workspace': _optionalWorkspaceProperty(
            '可选源工作区。默认使用 workspace 或当前工作区。',
          ),
          'to_workspace': _optionalWorkspaceProperty('可选目标工作区。默认与源工作区相同。'),
          'overwrite': {
            'type': 'boolean',
            'description': '目标文件已存在时是否覆盖。',
            'default': false,
          },
          'create_parent_dirs': {
            'type': 'boolean',
            'description': '是否自动创建目标父目录。',
            'default': true,
          },
        },
        'required': ['from_path', 'to_path'],
      },
    },
    {
      'name': 'kelivo_copy_file',
      'description': '复制文件或目录，支持跨工作区复制。目标已存在时默认不覆盖。',
      'inputSchema': _copyMoveSchema(),
    },
    {
      'name': 'kelivo_zip_files',
      'description': '将一个或多个文件/目录压缩成 ZIP。默认不覆盖已有 ZIP；目录压缩不跟随符号链接，并限制最大条目数。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          ..._workspaceProperty(),
          'paths': {
            'type': 'array',
            'description': '要压缩的文件或目录路径列表。默认在当前工作区，通常是 /storage/emulated/0。',
            'items': {'type': 'string'},
          },
          'destination_path': _pathProperty('目标 ZIP 路径，必须以 .zip 结尾。'),
          'destination_workspace': _optionalWorkspaceProperty(
            '可选目标工作区。默认使用 workspace 或当前工作区。',
          ),
          'overwrite': {
            'type': 'boolean',
            'description': '目标 ZIP 已存在时是否覆盖。',
            'default': false,
          },
          'create_parent_dirs': {
            'type': 'boolean',
            'description': '目标父目录不存在时是否自动创建。',
            'default': true,
          },
          'include_root_dir': {
            'type': 'boolean',
            'description': '压缩目录时是否包含目录本身这一层。',
            'default': false,
          },
        },
        'required': ['paths', 'destination_path'],
      },
    },
    {
      'name': 'kelivo_unzip_file',
      'description': '解压 ZIP 到指定目录。会拒绝路径穿越和符号链接条目，默认跳过已存在文件。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          ..._workspaceProperty(),
          'zip_path': _pathProperty('要解压的 ZIP 文件路径。'),
          'destination_path': _pathProperty('解压目标目录。'),
          'zip_workspace': _optionalWorkspaceProperty(
            '可选 ZIP 所在工作区。默认使用 workspace 或当前工作区。',
          ),
          'destination_workspace': _optionalWorkspaceProperty(
            '可选解压目标工作区。默认使用 workspace 或当前工作区。',
          ),
          'overwrite': {
            'type': 'boolean',
            'description': '目标文件已存在时是否覆盖。默认跳过。',
            'default': false,
          },
        },
        'required': ['zip_path', 'destination_path'],
      },
    },
    {
      'name': 'kelivo_search_files',
      'description': '按文件名或相对路径搜索文件/目录，类似简化版 find。',
      'inputSchema': _workspacePathSchema(
        requiredPath: false,
        extraProperties: {
          'query': {'type': 'string', 'description': '要搜索的文件名或路径片段。'},
          'recursive': {
            'type': 'boolean',
            'description': '是否递归搜索子目录。',
            'default': true,
          },
          'limit': {
            'type': 'integer',
            'description': '最多返回多少个匹配结果。',
            'default': defaultSearchLimit,
          },
        },
        requiredExtra: const ['query'],
      ),
    },
    {
      'name': 'kelivo_search_text',
      'description': '在 UTF-8 文本文件内容中搜索字符串，类似简化版 rg。',
      'inputSchema': _workspacePathSchema(
        requiredPath: false,
        extraProperties: {
          'query': {'type': 'string', 'description': '要搜索的文本。'},
          'case_sensitive': {
            'type': 'boolean',
            'description': '是否区分大小写。',
            'default': false,
          },
          'recursive': {
            'type': 'boolean',
            'description': '是否递归搜索子目录。',
            'default': true,
          },
          'limit': {
            'type': 'integer',
            'description': '最多返回多少个匹配结果。',
            'default': defaultSearchLimit,
          },
        },
        requiredExtra: const ['query'],
      ),
    },
  ];

  static Map<String, dynamic> _emptySchema() => {
    'type': 'object',
    'properties': <String, dynamic>{},
  };

  static Map<String, dynamic> _workspacePathSchema({
    bool requiredPath = true,
    Map<String, dynamic> extraProperties = const {},
    List<String> requiredExtra = const [],
  }) => {
    'type': 'object',
    'properties': {
      ..._workspaceProperty(),
      'path': _pathProperty(
        requiredPath
            ? '文件或目录路径。'
            : '可选目录路径；省略或传空字符串表示当前工作区根目录，默认是 /storage/emulated/0。',
      ),
      ...extraProperties,
    },
    if (requiredPath || requiredExtra.isNotEmpty)
      'required': [if (requiredPath) 'path', ...requiredExtra],
  };

  static Map<String, dynamic> _textWriteSchema({
    required bool overwriteDefault,
    bool includeOverwrite = true,
  }) {
    final properties = <String, dynamic>{
      ..._workspaceProperty(),
      'path': _pathProperty('Relative file path, such as "notes/hello.txt".'),
      'content': {'type': 'string', 'description': '要写入的 UTF-8 文本内容。'},
      'create_parent_dirs': {
        'type': 'boolean',
        'description': '父目录不存在时是否自动创建。',
        'default': true,
      },
    };
    if (includeOverwrite) {
      properties['overwrite'] = {
        'type': 'boolean',
        'description': '文件已存在时是否覆盖。',
        'default': overwriteDefault,
      };
    }
    return {
      'type': 'object',
      'properties': properties,
      'required': ['path', 'content'],
    };
  }

  static Map<String, dynamic> _binaryWriteSchema() => {
    'type': 'object',
    'properties': {
      ..._workspaceProperty(),
      'path': _pathProperty('目标文件路径。'),
      'content_base64': {'type': 'string', 'description': '要写入的 base64 内容。'},
      'overwrite': {
        'type': 'boolean',
        'description': '文件已存在时是否覆盖。',
        'default': true,
      },
      'create_parent_dirs': {
        'type': 'boolean',
        'description': '父目录不存在时是否自动创建。',
        'default': true,
      },
    },
    'required': ['path', 'content_base64'],
  };

  static Map<String, dynamic> _copyMoveSchema() => {
    'type': 'object',
    'properties': {
      ..._workspaceProperty(),
      'from_path': _pathProperty('源路径。'),
      'to_path': _pathProperty('目标路径。'),
      'from_workspace': _optionalWorkspaceProperty(
        '可选源工作区。默认使用 workspace 或当前工作区。',
      ),
      'to_workspace': _optionalWorkspaceProperty('可选目标工作区。默认与源工作区相同。'),
      'overwrite': {
        'type': 'boolean',
        'description': '目标文件已存在时是否覆盖。',
        'default': false,
      },
      'create_parent_dirs': {
        'type': 'boolean',
        'description': '是否自动创建目标父目录。',
        'default': true,
      },
    },
    'required': ['from_path', 'to_path'],
  };

  static Map<String, dynamic> _workspaceProperty() => {
    'workspace': {
      'type': 'string',
      'description': 'Kelivo 工作区名称。省略时使用当前工作区；默认是 phone_storage。',
      'enum': [
        'documents',
        'exports',
        'scratch',
        'uploads',
        'images',
        'cache',
        'fonts',
        phoneStorageWorkspace,
      ],
    },
  };

  static Map<String, dynamic> _optionalWorkspaceProperty(String description) =>
      {
        'type': 'string',
        'description': description,
        'enum': [
          'documents',
          'exports',
          'scratch',
          'uploads',
          'images',
          'cache',
          'fonts',
          phoneStorageWorkspace,
        ],
      };

  static Map<String, dynamic> _pathProperty(String description) => {
    'type': 'string',
    'description':
        '$description 默认工作区是 phone_storage（/storage/emulated/0）。可传相对路径，也可传 /storage/emulated/0 或 /sdcard 下的绝对路径；只有用户明确要求时才切换 workspace。禁止 URI scheme 和 .. 穿越。',
  };

  @override
  void close() {
    _closed = true;
  }
}

class _ResolvedKelivoPath {
  const _ResolvedKelivoPath({
    required this.workspace,
    required this.rootPath,
    required this.path,
    required this.relativePath,
    required this.displayPath,
  });

  final String workspace;
  final String rootPath;
  final String path;
  final String relativePath;
  final String displayPath;
}

class _BoundedText {
  const _BoundedText({
    required this.content,
    required this.start,
    required this.nextStartIndex,
    required this.truncated,
  });

  final String content;
  final int start;
  final int? nextStartIndex;
  final bool truncated;
}

class _MimeDetection {
  const _MimeDetection(this.mimeType, this.source);

  final String mimeType;
  final String source;
}
