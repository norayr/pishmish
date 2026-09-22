# pishmish — proof-of-concept Gemini browser

A minimal Gemini client for Lazarus built on `TIdGemini` + SynEdit.

- Address bar + Go, identity selector, status bar.
- Fetches with the selected **identity** (a `.crt`/`.key` pair from
  `~/.config/pishmish/idents/`, listed by CN + fingerprint — the directory
  is created on startup) or anonymously. Drop a Lagrange idents pair there
  and it logs you in on `gemini://bbs.geminispace.org/`.
- Gemtext is rendered in SynEdit.
- `Ctrl` + mouse wheel zooms the text.

## Build & run

```
./run.sh
```

(`LD_LIBRARY_PATH` is set by the script to the custom OpenSSL at
`/opt/openssl-1.0.2u/lib`.)

## Known limits

- Blocking fetch on the UI thread.
- Only `text/gemini` is rendered nicely; binary bodies shown raw.
- No history, no bookmarks, no seek configuration, single window.
