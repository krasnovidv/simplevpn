# SimpleVPN Mobile Library Build
#
# Prerequisites:
#   go install golang.org/x/mobile/cmd/gomobile@latest
#   gomobile init
#
# For Android: Android SDK + NDK must be installed
# For iOS: Xcode must be installed (macOS only)

MODULE := simplevpn/mobile/vpnlib

.PHONY: all android ios clean

all: android ios

# Build Android .aar library
android:
	@echo "=== Building Android .aar ==="
	gomobile bind -target=android -androidapi 21 \
		-o build/vpnlib.aar \
		$(MODULE)
	@echo "Output: build/vpnlib.aar"

# Build iOS .xcframework
ios:
	@echo "=== Building iOS .xcframework ==="
	gomobile bind -target=ios \
		-o build/Vpnlib.xcframework \
		$(MODULE)
	@echo "Output: build/Vpnlib.xcframework"

clean:
	rm -rf build/
