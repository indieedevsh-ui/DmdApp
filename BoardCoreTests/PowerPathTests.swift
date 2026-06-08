//
//  PowerPathTests.swift
//  BoardCoreTests
//

import Foundation
import Testing
@testable import BoardCore

struct PowerPathTests {
    @Test func startFieldVisitOpensEverySecondTime() {
        var progress: [UUID: PlayerPowerPathProgress] = [:]
        let id = UUID()

        let first = PowerPathEngine.recordStartFieldVisit(playerID: id, progress: &progress)
        #expect(first.shouldOpenPowerPath == false)
        #expect(first.visitCount == 1)
        #expect(progress[id]?.experiencePoints == PowerPathEngine.xpPerStartFieldVisit)

        let second = PowerPathEngine.recordStartFieldVisit(playerID: id, progress: &progress)
        #expect(second.shouldOpenPowerPath == true)
        #expect(second.visitCount == 2)
    }

    @Test func unlockRequiresChosenPath() {
        var progress: [UUID: PlayerPowerPathProgress] = [:]
        let id = UUID()
        progress[id] = PlayerPowerPathProgress(experiencePoints: 50)

        #expect(progress[id]?.canUnlock(.benevolent) == false)
        _ = PowerPathEngine.unlockPath(side: .light, playerID: id, progress: &progress)
        #expect(progress[id]?.chosenSide == .light)
        #expect(progress[id]?.canUnlock(.benevolent) == true)

        var stats: PlayerRuntimeStats? = PlayerRuntimeStats(
            finances: 100,
            health: 80,
            strength: PlayerRuntimeStats.startingStrength,
            abilities: 0
        )
        _ = PowerPathEngine.unlock(
            skill: .benevolent,
            playerID: id,
            progress: &progress,
            runtimeStats: &stats
        )
        #expect(progress[id]?.hasUnlocked(.benevolent) == true)
        #expect(stats?.strength == PlayerRuntimeStats.startingStrength + PowerPathEngine.skillUnlockStrengthBonus)
        #expect(stats?.health == 80 + PowerPathEngine.skillUnlockHealthBonus)

        var noStats: PlayerRuntimeStats?
        let darkResult = PowerPathEngine.unlock(
            skill: .darkAura,
            playerID: id,
            progress: &progress,
            runtimeStats: &noStats
        )
        #expect(darkResult?.contains("innej ścieżki") == true)
        #expect(progress[id]?.hasUnlocked(.darkAura) == false)
    }

    @Test func cannotPickSecondPath() {
        var progress: [UUID: PlayerPowerPathProgress] = [:]
        let id = UUID()
        _ = PowerPathEngine.unlockPath(side: .dark, playerID: id, progress: &progress)
        let message = PowerPathEngine.unlockPath(side: .light, playerID: id, progress: &progress)
        #expect(message?.contains("jedną") == true)
        #expect(progress[id]?.chosenSide == .dark)
    }

    @Test func startFieldGrantsTenXP() {
        #expect(PowerPathXPReward.startField == 10)
        #expect(PowerPathEngine.xpPerStartFieldVisit == 10)
    }

    @Test func bossVictoryXPByDifficulty() {
        #expect(PowerPathXPReward.bossFightVictory(difficulty: .easy) == 20)
        #expect(PowerPathXPReward.bossFightVictory(difficulty: .medium) == 40)
        #expect(PowerPathXPReward.bossFightVictory(difficulty: .hard) == 80)
    }

    @Test func negativeSpecialCardXPDoesNotGoBelowZero() {
        var progress: [UUID: PlayerPowerPathProgress] = [:]
        let id = UUID()
        progress[id] = PlayerPowerPathProgress(experiencePoints: 8)

        let card = SpecialCardDefinition.allCards.first { !$0.isPositive }!
        let applied = PowerPathEngine.grantSpecialCardExperience(
            card: card,
            playerID: id,
            progress: &progress
        )
        #expect(progress[id]?.experiencePoints == 0)
        #expect(applied == -8)
    }

    @Test func positiveSpecialCardGrantsTwentyXP() {
        var progress: [UUID: PlayerPowerPathProgress] = [:]
        let id = UUID()
        let card = SpecialCardDefinition.allCards.first { $0.isPositive }!
        let applied = PowerPathEngine.grantSpecialCardExperience(
            card: card,
            playerID: id,
            progress: &progress
        )
        #expect(applied == 20)
        #expect(progress[id]?.experiencePoints == 20)
    }

    @Test func lapUsageResetsAndPreventsStacking() {
        var usage: [UUID: PlayerLapAbilityUsage] = [:]
        let id = UUID()

        #expect(LapAbilityUsageEngine.markUsedPowerPath(.darkAura, playerID: id, usage: &usage))
        #expect(LapAbilityUsageEngine.hasUsedPowerPath(.darkAura, playerID: id, in: usage))
        #expect(!LapAbilityUsageEngine.markUsedPowerPath(.darkAura, playerID: id, usage: &usage))

        LapAbilityUsageEngine.resetLap(for: id, usage: &usage)
        #expect(!LapAbilityUsageEngine.hasUsedPowerPath(.darkAura, playerID: id, in: usage))
    }

    @Test func curseHalvesNextReward() {
        var progress: [UUID: PlayerPowerPathProgress] = [:]
        let casterID = UUID()
        let victimID = UUID()
        progress[casterID] = PlayerPowerPathProgress(cursedPlayerIDs: [victimID])

        let (coins, message) = PowerPathEngine.applyRewardMultiplier(
            playerID: victimID,
            baseCoins: 200,
            progress: &progress
        )
        #expect(coins == 100)
        #expect(message != nil)
        #expect(progress[casterID]?.cursedPlayerIDs.contains(victimID) == false)
    }
}
