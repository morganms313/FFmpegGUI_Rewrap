import SwiftUI

struct MXFSectionView: View {
    @Binding var settings: JobSettings

    var body: some View {
        Section {
            Picker("Operational Pattern", selection: $settings.mxfSettings.operationalPattern) {
                ForEach(MXFOperationalPattern.allCases) { op in
                    Text(op.displayName).tag(op)
                }
            }

            Picker("Audio Layout", selection: $settings.mxfSettings.audioLayout) {
                ForEach(MXFAudioLayout.allCases) { layout in
                    Text(layout.rawValue).tag(layout)
                }
            }

            Toggle("Preserve Material Package UMID", isOn: $settings.mxfSettings.preserveUMID)
            Toggle("Regenerate Source Package UID",  isOn: $settings.mxfSettings.regenerateSourcePackageUID)
            Toggle("Preserve KLV Metadata",          isOn: $settings.mxfSettings.preserveKLV)

        } header: {
            Text("MXF")
        } footer: {
            Text("OP-Atom wraps a single essence stream per file. OP1a interleaves all streams in one file.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
