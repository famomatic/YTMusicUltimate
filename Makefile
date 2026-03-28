ifeq ($(ROOTLESS),1)
THEOS_PACKAGE_SCHEME = rootless
else ifeq ($(ROOTHIDE),1)
THEOS_PACKAGE_SCHEME = roothide
endif

ARCHS = arm64
INSTALL_TARGET_PROCESSES = YouTubeMusic
TARGET = iphone:clang:16.5:13.0
PACKAGE_VERSION = 2.4.1
ENABLE_DISCORD_SOCIAL_SDK ?= 1
DISCORD_SDK_ROOT ?= $(CURDIR)/ThirdParty/discord_social_sdk
DISCORD_SDK_INCLUDE_DIR := $(DISCORD_SDK_ROOT)/include
DISCORD_SDK_IOS_FRAMEWORK_DIR := $(DISCORD_SDK_ROOT)/ios
DISCORD_SDK_FRAMEWORK := $(DISCORD_SDK_IOS_FRAMEWORK_DIR)/discord_partner_sdk.framework
DISCORD_SDK_BINARY := $(DISCORD_SDK_FRAMEWORK)/discord_partner_sdk

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YTMusicUltimate
$(TWEAK_NAME)_FILES = $(filter-out Source/Sideloading.x, $(wildcard Source/*.x))
$(TWEAK_NAME)_FILES += $(shell find Source -name '*.m')
$(TWEAK_NAME)_FILES += $(shell find Source -name '*.mm')
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -DTWEAK_VERSION=$(PACKAGE_VERSION)
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation AVFoundation AudioToolbox VideoToolbox SystemConfiguration
$(TWEAK_NAME)_OBJ_FILES = $(shell find Source/Utils/lib -name '*.a')
$(TWEAK_NAME)_LIBRARIES = bz2 c++ iconv z

ifeq ($(ENABLE_DISCORD_SOCIAL_SDK),1)
ifeq ($(wildcard $(DISCORD_SDK_INCLUDE_DIR)/discord_partner_sdk/discordpp.h),)
$(error Discord Social SDK header not found at $(DISCORD_SDK_INCLUDE_DIR)/discord_partner_sdk/discordpp.h. Download and extract the official SDK to ThirdParty/discord_social_sdk)
endif
ifeq ($(wildcard $(DISCORD_SDK_BINARY)),)
$(error Discord Social SDK iOS framework binary not found at $(DISCORD_SDK_BINARY). Download and extract the official SDK to ThirdParty/discord_social_sdk)
endif
$(TWEAK_NAME)_CFLAGS += -DYTMU_DISCORD_SOCIAL_SDK=1 -I$(DISCORD_SDK_INCLUDE_DIR) -I$(DISCORD_SDK_FRAMEWORK)/Headers
$(TWEAK_NAME)_CCFLAGS += -std=c++17
$(TWEAK_NAME)_LDFLAGS += -F$(DISCORD_SDK_IOS_FRAMEWORK_DIR) -framework discord_partner_sdk -Wl,-rpath,@loader_path
else
$(TWEAK_NAME)_CFLAGS += -DYTMU_DISCORD_SOCIAL_SDK=0
endif

ifeq ($(SIDELOADING),1)
$(TWEAK_NAME)_FILES += Source/Sideloading.x
endif

include $(THEOS_MAKE_PATH)/tweak.mk

before-package::
ifeq ($(ENABLE_DISCORD_SOCIAL_SDK),1)
	@mkdir -p $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries
	@rm -rf $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/discord_partner_sdk.framework
	@cp -R $(DISCORD_SDK_FRAMEWORK) $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/
endif
