import 'dart:math';
import '../../domain/models/corpus.dart';
import '../../domain/repositories/i_corpus_repository.dart';

class MockCorpusRepository implements ICorpusRepository {
  final List<DocumentEntry> _documents = [
    DocumentEntry(
      id: 'doc_neural_ir_01',
      title: 'Neural IR Foundations',
      filename: 'foundations_neural_ir.pdf',
      chunkCount: 142,
      sizeBytes: 2450890,
      updatedAt: DateTime.now().subtract(const Duration(hours: 3)),
      status: IngestionStatus.indexed,
      indexingProgress: 1.0,
    ),
    DocumentEntry(
      id: 'doc_hierarchical_rerank_02',
      title: 'Hierarchical Reranking in RAG',
      filename: 'hierarchical_rerank_prod.pdf',
      chunkCount: 88,
      sizeBytes: 1540120,
      updatedAt: DateTime.now().subtract(const Duration(hours: 14)),
      status: IngestionStatus.indexed,
      indexingProgress: 1.0,
    ),
    DocumentEntry(
      id: 'doc_llm_context_03',
      title: 'LLM Context Compression',
      filename: 'context_compress_paper.md',
      chunkCount: 64,
      sizeBytes: 890430,
      updatedAt: DateTime.now().subtract(const Duration(days: 1)),
      status: IngestionStatus.indexed,
      indexingProgress: 1.0,
    ),
    DocumentEntry(
      id: 'doc_vector_index_04',
      title: 'HNSW Graph Quantization',
      filename: 'hnsw_quant_arch.pdf',
      chunkCount: 210,
      sizeBytes: 4210000,
      updatedAt: DateTime.now().subtract(const Duration(minutes: 25)),
      status: IngestionStatus.indexing,
      indexingProgress: 0.68,
    ),
  ];

  @override
  Future<List<DocumentEntry>> getCorpusManifest() async {
    await Future.delayed(const Duration(milliseconds: 120));
    return List.unmodifiable(_documents);
  }

  @override
  Future<DocumentEntry> uploadDocument({
    required String filename,
    required String documentsUrl,
    String? filePath,
    List<int>? bytes,
    String? apiKey,
    bool? semanticChunking,
  }) {
    return simulateUpload(
      filename: filename,
      byteLength: bytes?.length ?? 250000,
    );
  }

  @override
  Future<DocumentEntry> simulateUpload({
    required String filename,
    required int byteLength,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));

    final newDoc = DocumentEntry(
      id: 'doc_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999)}',
      title: filename
          .replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '')
          .replaceAll('_', ' '),
      filename: filename,
      chunkCount: (byteLength / 3500).clamp(10, 400).round(),
      sizeBytes: byteLength,
      updatedAt: DateTime.now(),
      status: IngestionStatus.indexed,
      indexingProgress: 1.0,
    );

    _documents.insert(0, newDoc);
    return newDoc;
  }

  @override
  Future<Map<String, dynamic>> checkIngestionStatus({
    required String documentsUrl,
    required String jobId,
    String? apiKey,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return {
      'job_id': jobId,
      'document_id': 'doc_$jobId',
      'filename': 'mock_doc.pdf',
      'status': 'completed',
      'chunks': 12,
    };
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
  }

  @override
  Future<void> deleteDocument(String documentId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    _documents.removeWhere((doc) => doc.id == documentId);
  }
}
