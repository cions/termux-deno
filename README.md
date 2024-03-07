[![Build Status](https://api.cirrus-ci.com/github/cions/termux-deno.svg)](https://cirrus-ci.com/github/cions/termux-deno)

[Download for latest binary](https://api.cirrus-ci.com/v1/artifact/github/cions/termux-deno/deno/deno-aarch64-android/deno).

---

## `termux-deno` script

This script installs or updates latest Deno on Termux.

```sh
curl -sSL https://raw.githubusercontent.com/cions/termux-deno/main/termux-deno.sh | bash
```

---

## Docker example

```sh
docker run --privileged --rm multiarch/qemu-user-static --reset -p yes
docker build --output=type=local,dest=artifacts --progress=plain .
```
