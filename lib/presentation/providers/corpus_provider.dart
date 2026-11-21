import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/cloudwatch_service.dart';
import '../../domain/models/corpus.dart';
import '../../domain/repositories/i_corpus_repository.dart';

class CorpusProvider extends ChangeNotifier {
  static const _kSemanticChunkingPrefKey = 'rag_pref_semantic_chunking';

  final ICorpusRepository _repository;
  final CloudWatchService? _cloudWatchService;
  List<DocumentEntry> _documents = [];
  final Set<String> _selectedDocumentIds = {};
  bool _isLoading = false;
  bool _isUploading = false;
  bool _useSemanticChunking = true;
  String? _error;

  CorpusProvider({
    required ICorpusRepository repository,
    CloudWatchService? cloudWatchService,
  })  : _repository = repository,
        _cloudWatchService = cloudWatchService {
    loadManifest();
  }

  List<DocumentEntry> get documents => List.unmodifiable(_documents);
  Set<String> get selectedDocumentIds => Set.unmodifiable(_selectedDocumentIds);
  List<DocumentEntry> get selectedDocuments => _documents
      .where((d) => _selectedDocumentIds.contains(d.id))
      .toList(growable: false);
  bool isSelected(String documentId) =>
      _selectedDocumentIds.contains(documentId);
  bool get hasSelection => _selectedDocumentIds.isNotEmpty;
  bool get isLoading => _isLoading;
  bool get isUploading => _isUploading;
  bool get useSemanticChunking => _useSemanticChunking;
  String? get error => _error;

  Future<void> setSemanticChunking(bool value) async {
    if (_useSemanticChunking == value) return;
    _useSemanticChunking = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSemanticChunkingPrefKey, value);
    } catch (_) {}
  }

  void toggleSemanticChunking() {
    setSemanticChunking(!_useSemanticChunking);
  }

  void toggleSelection(String documentId) {
    if (_selectedDocumentIds.contains(documentId)) {
      _selectedDocumentIds.remove(documentId);
    } else {
      _selectedDocumentIds.add(documentId);
    }
    notifyListeners();
  }

  void setSelected(String documentId, bool selected) {
    final changed =
        selected
            ? _selectedDocumentIds.add(documentId)
            : _selectedDocumentIds.remove(documentId);
    if (changed) notifyListeners();
  }

  void applyDragRangeSelection({
    required int anchorIndex,
    required int targetIndex,
    required Set<String> baseSelection,
    bool selectRange = true,
  }) {
    if (_documents.isEmpty) return;
    final start = (anchorIndex < targetIndex ? anchorIndex : targetIndex).clamp(
      0,
      _documents.length - 1,
    );
    final end = (anchorIndex > targetIndex ? anchorIndex : targetIndex).clamp(
      0,
      _documents.length - 1,
    );

    final next = <String>{...baseSelection};
    for (var i = start; i <= end; i++) {
      final id = _documents[i].id;
      if (selectRange) {
        next.add(id);
      } else {
        next.remove(id);
      }
    }

    if (next.length == _selectedDocumentIds.length &&
        next.containsAll(_selectedDocumentIds)) {
      return;
    }
    _selectedDocumentIds
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void selectAll() {
    final allIds = _documents.map((d) => d.id).toSet();
    if (_selectedDocumentIds.length == allIds.length &&
        _selectedDocumentIds.containsAll(allIds)) {
      return;
    }
    _selectedDocumentIds
      ..clear()
      ..addAll(allIds);
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedDocumentIds.isEmpty) return;
    _selectedDocumentIds.clear();
    notifyListeners();
  }

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  static String resolveDocumentsUrl(String questionEndpoint) {
    final trimmed = questionEndpoint.trim();
    if (trimmed.isEmpty) return 'http://localhost:8000/documents';
    try {
      final uri = Uri.parse(trimmed);
      if (uri.hasScheme && uri.host.isNotEmpty) {
        return Uri(
          scheme: uri.scheme,
          userInfo: uri.userInfo.isNotEmpty ? uri.userInfo : null,
          host: uri.host,
          port: uri.hasPort ? uri.port : null,
          path: '/documents',
        ).toString();
      }
    } catch (_) {}
    return 'http://localhost:8000/documents';
  }

  Future<void> loadManifest() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_kSemanticChunkingPrefKey)) {
        _useSemanticChunking = prefs.getBool(_kSemanticChunkingPrefKey) ?? true;
      }
      _documents = await _repository.getCorpusManifest();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  final Map<String, bool> _activePollers = {};

  Future<void> _pollIngestionJob({
    required String jobId,
    required String documentId,
    required String documentsUrl,
    String? apiKey,
    int maxAttempts = 60,
    Duration interval = const Duration(milliseconds: 1500),
  }) async {
    if (_activePollers[jobId] == true) return;
    _activePollers[jobId] = true;

    int attempts = 0;
    try {
      while (attempts < maxAttempts && _activePollers[jobId] == true) {
        await Future.delayed(interval);
        attempts++;

        try {
          final res = await _repository.checkIngestionStatus(
            documentsUrl: documentsUrl,
            jobId: jobId,
            apiKey: apiKey,
          );

          final rawStatus = res['status']?.toString().toLowerCase();
          final chunks =
              res['chunks'] is int
                  ? res['chunks'] as int
                  : int.tryParse(res['chunks']?.toString() ?? '');

          final targetIndex = _documents.indexWhere(
            (d) => d.id == documentId || d.jobId == jobId,
          );

          if (targetIndex != -1) {
            final existing = _documents[targetIndex];

            if (rawStatus == 'completed') {
              final updated = existing.copyWith(
                status: IngestionStatus.indexed,
                indexingProgress: 1.0,
                chunkCount: chunks ?? existing.chunkCount,
                updatedAt: DateTime.now(),
              );
              _documents[targetIndex] = updated;
              await _repository.updateDocument(updated);
              _cloudWatchService?.logIngest(
                filename: existing.filename,
                chunkCount: updated.chunkCount,
                strategy: _useSemanticChunking ? 'SEMANTIC' : 'FIXED',
                isSuccess: true,
              );
              notifyListeners();
              break;
            } else if (rawStatus == 'failed') {
              final detail =
                  res['detail']?.toString() ?? 'Ingestion failed on backend';
              final updated = existing.copyWith(
                status: IngestionStatus.failed,
                indexingProgress: 0.0,
                updatedAt: DateTime.now(),
              );
              _documents[targetIndex] = updated;
              _error = detail;
              await _repository.updateDocument(updated);
              _cloudWatchService?.logIngest(
                filename: existing.filename,
                chunkCount: 0,
                strategy: _useSemanticChunking ? 'SEMANTIC' : 'FIXED',
                isSuccess: false,
                error: detail,
              );
              notifyListeners();
              break;
            } else if (rawStatus == 'processing') {
              final updated = existing.copyWith(
                status: IngestionStatus.indexing,
                indexingProgress: 0.65,
              );
              _documents[targetIndex] = updated;
              notifyListeners();
            } else {
              // queued / pending
              final updated = existing.copyWith(
                status: IngestionStatus.indexing,
                indexingProgress: 0.25,
              );
              _documents[targetIndex] = updated;
              notifyListeners();
            }
          }
        } catch (e) {
          if (attempts >= maxAttempts) {
            final targetIndex = _documents.indexWhere(
              (d) => d.id == documentId || d.jobId == jobId,
            );
            if (targetIndex != -1) {
              final existing = _documents[targetIndex];
              final updated = existing.copyWith(
                status: IngestionStatus.failed,
                indexingProgress: 0.0,
              );
              _documents[targetIndex] = updated;
              _error = 'Ingestion polling timed out: $e';
              await _repository.updateDocument(updated);
              notifyListeners();
            }
          }
        }
      }
    } finally {
      _activePollers.remove(jobId);
    }
  }

  void resumePendingJobs(String endpointUrl, {String? apiKey}) {
    final docsUrl = resolveDocumentsUrl(endpointUrl);
    for (final doc in _documents) {
      if (doc.status == IngestionStatus.indexing && doc.jobId != null) {
        _pollIngestionJob(
          jobId: doc.jobId!,
          documentId: doc.id,
          documentsUrl: docsUrl,
          apiKey: apiKey,
        );
      }
    }
  }

  Future<DocumentEntry?> uploadPdf({
    required String filename,
    required String endpointUrl,
    String? filePath,
    List<int>? bytes,
    String? apiKey,
    bool useOfflineSimulation = false,
    bool? semanticChunking,
  }) async {
    _isUploading = true;
    _error = null;
    notifyListeners();

    try {
      final DocumentEntry doc;
      if (useOfflineSimulation) {
        doc = await _repository.simulateUpload(
          filename: filename,
          byteLength: bytes?.length ?? 1850400,
        );
      } else {
        final documentsUrl = resolveDocumentsUrl(endpointUrl);
        doc = await _repository.uploadDocument(
          filename: filename,
          documentsUrl: documentsUrl,
          filePath: filePath,
          bytes: bytes,
          apiKey: apiKey,
          semanticChunking: semanticChunking ?? _useSemanticChunking,
        );
      }
      _documents = [doc, ..._documents.where((d) => d.id != doc.id)];
      _cloudWatchService?.logIngest(
        filename: filename,
        chunkCount: doc.chunkCount,
        strategy:
            (semanticChunking ?? _useSemanticChunking) ? 'SEMANTIC' : 'FIXED',
        isSuccess: doc.status != IngestionStatus.failed,
      );
      notifyListeners();

      if (doc.jobId != null && doc.status == IngestionStatus.indexing) {
        _pollIngestionJob(
          jobId: doc.jobId!,
          documentId: doc.id,
          documentsUrl: resolveDocumentsUrl(endpointUrl),
          apiKey: apiKey,
        );
      }
      return doc;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _cloudWatchService?.logIngest(
        filename: filename,
        chunkCount: 0,
        strategy:
            (semanticChunking ?? _useSemanticChunking) ? 'SEMANTIC' : 'FIXED',
        isSuccess: false,
        error: _error,
      );
      return null;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  Future<void> simulateUploadDocument(String filename, int bytes) async {
    try {
      final doc = await _repository.simulateUpload(
        filename: filename,
        byteLength: bytes,
      );
      _documents = [doc, ..._documents];
      notifyListeners();
    } catch (e) {
      _error = 'Upload failed: $e';
      notifyListeners();
    }
  }

  Future<void> removeDocument(String id) async {
    try {
      await _repository.deleteDocument(id);
      _documents = _documents.where((d) => d.id != id).toList();
      _selectedDocumentIds.remove(id);
      notifyListeners();
    } catch (e) {
      _error = 'Delete failed: $e';
      notifyListeners();
    }
  }
}
