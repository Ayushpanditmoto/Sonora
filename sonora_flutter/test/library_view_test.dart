import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonora_flutter/services/download_store.dart';
import 'package:sonora_flutter/ui/app_shell.dart';
import 'package:sonora_flutter/ui/sonora_theme.dart';

const _art = 'assets/art/neon-rain.png';

void main() {
  testWidgets('library tabs keep downloads first and switch saved sections', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final favorites = FavoriteStore();
    final recents = RecentStore();
    final downloads = DownloadStore();
    await favorites.load();
    await recents.load();
    favorites.toggle(_song('liked', 'Liked track'));
    recents.add(_song('recent', 'Recent track'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoriteStoreProvider.overrideWithValue(favorites),
          recentStoreProvider.overrideWithValue(recents),
          downloadStoreProvider.overrideWithValue(downloads),
        ],
        child: MaterialApp(
          theme: SonoraTheme.dark,
          home: const Scaffold(body: LibraryView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Tab, 'Downloads'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Your library')).style?.fontSize, 26);
    expect(find.widgetWithText(Tab, 'Recently played'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Liked songs'), findsOneWidget);
    expect(
      find.text('Tap the download icon on a track to keep it on this device.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(Tab, 'Liked songs'));
    await tester.pumpAndSettle();
    expect(find.text('Liked track'), findsOneWidget);
    expect(find.text('Recent track'), findsNothing);

    await tester.tap(find.widgetWithText(Tab, 'Recently played'));
    await tester.pumpAndSettle();
    expect(find.text('Recent track'), findsOneWidget);
    expect(find.text('Liked track'), findsNothing);
  });
}

MediaItem _song(String id, String title) =>
    MediaItem(id: id, title: title, artist: 'Sonora', extras: {'art': _art});
