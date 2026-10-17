# Glasspad developer tasks. Run `make` (or `make help`) to list them.
# Each task is a thin wrapper around a script in scripts/ (see scripts/README.md) or a web/ npm
# script, so you can always run the underlying command directly. Works with the GNU Make 3.81
# that ships with macOS.

SHELL := /bin/bash
.DEFAULT_GOAL := help
ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# Where SwiftPM and Xcode build for this checkout, outside the repo (scripts/toolchain.sh).
# Computed only when a task needs it.
BUILD_ROOT = $(shell cd "$(ROOT)" && bash -c '. scripts/toolchain.sh >/dev/null 2>&1; printf %s "$$GP_BUILD_ROOT"')
CACHE_ROOT := $(HOME)/Library/Caches/glasspad-build

# Optional inputs: make test ARGS="--filter Layout", make install-phone DEVICE=<udid>.
ARGS ?=
DEVICE ?=

.PHONY: help doctor test build-ios build-mac install-mac install-phone autorefresh live-check \
        web-deps web web-dev web-preview web-themes icons lint clean

help: ## List every task
	@echo "Glasspad tasks (run from the repo root, or with make -C <repo>):"
	@echo
	@awk 'BEGIN {FS = ":.*## "} /^[a-z][a-z-]*:.*## / {printf "  make %-14s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Inputs: ARGS=\"...\" goes to the script behind test and live-check (make test ARGS=\"--filter Layout\")."
	@echo "        DEVICE=<udid> picks the iPhone for install-phone."
	@echo "Every script also answers --help. Details: scripts/README.md"

doctor: ## Check which tools this Mac has (changes nothing)
	@cd "$(ROOT)"; ok=0; \
	check() { if command -v "$$1" >/dev/null 2>&1; then printf '  ok       %-11s %s\n' "$$1" "$$("$${@:2}" 2>&1 | head -1)"; \
	          else printf '  missing  %-11s %s\n' "$$1" "$$need"; ok=1; fi; }; \
	echo "Needed for tests and the Mac app:"; \
	need="install Xcode or run: xcode-select --install"; check swift swift --version; \
	echo "Needed for the iPhone app:"; \
	need="install Xcode from the App Store"; check xcodebuild xcodebuild -version; \
	need="brew install xcodegen"; check xcodegen xcodegen --version; \
	echo "Needed for the website:"; \
	need="brew install node"; check node node --version; check npm npm --version; \
	if [ -d web/node_modules ]; then echo "  ok       web deps    web/node_modules is there"; \
	else echo "  missing  web deps    run: make web-deps"; ok=1; fi; \
	echo "Optional:"; \
	need="brew install shellcheck (used by make lint)"; check shellcheck shellcheck --version; \
	if python3 -I -c 'import PIL' >/dev/null 2>&1; then echo "  ok       Pillow      for the visual checks"; \
	else echo "  missing  Pillow      python3 -m pip install Pillow (only for scripts/visual-check*.sh)"; fi; \
	if [ $$ok = 0 ]; then echo "All needed tools are here."; else echo "Some tools are missing; see above."; fi

test: ## Run every test: Swift packages, installer, main thread check (scripts/test.sh)
	cd "$(ROOT)" && scripts/test.sh $(ARGS)

build-ios: ## Build the iPhone app for the simulator, unsigned (needs Xcode and xcodegen)
	@cd "$(ROOT)" && command -v xcodegen >/dev/null || { echo "xcodegen is missing: brew install xcodegen" >&2; exit 1; }
	cd "$(ROOT)" && xcodegen generate --quiet
	cd "$(ROOT)" && xcodebuild -project Glasspad.xcodeproj -scheme "Glasspad iOS" -configuration Debug \
	  -destination "generic/platform=iOS Simulator" -derivedDataPath "$(BUILD_ROOT)/ios" \
	  CODE_SIGNING_ALLOWED=NO -quiet build
	@echo "Built $(BUILD_ROOT)/ios/Build/Products/Debug-iphonesimulator/Glasspad.app"

build-mac: ## Build the Mac app into build/Glasspad.app, ad hoc signed (scripts/build-mac.sh)
	cd "$(ROOT)" && scripts/build-mac.sh

install-mac: ## Build, sign and install the Mac app in /Applications, then restart it
	cd "$(ROOT)" && scripts/install-mac.sh

install-phone: ## Build and install on your iPhone; DEVICE=<udid> picks one (scripts/install-phone.sh)
	cd "$(ROOT)" && scripts/install-phone.sh $(DEVICE)

autorefresh: ## Turn on the hourly job that renews the iPhone install (scripts/setup-autorefresh.sh)
	cd "$(ROOT)" && scripts/setup-autorefresh.sh

live-check: ## Try every Mac feature for real, one step at a time (scripts/live-check.sh)
	cd "$(ROOT)" && scripts/live-check.sh $(ARGS)

web-deps: ## Install the website's npm packages from web/package-lock.json
	cd "$(ROOT)/web" && npm ci

web: ## Build the website into web/dist (type check, then Vite)
	@cd "$(ROOT)" && [ -d web/node_modules ] || { echo "Run make web-deps first." >&2; exit 1; }
	cd "$(ROOT)/web" && npm run build

web-dev: ## Serve the website locally with live reload (Vite dev server)
	@cd "$(ROOT)" && [ -d web/node_modules ] || { echo "Run make web-deps first." >&2; exit 1; }
	cd "$(ROOT)/web" && npm run dev

web-preview: ## Serve the built web/dist at http://localhost:4173
	cd "$(ROOT)/web" && npm run preview

web-themes: ## Copy the app's theme list into web/src/themes.ts (scripts/web-themes.sh)
	cd "$(ROOT)" && scripts/web-themes.sh

icons: ## Redraw the app icons (scripts/make-icons.swift)
	cd "$(ROOT)" && swift scripts/make-icons.swift

lint: ## Check scripts and web types (scripts/lint.sh when present)
	@cd "$(ROOT)"; \
	if [ -f scripts/lint.sh ]; then exec bash scripts/lint.sh $(ARGS); fi; \
	set -e; \
	echo "== shell syntax"; \
	for f in install.sh scripts/*.sh scripts/tests/*.sh scripts/tests/stubs/*; do bash -n "$$f"; done; \
	if command -v shellcheck >/dev/null; then \
	  echo "== shellcheck (errors fail, warnings are shown)"; \
	  shellcheck -x --shell=bash -S warning install.sh scripts/*.sh scripts/tests/*.sh || true; \
	  shellcheck -x --shell=bash -S error install.sh scripts/*.sh scripts/tests/*.sh; \
	else echo "== shellcheck not installed (brew install shellcheck); skipped"; fi; \
	echo "== python syntax"; \
	python3 -I -c 'import ast, sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]' scripts/*.py; \
	if [ -d web/node_modules ]; then echo "== web types"; (cd web && npx --no-install tsc --noEmit); \
	else echo "== web types skipped (run make web-deps)"; fi; \
	echo "lint: ok"

clean: ## Remove this checkout's build folders (prints each one; nothing outside the repo or its cache)
	@cd "$(ROOT)"; \
	gone=0; \
	rmv() { if [ -e "$$1" ] || [ -L "$$1" ]; then echo "  removing $$1"; rm -rf -- "$$1"; gone=1; fi; }; \
	for d in build Glasspad.xcodeproj web/dist web/public/img Apps/*/.build Packages/*/.build; do rmv "$(ROOT)/$$d"; done; \
	b="$(BUILD_ROOT)"; \
	case "$$b" in \
	  "$(CACHE_ROOT)"/?*) rmv "$$b" ;; \
	  *) echo "  skipping $$b: not under $(CACHE_ROOT) (GLASSPAD_BUILD_ROOT is set), remove it yourself" ;; \
	esac; \
	if [ $$gone = 0 ]; then echo "Nothing to clean."; else echo "Clean."; fi
