import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/money.dart';
import '../theme.dart';

/// Lets money fields take sums like "1000-300": digits, a decimal point,
/// + - × ÷ and brackets. Commas are digit grouping, as in "1,200", so they
/// are dropped rather than read as a decimal point.
final sumFormatter = TextInputFormatter.withFunction((old, value) {
  final text = value.text.replaceAll(',', '');
  if (!RegExp(r'^[\d.+\-*/×÷() ]{0,40}$').hasMatch(text)) return old;
  final caret = value.selection.end.clamp(0, value.text.length);
  final dropped = ','.allMatches(value.text.substring(0, caret)).length;
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret - dropped),
  );
});

/// Holds whichever money field has focus, so [SumKeys] can type into it.
class SumScope extends StatefulWidget {
  const SumScope({super.key, required this.child});
  final Widget child;

  static ValueNotifier<TextEditingController?>? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SumScope>()?.active;

  @override
  State<SumScope> createState() => _SumScopeState();
}

class _SumScopeState extends State<SumScope> {
  // Not disposed: fields below may still clear it as they go, after this
  // state is gone. Nothing else listens once the keys are gone.
  final active = ValueNotifier<TextEditingController?>(null);

  @override
  Widget build(BuildContext context) => _SumScope(
    active: active,
    child: Column(
      children: [
        Expanded(child: widget.child),
        ValueListenableBuilder(
          valueListenable: active,
          builder: (context, controller, _) => controller == null
              ? const SizedBox.shrink()
              : SumKeys(controller: controller),
        ),
      ],
    ),
  );
}

class _SumScope extends InheritedWidget {
  const _SumScope({required this.active, required super.child});
  final ValueNotifier<TextEditingController?> active;

  @override
  bool updateShouldNotify(_SumScope old) => active != old.active;
}

/// The keys a number keypad lacks, for typing a sum into [controller].
class SumKeys extends StatelessWidget {
  const SumKeys({super.key, required this.controller});
  final TextEditingController controller;

  void _type(String text) {
    final value = controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    controller.value = TextEditingValue(
      text: value.text.replaceRange(selection.start, selection.end, text),
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Tapping a key keeps the field focused, and the keyboard up.
    return TextFieldTapRegion(
      child: ExcludeFocus(
        child: Material(
          color: theme.colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                for (final (key, label, typed) in const [
                  ('+', 'Plus', '+'),
                  ('−', 'Minus', '-'),
                  ('×', 'Times', '×'),
                  ('÷', 'Divided by', '÷'),
                  ('(', 'Open bracket', '('),
                  (')', 'Close bracket', ')'),
                ])
                  Expanded(
                    child: Semantics(
                      label: label,
                      button: true,
                      excludeSemantics: true,
                      child: TextButton(
                        onPressed: () => _type(typed),
                        child: Text(
                          key,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontFeatures: tabular,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A rupee or percentage field that also takes sums, like a spreadsheet cell:
/// "1000-300" is read as 700, shown as "= ₹700" while typing, and replaced
/// by 700 when the field is left. [onValue] gets the result in hundredths,
/// or null while the text isn't a whole sum.
class MoneyField extends StatefulWidget {
  const MoneyField({
    super.key,
    required this.controller,
    required this.onValue,
    this.focusNode,
    this.style,
    this.decoration = const InputDecoration(),
    this.textAlign = TextAlign.start,
    this.textInputAction,
    this.onSubmitted,
    this.onEditingComplete,
    this.showResult = true,
    this.unit = '₹',
  });
  final TextEditingController controller;
  final ValueChanged<int?> onValue;
  final FocusNode? focusNode;
  final TextStyle? style;
  final InputDecoration decoration;
  final TextAlign textAlign;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;

  /// Whether to show what a sum comes to under the field. Narrow fields
  /// leave it out; they show the result once left.
  final bool showResult;

  /// How the result is labelled: '₹' for rupees, '%' for a percentage.
  final String unit;

  @override
  State<MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<MoneyField> {
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());
  late String _text = widget.controller.text;
  ValueNotifier<TextEditingController?>? _active;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = SumScope._of(context);
  }

  @override
  void didUpdateWidget(MoneyField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _text = widget.controller.text;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.removeListener(_focusChanged);
    if (_active?.value == widget.controller) {
      // Cleared after this frame: the scope may be rebuilding right now.
      final active = _active!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (active.value == widget.controller) active.value = null;
      });
    }
    _ownFocus?.dispose();
    super.dispose();
  }

  void _changed() {
    final text = widget.controller.text;
    if (text == _text) return;
    _text = text;
    widget.onValue(evaluateHundredths(text));
    if (widget.showResult) setState(() {});
  }

  void _focusChanged() {
    final active = _active;
    if (_focus.hasFocus) {
      active?.value = widget.controller;
      return;
    }
    if (active?.value == widget.controller) active?.value = null;
    // Like a spreadsheet, a finished sum shows its result.
    final text = widget.controller.text;
    if (isSum(text)) {
      if (evaluateHundredths(text) case final value?) {
        widget.controller.text = hundredthsText(value);
      }
    }
  }

  String? get _result {
    final text = widget.controller.text;
    if (!widget.showResult || !isSum(text)) return null;
    return switch (evaluateHundredths(text)) {
      final value? when widget.unit == '₹' => '= ${rupees(value)}',
      final value? => '= ${hundredthsText(value)}${widget.unit}',
      null => null,
    };
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    focusNode: _focus,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    autocorrect: false,
    enableSuggestions: false,
    inputFormatters: [sumFormatter],
    textAlign: widget.textAlign,
    textInputAction: widget.textInputAction,
    style: widget.style,
    decoration: widget.decoration.copyWith(helperText: _result),
    onEditingComplete: widget.onEditingComplete,
    onSubmitted: (text) {
      if (isSum(text)) {
        if (evaluateHundredths(text) case final value?) {
          widget.controller.text = hundredthsText(value);
        }
      }
      widget.onSubmitted?.call(widget.controller.text);
    },
  );
}
