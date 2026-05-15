import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/area.dart';
import '../providers/area_provider.dart';
import '../providers/auth_provider.dart';
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
  final _customLocation = TextEditingController();
  final _customFloor = TextEditingController();
  final _customRoom = TextEditingController();
  final _customDepartment = TextEditingController();
  final _customRole = TextEditingController();
  final _customCapacity = TextEditingController();
  final _locationFocus = FocusNode();
  final _floorFocus = FocusNode();
  final _roomFocus = FocusNode();
  final _departmentFocus = FocusNode();
  final _roleFocus = FocusNode();
  final _capacityFocus = FocusNode();

  String _location = _locations.first;
  String _floor = _floors.first;
  String _room = _rooms.first;
  String _department = _departments.first;
  String _role = _roles.first;
  String _capacity = _capacities[2].toString();

  @override
  void dispose() {
    _customLocation.dispose();
    _customFloor.dispose();
    _customRoom.dispose();
    _customDepartment.dispose();
    _customRole.dispose();
    _customCapacity.dispose();
    _locationFocus.dispose();
    _floorFocus.dispose();
    _roomFocus.dispose();
    _departmentFocus.dispose();
    _roleFocus.dispose();
    _capacityFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.loading && auth.user == null) {
      return const AppBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (!auth.isAdmin) {
      return const AppBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: Text('Management access is unavailable.')),
        ),
      );
    }
    final provider = context.watch<AreaProvider>();
    final location = _resolvedSelection(_location, _customLocation);
    final floor = _resolvedSelection(_floor, _customFloor);
    final room = _resolvedSelection(_room, _customRoom);
    final department = _resolvedSelection(_department, _customDepartment);
    final role = _resolvedSelection(_role, _customRole);
    final capacity =
        int.tryParse(_resolvedSelection(_capacity, _customCapacity)) ?? 0;
    final areaName = '$floor - Room $room';
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Add Room'),
          backgroundColor: Colors.transparent,
        ),
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
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Structured room profile',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _OtherDropdownField(
                      value: _location,
                      label: 'Location',
                      options: _locations,
                      customController: _customLocation,
                      customFocusNode: _locationFocus,
                      customLabel: 'Campus location',
                      onChanged: (value) => _selectOtherAware(
                        value,
                        _location,
                        _locationFocus,
                        (next) => _location = next,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _OtherDropdownField(
                      value: _floor,
                      label: 'Floor',
                      options: _floors,
                      customController: _customFloor,
                      customFocusNode: _floorFocus,
                      customLabel: 'Floor',
                      onChanged: (value) => _selectOtherAware(
                        value,
                        _floor,
                        _floorFocus,
                        (next) => _floor = next,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _OtherDropdownField(
                      value: _room,
                      label: 'Room',
                      options: _rooms,
                      displayBuilder: (value) => 'Room $value',
                      customController: _customRoom,
                      customFocusNode: _roomFocus,
                      customLabel: 'Room',
                      onChanged: (value) => _selectOtherAware(
                        value,
                        _room,
                        _roomFocus,
                        (next) => _room = next,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _OtherDropdownField(
                      value: _department,
                      label: 'Department',
                      options: _departments,
                      customController: _customDepartment,
                      customFocusNode: _departmentFocus,
                      customLabel: 'Campus department',
                      onChanged: (value) => _selectOtherAware(
                        value,
                        _department,
                        _departmentFocus,
                        (next) => _department = next,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _OtherDropdownField(
                      value: _role,
                      label: 'Role',
                      options: _roles,
                      customController: _customRole,
                      customFocusNode: _roleFocus,
                      customLabel: 'Role',
                      onChanged: (value) => _selectOtherAware(
                        value,
                        _role,
                        _roleFocus,
                        (next) => _role = next,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _OtherDropdownField(
                      value: _capacity,
                      label: 'Occupancy capacity',
                      options: _capacities.map((value) => '$value').toList(),
                      customController: _customCapacity,
                      customFocusNode: _capacityFocus,
                      customLabel: 'Occupancy capacity',
                      keyboardType: TextInputType.number,
                      customValidator: _capacityValidator,
                      onChanged: (value) => _selectOtherAware(
                        value,
                        _capacity,
                        _capacityFocus,
                        (next) => _capacity = next,
                      ),
                    ),
                    if (provider.error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        provider.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: 'Save Room',
                      loading: provider.loading,
                      icon: Icons.save_rounded,
                      onPressed: () async {
                        if (!_form.currentState!.validate()) return;
                        await context.read<AreaProvider>().addArea(
                          Area(
                            id: '',
                            name: areaName,
                            location: location,
                            floor: floor,
                            roomNumber: room,
                            active: true,
                            createdAt: DateTime.now(),
                            allowedDepartments: [department],
                            allowedRoles: [role],
                            currentOccupancy: 0,
                            capacity: capacity,
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
  static const _departments = [
    'Software Engineering',
    'Information Security',
    'Multimedia',
  ];
  static const _roles = ['Student', 'Admin', 'Staff'];
  static const _capacities = [10, 25, 50, 75, 100];

  String _resolvedSelection(String value, TextEditingController custom) {
    if (value != _OtherDropdownField.otherValue) return value.trim();
    return custom.text.trim();
  }

  void _selectOtherAware(
    String? value,
    String fallback,
    FocusNode focusNode,
    ValueChanged<String> assign,
  ) {
    final next = value ?? fallback;
    setState(() => assign(next));
    if (next == _OtherDropdownField.otherValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        focusNode.requestFocus();
      });
    }
  }

  String? _capacityValidator(String? value) {
    final capacity = int.tryParse(value?.trim() ?? '');
    if (capacity == null || capacity < 0) return 'Enter a valid capacity';
    return null;
  }
}

class _OtherDropdownField extends StatelessWidget {
  const _OtherDropdownField({
    required this.value,
    required this.label,
    required this.options,
    required this.customController,
    required this.customFocusNode,
    required this.customLabel,
    required this.onChanged,
    this.displayBuilder,
    this.keyboardType,
    this.customValidator,
  });

  static const otherValue = 'Other...';

  final String value;
  final String label;
  final List<String> options;
  final TextEditingController customController;
  final FocusNode customFocusNode;
  final String customLabel;
  final ValueChanged<String?> onChanged;
  final String Function(String value)? displayBuilder;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? customValidator;

  @override
  Widget build(BuildContext context) {
    final items = [...options, otherValue];
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          items: items
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(
                    item == otherValue
                        ? otherValue
                        : displayBuilder?.call(item) ?? item,
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
        if (value == otherValue) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: customController,
            focusNode: customFocusNode,
            keyboardType: keyboardType,
            decoration: InputDecoration(labelText: customLabel),
            validator:
                customValidator ??
                (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
          ),
        ],
      ],
    );
  }
}
