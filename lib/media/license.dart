class License {
  const License(this.label, this.url);

  final String label;
  final String url;
}

/// Upstream CC paths map onto the CC URL space.
License? parseLicense(String? code) {
  final clean = code?.trim().replaceAll(RegExp(r'^/+|/+$'), '') ?? '';
  if (clean.isEmpty) return null;

  final parts = clean.split('/');
  if (parts.length < 2 || parts[0].isEmpty || parts[1].isEmpty) return null;

  final label = [
    'CC',
    parts[0].toUpperCase(),
    parts[1],
    if (parts.length > 2 && parts[2].isNotEmpty) parts[2].toUpperCase(),
  ].join(' ');

  return License(label, 'https://creativecommons.org/licenses/$clean/');
}
