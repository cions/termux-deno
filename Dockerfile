# syntax=docker/dockerfile:1

# curl -fsSL https://raw.githubusercontent.com/rust-lang/crates.io-index/master/de/no/deno | tail -n1 | jq -r '.vers'
ARG DENO_VERSION="v2.0.1"
# curl -fsSL https://raw.githubusercontent.com/denoland/deno/main/Cargo.lock | grep -A 1 'name = "v8"'
ARG RUSTY_V8_VERSION="v0.106.0"


FROM --platform=linux/amd64 golang:latest AS resolver

COPY resolve.go .
RUN go run resolve.go \
        packages-cf.termux.dev \
        github.com \
        chromium.googlesource.com \
        crates.io \
        index.crates.io \
        static.crates.io \
    > /hosts


FROM --platform=linux/amd64 rust:latest AS build-rusty_v8

ENV HOST="x86_64-unknown-linux-gnu" \
    TARGET="aarch64-linux-android" \
    LLVM_VERSION="18" \
    ANDROID_NDK_VERSION="r27b" \
    ANDROID_API="29"
ENV ANDROID_NDK="/opt/android-ndk-${ANDROID_NDK_VERSION}"
ENV ANDROID_NDK_BIN="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin" \
    ANDROID_NDK_SYSROOT="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/sysroot" \
    CLANG_BASE_PATH="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64"
ENV PATH="/usr/lib/llvm-${LLVM_VERSION}/bin:${PATH}" \
    BINDGEN_EXTRA_CLANG_ARGS="--sysroot=${ANDROID_NDK_SYSROOT}" \
    CC_aarch64_linux_android="${ANDROID_NDK_BIN}/${TARGET}${ANDROID_API}-clang" \
    CXX_aarch64_linux_android="${ANDROID_NDK_BIN}/${TARGET}${ANDROID_API}-clang++" \
    AR_aarch64_linux_android="${ANDROID_NDK_BIN}/llvm-ar" \
    NM_aarch64_linux_android="${ANDROID_NDK_BIN}/llvm-nm" \
    CC_x86_64_unknown_linux_gnu="/usr/lib/llvm-${LLVM_VERSION}/bin/clang" \
    CXX_x86_64_unknown_linux_gnu="/usr/lib/llvm-${LLVM_VERSION}/bin/clang++" \
    AR_x86_64_unknown_linux_gnu="/usr/lib/llvm-${LLVM_VERSION}/bin/llvm-ar" \
    NM_x86_64_unknown_linux_gnu="/usr/lib/llvm-${LLVM_VERSION}/bin/llvm-nm"
ENV CC="${CC_aarch64_linux_android}" \
    CXX="${CXX_aarch64_linux_android}" \
    AR="${AR_aarch64_linux_android}" \
    NM="${NM_aarch64_linux_android}" \
    BUILD_CC="${CC_x86_64_unknown_linux_gnu}" \
    BUILD_CXX="${CXX_x86_64_unknown_linux_gnu}" \
    BUILD_AR="${AR_x86_64_unknown_linux_gnu}" \
    BUILD_NM="${NM_x86_64_unknown_linux_gnu}"
ENV CARGO_BUILD_TARGET_DIR="/cargo-build" \
    CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="${CC_aarch64_linux_android}" \
    CARGO_NET_GIT_FETCH_WITH_CLI="true"

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
 && echo 'APT::Get::Assume-Yes "true";' > /etc/apt/apt.conf.d/assumeyes \
 && echo 'APT::Quiet "true";' > /etc/apt/apt.conf.d/quiet \
 && echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/norecommends \
 && echo 'APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keepdebs \
 && echo "deb https://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-${LLVM_VERSION} main" > /etc/apt/sources.list.d/llvm.list \
 && curl -fsSL -o /etc/apt/trusted.gpg.d/apt.llvm.org.asc https://apt.llvm.org/llvm-snapshot.gpg.key \
 && apt-get update \
 && apt-get install \
        clang-${LLVM_VERSION} \
        libc++1-${LLVM_VERSION}  \
        libclang-rt-${LLVM_VERSION}-dev \
        lld-${LLVM_VERSION} \
        llvm-${LLVM_VERSION}

RUN rustup toolchain install stable \
 && rustup default stable \
 && rustup target add "${TARGET}"

RUN curl -fsSLO "https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux.zip" \
 && unzip -q -d /opt "android-ndk-${ANDROID_NDK_VERSION}-linux.zip" \
 && rm "android-ndk-${ANDROID_NDK_VERSION}-linux.zip" \
 && ln -sf "${TARGET}/asm" "${ANDROID_NDK_SYSROOT}/usr/include/asm"

COPY config-rusty_v8.toml .cargo/config.toml

ARG RUSTY_V8_VERSION
ADD --link https://github.com/denoland/rusty_v8.git#${RUSTY_V8_VERSION} rusty_v8

COPY *.patch .
RUN patch -d rusty_v8 -p1 < rusty_v8-cross-toolchain.patch

RUN env -C rusty_v8 cargo +stable build --release --locked -vv \
 && cp "${CARGO_BUILD_TARGET_DIR}/${TARGET}/release/gn_out/obj/librusty_v8.a" /librusty_v8.a \
 && cp "${CARGO_BUILD_TARGET_DIR}/${TARGET}/release/gn_out/src_binding.rs" /src_binding.rs


FROM --platform=linux/arm64 termux/termux-docker:aarch64 AS build-deno

COPY --from=resolver /hosts /system/etc/hosts

USER system

RUN --mount=type=cache,target=/data/data/com.termux/files/usr/var/lib/apt,uid=1000,gid=1000,sharing=locked \
    --mount=type=cache,target=/data/data/com.termux/cache/apt,uid=1000,gid=1000,sharing=locked \
    echo 'APT::Get::Assume-Yes "true";' > /data/data/com.termux/files/usr/etc/apt/apt.conf.d/assumeyes \
 && echo 'APT::Quiet "true";' > /data/data/com.termux/files/usr/etc/apt/apt.conf.d/quiet \
 && echo 'APT::Install-Recommends "false";' > /data/data/com.termux/files/usr/etc/apt/apt.conf.d/norecommends \
 && echo 'APT::Keep-Downloaded-Packages "true";' > /data/data/com.termux/files/usr/etc/apt/apt.conf.d/keepdebs \
 && echo 'DPkg::Options { "--force-confdef"; "--force-confold"; };' > /data/data/com.termux/files/usr/etc/apt/apt.conf.d/confold \
 && apt-get update \
 && apt-get install \
        binutils-is-llvm \
        cmake \
        git \
        libandroid-stub \
        libc++ \
        make \
        openssl \
        patch \
        protobuf \
        rust \
        termux-elf-cleaner \
 && ln -sf aarch64-linux-android/asm /data/data/com.termux/files/usr/include/asm

ENV CARGO_BUILD_TARGET_DIR="/data/data/com.termux/files/home/cargo-build" \
    CARGO_INSTALL_ROOT="/data/data/com.termux/files/home/cargo-install" \
    CARGO_NET_GIT_FETCH_WITH_CLI="true"

COPY --from=build-rusty_v8 --chown=system /librusty_v8.a /data/data/com.termux/files/usr/tmp/librusty_v8.a
COPY --from=build-rusty_v8 --chown=system /src_binding.rs /data/data/com.termux/files/usr/tmp/src_binding.rs

COPY --chown=system config-deno.toml /data/data/com.termux/files/home/.cargo/config.toml

ARG DENO_VERSION
RUN --mount=type=cache,target=/data/data/com.termux/files/home/.cargo/registry,uid=1000,gid=1000,sharing=locked \
    --mount=type=cache,target=${CARGO_BUILD_TARGET_DIR},uid=1000,gid=1000,sharing=locked \
    cargo install --locked -vv --version="${DENO_VERSION#v}" deno

RUN termux-elf-cleaner /data/data/com.termux/files/home/cargo-install/bin/deno


FROM scratch

COPY --from=build-deno /data/data/com.termux/files/home/cargo-install/bin/deno /
