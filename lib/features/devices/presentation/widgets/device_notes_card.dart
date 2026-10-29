import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'glass_card.dart';

enum _SaveState { idle, pending, saving, saved, failed }

/// Cihaz sayfasındaki düzenlenebilir not kutusu. Yazarken kendiliğinden kaydeder:
/// yazmaya ara verilince, kutudan çıkılınca ve sayfa kapanırken.
class DeviceNotesCard extends StatefulWidget {
  final String text;
  final Future<void> Function(String text) onSave;

  const DeviceNotesCard({super.key, required this.text, required this.onSave});

  @override
  State<DeviceNotesCard> createState() => _DeviceNotesCardState();
}

class _DeviceNotesCardState extends State<DeviceNotesCard> {
  static const _saveDelay = Duration(milliseconds: 1000);

  late final TextEditingController _controller = TextEditingController(text: widget.text);
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  late String _saved = widget.text.trim();
  String? _saving; // Kaydı süren metin; sayfa bunu geri yansıtınca kutu yeniden yazılmasın.
  _SaveState _state = _SaveState.idle;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _flush();
    });
  }

  @override
  void didUpdateWidget(DeviceNotesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Not başka bir yerden (düzenleme sayfası) değiştiyse kutuya yansıt; kendi kaydımız ya da
    // yazmakta olduğumuz bir metin değilse.
    if (widget.text == oldWidget.text) return;
    final external = widget.text.trim();
    if (external == _saved || external == _saving || _focusNode.hasFocus) return;
    _controller.text = widget.text;
    _saved = external;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    final text = _controller.text.trim();
    if (text != _saved) unawaited(widget.onSave(text));
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(_saveDelay, _flush);
    if (_state != _SaveState.pending) setState(() => _state = _SaveState.pending);
  }

  Future<void> _flush() async {
    _debounce?.cancel();
    final text = _controller.text.trim();
    if (text == _saved) {
      if (mounted && _state == _SaveState.pending) setState(() => _state = _SaveState.idle);
      return;
    }

    _saving = text;
    if (mounted) setState(() => _state = _SaveState.saving);
    try {
      await widget.onSave(text);
      _saved = text;
      if (mounted) setState(() => _state = _SaveState.saved);
    } catch (e) {
      debugPrint('Not kaydedilemedi: $e');
      if (mounted) setState(() => _state = _SaveState.failed);
    } finally {
      _saving = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sticky_note_2_outlined, size: 20, color: AppTheme.textSecondary),
              const SizedBox(width: 12),
              Expanded(child: Text('Notlar', style: theme.titleMedium)),
              _buildStatus(theme),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _onChanged,
            onTapOutside: (_) => _focusNode.unfocus(),
            minLines: 3,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: theme.bodyLarge,
            cursorColor: AppTheme.accentEnd,
            decoration: InputDecoration(
              hintText: 'Bu cihaz için not ekleyin (filtre modeli, seri no, servis bilgisi…)',
              hintStyle: theme.bodyMedium,
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.18),
              contentPadding: const EdgeInsets.all(14),
              border: _border(AppTheme.glassBorder),
              enabledBorder: _border(AppTheme.glassBorder),
              focusedBorder: _border(AppTheme.accentEnd),
            ),
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color),
      );

  Widget _buildStatus(TextTheme theme) {
    final (String text, Color color) = switch (_state) {
      _SaveState.idle => ('', AppTheme.textSecondary),
      _SaveState.pending => ('Yazıyorsunuz…', AppTheme.textSecondary),
      _SaveState.saving => ('Kaydediliyor…', AppTheme.textSecondary),
      _SaveState.saved => ('Kaydedildi', AppTheme.statusNormal),
      _SaveState.failed => ('Kaydedilemedi', AppTheme.statusOverdue),
    };
    return Text(text, style: theme.bodySmall?.copyWith(color: color));
  }
}
