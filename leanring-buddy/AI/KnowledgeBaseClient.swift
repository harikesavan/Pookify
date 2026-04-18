//
//  KnowledgeBaseClient.swift
//  leanring-buddy
//

import Foundation

struct KnowledgeChunk: Decodable {
    let file_id: String
    let filename: String
    let score: Double
    let text: String
}

struct KnowledgeQueryResponse: Decodable {
    let query: String
    let company_id: String?
    let custom_instructions: String?
    let chunks: [KnowledgeChunk]
}

class KnowledgeBaseClient {
    private let baseURL: URL
    private let session: URLSession
    private var apiKey: String?

    init(baseURL: String) {
        self.baseURL = URL(string: baseURL)!

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }

    func configure(apiKey: String) {
        self.apiKey = apiKey
    }

    func queryRelevantChunks(for query: String, maxResults: Int = 5) async -> KnowledgeQueryResponse? {
        guard let apiKey, !apiKey.isEmpty else {
            return nil
        }

        let url = baseURL.appendingPathComponent("query-knowledge")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let body: [String: Any] = ["query": query, "max_results": maxResults]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                print("⚠️ Knowledge base query failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }

            let queryResponse = try JSONDecoder().decode(KnowledgeQueryResponse.self, from: data)
            print("📚 Knowledge base returned \(queryResponse.chunks.count) chunk(s) for \(queryResponse.company_id ?? "unknown")")
            return queryResponse
        } catch {
            print("⚠️ Knowledge base unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    func formatChunksForPrompt(_ chunks: [KnowledgeChunk]) -> String? {
        guard !chunks.isEmpty else { return nil }

        var contextParts: [String] = []
        for chunk in chunks {
            contextParts.append("<document title=\"\(chunk.filename)\" relevance=\"\(String(format: "%.2f", chunk.score))\">\n\(chunk.text)\n</document>")
        }

        return "<retrieved_context>\n" + contextParts.joined(separator: "\n\n") + "\n</retrieved_context>"
    }
}
