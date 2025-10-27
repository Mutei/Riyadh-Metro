// lib/services/app_bus.dart
import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Event fired when the bot asks the map to focus on a single station.
class FocusStationEvent {
  final LatLng ll;
  final double? zoom;
  final bool pulse;
  FocusStationEvent(this.ll, {this.zoom, this.pulse = false});
}

/// Event fired when the bot requests a route between two stations.
class RouteRequestEvent {
  final LatLng from;
  final LatLng to;
  RouteRequestEvent({required this.from, required this.to});
}

/// Global event bus to communicate between pages (e.g. ChatBot → MainScreen)
class AppBus {
  AppBus._();
  static final AppBus I = AppBus._();

  /// The broadcast stream controller.
  final _controller = StreamController<Object>.broadcast();

  /// Emit a new event.
  void emit(Object event) => _controller.add(event);

  /// Listen for a specific event type.
  StreamSubscription<T> on<T>(void Function(T e) handler) {
    return _controller.stream.where((e) => e is T).cast<T>().listen(handler);
  }

  /// Optional: raw stream access
  Stream<Object> get stream => _controller.stream;
}
