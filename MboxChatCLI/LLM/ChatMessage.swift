//
//  ChatMessage.swift
//  MboxChatCLI
//
//  Ported from AIStudio (Jordan Koch). Copyright © 2026 Jordan Koch.
//

import Foundation

/// Role in a chat conversation
enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

/// A single chat message
struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: ChatRole
    var content: String
    let timestamp: Date

    init(role: ChatRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}
