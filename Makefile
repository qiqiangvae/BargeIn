.PHONY: build run app open clean

build:
	swift build

run:
	swift run BargeIn

app:
	bash scripts/bundle.sh

open: app
	open "Barge In.app"

clean:
	swift package clean
	rm -rf "Barge In.app"
