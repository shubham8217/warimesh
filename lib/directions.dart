// WariMesh — hands an alert's coordinates to a maps app for turn-by-turn
// walking directions.
//
// A distance and a compass word ("240 m, to your north-east") is enough to
// start moving, but in a crowd of a hundred thousand people, on unfamiliar
// ground, it is not enough to actually arrive. This closes that gap: the
// position that came off the mesh goes straight into navigation.
//
// Walking mode is hardcoded, deliberately. Everyone on the Wari is on foot,
// and driving directions would route a rescuer onto roads and away from the
// person they're trying to reach.
//
// Note this is the one part of WariMesh that wants the internet: Google
// Maps needs connectivity to fetch a route. That's an acceptable dependency
// precisely because it's optional — the alert, the coordinates and the
// distance all arrive over the mesh with no network at all, and this is
// simply an extra that works when there happens to be signal. If it fails,
// the coordinates are still on screen to read out or type in by hand.
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens walking directions to [latitude], [longitude].
///
/// Tries Google Maps' navigation intent first, which drops straight into
/// turn-by-turn. Falls back to the universal maps URL, which any installed
/// maps app — or a browser — can handle. Returns false only if nothing on
/// the phone could open either.
Future<bool> openWalkingDirections(double latitude, double longitude) async {
  final coords = '$latitude,$longitude';

  final candidates = <Uri>[
    // Turn-by-turn, walking. Android-specific and the best outcome.
    Uri.parse('google.navigation:q=$coords&mode=w'),
    // Universal fallback: the cross-platform Maps URL. Works through a
    // browser when no maps app is installed.
    Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$coords&travelmode=walking',
    ),
    // Last resort: a plain geo: pin. No route, but it at least shows the
    // place on a map, which beats nothing.
    Uri.parse('geo:$coords?q=$coords'),
  ];

  for (final uri in candidates) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (e) {
      // Deliberately not checking canLaunchUrl first: on Android 11+ it
      // returns false for anything missing from the manifest's <queries>,
      // and a false negative here would refuse to open a maps app that is
      // in fact installed. Trying and catching is the more reliable order.
      debugPrint('WariMesh[Directions] $uri failed: $e');
    }
  }
  return false;
}
