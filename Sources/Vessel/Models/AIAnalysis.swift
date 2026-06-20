import Foundation

public struct AIAnalysisRequest: Codable {
    public let model: String
    public let messages: [Message]

    public struct Message: Codable {
        public let role: String
        public let content: String

        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    public init(model: String, messages: [Message]) {
        self.model = model
        self.messages = messages
    }
}

public struct AIAnalysisResponse: Codable {
    public let choices: [Choice]

    public struct Choice: Codable {
        public let message: Message
    }

    public struct Message: Codable {
        public let content: String
    }
}
