// The build fills the two tokens in. Only the config below is ours.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // CanvasKit draws every glyph from a font file and fetches Roboto plus
    // the symbol fallbacks from fonts.gstatic.com. tools/web_assets.py puts
    // them under this path, so nothing is pulled off the net at runtime.
    fontFallbackBaseUrl: "fonts/",
  },
});
