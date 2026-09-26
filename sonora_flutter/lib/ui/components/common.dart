import 'package:flutter/material.dart';

import '../shimmer.dart';
import '../sonora_theme.dart';

class NavBackButton extends StatelessWidget {
  const NavBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => IconButton.filledTonal(
        tooltip: 'Open menu',
        onPressed: Scaffold.of(context).openDrawer,
        style: IconButton.styleFrom(
          backgroundColor: SonoraColors.surfaceHigh,
          foregroundColor: SonoraColors.text,
        ),
        icon: const Icon(Icons.menu_rounded),
      ),
    );
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: child,
        ),
      ),
    );
  }
}

/// A row of shimmer cards in place of a collection rail.
class SkeletonCollectionRail extends StatelessWidget {
  const SkeletonCollectionRail({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 202,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, _) => const SizedBox(
          width: 144,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 144, height: 144, radius: 6),
              SizedBox(height: 10),
              SkeletonBox(width: 116, height: 14),
              SizedBox(height: 7),
              SkeletonBox(width: 82, height: 11),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.action,
    this.onAction,
    super.key,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (action != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Text(
                    action!,
                    style: const TextStyle(
                      color: SonoraColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: SonoraColors.muted,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class LibraryEmpty extends StatelessWidget {
  const LibraryEmpty({required this.icon, required this.message, super.key});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Icon(icon, size: 40, color: SonoraColors.muted),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: SonoraColors.muted),
          ),
        ],
      ),
    );
  }
}

/// Swipes a row away to remove a single item, like clearing one track from the
/// history without wiping the rest of it.
class SwipeToRemove extends StatelessWidget {
  const SwipeToRemove({required this.onRemove, required this.child, super.key});

  final VoidCallback onRemove;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: key!,
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: const ColoredBox(
        color: Colors.red,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: 20),
            child: Icon(Icons.delete_outline_rounded, color: Colors.white),
          ),
        ),
      ),
      child: child,
    );
  }
}
