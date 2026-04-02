import SwiftUI

/// Tinder-style swipe UI. The large bottom card is the active one — drag or tap it to pick it.
/// Tap the compact top card to pick it instead.
struct PairwiseView: View {

    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var engine: PairwiseEngine

    @State private var dragOffset: CGSize = .zero
    /// Randomly flipped each comparison so neither position is consistently "favoured".
    @State private var isFlipped: Bool = false
    @State private var showCancelAlert = false

    private let swipeThreshold: CGFloat = 100

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            if let pair = engine.currentPair {
                swipeContent(pair)
                    .id(engine.comparisonNumber)
                    .transition(.asymmetric(
                        insertion: .push(from: .trailing).combined(with: .opacity),
                        removal:   .push(from: .leading).combined(with: .opacity)
                    ))
            } else {
                Spacer()
                ProgressView("Thinking…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: engine.comparisonNumber)
        .onChange(of: engine.comparisonNumber) { _, _ in
            withAnimation(.spring(response: 0.3)) { dragOffset = .zero }
            isFlipped = Bool.random()
        }
        .onAppear {
            if !engine.isStarted {
                engine.start(with: session.filteredItems)
                isFlipped = Bool.random()
            }
        }
        .onChange(of: engine.isComplete) { _, complete in
            guard complete else { return }
            var ranked = engine.sortedItems
            for i in ranked.indices { ranked[i].sortRank = i }
            session.rankedItems = ranked
            session.phase = .results
        }
        .alert("Stop comparing?", isPresented: $showCancelAlert) {
            Button("Keep going", role: .cancel) { }
            Button("Stop", role: .destructive) {
                engine.reset()
                session.phase = .listPicking
            }
        } message: {
            Text("Your comparison progress will be lost.")
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 10) {
            HStack {
                Button("Stop") { showCancelAlert = true }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Which matters more?")
                    .font(.headline)

                Spacer()

                Text("\(engine.comparisonNumber)/\(engine.estimatedTotal)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal)
            .padding(.top)

            ProgressView(
                value: Double(engine.comparisonNumber),
                total: Double(max(engine.estimatedTotal, 1))
            )
            .tint(.blue)
            .padding(.horizontal)

            if session.aiFilteringFailed {
                Text("AI filtering unavailable — comparing all items")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Swipe Layout

    private func swipeContent(_ pair: (ReminderItem, ReminderItem)) -> some View {
        // Randomly assign top (compact) vs bottom (large interactive) each comparison.
        let topItem    = isFlipped ? pair.1 : pair.0
        let bottomItem = isFlipped ? pair.0 : pair.1

        return VStack(spacing: 0) {
            Spacer()

            // Compact top card — tap to pick it
            Button { engine.choose(winner: topItem) } label: {
                compactCard(topItem)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)

            HStack {
                Spacer()
                Text("vs")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.vertical, 10)

            // Large bottom card — swipe right to pick it, swipe left to pick top card
            swipeCard(item: bottomItem, versus: topItem)
                .padding(.horizontal)

            swipeHints
                .padding(.top, 10)

            Button("No preference") { engine.skip() }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

            Spacer(minLength: 20)
        }
    }

    // MARK: - Large Swipe Card (bottom)

    private func swipeCard(item: ReminderItem, versus other: ReminderItem) -> some View {
        let normalized = min(max(dragOffset.width / swipeThreshold, -1.0), 1.0)

        return CardBody(item: item)
            .overlay(swipeOverlay(normalized: normalized))
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
        if magnitude > 0.25 {
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

    private var swipeHints: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "arrow.left")
                Text("top one")
            }
            Spacer()
            HStack(spacing: 4) {
                Text("this one")
                Image(systemName: "arrow.right")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 28)
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
            Image(systemName: "hand.tap")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
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

            if let reasoning = item.aiReasoning {
                Text(reasoning)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

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
