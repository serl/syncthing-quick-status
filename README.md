# syncthing-quick-status

[![Build Status](https://api.travis-ci.com/serl/syncthing-quick-status.svg)](https://travis-ci.com/serl/syncthing-quick-status)

> Because sometimes I'm too lazy to open the browser.

An elegant(?), fast(?) and colorful(!) solution to have the complete(?) `syncthing` status in a jiffy(?).

## Dependencies

* bash 4+
* `curl`
* `jq`
* `coreutils` (for `numfmt`)
* works on Linux as well as on MacOS

## Env variables

* `SYNCTHING_API_KEY`.
* `SYNCTHING_CONFIG_FILE`, the place where it'll look for the api key if not given in the variable above. Defaults to `$HOME/.config/syncthing/config.xml` on Linux and `$HOME/Library/Application Support/Syncthing/config.xml` on MacOS.
* `SYNCTHING_ADDRESS`, defaults to `localhost:8384`.

## Arguments

* `-v`: verbose, show devices/folder ids and a selection of latest log messages (which is specially helpful for more details about "out of sync" folders).
