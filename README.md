[![Build Status](https://api.cirrus-ci.com/github/cions/termux-deno.svg)](https://cirrus-ci.com/github/cions/termux-deno)

[Download](https://api.cirrus-ci.com/v1/artifact/github/cions/termux-deno/deno/deno-aarch64-android/deno)

```sh
docker run --privileged --rm multiarch/qemu-user-static --reset -p yes
docker build --output=type=local,dest=artifacts --progress=plain .
```
