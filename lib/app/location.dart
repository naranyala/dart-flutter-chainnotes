import 'package:geolocator/geolocator.dart';

/// The one seam between the Map Explorer and the platform location stack.
///
/// `MapSession` talks only to this interface; production uses
/// `GeolocatorQuery`, tests inject a scripted fake. Wrapping the static
/// `Geolocator` API (which has no injectable instance) keeps the denied,
/// disabled, and success paths unit-testable without a device.
abstract class LocationQuery {
  Future<bool> serviceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<Position> currentPosition();
}

class GeolocatorQuery implements LocationQuery {
  const GeolocatorQuery();

  @override
  Future<bool> serviceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() =>
      Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<Position> currentPosition() => Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.low),
      );
}
