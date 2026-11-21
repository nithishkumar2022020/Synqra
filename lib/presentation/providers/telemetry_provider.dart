import 'package:flutter/foundation.dart';
import '../../core/services/cloudwatch_service.dart';
import '../../domain/models/telemetry.dart';
import '../../domain/repositories/i_telemetry_repository.dart';

class TelemetryProvider extends ChangeNotifier {
  final ITelemetryRepository _repository;
  final CloudWatchService? _cloudWatchService;
  TelemetryData? _telemetry;
  bool _isLoading = false;

  TelemetryProvider({
    required ITelemetryRepository repository,
    CloudWatchService? cloudWatchService,
  })  : _repository = repository,
        _cloudWatchService = cloudWatchService {
    fetchLatestTelemetry();
  }

  TelemetryData? get telemetry => _telemetry;
  bool get isLoading => _isLoading;
  CloudWatchService? get cloudWatchService => _cloudWatchService;

  CloudWatchState get cloudWatchState =>
      _cloudWatchService?.state ?? CloudWatchState.active;

  int get cloudWatchEventsCount =>
      _cloudWatchService?.eventsIngestedCount ?? 0;

  String get cloudWatchRegion =>
      _cloudWatchService?.region ?? 'ap-southeast-2';

  String get cloudWatchLogGroup =>
      _cloudWatchService?.logGroupName ?? '/synqra/archival-rag';

  List<CloudWatchLogRecord> get recentCloudWatchLogs =>
      _cloudWatchService?.recentLogs ?? [];

  Future<void> fetchLatestTelemetry({String? queryId}) async {
    _isLoading = true;
    notifyListeners();
    try {
      _telemetry = await _repository.getTelemetryForQuery(queryId: queryId);
      if (_telemetry != null && _cloudWatchService != null) {
        _cloudWatchService.putMetric(
          metricName: 'TotalLatency',
          value: _telemetry!.totalLatencyMs.toDouble(),
          unit: 'Milliseconds',
        );
        _cloudWatchService.putMetric(
          metricName: 'DenseRetrievalScore',
          value: _telemetry!.denseRetrievalScore,
          unit: 'None',
        );
        _cloudWatchService.putMetric(
          metricName: 'SparseBM25Score',
          value: _telemetry!.sparseBM25Score,
          unit: 'None',
        );
      }
    } catch (_) {
      _telemetry = TelemetryData.mock();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
