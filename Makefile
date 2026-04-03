.PHONY: build install uninstall status clean menubar

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

clean:
	rm -rf ClockBar.app
