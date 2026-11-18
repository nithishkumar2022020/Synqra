enum IngestionStatus { indexed, indexing, failed, pending }

class DocumentEntry {
  final String id;
  final String title;
  final String filename;
  final int chunkCount;
  final int sizeBytes;
  final DateTime updatedAt;
  final IngestionStatus status;
  final double indexingProgress; // 0.0 to 1.0
  final String? jobId;

  const DocumentEntry({
    required this.id,
    required this.title,
    required this.filename,
    required this.chunkCount,
    required this.sizeBytes,
    required this.updatedAt,
    required this.status,
    this.indexingProgress = 1.0,
    this.jobId,
  });

  static String titleFromFilename(String filename) {
    return filename
        .replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '')
        .replaceAll('_', ' ');
  }

  factory DocumentEntry.fromJson(Map<String, dynamic> json) {
    final filename = json['filename']?.toString() ?? 'document.pdf';
    final rawStatus = json['status']?.toString().toLowerCase() ?? 'indexed';
    final IngestionStatus parsedStatus;
    final double defaultProgress;

    switch (rawStatus) {
      case 'queued':
      case 'pending':
        parsedStatus = IngestionStatus.indexing;
        defaultProgress = 0.15;
        break;
      case 'processing':
      case 'indexing':
        parsedStatus = IngestionStatus.indexing;
        defaultProgress = 0.5;
        break;
      case 'failed':
        parsedStatus = IngestionStatus.failed;
        defaultProgress = 0.0;
        break;
      case 'completed':
      case 'indexed':
      default:
        parsedStatus = IngestionStatus.indexed;
        defaultProgress = 1.0;
        break;
    }

    return DocumentEntry(
      id: json['id']?.toString() ?? json['document_id']?.toString() ?? '',
      title: json['title']?.toString() ?? titleFromFilename(filename),
      filename: filename,
      chunkCount:
          json['chunkCount'] is int
              ? json['chunkCount'] as int
              : int.tryParse(json['chunks']?.toString() ?? '0') ?? 0,
      sizeBytes:
          json['sizeBytes'] is int
              ? json['sizeBytes'] as int
              : int.tryParse(json['sizeBytes']?.toString() ?? '0') ?? 0,
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      status: parsedStatus,
      indexingProgress:
          (json['indexingProgress'] is num)
              ? (json['indexingProgress'] as num).toDouble()
              : defaultProgress,
      jobId: json['job_id']?.toString() ?? json['jobId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'filename': filename,
    'chunkCount': chunkCount,
    'sizeBytes': sizeBytes,
    'updatedAt': updatedAt.toIso8601String(),
    'status': status.name,
    'indexingProgress': indexingProgress,
    if (jobId != null) 'jobId': jobId,
  };

  DocumentEntry copyWith({
    String? id,
    String? title,
    String? filename,
    int? chunkCount,
    int? sizeBytes,
    DateTime? updatedAt,
    IngestionStatus? status,
    double? indexingProgress,
    String? jobId,
  }) {
    return DocumentEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      filename: filename ?? this.filename,
      chunkCount: chunkCount ?? this.chunkCount,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      indexingProgress: indexingProgress ?? this.indexingProgress,
      jobId: jobId ?? this.jobId,
    );
  }
}
