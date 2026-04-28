import SwiftUI

struct MetadataFormView: View {
    @Binding var settings: JobSettings
    let mediaFile: MediaFile

    var body: some View {
        Form {
            ContainerSectionView(settings: $settings)
            ColorMetadataSectionView(settings: $settings)
            AFDSectionView(settings: $settings)
            HDRSectionView(settings: $settings)
            TimecodeSectionView(settings: $settings)
            AudioSectionView(settings: $settings, mediaFile: mediaFile)
            if settings.outputFormat == .mxf {
                MXFSectionView(settings: $settings)
            }
            if settings.outputFormat == .mov {
                QuickTimeSectionView(settings: $settings)
            }
            GeneralMetadataSectionView(settings: $settings)
            OutputSectionView(settings: $settings)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Output section (within form)

struct OutputSectionView: View {
    @Binding var settings: JobSettings

    var body: some View {
        Section("Output") {
            Picker("Format", selection: $settings.outputFormat) {
                ForEach(OutputFormat.allCases) { fmt in
                    Text(fmt.displayName).tag(fmt)
                }
            }

            HStack {
                if let dir = settings.outputDirectory {
                    Text(dir).lineLimit(1).truncationMode(.head)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Same as source").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK {
                        settings.outputDirectory = panel.url?.path
                    }
                }
                if settings.outputDirectory != nil {
                    Button("Clear") { settings.outputDirectory = nil }
                        .foregroundStyle(.red)
                }
            }
            .accessibilityLabel("Output Directory")

            Picker("Filename", selection: $settings.filenameTemplate) {
                ForEach(FilenameTemplate.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }

            if settings.filenameTemplate == .custom {
                TextField("Template", text: $settings.customFilenameTemplate)
                    .font(.system(.body, design: .monospaced))
                Text("Use {name} for source filename (no extension), {date} for today's date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Strip all metadata", isOn: $settings.stripAllMetadata)
        }
    }
}
