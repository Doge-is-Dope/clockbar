.PHONY: build install uninstall status clean menubar

build: Notify.app ClockBar.app

Notify.app: Notify/notify.swift Notify/Info.plist
	mkdir -p Notify.app/Contents/MacOS
	swiftc -o Notify.app/Contents/MacOS/notify Notify/notify.swift -framework UserNotifications -framework Cocoa
	cp Notify/Info.plist Notify.app/Contents/Info.plist
	codesign --force --sign - Notify.app

ClockBar.app: ClockBar/ClockBar.swift ClockBar/Info.plist
	mkdir -p ClockBar.app/Contents/MacOS
	swiftc -o ClockBar.app/Contents/MacOS/clockbar ClockBar/ClockBar.swift -framework SwiftUI -framework Cocoa -parse-as-library -O
	cp ClockBar/Info.plist ClockBar.app/Contents/Info.plist
	codesign --force --sign - ClockBar.app

menubar: ClockBar.app
	open ClockBar.app

install: build
	python3 clock104.py schedule install

uninstall:
	python3 clock104.py schedule remove

status:
	python3 clock104.py schedule status

clean:
	rm -rf Notify.app ClockBar.app
