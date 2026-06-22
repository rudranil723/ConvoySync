import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import 'package:frontend/theme.dart';
import 'package:frontend/providers/telemetry_provider.dart';
import 'package:frontend/providers/lobby_provider.dart';
import 'package:frontend/services/location_service.dart';
import 'package:frontend/services/tts_service.dart';
import 'package:frontend/services/websocket_service.dart';

// ---------------------------------------------------------------------------
// Dark-mode Google Map styling JSON
// ---------------------------------------------------------------------------
const _darkMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#121212"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#212121"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#757575"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#bdbdbd"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#181818"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#2c2c2c"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#8a8a8a"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#373737"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3c3c3c"}]},
  {"featureType":"road.highway.controlled_access","elementType":"geometry","stylers":[{"color":"#4e4e4e"}]},
  {"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},
  {"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#000000"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3d3d3d"}]}
]''';

// ---------------------------------------------------------------------------
// MapScreen
// ---------------------------------------------------------------------------
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {

  GoogleMapController? _mapController;
  StreamSubscription<Position>? _locationSub;
  Position? _myPosition;

  // Live HUD values
  double _speedKmh = 0.0;
  double _bearingDeg = 0.0;

  // Warning banner animation controller
  late AnimationController _bannerController;
  late Animation<Color?> _bannerColor;
  bool _anomalyActive = false;

  final WebSocketService _ws = WebSocketService();

  @override
  void initState() {
    super.initState();

    // Set up pulsing animation for the warning banner
    _bannerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _bannerColor = ColorTween(
      begin: const Color(0xFF2C2C2C),
      end: ConvoyTheme.primary,
    ).animate(CurvedAnimation(parent: _bannerController, curve: Curves.easeInOut));

    TtsService.instance.initialize();
    _startLocationTracking();
    _attachWebSocketCallbacks();
  }

  // --------------------------------------------------------------------------
  // Location tracking
  // --------------------------------------------------------------------------
  void _startLocationTracking() {
    _locationSub = LocationService.instance.streamLocation().listen(
      (position) {
        if (!mounted) return;
        setState(() {
          _myPosition = position;
          _speedKmh = (position.speed * 3.6).clamp(0.0, 999.0); // m/s → km/h
          _bearingDeg = position.heading.clamp(0.0, 360.0);
        });

        // Smoothly follow device position on the map
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(position.latitude, position.longitude),
          ),
        );

        // Send live telemetry to backend via WebSocket
        final lobby = ref.read(lobbyProvider);
        if (lobby.activeConvoyId != null) {
          _ws.streamTelemetry(
            latitude: position.latitude,
            longitude: position.longitude,
            speed: position.speed,
            bearing: position.heading,
          );
        }
      },
      onError: (e) => print('Location stream error in map screen: $e'),
    );
  }

  // --------------------------------------------------------------------------
  // WebSocket callbacks
  // --------------------------------------------------------------------------
  void _attachWebSocketCallbacks() {
    _ws.setAiAlertCallback((String alertText) {
      if (!mounted) return;
      ref.read(telemetryProvider.notifier).addAlert(alertText);
      _triggerAnomalyBanner();
      TtsService.instance.speak(alertText);
    });
  }

  void _triggerAnomalyBanner() {
    if (!mounted) return;
    setState(() => _anomalyActive = true);
    _bannerController.repeat(reverse: true);
  }

  void _clearAnomalyBanner() {
    if (!mounted) return;
    _bannerController.stop();
    _bannerController.reset();
    setState(() => _anomalyActive = false);
  }

  // --------------------------------------------------------------------------
  // Simulate anomaly — manual dev trigger
  // --------------------------------------------------------------------------
  void _simulateAnomaly() {
    const mockAlert =
        'Alert: follower has deviated over one hundred meters from the convoy route. '
        'Shell Gas Station is located two miles ahead on your current bearing. Regroup now.';
    ref.read(telemetryProvider.notifier).addAlert(mockAlert);

    // Inject a mock telemetry packet with wrong_turn: true
    ref.read(telemetryProvider.notifier).updateRiderTelemetry({
      'profile_id': 'mock-follower-001',
      'latitude': _myPosition?.latitude ?? 0.0,
      'longitude': _myPosition?.longitude ?? 0.0,
      'speed': 40.0,
      'bearing': 220.0,
      'timestamp': DateTime.now().toIso8601String(),
      'metrics': {
        'distance_to_leader_km': 1.72,
        'cross_track_error_meters': 130.5,
        'road_bearing': 90.0,
      },
      'flags': {
        'distance_exceeded': false,
        'wrong_turn': true,
      },
    });

    _triggerAnomalyBanner();
    TtsService.instance.speak(mockAlert);
  }

  // --------------------------------------------------------------------------
  // Build markers from live telemetry state
  // --------------------------------------------------------------------------
  Set<Marker> _buildMarkers(TelemetryState telemetry) {
    final markers = <Marker>{};

    // My own position marker (vivid orange)
    if (_myPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('me'),
        position: LatLng(_myPosition!.latitude, _myPosition!.longitude),
        infoWindow: const InfoWindow(title: 'You (Leader)'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ));
    }

    // Remote rider markers (one per live telemetry record)
    for (final entry in telemetry.activeRiders.entries) {
      final rider = entry.value;
      final isAnomalous = rider.wrongTurn || rider.distanceExceeded;

      markers.add(Marker(
        markerId: MarkerId(rider.profileId),
        position: LatLng(rider.latitude, rider.longitude),
        infoWindow: InfoWindow(
          title: 'Rider ${rider.profileId.substring(0, 8)}',
          snippet: isAnomalous ? '⚠ Anomaly detected' : 'OK — ${rider.distanceToLeaderKm.toStringAsFixed(2)} km',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          isAnomalous ? BitmapDescriptor.hueRed : BitmapDescriptor.hueAzure,
        ),
      ));
    }

    return markers;
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _bannerController.dispose();
    _ws.disconnect();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final telemetry = ref.watch(telemetryProvider);
    final lobby = ref.watch(lobbyProvider);

    // Evaluate overall anomaly flag from any active rider packet
    final anyAnomalyFlag = telemetry.activeRiders.values.any(
      (r) => r.wrongTurn || r.distanceExceeded,
    );
    if (anyAnomalyFlag && !_anomalyActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _triggerAnomalyBanner());
    } else if (!anyAnomalyFlag && _anomalyActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _clearAnomalyBanner());
    }

    // Aggregate HUD distance metric from the most critical (furthest) rider
    double maxDistKm = 0.0;
    double maxCteMeters = 0.0;
    for (final r in telemetry.activeRiders.values) {
      if (r.distanceToLeaderKm > maxDistKm) maxDistKm = r.distanceToLeaderKm;
      if (r.crossTrackErrorMeters > maxCteMeters) maxCteMeters = r.crossTrackErrorMeters;
    }

    final initialCamera = CameraPosition(
      target: _myPosition != null
          ? LatLng(_myPosition!.latitude, _myPosition!.longitude)
          : const LatLng(28.6139, 77.2090), // Default: New Delhi
      zoom: 16.0,
    );

    return Scaffold(
      backgroundColor: ConvoyTheme.background,
      appBar: AppBar(
        backgroundColor: ConvoyTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: ConvoyTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lobby.activeConvoyCode != null
                  ? 'Convoy · ${lobby.activeConvoyCode}'
                  : 'Live Map',
              style: const TextStyle(
                color: ConvoyTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              lobby.role == 'leader' ? '🔶 You are the Leader' : '🔵 Following convoy',
              style: const TextStyle(
                color: ConvoyTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: ConvoyTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ConvoyTheme.primary.withOpacity(0.5)),
                ),
                child: Text(
                  '${telemetry.activeRiders.length} rider${telemetry.activeRiders.length != 1 ? 's' : ''} live',
                  style: const TextStyle(
                    color: ConvoyTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),

      body: Stack(
        children: [
          // ----------------------------------------------------------------
          // 1. Google Map Canvas
          // ----------------------------------------------------------------
          GoogleMap(
            initialCameraPosition: initialCamera,
            mapType: MapType.normal,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            markers: _buildMarkers(telemetry),
            onMapCreated: (controller) async {
              _mapController = controller;
              try {
                await controller.setMapStyle(_darkMapStyle);
              } catch (e) {
                print('Failed to apply dark map style: $e');
              }
            },
          ),

          // ----------------------------------------------------------------
          // 2. Bottom HUD Glass Overlay
          // ----------------------------------------------------------------
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xF0121212), // 94% opacity charcoal
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 3,
                      decoration: BoxDecoration(
                        color: ConvoyTheme.textSecondary.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // --------------------------------------------------------
                  // 3. Anomaly warning banner
                  // --------------------------------------------------------
                  AnimatedBuilder(
                    animation: _bannerController,
                    builder: (context, child) {
                      final isAnomalyState = _anomalyActive;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: isAnomalyState
                              ? (_bannerColor.value ?? const Color(0xFF2C2C2C))
                              : const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isAnomalyState
                                ? ConvoyTheme.primary
                                : const Color(0xFF333333),
                            width: isAnomalyState ? 1.5 : 1.0,
                          ),
                        ),
                        child: isAnomalyState
                            ? const Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      color: Colors.white, size: 20),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'ALERT: WRONG TURN DETECTED — AI ASSISTANT VOCALIZING REGROUP INSTRUCTIONS',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : const Row(
                                children: [
                                  Icon(Icons.check_circle_outline,
                                      color: ConvoyTheme.textSecondary, size: 18),
                                  SizedBox(width: 10),
                                  Text(
                                    'All riders nominal — convoy synced',
                                    style: TextStyle(
                                      color: ConvoyTheme.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                      );
                    },
                  ),

                  // --------------------------------------------------------
                  // Live metric counters row
                  // --------------------------------------------------------
                  Row(
                    children: [
                      _buildHudMetric(
                        label: 'SPEED',
                        value: '${_speedKmh.toStringAsFixed(0)} km/h',
                        icon: Icons.speed,
                        highlighted: false,
                      ),
                      const SizedBox(width: 12),
                      _buildHudMetric(
                        label: 'DIST TO LEAD',
                        value: maxDistKm > 0
                            ? '${maxDistKm.toStringAsFixed(2)} km'
                            : '—',
                        icon: Icons.social_distance_outlined,
                        highlighted: maxDistKm > 1.5,
                      ),
                      const SizedBox(width: 12),
                      _buildHudMetric(
                        label: 'CROSS-TRACK',
                        value: maxCteMeters > 0
                            ? '${maxCteMeters.toStringAsFixed(0)} m'
                            : '—',
                        icon: Icons.alt_route_outlined,
                        highlighted: maxCteMeters > 100.0,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // --------------------------------------------------------
                  // 4. Simulate Anomaly test button
                  // --------------------------------------------------------
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _simulateAnomaly,
                          icon: const Icon(Icons.science_outlined,
                              size: 16, color: ConvoyTheme.primary),
                          label: const Text(
                            'Simulate Anomaly',
                            style: TextStyle(
                                color: ConvoyTheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: ConvoyTheme.primary),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      if (_anomalyActive) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ref.read(telemetryProvider.notifier).clearTelemetry();
                              _clearAnomalyBanner();
                              TtsService.instance.stop();
                            },
                            icon: const Icon(Icons.check,
                                size: 16, color: Colors.green),
                            label: const Text(
                              'Clear Alert',
                              style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.green),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // HUD metric tile
  // --------------------------------------------------------------------------
  Widget _buildHudMetric({
    required String label,
    required String value,
    required IconData icon,
    required bool highlighted,
  }) {
    final accentColor = highlighted ? ConvoyTheme.primary : ConvoyTheme.textSecondary;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: highlighted
              ? ConvoyTheme.primary.withOpacity(0.08)
              : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: highlighted
                ? ConvoyTheme.primary.withOpacity(0.4)
                : const Color(0xFF2C2C2C),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: accentColor),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: highlighted ? ConvoyTheme.primary : ConvoyTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
