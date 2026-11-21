class ProfileSettings {
  static const String defaultProductionDomain = 'synqra-api.duckdns.org';
  static const String liveBaseUrl = 'https://$defaultProductionDomain';
  static const String productionEndpoint = '$liveBaseUrl/questions/stream';
  static const String defaultEndpoint = productionEndpoint;
  static const String localEndpoint = 'http://localhost:8000/questions/stream';
  static const String ec2Host = '32.236.134.203';
  static const String ec2Endpoint = 'http://$ec2Host/questions/stream';

  final String apiKey;
  final String sseEndpoint;
  final bool isNocturneMode;
  final bool enableDenseOnly;
  final double similarityThreshold;
  final int topK;
  final bool isAuthenticated;
  final String researcherName;
  final String callSign;
  final String clearanceLevel;
  final bool isGuest;
  final bool useOfflineSimulation;
  final String cloudWatchLogGroup;
  final String cloudWatchRegion;
  final bool enableCloudWatch;

  const ProfileSettings({
    required this.apiKey,
    required this.sseEndpoint,
    required this.isNocturneMode,
    required this.enableDenseOnly,
    required this.similarityThreshold,
    required this.topK,
    this.isAuthenticated = false,
    this.researcherName = 'Nithish R.',
    this.callSign = 'ARCH-9942',
    this.clearanceLevel = 'Level-3 Architect',
    this.isGuest = false,
    this.useOfflineSimulation = false,
    this.cloudWatchLogGroup = '/synqra/archival-rag',
    this.cloudWatchRegion = 'ap-southeast-2',
    this.enableCloudWatch = true,
  });

  factory ProfileSettings.defaults() {
    return const ProfileSettings(
      apiKey: '',
      sseEndpoint: defaultEndpoint,
      isNocturneMode: false,
      enableDenseOnly: false,
      similarityThreshold: 0.75,
      topK: 5,
      isAuthenticated: false,
      researcherName: 'Nithish R.',
      callSign: 'ARCH-9942',
      clearanceLevel: 'Level-3 Architect',
      isGuest: false,
      useOfflineSimulation: false,
      cloudWatchLogGroup: '/synqra/archival-rag',
      cloudWatchRegion: 'ap-southeast-2',
      enableCloudWatch: true,
    );
  }

  ProfileSettings copyWith({
    String? apiKey,
    String? sseEndpoint,
    bool? isNocturneMode,
    bool? enableDenseOnly,
    double? similarityThreshold,
    int? topK,
    bool? isAuthenticated,
    String? researcherName,
    String? callSign,
    String? clearanceLevel,
    bool? isGuest,
    bool? useOfflineSimulation,
    String? cloudWatchLogGroup,
    String? cloudWatchRegion,
    bool? enableCloudWatch,
  }) {
    return ProfileSettings(
      apiKey: apiKey ?? this.apiKey,
      sseEndpoint: sseEndpoint ?? this.sseEndpoint,
      isNocturneMode: isNocturneMode ?? this.isNocturneMode,
      enableDenseOnly: enableDenseOnly ?? this.enableDenseOnly,
      similarityThreshold: similarityThreshold ?? this.similarityThreshold,
      topK: topK ?? this.topK,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      researcherName: researcherName ?? this.researcherName,
      callSign: callSign ?? this.callSign,
      clearanceLevel: clearanceLevel ?? this.clearanceLevel,
      isGuest: isGuest ?? this.isGuest,
      useOfflineSimulation: useOfflineSimulation ?? this.useOfflineSimulation,
      cloudWatchLogGroup: cloudWatchLogGroup ?? this.cloudWatchLogGroup,
      cloudWatchRegion: cloudWatchRegion ?? this.cloudWatchRegion,
      enableCloudWatch: enableCloudWatch ?? this.enableCloudWatch,
    );
  }
}
