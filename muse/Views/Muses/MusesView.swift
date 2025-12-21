//
//  MusesView.swift
//  muse
//
//  Voice vault - beautiful card-based view of transcribed recordings
//  Serif text, typewriter timestamps, zen aesthetic
//

import SwiftUI
import SwiftData

// MARK: - Time Period Filter

enum MuseTimePeriod: String, CaseIterable {
    case today = "today"
    case week = "week"
    case all = "all"
}

// MARK: - Muses View

struct MusesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Muse.createdAt, order: .reverse) private var muses: [Muse]
    @State private var selectedPeriod: MuseTimePeriod = .all

    var body: some View {
        NavigationStack {
            ZStack {
                Color.museBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Period selector
                    periodSelector
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.sm)

                    // Content
                    if filteredMuses.isEmpty {
                        emptyState
                    } else {
                        musesList
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.museBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("muses")
                        .font(.museBodyMedium)
                        .foregroundColor(.museText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if !muses.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                deleteAll()
                            } label: {
                                Label("Clear All", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.museTextSecondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Period Selector

    private var periodSelector: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(MuseTimePeriod.allCases, id: \.self) { period in
                Button {
                    withAnimation(.museSoft) {
                        selectedPeriod = period
                    }
                } label: {
                    Text(period.rawValue)
                        .font(.museCaptionMedium)
                        .foregroundColor(selectedPeriod == period ? .museText : .museTextTertiary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .background(selectedPeriod == period ? Color.museBackgroundSecondary : Color.clear)
                        .clipShape(Capsule())
                }
            }

            Spacer()

            // Entry count
            Text("\(filteredMuses.count)")
                .font(.museMono)
                .foregroundColor(.museTextMuted)
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Minimal icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.museBorder.opacity(0.5), lineWidth: 1)
                    .frame(width: 80, height: 100)

                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.museBorder.opacity(0.3))
                            .frame(width: 50, height: 6)
                    }
                }
            }

            VStack(spacing: Spacing.sm) {
                Text("no muses yet")
                    .font(.museSerifLarge)
                    .foregroundColor(.museTextSecondary)

                Text("tap and hold your ring to speak\nyour thoughts will appear here")
                    .font(.museCaption)
                    .foregroundColor(.museTextTertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
    }

    // MARK: - Muses List

    private var musesList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.md) {
                ForEach(filteredMuses) { muse in
                    MuseCard(
                        muse: muse,
                        onDelete: { deleteMuse(muse) }
                    )
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xxxl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Filtered Muses

    private var filteredMuses: [Muse] {
        switch selectedPeriod {
        case .today:
            return muses.filter { Calendar.current.isDateInToday($0.createdAt) }
        case .week:
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return muses.filter { $0.createdAt >= weekAgo }
        case .all:
            return muses
        }
    }

    // MARK: - Actions

    private func deleteMuse(_ muse: Muse) {
        modelContext.delete(muse)
    }

    private func deleteAll() {
        for muse in muses {
            modelContext.delete(muse)
        }
    }
}

// MARK: - Muse Card

struct MuseCard: View {
    let muse: Muse
    let onDelete: () -> Void

    @State private var showShareSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header: timestamp + duration
            HStack(alignment: .top) {
                // Timestamp (typewriter style)
                VStack(alignment: .leading, spacing: 2) {
                    Text(muse.timeString)
                        .font(.museMono)
                        .foregroundColor(.museTextTertiary)

                    Text(muse.dateString)
                        .font(.museMono)
                        .foregroundColor(.museTextMuted)
                }

                Spacer()

                // Duration badge
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))

                    Text(muse.durationString)
                        .font(.museMonoMedium)
                }
                .foregroundColor(.museTextTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.museBackgroundSecondary)
                .clipShape(Capsule())
            }

            // Transcribed text (serif)
            Text(muse.transcription)
                .font(.museSerif)
                .foregroundColor(.museText)
                .lineSpacing(6)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.museCard)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .stroke(Color.museBorder.opacity(0.3), lineWidth: 0.5)
        )
        .museShadowSmall()
        .contextMenu {
            Button {
                showShareSheet = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Button {
                UIPasteboard.general.string = muse.transcription
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareMuseScreen(muse: muse)
        }
    }
}

#Preview {
    MusesView()
        .modelContainer(for: Muse.self, inMemory: true)
}
