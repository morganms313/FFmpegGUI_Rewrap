import SwiftUI

struct HDRSectionView: View {
    @Binding var settings: JobSettings

    var body: some View {
        Section {
            Picker("HDR Mode", selection: $settings.hdrMode) {
                ForEach(HDRMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if settings.hdrMode == .set {
                masteringDisplaySection
                cllSection
            }

            Toggle("Strip Dolby Vision RPU", isOn: $settings.stripDolbyVisionRPU)
            Toggle("Strip HDR10+ SEI",       isOn: $settings.stripHDR10Plus)

        } header: {
            Text("HDR Metadata")
        } footer: {
            Text("Mastering display and content light level metadata is written to container tags. For HEVC, SEI is patched via bitstream filter.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Mastering Display

    private var masteringDisplaySection: some View {
        Group {
            Text("Mastering Display (SMPTE ST 2086)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            // Presets
            HStack {
                Text("Primaries Preset").foregroundStyle(.secondary)
                Spacer()
                Menu("Apply…") {
                    Button("P3-D65 (P3 Display)") {
                        settings.masteringDisplay = .p3d65
                    }
                    Button("BT.2020") {
                        settings.masteringDisplay = .bt2020
                    }
                    Button("DCI-P3") {
                        settings.masteringDisplay = .dciP3
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // Chromaticity grid
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Color.clear.frame(width: 40)
                    Text("x").font(.caption.bold()).foregroundStyle(.secondary)
                    Text("y").font(.caption.bold()).foregroundStyle(.secondary)
                }
                ChromaRow(label: "Red",   x: $settings.masteringDisplay.redX,   y: $settings.masteringDisplay.redY,   color: .red)
                ChromaRow(label: "Green", x: $settings.masteringDisplay.greenX, y: $settings.masteringDisplay.greenY, color: .green)
                ChromaRow(label: "Blue",  x: $settings.masteringDisplay.blueX,  y: $settings.masteringDisplay.blueY,  color: .blue)
                ChromaRow(label: "White", x: $settings.masteringDisplay.whiteX, y: $settings.masteringDisplay.whiteY, color: .primary)
            }

            // Luminance
            HStack(spacing: 16) {
                LabeledContent("Min Lum (cd/m²)") {
                    DecimalField(value: $settings.masteringDisplay.minLuminance, format: "%.4f")
                }
                LabeledContent("Max Lum (cd/m²)") {
                    DecimalField(value: $settings.masteringDisplay.maxLuminance, format: "%.0f")
                }
            }
        }
    }

    // MARK: - Content Light Level

    private var cllSection: some View {
        Group {
            Text("Content Light Level (CEA-861.3)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                LabeledContent("MaxCLL (cd/m²)") {
                    IntegerField(value: $settings.contentLightLevel.maxCLL, range: 0...10000)
                }
                LabeledContent("MaxFALL (cd/m²)") {
                    IntegerField(value: $settings.contentLightLevel.maxFALL, range: 0...10000)
                }
            }
        }
    }
}

// MARK: - Chromaticity row

struct ChromaRow: View {
    let label: String
    @Binding var x: Double
    @Binding var y: Double
    let color: Color

    var body: some View {
        GridRow {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).font(.caption)
            }
            DecimalField(value: $x, format: "%.4f").frame(width: 80)
            DecimalField(value: $y, format: "%.4f").frame(width: 80)
        }
    }
}
