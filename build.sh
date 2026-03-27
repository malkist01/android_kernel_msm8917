#!/bin/bash

# ================= COLOR =================
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
white='\033[0m'

# ================= PATH =================
ROOTDIR=$(pwd)
OUTDIR="$ROOTDIR/out/arch/arm64/boot"
ANYKERNEL_DIR="$ROOTDIR/AnyKernel"

KIMG_DTB="$OUTDIR/Image.gz-dtb"
KIMG="$OUTDIR/Image.gz"

# ================= INFO =================
KERNEL_NAME="Teletubies 🕊️"
DEVICE="j6primelte"

# ================= DATE =================
DATE_TITLE=$(date +"%d%m%Y")
DATE_CAPTION=$(date +"%d %B %Y")

ZIP_NAME="${KERNEL_NAME}-${DEVICE}-${DATE_TITLE}.zip"

# ================= TOOLCHAIN =================
TC64="$ROOTDIR/linegcc49/bin/aarch64-linux-android-"
TC32="$ROOTDIR/linegcc49/bin/arm-linux-androideabi-"

# ================= TELEGRAM =================
TG_BOT_TOKEN="7868194496:AAGY7WwRRbeCOPYOnczoCPh2psC43Q0F3JI"
TG_CHAT_ID="-1002287610863"

# ================= GLOBAL =================
BUILD_TIME="unknown"
KERNEL_VERSION="unknown"
TC_INFO="unknown"
IMG_USED="unknown"

# ================= FUNCTION =================

clone_anykernel() {
    if [ ! -d "$ANYKERNEL_DIR" ]; then
        echo -e "$yellow[+] Cloning AnyKernel3...$white"
        git clone -b master https://github.com/malkist01/AnyKernel3.git "$ANYKERNEL_DIR" || exit 1
    fi
}

get_toolchain_info() {
    if [ -x "${TC64}gcc" ]; then
        if ${TC64}gcc --version | grep -qi prerelease; then
            TC_INFO="GCC 4.9 Prerelease"
        else
            TC_INFO="GCC 4.9.x"
        fi
    else
        TC_INFO="unknown"
    fi
}

# === FIX FINAL KERNEL VERSION (VALID) ===
get_kernel_version() {
    if [ -f "out/include/generated/utsrelease.h" ]; then
        KERNEL_VERSION=$(sed -n 's/#define UTS_RELEASE "\(.*\)"/\1/p' \
            out/include/generated/utsrelease.h)
        KERNEL_VERSION=$(echo "$KERNEL_VERSION" | cut -d- -f1)
    else
        KERNEL_VERSION="unknown"
    fi
}

send_telegram_error() {
    local ERROR_MSG="$1"

    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d parse_mode=Markdown \
        -d text="❌ *Kernel CI Build Failed*

📱 *Device* : ${DEVICE}
🧠 *Kernel Name* : ${KERNEL_NAME}
🧬 *Kernel Version* : ${KERNEL_VERSION}
🛠 *Toolchain* : ${TC_INFO}

⚠️ *Error* :
\`${ERROR_MSG}\`

⌛ *Build Time* : ${BUILD_TIME}
🕒 *Build Date* : ${DATE_CAPTION}"
}

build_kernel() {
    echo -e "$yellow[+] Building kernel...$white"

    rm -rf out
    make O=out ARCH=arm64 rolex_defconfig || {
        get_toolchain_info
        send_telegram_error "Defconfig failed"
        exit 1
    }

    get_toolchain_info
    BUILD_START=$(date +%s)

    make -j$(nproc) O=out ARCH=arm64 \
        CROSS_COMPILE=$TC64 \
        CROSS_COMPILE_ARM32=$TC32 \
        CROSS_COMPILE_COMPAT=$TC32

    MAKE_STATUS=$?
    if [ $MAKE_STATUS -ne 0 ]; then
        send_telegram_error "Kernel compilation failed (exit code $MAKE_STATUS)"
        exit 1
    fi

    BUILD_END=$(date +%s)
    DIFF=$((BUILD_END - BUILD_START))
    BUILD_TIME="$((DIFF / 60)) min $((DIFF % 60)) sec"

    get_kernel_version
}

pack_kernel() {
    echo -e "$yellow[+] Packing AnyKernel...$white"

    clone_anykernel
    cd "$ANYKERNEL_DIR" || exit 1

    rm -f Image* *.zip

    if [ -f "$KIMG_DTB" ]; then
        cp "$KIMG_DTB" Image.gz-dtb
        IMG_USED="Image.gz-dtb"
    elif [ -f "$KIMG" ]; then
        cp "$KIMG" Image.gz
        IMG_USED="Image.gz"
    else
        send_telegram_error "Kernel image not found"
        exit 1
    fi

    zip -r9 "$ZIP_NAME" . -x ".git*" "README.md"
    echo -e "$green[✓] Zip created: $ZIP_NAME ($IMG_USED)$white"
}

upload_telegram() {
    ZIP_PATH="$ANYKERNEL_DIR/$ZIP_NAME"
    [ ! -f "$ZIP_PATH" ] && return

    echo -e "$yellow[+] Uploading to Telegram...$white"

    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
        -F chat_id="${TG_CHAT_ID}" \
        -F document=@"${ZIP_PATH}" \
        -F parse_mode=Markdown \
        -F caption="🔥 *Kernel CI Build Success*

📱 *Device* : ${DEVICE}
🧠 *Kernel Name* : ${KERNEL_NAME}
🧬 *Kernel Version* : ${KERNEL_VERSION}

🛠 *Toolchain* : ${TC_INFO}

⌛ *Build Time* : ${BUILD_TIME}
🕒 *Build Date* : ${DATE_CAPTION}

✅ *Flash via Recovery*"

    echo -e "$green[✓] Uploaded to Telegram$white"
}

# ================= RUN =================
START=$(date +%s)

build_kernel
pack_kernel
upload_telegram

END=$(date +%s)
echo -e "$green[✓] Done in $((END - START)) seconds$white"
