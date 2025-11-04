import SwiftUI

/// Native sheet view for displaying content pages (local businesses, creators, about)
struct ContentPageView: View {
    let contentPageId: String
    @StateObject private var manager = ContentPageManager()
    @State private var contentPage: ContentPage?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if manager.isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                } else if let page = contentPage {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            // Render sections in order
                            ForEach(page.sections.sorted(by: { $0.order < $1.order })) { section in
                                sectionView(for: section)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 24)
                    }
                    .navigationTitle(page.title)
                    .navigationBarTitleDisplayMode(.inline)
                } else if let error = manager.error {
                    ContentUnavailableView {
                        Label("Error Loading Content", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error.localizedDescription)
                    } actions: {
                        Button("Try Again") {
                            Task {
                                await loadContent()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Content Not Found", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text("This content is not available.")
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadContent()
        }
    }
    
    // MARK: - Section Rendering
    
    @ViewBuilder
    private func sectionView(for section: ContentSection) -> some View {
        switch section.type {
        case .text:
            if let content = section.content {
                Text(content)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineSpacing(4)
            }
            
        case .image:
            if let imageUrl = section.imageUrl {
                AsyncImage(url: URL(string: imageUrl)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .clipped()
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                    @unknown default:
                        EmptyView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
        case .link:
            if let url = section.linkUrl, let urlObj = URL(string: url) {
                Link(destination: urlObj) {
                    Text(section.linkLabel ?? "Let's Chat")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            
        case .hours:
            if let hoursData = section.hoursData {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Hours")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(daysOfWeek, id: \.self) { day in
                            if let hours = hoursData[day] {
                                HStack {
                                    Text(day)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .frame(width: 90, alignment: .leading)
                                    Text(hours)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
        case .divider:
            Divider()
                .padding(.vertical, 4)
        }
    }
    
    // MARK: - Helpers
    
    private let daysOfWeek = [
        "Monday", "Tuesday", "Wednesday", "Thursday", 
        "Friday", "Saturday", "Sunday"
    ]
    
    private func loadContent() async {
        contentPage = await manager.fetchContentPage(id: contentPageId)
    }
}

// MARK: - Preview

#Preview {
    ContentPageView(contentPageId: "test-business")
}

