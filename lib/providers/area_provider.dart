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
        .map((area) => area.copyWith(location: 'FSKTM'));
    return [...commandRooms, ...extras];
  }
}
