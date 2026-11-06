import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Full-width surface card with the app's large corner radius.
class PocketCard extends StatelessWidget {
  const PocketCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = 28,
    this.semanticLabel,
    this.clip = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final String? semanticLabel;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final BorderRadius shape = BorderRadius.circular(radius);
    final Widget content = Padding(padding: padding, child: child);

    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      container: true,
      child: Material(
        color: color ?? AppColors.surface(brightness),
        shape: RoundedRectangleBorder(
          borderRadius: shape,
          side: BorderSide(color: borderColor ?? AppColors.border(brightness)),
        ),
        clipBehavior: clip ? Clip.antiAlias : Clip.none,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                borderRadius: shape,
                splashColor: AppColors.accent(brightness)
                    .withValues(alpha: 0.08),
                child: content,
              ),
      ),
    );
  }
}

/// Pill-shaped filter/choice chip with a checkmark-free design consistent with
/// the reference art direction.
class PocketChip extends StatelessWidget {
  const PocketChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.leading,
    this.count,
    this.semanticLabel,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;
  final int? count;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final Color accent = AppColors.accent(brightness);
    final Color textColor = selected
        ? AppColors.accentText(brightness)
        : AppColors.textPrimary(brightness);

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? label,
      child: Material(
        color: selected
            ? accent.withValues(alpha: 0.16)
            : AppColors.raised(brightness),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? accent.withValues(alpha: 0.55)
                : AppColors.border(brightness),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (leading != null) ...<Widget>[
                  IconTheme(
                    data: IconThemeData(size: 15, color: textColor),
                    child: leading!,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: textColor,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                if (count != null) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: AppColors.textSecondary(brightness)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small uppercase label used for metadata ("12 MB", "English").
class MetaLabel extends StatelessWidget {
  const MetaLabel(
    this.text, {
    super.key,
    this.icon,
    this.color,
    this.maxLines = 1,
  });

  final String text;
  final IconData? icon;
  final Color? color;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final Color resolved = color ?? AppColors.textSecondary(brightness);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 13, color: resolved),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: resolved),
          ),
        ),
      ],
    );
  }
}

/// Status dot + label for job state on cards.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.showSpinner = false,
    this.icon,
  });

  final String label;
  final Color color;
  final bool showSpinner;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showSpinner)
              SizedBox(
                width: 9,
                height: 9,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: color,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 11, color: color)
            else
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// Screen-level actions that lead nowhere must not exist; this helper keeps
/// empty/error surfaces informative and actionable.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.illustration,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String message;
  final Widget? illustration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (illustration != null) ...<Widget>[
            illustration!,
            const SizedBox(height: 22),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondary(brightness)),
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
          if (secondaryLabel != null && onSecondary != null) ...<Widget>[
            const SizedBox(height: 4),
            TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ],
      ),
    );
  }
}

/// Inline error block with retry.
class ErrorBlock extends StatelessWidget {
  const ErrorBlock({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final Color danger = AppColors.dangerFor(Theme.of(context).brightness);
    return PocketCard(
      color: danger.withValues(alpha: 0.06),
      borderColor: danger.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.error_outline_rounded, size: 20, color: danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ],
      ),
    );
  }
}
