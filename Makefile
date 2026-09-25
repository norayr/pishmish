# Build and run pishmish.
#
# pishmish needs the lazarus LCL and the indy package (indylaz). Lazarus does
# not ship indy, so fetch it once and register it with your lazarus:
#
#   lazbuild --add-package=/path/to/Indy/Lib/indylaz.lpk
#
# With a normal debian, arch or gentoo lazarus 'make' is all you need.
#
# If your lazarus lives somewhere else, or if you build it from git like i do,
# point this makefile at it:
#
#   make LAZBUILD=/home/you/laz/lazarus/lazbuild \
#        LAZCFG="--primary-config-path=$HOME/.lazarus-git --ws=gtk2"
#
# SSL_LIB is only needed when the openssl libraries are not in the default
# linker path. My own build is in makefile_noch.

LAZBUILD ?= lazbuild
LAZCFG    ?=
PROJECT   = pishmish.lpi
TARGET    = pishmish
SSL_LIB  ?=
FLAGS    ?=

.PHONY: all build run clean

all: build

build:
	$(LAZBUILD) $(LAZCFG) $(PROJECT) $(FLAGS)

run: build
	LD_LIBRARY_PATH=$(SSL_LIB):$$LD_LIBRARY_PATH ./$(TARGET)

clean:
	rm -f $(TARGET)
	rm -rf lib
