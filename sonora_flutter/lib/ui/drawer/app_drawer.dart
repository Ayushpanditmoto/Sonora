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
      width: math.min(332.0, MediaQuery.sizeOf(context).width * 0.88),
      backgroundColor: SonoraColors.background,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DrawerHeader(onClose: () => Navigator.of(context).pop()),
              const _DrawerSectionLabel(label: 'DISCOVER'),
              for (final (index, destination) in _drawerDestinations.indexed)
                _DrawerNavigationItem(
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
              const _DrawerSectionLabel(label: 'PROJECT'),
              _GitHubCard(
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
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 0, 22, 20),
                child: Row(
                  children: [
                    Icon(
                      Icons.favorite_rounded,
                      size: 14,
                      color: SonoraColors.coral,
                    ),
                    SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Open-source music for everyone',
                        style: TextStyle(
                          fontSize: 11,
                          color: SonoraColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 248,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1D2B23), Color(0xFF121614)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -48,
            top: -54,
            child: Container(
              width: 156,
              height: 156,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SonoraColors.green.withValues(alpha: 0.09),
              ),
            ),
          ),
          Positioned(
            right: 44,
            bottom: -64,
            child: Container(
              width: 126,
              height: 126,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SonoraColors.lilac.withValues(alpha: 0.07),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 14, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: SonoraColors.green,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.graphic_eq_rounded,
                        color: Colors.black,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SONORA',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.4,
                              color: SonoraColors.green,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'YOUR MUSIC, YOUR SPACE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                              color: SonoraColors.muted,
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
                const Spacer(),
                const Text(
                  'Find your next\nfavorite sound.',
                  style: TextStyle(
                    fontSize: 27,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: SonoraColors.green.withValues(alpha: 0.18),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: SonoraColors.green,
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox.square(dimension: 6),
                      ),
                      SizedBox(width: 7),
                      Text(
                        'OPEN SOURCE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: SonoraColors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: SonoraColors.muted,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Divider(height: 1, color: Color(0xFF2A302C))),
        ],
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
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Material(
        color: selected ? const Color(0xFF213129) : Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? SonoraColors.green.withValues(alpha: 0.14)
                        : SonoraColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    icon.icon,
                    size: 20,
                    color: selected ? SonoraColors.green : SonoraColors.muted,
                  ),
                ),
                const SizedBox(width: 13),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? SonoraColors.text : SonoraColors.muted,
                  ),
                ),
                const Spacer(),
                if (selected)
                  Container(
                    width: 4,
                    height: 22,
                    decoration: BoxDecoration(
                      color: SonoraColors.green,
                      borderRadius: BorderRadius.circular(4),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Material(
        color: SonoraColors.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF303832)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: SonoraColors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.code_rounded,
                    color: SonoraColors.green,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Made by Ayush Pandit',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'github.com/Ayushpanditmoto',
                        style: TextStyle(
                          fontSize: 10,
                          color: SonoraColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_outward_rounded,
                  size: 18,
                  color: SonoraColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
