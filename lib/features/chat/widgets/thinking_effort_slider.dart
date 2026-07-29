import 'dart:math' as math;

import 'package:flutter/material.dart';

@immutable
class ThinkingEffortLevel {
  const ThinkingEffortLevel({
    required this.label,
    required this.budget,
    required this.description,
    this.particleMode = false,
  });

  final String label;
  final int budget;
  final String description;
  final bool particleMode;
}

class ThinkingEffortSlider extends StatefulWidget {
  static const sliderKey = ValueKey<String>('thinking-effort-slider-track');

  const ThinkingEffortSlider({
    super.key,
    required this.levels,
    required this.selectedBudget,
    required this.onChanged,
    required this.title,
    required this.fastLabel,
    required this.smartLabel,
    required this.helpLabel,
  });

  final List<ThinkingEffortLevel> levels;
  final int? selectedBudget;
  final ValueChanged<ThinkingEffortLevel> onChanged;
  final String title;
  final String fastLabel;
  final String smartLabel;
  final String helpLabel;

  @override
  State<ThinkingEffortSlider> createState() => _ThinkingEffortSliderState();
}

class _ThinkingEffortSliderState extends State<ThinkingEffortSlider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _particleController;
  late int _selectedIndex;
  bool _showInfo = false;

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController.unbounded(vsync: this);
    _selectedIndex = _indexForBudget(widget.selectedBudget);
    _syncParticleController();
  }

  @override
  void didUpdateWidget(covariant ThinkingEffortSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedBudget != widget.selectedBudget ||
        oldWidget.levels != widget.levels) {
      final currentIndex = _selectedIndex.clamp(0, widget.levels.length - 1);
      final currentLevel = widget.levels.isEmpty
          ? null
          : widget.levels[currentIndex];
      if (widget.selectedBudget != null &&
          widget.selectedBudget! > 0 &&
          currentLevel?.budget == widget.selectedBudget) {
        _selectedIndex = currentIndex;
      } else {
        _selectedIndex = _indexForBudget(widget.selectedBudget);
      }
      _syncParticleController();
    }
  }

  @override
  void dispose() {
    _particleController.dispose();
    super.dispose();
  }

  int _indexForBudget(int? budget) {
    if (widget.levels.isEmpty) return 0;
    if (budget == null || budget <= 0) return 0;
    final exact = widget.levels.indexWhere((level) => level.budget == budget);
    if (exact >= 0) return exact;

    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < widget.levels.length; i += 1) {
      final distance = (widget.levels[i].budget - budget).abs().toDouble();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  void _selectIndex(int index, {bool commit = true}) {
    if (widget.levels.isEmpty) return;
    final clamped = index.clamp(0, widget.levels.length - 1);
    if (_selectedIndex == clamped && !commit) return;
    setState(() => _selectedIndex = clamped);
    _syncParticleController();
    if (commit) widget.onChanged(widget.levels[clamped]);
  }

  void _syncParticleController() {
    if (widget.levels.isEmpty) return;
    final selected =
        widget.levels[_selectedIndex.clamp(0, widget.levels.length - 1)];
    final shouldAnimate =
        _selectedIndex == widget.levels.length - 1 && selected.particleMode;
    if (shouldAnimate) {
      if (!_particleController.isAnimating) {
        _particleController.repeat(
          min: 0,
          max: 1,
          period: const Duration(milliseconds: 1600),
        );
      }
    } else if (_particleController.isAnimating) {
      _particleController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final levels = widget.levels;

    if (levels.isEmpty) return const SizedBox.shrink();

    final selected = levels[_selectedIndex.clamp(0, levels.length - 1)];
    final isHighest = _selectedIndex == levels.length - 1;
    final trackHeight = 19.0;
    final thumbSize = const Size(18, 23);

    return Material(
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(constraints.maxWidth, 360.0);
          return Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: width,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.75),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 24,
                        child: Row(
                          children: [
                            Flexible(
                              flex: 3,
                              child: Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                selected.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.primary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            _HelpButton(
                              label: widget.helpLabel,
                              color: cs.onSurfaceVariant.withValues(
                                alpha: 0.62,
                              ),
                              onTap: () =>
                                  setState(() => _showInfo = !_showInfo),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            widget.fastLabel,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            widget.smartLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      RepaintBoundary(
                        child: SizedBox(
                          height: thumbSize.height,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final trackWidth = constraints.maxWidth;
                              final progress = levels.length == 1
                                  ? 0.0
                                  : _selectedIndex / (levels.length - 1);
                              final thumbCenter = trackWidth * progress;
                              final thumbLeft =
                                  thumbCenter - thumbSize.width / 2;
                              return GestureDetector(
                                key: ThinkingEffortSlider.sliderKey,
                                behavior: HitTestBehavior.opaque,
                                onTapDown: (details) {
                                  _selectIndex(
                                    _indexFromDx(
                                      details.localPosition.dx,
                                      trackWidth,
                                    ),
                                  );
                                },
                                onHorizontalDragUpdate: (details) {
                                  _selectIndex(
                                    _indexFromDx(
                                      details.localPosition.dx,
                                      trackWidth,
                                    ),
                                    commit: false,
                                  );
                                },
                                onHorizontalDragEnd: (_) {
                                  widget.onChanged(levels[_selectedIndex]);
                                },
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.centerLeft,
                                  children: [
                                    Positioned.fill(
                                      child: Center(
                                        child: SizedBox(
                                          height: trackHeight,
                                          child: AnimatedBuilder(
                                            animation: _particleController,
                                            builder: (context, _) {
                                              return CustomPaint(
                                                painter: _EffortTrackPainter(
                                                  levelCount: levels.length,
                                                  isParticleMode:
                                                      isHighest &&
                                                      selected.particleMode,
                                                  tick:
                                                      _particleController.value,
                                                  colorScheme: cs,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: thumbLeft,
                                      top: 0,
                                      child: Container(
                                        width: thumbSize.width,
                                        height: thumbSize.height,
                                        decoration: BoxDecoration(
                                          color: cs.surface,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showInfo)
                  Positioned(
                    top: 39,
                    right: 10,
                    child: _InfoPopover(level: selected),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  int _indexFromDx(double dx, double width) {
    if (widget.levels.length <= 1 || width <= 0) return 0;
    final progress = (dx / width).clamp(0.0, 1.0);
    return (progress * (widget.levels.length - 1)).round();
  }
}

class _HelpButton extends StatelessWidget {
  const _HelpButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CustomPaint(painter: _QuestionIconPainter(color: color)),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoPopover extends StatelessWidget {
  const _InfoPopover({required this.level});

  final ThinkingEffortLevel level;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: 230,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            level.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            level.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 11,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _EffortTrackPainter extends CustomPainter {
  _EffortTrackPainter({
    required this.levelCount,
    required this.isParticleMode,
    required this.tick,
    required this.colorScheme,
  });

  final int levelCount;
  final bool isParticleMode;
  final double tick;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    canvas.save();
    canvas.clipRRect(rrect);

    final basePaint = Paint()
      ..shader = LinearGradient(
        colors: isParticleMode
            ? const [
                Color(0xFFDCDCDF),
                Color(0xFFD4D0DD),
                Color(0xFFC1ACD8),
                Color(0xFFA57BD4),
              ]
            : const [Color(0xFFDCDCDF), Color(0xFFD4D4D8), Color(0xFFCFCFD4)],
      ).createShader(rect);
    canvas.drawRRect(rrect, basePaint);

    final shinePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x66FFFFFF), Color(0x00FFFFFF), Color(0x14000000)],
        stops: [0, 0.54, 1],
      ).createShader(rect);
    canvas.drawRRect(rrect, shinePaint);

    if (isParticleMode) {
      _drawParticles(canvas, size);
    } else {
      _drawDividers(canvas, size);
    }

    canvas.restore();
  }

  void _drawDividers(Canvas canvas, Size size) {
    if (levelCount <= 1) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.44)
      ..strokeWidth = 1;
    for (var i = 1; i < levelCount; i += 1) {
      final x = size.width * i / (levelCount - 1);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  void _drawParticles(Canvas canvas, Size size) {
    final washPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0x00FFFFFF),
          Color(0x14D8D0E5),
          Color(0x2EAA87DD),
          Color(0x579B6BE8),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, washPaint);

    const count = 140;
    for (var i = 0; i < count; i += 1) {
      final seed = math.sin(i * 12.9898) * 43758.5453;
      final n = seed - seed.floorToDouble();
      final ySeed = math.sin(i * 78.233) * 24634.6345;
      final yn = ySeed - ySeed.floorToDouble();
      final speed = 0.22 + (n * 0.32);
      final rightBias = 1 - math.pow(n, 2.3) * 0.82;
      final x = ((rightBias - tick * speed) % 1.18) * size.width;
      if (x < size.width * 0.16) continue;
      final y = 2 + (yn * 9).floor() * 2 + yn;
      final rightness = (x / size.width).clamp(0.0, 1.0);
      final alpha =
          (0.18 + rightness * 0.62) *
          ((x - size.width * 0.16) / (size.width * 0.55)).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = Color.lerp(
          const Color(0xFFFFFFFF),
          const Color(0xFF9B6BE8),
          n,
        )!.withValues(alpha: alpha.clamp(0.0, 0.86));
      final w = n > 0.85 ? 2.4 : (n > 0.5 ? 1.6 : 1.0);
      canvas.drawRect(
        Rect.fromLTWH(x.roundToDouble(), y.roundToDouble(), w, 1),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EffortTrackPainter oldDelegate) {
    return oldDelegate.levelCount != levelCount ||
        oldDelegate.isParticleMode != isParticleMode ||
        oldDelegate.tick != tick ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _QuestionIconPainter extends CustomPainter {
  _QuestionIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, 6.25, paint);

    final path = Path()
      ..moveTo(6.3, 6.4)
      ..cubicTo(6.45, 5.35, 7.15, 4.75, 8.1, 4.75)
      ..cubicTo(9.15, 4.75, 9.85, 5.38, 9.85, 6.25)
      ..cubicTo(9.85, 6.92, 9.45, 7.32, 8.87, 7.68)
      ..cubicTo(8.35, 8.02, 8.1, 8.34, 8.1, 8.95);
    canvas.drawPath(path, paint);

    canvas.drawCircle(const Offset(8.1, 11.25), 0.58, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _QuestionIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
