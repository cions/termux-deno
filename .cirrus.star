load("github.com/cirrus-modules/helpers", "task", "container", "arm_container", "script", "artifacts")

DENO_VERSION = "v1.46.0"
RUSTY_V8_VERSION = "v0.104.0"
LIBSUI_VERSION = "1c6d863f2cc037905de4220f7e8b9cefd3a8da35"


def main():
    return [
        task(
            name="Build librusty_v8.a",
            alias="rustyv8",
            instance=container("rust:latest", cpu=8, memory="8G"),
            timeout_in="120m",
            env={
                "RUSTY_V8_VERSION": RUSTY_V8_VERSION,
                "HOST": "x86_64-unknown-linux-gnu",
                "TARGET": "aarch64-linux-android",
                "LLVM_VERSION": "18",
                "ANDROID_NDK_VERSION": "r27",
                "ANDROID_API": "29",
                "ANDROID_NDK": "/opt/android-ndk-${ANDROID_NDK_VERSION}",
                "ANDROID_NDK_BIN": "${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin",
                "ANDROID_NDK_SYSROOT": "${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/sysroot",
                "CLANG_BASE_PATH": "${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64",
                "PATH": "/usr/lib/llvm-${LLVM_VERSION}/bin:${PATH}",
                "BINDGEN_EXTRA_CLANG_ARGS": "--sysroot=${ANDROID_NDK_SYSROOT}",
                "CC_aarch64_linux_android": "${ANDROID_NDK_BIN}/${TARGET}${ANDROID_API}-clang",
                "CXX_aarch64_linux_android": "${ANDROID_NDK_BIN}/${TARGET}${ANDROID_API}-clang++",
                "AR_aarch64_linux_android": "${ANDROID_NDK_BIN}/llvm-ar",
                "NM_aarch64_linux_android": "${ANDROID_NDK_BIN}/llvm-nm",
                "CC_x86_64_unknown_linux_gnu": "/usr/lib/llvm-${LLVM_VERSION}/bin/clang",
                "CXX_x86_64_unknown_linux_gnu": "/usr/lib/llvm-${LLVM_VERSION}/bin/clang++",
                "AR_x86_64_unknown_linux_gnu": "/usr/lib/llvm-${LLVM_VERSION}/bin/llvm-ar",
                "NM_x86_64_unknown_linux_gnu": "/usr/lib/llvm-${LLVM_VERSION}/bin/llvm-nm",
                "CC": "${CC_aarch64_linux_android}",
                "CXX": "${CXX_aarch64_linux_android}",
                "AR": "${AR_aarch64_linux_android}",
                "NM": "${NM_aarch64_linux_android}",
                "BUILD_CC": "${CC_x86_64_unknown_linux_gnu}",
                "BUILD_CXX": "${CXX_x86_64_unknown_linux_gnu}",
                "BUILD_AR": "${AR_x86_64_unknown_linux_gnu}",
                "BUILD_NM": "${NM_x86_64_unknown_linux_gnu}",
                "__CARGO_TEST_CHANNEL_OVERRIDE_DO_NOT_USE_THIS": "nightly",
                "RUSTC_BOOTSTRAP": "1",
                "CARGO_UNSTABLE_HOST_CONFIG": "true",
                "CARGO_UNSTABLE_TARGET_APPLIES_TO_HOST": "true",
                "CARGO_TARGET_APPLIES_TO_HOST": "false",
                "CARGO_BUILD_TARGET_DIR": "${CIRRUS_WORKING_DIR}/cargo-build",
                "CARGO_HOST_LINKER": "${CC_x86_64_unknown_linux_gnu}",
                "CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER": "${CC_aarch64_linux_android}",
                "CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER": "${CC_x86_64_unknown_linux_gnu}",
                "CARGO_NET_GIT_FETCH_WITH_CLI": "true",
            },
            instructions=[
                script("prepare",
                    'echo "deb https://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-${LLVM_VERSION} main" > /etc/apt/sources.list.d/llvm.list',
                    'curl -fsSL -o /etc/apt/trusted.gpg.d/apt.llvm.org.asc https://apt.llvm.org/llvm-snapshot.gpg.key',
                    'apt-get update -qq',
                    'apt-get install -qy --no-install-recommends clang-${LLVM_VERSION} libc++1-${LLVM_VERSION} libclang-rt-${LLVM_VERSION}-dev lld-${LLVM_VERSION} llvm-${LLVM_VERSION}',

                    'rustup toolchain install stable',
                    'rustup default stable',
                    'rustup target add "${TARGET}"',

                    'curl -fsSLO "https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux.zip"',
                    'unzip -q -d /opt "android-ndk-${ANDROID_NDK_VERSION}-linux.zip"',
                    'ln -sf "${TARGET}/asm" "${ANDROID_NDK_SYSROOT}/usr/include/asm"',

                    'install -D config-rusty_v8.toml .cargo/config.toml',

                    'git clone --depth=1 --recurse-submodules --shallow-submodules --branch="${RUSTY_V8_VERSION}" https://github.com/denoland/rusty_v8.git rusty_v8',
                    'patch -d rusty_v8 -p1 < rusty_v8-custom-toolchain.patch',
                    'patch -d rusty_v8 -p1 < rusty_v8-fix-static_assert.patch',
                ),
                script("build",
                    'env -C rusty_v8 cargo +stable build --release --locked -vv',
                    'cp "${CARGO_BUILD_TARGET_DIR}/${TARGET}/release/gn_out/obj/librusty_v8.a" "${CIRRUS_WORKING_DIR}/librusty_v8.a"',
                    'cp "${CARGO_BUILD_TARGET_DIR}/${TARGET}/release/gn_out/src_binding.rs" "${CIRRUS_WORKING_DIR}/src_binding.rs"',
                ),
                artifacts("librusty_v8_aarch64_android", "librusty_v8.a"),
                artifacts("src_binding_aarch64_android", "src_binding.rs"),
            ],
        ),
        task(
            name="Build deno",
            alias="deno",
            depends_on=["Build librusty_v8.a"],
            instance=arm_container(dockerfile="Dockerfile.cirrus", cpu=8, memory="8G"),
            env={
                "RUSTY_V8_VERSION": RUSTY_V8_VERSION,
                "DENO_VERSION": DENO_VERSION,
                "LIBSUI_VERSION": LIBSUI_VERSION,
                "RUSTC_BOOTSTRAP": "1",
                "CARGO_BUILD_TARGET_DIR": "/data/data/com.termux/files/home/cargo-build",
                "CARGO_INSTALL_ROOT": "/data/data/com.termux/files/home/cargo-install",
                "CARGO_NET_GIT_FETCH_WITH_CLI": "true",
            },
            instructions=[
                script("build",
                    'curl -fsSL -o /data/data/com.termux/files/usr/tmp/librusty_v8.a "https://api.cirrus-ci.com/v1/artifact/build/${CIRRUS_BUILD_ID}/rustyv8/librusty_v8_aarch64_android/librusty_v8.a"',
                    'curl -fsSL -o /data/data/com.termux/files/usr/tmp/src_binding.rs "https://api.cirrus-ci.com/v1/artifact/build/${CIRRUS_BUILD_ID}/rustyv8/src_binding_aarch64_android/src_binding.rs"',

                    'install -D config-deno.toml /data/data/com.termux/files/home/.cargo/config.toml',

                    'git clone --depth=1 --recurse-submodules --shallow-submodules --branch="${RUSTY_V8_VERSION}" https://github.com/denoland/rusty_v8.git /data/data/com.termux/files/usr/tmp/rusty_v8',
                    'patch -d /data/data/com.termux/files/usr/tmp/rusty_v8 -p1 < rusty_v8-src-binding-path.patch',

                    'git clone https://github.com/denoland/sui.git /data/data/com.termux/files/usr/tmp/sui && git -C /data/data/com.termux/files/usr/tmp/sui checkout "${LIBSUI_VERSION}"',
                    'patch -d /data/data/com.termux/files/usr/tmp/sui -p1 < libsui-android.patch',

                    'git clone --depth=1 --recurse-submodules --shallow-submodules --branch="${DENO_VERSION}" https://github.com/denoland/deno.git /data/data/com.termux/files/usr/tmp/deno',
                    'patch -d /data/data/com.termux/files/usr/tmp/deno -p1 < deno-fix-webgpu-byow.patch',
                    'cargo install --locked -vv --path /data/data/com.termux/files/usr/tmp/deno/cli',
                    # 'cargo install --locked -vv --version="${DENO_VERSION#v}" deno',

                    'termux-elf-cleaner "${CARGO_INSTALL_ROOT}/bin/deno"',

                    'mv "${CARGO_INSTALL_ROOT}/bin/deno" "${CIRRUS_WORKING_DIR}/deno"',
                ),
                artifacts("deno-aarch64-android", "deno", type="application/x-executable"),
            ],
        ),
    ]
