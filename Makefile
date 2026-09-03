.PHONY: app build test package install clean

app:
	zsh Scripts/build-app.sh

build:
	swift build

test:
	zsh Scripts/test.sh

package: test
	zsh Scripts/package-app.sh

install: app
	zsh Scripts/install-app.sh

clean:
	swift package clean
