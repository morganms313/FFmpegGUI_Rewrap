# -----------------------------------------------------------------------
# FFmpegGUI-Rewrap — build & package a standalone macOS .app
#
#   make               build debug + package
#   make release       build release (optimised) + package
#   make run           build debug, package, and launch
#   make fetch-ffmpeg  download ffmpeg + ffprobe into Resources/bin/
#   make clean         remove build artefacts
# -----------------------------------------------------------------------

PRODUCT       = FFmpegGUI-Rewrap
APP           = $(PRODUCT).app
PLIST         = Info.plist
FFMPEG_BIN    = Sources/FFmpegGUIRewrap/Resources/bin

DEBUG_BIN     = .build/debug/$(PRODUCT)
RELEASE_BIN   = .build/release/$(PRODUCT)

.PHONY: all debug release run fetch-ffmpeg clean

all: debug

debug:
	swift build
	@$(MAKE) --no-print-directory _bundle BIN=$(DEBUG_BIN)

release:
	swift build -c release
	@$(MAKE) --no-print-directory _bundle BIN=$(RELEASE_BIN)

run: debug
	open $(APP)

# Download the latest static ffmpeg + ffprobe from evermeet.cx
fetch-ffmpeg:
	@echo "→ Downloading ffmpeg…"
	@mkdir -p $(FFMPEG_BIN)
	@curl -# -L "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip" -o /tmp/ffmpeg.zip
	@unzip -o /tmp/ffmpeg.zip -d $(FFMPEG_BIN) && rm /tmp/ffmpeg.zip
	@echo "→ Downloading ffprobe…"
	@curl -# -L "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip" -o /tmp/ffprobe.zip
	@unzip -o /tmp/ffprobe.zip -d $(FFMPEG_BIN) && rm /tmp/ffprobe.zip
	@chmod +x $(FFMPEG_BIN)/ffmpeg $(FFMPEG_BIN)/ffprobe
	@echo "✓ Binaries ready in $(FFMPEG_BIN)/"
	@$(FFMPEG_BIN)/ffmpeg -version 2>&1 | head -1

# Internal: package a binary into the .app bundle
_bundle:
	@echo "→ Packaging $(APP)…"
	@# Always start from a clean bundle so Finder metadata never accumulates
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS
	@mkdir -p $(APP)/Contents/Resources/bin
	@cp $(BIN) $(APP)/Contents/MacOS/$(PRODUCT)
	@cp $(PLIST) $(APP)/Contents/Info.plist
	@# Copy bundled FFmpeg binaries if present
	@if [ -f $(FFMPEG_BIN)/ffmpeg ] && [ -f $(FFMPEG_BIN)/ffprobe ]; then \
		cp $(FFMPEG_BIN)/ffmpeg  $(APP)/Contents/Resources/bin/ffmpeg; \
		cp $(FFMPEG_BIN)/ffprobe $(APP)/Contents/Resources/bin/ffprobe; \
		echo "  ✓ Bundled ffmpeg $$($(FFMPEG_BIN)/ffmpeg -version 2>&1 | head -1 | awk '{print $$3}')"; \
	else \
		echo "  ⚠ No bundled ffmpeg found — run 'make fetch-ffmpeg' first"; \
	fi
	@# Strip any extended attributes before signing
	@xattr -cr $(APP)
	@codesign --force --deep --sign - $(APP)
	@echo "✓ Done — launch with:  open $(APP)"

clean:
	swift package clean
	rm -rf $(APP)
