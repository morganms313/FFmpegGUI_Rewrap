import SwiftUI

struct ColorMetadataSectionView: View {
    @Binding var settings: JobSettings

    var body: some View {
        Section {
            OptionalPicker(label: "Color Primaries",
                           selection: $settings.colorPrimaries,
                           options: ColorPrimaries.allCases,
                           displayName: { $0.displayName })

            OptionalPicker(label: "Transfer Characteristics",
                           selection: $settings.colorTransfer,
                           options: ColorTransfer.allCases,
                           displayName: { $0.displayName })

            OptionalPicker(label: "Matrix Coefficients",
                           selection: $settings.colorMatrix,
                           options: ColorMatrix.allCases,
                           displayName: { $0.displayName })

            OptionalPicker(label: "Color Range",
                           selection: $settings.colorRange,
                           options: ColorRange.allCases,
                           displayName: { $0.displayName })

            // Quick-set presets
            HStack {
                Text("Quick Set")
                    .foregroundStyle(.secondary)
                Spacer()
                Menu("BT.709 HD") {
                    Button("BT.709 HD (Broadcast)") { applyBT709() }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Menu("BT.2020 HDR") {
                    Button("BT.2020 + PQ (HDR10)") { applyHDR10() }
                    Button("BT.2020 + HLG")         { applyHLG() }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button("Clear All") { clearColor() }
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                    .font(.callout)
            }

        } header: {
            Text("Color Metadata")
        } footer: {
            Text("Container-level tags are updated via stream copy. For H.264/HEVC, VUI parameters in the bitstream are also patched using a bitstream filter.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func applyBT709() {
        settings.colorPrimaries = .bt709
        settings.colorTransfer  = .bt709
        settings.colorMatrix    = .bt709
        settings.colorRange     = .limited
    }

    private func applyHDR10() {
        settings.colorPrimaries = .bt2020
        settings.colorTransfer  = .smpte2084
        settings.colorMatrix    = .bt2020nc
        settings.colorRange     = .limited
    }

    private func applyHLG() {
        settings.colorPrimaries = .bt2020
        settings.colorTransfer  = .arib_std_b67
        settings.colorMatrix    = .bt2020nc
        settings.colorRange     = .limited
    }

    private func clearColor() {
        settings.colorPrimaries = nil
        settings.colorTransfer  = nil
        settings.colorMatrix    = nil
        settings.colorRange     = nil
        settings.chromaSampleLocation = nil
    }
}
