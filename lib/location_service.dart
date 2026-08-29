// WariMesh — where this phone is, so an alert can say where it came from.
//
// The governing rule here: an SOS must NEVER wait on a GPS fix. A cold fix
// can take 30+ seconds under tree cover or between buildings, and a person
// pressing an emergency button does not have 30 seconds. So this keeps a
// continuously-updated last-known position in memory, and sendAlert reads
// it instantly. A fresher fix, if one arrives while the alert is still on
// the air, is broadcast as a follow-up (see MeshService.sendAlert) — the
// alert goes out immediately either way.
//
// Everything degrades to null rather than throwing: location permission
// refused, GPS switched off, no fix yet. An alert with no coordinates is
// still a perfectly good alert.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  Position? _last;
  StreamSubscription<Position>? _sub;
  bool _started = false;

  /// The most recent fix, or null if we've never had one.
  Position? get lastKnown => _last;

  bool get hasFix => _last != null;

  /// Begins tracking. Safe to call more than once. Returns false if
  /// location is unavailable (denied, or the device's GPS is off) — the
  /// caller carries on without coordinates rather than treating it as
  /// fatal.
  Future<bool> start() async {
    if (_started) return _last != null;
    _started = true;

    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }

      // Seed from the OS's cached fix so an SOS in the first few seconds
      // after launch still carries a position, before our own stream has
      // produced anything.
      _last = await Geolocator.getLastKnownPosition();

      // A phone that has never had a fix (fresh install, or GPS just turned
      // on) has no cached position, so seeding above yields nothing and the
      // first SOS would go out blind. Kick off a real fix now rather than
      // waiting for the position stream's first update, which only fires
      // once the person has moved far enough to clear the distance filter.
      if (_last == null) unawaited(currentFix());

      _sub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              // Medium, not high, on purpose. High is GPS-only: indoors, in a
              // vehicle, or under dense cover it simply never fires, so the
              // stream stays silent exactly when a cached position would have
              // been better than nothing. Medium lets Android use the fused
              // network provider too, which resolves almost anywhere to within
              // a hundred metres or so — plenty to say which part of a crowd
              // to search, and the GPS fix supersedes it as soon as one lands.
              accuracy: LocationAccuracy.medium,
              // Someone walking the Wari covers 10m every few seconds. Updating
              // on distance rather than on a timer keeps the fix current while
              // they move and costs nothing while they're resting.
              distanceFilter: 10,
            ),
          ).listen(
            (p) => _last = p,
            onError: (Object e) =>
                debugPrint('WariMesh[Location] stream error: $e'),
          );

      return true;
    } catch (e) {
      debugPrint('WariMesh[Location] unavailable: $e');
      return false;
    }
  }

  /// One fresh fix, giving up after [timeout]. Used to improve on the
  /// cached position just after an SOS goes out — never to gate it.
  Future<Position?> currentFix({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    // Two attempts, deliberately. A high-accuracy request is GPS-only, and
    // GPS indoors or under dense tree cover frequently never fixes at all —
    // it just times out and yields nothing. Falling back to reduced
    // accuracy lets Android use the fused/network provider, which resolves
    // in seconds almost anywhere. A position good to a hundred metres tells
    // a responder which part of a crowd to search; no position tells them
    // nothing, so a coarse fix always beats holding out for a precise one.
    for (final accuracy in [LocationAccuracy.high, LocationAccuracy.medium]) {
      try {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: accuracy,
            timeLimit: timeout,
          ),
        );
        _last = p;
        return p;
      } catch (e) {
        debugPrint('WariMesh[Location] no fix at $accuracy: $e');
      }
    }

    // Last resort: whatever the OS already had lying around, however old.
    // Another app (Maps, the weather widget) may have fixed a position
    // minutes ago even though we can't get one right now. For someone
    // walking, a fix from a few minutes back still puts a searcher within
    // a few hundred metres — far better than telling them nothing at all.
    try {
      final cached = await Geolocator.getLastKnownPosition();
      if (cached != null) {
        _last = cached;
        debugPrint(
          'WariMesh[Location] falling back to a cached fix from ${cached.timestamp}',
        );
        return cached;
      }
    } catch (e) {
      debugPrint('WariMesh[Location] no cached fix either: $e');
    }

    debugPrint(
      'WariMesh[Location] no position available at all — likely indoors with no cached fix',
    );
    return null;
  }

  /// Metres between two coordinates.
  static double distanceBetween(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) => Geolocator.distanceBetween(lat1, lon1, lat2, lon2);

  /// Compass bearing from the first coordinate to the second, in degrees.
  static double bearingBetween(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) => Geolocator.bearingBetween(lat1, lon1, lat2, lon2);

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
