import SwiftUI

/// Tinder-style swipe UI: drag the top card right (more urgent) or left (less urgent).
/// Tap the smaller bottom card to pick it directly.
struct PairwiseView: View {

    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var engine: PairwiseEngine

    @State private var dragOffset: CGSize = .zero

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
        }
        .onAppear {
            if !engine.isStarted {
                engine.start(with: session.filteredItems)
            }
        }
        .onChange(of: engine.isComplete) { _, complete in
            guard complete else { return }
            var ranked = engine.sortedItems
            for i in ranked.indices {
                ranked[i].sortRank = i
            }
            session.rankedItems = ranked
            session.phase = .results
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Which is more urgent?")
                    .font(.headline)
                Spacer()
                Text("~\(engine.comparisonNumber) of \(engine.estimatedTotal)")
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
        VStack(spacing: 0) {
            Spacer()

            swipeCard(item: pair.0, versus: pair.1)
                .padding(.horizontal)

            swipeHints
                .padding(.top, 10)

            Text("vs")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .padding(.vertical, 10)

            Button { engine.choose(winner: pair.1) } label: {
                otherCard(pair.1)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)

            Spacer(minLength: 20)
        }
    }

    // MARK: - Main Swipe Card

    private func swipeCard(item: ReminderItem, versus other: ReminderItem) -> some View {
        let normalized = min(max(dragOffset.width / swipeThreshold, -1.0), 1.0)

        return CardBody(item: item)
            .overlay(swipeOverlay(normalized: normalized))
            .rotationEffect(.degrees(Double(normalized) * 7))
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
            let isRight = normalized > 0
            RoundedRectangle(cornerRadius: 18)
                .fill((isRight ? Color.green : Color.red).opacity(magnitude * 0.3))
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: isRight ? "checkmark" : "xmark")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(isRight ? .green : .red)
                        Text(isRight ? "More urgent" : "Less urgent")
                            .font(.caption.bold())
                            .foregroundStyle(isRight ? .green : .red)
                    }
                    .opacity(Double(magnitude))
                )
        }
    }

    private var swipeHints: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "arrow.left")
                Text("less urgent")
            }
            Spacer()
            HStack(spacing: 4) {
                Text("more urgent")
                Image(systemName: "arrow.right")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 28)
    }

    // MARK: - Secondary Card

    private func otherCard(_ item: ReminderItem) -> some View {
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
