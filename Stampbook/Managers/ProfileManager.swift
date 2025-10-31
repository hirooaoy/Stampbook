import Foundation
import Combine

/// Manages user profile state and operations
class ProfileManager: ObservableObject {
    @Published var currentUserProfile: UserProfile?
    @Published var isLoading = false
    @Published var error: String?
    @Published var userRank: Int? // Global rank based on totalStamps
    
    private let firebaseService = FirebaseService.shared
    
    // Rank caching to avoid expensive queries
    private var cachedRanks: [String: (rank: Int, timestamp: Date)] = [:]
    // Extended cache from 5 minutes to 30 minutes to reduce query costs
    private let rankCacheExpiration: TimeInterval = 1800 // 30 minutes
    
    /// Load the current user's profile from Firebase
    /// Rank is loaded lazily in the view when needed
    func loadProfile(userId: String, loadRank: Bool = false) {
        // Prevent duplicate loads
        if isLoading {
            print("⚠️ [ProfileManager] Already loading profile, skipping duplicate request")
            return
        }
        
        isLoading = true
        error = nil
        
        print("🔄 [ProfileManager] Loading profile for userId: \(userId)")
        
        Task {
            do {
                let profile = try await firebaseService.fetchUserProfile(userId: userId)
                await MainActor.run {
                    self.currentUserProfile = profile
                    self.isLoading = false
                }
                print("✅ [ProfileManager] Loaded user profile: \(profile.displayName)")
                
                // Fetch rank only if requested (opt-in for better performance)
                if loadRank {
                    await fetchUserRank(for: profile)
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
                print("❌ [ProfileManager] Failed to load profile: \(error.localizedDescription)")
            }
        }
    }
    
    /// Update the current user's profile
    func updateProfile(_ profile: UserProfile) {
        currentUserProfile = profile
    }
    
    /// Refresh the current user's profile from Firebase
    /// Useful after collecting stamps or other actions that update stats
    func refreshProfile() {
        guard let userId = currentUserProfile?.id else { return }
        loadProfile(userId: userId)
    }
    
    /// Refresh profile data from server (pull-to-refresh)
    func refresh() async {
        guard let userId = currentUserProfile?.id else { return }
        
        do {
            let profile = try await firebaseService.fetchUserProfile(userId: userId)
            await MainActor.run {
                self.currentUserProfile = profile
            }
            
            // Fetch updated rank (only if already had rank loaded)
            if userRank != nil {
                await fetchUserRank(for: profile)
            }
        } catch {
            print("⚠️ Failed to refresh profile: \(error.localizedDescription)")
        }
    }
    
    /// Refresh profile data without rank calculation (faster for pull-to-refresh)
    func refreshWithoutRank() async {
        guard let userId = currentUserProfile?.id else { return }
        
        do {
            let profile = try await firebaseService.fetchUserProfile(userId: userId)
            await MainActor.run {
                self.currentUserProfile = profile
            }
        } catch {
            print("⚠️ Failed to refresh profile: \(error.localizedDescription)")
        }
    }
    
    /// Fetch user's global rank based on total stamps
    /// Called automatically after loading profile
    /// Uses caching to avoid expensive Firestore queries
    func fetchUserRank(for profile: UserProfile) async {
        // Check cache first
        if let cached = cachedRanks[profile.id],
           Date().timeIntervalSince(cached.timestamp) < rankCacheExpiration {
            await MainActor.run {
                self.userRank = cached.rank
            }
            print("✅ Using cached rank for \(profile.displayName): #\(cached.rank)")
            return
        }
        
        do {
            let rank = try await firebaseService.calculateUserRank(
                userId: profile.id,
                totalStamps: profile.totalStamps
            )
            await MainActor.run {
                self.userRank = rank
                // Cache the rank
                self.cachedRanks[profile.id] = (rank: rank, timestamp: Date())
            }
            print("✅ User rank: #\(rank)")
        } catch {
            print("⚠️ Failed to fetch rank: \(error.localizedDescription)")
            // Don't set error - rank is optional/non-critical
        }
    }
    
    /// Clear profile data (on sign out)
    func clearProfile() {
        currentUserProfile = nil
        userRank = nil
        error = nil
        cachedRanks.removeAll()
    }
}

