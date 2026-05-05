import SwiftUI

struct ContainerSectionView: View {
    @Binding var settings: JobSettings
    let mediaFile: MediaFile

    private var video: StreamInfo? { mediaFile.primaryVideo }

    var body: some View {
        Section("Container") {
            Picker("Output Format", selection: $settings.outputFormat) {
                ForEach(OutputFormat.allCases) { fmt in
                    Text(fmt.displayName).tag(fmt)
                }
            }

            if settings.outputFormat == .mxf {
                Picker("OP Pattern", selection: $settings.mxfSettings.operationalPattern) {
                    ForEach(MXFOperationalPattern.allCases) { op in
                        Text(op.displayName).tag(op)
                    }
                }
            }

            // Geometry overrides
            OptionalTextField("Override SAR (e.g. 1:1)",
                              value: $settings.sarOverride,
                              label: "Sample Aspect Ratio",
                              current: video?.sampleAspectRatio)

            OptionalTextField("Override DAR (e.g. 16:9)",
                              value: $settings.darOverride,
                              label: "Display Aspect Ratio",
                              current: video?.displayAspectRatio)

            OptionalTextField("e.g. 24000/1001 or 24",
                              value: $settings.frameRateOverride,
                              label: "Frame Rate",
                              current: video?.rFrameRate)

            // Field order
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
    }
}
