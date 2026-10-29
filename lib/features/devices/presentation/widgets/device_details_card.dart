import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/device_model.dart';
import '../../device_details.dart';
import 'glass_card.dart';

/// "Ayrıntılar" düğmesi: dokununca model, fiyat, satın alma, garanti ve notlar açılır.
class DeviceDetailsCard extends StatefulWidget {
  final DeviceModel device;

  const DeviceDetailsCard({super.key, required this.device});

  @override
  State<DeviceDetailsCard> createState() => _DeviceDetailsCardState();
}

class _DeviceDetailsCardState extends State<DeviceDetailsCard> {
  static final _dateFormat = DateFormat('dd.MM.yyyy');

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 20, color: AppTheme.textSecondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Ayrıntılar', style: Theme.of(context).textTheme.titleMedium),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded ? _buildRows(context) : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildRows(BuildContext context) {
    final device = widget.device;
    final now = DateTime.now();
    final purchase = device.purchaseDate;
    final warrantyEnd = device.warrantyEndDate;

    final model = device.modelInfo?.trim() ?? '';
    final notes = device.notes?.trim() ?? '';

    final rows = <Widget>[
      _DetailRow(label: 'Model', value: model),
      _DetailRow(label: 'Fiyat', value: device.price == null ? '' : formatPrice(device.price!)),
      _DetailRow(
        label: 'Satın alma',
        value: purchase == null ? '' : _dateFormat.format(purchase),
        caption: purchase == null ? null : 'Kullanım süresi: ${usageTimeLabel(purchase, now)}',
      ),
      _DetailRow(
        label: 'Garanti',
        value: warrantyEnd == null
            ? ''
            : device.warrantyMonths <= 0
                ? 'Garanti yok'
                : warrantyRemainingLabel(warrantyEnd, now),
        caption: warrantyEnd == null || device.warrantyMonths <= 0
            ? null
            : 'Bitiş: ${_dateFormat.format(warrantyEnd)}',
      ),
      _DetailRow(label: 'Notlar', value: notes, leftAligned: true, emptyText: 'Not eklenmemiş'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          for (final row in rows) ...[
            const Divider(height: 1, color: AppTheme.glassBorder),
            row,
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final String? caption;
  final bool leftAligned;
  final String emptyText;

  const _DetailRow({
    required this.label,
    required this.value,
    this.caption,
    this.leftAligned = false,
    this.emptyText = '—',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final isEmpty = value.isEmpty;
    final align = leftAligned ? CrossAxisAlignment.start : CrossAxisAlignment.end;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(width: 92, child: Text(label, style: theme.bodyMedium)),
          Expanded(
            child: Column(
              crossAxisAlignment: align,
              children: [
                Text(
                  isEmpty ? emptyText : value,
                  textAlign: leftAligned ? TextAlign.start : TextAlign.end,
                  style: theme.bodyLarge?.copyWith(
                    color: isEmpty ? AppTheme.textSecondary : AppTheme.textPrimary,
                    fontWeight: isEmpty ? FontWeight.w400 : FontWeight.w500,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(caption!, style: theme.bodySmall?.copyWith(color: AppTheme.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
