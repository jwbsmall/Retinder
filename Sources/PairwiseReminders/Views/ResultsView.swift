import SwiftUI
import UIKit

/// Shows the final ranked list and lets the user write priorities back to Reminders.
struct ResultsView: View {

    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var remindersManager: RemindersManager
    @EnvironmentObject private var engine: PairwiseEngine

    @State private var showApplySheet = false
    @State private var showSuccessBanner = false
    @State private var isApplying = false
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showSuccessBanner {
                    successBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                rankedList

                if let error = session.applyError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }

                bottomBar
            }
            .navigationTitle("Your Priorities")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showApplySheet) {
                ApplySheet(
                    itemCount: session.rankedItems.count,
                    isApplying: isApplying
                ) { mode, urgentCount in
                    applyPriorities(mode: mode, urgentCount: urgentCount)
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Sub-views

    private var successBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Priorities applied to Reminders!")
                .font(.subheadline.bold())
            Spacer()
        }
        .padding()
        .background(Color.green.opacity(0.12))
    }

    private var rankedList: some View {
        List {
            ForEach(Array(session.rankedItems.enumerated()), id: \.element.id) { index, item in
                RankedRow(
                    item: item,
                    rank: index + 1,
                    total: session.rankedItems.count
                )
            }
        }
        .listStyle(.insetGrouped)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Divider()
                .padding(.bottom, 2)

            Button(action: { showApplySheet = true }) {
                Label(
                    session.didApply ? "Applied!" : "Apply to Reminders…",
                    systemImage: session.didApply ? "checkmark" : "square.and.arrow.down"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(session.didApply ? Color.green : Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(session.didApply || isApplying)
            .padding(.horizontal)

            HStack {
                Button(action: copyList) {
                    Label(didCopy ? "Copied!" : "Copy list", systemImage: "doc.on.doc")
                        .font(.subheadline)
                        .animation(.default, value: didCopy)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Start Over") {
                    engine.reset()
                    session.reset()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Actions

    private func applyPriorities(mode: ApplySheet.Mode, urgentCount: Int) {
        isApplying = true
        session.applyError = nil
        showApplySheet = false

        Task { @MainActor in
            defer { isApplying = false }
            do {
                switch mode {
                case .tiered:
                    try remindersManager.applyPriorities(session.rankedItems)
                case .urgent:
                    try remindersManager.applyTopNUrgent(session.rankedItems, count: urgentCount)
                }
                session.didApply = true
                withAnimation(.spring(response: 0.4)) { showSuccessBanner = true }
            } catch {
                session.applyError = error.localizedDescription
            }
        }
    }

    private func copyList() {
        let text = session.rankedItems.enumerated().map { i, item in
            "\(i + 1). \(item.title)"
        }.joined(separator: "\n")
        UIPasteboard.general.string = text
        withAnimation { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { didCopy = false }
        }
    }
}

// MARK: - Apply Sheet

private struct ApplySheet: View {

    enum Mode { case tiered, urgent }

    let itemCount: Int
    let isApplying: Bool
    let onApply: (Mode, Int) -> Void

    @State private var mode: Mode = .tiered
    @State private var urgentCount = 3
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("How to apply", selection: $mode) {
                        Text("Tiered priorities").tag(Mode.tiered)
                        Text("Mark top N as urgent").tag(Mode.urgent)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if mode == .urgent {
                    Section("How many items?") {
                        Stepper(
                            "\(urgentCount) item\(urgentCount == 1 ? "" : "s")",
                            value: $urgentCount,
                            in: 1...max(1, itemCount)
                        )
                    }
                }

                Section {
                    Label(modeDescription, systemImage: modeIcon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Apply to Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { onApply(mode, urgentCount) }
                        .bold()
                        .disabled(isApplying)
                }
            }
        }
    }

    private var modeDescription: String {
        switch mode {
        case .tiered:
            return "Top 25% → High, next 25% → Medium, next 25% → Low, rest → None."
        case .urgent:
            return "Top \(urgentCount) item\(urgentCount == 1 ? "" : "s") → High priority. Everything else → None."
        }
    }

    private var modeIcon: String {
        switch mode {
        case .tiered: return "chart.bar.fill"
        case .urgent: return "exclamationmark.2"
        }
    }
}

// MARK: - Ranked Row

private struct RankedRow: View {
    let item: ReminderItem
    let rank: Int
    let total: Int

    private var priorityLabel: String { item.priorityLabel(totalCount: total) }
    private var priorityColor: Color  { mapColor(item.priorityColor(totalCount: total)) }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(badgeColor)
                    .frame(width: 38, height: 38)
                Text("\(rank)")
                    .font(.system(.body, design: .rounded).bold())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(item.listName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let reasoning = item.aiReasoning {
                        Text("·")
                            .foregroundStyle(Color(.tertiaryLabel))
                        Text(reasoning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text(priorityLabel)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(priorityColor.opacity(0.15))
                .foregroundStyle(priorityColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.vertical, 4)
    }

    private var badgeColor: Color {
        switch rank {
        case 1:  return .blue
        case 2:  return .indigo
        case 3:  return .purple
        default: return Color(.systemGray3)
        }
    }

    private func mapColor(_ c: ReminderItem.PriorityColor) -> Color {
        switch c {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .yellow
        case .none:   return Color(.secondaryLabel)
        }
    }
}
