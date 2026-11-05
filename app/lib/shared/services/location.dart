import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// A position as the backend takes it (`LocationDto`).
class LatLng {
  const LatLng(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  Map<String, dynamic> get json => {'latitude': latitude, 'longitude': longitude};
}

/// What the phone lets the app do with its position, as the pro space shows it.
enum LocationAccess {
  /// Never asked, or refused once: the app may still ask.
  askable,

  /// Granted (while in use or always).
  granted,

  /// Refused for good, or location turned off: only the system settings can change it.
  blocked,
}

/// The phone's position, for "Près de moi". Never throws: location off,
/// permission refused or no fix in time all come back as null, and the caller
/// carries on without a position — the city still matches.
class LocationService {
  const LocationService();

  /// One lookup at a time: a launch and a resume landing together share it,
  /// instead of stacking two system requests.
  static Future<LatLng?>? _inFlight;

  Future<LocationAccess> access() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.blocked;
      return switch (await Geolocator.checkPermission()) {
        LocationPermission.always || LocationPermission.whileInUse => LocationAccess.granted,
        LocationPermission.deniedForever => LocationAccess.blocked,
        _ => LocationAccess.askable,
      };
    } catch (_) {
      return LocationAccess.blocked;
    }
  }

  /// Where the member can turn it back on: the phone's location settings when
  /// location is off altogether, otherwise the app's own permissions page.
  Future<void> openSettings() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (_) {}
  }

  /// [prompt] lets the system ask for permission. Only pass it when the
  /// member just acted (sending a request, turning sharing on), so the
  /// question never comes out of nowhere.
  Future<LatLng?> current({bool prompt = true}) => _inFlight ??= _lookup(prompt).whenComplete(() => _inFlight = null);

  Future<LatLng?> _lookup(bool prompt) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && prompt) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }
      // A neighbourhood is all matching needs; a last known fix saves the wait.
      final last = await Geolocator.getLastKnownPosition(forceAndroidLocationManager: Platform.isAndroid);
      if (last != null && DateTime.now().difference(last.timestamp) < const Duration(minutes: 10)) {
        return LatLng(last.latitude, last.longitude);
      }
      try {
        final p = await Geolocator.getCurrentPosition(locationSettings: _settings);
        return LatLng(p.latitude, p.longitude);
      } catch (_) {
        // No fix in time: an hour-old position still places the pro in the
        // right neighbourhood.
        if (last != null && DateTime.now().difference(last.timestamp) < const Duration(hours: 1)) {
          return LatLng(last.latitude, last.longitude);
        }
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// On Android, the plain LocationManager: Google's fused provider answers
  /// a missing "Location Accuracy" setting with a full-screen dialog of its
  /// own, one per lookup, which a neighbourhood-level position never needs.
  static LocationSettings get _settings {
    const limit = Duration(seconds: 10);
    if (Platform.isAndroid) {
      return AndroidSettings(accuracy: LocationAccuracy.medium, timeLimit: limit, forceLocationManager: true);
    }
    return const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: limit);
  }
}

/// Overridden in tests.
final locationServiceProvider = Provider<LocationService>((ref) => const LocationService());

/// A rounded distance as the backend sends it: "1,5 km", "9 km".
String formatKm(double km) {
  final whole = km == km.roundToDouble();
  return '${whole ? km.round().toString() : km.toStringAsFixed(1).replaceAll('.', ',')} km';
}
