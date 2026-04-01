.PHONY: build install uninstall status clean menubar

build: ClockBar.app

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
	rm -rf ClockBar.app
