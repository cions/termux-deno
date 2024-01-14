load("github.com/cirrus-modules/helpers", "task", "container", "arm_container", "script", "artifacts")

DENO_VERSION = "v1.39.3"
RUSTY_V8_VERSION = "v0.82.0"
LIBZ_SYS_VERSION = "1.1.12"


def main():
    return [
        task(
            name="Build librusty_v8.a",
            alias="rustyv8",
            instance=container("rust:latest", cpu=8, memory="8G"),
            env={
                "RUSTY_V8_VERSION": RUSTY_V8_VERSION,
                "HOST": "x86_64-unknown-linux-gnu",
                "TARGET": "aarch64-linux-android",
                "LLVM_VERSION": "17",
                "ANDROID_NDK_VERSION": "r26b",
                "ANDROID_NDK_MAJOR_VERSION": "26",
                "ANDROID_API": "29",
                "ANDROID_NDK": "/opt/android-ndk-${ANDROID_NDK_VERSION}",
                "ANDROID_NDK_BIN": "${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin",
                "ANDROID_NDK_SYSROOT": "${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/sysroot",
                "CLANG_BASE_PATH": "${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64",
                "PATH": "/usr/lib/llvm-${LLVM_VERSION}/bin:${PATH}",
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
                "CARGO_UNSTABLE_HOST_CONFIG": "true",
                "CARGO_UNSTABLE_TARGET_APPLIES_TO_HOST": "true",
                "CARGO_TARGET_APPLIES_TO_HOST": "false",
                "CARGO_BUILD_TARGET_DIR": "${CIRRUS_WORKING_DIR}/cargo-build",
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

                    'git clone --depth=1 --recurse-submodules --shallow-submodules --branch="${RUSTY_V8_VERSION}" "https://github.com/denoland/rusty_v8.git" rusty_v8',
                    'patch -d rusty_v8 -p1 < rusty_v8-custom-toolchain.patch',
                    'patch -d rusty_v8 -p1 < rusty_v8-fix-static_assert.patch',

                    'install -D config-rusty_v8.toml .cargo/config.toml',
                ),
                script("build",
                    'env -C rusty_v8 cargo +stable build --release --locked -vv',
                    'mv "${CARGO_BUILD_TARGET_DIR}/${TARGET}/release/gn_out/obj/librusty_v8.a" "${CIRRUS_WORKING_DIR}/librusty_v8.a"',
                ),
                artifacts("librusty_v8-aarch64-android", "librusty_v8.a"),
            ],
        ),
        task(
            name="Build deno",
            alias="deno",
            depends_on=["Build librusty_v8.a"],
            instance=arm_container(dockerfile="Dockerfile.cirrus", cpu=8, memory="8G"),
            env={
                "DENO_VERSION": DENO_VERSION,
                "LIBZ_SYS_VERSION": LIBZ_SYS_VERSION,
                "CARGO_NET_GIT_FETCH_WITH_CLI": "true",
            },
            instructions=[
                script("build",
                    'curl -fsSL -o /data/data/com.termux/files/usr/tmp/librusty_v8.a "https://api.cirrus-ci.com/v1/artifact/build/${CIRRUS_BUILD_ID}/rustyv8/librusty_v8-aarch64-android/librusty_v8.a"',

                    'install -D config-deno.toml /data/data/com.termux/files/.cargo/config.toml',

                    'git clone --depth=1 --recurse-submodules --shallow-submodules --branch="${LIBZ_SYS_VERSION}" "https://github.com/rust-lang/libz-sys.git" /data/data/com.termux/files/usr/tmp/libz-sys',
                    'patch -d /data/data/com.termux/files/usr/tmp/libz-sys -p1 < libz-sys-fix-tls-alignment.patch',

                    'cargo install --root="${CIRRUS_WORKING_DIR}/cargo-install" --locked -vv --version="${DENO_VERSION#v}" deno',

                    'termux-elf-cleaner "${CIRRUS_WORKING_DIR}/cargo-install/bin/deno"',

                    'mv "${CIRRUS_WORKING_DIR}/cargo-install/bin/deno" deno',
                ),
                artifacts("deno-aarch64-android", "deno", type="application/x-executable"),
            ],
        ),
    ]
