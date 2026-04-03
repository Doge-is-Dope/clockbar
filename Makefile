.PHONY: build install uninstall status clean menubar

MACOS_TARGET := $(shell uname -m)-apple-macos15.0

APP_SOURCES := \
	ClockBar/DesignSystem.swift \
	ClockBar/Services.swift \
	ClockBar/Components/PunchButtonStyle.swift \
	ClockBar/Components/ScheduleRow.swift \
	ClockBar/Components/StatusMetric.swift \
	ClockBar/Models.swift \
	ClockBar/ClockBar.swift \
	ClockBar/StatusViewModel.swift

HELPER_SOURCES := \
	ClockBar/Models.swift \
	ClockBar/Services.swift \
	ClockBarHelper.swift

build: ClockBar.app

ClockBar.app: $(APP_SOURCES) $(HELPER_SOURCES) ClockBar/Info.plist
	mkdir -p ClockBar.app/Contents/MacOS
	swiftc -o ClockBar.app/Contents/MacOS/clockbar $(APP_SOURCES) \
		-target $(MACOS_TARGET) \
		-framework SwiftUI -framework Cocoa -framework WebKit -framework UserNotifications -framework ServiceManagement -framework Security \
		-parse-as-library -O
	swiftc -o ClockBar.app/Contents/MacOS/clockbar-helper $(HELPER_SOURCES) \
		-target $(MACOS_TARGET) \
		-framework UserNotifications -framework Security -O
	cp ClockBar/Info.plist ClockBar.app/Contents/Info.plist
	codesign --force --sign - ClockBar.app

menubar: ClockBar.app
	open ClockBar.app

install: ClockBar.app
	cp -R ClockBar.app /Applications/
	/Applications/ClockBar.app/Contents/MacOS/clockbar-helper schedule install

uninstall:
	-if [ -x /Applications/ClockBar.app/Contents/MacOS/clockbar-helper ]; then /Applications/ClockBar.app/Contents/MacOS/clockbar-helper schedule remove; fi
	rm -rf /Applications/ClockBar.app

status: ClockBar.app
	./ClockBar.app/Contents/MacOS/clockbar-helper schedule status

clean:
	rm -rf ClockBar.app
