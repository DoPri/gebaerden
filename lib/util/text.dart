final _keep = RegExp('[^a-z0-9]');

/// Ignores case, umlaut spelling and punctuation.
String normalizeAnswer(String value) => value
    .toLowerCase()
    .replaceAll('ß', 'ss')
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll(_keep, '');

bool answersMatch(String typed, String expected) {
  final a = normalizeAnswer(typed);
  return a.isNotEmpty && a == normalizeAnswer(expected);
}

/// DIN 5007-1. Codepoint order would put Baum before Bär.
String collateDe(String value) => value
    .toLowerCase()
    .replaceAll('ä', 'a')
    .replaceAll('ö', 'o')
    .replaceAll('ü', 'u')
    .replaceAll('ß', 'ss');

String count(int n, String one, String many) => '$n ${n == 1 ? one : many}';

int compareDe(String a, String b) {
  final folded = collateDe(a).compareTo(collateDe(b));
  // Bar and Bär fold alike.
  return folded != 0 ? folded : a.compareTo(b);
}
