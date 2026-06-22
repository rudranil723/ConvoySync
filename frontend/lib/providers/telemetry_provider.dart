import 'package:flutter_riverpod/flutter_riverpod.dart';

class RiderTelemetry {
  final String profileId;
  final double latitude;
  final double longitude;
  final double speed;
  final double bearing;
  final double distanceToLeaderKm;
  final double crossTrackErrorMeters;
  final bool distanceExceeded;
  final bool wrongTurn;
  final DateTime timestamp;

  RiderTelemetry({
    required this.profileId,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.bearing,
    required this.distanceToLeaderKm,
    required this.crossTrackErrorMeters,
    required this.distanceExceeded,
    required this.wrongTurn,
    required this.timestamp,
  });

  factory RiderTelemetry.fromJson(Map<String, dynamic> json) {
    final metrics = json['metrics'] ?? {};
    final flags = json['flags'] ?? {};
    
    return RiderTelemetry(
      profileId: json['profile_id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      speed: (json['speed'] as num).toDouble(),
      bearing: (json['bearing'] as num).toDouble(),
      distanceToLeaderKm: (metrics['distance_to_leader_km'] as num? ?? 0.0).toDouble(),
      crossTrackErrorMeters: (metrics['cross_track_error_meters'] as num? ?? 0.0).toDouble(),
      distanceExceeded: flags['distance_exceeded'] as bool? ?? false,
      wrongTurn: flags['wrong_turn'] as bool? ?? false,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

class TelemetryState {
  final Map<String, RiderTelemetry> activeRiders;
  final List<String> alertHistory;

  TelemetryState({
    required this.activeRiders,
    required this.alertHistory,
  });

  TelemetryState copyWith({
    Map<String, RiderTelemetry>? activeRiders,
    List<String>? alertHistory,
  }) {
    return TelemetryState(
      activeRiders: activeRiders ?? this.activeRiders,
      alertHistory: alertHistory ?? this.alertHistory,
    );
  }
}

class TelemetryNotifier extends StateNotifier<TelemetryState> {
  TelemetryNotifier() : super(TelemetryState(activeRiders: {}, alertHistory: []));

  void updateRiderTelemetry(Map<String, dynamic> payload) {
    try {
      final telemetry = RiderTelemetry.fromJson(payload);
      final updatedRiders = Map<String, RiderTelemetry>.from(state.activeRiders);
      updatedRiders[telemetry.profileId] = telemetry;
      state = state.copyWith(activeRiders: updatedRiders);
    } catch (e) {
      print('Error updating telemetry state: $e');
    }
  }

  void addAlert(String alertText) {
    state = state.copyWith(
      alertHistory: [alertText, ...state.alertHistory],
    );
  }

  void clearTelemetry() {
    state = TelemetryState(activeRiders: {}, alertHistory: []);
  }
}

final telemetryProvider = StateNotifierProvider<TelemetryNotifier, TelemetryState>((ref) {
  return TelemetryNotifier();
});
