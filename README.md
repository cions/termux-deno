# deno for Termux
[![Build Status](https://api.cirrus-ci.com/github/cions/termux-deno.svg)](https://cirrus-ci.com/github/cions/termux-deno)

## Install
[Download](https://api.cirrus-ci.com/v1/artifact/github/cions/termux-deno/deno/deno-aarch64-android/deno)

```sh
curl -fsSL -o ~/.deno/bin/deno https://api.cirrus-ci.com/v1/artifact/github/cions/termux-deno/deno/deno-aarch64-android/deno && chmod +x ~/.deno/bin/deno
```

NOTE: Pre-built binary is optimized for Cortex-A75+ and may not works for older CPUs.

## Build locally

```sh
docker run --privileged --rm multiarch/qemu-user-static --reset -p yes
docker build --output=type=local,dest=artifacts --progress=plain .
```
