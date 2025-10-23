import SwiftUI

struct FollowListView: View {
    @State private var selectedTab: FollowTab
    @State private var searchText = ""
    
    init(initialTab: FollowTab = .followers) {
        _selectedTab = State(initialValue: initialTab)
    }
    
    enum FollowTab: String, CaseIterable {
        case followers = "10 Followers"
        case following = "15 Following"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Native segmented control
            Picker("View", selection: $selectedTab) {
                ForEach(FollowTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue)
                        .font(.system(size: 24, weight: .medium))
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            
            // List of users
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(0..<20, id: \.self) { index in
                        NavigationLink(destination: UserProfileView(username: "username", displayName: "User Name")) {
                            UserRow()
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Hiroo")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct UserRow: View {
    @State private var isFollowing = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile picture
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.gray)
                )
            
            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text("User Name")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("@username")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Follow button
            Button(action: {
                isFollowing.toggle()
            }) {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(isFollowing ? .primary : .white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(isFollowing ? Color(.systemGray5) : Color.blue)
                    .cornerRadius(8)
            }
        }
    }
}

#Preview {
    NavigationStack {
        FollowListView()
    }
}

