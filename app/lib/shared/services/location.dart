import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// A position as the backend takes it (`LocationDto`).
class LatLng {
  const LatLng(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  Map<String, dynamic> get json => {'latitude': latitude, 'longitude': longitude};
}

/// The phone's position, for "Près de moi". Never throws: location off,
/// permission refused or no fix in time all come back as null, and the caller
/// carries on without a position — the city still matches.
class LocationService {
  const LocationService();

  Future<LatLng?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }
      // A neighbourhood is all matching needs; a last known fix saves the wait.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && DateTime.now().difference(last.timestamp) < const Duration(minutes: 10)) {
        return LatLng(last.latitude, last.longitude);
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return LatLng(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }
}

/// Overridden in tests.
final locationServiceProvider = Provider<LocationService>((ref) => const LocationService());

/// A rounded distance as the backend sends it: "1,5 km", "9 km".
String formatKm(double km) {
  final whole = km == km.roundToDouble();
  return '${whole ? km.round().toString() : km.toStringAsFixed(1).replaceAll('.', ',')} km';
}
