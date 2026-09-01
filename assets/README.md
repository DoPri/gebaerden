# Assets

## Icon

`icon.svg` is the bare hand. `icon-store.svg` is the same hand carrying the DGS
lettering.

`tools/icons.py` picks between them per target size. Everything from 76 pixels
up gets the lettering, below that the letters run into one blur and the bare
hand goes out instead. The threshold is `LETTERED_FROM` in that script.

Both are one flat color on a transparent ground. The ground has to stay
transparent: `ic_launcher.xml` points `monochrome` at the same foreground the
adaptive icon uses, and Android builds the themed icon from its alpha channel
alone, so a background rectangle would turn it into a solid block.

Render every size again after a change:

```bash
python3 tools/icons.py
```

## Badges

`badges/` holds the install badges the README shows.

- `google-play.png` comes from
  `play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png`.
  The Google Play brand guidelines require it unaltered.
- `github.png` comes from `NeoApplications/Neo-Backup`, commit `034b226`.
- `obtainium.png` comes from `ImranR98/Obtainium`, commit `b1c8ac6`.

All three are 646 by 250 pixels and carry the same clear space around the
badge, so `height="80"` in the README renders them at one size.
