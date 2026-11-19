TARGET := iphone:clang:latest:13.0
ARCHS := arm64
INSTALL_TARGET_PROCESSES := Paperback

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := PaperbackMod
PaperbackMod_FILES := Tweak.xm Notifier.xm KeepAlive.m SubstrateShim.m
PaperbackMod_FRAMEWORKS := UIKit UserNotifications AVFoundation Foundation
PaperbackMod_CFLAGS := -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
