import SwiftUI

/// Tinder-style swipe UI for Elo-based pairwise comparisons.
///
/// Both cards are swipeable with mirrored semantics: swipe right = this card wins,
/// swipe left = other card wins. Tap either card to choose it; long-press to edit.
struct PairwiseView: View {

    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var engine: EloEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Bottom card drag state
    @State private var dragOffset: CGSize = .zero
    @State private var exitOffset: CGFloat = 0
    @State private var isExiting: Bool = false

    // Top card drag state
    @State private var topDragOffset: CGSize = .zero
    @State private var topExitOffset: CGFloat = 0
    @State private var topIsExiting: Bool = false

    /// Randomly flipped each comparison so neither position is consistently favoured.
    @State private var isFlipped: Bool = false
    @State private var editingItem: ReminderItem?

    private let swipeThreshold: CGFloat = 100

    var body: some View {
        VStack(spacing: 0) {
            if let pair = engine.currentPair {
                swipeContent(pair)
                    .id(engine.comparisonCount)
                    .transition(reduceMotion
                        ? .opacity
                        : .asymmetric(
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
        .safeAreaInset(edge: .top, spacing: 0) {
            progressBand
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.8), value: engine.comparisonCount)
        .onChange(of: engine.comparisonCount) { _, _ in
            withAnimation(.spring(response: 0.3)) {
                dragOffset = .zero
                topDragOffset = .zero
            }
            exitOffset = 0
            isExiting = false
            topExitOffset = 0
            topIsExiting = false
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
        .navigationTitle("Which matters more?")
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
                Button { showSettingsSheet = true } label: {
                    Image(systemName: "gear")
                }
                .accessibilityLabel("Settings")
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
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView()
        }
    }

    // MARK: - Progress Band (extends nav bar glass downward)

    private var progressBand: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack {
                    Group {
                        if engine.estimatedRemaining > 0 {
                            Text("\(engine.estimatedRemaining) left")
                        } else {
                            Text("Almost done")
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    Spacer()
                }
                ProgressView(
                    value: Double(engine.comparisonCount),
                    total: Double(max(engine.comparisonCount + engine.estimatedRemaining, 1))
                )
                .tint(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if session.seedingFailed && session.mode != .pairwise {
                Text("AI seeding unavailable — using default ratings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    @State private var showSettingsSheet = false

    // MARK: - Converged State

    private var convergedState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .dynamicTypeSize(.small ... .accessibility2)
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

            // Top card — swipeable: right = top wins, left = bottom wins
            swipeCard(
                item: topItem, versus: bottomItem,
                dragOffset: $topDragOffset,
                exitOffset: $topExitOffset,
                isExiting: $topIsExiting
            )
            .padding(.horizontal)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in editingItem = topItem })

            // About equal + vs separator
            HStack {
                Spacer()
                Button { engine.equal() } label: {
                    Text("About equal")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.vertical, 10)

            // Bottom card — swipeable: right = bottom wins, left = top wins
            swipeCard(
                item: bottomItem, versus: topItem,
                dragOffset: $dragOffset,
                exitOffset: $exitOffset,
                isExiting: $isExiting
            )
            .padding(.horizontal)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in editingItem = bottomItem })

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

            Spacer(minLength: 20)
        }
    }

    // MARK: - Swipe Card

    private func swipeCard(
        item: ReminderItem,
        versus other: ReminderItem,
        dragOffset: Binding<CGSize>,
        exitOffset: Binding<CGFloat>,
        isExiting: Binding<Bool>
    ) -> some View {
        let normalized = min(max(dragOffset.wrappedValue.width / swipeThreshold, -1.0), 1.0)

        return PairwiseCardBody(item: item)
            .overlay(swipeOverlay(normalized: normalized))
            .rotationEffect(.degrees(Double(normalized) * 5))
            .scaleEffect(1.0 - abs(normalized) * 0.04)
            .offset(x: dragOffset.wrappedValue.width * 0.5 + exitOffset.wrappedValue)
            .opacity(isExiting.wrappedValue ? 0 : 1)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { dragOffset.wrappedValue = $0.translation }
                    .onEnded { value in
                        let dx = value.translation.width
                        if dx > swipeThreshold {
                            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.8)) {
                                exitOffset.wrappedValue = 900
                                isExiting.wrappedValue = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                engine.choose(winner: item)
                            }
                        } else if dx < -swipeThreshold {
                            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.8)) {
                                exitOffset.wrappedValue = -900
                                isExiting.wrappedValue = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                engine.choose(winner: other)
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                dragOffset.wrappedValue = .zero
                            }
                        }
                    }
            )
            .onTapGesture { engine.choose(winner: item) }
    }

    @ViewBuilder
    private func swipeOverlay(normalized: CGFloat) -> some View {
        let magnitude = abs(normalized)
        if magnitude > 0.12 {
            let pickingThis = normalized > 0
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill((pickingThis ? Color.green : Color.blue).opacity(magnitude * 0.25))
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: pickingThis ? "hand.thumbsup.fill" : "arrow.up")
                            .font(.title.bold())
                            .dynamicTypeSize(.small ... .accessibility1)
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
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 3)
        )
    }
}
