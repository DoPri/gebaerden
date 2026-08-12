# Icon

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
