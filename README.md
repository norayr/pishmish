# pishmish — proof-of-concept Gemini browser

A minimal Gemini client for Lazarus built on `TIdGemini` + SynEdit.

- Address bar + Go, identity selector, status bar.
- Fetches with the selected **identity** (a `.crt`/`.key` pair from
  `~/.config/pishmish/idents/`, listed by CN + fingerprint — the directory
  is created on startup) or anonymously. Drop a Lagrange idents pair there
  and it logs you in on `gemini://bbs.geminispace.org/`.
- Gemtext is rendered in SynEdit, gutter hidden. `=>` rocketlinks show only
  the label (the URL is not printed); hovering a link underlines the label
  (heliko-style `PixelsToRowColumn` + `OnPaint`) and the **status bar shows
  the link target**; clicking navigates. Relative targets are resolved
  against the current page. Input prompts (status 10/11) pop an
  `InputQuery` and resend.
- `Ctrl` + mouse wheel zooms the text (same binding as heliko).

## Build & run

```
./run.sh
```

(`LD_LIBRARY_PATH` is set by the script to the custom OpenSSL at
`/opt/openssl-1.0.2u/lib`.)

## Interesting bits

- SynEdit redeclares its mouse/paint events as bare `property OnMouseMove;`
  etc.; in `{$mode Delphi}` assign handlers **without** `@`
  (`GmiView.OnMouseMove := GmiMouseMove;`) — the `@` form fails with FPC
  error 4004 (minimal reproduction in `../etest`).
- Link resolution uses `TIdURI`; `Path + Document` form the request path
  (single-segment URLs land in `Document`). `TIdURI.Port` is a string.
- Self-signed server certificates are accepted (the Gemini trust model: the
  application asks the user — here `VerifyMode`/`OnVerifyPeer` are left at
  their defaults; hook them for a "trust this certificate?" prompt).

## Known limits

- Blocking fetch on the UI thread.
- Only `text/gemini` is rendered nicely; binary bodies shown raw.
- No history, no bookmarks, no seek configuration, single window.