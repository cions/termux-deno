# curl -fsSL https://raw.githubusercontent.com/rust-lang/crates.io-index/master/de/no/deno | tail | jq -r '"\(.vers): deno_core \(.deps[] | select(.name == "deno_core" and .kind == "normal") | .req)"'
ARG DENO_VERSION="v1.38.0"
# curl -fsSL https://raw.githubusercontent.com/rust-lang/crates.io-index/master/de/no/deno_core | tail | jq -r '"\(.vers): v8 \(.deps[] | select(.name == "v8") | .req)"'
ARG RUSTY_V8_VERSION="v0.81.0"


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

ENV HOST="x86_64-unknown-linux-gnu"
ENV TARGET="aarch64-linux-android"
ENV LLVM_VERSION="17"
ENV ANDROID_NDK_VERSION="r26b"
ENV ANDROID_NDK_MAJOR_VERSION="26"
ENV ANDROID_API="29"
ENV ANDROID_NDK="/opt/android-ndk-${ANDROID_NDK_VERSION}"
ENV ANDROID_NDK_BIN="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin"
ENV ANDROID_NDK_SYSROOT="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
ENV CLANG_BASE_PATH="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64"

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
 && ln -sf "${TARGET}/asm" "${ANDROID_NDK_SYSROOT}/usr/include/asm"

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

RUN cargo +stable -Z unstable-options -C rusty_v8 build --release -vv \
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
 && ln -sf "aarch64-linux-android/asm" "${PREFIX}/include/asm"

ARG DENO_VERSION
RUN git clone --depth=1 --recurse-submodules --shallow-submodules \
        --branch="${DENO_VERSION}" "https://github.com/denoland/deno.git" deno

COPY --from=build-rusty_v8 --chown=system /librusty_v8.a .

COPY --chown=system *.patch .

RUN patch -d deno -p1 < deno-android.patch

COPY --chown=system config-deno.toml .cargo/config.toml

# RUN cargo install --root="${HOME}/cargo-install" -vv --version="${DENO_VERSION#v}" deno
RUN cargo install --root="${HOME}/cargo-install" -vv --path deno/cli


FROM scratch

COPY --from=build-deno /data/data/com.termux/files/home/cargo-install/bin/deno /
