//
//  QRMasterActionCode.swift
//  BoardCore
//

import Foundation

/// Kody szybkich akcji w rozgrywce (9001–9003).
enum QRMasterActionCode: String, CaseIterable, Identifiable {
    case skipTurn = "9001"
    case showItems = "9002"
    case showAbilities = "9003"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .skipTurn: "Pomiń turę"
        case .showItems: "Pokaż przedmioty"
        case .showAbilities: "Twoje Umiejętności"
        }
    }

    static func parse(_ raw: String) -> QRMasterActionCode? {
        if let id = QRCodeParser.normalizedID(from: raw),
           let action = QRMasterActionCode(rawValue: id) {
            return action
        }

        let alias = QRCodeParser.normalizedAlias(from: raw)
        switch alias {
        case "9001", "POMINTURE", "SKIPTURN", "SKIP":
            return .skipTurn
        case "9002", "PRZEDMIOTY", "PREDMIOTY", "SHOWITEMS", "ITEMS", "POKAZPRZEDMIOTY":
            return .showItems
        case "9003", "ZDOLNOSCI", "TWOJEZDOLNOSCI", "ABILITIES", "SHOWABILITIES", "SKILLS":
            return .showAbilities
        default:
            break
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed == "DMD://9001" || trimmed == "DMD:9001" { return .skipTurn }
        if trimmed == "DMD://9002" || trimmed == "DMD:9002" { return .showItems }
        if trimmed == "DMD://9003" || trimmed == "DMD:9003" { return .showAbilities }
        return nil
    }
}

enum QRGameplayScanResult: Equatable {
    case gameEvent(QRGameEventCode)
    case masterAction(QRMasterActionCode)
    case powerPathSkill(PowerPathSkillID)
}

enum QRGameplayScanParser {
    static func parse(_ raw: String) -> QRGameplayScanResult? {
        if let action = QRMasterActionCode.parse(raw) {
            return .masterAction(action)
        }
        if let skill = PowerPathQRCodes.skill(fromScanned: raw) {
            return .powerPathSkill(skill)
        }
        if let event = QRGameEventCode.fromScannedCode(raw) {
            return .gameEvent(event)
        }
        return nil
    }

    static func matches(_ raw: String) -> Bool {
        parse(raw) != nil
    }
}

enum QRScannerContext {
    case lobbyPlayer
    case passiveGameplay

    var title: String {
        switch self {
        case .lobbyPlayer: "Skanuj gracza"
        case .passiveGameplay: "Monitor QR"
        }
    }

    var manualPlaceholder: String {
        switch self {
        case .lobbyPlayer: "np. 4001"
        case .passiveGameplay: "np. 2002"
        }
    }

    func accepts(_ raw: String) -> Bool {
        switch self {
        case .lobbyPlayer:
            return QRLobbyScanParser.matches(raw)
        case .passiveGameplay:
            return QRGameplayScanParser.matches(raw)
        }
    }
}

enum QRLobbyScanParser {
    static func parsePlayerSlot(_ raw: String) -> PlayerSlotCode? {
        PlayerSlotCode.fromScannedCode(raw)
    }

    static func matches(_ raw: String) -> Bool {
        parsePlayerSlot(raw) != nil
    }
}
