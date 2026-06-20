import Foundation

public actor LLMService {
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    public init() {}

    // In a real app this should be securely fetched from Keychain.
    // Here we use an environment variable for prototyping.
    private var apiKey: String {
        ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    }

    public func analyzeLog(trace: String) async throws -> String {
        // We're mimicking an API call. In a local testing environment, we might not have a real API key.
        // For local development without a key, we can return a mock response or use an alternative like llama.cpp if available.
        // For now, we will enforce the API key requirement but allow a small delay to simulate processing.

        guard !apiKey.isEmpty else {
            // For testing purposes, if no API key is provided, we can return a mock string after a delay
            // If the user wants actual API interaction, they will need to provide OPENAI_API_KEY.
            try await Task.sleep(nanoseconds: 1_500_000_000)
            return """
            **Mock Analysis (No API Key Provided)**

            It looks like this is a sample log trace:
            `\(trace.prefix(100))...`

            **Possible Issues:**
            - This is a mock response because the `OPENAI_API_KEY` environment variable is not set.
            - To get real analysis, please set your OpenAI API key.

            **Suggested Solutions:**
            1. Set the API key using `export OPENAI_API_KEY="your-key"`.
            2. Run the app again.
            """
            // If strict enforcement is needed: throw LLMError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let prompt = """
        Proszę przeanalizuj następujące logi kontenera i wyjaśnij krótko potencjalne problemy oraz zaproponuj rozwiązania.
        Logi:
        \(trace)
        """

        let aiRequest = AIAnalysisRequest(
            model: "gpt-3.5-turbo",
            messages: [
                .init(role: "system", content: "Jesteś ekspertem DevOps i pomagasz w analizie logów z kontenerów."),
                .init(role: "user", content: prompt)
            ]
        )

        request.httpBody = try JSONEncoder().encode(aiRequest)

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30.0
        let session = URLSession(configuration: sessionConfig)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("API Error: \(errorText)")
            }
            throw LLMError.apiError
        }

        let aiResponse = try JSONDecoder().decode(AIAnalysisResponse.self, from: data)
        guard let content = aiResponse.choices.first?.message.content else {
            throw LLMError.invalidResponse
        }

        return content
    }
}

public enum LLMError: Error, LocalizedError {
    case missingAPIKey
    case apiError
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Brak klucza API OpenAI (ustaw OPENAI_API_KEY)."
        case .apiError: return "Błąd podczas komunikacji z API."
        case .invalidResponse: return "Nieprawidłowa odpowiedź od API."
        }
    }
}
