import 'package:flutter/material.dart';

class SearchField extends StatefulWidget {
  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  /// Show the clear button.
  final bool showClearButton;

  /// Make the field read-only (useful for custom pickers).
  final bool readOnly;

  /// Called when the field is tapped (useful with readOnly=true).
  final VoidCallback? onTap;

  /// Icon at the trailing side (defaults to search).
  final IconData trailingIcon;

  /// Override the text input action (default: search).
  final TextInputAction textInputAction;

  /// Provide a focus node so parents can react to focus changes.
  final FocusNode? focusNode;

  /// Show clear button on the leading side (matches screenshots).
  final bool clearOnLeft;

  const SearchField({
    super.key,
    required this.hint,
    this.controller,
    this.onSubmitted,
    this.onChanged,
    this.onClear,
    this.showClearButton = true,
    this.readOnly = false,
    this.onTap,
    this.trailingIcon = Icons.search_rounded,
    this.textInputAction = TextInputAction.search,
    this.focusNode,
    this.clearOnLeft = true,
  });

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _ctrl;
  bool _ownController = false;

  bool get _hasText => _ctrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownController = true;
      _ctrl = TextEditingController();
    } else {
      _ctrl = widget.controller!;
    }
    _ctrl.addListener(() {
      if (mounted) setState(() {}); // refresh clear/search visibility
    });
  }

  @override
  void dispose() {
    if (_ownController) _ctrl.dispose();
    super.dispose();
  }

  void _handleClear() {
    _ctrl.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  void _submitCurrent() {
    widget.onSubmitted?.call(_ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Colors that adapt to theme
    final onSurface = cs.onSurface;
    final iconActive = onSurface.withOpacity(0.65);
    final iconInactive = onSurface.withOpacity(0.30);
    final hintColor = onSurface.withOpacity(0.50);
    final outline = cs.outline;

    // Leading (prefix): Clear "X"
    final Widget? prefix = widget.showClearButton
        ? IconButton(
            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
            icon: Icon(
              Icons.close_rounded,
              color: (_hasText && !widget.readOnly) ? iconActive : iconInactive,
            ),
            onPressed: (_hasText && !widget.readOnly) ? _handleClear : null,
          )
        : null;

    // Trailing (suffix): Search icon -> triggers submit
    final Widget suffix = IconButton(
      tooltip: MaterialLocalizations.of(context).searchFieldLabel,
      icon: Icon(widget.trailingIcon, color: iconActive),
      onPressed: widget.readOnly ? null : _submitCurrent,
    );

    final usePrefixForClear = widget.clearOnLeft;

    final borderRadius = const BorderRadius.all(Radius.circular(18));
    final InputBorder enabled = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: outline, width: 1),
    );
    final InputBorder focused = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: cs.primary, width: 2),
    );

    return TextField(
      controller: _ctrl,
      focusNode: widget.focusNode,
      readOnly: widget.readOnly,
      onTap: widget.onTap,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      textInputAction: widget.textInputAction,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: TextStyle(color: hintColor),
        isDense: true,
        filled: true,
        // Use themed surface for both light & dark (plays nice with M3)
        fillColor: theme.inputDecorationTheme.fillColor ?? cs.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),

        // Prefix/Suffix per layout
        prefixIcon: usePrefixForClear ? prefix : suffix,
        suffixIcon: usePrefixForClear ? suffix : prefix,

        // Borders
        border: enabled,
        enabledBorder: enabled,
        focusedBorder: focused,
      ),
      style: theme.textTheme.bodyLarge, // inherits proper text color
      cursorColor: cs.primary,
    );
  }
}
