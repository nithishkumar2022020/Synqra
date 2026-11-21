import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/services/cloudwatch_service.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/corpus_repository.dart';
import 'data/repositories/mock_telemetry_repository.dart';
import 'data/repositories/profile_settings_repository.dart';
import 'data/repositories/rag_stream_repository.dart';
import 'domain/repositories/i_corpus_repository.dart';
import 'domain/repositories/i_profile_settings_repository.dart';
import 'domain/repositories/i_rag_stream_repository.dart';
import 'domain/repositories/i_telemetry_repository.dart';
import 'firebase_options.dart';
import 'presentation/providers/corpus_provider.dart';
import 'presentation/providers/rag_session_provider.dart';
import 'presentation/providers/settings_provider.dart';
import 'presentation/providers/telemetry_provider.dart';
import 'presentation/screens/archival_splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  // Initialize Firebase asynchronously in the background so it never blocks the first frame
  Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  ).catchError((_) {
    // Graceful initialization fallback for local/offline testing
    return Firebase.app();
  });

  final CloudWatchService cloudWatchService = CloudWatchService();
  final IRagStreamRepository ragStreamRepo = RagStreamRepository();
  final ICorpusRepository corpusRepo = CorpusRepository();
  final ITelemetryRepository telemetryRepo = MockTelemetryRepository();
  final IProfileSettingsRepository settingsRepo = ProfileSettingsRepository();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(
            repository: settingsRepo,
            cloudWatchService: cloudWatchService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => RagSessionProvider(
            repository: ragStreamRepo,
            cloudWatchService: cloudWatchService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => CorpusProvider(
            repository: corpusRepo,
            cloudWatchService: cloudWatchService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => TelemetryProvider(
            repository: telemetryRepo,
            cloudWatchService: cloudWatchService,
          ),
        ),
      ],
      child: const RagApplication(),
    ),
  );
}

class RagApplication extends StatelessWidget {
  const RagApplication({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProv, _) {
        final isDark = settingsProv.isNocturneMode;
        return MaterialApp(
          title: 'Archival RAG Shell',
          debugShowCheckedModeBanner: false,
          scrollBehavior: const SynqraScrollBehavior(),
          theme: AppTheme.buildTheme(isDark),
          home: const ArchivalSplashScreen(),
        );
      },
    );
  }
}
