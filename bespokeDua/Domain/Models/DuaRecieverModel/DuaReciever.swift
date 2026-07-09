//
//  DuaReciever.swift
//  bespokeDua
//
//  Created by Hassan Kambala on 30/03/2026.
//

import Foundation

struct DuaReceiver: Identifiable, Sendable, Equatable {
    let id: UUID
    let duaText: String
    let explanations: [ExplanationModel]
    /// When set, this JSON is sent to `SavedDuas` instead of the default bespoke payload.
    let storageJSON: String?

    init(id: UUID = UUID(), duaText: String, explanations: [ExplanationModel], storageJSON: String? = nil) {
        self.id = id
        self.duaText = duaText
        self.explanations = explanations
        self.storageJSON = storageJSON
    }
}

struct ExplanationModel: Identifiable, Sendable, Equatable, Hashable {
    let id: UUID
    let name: String
    let explanation: String

    init(id: UUID = UUID(), name: String, explanation: String) {
        self.id = id
        self.name = name
        self.explanation = explanation
    }
}
