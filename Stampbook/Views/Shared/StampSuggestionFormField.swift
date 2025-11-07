import SwiftUI

/// Reusable form component for entering stamp details (name, address, notes)
/// Used in both single stamp and collection suggestion views
struct StampSuggestionFormField: View {
    let stampNumber: String? // e.g., "1" for "Stamp 1", nil for single stamp
    @Binding var name: String
    @Binding var address: String
    @Binding var notes: String
    let showFooter: Bool // Whether to show helper text
    
    init(stampNumber: String? = nil, name: Binding<String>, address: Binding<String>, notes: Binding<String>, showFooter: Bool = true) {
        self.stampNumber = stampNumber
        self._name = name
        self._address = address
        self._notes = notes
        self.showFooter = showFooter
    }
    
    var body: some View {
        Group {
            if let number = stampNumber {
                // Collection view: All fields in one section with spacing
                Section {
                    TextField("Golden Gate View Point", text: $name)
                    
                    TextField("Old Conzelman Rd, Mill Valley, CA 94941", text: $address)
                        .padding(.top, 16)
                    
                    TextField("Stamp should include the bridge", text: $notes, axis: .vertical)
                        .lineLimit(5...10)
                        .padding(.top, 16)
                } header: {
                    Text("Stamp \(number)")
                } footer: {
                    if showFooter {
                        Text("Copy full address from Google or Apple Maps. Tell us what we should include for the stamp image and things to do.")
                    }
                }
            } else {
                // Single stamp view: Separate sections
                Section {
                    TextField("Golden Gate View Point", text: $name)
                } header: {
                    Text("Stamp Name")
                }
                
                Section {
                    TextField("Old Conzelman Rd, Mill Valley, CA 94941", text: $address)
                } header: {
                    Text("Address")
                } footer: {
                    Text("Copy full address from Google or Apple Maps")
                }
                
                Section {
                    TextField("Stamp should include the bridge", text: $notes, axis: .vertical)
                        .lineLimit(5...10)
                } header: {
                    Text("Additional Notes")
                } footer: {
                    Text("Tell us what we should include for the stamp image and things to do.")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        Form {
            StampSuggestionFormField(
                stampNumber: nil,
                name: .constant(""),
                address: .constant(""),
                notes: .constant("")
            )
        }
    }
}
