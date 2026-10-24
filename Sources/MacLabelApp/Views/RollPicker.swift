import LabelMedia
import SwiftUI

/// Search field plus the matching rolls. Rolls of the same physical size (standard and durable
/// variants) form one section with the standard roll first, as in the CLI (Ruling 27).
struct RollPicker: View {
    /// The roll in use, marked with a checkmark.
    let current: LabelRoll?
    /// Print head width of the selected printer; wider rolls are hidden.
    let headDots: Int
    let onSelect: (LabelRoll) -> Void

    @State private var query = ""
    @State private var selection: String?
    @FocusState private var focus: Field?

    private enum Field { case search, list }

    var body: some View {
        VStack(spacing: 0) {
            TextField(L10n.string("Search rolls"), text: $query, prompt: Text(L10n.string("Article number, size or name")))
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .search)
                .padding()
                .accessibilityLabel(L10n.string("Search rolls"))
                .onSubmit { chooseFirst(of: Self.groups(for: query, catalog: .bundled, headDots: headDots)) }
                .onKeyPress(.downArrow) { moveIntoList() }

            let groups = Self.groups(for: query, catalog: .bundled, headDots: headDots)
            if groups.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                // Arrow keys move the selection; Return or a double-click chooses the roll.
                List(selection: $selection) {
                    ForEach(groups, id: \.first?.id) { group in
                        Section(group.first?.sizeText ?? "") {
                            ForEach(group) { roll in
                                RollRow(roll: roll, isCurrent: roll.id == current?.id)
                                    .tag(roll.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .focused($focus, equals: .list)
                .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { ids in
                    choose(ids: ids, in: groups)
                }
            }
        }
        .onAppear {
            selection = current?.id
            focus = .search
        }
    }

    private func moveIntoList() -> KeyPress.Result {
        if selection == nil {
            selection = Self.groups(for: query, catalog: .bundled, headDots: headDots).first?.first?.id
        }
        focus = .list
        return .handled
    }

    private func chooseFirst(of groups: [[LabelRoll]]) {
        if let roll = groups.first?.first { onSelect(roll) }
    }

    private func choose(ids: Set<String>, in groups: [[LabelRoll]]) {
        if let roll = groups.joined().first(where: { ids.contains($0.id) }) { onSelect(roll) }
    }

    /// The search result (or, for an empty query, the whole catalog sorted by size), grouped by
    /// physical size in ranking order, the standard material first within each group.
    nonisolated static func groups(for query: String, catalog: MediaCatalog, headDots: Int? = nil) -> [[LabelRoll]] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var rolls = trimmed.isEmpty ? catalog.rolls.sorted(by: browsingOrder) : catalog.search(trimmed)
        if let headDots { rolls = rolls.filter { $0.minHeadDots <= headDots } }

        var order: [SizeKey] = []
        var buckets: [SizeKey: [LabelRoll]] = [:]
        for roll in rolls {
            let key = SizeKey(roll)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(roll)
        }
        return order.map { key in
            let group = buckets[key] ?? []
            return group.filter { $0.material == "standard" } + group.filter { $0.material != "standard" }
        }
    }

    /// "11354 · 57 × 32 mm" for the toolbar chip.
    nonisolated static func chipText(_ roll: LabelRoll) -> String {
        L10n.string("\(roll.id) · \(roll.sizeText)")
    }

    /// Die-cut rolls by reading size, continuous rolls last, ties by id.
    nonisolated private static func browsingOrder(_ a: LabelRoll, _ b: LabelRoll) -> Bool {
        let sa = a.readingSizeMM, sb = b.readingSizeMM
        let ka = (a.kind == .continuous ? 1 : 0, sa.width, sa.height ?? 0, a.id)
        let kb = (b.kind == .continuous ? 1 : 0, sb.width, sb.height ?? 0, b.id)
        return ka < kb
    }

    private struct SizeKey: Hashable {
        let across: Int
        let feed: Int?
        let kind: LabelRoll.Kind

        init(_ roll: LabelRoll) {
            across = roll.acrossDots
            feed = roll.feedDots
            kind = roll.kind
        }
    }
}
