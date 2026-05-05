# -----------------------------------------------------------------------
# FFmpegGUI-Rewrap — build & package a standalone macOS .app
#
#   make               build debug (native arch) + package  [fast, for dev]
#   make release       build universal release (arm64 + x86_64) + package
#   make run           build debug, package, and launch
#   make fetch-ffmpeg  download arm64 ffmpeg + ffprobe from evermeet.cx
#                      (Intel: app falls back to Homebrew /usr/local/bin/ffmpeg)
#   make clean         remove build artefacts
# -----------------------------------------------------------------------

PRODUCT       = FFmpegGUI-Rewrap
APP           = $(PRODUCT).app
PLIST         = Info.plist
FFMPEG_BIN    = Sources/FFmpegGUIRewrap/Resources/bin

DEBUG_BIN     = .build/debug/$(PRODUCT)
UNIVERSAL_BIN = .build/universal/$(PRODUCT)

.PHONY: all debug release run fetch-ffmpeg clean

all: debug

debug:
	swift build
	@$(MAKE) --no-print-directory _bundle BIN=$(DEBUG_BIN)

# Release always produces a universal binary (arm64 + x86_64).
# The bundled ffmpeg (arm64 from evermeet.cx) is lipo'd with the Intel
# Homebrew build when available; otherwise arm64 only is bundled and
# Intel users fall back to the system/Homebrew ffmpeg automatically.
release:
	@echo "→ Building arm64…"
	swift build -c release --arch arm64
	@echo "→ Building x86_64…"
	swift build -c release --arch x86_64
	@mkdir -p .build/universal
	lipo -create -output $(UNIVERSAL_BIN) \
	    .build/arm64-apple-macosx/release/$(PRODUCT) \
	    .build/x86_64-apple-macosx/release/$(PRODUCT)
	@echo "→ Merging ffmpeg binaries…"
	@$(MAKE) --no-print-directory _lipo_ffmpeg
	@$(MAKE) --no-print-directory _bundle BIN=$(UNIVERSAL_BIN)

# Merge arm64 ffmpeg (evermeet.cx bundle) with x86_64 (Homebrew) into fat binaries.
# Skips lipo gracefully if either side is missing.
_lipo_ffmpeg:
	@for TOOL in ffmpeg ffprobe; do \
	    ARM64="$(FFMPEG_BIN)/$$TOOL"; \
	    INTEL="/usr/local/bin/$$TOOL"; \
	    OUT="$(FFMPEG_BIN)/$${TOOL}_universal"; \
	    if [ -f "$$ARM64" ] && [ -f "$$INTEL" ]; then \
	        lipo -create -output "$$OUT" "$$ARM64" "$$INTEL" && \
	        mv "$$OUT" "$$ARM64" && \
	        echo "  ✓ $$TOOL: universal (arm64 + x86_64)"; \
	    elif [ -f "$$ARM64" ]; then \
	        echo "  ⚠ $$TOOL: arm64 only (Intel Homebrew not found at $$INTEL — Intel users need: brew install ffmpeg)"; \
	    else \
	        echo "  ⚠ $$TOOL: not found — run 'make fetch-ffmpeg' first"; \
	    fi; \
	done

run: debug
	open $(APP)

# Download the latest arm64 static ffmpeg + ffprobe from evermeet.cx.
# evermeet.cx provides Apple Silicon builds only. Intel users are served by
# the app's automatic fallback to Homebrew (/usr/local/bin/ffmpeg).
fetch-ffmpeg:
	@ARCH=$$(uname -m); \
	if [ "$$ARCH" = "arm64" ]; then \
	    echo "→ Downloading arm64 ffmpeg from evermeet.cx…"; \
	    mkdir -p $(FFMPEG_BIN); \
	    curl -# -L "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip" -o /tmp/ffmpeg.zip; \
	    unzip -o /tmp/ffmpeg.zip -d $(FFMPEG_BIN) && rm /tmp/ffmpeg.zip; \
	    curl -# -L "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip" -o /tmp/ffprobe.zip; \
	    unzip -o /tmp/ffprobe.zip -d $(FFMPEG_BIN) && rm /tmp/ffprobe.zip; \
	    chmod +x $(FFMPEG_BIN)/ffmpeg $(FFMPEG_BIN)/ffprobe; \
	    echo "✓ Binaries ready:"; \
	    $(FFMPEG_BIN)/ffmpeg -version 2>&1 | head -1; \
	else \
	    echo "ℹ Intel Mac detected — evermeet.cx provides arm64 builds only."; \
	    echo "  The app automatically uses Homebrew ffmpeg on Intel."; \
	    echo "  If not installed: brew install ffmpeg"; \
	    if [ -x "/usr/local/bin/ffmpeg" ]; then \
	        echo "  ✓ Found: $$(/usr/local/bin/ffmpeg -version 2>&1 | head -1)"; \
	    else \
	        echo "  ⚠ /usr/local/bin/ffmpeg not found — run: brew install ffmpeg"; \
	    fi; \
	fi

# Internal: package a binary into the .app bundle
_bundle:
	@echo "→ Packaging $(APP)…"
	@# Always start from a clean bundle so Finder metadata never accumulates
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS
	@mkdir -p $(APP)/Contents/Resources/bin
	@cp $(BIN) $(APP)/Contents/MacOS/$(PRODUCT)
	@cp $(PLIST) $(APP)/Contents/Info.plist
	@# Show architectures in the packaged binary
	@echo "  ✓ App binary: $$(lipo -archs $(APP)/Contents/MacOS/$(PRODUCT))"
	@# Copy bundled FFmpeg binaries if present
	@if [ -f $(FFMPEG_BIN)/ffmpeg ] && [ -f $(FFMPEG_BIN)/ffprobe ]; then \
		cp $(FFMPEG_BIN)/ffmpeg  $(APP)/Contents/Resources/bin/ffmpeg; \
		cp $(FFMPEG_BIN)/ffprobe $(APP)/Contents/Resources/bin/ffprobe; \
		echo "  ✓ Bundled ffmpeg $$($(FFMPEG_BIN)/ffmpeg -version 2>&1 | head -1 | awk '{print $$3}') ($$(lipo -archs $(APP)/Contents/Resources/bin/ffmpeg))"; \
	else \
		echo "  ⚠ No bundled ffmpeg — run 'make fetch-ffmpeg' (Intel: brew install ffmpeg)"; \
	fi
	@# Strip any extended attributes before signing
	@xattr -cr $(APP)
	@codesign --force --deep --sign - $(APP)
	@echo "✓ Done — launch with:  open $(APP)"

clean:
	swift package clean
	rm -rf $(APP) .build/universal
