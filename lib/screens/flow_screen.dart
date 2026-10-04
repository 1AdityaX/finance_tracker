import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/ledger.dart';
import '../data/money.dart';
import '../data/store.dart';
import '../flows/flows.dart';
import '../theme.dart';
import 'ask_views.dart';
import 'widgets.dart';

/// Runs a [CommandFlow]: one question per page, the answers so far in a strip
/// at the top, and a review card before saving.
///
/// Continue goes to the first question that is unanswered or no longer valid,
/// so revising an answer returns straight to the review. Back, including the
/// system back gesture, returns to the previous page without losing answers.
class FlowScreen extends StatefulWidget {
  const FlowScreen({super.key, required this.store, required this.flow});
  final Store store;
  final CommandFlow flow;

  @override
  State<FlowScreen> createState() => _FlowScreenState();
}

class _FlowScreenState extends State<FlowScreen> {
  CommandFlow get flow => widget.flow;

  /// Questions the user has answered and moved past.
  late final confirmed = <Ask>{...flow.preset, if (flow.editing) ...flow.asks};

  /// Pages shown before this one; null stands for the review.
  final history = <Ask?>[];

  /// The question on screen, or null for the review.
  late Ask? current = flow.editing ? null : _firstOpen();

  bool forward = true;
  bool showProblem = false;

  /// Whether any answer changed; until then an edit's button just closes.
  bool edited = false;
  bool saving = false;
  String? saveError;

  /// Whether [ask] is answered, still valid, and needs no other look.
  bool _done(Ask ask) =>
      confirmed.contains(ask) && ask.problem == null && !ask.stale;

  /// The first question that still needs the user.
  Ask? _firstOpen() => flow.asks.where((a) => !_done(a)).firstOrNull;

  int _position(Ask? ask) =>
      ask == null ? flow.asks.length : flow.asks.indexOf(ask);

  void _show(Ask? next, {bool remember = true}) => setState(() {
    // The review only shows once nothing is open; otherwise say what's wrong.
    final open = next == null ? _firstOpen() : null;
    next ??= open;
    if (next == null && history.contains(null)) {
      // Back on the review after changing an answer: unwind to it instead of
      // stacking a second review in the history.
      history.removeRange(history.indexOf(null), history.length);
    } else if (remember) {
      history.add(current);
    }
    forward = _position(next) >= _position(current);
    current = next;
    showProblem = open != null;
    saveError = null;
  });

  void _continue() {
    final ask = current;
    if (ask == null) {
      // Opening a record to look at it, then leaving, saves nothing.
      flow.editing && !edited ? _close() : _save();
      return;
    }
    if (ask.problem != null) {
      setState(() => showProblem = true);
      return;
    }
    ask.accept();
    confirmed.add(ask);
    final next = _firstOpen();
    if (next == null && !flow.hasReview) {
      _save();
      return;
    }
    _show(next);
  }

  void _back() {
    if (saving) return;
    // Leaving a page with Back counts as having looked at it, so a valid
    // answer due another look doesn't hold the user there.
    if (current case final ask? when ask.problem == null) ask.accept();
    while (history.isNotEmpty) {
      final previous = history.removeLast();
      if (previous == null || flow.asks.contains(previous)) {
        _show(previous, remember: false);
        return;
      }
    }
    _close();
  }

  /// Whether closing now would lose something the user entered.
  bool get _dirty =>
      flow.editing ? edited : confirmed.difference(flow.preset).isNotEmpty;

  Future<void> _close() async {
    if (saving) return;
    final navigator = Navigator.of(context);
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            flow.editing ? 'Discard your changes?' : 'Discard your answers?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    navigator.pop(false);
  }

  Future<void> _commit(Ledger next, String message) async {
    if (saving) return; // A double tap must not save twice.
    setState(() {
      saving = true;
      saveError = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.store.save(next, message);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          saveError = 'Couldn’t save. Please try again.';
        });
      }
      return;
    }
    if (!mounted) return;
    unawaited(HapticFeedback.lightImpact());
    Navigator.of(context).pop(true);
    showUndo(messenger, widget.store, message);
  }

  void _save() => _commit(flow.save(widget.store.ledger), flow.savedMessage);

  void _delete() {
    final deleted = flow.delete(widget.store.ledger)!;
    _commit(deleted.ledger, deleted.message);
  }

  String get _buttonLabel {
    if (current == null) {
      return flow.editing && !edited ? 'Done' : flow.saveLabel;
    }
    final last =
        !flow.hasReview && flow.asks.every((a) => a == current || _done(a));
    return last ? flow.saveLabel : 'Continue';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answered = [
      for (final a in flow.asks)
        if (a != current && _done(a)) a,
    ];
    // The split page shows its own problem as it changes.
    final problem = showProblem && current is! SplitAsk
        ? current?.problem
        : saveError;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Read here: inside the Scaffold body the keyboard inset is already gone.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    // Back steps through earlier pages. Only the first page lets the route
    // pop, which keeps the predictive back and iOS swipe gestures there.
    return PopScope(
      canPop: history.isEmpty && !saving && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _back},
        child: Scaffold(
          appBar: AppBar(
            // Top-left goes back, as people expect; closing moves right.
            leading: history.isEmpty
                ? CloseButton(onPressed: saving ? null : _close)
                : BackButton(onPressed: saving ? null : _back),
            title: Text(flow.title),
            actions: [
              if (history.isNotEmpty)
                CloseButton(onPressed: saving ? null : _close),
              if (flow.editing)
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: saving ? null : _delete,
                ),
            ],
            bottom: flow.asks.length > 1
                ? _StepBar(flow: flow, current: current, confirmed: confirmed)
                : null,
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => _fitHeight(
                box,
                Column(
                  children: [
                    AnimatedSize(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      alignment: Alignment.topCenter,
                      // The review scrolls its own copy with the record, and a
                      // short screen with the keyboard up has no room for it.
                      child:
                          current == null ||
                              (keyboardOpen && box.maxHeight < 320)
                          ? const SizedBox(width: double.infinity)
                          : _AnswerStrip(
                              answers: answered,
                              onTap: _show,
                              oneLine: keyboardOpen,
                              maxHeight: box.maxHeight / 4,
                            ),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.topCenter,
                          children: [...previous, ?current],
                        ),
                        // The outgoing page runs its animation in reverse, so it
                        // takes the opposite offset to leave the way the new page
                        // came from. It can't be tapped or read while it leaves.
                        transitionBuilder: (child, animation) {
                          final incoming = child.key == ObjectKey(current);
                          final dx = incoming == forward ? 0.08 : -0.08;
                          return IgnorePointer(
                            ignoring: !incoming,
                            child: ExcludeSemantics(
                              excluding: !incoming,
                              child: FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween(
                                    begin: Offset(dx, 0),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ObjectKey(current),
                          child: switch (current) {
                            null => _Review(
                              flow: flow,
                              strip: _AnswerStrip(
                                answers: answered,
                                onTap: _show,
                                scrolls: true,
                              ),
                            ),
                            final ask => AskView(
                              ask: ask,
                              onChanged: () => setState(() => edited = true),
                              // A late submit from the page sliding out must not
                              // answer the page that replaced it.
                              onDone: () {
                                if (identical(ask, current)) _continue();
                              },
                            ),
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (problem != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  problem,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                            ),
                          FilledButton(
                            onPressed: saving ? null : _continue,
                            child: Text(_buttonLabel),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Very short screens, such as a landscape phone with the keyboard up,
  /// scroll the whole page rather than overflow. Anything taller keeps
  /// Continue pinned above the keyboard; the question scrolls on its own.
  static Widget _fitHeight(BoxConstraints box, Widget page) {
    if (box.maxHeight >= 160) return page;
    return SingleChildScrollView(child: SizedBox(height: 240, child: page));
  }
}

/// One segment per question: filled once answered, strongest for the
/// current one.
class _StepBar extends StatelessWidget implements PreferredSizeWidget {
  const _StepBar({
    required this.flow,
    required this.current,
    required this.confirmed,
  });
  final CommandFlow flow;
  final Ask? current;
  final Set<Ask> confirmed;

  @override
  Size get preferredSize => const Size.fromHeight(36);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Questions answered from where the flow started aren't counted.
    final asks = [
      for (final a in flow.asks)
        if (!flow.preset.contains(a) || a == current) a,
    ];
    final label = current == null
        ? 'Review'
        : '${asks.indexOf(current!) + 1} of ${asks.length}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Semantics(
        label: current == null ? 'Review' : 'Question $label',
        excludeSemantics: true,
        child: Row(
          children: [
            for (final ask in asks)
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 4,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: ask == current
                        ? scheme.primary
                        : confirmed.contains(ask)
                        ? scheme.primary.withValues(alpha: 0.4)
                        : scheme.surfaceContainerHighest,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            // Capped so the bar fits its fixed height at any text size and
            // never squeezes the toolbar's buttons.
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: tabular,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The answers so far as tappable chips, newest at the end.
///
/// The chips wrap, so the whole record reads as a sentence.
class _AnswerStrip extends StatelessWidget {
  const _AnswerStrip({
    required this.answers,
    required this.onTap,
    this.scrolls = false,
    this.oneLine = false,
    this.maxHeight = double.infinity,
  });
  final List<Ask> answers;
  final void Function(Ask ask) onTap;

  /// True inside a page that scrolls, where the chips simply wrap.
  final bool scrolls;

  /// One line that scrolls sideways, newest last, while the keyboard is up.
  final bool oneLine;

  /// How tall the wrapped chips may grow before they scroll.
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (answers.isEmpty) return const SizedBox(width: double.infinity);
    final chips = [
      for (final ask in answers)
        ActionChip(
          label: Text(ask.phrase),
          tooltip: 'Change: ${ask.question}',
          onPressed: () => onTap(ask),
        ),
    ];
    const padding = EdgeInsets.fromLTRB(20, 4, 20, 0);
    final wrap = SizedBox(
      width: double.infinity,
      child: Wrap(spacing: 8, children: chips),
    );
    if (scrolls) return Padding(padding: padding, child: wrap);
    if (!oneLine) {
      // Capped so very large text can't push the question off the screen.
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: _FadeEnd(
          child: SingleChildScrollView(
            padding: padding.copyWith(bottom: _FadeEnd.height),
            child: wrap,
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth - 40),
          child: Row(spacing: 8, children: chips),
        ),
      ),
    );
  }
}

/// The record as it will be saved, with what it means for each friend.
class _Review extends StatelessWidget {
  const _Review({required this.flow, required this.strip});
  final CommandFlow flow;

  /// The answers, scrolling with the record so neither hides the other.
  final Widget strip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final heading = flow.heading;
    return _FadeEnd(
      child: ListView(
        padding: const EdgeInsets.only(bottom: _FadeEnd.height),
        children: [
          strip,
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: _card(theme, scheme, heading),
          ),
        ],
      ),
    );
  }

  Widget _card(
    ThemeData theme,
    ColorScheme scheme,
    ({String title, int amount}) heading,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (flow.editing)
        Text(
          'Tap an answer above to change it.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        )
      else
        Semantics(
          header: true,
          headingLevel: 1,
          liveRegion: true,
          child: Text('Look right?', style: theme.textTheme.headlineSmall),
        ),
      const SizedBox(height: 16),
      DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(heading.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                rupees(heading.amount),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFeatures: tabular,
                ),
              ),
              for (final section in flow.review)
                if (section.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(),
                  ),
                  for (final line in section) _line(theme, line),
                ],
            ],
          ),
        ),
      ),
    ],
  );

  Widget _line(ThemeData theme, Line line) {
    final color = theme.colorScheme.forSign(line.sign);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.label, style: theme.textTheme.bodyLarge),
                if (line.detail case final detail?)
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            line.value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFeatures: tabular,
              color: line.sign == 0 ? null : color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades the last [height] pixels of a scrolling [child] whose bottom
/// padding is [height]. The padding is blank until content scrolls under it,
/// so the fade only shows when there is more below.
class _FadeEnd extends StatelessWidget {
  const _FadeEnd({required this.child});
  static const height = 16.0;
  final Widget child;

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (bounds) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Colors.white, Colors.white, Colors.transparent],
      stops: [0, 1 - height / bounds.height, 1],
    ).createShader(bounds),
    child: child,
  );
}
