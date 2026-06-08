//
//  PowerPathModels.swift
//  BoardCore
//

import Foundation

enum PowerPathSide: String, Codable, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: "Mroczny Użytkownik"
        case .light: "Bohater Światła"
        }
    }

    var icon: String {
        switch self {
        case .dark: "moon.stars.fill"
        case .light: "sun.max.fill"
        }
    }

    var accentSymbol: String {
        switch self {
        case .dark: "🌑"
        case .light: "☀️"
        }
    }

    var magicKindTitle: String {
        switch self {
        case .dark: "Magia Mroku"
        case .light: "Magia Światła"
        }
    }

}

enum PowerPathSkillID: String, Codable, CaseIterable, Identifiable {
    case darkAura
    case curse
    case shadow
    case benevolent
    case protection
    case healing

    var id: String { rawValue }

    var side: PowerPathSide {
        switch self {
        case .darkAura, .curse, .shadow: .dark
        case .benevolent, .protection, .healing: .light
        }
    }

    var tier: Int {
        switch self {
        case .darkAura, .benevolent: 1
        case .curse, .protection: 2
        case .shadow, .healing: 3
        }
    }

    var xpCost: Int {
        switch self {
        case .darkAura: 60
        case .benevolent: 50
        case .curse: 110
        case .protection: 110
        case .shadow, .healing: 260
        }
    }

    var title: String {
        switch self {
        case .darkAura: "Mroczna Aura"
        case .curse: "Klątwa"
        case .shadow: "Cień"
        case .benevolent: "Dobroduszny"
        case .protection: "Ochrona"
        case .healing: "Uzdrowienie"
        }
    }

    var summary: String {
        switch self {
        case .darkAura:
            "Masz 40% szans na okradnięcie gracza który jest na tym samym polu co ty. Możliwe jest okradnięcie losowo od 10-30% funduszy gracza."
        case .curse:
            "Następna nagroda wybranego przeciwnika jest o połowę mniejsza."
        case .shadow:
            "Po utracie zdrowia: 80% szans na zabranie 10% zdrowia każdemu innemu graczowi. +25% skuteczności kradzieży."
        case .benevolent:
            "Raz na turę: 30% szans na +100 monet. Szansa udanego okradania ciebie spada do 20%."
        case .protection:
            "Ignorujesz negatywny efekt wylosowanej karty specjalnej."
        case .healing:
            "Po przegranej walce: zapłać 2% finansów, by odzyskać 100% zdrowia. Dodatkowo −20% szansy okradania."
        }
    }

    var qrPayload: String? {
        switch self {
        case .darkAura: PowerPathQRCodes.darkAura
        case .curse: PowerPathQRCodes.curse
        case .shadow: PowerPathQRCodes.shadow
        default: nil
        }
    }

    static func skills(for side: PowerPathSide) -> [PowerPathSkillID] {
        allCases.filter { $0.side == side }.sorted { $0.tier < $1.tier }
    }
}

enum PowerPathQRCodes {
    static let darkAura = "POWER-DARK-AURA"
    static let curse = "POWER-DARK-CURSE"
    static let shadow = "POWER-DARK-SHADOW"

    static func skill(fromScanned payload: String) -> PowerPathSkillID? {
        let normalized = payload.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalized {
        case darkAura: return .darkAura
        case curse: return .curse
        case shadow: return .shadow
        default: return nil
        }
    }
}

struct PlayerPowerPathProgress: Codable, Equatable {
    var startFieldVisitCount: Int = 0
    var experiencePoints: Int = 0
    /// Wybrana ścieżka — tylko jedna (mrok albo światło).
    var chosenSide: PowerPathSide?
    /// Własna ścieżka z DevCentrum.
    var chosenCustomPathID: UUID?
    var unlockedCustomUpgradeIDs: Set<UUID> = []
    var unlockedSkills: Set<PowerPathSkillID> = []
    /// Tury od ostatniego użycia Mrocznej Aury (cooldown 3 tury).
    var turnsSinceDarkAuraUse: Int = 3
    var benevolentTriggeredThisTurn: Bool = false
    /// Gracze, których następna nagroda zostanie obcięta o połowę.
    var cursedPlayerIDs: Set<UUID> = []
    /// Ostatnio aktywowana umiejętność mroczna (skan QR).
    var pendingDarkActivation: PowerPathSkillID?

    func hasUnlocked(_ skill: PowerPathSkillID) -> Bool {
        unlockedSkills.contains(skill)
    }

    var hasChosenPath: Bool { chosenSide != nil || chosenCustomPathID != nil }

    func canUnlock(_ skill: PowerPathSkillID) -> Bool {
        guard let chosenSide, chosenSide == skill.side else { return false }
        guard !hasUnlocked(skill) else { return false }
        guard experiencePoints >= skill.xpCost else { return false }
        let prerequisites = PowerPathSkillID.skills(for: skill.side).filter { $0.tier < skill.tier }
        return prerequisites.allSatisfy { hasUnlocked($0) }
    }

    /// Uzupełnia `chosenSide` na podstawie już odblokowanych umiejętności (zapisane gry).
    mutating func reconcileChosenSideFromSkills() {
        guard chosenSide == nil else { return }
        let hasDark = unlockedSkills.contains { $0.side == .dark }
        let hasLight = unlockedSkills.contains { $0.side == .light }
        if hasDark, !hasLight { chosenSide = .dark }
        else if hasLight, !hasDark { chosenSide = .light }
        else if hasDark { chosenSide = .dark }
    }
}

struct PowerPathPresentation: Identifiable, Equatable {
    let id = UUID()
    let playerID: UUID
    let playerName: String
    let visitCount: Int
}

enum PowerPathXPReward {
    static let startField = 10
    static let startFieldStayFullHealth = 5
    static let artifact = 10
    static let specialCardPositive = 20
    static let specialCardNegative = 10

    static func bossFightVictory(difficulty: BossDifficulty) -> Int {
        switch difficulty {
        case .easy: 20
        case .medium: 40
        case .hard: 80
        }
    }
}

enum PowerPathEngine {
    /// XP za każde ukończone pole start (skan + rozstrzygnięcie).
    static let xpPerStartFieldVisit = PowerPathXPReward.startField
    /// Bonus do statystyk za każdą odblokowaną umiejętność (obie ścieżki).
    static let skillUnlockHealthBonus = 10
    static let skillUnlockStrengthBonus = 10

    static func applySkillUnlockStatBonus(to stats: inout PlayerRuntimeStats) {
        stats.health = min(100, stats.health + skillUnlockHealthBonus)
        stats.strength = min(100, stats.strength + skillUnlockStrengthBonus)
    }

    static func progress(for playerID: UUID, in map: [UUID: PlayerPowerPathProgress]) -> PlayerPowerPathProgress {
        map[playerID] ?? PlayerPowerPathProgress()
    }

    /// Zmiana XP (ujemna dozwolona); wynik nigdy nie spada poniżej 0.
    @discardableResult
    static func grantExperience(
        _ amount: Int,
        playerID: UUID,
        progress: inout [UUID: PlayerPowerPathProgress]
    ) -> Int {
        var playerProgress = progress[playerID] ?? PlayerPowerPathProgress()
        let before = playerProgress.experiencePoints
        playerProgress.experiencePoints = max(0, before + amount)
        progress[playerID] = playerProgress
        return playerProgress.experiencePoints - before
    }

    static func spendExperience(
        _ amount: Int,
        playerID: UUID,
        progress: inout [UUID: PlayerPowerPathProgress]
    ) -> Bool {
        guard amount > 0 else { return true }
        var playerProgress = progress[playerID] ?? PlayerPowerPathProgress()
        guard playerProgress.experiencePoints >= amount else { return false }
        playerProgress.experiencePoints -= amount
        progress[playerID] = playerProgress
        return true
    }

    @discardableResult
    static func grantArtifactExperience(
        playerID: UUID,
        progress: inout [UUID: PlayerPowerPathProgress],
        amount: Int = PowerPathXPReward.artifact
    ) -> Int {
        grantExperience(amount, playerID: playerID, progress: &progress)
    }

    @discardableResult
    static func grantBossFightVictoryExperience(
        difficulty: BossDifficulty,
        participantIDs: [UUID],
        progress: inout [UUID: PlayerPowerPathProgress]
    ) -> Int {
        let amount = PowerPathXPReward.bossFightVictory(difficulty: difficulty)
        guard amount > 0, let firstID = participantIDs.first else { return 0 }
        for id in participantIDs.dropFirst() {
            grantExperience(amount, playerID: id, progress: &progress)
        }
        return grantExperience(amount, playerID: firstID, progress: &progress)
    }

    @discardableResult
    static func grantSpecialCardExperience(
        card: SpecialCardDefinition,
        playerID: UUID,
        progress: inout [UUID: PlayerPowerPathProgress],
        positiveXP: Int = PowerPathXPReward.specialCardPositive,
        negativeXP: Int = PowerPathXPReward.specialCardNegative
    ) -> Int {
        let amount = card.isPositive ? positiveXP : -negativeXP
        return grantExperience(amount, playerID: playerID, progress: &progress)
    }

    static func experienceChangeDescription(applied: Int) -> String? {
        guard applied != 0 else { return nil }
        return applied > 0 ? "+\(applied) XP" : "\(applied) XP"
    }

    @discardableResult
    static func recordStartFieldVisit(
        playerID: UUID,
        progress: inout [UUID: PlayerPowerPathProgress],
        rules: StartFieldGameRules = StartFieldGameRules()
    ) -> (visitCount: Int, shouldOpenPowerPath: Bool) {
        var playerProgress = progress[playerID] ?? PlayerPowerPathProgress()
        playerProgress.startFieldVisitCount += 1
        playerProgress.experiencePoints += rules.xpPerVisit
        progress[playerID] = playerProgress
        let interval = max(1, rules.powerPathEveryVisits)
        let shouldOpen = playerProgress.startFieldVisitCount > 0
            && playerProgress.startFieldVisitCount.isMultiple(of: interval)
        return (playerProgress.startFieldVisitCount, shouldOpen)
    }

    static func unlockPath(
        side: PowerPathSide,
        playerID: UUID,
        progress: inout [UUID: PlayerPowerPathProgress]
    ) -> String? {
        var playerProgress = progress[playerID] ?? PlayerPowerPathProgress()
        if let chosen = playerProgress.chosenSide {
            if chosen == side {
                return "Ta ścieżka jest już aktywna."
            }
            return "Możesz mieć tylko jedną ścieżkę mocy."
        }
        if playerProgress.chosenCustomPathID != nil {
            return "Możesz mieć tylko jedną ścieżkę mocy."
        }
        playerProgress.chosenSide = side
        progress[playerID] = playerProgress
        return "Odblokowano ścieżkę: \(side.title)."
    }

    static func unlock(
        skill: PowerPathSkillID,
        playerID: UUID,
        progress: inout [UUID: PlayerPowerPathProgress],
        runtimeStats: inout PlayerRuntimeStats?
    ) -> String? {
        var playerProgress = progress[playerID] ?? PlayerPowerPathProgress()
        guard let chosenSide = playerProgress.chosenSide else {
            return "Najpierw odblokuj ścieżkę mocy."
        }
        guard skill.side == chosenSide else {
            return "Ta umiejętność należy do innej ścieżki."
        }
        guard playerProgress.canUnlock(skill) else {
            if playerProgress.hasUnlocked(skill) { return "Umiejętność jest już odblokowana." }
            if playerProgress.experiencePoints < skill.xpCost {
                return "Potrzebujesz \(skill.xpCost) XP (masz \(playerProgress.experiencePoints))."
            }
            return "Najpierw odblokuj wcześniejszą umiejętność na tej ścieżce."
        }
        playerProgress.experiencePoints -= skill.xpCost
        playerProgress.unlockedSkills.insert(skill)
        progress[playerID] = playerProgress

        if var stats = runtimeStats {
            applySkillUnlockStatBonus(to: &stats)
            runtimeStats = stats
        }

        let statBonusNote = " +\(skillUnlockStrengthBonus) siły, +\(skillUnlockHealthBonus) zdrowia"
        if let qr = skill.qrPayload {
            return "Odblokowano „\(skill.title)”.\(statBonusNote) Kod QR: \(qr)"
        }
        return "Odblokowano „\(skill.title)”.\(statBonusNote)"
    }

    // MARK: - Light path

    static func processTurnStart(
        playerID: UUID,
        progress: inout [UUID: PlayerPowerPathProgress]
    ) -> (message: String?, coinBonus: Int)? {
        var playerProgress = progress[playerID] ?? PlayerPowerPathProgress()
        playerProgress.benevolentTriggeredThisTurn = false
        defer { progress[playerID] = playerProgress }

        guard playerProgress.hasUnlocked(.benevolent) else { return nil }
        guard Double.random(in: 0..<1) < 0.30 else { return nil }

        playerProgress.benevolentTriggeredThisTurn = true
        return (message: "Dobroduszny: +100 monet (szczęście w tej turze).", coinBonus: 100)
    }

    static func robberySuccessChance(
        againstVictimID: UUID,
        progress: [UUID: PlayerPowerPathProgress]
    ) -> Double {
        let victim = progress[againstVictimID] ?? PlayerPowerPathProgress()
        var chance = 1.0
        if victim.hasUnlocked(.benevolent) {
            chance = 0.20
        }
        if victim.hasUnlocked(.healing) {
            chance = max(0.05, chance - 0.20)
        }
        return chance
    }

    static func shouldIgnoreNegativeSpecialCard(playerID: UUID, card: SpecialCardDefinition, progress: [UUID: PlayerPowerPathProgress]) -> Bool {
        guard !card.isPositive else { return false }
        return progress[playerID]?.hasUnlocked(.protection) == true
    }

    static func isPlayerCursedForNextCoinReward(
        playerID: UUID,
        progress: [UUID: PlayerPowerPathProgress]
    ) -> Bool {
        progress.values.contains { $0.cursedPlayerIDs.contains(playerID) }
    }

    static func clearCurseForNextCoinReward(
        playerID: UUID,
        progress: inout [UUID: PlayerPowerPathProgress]
    ) {
        for id in progress.keys {
            var playerProgress = progress[id] ?? PlayerPowerPathProgress()
            playerProgress.cursedPlayerIDs.remove(playerID)
            progress[id] = playerProgress
        }
    }

    static func applyRewardMultiplier(
        playerID: UUID,
        baseCoins: Int,
        progress: inout [UUID: PlayerPowerPathProgress]
    ) -> (coins: Int, message: String?) {
        guard baseCoins > 0 else { return (baseCoins, nil) }
        guard isPlayerCursedForNextCoinReward(playerID: playerID, progress: progress) else {
            return (baseCoins, nil)
        }
        clearCurseForNextCoinReward(playerID: playerID, progress: &progress)
        return (max(0, baseCoins / 2), "Klątwa: nagroda o połowę mniejsza.")
    }

    static func offerPostFightHealing(
        playerID: UUID,
        progress: [UUID: PlayerPowerPathProgress],
        stats: inout PlayerRuntimeStats,
        accept: Bool
    ) -> String? {
        guard progress[playerID]?.hasUnlocked(.healing) == true else { return nil }
        guard accept else { return nil }
        let cost = max(1, Int(Double(stats.finances) * 0.02))
        guard stats.finances >= cost else { return "Za mało monet na uzdrowienie (2% finansów)." }
        stats.finances -= cost
        stats.health = 100
        return "Uzdrowienie: −\(cost) monet, pełne zdrowie."
    }

    // MARK: - Dark path

    static func tickTurnCooldowns(progress: inout [UUID: PlayerPowerPathProgress]) {
        for id in progress.keys {
            var p = progress[id] ?? PlayerPowerPathProgress()
            if p.turnsSinceDarkAuraUse < 3 {
                p.turnsSinceDarkAuraUse += 1
            }
            progress[id] = p
        }
    }

    struct DarkAuraTheftResult: Equatable {
        let message: String
        let victimID: UUID
    }

    static func tryDarkAuraTheft(
        actorID: UUID,
        players: [PlayerCharacter],
        positions: [UUID: Int],
        stats: inout [UUID: PlayerRuntimeStats],
        progress: inout [UUID: PlayerPowerPathProgress],
        lapUsage: inout [UUID: PlayerLapAbilityUsage]
    ) -> DarkAuraTheftResult? {
        var actorProgress = progress[actorID] ?? PlayerPowerPathProgress()
        guard actorProgress.hasUnlocked(.darkAura) else { return nil }
        guard !LapAbilityUsageEngine.hasUsedPowerPath(.darkAura, playerID: actorID, in: lapUsage) else {
            return nil
        }

        guard let actorPosition = positions[actorID] else { return nil }
        let victims = players.filter {
            $0.id != actorID && positions[$0.id] == actorPosition
        }
        guard let victim = victims.randomElement() else { return nil }
        let successChance = 0.40 * darkAuraTheftSuccessBonus(progress: progress, actorID: actorID)
        guard Double.random(in: 0..<1) < successChance else { return nil }

        guard var victimStats = stats[victim.id], var actorStats = stats[actorID] else { return nil }
        let fraction = Double.random(in: 0.10...0.30)
        let stolen = max(1, Int(Double(victimStats.finances) * fraction))
        victimStats.finances = max(0, victimStats.finances - stolen)
        actorStats.finances += stolen
        stats[victim.id] = victimStats
        stats[actorID] = actorStats

        _ = LapAbilityUsageEngine.markUsedPowerPath(.darkAura, playerID: actorID, usage: &lapUsage)
        progress[actorID] = actorProgress

        return DarkAuraTheftResult(
            message: "Mroczna Aura: zabrano \(stolen) monet od \(victim.displayTitle).",
            victimID: victim.id
        )
    }

    static func applyShadowAfterHealthLoss(
        playerID: UUID,
        players: [PlayerCharacter],
        stats: inout [UUID: PlayerRuntimeStats],
        progress: [UUID: PlayerPowerPathProgress]
    ) -> String? {
        guard progress[playerID]?.hasUnlocked(.shadow) == true else { return nil }
        guard Double.random(in: 0..<1) < 0.80 else { return nil }

        var lines: [String] = []
        for other in players where other.id != playerID {
            guard var otherStats = stats[other.id] else { continue }
            let drain = max(1, Int(Double(otherStats.health) * 0.10))
            otherStats.health = max(0, otherStats.health - drain)
            stats[other.id] = otherStats
            lines.append("\(other.displayTitle) −\(drain) HP")
        }
        guard !lines.isEmpty else { return nil }
        return "Cień: \(lines.joined(separator: ", "))."
    }

    static func darkAuraTheftSuccessBonus(progress: [UUID: PlayerPowerPathProgress], actorID: UUID) -> Double {
        progress[actorID]?.hasUnlocked(.shadow) == true ? 1.25 : 1.0
    }

    static func activateCurse(
        casterID: UUID,
        targetID: UUID,
        progress: inout [UUID: PlayerPowerPathProgress]
    ) -> String? {
        guard var caster = progress[casterID], caster.hasUnlocked(.curse) else {
            return "Nie masz odblokowanej Klątwy."
        }
        caster.cursedPlayerIDs.insert(targetID)
        progress[casterID] = caster
        return "Klątwa nałożona — następna nagroda celu będzie o połowę mniejsza."
    }

    static func registerDarkQRActivation(
        playerID: UUID,
        skill: PowerPathSkillID,
        progress: inout [UUID: PlayerPowerPathProgress]
    ) -> String? {
        guard skill.side == .dark else { return nil }
        var playerProgress = progress[playerID] ?? PlayerPowerPathProgress()
        guard playerProgress.hasUnlocked(skill) else {
            return "Najpierw odblokuj „\(skill.title)” na Ścieżce Mocy."
        }
        playerProgress.pendingDarkActivation = skill
        progress[playerID] = playerProgress
        return "Aktywowano „\(skill.title)” — efekt przy najbliższej okazji."
    }
}
