import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Linked Rooms'),
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              tooltip: 'Add row',
              onPressed: _addDraft,
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
                onPressed: _addDraft,
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
                label: Text(provider.loading ? 'Saving' : 'Save Changes'),
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
    final draft = _drafts.removeAt(index);
    draft.dispose();
    setState(() {});
  }

  Future<void> _saveAll() async {
    if (!_form.currentState!.validate()) return;
    final provider = context.read<AreaProvider>();
    for (final draft in _drafts) {
      await provider.addArea(draft.toArea());
      if (provider.error != null) break;
    }
    if (!mounted || provider.error != null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_drafts.length} room assets saved.')),
    );
    Navigator.pop(context);
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
            'Linked Rooms',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Register multiple linked room profiles in one save operation.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
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
  int get index => widget.index;
  _RoomDraft get draft => widget.draft;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Room Profile ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Remove room profile',
                onPressed: widget.canRemove ? widget.onRemove : null,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: draft.location,
            decoration: const InputDecoration(labelText: 'Location'),
            validator: _required,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: draft.floor,
                  decoration: const InputDecoration(labelText: 'Floor'),
                  validator: _required,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: draft.room,
                  decoration: const InputDecoration(labelText: 'Room'),
                  validator: _required,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: draft.capacity,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Occupancy Capacity'),
            validator: _capacityValidator,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: draft.department,
            decoration: const InputDecoration(labelText: 'Department'),
            validator: _required,
          ),
          const SizedBox(height: 10),
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

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  static String? _capacityValidator(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 0) return 'Enter a valid capacity';
    return null;
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

class _RoomDraft {
  _RoomDraft();

  final location = TextEditingController(text: 'FSKTM');
  final floor = TextEditingController(text: 'Level 1');
  final room = TextEditingController();
  final capacity = TextEditingController(text: '25');
  final department = TextEditingController(text: 'Software Engineering');
  final roles = <String>{'Student'};

  Area toArea() {
    final floorValue = floor.text.trim();
    final roomValue = room.text.trim();
    return Area(
      id: '',
      name: '$floorValue - Room $roomValue',
      location: location.text.trim(),
      floor: floorValue,
      roomNumber: roomValue,
      active: true,
      createdAt: DateTime.now(),
      allowedDepartments: [department.text.trim()],
      allowedRoles: roles.toList(),
      currentOccupancy: 0,
      capacity: int.tryParse(capacity.text.trim()) ?? 0,
    );
  }

  void dispose() {
    location.dispose();
    floor.dispose();
    room.dispose();
    capacity.dispose();
    department.dispose();
  }
}
