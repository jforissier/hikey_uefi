# Makefile for HiKey UEFI boot firmware
#
# 'make help' for details

SHELL = /bin/bash
CURL = curl -L

ifeq ($(V),1)
  Q :=
  ECHO := @:
else
  Q := @
  ECHO := @echo
endif

.PHONY: _all
_all:
	$(Q)$(MAKE) all $(filter-out _all,$(MAKECMDGOALS))

all: build-lloader build-fip build-boot-img build-nvme build-ptable

clean: clean-bl1-bl2-bl31-fip clean-bl33 clean-lloader-ptable
clean: clean-linux-dtb clean-boot-img clean-initramfs clean-optee-linuxdriver
clean: clean-optee-client clean-bl32

cleaner: clean cleaner-nvme cleaner-aarch64-gcc cleaner-busybox cleaner-strace

distclean: cleaner distclean-aarch64-gcc distclean-busybox

help:
	@echo "Makefile for HiKey board UEFI firmware/kernel"
	@echo
	@echo "- Run 'make' to build the following images:"
	@echo "  LLOADER = $(LLOADER) with:"
	@echo "      [BL1 = $(BL1)]"
	@echo "      [l-loader/*.S]"
	@echo "  PTABLE = $(PTABLE)"
	@echo "  FIP = $(FIP) with:"
	@echo "      [BL2 = $(BL2)]"
	@echo "      [BL31 = $(BL31)]"
	@echo "      [BL32 = $(BL32)]"
	@echo "      [BL33 = $(BL33)]"
	@echo "  NVME = $(NVME)"
	@echo "      [downloaded from GitHub]"
	@echo "  BOOT-IMG = $(BOOT-IMG)"
	@echo "      [LINUX = $(LINUX)]"
	@echo "      [DTB = $(DTB)]"
	@echo "      [INITRAMFS = $(INITRAMFS)]"
	@echo "          [gen_rootfs/busybox/*]"
	@echo "          [STRACE = $(STRACE)]"
	@echo "          [OPTEE-LINUXDRIVER = $(optee-linuxdriver-files)]"
	@echo "          [OPTEE-CLIENT = optee_client/out/libteec.so*" \
	                 "optee_client/out/tee-supplicant/tee-supplicant]"
	@echo "- 'make clean' removes most files generated by make, except the"
	@echo "downloaded files/tarballs and the directories they were"
	@echo "extracted to."
	@echo "- 'make cleaner' also removes tar directories."
	@echo "- 'make distclean' removes all generated or downloaded files."
	@echo
	@echo "Image files can be built separately with e.g., 'make build-fip'"
	@echo "or 'make build-bl1', and so on. Note: In order to speed up the "
	@echo "build and reduce output when working on a single component,"
	@echo "build-<foo> will NOT invoke build-<bar>."
	@echo "Therefore, if you want to make sure that <bar> is up-to-date,"
	@echo "use 'make build-<foo> build-<bar>'."
	@echo "Plain 'make' or 'make all' do check all dependencies, however."
	@echo
	@echo "Flashing micro-howto:"
	@echo "  # Set J15 pins 1-2 closed 3-4 closed 5-6 open (recovery mode)"
	@echo "  sudo python burn-boot/hisi-idt.py -d /dev/ttyUSB1 --img1=$(LLOADER)"
	@echo "  # It takes a few seconds before fastboot is ready on the USB port"
	@echo "  fastboot flash ptable $(PTABLE)"
	@echo "  # Or, on the board: dd if=/tmp/fip.bin of=/dev/mmcblk0p4"
	@echo "  fastboot flash fastboot $(FIP)"
	@echo "  fastboot flash nvme $(NVME)"
	@echo "  fastboot flash boot $(BOOT-IMG)"
	@echo "  # Set J15 pins 1-2 closed 3-4 open 5-6 open (boot from eMMC)"

ifneq (,$(shell which ccache))
CCACHE = ccache # do not remove this comment or the trailing space will go
endif

filename = $(lastword $(subst /, ,$(1)))

# Read stdin, expand ${VAR} environment variables, output to stdout
# http://superuser.com/a/302847
define expand-env-var
awk '{while(match($$0,"[$$]{[^}]*}")) {var=substr($$0,RSTART+2,RLENGTH -3);gsub("[$$]{"var"}",ENVIRON[var])}}1'
endef

BUSYBOX_URL = http://busybox.net/downloads/busybox-1.23.0.tar.bz2
BUSYBOX_TARBALL = $(call filename,$(BUSYBOX_URL))
BUSYBOX_DIR = $(BUSYBOX_TARBALL:.tar.bz2=)

#AARCH64_GCC_URL = http://releases.linaro.org/14.04/components/toolchain/binaries/gcc-linaro-aarch64-linux-gnu-4.8-2014.04_linux.tar.xz
AARCH64_GCC_URL = http://releases.linaro.org/14.08/components/toolchain/binaries/gcc-linaro-aarch64-linux-gnu-4.9-2014.08_linux.tar.xz
AARCH64_GCC_TARBALL = $(call filename,$(AARCH64_GCC_URL))
AARCH64_GCC_DIR = $(AARCH64_GCC_TARBALL:.tar.xz=)
aarch64-linux-gnu-gcc := toolchains/$(AARCH64_GCC_DIR)

export CROSS_COMPILE ?= $(CCACHE)$(PWD)/toolchains/$(AARCH64_GCC_DIR)/bin/aarch64-linux-gnu-

#
# Download rules
#

downloads/$(AARCH64_GCC_TARBALL):
	$(ECHO) '  CURL    $@'
	$(Q)$(CURL) $(AARCH64_GCC_URL) -o $@

toolchains/$(AARCH64_GCC_DIR): downloads/$(AARCH64_GCC_TARBALL)
	$(ECHO) '  TAR     $@'
	$(Q)rm -rf toolchains/$(AARCH64_GCC_DIR)
	$(Q)cd toolchains && tar xf ../downloads/$(AARCH64_GCC_TARBALL)
	$(Q)touch $@

cleaner-aarch64-gcc:
	$(ECHO) '  CLEANER $@'
	$(Q)rm -rf toolchains/$(AARCH64_GCC_DIR)

distclean-aarch64-gcc:
	$(ECHO) '  DISTCL  $@'
	$(Q)rm -f downloads/$(AARCH64_GCC_TARBALL)

.busybox: downloads/$(BUSYBOX_TARBALL)
	$(ECHO) '  TAR     gen_rootfs/busybox'
	$(Q)rm -rf gen_rootfs/$(BUSYBOX_DIR) gen_rootfs/busybox
	$(Q)cd gen_rootfs && tar xf ../downloads/$(BUSYBOX_TARBALL)
	$(Q)mv gen_rootfs/$(BUSYBOX_DIR) gen_rootfs/busybox
	$(Q)touch $@

downloads/$(BUSYBOX_TARBALL):
	$(ECHO) '  CURL    $@'
	$(Q)$(CURL) $(BUSYBOX_URL) -o $@

cleaner-busybox:
	$(ECHO) '  CLEANER $@'
	$(Q)rm -rf gen_rootfs/$(BUSYBOX_DIR) gen_rootfs/busybox .busybox

distclean-busybox:
	$(ECHO) '  DISTCL  $@'
	$(Q)rm -f downloads/$(BUSYBOX_TARBALL)


#
# UEFI
#

BL33 = edk2/Build/HiKey/RELEASE_GCC49/FV/BL33_AP_UEFI.fd
EDK2_VARS = EDK2_ARCH=AARCH64 EDK2_DSC=HisiPkg/HiKeyPkg/HiKey.dsc EDK2_TOOLCHAIN=GCC49 EDK2_BUILD=RELEASE

.PHONY: build-bl33
build-bl33 $(BL33): .edk2basetools $(aarch64-linux-gnu-gcc)
	$(ECHO) '  BUILD   build-bl33'
	$(Q)set -e ; cd edk2 ; export GCC49_AARCH64_PREFIX='"$(CROSS_COMPILE)"' ; \
	    . edksetup.sh ; \
	    $(MAKE) -j1 -f HisiPkg/HiKeyPkg/Makefile $(EDK2_VARS)
	$(Q)touch ${BL33}

clean-bl33: clean-edk2-basetools
	$(ECHO) '  CLEAN   $@'
	$(Q)set -e ; cd edk2 ; . edksetup.sh ; \
	    $(MAKE) -f HisiPkg/HiKeyPkg/Makefile $(EDK2_VARS) clean

.edk2basetools:
	$(ECHO) '  BUILD   edk2/BaseTools'
	$(Q)set -e ; cd edk2 ; . edksetup.sh ; \
	    $(MAKE) -j1 -C BaseTools CC="$(CCACHE)gcc" CXX="$(CCACHE)g++"
	$(Q)touch $@

clean-edk2-basetools:
	$(ECHO) '  CLEAN   $@'
	$(Q)set -e ; cd edk2 ; . edksetup.sh ; \
	    $(MAKE) -C BaseTools clean
	$(Q)rm -f .edk2basetools

#
# ARM Trusted Firmware
#

ATF = arm-trusted-firmware/build/hikey/release
BL1 = $(ATF)/bl1.bin
BL2 = $(ATF)/bl2.bin
BL31 = $(ATF)/bl31.bin
# Uncomment to include OP-TEE OS image in fip.bin
#BL32 = optee_os/out/arm32-plat-hikey/core/tee.bin
FIP = $(ATF)/fip.bin

ARMTF_FLAGS := PLAT=hikey LOG_LEVEL=50
ARMTF_EXPORTS := BL33=$(PWD)/$(BL33) #CFLAGS=""
ifneq (,$(BL32))
ARMTF_FLAGS += PLAT_TSP_LOCATION=dram SPD=opteed
ARMTF_EXPORTS += BL32=$(PWD)/$(BL32)
endif

define arm-tf-make
        $(ECHO) '  BUILD   build-$(strip $(1)) [$@]'
        +$(Q)export $(ARMTF_EXPORTS) ; \
	    $(MAKE) -C arm-trusted-firmware $(ARMTF_FLAGS) $(1)
endef

.PHONY: build-bl1
build-bl1 $(BL1): $(aarch64-linux-gnu-gcc)
	$(call arm-tf-make, bl1)

.PHONY: build-bl2
build-bl2 $(BL2): $(aarch64-linux-gnu-gcc)
	$(call arm-tf-make, bl2)

.PHONY: build-bl31
build-bl31 $(BL31): $(aarch64-linux-gnu-gcc)
	$(call arm-tf-make, bl31)


ifneq ($(filter all build-bl2,$(MAKECMDGOALS)),)
tf-deps += build-bl2
endif
ifneq ($(filter all build-bl31,$(MAKECMDGOALS)),)
tf-deps += build-bl31
endif
ifneq ($(filter all build-bl32,$(MAKECMDGOALS)),)
tf-deps += build-bl32
endif
ifneq ($(filter all build-bl33,$(MAKECMDGOALS)),)
tf-deps += build-bl33
endif

.PHONY: build-fip
build-fip:: $(tf-deps)
build-fip $(FIP)::
	$(call arm-tf-make, fip)

clean-bl1-bl2-bl31-fip:
	$(ECHO) '  CLEAN   edk2/BaseTools'
	$(Q)export $(ARMTF_EXPORTS) ; \
	    $(MAKE) -C arm-trusted-firmware $(ARMTF_FLAGS) clean

#
# l-loader
#

LLOADER = l-loader/l-loader.bin
PTABLE = l-loader/ptable.img

ifneq ($(filter all build-bl1,$(MAKECMDGOALS)),)
lloader-deps += build-bl1
endif

# FIXME: adding $(BL1) as a dependency [after $(LLOADER)::] breaks
# parallel build (-j) because the same rule is run twice simultaneously
# $ make -j9 build-bl1 build-lloader
#   BUILD   build-bl1 # $@ = build-bl1
#   BUILD   build-bl1 # $@ = arm-trusted-firmware/build/.../bl1.bin
# make[1]: Entering directory '/home/jerome/work/hikey_uefi/arm-trusted-firmware'
# make[1]: Entering directory '/home/jerome/work/hikey_uefi/arm-trusted-firmware'
#   DEPS    build/hikey/debug/bl31/bl31.ld.d
#   DEPS    build/hikey/debug/bl31/bl31.ld.d
.PHONY: build-lloader
build-lloader:: $(lloader-deps)
build-lloader $(LLOADER)::
	$(ECHO) '  BUILD   build-lloader'
	$(Q)$(MAKE) -C l-loader BL1=$(PWD)/$(BL1) l-loader.bin

build-ptable $(PTABLE):
	$(ECHO) '  BUILD   build-ptable'
	$(Q)$(MAKE) -C l-loader ptable.img

clean-lloader-ptable:
	$(ECHO) '  CLEAN   $@'
	$(Q)$(MAKE) -C l-loader clean

#
# Linux/DTB
#

# FIXME: 'make build-linux' needlessy (?) recompiles a few files (efi.o...)
# each time it is run

LINUX = linux/arch/arm64/boot/Image
DTB = linux/arch/arm64/boot/dts/hi6220-hikey.dtb

.PHONY: build-linux
build-linux $(LINUX): linux/.config $(aarch64-linux-gnu-gcc)
	$(ECHO) '  BUILD   build-linux'
	$(Q)flock .linuxbuildinprogress $(MAKE) -C linux ARCH=arm64 LOCALVERSION= Image

build-dtb $(DTB): linux/.config
	$(ECHO) '  BUILD   build-dtb'
	$(Q)flock .linuxbuildinprogress $(MAKE) -C linux ARCH=arm64 LOCALVERSION= dtbs

linux/.config:
	$(ECHO) '  BUILD   $@'
	$(Q)cd linux && ARCH=arm64 scripts/kconfig/merge_config.sh \
	    arch/arm64/configs/defconfig ../kernel.config

linux/usr/gen_init_cpio: linux/.config
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C linux/usr ARCH=arm64 gen_init_cpio

clean-linux-dtb:
	$(ECHO) '  CLEAN   arm-trusted-firmware'
	$(Q)$(MAKE) -C linux ARCH=arm64 clean
	$(Q)rm -f .linuxbuildinprogress

#
# EFI boot partition
#

BOOT-IMG = boot.img

ifneq ($(filter all build-linux,$(MAKECMDGOALS)),)
boot-img-deps += build-linux
endif
ifneq ($(filter all build-dtb,$(MAKECMDGOALS)),)
boot-img-deps += build-dtb
endif
ifneq ($(filter all build-initramfs,$(MAKECMDGOALS)),)
boot-img-deps += build-initramfs
endif

.PHONY: build-boot-img
build-boot-img:: $(boot-img-deps)
build-boot-img $(BOOT-IMG)::
	$(ECHO) '  GEN    $(BOOT-IMG)'
	$(Q)sudo -p "[sudo] Password:" true
	$(Q)if [ -d .tmpbootimg ] ; then sudo rm -rf .tmpbootimg ; fi
	$(Q)mkdir -p .tmpbootimg
	$(Q)dd if=/dev/zero of=$(BOOT-IMG) bs=512 count=131072 status=none
	$(Q)sudo mkfs.fat -n "BOOT IMG" $(BOOT-IMG) >/dev/null
	$(Q)sudo mount -o loop,rw,sync $(BOOT-IMG) .tmpbootimg
	$(Q)sudo cp $(LINUX) $(DTB) .tmpbootimg
	$(Q)sudo cp $(INITRAMFS) .tmpbootimg/initrd.img
	$(Q)sudo umount .tmpbootimg
	$(Q)sudo rm -rf .tmpbootimg

clean-boot-img:
	$(ECHO) '  CLEAN   $@'
	$(Q)rm -f $(BOOT-IMG)

#
# Initramfs
#

INITRAMFS = initramfs.cpio.gz

ifneq ($(filter all build-optee-linuxdriver,$(MAKECMDGOALS)),)
initramfs-deps += build-optee-linuxdriver
endif
ifneq ($(filter all build-optee-client,$(MAKECMDGOALS)),)
initramfs-deps += build-optee-client
endif
ifneq ($(filter all build-strace,$(MAKECMDGOALS)),)
initramfs-deps += build-strace
endif

.PHONY: build-initramfs
build-initramfs:: $(initramfs-deps)
build-initramfs $(INITRAMFS):: gen_rootfs/filelist-all.txt linux/usr/gen_init_cpio
	$(ECHO) "  GEN    $(INITRAMFS)"
	$(Q)(cd gen_rootfs && ../linux/usr/gen_init_cpio filelist-all.txt) | gzip >$(INITRAMFS)

gen_rootfs/filelist-all.txt: gen_rootfs/filelist-final.txt initramfs-add-files.txt
	$(ECHO) '  GEN    $@'
	$(Q)cat gen_rootfs/filelist-final.txt | sed '/fbtest/d' >$@
	$(Q)export KERNEL_VERSION=`cd linux ; $(MAKE) --no-print-directory -s kernelversion` ;\
	    export TOP=$(PWD) ; export IFTESTS="$(IFTESTS)" ; \
	    $(expand-env-var) <initramfs-add-files.txt >>$@

gen_rootfs/filelist-final.txt: .busybox $(aarch64-linux-gnu-gcc)
	$(ECHO) '  GEN    gen_rootfs/filelist-final.txt'
	$(Q)cd gen_rootfs ; \
	    export CC_DIR=$(PWD)/toolchains/$(AARCH64_GCC_DIR) ; \
	    ./generate-cpio-rootfs.sh hikey nocpio

clean-initramfs:
	$(ECHO) "  CLEAN  $@"
	$(Q)cd gen_rootfs ; ./generate-cpio-rootfs.sh hikey clean
	$(Q)rm -f $(INITRAMFS) gen_rootfs/filelist-all.txt gen_rootfs/filelist-final.txt

#
# Download nvme.img
#

NVME = nvme.img

.PHONY: build-nvme
build-nvme: $(NVME)

$(NVME):
	$(CURL) https://builds.96boards.org/releases/hikey/nvme.img -o $(NVME)

cleaner-nvme:
	$(ECHO) '  CLEANER $(NVME)'
	$(Q)rm -f $(NVME)

#
# OP-TEE Linux driver
#

optee-linuxdriver-files := optee_linuxdriver/optee.ko \
                           optee_linuxdriver/optee_armtz.ko

ifneq ($(filter all build-linux,$(MAKECMDGOALS)),)
optee-linuxdriver-deps += build-linux
endif

.PHONY: build-optee-linuxdriver
build-optee-linuxdriver:: $(optee-linuxdriver-deps)
build-optee-linuxdriver $(optee-linuxdriver-files):: $(aarch64-linux-gnu-gcc)
	$(ECHO) '  BUILD   build-optee-linuxdriver'
	$(Q)$(MAKE) -C linux \
	   ARCH=arm64 \
	   LOCALVERSION= \
	   M=../optee_linuxdriver \
	   modules

clean-optee-linuxdriver:
	$(ECHO) '  CLEAN   $@'
	$(Q)$(MAKE) -C linux \
	   ARCH=arm64 \
	   LOCALVERSION= \
	   M=../optee_linuxdriver \
	   clean

#
# OP-TEE client library and tee-supplicant executable
#

.PHONY: build-optee-client
build-optee-client: $(aarch64-linux-gnu-gcc)
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C optee_client

clean-optee-client:
	$(ECHO) '  CLEAN   $@'
	$(Q)$(MAKE) -C optee_client clean

#
# OP-TEE OS
#

optee-os-flags := CROSS_COMPILE=arm-linux-gnueabihf- PLATFORM=hikey CFG_TEE_CORE_LOG_LEVEL=4

.PHONY: build-bl32
build-bl32:
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C optee_os $(optee-os-flags)

.PHONY: clean-bl32
clean-bl32:
	$(ECHO) '  CLEAN   $@'
	$(Q)$(MAKE) -C optee_os $(optee-os-flags) clean


#
# OP-TEE tests (xtest)
#

ifneq (,$(wildcard optee_test/Makefile))

all: build-optee-test
clean: clean-optee-test

optee-test-flags := CFG_CROSS_COMPILE="$(PWD)/toolchains/$(AARCH64_GCC_DIR)/bin/aarch64-linux-gnu-" \
		    CFG_TA_CROSS_COMPILE=arm-linux-gnueabihf- \
		    CFG_PLATFORM=hikey CFG_DEV_PATH=$(PWD) \
		    CFG_ROOTFS_DIR=$(PWD)/out

ifneq ($(filter all build-bl32,$(MAKECMDGOALS)),)
optee-test-deps += build-bl32
endif
ifneq ($(filter all build-optee-client,$(MAKECMDGOALS)),)
optee-test-deps += build-optee-client
endif

# FIXME: will rebuild all files, even if they are already up-to-date
.PHONY: build-optee-test
build-optee-test:: $(optee-test-deps)
build-optee-test:: $(aarch64-linux-gnu-gcc)
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C optee_test $(optee-test-flags)

# FIXME:
# No "make clean" in optee_test: fails if optee_os has been cleaned
# previously.
clean-optee-test:
	$(Q)rm -rf out public

else

IFTESTS=\#

endif # if optee_test/Makefile exists

#
# strace
#

STRACE = strace/strace
STRACE_EXPORTS := CC='$(CROSS_COMPILE)gcc' LD='$(CROSS_COMPILE)ld'

build-strace $(STRACE): strace/Makefile
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C strace

strace/Makefile: strace/configure
	$(ECHO) '  GEN     $@'
	$(Q)set -e ; export $(STRACE_EXPORTS) ; \
	    cd strace ; ./configure --host=aarch64-linux-gnu

strace/configure: strace/bootstrap
	$(ECHO) ' GEN      $@'
	$(Q)cd strace ; ./bootstrap

.PHONY: clean-strace
clean-strace:
	$(ECHO) '  CLEAN   $@'
	$(Q)export $(STRACE_EXPORTS) ; $(MAKE) -C strace clean

cleaner-strace:
	$(ECHO) '  CLEANER $@'
	$(Q)rm -f strace/Makefile strace/configure

