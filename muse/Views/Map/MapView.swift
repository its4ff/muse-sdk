//
//  MapView.swift
//  muse
//
//  Interactive map showing muses as pins with clustering
//  Clusters muses within 75m radius, shows count badge
//

import SwiftUI
import SwiftData
import MapKit
import CoreLocation

// MARK: - Cluster Model

struct MuseCluster: Identifiable {
    let id = UUID()
    let muses: [Muse]
    let coordinate: CLLocationCoordinate2D
    let minClusterSize: Int

    var count: Int { muses.count }
    var isCluster: Bool { muses.count >= minClusterSize }

    // Most recent muse (for single pins)
    var primaryMuse: Muse? { muses.first }
}

struct MapView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Muse.createdAt, order: .reverse) private var allMuses: [Muse]

    // Map state
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedCluster: MuseCluster?
    @State private var showDetail = false

    // Carousel state
    @State private var currentCarouselIndex: Int = 0

    // Clustering settings
    private let clusterRadius: CLLocationDistance = 50  // meters
    private let minClusterSize: Int = 10  // minimum muses to form a cluster

    // Filter to only muses with location
    private var musesWithLocation: [Muse] {
        allMuses.filter { $0.hasLocation }
    }

    // Compute clusters from muses
    private var clusters: [MuseCluster] {
        computeClusters(from: musesWithLocation, radius: clusterRadius)
    }

    // Get muses in selected cluster (sorted by most recent)
    private var clusterMuses: [Muse] {
        guard let cluster = selectedCluster else { return [] }
        return cluster.muses.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ZStack {
            // Map with clusters
            Map(position: $position) {
                ForEach(clusters) { cluster in
                    Annotation("", coordinate: cluster.coordinate) {
                        if cluster.isCluster {
                            // Cluster pin with count
                            ClusterMapPin(
                                count: cluster.count,
                                isSelected: selectedCluster?.id == cluster.id
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    selectedCluster = cluster
                                    showDetail = true
                                    currentCarouselIndex = 0
                                }
                            }
                        } else if let muse = cluster.primaryMuse {
                            // Single muse pin
                            MuseMapPin(
                                muse: muse,
                                isSelected: selectedCluster?.id == cluster.id,
                                isInCarousel: false
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    selectedCluster = cluster
                                    showDetail = true
                                    currentCarouselIndex = 0
                                }
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapUserLocationButton()
            }
            .tint(.white) // Make map controls (location button) white
            .onTapGesture {
                // Dismiss detail when tapping map background
                if showDetail {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showDetail = false
                        selectedCluster = nil
                    }
                }
            }

            // Empty state
            if musesWithLocation.isEmpty {
                emptyState
            }

            // Carousel overlay
            if showDetail && !clusterMuses.isEmpty {
                VStack {
                    Spacer()
                    carouselView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 100) // Above tab bar
                }
            }
        }
        .onChange(of: currentCarouselIndex) { _, newIndex in
            // Update map position when swiping carousel
            if newIndex < clusterMuses.count {
                let muse = clusterMuses[newIndex]
                if let coord = muse.coordinate {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        position = .camera(MapCamera(centerCoordinate: coord, distance: 1000))
                    }
                }
            }
        }
    }

    // MARK: - Clustering Algorithm

    private func computeClusters(from muses: [Muse], radius: CLLocationDistance) -> [MuseCluster] {
        var remainingMuses = muses
        var clusters: [MuseCluster] = []

        while !remainingMuses.isEmpty {
            guard let firstMuse = remainingMuses.first,
                  let firstCoord = firstMuse.coordinate else {
                remainingMuses.removeFirst()
                continue
            }

            let firstLocation = CLLocation(latitude: firstCoord.latitude, longitude: firstCoord.longitude)

            // Find all muses within radius of this one
            var clusterMuses: [Muse] = []
            var indicesToRemove: [Int] = []

            for (index, muse) in remainingMuses.enumerated() {
                guard let coord = muse.coordinate else { continue }
                let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)

                if location.distance(from: firstLocation) <= radius {
                    clusterMuses.append(muse)
                    indicesToRemove.append(index)
                }
            }

            // Remove clustered muses from remaining
            for index in indicesToRemove.reversed() {
                remainingMuses.remove(at: index)
            }

            // Calculate cluster center (average of all coordinates)
            let centerLat = clusterMuses.compactMap { $0.latitude }.reduce(0, +) / Double(clusterMuses.count)
            let centerLon = clusterMuses.compactMap { $0.longitude }.reduce(0, +) / Double(clusterMuses.count)

            // Sort muses by date (most recent first)
            let sortedMuses = clusterMuses.sorted { $0.createdAt > $1.createdAt }

            clusters.append(MuseCluster(
                muses: sortedMuses,
                coordinate: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                minClusterSize: minClusterSize
            ))
        }

        return clusters
    }

    // MARK: - Carousel View

    private var carouselView: some View {
        VStack(spacing: 12) {
            // Swipeable cards
            TabView(selection: $currentCarouselIndex) {
                ForEach(Array(clusterMuses.enumerated()), id: \.element.id) { index, muse in
                    MapMuseDetailCard(muse: muse) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showDetail = false
                            selectedCluster = nil
                        }
                    }
                    .padding(.horizontal, 20)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 160)

            // Counter indicator (cleaner than dots for many items)
            if clusterMuses.count > 1 {
                Text("\(currentCarouselIndex + 1) of \(clusterMuses.count)")
                    .font(.museMono)
                    .foregroundColor(.museTextTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.museCard.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.museTextTertiary)

            VStack(spacing: 8) {
                Text("no locations yet")
                    .font(.museTitle3)
                    .foregroundColor(.museText)

                Text("muses with location will appear here")
                    .font(.museCaption)
                    .foregroundColor(.museTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.museBackground.opacity(0.9))
    }
}

// MARK: - Cluster Pin

struct ClusterMapPin: View {
    let count: Int
    let isSelected: Bool

    var body: some View {
        ZStack {
            // Outer ring (selected state)
            if isSelected {
                Circle()
                    .stroke(Color.museAccent, lineWidth: 2)
                    .frame(width: 44, height: 44)
            }

            // Main cluster circle
            Circle()
                .fill(Color.museText)
                .frame(width: isSelected ? 36 : 32, height: isSelected ? 36 : 32)
                .shadow(color: Color.black.opacity(0.2), radius: 6, y: 3)

            // Count label
            Text("\(count)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.museCard)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Custom Map Pin

struct MuseMapPin: View {
    let muse: Muse
    let isSelected: Bool
    var isInCarousel: Bool = false

    var body: some View {
        ZStack {
            // Outer ring (selected state)
            if isSelected {
                Circle()
                    .stroke(Color.museAccent, lineWidth: 2)
                    .frame(width: 32, height: 32)
            }

            // Main pin circle
            Circle()
                .fill(isSelected ? Color.museAccent : (isInCarousel ? Color.museAccent.opacity(0.6) : Color.museAccent))
                .frame(width: isSelected ? 20 : 16, height: isSelected ? 20 : 16)
                .shadow(color: Color.black.opacity(0.15), radius: 4, y: 2)

            // Inner dot
            Circle()
                .fill(Color.museCard)
                .frame(width: isSelected ? 8 : 6, height: isSelected ? 8 : 6)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isInCarousel)
    }
}

// MARK: - Detail Card

struct MapMuseDetailCard: View {
    let muse: Muse
    let onDismiss: () -> Void

    @State private var audioPlayer = MuseAudioPlayer.shared

    private var isPlaying: Bool {
        audioPlayer.playingMuseId == muse.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with play button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let location = muse.locationString {
                        Text(location)
                            .font(.museCaptionMedium)
                            .foregroundColor(.museTextSecondary)
                    }

                    Text(muse.fullDateString)
                        .font(.museCaption)
                        .foregroundColor(.museTextTertiary)
                }

                Spacer()

                // Play button (like muse cards)
                Button {
                    if muse.hasAudio {
                        audioPlayer.togglePlayback(muse: muse)
                    }
                } label: {
                    HStack(spacing: 4) {
                        if muse.hasAudio {
                            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                                .font(.system(size: 8))
                                .foregroundColor(isPlaying ? .museAccent : .museTextTertiary)
                        } else {
                            Image(systemName: "waveform")
                                .font(.system(size: 10))
                        }

                        Text(muse.durationString)
                            .font(.museMonoMedium)
                    }
                    .foregroundColor(isPlaying ? .museAccent : .museTextTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isPlaying ? Color.museAccent.opacity(0.1) : Color.museBackgroundSecondary)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(isPlaying ? Color.museAccent.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!muse.hasAudio)
            }

            // Transcription preview
            Text(muse.transcription.isEmpty ? "(audio only)" : muse.preview)
                .font(.museSerif)
                .foregroundColor(muse.transcription.isEmpty ? .museTextTertiary : .museText)
                .lineLimit(3)

            // Footer (time right aligned)
            HStack {
                Spacer()

                Text(muse.timeString)
                    .font(.museMono)
                    .foregroundColor(.museTextTertiary)
            }
        }
        .padding(16)
        .background(Color.museCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isPlaying ? Color.museAccent.opacity(0.3) : Color.museBorder, lineWidth: isPlaying ? 1 : 0.5)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 20, y: 10)
        .animation(.museSoft, value: isPlaying)
    }
}

// MARK: - Preview

#Preview("With Clustered Muses") {
    MapView()
        .modelContainer(for: Muse.self, inMemory: true) { result in
            if case .success(let container) = result {
                let context = container.mainContext

                // Clustered muses in SF (within 500m)
                let muse1 = Muse(
                    transcription: "Walking through the park today, feeling grateful for this moment of peace.",
                    duration: 15.0,
                    locationString: "san francisco, usa",
                    latitude: 37.7749,
                    longitude: -122.4194
                )
                context.insert(muse1)

                let muse2 = Muse(
                    transcription: "Coffee shop thoughts - sometimes the best ideas come when you're not trying.",
                    duration: 8.5,
                    locationString: "san francisco, usa",
                    latitude: 37.7752, // Very close to muse1
                    longitude: -122.4190
                )
                context.insert(muse2)

                let muse3 = Muse(
                    transcription: "Another thought nearby, this one about creativity.",
                    duration: 12.0,
                    locationString: "san francisco, usa",
                    latitude: 37.7748, // Very close to muse1
                    longitude: -122.4196
                )
                context.insert(muse3)

                // Far away muse
                let muse4 = Muse(
                    transcription: "Oakland vibes are different.",
                    duration: 5.0,
                    locationString: "oakland, usa",
                    latitude: 37.8044,
                    longitude: -122.2712
                )
                context.insert(muse4)
            }
        }
}

#Preview("Empty State") {
    MapView()
        .modelContainer(for: Muse.self, inMemory: true)
}
