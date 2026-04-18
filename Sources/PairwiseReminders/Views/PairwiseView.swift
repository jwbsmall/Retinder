import SwiftUI

/// Tinder-style swipe UI for Elo-based pairwise comparisons.
///
/// The large bottom card is the interactive one — drag or tap it to pick it.
/// Tap the compact top card to pick it instead.
/// "Done for now" is always safe — partial Elo rankings are valid.
struct PairwiseView: View {

    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var engine: EloEngine
    @Environment(\.modelContext) private var modelContext

    @State private var dragOffset: CGSize = .zero
    /// Randomly flipped each comparison so neither position is consistently favoured.
    @State private var isFlipped: Bool = false
    @State private var editingItem: ReminderItem?

    private let swipeThreshold: CGFloat = 100

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
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: engine.comparisonCount)
        .onChange(of: engine.comparisonCount) { _, _ in
            withAnimation(.spring(response: 0.3)) { dragOffset = .zero }
            isFlipped = Bool.random()
        }
        .onChange(of: engine.isConverged) { _, converged in
            if converged { session.finish(eloEngine: engine, context: modelContext) }
        }
        .sheet(item: $editingItem, onDismiss: {
            // Force a redraw so edits appear on the cards immediately.
            let _ = session.sessionItems
        }) { item in
            ReminderEditSheet(item: item)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if engine.canUndo {
                        Button("Undo", systemImage: "arrow.uturn.backward") {
                            engine.undo()
                        }
                    }
                    Button("Done for now", systemImage: "xmark") {
                        session.finish(eloEngine: engine, context: modelContext)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Text("Which matters more?")
                    .font(.headline)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Group {
                    if engine.estimatedRemaining > 0 {
                        Text("\(engine.estimatedRemaining) left")
                    } else {
                        Text("Almost done")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .padding(.horizontal)
            .padding(.top)

            ProgressView(
                value: Double(engine.comparisonCount),
                total: Double(max(engine.comparisonCount + engine.estimatedRemaining, 1))
            )
            .tint(.blue)
            .padding(.horizontal)

            if session.seedingFailed && session.mode != .pairwise {
                Text("AI seeding unavailable — using default ratings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
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

            // Compact top card — tap to pick it, long-press to edit
            Button { engine.choose(winner: topItem) } label: {
                compactCard(topItem)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(LongPressGesture().onEnded { _ in editingItem = topItem })
            .padding(.horizontal)

            HStack {
                Spacer()
                Text("vs")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.vertical, 8)

            // Large bottom card — swipe right to pick it, swipe left to pick top card
            swipeCard(item: bottomItem, versus: topItem)
                .padding(.horizontal)
                .simultaneousGesture(LongPressGesture().onEnded { _ in editingItem = bottomItem })

            // Secondary action
            Button { engine.equal() } label: {
                Text("About equal")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.secondary)
            .padding(.top, 12)

            Spacer(minLength: 20)
        }
    }

    // MARK: - Large Swipe Card (bottom)

    private func swipeCard(item: ReminderItem, versus other: ReminderItem) -> some View {
        let normalized = min(max(dragOffset.width / swipeThreshold, -1.0), 1.0)

        return CardBody(item: item)
            .overlay(swipeOverlay(normalized: normalized))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.blue.opacity(0.3), lineWidth: 2))
            .rotationEffect(.degrees(Double(normalized) * 6))
            .offset(x: dragOffset.width * 0.5)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { dragOffset = $0.translation }
                    .onEnded { value in
                        let dx = value.translation.width
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = .zero
                        }
                        if dx > swipeThreshold {
                            engine.choose(winner: item)
                        } else if dx < -swipeThreshold {
                            engine.choose(winner: other)
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
            RoundedRectangle(cornerRadius: 18)
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

    // MARK: - Compact Top Card

    private func compactCard(_ item: ReminderItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(item.listName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Card Body

private struct CardBody: View {
    let item: ReminderItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let notes = item.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                Label(item.listName, systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let due = item.dueDate {
                    Label(due.formatted(.dateTime.day().month()), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        )
    }
}
