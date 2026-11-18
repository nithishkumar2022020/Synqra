import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/corpus.dart';
import '../providers/corpus_provider.dart';
import '../providers/rag_session_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/brutalist_container.dart';

class IngestionScreen extends StatefulWidget {
  final VoidCallback onNavigateToQuery;

  const IngestionScreen({super.key, required this.onNavigateToQuery});

  @override
  State<IngestionScreen> createState() => _IngestionScreenState();
}

class _IngestionScreenState extends State<IngestionScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _quickQueryController = TextEditingController();
  final Map<int, GlobalKey> _itemKeys = {};
  int? _dragAnchorIndex;
  int? _dragLastIndex;
  Set<String> _dragBaseSelection = {};
  bool _dragSelectMode = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _quickQueryController.dispose();
    super.dispose();
  }

  GlobalKey _keyForIndex(int index) {
    return _itemKeys.putIfAbsent(index, () => GlobalKey());
  }

  void _startDragSelection(int index, CorpusProvider corpus) {
    if (index < 0 || index >= corpus.documents.length) return;
    HapticFeedback.mediumImpact();
    _dragAnchorIndex = index;
    _dragLastIndex = index;
    _dragBaseSelection = Set<String>.from(corpus.selectedDocumentIds);
    _dragSelectMode = !corpus.isSelected(corpus.documents[index].id);
    corpus.applyDragRangeSelection(
      anchorIndex: index,
      targetIndex: index,
      baseSelection: _dragBaseSelection,
      selectRange: _dragSelectMode,
    );
  }

  void _updateDragSelection(Offset globalPosition, CorpusProvider corpus) {
    final anchor = _dragAnchorIndex;
    if (anchor == null) return;
    final hitIndex = _findItemIndexAt(globalPosition);
    if (hitIndex == null || hitIndex == _dragLastIndex) return;
    _dragLastIndex = hitIndex;
    HapticFeedback.selectionClick();
    corpus.applyDragRangeSelection(
      anchorIndex: anchor,
      targetIndex: hitIndex,
      baseSelection: _dragBaseSelection,
      selectRange: _dragSelectMode,
    );
  }

  void _endDragSelection() {
    _dragAnchorIndex = null;
    _dragLastIndex = null;
    _dragBaseSelection = {};
  }

  int? _findItemIndexAt(Offset globalPosition) {
    for (final entry in _itemKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final topLeft = box.localToGlobal(Offset.zero);
      final bottom = topLeft.dy + box.size.height;
      if (globalPosition.dy >= topLeft.dy - 6 &&
          globalPosition.dy <= bottom + 6) {
        return entry.key;
      }
    }
    return null;
  }

  void _submitAutoRouteQuery() {
    final text = _quickQueryController.text.trim();
    if (text.isEmpty) return;

    final ragSession = context.read<RagSessionProvider>();
    final settings = context.read<SettingsProvider>().settings;
    final selectedIds =
        context.read<CorpusProvider>().selectedDocumentIds.toList();

    ragSession.submitQuery(
      text,
      settings: settings,
      selectedDocumentIds: selectedIds,
    );
    _quickQueryController.clear();
    widget.onNavigateToQuery();
  }

  Future<void> _handleIngestPdf(Color vermilion) async {
    final corpus = context.read<CorpusProvider>();
    if (corpus.isUploading) return;

    final settings = context.read<SettingsProvider>().settings;

    if (settings.useOfflineSimulation) {
      final doc = await corpus.uploadPdf(
        filename: 'demo_corpus_${DateTime.now().second}.pdf',
        endpointUrl: settings.sseEndpoint,
        useOfflineSimulation: true,
      );
      if (mounted && doc != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Simulated ingest "${doc.filename}" (${doc.chunkCount} chunks).',
              style: AppTheme.monospace(color: Colors.white, fontSize: 12),
            ),
            backgroundColor: vermilion,
          ),
        );
      }
      return;
    }

    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );

    if (picked == null || !mounted) return;

    final bytes = picked.path == null ? await picked.readAsBytes() : null;
    if (!mounted) return;

    final doc = await corpus.uploadPdf(
      filename: picked.name,
      endpointUrl: settings.sseEndpoint,
      filePath: picked.path,
      bytes: bytes,
      apiKey: settings.apiKey,
      useOfflineSimulation: false,
    );

    if (!mounted) return;
    if (doc != null) {
      final mode = corpus.useSemanticChunking ? 'semantic' : 'fixed-size';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ingested "${doc.filename}" (${doc.chunkCount} chunks, $mode mode).',
            style: AppTheme.monospace(color: Colors.white, fontSize: 12),
          ),
          backgroundColor: vermilion,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.nocturneText : AppTheme.parchmentText;
    final mutedText =
        isDark ? AppTheme.nocturneMutedText : AppTheme.parchmentMutedText;
    final vermilion =
        isDark ? AppTheme.nocturneVermilion : AppTheme.parchmentVermilion;
    final borderColor =
        isDark ? AppTheme.nocturneBorder : AppTheme.parchmentBorder;
    final surfaceColor =
        isDark ? AppTheme.nocturneSurface : AppTheme.parchmentSurface;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            // Top Bar
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: borderColor, width: 2),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CORPUS REPOSITORY',
                      style: AppTheme.monospace(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'GESTURE: SWIPE ➔ QUERY',
                      style: AppTheme.monospace(
                        color: vermilion,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Contextual Auto-Route Search Field
                  Text(
                    'CONTEXTUAL RAG SEARCH (AUTO-ROUTES)',
                    style: AppTheme.monospace(
                      color: mutedText,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: AppTheme.brutalistDecoration(
                      bgColor: surfaceColor,
                      borderColor: borderColor,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _quickQueryController,
                            style: AppTheme.readingSerif(
                              color: textColor,
                              fontSize: 14,
                            ),
                            onSubmitted: (_) => _submitAutoRouteQuery(),
                            decoration: InputDecoration(
                              hintText: 'Ask corpus or tap query to stream...',
                              hintStyle: AppTheme.readingSerif(
                                color: mutedText,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _submitAutoRouteQuery,
                          child: Container(
                            color: vermilion,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: const Icon(
                              Icons.arrow_forward,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Chunking Strategy Selector
                  _buildChunkingStrategyCard(
                    isDark: isDark,
                    textColor: textColor,
                    mutedText: mutedText,
                    vermilion: vermilion,
                    borderColor: borderColor,
                    surfaceColor: surfaceColor,
                  ),
                  const SizedBox(height: 12),

                  // Actions row: Pick & Upload PDF
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'INGESTED MANIFEST',
                        style: AppTheme.monospace(
                          color: mutedText,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Consumer<CorpusProvider>(
                        builder:
                            (context, corpus, _) => GestureDetector(
                              key: const Key('corpus_ingest_btn'),
                              onTap:
                                  corpus.isUploading
                                      ? null
                                      : () => _handleIngestPdf(vermilion),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: AppTheme.brutalistDecoration(
                                  bgColor:
                                      corpus.isUploading
                                          ? mutedText
                                          : vermilion,
                                  borderColor: borderColor,
                                  borderWidth: 1.5,
                                  shadowOffset: const Offset(2, 2),
                                ),
                                child: Row(
                                  children: [
                                    if (corpus.isUploading)
                                      const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    else
                                      const Icon(
                                        Icons.upload_file,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    const SizedBox(width: 6),
                                    Text(
                                      corpus.isUploading
                                          ? 'INGESTING...'
                                          : '+ INGEST PDF',
                                      style: AppTheme.monospace(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Error Banner (if upload fails)
                  Consumer<CorpusProvider>(
                    builder: (context, corpus, _) {
                      if (corpus.error == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: BrutalistContainer(
                          backgroundColor: vermilion.withValues(alpha: 0.12),
                          borderColor: vermilion,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  corpus.error!,
                                  style: AppTheme.monospace(
                                    color: vermilion,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: vermilion,
                                ),
                                onPressed: corpus.clearError,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  // Selection Scope Bar
                  Consumer<CorpusProvider>(
                    builder: (context, corpus, _) {
                      if (corpus.documents.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final count = corpus.selectedDocumentIds.length;
                      final String scopeText;
                      if (count == 0) {
                        scopeText =
                            'RAG SCOPE: ALL DATABASE (TAP OR HOLD & SLIDE)';
                      } else if (count == 1) {
                        scopeText = 'RAG SCOPE: 1 PDF SELECTED';
                      } else {
                        scopeText = 'RAG SCOPE: $count PDFS SELECTED';
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color:
                                count > 0
                                    ? Color.alphaBlend(
                                      vermilion.withValues(alpha: 0.10),
                                      surfaceColor,
                                    )
                                    : surfaceColor,
                            border: Border.all(
                              color:
                                  count > 0
                                      ? vermilion
                                      : borderColor.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  scopeText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.monospace(
                                    color: count > 0 ? vermilion : mutedText,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (count < corpus.documents.length) ...[
                                const SizedBox(width: 6),
                                GestureDetector(
                                  key: const Key('corpus_select_all_btn'),
                                  onTap: corpus.selectAll,
                                  child: Text(
                                    'ALL',
                                    style: AppTheme.monospace(
                                      color: textColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                              if (count > 0) ...[
                                const SizedBox(width: 10),
                                GestureDetector(
                                  key: const Key('corpus_clear_selection_btn'),
                                  onTap: corpus.clearSelection,
                                  child: Text(
                                    'CLEAR',
                                    style: AppTheme.monospace(
                                      color: mutedText,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                GestureDetector(
                                  key: const Key('corpus_ask_selected_btn'),
                                  onTap: widget.onNavigateToQuery,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    color: vermilion,
                                    child: Text(
                                      'QUERY',
                                      style: AppTheme.monospace(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ]),
              ),
            ),

            // Document Manifest List
            Consumer<CorpusProvider>(
              builder: (context, corpus, _) {
                if (corpus.isLoading) {
                  return SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'RETRIEVING MANIFEST...',
                          style: AppTheme.monospace(
                            color: mutedText,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );
                }

                if (corpus.documents.isEmpty) {
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: BrutalistContainer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'NO PDFS INGESTED FROM THIS DEVICE YET',
                              style: AppTheme.monospace(
                                color: textColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Tap "+ INGEST PDF" above to select a readable PDF and upload it to POST /documents for chunking and Milvus indexing.',
                              style: AppTheme.readingSerif(
                                color: mutedText,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final doc = corpus.documents[index];
                      final isIndexed = doc.status == IngestionStatus.indexed;
                      final isIndexing = doc.status == IngestionStatus.indexing;
                      final isFailed = doc.status == IngestionStatus.failed;
                      final isSelected = corpus.isSelected(doc.id);

                      final Color statusBg;
                      final Color statusFg;
                      final String statusLabel;

                      if (isSelected) {
                        statusBg = vermilion;
                        statusFg = Colors.white;
                        statusLabel = 'RAG ACTIVE';
                      } else if (isIndexed) {
                        statusBg = (isDark
                                ? AppTheme.nocturneSage
                                : AppTheme.parchmentSage)
                            .withValues(alpha: 0.2);
                        statusFg =
                            isDark
                                ? AppTheme.nocturneSage
                                : AppTheme.parchmentSage;
                        statusLabel = 'INDEXED';
                      } else if (isFailed) {
                        statusBg = vermilion.withValues(alpha: 0.2);
                        statusFg = vermilion;
                        statusLabel = 'FAILED';
                      } else {
                        statusBg = (isDark
                                ? AppTheme.nocturneAmber
                                : AppTheme.parchmentAmber)
                            .withValues(alpha: 0.2);
                        statusFg =
                            isDark
                                ? AppTheme.nocturneAmber
                                : AppTheme.parchmentAmber;
                        statusLabel = 'INDEXING';
                      }

                      return Padding(
                        key: _keyForIndex(index),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GestureDetector(
                          key: Key('corpus_doc_card_${doc.id}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => corpus.toggleSelection(doc.id),
                          onLongPressStart:
                              (_) => _startDragSelection(index, corpus),
                          onLongPressMoveUpdate:
                              (details) => _updateDragSelection(
                                details.globalPosition,
                                corpus,
                              ),
                          onLongPressEnd: (_) => _endDragSelection(),
                          child: BrutalistContainer(
                            backgroundColor:
                                isSelected
                                    ? vermilion.withValues(alpha: 0.08)
                                    : null,
                            borderColor: isSelected ? vermilion : borderColor,
                            borderWidth: isSelected ? 2.5 : 2.0,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      width: 18,
                                      height: 18,
                                      margin: const EdgeInsets.only(right: 10),
                                      decoration: BoxDecoration(
                                        color:
                                            isSelected
                                                ? vermilion
                                                : Colors.transparent,
                                        border: Border.all(
                                          color:
                                              isSelected
                                                  ? vermilion
                                                  : borderColor,
                                          width: 1.5,
                                        ),
                                      ),
                                      child:
                                          isSelected
                                              ? const Icon(
                                                Icons.check,
                                                size: 13,
                                                color: Colors.white,
                                              )
                                              : null,
                                    ),
                                    Expanded(
                                      child: Text(
                                        doc.title,
                                        style: AppTheme.slabHeader(
                                          color: textColor,
                                          fontSize: 16,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      color: statusBg,
                                      child: Text(
                                        statusLabel,
                                        style: AppTheme.monospace(
                                          color: statusFg,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'FILE: ${doc.filename}  •  ID: ${doc.id}${doc.jobId != null ? '  •  JOB: ${doc.jobId}' : ''}',
                                  style: AppTheme.monospace(
                                    color: mutedText,
                                    fontSize: 10,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      '${doc.chunkCount} CHUNKS',
                                      style: AppTheme.monospace(
                                        color: textColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (doc.sizeBytes > 0) ...[
                                      const SizedBox(width: 12),
                                      Text(
                                        '${(doc.sizeBytes / 1024).toStringAsFixed(1)} KB',
                                        style: AppTheme.monospace(
                                          color: mutedText,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (isIndexing) ...[
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.zero,
                                    child: LinearProgressIndicator(
                                      value:
                                          doc.indexingProgress > 0
                                              ? doc.indexingProgress
                                              : null,
                                      backgroundColor: borderColor.withValues(
                                        alpha: 0.2,
                                      ),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        isDark
                                            ? AppTheme.nocturneAmber
                                            : AppTheme.parchmentAmber,
                                      ),
                                      minHeight: 3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'ASYNCHRONOUS INGESTION IN PROGRESS (${(doc.indexingProgress * 100).toInt()}%)',
                                    style: AppTheme.monospace(
                                      color:
                                          isDark
                                              ? AppTheme.nocturneAmber
                                              : AppTheme.parchmentAmber,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                                if (isFailed) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'INGESTION ERROR: PARSING / VECTOR INDEX FAILED',
                                    style: AppTheme.monospace(
                                      color: vermilion,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }, childCount: corpus.documents.length),
                  ),
                );
              },
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }

  Widget _buildChunkingStrategyCard({
    required bool isDark,
    required Color textColor,
    required Color mutedText,
    required Color vermilion,
    required Color borderColor,
    required Color surfaceColor,
  }) {
    return Consumer<CorpusProvider>(
      builder: (context, corpus, _) {
        final isSemantic = corpus.useSemanticChunking;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: AppTheme.brutalistDecoration(
            bgColor: surfaceColor,
            borderColor: borderColor,
            borderWidth: 1.5,
            shadowOffset: const Offset(3, 3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isSemantic ? vermilion : mutedText,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'CHUNKING STRATEGY',
                        style: AppTheme.monospace(
                          color: textColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (isSemantic
                              ? vermilion
                              : (isDark
                                  ? AppTheme.nocturneAmber
                                  : AppTheme.parchmentAmber))
                          .withValues(alpha: 0.15),
                      border: Border.all(
                        color:
                            isSemantic
                                ? vermilion
                                : (isDark
                                    ? AppTheme.nocturneAmber
                                    : AppTheme.parchmentAmber),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      isSemantic ? 'SEMANTIC // 1536-D' : 'FIXED // WINDOW',
                      style: AppTheme.monospace(
                        color:
                            isSemantic
                                ? vermilion
                                : (isDark
                                    ? AppTheme.nocturneAmber
                                    : AppTheme.parchmentAmber),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor, width: 1.5),
                  color: isDark ? AppTheme.nocturneBg : AppTheme.parchmentBg,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        key: const Key('chunking_semantic_option'),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          corpus.setSemanticChunking(true);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isSemantic ? vermilion : Colors.transparent,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.psychology,
                                size: 14,
                                color: isSemantic ? Colors.white : mutedText,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'SEMANTIC',
                                style: AppTheme.monospace(
                                  color: isSemantic ? Colors.white : textColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(width: 1.5, height: 32, color: borderColor),
                    Expanded(
                      child: GestureDetector(
                        key: const Key('chunking_fixed_option'),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          corpus.setSemanticChunking(false);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color:
                                !isSemantic
                                    ? (isDark
                                        ? AppTheme.nocturneBorder
                                        : AppTheme.parchmentBorder)
                                    : Colors.transparent,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.straighten,
                                size: 14,
                                color:
                                    !isSemantic
                                        ? (isDark
                                            ? AppTheme.nocturneBg
                                            : Colors.white)
                                        : mutedText,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'FIXED-SIZE',
                                style: AppTheme.monospace(
                                  color:
                                      !isSemantic
                                          ? (isDark
                                              ? AppTheme.nocturneBg
                                              : Colors.white)
                                          : textColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isSemantic
                    ? '• Semantic mode: Inter-sentence Gemini embeddings for coherent, natural context boundaries.'
                    : '• Fixed-size mode: Rapid token windows. Skips intermediate sentence embeddings for faster ingest.',
                style: AppTheme.monospace(
                  color: mutedText,
                  fontSize: 9.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
