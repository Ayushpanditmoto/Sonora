import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../sonora_theme.dart';

const _sonoraGitHubUrl = 'https://github.com/Ayushpanditmoto';

const _drawerDestinations = <({Icon icon, Icon selectedIcon, String label})>[
  (
    icon: Icon(Icons.home_outlined),
    selectedIcon: Icon(Icons.home_rounded),
    label: 'Home',
  ),
  (
    icon: Icon(Icons.search_rounded),
    selectedIcon: Icon(Icons.manage_search_rounded),
    label: 'Search',
  ),
  (
    icon: Icon(Icons.library_music_outlined),
    selectedIcon: Icon(Icons.library_music_rounded),
    label: 'Library',
  ),
];

/// App-wide navigation and project attribution.
///
/// The header is a compact identity row rather than a banner. A drawer is a
/// place to get somewhere, so the destinations sit as close to the top as the
/// app mark allows and stay above the fold on a short screen; a slogan and a
/// decorative wash had pushed them a third of the way down the panel.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    required this.selectedIndex,
    required this.onDestinationSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: math.min(320.0, MediaQuery.sizeOf(context).width * 0.86),
      backgroundColor: SonoraColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: SonoraRadius.panel),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DrawerHeader(onClose: () => Navigator.of(context).pop()),
            const SizedBox(height: 10),
            for (final (index, destination) in _drawerDestinations.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _DrawerNavigationItem(
                  key: ValueKey('drawer-${destination.label.toLowerCase()}'),
                  label: destination.label,
                  icon: index == selectedIndex
                      ? destination.selectedIcon
                      : destination.icon,
                  selected: index == selectedIndex,
                  onTap: () {
                    onDestinationSelected(index);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            const SizedBox(height: 14),
            const _DrawerFooter(),
            // The spare height falls below the content rather than above it, so
            // the panel reads as a list that ends, not as items trapped between
            // a banner and a footer.
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

/// The app mark and a close control, and nothing else.
///
/// A drawer is a list of places to go. The banner this replaced stood 248 dp
/// tall and carried a slogan, a badge and two decorative circles, which pushed
/// Home, Search and Library well down the panel and left them below the fold on
/// a short screen. The mark is kept because it is the app's identity, not a
/// promotion.
class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
      decoration: const BoxDecoration(
        color: SonoraColors.brandWash,
        border: Border(bottom: BorderSide(color: SonoraColors.outline)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: SonoraColors.green,
              borderRadius: SonoraRadius.chip,
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Colors.black,
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sonora',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Open-source music',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: SonoraColors.muted,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close menu',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 20),
            color: SonoraColors.muted,
          ),
        ],
      ),
    );
  }
}

/// Attribution, as one quiet row at the foot of the panel.
///
/// It was its own labelled section, which read as a fourth destination and gave
/// a footer link the weight of a navigation item.
class _DrawerFooter extends StatelessWidget {
  const _DrawerFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SonoraColors.outline)),
      ),
      child: _GitHubCard(
        key: const ValueKey('sonora-github-link'),
        onTap: () {
          Navigator.of(context).pop();
          unawaited(
            launchUrl(
              Uri.parse(_sonoraGitHubUrl),
              mode: LaunchMode.externalApplication,
            ),
          );
        },
      ),
    );
  }
}

class _DrawerNavigationItem extends StatelessWidget {
  const _DrawerNavigationItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final Icon icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: selected ? SonoraColors.selected : Colors.transparent,
        borderRadius: SonoraRadius.control,
        child: InkWell(
          onTap: onTap,
          borderRadius: SonoraRadius.control,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  icon.icon,
                  size: 23,
                  color: selected ? SonoraColors.green : SonoraColors.muted,
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? SonoraColors.text : SonoraColors.muted,
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

class _GitHubCard extends StatelessWidget {
  const _GitHubCard({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 20, 14),
          child: Row(
            children: [
              const Icon(
                Icons.code_rounded,
                color: SonoraColors.muted,
                size: 18,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Made by Ayush Pandit',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'github.com/Ayushpanditmoto',
                      style: TextStyle(fontSize: 11, color: SonoraColors.muted),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_outward_rounded,
                size: 15,
                color: SonoraColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
