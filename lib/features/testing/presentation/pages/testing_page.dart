import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_type/core/controllers/zero_type_controller.dart';
import 'package:zero_type/core/services/recording_service.dart';
import 'package:zero_type/core/state/zero_type_state.dart';

@RoutePage()
class TestingPage extends ConsumerStatefulWidget {
  const TestingPage({super.key});

  @override
  ConsumerState<TestingPage> createState() => _TestingPageState();
}

class _TestingPageState extends ConsumerState<TestingPage> {
  String _permissionStatus = '未檢查';
  bool _overlayVisible = false;

  Future<void> _toggleOverlay() async {
    final notifier = ref.read(zeroTypeControllerProvider.notifier);
    if (_overlayVisible) {
      await notifier.hideOverlay();
    } else {
      await notifier.showOverlay('recording', '錄音中');
    }
    if (mounted) setState(() => _overlayVisible = !_overlayVisible);
  }

  Future<void> _checkPermission() async {
    final svc = RecordingService();
    final granted = await svc.requestPermission();
    await svc.dispose();
    if (mounted) {
      setState(() {
        _permissionStatus = granted ? '已授權' : '被拒絕（請至系統設定 > 隱私權 > 麥克風 開啟）';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(zeroTypeControllerProvider);
    final notifier = ref.read(zeroTypeControllerProvider.notifier);

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isIdle = state.status == ZeroTypeStatus.idle;
    final isRecording = state.status == ZeroTypeStatus.recording;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Text(
              '測試',
              style: tt.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '測試錄音與辨識；成功後的錄音與逐字稿會加密保存於歷史紀錄',
              style: tt.bodyMedium?.copyWith(color: cs.onSurface.withAlpha(150)),
            ),
            const SizedBox(height: 32),

            // ── Permission check ─────────────────────────────────────────────
            _SectionCard(
              child: Row(
                children: [
                  Icon(Icons.security, color: cs.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('麥克風權限', style: tt.labelLarge),
                        const SizedBox(height: 2),
                        Text(
                          _permissionStatus,
                          style: tt.bodySmall?.copyWith(
                            color: _permissionStatus == '已授權'
                                ? Colors.greenAccent
                                : cs.onSurface.withAlpha(150),
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: _checkPermission,
                    child: const Text('檢查權限'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Overlay toggle ───────────────────────────────────────────────
            _SectionCard(
              child: Row(
                children: [
                  Icon(Icons.picture_in_picture_alt,
                      color: cs.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Recording Overlay', style: tt.labelLarge),
                        const SizedBox(height: 2),
                        Text(
                          _overlayVisible ? '顯示中' : '已隱藏',
                          style: tt.bodySmall?.copyWith(
                            color: _overlayVisible
                                ? const Color(0xFF6C63FF)
                                : cs.onSurface.withAlpha(150),
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: _toggleOverlay,
                    child: Text(_overlayVisible ? '隱藏 Overlay' : '顯示 Overlay'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── State display ────────────────────────────────────────────────
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StatusDot(status: state.status),
                      const SizedBox(width: 10),
                      Text(
                        _statusLabel(state.status),
                        style: tt.titleMedium?.copyWith(
                          color: _statusColor(state.status),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (isRecording) ...[
                    const SizedBox(height: 16),
                    _AmplitudeBar(amplitude: state.amplitude),
                  ],
                  if (state.status == ZeroTypeStatus.done &&
                      state.result != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: Colors.greenAccent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '已儲存：${state.result}',
                            style: tt.bodySmall
                                ?.copyWith(color: Colors.greenAccent),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (state.status == ZeroTypeStatus.error &&
                      state.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: cs.error, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.errorMessage!,
                            style:
                                tt.bodySmall?.copyWith(color: cs.error),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Basic Controls ──────────────────────────────────────────────
            Row(
              children: [
                FilledButton.icon(
                  onPressed: isIdle ? () => notifier.toggleRecording() : null,
                  icon: const Icon(Icons.mic, size: 18),
                  label: const Text('開始'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: isRecording ? () => notifier.toggleRecording() : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                  ),
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('停止'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: !isIdle ? () => notifier.cancel() : null,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('取消'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Full Test ────────────────────────────────────────────────────
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.play_circle_filled,
                          color: cs.primary, size: 20),
                      const SizedBox(width: 12),
                      Text('完整流程測試', style: tt.labelLarge),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '點擊下方按鈕開始完整錄音流程。系統會自動顯示 Overlay 並在結束後將成品儲存至桌面。',
                    style: tt.bodySmall?.copyWith(color: cs.onSurface.withAlpha(150)),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => notifier.toggleRecording(),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: isRecording ? cs.error : cs.primary,
                        foregroundColor: isRecording ? cs.onError : cs.onPrimary,
                      ),
                      icon: Icon(isRecording ? Icons.stop : Icons.mic),
                      label: Text(isRecording ? '停止測試' : '完整測試'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(ZeroTypeStatus status) => switch (status) {
        ZeroTypeStatus.idle => '待機中',
        ZeroTypeStatus.recording => '錄音中…',
        ZeroTypeStatus.cancelling => '取消中…',
        ZeroTypeStatus.saving => '擷取中…',
        ZeroTypeStatus.transcribing => '處理中…',
        ZeroTypeStatus.done => '完成',
        ZeroTypeStatus.error => '錯誤',
      };

  Color _statusColor(ZeroTypeStatus status) => switch (status) {
        ZeroTypeStatus.idle =>
          Theme.of(context).colorScheme.onSurface.withAlpha(100),
        ZeroTypeStatus.recording => const Color(0xFF6C63FF),
        ZeroTypeStatus.cancelling =>
          Theme.of(context).colorScheme.onSurface.withAlpha(100),
        ZeroTypeStatus.saving => const Color(0xFFFFAA00),
        ZeroTypeStatus.transcribing => const Color(0xFF63B3FF),
        ZeroTypeStatus.done => Colors.greenAccent,
        ZeroTypeStatus.error => Theme.of(context).colorScheme.error,
      };
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final ZeroTypeStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status == ZeroTypeStatus.recording
        ? const Color(0xFF6C63FF)
        : status == ZeroTypeStatus.done
            ? Colors.greenAccent
            : status == ZeroTypeStatus.error
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.onSurface.withAlpha(80);

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _AmplitudeBar extends StatelessWidget {
  const _AmplitudeBar({required this.amplitude});
  final double amplitude;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '音量',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
              ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: amplitude.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor:
                Theme.of(context).colorScheme.onSurface.withAlpha(30),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF6C63FF)),
          ),
        ),
      ],
    );
  }
}
