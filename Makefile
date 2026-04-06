.PHONY: build install uninstall status clean menubar dmg

VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0-dev")
MACOS_TARGET := $(shell uname -m)-apple-macos15.0

APP_SOURCES := \
	ClockBar/Support/AppPaths.swift \
	ClockBar/Support/AutoPunchLog.swift \
	ClockBar/Support/ClockStoreCoding.swift \
	ClockBar/Support/ConfigManager.swift \
	ClockBar/Support/DateFormatters.swift \
	ClockBar/Support/NotificationManager.swift \
	ClockBar/Support/Shell.swift \
	ClockBar/Support/StringExtensions.swift \
	ClockBar/Support/SystemUI.swift \
	ClockBar/Models/ClockAction.swift \
	ClockBar/Models/ClockConfig.swift \
	ClockBar/Models/PunchStatus.swift \
	ClockBar/Models/ScheduledTime.swift \
	ClockBar/Models/ScheduleState.swift \
	ClockBar/Models/StoredSession.swift \
	ClockBar/API/Clock104API.swift \
	ClockBar/API/Clock104Error.swift \
	ClockBar/API/ClockService.swift \
	ClockBar/Auth/AuthStore.swift \
	ClockBar/Auth/AuthWindowController.swift \
	ClockBar/Scheduling/AutoPunchEngine.swift \
	ClockBar/Scheduling/HolidayStore.swift \
	ClockBar/Scheduling/LaunchAgentManager.swift \
	ClockBar/Scheduling/PowerStateMonitor.swift \
	ClockBar/App/StatusViewModel.swift \
	ClockBar/App/ClockBarApp.swift \
	ClockBar/UI/ContentView.swift \
	ClockBar/UI/DesignSystem.swift \
	ClockBar/UI/MenuPanelButton.swift \
	ClockBar/UI/MenuPanelToggleRow.swift \
	ClockBar/UI/PunchButtonStyle.swift \
	ClockBar/UI/ScheduleRow.swift \
	ClockBar/UI/SettingsView.swift \
	ClockBar/UI/StatusMetric.swift

HELPER_SOURCES := \
	ClockBar/Support/AppPaths.swift \
	ClockBar/Support/AutoPunchLog.swift \
	ClockBar/Support/ClockStoreCoding.swift \
	ClockBar/Support/ConfigManager.swift \
	ClockBar/Support/DateFormatters.swift \
	ClockBar/Support/Shell.swift \
	ClockBar/Support/StringExtensions.swift \
	ClockBar/Support/SystemUI.swift \
	ClockBar/Models/ClockAction.swift \
	ClockBar/Models/ClockConfig.swift \
	ClockBar/Models/PunchStatus.swift \
	ClockBar/Models/ScheduledTime.swift \
	ClockBar/Models/ScheduleState.swift \
	ClockBar/Models/StoredSession.swift \
	ClockBar/API/Clock104API.swift \
	ClockBar/API/Clock104Error.swift \
	ClockBar/API/ClockService.swift \
	ClockBar/Auth/AuthStore.swift \
	ClockBar/Scheduling/AutoPunchEngine.swift \
	ClockBar/Scheduling/HolidayStore.swift \
	ClockBar/Scheduling/LaunchAgentManager.swift \
	ClockBar/Scheduling/PowerStateMonitor.swift \
	ClockBarHelper.swift

build: ClockBar.app

ClockBar.app: $(APP_SOURCES) $(HELPER_SOURCES) ClockBar/Info.plist
	mkdir -p ClockBar.app/Contents/MacOS ClockBar.app/Contents/Resources
	actool ClockBar/Resources/Assets.xcassets \
		--compile ClockBar.app/Contents/Resources \
		--platform macosx --minimum-deployment-target 15.0 \
		--output-partial-info-plist /dev/null
	swiftc -o ClockBar.app/Contents/MacOS/clockbar $(APP_SOURCES) \
		-target $(MACOS_TARGET) \
		-framework SwiftUI -framework Cocoa -framework WebKit -framework UserNotifications -framework ServiceManagement \
		-parse-as-library -O
	swiftc -o ClockBar.app/Contents/MacOS/clockbar-helper $(HELPER_SOURCES) \
		-target $(MACOS_TARGET) \
		-framework UserNotifications -O
	cp ClockBar/Info.plist ClockBar.app/Contents/Info.plist
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" ClockBar.app/Contents/Info.plist
	plutil -replace CFBundleVersion -string "$(VERSION)" ClockBar.app/Contents/Info.plist
	codesign --force --sign - ClockBar.app

menubar: ClockBar.app
	-pkill -x clockbar 2>/dev/null
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
