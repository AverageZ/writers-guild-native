.PHONY: all editor build app run test clean
all: app
editor:
	cd Editor && npm ci && npm run build
build: editor
	swift build
app: build
	python3 scripts/bundle.py
run: app
	open build/WritersGuild.app
test: editor
	swift test
	cd Editor && npm test
clean:
	swift package clean
