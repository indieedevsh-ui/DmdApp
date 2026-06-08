//
//  LapAbilityUsage.swift
//  BoardCore
//

import Foundation

/// Zużycie umiejętności w bieżącym okrążeniu (reset po przejściu przez pole start).
struct PlayerLapAbilityUsage: Codable, Equatable {
    var usedPowerPathSkills: Set<PowerPathSkillID> = []
    var usedSessionAbilityIDs: Set<UUID> = []
}

enum LapAbilityUsageEngine {
    static func progress(for playerID: UUID, in map: [UUID: PlayerLapAbilityUsage]) -> PlayerLapAbilityUsage {
        map[playerID] ?? PlayerLapAbilityUsage()
    }

    static func resetLap(for playerID: UUID, usage: inout [UUID: PlayerLapAbilityUsage]) {
        usage[playerID] = PlayerLapAbilityUsage()
    }

    static func hasUsedPowerPath(
        _ skill: PowerPathSkillID,
        playerID: UUID,
        in usage: [UUID: PlayerLapAbilityUsage]
    ) -> Bool {
        progress(for: playerID, in: usage).usedPowerPathSkills.contains(skill)
    }

    static func hasUsedSessionAbility(
        _ abilityID: UUID,
        playerID: UUID,
        in usage: [UUID: PlayerLapAbilityUsage]
    ) -> Bool {
        progress(for: playerID, in: usage).usedSessionAbilityIDs.contains(abilityID)
    }

    @discardableResult
    static func markUsedPowerPath(
        _ skill: PowerPathSkillID,
        playerID: UUID,
        usage: inout [UUID: PlayerLapAbilityUsage]
    ) -> Bool {
        var playerUsage = progress(for: playerID, in: usage)
        guard !playerUsage.usedPowerPathSkills.contains(skill) else { return false }
        playerUsage.usedPowerPathSkills.insert(skill)
        usage[playerID] = playerUsage
        return true
    }

    @discardableResult
    static func markUsedSessionAbility(
        _ abilityID: UUID,
        playerID: UUID,
        usage: inout [UUID: PlayerLapAbilityUsage]
    ) -> Bool {
        var playerUsage = progress(for: playerID, in: usage)
        guard !playerUsage.usedSessionAbilityIDs.contains(abilityID) else { return false }
        playerUsage.usedSessionAbilityIDs.insert(abilityID)
        usage[playerID] = playerUsage
        return true
    }
}

extension PowerPathSkillID {
    /// Pasywna — działa bez przycisku w „Twoje Zdolności”.
    var isPassiveInGameplay: Bool {
        switch self {
        case .shadow, .benevolent, .protection:
            return true
        case .darkAura, .curse, .healing:
            return false
        }
    }

    /// Można aktywować ręcznie z ekranu zdolności (raz na okrążenie).
    var isActivatablePerLap: Bool {
        switch self {
        case .darkAura, .curse, .healing:
            return true
        case .shadow, .benevolent, .protection:
            return false
        }
    }
}
