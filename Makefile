.PHONY: app build test install clean

app:
	zsh Scripts/build-app.sh

build:
	swift build

test:
	zsh Scripts/test.sh

install: app
	zsh Scripts/install-app.sh

clean:
	swift package clean
