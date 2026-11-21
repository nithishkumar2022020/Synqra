import 'dart:convert';
import 'package:aws_common/aws_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_flutter_proj_dq/core/services/cloudwatch_service.dart';

void main() {
  group('CloudWatch Models & Serialization Tests', () {
    test('CloudWatchLogRecord formats event correctly', () {
      final now = DateTime.utc(2026, 11, 21, 12, 0, 0);
      final record = CloudWatchLogRecord(
        timestamp: now,
        level: 'INFO',
        message: 'Test event dispatched',
        metadata: {'latency_ms': 142, 'operator': 'ARCH-9942'},
      );

      final event = record.toCloudWatchEvent();
      expect(event['timestamp'], equals(now.millisecondsSinceEpoch));
      final decodedMsg = jsonDecode(event['message'] as String);
      expect(decodedMsg['level'], equals('INFO'));
      expect(decodedMsg['message'], equals('Test event dispatched'));
      expect(decodedMsg['metadata']['latency_ms'], equals(142));
      expect(decodedMsg['metadata']['operator'], equals('ARCH-9942'));
    });

    test('CloudWatchMetricDatum formats metric JSON correctly', () {
      final now = DateTime.utc(2026, 11, 21, 12, 0, 0);
      final datum = CloudWatchMetricDatum(
        metricName: 'QueryLatency',
        value: 167.0,
        unit: 'Milliseconds',
        timestamp: now,
        dimensions: {'Operator': 'ARCH-9942', 'Status': 'OK'},
      );

      final json = datum.toJson();
      expect(json['MetricName'], equals('QueryLatency'));
      expect(json['Value'], equals(167.0));
      expect(json['Unit'], equals('Milliseconds'));
      expect(json['Timestamp'], equals(now.toIso8601String()));
      final dims = json['Dimensions'] as List;
      expect(dims.length, equals(2));
      expect(dims.any((d) => d['Name'] == 'Operator' && d['Value'] == 'ARCH-9942'), isTrue);
      expect(dims.any((d) => d['Name'] == 'Status' && d['Value'] == 'OK'), isTrue);
    });

    test('getStreamName sanitizes special characters and appends UTC date', () {
      final service = CloudWatchService();
      final streamName = service.getStreamName('ARCH/Lead:9942@Sydney');
      expect(streamName.startsWith('operator-ARCH_Lead_9942_Sydney/'), isTrue);
      final parts = streamName.split('/');
      expect(parts.length, equals(2));
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(parts[1]), isTrue);
    });
  });

  group('CloudWatchService In-Memory Telemetry Ring Buffer Tests', () {
    test('logEvent buffers records and increments counter', () async {
      final service = CloudWatchService();
      expect(service.eventsIngestedCount, equals(0));
      expect(service.recentLogs, isEmpty);

      final success = await service.logEvent(
        level: 'INFO',
        message: 'System initialization pulse',
        callSign: 'ARCH-9942',
      );

      expect(success, isTrue);
      expect(service.eventsIngestedCount, equals(1));
      expect(service.recentLogs.length, equals(1));
      expect(service.recentLogs.first.level, equals('INFO'));
      expect(service.recentLogs.first.message, equals('System initialization pulse'));
    });

    test('logEvent respects maxBufferedLogs cap', () async {
      final service = CloudWatchService();
      for (int i = 0; i < 75; i++) {
        await service.logEvent(
          level: 'DEBUG',
          message: 'Pulse $i',
        );
      }

      expect(service.eventsIngestedCount, equals(75));
      expect(service.recentLogs.length, equals(CloudWatchService.maxBufferedLogs));
      expect(service.recentLogs.first.message, equals('Pulse 74'));
    });

    test('putMetric buffers metric data', () async {
      final service = CloudWatchService();
      await service.putMetric(
        metricName: 'DenseCosineScore',
        value: 0.945,
        unit: 'None',
        dimensions: {'Doc': 'neural_ir.pdf'},
      );

      expect(service.recentMetrics.length, equals(1));
      expect(service.recentMetrics.first.metricName, equals('DenseCosineScore'));
      expect(service.recentMetrics.first.value, equals(0.945));
    });

    test('disabled service ignores logEvent and putMetric', () async {
      final service = CloudWatchService(isEnabled: false);
      expect(service.state, equals(CloudWatchState.disabled));

      final logOk = await service.logEvent(level: 'INFO', message: 'Should be ignored');
      final metricOk = await service.putMetric(metricName: 'IgnoredMetric', value: 1.0);

      expect(logOk, isFalse);
      expect(metricOk, isFalse);
      expect(service.eventsIngestedCount, equals(0));
      expect(service.recentLogs, isEmpty);
      expect(service.recentMetrics, isEmpty);
    });
  });

  group('CloudWatchService High-Level Telemetry Workflows', () {
    test('logQuery records both event and CloudWatch metrics', () async {
      final service = CloudWatchService();
      await service.logQuery(
        prompt: 'What is cross-attention reranking?',
        latencyMs: 185,
        tokenCount: 42,
        citationCount: 3,
        callSign: 'ARCH-9942',
        isSuccess: true,
      );

      expect(service.recentLogs.length, equals(1));
      expect(service.recentLogs.first.level, equals('INFO'));
      expect(service.recentLogs.first.metadata['latency_ms'], equals(185));
      expect(service.recentLogs.first.metadata['tokens_streamed'], equals(42));
      expect(service.recentLogs.first.metadata['citations_count'], equals(3));

      expect(service.recentMetrics.length, equals(2));
      expect(service.recentMetrics.any((m) => m.metricName == 'QueryLatency' && m.value == 185.0), isTrue);
      expect(service.recentMetrics.any((m) => m.metricName == 'TokensStreamed' && m.value == 42.0), isTrue);
    });

    test('logIngest records ingestion metadata and chunk count metric', () async {
      final service = CloudWatchService();
      await service.logIngest(
        filename: 'neural_ir_paper.pdf',
        chunkCount: 16,
        strategy: 'SEMANTIC',
        callSign: 'ARCH-9942',
        isSuccess: true,
      );

      expect(service.recentLogs.length, equals(1));
      expect(service.recentLogs.first.message, contains('neural_ir_paper.pdf'));
      expect(service.recentLogs.first.metadata['chunks'], equals(16));

      expect(service.recentMetrics.length, equals(1));
      expect(service.recentMetrics.first.metricName, equals('ChunksIngested'));
      expect(service.recentMetrics.first.value, equals(16.0));
    });

    test('logAuth records operator authentication actions', () async {
      final service = CloudWatchService();
      await service.logAuth(
        action: 'SIGN_IN',
        callSign: 'ARCH-9942',
        isSuccess: true,
        detail: 'Clearance: Level-3 Architect',
      );

      expect(service.recentLogs.length, equals(1));
      expect(service.recentLogs.first.level, equals('INFO'));
      expect(service.recentLogs.first.message, equals('Operator auth action: SIGN_IN'));
      expect(service.recentLogs.first.metadata['call_sign'], equals('ARCH-9942'));
    });
  });

  group('AWS SigV4 PutLogEvents Mock Dispatch Tests', () {
    test('sends signed AWS SigV4 PutLogEvents request when credentials exist', () async {
      String? capturedAuthHeader;
      String? capturedTargetHeader;
      String? capturedBody;

      final mockClient = MockClient((request) async {
        capturedAuthHeader = request.headers['authorization'];
        capturedTargetHeader = request.headers['x-amz-target'];
        capturedBody = request.body;

        return http.Response(
          jsonEncode({
            'nextSequenceToken': '495912345678901234567890',
          }),
          200,
          headers: {'content-type': 'application/x-amz-json-1.1'},
        );
      });

      final service = CloudWatchService(
        region: 'ap-southeast-2',
        logGroupName: '/synqra/archival-rag',
        httpClient: mockClient,
        credentialsProvider: () async => const AWSCredentials(
          'ASIAIOSFODNN7EXAMPLE',
          'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
          'SESSION_TOKEN_EXAMPLE',
        ),
      );

      final success = await service.logEvent(
        level: 'INFO',
        message: 'Signed SigV4 telemetry event',
        callSign: 'ARCH-9942',
      );

      expect(success, isTrue);
      expect(service.state, equals(CloudWatchState.active));
      expect(capturedAuthHeader, isNotNull);
      expect(capturedAuthHeader, contains('AWS4-HMAC-SHA256'));
      expect(capturedAuthHeader, contains('ap-southeast-2/logs/aws4_request'));
      expect(capturedTargetHeader, equals('Logs_20140328.PutLogEvents'));

      final payload = jsonDecode(capturedBody!);
      expect(payload['logGroupName'], equals('/synqra/archival-rag'));
      expect((payload['logEvents'] as List).length, equals(1));
    });
  });
}
