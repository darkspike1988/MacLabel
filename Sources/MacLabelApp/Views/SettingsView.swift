import AppKit
import SwiftUI

/// The Settings window: default printer, menu bar extra, status polling and the command line hint.
/// Reads `AppModel` from the environment.
public struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppSettings.showMenuBarExtraKey) private var showsMenuBarExtra = true
    @AppStorage(AppSettings.statusPollingKey) private var statusPolling = true
    @AppStorage(AppSettings.defaultPrinterSerialKey) private var defaultSerial = ""

    public init() {}

    public var body: some View {
        let command = AppSettings.cliInstallCommand()
        Form {
            Section {
                let choices = model.printers.filter { $0.serialNumber != nil }
                if choices.count > 1 {
                    Picker(L10n.string("Default printer"), selection: $defaultSerial) {
                        Text(L10n.string("Automatic")).tag("")
                        ForEach(choices, id: \.id) { printer in
                            Text("\(printer.model.name) · \(printer.serialNumber ?? "")").tag(printer.serialNumber ?? "")
                        }
                    }
                }
                Toggle(L10n.string("Show in the menu bar"), isOn: $showsMenuBarExtra)
                Toggle(L10n.string("Poll the printer status automatically"), isOn: $statusPolling)
            } footer: {
                Text(L10n.string("MacLabel only asks the printer while a window or the menu bar panel is open."))
            }

            Section {
                Text(command)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                Button(L10n.string("Copy Command"), systemImage: "doc.on.doc") { copy(command) }
            } header: {
                Text(L10n.string("Command Line"))
            } footer: {
                Text(L10n.string("Run this command in Terminal to use maclabel there. The app and the command line tool remember rolls separately."))
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
