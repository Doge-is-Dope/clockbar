.PHONY: build install uninstall status clean menubar dmg

VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' | grep . || echo "0.0.0-dev")
MACOS_TARGET := $(shell uname -m)-apple-macos15.0
DERIVED_DATA := build/DerivedData
XCODE_APP := $(DERIVED_DATA)/Build/Products/Release/ClockBar.app
SPARKLE_PUBLIC_ED_KEY ?=

APP_SOURCES := \
	ClockBar/Support/AppPaths.swift \
	ClockBar/Support/AutoPunchLock.swift \
	ClockBar/Support/Log.swift \
	ClockBar/Support/ClockStoreCoding.swift \
	ClockBar/Support/ConfigManager.swift \
	ClockBar/Support/DateFormatters.swift \
	ClockBar/Support/NotificationManager.swift \
	ClockBar/Support/Shell.swift \
	ClockBar/Support/StringExtensions.swift \
	ClockBar/Support/TimeHelpers.swift \
	ClockBar/Support/SystemUI.swift \
	ClockBar/Support/NotificationKind.swift \
	ClockBar/Support/NotificationLedger.swift \
	ClockBar/Models/ClockAction.swift \
	ClockBar/Models/ClockConfig.swift \
	ClockBar/Models/NextPunch.swift \
	ClockBar/Models/PunchStatus.swift \
	ClockBar/Models/ScheduledTime.swift \
	ClockBar/Models/ScheduleState.swift \
	ClockBar/Models/StoredSession.swift \
	ClockBar/API/Clock104API.swift \
	ClockBar/API/Clock104Error.swift \
	ClockBar/API/ClockService.swift \
	ClockBar/Auth/AuthStore.swift \
	ClockBar/Auth/AuthWindowController.swift \
	ClockBar/Auth/SessionRefreshSignal.swift \
	ClockBar/Auth/SilentAuthRefresher.swift \
	ClockBar/Scheduling/AutoPunchEngine.swift \
	ClockBar/Scheduling/HolidayStore.swift \
	ClockBar/Scheduling/LaunchAgentManager.swift \
	ClockBar/App/PunchReminderCoordinator.swift \
	ClockBar/App/StatusViewModel.swift \
	ClockBar/App/WakeObserver.swift \
	ClockBar/App/AppUpdater.swift \
	ClockBar/App/ClockBarApp.swift \
	ClockBar/UI/ContentView.swift \
	ClockBar/UI/DesignSystem.swift \
	ClockBar/UI/MenuPanelButton.swift \
	ClockBar/UI/MenuPanelToggleRow.swift \
	ClockBar/UI/PunchButtonStyle.swift \
	ClockBar/UI/SettingsView.swift \
	ClockBar/UI/StatusMetric.swift

HELPER_SOURCES := \
	ClockBar/Support/AppPaths.swift \
	ClockBar/Support/AutoPunchLock.swift \
	ClockBar/Support/Log.swift \
	ClockBar/Support/ClockStoreCoding.swift \
	ClockBar/Support/ConfigManager.swift \
	ClockBar/Support/DateFormatters.swift \
	ClockBar/Support/Shell.swift \
	ClockBar/Support/StringExtensions.swift \
	ClockBar/Support/TimeHelpers.swift \
	ClockBar/Support/SystemUI.swift \
	ClockBar/Support/NotificationKind.swift \
	ClockBar/Models/ClockAction.swift \
	ClockBar/Models/ClockConfig.swift \
	ClockBar/Models/NextPunch.swift \
	ClockBar/Models/PunchStatus.swift \
	ClockBar/Models/ScheduledTime.swift \
	ClockBar/Models/ScheduleState.swift \
	ClockBar/Models/StoredSession.swift \
	ClockBar/API/Clock104API.swift \
	ClockBar/API/Clock104Error.swift \
	ClockBar/API/ClockService.swift \
	ClockBar/Auth/AuthStore.swift \
	ClockBar/Auth/SessionRefreshSignal.swift \
	ClockBar/Scheduling/AutoPunchEngine.swift \
	ClockBar/Scheduling/HolidayStore.swift \
	ClockBar/Scheduling/LaunchAgentManager.swift \
	ClockBarHelper.swift

build: ClockBar.app

ClockBar.app: $(APP_SOURCES) $(HELPER_SOURCES) ClockBar/Info.plist ClockBar.xcodeproj/project.pbxproj
	xcodebuild -project ClockBar.xcodeproj -scheme ClockBar -configuration Release -destination "platform=macOS" -derivedDataPath $(DERIVED_DATA) SPARKLE_PUBLIC_ED_KEY="$(SPARKLE_PUBLIC_ED_KEY)" MARKETING_VERSION="$(VERSION)" CURRENT_PROJECT_VERSION="$(VERSION)" build
	rm -rf ClockBar.app
	cp -R "$(XCODE_APP)" ClockBar.app
	swiftc -o ClockBar.app/Contents/MacOS/clockbar-helper $(HELPER_SOURCES) \
		-target $(MACOS_TARGET) \
		-framework UserNotifications -O
	codesign --force --sign - ClockBar.app

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
