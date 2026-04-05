//
//  DuaReciever.swift
//  bespokeDua
//
//  Created by Hassan Kambala on 30/03/2026.
//

import Foundation

struct DuaReceiver: Identifiable, Sendable {
    let id: UUID
    let duaText: String
    let explanations: [ExplanationModel]

    init(id: UUID = UUID(), duaText: String, explanations: [ExplanationModel]) {
        self.id = id
        self.duaText = duaText
        self.explanations = explanations
    }
}

struct ExplanationModel: Identifiable, Sendable {
    let id: UUID
    let name: String
    let explanation: String

    init(id: UUID = UUID(), name: String, explanation: String) {
        self.id = id
        self.name = name
        self.explanation = explanation
    }
}
