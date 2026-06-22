import 'package:geolocator/geolocator.dart';

class LocationService {
  static final LocationService instance = LocationService._internal();
  LocationService._internal();

  /// Requests permission and returns a continuous stream of device GPS positions.
  Stream<Position> streamLocation() async* {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled.');
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permission denied by user.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('Location permission permanently denied.');
        return;
      }
    } catch (e) {
      print('Error requesting location permission: $e');
      return;
    }

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5, // emit event every 5 meters of movement
    );

    yield* Geolocator.getPositionStream(locationSettings: locationSettings)
        .handleError((error) {
      print('Location stream error: $error');
    });
  }

  /// Returns a single last-known position — useful for an initial camera placement.
  Future<Position?> getLastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (e) {
      print('Error fetching last known position: $e');
      return null;
    }
  }
}
