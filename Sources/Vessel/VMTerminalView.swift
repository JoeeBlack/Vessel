import SwiftUI
import SwiftTerm
import Foundation

struct VMTerminalView: NSViewRepresentable {
    let inputHandle: FileHandle
    let outputHandle: FileHandle
    var filterText: String = ""
    
    func makeNSView(context: Context) -> TerminalView {
        let terminalView = TerminalView()
        
        // Zabraniamy przewijania systemowego (nie we wszystkich wersjach dostępne, TerminalView sam dba o scroll)
        // Jeśli potrzebne, osadzamy w NSScrollView wyżej.
        terminalView.terminalDelegate = context.coordinator
        context.coordinator.startReading(from: outputHandle, into: terminalView)
        
        return terminalView
    }
    
    func updateNSView(_ nsView: TerminalView, context: Context) {
        context.coordinator.filterText = filterText
    }
    
    static func dismantleNSView(_ nsView: TerminalView, coordinator: Coordinator) {
        coordinator.stopReading()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(inputHandle: inputHandle, outputHandle: outputHandle)
    }
    
    class Coordinator: NSObject, TerminalViewDelegate, @unchecked Sendable {
        let inputHandle: FileHandle
        let outputHandle: FileHandle
        
        init(inputHandle: FileHandle, outputHandle: FileHandle) {
            self.inputHandle = inputHandle
            self.outputHandle = outputHandle
        }
        
        var filterText: String = ""

        func startReading(from handle: FileHandle, into terminalView: TerminalView) {
            handle.readabilityHandler = { [weak self, weak terminalView] fileHandle in
                guard let self = self else { return }
                let data = fileHandle.availableData
                guard !data.isEmpty, let terminal = terminalView else { return }
                
                DispatchQueue.main.async {
                    let text = String(decoding: data, as: UTF8.self)

                    // 🛡️ Sentinel / Fix: Never drop stream chunks, as that permanently loses data.
                    // For now, SwiftTerm does not have a simple built-in view-level filter that keeps history intact without complex buffer manipulation.
                    // We feed all data to the terminal. If a filter is applied, we just highlight it using search selection if the API supports it,
                    // or in this prototype, we only highlight incoming text but DO NOT drop non-matching text.
                    // ⚡ Bolt Optimization: Use localizedCaseInsensitiveContains to avoid allocating intermediate lowercased strings
                    let outText: String
                    if !self.filterText.isEmpty, text.localizedCaseInsensitiveContains(self.filterText) {
                        outText = text.replacingOccurrences(of: self.filterText, with: "\u{1B}[43;30m\(self.filterText)\u{1B}[0m", options: .caseInsensitive)
                    } else {
                        outText = text
                    }

                    let bytes = [UInt8](outText.utf8)
                    terminal.feed(byteArray: bytes[...])
                }
            }
        }
        
        func stopReading() {
            outputHandle.readabilityHandler = nil
        }
        
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let writeData = Data(data)
            do {
                if #available(macOS 10.15.4, *) {
                    try inputHandle.write(contentsOf: writeData)
                } else {
                    inputHandle.write(writeData)
                }
            } catch {
                print("Błąd zapisu do wejścia terminala: \(error.localizedDescription)")
            }
        }
        
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
