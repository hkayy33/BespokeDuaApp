//
//  DuaReciever.swift
//  bespokeDua
//
//  Created by Hassan Kambala on 30/03/2026.
//

import Foundation

struct DuaReceiver: Identifiable, Codable {
    let id = UUID()
    let duaText: String
    let explanations: [ExplanationModel]
}

struct ExplanationModel: Identifiable, Codable {
    let id = UUID()
    let name: String
    let explanation: String
}
