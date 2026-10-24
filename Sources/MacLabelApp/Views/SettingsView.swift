import AppKit
import LabelTransport
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
        Form {
            Section {
                let choices = Self.printerChoices(connected: model.printers, saved: defaultSerial)
                if choices.count > 1 || (!defaultSerial.isEmpty && !choices.isEmpty) {
                    Picker(L10n.string("Default printer"), selection: $defaultSerial) {
                        Text(L10n.string("Automatic")).tag("")
                        ForEach(choices, id: \.serial) { choice in
                            Text(verbatim: choice.title).tag(choice.serial)
                        }
                    }
                }
                Toggle(L10n.string("Show in the menu bar"), isOn: $showsMenuBarExtra)
                Toggle(L10n.string("Poll the printer status automatically"), isOn: $statusPolling)
            } footer: {
                Text(L10n.string("MacLabel only asks the printer while a window or the menu bar panel is open."))
            }

            cliSection(AppSettings.cliInstall())
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func cliSection(_ install: AppSettings.CLIInstall) -> some View {
        Section {
            switch install {
            case .homebrew(let command), .systemWide(let command):
                Text(command)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                Button(L10n.string("Copy Command"), systemImage: "doc.on.doc") { copy(command) }
            case .moveFirst:
                Label(L10n.string("Move MacLabel to the Applications folder first."), systemImage: "folder")
            }
        } header: {
            Text(L10n.string("Command Line"))
        } footer: {
            switch install {
            case .homebrew:
                Text(L10n.string("Run this command in Terminal to use maclabel there. The app and the command line tool remember rolls separately."))
            case .systemWide:
                Text(L10n.string("Run this command in Terminal to use maclabel there. It asks for the administrator password. The app and the command line tool remember rolls separately."))
            case .moveFirst:
                Text(L10n.string("The app and the command line tool remember rolls separately."))
            }
        }
    }

    /// One entry of the default-printer picker.
    struct PrinterChoice: Equatable {
        let serial: String
        let title: String
        let isConnected: Bool
    }

    /// The connected printers with a serial number, plus the saved default when it is not connected.
    nonisolated static func printerChoices(connected: [DiscoveredPrinter], saved: String, bundle: Bundle = L10n.bundle) -> [PrinterChoice] {
        var choices = connected.compactMap { printer in
            printer.serialNumber.map { PrinterChoice(serial: $0, title: "\(printer.model.name) · \($0)", isConnected: true) }
        }
        if !saved.isEmpty, !choices.contains(where: { $0.serial == saved }) {
            choices.append(PrinterChoice(
                serial: saved, title: String(localized: "\(saved) (not connected)", bundle: bundle), isConnected: false
            ))
        }
        return choices
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
