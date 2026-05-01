import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/area.dart';
import '../providers/area_provider.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/primary_button.dart';

class AddAreaScreen extends StatefulWidget {
  const AddAreaScreen({super.key});
  static const route = '/add-area';

  @override
  State<AddAreaScreen> createState() => _AddAreaScreenState();
}

class _AddAreaScreenState extends State<AddAreaScreen> {
  final _form = GlobalKey<FormState>();

  String _location = _locations.first;
  String _floor = _floors.first;
  String _room = _rooms.first;
  String _department = _departments.first;
  String _role = _roles.first;
  int _capacity = _capacities[2];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AreaProvider>();
    final areaName = '$_floor - Room $_room';
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Add Area'), backgroundColor: Colors.transparent),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            GlassCard(
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      areaName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Structured area profile',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 18),
                    DropdownButtonFormField<String>(
                      initialValue: _location,
                      decoration: const InputDecoration(labelText: 'Location'),
                      items: _locations.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                      onChanged: (value) => setState(() => _location = value ?? _location),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _floor,
                      decoration: const InputDecoration(labelText: 'Floor'),
                      items: _floors.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                      onChanged: (value) => setState(() => _floor = value ?? _floor),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _room,
                      decoration: const InputDecoration(labelText: 'Room'),
                      items: _rooms.map((value) => DropdownMenuItem(value: value, child: Text('Room $value'))).toList(),
                      onChanged: (value) => setState(() => _room = value ?? _room),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _department,
                      decoration: const InputDecoration(labelText: 'Department'),
                      items: _departments.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                      onChanged: (value) => setState(() => _department = value ?? _department),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _role,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: _roles.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                      onChanged: (value) => setState(() => _role = value ?? _role),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _capacity,
                      decoration: const InputDecoration(labelText: 'Occupancy capacity'),
                      items: _capacities.map((value) => DropdownMenuItem(value: value, child: Text(value.toString()))).toList(),
                      onChanged: (value) => setState(() => _capacity = value ?? _capacity),
                    ),
                    if (provider.error != null) ...[
                      const SizedBox(height: 12),
                      Text(provider.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: 'Save Area',
                      loading: provider.loading,
                      icon: Icons.save_rounded,
                      onPressed: () async {
                        if (!_form.currentState!.validate()) return;
                        await context.read<AreaProvider>().addArea(
                              Area(
                                id: '',
                                name: areaName,
                                location: _location,
                                floor: _floor,
                                roomNumber: _room,
                                active: true,
                                createdAt: DateTime.now(),
                                allowedDepartments: [_department],
                                allowedRoles: [_role],
                                currentOccupancy: 0,
                                capacity: _capacity,
                              ),
                            );
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _locations = ['FSKTM'];
  static const _floors = ['Level 1', 'Level 2', 'Level 3'];
  static const _rooms = ['31', '32', '33', '34', '35', '36'];
  static const _departments = ['Software Engineering', 'Information Security', 'Multimedia'];
  static const _roles = ['Admin', 'Security', 'Staff'];
  static const _capacities = [10, 25, 50, 75, 100];
}
