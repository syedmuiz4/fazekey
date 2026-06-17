import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/command_center_options.dart';
import '../models/area.dart';
import '../providers/area_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';

class AddAreaScreen extends StatefulWidget {
  const AddAreaScreen({super.key});
  static const route = '/add-area';

  @override
  State<AddAreaScreen> createState() => _AddAreaScreenState();
}

class _AddAreaScreenState extends State<AddAreaScreen> {
  final _form = GlobalKey<FormState>();
  final List<_RoomDraft> _drafts = [_RoomDraft()];

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.loading && auth.user == null) {
      return const AppBackground(
        child: Scaffold(
          backgroundColor: AppBackground.slateGray,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (!auth.isAdmin) {
      return const AppBackground(
        child: Scaffold(
          backgroundColor: AppBackground.slateGray,
          body: Center(child: Text('Management access is unavailable.')),
        ),
      );
    }
    final provider = context.watch<AreaProvider>();
    return AppBackground(
      child: Scaffold(
        backgroundColor: AppBackground.slateGray,
        appBar: AppBar(
          title: const Text('Add Rooms'),
          backgroundColor: AppBackground.slateGray,
          actions: [
            IconButton(
              tooltip: 'Add another room',
              onPressed: provider.loading ? null : _addDraft,
              icon: const Icon(Icons.playlist_add_rounded),
            ),
          ],
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const _AddRoomsHeader(),
              const SizedBox(height: 12),
              for (var i = 0; i < _drafts.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RoomDraftCard(
                    index: i,
                    draft: _drafts[i],
                    canRemove: _drafts.length > 1,
                    onRemove: () => _removeDraft(i),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: provider.loading ? null : _addDraft,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Another Room'),
              ),
              if (provider.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  provider.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: provider.loading ? null : _saveAll,
                icon: provider.loading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  provider.loading
                      ? 'Saving'
                      : 'Save ${_drafts.length} Room${_drafts.length == 1 ? '' : 's'}',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addDraft() {
    setState(() => _drafts.add(_RoomDraft()));
  }

  void _removeDraft(int index) {
    if (_drafts.length == 1) return;
    final draft = _drafts.removeAt(index);
    draft.dispose();
    setState(() {});
  }

  Future<void> _saveAll() async {
    if (!_form.currentState!.validate()) return;
    final provider = context.read<AreaProvider>();
    for (final draft in List<_RoomDraft>.of(_drafts)) {
      await provider.addArea(draft.toArea());
      if (provider.error != null) break;
    }
    if (!mounted || provider.error != null) return;
    final count = _drafts.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$count room${count == 1 ? '' : 's'} added to Room Control.',
        ),
      ),
    );
    Navigator.pop(context);
  }

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  static String? _capacityValidator(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 0) return 'Enter a valid capacity';
    return null;
  }
}

class _AddRoomsHeader extends StatelessWidget {
  const _AddRoomsHeader();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Batch Room Creation',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Add one or many room profiles before saving them to Firestore.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomDraft {
  final name = TextEditingController();
  final code = TextEditingController();
  final floor = TextEditingController();
  final capacity = TextEditingController(text: '25');
  String floorChoice = commandCenterFloorOptions.first;
  String department = commandCenterDepartments.first;
  final Set<String> roles = {'Student', 'Staff'};

  Area toArea() {
    final roomName = name.text.trim();
    final floorLabel = floorChoice == 'Other...'
        ? floor.text.trim()
        : floorChoice;
    return Area(
      id: '',
      name: roomName,
      location: 'FSKTM',
      floor: floorLabel,
      roomNumber: code.text.trim(),
      active: true,
      createdAt: DateTime.now(),
      allowedDepartments: [department],
      allowedRoles: roles.toList(),
      currentOccupancy: 0,
      capacity: int.tryParse(capacity.text.trim()) ?? 0,
    );
  }

  void dispose() {
    name.dispose();
    code.dispose();
    floor.dispose();
    capacity.dispose();
  }
}

class _RoomDraftCard extends StatefulWidget {
  const _RoomDraftCard({
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.onRemove,
  });

  final int index;
  final _RoomDraft draft;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  State<_RoomDraftCard> createState() => _RoomDraftCardState();
}

class _RoomDraftCardState extends State<_RoomDraftCard> {
  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Room ${widget.index + 1}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (widget.canRemove)
                IconButton(
                  tooltip: 'Remove room',
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_rounded),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: draft.name,
            decoration: const InputDecoration(
              labelText: 'Room Name',
              prefixIcon: Icon(Icons.meeting_room_rounded),
            ),
            validator: _AddAreaScreenState._required,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: draft.code,
            decoration: const InputDecoration(
              labelText: 'Room Code',
              hintText: 'Example: SR-1',
              prefixIcon: Icon(Icons.tag_rounded),
            ),
            textCapitalization: TextCapitalization.characters,
            validator: _AddAreaScreenState._required,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: draft.floorChoice,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Floor Label',
              prefixIcon: Icon(Icons.layers_rounded),
            ),
            items: commandCenterFloorOptions
                .map(
                  (floor) => DropdownMenuItem(value: floor, child: Text(floor)),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => draft.floorChoice = value);
            },
          ),
          if (draft.floorChoice == 'Other...') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: draft.floor,
              decoration: const InputDecoration(
                labelText: 'Custom Floor Label',
                prefixIcon: Icon(Icons.edit_location_alt_rounded),
              ),
              validator: _AddAreaScreenState._required,
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: draft.capacity,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Capacity',
              prefixIcon: Icon(Icons.groups_rounded),
            ),
            validator: _AddAreaScreenState._capacityValidator,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: draft.department,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Department',
              prefixIcon: Icon(Icons.school_rounded),
            ),
            items: commandCenterDepartments
                .map(
                  (department) => DropdownMenuItem(
                    value: department,
                    child: Text(
                      department,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => draft.department = value);
            },
          ),
          const SizedBox(height: 12),
          _RolePolicySelector(
            selected: draft.roles,
            onChanged: (roles) {
              setState(() {
                draft.roles
                  ..clear()
                  ..addAll(roles);
              });
            },
          ),
        ],
      ),
    );
  }
}

class _RolePolicySelector extends StatelessWidget {
  const _RolePolicySelector({required this.selected, required this.onChanged});

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Role Policy',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              selected: selected.contains('Student'),
              avatar: const Icon(Icons.school_rounded),
              label: const Text('Students'),
              onSelected: (value) => _toggle('Student', value),
            ),
            FilterChip(
              selected: selected.contains('Staff'),
              avatar: const Icon(Icons.work_rounded),
              label: const Text('Staff'),
              onSelected: (value) => _toggle('Staff', value),
            ),
            FilterChip(
              selected: selected.contains('Admin'),
              avatar: const Icon(Icons.admin_panel_settings_rounded),
              label: const Text('Admins'),
              onSelected: (value) => _toggle('Admin', value),
            ),
          ],
        ),
      ],
    );
  }

  void _toggle(String role, bool selectedValue) {
    final next = {...selected}..remove(role);
    if (selectedValue) next.add(role);
    onChanged(next);
  }
}
