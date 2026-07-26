import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

typedef GitHubAccessTokenProvider = Future<String?> Function();

class GitHubApiException implements Exception {
  GitHubApiException({
    required this.statusCode,
    required this.message,
    this.documentationUrl,
  });

  final int statusCode;
  final String message;
  final String? documentationUrl;

  @override
  String toString() {
    final doc = documentationUrl == null ? '' : ' ($documentationUrl)';
    return 'GitHub API error $statusCode: $message$doc';
  }
}

class GitHubApiClient {
  GitHubApiClient({
    http.Client? httpClient,
    this.accessTokenProvider,
    Uri? baseUri,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _httpClient = httpClient ?? http.Client(),
       _baseUri = baseUri ?? Uri.parse('https://api.github.com'),
       _ownsClient = httpClient == null;

  static const int defaultResultLimit = 10;
  static const int maximumResultLimit = 50;
  static const int defaultMaxTextLength = 12000;
  static const int maximumMaxTextLength = 50000;

  final http.Client _httpClient;
  final GitHubAccessTokenProvider? accessTokenProvider;
  final Uri _baseUri;
  final Duration requestTimeout;
  final bool _ownsClient;

  Future<Map<String, dynamic>> getViewer() async {
    final raw = await _getJson('/user');
    return {
      'login': raw['login'],
      'id': raw['id'],
      'name': raw['name'],
      'html_url': raw['html_url'],
      'type': raw['type'],
    };
  }

  Future<Map<String, dynamic>> searchCode({
    required String query,
    int perPage = defaultResultLimit,
    int page = 1,
  }) async {
    final normalizedQuery = _requiredQuery(query);
    final raw = await _getJson(
      '/search/code',
      query: {
        'q': normalizedQuery,
        'per_page': _boundedResultLimit(perPage).toString(),
        'page': _positiveInt(page, name: 'page').toString(),
      },
    );
    return _compactSearch(raw, query: normalizedQuery, mapper: _codeItem);
  }

  Future<Map<String, dynamic>> searchRepositories({
    required String query,
    int perPage = defaultResultLimit,
    int page = 1,
  }) async {
    final normalizedQuery = _requiredQuery(query);
    final raw = await _getJson(
      '/search/repositories',
      query: {
        'q': normalizedQuery,
        'per_page': _boundedResultLimit(perPage).toString(),
        'page': _positiveInt(page, name: 'page').toString(),
      },
    );
    return _compactSearch(raw, query: normalizedQuery, mapper: _repositoryItem);
  }

  Future<Map<String, dynamic>> searchIssues({
    required String query,
    int perPage = defaultResultLimit,
    int page = 1,
  }) async {
    final normalizedQuery = _ensureIssueKind(_requiredQuery(query), 'is:issue');
    final raw = await _getJson(
      '/search/issues',
      query: {
        'q': normalizedQuery,
        'per_page': _boundedResultLimit(perPage).toString(),
        'page': _positiveInt(page, name: 'page').toString(),
      },
    );
    return _compactSearch(raw, query: normalizedQuery, mapper: _issueItem);
  }

  Future<Map<String, dynamic>> searchPullRequests({
    required String query,
    int perPage = defaultResultLimit,
    int page = 1,
  }) async {
    final normalizedQuery = _ensureIssueKind(_requiredQuery(query), 'is:pr');
    final raw = await _getJson(
      '/search/issues',
      query: {
        'q': normalizedQuery,
        'per_page': _boundedResultLimit(perPage).toString(),
        'page': _positiveInt(page, name: 'page').toString(),
      },
    );
    return _compactSearch(raw, query: normalizedQuery, mapper: _issueItem);
  }

  Future<Map<String, dynamic>> getRepository({
    required String owner,
    required String repo,
  }) async {
    final raw = await _getJson('/repos/${_segment(owner)}/${_segment(repo)}');
    return _repositoryItem(raw);
  }

  Future<Map<String, dynamic>> createRepository({
    required String name,
    String? description,
    bool private = false,
    String? org,
    bool autoInit = false,
  }) async {
    final body = <String, dynamic>{
      'name': _requiredRepositoryName(name),
      if ((description ?? '').trim().isNotEmpty)
        'description': description!.trim(),
      'private': private,
      'auto_init': autoInit,
    };
    final path = (org ?? '').trim().isEmpty
        ? '/user/repos'
        : '/orgs/${_segment(org!)}/repos';
    final raw = await _postJson(path, body: body);
    return _repositoryItem(raw);
  }

  Future<Map<String, dynamic>> updateRepository({
    required String owner,
    required String repo,
    String? name,
    String? description,
    bool? private,
    bool? hasIssues,
    bool? hasWiki,
    bool? archived,
    String? defaultBranch,
  }) async {
    final body = <String, dynamic>{
      if ((name ?? '').trim().isNotEmpty)
        'name': _requiredRepositoryName(name!),
      if (description != null) 'description': description,
      if (private != null) 'private': private,
      if (hasIssues != null) 'has_issues': hasIssues,
      if (hasWiki != null) 'has_wiki': hasWiki,
      if (archived != null) 'archived': archived,
      if ((defaultBranch ?? '').trim().isNotEmpty)
        'default_branch': defaultBranch!.trim(),
    };
    if (body.isEmpty) {
      throw ArgumentError('At least one repository field must be provided');
    }
    final raw = await _patchJson(
      '/repos/${_segment(owner)}/${_segment(repo)}',
      body: body,
    );
    return _repositoryItem(raw);
  }

  Future<Map<String, dynamic>> deleteRepository({
    required String owner,
    required String repo,
    required String confirmRepoFullName,
  }) async {
    final fullName = '${_segment(owner)}/${_segment(repo)}';
    if (confirmRepoFullName.trim() != fullName) {
      throw ArgumentError(
        'confirm_repo_full_name must exactly equal $fullName',
      );
    }
    await _deleteText('/repos/${_segment(owner)}/${_segment(repo)}');
    return {'owner': owner, 'repo': repo, 'deleted': true};
  }

  Future<Map<String, dynamic>> forkRepository({
    required String owner,
    required String repo,
    String? organization,
    String? name,
    bool? defaultBranchOnly,
  }) async {
    final raw = await _postJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/forks',
      body: {
        if ((organization ?? '').trim().isNotEmpty)
          'organization': organization!.trim(),
        if ((name ?? '').trim().isNotEmpty)
          'name': _requiredRepositoryName(name!),
        if (defaultBranchOnly != null) 'default_branch_only': defaultBranchOnly,
      },
    );
    return _repositoryItem(raw);
  }

  Future<Map<String, dynamic>> listDirectory({
    required String owner,
    required String repo,
    String path = '',
    String? ref,
  }) async {
    final cleanPath = path.trim().isEmpty ? '' : _requiredPath(path);
    final apiPath = cleanPath.isEmpty
        ? '/repos/${_segment(owner)}/${_segment(repo)}/contents'
        : '/repos/${_segment(owner)}/${_segment(repo)}/contents/${_pathSegments(cleanPath)}';
    final raw = await _getJsonList(
      apiPath,
      query: {if ((ref ?? '').trim().isNotEmpty) 'ref': ref!.trim()},
    );
    return {
      'owner': owner,
      'repo': repo,
      'path': cleanPath,
      if ((ref ?? '').trim().isNotEmpty) 'ref': ref!.trim(),
      'items': raw.map(_contentListItem).toList(growable: false),
    };
  }

  Future<Map<String, dynamic>> listBranches({
    required String owner,
    required String repo,
    int perPage = defaultResultLimit,
    int page = 1,
  }) async {
    final raw = await _getJsonList(
      '/repos/${_segment(owner)}/${_segment(repo)}/branches',
      query: _pagingQuery(perPage: perPage, page: page),
    );
    return {
      'owner': owner,
      'repo': repo,
      'page': page,
      'per_page': _boundedResultLimit(perPage),
      'branches': raw.map(_branchItem).toList(growable: false),
    };
  }

  Future<Map<String, dynamic>> listTags({
    required String owner,
    required String repo,
    int perPage = defaultResultLimit,
    int page = 1,
  }) async {
    final raw = await _getJsonList(
      '/repos/${_segment(owner)}/${_segment(repo)}/tags',
      query: _pagingQuery(perPage: perPage, page: page),
    );
    return {
      'owner': owner,
      'repo': repo,
      'page': page,
      'per_page': _boundedResultLimit(perPage),
      'tags': raw.map(_tagItem).toList(growable: false),
    };
  }

  Future<Map<String, dynamic>> listCommits({
    required String owner,
    required String repo,
    String? sha,
    String? path,
    int perPage = defaultResultLimit,
    int page = 1,
  }) async {
    final raw = await _getJsonList(
      '/repos/${_segment(owner)}/${_segment(repo)}/commits',
      query: {
        ..._pagingQuery(perPage: perPage, page: page),
        if ((sha ?? '').trim().isNotEmpty) 'sha': sha!.trim(),
        if ((path ?? '').trim().isNotEmpty) 'path': _requiredPath(path!),
      },
    );
    return {
      'owner': owner,
      'repo': repo,
      'page': page,
      'per_page': _boundedResultLimit(perPage),
      'commits': raw.map(_commitSummaryItem).toList(growable: false),
    };
  }

  Future<Map<String, dynamic>> getCommit({
    required String owner,
    required String repo,
    required String ref,
  }) async {
    final raw = await _getJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/commits/${_segment(ref)}',
    );
    return _commitDetailItem(raw);
  }

  Future<Map<String, dynamic>> compareRefs({
    required String owner,
    required String repo,
    required String base,
    required String head,
  }) async {
    final raw = await _getJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/compare/${_segment(base)}...${_segment(head)}',
    );
    return {
      'owner': owner,
      'repo': repo,
      'base': base,
      'head': head,
      'status': raw['status'],
      'ahead_by': raw['ahead_by'],
      'behind_by': raw['behind_by'],
      'total_commits': raw['total_commits'],
      'html_url': raw['html_url'],
      'commits': raw['commits'] is List
          ? (raw['commits'] as List)
                .map(_commitSummaryItem)
                .toList(growable: false)
          : const <dynamic>[],
      'files': raw['files'] is List
          ? (raw['files'] as List).map(_fileChangeItem).toList(growable: false)
          : const <dynamic>[],
    };
  }

  Future<Map<String, dynamic>> getFile({
    required String owner,
    required String repo,
    required String path,
    String? ref,
    int maxLength = defaultMaxTextLength,
    int startIndex = 0,
  }) async {
    final cleanPath = _requiredPath(path);
    final raw = await _getJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/contents/${_pathSegments(cleanPath)}',
      query: {if (ref != null && ref.trim().isNotEmpty) 'ref': ref.trim()},
    );
    if ((raw['type'] ?? '').toString() != 'file') {
      throw GitHubApiException(
        statusCode: 422,
        message: 'Path is not a file: $cleanPath',
      );
    }
    final encoding = (raw['encoding'] ?? '').toString();
    if (encoding != 'base64') {
      throw GitHubApiException(
        statusCode: 422,
        message: 'Unsupported GitHub content encoding: $encoding',
      );
    }
    final encoded = (raw['content'] ?? '').toString().replaceAll('\n', '');
    final bytes = base64Decode(encoded);
    final text = utf8.decode(bytes, allowMalformed: true);
    final bounded = _boundedText(
      text,
      maxLength: _boundedTextLength(maxLength),
      startIndex: _nonNegativeInt(startIndex, name: 'start_index'),
    );
    return {
      'owner': owner,
      'repo': repo,
      'path': raw['path'] ?? cleanPath,
      'name': raw['name'],
      'sha': raw['sha'],
      'size': raw['size'],
      'html_url': raw['html_url'],
      'download_url': raw['download_url'],
      if (ref != null && ref.trim().isNotEmpty) 'ref': ref.trim(),
      ...bounded.toJson(contentKey: 'content'),
    };
  }

  Future<Map<String, dynamic>> getIssueComments({
    required String owner,
    required String repo,
    required int issueNumber,
    int perPage = defaultResultLimit,
    int page = 1,
  }) async {
    final raw = await _getJsonList(
      '/repos/${_segment(owner)}/${_segment(repo)}/issues/${_positiveInt(issueNumber, name: 'issue_number')}/comments',
      query: {
        'per_page': _boundedResultLimit(perPage).toString(),
        'page': _positiveInt(page, name: 'page').toString(),
      },
    );
    return {
      'owner': owner,
      'repo': repo,
      'issue_number': issueNumber,
      'page': page,
      'per_page': perPage,
      'comments': raw.map(_commentItem).toList(growable: false),
    };
  }

  Future<Map<String, dynamic>> getPullRequestDiff({
    required String owner,
    required String repo,
    required int pullNumber,
    int maxLength = defaultMaxTextLength,
    int startIndex = 0,
  }) async {
    final response = await _getText(
      '/repos/${_segment(owner)}/${_segment(repo)}/pulls/${_positiveInt(pullNumber, name: 'pull_number')}',
      accept: 'application/vnd.github.diff',
    );
    final bounded = _boundedText(
      response,
      maxLength: _boundedTextLength(maxLength),
      startIndex: _nonNegativeInt(startIndex, name: 'start_index'),
    );
    return {
      'owner': owner,
      'repo': repo,
      'pull_number': pullNumber,
      ...bounded.toJson(contentKey: 'diff'),
    };
  }

  Future<Map<String, dynamic>> getPullRequest({
    required String owner,
    required String repo,
    required int pullNumber,
  }) async {
    final raw = await _getJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/pulls/${_positiveInt(pullNumber, name: 'pull_number')}',
    );
    return _pullRequestItem(raw);
  }

  Future<Map<String, dynamic>> updatePullRequest({
    required String owner,
    required String repo,
    required int pullNumber,
    String? title,
    String? body,
    String? state,
    String? base,
    bool? maintainerCanModify,
  }) async {
    final requestBody = <String, dynamic>{
      if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
      if (body != null) 'body': body,
      if ((state ?? '').trim().isNotEmpty) 'state': state!.trim(),
      if ((base ?? '').trim().isNotEmpty) 'base': base!.trim(),
      if (maintainerCanModify != null)
        'maintainer_can_modify': maintainerCanModify,
    };
    if (requestBody.isEmpty) {
      throw ArgumentError('At least one pull request field must be provided');
    }
    final raw = await _patchJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/pulls/${_positiveInt(pullNumber, name: 'pull_number')}',
      body: requestBody,
    );
    return _pullRequestItem(raw);
  }

  Future<Map<String, dynamic>> listPullRequestFiles({
    required String owner,
    required String repo,
    required int pullNumber,
    int perPage = defaultResultLimit,
    int page = 1,
  }) async {
    final raw = await _getJsonList(
      '/repos/${_segment(owner)}/${_segment(repo)}/pulls/${_positiveInt(pullNumber, name: 'pull_number')}/files',
      query: _pagingQuery(perPage: perPage, page: page),
    );
    return {
      'owner': owner,
      'repo': repo,
      'pull_number': pullNumber,
      'page': page,
      'per_page': _boundedResultLimit(perPage),
      'files': raw.map(_fileChangeItem).toList(growable: false),
    };
  }

  Future<Map<String, dynamic>> listPullRequestReviews({
    required String owner,
    required String repo,
    required int pullNumber,
    int perPage = defaultResultLimit,
    int page = 1,
  }) async {
    final raw = await _getJsonList(
      '/repos/${_segment(owner)}/${_segment(repo)}/pulls/${_positiveInt(pullNumber, name: 'pull_number')}/reviews',
      query: _pagingQuery(perPage: perPage, page: page),
    );
    return {
      'owner': owner,
      'repo': repo,
      'pull_number': pullNumber,
      'page': page,
      'per_page': _boundedResultLimit(perPage),
      'reviews': raw.map(_pullRequestReviewItem).toList(growable: false),
    };
  }

  Future<Map<String, dynamic>> listPullRequestReviewComments({
    required String owner,
    required String repo,
    required int pullNumber,
    int perPage = defaultResultLimit,
    int page = 1,
  }) async {
    final raw = await _getJsonList(
      '/repos/${_segment(owner)}/${_segment(repo)}/pulls/${_positiveInt(pullNumber, name: 'pull_number')}/comments',
      query: _pagingQuery(perPage: perPage, page: page),
    );
    return {
      'owner': owner,
      'repo': repo,
      'pull_number': pullNumber,
      'page': page,
      'per_page': _boundedResultLimit(perPage),
      'comments': raw
          .map(_pullRequestReviewCommentItem)
          .toList(growable: false),
    };
  }

  Future<Map<String, dynamic>> createPullRequestReview({
    required String owner,
    required String repo,
    required int pullNumber,
    String? body,
    String event = 'COMMENT',
  }) async {
    final raw = await _postJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/pulls/${_positiveInt(pullNumber, name: 'pull_number')}/reviews',
      body: {
        'event': _requiredPullReviewEvent(event),
        if ((body ?? '').trim().isNotEmpty) 'body': body!.trim(),
      },
    );
    return _pullRequestReviewItem(raw);
  }

  Future<Map<String, dynamic>> createPullRequestReviewComment({
    required String owner,
    required String repo,
    required int pullNumber,
    required String body,
    String? commitId,
    String? path,
    int? line,
    String side = 'RIGHT',
    int? startLine,
    String? startSide,
    String? subjectType,
    int? inReplyTo,
  }) async {
    final normalizedBody = _requiredQuery(body);
    final replyTo = inReplyTo == null
        ? null
        : _positiveInt(inReplyTo, name: 'in_reply_to');

    final Map<String, dynamic> requestBody;
    if (replyTo != null) {
      requestBody = <String, dynamic>{
        'body': normalizedBody,
        'in_reply_to': replyTo,
      };
    } else {
      final normalizedSubjectType = (subjectType ?? '').trim().isEmpty
          ? null
          : _requiredReviewSubjectType(subjectType!);
      if (line == null && normalizedSubjectType != 'file') {
        throw ArgumentError(
          'line is required for inline comments unless subject_type is file',
        );
      }
      requestBody = <String, dynamic>{
        'body': normalizedBody,
        'commit_id': _requiredQuery(commitId ?? ''),
        'path': _requiredPath(path ?? ''),
        if (line != null) 'line': _positiveInt(line, name: 'line'),
        'side': _requiredReviewSide(side),
        if (startLine != null)
          'start_line': _positiveInt(startLine, name: 'start_line'),
        if ((startSide ?? '').trim().isNotEmpty)
          'start_side': _requiredReviewSide(startSide!),
        if (normalizedSubjectType != null) 'subject_type': normalizedSubjectType,
      };
    }
    final raw = await _postJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/pulls/${_positiveInt(pullNumber, name: 'pull_number')}/comments',
      body: requestBody,
    );
    return _pullRequestReviewCommentItem(raw);
  }

  Future<Map<String, dynamic>> mergePullRequest({
    required String owner,
    required String repo,
    required int pullNumber,
    String? commitTitle,
    String? commitMessage,
    String mergeMethod = 'merge',
    String? expectedHeadSha,
  }) async {
    final raw = await _putJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/pulls/${_positiveInt(pullNumber, name: 'pull_number')}/merge',
      body: {
        if ((commitTitle ?? '').trim().isNotEmpty)
          'commit_title': commitTitle!.trim(),
        if ((commitMessage ?? '').trim().isNotEmpty)
          'commit_message': commitMessage!.trim(),
        'merge_method': _requiredMergeMethod(mergeMethod),
        if ((expectedHeadSha ?? '').trim().isNotEmpty)
          'sha': expectedHeadSha!.trim(),
      },
    );
    return {
      'owner': owner,
      'repo': repo,
      'pull_number': pullNumber,
      'merged': raw['merged'],
      'message': raw['message'],
      'sha': raw['sha'],
    };
  }

  Future<Map<String, dynamic>> deleteBranch({
    required String owner,
    required String repo,
    required String branch,
    required String confirmBranch,
  }) async {
    final cleanBranch = _requiredBranchName(branch);
    if (confirmBranch.trim() != cleanBranch) {
      throw ArgumentError('confirm_branch must exactly equal $cleanBranch');
    }
    await _deleteText(
      '/repos/${_segment(owner)}/${_segment(repo)}/git/refs/heads/${_pathSegments(cleanBranch)}',
    );
    return {
      'owner': owner,
      'repo': repo,
      'branch': cleanBranch,
      'deleted': true,
    };
  }

  Future<Map<String, dynamic>> createBranch({
    required String owner,
    required String repo,
    required String branch,
    String? fromSha,
    String? fromBranch,
  }) async {
    final cleanBranch = _requiredBranchName(branch);
    var initialized = false;
    var baseSha = (fromSha ?? '').trim().isNotEmpty ? fromSha!.trim() : '';
    if (baseSha.isEmpty) {
      final baseBranch = (fromBranch ?? '').trim().isNotEmpty
          ? fromBranch!.trim()
          : await _defaultBranch(owner: owner, repo: repo);
      try {
        baseSha = await _branchCommitSha(
          owner: owner,
          repo: repo,
          branch: baseBranch,
        );
      } on GitHubApiException catch (e) {
        if (!_looksLikeEmptyRepositoryError(e)) rethrow;
        final init = await createOrUpdateFile(
          owner: owner,
          repo: repo,
          path: 'README.md',
          content: '# $repo\n',
          message: 'Initialize repository',
          branch: baseBranch,
        );
        baseSha = (_asMap(init['commit'])['sha'] ?? '').toString();
        initialized = true;
        if (baseSha.isEmpty) {
          throw GitHubApiException(
            statusCode: 502,
            message: 'Repository initialization did not return commit.sha.',
          );
        }
      }
    }
    final raw = await _postJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/git/refs',
      body: {'ref': 'refs/heads/$cleanBranch', 'sha': baseSha},
    );
    final object = _asMap(raw['object']);
    return {
      'owner': owner,
      'repo': repo,
      'branch': cleanBranch,
      'initialized_repository': initialized,
      'ref': raw['ref'],
      'url': raw['url'],
      'object': {
        'type': object['type'],
        'sha': object['sha'],
        'url': object['url'],
      },
    };
  }

  Future<Map<String, dynamic>> createOrUpdateFile({
    required String owner,
    required String repo,
    required String path,
    required String content,
    required String message,
    String? branch,
    String? sha,
  }) async {
    final cleanPath = _requiredPath(path);
    final body = <String, dynamic>{
      'message': _requiredMessage(message),
      'content': base64Encode(utf8.encode(content)),
      if ((branch ?? '').trim().isNotEmpty) 'branch': branch!.trim(),
      if ((sha ?? '').trim().isNotEmpty) 'sha': sha!.trim(),
    };
    final raw = await _putJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/contents/${_pathSegments(cleanPath)}',
      body: body,
    );
    return _contentMutationResult(
      raw,
      owner: owner,
      repo: repo,
      path: cleanPath,
      branch: branch,
    );
  }

  Future<Map<String, dynamic>> deleteFile({
    required String owner,
    required String repo,
    required String path,
    required String sha,
    required String message,
    String? branch,
  }) async {
    final cleanPath = _requiredPath(path);
    final raw = await _deleteJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/contents/${_pathSegments(cleanPath)}',
      body: {
        'message': _requiredMessage(message),
        'sha': _requiredQuery(sha),
        if ((branch ?? '').trim().isNotEmpty) 'branch': branch!.trim(),
      },
    );
    return _contentMutationResult(
      raw,
      owner: owner,
      repo: repo,
      path: cleanPath,
      branch: branch,
    );
  }

  Future<Map<String, dynamic>> createIssue({
    required String owner,
    required String repo,
    required String title,
    String? body,
    List<String> labels = const <String>[],
    List<String> assignees = const <String>[],
  }) async {
    final raw = await _postJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/issues',
      body: {
        'title': _requiredQuery(title),
        if ((body ?? '').trim().isNotEmpty) 'body': body!.trim(),
        if (labels.isNotEmpty) 'labels': labels,
        if (assignees.isNotEmpty) 'assignees': assignees,
      },
    );
    return _issueItem(raw);
  }

  Future<Map<String, dynamic>> updateIssue({
    required String owner,
    required String repo,
    required int issueNumber,
    String? title,
    String? body,
    String? state,
    List<String>? labels,
    List<String>? assignees,
  }) async {
    final requestBody = <String, dynamic>{
      if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
      if (body != null) 'body': body,
      if ((state ?? '').trim().isNotEmpty) 'state': state!.trim(),
      if (labels != null) 'labels': labels,
      if (assignees != null) 'assignees': assignees,
    };
    if (requestBody.isEmpty) {
      throw ArgumentError('At least one issue field must be provided');
    }
    final raw = await _patchJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/issues/${_positiveInt(issueNumber, name: 'issue_number')}',
      body: requestBody,
    );
    return _issueItem(raw);
  }

  Future<Map<String, dynamic>> createIssueComment({
    required String owner,
    required String repo,
    required int issueNumber,
    required String body,
  }) async {
    final raw = await _postJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/issues/${_positiveInt(issueNumber, name: 'issue_number')}/comments',
      body: {'body': _requiredQuery(body)},
    );
    return _commentItem(raw);
  }

  Future<Map<String, dynamic>> createPullRequest({
    required String owner,
    required String repo,
    required String title,
    required String head,
    required String base,
    String? body,
    bool draft = false,
    bool maintainerCanModify = true,
  }) async {
    final raw = await _postJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/pulls',
      body: {
        'title': _requiredQuery(title),
        'head': _requiredQuery(head),
        'base': _requiredQuery(base),
        if ((body ?? '').trim().isNotEmpty) 'body': body!.trim(),
        'draft': draft,
        'maintainer_can_modify': maintainerCanModify,
      },
    );
    return _pullRequestItem(raw);
  }

  Future<Map<String, dynamic>> listReleases({
    required String owner,
    required String repo,
    int perPage = defaultResultLimit,
    int page = 1,
  }) async {
    final raw = await _getJsonList(
      '/repos/${_segment(owner)}/${_segment(repo)}/releases',
      query: _pagingQuery(perPage: perPage, page: page),
    );
    return {
      'owner': owner,
      'repo': repo,
      'page': page,
      'per_page': _boundedResultLimit(perPage),
      'releases': raw.map(_releaseItem).toList(growable: false),
    };
  }

  Future<Map<String, dynamic>> getRelease({
    required String owner,
    required String repo,
    required int releaseId,
  }) async {
    final raw = await _getJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/releases/${_positiveInt(releaseId, name: 'release_id')}',
    );
    return _releaseItem(raw);
  }

  Future<Map<String, dynamic>> createRelease({
    required String owner,
    required String repo,
    required String tagName,
    String? targetCommitish,
    String? name,
    String? body,
    bool draft = false,
    bool prerelease = false,
    bool generateReleaseNotes = false,
  }) async {
    final raw = await _postJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/releases',
      body: {
        'tag_name': _requiredQuery(tagName),
        if ((targetCommitish ?? '').trim().isNotEmpty)
          'target_commitish': targetCommitish!.trim(),
        if ((name ?? '').trim().isNotEmpty) 'name': name!.trim(),
        if ((body ?? '').trim().isNotEmpty) 'body': body!.trim(),
        'draft': draft,
        'prerelease': prerelease,
        'generate_release_notes': generateReleaseNotes,
      },
    );
    return _releaseItem(raw);
  }

  Future<Map<String, dynamic>> updateRelease({
    required String owner,
    required String repo,
    required int releaseId,
    String? tagName,
    String? targetCommitish,
    String? name,
    String? body,
    bool? draft,
    bool? prerelease,
  }) async {
    final requestBody = <String, dynamic>{
      if ((tagName ?? '').trim().isNotEmpty) 'tag_name': tagName!.trim(),
      if ((targetCommitish ?? '').trim().isNotEmpty)
        'target_commitish': targetCommitish!.trim(),
      if (name != null) 'name': name,
      if (body != null) 'body': body,
      if (draft != null) 'draft': draft,
      if (prerelease != null) 'prerelease': prerelease,
    };
    if (requestBody.isEmpty) {
      throw ArgumentError('At least one release field must be provided');
    }
    final raw = await _patchJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/releases/${_positiveInt(releaseId, name: 'release_id')}',
      body: requestBody,
    );
    return _releaseItem(raw);
  }

  Future<Map<String, dynamic>> deleteRelease({
    required String owner,
    required String repo,
    required int releaseId,
    required int confirmReleaseId,
  }) async {
    final id = _positiveInt(releaseId, name: 'release_id');
    if (confirmReleaseId != id) {
      throw ArgumentError('confirm_release_id must exactly equal release_id');
    }
    await _deleteText(
      '/repos/${_segment(owner)}/${_segment(repo)}/releases/$id',
    );
    return {'owner': owner, 'repo': repo, 'release_id': id, 'deleted': true};
  }

  Future<Map<String, dynamic>> listWorkflows({
    required String owner,
    required String repo,
    int perPage = defaultResultLimit,
    int page = 1,
  }) async {
    final raw = await _getJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/actions/workflows',
      query: _pagingQuery(perPage: perPage, page: page),
    );
    final workflows = raw['workflows'];
    return {
      'owner': owner,
      'repo': repo,
      'total_count': raw['total_count'] ?? 0,
      'page': page,
      'per_page': _boundedResultLimit(perPage),
      'workflows': workflows is List
          ? workflows.map(_workflowItem).toList(growable: false)
          : const <dynamic>[],
    };
  }

  Future<Map<String, dynamic>> listWorkflowRuns({
    required String owner,
    required String repo,
    String? workflowId,
    String? branch,
    String? status,
    int perPage = defaultResultLimit,
    int page = 1,
  }) async {
    final path = (workflowId ?? '').trim().isEmpty
        ? '/repos/${_segment(owner)}/${_segment(repo)}/actions/runs'
        : '/repos/${_segment(owner)}/${_segment(repo)}/actions/workflows/${_segment(workflowId!)}/runs';
    final raw = await _getJson(
      path,
      query: {
        ..._pagingQuery(perPage: perPage, page: page),
        if ((branch ?? '').trim().isNotEmpty) 'branch': branch!.trim(),
        if ((status ?? '').trim().isNotEmpty) 'status': status!.trim(),
      },
    );
    final runs = raw['workflow_runs'];
    return {
      'owner': owner,
      'repo': repo,
      if ((workflowId ?? '').trim().isNotEmpty)
        'workflow_id': workflowId!.trim(),
      'total_count': raw['total_count'] ?? 0,
      'page': page,
      'per_page': _boundedResultLimit(perPage),
      'workflow_runs': runs is List
          ? runs.map(_workflowRunItem).toList(growable: false)
          : const <dynamic>[],
    };
  }

  Future<Map<String, dynamic>> getWorkflowRun({
    required String owner,
    required String repo,
    required int runId,
  }) async {
    final raw = await _getJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/actions/runs/${_positiveInt(runId, name: 'run_id')}',
    );
    return _workflowRunItem(raw);
  }

  Future<Map<String, dynamic>> listWorkflowRunJobs({
    required String owner,
    required String repo,
    required int runId,
    int perPage = defaultResultLimit,
    int page = 1,
  }) async {
    final raw = await _getJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/actions/runs/${_positiveInt(runId, name: 'run_id')}/jobs',
      query: _pagingQuery(perPage: perPage, page: page),
    );
    final jobs = raw['jobs'];
    return {
      'owner': owner,
      'repo': repo,
      'run_id': runId,
      'total_count': raw['total_count'] ?? 0,
      'page': page,
      'per_page': _boundedResultLimit(perPage),
      'jobs': jobs is List
          ? jobs.map(_workflowJobItem).toList(growable: false)
          : const <dynamic>[],
    };
  }

  Future<Map<String, dynamic>> getWorkflowRunLogs({
    required String owner,
    required String repo,
    required int runId,
    int maxLength = defaultMaxTextLength,
    int startIndex = 0,
  }) async {
    final bytes = await _getBytes(
      '/repos/${_segment(owner)}/${_segment(repo)}/actions/runs/${_positiveInt(runId, name: 'run_id')}/logs',
      accept: 'application/vnd.github+json',
    );
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final buffer = StringBuffer();
    for (final file in archive.files) {
      if (!file.isFile) continue;
      buffer.writeln('===== ${file.name} =====');
      buffer.writeln(utf8.decode(file.content, allowMalformed: true));
    }
    final bounded = _boundedText(
      buffer.toString(),
      maxLength: _boundedTextLength(maxLength),
      startIndex: _nonNegativeInt(startIndex, name: 'start_index'),
    );
    return {
      'owner': owner,
      'repo': repo,
      'run_id': runId,
      ...bounded.toJson(contentKey: 'logs'),
    };
  }

  Future<Map<String, dynamic>> dispatchWorkflow({
    required String owner,
    required String repo,
    required String workflowId,
    required String ref,
    Map<String, dynamic> inputs = const <String, dynamic>{},
  }) async {
    await _postText(
      '/repos/${_segment(owner)}/${_segment(repo)}/actions/workflows/${_segment(workflowId)}/dispatches',
      body: {
        'ref': _requiredQuery(ref),
        if (inputs.isNotEmpty) 'inputs': inputs,
      },
    );
    return {
      'owner': owner,
      'repo': repo,
      'workflow_id': workflowId,
      'ref': ref,
      'dispatched': true,
    };
  }

  Future<Map<String, dynamic>> rerunWorkflowRun({
    required String owner,
    required String repo,
    required int runId,
  }) async {
    await _postText(
      '/repos/${_segment(owner)}/${_segment(repo)}/actions/runs/${_positiveInt(runId, name: 'run_id')}/rerun',
      body: const <String, dynamic>{},
    );
    return {
      'owner': owner,
      'repo': repo,
      'run_id': runId,
      'rerun_requested': true,
    };
  }

  Future<Map<String, dynamic>> cancelWorkflowRun({
    required String owner,
    required String repo,
    required int runId,
  }) async {
    await _postText(
      '/repos/${_segment(owner)}/${_segment(repo)}/actions/runs/${_positiveInt(runId, name: 'run_id')}/cancel',
      body: const <String, dynamic>{},
    );
    return {
      'owner': owner,
      'repo': repo,
      'run_id': runId,
      'cancel_requested': true,
    };
  }

  Future<Map<String, dynamic>> getRepositoryPublicKey({
    required String owner,
    required String repo,
    String kind = 'actions',
  }) async {
    final raw = await _getJson(
      _repositorySecretsPublicKeyPath(owner: owner, repo: repo, kind: kind),
    );
    return {
      'owner': owner,
      'repo': repo,
      'kind': _secretKind(kind),
      'key_id': raw['key_id'],
      'key': raw['key'],
    };
  }

  Future<Map<String, dynamic>> putRepositorySecret({
    required String owner,
    required String repo,
    required String secretName,
    required String encryptedValue,
    required String keyId,
    String kind = 'actions',
  }) async {
    final normalizedKind = _secretKind(kind);
    await _putText(
      _repositorySecretPath(
        owner: owner,
        repo: repo,
        secretName: secretName,
        kind: normalizedKind,
      ),
      body: {
        'encrypted_value': _requiredQuery(encryptedValue),
        'key_id': _requiredQuery(keyId),
      },
    );
    return {
      'owner': owner,
      'repo': repo,
      'kind': normalizedKind,
      'secret': _requiredSecretName(secretName),
      'updated': true,
    };
  }

  Future<Map<String, dynamic>> deleteRepositorySecret({
    required String owner,
    required String repo,
    required String secretName,
    String kind = 'actions',
    required String confirmSecretName,
  }) async {
    final name = _requiredSecretName(secretName);
    if (confirmSecretName.trim() != name) {
      throw ArgumentError('confirm_secret_name must exactly equal $name');
    }
    final normalizedKind = _secretKind(kind);
    await _deleteText(
      _repositorySecretPath(
        owner: owner,
        repo: repo,
        secretName: name,
        kind: normalizedKind,
      ),
    );
    return {
      'owner': owner,
      'repo': repo,
      'kind': normalizedKind,
      'secret': name,
      'deleted': true,
    };
  }

  Future<Map<String, dynamic>> listRepositoryVariables({
    required String owner,
    required String repo,
    int perPage = defaultResultLimit,
    int page = 1,
  }) async {
    final raw = await _getJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/actions/variables',
      query: _pagingQuery(perPage: perPage, page: page),
    );
    final variables = raw['variables'];
    return {
      'owner': owner,
      'repo': repo,
      'total_count': raw['total_count'] ?? 0,
      'variables': variables is List
          ? variables.map(_variableItem).toList(growable: false)
          : const <dynamic>[],
    };
  }

  Future<Map<String, dynamic>> createOrUpdateRepositoryVariable({
    required String owner,
    required String repo,
    required String name,
    required String value,
  }) async {
    final variableName = _requiredVariableName(name);
    final path =
        '/repos/${_segment(owner)}/${_segment(repo)}/actions/variables/$variableName';
    try {
      await _patchText(path, body: {'name': variableName, 'value': value});
      return {
        'owner': owner,
        'repo': repo,
        'variable': variableName,
        'updated': true,
        'created': false,
      };
    } on GitHubApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      await _postText(
        '/repos/${_segment(owner)}/${_segment(repo)}/actions/variables',
        body: {'name': variableName, 'value': value},
      );
      return {
        'owner': owner,
        'repo': repo,
        'variable': variableName,
        'updated': true,
        'created': true,
      };
    }
  }

  Future<Map<String, dynamic>> deleteRepositoryVariable({
    required String owner,
    required String repo,
    required String name,
    required String confirmVariableName,
  }) async {
    final variableName = _requiredVariableName(name);
    if (confirmVariableName.trim() != variableName) {
      throw ArgumentError(
        'confirm_variable_name must exactly equal $variableName',
      );
    }
    await _deleteText(
      '/repos/${_segment(owner)}/${_segment(repo)}/actions/variables/$variableName',
    );
    return {
      'owner': owner,
      'repo': repo,
      'variable': variableName,
      'deleted': true,
    };
  }

  void close() {
    if (_ownsClient) _httpClient.close();
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String> query = const {},
  }) async {
    final text = await _getText(path, query: query);
    if (text.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw GitHubApiException(
        statusCode: 502,
        message: 'Expected GitHub JSON object response.',
      );
    }
    return decoded.cast<String, dynamic>();
  }

  Future<List<dynamic>> _getJsonList(
    String path, {
    Map<String, String> query = const {},
  }) async {
    final text = await _getText(path, query: query);
    if (text.trim().isEmpty) return const <dynamic>[];
    final decoded = jsonDecode(text);
    if (decoded is! List) {
      throw GitHubApiException(
        statusCode: 502,
        message: 'Expected GitHub JSON array response.',
      );
    }
    return decoded;
  }

  Future<String> _getText(
    String path, {
    Map<String, String> query = const {},
    String accept = 'application/vnd.github+json',
  }) async {
    return _requestText(path, query: query, accept: accept);
  }

  Future<Map<String, dynamic>> _postJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    return _decodeObject(await _requestText(path, method: 'POST', body: body));
  }

  Future<String> _postText(String path, {required Map<String, dynamic> body}) {
    return _requestText(path, method: 'POST', body: body);
  }

  Future<Map<String, dynamic>> _putJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    return _decodeObject(await _requestText(path, method: 'PUT', body: body));
  }

  Future<String> _putText(String path, {required Map<String, dynamic> body}) {
    return _requestText(path, method: 'PUT', body: body);
  }

  Future<Map<String, dynamic>> _patchJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    return _decodeObject(await _requestText(path, method: 'PATCH', body: body));
  }

  Future<String> _patchText(String path, {required Map<String, dynamic> body}) {
    return _requestText(path, method: 'PATCH', body: body);
  }

  Future<Map<String, dynamic>> _deleteJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    return _decodeObject(
      await _requestText(path, method: 'DELETE', body: body),
    );
  }

  Future<String> _deleteText(String path, {Map<String, dynamic>? body}) {
    return _requestText(path, method: 'DELETE', body: body);
  }

  Future<List<int>> _getBytes(
    String path, {
    Map<String, String> query = const {},
    String accept = 'application/vnd.github+json',
  }) async {
    final uri = _uri(path, query);
    final headers = await _headers(accept: accept);
    final response = await _httpClient
        .get(uri, headers: headers)
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response);
    }
    return response.bodyBytes;
  }

  Future<String> _requestText(
    String path, {
    String method = 'GET',
    Map<String, String> query = const {},
    String accept = 'application/vnd.github+json',
    Map<String, dynamic>? body,
  }) async {
    final uri = _uri(path, query);
    final headers = await _headers(accept: accept);
    Object? encodedBody;
    if (body != null) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
      encodedBody = jsonEncode(body);
    }
    final normalizedMethod = method.toUpperCase();
    final response = await switch (normalizedMethod) {
      'GET' => _httpClient.get(uri, headers: headers),
      'POST' => _httpClient.post(uri, headers: headers, body: encodedBody),
      'PUT' => _httpClient.put(uri, headers: headers, body: encodedBody),
      'PATCH' => _httpClient.patch(uri, headers: headers, body: encodedBody),
      'DELETE' => _httpClient.delete(uri, headers: headers, body: encodedBody),
      _ => throw ArgumentError('Unsupported GitHub API method: $method'),
    }.timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response);
    }
    return response.body;
  }

  Map<String, dynamic> _decodeObject(String text) {
    if (text.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw GitHubApiException(
        statusCode: 502,
        message: 'Expected GitHub JSON object response.',
      );
    }
    return decoded.cast<String, dynamic>();
  }

  Future<Map<String, String>> _headers({required String accept}) async {
    final headers = <String, String>{
      'Accept': accept,
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'Kelivo-GitHub-MCP',
    };
    final token = (await accessTokenProvider?.call())?.trim();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Uri _uri(String path, Map<String, String> query) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    final fullPath = <String>[
      if (basePath.isNotEmpty) basePath,
      cleanPath,
    ].join('/');
    final filteredQuery = <String, String>{
      for (final entry in query.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value,
    };
    return _baseUri.replace(
      path: fullPath.startsWith('/') ? fullPath : '/$fullPath',
      queryParameters: filteredQuery.isEmpty ? null : filteredQuery,
    );
  }

  GitHubApiException _apiException(http.Response response) {
    String message = response.reasonPhrase ?? 'Request failed';
    String? documentationUrl;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        message = (decoded['message'] ?? message).toString();
        final doc = decoded['documentation_url'];
        if (doc != null) documentationUrl = doc.toString();
      }
    } catch (_) {
      if (response.body.trim().isNotEmpty) message = response.body.trim();
    }
    return GitHubApiException(
      statusCode: response.statusCode,
      message: message,
      documentationUrl: documentationUrl,
    );
  }

  static Map<String, dynamic> _compactSearch(
    Map<String, dynamic> raw, {
    required String query,
    required Map<String, dynamic> Function(dynamic item) mapper,
  }) {
    final items = raw['items'];
    return {
      'query': query,
      'total_count': raw['total_count'] ?? 0,
      'incomplete_results': raw['incomplete_results'] ?? false,
      'items': items is List
          ? items.map(mapper).toList(growable: false)
          : const <dynamic>[],
    };
  }

  static Map<String, dynamic> _codeItem(dynamic item) {
    final map = _asMap(item);
    final repo = _asMap(map['repository']);
    return {
      'name': map['name'],
      'path': map['path'],
      'sha': map['sha'],
      'html_url': map['html_url'],
      'score': map['score'],
      'repository': {
        'full_name': repo['full_name'],
        'html_url': repo['html_url'],
        'default_branch': repo['default_branch'],
        'private': repo['private'],
      },
    };
  }

  static Map<String, dynamic> _repositoryItem(dynamic item) {
    final map = _asMap(item);
    final owner = _asMap(map['owner']);
    final license = _asMap(map['license']);
    return {
      'full_name': map['full_name'],
      'name': map['name'],
      'owner': owner['login'],
      'private': map['private'],
      'description': map['description'],
      'html_url': map['html_url'],
      'language': map['language'],
      'default_branch': map['default_branch'],
      'stargazers_count': map['stargazers_count'],
      'forks_count': map['forks_count'],
      'open_issues_count': map['open_issues_count'],
      'archived': map['archived'],
      'updated_at': map['updated_at'],
      if (map['topics'] is List) 'topics': map['topics'],
      if (license.isNotEmpty) 'license': license['spdx_id'] ?? license['key'],
    };
  }

  static Map<String, dynamic> _issueItem(dynamic item) {
    final map = _asMap(item);
    final user = _asMap(map['user']);
    final labels = map['labels'];
    return {
      'number': map['number'],
      'title': map['title'],
      'state': map['state'],
      'html_url': map['html_url'],
      'repository': _repoNameFromApiUrl(
        (map['repository_url'] ?? '').toString(),
      ),
      'author': user['login'],
      'comments': map['comments'],
      'created_at': map['created_at'],
      'updated_at': map['updated_at'],
      'is_pull_request': map.containsKey('pull_request'),
      'labels': labels is List
          ? labels.map((e) => _asMap(e)['name']).whereType<String>().toList()
          : const <String>[],
    };
  }

  static Map<String, dynamic> _commentItem(dynamic item) {
    final map = _asMap(item);
    final user = _asMap(map['user']);
    return {
      'id': map['id'],
      'user': user['login'],
      'html_url': map['html_url'],
      'created_at': map['created_at'],
      'updated_at': map['updated_at'],
      'body': map['body'],
    };
  }

  static Map<String, dynamic> _contentListItem(dynamic item) {
    final map = _asMap(item);
    return {
      'name': map['name'],
      'path': map['path'],
      'sha': map['sha'],
      'type': map['type'],
      'size': map['size'],
      'html_url': map['html_url'],
      'download_url': map['download_url'],
    };
  }

  static Map<String, dynamic> _branchItem(dynamic item) {
    final map = _asMap(item);
    final commit = _asMap(map['commit']);
    return {
      'name': map['name'],
      'protected': map['protected'],
      'commit': {'sha': commit['sha'], 'url': commit['url']},
    };
  }

  static Map<String, dynamic> _tagItem(dynamic item) {
    final map = _asMap(item);
    final commit = _asMap(map['commit']);
    return {
      'name': map['name'],
      'zipball_url': map['zipball_url'],
      'tarball_url': map['tarball_url'],
      'commit': {'sha': commit['sha'], 'url': commit['url']},
    };
  }

  static Map<String, dynamic> _commitSummaryItem(dynamic item) {
    final map = _asMap(item);
    final commit = _asMap(map['commit']);
    final author = _asMap(commit['author']);
    final user = _asMap(map['author']);
    return {
      'sha': map['sha'],
      'html_url': map['html_url'],
      'message': commit['message'],
      'author': {
        'name': author['name'],
        'email': author['email'],
        'date': author['date'],
        'login': user['login'],
      },
    };
  }

  static Map<String, dynamic> _commitDetailItem(dynamic item) {
    final map = _commitSummaryItem(item);
    final raw = _asMap(item);
    map['files'] = raw['files'] is List
        ? (raw['files'] as List).map(_fileChangeItem).toList(growable: false)
        : const <dynamic>[];
    final stats = _asMap(raw['stats']);
    if (stats.isNotEmpty) map['stats'] = stats;
    return map;
  }

  static Map<String, dynamic> _fileChangeItem(dynamic item) {
    final map = _asMap(item);
    return {
      'filename': map['filename'],
      'status': map['status'],
      'additions': map['additions'],
      'deletions': map['deletions'],
      'changes': map['changes'],
      'sha': map['sha'],
      'blob_url': map['blob_url'],
      'raw_url': map['raw_url'],
      'contents_url': map['contents_url'],
      if (map['patch'] != null) 'patch': map['patch'],
    };
  }

  static Map<String, dynamic> _pullRequestItem(dynamic item) {
    final map = _asMap(item);
    final user = _asMap(map['user']);
    final head = _asMap(map['head']);
    final base = _asMap(map['base']);
    return {
      'number': map['number'],
      'title': map['title'],
      'state': map['state'],
      'draft': map['draft'],
      'html_url': map['html_url'],
      'author': user['login'],
      'head': {'ref': head['ref'], 'sha': head['sha'], 'label': head['label']},
      'base': {'ref': base['ref'], 'sha': base['sha'], 'label': base['label']},
      'created_at': map['created_at'],
      'updated_at': map['updated_at'],
      'body': map['body'],
    };
  }

  static Map<String, dynamic> _pullRequestReviewItem(dynamic item) {
    final map = _asMap(item);
    final user = _asMap(map['user']);
    return {
      'id': map['id'],
      'user': user['login'],
      'state': map['state'],
      'body': map['body'],
      'commit_id': map['commit_id'],
      'submitted_at': map['submitted_at'],
      'html_url': map['html_url'],
    };
  }

  static Map<String, dynamic> _pullRequestReviewCommentItem(dynamic item) {
    final map = _asMap(item);
    final user = _asMap(map['user']);
    return {
      'id': map['id'],
      'user': user['login'],
      'body': map['body'],
      'path': map['path'],
      'diff_hunk': map['diff_hunk'],
      'line': map['line'],
      'side': map['side'],
      'commit_id': map['commit_id'],
      'in_reply_to_id': map['in_reply_to_id'],
      'html_url': map['html_url'],
      'created_at': map['created_at'],
      'updated_at': map['updated_at'],
    };
  }

  static Map<String, dynamic> _releaseItem(dynamic item) {
    final map = _asMap(item);
    final author = _asMap(map['author']);
    final assets = map['assets'];
    return {
      'id': map['id'],
      'tag_name': map['tag_name'],
      'target_commitish': map['target_commitish'],
      'name': map['name'],
      'draft': map['draft'],
      'prerelease': map['prerelease'],
      'html_url': map['html_url'],
      'upload_url': map['upload_url'],
      'author': author['login'],
      'created_at': map['created_at'],
      'published_at': map['published_at'],
      'body': map['body'],
      'assets': assets is List
          ? assets.map(_releaseAssetItem).toList(growable: false)
          : const <dynamic>[],
    };
  }

  static Map<String, dynamic> _releaseAssetItem(dynamic item) {
    final map = _asMap(item);
    return {
      'id': map['id'],
      'name': map['name'],
      'label': map['label'],
      'content_type': map['content_type'],
      'size': map['size'],
      'download_count': map['download_count'],
      'browser_download_url': map['browser_download_url'],
      'created_at': map['created_at'],
      'updated_at': map['updated_at'],
    };
  }

  static Map<String, dynamic> _workflowItem(dynamic item) {
    final map = _asMap(item);
    return {
      'id': map['id'],
      'name': map['name'],
      'path': map['path'],
      'state': map['state'],
      'html_url': map['html_url'],
      'badge_url': map['badge_url'],
      'created_at': map['created_at'],
      'updated_at': map['updated_at'],
    };
  }

  static Map<String, dynamic> _workflowRunItem(dynamic item) {
    final map = _asMap(item);
    final headCommit = _asMap(map['head_commit']);
    return {
      'id': map['id'],
      'name': map['name'],
      'display_title': map['display_title'],
      'status': map['status'],
      'conclusion': map['conclusion'],
      'event': map['event'],
      'workflow_id': map['workflow_id'],
      'run_number': map['run_number'],
      'run_attempt': map['run_attempt'],
      'head_branch': map['head_branch'],
      'head_sha': map['head_sha'],
      'html_url': map['html_url'],
      'created_at': map['created_at'],
      'updated_at': map['updated_at'],
      if (headCommit.isNotEmpty)
        'head_commit': {
          'id': headCommit['id'],
          'message': headCommit['message'],
        },
    };
  }

  static Map<String, dynamic> _workflowJobItem(dynamic item) {
    final map = _asMap(item);
    return {
      'id': map['id'],
      'run_id': map['run_id'],
      'name': map['name'],
      'status': map['status'],
      'conclusion': map['conclusion'],
      'started_at': map['started_at'],
      'completed_at': map['completed_at'],
      'html_url': map['html_url'],
      'steps': map['steps'] is List ? map['steps'] : const <dynamic>[],
    };
  }

  static Map<String, dynamic> _variableItem(dynamic item) {
    final map = _asMap(item);
    return {
      'name': map['name'],
      'value': map['value'],
      'created_at': map['created_at'],
      'updated_at': map['updated_at'],
    };
  }

  static Map<String, dynamic> _contentMutationResult(
    Map<String, dynamic> raw, {
    required String owner,
    required String repo,
    required String path,
    String? branch,
  }) {
    final content = _asMap(raw['content']);
    final commit = _asMap(raw['commit']);
    return {
      'owner': owner,
      'repo': repo,
      'path': content['path'] ?? path,
      if ((branch ?? '').trim().isNotEmpty) 'branch': branch!.trim(),
      'content': {
        'name': content['name'],
        'path': content['path'],
        'sha': content['sha'],
        'html_url': content['html_url'],
      },
      'commit': {
        'sha': commit['sha'],
        'html_url': commit['html_url'],
        'message': commit['message'],
      },
    };
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return value.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  static String _repoNameFromApiUrl(String repositoryUrl) {
    final marker = '/repos/';
    final index = repositoryUrl.indexOf(marker);
    if (index < 0) return repositoryUrl;
    return repositoryUrl.substring(index + marker.length);
  }

  static String _ensureIssueKind(String query, String kind) {
    if (RegExp(r'\bis:(issue|pr)\b', caseSensitive: false).hasMatch(query)) {
      return query;
    }
    return '$query $kind';
  }

  static String _requiredQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('query must not be empty');
    }
    return trimmed;
  }

  static String _requiredMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) throw ArgumentError('message must not be empty');
    return trimmed;
  }

  static String _requiredRepositoryName(String name) {
    final trimmed = _requiredQuery(name);
    if (trimmed.contains('/') || trimmed.contains('\\')) {
      throw ArgumentError('repository name must not contain path separators');
    }
    return trimmed;
  }

  static String _requiredBranchName(String branch) {
    final trimmed = _requiredQuery(branch);
    if (trimmed.startsWith('/') ||
        trimmed.endsWith('/') ||
        trimmed.contains('..') ||
        trimmed.contains(' ')) {
      throw ArgumentError('branch must be a valid Git ref name');
    }
    return trimmed;
  }

  static String _requiredPath(String path) {
    final trimmed = path.trim().replaceAll('\\', '/');
    if (trimmed.isEmpty) throw ArgumentError('path must not be empty');
    if (trimmed.startsWith('/') || trimmed.contains('..')) {
      throw ArgumentError('path must be a relative GitHub repository path');
    }
    return trimmed;
  }

  static String _segment(String value) => _requiredQuery(value);

  static String _requiredPullReviewEvent(String event) {
    final value = event.trim().toUpperCase();
    const allowed = {'APPROVE', 'REQUEST_CHANGES', 'COMMENT'};
    if (!allowed.contains(value)) {
      throw ArgumentError('event must be APPROVE, REQUEST_CHANGES, or COMMENT');
    }
    return value;
  }

  static String _requiredReviewSide(String side) {
    final value = side.trim().toUpperCase();
    if (value != 'LEFT' && value != 'RIGHT') {
      throw ArgumentError('side must be LEFT or RIGHT');
    }
    return value;
  }

  static String _requiredReviewSubjectType(String subjectType) {
    final value = subjectType.trim().toLowerCase();
    if (value != 'line' && value != 'file') {
      throw ArgumentError('subject_type must be line or file');
    }
    return value;
  }

  static String _requiredMergeMethod(String method) {
    final value = method.trim().toLowerCase();
    const allowed = {'merge', 'squash', 'rebase'};
    if (!allowed.contains(value)) {
      throw ArgumentError('merge_method must be merge, squash, or rebase');
    }
    return value;
  }

  static String _requiredSecretName(String name) {
    final value = _requiredQuery(name).toUpperCase();
    if (!RegExp(r'^[A-Z0-9_]+$').hasMatch(value)) {
      throw ArgumentError(
        'secret or variable name must use A-Z, 0-9, or underscore',
      );
    }
    return value;
  }

  static String _requiredVariableName(String name) {
    final value = _requiredSecretName(name);
    if (value.startsWith('GITHUB_')) {
      throw ArgumentError(
        'GitHub Actions variables cannot use the reserved GITHUB_ prefix. Use TOOL_, APP_, CI_, or another project-specific prefix instead.',
      );
    }
    return value;
  }

  static bool _looksLikeEmptyRepositoryError(GitHubApiException error) {
    final message = error.message.toLowerCase();
    return error.statusCode == 409 ||
        (error.statusCode == 404 &&
            (message.contains('empty') || message.contains('no commit')));
  }

  static String _secretKind(String kind) {
    final value = kind.trim().toLowerCase();
    if (value == 'dependabot') return 'dependabot';
    if (value == 'codespaces') return 'codespaces';
    if (value == 'actions' || value.isEmpty) return 'actions';
    throw ArgumentError('kind must be actions, dependabot, or codespaces');
  }

  static String _pathSegments(String path) =>
      path.split('/').where((segment) => segment.isNotEmpty).join('/');

  static Map<String, String> _pagingQuery({
    required int perPage,
    required int page,
  }) => {
    'per_page': _boundedResultLimit(perPage).toString(),
    'page': _positiveInt(page, name: 'page').toString(),
  };

  static int _boundedResultLimit(int value) {
    if (value < 1) return 1;
    if (value > maximumResultLimit) return maximumResultLimit;
    return value;
  }

  static int _boundedTextLength(int value) {
    if (value < 1) return 1;
    if (value > maximumMaxTextLength) return maximumMaxTextLength;
    return value;
  }

  static int _positiveInt(int value, {required String name}) {
    if (value < 1) throw ArgumentError('$name must be positive');
    return value;
  }

  static int _nonNegativeInt(int value, {required String name}) {
    if (value < 0) throw ArgumentError('$name must not be negative');
    return value;
  }

  Future<String> _defaultBranch({
    required String owner,
    required String repo,
  }) async {
    final repository = await getRepository(owner: owner, repo: repo);
    return _requiredQuery((repository['default_branch'] ?? '').toString());
  }

  Future<String> _branchCommitSha({
    required String owner,
    required String repo,
    required String branch,
  }) async {
    final raw = await _getJson(
      '/repos/${_segment(owner)}/${_segment(repo)}/git/ref/heads/${_pathSegments(_requiredBranchName(branch))}',
    );
    final object = _asMap(raw['object']);
    final sha = (object['sha'] ?? '').toString();
    if (sha.isEmpty) {
      throw GitHubApiException(
        statusCode: 502,
        message: 'GitHub branch ref response did not include object.sha.',
      );
    }
    return sha;
  }

  static String _repositorySecretsPublicKeyPath({
    required String owner,
    required String repo,
    required String kind,
  }) {
    final normalized = _secretKind(kind);
    return '/repos/${_segment(owner)}/${_segment(repo)}/$normalized/secrets/public-key';
  }

  static String _repositorySecretPath({
    required String owner,
    required String repo,
    required String secretName,
    required String kind,
  }) {
    final normalized = _secretKind(kind);
    final name = _requiredSecretName(secretName);
    return '/repos/${_segment(owner)}/${_segment(repo)}/$normalized/secrets/$name';
  }

  static _BoundedGitHubText _boundedText(
    String text, {
    required int maxLength,
    required int startIndex,
  }) {
    if (startIndex >= text.length) {
      return _BoundedGitHubText(
        content: '',
        startIndex: startIndex,
        nextStartIndex: null,
        truncated: false,
        totalCharacters: text.length,
      );
    }
    final endIndex = startIndex + maxLength > text.length
        ? text.length
        : startIndex + maxLength;
    return _BoundedGitHubText(
      content: text.substring(startIndex, endIndex),
      startIndex: startIndex,
      nextStartIndex: endIndex < text.length ? endIndex : null,
      truncated: endIndex < text.length,
      totalCharacters: text.length,
    );
  }
}

class _BoundedGitHubText {
  const _BoundedGitHubText({
    required this.content,
    required this.startIndex,
    required this.nextStartIndex,
    required this.truncated,
    required this.totalCharacters,
  });

  final String content;
  final int startIndex;
  final int? nextStartIndex;
  final bool truncated;
  final int totalCharacters;

  Map<String, dynamic> toJson({required String contentKey}) => {
    contentKey: content,
    'start_index': startIndex,
    'next_start_index': nextStartIndex,
    'truncated': truncated,
    'total_characters': totalCharacters,
  };
}
