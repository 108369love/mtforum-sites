import 'package:flutter/material.dart';

import 'glass_controls.dart';

import '../../data/models.dart';
import 'glass_dialog.dart';

/// 把站点要求的表单字段渲染成原生输入项，确认后返回提交值。
Future<Map<String, String>?> showSiteFormDialog(
  BuildContext context, {
  required String title,
  required List<MagicFormField> fields,
  String description = '',
  String confirmText = '确认',
}) {
  return showGlassDialog<Map<String, String>>(
    context: context,
    builder: (_) => _SiteFormDialog(
      title: title,
      fields: fields,
      description: description,
      confirmText: confirmText,
    ),
  );
}

class _SiteFormDialog extends StatefulWidget {
  const _SiteFormDialog({
    required this.title,
    required this.fields,
    required this.description,
    required this.confirmText,
  });

  final String title;
  final List<MagicFormField> fields;
  final String description;
  final String confirmText;

  @override
  State<_SiteFormDialog> createState() => _SiteFormDialogState();
}

class _SiteFormDialogState extends State<_SiteFormDialog> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _choices = {};

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      if (field.type == MagicFieldType.text || field.type == MagicFieldType.textarea) {
        _controllers[field.name] = TextEditingController(text: field.value);
      } else if (field.options.isNotEmpty) {
        _choices[field.name] = field.options
            .firstWhere((option) => option.value == field.value, orElse: () => field.options.first)
            .value;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final values = <String, String>{};
    for (final field in widget.fields) {
      if (field.type == MagicFieldType.text || field.type == MagicFieldType.textarea) {
        values[field.name] = _controllers[field.name]?.text.trim() ?? '';
      } else {
        values[field.name] = _choices[field.name] ?? field.value;
      }
    }
    Navigator.of(context).pop(values);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.description.isNotEmpty) ...[
              Text(
                widget.description,
                style: TextStyle(fontSize: 12, height: 1.45, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
            ],
            if (widget.fields.isEmpty)
              Text(
                '确认后立即提交到站点。',
                style: TextStyle(fontSize: 12.5, height: 1.5, color: scheme.onSurfaceVariant),
              ),
            for (final field in widget.fields) ...[
              if (field.label.isNotEmpty) ...[
                Text(
                  field.label,
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
              ],
              _fieldInput(field),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmText)),
      ],
    );
  }

  /// 选项值换成显示文案；值不在列表里时原样显示。
  String _labelOf(MagicFormField field, String value) {
    for (final option in field.options) {
      if (option.value == value) return option.label;
    }
    return value;
  }

  Widget _fieldInput(MagicFormField field) {
    switch (field.type) {
      case MagicFieldType.text:
        final numeric = field.name.contains('id') || field.name.contains('tid');
        return GlassField(
          controller: _controllers[field.name]!,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          textInputAction: TextInputAction.next,
          hintText: field.label.isEmpty ? field.name : field.label,
        );
      case MagicFieldType.textarea:
        return GlassField(
          controller: _controllers[field.name]!,
          maxLines: 3,
          hintText: field.label.isEmpty ? field.name : field.label,
        );
      case MagicFieldType.radio:
        final selected = _choices[field.name] ?? field.value;
        return GlassSegmented<String>(
          segments: [for (final option in field.options) (option.value, option.label)],
          value: selected,
          dense: true,
          expand: field.options.length <= 3,
          onChanged: (value) => setState(() => _choices[field.name] = value),
        );
      case MagicFieldType.select:
        final fallback = field.options.isEmpty ? '' : field.options.first.value;
        final selected = _choices[field.name] ?? (field.value.isEmpty ? fallback : field.value);
        return GlassSelectRow(
          value: _labelOf(field, selected),
          leading: Icons.list_alt_rounded,
          onTap: () async {
            final picked = await showGlassOptionSheet<String>(
              context,
              title: field.label.isEmpty ? field.name : field.label,
              options: [for (final option in field.options) (option.value, option.label)],
              selected: selected,
            );
            if (picked == null || !mounted) return;
            setState(() => _choices[field.name] = picked);
          },
        );
    }
  }
}
