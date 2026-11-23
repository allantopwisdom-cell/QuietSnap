include ../AxsQuietSnapBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AxsQuietSnapPrefs
AxsQuietSnapPrefs_FILES = $(wildcard *.m)
AxsQuietSnapPrefs_CFLAGS = -fobjc-arc -I../Sources
AxsQuietSnapPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
AxsQuietSnapPrefs_PRIVATE_FRAMEWORKS = Preferences
AxsQuietSnapPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
