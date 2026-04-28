import SwiftUI

struct GeneralMetadataSectionView: View {
    @Binding var settings: JobSettings
    @State private var newCustomKey   = ""
    @State private var newCustomValue = ""

    var body: some View {
        Section("General Metadata") {
            MetadataField("Title",       value: $settings.generalMetadata.title)
            MetadataField("Comment",     value: $settings.generalMetadata.comment)
            MetadataField("Description", value: $settings.generalMetadata.description)
            MetadataField("Copyright",   value: $settings.generalMetadata.copyright)
            MetadataField("Artist",      value: $settings.generalMetadata.artist)
            MetadataField("Album",       value: $settings.generalMetadata.album)
            MetadataField("Date",        value: $settings.generalMetadata.date,   placeholder: "YYYY-MM-DD")
            MetadataField("Genre",       value: $settings.generalMetadata.genre)
            MetadataField("Encoder",     value: $settings.generalMetadata.encoder)
        }

        Section {
            ForEach(settings.generalMetadata.customPairs.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                HStack {
                    Text(kv.key)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 130, alignment: .trailing)
                    Text(kv.value)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(role: .destructive) {
                        settings.generalMetadata.customPairs.removeValue(forKey: kv.key)
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                TextField("key", text: $newCustomKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: 140)
                TextField("value", text: $newCustomValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                Button {
                    let k = newCustomKey.trimmingCharacters(in: .whitespaces)
                    let v = newCustomValue.trimmingCharacters(in: .whitespaces)
                    guard !k.isEmpty, !v.isEmpty else { return }
                    settings.generalMetadata.customPairs[k] = v
                    newCustomKey   = ""
                    newCustomValue = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .disabled(newCustomKey.isEmpty || newCustomValue.isEmpty)
            }
        } header: {
            Text("Custom Key/Value Pairs")
        } footer: {
            Text("Arbitrary -metadata key=value pairs passed directly to FFmpeg.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct MetadataField: View {
    let label: String
    @Binding var value: String?
    var placeholder: String = ""

    init(_ label: String, value: Binding<String?>, placeholder: String = "") {
        self.label = label
        self._value = value
        self.placeholder = placeholder.isEmpty ? label : placeholder
    }

    var body: some View {
        LabeledContent(label) {
            TextField(placeholder, text: Binding(
                get: { value ?? "" },
                set: { value = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
        }
    }
}
