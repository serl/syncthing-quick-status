# syncthing-quick-status

[![Build Status](https://travis-ci.org/serl/syncthing-quick-status.svg)](https://travis-ci.org/serl/syncthing-quick-status)

> Because sometimes I'm too lazy to open the browser.

An elegant(?), fast(?) and colorful(!) solution to have the complete(?) `syncthing` status in a jiffy(?).

## Dependencies

* bash 4
* `curl`
* `jq`

## Env variables

* `SYNCTHING_API_KEY`, defaults to _what?_.
* `SYNCTHING_CONFIG_FILE`, the place where it'll look for the api key if not given in the above variable. Defaults to `$HOME/.config/syncthing/config.xml`.
* `SYNCTHING_ADDRESS`, defaults to `localhost:8384`.

## Arguments

* `-v`: verbose, show devices/folder ids and a selection of latest log messages.
