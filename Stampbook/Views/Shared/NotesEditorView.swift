import SwiftUI

struct NotesEditorView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var notes: String
    @FocusState private var isTextFieldFocused: Bool
    
    let onSave: (String) -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Text Editor
                TextEditor(text: $notes)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .focused($isTextFieldFocused)
                    .overlay(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("Thoughts to remember and help others")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(notes)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                // Full screen cover = no nested presentation issues
                // Can focus immediately
                isTextFieldFocused = true
            }
            .toolbar(.visible, for: .tabBar)
        }
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    NotesEditorView(notes: .constant(""), onSave: { _ in })
}

