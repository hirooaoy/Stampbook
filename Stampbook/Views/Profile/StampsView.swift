import SwiftUI
import AuthenticationServices

struct StampsView: View {
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: StampTab = .all
    @State private var showProfileMenu = false
    
    enum StampTab: String, CaseIterable {
        case all = "All"
        case collections = "Collections"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    if authManager.isSignedIn {
                        // Signed-in: Show username
                        Text("@hirooaoy")
                            .font(.headline)
                            .fontWeight(.semibold)
                    } else {
                        // Signed-out: Show app logo
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                    }
                    
                    Spacer()
                    
                    if authManager.isSignedIn {
                        // Signed-in menu
                        HStack(spacing: 16) {
                            Button(action: {
                                // TODO: Implement edit profile
                            }) {
                                Image(systemName: "pencil.circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(.primary)
                            }
                            
                            Button(action: {
                                showProfileMenu = true
                            }) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 24))
                                    .foregroundColor(.primary)
                                    .frame(width: 44, height: 44)  // Larger tap target
                                    .contentShape(Rectangle())     // Make entire frame tappable
                            }
                        }
                    } else {
                        // Signed-out menu: Just ellipsis with Menu
                        Menu {
                            Button(action: {
                                // TODO: Open privacy policy
                                print("Privacy Policy tapped")
                            }) {
                                Label("Privacy Policy", systemImage: "hand.raised")
                            }
                            
                            Divider()
                            
                            Button(action: {
                                // TODO: Open business info
                                print("For Local Business tapped")
                            }) {
                                Label("For Local Business", systemImage: "storefront")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 24))
                                .foregroundColor(.primary)
                                .frame(width: 44, height: 44)  // Larger tap target
                                .contentShape(Rectangle())     // Make entire frame tappable
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)
                
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
                                    
                                    Text("Sign in to start your stamp collection and create your own stampbook")
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
                        }
                        
                        // Profile section (only when signed in)
                        if authManager.isSignedIn {
                        HStack(spacing: 12) {
                            // Profile picture
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 64, height: 64)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.gray)
                                )
                            
                            // Name and bio
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hiroo")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                
                                Text("I love traveling and taking pictures around the world")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                        
                        // Stats cards - horizontal scrollable
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                // Rank card
                                HStack(spacing: 12) {
                                    Image(systemName: "trophy.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.orange)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Rank")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("#1852")
                                            .font(.body)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .frame(width: 160)
                                .frame(height: 70)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                                
                                // Countries card
                                HStack(spacing: 12) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 24))
                                        .foregroundColor(.blue)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Countries")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("1")
                                            .font(.body)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .frame(width: 160)
                                .frame(height: 70)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                                
                                // Followers card
                                NavigationLink(destination: FollowListView(initialTab: .followers)) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "person.2.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(.green)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Followers")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("10")
                                                .font(.body)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.5)
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .frame(width: 160)
                                    .frame(height: 70)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                // Following card
                                NavigationLink(destination: FollowListView(initialTab: .following)) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "person.fill.checkmark")
                                            .font(.system(size: 24))
                                            .foregroundColor(.purple)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Following")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("15")
                                                .font(.body)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.5)
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .frame(width: 160)
                                    .frame(height: 70)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 20)
                        }
                        
                        // Native segmented control (only when signed in)
                        if authManager.isSignedIn {
                            Picker("View", selection: $selectedTab) {
                                ForEach(StampTab.allCases, id: \.self) { tab in
                                    Text(tab.rawValue)
                                        .font(.system(size: 24, weight: .medium))
                                        .tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.large)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                            
                            // Content based on selected tab
                            if selectedTab == .all {
                                AllStampsContent()
                            } else {
                                CollectionsContent()
                            }
                        }
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
                .alert("Developer Options", isPresented: $showProfileMenu) {
                    Button("Collect All") {
                        if let userId = authManager.userId {
                            stampsManager.obtainAll(userId: userId)
                        }
                    }
                    
                    Button("Collect Half") {
                        if let userId = authManager.userId {
                            stampsManager.obtainHalf(userId: userId)
                        }
                    }
                    
                    Button("Reset All", role: .destructive) {
                        stampsManager.resetAll()
                    }
                    
                    Button("Sign Out", role: .destructive) {
                        authManager.signOut()
                    }
                    
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
    }
    
    struct AllStampsContent: View {
        @EnvironmentObject var stampsManager: StampsManager
        @State private var displayedCount = 20 // Initial load
        
        private let columns = [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ]
        
        // Get collected stamps sorted by date (latest first)
        private var sortedCollectedStamps: [(stamp: Stamp, collectedDate: Date)] {
            let collectedStamps = stampsManager.userCollection.collectedStamps
                .sorted { $0.collectedDate > $1.collectedDate } // Latest first
            
            return collectedStamps.compactMap { collected in
                if let stamp = stampsManager.stamps.first(where: { $0.id == collected.stampId }) {
                    return (stamp, collected.collectedDate)
                }
                return nil
            }
        }
        
        // Get stamps to display (paginated)
        private var displayedStamps: [(stamp: Stamp, collectedDate: Date)] {
            Array(sortedCollectedStamps.prefix(displayedCount))
        }
        
        var body: some View {
            Group {
                if sortedCollectedStamps.isEmpty {
                    // Empty state
                    VStack {
                        Spacer()
                        
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                            .padding(.bottom, 20)
                        
                        Text("All Stamps")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Your stamp collection will appear here")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Spacer()
                    }
                    .frame(height: 300)
                } else {
                    // Grid view
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(Array(displayedStamps.enumerated()), id: \.element.stamp.id) { index, item in
                            NavigationLink(destination:
                                            StampDetailView(
                                                stamp: item.stamp,
                                                userLocation: nil,
                                                showBackButton: true
                                            )
                                                .environmentObject(stampsManager)
                            ) {
                                StampGridItem(stamp: item.stamp)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .onAppear {
                                // Load more when approaching the end
                                if index == displayedStamps.count - 1 && displayedCount < sortedCollectedStamps.count {
                                    loadMoreStamps()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        
        private func loadMoreStamps() {
            // Load 20 more stamps
            let newCount = min(displayedCount + 20, sortedCollectedStamps.count)
            displayedCount = newCount
        }
    }
    
    struct StampGridItem: View {
        let stamp: Stamp
        
        var body: some View {
            VStack(spacing: 12) {
                // Stamp image
                Image(stamp.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Stamp name (centered, fixed height for 2 lines)
                Text(stamp.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .top)
            }
        }
    }
    
    struct CollectionsContent: View {
        @EnvironmentObject var stampsManager: StampsManager
        
        var body: some View {
            VStack(spacing: 20) {
                ForEach(stampsManager.sortedCollections) { collection in
                    NavigationLink(destination: CollectionDetailView(collection: collection)) {
                        let collectedCount = stampsManager.collectedStampsInCollection(collection.id)
                        let totalCount = stampsManager.stampsInCollection(collection.id).count
                        let percentage = totalCount > 0 ? Double(collectedCount) / Double(totalCount) : 0.0
                        
                        CollectionCardView(
                            name: collection.name,
                            collectedCount: collectedCount,
                            totalCount: totalCount,
                            completionPercentage: percentage
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }
}
