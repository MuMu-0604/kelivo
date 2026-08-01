import 'dart:convert';

import 'package:mcp_client/mcp_client.dart' as mcp;

import '../in_memory_mcp_server.dart';
import 'github_api_client.dart';

class KelivoGithubMcpServerEngine implements KelivoInMemoryMcpServerEngine {
  KelivoGithubMcpServerEngine({GitHubApiClient? client})
    : _client = client ?? GitHubApiClient();

  final GitHubApiClient _client;
  bool _closed = false;

  @override
  Future<dynamic> handleMessage(dynamic message) async {
    if (_closed) return null;

    if (message is List) {
      final responses = <dynamic>[];
      for (final item in message) {
        responses.add(await _handleSingle(item));
      }
      return responses;
    }
    return _handleSingle(message);
  }

  Future<Map<String, dynamic>> _handleSingle(dynamic raw) async {
    try {
      if (raw is! Map) {
        return _error(null, code: -32600, message: 'Invalid Request');
      }
      final request = raw.cast<String, dynamic>();
      final id = request['id'];
      final method = (request['method'] ?? '').toString();
      final params = (request['params'] is Map)
          ? (request['params'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      switch (method) {
        case mcp.McpProtocol.methodInitialize:
          return _ok(
            id,
            result: {
              'serverInfo': {'name': '@kelivo/github', 'version': '0.1.0'},
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
    } catch (error) {
      return _error(null, code: -32603, message: 'Internal error: $error');
    }
  }

  Future<Map<String, dynamic>> _callTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      switch (name) {
        case 'github_get_viewer':
          return _okText(await _json(_client.getViewer()));
        case 'github_search':
          return _callLegacyAction(args, {
            'code': 'github_search_code',
            'repositories': 'github_search_repositories',
            'repos': 'github_search_repositories',
            'issues': 'github_search_issues',
            'pull_requests': 'github_search_pull_requests',
            'prs': 'github_search_pull_requests',
          });
        case 'github_repository_read':
          return _callLegacyAction(args, {
            'get': 'github_get_repository',
            'list_directory': 'github_list_directory',
            'directory': 'github_list_directory',
            'list_branches': 'github_list_branches',
            'branches': 'github_list_branches',
            'list_tags': 'github_list_tags',
            'tags': 'github_list_tags',
            'list_commits': 'github_list_commits',
            'commits': 'github_list_commits',
            'get_commit': 'github_get_commit',
            'compare_refs': 'github_compare_refs',
            'compare': 'github_compare_refs',
            'get_file': 'github_get_file',
            'file': 'github_get_file',
          });
        case 'github_repository_write':
          return _callLegacyAction(args, {
            'create_repository': 'github_create_repository',
            'create_repo': 'github_create_repository',
            'update_repository': 'github_update_repository',
            'update_repo': 'github_update_repository',
            'delete_repository': 'github_delete_repository',
            'delete_repo': 'github_delete_repository',
            'fork_repository': 'github_fork_repository',
            'fork_repo': 'github_fork_repository',
            'create_branch': 'github_create_branch',
            'create_or_update_file': 'github_create_or_update_file',
            'write_file': 'github_create_or_update_file',
            'delete_file': 'github_delete_file',
            'delete_branch': 'github_delete_branch',
          });
        case 'github_issue_read':
          return _callLegacyAction(args, {
            'get_comments': 'github_get_issue_comments',
            'comments': 'github_get_issue_comments',
          });
        case 'github_issue_write':
          return _callLegacyAction(args, {
            'create': 'github_create_issue',
            'update': 'github_update_issue',
            'comment': 'github_create_issue_comment',
            'create_comment': 'github_create_issue_comment',
          });
        case 'github_pull_request_read':
          return _callLegacyAction(args, {
            'get': 'github_get_pull_request',
            'diff': 'github_get_pr_diff',
            'list_files': 'github_list_pr_files',
            'files': 'github_list_pr_files',
            'list_reviews': 'github_list_pr_reviews',
            'reviews': 'github_list_pr_reviews',
            'list_review_comments': 'github_list_pr_review_comments',
            'review_comments': 'github_list_pr_review_comments',
          });
        case 'github_pull_request_write':
          return _callLegacyAction(args, {
            'create': 'github_create_pull_request',
            'update': 'github_update_pull_request',
            'create_review': 'github_create_pr_review',
            'review': 'github_create_pr_review',
            'create_review_comment': 'github_create_pr_review_comment',
            'review_comment': 'github_create_pr_review_comment',
            'merge': 'github_merge_pull_request',
          });
        case 'github_release_read':
          return _callLegacyAction(args, {
            'list': 'github_list_releases',
            'get': 'github_get_release',
          });
        case 'github_release_write':
          return _callLegacyAction(args, {
            'create': 'github_create_release',
            'update': 'github_update_release',
            'delete': 'github_delete_release',
          });
        case 'github_actions_read':
          return _callLegacyAction(args, {
            'list_workflows': 'github_list_workflows',
            'workflows': 'github_list_workflows',
            'list_runs': 'github_list_workflow_runs',
            'runs': 'github_list_workflow_runs',
            'get_run': 'github_get_workflow_run',
            'list_jobs': 'github_list_workflow_run_jobs',
            'jobs': 'github_list_workflow_run_jobs',
            'get_logs': 'github_get_workflow_run_logs',
            'logs': 'github_get_workflow_run_logs',
          });
        case 'github_actions_write':
          return _callLegacyAction(args, {
            'dispatch': 'github_dispatch_workflow',
            'dispatch_workflow': 'github_dispatch_workflow',
            'rerun': 'github_rerun_workflow_run',
            'rerun_run': 'github_rerun_workflow_run',
            'cancel': 'github_cancel_workflow_run',
            'cancel_run': 'github_cancel_workflow_run',
          });
        case 'github_secrets_read':
          return _callLegacyAction(args, {
            'get_public_key': 'github_get_repo_public_key',
            'public_key': 'github_get_repo_public_key',
            'list_variables': 'github_list_repo_variables',
            'variables': 'github_list_repo_variables',
          });
        case 'github_secrets_write':
          return _callLegacyAction(args, {
            'put_secret': 'github_put_repo_secret',
            'set_secret': 'github_put_repo_secret',
            'delete_secret': 'github_delete_repo_secret',
            'put_variable': 'github_create_or_update_repo_variable',
            'set_variable': 'github_create_or_update_repo_variable',
            'delete_variable': 'github_delete_repo_variable',
          });
        case 'github_search_code':
          return _okText(
            await _json(
              _client.searchCode(
                query: _stringArg(args, 'query', requiredValue: true),
                perPage: _intArg(args, 'per_page', defaultValue: 10),
                page: _intArg(args, 'page', defaultValue: 1),
              ),
            ),
          );
        case 'github_search_repositories':
          return _okText(
            await _json(
              _client.searchRepositories(
                query: _stringArg(args, 'query', requiredValue: true),
                perPage: _intArg(args, 'per_page', defaultValue: 10),
                page: _intArg(args, 'page', defaultValue: 1),
              ),
            ),
          );
        case 'github_search_issues':
          return _okText(
            await _json(
              _client.searchIssues(
                query: _stringArg(args, 'query', requiredValue: true),
                perPage: _intArg(args, 'per_page', defaultValue: 10),
                page: _intArg(args, 'page', defaultValue: 1),
              ),
            ),
          );
        case 'github_search_pull_requests':
          return _okText(
            await _json(
              _client.searchPullRequests(
                query: _stringArg(args, 'query', requiredValue: true),
                perPage: _intArg(args, 'per_page', defaultValue: 10),
                page: _intArg(args, 'page', defaultValue: 1),
              ),
            ),
          );
        case 'github_get_repository':
          return _okText(
            await _json(
              _client.getRepository(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
              ),
            ),
          );
        case 'github_create_repository':
          return _okText(
            await _json(
              _client.createRepository(
                name: _stringArg(args, 'name', requiredValue: true),
                description: _stringArg(args, 'description'),
                private: _boolArg(args, 'private'),
                org: _stringArg(args, 'org'),
                autoInit: _boolArg(args, 'auto_init'),
              ),
            ),
          );
        case 'github_update_repository':
          return _okText(
            await _json(
              _client.updateRepository(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                name: _stringArg(args, 'name'),
                description: args.containsKey('description')
                    ? args['description']?.toString()
                    : null,
                private: args.containsKey('private')
                    ? _boolArg(args, 'private')
                    : null,
                hasIssues: args.containsKey('has_issues')
                    ? _boolArg(args, 'has_issues')
                    : null,
                hasWiki: args.containsKey('has_wiki')
                    ? _boolArg(args, 'has_wiki')
                    : null,
                archived: args.containsKey('archived')
                    ? _boolArg(args, 'archived')
                    : null,
                defaultBranch: _stringArg(args, 'default_branch'),
              ),
            ),
          );
        case 'github_delete_repository':
          return _okText(
            await _json(
              _client.deleteRepository(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                confirmRepoFullName: _stringArg(
                  args,
                  'confirm_repo_full_name',
                  requiredValue: true,
                ),
              ),
            ),
          );
        case 'github_fork_repository':
          return _okText(
            await _json(
              _client.forkRepository(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                organization: _stringArg(args, 'organization'),
                name: _stringArg(args, 'name'),
                defaultBranchOnly: args.containsKey('default_branch_only')
                    ? _boolArg(args, 'default_branch_only')
                    : null,
              ),
            ),
          );
        case 'github_list_directory':
          return _okText(
            await _json(
              _client.listDirectory(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                path: _stringArg(args, 'path'),
                ref: _stringArg(args, 'ref'),
              ),
            ),
          );
        case 'github_list_branches':
          return _okText(
            await _json(
              _client.listBranches(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                perPage: _intArg(args, 'per_page', defaultValue: 10),
                page: _intArg(args, 'page', defaultValue: 1),
              ),
            ),
          );
        case 'github_list_tags':
          return _okText(
            await _json(
              _client.listTags(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                perPage: _intArg(args, 'per_page', defaultValue: 10),
                page: _intArg(args, 'page', defaultValue: 1),
              ),
            ),
          );
        case 'github_list_commits':
          return _okText(
            await _json(
              _client.listCommits(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                sha: _stringArg(args, 'sha'),
                path: _stringArg(args, 'path'),
                perPage: _intArg(args, 'per_page', defaultValue: 10),
                page: _intArg(args, 'page', defaultValue: 1),
              ),
            ),
          );
        case 'github_get_commit':
          return _okText(
            await _json(
              _client.getCommit(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                ref: _stringArg(args, 'ref', requiredValue: true),
              ),
            ),
          );
        case 'github_compare_refs':
          return _okText(
            await _json(
              _client.compareRefs(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                base: _stringArg(args, 'base', requiredValue: true),
                head: _stringArg(args, 'head', requiredValue: true),
              ),
            ),
          );
        case 'github_get_file':
          return _okText(
            await _json(
              _client.getFile(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                path: _stringArg(args, 'path', requiredValue: true),
                ref: _stringArg(args, 'ref'),
                maxLength: _intArg(args, 'max_length', defaultValue: 12000),
                startIndex: _intArg(args, 'start_index', defaultValue: 0),
              ),
            ),
          );
        case 'github_get_issue_comments':
          return _okText(
            await _json(
              _client.getIssueComments(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                issueNumber: _intArg(args, 'issue_number', requiredValue: true),
                perPage: _intArg(args, 'per_page', defaultValue: 10),
                page: _intArg(args, 'page', defaultValue: 1),
              ),
            ),
          );
        case 'github_get_pr_diff':
          return _okText(
            await _json(
              _client.getPullRequestDiff(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                pullNumber: _intArg(args, 'pull_number', requiredValue: true),
                maxLength: _intArg(args, 'max_length', defaultValue: 12000),
                startIndex: _intArg(args, 'start_index', defaultValue: 0),
              ),
            ),
          );
        case 'github_get_pull_request':
          return _okText(
            await _json(
              _client.getPullRequest(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                pullNumber: _intArg(args, 'pull_number', requiredValue: true),
              ),
            ),
          );
        case 'github_update_pull_request':
          return _okText(
            await _json(
              _client.updatePullRequest(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                pullNumber: _intArg(args, 'pull_number', requiredValue: true),
                title: _stringArg(args, 'title'),
                body: args.containsKey('body')
                    ? args['body']?.toString()
                    : null,
                state: _stringArg(args, 'state'),
                base: _stringArg(args, 'base'),
                maintainerCanModify: args.containsKey('maintainer_can_modify')
                    ? _boolArg(args, 'maintainer_can_modify')
                    : null,
              ),
            ),
          );
        case 'github_list_pr_files':
          return _okText(
            await _json(
              _client.listPullRequestFiles(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                pullNumber: _intArg(args, 'pull_number', requiredValue: true),
                perPage: _intArg(args, 'per_page', defaultValue: 10),
                page: _intArg(args, 'page', defaultValue: 1),
              ),
            ),
          );
        case 'github_list_pr_reviews':
          return _okText(
            await _json(
              _client.listPullRequestReviews(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                pullNumber: _intArg(args, 'pull_number', requiredValue: true),
                perPage: _intArg(args, 'per_page', defaultValue: 10),
                page: _intArg(args, 'page', defaultValue: 1),
              ),
            ),
          );
        case 'github_list_pr_review_comments':
          return _okText(
            await _json(
              _client.listPullRequestReviewComments(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                pullNumber: _intArg(args, 'pull_number', requiredValue: true),
                perPage: _intArg(args, 'per_page', defaultValue: 10),
                page: _intArg(args, 'page', defaultValue: 1),
              ),
            ),
          );
        case 'github_create_pr_review':
          return _okText(
            await _json(
              _client.createPullRequestReview(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                pullNumber: _intArg(args, 'pull_number', requiredValue: true),
                body: _stringArg(args, 'body'),
                event: _stringArg(args, 'event', defaultValue: 'COMMENT'),
              ),
            ),
          );
        case 'github_create_pr_review_comment':
          return _okText(
            await _json(
              _client.createPullRequestReviewComment(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                pullNumber: _intArg(args, 'pull_number', requiredValue: true),
                body: _stringArg(args, 'body', requiredValue: true),
                commitId: _stringArg(args, 'commit_id'),
                path: _stringArg(args, 'path'),
                line: args.containsKey('line') ? _intArg(args, 'line') : null,
                side: _stringArg(args, 'side', defaultValue: 'RIGHT'),
                startLine: args.containsKey('start_line')
                    ? _intArg(args, 'start_line')
                    : null,
                startSide: _stringArg(args, 'start_side'),
                subjectType: _stringArg(args, 'subject_type'),
                inReplyTo: _optionalPositiveIntArg(args, 'in_reply_to'),
              ),
            ),
          );
        case 'github_merge_pull_request':
          return _okText(
            await _json(
              _client.mergePullRequest(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                pullNumber: _intArg(args, 'pull_number', requiredValue: true),
                commitTitle: _stringArg(args, 'commit_title'),
                commitMessage: _stringArg(args, 'commit_message'),
                mergeMethod: _stringArg(
                  args,
                  'merge_method',
                  defaultValue: 'merge',
                ),
                expectedHeadSha: _stringArg(args, 'expected_head_sha'),
              ),
            ),
          );
        case 'github_delete_branch':
          return _okText(
            await _json(
              _client.deleteBranch(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                branch: _stringArg(args, 'branch', requiredValue: true),
                confirmBranch: _stringArg(
                  args,
                  'confirm_branch',
                  requiredValue: true,
                ),
              ),
            ),
          );
        case 'github_create_branch':
          return _okText(
            await _json(
              _client.createBranch(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                branch: _stringArg(args, 'branch', requiredValue: true),
                fromSha: _stringArg(args, 'from_sha'),
                fromBranch: _stringArg(args, 'from_branch'),
              ),
            ),
          );
        case 'github_create_or_update_file':
          return _okText(
            await _json(
              _client.createOrUpdateFile(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                path: _stringArg(args, 'path', requiredValue: true),
                content: _stringArg(args, 'content', requiredValue: true),
                message: _stringArg(args, 'message', requiredValue: true),
                branch: _stringArg(args, 'branch'),
                sha: _stringArg(args, 'sha'),
              ),
            ),
          );
        case 'github_delete_file':
          return _okText(
            await _json(
              _client.deleteFile(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                path: _stringArg(args, 'path', requiredValue: true),
                sha: _stringArg(args, 'sha', requiredValue: true),
                message: _stringArg(args, 'message', requiredValue: true),
                branch: _stringArg(args, 'branch'),
              ),
            ),
          );
        case 'github_create_issue':
          return _okText(
            await _json(
              _client.createIssue(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                title: _stringArg(args, 'title', requiredValue: true),
                body: _stringArg(args, 'body'),
                labels: _stringListArg(args, 'labels'),
                assignees: _stringListArg(args, 'assignees'),
              ),
            ),
          );
        case 'github_update_issue':
          return _okText(
            await _json(
              _client.updateIssue(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                issueNumber: _intArg(args, 'issue_number', requiredValue: true),
                title: _stringArg(args, 'title'),
                body: args.containsKey('body')
                    ? args['body']?.toString()
                    : null,
                state: _stringArg(args, 'state'),
                labels: args.containsKey('labels')
                    ? _stringListArg(args, 'labels')
                    : null,
                assignees: args.containsKey('assignees')
                    ? _stringListArg(args, 'assignees')
                    : null,
              ),
            ),
          );
        case 'github_create_issue_comment':
          return _okText(
            await _json(
              _client.createIssueComment(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                issueNumber: _intArg(args, 'issue_number', requiredValue: true),
                body: _stringArg(args, 'body', requiredValue: true),
              ),
            ),
          );
        case 'github_create_pull_request':
          return _okText(
            await _json(
              _client.createPullRequest(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                title: _stringArg(args, 'title', requiredValue: true),
                head: _stringArg(args, 'head', requiredValue: true),
                base: _stringArg(args, 'base', requiredValue: true),
                body: _stringArg(args, 'body'),
                draft: _boolArg(args, 'draft'),
                maintainerCanModify: _boolArg(
                  args,
                  'maintainer_can_modify',
                  defaultValue: true,
                ),
              ),
            ),
          );
        case 'github_list_releases':
          return _okText(
            await _json(
              _client.listReleases(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                perPage: _intArg(args, 'per_page', defaultValue: 10),
                page: _intArg(args, 'page', defaultValue: 1),
              ),
            ),
          );
        case 'github_get_release':
          return _okText(
            await _json(
              _client.getRelease(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                releaseId: _intArg(args, 'release_id', requiredValue: true),
              ),
            ),
          );
        case 'github_create_release':
          return _okText(
            await _json(
              _client.createRelease(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                tagName: _stringArg(args, 'tag_name', requiredValue: true),
                targetCommitish: _stringArg(args, 'target_commitish'),
                name: _stringArg(args, 'name'),
                body: _stringArg(args, 'body'),
                draft: _boolArg(args, 'draft'),
                prerelease: _boolArg(args, 'prerelease'),
                generateReleaseNotes: _boolArg(args, 'generate_release_notes'),
              ),
            ),
          );
        case 'github_update_release':
          return _okText(
            await _json(
              _client.updateRelease(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                releaseId: _intArg(args, 'release_id', requiredValue: true),
                tagName: _stringArg(args, 'tag_name'),
                targetCommitish: _stringArg(args, 'target_commitish'),
                name: args.containsKey('name')
                    ? args['name']?.toString()
                    : null,
                body: args.containsKey('body')
                    ? args['body']?.toString()
                    : null,
                draft: args.containsKey('draft')
                    ? _boolArg(args, 'draft')
                    : null,
                prerelease: args.containsKey('prerelease')
                    ? _boolArg(args, 'prerelease')
                    : null,
              ),
            ),
          );
        case 'github_delete_release':
          return _okText(
            await _json(
              _client.deleteRelease(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                releaseId: _intArg(args, 'release_id', requiredValue: true),
                confirmReleaseId: _intArg(
                  args,
                  'confirm_release_id',
                  requiredValue: true,
                ),
              ),
            ),
          );
        case 'github_list_workflows':
          return _okText(
            await _json(
              _client.listWorkflows(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                perPage: _intArg(args, 'per_page', defaultValue: 10),
                page: _intArg(args, 'page', defaultValue: 1),
              ),
            ),
          );
        case 'github_list_workflow_runs':
          return _okText(
            await _json(
              _client.listWorkflowRuns(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                workflowId: _stringArg(args, 'workflow_id'),
                branch: _stringArg(args, 'branch'),
                status: _stringArg(args, 'status'),
                perPage: _intArg(args, 'per_page', defaultValue: 10),
                page: _intArg(args, 'page', defaultValue: 1),
              ),
            ),
          );
        case 'github_get_workflow_run':
          return _okText(
            await _json(
              _client.getWorkflowRun(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                runId: _intArg(args, 'run_id', requiredValue: true),
              ),
            ),
          );
        case 'github_list_workflow_run_jobs':
          return _okText(
            await _json(
              _client.listWorkflowRunJobs(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                runId: _intArg(args, 'run_id', requiredValue: true),
                perPage: _intArg(args, 'per_page', defaultValue: 10),
                page: _intArg(args, 'page', defaultValue: 1),
              ),
            ),
          );
        case 'github_get_workflow_run_logs':
          return _okText(
            await _json(
              _client.getWorkflowRunLogs(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                runId: _intArg(args, 'run_id', requiredValue: true),
                maxLength: _intArg(args, 'max_length', defaultValue: 12000),
                startIndex: _intArg(args, 'start_index', defaultValue: 0),
              ),
            ),
          );
        case 'github_dispatch_workflow':
          return _okText(
            await _json(
              _client.dispatchWorkflow(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                workflowId: _stringArg(
                  args,
                  'workflow_id',
                  requiredValue: true,
                ),
                ref: _stringArg(args, 'ref', requiredValue: true),
                inputs: _mapArg(args, 'inputs'),
              ),
            ),
          );
        case 'github_rerun_workflow_run':
          return _okText(
            await _json(
              _client.rerunWorkflowRun(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                runId: _intArg(args, 'run_id', requiredValue: true),
              ),
            ),
          );
        case 'github_cancel_workflow_run':
          return _okText(
            await _json(
              _client.cancelWorkflowRun(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                runId: _intArg(args, 'run_id', requiredValue: true),
              ),
            ),
          );
        case 'github_get_repo_public_key':
          return _okText(
            await _json(
              _client.getRepositoryPublicKey(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                kind: _stringArg(args, 'kind', defaultValue: 'actions'),
              ),
            ),
          );
        case 'github_put_repo_secret':
          return _okText(
            await _json(
              _client.putRepositorySecret(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                secretName: _stringArg(
                  args,
                  'secret_name',
                  requiredValue: true,
                ),
                encryptedValue: _stringArg(
                  args,
                  'encrypted_value',
                  requiredValue: true,
                ),
                keyId: _stringArg(args, 'key_id', requiredValue: true),
                kind: _stringArg(args, 'kind', defaultValue: 'actions'),
              ),
            ),
          );
        case 'github_delete_repo_secret':
          return _okText(
            await _json(
              _client.deleteRepositorySecret(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                secretName: _stringArg(
                  args,
                  'secret_name',
                  requiredValue: true,
                ),
                kind: _stringArg(args, 'kind', defaultValue: 'actions'),
                confirmSecretName: _stringArg(
                  args,
                  'confirm_secret_name',
                  requiredValue: true,
                ),
              ),
            ),
          );
        case 'github_list_repo_variables':
          return _okText(
            await _json(
              _client.listRepositoryVariables(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                perPage: _intArg(args, 'per_page', defaultValue: 10),
                page: _intArg(args, 'page', defaultValue: 1),
              ),
            ),
          );
        case 'github_create_or_update_repo_variable':
          return _okText(
            await _json(
              _client.createOrUpdateRepositoryVariable(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                name: _stringArg(args, 'name', requiredValue: true),
                value: _stringArg(args, 'value', requiredValue: true),
              ),
            ),
          );
        case 'github_delete_repo_variable':
          return _okText(
            await _json(
              _client.deleteRepositoryVariable(
                owner: _stringArg(args, 'owner', requiredValue: true),
                repo: _stringArg(args, 'repo', requiredValue: true),
                name: _stringArg(args, 'name', requiredValue: true),
                confirmVariableName: _stringArg(
                  args,
                  'confirm_variable_name',
                  requiredValue: true,
                ),
              ),
            ),
          );
        default:
          return _err('Tool not found: $name');
      }
    } catch (error) {
      return _err(error.toString());
    }
  }

  static Future<String> _json(Future<Map<String, dynamic>> result) async =>
      const JsonEncoder.withIndent('  ').convert(await result);

  static String _stringArg(
    Map<String, dynamic> args,
    String name, {
    bool requiredValue = false,
    String defaultValue = '',
  }) {
    final raw = args[name];
    final value = raw == null ? defaultValue.trim() : raw.toString().trim();
    if (requiredValue && value.isEmpty) {
      throw ArgumentError('$name is required');
    }
    return value;
  }

  static int _intArg(
    Map<String, dynamic> args,
    String name, {
    int defaultValue = 0,
    bool requiredValue = false,
  }) {
    final raw = args[name];
    if (raw == null) {
      if (requiredValue) throw ArgumentError('$name is required');
      return defaultValue;
    }
    if (raw is int) return raw;
    if (raw is num && raw.isFinite && raw.roundToDouble() == raw) {
      return raw.toInt();
    }
    final parsed = int.tryParse(raw.toString());
    if (parsed != null) return parsed;
    throw ArgumentError('$name must be an integer');
  }

  static int? _optionalPositiveIntArg(
    Map<String, dynamic> args,
    String name,
  ) {
    if (!args.containsKey(name)) return null;
    final raw = args[name];
    if (raw == null) return null;
    if (raw is String && raw.trim().isEmpty) return null;
    final value = _intArg(args, name);
    return value > 0 ? value : null;
  }

  static bool _boolArg(
    Map<String, dynamic> args,
    String name, {
    bool defaultValue = false,
  }) {
    final raw = args[name];
    if (raw == null) return defaultValue;
    if (raw is bool) return raw;
    final value = raw.toString().trim().toLowerCase();
    if (value == 'true' || value == '1' || value == 'yes') return true;
    if (value == 'false' || value == '0' || value == 'no') return false;
    throw ArgumentError('$name must be a boolean');
  }

  static List<String> _stringListArg(Map<String, dynamic> args, String name) {
    final raw = args[name];
    if (raw == null) return const <String>[];
    if (raw is List) {
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final text = raw.toString().trim();
    if (text.isEmpty) return const <String>[];
    return text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, dynamic> _mapArg(Map<String, dynamic> args, String name) {
    final raw = args[name];
    if (raw == null) return const <String, dynamic>{};
    if (raw is Map) return raw.cast<String, dynamic>();
    final text = raw.toString().trim();
    if (text.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(text);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw ArgumentError('$name must be an object');
  }

  Future<Map<String, dynamic>> _callLegacyAction(
    Map<String, dynamic> args,
    Map<String, String> actions,
  ) {
    final action = _stringArg(
      args,
      'action',
      requiredValue: true,
    ).toLowerCase().replaceAll('-', '_');
    final toolName = actions[action];
    if (toolName == null) {
      throw ArgumentError(
        'Unsupported action "$action". Supported actions: ${actions.keys.join(', ')}',
      );
    }
    final forwardedArgs = Map<String, dynamic>.from(args)..remove('action');
    return _callTool(toolName, forwardedArgs);
  }

  static Map<String, dynamic> _ok(dynamic id, {required dynamic result}) => {
    'jsonrpc': '2.0',
    if (id != null) 'id': id,
    'result': result,
  };

  static Map<String, dynamic> _error(
    dynamic id, {
    required int code,
    required String message,
  }) => {
    'jsonrpc': '2.0',
    if (id != null) 'id': id,
    'error': {'code': code, 'message': message},
  };

  static Map<String, dynamic> _noop() => {'jsonrpc': '2.0'};

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

  List<Map<String, dynamic>> _toolDefinitions() => _groupedToolDefinitions();

  List<Map<String, dynamic>> _groupedToolDefinitions() => [
    _tool(
      'github_get_viewer',
      '读取当前 GitHub Token 对应的登录用户，用于确认 Token 是否配置正确以及权限是否可用。',
      const <String, dynamic>{},
      const <String>[],
    ),
    _tool(
      'github_search',
      '搜索 GitHub 代码、仓库、Issue 或 Pull Request。刚写入文件后的验证不要用代码搜索，应使用读取文件、列目录、读取提交或比较引用。',
      {
        'action': _enumProperty('搜索类型。', [
          'code',
          'repositories',
          'issues',
          'pull_requests',
        ]),
        'query': _stringProperty(
          'GitHub 搜索语句，可包含 repo:、org:、user:、language:、path: 等限定符。',
        ),
        ..._searchPagingProperties(),
      },
      ['action', 'query'],
    ),
    _tool(
      'github_repository_read',
      '读取仓库信息、目录、分支、标签、提交、引用比较结果或文件内容。写入后的强一致校验建议使用本工具。',
      {
        'action': _enumProperty('仓库读取动作。', [
          'get',
          'list_directory',
          'list_branches',
          'list_tags',
          'list_commits',
          'get_commit',
          'compare_refs',
          'get_file',
        ]),
        ..._repoProperties(),
        'path': _stringProperty('文件或目录在仓库内的相对路径。'),
        'ref': _stringProperty('分支、标签或提交 SHA。'),
        'sha': _stringProperty('列提交时使用的分支名或提交 SHA。'),
        'base': _stringProperty('compare_refs 的基准引用。'),
        'head': _stringProperty('compare_refs 的目标引用。'),
        ..._searchPagingProperties(),
        ..._textPagingProperties(),
      },
      ['action', 'owner', 'repo'],
    ),
    _tool(
      'github_repository_write',
      '创建、更新、删除或 fork 仓库；创建/删除分支；创建、更新或删除仓库文件。空仓库创建分支时会先自动初始化 README。',
      {
        'action': _enumProperty('仓库写入动作。', [
          'create_repository',
          'update_repository',
          'delete_repository',
          'fork_repository',
          'create_branch',
          'create_or_update_file',
          'delete_file',
          'delete_branch',
        ]),
        ..._repoProperties(),
        'name': _stringProperty('仓库名或 fork 后的新仓库名。'),
        'description': _stringProperty('仓库描述。'),
        'private': _boolProperty('是否创建或设置为私有仓库。'),
        'org': _stringProperty('创建仓库时使用的组织名，留空则创建到当前用户。'),
        'organization': _stringProperty('fork 仓库时使用的目标组织名。'),
        'auto_init': _boolProperty('创建仓库时是否自动生成 README 初始化提交。'),
        'has_issues': _boolProperty('是否启用 Issues。'),
        'has_wiki': _boolProperty('是否启用 Wiki。'),
        'archived': _boolProperty('是否归档或取消归档仓库。'),
        'default_branch': _stringProperty('默认分支名。'),
        'confirm_repo_full_name': _stringProperty('删除仓库时必须精确等于 owner/repo。'),
        'default_branch_only': _boolProperty('fork 时是否只复制默认分支。'),
        'branch': _stringProperty('目标分支名。'),
        'from_branch': _stringProperty('创建分支时使用的来源分支。'),
        'from_sha': _stringProperty('创建分支时使用的来源提交 SHA，优先级高于 from_branch。'),
        'confirm_branch': _stringProperty('删除分支时必须精确等于 branch。'),
        'path': _stringProperty('仓库内文件相对路径。'),
        'content': _stringProperty('要写入的 UTF-8 文本内容。'),
        'message': _stringProperty('提交信息。'),
        'sha': _stringProperty('更新或删除文件时使用的当前文件 SHA。'),
      },
      ['action'],
    ),
    _tool(
      'github_issue_read',
      '读取 Issue 或 Pull Request 对话评论。',
      {
        'action': _enumProperty('Issue 读取动作。', ['get_comments']),
        ..._repoProperties(),
        'issue_number': _intProperty('Issue 或 Pull Request 编号。'),
        ..._searchPagingProperties(),
      },
      ['action', 'owner', 'repo', 'issue_number'],
    ),
    _tool(
      'github_issue_write',
      '创建或更新 Issue，或给 Issue / Pull Request 添加普通评论。',
      {
        'action': _enumProperty('Issue 写入动作。', ['create', 'update', 'comment']),
        ..._repoProperties(),
        'issue_number': _intProperty('更新或评论时使用的 Issue 编号。'),
        'title': _stringProperty('Issue 标题。'),
        'body': _stringProperty('Issue 正文或评论正文。'),
        'state': _enumProperty('Issue 状态。', ['open', 'closed']),
        'labels': _stringArrayProperty('标签列表。'),
        'assignees': _stringArrayProperty('指派用户列表。'),
      },
      ['action', 'owner', 'repo'],
    ),
    _tool(
      'github_pull_request_read',
      '读取 Pull Request 详情、diff、变更文件、Review 或 Review 评论。',
      {
        'action': _enumProperty('Pull Request 读取动作。', [
          'get',
          'diff',
          'list_files',
          'list_reviews',
          'list_review_comments',
        ]),
        ..._repoProperties(),
        'pull_number': _intProperty('Pull Request 编号。'),
        ..._searchPagingProperties(),
        ..._textPagingProperties(),
      },
      ['action', 'owner', 'repo', 'pull_number'],
    ),
    _tool(
      'github_pull_request_write',
      '创建、更新、Review、添加 Review 评论或合并 Pull Request。更新 PR 时只会发送 title、body、state、base、maintainer_can_modify 等合法字段。',
      {
        'action': _enumProperty('Pull Request 写入动作。', [
          'create',
          'update',
          'create_review',
          'create_review_comment',
          'merge',
        ]),
        ..._repoProperties(),
        'pull_number': _intProperty('Pull Request 编号。'),
        'title': _stringProperty('Pull Request 标题。'),
        'head': _stringProperty('创建 PR 时使用的来源分支。'),
        'base': _stringProperty('创建或更新 PR 时使用的目标分支。'),
        'body': _stringProperty('PR 正文、Review 正文或评论正文。'),
        'draft': _boolProperty('是否创建为 Draft PR。'),
        'maintainer_can_modify': _boolProperty('是否允许维护者修改来源分支。'),
        'state': _enumProperty('Pull Request 状态。', ['open', 'closed']),
        'event': _enumProperty('Review 事件。', [
          'COMMENT',
          'APPROVE',
          'REQUEST_CHANGES',
        ]),
        'commit_id': _stringProperty('新建 inline comment 时的目标提交 SHA；回复评论时不要传。'),
        'path': _stringProperty('新建 inline comment 时的文件路径；回复评论时不要传。'),
        'line': _intProperty('新建行评论时的目标行号；file-level comment 可不传。'),
        'side': _enumProperty('diff 侧。', ['LEFT', 'RIGHT']),
        'start_line': _intProperty('多行评论起始行号。'),
        'start_side': _enumProperty('多行评论起始 diff 侧。', ['LEFT', 'RIGHT']),
        'subject_type': _enumProperty('Review 评论类型。', ['line', 'file']),
        'in_reply_to': _intProperty(
          '要回复的已有 Review 评论 ID；回复路径只传 body 和 in_reply_to。',
        ),
        'commit_title': _stringProperty('合并提交标题。'),
        'commit_message': _stringProperty('合并提交正文。'),
        'merge_method': _enumProperty('合并方式。', ['merge', 'squash', 'rebase']),
        'expected_head_sha': _stringProperty('合并前期望的 PR head SHA，用于避免误合并。'),
      },
      ['action', 'owner', 'repo'],
    ),
    _tool(
      'github_release_read',
      '列出 Release 或按 ID 读取单个 Release。',
      {
        'action': _enumProperty('Release 读取动作。', ['list', 'get']),
        ..._repoProperties(),
        'release_id': _intProperty('Release ID。'),
        ..._searchPagingProperties(),
      },
      ['action', 'owner', 'repo'],
    ),
    _tool(
      'github_release_write',
      '创建、更新或删除 GitHub Release。',
      {
        'action': _enumProperty('Release 写入动作。', [
          'create',
          'update',
          'delete',
        ]),
        ..._repoProperties(),
        'release_id': _intProperty('Release ID。'),
        'confirm_release_id': _intProperty('删除 Release 时必须等于 release_id。'),
        'tag_name': _stringProperty('Release 标签名。'),
        'target_commitish': _stringProperty('目标提交、分支或标签。'),
        'name': _stringProperty('Release 名称。'),
        'body': _stringProperty('Release 正文。'),
        'draft': _boolProperty('是否为草稿。'),
        'prerelease': _boolProperty('是否为预发布。'),
        'generate_release_notes': _boolProperty(
          '是否让 GitHub 自动生成 Release Notes。',
        ),
      },
      ['action', 'owner', 'repo'],
    ),
    _tool(
      'github_actions_read',
      '读取 GitHub Actions 的 workflow、运行记录、任务或日志。',
      {
        'action': _enumProperty('Actions 读取动作。', [
          'list_workflows',
          'list_runs',
          'get_run',
          'list_jobs',
          'get_logs',
        ]),
        ..._repoProperties(),
        'workflow_id': _stringProperty('Workflow ID 或 workflow 文件名。'),
        'run_id': _intProperty('Workflow run ID。'),
        'branch': _stringProperty('分支过滤条件。'),
        'status': _stringProperty('运行状态过滤条件。'),
        ..._searchPagingProperties(),
        ..._textPagingProperties(),
      },
      ['action', 'owner', 'repo'],
    ),
    _tool(
      'github_actions_write',
      '触发、重新运行或取消 GitHub Actions workflow run。',
      {
        'action': _enumProperty('Actions 写入动作。', [
          'dispatch',
          'rerun',
          'cancel',
        ]),
        ..._repoProperties(),
        'workflow_id': _stringProperty('dispatch 时使用的 Workflow ID 或文件名。'),
        'ref': _stringProperty('dispatch 时使用的 Git 引用。'),
        'inputs': {'type': 'object', 'description': 'workflow_dispatch 输入参数。'},
        'run_id': _intProperty('重新运行或取消时使用的 workflow run ID。'),
      },
      ['action', 'owner', 'repo'],
    ),
    _tool(
      'github_secrets_read',
      '读取仓库 secrets 公钥，或列出仓库 Actions variables。',
      {
        'action': _enumProperty('Secrets/Variables 读取动作。', [
          'get_public_key',
          'list_variables',
        ]),
        ..._repoProperties(),
        'kind': _enumProperty('Secret 类型。', [
          'actions',
          'dependabot',
          'codespaces',
        ]),
        ..._searchPagingProperties(),
      },
      ['action', 'owner', 'repo'],
    ),
    _tool(
      'github_secrets_write',
      '创建/更新加密仓库 secret 或 Actions variable，或删除它们。变量名不能使用 GitHub 保留的 GITHUB_ 前缀。',
      {
        'action': _enumProperty('Secrets/Variables 写入动作。', [
          'put_secret',
          'delete_secret',
          'put_variable',
          'delete_variable',
        ]),
        ..._repoProperties(),
        'kind': _enumProperty('Secret 类型。', [
          'actions',
          'dependabot',
          'codespaces',
        ]),
        'secret_name': _stringProperty('Secret 名称。'),
        'encrypted_value': _stringProperty('用 GitHub 公钥加密后的 Base64 secret 值。'),
        'key_id': _stringProperty('GitHub 公钥 ID。'),
        'confirm_secret_name': _stringProperty('删除 secret 时必须等于 secret_name。'),
        'name': _stringProperty('Variable 名称，不能以 GITHUB_ 开头。'),
        'value': _stringProperty('Variable 值。'),
        'confirm_variable_name': _stringProperty('删除 variable 时必须等于 name。'),
      },
      ['action', 'owner', 'repo'],
    ),
  ];

  // ignore: unused_element
  List<Map<String, dynamic>> _legacyToolDefinitions() => [
    {
      'name': 'github_get_viewer',
      'description':
          '返回当前配置 Token 对应的 GitHub 登录用户。执行私有仓库操作前，可先用它验证 GitHub 访问权限。',
      'inputSchema': _emptySchema(),
    },
    {
      'name': 'github_search_code',
      'description':
          '使用 GitHub 代码搜索查找代码，支持 repo:、org:、user:、language:、path:、filename:、extension: 以及精确引号关键词。适合查找实现示例或代码引用；私有仓库需要已配置 Token 具备访问权限。',
      'inputSchema': _searchSchema(),
    },
    {
      'name': 'github_search_repositories',
      'description':
          '按关键词和 language:、topic:、stars:、pushed:、size:、user:、org: 等限定符搜索 GitHub 仓库，用于发现相关开源项目。',
      'inputSchema': _searchSchema(),
    },
    {
      'name': 'github_search_issues',
      'description':
          '搜索 GitHub Issue。若查询未指定 is:issue 或 is:pr，工具会自动加入 is:issue。支持 repo:、org:、author:、label:、state:、created:、updated: 和引号关键词。',
      'inputSchema': _searchSchema(),
    },
    {
      'name': 'github_search_pull_requests',
      'description':
          '搜索 GitHub Pull Request。若查询未指定 is:issue 或 is:pr，工具会自动加入 is:pr。支持 repo:、org:、author:、review:、state:、created:、updated: 和引号关键词。',
      'inputSchema': _searchSchema(),
    },
    {
      'name': 'github_get_repository',
      'description': '根据 owner 和 repo 名称读取 GitHub 仓库的精简元数据。',
      'inputSchema': _repoSchema(),
    },
    {
      'name': 'github_get_file',
      'description':
          '从 GitHub 仓库读取 UTF-8 文本文件。可在 github_search_code 后使用，或在用户指定仓库文件时使用。支持通过 ref 指定分支、标签或提交 SHA，并支持 start_index/max_length 分页。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          ..._repoProperties(),
          'path': {
            'type': 'string',
            'description': '仓库内相对文件路径，例如 lib/main.dart。',
          },
          'ref': {'type': 'string', 'description': '可选的分支、标签或提交 SHA。'},
          ..._textPagingProperties(),
        },
        'required': ['owner', 'repo', 'path'],
      },
    },
    {
      'name': 'github_get_issue_comments',
      'description':
          '读取指定 GitHub Issue 或 Pull Request 编号下的评论。需要讨论上下文时，可在 Issue/PR 搜索后使用。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          ..._repoProperties(),
          'issue_number': {
            'type': 'integer',
            'description': 'Issue 或 Pull Request 编号。',
          },
          ..._searchPagingProperties(),
        },
        'required': ['owner', 'repo', 'issue_number'],
      },
    },
    {
      'name': 'github_get_pr_diff',
      'description':
          '读取 GitHub Pull Request 的 diff。适合审查或总结变更，支持 start_index/max_length 分页。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          ..._repoProperties(),
          'pull_number': {'type': 'integer', 'description': 'Pull Request 编号。'},
          ..._textPagingProperties(),
        },
        'required': ['owner', 'repo', 'pull_number'],
      },
    },
    {
      'name': 'github_create_branch',
      'description':
          '创建 GitHub 分支。默认从仓库默认分支创建，也可通过 from_branch 或 from_sha 指定来源。需要 Token 具备 contents 写权限。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          ..._repoProperties(),
          'branch': {'type': 'string', 'description': '要创建的新分支名。'},
          'from_branch': {
            'type': 'string',
            'description': '可选，作为来源的已有分支名。未填时使用默认分支。',
          },
          'from_sha': {
            'type': 'string',
            'description': '可选，作为来源的提交 SHA。优先级高于 from_branch。',
          },
        },
        'required': ['owner', 'repo', 'branch'],
      },
    },
    {
      'name': 'github_create_or_update_file',
      'description':
          '在 GitHub 仓库创建或更新文本文件。更新已有文件时应先用 github_get_file 获取当前 sha，并传入 sha 防止覆盖冲突。建议在功能分支上操作。需要 contents 写权限。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          ..._repoProperties(),
          'path': {'type': 'string', 'description': '仓库内相对文件路径。'},
          'content': {'type': 'string', 'description': '要写入的 UTF-8 文本内容。'},
          'message': {'type': 'string', 'description': '提交信息。'},
          'branch': {'type': 'string', 'description': '可选，目标分支。'},
          'sha': {'type': 'string', 'description': '可选，更新已有文件时填写当前文件 SHA。'},
        },
        'required': ['owner', 'repo', 'path', 'content', 'message'],
      },
    },
    {
      'name': 'github_delete_file',
      'description':
          '删除 GitHub 仓库中的文件。必须提供当前文件 sha，建议先用 github_get_file 确认目标。需要 contents 写权限。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          ..._repoProperties(),
          'path': {'type': 'string', 'description': '仓库内相对文件路径。'},
          'sha': {'type': 'string', 'description': '当前文件 SHA。'},
          'message': {'type': 'string', 'description': '提交信息。'},
          'branch': {'type': 'string', 'description': '可选，目标分支。'},
        },
        'required': ['owner', 'repo', 'path', 'sha', 'message'],
      },
    },
    {
      'name': 'github_create_issue',
      'description': '创建 GitHub Issue。需要 issues 写权限。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          ..._repoProperties(),
          'title': {'type': 'string', 'description': 'Issue 标题。'},
          'body': {'type': 'string', 'description': 'Issue 正文。'},
          'labels': _stringArrayProperty('标签列表。'),
          'assignees': _stringArrayProperty('指派用户列表。'),
        },
        'required': ['owner', 'repo', 'title'],
      },
    },
    {
      'name': 'github_update_issue',
      'description':
          '更新 GitHub Issue 或关闭/重开 Issue。至少提供 title、body、state、labels、assignees 之一。需要 issues 写权限。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          ..._repoProperties(),
          'issue_number': {'type': 'integer', 'description': 'Issue 编号。'},
          'title': {'type': 'string', 'description': '新标题。'},
          'body': {'type': 'string', 'description': '新正文；传空字符串可清空正文。'},
          'state': {
            'type': 'string',
            'description': 'open 或 closed。',
            'enum': ['open', 'closed'],
          },
          'labels': _stringArrayProperty('替换后的标签列表。'),
          'assignees': _stringArrayProperty('替换后的指派用户列表。'),
        },
        'required': ['owner', 'repo', 'issue_number'],
      },
    },
    {
      'name': 'github_create_issue_comment',
      'description':
          '给 GitHub Issue 或 Pull Request 添加评论。Pull Request 评论区也走 issue_number。需要 issues 写权限。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          ..._repoProperties(),
          'issue_number': {'type': 'integer', 'description': 'Issue 或 PR 编号。'},
          'body': {'type': 'string', 'description': '评论正文。'},
        },
        'required': ['owner', 'repo', 'issue_number', 'body'],
      },
    },
    {
      'name': 'github_create_pull_request',
      'description':
          '创建 GitHub Pull Request。head 是源分支，base 是目标分支。需要 pull_requests 写权限。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          ..._repoProperties(),
          'title': {'type': 'string', 'description': 'PR 标题。'},
          'head': {'type': 'string', 'description': '源分支，例如 feature/foo。'},
          'base': {'type': 'string', 'description': '目标分支，例如 main。'},
          'body': {'type': 'string', 'description': 'PR 正文。'},
          'draft': {
            'type': 'boolean',
            'description': '是否创建为 Draft PR。',
            'default': false,
          },
          'maintainer_can_modify': {
            'type': 'boolean',
            'description': '是否允许维护者修改源分支。',
            'default': true,
          },
        },
        'required': ['owner', 'repo', 'title', 'head', 'base'],
      },
    },
  ];

  static Map<String, dynamic> _emptySchema() => {
    'type': 'object',
    'properties': <String, dynamic>{},
  };

  static Map<String, dynamic> _searchSchema() => {
    'type': 'object',
    'properties': {
      'query': {'type': 'string', 'description': 'GitHub 搜索查询，可包含任意支持的限定符。'},
      ..._searchPagingProperties(),
    },
    'required': ['query'],
  };

  static Map<String, dynamic> _repoSchema() => {
    'type': 'object',
    'properties': _repoProperties(),
    'required': ['owner', 'repo'],
  };

  static Map<String, dynamic> _tool(
    String name,
    String description,
    Map<String, dynamic> properties,
    List<String> required,
  ) => {
    'name': name,
    'description': description,
    'inputSchema': {
      'type': 'object',
      'properties': properties,
      'required': required,
    },
  };

  static Map<String, dynamic> _stringProperty(String description) => {
    'type': 'string',
    'description': description,
  };

  static Map<String, dynamic> _intProperty(String description) => {
    'type': 'integer',
    'description': description,
  };

  static Map<String, dynamic> _boolProperty(String description) => {
    'type': 'boolean',
    'description': description,
  };

  static Map<String, dynamic> _enumProperty(
    String description,
    List<String> values,
  ) => {'type': 'string', 'description': description, 'enum': values};

  static Map<String, dynamic> _repoProperties() => {
    'owner': {'type': 'string', 'description': '仓库所有者或组织名称。'},
    'repo': {'type': 'string', 'description': '不包含所有者前缀的仓库名称。'},
  };

  static Map<String, dynamic> _stringArrayProperty(String description) => {
    'type': 'array',
    'items': {'type': 'string'},
    'description': description,
    'default': <String>[],
  };

  static Map<String, dynamic> _searchPagingProperties() => {
    'per_page': {
      'type': 'integer',
      'description': '最多返回的结果数量，上限为 50。',
      'default': 10,
    },
    'page': {'type': 'integer', 'description': '从 1 开始的结果页码。', 'default': 1},
  };

  static Map<String, dynamic> _textPagingProperties() => {
    'max_length': {
      'type': 'integer',
      'description': '最多返回的字符数，上限为 50000。',
      'default': 12000,
    },
    'start_index': {
      'type': 'integer',
      'description': '继续读取被截断内容时的字符起始位置。',
      'default': 0,
    },
  };

  @override
  void close() {
    _closed = true;
    _client.close();
  }
}
