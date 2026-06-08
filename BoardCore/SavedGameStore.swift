//
//  SavedGameStore.swift
//  BoardCore
//

import Foundation
import Observation

struct SavedGameSnapshot: Codable {
    var campaignTitle: String
    var savedAt: Date
    var players: [PlayerCharacter]
    var playerStats: [String: PlayerRuntimeStats]
    var currentPlayerIndex: Int
    var roundNumber: Int
    var eventLog: [GameEventLogEntry]
    var lastTurnMessage: String
    var sceneIndex: Int
    var decisionIndex: Int
    /// Indeks sceny per gracz (klucz = UUID gracza) — osobne ścieżki fabularne.
    var playerSceneIndices: [String: Int] = [:]
    var selectedChoices: [String: String]
    var interpretation: String
    var lastEventCode: String?
    var pendingStartFieldChoice: Bool = false
    var awaitingStartPassDecisions: Bool = false
    var showingStartStayReward: Bool = false
    var startFieldHealthBefore: Int?
    var startFieldHealthAfter: Int?
    var showingStartPassCoinReward: Bool = false
    var startFieldFinancesBefore: Int?
    var startFieldFinancesAfter: Int?
    /// ID zdolności z kreatora przyznanych graczom (klucz = UUID gracza).
    var playerGrantedAbilityIDs: [String: [UUID]] = [:]
    /// ID przedmiotów z kreatora przyznanych graczom (klucz = UUID gracza).
    var playerGrantedItemIDs: [String: [UUID]] = [:]
    /// Założony ekwipunek: gracz → kategoria → ID przedmiotu.
    var playerEquippedItems: [String: [String: UUID]] = [:]
    /// Aktualna wartość rynkowa posiadanych przedmiotów (gracz → przedmiot → monety).
    var playerOwnedItemValues: [String: [String: Int]] = [:]
    /// Pozostałe tury blokady kolejki (klucz = UUID gracza).
    var playerQueueBlockRounds: [String: Int] = [:]
    var isBossFightActive: Bool = false
    var campaignStoryFinished: Bool = false
    var pendingFinalTurn: Bool = false
    var finalTurnEndAfterPlayerIndex: Int = 0
    var finalTurnRoundActive: Bool = false
    var sessionAbilityGoalReachedOrder: [String] = []
    var sessionWinnerPlayerID: String?
    var sessionEndPhase: String = SessionEndPhase.none.rawValue
    var sessionAbilityPool: GameplaySessionAbilityPoolState?
    var playerBoardPositions: [String: Int] = [:]
    var activeTurnDamageEffects: [ActiveTurnDamageEffect] = []
    var activeTemporaryBoosts: [String: [ActiveTemporaryBoost]] = [:]
    /// Liczba ukończonych walk z bossami (klucz = UUID gracza).
    var playerBossFightCounts: [String: Int] = [:]
    /// Postęp Ścieżki Mocy (klucz = UUID gracza).
    var playerPowerPathProgress: [String: PlayerPowerPathProgress] = [:]
    /// Zużycie zdolności w bieżącym okrążeniu (klucz = UUID gracza).
    var playerLapAbilityUsage: [String: PlayerLapAbilityUsage] = [:]

    func stats(for playerID: UUID) -> PlayerRuntimeStats? {
        playerStats[playerID.uuidString]
    }

    func grantedAbilityIDs(for playerID: UUID) -> [UUID] {
        playerGrantedAbilityIDs[playerID.uuidString] ?? []
    }

    func grantedItemIDs(for playerID: UUID) -> [UUID] {
        playerGrantedItemIDs[playerID.uuidString] ?? []
    }

    func ownedItemValues(for playerID: UUID) -> [UUID: Int] {
        guard let stored = playerOwnedItemValues[playerID.uuidString] else { return [:] }
        var values: [UUID: Int] = [:]
        for (key, value) in stored {
            if let itemID = UUID(uuidString: key) {
                values[itemID] = value
            }
        }
        return values
    }

    func queueBlockRounds(for playerID: UUID) -> Int {
        playerQueueBlockRounds[playerID.uuidString] ?? 0
    }

    func bossFightCount(for playerID: UUID) -> Int {
        playerBossFightCounts[playerID.uuidString] ?? 0
    }

    func playerSceneIndex(for playerID: UUID, fallback: Int = 0) -> Int {
        playerSceneIndices[playerID.uuidString] ?? fallback
    }
}

@MainActor
@Observable
final class SavedGameStore {
    private static let hasSaveKey = "hasSavedGame"
    private static let saveFileName = "savedGame.json"

    private(set) var hasSavedGame = false
    private(set) var lastSavedAt: Date?
    private(set) var lastSavedCampaignTitle = ""

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        hasSavedGame = FileManager.default.fileExists(atPath: saveFileURL.path)
        if hasSavedGame, let snapshot = load() {
            lastSavedAt = snapshot.savedAt
            lastSavedCampaignTitle = snapshot.campaignTitle
        } else {
            lastSavedAt = nil
            lastSavedCampaignTitle = ""
        }
    }

    func save(_ snapshot: SavedGameSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try FileManager.default.createDirectory(
                at: saveFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: saveFileURL, options: .atomic)
            UserDefaults.standard.set(true, forKey: Self.hasSaveKey)
            hasSavedGame = true
            lastSavedAt = snapshot.savedAt
            lastSavedCampaignTitle = snapshot.campaignTitle
        } catch {
            UserDefaults.standard.set(false, forKey: Self.hasSaveKey)
            hasSavedGame = false
        }
    }

    func load() -> SavedGameSnapshot? {
        guard let data = try? Data(contentsOf: saveFileURL) else { return nil }
        return try? JSONDecoder().decode(SavedGameSnapshot.self, from: data)
    }

    func clearSave() {
        try? FileManager.default.removeItem(at: saveFileURL)
        UserDefaults.standard.set(false, forKey: Self.hasSaveKey)
        hasSavedGame = false
        lastSavedAt = nil
        lastSavedCampaignTitle = ""
    }

    private var saveFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Game/\(Self.saveFileName)")
    }
}
