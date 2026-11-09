import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_home_theme.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

/// A light Help section card: a title header plus either a single prose body or
/// a list of bullet items.
///
/// The title is the semantic heading for the group and the inner title [Text]
/// is excluded so it is announced exactly once. [body] renders as one grouped
/// text node; [items] renders one semantic node per bullet so a screen reader
/// can move through the list item by item. Exactly one of [body] and [items]
/// must be supplied.
class HelpSectionCard extends StatelessWidget {
  /// The section heading (also the semantic header label).
  final String title;

  /// Optional single prose lead-in rendered above [items].
  final String? intro;

  /// Bullet items, rendered one per semantic node. Leading markers must not be
  /// included — the widget prepends the visual bullet.
  final List<String>? items;

  /// A single grouped body, rendered as one text node.
  final String? body;

  const HelpSectionCard({
    super.key,
    required this.title,
    this.intro,
    this.items,
    this.body,
  }) : assert(
         (body == null) != (items == null),
         'Supply exactly one of body or items.',
       );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyLarge?.copyWith(height: 1.4);
    final itemList = items;

    return Container(
      margin: const EdgeInsets.only(bottom: kSpace16),
      padding: const EdgeInsets.all(kSpace16),
      decoration: BoxDecoration(
        color: kHomeSurfaceCard,
        borderRadius: BorderRadius.circular(kRadius24),
        boxShadow: kHomeShadowSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            // The section title is the semantic heading for the group. The
            // inner Text is excluded so the title is exposed exactly once (no
            // duplicate label from the visual text).
            container: true,
            header: true,
            label: title,
            child: ExcludeSemantics(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: kSpace12),
          if (intro != null)
            Semantics(container: true, child: Text(intro!, style: textStyle)),
          if (itemList != null)
            for (var i = 0; i < itemList.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == itemList.length - 1 ? 0 : kSpace4,
                ),
                // One node per bullet so each item is its own reading stop.
                child: Semantics(
                  container: true,
                  child: Text('• ${itemList[i]}', style: textStyle),
                ),
              ),
          if (body != null) Text(body!, style: textStyle),
        ],
      ),
    );
  }
}
