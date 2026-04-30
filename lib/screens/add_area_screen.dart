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
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _floor = TextEditingController();
  final _room = TextEditingController();
  final _departments = TextEditingController();
  final _roles = TextEditingController(text: 'admin, security');
  final _capacity = TextEditingController(text: '0');

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _floor.dispose();
    _room.dispose();
    _departments.dispose();
    _roles.dispose();
    _capacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AreaProvider>();
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
                  children: [
                    TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Area name'), validator: _required),
                    const SizedBox(height: 12),
                    TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'Location'), validator: _required),
                    const SizedBox(height: 12),
                    TextFormField(controller: _floor, decoration: const InputDecoration(labelText: 'Floor'), validator: _required),
                    const SizedBox(height: 12),
                    TextFormField(controller: _room, decoration: const InputDecoration(labelText: 'Room number'), validator: _required),
                    const SizedBox(height: 12),
                    TextFormField(controller: _departments, decoration: const InputDecoration(labelText: 'Allowed departments', hintText: 'IT, Security')),
                    const SizedBox(height: 12),
                    TextFormField(controller: _roles, decoration: const InputDecoration(labelText: 'Allowed roles', hintText: 'admin, security, staff')),
                    const SizedBox(height: 12),
                    TextFormField(controller: _capacity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Occupancy capacity'), validator: _number),
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
                                name: _name.text.trim(),
                                location: _location.text.trim(),
                                floor: _floor.text.trim(),
                                roomNumber: _room.text.trim(),
                                active: true,
                                createdAt: DateTime.now(),
                                allowedDepartments: _csv(_departments.text),
                                allowedRoles: _csv(_roles.text),
                                currentOccupancy: 0,
                                capacity: int.tryParse(_capacity.text.trim()) ?? 0,
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

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Required' : null;
  String? _number(String? value) => int.tryParse(value?.trim() ?? '') == null ? 'Enter a number' : null;
  List<String> _csv(String value) => value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}
