# Build and run the POC Gemini browser.
# Requires the Indy lib (indylaz) and SynEdit (Lazarus) packages installed.
# I build the Lazarus IDE like this:
# ./lazbuild --build-ide= --add-package ../components-4.2/Indy/Lib/indylaz.lpk

LAZBUILD := /home/inky/laz/lazarus-4.2/lazbuild
PROJECT  := gemini_browser.lpi
TARGET   := pishmish
SSL_LIB  := /opt/openssl-1.0.2u/lib
FLAGS    :=

.PHONY: all build run clean

all: build

build:
	$(LAZBUILD) $(PROJECT) $(FLAGS)

run: build
	LD_LIBRARY_PATH=$(SSL_LIB) ./$(TARGET)

clean:
	rm -f $(TARGET)
	rm -rf lib
