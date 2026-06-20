import Foundation
import SwiftUI

@Observable
public class AIAnalysisViewModel {
    public var isAnalyzing: Bool = false
    public var analysisResult: String? = nil
    public var errorMessage: String? = nil
    public var isPopoverPresented: Bool = false

    private let llmService = LLMService()

    public init() {}

    @MainActor
    public func analyzeLogs(trace: String) {
        guard !trace.isEmpty else {
            self.errorMessage = "Brak logów do analizy."
            self.isPopoverPresented = true
            return
        }

        self.isAnalyzing = true
        self.analysisResult = nil
        self.errorMessage = nil
        self.isPopoverPresented = true

        Task {
            do {
                let result = try await llmService.analyzeLog(trace: trace)
                self.analysisResult = result
                self.isAnalyzing = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isAnalyzing = false
            }
        }
    }
}
