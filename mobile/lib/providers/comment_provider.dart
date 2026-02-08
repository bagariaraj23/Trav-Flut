import 'package:flutter/foundation.dart';
import 'package:tripthread/models/comment.dart';
import 'package:tripthread/services/comment_service.dart';
import 'package:tripthread/utils/error_handler.dart';
import 'package:tripthread/utils/error_handler.dart' as errors;

class CommentProvider extends ChangeNotifier {
  final CommentService _commentService;

  CommentProvider({required CommentService commentService})
    : _commentService = commentService;

  final Map<String, List<Comment>> _entityComments = {};
  final Map<String, List<Comment>> _commentReplies = {};
  final Map<String, int> _currentPage = {};
  final Map<String, bool> _hasMore = {};
  final Map<String, bool> _isLoading = {};
  final Map<String, bool> _isLoadingReplies =
      {}; // Separate loading state for replies
  final Map<String, bool> _isCreating = {};
  final Map<String, bool> _isUpdating = {};
  final Map<String, bool> _isDeleting = {};
  String? _error;

  List<Comment> getCommentsList(String entityKey) =>
      _entityComments[entityKey] ?? [];
  List<Comment> getRepliesList(String commentId) =>
      _commentReplies[commentId] ?? [];
  int getCurrentPage(String entityKey) => _currentPage[entityKey] ?? 1;
  bool hasMore(String entityKey) => _hasMore[entityKey] ?? false;
  bool isLoading(String entityKey) => _isLoading[entityKey] ?? false;
  bool isCreating(String entityKey) => _isCreating[entityKey] ?? false;
  bool isUpdating(String commentId) => _isUpdating[commentId] ?? false;
  bool isDeleting(String commentId) => _isDeleting[commentId] ?? false;
  String? get error => _error;

  String _getEntityKey(String entityType, String entityId) {
    return '$entityType:$entityId';
  }

  /// [refresh] when true, refetches from page 1 so like counts and list are
  /// up to date for other users' likes/unlikes (e.g. when opening the sheet).
  Future<void> getComments(
    String entityType,
    String entityId, {
    bool refresh = false,
  }) async {
    final entityKey = _getEntityKey(entityType, entityId);
    if (refresh) {
      _currentPage[entityKey] = 1;
    }
    final page = _currentPage[entityKey] ?? 1;

    if (_isLoading[entityKey] == true) {
      return;
    }

    if (page > 1 && !(_hasMore[entityKey] ?? false)) {
      return;
    }

    _isLoading[entityKey] = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _commentService.getComments(
        entityType,
        entityId,
        page,
      );

      if (page == 1) {
        _entityComments[entityKey] = response.data;
      } else {
        _entityComments[entityKey] = [
          ...(_entityComments[entityKey] ?? []),
          ...response.data,
        ];
      }

      _hasMore[entityKey] = response.pagination.totalPages > page;
      _currentPage[entityKey] = page + 1;
      _isLoading[entityKey] = false;
      notifyListeners();
    } catch (e) {
      _isLoading[entityKey] = false;
      _error = ErrorHandler.handleError(e).message;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> createComment(
    String entityType,
    String entityId,
    String text,
    String? parentId,
  ) async {
    final entityKey = _getEntityKey(entityType, entityId);

    if (_isCreating[entityKey] == true) {
      return;
    }

    _isCreating[entityKey] = true;
    _error = null;
    notifyListeners();

    final tempComment = Comment(
      id: 'temp-${DateTime.now().millisecondsSinceEpoch}',
      userId: '',
      entityType: entityType,
      entityId: entityId,
      contentText: text,
      parentCommentId: parentId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    if (parentId == null) {
      _entityComments[entityKey] = [
        tempComment,
        ...(_entityComments[entityKey] ?? []),
      ];
    } else {
      _commentReplies[parentId] = [
        tempComment,
        ...(_commentReplies[parentId] ?? []),
      ];
    }
    notifyListeners();

    try {
      final comment = await _commentService.createComment(
        entityType,
        entityId,
        text,
        parentId,
      );

      if (parentId == null) {
        final index =
            _entityComments[entityKey]?.indexWhere(
              (c) => c.id == tempComment.id,
            ) ??
            -1;
        if (index >= 0) {
          _entityComments[entityKey]![index] = comment;
        } else {
          _entityComments[entityKey] = [
            comment,
            ...(_entityComments[entityKey] ?? []),
          ];
        }
      } else {
        final index =
            _commentReplies[parentId]?.indexWhere(
              (c) => c.id == tempComment.id,
            ) ??
            -1;
        if (index >= 0) {
          _commentReplies[parentId]![index] = comment;
        } else {
          _commentReplies[parentId] = [
            comment,
            ...(_commentReplies[parentId] ?? []),
          ];
        }
      }

      _isCreating[entityKey] = false;
      notifyListeners();
    } catch (e) {
      if (parentId == null) {
        _entityComments[entityKey]?.removeWhere((c) => c.id == tempComment.id);
      } else {
        _commentReplies[parentId]?.removeWhere((c) => c.id == tempComment.id);
      }
      _isCreating[entityKey] = false;
      _error = ErrorHandler.handleError(e).message;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateComment(String commentId, String newText) async {
    if (_isUpdating[commentId] == true) {
      return;
    }

    Comment? originalComment;
    String? entityKey;
    String? replyKey;

    for (final entry in _entityComments.entries) {
      final index = entry.value.indexWhere((c) => c.id == commentId);
      if (index >= 0) {
        originalComment = entry.value[index];
        entityKey = entry.key;
        _entityComments[entityKey]![index] = originalComment.copyWith(
          contentText: newText,
        );
        break;
      }
    }

    if (originalComment == null) {
      for (final entry in _commentReplies.entries) {
        final index = entry.value.indexWhere((c) => c.id == commentId);
        if (index >= 0) {
          originalComment = entry.value[index];
          replyKey = entry.key;
          _commentReplies[replyKey]![index] = originalComment.copyWith(
            contentText: newText,
          );
          break;
        }
      }
    }

    if (originalComment == null) {
      throw errors.AppException('Comment not found');
    }

    _isUpdating[commentId] = true;
    _error = null;
    notifyListeners();

    try {
      final updatedComment = await _commentService.updateComment(
        commentId,
        newText,
      );

      if (entityKey != null) {
        final index =
            _entityComments[entityKey]?.indexWhere((c) => c.id == commentId) ??
            -1;
        if (index >= 0) {
          _entityComments[entityKey]![index] = updatedComment;
        }
      } else if (replyKey != null) {
        final index =
            _commentReplies[replyKey]?.indexWhere((c) => c.id == commentId) ??
            -1;
        if (index >= 0) {
          _commentReplies[replyKey]![index] = updatedComment;
        }
      }

      _isUpdating[commentId] = false;
      notifyListeners();
    } catch (e) {
      if (entityKey != null) {
        final index =
            _entityComments[entityKey]?.indexWhere((c) => c.id == commentId) ??
            -1;
        if (index >= 0) {
          _entityComments[entityKey]![index] = originalComment;
        }
      } else if (replyKey != null) {
        final index =
            _commentReplies[replyKey]?.indexWhere((c) => c.id == commentId) ??
            -1;
        if (index >= 0) {
          _commentReplies[replyKey]![index] = originalComment;
        }
      }
      _isUpdating[commentId] = false;
      _error = ErrorHandler.handleError(e).message;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteComment(String commentId) async {
    if (_isDeleting[commentId] == true) {
      return;
    }

    Comment? deletedComment;
    String? entityKey;
    String? replyKey;

    for (final entry in _entityComments.entries) {
      final index = entry.value.indexWhere((c) => c.id == commentId);
      if (index >= 0) {
        deletedComment = entry.value[index];
        entityKey = entry.key;
        _entityComments[entityKey]!.removeAt(index);
        _commentReplies.remove(commentId);
        break;
      }
    }

    if (deletedComment == null) {
      for (final entry in _commentReplies.entries) {
        final index = entry.value.indexWhere((c) => c.id == commentId);
        if (index >= 0) {
          deletedComment = entry.value[index];
          replyKey = entry.key;
          _commentReplies[replyKey]!.removeAt(index);
          _decrementParentReplyCount(replyKey);
          break;
        }
      }
    }

    if (deletedComment == null) {
      throw errors.AppException('Comment not found');
    }

    _isDeleting[commentId] = true;
    _error = null;
    notifyListeners();

    try {
      await _commentService.deleteComment(commentId);
      _isDeleting[commentId] = false;
      notifyListeners();
    } catch (e) {
      if (entityKey != null) {
        _entityComments[entityKey] = [
          deletedComment,
          ...(_entityComments[entityKey] ?? []),
        ];
      } else if (replyKey != null) {
        _commentReplies[replyKey] = [
          deletedComment,
          ...(_commentReplies[replyKey] ?? []),
        ];
        _incrementParentReplyCount(replyKey);
      }
      _isDeleting[commentId] = false;
      _error = ErrorHandler.handleError(e).message;
      notifyListeners();
      rethrow;
    }
  }

  void _decrementParentReplyCount(String parentCommentId) {
    for (final entry in _entityComments.entries) {
      final index = entry.value.indexWhere((c) => c.id == parentCommentId);
      if (index >= 0) {
        final parent = entry.value[index];
        final newCount = (parent.replyCount ?? 1) - 1;
        _entityComments[entry.key]![index] = parent.copyWith(
          replyCount: newCount >= 0 ? newCount : 0,
        );
        break;
      }
    }
  }

  void _incrementParentReplyCount(String parentCommentId) {
    for (final entry in _entityComments.entries) {
      final index = entry.value.indexWhere((c) => c.id == parentCommentId);
      if (index >= 0) {
        final parent = entry.value[index];
        _entityComments[entry.key]![index] = parent.copyWith(
          replyCount: (parent.replyCount ?? 0) + 1,
        );
        break;
      }
    }
  }

  Future<void> getReplies(String commentId) async {
    if (_isLoadingReplies[commentId] == true) {
      return;
    }

    final page = 1;

    _isLoadingReplies[commentId] = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _commentService.getReplies(commentId, page);
      _commentReplies[commentId] = response.data;
      _isLoadingReplies[commentId] = false;
      notifyListeners();
    } catch (e) {
      _isLoadingReplies[commentId] = false;
      _error = ErrorHandler.handleError(e).message;
      notifyListeners();
      rethrow;
    }
  }

  bool isLoadingReplies(String commentId) =>
      _isLoadingReplies[commentId] ?? false;

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
