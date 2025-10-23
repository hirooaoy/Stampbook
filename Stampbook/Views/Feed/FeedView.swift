import SwiftUI
import AuthenticationServices

struct FeedView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedTab: Int
    @State private var showNotifications = false
    @State private var showFeedMenu = false
    @State private var selectedFeedTab: FeedTab = .all
    
    enum FeedTab: String, CaseIterable {
        case all = "All"
        case onlyYou = "Only You"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top bar with logo and icons (only when signed in)
                if authManager.isSignedIn {
                    HStack {
                        // Logo on the left (app icon)
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                        
                    Spacer()
                        
                        // Search, notification, and ellipses on the right
                        HStack(spacing: 16) {
                            Button(action: {
                                // TODO: Implement search functionality
                            }) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 24))
                                    .foregroundColor(.primary)
                            }
                            
                            Button(action: {
                                showNotifications = true
                            }) {
                                Image(systemName: "bell")
                                    .font(.system(size: 24))
                                    .foregroundColor(.primary)
                            }
                            
                            Button(action: {
                                showFeedMenu = true
                            }) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 24))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
                
                // Scrollable content
                ScrollView {
                    VStack(spacing: 0) {
                        // Sign-in prompt (only when signed out)
                        if !authManager.isSignedIn {
                            VStack(spacing: 24) {
                                Spacer()
                                    .frame(height: 60)
                                
                                // App logo
                                Image("AppLogo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 80, height: 80)
                                    .cornerRadius(16)
                                
                                VStack(spacing: 12) {
                                    Text("Welcome to Stampbook")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                    
                                    Text("Sign in to start your stamp collection and follow your friends.")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 32)
                                }
                                
                                // Native Sign In with Apple button
                                Button(action: {
                                    authManager.signInWithApple()
                                }) {
                                    SignInWithAppleButton(.signIn) { _ in }
                                        onCompletion: { _ in }
                                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                                        .frame(height: 50)
                                        .cornerRadius(8)
                                        .allowsHitTesting(false)
                                }
                                .padding(.horizontal, 32)
                                .padding(.top, 8)
                                .padding(.bottom, 40)
                            }
                        } else {
                            // Signed in - show segmented control and content
                            VStack(spacing: 0) {
                                // Segmented control
                                Picker("Feed Type", selection: $selectedFeedTab) {
                                    ForEach(FeedTab.allCases, id: \.self) { tab in
                                        Text(tab.rawValue)
                                            .font(.system(size: 24, weight: .medium))
                                            .tag(tab)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .controlSize(.large)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .padding(.bottom, 20)
                                
                                // Content based on selected tab
                                if selectedFeedTab == .all {
                                    AllFeedContent(selectedTab: $selectedTab)
                                } else {
                                    OnlyYouContent(selectedTab: $selectedTab)
                                }
                            }
                        }
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
                .alert("Notifications", isPresented: $showNotifications) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("No new notifications")
                }
                .alert("Feed Options", isPresented: $showFeedMenu) {
                    Button("Settings") {
                        // TODO: Implement feed settings
                    }
                    
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
    }
    
    struct AllFeedContent: View {
        @Binding var selectedTab: Int
        @EnvironmentObject var stampsManager: StampsManager
        @EnvironmentObject var authManager: AuthManager
        
        // Struct to hold post data
        private struct FeedPost: Identifiable {
            let id: String
            let userName: String
            let stampName: String
            let location: String
            let date: String
            let actualDate: Date
            let isCurrentUser: Bool
            let stamp: Stamp
            let userPhotos: [String]
            let note: String?
            let likeCount: Int
            let commentCount: Int
        }
        
        // Computed property to get all posts (user + mock posts)
        private var allPosts: [FeedPost] {
            var posts: [FeedPost] = []
            
            // Add user's collected stamps
            let userPosts = stampsManager.userCollection.collectedStamps.compactMap { collectedStamp -> FeedPost? in
                guard let stamp = stampsManager.stamps.first(where: { $0.id == collectedStamp.stampId }) else {
                    return nil
                }
                return FeedPost(
                    id: "user-\(collectedStamp.stampId)",
                    userName: "Hiroo", // TODO: Replace with actual user name from auth
                    stampName: stamp.name,
                    location: stamp.cityCountry,
                    date: formatDate(collectedStamp.collectedDate),
                    actualDate: collectedStamp.collectedDate,
                    isCurrentUser: true,
                    stamp: stamp,
                    userPhotos: collectedStamp.userImageNames,
                    note: collectedStamp.userNotes.isEmpty ? nil : collectedStamp.userNotes,
                    likeCount: 0, // TODO: Add social features
                    commentCount: 0
                )
            }
            posts.append(contentsOf: userPosts)
            
            // Add mock posts from other users (TODO: Replace with backend data)
            if let ferryBuilding = stampsManager.stamps.first(where: { $0.id == "us-ca-sf-ferry-building" }) {
                posts.append(FeedPost(
                    id: "john-ferry",
                    userName: "John",
                    stampName: ferryBuilding.name,
                    location: ferryBuilding.cityCountry,
                    date: "Oct 20, 2025",
                    actualDate: dateFromString("Oct 20, 2025") ?? Date(),
                    isCurrentUser: false,
                    stamp: ferryBuilding,
                    userPhotos: [],
                    note: "I love the vibes in there. What a great market!",
                    likeCount: 24,
                    commentCount: 7
                ))
            }
            
            if let doloresPark = stampsManager.stamps.first(where: { $0.id == "us-ca-sf-dolores-park" }) {
                posts.append(FeedPost(
                    id: "sarah-dolores",
                    userName: "Sarah",
                    stampName: doloresPark.name,
                    location: doloresPark.cityCountry,
                    date: "Oct 19, 2025",
                    actualDate: dateFromString("Oct 19, 2025") ?? Date(),
                    isCurrentUser: false,
                    stamp: doloresPark,
                    userPhotos: [],
                    note: nil,
                    likeCount: 8,
                    commentCount: 2
                ))
            }
            
            // Sort by date (most recent first)
            return posts.sorted { $0.actualDate > $1.actualDate }
        }
        
        var body: some View {
            VStack(spacing: 20) {
                if !authManager.isSignedIn || allPosts.isEmpty {
                    // Empty state (when signed out or no posts)
                    VStack(spacing: 16) {
                        Image(systemName: "newspaper")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No posts yet")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("Follow others or collect stamps to see activity")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 80)
                } else {
                    ForEach(Array(allPosts.enumerated()), id: \.element.id) { index, post in
                        PostView(
                            userName: post.userName,
                            stampName: post.stampName,
                            location: post.location,
                            date: post.date,
                            isCurrentUser: post.isCurrentUser,
                            stamp: post.stamp,
                            userPhotos: post.userPhotos,
                            note: post.note,
                            likeCount: post.likeCount,
                            commentCount: post.commentCount,
                            selectedTab: $selectedTab
                        )
                        
                        if index < allPosts.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        
        private func formatDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: date)
        }
        
        private func dateFromString(_ dateString: String) -> Date? {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.date(from: dateString)
        }
    }
    
    struct OnlyYouContent: View {
        @Binding var selectedTab: Int
        @EnvironmentObject var stampsManager: StampsManager
        @EnvironmentObject var authManager: AuthManager
        
        // Computed property to get user's collected stamps with their data
        private var userCollectedPosts: [(stamp: Stamp, collectedStamp: CollectedStamp)] {
            stampsManager.userCollection.collectedStamps
                .compactMap { collectedStamp in
                    guard let stamp = stampsManager.stamps.first(where: { $0.id == collectedStamp.stampId }) else {
                        return nil
                    }
                    return (stamp: stamp, collectedStamp: collectedStamp)
                }
                .sorted { $0.collectedStamp.collectedDate > $1.collectedStamp.collectedDate } // Most recent first
        }
        
        var body: some View {
            VStack(spacing: 20) {
                if !authManager.isSignedIn || userCollectedPosts.isEmpty {
                    // Empty state (when signed out or no stamps)
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No stamps collected yet")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("Start exploring to collect your first stamp!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 80)
                } else {
                    // Show collected stamps as posts
                    ForEach(Array(userCollectedPosts.enumerated()), id: \.element.stamp.id) { index, post in
                        PostView(
                            userName: "Hiroo", // TODO: Replace with actual user name from auth
                            stampName: post.stamp.name,
                            location: post.stamp.cityCountry,
                            date: formatDate(post.collectedStamp.collectedDate),
                            isCurrentUser: true,
                            stamp: post.stamp,
                            userPhotos: post.collectedStamp.userImageNames,
                            note: post.collectedStamp.userNotes.isEmpty ? nil : post.collectedStamp.userNotes,
                            likeCount: 0, // TODO: Add social features
                            commentCount: 0, // TODO: Add social features
                            selectedTab: $selectedTab
                        )
                        
                        if index < userCollectedPosts.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        
        private func formatDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: date)
        }
    }
    
    struct PostView: View {
        let userName: String
        let stampName: String
        let location: String
        let date: String
        let isCurrentUser: Bool // true if this is the current user's post
        let stamp: Stamp // The actual stamp object
        let userPhotos: [String] // Additional user photos (can be empty)
        let note: String? // Optional note
        let likeCount: Int
        let commentCount: Int
        @Binding var selectedTab: Int
        @State private var isLiked: Bool = false
        @State private var navigateToStampDetail: Bool = false
        @State private var showNotesEditor: Bool = false
        @State private var editingNotes: String = ""
        @EnvironmentObject var stampsManager: StampsManager
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    if isCurrentUser {
                        // Current user - tapping should switch to Stamps tab
                        Button(action: {
                            selectedTab = 2
                        }) {
                            profilePicture
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        // Other user - navigate to their profile
                        NavigationLink(destination: UserProfileView(username: userName, displayName: userName)) {
                            profilePicture
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Text content on the right (top-aligned)
                    VStack(alignment: .leading, spacing: 4) {
                        // First line: "Hiroo collected Golden Gate Park" - wraps naturally
                        ZStack(alignment: .topLeading) {
                            // Visible text that wraps naturally
                            Text("\(Text(userName).fontWeight(.bold)) collected \(Text(stampName).fontWeight(.bold))")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            // Invisible clickable overlay
                            HStack(alignment: .top, spacing: 0) {
                                // User name button
                                Button(action: {
                                    if isCurrentUser {
                                        selectedTab = 2
                                    }
                                }) {
                                    Text(userName)
                                        .font(.body)
                                        .fontWeight(.bold)
                                        .opacity(0.001)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Text(" collected ")
                                    .font(.body)
                                    .opacity(0.001)
                                
                                // Stamp name button
                                Button(action: {
                                    navigateToStampDetail = true
                                }) {
                                    Text(stampName)
                                        .font(.body)
                                        .fontWeight(.bold)
                                        .opacity(0.001)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Spacer(minLength: 0)
                            }
                        }
                        
                        // Second line: Location
                        Text(location)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Third line: Date
                        Text(date)
                    .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                // Photos section - stamp + user photos
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // First photo: Stamp (tappable)
                        Button(action: {
                            navigateToStampDetail = true
                        }) {
                            Image(stamp.imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipped()
                                .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Show user photos first (if any)
                        ForEach(userPhotos, id: \.self) { photoName in
                            Image(photoName)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipped()
                                .cornerRadius(12)
                        }
                        
                        // Add button at the end for current user
                        if isCurrentUser {
                            Button(action: {
                                // TODO: Add photo action
                            }) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .font(.system(size: 24))
                                            .foregroundColor(.gray)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                // Note section
                if let note = note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if isCurrentUser {
                    // Add Notes button (only for current user)
                    Button(action: {
                        editingNotes = ""
                        showNotesEditor = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "note.text")
                                .font(.body)
                                .foregroundColor(.primary)
                            Text("Add Notes")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Like and Comment row
                HStack(spacing: 16) {
                    // Like button
                    Button(action: {
                        isLiked.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 18))
                                .foregroundColor(isLiked ? .red : .primary)
                            
                            Text("\(isLiked ? likeCount + 1 : likeCount)")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Comment (non-interactive for now)
                    HStack(spacing: 4) {
                        Image(systemName: "message")
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                        
                        Text("\(commentCount)")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                }
            }
            .padding(.vertical, 8)
            .navigationDestination(isPresented: $navigateToStampDetail) {
                StampDetailView(
                    stamp: stamp,
                    userLocation: nil,
                    showBackButton: true
                )
            }
            .sheet(isPresented: $showNotesEditor) {
                NotesEditorView(notes: $editingNotes) { savedNotes in
                    stampsManager.userCollection.updateNotes(for: stamp.id, notes: savedNotes)
                }
            }
        }
        
        private var profilePicture: some View {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                )
        }
        
        private func buildCollectionText() -> AttributedString {
            var result = AttributedString()
            
            // Bold user name
            var userNameAttr = AttributedString(userName)
            userNameAttr.font = .body.bold()
            result += userNameAttr
            
            // Regular "collected"
            result += AttributedString(" collected ")
            
            // Bold stamp name (make it interactive-looking)
            var stampNameAttr = AttributedString(stampName)
            stampNameAttr.font = .body.bold()
            result += stampNameAttr
            
            return result
        }
        
        private func buildCollectionTextButton() -> some View {
            Button(action: {
                navigateToStampDetail = true
            }) {
                Text(buildCollectionText())
                    .font(.body)
                    .foregroundColor(.primary)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

