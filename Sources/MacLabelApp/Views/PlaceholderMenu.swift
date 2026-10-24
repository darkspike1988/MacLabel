import SwiftUI

/// "Insert Field": adds `{column}` or `{n}` to the layout's main field.
struct PlaceholderMenu: View {
    @Environment(AppModel.self) private var model
    let names: [String]

    var body: some View {
        Menu(L10n.string("Insert Field"), systemImage: "curlybraces") {
            ForEach(names, id: \.self) { name in
                let token = "{\(name)}"
                Button(token) { model.document.insertPlaceholder(name) }
            }
        }
    }
}
