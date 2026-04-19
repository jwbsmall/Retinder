import SwiftUI

/// Tinder-style swipe UI for Elo-based pairwise comparisons.
///
/// Both cards are identical in size and material — swipe the bottom card or tap either card
/// to pick a winner. "Done for now" and Undo live in the navigation bar as glass pills.
struct PairwiseView: View {

    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var engine: EloEngine
    @Environment(\.modelContext) private var modelContext

    @AppStorage("pairwise_tap_default") private var pairwiseTapDefaultRaw: String = PairwiseTapDefault.choose.rawValue
    private var pairwiseTapDefault: PairwiseTapDefault { PairwiseTapDefault(rawValue: pairwiseTapDefaultRaw) ?? .choose }

    @State private var dragOffset: CGSize = .zero
    @State private var exitOffset: CGFloat = 0
    @State private var isExiting: Bool = false
    /// Randomly flipped each comparison so neither position is consistently favoured.
    @State private var isFlipped: Bool = false
    @State private var editingItem: ReminderItem?

    private let swipeThreshold: CGFloat = 100

    private func primaryAction(for item: ReminderItem) {
        switch pairwiseTapDefault {
        case .choose: engine.choose(winner: item)
        case .edit:   editingItem = item
        }
    }

    private func secondaryAction(for item: ReminderItem) {
        switch pairwiseTapDefault {
        case .choose: editingItem = item
        case .edit:   engine.choose(winner: item)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            if let pair = engine.currentPair {
                swipeContent(pair)
                    .id(engine.comparisonCount)
                    .transition(.asymmetric(
                        insertion: .push(from: .trailing).combined(with: .opacity),
                        removal:   .push(from: .leading).combined(with: .opacity)
                    ))
            } else if engine.isConverged {
                convergedState
            } else {
                Spacer()
                ProgressView("Thinking…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: engine.comparisonCount)
        .onChange(of: engine.comparisonCount) { _, _ in
            withAnimation(.spring(response: 0.3)) { dragOffset = .zero }
            exitOffset = 0
            isExiting = false
            isFlipped = Bool.random()
        }
        .onChange(of: engine.isConverged) { _, converged in
            if converged { session.finish(eloEngine: engine, context: modelContext) }
        }
        .sheet(item: $editingItem, onDismiss: {
            let _ = session.sessionItems
        }) { item in
            ReminderEditSheet(item: item)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    engine.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .labelStyle(.iconOnly)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(!engine.canUndo)
                .opacity(engine.canUndo ? 1 : 0.35)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    session.finish(eloEngine: engine, context: modelContext)
                } label: {
                    Label("Done for now", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Frosted Header

    private var headerBar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Text("Which matters more?")
                        .font(.headline)
                    Spacer()
                    Group {
                        if engine.estimatedRemaining > 0 {
                            Text("\(engine.estimatedRemaining) left")
                        } else {
                            Text("Almost done")
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                ProgressView(
                    value: Double(engine.comparisonCount),
                    total: Double(max(engine.comparisonCount + engine.estimatedRemaining, 1))
                )
                .tint(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if session.seedingFailed && session.mode != .pairwise {
                Text("AI seeding unavailable — using default ratings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: - Converged State

    private var convergedState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.blue)
            Text("Ranking settled!")
                .font(.title2.bold())
            Text("All items have been compared enough to produce a confident ranking.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("See Results") {
                session.finish(eloEngine: engine, context: modelContext)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    // MARK: - Swipe Layout

    private func swipeContent(_ pair: (ReminderItem, ReminderItem)) -> some View {
        let topItem    = isFlipped ? pair.1 : pair.0
        let bottomItem = isFlipped ? pair.0 : pair.1

        return VStack(spacing: 0) {
            Spacer(minLength: 8)

            // Top card — same size as bottom, tappable
            Button { primaryAction(for: topItem) } label: {
                PairwiseCardBody(item: topItem)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in secondaryAction(for: topItem) })
            .padding(.horizontal)

            HStack {
                Spacer()
                Text("vs")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.vertical, 8)

            // Bottom card — swipeable
            swipeCard(item: bottomItem, versus: topItem)
                .padding(.horizontal)
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in secondaryAction(for: bottomItem) })

            // Swipe direction hints
            HStack {
                Label("Top card", systemImage: "arrow.left")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Label("This one", systemImage: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)

            // Equal button
            Button { engine.equal() } label: {
                Text("About equal")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 11)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            Spacer(minLength: 20)
        }
    }

    // MARK: - Swipe Card (bottom)

    private func swipeCard(item: ReminderItem, versus other: ReminderItem) -> some View {
        let normalized = min(max(dragOffset.width / swipeThreshold, -1.0), 1.0)

        return PairwiseCardBody(item: item)
            .overlay(swipeOverlay(normalized: normalized))
            .rotationEffect(.degrees(Double(normalized) * 6))
            .scaleEffect(1.0 - abs(normalized) * 0.06)
            .offset(x: dragOffset.width * 0.5 + exitOffset)
            .opacity(isExiting ? 0 : 1)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { dragOffset = $0.translation }
                    .onEnded { value in
                        let dx = value.translation.width
                        if dx > swipeThreshold {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                exitOffset = 900
                                isExiting = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                engine.choose(winner: item)
                            }
                        } else if dx < -swipeThreshold {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                exitOffset = -900
                                isExiting = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                engine.choose(winner: other)
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                dragOffset = .zero
                            }
                        }
                    }
            )
            .onTapGesture { primaryAction(for: item) }
    }

    @ViewBuilder
    private func swipeOverlay(normalized: CGFloat) -> some View {
        let magnitude = abs(normalized)
        if magnitude > 0.12 {
            let pickingThis = normalized > 0
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill((pickingThis ? Color.green : Color.blue).opacity(magnitude * 0.3))
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: pickingThis ? "hand.thumbsup.fill" : "arrow.up")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(pickingThis ? .green : .blue)
                        Text(pickingThis ? "This one" : "Top one")
                            .font(.caption.bold())
                            .foregroundStyle(pickingThis ? .green : .blue)
                    }
                    .opacity(Double(magnitude))
                )
        }
    }
}

// MARK: - Card Body

private struct PairwiseCardBody: View {
    let item: ReminderItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let notes = item.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                Label(item.listName, systemImage: "list.bullet")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                if let due = item.dueDate {
                    Label(due.formatted(.dateTime.day().month()), systemImage: "calendar")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 170)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 16, y: 4)
        )
    }
}
