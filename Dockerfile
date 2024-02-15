# curl -fsSL https://raw.githubusercontent.com/rust-lang/crates.io-index/master/de/no/deno | tail -n1 | jq -r '.vers'
ARG DENO_VERSION="v1.40.5"
# curl -fsSL https://raw.githubusercontent.com/denoland/deno/main/Cargo.lock | grep -A 1 'name = "(v8|libz-sys)"'
ARG RUSTY_V8_VERSION="v0.83.2"
ARG LIBZ_SYS_VERSION="1.1.12"


FROM --platform=linux/amd64 golang:latest AS resolver

COPY resolve.go /

RUN go run /resolve.go \
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
    LLVM_VERSION="17" \
    ANDROID_NDK_VERSION="r26b" \
    ANDROID_NDK_MAJOR_VERSION="26" \
    ANDROID_API="29"
ENV ANDROID_NDK="/opt/android-ndk-${ANDROID_NDK_VERSION}"
ENV ANDROID_NDK_BIN="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin" \
    ANDROID_NDK_SYSROOT="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/sysroot" \
    CLANG_BASE_PATH="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64"

RUN echo "deb https://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-${LLVM_VERSION} main" > /etc/apt/sources.list.d/llvm.list \
 && curl -fsSL -o /etc/apt/trusted.gpg.d/apt.llvm.org.asc https://apt.llvm.org/llvm-snapshot.gpg.key \
 && apt-get update -qq \
 && apt-get install -qy --no-install-recommends \
        clang-${LLVM_VERSION} \
        libc++1-${LLVM_VERSION}  \
        libclang-rt-${LLVM_VERSION}-dev \
        lld-${LLVM_VERSION} \
        llvm-${LLVM_VERSION} \
 && rm -rf /var/lib/apt/lists/*

RUN rustup toolchain install stable \
 && rustup default stable \
 && rustup target add "${TARGET}"

RUN curl -fsSLO "https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux.zip" \
 && unzip -q -d /opt "android-ndk-${ANDROID_NDK_VERSION}-linux.zip" \
 && rm -rf "android-ndk-${ANDROID_NDK_VERSION}-linux.zip" \
 && ln -sf "${TARGET}/asm" "${ANDROID_NDK_SYSROOT}/usr/include/asm" \
 && cp "${ANDROID_NDK_SYSROOT}/usr/lib/${TARGET}/${ANDROID_API}/libandroid.so" /libandroid.so

ENV PATH="/usr/lib/llvm-${LLVM_VERSION}/bin:${PATH}" \
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
ENV __CARGO_TEST_CHANNEL_OVERRIDE_DO_NOT_USE_THIS="nightly" \
    CARGO_UNSTABLE_HOST_CONFIG="true" \
    CARGO_UNSTABLE_TARGET_APPLIES_TO_HOST="true" \
    CARGO_TARGET_APPLIES_TO_HOST="false" \
    CARGO_BUILD_TARGET_DIR="/cargo-build" \
    CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="${CC_aarch64_linux_android}" \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="${CC_x86_64_unknown_linux_gnu}"

ARG RUSTY_V8_VERSION
RUN git clone --depth=1 --recurse-submodules --shallow-submodules \
        --branch="${RUSTY_V8_VERSION}" "https://github.com/denoland/rusty_v8.git" rusty_v8

COPY *.patch .

RUN patch -d rusty_v8 -p1 < rusty_v8-custom-toolchain.patch \
 && patch -d rusty_v8 -p1 < rusty_v8-fix-static_assert.patch

COPY config-rusty_v8.toml .cargo/config.toml

RUN env -C rusty_v8 cargo +stable build --release --locked -vv \
 && mv "${CARGO_BUILD_TARGET_DIR}/${TARGET}/release/gn_out/obj/librusty_v8.a" /librusty_v8.a


FROM --platform=linux/arm64 termux/termux-docker:aarch64 AS build-deno

COPY --from=resolver /hosts /system/etc/hosts

USER system

RUN apt-get update -qq \
 && apt-get install -qy --no-install-recommends \
        binutils-is-llvm \
        cmake \
        git \
        make \
        patch \
        protobuf \
        rust \
        termux-elf-cleaner \
 && ln -sf "aarch64-linux-android/asm" "${PREFIX}/include/asm"

ARG DENO_VERSION
RUN git clone --depth=1 --recurse-submodules --shallow-submodules \
        --branch="${DENO_VERSION}" "https://github.com/denoland/deno.git" \
        /data/data/com.termux/files/usr/tmp/deno
ARG LIBZ_SYS_VERSION
RUN git clone --depth=1 --recurse-submodules --shallow-submodules \
        --branch="${LIBZ_SYS_VERSION}" "https://github.com/rust-lang/libz-sys.git" \
        /data/data/com.termux/files/usr/tmp/libz-sys

COPY --from=build-rusty_v8 --chown=system /librusty_v8.a /data/data/com.termux/files/usr/tmp/librusty_v8.a
COPY --from=build-rusty_v8 --chown=system /libandroid.so /data/data/com.termux/files/usr/lib/libandroid.so
ENV LD_LIBRARY_PATH="/data/data/com.termux/files/usr/lib"

COPY --chown=system *.patch .

RUN patch -d /data/data/com.termux/files/usr/tmp/deno -p1 < deno-fix-webgpu-byow.patch \
 && patch -d /data/data/com.termux/files/usr/tmp/libz-sys -p1 < libz-sys-fix-tls-alignment.patch

COPY --chown=system config-deno.toml /data/data/com.termux/files/.cargo/config.toml

RUN cargo install --root="/data/data/com.termux/files/usr/tmp/cargo-install" --locked -vv --path /data/data/com.termux/files/usr/tmp/deno/cli
# ARG DENO_VERSION
# RUN cargo install --root="/data/data/com.termux/files/usr/tmp/cargo-install" --locked -vv --version="${DENO_VERSION#v}" deno

RUN termux-elf-cleaner /data/data/com.termux/files/usr/tmp/cargo-install/bin/deno


FROM scratch

COPY --from=build-deno /data/data/com.termux/files/usr/tmp/cargo-install/bin/deno /
