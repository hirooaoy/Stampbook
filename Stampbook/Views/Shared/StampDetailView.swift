import SwiftUI
import MapKit
import Contacts
import AuthenticationServices

struct StampDetailView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var authManager: AuthManager
    let stamp: Stamp
    let userLocation: CLLocation?
    let showBackButton: Bool
    @State private var showMapOptions = false
    @State private var showMemorySection = false
    @State private var showNotesEditor = false
    @State private var editingNotes = ""
    
    private var isCollected: Bool {
        stampsManager.isCollected(stamp)
    }
    
    private var isWithinRange: Bool {
        guard let userLocation = userLocation else { return false }
        let stampLocation = CLLocation(latitude: stamp.coordinate.latitude, longitude: stamp.coordinate.longitude)
        let distance = userLocation.distance(from: stampLocation)
        return distance <= MapView.stampCollectionRadius
    }
    
    private var collectedDate: Date? {
        stampsManager.userCollection.collectedStamps
            .first(where: { $0.stampId == stamp.id })?.collectedDate
    }
    
    private var userNotes: String {
        stampsManager.userCollection.collectedStamps
            .first(where: { $0.stampId == stamp.id })?.userNotes ?? ""
    }
    
    private var formattedShortDate: String {
        guard let date = collectedDate else { return "" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
    
    private var formattedYear: String {
        guard let date = collectedDate else { return "" }
        return date.formatted(.dateTime.year())
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // Stamp name and collection count
                    VStack(spacing: 6) {
                        Text(stamp.name)
                            .font(.system(size: 28, weight: .bold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        // TODO: Replace with real collection count from backend
                        Text(isCollected ? "14 people have this stamp" : "13 people have this stamp")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    
                    // Centered square stamp image with lock icon
                    ZStack {
                        if isCollected {
                            // Show stamp image when collected
                            Image(stamp.imageName)
                                .resizable()
                                .renderingMode(.original)
                                .scaledToFit()
                                .frame(width: 240, height: 240)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            // Show lock icon when not collected
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 240, height: 240)
                            
                            Image(systemName: "lock.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.gray)
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 1.0), value: isCollected)
                    .padding(.bottom, 36)
                    
                    // Memory section - only visible after collection
                    if isCollected && showMemorySection {
                        VStack(alignment: .leading, spacing: 0) {
                            // Memory heading
                            Text("Memory")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 8)
                            
                            // Rank and date cards
                            HStack(spacing: 12) {
                                // Rank card
                                HStack(spacing: 12) {
                                    Image(systemName: "number")
                                        .font(.system(size: 24))
                                        .foregroundColor(.purple)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Number")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("14")
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
                                .frame(maxWidth: .infinity)
                                .frame(height: 70)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                                
                                // Date card
                                HStack(spacing: 12) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 24))
                                        .foregroundColor(.red)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(formattedYear)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(formattedShortDate)
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
                                .frame(maxWidth: .infinity)
                                .frame(height: 70)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .padding(.bottom, 16)
                            
                            // Add photos button
                            Button(action: {
                                // TODO: Implement add photo
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "photo")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .frame(width: 20, height: 20, alignment: .center)
                                    Text("Add Photos")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Spacer(minLength: 6)
                                    Image(systemName: "chevron.right")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.bottom, 16)
                            
                            // Add notes button
                            Button(action: {
                                editingNotes = userNotes
                                showNotesEditor = true
                            }) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "note.text")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .frame(width: 20, height: 20, alignment: .center)
                                    
                                    if userNotes.isEmpty {
                                        Text("Add Notes")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        Text(userNotes)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    
                                    Spacer(minLength: 6)
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    // Divider
                    if isCollected && showMemorySection {
                        Divider()
                            .padding(.horizontal, 24)
                            .padding(.bottom, 36)
                    }
                    
                    // About section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text(stamp.about)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                    
                    // Divider
                    Divider()
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                    
                    // Location section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Location")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                showMapOptions = true
                            }) {
                                Text(stamp.address)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                showMapOptions = true
                            }) {
                                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                    
                    // Divider
                    Divider()
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                    
                    // Notes from others section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Notes from others")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(stamp.notesFromOthers, id: \.self) { note in
                                HStack(alignment: .center, spacing: 12) {
                                    // Profile thumbnail
                                    Circle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 18))
                                                .foregroundColor(.gray)
                                        )
                                    
                                    // Note text
                                    Text(note)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        
                        // See all button
                        Button(action: {
                            // TODO: Implement see all notes
                        }) {
                            Text("See all")
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                    
                    // Collections section - only show if stamp belongs to at least one collection
                    let stampCollections = stampsManager.collections.filter { collection in
                        stamp.collectionIds.contains(collection.id)
                    }
                    
                    if !stampCollections.isEmpty {
                        // Divider
                        Divider()
                            .padding(.horizontal, 24)
                            .padding(.bottom, 36)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Collections")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            ForEach(stampCollections) { collection in
                                NavigationLink(destination: CollectionDetailView(collection: collection)) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(collection.name)
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                        
                                        let collectedCount = stampsManager.collectedStampsInCollection(collection.id)
                                        let totalCount = stampsManager.stampsInCollection(collection.id).count
                                        Text("\(collectedCount) out of \(totalCount) stamp\(totalCount == 1 ? "" : "s") collected")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 32)
                                    .padding(.horizontal, 20)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 48)
                .animation(.spring(response: 0.4, dampingFraction: 1.0), value: isCollected)
            }
            
            // Sticky button at bottom
            VStack(spacing: 0) {
                Divider()
                
                if !authManager.isSignedIn {
                    // Not signed in - show text and native Sign In with Apple button
                    VStack(spacing: 16) {
                        Text("Want to start collecting?")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Button(action: {
                            authManager.signInWithApple()
                        }) {
                            SignInWithAppleButton(.signIn) { _ in }
                                onCompletion: { _ in }
                                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                                .frame(height: 50)
                                .cornerRadius(12)
                                .allowsHitTesting(false) // Disable built-in handler
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                } else if !isCollected {
                    Button(action: {
                        if isWithinRange, let userId = authManager.userId {
                            stampsManager.collectStamp(stamp, userId: userId)
                        }
                    }) {
                        Text(isWithinRange ? "Collect Stamp" : "You are too far")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(isWithinRange ? Color.blue : Color.clear)
                            .foregroundColor(isWithinRange ? .white : .secondary)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    .opacity(isWithinRange ? 0 : 1)
                            )
                    }
                    .disabled(!isWithinRange)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                } else {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("Collected")
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                }
            }
        }
        .toolbar {
            if !showBackButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Show Memory section immediately if stamp is already collected
            if isCollected {
                showMemorySection = true
            }
        }
        .onChange(of: isCollected) { _, newValue in
            if newValue {
                withAnimation(.spring(response: 0.4, dampingFraction: 1.0)) {
                    showMemorySection = true
                }
            } else {
                showMemorySection = false
            }
        }
        .fullScreenCover(isPresented: $showNotesEditor) {
            NotesEditorView(notes: $editingNotes) { savedNotes in
                stampsManager.userCollection.updateNotes(for: stamp.id, notes: savedNotes)
            }
        }
        .sheet(isPresented: $showMapOptions) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    // Google Maps button
                    Button(action: {
                        showMapOptions = false
                        openInGoogleMaps()
                    }) {
                        Text("Open in Google Maps")
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                    
                    // Apple Maps button
                    Button(action: {
                        showMapOptions = false
                        openInAppleMaps()
                    }) {
                        Text("Open in Apple Maps")
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                    
                    // Copy address button
                    Button(action: {
                        UIPasteboard.general.string = stamp.address
                        showMapOptions = false
                    }) {
                        Text("Copy address")
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                    
                    // Cancel button (no background)
                    Button(action: {
                        showMapOptions = false
                    }) {
                        Text("Cancel")
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 32)
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
        }
    }
    
    private func openInAppleMaps() {
        let location = CLLocation(latitude: stamp.coordinate.latitude, longitude: stamp.coordinate.longitude)
        
        // Create MKMapItem with location and name
        let mapItem = MKMapItem(location: location, address: nil)
        mapItem.name = stamp.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
    
    private func openInGoogleMaps() {
        // Use place name in query for better recognition
        let placeName = stamp.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let address = stamp.address.replacingOccurrences(of: "\n", with: ",").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // Try with place name and address as query, with coordinates as fallback
        let googleMapsURL = URL(string: "comgooglemaps://?q=\(placeName),\(address)&directionsmode=walking")!
        let googleMapsWebURL = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(placeName),\(address)&travelmode=walking")!
        
        if UIApplication.shared.canOpenURL(googleMapsURL) {
            UIApplication.shared.open(googleMapsURL)
        } else {
            // Fallback to web version if Google Maps app not installed
            UIApplication.shared.open(googleMapsWebURL)
        }
    }
}

#Preview {
    StampDetailView(
        stamp: Stamp(
            id: "us-ca-sf-baker-beach",
            name: "Baker Beach",
            latitude: 37.7937,
            longitude: -122.4844,
            address: "1504 Pershing Dr\nSan Francisco, CA, USA 94129",
            imageName: "us-ca-sf-baker-beach",
            collectionIds: ["sf-must-visits"],
            about: "Baker Beach is a public beach on the peninsula of San Francisco, California. The beach lies on the shore of the Pacific Ocean in the northwest of the city, with stunning views of the Golden Gate Bridge.",
            notesFromOthers: [
                "Great spot for photos of the Golden Gate Bridge!",
                "Battery Chamberlin trail gives amazing panoramic views",
                "Sunset here is absolutely stunning"
            ]
        ),
        userLocation: nil,
        showBackButton: false
    )
    .environmentObject(StampsManager())
}

