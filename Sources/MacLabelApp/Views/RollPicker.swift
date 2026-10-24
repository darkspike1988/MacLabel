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
                rollList(groups)
            }
        }
        .onAppear {
            selection = current?.id
            focus = .search
        }
    }

    private func rollList(_ groups: [[LabelRoll]]) -> some View {
        // Arrow keys move the selection; Return or a double-click chooses the roll.
        List(selection: $selection) {
            ForEach(groups, id: \.first?.id) { group in
                Section(group.first?.sizeText ?? "") {
                    ForEach(group) { roll in
                        row(roll)
                    }
                }
            }
        }
        .listStyle(.inset)
        .focused($focus, equals: .list)
        .onChange(of: query) {
            selection = Self.selection(afterFilter: self.groups(for: query), keeping: selection)
        }
        .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { ids in
            choose(ids: ids, in: groups)
        }
    }

    private func row(_ roll: LabelRoll) -> some View {
        RollRow(roll: roll, isCurrent: roll.id == current?.id)
            .tag(roll.id)
            // A popover has no confirm button, so a click chooses at once.
            .onTapGesture { onSelect(roll) }
    }

    private func moveIntoList() -> KeyPress.Result {
        if selection == nil {
            selection = Self.groups(for: query, catalog: .bundled, headDots: headDots).first?.first?.id
        }
        focus = .list
        return .handled
    }

    private func groups(for query: String) -> [[LabelRoll]] {
        Self.groups(for: query, catalog: .bundled, headDots: headDots)
    }

    private func chooseFirst(of groups: [[LabelRoll]]) {
        if let roll = Self.roll(ids: [], in: groups) { onSelect(roll) }
    }

    private func choose(ids: Set<String>, in groups: [[LabelRoll]]) {
        if let roll = Self.roll(ids: ids, in: groups) { onSelect(roll) }
    }

    /// The first roll whose id is in `ids`; for an empty `ids` the first roll shown.
    nonisolated static func roll(ids: Set<String>, in groups: [[LabelRoll]]) -> LabelRoll? {
        let rolls = groups.joined()
        return ids.isEmpty ? rolls.first : rolls.first { ids.contains($0.id) }
    }

    /// The selection after the result list changed: kept while still visible, else the first result (nil if none).
    nonisolated static func selection(afterFilter groups: [[LabelRoll]], keeping selection: String?) -> String? {
        let rolls = groups.joined()
        if let selection, rolls.contains(where: { $0.id == selection }) { return selection }
        return rolls.first?.id
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
