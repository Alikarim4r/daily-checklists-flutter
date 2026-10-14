import 'package:flutter/material.dart';

import 'checkview_tokens.dart';

/// Presence animation that keeps every visited workspace mounted.
///
/// A fading workspace is always pointer-inert and removed from the
/// accessibility tree immediately. It cannot intercept review actions.
class CvPagePresence extends StatelessWidget {
  const CvPagePresence({
    super.key,
    required this.active,
    required this.child,
    this.depth = 0.028,
  });

  final bool active;
  final Widget child;
  final double depth;

  @override
  Widget build(BuildContext context) {
    final duration = CvMotion.of(context, CvMotion.spatial);
    // Keep the implicit opacity and slide animations ticking on departure.
    // Only expensive inner page animations should be muted when inactive.
    return IgnorePointer(
      ignoring: !active,
      child: ExcludeSemantics(
        excluding: !active,
        child: AnimatedOpacity(
          opacity: active ? 1 : 0,
          duration: duration,
          curve: CvMotion.glide,
          child: AnimatedSlide(
            offset: active ? Offset.zero : Offset(0, depth),
            duration: duration,
            curve: CvMotion.glide,
            child: TickerMode(enabled: active, child: child),
          ),
        ),
      ),
    );
  }
}

/// A quiet upward reveal for new sections and empty/loading states.
/// Uses an implicit animation: no delayed jobs or persistent ticker.
class CvEntrance extends StatefulWidget {
  const CvEntrance({
    super.key,
    required this.child,
    this.distance = 12,
    this.duration = CvMotion.spatial,
  });

  final Widget child;
  final double distance;
  final Duration duration;

  @override
  State<CvEntrance> createState() => _CvEntranceState();
}

class _CvEntranceState extends State<CvEntrance> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    // Scheduled after the first layout so a new item has a real entry frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: CvMotion.of(context, widget.duration),
      curve: CvMotion.glide,
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : Offset(0, widget.distance / 400),
        duration: CvMotion.of(context, widget.duration),
        curve: CvMotion.glide,
        child: widget.child,
      ),
    );
  }
}

/// Subtle spring-like lift on mouse hover and tactile compression on press.
/// The inner InkWell keeps ownership of click, focus and keyboard actions.
class CvInteractiveSurface extends StatefulWidget {
  const CvInteractiveSurface({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<CvInteractiveSurface> createState() => _CvInteractiveSurfaceState();
}

class _CvInteractiveSurfaceState extends State<CvInteractiveSurface> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHover(bool value) {
    if (widget.enabled && _hovered != value) {
      setState(() => _hovered = value);
    }
  }

  void _setPressed(bool value) {
    if (widget.enabled && _pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final scale = reduced || !widget.enabled
        ? 1.0
        : _pressed
        ? 0.987
        : _hovered
        ? 1.006
        : 1.0;
    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: scale,
          duration: CvMotion.of(
            context,
            _pressed ? CvMotion.quick : CvMotion.standard,
          ),
          curve: _pressed ? Curves.easeOut : CvMotion.spring,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Navigation for dialogs/details. iOS keeps its platform edge-back gesture.
class CvPageTransitionsBuilder extends PageTransitionsBuilder {
  const CvPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: CvMotion.glide,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.055),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.987, end: 1).animate(curved),
          child: child,
        ),
      ),
    );
  }
}
