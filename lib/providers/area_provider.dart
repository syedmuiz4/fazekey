import 'dart:async';

import 'package:flutter/material.dart';

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
        areas = value;
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
}
