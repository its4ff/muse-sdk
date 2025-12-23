//
//  MapView.swift
//  muse
//
//  Interactive map showing muses as pins
//  Minimal aesthetic with swipeable carousel for nearby muses
//

import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct MapView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Muse.createdAt, order: .reverse) private var allMuses: [Muse]

    // Map state
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedMuse: Muse?
    @State private var showDetail = false

    // Carousel state
    @State private var currentCarouselIndex: Int = 0

    // Proximity radius in meters (500m)
    private let proximityRadius: CLLocationDistance = 500

    // Filter to only muses with location
    private var musesWithLocation: [Muse] {
        allMuses.filter { $0.hasLocation }
    }

    // Get nearby muses sorted by most recent
    private var nearbyMuses: [Muse] {
        guard let selected = selectedMuse,
              let selectedCoord = selected.coordinate else {
            return []
        }

        let selectedLocation = CLLocation(latitude: selectedCoord.latitude, longitude: selectedCoord.longitude)

        return musesWithLocation
            .filter { muse in
                guard let coord = muse.coordinate else { return false }
                let museLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                return museLocation.distance(from: selectedLocation) <= proximityRadius
            }
            .sorted { $0.createdAt > $1.createdAt } // Most recent first
    }

    var body: some View {
        ZStack {
            // Map
            Map(position: $position, selection: $selectedMuse) {
                ForEach(musesWithLocation, id: \.id) { muse in
                    if let coordinate = muse.coordinate {
                        Annotation(muse.preview.prefix(20).description, coordinate: coordinate) {
                            MuseMapPin(
                                muse: muse,
                                isSelected: selectedMuse?.id == muse.id,
                                isInCarousel: nearbyMuses.contains { $0.id == muse.id } && showDetail
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    selectedMuse = muse
                                    showDetail = true
                                    // Find index of tapped muse in nearby array
                                    if let index = nearbyMuses.firstIndex(where: { $0.id == muse.id }) {
                                        currentCarouselIndex = index
                                    } else {
                                        currentCarouselIndex = 0
                                    }
                                }
                            }
                        }
                        .tag(muse)
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapUserLocationButton()
            }

            // Empty state
            if musesWithLocation.isEmpty {
                emptyState
            }

            // Carousel overlay
            if showDetail && !nearbyMuses.isEmpty {
                VStack {
                    Spacer()
                    carouselView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 100) // Above tab bar
                }
            }
        }
        .onChange(of: selectedMuse) { _, newValue in
            if newValue != nil {
                showDetail = true
                // Reset to first index when new muse selected
                if let index = nearbyMuses.firstIndex(where: { $0.id == newValue?.id }) {
                    currentCarouselIndex = index
                } else {
                    currentCarouselIndex = 0
                }
            }
        }
        .onChange(of: currentCarouselIndex) { _, newIndex in
            // Update selected muse and animate map to it
            if newIndex < nearbyMuses.count {
                let newMuse = nearbyMuses[newIndex]
                selectedMuse = newMuse
            }
        }
    }

    // MARK: - Carousel View

    private var carouselView: some View {
        VStack(spacing: 12) {
            // Swipeable cards
            TabView(selection: $currentCarouselIndex) {
                ForEach(Array(nearbyMuses.enumerated()), id: \.element.id) { index, muse in
                    MapMuseDetailCard(muse: muse) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showDetail = false
                            selectedMuse = nil
                        }
                    }
                    .padding(.horizontal, 20)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 160)

            // Page indicator (only show if more than 1 nearby)
            if nearbyMuses.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<nearbyMuses.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentCarouselIndex ? Color.museAccent : Color.museTextMuted)
                            .frame(width: 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentCarouselIndex)
                    }
                }
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
