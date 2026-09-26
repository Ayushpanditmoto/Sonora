import 'dart:convert';

import 'package:dart_des/dart_des.dart';

/// The DES key JioSaavn encrypts every media url with.
const _mediaUrlKey = '38346591';

/// Matches the bitrate JioSaavn bakes into the media url, which always sits
/// just before the file extension: `.../c018551b00a2_96.mp4`.
final _bitrateInUrl = RegExp(r'_\d+(\.[A-Za-z0-9]+)$');

/// Turns JioSaavn's `encrypted_media_url` into a playable url, or null when the
/// value is missing or does not decrypt to one.
///
/// The JioSaavn web API never sends a ready-to-play url the way the old
/// `saavn.sumit.co` proxy did. It sends a DES encrypted string instead, and the
/// only way to reach the audio is to decrypt it here. `saavn_play` ships this
/// routine in `src/utils/link.dart` but does not export it, so it is
/// reimplemented rather than reached into, which would tie us to a private
/// file that can move in any patch release.
///
/// `pointycastle` cannot be used for this: as of 4.0 it only ships Triple DES,
/// so single DES comes from `dart_des`, the same library `saavn_play` uses.
String? decryptMediaUrl(String? encryptedMediaUrl) {
  if (encryptedMediaUrl == null || encryptedMediaUrl.isEmpty) return null;
  try {
    final decipher = DES(
      key: ascii.encode(_mediaUrlKey),
      mode: DESMode.ECB,
      paddingType: DESPaddingType.PKCS7,
    );
    final url = utf8
        .decode(decipher.decrypt(base64Decode(encryptedMediaUrl)))
        .trim();
    return url.startsWith('http') ? url : null;
  } catch (_) {
    // A track whose url does not decrypt has no audio to offer, which is
    // treated the same as a track that never sent one.
    return null;
  }
}

/// The best url JioSaavn serves for the track described by [moreInfo].
///
/// The decrypted url carries one bitrate. Higher bitrate variants of the same
/// path are served as well, but only for tracks mastered that way, so asking a
/// non 320kbps track for one would 404 mid-playback. The flag the API reports is
/// what decides whether the upgrade is safe.
String? bestMediaUrl(Map<String, dynamic> moreInfo) {
  final url = decryptMediaUrl(moreInfo['encrypted_media_url'] as String?);
  if (url == null) return null;
  final has320 = moreInfo['320kbps'];
  if (has320 != true && has320 != 'true') return url;
  return url.replaceAllMapped(
    _bitrateInUrl,
    (match) => '_320${match.group(1)}',
  );
}
