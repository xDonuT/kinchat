import 'package:flutter/material.dart';

import '../models/duel.dart';

Future<(String, String)?> showDuelClassPicker(BuildContext context) {
  return showDialog<(String, String)>(
    context: context,
    builder: (context) => const _DuelClassPickerDialog(),
  );
}

class _DuelClassPickerDialog extends StatefulWidget {
  const _DuelClassPickerDialog();

  @override
  State<_DuelClassPickerDialog> createState() => _DuelClassPickerDialogState();
}

class _DuelClassPickerDialogState extends State<_DuelClassPickerDialog> {
  String _myClass = defaultDuelClassId;
  String _opponentClass = 'ninja';

  @override
  Widget build(BuildContext context) {
    final classes = duelClasses.values.toList(growable: false);
    final scheme = Theme.of(context).colorScheme;
    final hintStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);

    return AlertDialog(
      title: const Text('Choose duel classes'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ClassDropdown(
              label: 'Your class',
              value: _myClass,
              classes: classes,
              onChanged: (value) => setState(() => _myClass = value),
            ),
            const SizedBox(height: 4),
            Text(duelClasses[_myClass]?.description ?? '', style: hintStyle),
            const SizedBox(height: 16),
            _ClassDropdown(
              label: "Opponent's class",
              value: _opponentClass,
              classes: classes,
              onChanged: (value) => setState(() => _opponentClass = value),
            ),
            const SizedBox(height: 4),
            Text(
              duelClasses[_opponentClass]?.description ?? '',
              style: hintStyle,
            ),
            const SizedBox(height: 16),
            Text('The inviter picks both classes for now.', style: hintStyle),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(context).pop((_myClass, _opponentClass)),
          icon: const Icon(Icons.sports_esports),
          label: const Text('Start duel'),
        ),
      ],
    );
  }
}

class _ClassDropdown extends StatelessWidget {
  const _ClassDropdown({
    required this.label,
    required this.value,
    required this.classes,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<DuelClass> classes;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          items: [
            for (final duelClass in classes)
              DropdownMenuItem<String>(
                value: duelClass.id,
                child: Text(duelClass.name),
              ),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}
