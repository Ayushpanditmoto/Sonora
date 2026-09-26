/// Counts and sizes, formatted for a label.
///
/// These are read by rows, tabs and the queue rather than by any one screen, so
/// they live apart from the views and have a single spelling of each.
library;

/// `1 track`, `12 tracks`. Avoids a second plural rule in every caller.
String plural(int count, String noun) =>
    '$count ${count == 1 ? noun : '${noun}s'}';

/// A byte count as KB or MB.
///
/// Downloads are usually megabytes, and the exact count matters less than which
/// unit it is in.
String formatSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
