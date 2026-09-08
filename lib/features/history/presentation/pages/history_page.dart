import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_type/core/constants/model_pricing.dart';
import 'package:zero_type/features/history/domain/entities/history_stats.dart';
import 'package:zero_type/features/history/domain/entities/transcription_record.dart';
import '../controllers/history_controller.dart';

@RoutePage()
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(historyControllerProvider);
    final statsAsync = ref.watch(historyStatsProvider);
    final stats = statsAsync.asData?.value ?? HistoryStats.zero;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('無法解密或載入歷史紀錄。請確認系統安全儲存可用。'),
          TextButton(onPressed: () => _PageHeader(records: const [], ref: ref)._confirmClearAll(context, ref),
            child: const Text('清除無法讀取的歷史紀錄')),
        ])),
        data: (records) => Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(left: 24, right: 24, bottom: 16, top: 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PageHeader(records: records, ref: ref),
                    const SizedBox(height: 24),
                    if (records.isEmpty)
                      const _EmptyState()
                    else
                      _HistoryList(records: records),
                  ],
                ),
              ),
            ),
            if (stats.totalCount > 0) _StatsSummaryCard(stats: stats),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page Header
// ---------------------------------------------------------------------------

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.records, required this.ref});
  final List<TranscriptionRecord> records;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '歷史記錄',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '錄音與逐字稿已加密保存；複製的文字會留在系統剪貼簿',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                    ),
              ),
            ],
          ),
        ),
        if (records.isNotEmpty)
          TextButton.icon(
            onPressed: () => _confirmClearAll(context, ref),
            icon: const Icon(Icons.delete_sweep_outlined, size: 16),
            label: const Text('全部清除'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red.withOpacity(0.8),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除全部記錄'),
        content: const Text('確定要刪除所有歷史記錄與音檔嗎？此操作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(historyControllerProvider.notifier).clearAll();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('全部刪除'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History list wrapped in card
// ---------------------------------------------------------------------------

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.records});
  final List<TranscriptionRecord> records;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withOpacity(0.1)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: records.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          indent: 16,
          endIndent: 16,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
        ),
        itemBuilder: (context, index) => _HistoryItem(record: records[index]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History item
// ---------------------------------------------------------------------------

class _HistoryItem extends ConsumerStatefulWidget {
  const _HistoryItem({required this.record});
  final TranscriptionRecord record;

  @override
  ConsumerState<_HistoryItem> createState() => _HistoryItemState();
}

class _HistoryItemState extends ConsumerState<_HistoryItem> {
  OverlayEntry? _overlayEntry;
  final _textKey = GlobalKey();
  final _scrollController = ScrollController();
  bool _hoverText = false;
  bool _hoverPopup = false;

  void _onTextEnter() {
    _hoverText = true;
    if (_overlayEntry == null) _showPopup();
  }

  void _onTextExit() {
    _hoverText = false;
    // Small delay so mouse can travel to popup before we decide to close
    Future.delayed(const Duration(milliseconds: 80), _maybeHide);
  }

  void _onPopupEnter() => _hoverPopup = true;

  void _onPopupExit() {
    _hoverPopup = false;
    Future.delayed(const Duration(milliseconds: 80), _maybeHide);
  }

  void _maybeHide() {
    if (!_hoverText && !_hoverPopup) _hidePopup();
  }

  void _showPopup() {
    if (record.text.length <= 40) return;
    final renderBox = _textKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenSize = MediaQuery.of(context).size;

    final popupWidth = (screenSize.width * 0.55).clamp(320.0, 680.0);
    final popupMaxHeight = screenSize.height * 0.65;
    final spaceBelow = screenSize.height - (offset.dy + size.height + 8);
    final showAbove = spaceBelow < 200 && offset.dy > spaceBelow;

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        final content = MouseRegion(
          onEnter: (_) => _onPopupEnter(),
          onExit: (_) => _onPopupExit(),
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(14),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            shadowColor: Colors.black.withOpacity(0.25),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: popupMaxHeight),
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    record.text,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.7,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        if (showAbove) {
          return Positioned(
            left: offset.dx,
            bottom: screenSize.height - offset.dy + 6,
            width: popupWidth,
            child: content,
          );
        } else {
          return Positioned(
            left: offset.dx,
            top: offset.dy + size.height + 6,
            width: popupWidth,
            child: content,
          );
        }
      },
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hidePopup() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  TranscriptionRecord get record => widget.record;

  @override
  void dispose() {
    _hidePopup();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playingId = ref.watch(playingRecordIdProvider);
    final isPlaying = playingId == record.id;
    final cs = Theme.of(context).colorScheme;
    final hasAudio = record.audioPath != null && File(record.audioPath!).existsSync();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Left: date + text + token info ---
          Expanded(
            child: MouseRegion(
              onEnter: (_) => _onTextEnter(),
              onExit: (_) => _onTextExit(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDateTime(record.createdAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.45),
                        ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    key: _textKey,
                    record.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w500),
                  ),
                  if (record.inputTokens != null) ...[
                    const SizedBox(height: 5),
                    _TokenInfoRow(record: record),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // --- Right: action buttons ---
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasAudio)
                _ActionIcon(
                  icon: isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  tooltip: isPlaying ? '停止' : '播放',
                  color: isPlaying ? cs.primary : null,
                  onTap: () => ref.read(historyControllerProvider.notifier).togglePlay(record),
                ),
              _ActionIcon(
                icon: Icons.copy_outlined,
                tooltip: '複製文字',
                onTap: () => ref.read(historyControllerProvider.notifier).copyText(record.text),
              ),
              if (hasAudio)
                _ActionIcon(
                  icon: Icons.folder_open_outlined,
                  tooltip: '顯示加密音檔（僅能在本程式播放）',
                  onTap: () =>
                      ref.read(historyControllerProvider.notifier).revealInFinder(record.audioPath!),
                ),
              _ActionIcon(
                icon: Icons.delete_outline,
                tooltip: '刪除',
                color: Colors.red.withOpacity(0.7),
                onTap: () => ref.read(historyControllerProvider.notifier).deleteRecord(record.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final time = '$h:$m';
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isToday) return '今天  $time';
    if (dt.year == now.year) return '${dt.month}/${dt.day}  $time';
    return '${dt.year}/${dt.month}/${dt.day}  $time';
  }
}

class _TokenInfoRow extends StatelessWidget {
  const _TokenInfoRow({required this.record});
  final TranscriptionRecord record;

  @override
  Widget build(BuildContext context) {
    final providerName = kProviderNames[record.provider] ?? record.provider;
    final modelName = kModelNames[record.model] ?? record.model;
    final costStr = record.costUsd != null ? formatCostUsd(record.costUsd!) : '';
    final parts = [
      providerName,
      modelName,
      'in: ${record.inputTokens} / out: ${record.outputTokens}',
      if (costStr.isNotEmpty) costStr,
    ];

    return Text(
      parts.join(' · '),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
          ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 17,
            color: color ?? Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
            ),
            const SizedBox(height: 16),
            Text(
              '尚無轉寫記錄',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              '完成一次語音辨識後，記錄將會顯示在這裡',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.25),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats summary card (floating bottom)
// ---------------------------------------------------------------------------

class _StatsSummaryCard extends StatelessWidget {
  const _StatsSummaryCard({required this.stats});
  final HistoryStats stats;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final costDisplay = stats.totalCostUsd > 0
        ? formatCostUsd(stats.totalCostUsd)
        : '—';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.onSurface.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withOpacity(0.35)
                  : Colors.black.withOpacity(0.08),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: cs.primary.withOpacity(0.04),
              blurRadius: 12,
              spreadRadius: 0,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _StatCell(
                  label: '轉寫次數',
                  value: '${stats.totalCount}',
                  primaryColor: cs.primary,
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                indent: 16,
                endIndent: 16,
                color: cs.onSurface.withOpacity(0.1),
              ),
              Expanded(
                child: _StatCell(
                  label: '總花費 (USD)',
                  value: costDisplay,
                  primaryColor: cs.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.primaryColor,
  });

  final String label;
  final String value;
  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                letterSpacing: 0.3,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: primaryColor,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}
