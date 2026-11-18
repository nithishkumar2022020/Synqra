import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/corpus.dart';
import '../../domain/repositories/i_corpus_repository.dart';

class CorpusRepository implements ICorpusRepository {
  static const _kIngestedManifestKey = 'rag_ingested_corpus_manifest_v1';

  final http.Client? _injectedClient;
  List<DocumentEntry> _documents = [];
  bool _loaded = false;

  CorpusRepository({http.Client? client}) : _injectedClient = client;

  @override
  Future<List<DocumentEntry>> getCorpusManifest() async {
    if (!_loaded) {
      await _loadFromPrefs();
      _loaded = true;
    }
    return List.unmodifiable(_documents);
  }

  static bool _isValidApiKey(String? key) {
    if (key == null) return false;
    final trimmed = key.trim();
    if (trimmed.isEmpty) return false;
    // Block masked/placeholder keys like '******' or '••••••••'
    if (RegExp(r'^[\*•\s]+$').hasMatch(trimmed)) return false;
    return true;
  }

  @override
  Future<DocumentEntry> uploadDocument({
    required String filename,
    required String documentsUrl,
    String? filePath,
    List<int>? bytes,
    String? apiKey,
    bool? semanticChunking,
  }) async {
    final targetUrl = documentsUrl.trim();
    if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://')) {
      throw Exception('Invalid documents URL: "$targetUrl"');
    }

    final request = http.MultipartRequest('POST', Uri.parse(targetUrl));
    if (_isValidApiKey(apiKey)) {
      request.headers['Authorization'] = 'Bearer ${apiKey!.trim()}';
    }

    if (semanticChunking != null) {
      request.fields['semantic_chunking'] = semanticChunking ? 'true' : 'false';
    }

    if (bytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    } else if (filePath != null && filePath.isNotEmpty) {
      request.files.add(
        await http.MultipartFile.fromPath('file', filePath, filename: filename),
      );
    } else {
      throw ArgumentError('No file bytes or path available for "$filename".');
    }

    final client = _injectedClient ?? http.Client();
    try {
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 60));
      final respBytes = await streamed.stream.toBytes();
      final bodyStr = utf8.decode(respBytes, allowMalformed: true);

      if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
        final decoded = jsonDecode(bodyStr);
        if (decoded is! Map<String, dynamic>) {
          throw Exception('Unexpected JSON response from $targetUrl');
        }

        final docId =
            decoded['document_id']?.toString() ??
            decoded['id']?.toString() ??
            'doc_${DateTime.now().millisecondsSinceEpoch}';
        final respFilename = decoded['filename']?.toString() ?? filename;
        final rawStatus = decoded['status']?.toString().toLowerCase();
        final jobId =
            decoded['job_id']?.toString() ?? decoded['jobId']?.toString();

        final bool isAsync =
            streamed.statusCode == 202 ||
            rawStatus == 'queued' ||
            rawStatus == 'processing' ||
            jobId != null;

        final IngestionStatus status;
        final double progress;
        if (isAsync && rawStatus != 'completed' && rawStatus != 'indexed') {
          status = IngestionStatus.indexing;
          progress = rawStatus == 'processing' ? 0.5 : 0.15;
        } else {
          status = IngestionStatus.indexed;
          progress = 1.0;
        }

        final chunks =
            decoded['chunks'] is int
                ? decoded['chunks'] as int
                : int.tryParse(decoded['chunks']?.toString() ?? '0') ?? 0;

        final entry = DocumentEntry(
          id: docId,
          title: DocumentEntry.titleFromFilename(respFilename),
          filename: respFilename,
          chunkCount: chunks,
          sizeBytes: bytes?.length ?? 0,
          updatedAt: DateTime.now(),
          status: status,
          indexingProgress: progress,
          jobId: jobId,
        );

        _documents = [entry, ..._documents.where((d) => d.id != entry.id)];
        await _saveToPrefs();
        return entry;
      }

      String detail = bodyStr;
      try {
        final errJson = jsonDecode(bodyStr);
        if (errJson is Map && errJson['detail'] != null) {
          detail = errJson['detail'].toString();
        }
      } catch (_) {}

      throw Exception(
        'HTTP ${streamed.statusCode}: ${detail.isNotEmpty ? detail : 'Upload rejected'}',
      );
    } finally {
      if (_injectedClient == null) {
        client.close();
      }
    }
  }

  @override
  Future<Map<String, dynamic>> checkIngestionStatus({
    required String documentsUrl,
    required String jobId,
    String? apiKey,
  }) async {
    final cleanDocUrl = documentsUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final targetUrl = '$cleanDocUrl/$jobId';
    if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://')) {
      throw Exception('Invalid documents URL: "$targetUrl"');
    }

    final request = http.Request('GET', Uri.parse(targetUrl));
    if (_isValidApiKey(apiKey)) {
      request.headers['Authorization'] = 'Bearer ${apiKey!.trim()}';
    }
    request.headers['Accept'] = 'application/json';

    final client = _injectedClient ?? http.Client();
    try {
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      final respBytes = await streamed.stream.toBytes();
      final bodyStr = utf8.decode(respBytes, allowMalformed: true);

      if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
        final decoded = jsonDecode(bodyStr);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        throw Exception('Unexpected response format from $targetUrl');
      }

      String detail = bodyStr;
      try {
        final errJson = jsonDecode(bodyStr);
        if (errJson is Map && errJson['detail'] != null) {
          detail = errJson['detail'].toString();
        }
      } catch (_) {}

      throw Exception(
        'HTTP ${streamed.statusCode}: ${detail.isNotEmpty ? detail : 'Status check failed'}',
      );
    } finally {
      if (_injectedClient == null) {
        client.close();
      }
    }
  }

  @override
  Future<void> updateDocument(DocumentEntry entry) async {
    final idx = _documents.indexWhere(
      (d) =>
          d.id == entry.id || (entry.jobId != null && d.jobId == entry.jobId),
    );
    if (idx != -1) {
      _documents[idx] = entry;
    } else {
      _documents.insert(0, entry);
    }
    await _saveToPrefs();
  }

  @override
  Future<DocumentEntry> simulateUpload({
    required String filename,
    required int byteLength,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final newDoc = DocumentEntry(
      id: 'sim_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999)}',
      title: DocumentEntry.titleFromFilename(filename),
      filename: filename,
      chunkCount: (byteLength / 3500).clamp(10, 400).round(),
      sizeBytes: byteLength,
      updatedAt: DateTime.now(),
      status: IngestionStatus.indexed,
      indexingProgress: 1.0,
    );
    _documents = [newDoc, ..._documents];
    await _saveToPrefs();
    return newDoc;
  }

  @override
  Future<void> deleteDocument(String documentId) async {
    _documents.removeWhere((doc) => doc.id == documentId);
    await _saveToPrefs();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kIngestedManifestKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _documents =
            decoded
                .whereType<Map<String, dynamic>>()
                .map(DocumentEntry.fromJson)
                .toList();
      }
    } catch (_) {}
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_documents.map((d) => d.toJson()).toList());
      await prefs.setString(_kIngestedManifestKey, encoded);
    } catch (_) {}
  }
}
