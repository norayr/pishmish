#!/bin/bash
# Build and run the POC Gemini browser.
# Requires the Irvine lib and SynEdit (Lazarus) packages installed.
set -e
cd "$(dirname "$0")"
/home/inky/laz/lazarus-4.2/lazbuild gemini_browser.lpi "$@"
LD_LIBRARY_PATH=/opt/openssl-1.0.2u/lib ./pishmish