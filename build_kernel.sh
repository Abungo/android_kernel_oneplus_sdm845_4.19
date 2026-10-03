#!/bin/bash

# Some general variables
DIR=`readlink -f .`
PARENT_DIR=`readlink -f ${DIR}/..`

export ARCH=arm64
export DEFCONFIG="vendor/sdm845-perf_defconfig vendor/enchilada.config"
export COMPILER=clang
export VARIANT="EvolutionX_SDM845"

# Toolchain paths (uses workspace prebuilt Clang 20.0.0 clang-r547379 if present, or downloads fallback)
ROM_CLANG=`readlink -f ${DIR}/../../../prebuilts/clang/host/linux-x86/clang-r547379`
ROM_GCC_64=`readlink -f ${DIR}/../../../prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9`
ROM_GCC_32=`readlink -f ${DIR}/../../../prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9`

if [ -d "${ROM_CLANG}" ]; then
  export COMPILERDIR=${ROM_CLANG}
else
  export COMPILERDIR=${DIR}/scratch/clang-r547379
fi

if [ -d "${ROM_GCC_64}" ]; then
  export AARCH64DIR=${ROM_GCC_64}
else
  export AARCH64DIR=${DIR}/scratch/aarch64-linux-android-4.9
fi

if [ -d "${ROM_GCC_32}" ]; then
  export ARM32DIR=${ROM_GCC_32}
else
  export ARM32DIR=${DIR}/scratch/arm-linux-androideabi-4.9
fi

export PATH=${COMPILERDIR}/bin:${PATH}

# LLVM=1 makes kernel use clang instead of gcc
# LLVM_IAS makes kernel use clang integrated assembler
export LLVM=1
export LLVM_IAS=1

# Color
ON_BLUE=`echo -e "\033[44m"`	# On Blue
RED=`echo -e "\033[1;31m"`	# Red
BLUE=`echo -e "\033[1;34m"`	# Blue
GREEN=`echo -e "\033[1;32m"`	# Green
Under_Line=`echo -e "\e[4m"`	# Text Under Line
STD=`echo -e "\033[0m"`		# Text Clear

# Functions
pause(){
  read -p "${RED}$2${STD}Press ${BLUE}[Enter]${STD} key to $1..." fackEnterKey
}

toolchain(){
  if [ ! -d "${AARCH64DIR}" ]; then
    echo "${GREEN}Cloning toolchain aarch64-linux-android-4.9 cross compiler...${STD}"
    git clone --branch lineage-19.1 --depth=1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9 ${AARCH64DIR}
  fi
  if [ ! -d "${ARM32DIR}" ]; then
    echo "${GREEN}Cloning toolchain arm-linux-androideabi-4.9 32-bit cross compiler...${STD}"
    git clone --branch lineage-19.1 --depth=1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9 ${ARM32DIR}
  fi
}

clang(){
  if [ ! -d "${COMPILERDIR}" ]; then
    echo "${GREEN}Cloning Clang toolchain into scratch/...${STD}"
    git clone --depth=1 https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r498229b ${COMPILERDIR}
  fi
}

clean(){
  echo "${GREEN}***** Cleaning in Progress *****${STD}"
  make clean -j$(nproc)
  make mrproper -j$(nproc)
  [ -d "out" ] && rm -rf out
  echo "${GREEN}***** Cleaning Done *****${STD}"
}

build_kernel() {
  echo "${GREEN}***** Compiling kernel for ${VARIANT} *****${STD}"
  [ ! -d "out" ] && mkdir out
  export PATH=${COMPILERDIR}/bin:${PATH}
  make O=out ARCH=${ARCH} ${DEFCONFIG}
  make -j$(nproc) O=out \
    ARCH=${ARCH} \
    CC=${COMPILERDIR}/bin/clang \
    CROSS_COMPILE=${AARCH64DIR}/bin/aarch64-linux-android- \
    CROSS_COMPILE_ARM32=${ARM32DIR}/bin/arm-linux-androideabi- \
    CLANG_TRIPLE=${COMPILERDIR}/bin/aarch64-linux-gnu- \
    HOSTCC=${COMPILERDIR}/bin/clang \
    HOSTCXX=${COMPILERDIR}/bin/clang++ \
    LD=${COMPILERDIR}/bin/ld.lld \
    AR=${COMPILERDIR}/bin/llvm-ar \
    LLVM=1 \
    LLVM_IAS=1
}

anykernel3(){
  if [ ! -d "${DIR}/scratch" ]; then
    mkdir -p "${DIR}/scratch"
  fi

  if [ ! -d "${DIR}/scratch/AnyKernel3" ]; then
    echo "${GREEN}Cloning AnyKernel3 template into scratch/...${STD}"
    git clone https://github.com/osm0sis/AnyKernel3 "${DIR}/scratch/AnyKernel3"
  fi

  curtime=`date +"%m_%d_%H%M"`
  releasefilename=EvolutionX_kernel-${VARIANT}_${curtime}

  if [ -e $DIR/out/arch/arm64/boot/Image.gz-dtb ]; then
    echo "${GREEN}Creating flashable zip: ${releasefilename}.zip...${STD}"
    cd "${DIR}/scratch/AnyKernel3"
    git reset --hard 2>/dev/null || true
    
    cp $DIR/out/arch/arm64/boot/Image.gz-dtb Image.gz-dtb
    
    sed -i "s/ExampleKernel by osm0sis @ xda-developers/EvolutionX Kernel by Abungo/g" anykernel.sh
    sed -i "s/=maguro/=OnePlus6/g" anykernel.sh
    sed -i "s/=toroplus/=OnePlus6T/g" anykernel.sh
    sed -i "s/=toro/=/g" anykernel.sh
    sed -i "s/=tuna/=/g" anykernel.sh
    sed -i "s/IS_SLOT_DEVICE=0/IS_SLOT_DEVICE=1/g" anykernel.sh
    sed -i "s/\/dev\/block\/platform\/omap\/omap_hsmmc\.0\/by-name\/boot/boot/g" anykernel.sh
    sed -i "s/backup_file/#backup_file/g" anykernel.sh
    sed -i "s/replace_string/#replace_string/g" anykernel.sh
    sed -i "s/insert_line/#insert_line/g" anykernel.sh
    sed -i "s/append_file/#append_file/g" anykernel.sh
    sed -i "s/patch_fstab/#patch_fstab/g" anykernel.sh

    zip -r9 "${DIR}/scratch/${releasefilename}.zip" * -x .git README.md *placeholder
    echo "${GREEN}***** Flashable kernel zip created at: ${DIR}/scratch/${releasefilename}.zip *****${STD}"
    cd $DIR
  else
    echo "${RED}Error: Image.gz-dtb not found in $DIR/out/arch/arm64/boot/${STD}"
  fi
}

build_kernel_sdm845(){
  build_kernel
  anykernel3
}

# Run once
toolchain
clang

# Show menu
show_menus(){
  echo "${ON_BLUE} B U I L D - M E N U ${STD}"
  echo "1. ${Under_Line}B${STD}uild kernel for ${VARIANT}"
  echo "2. ${Under_Line}C${STD}lean"
  echo "3. Make ${Under_Line}f${STD}lashable zip"
  echo "4. E${Under_Line}x${STD}it"
}

# Read input
read_options(){
  local choice
  read -p "Enter choice [ 1 - 4] " choice
  case $choice in
    1|b|B) build_kernel_sdm845 ;;
    2|c|C) clean ;;
    3|f|F) anykernel3;;
    4|x|X) exit 0;;
    *) pause 'return to Main menu' 'Invalid option, '
  esac
}

# Trap CTRL+C, CTRL+Z and quit singles
trap '' SIGINT SIGQUIT SIGTSTP

# Main logic - infinite loop
while true
do
  show_menus
  read_options
done
