import SwiftUI
import AppKit

public class AsyncFilePromiseProvider: NSFilePromiseProvider, @unchecked Sendable {
    public var item: FileItem
    public var viewModel: FileBrowserViewModel

    public init(item: FileItem, viewModel: FileBrowserViewModel) {
        self.item = item
        self.viewModel = viewModel
        super.init(fileType: "public.data", delegate: nil)
        self.delegate = self
    }
}

extension AsyncFilePromiseProvider: NSFilePromiseProviderDelegate {
    public func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        return item.name
    }

    public func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        Task {
            do {
                try? FileManager.default.removeItem(at: url)
                await viewModel.download(file: item, to: url)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }
}
