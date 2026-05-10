.PHONY: build install uninstall status clean menubar dmg lint format

VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' | grep . || echo "0.0.0-dev")
DERIVED_DATA := build/DerivedData
XCODE_APP := $(DERIVED_DATA)/Build/Products/Release/ClockBar.app
SWIFT_PATHS := ClockBar ClockBarHelper.swift
SWIFT_SOURCES := $(shell find ClockBar -name '*.swift') ClockBarHelper.swift
SWIFT_FORMAT := $(shell command -v swift-format 2>/dev/null || echo xcrun swift-format)

build: ClockBar.app

ClockBar.app: $(SWIFT_SOURCES) ClockBar/Info.plist ClockBar.xcodeproj/project.pbxproj
	xcodebuild -project ClockBar.xcodeproj -scheme ClockBar -configuration Release -destination "platform=macOS" -derivedDataPath $(DERIVED_DATA) MARKETING_VERSION="$(VERSION)" CURRENT_PROJECT_VERSION="$(VERSION)" build
	rm -rf ClockBar.app
	cp -R "$(XCODE_APP)" ClockBar.app

lint:
	$(SWIFT_FORMAT) lint --strict --recursive $(SWIFT_PATHS)

format:
	$(SWIFT_FORMAT) format --in-place --recursive $(SWIFT_PATHS)

menubar: ClockBar.app
	-pkill -f ClockBar 2>/dev/null
	open ClockBar.app

install: ClockBar.app
	cp -R ClockBar.app /Applications/
	/Applications/ClockBar.app/Contents/MacOS/clockbar-helper schedule install

uninstall:
	-if [ -x /Applications/ClockBar.app/Contents/MacOS/clockbar-helper ]; then /Applications/ClockBar.app/Contents/MacOS/clockbar-helper schedule remove; fi
	rm -rf /Applications/ClockBar.app

status: ClockBar.app
	./ClockBar.app/Contents/MacOS/clockbar-helper schedule status

dmg: ClockBar.app
	rm -rf dmg_staging ClockBar-$(VERSION).dmg
	mkdir -p dmg_staging
	cp -R ClockBar.app dmg_staging/
	ln -s /Applications dmg_staging/Applications
	hdiutil create -volname "ClockBar" -srcfolder dmg_staging -ov -format UDZO "ClockBar-$(VERSION).dmg"
	rm -rf dmg_staging

clean:
	rm -rf ClockBar.app dmg_staging ClockBar-*.dmg
