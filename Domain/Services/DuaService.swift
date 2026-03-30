//
//  DuaService.swift
//  bespokeDua
//
//  Created by Hassan Kambala on 30/03/2026.
//

import Foundation
import Combine

@MainActor
class DuaService: ObservableObject {
    
    static let shared = DuaService()
    
    private init() {}
    
    // MARK: - State (like Angular signals)
    @Published var duas: [DuaReceiver] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    // Backend base (service appends `/generate`)
    private let baseUrl = "https://bespoke-app.fly.dev/api/dua"
    
    // MARK: - Generate Duas (Angular generateDuas equivalent)
    func generateDuas(input: DuaSender) async {
        
        isLoading = true
        errorMessage = nil
        
        guard let url = URL(string: "\(baseUrl)/generate") else {
            isLoading = false
            errorMessage = "Invalid URL"
            return
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            request.httpBody = try JSONEncoder().encode([
                "text": input.inputtedDuaText
            ])
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                throw URLError(.badServerResponse)
            }
            
            // MARK: - Backend response shape
            struct Response: Decodable {
                let duas: [BackendDua]
            }
            
            struct BackendDua: Decodable {
                let dua: String
                let explanations: [BackendExplanation]
            }
            
            struct BackendExplanation: Decodable {
                let name: String
                let explanation: String
            }
            
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            
            // MARK: - Map (Angular map())
            self.duas = decoded.duas.map {
                DuaReceiver(
                    duaText: $0.dua,
                    explanations: $0.explanations.map {
                        ExplanationModel(name: $0.name, explanation: $0.explanation)
                    }
                )
            }
            
            isLoading = false
            
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Clear (like clearDuas)
    func clearDuas() {
        duas = []
        errorMessage = nil
    }
}
