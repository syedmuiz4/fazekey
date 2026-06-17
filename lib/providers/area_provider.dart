import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/command_center_options.dart';
import '../models/area.dart';
import '../services/firebase_service.dart';

class AreaProvider extends ChangeNotifier {
  AreaProvider(this._firebase);
  final FirebaseService _firebase;
  StreamSubscription<List<Area>>? _sub;
  List<Area> areas = [];
  bool loading = false;
  String? error;
  bool _sampleAreasRequested = false;

  void listen() {
    if (!_sampleAreasRequested) {
      _sampleAreasRequested = true;
      _firebase.ensureSampleAreas().catchError((e) {
        error = e.toString();
        notifyListeners();
      });
    }
    _sub ??= _firebase.watchAreas().listen(
      (value) {
        areas = _presentationAreas(value);
        notifyListeners();
      },
      onError: (e) {
        error = e.toString();
        notifyListeners();
      },
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    areas = [];
    error = null;
    notifyListeners();
  }

  Future<void> addArea(Area area) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _firebase.addArea(area);
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> updateArea(Area area) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _firebase.updateArea(area);
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> deleteArea(String id) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _firebase.deleteArea(id);
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    _sub?.cancel();
    _sub = null;
    listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  List<Area> _presentationAreas(List<Area> firestoreAreas) {
    final byId = {for (final area in firestoreAreas) area.id: area};
    final commandRooms = commandCenterAreas.entries.map((entry) {
      final area = byId[entry.key] ?? entry.value;
      return area.copyWith(location: 'FSKTM');
    }).toList();
    final extras = firestoreAreas
        .where((area) => !commandCenterAreas.containsKey(area.id))
        .where((area) => !_isLegacyDuplicateRoom(area))
        .map((area) => area.copyWith(location: 'FSKTM'));
    final cleanRooms = <Area>[];
    final seen = <String>{};
    for (final area in [...commandRooms, ...extras]) {
      final key = _roomIdentity(area);
      if (key.isNotEmpty && !seen.add(key)) continue;
      cleanRooms.add(area);
    }
    return cleanRooms;
  }

  bool _isLegacyDuplicateRoom(Area area) {
    final id = area.id.trim().toLowerCase();
    final name = area.name.trim().toLowerCase();
    final roomNumber = area.roomNumber.trim().toLowerCase();
    return id == 'server_room' ||
        name == 'server room' ||
        name == 'nco network operations' ||
        roomNumber == 'sr-01';
  }

  String _roomIdentity(Area area) {
    final roomNumber = area.roomNumber.trim();
    if (roomNumber.isNotEmpty) return _accessKey(roomNumber);
    return _accessKey('${area.floor} ${area.name}');
  }

  String _accessKey(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
}
