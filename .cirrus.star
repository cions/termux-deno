load("cirrus", "env", "http")
load("github.com/cirrus-modules/helpers", "task", "container", "arm_container", "script", "artifacts", "file_from_env")

DENO_VERSION = "v1.34.1"
RUSTY_V8_VERSION = "v0.73.0"


def main():
    return [
        task(
            name="Build librusty_v8.a",
            alias="rustyv8",
            instance=container("rust:latest", cpu=8, memory="16G", greedy=True),
            env={
                "RUSTY_V8_VERSION": RUSTY_V8_VERSION,
                "HOST": "x86_64-unknown-linux-gnu",
                "TARGET": "aarch64-linux-android",
                "LLVM_VERSION": "14",
                "ANDROID_NDK_VERSION": "r25c",
                "ANDROID_NDK_MAJOR_VERSION": "25",
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
                "CARGO_BUILD_TARGET_DIR": "${CIRRUS_WORKING_DIR}/cargo-build",
                "CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER": "${CC_aarch64_linux_android}",
                "CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER": "${CC_x86_64_unknown_linux_gnu}",
                "CARGO_NET_GIT_FETCH_WITH_CLI": "true",
            },
            instructions=[
                script("build",
                    'echo "deb https://apt.llvm.org/bullseye/ llvm-toolchain-bullseye-${LLVM_VERSION} main" > /etc/apt/sources.list.d/llvm.list',
                    'curl -fsSL -o /etc/apt/trusted.gpg.d/apt.llvm.org.asc "https://apt.llvm.org/llvm-snapshot.gpg.key"',
                    'apt-get update -qq',
                    'apt-get install -qy --no-install-recommends clang-${LLVM_VERSION} libc++1-${LLVM_VERSION} libclang-rt-${LLVM_VERSION}-dev lld-${LLVM_VERSION} llvm-${LLVM_VERSION}',

                    'rustup toolchain install nightly',
                    'rustup default nightly',
                    'rustup target add "${TARGET}"',

                    'curl -fsSLO "https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux.zip"',
                    'unzip -q -d /opt "android-ndk-${ANDROID_NDK_VERSION}-linux.zip"',
                    'ln -sf "${TARGET}/asm" "${ANDROID_NDK_SYSROOT}/usr/include/asm"',

                    'install -D config-rusty_v8.toml .cargo/config.toml',

                    'git clone --depth=1 --recurse-submodules --shallow-submodules --branch="${RUSTY_V8_VERSION}" "https://github.com/denoland/rusty_v8.git" rusty_v8',
                    'patch -d rusty_v8 -p1 < rusty_v8.patch',

                    'cargo +nightly -Z unstable-options -C rusty_v8 build --release -vv',
                    'mv "${CARGO_BUILD_TARGET_DIR}/${TARGET}/release/gn_out/obj/librusty_v8.a" librusty_v8.a',
                ),
                artifacts("librusty_v8-aarch64-android", "librusty_v8.a"),
            ],
        ),
        task(
            name="Build deno",
            depends_on=["Build librusty_v8.a"],
            instance=arm_container(dockerfile="Dockerfile.cirrus", cpu=8, memory="16G", greedy=True),
            env={
                "DENO_VERSION": DENO_VERSION,
                "RUSTY_V8_VERSION": RUSTY_V8_VERSION,
                "CARGO_NET_GIT_FETCH_WITH_CLI": "true",
            },
            instructions=[
                script("build",
                    'curl -fsSLO "https://api.cirrus-ci.com/v1/artifact/build/${CIRRUS_BUILD_ID}/rustyv8/librusty_v8-aarch64-android/librusty_v8.a"',

                    'install -D config-deno.toml .cargo/config.toml',

                    'git clone --filter=tree:0 --branch="${DENO_VERSION}" "https://github.com/denoland/deno.git" deno',
                    'git clone --filter=tree:0 --recurse-submodules --also-filter-submodules --branch="${RUSTY_V8_VERSION}" "https://github.com/denoland/rusty_v8.git" rusty_v8',

                    'patch -d deno -p1 < deno-android.patch',
                    'patch -d deno -p1 < deno-ambiguous-name.patch',
                    'patch -d rusty_v8 -p1 < rusty_v8.patch',

                    'cargo install --root="${CIRRUS_WORKING_DIR}/cargo-install" -vv --path deno/cli',
                    'mv "${CIRRUS_WORKING_DIR}/cargo-install/bin/deno" deno',
                ),
                artifacts("deno-aarch64-android", "deno"),
            ],
        ),
    ]
