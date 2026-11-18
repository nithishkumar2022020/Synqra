import '../models/corpus.dart';

abstract class ICorpusRepository {
  Future<List<DocumentEntry>> getCorpusManifest();

  Future<DocumentEntry> uploadDocument({
    required String filename,
    required String documentsUrl,
    String? filePath,
    List<int>? bytes,
    String? apiKey,
    bool? semanticChunking,
  });

  Future<DocumentEntry> simulateUpload({
    required String filename,
    required int byteLength,
  });

  Future<Map<String, dynamic>> checkIngestionStatus({
    required String documentsUrl,
    required String jobId,
    String? apiKey,
  });

  Future<void> updateDocument(DocumentEntry entry);

  Future<void> deleteDocument(String documentId);
}
