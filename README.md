# pishmish — proof-of-concept Gemini browser

A minimal Gemini client for Lazarus built on `TIdGemini` + SynEdit.

- Address bar + Go, identity selector, status bar.
- Fetches with the selected **identity** (a `.crt`/`.key` pair from
  `~/.config/pishmish/idents/`, listed by CN + fingerprint — the directory
  is created on startup) or anonymously. Drop a Lagrange idents pair there
  and it logs you in on `gemini://bbs.geminispace.org/`.
- Gemtext is rendered in SynEdit.
- `Ctrl` + mouse wheel zooms the text.

## Build

Currently no easier process.

You need to edit variables in Makefile in order to build it.
We need Lazarus that is compiled with Indy.
I prefer to use custom Lazarus builds, so I have ~/laz/lazarus-3.0, ~/laz/lazarus-4.0, ~/laz-lazarus-4.2.
Then I build the IDE by also including other components, for instance like this:
```
./lazbuild --build-ide= --add-package ../components-4.2/Indy/Lib/indylaz.lpk --add-package ../components-4.2/rackctls/RackCtlsPkg.lpk --add-package ../components-4.2/acs/packages/laz_acs.lpk
```

If you have Indy installed, adjust paths for your installation, and do

```
make
```

## Run

Currently Indy only supports older OpenSSL versions. So I had to compile
and install one to prefix.

(`LD_LIBRARY_PATH` is set by the script to the custom OpenSSL at
`/opt/openssl-1.0.2u/lib`.)

So I run pishmish like this:

```
LD_LIBRARY_PATH=/opt/openssl-1.0.2u/lib ./pishmish
```

Or you can use `make run`


## Known limits
- This is not a fully featured browser. It was developed to test
  support of Gemini in Indy.
- Blocking fetch on the UI thread.
- Only `text/gemini` is rendered nicely; binary bodies shown raw.
- No history, no bookmarks, no seek configuration, single window.
