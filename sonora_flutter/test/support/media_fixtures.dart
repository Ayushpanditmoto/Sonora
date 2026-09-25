/// Bytes that start with a real `ftyp` box, so a fixture looks to the download
/// store like a genuine download.
///
/// The store refuses to keep anything it could not hand to ExoPlayer, because a
/// response can arrive at the right length while holding bytes from elsewhere
/// in the file. A fixture of arbitrary text would therefore be rejected instead
/// of downloaded, which is not what these tests are about.
List<int> mediaPayload(int length) {
  const header = [
    0x00,
    0x00,
    0x00,
    0x18, // box length
    0x66,
    0x74,
    0x79,
    0x70, // ftyp
    0x6d,
    0x34,
    0x61,
    0x20, // m4a
  ];
  assert(length >= header.length, 'a container header needs room for itself');
  return [
    ...header,
    ...List<int>.generate(
      length - header.length,
      (index) => index % 251,
      growable: false,
    ),
  ];
}
