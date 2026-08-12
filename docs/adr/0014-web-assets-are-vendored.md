# 0014 The web build ships what it loads

Status: accepted

## Context

A Flutter web build fetches several things from Google at runtime. The
bootstrap pulls CanvasKit from www.gstatic.com. The engine downloads Roboto
from fonts.gstatic.com on every start, because CanvasKit draws every glyph
from a font file and carries none. It downloads a Noto face on top of that for
any character Roboto lacks, which here is the arrow in the trainer.

drift needs `sqlite3.wasm` and `drift_worker.js` in the browser, and both
belong to a package version. A mismatch shows up as a database that never
opens.

None of this is visible in a build log. It shows up as a blank page in a
locked down network, as a page that phones home on every visit, and as a
version skew after a dependency bump.

## Decision

Everything the page loads at runtime comes from its own origin. The stills and
the videos stay on the SignDict CDN, they are the content, not the app.

`flutter build web --no-web-resources-cdn` keeps CanvasKit local.
`web/flutter_bootstrap.js` sets `fontFallbackBaseUrl` to `fonts/`, so the
engine takes the fonts from next to the app.

`tools/web_assets.py` writes all four files and derives every version rather
than repeating it. The drift worker is copied out of the resolved drift
package, `sqlite3.wasm` comes from the release named by `pubspec.lock`, and
the two font addresses are read out of the installed engine sources, where the
paths are pinned per Flutter version. A path the script cannot find is a hard
stop, since the alternative is an image that builds and then shows nothing.

The files are generated and stay out of the repository, the way `build_runner`
output does.

`Content-Security-Policy: default-src 'self'` in the container turns this from
an intention into a check. A request that escapes is refused and logged rather
than sent.

## Consequences

A Flutter update can move the font paths. The script fails loudly, the fix is
a rebuild, and nobody has to notice tofu on a screen first.

`flutter build web` without the script and the flag produces a page that works
and quietly loads from Google again. The README says so, CI builds the image,
and only that path is the supported one.

Without `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` drift
falls back from OPFS to IndexedDB, which is slower and works. Setting them is
not an option: `require-corp` blocks the videos, since the CDN sends no
`cross-origin-resource-policy`.
