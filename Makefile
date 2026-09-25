# Build and run the POC Gemini browser.
# Requires the Indy lib (indylaz) and SynEdit (Lazarus) packages installed.
# I build the Lazarus IDE like this:
# ./lazbuild --primary-config-path="$HOME/.lazarus-git" --build-ide= --add-package ../components/Indy/Lib/indylaz.lpk

LAZBUILD := /home/inky/laz/lazarus/lazbuild
# the IDE config must match the Lazarus tree, otherwise lazbuild fails with
# 'Package "IdeSynedit" is installed but no valid package file (.lpk) was found'
LAZCFG    := --primary-config-path=$(HOME)/.lazarus-git --ws=gtk2
PROJECT  := gemini_browser.lpi
TARGET   := pishmish
SSL_LIB  := /opt/openssl-1.0.2u/lib
FLAGS    :=

.PHONY: all build run clean

all: build

build:
	$(LAZBUILD) $(LAZCFG) $(PROJECT) $(FLAGS)

run: build
	LD_LIBRARY_PATH=$(SSL_LIB) ./$(TARGET)

test:
	LD_LIBRARY_PATH=/opt/openssl-1.0.2u/lib ./pishmish

clean:
	rm -f $(TARGET)
	rm -rf lib
