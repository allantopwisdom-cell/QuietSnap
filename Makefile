DEBUG = 0
FINALPACKAGE = 1

ARCHS = arm64 arm64e

# Share the SDK and deployment targets with the PreferenceBundle.
include AxsQuietSnapBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AxsQuietSnap
AxsQuietSnap_FILES = $(wildcard Hooks/*.xm Sources/*.m)
AxsQuietSnap_CFLAGS = -fobjc-arc -I./Headers -I./Sources
AxsQuietSnap_FRAMEWORKS = UIKit Foundation CoreFoundation AVFoundation Photos AudioToolbox CoreMedia CoreGraphics
# substrate is resolved with dlopen at runtime (see AxsQuietSnapMain.xm)

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += AxsQuietSnapPrefs
SUBPROJECTS += AxsQuietSnapCCAudio
SUBPROJECTS += AxsQuietSnapCCVideo
SUBPROJECTS += AxsQuietSnapCCPhoto
include $(THEOS_MAKE_PATH)/aggregate.mk
