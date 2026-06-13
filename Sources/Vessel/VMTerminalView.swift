import SwiftUI
import SwiftTerm
import Foundation

struct VMTerminalView: NSViewRepresentable {
    let inputHandle: FileHandle
    let outputHandle: FileHandle
    
    func makeNSView(context: Context) -> TerminalView {
        let terminalView = TerminalView()
        
        // Zabraniamy przewijania systemowego (nie we wszystkich wersjach dostępne, TerminalView sam dba o scroll)
        // Jeśli potrzebne, osadzamy w NSScrollView wyżej.
        terminalView.terminalDelegate = context.coordinator
        context.coordinator.startReading(from: outputHandle, into: terminalView)
        
        return terminalView
    }
    
    func updateNSView(_ nsView: TerminalView, context: Context) {
    }
    
    static func dismantleNSView(_ nsView: TerminalView, coordinator: Coordinator) {
        coordinator.stopReading()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(inputHandle: inputHandle, outputHandle: outputHandle)
    }
    
    class Coordinator: NSObject, TerminalViewDelegate {
        let inputHandle: FileHandle
        let outputHandle: FileHandle
        
        init(inputHandle: FileHandle, outputHandle: FileHandle) {
            self.inputHandle = inputHandle
            self.outputHandle = outputHandle
        }
        
        func startReading(from handle: FileHandle, into terminalView: TerminalView) {
            handle.readabilityHandler = { [weak terminalView] fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty, let terminal = terminalView else { return }
                
                DispatchQueue.main.async {
                    let bytes = [UInt8](data)
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
