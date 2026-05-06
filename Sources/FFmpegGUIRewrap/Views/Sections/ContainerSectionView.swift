import SwiftUI

struct ContainerSectionView: View {
    @Binding var settings: JobSettings
    let mediaFile: MediaFile

    private var video: StreamInfo? { mediaFile.primaryVideo }

    private var fastModeAvailable: Bool {
        [OutputFormat.mov, .mp4].contains(settings.outputFormat)
    }

    private var modeCaption: String {
        switch settings.frameRateConformMode {
        case .rewrap:
            return "Standard pipeline. All settings honoured. Slower for large files."
        case .fastClone:
            return "Clones source → output and patches atoms. Seconds, not minutes. Other settings ignored. .mov / .mp4 only."
        case .inPlace:
            return "⚠️ DESTRUCTIVE: patches the source file directly. No new file produced, no undo. Other settings ignored."
        }
    }

    var body: some View {
        Section("Container") {
            Picker("Output Format", selection: $settings.outputFormat) {
                ForEach(OutputFormat.allCases) { fmt in
                    Text(fmt.displayName).tag(fmt)
                }
            }
            .disabled(settings.frameRateConformMode != .rewrap)

            if settings.outputFormat == .mxf {
                Picker("OP Pattern", selection: $settings.mxfSettings.operationalPattern) {
                    ForEach(MXFOperationalPattern.allCases) { op in
                        Text(op.displayName).tag(op)
                    }
                }
                .disabled(settings.frameRateConformMode != .rewrap)
            }

            // Geometry overrides
            Group {
                OptionalTextField("Override SAR (e.g. 1:1)",
                                  value: $settings.sarOverride,
                                  label: "Sample Aspect Ratio",
                                  current: video?.sampleAspectRatio)

                OptionalTextField("Override DAR (e.g. 16:9)",
                                  value: $settings.darOverride,
                                  label: "Display Aspect Ratio",
                                  current: video?.displayAspectRatio)
            }
            .disabled(settings.frameRateConformMode != .rewrap)

            OptionalTextField("e.g. 24000/1001 or 24",
                              value: $settings.frameRateOverride,
                              label: "Frame Rate",
                              current: video?.rFrameRate)

            // Frame-rate conform mode picker.
            // .rewrap = standard FFmpeg pipeline (default).
            // .fastClone / .inPlace bypass FFmpeg — only for .mov / .mp4.
            Picker("Frame Rate Conform", selection: $settings.frameRateConformMode) {
                ForEach(FrameRateConformMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                        .disabled(mode != .rewrap && !fastModeAvailable)
                }
            }
            Text(modeCaption)
                .font(.caption)
                .foregroundStyle(settings.frameRateConformMode == .inPlace ? .red : .secondary)

            // Field order
            Group {
                OptionalPicker(label: "Field Order",
                               selection: $settings.fieldOrder,
                               options: FieldOrder.allCases,
                               displayName: { $0.displayName },
                               current: video?.fieldOrder)

                // Chroma sample location
                OptionalPicker(label: "Chroma Sample Location",
                               selection: $settings.chromaSampleLocation,
                               options: ChromaSampleLocation.allCases,
                               displayName: { $0.displayName },
                               current: video?.chromaLocation)
            }
            .disabled(settings.frameRateConformMode != .rewrap)
        }
        // Auto-revert to full rewrap if user switches to a non-QT output format
        .onChange(of: settings.outputFormat) {
            if !fastModeAvailable { settings.frameRateConformMode = .rewrap }
        }
    }
}
