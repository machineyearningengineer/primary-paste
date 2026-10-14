.PHONY: help check build install version-check package-preview

help:
	@echo 'make check            Complete local quality gate'
	@echo 'make build            Unsigned build; no installation or launch'
	@echo 'make install          Signed local installation (see Docs/Developing.md)'
	@echo 'make version-check    Check version and release metadata'
	@echo 'make package-preview  Build unsigned universal inspection artifacts'

check:
	./Scripts/check.sh

build:
	xcodebuild -project PrimaryPaste.xcodeproj -scheme 'Primary Paste' -configuration Debug -derivedDataPath .artifacts/DeveloperBuild CODE_SIGNING_ALLOWED=NO build

install:
	./Scripts/install_dev_app.sh

version-check:
	python3 Scripts/release.py check

package-preview:
	python3 Scripts/release.py build --unsigned
