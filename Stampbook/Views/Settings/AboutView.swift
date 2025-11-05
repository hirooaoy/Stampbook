import SwiftUI

/// About Stampbook view - Philosophy and mission
struct AboutStampbookView: View {
    @Environment(\.dismiss) private var dismiss
    
    // ✏️ EDIT YOUR CONTENT HERE - Simple and clean!
    
    // Main content paragraphs (supports **bold** markdown!)
    private let contentParagraphs = [
        "Hello friends,",
        "Thank you so much for being here.",
        "",  // Extra spacing
        "Stampbook was inspired by **Eki Stamps**. In Japan, you can find physical stamps at train stations (\"Eki\" in Japanese) and collect them as you travel. Each one is unique, celebrating the station's history and character. I love the feeling of collecting stamps and remembering the places I've traveled to.",
        "",  // Extra spacing
        "I want to bring that same feeling here. I'm not here to grab your screen time. I want you out there exploring. Find stamps while you're traveling, hiking a trail, trying a new restaurant, or visiting a museum. Collect them as memories of where you've been and share them with your friends.",
        "",  // Extra spacing
        "I'm always open to feedback. Let's co-create this together.",
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Logo
                    HStack {
                        Spacer()
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .cornerRadius(16)
                        Spacer()
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 20)
                    
                    // Philosophy
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(contentParagraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(.init(paragraph))  // Supports markdown like **bold**
                                .font(.system(size: 17))
                                .lineSpacing(6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("About Stampbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// For Local Business view - Partnership information
struct ForLocalBusinessView: View {
    @Environment(\.dismiss) private var dismiss
    
    // ✏️ Edit your content here
    private let contentParagraphs = [
        "Have a café, shop, or local spot people love?",
        "",
        "You can create your own digital stamp that explorers collect when they visit.",
        "",
        "Every partner gets to write their own \"About\" story, and you'll work directly with me to design a stamp that captures your vibe.",
        "",
        "We're still early and small — I'm a solo developer building this idea and growing the community one place at a time.",
        "",
        "If you like the vision, I'd love to collaborate with you.",
        "",
        "💰 **Offer: $25 for a 6-month listing**",
        "(Early partner spots only)",
        "",
        "Contact: **partner@stampbook.app**"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Logo
                    HStack {
                        Spacer()
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .cornerRadius(16)
                        Spacer()
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 20)
                    
                    // Content
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(contentParagraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(.init(paragraph))  // Supports markdown like **bold**
                                .font(.system(size: 17))
                                .lineSpacing(6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("For local business")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// For Creators view - Creator collaboration information
struct ForCreatorsView: View {
    @Environment(\.dismiss) private var dismiss
    
    // ✏️ Edit your content here
    private let contentParagraphs = [
        "Know amazing places that should be stamps?",
        "",
        "I'm looking for passionate locals who want to help curate experiences in their city.",
        "",
        "**As a Creator, you'll:**",
        "• Suggest new stamp locations",
        "• Write compelling descriptions",
        "• Share insider tips and recommendations",
        "• Get credited on the stamps you create",
        "",
        "**This is perfect for:**",
        "📍 Local guides and tour leaders",
        "✈️ Travel bloggers",
        "🎨 People who love their city",
        "🗺️ Community builders",
        "",
        "We're still small and scrappy. You'd be working directly with me to shape how people discover your city.",
        "",
        "Contact: **hello@stampbook.app**"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Logo
                    HStack {
                        Spacer()
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .cornerRadius(16)
                        Spacer()
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 20)
                    
                    // Content
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(contentParagraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(.init(paragraph))  // Supports markdown like **bold**
                                .font(.system(size: 17))
                                .lineSpacing(6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("For creators")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview("About Stampbook") {
    AboutStampbookView()
}

#Preview("For Local Business") {
    ForLocalBusinessView()
}

#Preview("For Creators") {
    ForCreatorsView()
}

