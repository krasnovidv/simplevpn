# SimpleVPN Mobile Library Build
#
# Prerequisites:
#   go install golang.org/x/mobile/cmd/gomobile@latest
#   gomobile init
#
# For Android: Android SDK + NDK must be installed
# For iOS: Xcode must be installed (macOS only)

MODULE := simplevpn/mobile/vpnlib

.PHONY: all android ios clean install-android

all: android ios

# Build Android .aar library
android:
	@echo "=== Building Android .aar ==="
	gomobile bind -target=android -androidapi 21 \
		-o build/vpnlib.aar \
		$(MODULE)
	@echo "Output: build/vpnlib.aar"

# Build and install AAR into Flutter app
install-android: android
	@echo "=== Installing AAR into Flutter app ==="
	cp build/vpnlib.aar app/android/app/libs/vpnlib.aar
	@echo "Installed: app/android/app/libs/vpnlib.aar"

# Build iOS .xcframework
ios:
	@echo "=== Building iOS .xcframework ==="
	gomobile bind -target=ios \
		-o build/Vpnlib.xcframework \
		$(MODULE)
	@echo "Output: build/Vpnlib.xcframework"

clean:
	rm -rf build/
