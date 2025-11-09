import SwiftUI

/// Reusable form component for entering stamp details (Google Map link and description)
/// Used in both single stamp and collection suggestion views
struct StampSuggestionFormField: View {
    let stampNumber: String? // e.g., "1" for "Stamp 1", nil for single stamp
    @Binding var googleMapLink: String
    @Binding var description: String
    let showFooter: Bool // Whether to show helper text
    
    init(stampNumber: String? = nil, googleMapLink: Binding<String>, description: Binding<String>, showFooter: Bool = true) {
        self.stampNumber = stampNumber
        self._googleMapLink = googleMapLink
        self._description = description
        self.showFooter = showFooter
    }
    
    var body: some View {
        Group {
            if let number = stampNumber {
                // Collection view: All fields in one section with spacing
                Section {
                    TextField("http://...", text: $googleMapLink)
                    
                    TextField("The stamp should include the golden gate bridge", text: $description, axis: .vertical)
                        .lineLimit(5...10)
                        .padding(.top, 16)
                } header: {
                    Text("Stamp \(number)")
                } footer: {
                    if showFooter {
                        Text("Tell us about this place and what details we should include")
                    }
                }
            } else {
                // Single stamp view: Separate sections
                Section {
                    TextField("http://...", text: $googleMapLink)
                } header: {
                    Text("Google Map Link")
                }
                
                Section {
                    TextField("The stamp should include the golden gate bridge", text: $description, axis: .vertical)
                        .lineLimit(5...10)
                } header: {
                    Text("Description")
                } footer: {
                    Text("Tell us about this place and what details we should include")
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
                googleMapLink: .constant(""),
                description: .constant("")
            )
        }
    }
}
