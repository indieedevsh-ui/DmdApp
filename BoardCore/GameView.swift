//
//  GameView.swift
//  BoardCore
//

import SwiftUI

private enum GameLobbyMode {
    case chooseStart
    case newGameLobby
}

struct GameView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(CampaignStore.self) private var campaignStore
    @Environment(SavedGameStore.self) private var savedGameStore
    @Environment(CreatorStore.self) private var creatorStore
    @Environment(PlayerSlotStore.self) private var playerSlotStore
    @Environment(TrikiNavigationCoordinator.self) private var trikiCoordinator

    private let lobbyTrikiFocusID = UUID()
    @State private var lobbyMode: GameLobbyMode = .newGameLobby
    @State private var session = GameSession()
    @State private var showQRScanner = false
    @State private var gameStarted = false
    @State private var restoredSnapshot: SavedGameSnapshot?
    @State private var invalidCodeAlert = false
    @State private var characterSetupSlot: PlayerSlotCode?
    @State private var scannedRawCode = ""
    @State private var playerAddedOverlayName: String?

    private var requiresPlayableCampaign: Bool {
        settings.effectiveCampaignsEnabled
    }

    private var canStartOrLoadGame: Bool {
        !requiresPlayableCampaign || campaignStore.hasPlayableCampaign
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch lobbyMode {
                    case .chooseStart:
                        chooseStartSection
                    case .newGameLobby:
                        if requiresPlayableCampaign {
                            campaignSection
                        }
                        playersSection
                        addPlayerSection
                        startGameSection
                        if savedGameStore.hasSavedGame {
                            backToChooseButton
                        }
                    }
                }
                .padding()
            }
            .appScrollSurface()

            if let overlayName = playerAddedOverlayName {
                PlayerAddedOverlay(playerName: overlayName) {
                    playerAddedOverlayName = nil
                }
            }
        }
        .navigationTitle(lobbyMode == .chooseStart ? "Graj" : "Gracze")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $gameStarted) {
            GameInProgressView(
                campaign: campaignStore.parsedCampaign,
                campaignsEnabled: settings.effectiveCampaignsEnabled,
                players: session.players,
                restoredSnapshot: restoredSnapshot
            )
        }
        .sheet(isPresented: $showQRScanner) {
            QRCodeScannerView(context: .lobbyPlayer) { code in
                handleScannedCode(code)
            }
            .environment(settings)
        }
        .alert("Nieznany kod QR", isPresented: $invalidCodeAlert) {
            Button("OK", role: .cancel) {
                settings.playTapSound()
            }
        } message: {
            Text("Kod „\(scannedRawCode)” nie pasuje do gracza (4001–4004 / gracz 1–4).")
        }
        .fullScreenCover(item: $characterSetupSlot) { slot in
            NavigationStack {
                PlayerSlotCharacterSetupView(slot: slot) {
                    completeCharacterSetup(for: slot)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Zamknij") {
                            settings.playTapSound()
                            characterSetupSlot = nil
                        }
                    }
                }
            }
        }
        .onAppear {
            savedGameStore.refreshStatus()
            lobbyMode = savedGameStore.hasSavedGame ? .chooseStart : .newGameLobby
        }
        .background(Color.clear)
        .appThemedScreen()
        .toolbar(playerAddedOverlayName != nil ? .hidden : .visible, for: .tabBar)
        .appCartoonTabBarVisible(playerAddedOverlayName == nil && characterSetupSlot == nil)
        .trikiFocusContext(
            id: lobbyTrikiFocusID,
            buttons: lobbyTrikiButtons,
            onActivate: { activateLobbyTriki(at: $0) }
        )
    }

    private var lobbyTrikiButtons: [TrikiFocusButton] {
        switch lobbyMode {
        case .chooseStart:
            return [
                TrikiFocusButton(id: "load", title: "Wczytaj zapis"),
                TrikiFocusButton(id: "new", title: "Rozpocznij nową grę")
            ]
        case .newGameLobby:
            var buttons = [
                TrikiFocusButton(id: "scan", title: "Skanuj QR lub numer z kartki"),
                TrikiFocusButton(id: "start", title: "Rozpocznij grę")
            ]
            if savedGameStore.hasSavedGame {
                buttons.append(TrikiFocusButton(id: "back", title: "Wróć do wyboru zapisu"))
            }
            return buttons
        }
    }

    private func activateLobbyTriki(at index: Int) {
        let buttons = lobbyTrikiButtons
        guard buttons.indices.contains(index) else { return }
        settings.playTapSound()
        switch buttons[index].id {
        case "load":
            guard canStartOrLoadGame else { return }
            restoredSnapshot = savedGameStore.load()
            gameStarted = true
        case "new":
            lobbyMode = .newGameLobby
            restoredSnapshot = nil
            session.reset()
        case "scan":
            showQRScanner = true
        case "start":
            guard session.canStartGame, canStartOrLoadGame else { return }
            restoredSnapshot = nil
            gameStarted = true
        case "back":
            lobbyMode = .chooseStart
        default:
            break
        }
        trikiCoordinator.statusMessage = "Wciśnięto: \(buttons[index].title)"
    }

    private var chooseStartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Kontynuuj rozgrywkę")
                .font(.title2.bold())

            if let date = savedGameStore.lastSavedAt {
                Text("Zapis: \(savedGameStore.lastSavedCampaignTitle)")
                    .font(.headline)
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                settings.playTapSound()
                restoredSnapshot = savedGameStore.load()
                gameStarted = true
            } label: {
                Label("Wczytaj zapis", systemImage: "arrow.clockwise.circle.fill")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.appProminent)
            .disabled(!canStartOrLoadGame)

            Button {
                settings.playTapSound()
                lobbyMode = .newGameLobby
                restoredSnapshot = nil
                session.reset()
            } label: {
                Label("Rozpocznij nową grę", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.appSecondary)

            if requiresPlayableCampaign, !campaignStore.hasPlayableCampaign {
                Text("Brak zapisanej kampanii — wgraj ją w zakładce Kampanie.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var backToChooseButton: some View {
        Button {
            settings.playTapSound()
            lobbyMode = .chooseStart
        } label: {
            Label("Wróć do wyboru zapisu", systemImage: "chevron.backward")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.appSecondary)
    }

    private var campaignSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kampania")
                .font(.title2.bold())

            if campaignStore.hasPlayableCampaign {
                Text(campaignStore.title)
                    .font(.headline)
                Text("\(campaignStore.parsedCampaign.scenes.count) scen · \(campaignStore.parsedCampaign.decisions.count) decyzji")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Brak zapisanej kampanii.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Wgraj kampanię w zakładce Kampanie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Dodani gracze")
                    .font(.title2.bold())
                Spacer()
                Text("\(session.players.count)")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }

            if session.players.isEmpty {
                ContentUnavailableView(
                    "Brak graczy",
                    systemImage: "person.3.fill",
                    description: Text("Dodaj co najmniej 2 graczy, aby rozpocząć rozgrywkę.")
                )
                .frame(maxWidth: .infinity)
            } else {
                ForEach(session.players) { player in
                    PlayerCharacterRow(player: player)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .contextMenu {
                            Button("Usuń gracza", role: .destructive) {
                                settings.playTapSound()
                                session.removePlayer(id: player.id)
                            }
                        }
                }
            }
        }
    }

    private var addPlayerSection: some View {
        VStack(spacing: 12) {
            Button {
                settings.playTapSound()
                showQRScanner = true
            } label: {
                Label("Skanuj QR lub numer z kartki", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.appProminent)
        }
    }

    private var startGameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                settings.playTapSound()
                restoredSnapshot = nil
                gameStarted = true
            } label: {
                Text("Rozpocznij grę")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.appProminent)
            .disabled(!session.canStartGame || !canStartOrLoadGame)

            if requiresPlayableCampaign, !campaignStore.hasPlayableCampaign {
                Text("Najpierw wgraj i zapisz kampanię w zakładce Kampanie.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !session.canStartGame {
                Text("Potrzebujesz jeszcze \(max(0, 2 - session.players.count)) gracza(y), aby zacząć.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func handleScannedCode(_ raw: String) {
        scannedRawCode = raw

        if let slot = PlayerSlotCode.fromScannedCode(raw) {
            handlePlayerSlotScan(slot)
            return
        }

        invalidCodeAlert = true
    }

    private func handlePlayerSlotScan(_ slot: PlayerSlotCode) {
        characterSetupSlot = slot
    }

    private func completeCharacterSetup(for slot: PlayerSlotCode) {
        guard let player = playerSlotStore.playerCharacter(for: slot) else { return }
        session.addOrReplacePlayer(fromSlot: slot.rawValue, player: player)
        playerAddedOverlayName = player.displayTitle
        characterSetupSlot = nil
    }
}

struct GameInProgressView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerSlotStore.self) private var playerSlotStore
    @Environment(GameplayThinkingService.self) private var thinkingService
    @Environment(SavedGameStore.self) private var savedGameStore
    @Environment(CreatorStore.self) private var creatorStore
    @Environment(TrikiNavigationCoordinator.self) private var trikiCoordinator

    private let gameTrikiFocusID = UUID()

    let campaign: ParsedCampaign
    let campaignsEnabled: Bool
    let restoredSnapshot: SavedGameSnapshot?

    @State private var players: [PlayerCharacter]
    @State private var playerStats: [UUID: PlayerRuntimeStats]
    @State private var turnState = GameTurnState()
    @State private var sceneIndex = 0
    @State private var decisionIndex = 0
    @State private var playerSceneIndices: [UUID: Int] = [:]
    @State private var selectedChoices: [UUID: String] = [:]
    @State private var recommendations: [UUID: MasterChoiceRecommendation] = [:]
    @State private var interpretation = ""
    @State private var lastEventResult: QRGameEventCode?
    @State private var lastSpecialCardDetail = ""
    @State private var lastArtifactDetail = ""
    @State private var saveConfirmation = false
    @State private var startFieldPhase: StartFieldOverlayPhase = .hidden
    @State private var skipTurnPlayerName: String?
    @State private var turnChangePresentation: TurnChangePresentation?
    /// Skan QR włączony dopiero po zakończeniu animacji „kto ma turę”.
    @State private var canScanGameplayQR = false
    @State private var pendingEventIntro: QRGameEventCode?
    @State private var specialCardDrawSession: SpecialCardDrawSession?
    @State private var artifactDrawSession: ArtifactDrawSession?
    @State private var shopPhase: ShopOverlayPhase = .hidden
    @State private var shopStockItems: [CreatedItem] = []
    @State private var xpShopPhase: XPShopOverlayPhase = .hidden
    @State private var pendingXpShopRoll: XPShopPendingRoll?
    @State private var pendingFinalTurn = false
    @State private var finalTurnEndAfterPlayerIndex = 0
    @State private var finalTurnRoundActive = false
    @State private var showFinalTurnIntro = false
    @State private var sessionAbilityGoalReachedOrder: [UUID] = []
    @State private var sessionWinnerPlayerID: UUID?
    @State private var sessionEndPhase: SessionEndPhase = .none
    @State private var pendingPassChoiceText = ""
    @State private var startFieldStayTurnPending = false
    @State private var playerGrantedAbilityIDs: [UUID: [UUID]] = [:]
    @State private var playerGrantedItemIDs: [UUID: [UUID]] = [:]
    @State private var playerEquippedItems: PlayerEquipmentMap = [:]
    @State private var playerOwnedItemValues: [UUID: [UUID: Int]] = [:]
    @State private var playerQueueBlockRounds: [UUID: Int] = [:]
    @State private var isBossFightActive = false
    @State private var lastAbilityOutcome = ""
    @State private var fallenPlayerQueue: [PlayerFallenSummary] = []
    @State private var pendingEliminationIDs: Set<UUID> = []
    @State private var playerBossFightCounts: [UUID: Int] = [:]
    @State private var bossVictoryPresentation: BossFightVictoryPresentation?
    @State private var campaignStoryFinished = false
    @State private var inGameScreen: InGameScreen = .gameplay
    @State private var showBossFightAR = false
    @State private var showArenaPvPAR = false
    @State private var isArenaPvPActive = false
    @State private var sessionAbilityPool = GameplaySessionAbilityPoolState(abilities: [])
    @State private var playerBoardPositions: [UUID: Int] = [:]
    @State private var activeTurnDamageEffects: [ActiveTurnDamageEffect] = []
    @State private var activeTemporaryBoosts: [UUID: [ActiveTemporaryBoost]] = [:]
    @State private var pendingAbilityUse: PendingSessionAbilityUse?
    @State private var showPlayerItemsOverlay = false
    @State private var showPlayerStatsOverlay = false
    @State private var showSessionAbilitiesOverlay = false
    @State private var showYourSkillsOverlay = false
    @State private var powerPathSkillUsePresentation: PowerPathSkillUsePresentation?
    @State private var specialCardDrawRevealed = false
    @State private var artifactDrawRevealed = false
    @State private var playerPowerPathProgress: [UUID: PlayerPowerPathProgress] = [:]
    @State private var playerLapAbilityUsage: [UUID: PlayerLapAbilityUsage] = [:]
    @State private var powerPathPresentation: PowerPathPresentation?
    @State private var powerPathPendingAction: PowerPathPendingAction = .none
    @State private var pendingHealingPlayerID: UUID?
    @State private var showHealingOfferAlert = false
    @State private var showGameplayStartIntro: Bool
    @State private var financesChangePresentation: FinancesChangePresentation?
    @State private var pendingFinancesChangeAnimations: [FinancesChangePresentation] = []
    @State private var turnGlowColor = PlayerGlowColor(
        red: AppSettings.defaultBackgroundRed,
        green: AppSettings.defaultBackgroundGreen,
        blue: AppSettings.defaultBackgroundBlue,
        opacity: AppSettings.defaultBackgroundOpacity
    )
    @State private var pendingTrikiBossMove: BossClashMove?
    @State private var powerPathTrikiCatalog: [PowerPathTrikiRow] = []
    @State private var powerPathTrikiActivationTrigger = 0

    private enum FinancesAnimationPolicy {
        case automatic
        case suppressed
    }

    private enum XPShopCost {
        static let fiftyFifty = 80
        static let randomAbility = 250
    }

    private enum XPShopPendingRoll: Equatable {
        case fiftyFifty(XPShopFiftyFiftyRoll)
        case randomAbility(XPShopRandomAbilityRoll)
    }

    private enum PowerPathPendingAction: Equatable {
        case none
        case advanceTurnAfterStay
        case completeStartPassCoin(playerID: UUID)
        case completeStartPass(playerID: UUID, choice: String)
    }

    private enum InGameScreen: String, CaseIterable, Identifiable {
        case gameplay
        case campaignEnd

        var id: String { rawValue }

        var title: String {
            switch self {
            case .gameplay: "Gra"
            case .campaignEnd: "Koniec gry"
            }
        }
    }

    private enum TrikiSelectableButton: Hashable {
        case showStats
        case showItems
        case showAbilities
        case skipTurn
        case saveGame
        case ability(UUID)
        case bossEnterAR
        case bossEndFight
        case startFieldStay
        case startFieldPass
        case startFieldChoice(Int)
        case overlayContinue
        case queueSkipTurn
        case shopBuy
        case shopSell
        case shopBack
        case shopExit
        case shopPurchase(UUID)
        case shopSellItem(UUID)
        case powerPathOption(Int)
        case equipmentToggle(UUID)
        case equipmentExit
        case statsExit
        case abilitiesExit
        case finishCampaign
        case switchToGameplayTab
    }

    private func trikiButtonTitle(_ button: TrikiSelectableButton) -> String {
        switch button {
        case .showStats: return "Pokaż Statystyki"
        case .showItems: return "Pokaż przedmioty"
        case .showAbilities: return "Zdolności"
        case .skipTurn: return "Pomiń turę"
        case .saveGame: return "Zapisz grę"
        case .ability: return "Użyj zdolności"
        case .bossEnterAR: return "Wejdź do trybu AR"
        case .bossEndFight: return "Zakończ walkę z bossem"
        case .startFieldStay: return "Jestem na start"
        case .startFieldPass: return "Przechodzę przez start"
        case .startFieldChoice(let index):
            let labels = contextualStartField.choiceLabels
            if labels.indices.contains(index) {
                return labels[index]
            }
            return "Wybór \(index + 1)"
        case .overlayContinue: return "Kontynuuj"
        case .queueSkipTurn: return "Pomiń turę"
        case .shopBuy: return "Kup"
        case .shopSell: return "Sprzedaj"
        case .shopBack: return "Wróć"
        case .shopExit: return "Wyjdź ze sklepu"
        case .shopPurchase(let id):
            return shopStockItems.first(where: { $0.id == id })?.name ?? "Kup przedmiot"
        case .shopSellItem(let id):
            return ownedShopItems.first(where: { $0.id == id })?.name ?? "Sprzedaj przedmiot"
        case .powerPathOption(let index):
            if powerPathTrikiCatalog.indices.contains(index) {
                return powerPathTrikiCatalog[index].title
            }
            return "Ścieżka mocy"
        case .equipmentToggle(let id):
            return ownedShopItems.first(where: { $0.id == id })?.name ?? "Przedmiot"
        case .equipmentExit:
            return "Wyjdź"
        case .statsExit:
            return "Wyjdź"
        case .abilitiesExit:
            return "Wyjdź"
        case .finishCampaign:
            return "Zakończ"
        case .switchToGameplayTab:
            return "Gra"
        }
    }

    private struct SpecialCardDrawSession {
        let player: PlayerCharacter
        let card: SpecialCardDefinition
    }

    private struct ArtifactDrawSession {
        let player: PlayerCharacter
        let outcome: ArtifactOutcome
    }

    init(
        campaign: ParsedCampaign,
        campaignsEnabled: Bool,
        players: [PlayerCharacter],
        restoredSnapshot: SavedGameSnapshot? = nil
    ) {
        self.campaign = campaign
        self.campaignsEnabled = campaignsEnabled
        self.restoredSnapshot = restoredSnapshot
        _showGameplayStartIntro = State(initialValue: restoredSnapshot == nil)

        if let snapshot = restoredSnapshot {
            _players = State(initialValue: snapshot.players)
            var stats: [UUID: PlayerRuntimeStats] = [:]
            for player in snapshot.players {
                stats[player.id] = snapshot.stats(for: player.id) ?? .defaultStarting
            }
            _playerStats = State(initialValue: stats)
            _sceneIndex = State(initialValue: snapshot.sceneIndex)
            _decisionIndex = State(initialValue: snapshot.decisionIndex)
            _interpretation = State(initialValue: snapshot.interpretation)

            var choices: [UUID: String] = [:]
            for player in snapshot.players {
                if let text = snapshot.selectedChoices[player.id.uuidString] {
                    choices[player.id] = text
                }
            }
            _selectedChoices = State(initialValue: choices)

            if let code = snapshot.lastEventCode {
                _lastEventResult = State(initialValue: QRGameEventCode(rawValue: code))
            } else {
                _lastEventResult = State(initialValue: nil)
            }
            if snapshot.showingStartStayReward,
               let before = snapshot.startFieldHealthBefore,
               let after = snapshot.startFieldHealthAfter {
                _startFieldPhase = State(initialValue: .stayingReward(previousHealth: before, newHealth: after))
            } else if snapshot.showingStartPassCoinReward,
                      let before = snapshot.startFieldFinancesBefore,
                      let after = snapshot.startFieldFinancesAfter {
                _startFieldPhase = State(initialValue: .passingCoinReward(previousFinances: before, newFinances: after))
            } else if snapshot.pendingStartFieldChoice {
                _startFieldPhase = State(initialValue: .choosing)
            } else if snapshot.awaitingStartPassDecisions {
                _startFieldPhase = State(
                    initialValue: campaignsEnabled ? .passingDecisions : .hidden
                )
            } else {
                _startFieldPhase = State(initialValue: .hidden)
            }
            _playerGrantedAbilityIDs = State(
                initialValue: Self.grantedMap(from: snapshot.playerGrantedAbilityIDs)
            )
            _playerGrantedItemIDs = State(
                initialValue: Self.grantedMap(from: snapshot.playerGrantedItemIDs)
            )
            _playerEquippedItems = State(
                initialValue: PlayerEquipment.decode(from: snapshot.playerEquippedItems)
            )
            _playerOwnedItemValues = State(
                initialValue: Self.ownedItemValueMap(from: snapshot.playerOwnedItemValues)
            )
            _playerQueueBlockRounds = State(
                initialValue: Self.queueBlockMap(from: snapshot.playerQueueBlockRounds)
            )
            _isBossFightActive = State(initialValue: snapshot.isBossFightActive)
            _campaignStoryFinished = State(initialValue: snapshot.campaignStoryFinished)
            _pendingFinalTurn = State(initialValue: snapshot.pendingFinalTurn)
            _finalTurnEndAfterPlayerIndex = State(initialValue: snapshot.finalTurnEndAfterPlayerIndex)
            _finalTurnRoundActive = State(initialValue: snapshot.finalTurnRoundActive)
            _showFinalTurnIntro = State(initialValue: false)
            _sessionAbilityGoalReachedOrder = State(
                initialValue: snapshot.sessionAbilityGoalReachedOrder.compactMap(UUID.init(uuidString:))
            )
            _sessionWinnerPlayerID = State(
                initialValue: snapshot.sessionWinnerPlayerID.flatMap(UUID.init(uuidString:))
            )
            _sessionEndPhase = State(
                initialValue: {
                    let phase = SessionEndPhase(rawValue: snapshot.sessionEndPhase) ?? .none
                    if snapshot.campaignStoryFinished, phase == .none {
                        return .rankings
                    }
                    return phase
                }()
            )
            _inGameScreen = State(
                initialValue: snapshot.campaignStoryFinished ? .campaignEnd : .gameplay
            )
            _sessionAbilityPool = State(
                initialValue: snapshot.sessionAbilityPool
                    ?? GameplaySessionAbilityFactory.makePool(elements: CreatorCatalog.defaultElementNames)
            )
            _playerBoardPositions = State(
                initialValue: Self.boardPositionMap(from: snapshot.playerBoardPositions)
            )
            _activeTurnDamageEffects = State(initialValue: snapshot.activeTurnDamageEffects)
            _activeTemporaryBoosts = State(
                initialValue: Self.temporaryBoostMap(from: snapshot.activeTemporaryBoosts)
            )
            _playerBossFightCounts = State(
                initialValue: Self.bossFightCountMap(from: snapshot.playerBossFightCounts)
            )
            _playerPowerPathProgress = State(
                initialValue: Self.powerPathProgressMap(from: snapshot.playerPowerPathProgress)
            )
            _playerLapAbilityUsage = State(
                initialValue: Self.lapAbilityUsageMap(from: snapshot.playerLapAbilityUsage)
            )
            _playerSceneIndices = State(
                initialValue: Self.playerSceneIndexMap(
                    from: snapshot.playerSceneIndices,
                    players: snapshot.players,
                    fallbackSceneIndex: snapshot.sceneIndex,
                    sharedStart: campaign.sharedStartSceneIndex
                )
            )
        } else {
            _players = State(initialValue: players)
            var stats: [UUID: PlayerRuntimeStats] = [:]
            for player in players {
                stats[player.id] = PlayerRuntimeStats.initial(for: player)
            }
            _playerStats = State(initialValue: stats)
            _playerGrantedAbilityIDs = State(initialValue: [:])
            _playerGrantedItemIDs = State(initialValue: [:])
            _playerEquippedItems = State(initialValue: [:])
            _playerOwnedItemValues = State(initialValue: [:])
            _playerQueueBlockRounds = State(initialValue: [:])
            _isBossFightActive = State(initialValue: false)
            let pool = GameplaySessionAbilityFactory.makePool(
                elements: CreatorCatalog.defaultElementNames
            )
            _sessionAbilityPool = State(initialValue: pool)
            var board: [UUID: Int] = [:]
            for player in players {
                board[player.id] = 0
            }
            _playerBoardPositions = State(initialValue: board)
            _activeTurnDamageEffects = State(initialValue: [])
            _activeTemporaryBoosts = State(initialValue: [:])
            var sceneMap: [UUID: Int] = [:]
            let start = campaign.sharedStartSceneIndex
            for player in players {
                sceneMap[player.id] = start
            }
            _playerSceneIndices = State(initialValue: sceneMap)
            _sceneIndex = State(initialValue: start)
        }
    }

    private static func playerSceneIndexMap(
        from stored: [String: Int],
        players: [PlayerCharacter],
        fallbackSceneIndex: Int,
        sharedStart: Int
    ) -> [UUID: Int] {
        var map: [UUID: Int] = [:]
        for player in players {
            if let value = stored[player.id.uuidString] {
                map[player.id] = value
            } else {
                map[player.id] = fallbackSceneIndex
            }
        }
        if map.isEmpty {
            for player in players {
                map[player.id] = sharedStart
            }
        }
        return map
    }

    private func sceneIndex(for player: PlayerCharacter) -> Int {
        playerSceneIndices[player.id] ?? campaign.sharedStartSceneIndex
    }

    private func activePlayerSceneIndex() -> Int {
        guard let activePlayer else { return campaign.sharedStartSceneIndex }
        return sceneIndex(for: activePlayer)
    }

    private func ensurePlayerSceneIndices() {
        let start = campaign.sharedStartSceneIndex
        for player in players where playerSceneIndices[player.id] == nil {
            playerSceneIndices[player.id] = start
        }
    }

    private static func boardPositionMap(from stored: [String: Int]) -> [UUID: Int] {
        var map: [UUID: Int] = [:]
        for (key, value) in stored {
            if let id = UUID(uuidString: key) {
                map[id] = value
            }
        }
        return map
    }

    private static func powerPathProgressMap(from stored: [String: PlayerPowerPathProgress]) -> [UUID: PlayerPowerPathProgress] {
        var result: [UUID: PlayerPowerPathProgress] = [:]
        for (key, value) in stored {
            if let id = UUID(uuidString: key) {
                result[id] = value
            }
        }
        return result
    }

    private static func lapAbilityUsageMap(from stored: [String: PlayerLapAbilityUsage]) -> [UUID: PlayerLapAbilityUsage] {
        var result: [UUID: PlayerLapAbilityUsage] = [:]
        for (key, value) in stored {
            if let id = UUID(uuidString: key) {
                result[id] = value
            }
        }
        return result
    }

    private static func bossFightCountMap(from stored: [String: Int]) -> [UUID: Int] {
        var map: [UUID: Int] = [:]
        for (key, value) in stored {
            if let id = UUID(uuidString: key) {
                map[id] = value
            }
        }
        return map
    }

    private static func temporaryBoostMap(from stored: [String: [ActiveTemporaryBoost]]) -> [UUID: [ActiveTemporaryBoost]] {
        var map: [UUID: [ActiveTemporaryBoost]] = [:]
        for (key, value) in stored {
            if let id = UUID(uuidString: key) {
                map[id] = value
            }
        }
        return map
    }

    private static func grantedMap(from stored: [String: [UUID]]) -> [UUID: [UUID]] {
        var map: [UUID: [UUID]] = [:]
        for (key, value) in stored {
            if let id = UUID(uuidString: key) {
                map[id] = value
            }
        }
        return map
    }

    private static func queueBlockMap(from stored: [String: Int]) -> [UUID: Int] {
        var map: [UUID: Int] = [:]
        for (key, value) in stored {
            if let id = UUID(uuidString: key), value > 0 {
                map[id] = value
            }
        }
        return map
    }

    private static func ownedItemValueMap(from stored: [String: [String: Int]]) -> [UUID: [UUID: Int]] {
        var map: [UUID: [UUID: Int]] = [:]
        for (playerKey, itemValues) in stored {
            guard let playerID = UUID(uuidString: playerKey) else { continue }
            var values: [UUID: Int] = [:]
            for (itemKey, value) in itemValues {
                if let itemID = UUID(uuidString: itemKey) {
                    values[itemID] = value
                }
            }
            if !values.isEmpty {
                map[playerID] = values
            }
        }
        return map
    }

    private static func ownedItemValueStorage(from map: [UUID: [UUID: Int]]) -> [String: [String: Int]] {
        Dictionary(
            uniqueKeysWithValues: map.map { playerEntry in
                (
                    playerEntry.key.uuidString,
                    Dictionary(uniqueKeysWithValues: playerEntry.value.map { ($0.key.uuidString, $0.value) })
                )
            }
        )
    }

    private var activePlayerIndex: Int { turnState.currentPlayerIndex }

    private var activePlayer: PlayerCharacter? {
        turnState.currentPlayer(in: players)
    }

    private var activeStats: PlayerRuntimeStats? {
        guard let activePlayer else { return nil }
        return effectiveStats(for: activePlayer.id)
    }

    private func effectiveStats(for playerID: UUID) -> PlayerRuntimeStats? {
        guard let base = playerStats[playerID] else { return nil }
        return PlayerEquipment.effectiveRuntimeStats(
            base: base,
            for: playerID,
            equipment: playerEquippedItems,
            catalog: creatorStore.catalog.items
        )
    }

    private var resolvedDecisionIndex: Int {
        decisionIndex
    }

    private var currentScene: CampaignScene? {
        guard let activePlayer else {
            return campaign.scenes[safe: sceneIndex]
        }
        return campaign.scenes[safe: sceneIndex(for: activePlayer)]
    }

    private var currentDecision: CampaignDecision? {
        guard let activePlayer else {
            return campaign.decisions[safe: decisionIndex]
        }
        let idx = campaign.resolvedDecisionIndex(
            forSceneIndex: sceneIndex(for: activePlayer),
            fallback: decisionIndex
        )
        return campaign.decisions[safe: idx]
    }

    private var isStartFieldOverlayVisible: Bool {
        startFieldPhase != .hidden
    }

    private var isSkipTurnOverlayVisible: Bool {
        skipTurnPlayerName != nil
    }

    private var isTurnChangeOverlayVisible: Bool {
        turnChangePresentation != nil
    }

    private var isEventIntroVisible: Bool {
        pendingEventIntro != nil
    }

    private var isSpecialCardDrawVisible: Bool {
        specialCardDrawSession != nil
    }

    private var isArtifactDrawVisible: Bool {
        artifactDrawSession != nil
    }

    private var activeQueueBlockRounds: Int {
        guard let activePlayer else { return 0 }
        return playerQueueBlockRounds[activePlayer.id] ?? 0
    }

    private var isQueueBlockedOverlayVisible: Bool {
        !isSpecialCardDrawVisible
            && !isArtifactDrawVisible
            && activeQueueBlockRounds > 0
            && !isTurnChangeOverlayVisible
            && canScanGameplayQR
    }

    private var isShopOverlayVisible: Bool {
        shopPhase != .hidden
    }

    private var isXpShopOverlayVisible: Bool {
        xpShopPhase != .hidden
    }

    private var isXpShopDrawing: Bool {
        switch xpShopPhase {
        case .drawingFiftyFifty, .drawingRandomAbility:
            return true
        default:
            return false
        }
    }

    private var isXpShopResultReady: Bool {
        switch xpShopPhase {
        case .revealedFiftyFifty, .revealedRandomAbility:
            return true
        default:
            return false
        }
    }

    private var passiveQRMonitorEnabled: Bool {
        inGameScreen == .gameplay
            && !campaignStoryFinished
            && !showGameplayStartIntro
            && canScanGameplayQR
    }

    private var trikiSelectableButtons: [TrikiSelectableButton] {
        if showBossFightAR || showArenaPvPAR || pendingAbilityUse != nil {
            return []
        }
        if isStartFieldOverlayVisible {
            return startFieldTrikiButtons
        }
        if isShopOverlayVisible {
            return shopTrikiButtons
        }
        if isXpShopOverlayVisible {
            if isXpShopDrawing { return [] }
            if isXpShopResultReady { return [.overlayContinue] }
            return [.overlayContinue]
        }
        if showPlayerStatsOverlay {
            return [.statsExit]
        }
        if showSessionAbilitiesOverlay {
            return [.abilitiesExit]
        }
        if showYourSkillsOverlay {
            return [.abilitiesExit]
        }
        if showPlayerItemsOverlay {
            return equipmentTrikiButtons
        }
        if isPowerPathOverlayVisible {
            return powerPathTrikiButtons
        }
        if showFinalTurnIntro {
            return []
        }
        if pendingEventIntro != nil {
            return [.overlayContinue]
        }
        if isSkipTurnOverlayVisible || isTurnChangeOverlayVisible {
            return [.overlayContinue]
        }
        if showGameplayStartIntro {
            return [.overlayContinue]
        }
        if financesChangePresentation != nil {
            return [.overlayContinue]
        }
        if bossVictoryPresentation != nil {
            return [.overlayContinue]
        }
        if isSpecialCardDrawVisible, specialCardDrawRevealed {
            return [.overlayContinue]
        }
        if isArtifactDrawVisible, artifactDrawRevealed {
            return [.overlayContinue]
        }
        if isQueueBlockedOverlayVisible {
            return [.queueSkipTurn]
        }
        if !fallenPlayerQueue.isEmpty {
            return [.overlayContinue]
        }
        if isSpecialCardDrawVisible && !specialCardDrawRevealed {
            return []
        }
        if isArtifactDrawVisible && !artifactDrawRevealed {
            return []
        }
        if inGameScreen == .campaignEnd {
            var buttons: [TrikiSelectableButton] = [.switchToGameplayTab, .finishCampaign]
            if !campaignsEnabled {
                buttons = [.finishCampaign]
            }
            return buttons
        }
        return defaultTrikiGameplayButtons
    }

    private var trikiFocusButtons: [TrikiFocusButton] {
        trikiSelectableButtons.enumerated().map { index, button in
            TrikiFocusButton(id: trikiFocusButtonID(button, index: index), title: trikiButtonTitle(button))
        }
    }

    private func trikiFocusButtonID(_ button: TrikiSelectableButton, index: Int) -> String {
        switch button {
        case .showStats: return "showStats"
        case .showItems: return "showItems"
        case .showAbilities: return "showAbilities"
        case .skipTurn: return "skipTurn"
        case .saveGame: return "saveGame"
        case .ability(let id): return "ability-\(id.uuidString)"
        case .bossEnterAR: return "bossEnterAR"
        case .bossEndFight: return "bossEndFight"
        case .startFieldStay: return "startStay"
        case .startFieldPass: return "startPass"
        case .startFieldChoice(let i): return "choice-\(i)"
        case .overlayContinue: return "overlayContinue"
        case .queueSkipTurn: return "queueSkip"
        case .shopBuy: return "shopBuy"
        case .shopSell: return "shopSell"
        case .shopBack: return "shopBack"
        case .shopExit: return "shopExit"
        case .shopPurchase(let id): return "buy-\(id.uuidString)"
        case .shopSellItem(let id): return "sell-\(id.uuidString)"
        case .powerPathOption(let i): return "power-\(i)"
        case .equipmentToggle(let id): return "equip-\(id.uuidString)"
        case .equipmentExit: return "equipExit"
        case .statsExit: return "statsExit"
        case .abilitiesExit: return "abilitiesExit"
        case .finishCampaign: return "finishCampaign"
        case .switchToGameplayTab: return "switchGameplay"
        }
    }

    private var powerPathTrikiButtons: [TrikiSelectableButton] {
        powerPathTrikiCatalog.indices.map { .powerPathOption($0) }
    }

    private var equipmentTrikiButtons: [TrikiSelectableButton] {
        var buttons = ownedShopItems
            .filter { $0.resolvedItemKind.isEquippable }
            .map { TrikiSelectableButton.equipmentToggle($0.id) }
        buttons.append(.equipmentExit)
        return buttons
    }

    private var trikiNavigationContextID: String {
        [
            String(showPlayerItemsOverlay),
            String(showPlayerStatsOverlay),
            String(showSessionAbilitiesOverlay),
            String(showYourSkillsOverlay),
            String(isPowerPathOverlayVisible),
            powerPathTrikiCatalog.map(\.id).joined(separator: ","),
            String(bossVictoryPresentation != nil),
            String(isSpecialCardDrawVisible),
            String(specialCardDrawRevealed),
            String(isArtifactDrawVisible),
            String(artifactDrawRevealed),
            String(isStartFieldOverlayVisible),
            String(describing: startFieldPhase),
            String(describing: shopPhase),
            String(isQueueBlockedOverlayVisible),
            String(fallenPlayerQueue.count),
            String(pendingEventIntro != nil),
            String(isSkipTurnOverlayVisible),
            String(isTurnChangeOverlayVisible),
            String(showGameplayStartIntro),
            String(financesChangePresentation != nil),
            String(isBossFightActive),
            String(activeQueueBlockRounds),
            String(showBossFightAR),
            String(pendingAbilityUse != nil),
            String(inGameScreen == .campaignEnd)
        ].joined(separator: "|")
    }

    private var startFieldTrikiButtons: [TrikiSelectableButton] {
        switch startFieldPhase {
        case .hidden:
            return []
        case .choosing:
            return [.startFieldStay, .startFieldPass]
        case .stayingReward, .stayingFullHealthReward, .passingCoinReward, .choiceEffectsReveal:
            return [.overlayContinue]
        case .passingDecisions:
            return contextualStartField.choiceLabels.indices.map { .startFieldChoice($0) }
        }
    }

    private var shopTrikiButtons: [TrikiSelectableButton] {
        switch shopPhase {
        case .hidden:
            return []
        case .menu:
            return [.shopBuy, .shopSell, .shopExit]
        case .buy:
            var buttons = shopStockItems.map { TrikiSelectableButton.shopPurchase($0.id) }
            buttons.append(contentsOf: [.shopBack, .shopExit])
            return buttons
        case .sell:
            var buttons = ownedShopItems.map { TrikiSelectableButton.shopSellItem($0.id) }
            buttons.append(contentsOf: [.shopBack, .shopExit])
            return buttons
        }
    }

    private var defaultTrikiGameplayButtons: [TrikiSelectableButton] {
        var buttons: [TrikiSelectableButton] = [.showStats, .showItems, .showAbilities]
        if activeQueueBlockRounds == 0 {
            buttons.append(.skipTurn)
        }
        buttons.append(.saveGame)
        if isBossFightActive {
            buttons.append(contentsOf: [.bossEnterAR, .bossEndFight])
        }
        return buttons
    }

    private var selectedTrikiButton: TrikiSelectableButton {
        let buttons = trikiSelectableButtons
        guard !buttons.isEmpty else { return .skipTurn }
        let idx = trikiCoordinator.highlightIndex ?? 0
        return buttons[min(max(0, idx), buttons.count - 1)]
    }

    private var trikiHighlightIndexInContext: Int? {
        guard settings.trikiControllerEnabled else { return nil }
        return trikiCoordinator.highlightIndex
    }

    private var trikiHoldChargeProgress: Double {
        trikiCoordinator.holdChargeProgress
    }

    private func reconcileTrikiSelection(resetToFirst: Bool = false) {
        trikiCoordinator.reconcileSelection(resetToFirst: resetToFirst)
    }

    private var isPowerPathOverlayVisible: Bool {
        powerPathPresentation != nil
    }

    private var isFullScreenOverlayVisible: Bool {
        isStartFieldOverlayVisible
            || isSkipTurnOverlayVisible
            || isTurnChangeOverlayVisible
            || isEventIntroVisible
            || showFinalTurnIntro
            || isSpecialCardDrawVisible
            || isArtifactDrawVisible
            || isQueueBlockedOverlayVisible
            || isShopOverlayVisible
            || isXpShopOverlayVisible
            || !fallenPlayerQueue.isEmpty
            || bossVictoryPresentation != nil
            || isPowerPathOverlayVisible
            || showSessionAbilitiesOverlay
            || showYourSkillsOverlay
            || powerPathSkillUsePresentation != nil
    }

    private func ownedItemIDs(for playerID: UUID) -> [UUID] {
        playerGrantedItemIDs[playerID] ?? []
    }

    private func equippedItemIDs(for playerID: UUID) -> Set<UUID> {
        Set((playerEquippedItems[playerID] ?? [:]).values)
    }

    private func playerSlot(for player: PlayerCharacter) -> PlayerSlotCode? {
        guard let slot = player.lobbySlotNumber else { return nil }
        return PlayerSlotCode(rawValue: slot)
    }

    private func toggleEquipItem(
        _ item: CreatedItem,
        for playerID: UUID
    ) -> EquipmentStatBoostPresentation? {
        let catalog = creatorStore.catalog.items
        let kind = item.resolvedItemKind
        guard kind == .weapon || kind == .armor else {
            switch PlayerEquipment.toggleEquip(
                item,
                for: playerID,
                ownedItemIDs: ownedItemIDs(for: playerID),
                equipment: &playerEquippedItems
            ) {
            case .success(let equipped):
                settings.playTapSound()
                logEquipEvent(item: item, equipped: equipped, playerID: playerID)
            case .failure:
                break
            }
            return nil
        }

        guard let base = playerStats[playerID] else { return nil }
        let beforeEffective = PlayerEquipment.effectiveRuntimeStats(
            base: base,
            for: playerID,
            equipment: playerEquippedItems,
            catalog: catalog
        )

        switch PlayerEquipment.toggleEquip(
            item,
            for: playerID,
            ownedItemIDs: ownedItemIDs(for: playerID),
            equipment: &playerEquippedItems
        ) {
        case .success(let equipped):
            settings.playTapSound()
            logEquipEvent(item: item, equipped: equipped, playerID: playerID)
            guard equipped else { return nil }

            let afterEffective = PlayerEquipment.effectiveRuntimeStats(
                base: base,
                for: playerID,
                equipment: playerEquippedItems,
                catalog: catalog
            )
            let delta = EquipmentLoadoutBonus(
                health: afterEffective.health - beforeEffective.health,
                strength: afterEffective.strength - beforeEffective.strength,
                armor: 0
            )
            guard delta.health > 0 || delta.strength > 0 else { return nil }
            return EquipmentStatBoostPresentation(item: item, delta: delta)
        case .failure:
            return nil
        }
    }

    private func logEquipEvent(item: CreatedItem, equipped: Bool, playerID: UUID) {
        let verb = equipped ? "Założono" : "Zdjęto"
        if let player = players.first(where: { $0.id == playerID }) {
            turnState.logCustomEvent(
                playerName: player.className,
                message: "\(verb): \(item.name) (\(item.resolvedItemKind.displayName))."
            )
        }
    }

    private func unequipIfNeeded(itemID: UUID, for playerID: UUID) {
        guard let item = creatorStore.catalog.items.first(where: { $0.id == itemID }) else { return }
        if PlayerEquipment.isEquipped(item, playerID: playerID, equipment: playerEquippedItems) {
            PlayerEquipment.unequip(kind: item.resolvedItemKind, for: playerID, equipment: &playerEquippedItems)
        }
    }

    private var ownedShopItems: [CreatedItem] {
        guard let activePlayer else { return [] }
        return deduplicatedItems(from: ownedCatalogItems(for: activePlayer.id))
    }

    private func ownedCatalogItems(for playerID: UUID) -> [CreatedItem] {
        let ids = playerGrantedItemIDs[playerID] ?? []
        return ids.compactMap { id in
            creatorStore.catalog.items.first { $0.id == id }
        }
    }

    private func deduplicatedItems(from items: [CreatedItem]) -> [CreatedItem] {
        var seenNumericIDs = Set<String>()
        return items.filter { item in
            guard !seenNumericIDs.contains(item.numericId) else { return false }
            seenNumericIDs.insert(item.numericId)
            return true
        }
    }

    private func playerOwnsShopItem(_ item: CreatedItem, playerID: UUID) -> Bool {
        ownedCatalogItems(for: playerID).contains { $0.numericId == item.numericId }
    }

    private func addOwnedShopItem(_ item: CreatedItem, for playerID: UUID) {
        guard !playerOwnsShopItem(item, playerID: playerID) else { return }
        var owned = playerGrantedItemIDs[playerID] ?? []
        guard !owned.contains(item.id) else { return }
        owned.append(item.id)
        playerGrantedItemIDs[playerID] = owned
        PlayerOwnedItemValues.setValue(
            item.cost,
            playerID: playerID,
            itemID: item.id,
            values: &playerOwnedItemValues
        )
    }

    private func effectiveItemValue(_ item: CreatedItem, for playerID: UUID) -> Int {
        PlayerOwnedItemValues.effectiveValue(
            catalogCost: item.cost,
            playerID: playerID,
            itemID: item.id,
            values: playerOwnedItemValues
        )
    }

    private func fluctuateOwnedItemValuesOnTurnAdvance() {
        PlayerOwnedItemValues.fluctuateOnTurnAdvance(
            ownership: playerGrantedItemIDs,
            itemsCatalog: creatorStore.catalog.items,
            values: &playerOwnedItemValues
        )
    }

    private func syncOwnedItemValues(for playerID: UUID, previousItemIDs: [UUID], newItemIDs: [UUID]) {
        let previous = Set(previousItemIDs)
        let updated = Set(newItemIDs)

        for itemID in updated.subtracting(previous) {
            let catalogCost = creatorStore.catalog.items.first { $0.id == itemID }?.cost ?? 1
            PlayerOwnedItemValues.setValue(
                catalogCost,
                playerID: playerID,
                itemID: itemID,
                values: &playerOwnedItemValues
            )
        }

        for itemID in previous.subtracting(updated) {
            PlayerOwnedItemValues.removeItem(
                playerID: playerID,
                itemID: itemID,
                values: &playerOwnedItemValues
            )
        }
    }

    private var shouldAnimateFinancesChangesAutomatically: Bool {
        !isStartFieldOverlayVisible
            && !showBossFightAR
            && !showArenaPvPAR
            && !isBossFightActive
            && !isArenaPvPActive
            && bossVictoryPresentation == nil
            && !isArtifactDrawVisible
            && !isSpecialCardDrawVisible
    }

    private func queueFinancesChangeAnimation(delta: Int) {
        guard delta != 0 else { return }
        let presentation = FinancesChangePresentation(delta: delta)
        if financesChangePresentation == nil {
            financesChangePresentation = presentation
        } else {
            pendingFinancesChangeAnimations.append(presentation)
        }
    }

    private func advanceFinancesChangeQueue() {
        financesChangePresentation = nil
        guard !pendingFinancesChangeAnimations.isEmpty else { return }
        financesChangePresentation = pendingFinancesChangeAnimations.removeFirst()
    }

    private func applyFinancesDelta(
        _ delta: Int,
        for playerID: UUID,
        financesAnimation: FinancesAnimationPolicy = .automatic
    ) {
        guard delta != 0, var stats = playerStats[playerID] else { return }
        var actualDelta = delta
        if delta > 0 {
            let (adjusted, curseMessage) = PowerPathEngine.applyRewardMultiplier(
                playerID: playerID,
                baseCoins: delta,
                progress: &playerPowerPathProgress
            )
            actualDelta = adjusted
            if let curseMessage, let player = players.first(where: { $0.id == playerID }) {
                turnState.logCustomEvent(playerName: player.className, message: curseMessage)
            }
        }
        stats.finances = max(0, stats.finances + actualDelta)
        setPlayerStats(stats, for: playerID, financesAnimation: financesAnimation)
    }

    @discardableResult
    private func applyCursedCoinGain(
        _ amount: Int,
        to playerID: UUID,
        stats: inout PlayerRuntimeStats
    ) -> String? {
        guard amount > 0 else { return nil }
        let (adjusted, curseMessage) = PowerPathEngine.applyRewardMultiplier(
            playerID: playerID,
            baseCoins: amount,
            progress: &playerPowerPathProgress
        )
        stats.finances = min(9999, stats.finances + adjusted)
        if let curseMessage, let player = players.first(where: { $0.id == playerID }) {
            turnState.logCustomEvent(playerName: player.className, message: curseMessage)
        }
        return curseMessage
    }

    private func reconcileCoinGainWithCurse(
        playerID: UUID,
        beforeFinances: Int,
        stats: inout PlayerRuntimeStats
    ) {
        let gain = stats.finances - beforeFinances
        guard gain > 0 else { return }
        stats.finances = beforeFinances
        _ = applyCursedCoinGain(gain, to: playerID, stats: &stats)
    }

    private func setPlayerStats(
        _ stats: PlayerRuntimeStats,
        for playerID: UUID,
        financesAnimation: FinancesAnimationPolicy = .automatic
    ) {
        let previousHealth = playerStats[playerID]?.health
        let previousFinances = playerStats[playerID]?.finances
        var updated = stats
        updated.health = min(100, max(0, updated.health))
        updated.finances = max(0, updated.finances)
        playerStats[playerID] = updated

        if financesAnimation == .automatic,
           shouldAnimateFinancesChangesAutomatically,
           let previousFinances,
           updated.finances != previousFinances {
            let delta = updated.finances - previousFinances
            queueFinancesChangeAnimation(delta: delta)
        }

        if let previousHealth, updated.health < previousHealth {
            applyPowerPathShadowOnHealthLoss(playerID: playerID)
        }
        if updated.health <= 0 {
            queuePlayerFallen(id: playerID)
        } else {
            checkSessionWinCondition()
        }
    }

    private func syncAbilityStatCount(for playerID: UUID) {
        let count = playerGrantedAbilityIDs[playerID]?.count ?? 0
        guard var stats = playerStats[playerID] else { return }
        stats.abilities = PlayerRuntimeStats.abilityCountStat(count)
        let health = stats.health
        playerStats[playerID] = stats
        if health <= 0 {
            queuePlayerFallen(id: playerID)
        } else {
            checkSessionWinCondition()
        }
    }

    private func syncAllPlayersAbilityStatCounts() {
        for player in players {
            syncAbilityStatCount(for: player.id)
        }
    }

    private func updatePlayerFinances(
        _ finances: Int,
        for playerID: UUID,
        financesAnimation: FinancesAnimationPolicy = .automatic
    ) {
        guard var stats = playerStats[playerID] else { return }
        stats.finances = max(0, finances)
        setPlayerStats(stats, for: playerID, financesAnimation: financesAnimation)
    }

    private func buildFallenSummary(for id: UUID) -> PlayerFallenSummary? {
        guard let player = players.first(where: { $0.id == id }),
              let stats = playerStats[id] else { return nil }

        let playerNumber = player.lobbySlotNumber
            ?? (players.firstIndex(where: { $0.id == id }).map { $0 + 1 } ?? 1)
        let abilityCount = playerGrantedAbilityIDs[id]?.count ?? stats.abilities

        return PlayerFallenSummary(
            id: id,
            playerNumber: playerNumber,
            displayTitle: player.displayTitle,
            lobbySlotNumber: player.lobbySlotNumber,
            characterQRCode: player.qrCode,
            bossFightCount: playerBossFightCounts[id] ?? 0,
            abilityCount: abilityCount,
            finances: stats.finances
        )
    }

    private func queuePlayerFallen(id: UUID) {
        queuePlayersFallen(ids: [id])
    }

    private func queuePlayersFallen(ids: [UUID]) {
        let eligible = ids.filter { playerID in
            players.contains(where: { $0.id == playerID }) && !pendingEliminationIDs.contains(playerID)
        }
        guard !eligible.isEmpty else { return }

        let summaries = eligible.compactMap { buildFallenSummary(for: $0) }.shuffled()
        pendingEliminationIDs.formUnion(eligible)
        fallenPlayerQueue.append(contentsOf: summaries)
    }

    private func advanceFallenPlayerOverlay() {
        guard let current = fallenPlayerQueue.first else { return }
        fallenPlayerQueue.removeFirst()
        pendingEliminationIDs.remove(current.id)
        finalizePlayerElimination(id: current.id)

        guard fallenPlayerQueue.isEmpty else { return }

        if players.isEmpty {
            if campaignsEnabled {
                markCampaignStoryFinished()
            }
        } else {
            checkSessionWinCondition()
        }
    }

    private func recordBossFightParticipation(for ids: [UUID]) {
        for id in ids {
            playerBossFightCounts[id, default: 0] += 1
        }
    }

    private func checkSessionWinCondition() {
        guard !campaignStoryFinished else { return }
        let goal = GameplaySessionAbilityPoolState.poolSize
        var beganFinalTurn = false

        for player in players {
            let count = playerGrantedAbilityIDs[player.id]?.count ?? 0
            guard count >= goal else { continue }

            recordSessionAbilityGoalReached(by: player.id)
            guard !pendingFinalTurn else { continue }

            pendingFinalTurn = true
            finalTurnEndAfterPlayerIndex = players.firstIndex(where: { $0.id == player.id })
                ?? turnState.currentPlayerIndex
            showFinalTurnIntro = true
            beganFinalTurn = true
            turnState.logCustomEvent(
                playerName: player.className,
                message: "\(player.displayTitle) zebrał \(goal) zdolności — ostatnia tura dla wszystkich graczy.",
                turnMessage: "Ostatnia tura do zakończenia rozgrywki."
            )
        }

        if beganFinalTurn {
            syncGameplayQRScanningState()
        }
    }

    @discardableResult
    private func recordSessionAbilityGoalReached(by playerID: UUID) -> Bool {
        guard !sessionAbilityGoalReachedOrder.contains(playerID) else { return false }
        sessionAbilityGoalReachedOrder.append(playerID)
        return true
    }

    private func resolveSessionWinner() {
        let goal = GameplaySessionAbilityPoolState.poolSize
        let contenders = players.filter { player in
            (playerGrantedAbilityIDs[player.id]?.count ?? 0) >= goal
        }

        if let winner = SessionWinnerResolver.pickWinner(
            from: contenders.isEmpty
                ? players.filter { sessionAbilityGoalReachedOrder.contains($0.id) }
                : contenders,
            stats: playerStats,
            itemValuesByPlayer: ownedItemValueTotalsByPlayer,
            bossFightCounts: playerBossFightCounts,
            firstToGoalOrder: sessionAbilityGoalReachedOrder
        ) {
            sessionWinnerPlayerID = winner.id
        } else if let firstID = sessionAbilityGoalReachedOrder.first {
            sessionWinnerPlayerID = firstID
        }
    }

    private var sessionWinnerRevealDetail: String {
        let goal = GameplaySessionAbilityPoolState.poolSize
        let contenders = players.filter { (playerGrantedAbilityIDs[$0.id]?.count ?? 0) >= goal }
        if contenders.count <= 1 {
            return "Pierwszy gracz, który osiągnął \(goal) na \(goal) zdolności."
        }
        return "Wyłoniony po porównaniu: finanse (z przedmiotami), walki z bossem i siła."
    }

    private func shouldCompleteSessionAfterFinalRound() -> Bool {
        guard pendingFinalTurn, finalTurnRoundActive else { return false }
        return turnState.currentPlayerIndex == finalTurnEndAfterPlayerIndex
    }

    private func completeSessionGame() {
        pendingFinalTurn = false
        finalTurnRoundActive = false
        showFinalTurnIntro = false
        resolveSessionWinner()
        markSessionGameOver(showWinnerReveal: sessionWinnerPlayerID != nil)
    }

    private func finishFinalTurnIntro() {
        showFinalTurnIntro = false
        finalTurnRoundActive = true
        syncGameplayQRScanningState()
    }

    private func finishSessionWinnerReveal() {
        sessionEndPhase = .rankings
        settings.playStatsRevealSound()
    }

    private func finalizePlayerElimination(id: UUID) {
        guard players.contains(where: { $0.id == id }) else { return }

        guard let index = players.firstIndex(where: { $0.id == id }),
              let eliminatedPlayer = players[safe: index],
              let eliminatedStats = playerStats[id] else { return }

        let loot = eliminatedStats.finances
        let recipients = players.filter { $0.id != id }
        let shares = PlayerElimination.distributeLoot(
            amount: loot,
            among: recipients,
            stats: playerStats
        )

        for (recipientID, share) in shares where share > 0 {
            applyFinancesDelta(share, for: recipientID)
        }

        playerStats.removeValue(forKey: id)
        playerGrantedAbilityIDs.removeValue(forKey: id)
        playerGrantedItemIDs.removeValue(forKey: id)
        playerEquippedItems.removeValue(forKey: id)
        playerOwnedItemValues.removeValue(forKey: id)
        playerQueueBlockRounds.removeValue(forKey: id)
        playerBoardPositions.removeValue(forKey: id)
        activeTemporaryBoosts.removeValue(forKey: id)
        activeTurnDamageEffects.removeAll { $0.targetPlayerID == id }
        for abilityID in sessionAbilityPool.heldAbilityIDs(for: id) {
            sessionAbilityPool.consume(abilityID: abilityID, from: id)
        }
        selectedChoices.removeValue(forKey: id)
        playerSceneIndices.removeValue(forKey: id)

        if activePlayer?.id == id {
            skipTurnPlayerName = nil
            turnChangePresentation = nil
            shopPhase = .hidden
            shopStockItems = []
            specialCardDrawSession = nil
            artifactDrawSession = nil
            startFieldPhase = .hidden
        }

        let wasCurrent = index == turnState.currentPlayerIndex
        players.remove(at: index)

        let lootSummary = PlayerElimination.lootSummary(
            shares: shares,
            players: recipients,
            stats: playerStats
        )

        turnState.logCustomEvent(
            playerName: eliminatedPlayer.className,
            message: "Eliminacja (0 zdrowia). Łupy: \(lootSummary).",
            turnMessage: "\(eliminatedPlayer.displayTitle) odpada z gry."
        )

        playerBossFightCounts.removeValue(forKey: id)
        playerPowerPathProgress.removeValue(forKey: id)

        guard !players.isEmpty else { return }

        turnState.clampCurrentPlayerIndexAfterRemoval(
            removedIndex: index,
            wasCurrentPlayer: wasCurrent,
            activePlayerCount: players.count
        )
    }

    private var contextualStartField: ContextualizedStartField {
        guard let activePlayer else {
            return ContextualizedStartField(
                scene: currentScene,
                decisionQuestion: currentDecision?.question ?? "",
                choiceLabels: [],
                priorInfluenceLines: []
            )
        }
        return campaign.contextualizedStartField(
            playerSceneIndex: sceneIndex(for: activePlayer),
            currentDecisionIndex: decisionIndex,
            playerIndex: activePlayerIndex,
            memory: thinkingService.playthroughStore.memory
        )
    }

    private var ownedItemValueTotalsByPlayer: [UUID: Int] {
        var totals: [UUID: Int] = [:]
        for player in players {
            let itemIDs = playerGrantedItemIDs[player.id] ?? []
            totals[player.id] = itemIDs.reduce(0) { partial, itemID in
                guard let item = creatorStore.catalog.items.first(where: { $0.id == itemID }) else {
                    return partial
                }
                return partial + effectiveItemValue(item, for: player.id)
            }
        }
        return totals
    }

    private var financeEndRanking: [CampaignEndRankingRow] {
        CampaignEndRankings.financeRows(
            players: players,
            stats: playerStats,
            itemValuesByPlayer: ownedItemValueTotalsByPlayer
        )
    }

    private var abilityEndRanking: [CampaignEndRankingRow] {
        CampaignEndRankings.abilityRows(
            players: players,
            stats: playerStats,
            grantedAbilityIDs: playerGrantedAbilityIDs
        )
    }

    private var bossFightEndRanking: [CampaignEndRankingRow] {
        CampaignEndRankings.bossFightRows(
            players: players,
            bossFightCounts: playerBossFightCounts
        )
    }

    private var campaignEndWinnerName: String? {
        guard let sessionWinnerPlayerID,
              let winner = players.first(where: { $0.id == sessionWinnerPlayerID }) else {
            return nil
        }
        return winner.displayTitle
    }

    private var campaignEndSummary: String {
        if sessionWinnerPlayerID != nil {
            let goal = GameplaySessionAbilityPoolState.poolSize
            let contenders = players.filter { (playerGrantedAbilityIDs[$0.id]?.count ?? 0) >= goal }
            if contenders.count > 1 {
                return "Kilku graczy osiągnęło \(goal) zdolności — zwycięzcę wyłoniono po statystykach. Fundusze uwzględniają wartość przedmiotów."
            }
            return "Cel gry: \(goal) zdolności. Poniżej ranking drużyny — fundusze uwzględniają wartość przedmiotów."
        }
        return "Kampania fabularna dobiegła końca. Oto podsumowanie drużyny — fundusze uwzględniają wartość przedmiotów."
    }

    var body: some View {
        gameplayLifecycleLayer
    }

    private var gameplayNavigationChrome: some View {
        gameplayRootStack
            .background {
                if passiveQRMonitorEnabled {
                    PassiveQRCodeMonitor(
                        isEnabled: true,
                        cameraPosition: settings.qrScanCameraPosition
                    ) { result in
                        handlePassiveGameplayScan(result)
                    }
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: startFieldPhase)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isPowerPathOverlayVisible)
            .alert("Uzdrowienie", isPresented: $showHealingOfferAlert) {
                Button("Zapłać 2% finansów") {
                    acceptPostFightHealing()
                }
                Button("Odmów", role: .cancel) {
                    pendingHealingPlayerID = nil
                }
            } message: {
                Text("Odzyskaj pełne zdrowie po walce (Ścieżka Mocy — Uzdrowienie).")
            }
            .navigationTitle(
                isFullScreenOverlayVisible ? "" : (inGameScreen == .campaignEnd ? "Koniec gry" : "Gra")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isFullScreenOverlayVisible ? .hidden : .visible, for: .navigationBar)
            .toolbar(isFullScreenOverlayVisible ? .hidden : .visible, for: .tabBar)
            .appCartoonTabBarVisible(!isFullScreenOverlayVisible)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if campaignStoryFinished, fallenPlayerQueue.isEmpty {
                    campaignFinishedBottomBar
                }
            }
            .alert("Gra zapisana", isPresented: $saveConfirmation) {
                Button("OK", role: .cancel) {
                    settings.playTapSound()
                    dismiss()
                }
            } message: {
                Text("Postęp zapisany. Po wyjściu możesz wczytać grę z menu „Graj”.")
            }
    }

    private var gameplayPresentationLayer: some View {
        gameplayNavigationChrome
            .fullScreenCover(isPresented: $showPlayerStatsOverlay) {
                if let activePlayer, let stats = activeStats {
                    PlayerStatsFullScreenView(
                        stats: stats,
                        experiencePoints: playerPowerPathProgress[activePlayer.id]?.experiencePoints ?? 0,
                        playerGlow: turnGlowColor,
                        playerName: activePlayer.factionName,
                        onExit: {
                            settings.playTapSound()
                            showPlayerStatsOverlay = false
                        },
                        trikiExitHighlighted: selectedTrikiButton == .statsExit,
                        trikiHoldChargeProgress: trikiHoldChargeProgress
                    )
                }
            }
            .fullScreenCover(isPresented: $showSessionAbilitiesOverlay) {
                sessionAbilitiesOverlayContent
            }
            .fullScreenCover(isPresented: $showYourSkillsOverlay) {
                yourSkillsOverlayContent
            }
            .fullScreenCover(item: $powerPathSkillUsePresentation) { presentation in
                PowerPathSkillUseSequenceOverlay(presentation: presentation) {
                    powerPathSkillUsePresentation = nil
                }
            }
            .fullScreenCover(isPresented: $showPlayerItemsOverlay) {
                if let activePlayer {
                    PlayerItemsFullScreenView(
                        playerGlow: turnGlowColor,
                        items: ownedShopItems,
                        playerName: activePlayer.factionName,
                        playerSlot: playerSlot(for: activePlayer),
                        loadImage: { creatorStore.loadImage(fileName: $0) },
                        itemMarketValue: { effectiveItemValue($0, for: activePlayer.id) },
                        equippedItemIDs: equippedItemIDs(for: activePlayer.id),
                        onToggleEquip: { toggleEquipItem($0, for: activePlayer.id) },
                        onExit: {
                            settings.playTapSound()
                            showPlayerItemsOverlay = false
                        },
                        trikiHighlightItemID: trikiHighlightedEquipmentItemID,
                        trikiExitHighlighted: selectedTrikiButton == .equipmentExit,
                        trikiHoldChargeProgress: trikiHoldChargeProgress
                    )
                }
            }
            .fullScreenCover(isPresented: $showBossFightAR) {
                bossFightARContent
            }
            .fullScreenCover(isPresented: $showArenaPvPAR) {
                arenaPvPARContent
            }
            .sheet(item: $pendingAbilityUse) { pending in
                if let caster = players.first(where: { $0.id == pending.casterID }) {
                    SessionAbilityActivationView(
                        ability: pending.ability,
                        caster: caster,
                        players: players,
                        onConfirm: { targetID, spaces in
                            confirmSessionAbilityUse(
                                ability: pending.ability,
                                casterID: pending.casterID,
                                targetID: targetID,
                                boardSpaces: spaces
                            )
                        },
                        onCancel: {
                            pendingAbilityUse = nil
                        }
                    )
                }
            }
    }

    @ViewBuilder
    private var sessionAbilitiesOverlayContent: some View {
        if let activePlayer {
            SessionAbilitiesHubView(
                pool: sessionAbilityPool,
                activePlayer: activePlayer,
                playerGlow: turnGlowColor,
                playerName: activePlayer.factionName,
                canUseAbility: canUseSessionAbility,
                onUseAbility: { ability in
                    showSessionAbilitiesOverlay = false
                    pendingAbilityUse = PendingSessionAbilityUse(
                        ability: ability,
                        casterID: activePlayer.id
                    )
                    syncGameplayQRScanningState()
                },
                onExit: {
                    settings.playTapSound()
                    showSessionAbilitiesOverlay = false
                    syncGameplayQRScanningState()
                },
                trikiExitHighlighted: selectedTrikiButton == .abilitiesExit,
                trikiHoldChargeProgress: trikiHoldChargeProgress
            )
        }
    }

    @ViewBuilder
    private var yourSkillsOverlayContent: some View {
        if let activePlayer {
            YourSkillsFullScreenView(
                player: activePlayer,
                playerGlow: turnGlowColor,
                powerPathProgress: playerPowerPathProgress[activePlayer.id] ?? PlayerPowerPathProgress(),
                lapUsage: playerLapAbilityUsage[activePlayer.id] ?? PlayerLapAbilityUsage(),
                currentHealth: playerStats[activePlayer.id]?.health ?? 100,
                opponents: players.filter { $0.id != activePlayer.id },
                onUsePowerPathSkill: { skill in
                    presentPowerPathSkillUse(skill, playerID: activePlayer.id)
                },
                onCurseTarget: { targetID in
                    presentPowerPathCurseUse(casterID: activePlayer.id, targetID: targetID)
                },
                onExit: {
                    settings.playTapSound()
                    showYourSkillsOverlay = false
                    syncGameplayQRScanningState()
                },
                trikiExitHighlighted: selectedTrikiButton == .abilitiesExit,
                trikiHoldChargeProgress: trikiHoldChargeProgress
            )
        }
    }

    private var gameplayLifecycleLayer: some View {
        gameplayLifecycleTurnLayer
    }

    private var gameplayLifecycleSelectionLayer: some View {
        gameplayPresentationLayer
            .onChange(of: startFieldPhase) { _, phase in
                reconcileTrikiSelection(resetToFirst: true)
                if phase == .hidden {
                    syncGameplayQRScanningState()
                }
            }
            .onChange(of: shopPhase) { _, _ in
                reconcileTrikiSelection(resetToFirst: true)
            }
            .onChange(of: xpShopPhase) { _, _ in
                reconcileTrikiSelection(resetToFirst: true)
            }
            .onChange(of: showPlayerStatsOverlay) { _, _ in
                reconcileTrikiSelection(resetToFirst: true)
            }
            .onChange(of: showSessionAbilitiesOverlay) { _, _ in
                reconcileTrikiSelection(resetToFirst: true)
            }
            .onChange(of: showYourSkillsOverlay) { _, _ in
                reconcileTrikiSelection(resetToFirst: true)
            }
            .onChange(of: showPlayerItemsOverlay) { _, _ in
                reconcileTrikiSelection(resetToFirst: true)
            }
            .onChange(of: isQueueBlockedOverlayVisible) { _, _ in
                reconcileTrikiSelection(resetToFirst: true)
            }
            .onChange(of: fallenPlayerQueue.count) { _, _ in
                reconcileTrikiSelection(resetToFirst: true)
            }
            .onChange(of: pendingEventIntro) { _, _ in
                reconcileTrikiSelection(resetToFirst: true)
            }
            .onChange(of: trikiNavigationContextID) { _, _ in
                reconcileTrikiSelection(resetToFirst: true)
            }
            .onChange(of: powerPathTrikiCatalog.count) { _, _ in
                reconcileTrikiSelection()
            }
            .onAppear {
                if !showGameplayStartIntro {
                    resumeGameplayQRAfterLoad()
                }
            }
    }

    private var gameplayLifecycleTurnLayer: some View {
        gameplayLifecycleSelectionLayer
            .onChange(of: turnState.turnAdvanceCount) { _, _ in
                fluctuateOwnedItemValuesOnTurnAdvance()
                PowerPathEngine.tickTurnCooldowns(progress: &playerPowerPathProgress)
                if let activePlayer {
                    processTurnStartEffects(for: activePlayer.id)
                    processPowerPathTurnStart(for: activePlayer.id)
                }
            }
            .onChange(of: showGameplayStartIntro) { _, isIntroVisible in
                guard !isIntroVisible else { return }
                resumeGameplayQRAfterLoad()
            }
            .background(Color.clear)
            .gameplayThemedScreen(glow: turnGlowColor)
            .onAppear {
                applyTurnGlow(animated: false)
                reconcileLiveCreatorCatalog()
                reconcileTrikiSelection(resetToFirst: true)
            }
            .onDisappear {
                trikiCoordinator.unregister(id: gameTrikiFocusID)
            }
            .task {
                await loadGameplaySession()
            }
    }

    private func loadGameplaySession() async {
        if let snapshot = restoredSnapshot {
            turnState.restore(
                currentPlayerIndex: snapshot.currentPlayerIndex,
                roundNumber: snapshot.roundNumber,
                eventLog: snapshot.eventLog,
                lastTurnMessage: snapshot.lastTurnMessage
            )
            turnState.clampCurrentPlayerIndex(activePlayerCount: players.count)
        } else {
            turnState.reset()
        }
        await thinkingService.prepareForGameplay(campaign: campaign)
        ensurePlayerSceneIndices()
        if campaignsEnabled {
            sceneIndex = activePlayerSceneIndex()
        }
        if restoredSnapshot == nil {
            initializeSessionAbilitiesOnStart()
        } else {
            for player in players {
                sessionAbilityPool.ensurePlayer(player.id)
            }
            syncGrantedAbilityIDsFromPool()
            ensureBoardPositionsForAllPlayers()
        }
        syncAllPlayersAbilityStatCounts()
        if campaignsEnabled {
            if campaignStoryFinished {
                inGameScreen = .campaignEnd
            } else if campaign.isAtFinalStoryStep(decisionRound: decisionIndex),
                      allPlayersCompletedCurrentDecision() {
                markCampaignStoryFinished()
            }
        }
        if !showGameplayStartIntro {
            resumeGameplayQRAfterLoad()
        }
    }

    @ViewBuilder
    private var gameplayRootStack: some View {
        ZStack {
            gameplayCoreLayer
            gameplayEventOverlayLayer
            gameplayTrikiShopStartLayer
            gameplayStatusOverlayLayer
        }
        .trikiFocusContext(
            id: gameTrikiFocusID,
            buttons: trikiFocusButtons,
            onActivate: { activateTrikiButton(at: $0) }
        )
        .onChange(of: trikiCoordinator.motionGestureRevision) { _, _ in
            handleTrikiMotionGestureFromCoordinator()
        }
    }

    @ViewBuilder
    private var gameplayCoreLayer: some View {
        if showGameplayStartIntro {
            GameplayStartOverlay(
                playerGlow: glowColor(for: activePlayer ?? players.first)
            ) {
                showGameplayStartIntro = false
            }
            .zIndex(100)
            .transition(.opacity)
        }

        Group {
            if campaignStoryFinished, sessionEndPhase == .winnerReveal, let winnerName = campaignEndWinnerName {
                SessionWinnerRevealOverlay(
                    playerGlow: turnGlowColor,
                    winnerName: winnerName,
                    detail: sessionWinnerRevealDetail,
                    onComplete: finishSessionWinnerReveal
                )
            } else if campaignStoryFinished, inGameScreen == .campaignEnd {
                CampaignGameEndView(
                    campaignTitle: campaign.title,
                    winnerPlayerName: campaignEndWinnerName,
                    endSummary: campaignEndSummary,
                    financeRanking: financeEndRanking,
                    abilityRanking: abilityEndRanking,
                    bossFightRanking: bossFightEndRanking
                )
            } else {
                mainGameContent
            }
        }
        .opacity(isStartFieldOverlayVisible || isShopOverlayVisible || isXpShopOverlayVisible ? 0 : 1)
        .allowsHitTesting(!isFullScreenOverlayVisible)
        .animation(.easeInOut(duration: 0.45), value: isStartFieldOverlayVisible)
        .animation(.easeInOut(duration: 0.45), value: isShopOverlayVisible)
        .animation(.easeInOut(duration: 0.45), value: isXpShopOverlayVisible)
        .animation(.easeInOut(duration: 0.35), value: inGameScreen)
    }

    @ViewBuilder
    private var gameplayEventOverlayLayer: some View {
        if showFinalTurnIntro {
            SessionFinalTurnIntroOverlay(
                playerGlow: turnGlowColor,
                onComplete: finishFinalTurnIntro
            )
            .zIndex(95)
            .transition(.opacity)
        }

        if let pendingEventIntro {
            GameEventIntroOverlay(
                playerGlow: turnGlowColor,
                event: pendingEventIntro,
                onComplete: finishEventIntro
            )
        }

        if let drawSession = specialCardDrawSession {
            SpecialCardDrawOverlay(
                playerGlow: glowColor(for: drawSession.player),
                playerName: drawSession.player.displayTitle,
                drawnCard: drawSession.card,
                onRevealed: { specialCardDrawRevealed = true },
                onComplete: { finishSpecialCardDraw() }
            )
        }

        if let artifactSession = artifactDrawSession {
            ArtifactDrawOverlay(
                playerGlow: glowColor(for: artifactSession.player),
                playerName: artifactSession.player.displayTitle,
                outcome: artifactSession.outcome,
                onRevealed: { artifactDrawRevealed = true },
                onComplete: { finishArtifactDraw() }
            )
        }
    }

    @ViewBuilder
    private var gameplayTrikiShopStartLayer: some View {
        if trikiCoordinator.showPairingBanner {
            trikiPairingOverlay
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .zIndex(120)
        }

        if isXpShopOverlayVisible, let activePlayer {
            let xp = PowerPathEngine.progress(for: activePlayer.id, in: playerPowerPathProgress).experiencePoints
            XPShopFullScreenOverlay(
                playerGlow: turnGlowColor,
                phase: xpShopPhase,
                playerName: activePlayer.displayTitle,
                experiencePoints: xp,
                fiftyFiftyCost: XPShopCost.fiftyFifty,
                randomAbilityCost: XPShopCost.randomAbility,
                shuffleAbilities: sessionAbilityPool.abilities,
                onFiftyFifty: { purchaseXpShopFiftyFifty(for: activePlayer) },
                onBuyRandomAbility: { purchaseXpShopRandomAbility(for: activePlayer) },
                onDrawRevealed: { completeXpShopDraw(for: activePlayer) },
                onExit: { finishXpShop() },
                trikiHighlightIndex: trikiHighlightIndexInContext
            )
        }

        if isShopOverlayVisible, let activePlayer, let stats = activeStats {
                ShopFullScreenOverlay(
                    playerGlow: turnGlowColor,
                    phase: shopPhase,
                    playerName: activePlayer.displayTitle,
                    playerFinances: stats.finances,
                    stockItems: shopStockItems,
                    ownedItems: ownedShopItems,
                    itemSellValue: { item in
                        effectiveItemValue(item, for: activePlayer.id)
                    },
                    isItemOwned: { item in
                        playerOwnsShopItem(item, playerID: activePlayer.id)
                    },
                    loadImage: { creatorStore.loadImage(fileName: $0) },
                    onSelectBuy: { shopPhase = .buy },
                    onSelectSell: { shopPhase = .sell },
                    onPurchase: { purchaseShopItem($0) },
                    onSell: { sellShopItem($0) },
                    onBack: { shopPhase = .menu },
                    onExit: { finishShop() },
                    trikiHighlightIndex: trikiHighlightIndexInContext
                )
            }

            if isStartFieldOverlayVisible {
                StartFieldFullScreenOverlay(
                    playerGlow: turnGlowColor,
                    phase: startFieldPhase,
                    scene: contextualStartField.scene ?? currentScene,
                    decisionQuestion: contextualStartField.decisionQuestion.isEmpty
                        ? (currentDecision?.question ?? "")
                        : contextualStartField.decisionQuestion,
                    priorInfluenceLines: contextualStartField.priorInfluenceLines,
                    choiceLabels: contextualStartField.choiceLabels,
                    trikiHighlightIndex: trikiHighlightIndexInContext,
                    trikiHoldChargeProgress: trikiHoldChargeProgress,
                    onStay: { chooseStartStaying() },
                    onPass: { chooseStartPassing() },
                    onDismissStayReward: { finishStartFieldStay() },
                    onDismissChoiceEffects: { finishChoiceEffectsReveal() },
                    onSelectChoice: { index, label in
                        guard let activePlayer else { return }
                        settings.playTapSound()
                        selectChoice(label, choiceIndex: index, activePlayer: activePlayer)
                    }
                )
        }
    }

    @ViewBuilder
    private var gameplayStatusOverlayLayer: some View {
        if let skipTurnPlayerName {
                SkipTurnFullScreenOverlay(
                    playerGlow: turnGlowColor,
                    playerName: skipTurnPlayerName,
                    onComplete: { finishSkipTurnOverlay() }
                )
            }

            if let presentation = turnChangePresentation {
                TurnChangeFullScreenOverlay(
                    presentation: presentation,
                    onBeginGlowTransition: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            turnGlowColor = presentation.glowColor
                        }
                    },
                    onComplete: { finishTurnChangeOverlay() }
                )
            }

            if isQueueBlockedOverlayVisible, let activePlayer {
                QueueBlockedOverlay(
                    playerGlow: turnGlowColor,
                    playerName: activePlayer.displayTitle,
                    roundsRemaining: activeQueueBlockRounds,
                    isTrikiSelected: selectedTrikiButton == .queueSkipTurn,
                    onSkipTurn: { skipBlockedQueueTurn() }
                )
            }

            if let fallenSummary = fallenPlayerQueue.first {
                PlayerFallenFullScreenOverlay(
                    summary: fallenSummary,
                    isTrikiSelected: selectedTrikiButton == .overlayContinue,
                    onContinue: { advanceFallenPlayerOverlay() }
                )
            }

            if let bossVictoryPresentation {
                BossFightVictoryRewardOverlay(
                    presentation: bossVictoryPresentation,
                    onComplete: { finishBossVictoryOverlay(bossVictoryPresentation) }
                )
            }

            if let financesChangePresentation {
                FinancesChangeOverlay(presentation: financesChangePresentation) {
                    advanceFinancesChangeQueue()
                }
                .zIndex(250)
            }

            if let presentation = powerPathPresentation {
                PowerPathFullScreenView(
                    playerName: presentation.playerName,
                    visitCount: presentation.visitCount,
                    progress: Binding(
                        get: { playerPowerPathProgress[presentation.playerID] ?? PlayerPowerPathProgress() },
                        set: { playerPowerPathProgress[presentation.playerID] = $0 }
                    ),
                    powerPaths: creatorStore.catalog.powerPaths,
                    opponents: players.filter { $0.id != presentation.playerID },
                    onUnlockPath: { side in
                        unlockPowerPath(side, playerID: presentation.playerID)
                    },
                    onUnlockSkill: { skill in
                        unlockPowerPathSkill(skill, playerID: presentation.playerID)
                    },
                    onUnlockCustomPath: { pathID in
                        unlockCustomPowerPath(pathID, playerID: presentation.playerID)
                    },
                    onUnlockCustomUpgrade: { pathID, upgradeID in
                        unlockCustomPowerUpgrade(pathID: pathID, upgradeID: upgradeID, playerID: presentation.playerID)
                    },
                    onCurseTarget: { targetID in
                        applyPowerPathCurse(casterID: presentation.playerID, targetID: targetID)
                    },
                    onExit: { dismissPowerPathOverlay() },
                    trikiCatalog: $powerPathTrikiCatalog,
                    trikiActivationTrigger: $powerPathTrikiActivationTrigger,
                    trikiHighlightIndex: trikiHighlightIndexInContext,
                    trikiHoldChargeProgress: trikiHoldChargeProgress
                )
            }
    }

    private var trikiHighlightedEquipmentItemID: UUID? {
        if case .equipmentToggle(let itemID) = selectedTrikiButton {
            return itemID
        }
        return nil
    }

    private var campaignFinishedBottomBar: some View {
        VStack(spacing: 12) {
            if inGameScreen == .campaignEnd {
                Button {
                    settings.playTapSound()
                    finishCampaignSession()
                } label: {
                    Text("Zakończ")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.appProminent)
                .padding(.horizontal, 20)
            }

            HStack(spacing: 8) {
                ForEach(InGameScreen.allCases) { screen in
                    Button {
                        settings.playTapSound()
                        inGameScreen = screen
                    } label: {
                        Text(screen.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(inGameScreen == screen ? .white : .secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background {
                                if inGameScreen == screen {
                                    Capsule().fill(settings.accentColor.opacity(0.9))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.35), Color.clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var mainGameContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                turnHeaderSection

                if let stats = activeStats, let activePlayer {
                    VStack(spacing: 12) {
                        PlayerStatsRevealSection(
                            stats: stats,
                            playerID: activePlayer.id,
                            playerGlow: turnGlowColor,
                            playerName: activePlayer.factionName,
                            isTrikiSelected: selectedTrikiButton == .showStats,
                            trikiHoldChargeProgress: trikiHoldChargeProgress,
                            isScreenPresented: $showPlayerStatsOverlay
                        )

                        PlayerItemsRevealSection(
                            items: ownedShopItems,
                            playerID: activePlayer.id,
                            playerGlow: turnGlowColor,
                            playerName: activePlayer.factionName,
                            playerSlot: playerSlot(for: activePlayer),
                            loadImage: { creatorStore.loadImage(fileName: $0) },
                            itemMarketValue: { effectiveItemValue($0, for: activePlayer.id) },
                            equippedItemIDs: equippedItemIDs(for: activePlayer.id),
                            onToggleEquip: { toggleEquipItem($0, for: activePlayer.id) },
                            isTrikiSelected: selectedTrikiButton == .showItems,
                            trikiHoldChargeProgress: trikiHoldChargeProgress,
                            isScreenPresented: $showPlayerItemsOverlay
                        )
                    }
                    .padding(.horizontal, 4)
                }

                turnActionsSection
                if isBossFightActive {
                    bossFightAbilitiesSection
                }
                saveGameSection

                if let event = lastEventResult {
                    eventResultSection(event)
                }
            }
            .padding()
        }
        .appScrollSurface()
    }

    private func eventResultSection(_ event: QRGameEventCode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(event.title, systemImage: event.icon)
                .font(.headline)
            if event == .artifact, !lastArtifactDetail.isEmpty {
                Text(lastArtifactDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if event == .specialCard, !lastSpecialCardDetail.isEmpty {
                Text(lastSpecialCardDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(event.effectDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var turnHeaderSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Runda \(turnState.roundNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let activePlayer {
                Text("Tura gracza \(turnState.currentPlayerNumber) — \(activePlayer.factionName)")
                    .font(.title2.bold())
                if let boardPosition = playerBoardPositions[activePlayer.id] {
                    Text("Pozycja na planszy: \(boardPosition)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !turnState.lastTurnMessage.isEmpty {
                Text(turnState.lastTurnMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var turnActionsSection: some View {
        VStack(spacing: 12) {
            if let activePlayer {
                SessionAbilitiesRevealSection(
                    isTrikiSelected: selectedTrikiButton == .showAbilities,
                    trikiHoldChargeProgress: trikiHoldChargeProgress,
                    isScreenPresented: $showSessionAbilitiesOverlay
                )
            }

            Button {
                settings.playTapSound()
                skipActiveTurn()
            } label: {
                Label("Pomiń turę", systemImage: "forward.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.appSecondary)
            .disabled(isQueueBlockedOverlayVisible)
            .trikiSelectableHighlight(
                isSelected: selectedTrikiButton == .skipTurn,
                chargeProgress: selectedTrikiButton == .skipTurn ? trikiHoldChargeProgress : 0
            )

            if settings.trikiControllerEnabled {
                VStack(spacing: 4) {
                    if !trikiCoordinator.connectionMessage.isEmpty {
                        Text(trikiCoordinator.connectionMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Text("Triki: aktywna opcja — \(trikiButtonTitle(selectedTrikiButton))")
                        .font(.caption2.bold())
                        .foregroundStyle(settings.accentColor)
                        .multilineTextAlignment(.center)
                    Text("Krótki klik — następny przycisk; przytrzymaj 0,8 s — jaśniejsze tło, potem wybór.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if !trikiCoordinator.statusMessage.isEmpty {
                        Text(trikiCoordinator.statusMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
    }

    private var trikiPairingOverlay: some View {
        let isConnected = trikiCoordinator.connectionMessage.contains("połączono")
        return ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .opacity(isConnected ? 0 : 1)

                Text(isConnected ? "Połączono" : "Szukam połączenia z Triki...")
                    .font(.headline.bold())
                    .multilineTextAlignment(.center)

                if !isConnected {
                    Text("Upewnij się, że kontroler Triki jest włączony i blisko telefonu.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                if !isConnected {
                    Button("Anuluj") {
                        settings.playTapSound()
                        settings.trikiControllerEnabled = false
                    }
                    .buttonStyle(.appSecondary)
                    .padding(.top, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var bossFightAbilitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Walka z bossem — AR", systemImage: "shield.lefthalf.filled")
                .font(.headline)

            Text("Skanuj QR gracza (4001–4004) i dodaj wsparcie przed „Wybierz Bossa”. Statystyki w walce z bossem liczą założony ekwipunek z gry. W walce: 6 s na ruch; bez wyboru boss zadaje potrójne obrażenia. Co 2× pole start — Ścieżka Mocy.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Wejdź do trybu AR") {
                settings.playTapSound()
                showBossFightAR = true
            }
            .buttonStyle(.appProminent)
            .trikiSelectableHighlight(
                isSelected: selectedTrikiButton == .bossEnterAR,
                chargeProgress: selectedTrikiButton == .bossEnterAR ? trikiHoldChargeProgress : 0
            )

            Button("Zakończ walkę z bossem") {
                settings.playTapSound()
                isBossFightActive = false
                lastAbilityOutcome = ""
            }
            .buttonStyle(.appSecondary)
            .trikiSelectableHighlight(
                isSelected: selectedTrikiButton == .bossEndFight,
                chargeProgress: selectedTrikiButton == .bossEndFight ? trikiHoldChargeProgress : 0
            )
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var bossFightARContent: some View {
        Group {
            if let activePlayer {
                BossFightARView(
                    mainFighter: activePlayer,
                    players: players,
                    playerStats: playerStats,
                    playerEquippedItems: playerEquippedItems,
                    catalogItems: creatorStore.catalog.items,
                    sessionAbilityPool: sessionAbilityPool,
                    onPlayerHealthUpdate: applyBossFightHealthUpdate,
                    onPlayerStatsUpdate: { playerID, stats in
                        setPlayerStats(stats, for: playerID)
                    },
                    onAbilityConsumed: { playerID, abilityID in
                        sessionAbilityPool.consume(abilityID: abilityID, from: playerID)
                        if var ids = playerGrantedAbilityIDs[playerID] {
                            ids.removeAll { $0 == abilityID }
                            playerGrantedAbilityIDs[playerID] = ids.isEmpty ? nil : ids
                        }
                        syncAbilityStatCount(for: playerID)
                    },
                    onCombatFinished: handleBossFightCombatOutcome,
                    externalSelectedMove: $pendingTrikiBossMove,
                    onExit: {
                        isBossFightActive = false
                        showBossFightAR = false
                        syncGameplayQRScanningState()
                    }
                )
            }
        }
    }

    private var arenaPvPARContent: some View {
        ArenaPvPARView(
            players: players,
            playerStats: playerStats,
            playerExperiencePoints: playerPowerPathProgress.mapValues(\.experiencePoints),
            playerEquippedItems: playerEquippedItems,
            catalogItems: creatorStore.catalog.items,
            sessionAbilityPool: $sessionAbilityPool,
            onAbilityConsumed: { playerID, abilityID in
                if var ids = playerGrantedAbilityIDs[playerID] {
                    ids.removeAll { $0 == abilityID }
                    playerGrantedAbilityIDs[playerID] = ids.isEmpty ? nil : ids
                }
                syncAbilityStatCount(for: playerID)
            },
            onSettled: { outcome in
                applyArenaPvPOutcome(outcome)
            },
            onExit: {
                isArenaPvPActive = false
                showArenaPvPAR = false
                syncGameplayQRScanningState()
            }
        )
    }

    private func applyArenaPvPOutcome(_ outcome: ArenaPvPOutcome) {
        guard var winnerStats = playerStats[outcome.winnerID],
              var loserStats = playerStats[outcome.loserID] else { return }

        let transfer = outcome.transferAmount
        let xpTransfer = outcome.xpTransfer

        if transfer > 0 {
            let winnerFinancesBefore = winnerStats.finances
            loserStats.finances = max(0, loserStats.finances - transfer)
            winnerStats.finances += transfer
            reconcileCoinGainWithCurse(
                playerID: outcome.winnerID,
                beforeFinances: winnerFinancesBefore,
                stats: &winnerStats
            )
            setPlayerStats(loserStats, for: outcome.loserID, financesAnimation: .suppressed)
            setPlayerStats(winnerStats, for: outcome.winnerID, financesAnimation: .suppressed)

            if shouldAnimateFinancesChangesAutomatically {
                queueFinancesChangeAnimation(delta: transfer)
                queueFinancesChangeAnimation(delta: -transfer)
            }
        }

        if xpTransfer > 0 {
            _ = PowerPathEngine.grantExperience(-xpTransfer, playerID: outcome.loserID, progress: &playerPowerPathProgress)
            _ = PowerPathEngine.grantExperience(xpTransfer, playerID: outcome.winnerID, progress: &playerPowerPathProgress)
        }

        logArenaPvPResult(outcome: outcome, transfer: transfer, xpTransfer: xpTransfer)
    }

    private func logArenaPvPResult(outcome: ArenaPvPOutcome, transfer: Int, xpTransfer: Int) {
        let winnerName = players.first { $0.id == outcome.winnerID }?.displayTitle ?? "Gracz"
        let loserName = players.first { $0.id == outcome.loserID }?.displayTitle ?? "Gracz"
        var message = "Arena PvP: \(winnerName) wygrywa."
        if transfer > 0 {
            message += " \(loserName) traci \(transfer) monet, \(winnerName) zyskuje \(transfer)."
        }
        if xpTransfer > 0 {
            message += " \(loserName) traci \(xpTransfer) XP, \(winnerName) zyskuje \(xpTransfer) XP."
        }
        turnState.logCustomEvent(
            playerName: winnerName,
            message: message,
            turnMessage: "Arena PvP zakończona."
        )
    }

    private func handleBossFightCombatOutcome(_ outcome: BossFightCombatOutcome) {
        let participantIDs = [outcome.mainPlayerID] + outcome.supporterIDs
        recordBossFightParticipation(for: participantIDs)

        isBossFightActive = false
        showBossFightAR = false

        if outcome.victory {
            if let presentation = buildBossVictoryPresentation(for: outcome) {
                bossVictoryPresentation = presentation
            } else {
                applyBossVictoryRewards(presentationSteps: [], outcome: outcome)
            }
        } else {
            queuePlayersFallen(ids: participantIDs)

            turnState.logCustomEvent(
                playerName: "Drużyna",
                message: "Porażka z bossem — uczestnicy odpadają z gry.",
                turnMessage: "Walka z bossem — porażka."
            )
            syncGameplayQRScanningState()
        }
    }

    private func buildBossVictoryPresentation(for outcome: BossFightCombatOutcome) -> BossFightVictoryPresentation? {
        let totalPool = outcome.bossDifficulty.victoryCoinPool
        let split = BossFightStatsCalculator.financeRewardSplit(
            totalPool: totalPool,
            supporterCount: outcome.supporterIDs.count
        )
        let mainPercentLabel = outcome.supporterIDs.isEmpty ? "100%" : "80%"
        let supporterPercentLabel = "20%"
        let totalXP = bossVictoryXP(for: outcome.bossDifficulty)
        let xpSplit = BossFightStatsCalculator.experienceRewardSplit(
            totalPool: totalXP,
            supporterCount: outcome.supporterIDs.count
        )

        var steps: [BossFightVictoryRewardStep] = []

        if let main = players.first(where: { $0.id == outcome.mainPlayerID }),
           let stats = playerStats[outcome.mainPlayerID] {
            steps.append(
                BossFightVictoryRewardStep(
                    id: UUID(),
                    playerID: main.id,
                    playerName: main.displayTitle,
                    roleLabel: "Organizator walki",
                    lobbySlotNumber: main.lobbySlotNumber,
                    characterQRCode: main.qrCode,
                    financesBefore: stats.finances,
                    rewardAmount: split.mainShare,
                    rewardPercentLabel: mainPercentLabel,
                    xpBefore: PowerPathEngine.progress(for: main.id, in: playerPowerPathProgress).experiencePoints,
                    rewardXP: outcome.supporterIDs.isEmpty ? totalXP : xpSplit.mainShare
                )
            )
        }

        for supporterID in outcome.supporterIDs {
            guard let player = players.first(where: { $0.id == supporterID }),
                  let stats = playerStats[supporterID] else { continue }
            steps.append(
                BossFightVictoryRewardStep(
                    id: UUID(),
                    playerID: player.id,
                    playerName: player.displayTitle,
                    roleLabel: "Uczestnik walki",
                    lobbySlotNumber: player.lobbySlotNumber,
                    characterQRCode: player.qrCode,
                    financesBefore: stats.finances,
                    rewardAmount: split.supporterShare,
                    rewardPercentLabel: supporterPercentLabel,
                    xpBefore: PowerPathEngine.progress(for: player.id, in: playerPowerPathProgress).experiencePoints,
                    rewardXP: xpSplit.supporterShare
                )
            )
        }

        guard !steps.isEmpty else { return nil }
        return BossFightVictoryPresentation(steps: steps, outcome: outcome)
    }

    private func finishBossVictoryOverlay(_ presentation: BossFightVictoryPresentation) {
        guard let bossOutcome = presentation.bossOutcome else { return }
        applyBossVictoryRewards(presentationSteps: presentation.steps, outcome: bossOutcome)
        bossVictoryPresentation = nil
        syncGameplayQRScanningState()
    }

    private func applyBossVictoryRewards(
        presentationSteps: [BossFightVictoryRewardStep],
        outcome: BossFightCombatOutcome
    ) {
        for step in presentationSteps where step.rewardAmount > 0 {
            applyFinancesDelta(step.rewardAmount, for: step.playerID, financesAnimation: .suppressed)
        }

        if var mainStats = playerStats[outcome.mainPlayerID] {
            mainStats.health = max(0, min(100, outcome.mainPlayerFinalHealth))
            setPlayerStats(mainStats, for: outcome.mainPlayerID)
            offerPostFightHealingIfNeeded(for: outcome.mainPlayerID)
        }

        let totalXP = bossVictoryXP(for: outcome.bossDifficulty)
        let xpSplit = BossFightStatsCalculator.experienceRewardSplit(
            totalPool: totalXP,
            supporterCount: outcome.supporterIDs.count
        )

        if presentationSteps.isEmpty {
            _ = PowerPathEngine.grantExperience(
                outcome.supporterIDs.isEmpty ? totalXP : xpSplit.mainShare,
                playerID: outcome.mainPlayerID,
                progress: &playerPowerPathProgress
            )
            for supporterID in outcome.supporterIDs {
                _ = PowerPathEngine.grantExperience(
                    xpSplit.supporterShare,
                    playerID: supporterID,
                    progress: &playerPowerPathProgress
                )
            }
        } else {
            for step in presentationSteps where step.rewardXP > 0 {
                _ = PowerPathEngine.grantExperience(
                    step.rewardXP,
                    playerID: step.playerID,
                    progress: &playerPowerPathProgress
                )
            }
        }

        let mainShare = presentationSteps.first { $0.playerID == outcome.mainPlayerID }?.rewardAmount ?? 0
        let supporterShare = presentationSteps.first { $0.playerID != outcome.mainPlayerID }?.rewardAmount ?? 0
        let mainXP = presentationSteps.first { $0.playerID == outcome.mainPlayerID }?.rewardXP
            ?? (outcome.supporterIDs.isEmpty ? totalXP : xpSplit.mainShare)
        let supporterXP = presentationSteps.first { $0.playerID != outcome.mainPlayerID }?.rewardXP
            ?? xpSplit.supporterShare
        var rewardMessage = outcome.supporterIDs.isEmpty
            ? "Wygrana z bossem! Nagroda: \(mainShare) monet, +\(mainXP) XP."
            : "Wygrana z bossem! \(mainShare) monet i +\(mainXP) XP (gospodarz), \(supporterShare) monet i +\(supporterXP) XP (uczestnik)."

        turnState.logCustomEvent(
            playerName: players.first { $0.id == outcome.mainPlayerID }?.className ?? "Gracz",
            message: rewardMessage,
            turnMessage: "Walka z bossem — zwycięstwo!"
        )
        settings.playStatsRevealSound()
    }

    private func applyBossFightHealthUpdate(playerID: UUID, health: Int) {
        guard var stats = playerStats[playerID] else { return }
        stats.health = max(0, min(100, health))
        setPlayerStats(stats, for: playerID)
    }

    private var saveGameSection: some View {
        Button {
            settings.playTapSound()
            saveGame()
        } label: {
            Label("Zapisz grę", systemImage: "square.and.arrow.down")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.appSecondary)
        .trikiSelectableHighlight(
            isSelected: selectedTrikiButton == .saveGame,
            chargeProgress: selectedTrikiButton == .saveGame ? trikiHoldChargeProgress : 0
        )
    }

    private func saveGame() {
        var choiceMap: [String: String] = [:]
        for (id, text) in selectedChoices {
            choiceMap[id.uuidString] = text
        }

        var statsMap: [String: PlayerRuntimeStats] = [:]
        for (id, stats) in playerStats {
            statsMap[id.uuidString] = stats
        }

        let snapshot = SavedGameSnapshot(
            campaignTitle: campaign.title,
            savedAt: Date(),
            players: players,
            playerStats: statsMap,
            currentPlayerIndex: turnState.currentPlayerIndex,
            roundNumber: turnState.roundNumber,
            eventLog: turnState.eventLog,
            lastTurnMessage: turnState.lastTurnMessage,
            sceneIndex: activePlayerSceneIndex(),
            decisionIndex: decisionIndex,
            playerSceneIndices: Dictionary(
                uniqueKeysWithValues: playerSceneIndices.map { ($0.key.uuidString, $0.value) }
            ),
            selectedChoices: choiceMap,
            interpretation: interpretation,
            lastEventCode: lastEventResult?.rawValue,
            pendingStartFieldChoice: startFieldPhase == .choosing,
            awaitingStartPassDecisions: startFieldPhase == .passingDecisions,
            showingStartStayReward: isShowingStartStayReward,
            startFieldHealthBefore: startFieldHealthBeforeForSave,
            startFieldHealthAfter: startFieldHealthAfterForSave,
            showingStartPassCoinReward: isShowingStartPassCoinReward,
            startFieldFinancesBefore: startFieldFinancesBeforeForSave,
            startFieldFinancesAfter: startFieldFinancesAfterForSave,
            playerGrantedAbilityIDs: Dictionary(
                uniqueKeysWithValues: playerGrantedAbilityIDs.map { ($0.key.uuidString, $0.value) }
            ),
            playerGrantedItemIDs: Dictionary(
                uniqueKeysWithValues: playerGrantedItemIDs.map { ($0.key.uuidString, $0.value) }
            ),
            playerEquippedItems: PlayerEquipment.encode(playerEquippedItems),
            playerOwnedItemValues: Self.ownedItemValueStorage(from: playerOwnedItemValues),
            playerQueueBlockRounds: Dictionary(
                uniqueKeysWithValues: playerQueueBlockRounds.map { ($0.key.uuidString, $0.value) }
            ),
            isBossFightActive: isBossFightActive,
            campaignStoryFinished: campaignStoryFinished,
            pendingFinalTurn: pendingFinalTurn,
            finalTurnEndAfterPlayerIndex: finalTurnEndAfterPlayerIndex,
            finalTurnRoundActive: finalTurnRoundActive,
            sessionAbilityGoalReachedOrder: sessionAbilityGoalReachedOrder.map(\.uuidString),
            sessionWinnerPlayerID: sessionWinnerPlayerID?.uuidString,
            sessionEndPhase: sessionEndPhase.rawValue,
            sessionAbilityPool: sessionAbilityPool,
            playerBoardPositions: Dictionary(
                uniqueKeysWithValues: playerBoardPositions.map { ($0.key.uuidString, $0.value) }
            ),
            activeTurnDamageEffects: activeTurnDamageEffects,
            activeTemporaryBoosts: Dictionary(
                uniqueKeysWithValues: activeTemporaryBoosts.map { ($0.key.uuidString, $0.value) }
            ),
            playerBossFightCounts: Dictionary(
                uniqueKeysWithValues: playerBossFightCounts.map { ($0.key.uuidString, $0.value) }
            ),
            playerPowerPathProgress: Dictionary(
                uniqueKeysWithValues: playerPowerPathProgress.map { ($0.key.uuidString, $0.value) }
            ),
            playerLapAbilityUsage: Dictionary(
                uniqueKeysWithValues: playerLapAbilityUsage.map { ($0.key.uuidString, $0.value) }
            )
        )

        savedGameStore.save(snapshot)
        saveConfirmation = true
    }

    private var isShowingStartStayReward: Bool {
        switch startFieldPhase {
        case .stayingReward, .stayingFullHealthReward:
            return true
        default:
            return false
        }
    }

    private var startFieldHealthBeforeForSave: Int? {
        if case .stayingReward(let before, _) = startFieldPhase { return before }
        return nil
    }

    private var startFieldHealthAfterForSave: Int? {
        if case .stayingReward(_, let after) = startFieldPhase { return after }
        return nil
    }

    private var isShowingStartPassCoinReward: Bool {
        if case .passingCoinReward = startFieldPhase { return true }
        return false
    }

    private var startFieldFinancesBeforeForSave: Int? {
        if case .passingCoinReward(let before, _) = startFieldPhase { return before }
        return nil
    }

    private var startFieldFinancesAfterForSave: Int? {
        if case .passingCoinReward(_, let after) = startFieldPhase { return after }
        return nil
    }

    private func finishStartFieldStay() {
        settings.playTapSound()
        guard let activePlayer else {
            startFieldPhase = .hidden
            return
        }

        if case .passingCoinReward = startFieldPhase {
            finishStartFieldPassCoinReward(activePlayer: activePlayer)
            return
        }

        let shouldDeferTurn = registerStartFieldVisit(for: activePlayer)
        startFieldPhase = .hidden
        lastEventResult = nil
        recommendations = [:]

        if shouldDeferTurn {
            if startFieldStayTurnPending {
                powerPathPendingAction = .advanceTurnAfterStay
                startFieldStayTurnPending = false
            }
            return
        }

        if startFieldStayTurnPending {
            advanceTurnWithReveal()
            startFieldStayTurnPending = false
        }
    }

    private func finishStartFieldPassCoinReward(activePlayer: PlayerCharacter) {
        startFieldPhase = .hidden
        lastEventResult = nil
        recommendations = [:]

        if registerStartFieldVisit(for: activePlayer) {
            powerPathPendingAction = .completeStartPassCoin(playerID: activePlayer.id)
            return
        }

        completeStartFieldPassCoinTurn(activePlayer: activePlayer)
    }

    private func completeStartFieldPassCoinTurn(activePlayer: PlayerCharacter) {
        let previousRound = turnState.roundNumber
        turnState.completeStartFieldPass(
            activePlayer: activePlayer,
            choice: "Przejście przez start",
            totalPlayers: players.count
        )
        presentTurnChangeOverlay(highlightNewRound: turnState.roundNumber > previousRound)
    }

    @discardableResult
    private func registerStartFieldVisit(for player: PlayerCharacter) -> Bool {
        LapAbilityUsageEngine.resetLap(for: player.id, usage: &playerLapAbilityUsage)
        let result = PowerPathEngine.recordStartFieldVisit(
            playerID: player.id,
            progress: &playerPowerPathProgress,
            rules: creatorStore.gameRules.startField
        )
        if result.shouldOpenPowerPath {
            powerPathPresentation = PowerPathPresentation(
                playerID: player.id,
                playerName: player.displayTitle,
                visitCount: result.visitCount
            )
            return true
        }
        return false
    }

    private func dismissPowerPathOverlay() {
        powerPathTrikiCatalog = []
        powerPathTrikiActivationTrigger = 0
        settings.playTapSound()
        powerPathPresentation = nil

        switch powerPathPendingAction {
        case .none:
            break
        case .advanceTurnAfterStay:
            advanceTurnWithReveal()
        case .completeStartPassCoin(let playerID):
            if let player = players.first(where: { $0.id == playerID }) {
                completeStartFieldPassCoinTurn(activePlayer: player)
            }
        case .completeStartPass(let playerID, let choice):
            if let player = players.first(where: { $0.id == playerID }) {
                completeStartFieldPassAfterCampaign(player: player, choice: choice)
            }
        }
        powerPathPendingAction = .none
    }

    private func completeStartFieldPassAfterCampaign(player: PlayerCharacter, choice: String) {
        let previousRound = turnState.roundNumber
        turnState.completeStartFieldPass(
            activePlayer: player,
            choice: choice,
            totalPlayers: players.count
        )
        presentTurnChangeOverlay(highlightNewRound: turnState.roundNumber > previousRound)

        if allPlayersCompletedCurrentDecision() {
            if advanceCampaignStepAfterDecision() {
                markCampaignStoryFinished()
            }
        }
    }

    private func unlockPowerPath(_ side: PowerPathSide, playerID: UUID) -> String? {
        PowerPathEngine.unlockPath(side: side, playerID: playerID, progress: &playerPowerPathProgress)
    }

    private func unlockPowerPathSkill(_ skill: PowerPathSkillID, playerID: UUID) -> String? {
        var stats = playerStats[playerID]
        let message = PowerPathEngine.unlock(
            skill: skill,
            playerID: playerID,
            progress: &playerPowerPathProgress,
            runtimeStats: &stats
        )
        if let stats {
            setPlayerStats(stats, for: playerID)
        }
        return message
    }

    private func applyPowerPathCurse(casterID: UUID, targetID: UUID) -> String? {
        PowerPathEngine.activateCurse(
            casterID: casterID,
            targetID: targetID,
            progress: &playerPowerPathProgress
        )
    }

    private func processPowerPathTurnStart(for playerID: UUID) {
        guard var stats = playerStats[playerID] else { return }
        if let result = PowerPathEngine.processTurnStart(
            playerID: playerID,
            progress: &playerPowerPathProgress
        ) {
            if result.coinBonus > 0 {
                _ = applyCursedCoinGain(result.coinBonus, to: playerID, stats: &stats)
            }
            setPlayerStats(stats, for: playerID)
            if let message = result.message, let player = players.first(where: { $0.id == playerID }) {
                turnState.logCustomEvent(playerName: player.className, message: message)
            }
        }
    }

    private func applyPowerPathShadowOnHealthLoss(playerID: UUID) {
        if let message = PowerPathEngine.applyShadowAfterHealthLoss(
            playerID: playerID,
            players: players,
            stats: &playerStats,
            progress: playerPowerPathProgress
        ) {
            if let player = players.first(where: { $0.id == playerID }) {
                turnState.logCustomEvent(playerName: player.className, message: message)
            }
        }
    }

    private func applyStartFieldPassCoins(for playerID: UUID, stats: inout PlayerRuntimeStats) {
        _ = applyCursedCoinGain(StartFieldRewards.passCoins, to: playerID, stats: &stats)
    }

    private func offerPostFightHealingIfNeeded(for playerID: UUID) {
        guard playerPowerPathProgress[playerID]?.hasUnlocked(.healing) == true else { return }
        guard !LapAbilityUsageEngine.hasUsedPowerPath(.healing, playerID: playerID, in: playerLapAbilityUsage) else { return }
        guard let health = playerStats[playerID]?.health, health < 100 else { return }
        pendingHealingPlayerID = playerID
        showHealingOfferAlert = true
    }

    private func acceptPostFightHealing() {
        guard let playerID = pendingHealingPlayerID else { return }
        guard var stats = playerStats[playerID] else { return }
        guard !LapAbilityUsageEngine.hasUsedPowerPath(.healing, playerID: playerID, in: playerLapAbilityUsage) else {
            pendingHealingPlayerID = nil
            return
        }
        if let message = PowerPathEngine.offerPostFightHealing(
            playerID: playerID,
            progress: playerPowerPathProgress,
            stats: &stats,
            accept: true
        ) {
            _ = LapAbilityUsageEngine.markUsedPowerPath(.healing, playerID: playerID, usage: &playerLapAbilityUsage)
            setPlayerStats(stats, for: playerID)
            if let player = players.first(where: { $0.id == playerID }) {
                turnState.logCustomEvent(playerName: player.className, message: message)
            }
        }
        pendingHealingPlayerID = nil
    }

    private func chooseStartStaying() {
        guard let activePlayer else { return }
        settings.playTapSound()

        guard var stats = playerStats[activePlayer.id] else {
            startFieldPhase = .hidden
            return
        }

        if stats.health >= StartFieldRewards.maxHealth {
            let financesBefore = stats.finances
            _ = applyCursedCoinGain(StartFieldRewards.stayAtFullHealthCoins, to: activePlayer.id, stats: &stats)
            setPlayerStats(stats, for: activePlayer.id)
            let financesAfter = playerStats[activePlayer.id]?.finances ?? stats.finances
            let xpGained = PowerPathEngine.grantExperience(
                StartFieldRewards.stayAtFullHealthXP,
                playerID: activePlayer.id,
                progress: &playerPowerPathProgress
            )
            startFieldPhase = .stayingFullHealthReward(
                previousFinances: financesBefore,
                newFinances: financesAfter,
                xpGained: xpGained
            )
            startFieldStayTurnPending = true
            turnState.logCustomEvent(
                playerName: activePlayer.className,
                message: "Pole start: pełne zdrowie — +\(StartFieldRewards.stayAtFullHealthCoins) monet, +\(xpGained) XP."
            )
        } else {
            let before = stats.health
            stats.applyStartFieldStaying()
            setPlayerStats(stats, for: activePlayer.id)
            let afterHealth = playerStats[activePlayer.id]?.health ?? stats.health
            startFieldPhase = .stayingReward(previousHealth: before, newHealth: afterHealth)
            startFieldStayTurnPending = true
            turnState.appendStartFieldStayLog(activePlayer: activePlayer)
        }

        lastEventResult = nil
        recommendations = [:]
    }

    private func chooseStartPassing() {
        guard let activePlayer else { return }

        if !campaignsEnabled {
            chooseStartPassingWithoutCampaign(activePlayer: activePlayer)
            return
        }

        guard !campaignStoryFinished else {
            inGameScreen = .campaignEnd
            return
        }
        settings.playTapSound()

        startFieldPhase = .passingDecisions
        recommendations = [:]
        turnState.beginStartFieldPass(activePlayer: activePlayer)
    }

    private func chooseStartPassingWithoutCampaign(activePlayer: PlayerCharacter) {
        settings.playTapSound()

        let before = playerStats[activePlayer.id]?.finances ?? 0
        guard var stats = playerStats[activePlayer.id] else { return }
        applyStartFieldPassCoins(for: activePlayer.id, stats: &stats)
        setPlayerStats(stats, for: activePlayer.id)
        let after = playerStats[activePlayer.id]?.finances ?? stats.finances

        startFieldPhase = .passingCoinReward(previousFinances: before, newFinances: after)
        recommendations = [:]
        turnState.beginStartFieldPass(activePlayer: activePlayer)
    }

    private func handlePassiveGameplayScan(_ result: QRGameplayScanResult) {
        guard canScanGameplayQR else { return }

        if activeQueueBlockRounds > 0 {
            switch result {
            case .masterAction(.skipTurn):
                break
            default:
                return
            }
        }

        settings.playTapSound()

        switch result {
        case .powerPathSkill:
            openYourSkillsOverlay()
        case .masterAction(let action):
            switch action {
            case .skipTurn:
                if activeQueueBlockRounds > 0 {
                    skipBlockedQueueTurn()
                } else {
                    skipActiveTurn()
                }
            case .showItems:
                if showPlayerItemsOverlay {
                    showPlayerItemsOverlay = false
                } else {
                    showPlayerItemsOverlay = true
                }
            case .showAbilities:
                openYourSkillsOverlay()
            }
        case .gameEvent(let event):
            if isGameEventOverlayActive(event) {
                if canDismissGameEventOverlayViaQR(event) {
                    completeGameEventOverlayViaQR(event)
                }
            } else {
                pendingEventIntro = event
            }
        }
    }

    private func handleTrikiMotionGestureFromCoordinator() {
        guard let kind = trikiCoordinator.lastMotionGesture else { return }
        // Nawigacja w rozgrywce: wyłącznie fizyczny przycisk (coordinator.processPhysicalButton).
        switch kind {
        case .bowRelease, .swordSwing:
            break
        case .rotateLeft, .rotateRight, .moveForward, .moveBackward,
             .strafeLeft, .strafeRight, .shake, .physicalButton, .speedBurst:
            return
        }
    }

    private func activateTrikiButton(at index: Int) {
        let buttons = trikiSelectableButtons
        guard buttons.indices.contains(index) else { return }
        trikiCoordinator.selectionIndex = index
        activateTrikiButton(buttons[index])
    }

    private func activateTrikiButton(_ button: TrikiSelectableButton) {
        guard !trikiSelectableButtons.isEmpty else { return }
        switch button {
        case .showStats:
            settings.playStatsRevealSound()
            showPlayerStatsOverlay = true
            trikiCoordinator.statusMessage = "Wciśnięto: Pokaż Statystyki."
        case .showItems:
            settings.playStatsRevealSound()
            showPlayerItemsOverlay = true
            trikiCoordinator.statusMessage = "Wciśnięto: Pokaż Ekwipunek."
        case .showAbilities:
            settings.playTapSound()
            showSessionAbilitiesOverlay = true
            trikiCoordinator.statusMessage = "Wciśnięto: Zdolności."
        case .skipTurn:
            if activeQueueBlockRounds > 0 {
                skipBlockedQueueTurn()
            } else {
                skipActiveTurn()
            }
            trikiCoordinator.statusMessage = "Wciśnięto: Pomiń turę."
        case .saveGame:
            saveGame()
            trikiCoordinator.statusMessage = "Wciśnięto: Zapisz grę."
        case .ability(let abilityID):
            guard let activePlayer else { return }
            guard let ability = grantedSessionAbilities(for: activePlayer.id).first(where: { $0.id == abilityID }) else {
                trikiCoordinator.statusMessage = "Ta zdolność nie jest już dostępna."
                return
            }
            pendingAbilityUse = PendingSessionAbilityUse(ability: ability, casterID: activePlayer.id)
            trikiCoordinator.statusMessage = "Wciśnięto: \(ability.name)."
        case .bossEnterAR:
            showBossFightAR = true
            trikiCoordinator.statusMessage = "Wciśnięto: Wejdź do trybu AR."
        case .bossEndFight:
            isBossFightActive = false
            lastAbilityOutcome = ""
            trikiCoordinator.statusMessage = "Wciśnięto: Zakończ walkę z bossem."
        case .startFieldStay:
            chooseStartStaying()
            trikiCoordinator.statusMessage = "Wciśnięto: Jestem na start."
        case .startFieldPass:
            chooseStartPassing()
            trikiCoordinator.statusMessage = "Wciśnięto: Przechodzę przez start."
        case .startFieldChoice(let index):
            let labels = contextualStartField.choiceLabels
            guard let activePlayer, labels.indices.contains(index) else { return }
            settings.playTapSound()
            selectChoice(labels[index], choiceIndex: index, activePlayer: activePlayer)
            trikiCoordinator.statusMessage = "Wciśnięto: \(labels[index])."
        case .overlayContinue:
            settings.playTapSound()
            if isXpShopOverlayVisible, isXpShopResultReady {
                finishXpShop()
            } else if isXpShopOverlayVisible, case .menu = xpShopPhase {
                finishXpShop()
            } else if pendingEventIntro != nil {
                finishEventIntro()
            } else if isSkipTurnOverlayVisible {
                finishSkipTurnOverlay()
            } else if isTurnChangeOverlayVisible {
                finishTurnChangeOverlay()
            } else if showGameplayStartIntro {
                showGameplayStartIntro = false
                resumeGameplayQRAfterLoad()
            } else if financesChangePresentation != nil {
                advanceFinancesChangeQueue()
            } else if let bossVictoryPresentation {
                finishBossVictoryOverlay(bossVictoryPresentation)
            } else if isSpecialCardDrawVisible, specialCardDrawRevealed {
                finishSpecialCardDraw()
            } else if isArtifactDrawVisible, artifactDrawRevealed {
                finishArtifactDraw()
            } else {
                switch startFieldPhase {
                case .stayingReward, .stayingFullHealthReward, .passingCoinReward:
                    finishStartFieldStay()
                case .choiceEffectsReveal:
                    finishChoiceEffectsReveal()
                default:
                    if !fallenPlayerQueue.isEmpty {
                        advanceFallenPlayerOverlay()
                    }
                }
            }
            trikiCoordinator.statusMessage = "Wciśnięto: Kontynuuj."
        case .queueSkipTurn:
            skipBlockedQueueTurn()
            trikiCoordinator.statusMessage = "Wciśnięto: Pomiń turę."
        case .shopBuy:
            settings.playTapSound()
            shopPhase = .buy
            reconcileTrikiSelection(resetToFirst: true)
            trikiCoordinator.statusMessage = "Wciśnięto: Kup."
        case .shopSell:
            settings.playTapSound()
            shopPhase = .sell
            reconcileTrikiSelection(resetToFirst: true)
            trikiCoordinator.statusMessage = "Wciśnięto: Sprzedaj."
        case .shopBack:
            settings.playTapSound()
            shopPhase = .menu
            reconcileTrikiSelection(resetToFirst: true)
            trikiCoordinator.statusMessage = "Wciśnięto: Wróć."
        case .shopExit:
            finishShop()
            trikiCoordinator.statusMessage = "Wciśnięto: Wyjdź ze sklepu."
        case .shopPurchase(let itemID):
            guard let item = shopStockItems.first(where: { $0.id == itemID }) else { return }
            settings.playTapSound()
            purchaseShopItem(item)
            trikiCoordinator.statusMessage = "Wciśnięto: \(item.name)."
        case .shopSellItem(let itemID):
            guard let item = ownedShopItems.first(where: { $0.id == itemID }) else { return }
            settings.playTapSound()
            sellShopItem(item)
            trikiCoordinator.statusMessage = "Wciśnięto: Sprzedaj \(item.name)."
        case .powerPathOption:
            powerPathTrikiActivationTrigger += 1
            trikiCoordinator.statusMessage = "Wciśnięto: \(trikiButtonTitle(button))."
        case .equipmentToggle(let itemID):
            guard let activePlayer,
                  let item = ownedShopItems.first(where: { $0.id == itemID }) else { return }
            settings.playTapSound()
            _ = toggleEquipItem(item, for: activePlayer.id)
            trikiCoordinator.statusMessage = "Wciśnięto: \(item.name)."
        case .equipmentExit:
            settings.playTapSound()
            showPlayerItemsOverlay = false
            trikiCoordinator.statusMessage = "Wciśnięto: Wyjdź."
        case .statsExit:
            settings.playTapSound()
            showPlayerStatsOverlay = false
        case .abilitiesExit:
            settings.playTapSound()
            showSessionAbilitiesOverlay = false
            showYourSkillsOverlay = false
            syncGameplayQRScanningState()
            trikiCoordinator.statusMessage = "Wciśnięto: Wyjdź."
        case .finishCampaign:
            settings.playTapSound()
            finishCampaignSession()
            trikiCoordinator.statusMessage = "Wciśnięto: Zakończ."
        case .switchToGameplayTab:
            settings.playTapSound()
            inGameScreen = .gameplay
            trikiCoordinator.statusMessage = "Wciśnięto: Gra."
        }
    }

    private func openYourSkillsOverlay() {
        guard activePlayer != nil else { return }
        showYourSkillsOverlay = true
        syncGameplayQRScanningState()
        if let activePlayer {
            turnState.logCustomEvent(
                playerName: activePlayer.className,
                message: "Otwarto: Twoje Umiejętności.",
                turnMessage: "Twoje Umiejętności — wybierz umiejętność (raz na okrążenie)."
            )
        }
    }

    private func triggerTrikiStealAbility() {
        guard let activePlayer else { return }
        let financesBefore = playerStats.mapValues(\.finances)
        if let result = PowerPathEngine.tryDarkAuraTheft(
            actorID: activePlayer.id,
            players: players,
            positions: playerBoardPositions,
            stats: &playerStats,
            progress: &playerPowerPathProgress,
            lapUsage: &playerLapAbilityUsage
        ) {
            if shouldAnimateFinancesChangesAutomatically {
                for (playerID, afterStats) in playerStats {
                    guard let before = financesBefore[playerID] else { continue }
                    let delta = afterStats.finances - before
                    queueFinancesChangeAnimation(delta: delta)
                }
            }
            turnState.logCustomEvent(playerName: activePlayer.className, message: result.message)
            trikiCoordinator.statusMessage = result.message
        } else {
            trikiCoordinator.statusMessage = "Nie można użyć okradania w tym momencie."
        }
    }

    private func canDismissGameEventOverlayViaQR(_ event: QRGameEventCode) -> Bool {
        if pendingEventIntro == event { return false }

        switch event {
        case .startField:
            switch startFieldPhase {
            case .stayingReward, .stayingFullHealthReward, .passingCoinReward, .choiceEffectsReveal:
                return true
            default:
                return false
            }
        case .artifact:
            return artifactDrawSession != nil && artifactDrawRevealed
        case .specialCard:
            return specialCardDrawSession != nil && specialCardDrawRevealed
        case .shop:
            return shopPhase != .hidden
        case .xpShop:
            return isXpShopResultReady
        case .bossFight:
            return showBossFightAR
        case .arenaPvP:
            return showArenaPvPAR
        }
    }

    private func completeGameEventOverlayViaQR(_ event: QRGameEventCode) {
        switch event {
        case .startField:
            switch startFieldPhase {
            case .stayingReward, .stayingFullHealthReward, .passingCoinReward:
                finishStartFieldStay()
            case .choiceEffectsReveal:
                finishChoiceEffectsReveal()
            default:
                break
            }
        case .artifact:
            finishArtifactDraw()
        case .specialCard:
            finishSpecialCardDraw()
        case .shop:
            finishShop()
        case .xpShop:
            finishXpShop()
        case .bossFight:
            showBossFightAR = false
        case .arenaPvP:
            showArenaPvPAR = false
            isArenaPvPActive = false
        }
    }

    private func isGameEventOverlayActive(_ event: QRGameEventCode) -> Bool {
        if pendingEventIntro == event { return true }

        switch event {
        case .startField:
            return startFieldPhase != .hidden
        case .artifact:
            return artifactDrawSession != nil
        case .bossFight:
            return showBossFightAR
        case .arenaPvP:
            return showArenaPvPAR
        case .shop:
            return shopPhase != .hidden
        case .xpShop:
            return xpShopPhase != .hidden
        case .specialCard:
            return specialCardDrawSession != nil
        }
    }

    private func finishEventIntro() {
        guard let event = pendingEventIntro else { return }
        pendingEventIntro = nil

        if event == .specialCard {
            beginSpecialCardDraw()
            return
        }

        if event == .artifact {
            beginArtifactDraw()
            return
        }

        if event == .shop {
            beginShop()
            return
        }

        if event == .xpShop {
            beginXpShop()
            return
        }

        applyScannedGameEvent(event)
    }

    private func beginShop() {
        guard let activePlayer else { return }
        let catalog = creatorStore.catalog.items.filter {
            !playerOwnsShopItem($0, playerID: activePlayer.id)
        }
        let count = min(creatorStore.gameRules.shop.maxOffers, max(catalog.count, 0))
        shopStockItems = Array(catalog.shuffled().prefix(count))
        shopPhase = .menu
        settings.playShopOpenSound()
    }

    private func finishShop() {
        guard let activePlayer else {
            shopPhase = .hidden
            shopStockItems = []
            return
        }

        shopPhase = .hidden
        shopStockItems = []
        lastEventResult = .shop
        lastSpecialCardDetail = ""
        startFieldPhase = .hidden

        turnState.logCustomEvent(
            playerName: activePlayer.className,
            message: "Odwiedził sklepik handlowy.",
            turnMessage: "Gracz \(turnState.currentPlayerNumber) (\(activePlayer.className)) — Sklepik handlowy."
        )
        advanceTurnWithReveal()
        recommendations = [:]
    }

    private func beginXpShop() {
        guard activePlayer != nil else { return }
        xpShopPhase = .menu
        settings.playShopOpenSound()
    }

    private func finishXpShop() {
        guard let activePlayer else {
            xpShopPhase = .hidden
            pendingXpShopRoll = nil
            return
        }

        switch xpShopPhase {
        case .menu, .revealedFiftyFifty, .revealedRandomAbility:
            break
        default:
            return
        }

        xpShopPhase = .hidden
        pendingXpShopRoll = nil
        lastEventResult = .xpShop
        lastSpecialCardDetail = ""
        startFieldPhase = .hidden

        turnState.logCustomEvent(
            playerName: activePlayer.className,
            message: "Odwiedził Sklepik XP.",
            turnMessage: "Gracz \(turnState.currentPlayerNumber) (\(activePlayer.className)) — Sklepik XP."
        )
        advanceTurnWithReveal()
        recommendations = [:]
    }

    private func purchaseXpShopFiftyFifty(for player: PlayerCharacter) {
        guard xpShopPhase == .menu else { return }
        guard PowerPathEngine.spendExperience(
            XPShopCost.fiftyFifty,
            playerID: player.id,
            progress: &playerPowerPathProgress
        ) else { return }

        settings.playShopPurchaseSound()
        let roll = resolveXpShopFiftyFiftyRoll(for: player)
        pendingXpShopRoll = .fiftyFifty(roll)
        xpShopPhase = .drawingFiftyFifty(roll)
    }

    private func purchaseXpShopRandomAbility(for player: PlayerCharacter) {
        guard xpShopPhase == .menu else { return }
        guard PowerPathEngine.spendExperience(
            XPShopCost.randomAbility,
            playerID: player.id,
            progress: &playerPowerPathProgress
        ) else { return }

        settings.playShopPurchaseSound()
        let roll = resolveXpShopRandomAbilityRoll(for: player)
        pendingXpShopRoll = .randomAbility(roll)
        xpShopPhase = .drawingRandomAbility(roll)
    }

    private func completeXpShopDraw(for player: PlayerCharacter) {
        guard let pending = pendingXpShopRoll else { return }

        let message: String
        let logPrefix: String
        switch pending {
        case .fiftyFifty(let roll):
            message = applyXpShopFiftyFiftyRoll(roll, to: player)
            logPrefix = "Sklepik XP — 50 na 50"
        case .randomAbility(let roll):
            message = applyXpShopRandomAbilityRoll(roll, to: player)
            logPrefix = "Sklepik XP — losowa zdolność"
        }

        pendingXpShopRoll = nil
        switch pending {
        case .fiftyFifty(let roll):
            xpShopPhase = .revealedFiftyFifty(roll)
        case .randomAbility(let roll):
            xpShopPhase = .revealedRandomAbility(roll)
        }
        turnState.logCustomEvent(
            playerName: player.className,
            message: "\(logPrefix): \(message)"
        )
    }

    private func resolveXpShopFiftyFiftyRoll(for player: PlayerCharacter) -> XPShopFiftyFiftyRoll {
        if Bool.random() {
            if let ability = sessionAbilityPool.peekRandom(for: player.id) {
                return XPShopFiftyFiftyRoll(kind: .ability(ability))
            }
            return XPShopFiftyFiftyRoll(kind: .emptyAbilityPool)
        }
        let unlucky = XPShopUnluckyKind.allCases.randomElement() ?? .halveFinances
        return XPShopFiftyFiftyRoll(kind: .unlucky(unlucky))
    }

    private func resolveXpShopRandomAbilityRoll(for player: PlayerCharacter) -> XPShopRandomAbilityRoll {
        if let ability = sessionAbilityPool.peekRandom(for: player.id) {
            return XPShopRandomAbilityRoll(kind: .ability(ability))
        }
        return XPShopRandomAbilityRoll(kind: .emptyPool)
    }

    private func applyXpShopFiftyFiftyRoll(_ roll: XPShopFiftyFiftyRoll, to player: PlayerCharacter) -> String {
        switch roll.kind {
        case .ability(let ability):
            if grantSessionAbility(ability, to: player) != nil {
                return "Szczęście! Zdobyto zdolność: \(ability.name)."
            }
            return "Szczęście, ale pula zdolności jest już wyczerpana."
        case .emptyAbilityPool:
            return "Szczęście, ale pula zdolności jest już wyczerpana."
        case .unlucky(let kind):
            return applyXpShopUnluckyOutcome(kind, to: player)
        }
    }

    private func applyXpShopRandomAbilityRoll(_ roll: XPShopRandomAbilityRoll, to player: PlayerCharacter) -> String {
        switch roll.kind {
        case .ability(let ability):
            if grantSessionAbility(ability, to: player) != nil {
                return "Kupiono losową zdolność: \(ability.name)."
            }
            return "Brak wolnych zdolności w puli sesji."
        case .emptyPool:
            return "Brak wolnych zdolności w puli sesji."
        }
    }

    @discardableResult
    private func grantSessionAbility(
        _ ability: GameplaySessionAbility,
        to player: PlayerCharacter
    ) -> GameplaySessionAbility? {
        var ids = playerGrantedAbilityIDs[player.id] ?? []
        defer { playerGrantedAbilityIDs[player.id] = ids.isEmpty ? nil : ids }

        guard let granted = sessionAbilityPool.grant(ability, to: player.id) else { return nil }

        if !ids.contains(granted.id) {
            ids.append(granted.id)
            syncAbilityStatCount(for: player.id)
        } else {
            checkSessionWinCondition()
        }

        turnState.logCustomEvent(
            playerName: player.className,
            message: "Zdobyto zdolność sesji: \(granted.name) (\(granted.kindLabel))."
        )
        return granted
    }

    private func applyXpShopUnluckyOutcome(_ outcome: XPShopUnluckyKind, to player: PlayerCharacter) -> String {
        switch outcome {
        case .halveFinances:
            guard var stats = playerStats[player.id] else { return "Pech: brak finansów do utraty." }
            let before = stats.finances
            stats.finances = max(0, stats.finances / 2)
            updatePlayerFinances(stats.finances, for: player.id)
            return "Pech: −50% finansów (\(before) → \(stats.finances) monet)."

        case .queueBlock:
            let total = (playerQueueBlockRounds[player.id] ?? 0) + 4
            playerQueueBlockRounds[player.id] = total
            return "Pech: blokada kolejki na 4 tury."

        case .weakenStrength:
            applyTemporaryStrengthDebuff(to: player.id, amount: 12, turns: 5)
            return "Pech: osłabienie siły na 5 tur."

        case .loseRandomAbility:
            var ids = playerGrantedAbilityIDs[player.id] ?? []
            guard let removedID = ids.randomElement() else {
                return "Pech: brak zdolności do utraty."
            }
            ids.removeAll { $0 == removedID }
            playerGrantedAbilityIDs[player.id] = ids.isEmpty ? nil : ids
            if sessionAbilityPool.ability(id: removedID) != nil {
                sessionAbilityPool.consume(abilityID: removedID, from: player.id)
            }
            syncAbilityStatCount(for: player.id)
            let name = creatorStore.catalog.abilities.first(where: { $0.id == removedID })?.name
                ?? sessionAbilityPool.ability(id: removedID)?.name
                ?? "zdolność"
            return "Pech: utrata zdolności „\(name)”."

        case .halveStrength:
            guard var stats = playerStats[player.id] else { return "Pech: brak siły do osłabienia." }
            let before = stats.strength
            stats.strength = max(0, stats.strength / 2)
            setPlayerStats(stats, for: player.id)
            return "Pech: −50% siły (\(before) → \(stats.strength))."

        case .halveHealth:
            guard var stats = playerStats[player.id] else { return "Pech: brak zdrowia do utraty." }
            let before = stats.health
            stats.health = max(0, stats.health / 2)
            setPlayerStats(stats, for: player.id)
            return "Pech: −50% zdrowia (\(before) → \(stats.health))."

        case .removeRandomItem:
            var owned = playerGrantedItemIDs[player.id] ?? []
            guard let removedID = owned.randomElement(),
                  let item = creatorStore.catalog.items.first(where: { $0.id == removedID }) else {
                return "Pech: brak przedmiotu do usunięcia."
            }
            owned.removeAll { $0 == removedID }
            playerGrantedItemIDs[player.id] = owned.isEmpty ? nil : owned
            unequipIfNeeded(itemID: removedID, for: player.id)
            PlayerOwnedItemValues.removeItem(
                playerID: player.id,
                itemID: removedID,
                values: &playerOwnedItemValues
            )
            return "Pech: usunięto przedmiot „\(item.name)”."
        }
    }

    private func applyTemporaryStrengthDebuff(to playerID: UUID, amount: Int, turns: Int) {
        guard amount > 0, turns > 0, var stats = playerStats[playerID] else { return }
        stats.strength = max(0, stats.strength - amount)
        setPlayerStats(stats, for: playerID)

        var boosts = activeTemporaryBoosts[playerID] ?? []
        boosts.append(
            ActiveTemporaryBoost(
                target: .character,
                turnsRemaining: turns,
                strengthDelta: -amount
            )
        )
        activeTemporaryBoosts[playerID] = boosts
    }

    private func purchaseShopItem(_ item: CreatedItem) {
        guard let activePlayer, var stats = playerStats[activePlayer.id] else { return }
        guard stats.finances >= item.cost else { return }
        guard !playerOwnsShopItem(item, playerID: activePlayer.id) else { return }

        stats.finances = max(0, stats.finances - item.cost)
        updatePlayerFinances(stats.finances, for: activePlayer.id)
        addOwnedShopItem(item, for: activePlayer.id)
        shopStockItems.removeAll { $0.numericId == item.numericId }

        settings.playShopPurchaseSound()

        turnState.logCustomEvent(
            playerName: activePlayer.className,
            message: "Kupiono: \(item.name) za \(item.cost) monet."
        )
    }

    private func sellShopItem(_ item: CreatedItem) {
        guard let activePlayer, var stats = playerStats[activePlayer.id] else { return }
        var owned = playerGrantedItemIDs[activePlayer.id] ?? []
        guard owned.contains(item.id) else { return }

        let sellPrice = effectiveItemValue(item, for: activePlayer.id)
        _ = applyCursedCoinGain(sellPrice, to: activePlayer.id, stats: &stats)
        setPlayerStats(stats, for: activePlayer.id, financesAnimation: .automatic)
        owned.removeAll { $0 == item.id }
        playerGrantedItemIDs[activePlayer.id] = owned
        unequipIfNeeded(itemID: item.id, for: activePlayer.id)
        PlayerOwnedItemValues.removeItem(
            playerID: activePlayer.id,
            itemID: item.id,
            values: &playerOwnedItemValues
        )

        settings.playShopSellSound()

        turnState.logCustomEvent(
            playerName: activePlayer.className,
            message: "Sprzedano: \(item.name) za \(sellPrice) monet."
        )
    }

    private func beginArtifactDraw() {
        guard let activePlayer else { return }
        artifactDrawRevealed = false
        let outcome = ArtifactDrawRoller.roll(
            itemsCatalog: creatorStore.catalog.items,
            abilitiesCatalog: gameplayAbilityCatalog,
            existingItemIDs: playerGrantedItemIDs[activePlayer.id] ?? [],
            existingAbilityIDs: playerGrantedAbilityIDs[activePlayer.id] ?? [],
            rules: creatorStore.gameRules.artifact,
            pickSessionAbility: { [self] in
                grantGameplaySessionAbility(to: activePlayer)
            }
        )
        artifactDrawSession = ArtifactDrawSession(player: activePlayer, outcome: outcome)
    }

    private func artifactDetailText(
        for outcome: ArtifactOutcome,
        applyResult: ArtifactDrawApplier.ApplyResult
    ) -> String {
        var parts = ["\(outcome.title) — \(applyResult.detailMessage)"]
        if let brushBonusSummary = outcome.brushBonusSummary {
            parts.append(brushBonusSummary)
        }
        return parts.joined(separator: " · ")
    }

    private func finishArtifactDraw() {
        guard let session = artifactDrawSession else { return }
        artifactDrawSession = nil
        artifactDrawRevealed = false

        let playerID = session.player.id
        guard var stats = playerStats[playerID] else { return }
        let financesBefore = stats.finances

        var abilityIDs = playerGrantedAbilityIDs[playerID] ?? []
        let previousItemIDs = playerGrantedItemIDs[playerID] ?? []
        var itemIDs = previousItemIDs
        var queueBlock = playerQueueBlockRounds[playerID] ?? 0

        let result = ArtifactDrawApplier.apply(
            outcome: session.outcome,
            stats: &stats,
            abilityIDs: &abilityIDs,
            itemIDs: &itemIDs,
            queueBlockRounds: &queueBlock
        )
        reconcileCoinGainWithCurse(playerID: playerID, beforeFinances: financesBefore, stats: &stats)

        setPlayerStats(stats, for: playerID, financesAnimation: .suppressed)
        guard players.contains(where: { $0.id == playerID }) else {
            lastEventResult = .artifact
            lastArtifactDetail = artifactDetailText(for: session.outcome, applyResult: result)
            lastSpecialCardDetail = ""
            startFieldPhase = .hidden
            turnState.logCustomEvent(
                playerName: session.player.className,
                message: "Artefakt: \(session.outcome.title). \(result.detailMessage)",
                turnMessage: "\(session.player.displayTitle) odpada z gry."
            )
            recommendations = [:]
            return
        }

        playerGrantedAbilityIDs[playerID] = abilityIDs
        syncAbilityStatCount(for: playerID)
        playerGrantedItemIDs[playerID] = itemIDs
        syncOwnedItemValues(for: playerID, previousItemIDs: previousItemIDs, newItemIDs: itemIDs)
        if let grantedItemID = result.grantedItemID,
           let item = creatorStore.catalog.items.first(where: { $0.id == grantedItemID }) {
            PlayerOwnedItemValues.setValue(
                item.cost,
                playerID: playerID,
                itemID: grantedItemID,
                values: &playerOwnedItemValues
            )
        }
        if queueBlock > 0 {
            playerQueueBlockRounds[playerID] = queueBlock
        } else {
            playerQueueBlockRounds.removeValue(forKey: playerID)
        }

        let artifactXP = PowerPathEngine.grantArtifactExperience(
            playerID: playerID,
            progress: &playerPowerPathProgress,
            amount: creatorStore.gameRules.artifact.drawXP
        )

        lastEventResult = .artifact
        var artifactDetail = artifactDetailText(for: session.outcome, applyResult: result)
        if let xpNote = PowerPathEngine.experienceChangeDescription(applied: artifactXP) {
            artifactDetail += " · \(xpNote)"
        }
        lastArtifactDetail = artifactDetail
        lastSpecialCardDetail = ""
        startFieldPhase = .hidden

        var artifactLog = "Artefakt: \(session.outcome.title). \(result.detailMessage)"
        if let xpNote = PowerPathEngine.experienceChangeDescription(applied: artifactXP) {
            artifactLog += " \(xpNote)"
        }
        turnState.logCustomEvent(
            playerName: session.player.className,
            message: artifactLog,
            turnMessage: "Gracz \(turnState.currentPlayerNumber) (\(session.player.className)) — \(session.outcome.title)."
        )
        guard players.contains(where: { $0.id == playerID }) else {
            recommendations = [:]
            return
        }
        advanceTurnWithReveal()
        recommendations = [:]
    }

    private func beginSpecialCardDraw() {
        guard let activePlayer else { return }
        specialCardDrawRevealed = false
        let card = SpecialCardDefinition.randomDraw(rules: creatorStore.gameRules.specialCard)
        specialCardDrawSession = SpecialCardDrawSession(player: activePlayer, card: card)
    }

    private func finishSpecialCardDraw() {
        guard let session = specialCardDrawSession else { return }
        specialCardDrawSession = nil
        specialCardDrawRevealed = false

        let playerID = session.player.id
        guard var stats = playerStats[playerID] else { return }
        let financesBefore = stats.finances

        if PowerPathEngine.shouldIgnoreNegativeSpecialCard(
            playerID: playerID,
            card: session.card,
            progress: playerPowerPathProgress
        ) {
            lastEventResult = .specialCard
            lastSpecialCardDetail = "\(session.card.title) — Ochrona: zignorowano negatywny efekt."
            startFieldPhase = .hidden
            turnState.logCustomEvent(
                playerName: session.player.className,
                message: "Karta specjalna: \(session.card.title). Ochrona z Ścieżki Mocy.",
                turnMessage: "Gracz \(turnState.currentPlayerNumber) (\(session.player.className)) — ochrona przed kartą."
            )
            guard players.contains(where: { $0.id == playerID }) else {
                recommendations = [:]
                return
            }
            advanceTurnWithReveal()
            recommendations = [:]
            return
        }

        var abilityIDs = playerGrantedAbilityIDs[playerID] ?? []
        let previousAbilityIDs = abilityIDs
        let previousItemIDs = playerGrantedItemIDs[playerID] ?? []
        var itemIDs = previousItemIDs
        var queueBlock = playerQueueBlockRounds[playerID] ?? 0

        let result = SpecialCardApplier.apply(
            card: session.card,
            stats: &stats,
            abilityIDs: &abilityIDs,
            itemIDs: &itemIDs,
            queueBlockRounds: &queueBlock,
            abilitiesCatalog: gameplayAbilityCatalog,
            itemsCatalog: creatorStore.catalog.items,
            grantAbility: { ids in
                grantGameplayAbility(to: session.player, abilityIDs: &ids)
            }
        )
        reconcileCoinGainWithCurse(playerID: playerID, beforeFinances: financesBefore, stats: &stats)

        setPlayerStats(stats, for: playerID, financesAnimation: .suppressed)
        guard players.contains(where: { $0.id == playerID }) else {
            lastEventResult = .specialCard
            lastSpecialCardDetail = "\(session.card.title) — \(result.detailMessage)"
            startFieldPhase = .hidden
            turnState.logCustomEvent(
                playerName: session.player.className,
                message: "Karta specjalna: \(session.card.title). \(result.detailMessage)",
                turnMessage: "\(session.player.displayTitle) odpada z gry."
            )
            recommendations = [:]
            return
        }

        playerGrantedAbilityIDs[playerID] = abilityIDs
        syncAbilityStatCount(for: playerID)
        syncSessionPoolAfterAbilityListChange(
            playerID: playerID,
            previous: previousAbilityIDs,
            updated: abilityIDs
        )
        playerGrantedItemIDs[playerID] = itemIDs
        syncOwnedItemValues(for: playerID, previousItemIDs: previousItemIDs, newItemIDs: itemIDs)
        if queueBlock > 0 {
            playerQueueBlockRounds[playerID] = queueBlock
        } else {
            playerQueueBlockRounds.removeValue(forKey: playerID)
        }

        let cardXP = PowerPathEngine.grantSpecialCardExperience(
            card: session.card,
            playerID: playerID,
            progress: &playerPowerPathProgress,
            positiveXP: creatorStore.gameRules.specialCard.positiveXP,
            negativeXP: creatorStore.gameRules.specialCard.negativeXP
        )

        lastEventResult = .specialCard
        var cardDetail = "\(session.card.title) — \(result.detailMessage)"
        if let xpNote = PowerPathEngine.experienceChangeDescription(applied: cardXP) {
            cardDetail += " · \(xpNote)"
        }
        lastSpecialCardDetail = cardDetail
        startFieldPhase = .hidden

        var cardLog = "Karta specjalna: \(session.card.title). \(result.detailMessage)"
        if let xpNote = PowerPathEngine.experienceChangeDescription(applied: cardXP) {
            cardLog += " \(xpNote)"
        }
        turnState.logCustomEvent(
            playerName: session.player.className,
            message: cardLog,
            turnMessage: "Gracz \(turnState.currentPlayerNumber) (\(session.player.className)) — \(session.card.title)."
        )
        guard players.contains(where: { $0.id == playerID }) else {
            recommendations = [:]
            return
        }
        advanceTurnWithReveal()
        recommendations = [:]
    }

    private func syncSessionPoolAfterAbilityListChange(
        playerID: UUID,
        previous: [UUID],
        updated: [UUID]
    ) {
        let removed = Set(previous).subtracting(updated)
        for abilityID in removed {
            if sessionAbilityPool.ability(id: abilityID) != nil {
                sessionAbilityPool.consume(abilityID: abilityID, from: playerID)
            }
        }
    }

    private func applyScannedGameEvent(_ event: QRGameEventCode) {
        reconcileLiveCreatorCatalog()
        guard let activePlayer else { return }

        if event == .startField {
            lastEventResult = event
            sceneIndex = activePlayerSceneIndex()
            startFieldPhase = .choosing
            recommendations = [:]
            return
        }

        lastEventResult = event
        startFieldPhase = .hidden

        if event == .bossFight {
            isBossFightActive = true
            _ = grantSessionAbility(to: activePlayer)
            showBossFightAR = true
            turnState.logCustomEvent(
                playerName: activePlayer.className,
                message: "Rozpoczęto walkę z bossem — tryb AR (skan QR gracza i walka turowa).",
                turnMessage: "Walka z bossem — skanuj QR gracza w trybie AR."
            )
            recommendations = [:]
            return
        }

        if event == .arenaPvP {
            isArenaPvPActive = true
            showArenaPvPAR = true
            turnState.logCustomEvent(
                playerName: activePlayer.className,
                message: "Arena PvP — zeskanuj dwóch graczy w AR, potem walka na energię.",
                turnMessage: "Arena PvP — skanuj QR graczy (4001–4004)."
            )
            recommendations = [:]
            return
        }

        if var stats = playerStats[activePlayer.id] {
            stats.apply(event: event)
            setPlayerStats(stats, for: activePlayer.id)
        }
        guard players.contains(where: { $0.id == activePlayer.id }) else { return }
        lastSpecialCardDetail = ""
        lastArtifactDetail = ""
        let previousRound = turnState.roundNumber
        turnState.applyGameEvent(event, activePlayer: activePlayer, totalPlayers: players.count)
        presentTurnChangeOverlay(highlightNewRound: turnState.roundNumber > previousRound)
        recommendations = [:]
    }

    private func skipActiveTurn() {
        guard let activePlayer else { return }
        guard activeQueueBlockRounds == 0 else { return }
        skipTurnPlayerName = activePlayer.displayTitle
    }

    private func skipBlockedQueueTurn() {
        guard let activePlayer else { return }
        settings.playSkipTurnSound()

        if let remaining = playerQueueBlockRounds[activePlayer.id], remaining > 1 {
            playerQueueBlockRounds[activePlayer.id] = remaining - 1
        } else {
            playerQueueBlockRounds.removeValue(forKey: activePlayer.id)
        }

        lastEventResult = nil
        lastSpecialCardDetail = ""
        startFieldPhase = .hidden
        turnState.skipTurn(activePlayer: activePlayer, totalPlayers: players.count)
        recommendations = [:]
        presentTurnChangeOverlay()
    }

    private func finishSkipTurnOverlay() {
        guard let skippingPlayer = activePlayer else {
            skipTurnPlayerName = nil
            return
        }

        lastEventResult = nil
        lastSpecialCardDetail = ""
        startFieldPhase = .hidden
        let previousRound = turnState.roundNumber
        turnState.skipTurn(activePlayer: skippingPlayer, totalPlayers: players.count)
        recommendations = [:]
        skipTurnPlayerName = nil
        presentTurnChangeOverlay(highlightNewRound: turnState.roundNumber > previousRound)
    }

    private func advanceTurnWithReveal() {
        let previousRound = turnState.roundNumber
        turnState.advanceToNextPlayer(totalPlayers: players.count)
        presentTurnChangeOverlay(highlightNewRound: turnState.roundNumber > previousRound)
    }

    private func resumeGameplayQRAfterLoad() {
        turnState.clampCurrentPlayerIndex(activePlayerCount: players.count)

        guard inGameScreen == .gameplay, !campaignStoryFinished else { return }

        if isStartFieldOverlayVisible {
            canScanGameplayQR = false
            return
        }

        guard turnChangePresentation == nil else { return }

        if activePlayer != nil {
            presentTurnChangeOverlay()
        } else {
            syncGameplayQRScanningState()
        }
    }

    private func presentInitialTurnRevealIfNeeded() {
        guard inGameScreen == .gameplay, !campaignStoryFinished else { return }
        guard turnChangePresentation == nil else { return }
        if activePlayer != nil {
            presentTurnChangeOverlay()
        } else {
            syncGameplayQRScanningState()
        }
    }

    private func syncGameplayQRScanningState() {
        let blocked =
            inGameScreen != .gameplay
            || campaignStoryFinished
            || showGameplayStartIntro
            || isBossFightActive
            || isArenaPvPActive
            || showBossFightAR
            || showArenaPvPAR
            || turnChangePresentation != nil
            || skipTurnPlayerName != nil
            || specialCardDrawSession != nil
            || artifactDrawSession != nil
            || pendingEventIntro != nil
            || isStartFieldOverlayVisible
            || bossVictoryPresentation != nil
            || !fallenPlayerQueue.isEmpty
            || isShopOverlayVisible
            || isXpShopOverlayVisible
            || isPowerPathOverlayVisible
            || showSessionAbilitiesOverlay
            || showYourSkillsOverlay
            || powerPathSkillUsePresentation != nil
            || showFinalTurnIntro

        canScanGameplayQR = !blocked && activePlayer != nil
    }

    private func glowColor(for player: PlayerCharacter?) -> PlayerGlowColor {
        PlayerGlowColor.resolve(
            storedGlow: player?.glowColor,
            lobbySlotNumber: player?.lobbySlotNumber,
            slotStore: playerSlotStore,
            settings: settings
        )
    }

    private func applyTurnGlow(animated: Bool) {
        let target = glowColor(for: activePlayer)
        if animated {
            withAnimation(.easeInOut(duration: 0.5)) {
                turnGlowColor = target
            }
        } else {
            turnGlowColor = target
        }
    }

    private func presentTurnChangeOverlay(highlightNewRound: Bool? = nil) {
        if showFinalTurnIntro {
            syncGameplayQRScanningState()
            return
        }

        if shouldCompleteSessionAfterFinalRound() {
            completeSessionGame()
            return
        }

        guard let player = activePlayer else {
            syncGameplayQRScanningState()
            return
        }
        canScanGameplayQR = false
        let isNewRound = highlightNewRound ?? false
        turnChangePresentation = TurnChangePresentation(
            playerNumber: turnState.currentPlayerNumber,
            playerName: player.displayTitle,
            factionName: player.factionName,
            roundNumber: turnState.roundNumber,
            isNewRound: isNewRound,
            lobbySlotNumber: player.lobbySlotNumber,
            characterQRCode: player.qrCode,
            glowColor: glowColor(for: player)
        )
    }

    private func finishTurnChangeOverlay() {
        turnChangePresentation = nil
        syncGameplayQRScanningState()
    }

    private func selectChoice(_ choice: String, choiceIndex: Int, activePlayer: PlayerCharacter) {
        let decisionIdx = resolvedDecisionIndex
        selectedChoices[activePlayer.id] = choice
        thinkingService.playthroughStore.record(
            campaign: campaign,
            decisionIndex: decisionIdx,
            playerSlot: activePlayerIndex,
            choiceIndex: choiceIndex,
            choiceText: choice
        )

        guard startFieldPhase == .passingDecisions else { return }

        let detail = campaign.decisions[safe: decisionIdx]?
            .choiceDetail(forPlayerIndex: activePlayerIndex, choiceIndex: choiceIndex)
        let presentation = ChoiceEffectsPresentation.from(choice: detail, fallbackLabel: choice)

        if var stats = playerStats[activePlayer.id] {
            if let detail {
                var effects = detail.resolvedEffects
                let (coins, curseMessage) = PowerPathEngine.applyRewardMultiplier(
                    playerID: activePlayer.id,
                    baseCoins: effects.coins,
                    progress: &playerPowerPathProgress
                )
                effects.coins = coins
                stats.apply(effects: effects)
                if let curseMessage {
                    turnState.logCustomEvent(playerName: activePlayer.className, message: curseMessage)
                }
            }
            applyStartFieldPassCoins(for: activePlayer.id, stats: &stats)
            setPlayerStats(stats, for: activePlayer.id)
        }

        if let detail, ChoiceEffectsPresentation.impliesItemLoss(from: detail.disadvantage) {
            removeRandomOwnedItem(for: activePlayer.id, playerName: activePlayer.displayTitle)
        }

        if let detail {
            applyQueueBlockFromCampaignEffects(
                detail.resolvedEffects,
                playerID: activePlayer.id,
                playerName: activePlayer.displayTitle
            )

            if let nextScene = campaign.resolveNextSceneIndex(
                choice: detail,
                decisionRound: decisionIdx,
                choiceIndex: choiceIndex
            ) {
                playerSceneIndices[activePlayer.id] = nextScene
                sceneIndex = nextScene
            }
        }

        guard players.contains(where: { $0.id == activePlayer.id }) else { return }

        grantSessionAbility(to: activePlayer)
        pendingPassChoiceText = choice
        startFieldPhase = .choiceEffectsReveal(presentation)
        recommendations = [:]
    }

    private var sessionAbilityCatalog: [CreatedAbility] {
        sessionAbilityPool.abilities.map(\.asCreatedAbility)
    }

    private var gameplayAbilityCatalog: [CreatedAbility] {
        GameplayLiveCatalogSync.mergedAbilityCatalog(
            creatorAbilities: creatorStore.catalog.abilities,
            sessionPool: sessionAbilityPool
        )
    }

    private func reconcileLiveCreatorCatalog() {
        let abilityIDs = GameplayLiveCatalogSync.validAbilityIDs(
            creatorAbilities: creatorStore.catalog.abilities,
            sessionPool: sessionAbilityPool
        )
        let itemIDs = GameplayLiveCatalogSync.validItemIDs(items: creatorStore.catalog.items)
        let pathIDs = GameplayLiveCatalogSync.validPowerPathIDs(paths: creatorStore.catalog.powerPaths)
        let upgradeIDs = GameplayLiveCatalogSync.validUpgradeIDs(paths: creatorStore.catalog.powerPaths)

        GameplayLiveCatalogSync.pruneGrantedAbilities(&playerGrantedAbilityIDs, validIDs: abilityIDs)
        GameplayLiveCatalogSync.pruneGrantedItems(&playerGrantedItemIDs, validIDs: itemIDs)
        GameplayLiveCatalogSync.pruneEquipment(&playerEquippedItems, validItemIDs: itemIDs)
        GameplayLiveCatalogSync.prunePowerPathProgress(
            &playerPowerPathProgress,
            validPathIDs: pathIDs,
            validUpgradeIDs: upgradeIDs
        )
        for player in players {
            syncAbilityStatCount(for: player.id)
        }
    }

    @discardableResult
    private func grantGameplaySessionAbility(to player: PlayerCharacter) -> GameplaySessionAbility? {
        grantSessionAbility(to: player)
    }

    @discardableResult
    private func grantGameplayAbility(
        to player: PlayerCharacter,
        abilityIDs: inout [UUID]
    ) -> CreatedAbility? {
        if let ability = PlayerAbilityGranting.grantRandom(
            catalog: creatorStore.catalog.abilities,
            existingIDs: abilityIDs
        ) {
            if !abilityIDs.contains(ability.id) {
                abilityIDs.append(ability.id)
            }
            syncAbilityStatCount(for: player.id)
            turnState.logCustomEvent(
                playerName: player.className,
                message: "Zdobyto zdolność: \(ability.name)."
            )
            return ability
        }
        if let session = grantSessionAbility(to: player, abilityIDs: &abilityIDs) {
            return session.asCreatedAbility
        }
        return nil
    }

    private func bossVictoryXP(for difficulty: BossDifficulty) -> Int {
        let rules = creatorStore.gameRules.bossFight
        switch difficulty {
        case .easy: return rules.xpEasy
        case .medium: return rules.xpMedium
        case .hard: return rules.xpHard
        }
    }

    private func unlockCustomPowerPath(_ pathID: UUID, playerID: UUID) -> String? {
        CustomPowerPathEngine.unlockCustomPath(
            pathID: pathID,
            playerID: playerID,
            progress: &playerPowerPathProgress
        )
    }

    private func unlockCustomPowerUpgrade(pathID: UUID, upgradeID: UUID, playerID: UUID) -> String? {
        guard let path = creatorStore.catalog.powerPaths.first(where: { $0.id == pathID }) else {
            return "Nie znaleziono ścieżki mocy."
        }
        var stats = playerStats[playerID]
        let message = CustomPowerPathEngine.unlockCustomUpgrade(
            path: path,
            upgradeID: upgradeID,
            playerID: playerID,
            progress: &playerPowerPathProgress,
            runtimeStats: &stats
        )
        if let stats {
            setPlayerStats(stats, for: playerID)
        }
        return message
    }

    private func initializeSessionAbilitiesOnStart() {
        for player in players {
            sessionAbilityPool.ensurePlayer(player.id)
        }
        ensureBoardPositionsForAllPlayers()
    }

    private func ensureBoardPositionsForAllPlayers() {
        for player in players where playerBoardPositions[player.id] == nil {
            playerBoardPositions[player.id] = 0
        }
    }

    private func syncGrantedAbilityIDsFromPool() {
        let sessionIDs = Set(sessionAbilityPool.abilities.map(\.id))
        for player in players {
            var ids = playerGrantedAbilityIDs[player.id] ?? []
            ids.removeAll { sessionIDs.contains($0) }
            ids.append(contentsOf: sessionAbilityPool.collectedAbilityIDs(for: player.id))
            playerGrantedAbilityIDs[player.id] = ids.isEmpty ? nil : ids
        }
    }

    @discardableResult
    private func grantSessionAbility(
        to player: PlayerCharacter,
        abilityIDs: inout [UUID]
    ) -> GameplaySessionAbility? {
        guard let granted = sessionAbilityPool.grantRandom(to: player.id) else { return nil }

        if !abilityIDs.contains(granted.id) {
            abilityIDs.append(granted.id)
            syncAbilityStatCount(for: player.id)
        } else {
            checkSessionWinCondition()
        }

        turnState.logCustomEvent(
            playerName: player.className,
            message: "Zdobyto zdolność sesji: \(granted.name) (\(granted.kindLabel))."
        )
        return granted
    }

    private func grantSessionAbility(to player: PlayerCharacter) -> GameplaySessionAbility? {
        var ids = playerGrantedAbilityIDs[player.id] ?? []
        defer { playerGrantedAbilityIDs[player.id] = ids.isEmpty ? nil : ids }
        return grantSessionAbility(to: player, abilityIDs: &ids)
    }

    private func grantedSessionAbilities(for playerID: UUID) -> [GameplaySessionAbility] {
        sessionAbilityPool.collectedAbilities(for: playerID)
    }

    private func canUseSessionAbility(_ ability: GameplaySessionAbility) -> Bool {
        switch ability.scope {
        case .board:
            return inGameScreen == .gameplay
                && !showBossFightAR
                && !showArenaPvPAR
                && !isArenaPvPActive
        case .bossFight:
            return showBossFightAR || isBossFightActive
        case .arenaPvP:
            return showArenaPvPAR || isArenaPvPActive
        }
    }

    private func presentPowerPathSkillUse(_ skill: PowerPathSkillID, playerID: UUID) {
        guard let caster = players.first(where: { $0.id == playerID }) else { return }
        guard playerPowerPathProgress[playerID]?.hasUnlocked(skill) == true else { return }
        guard skill.isActivatablePerLap else { return }
        guard !LapAbilityUsageEngine.hasUsedPowerPath(skill, playerID: playerID, in: playerLapAbilityUsage) else { return }

        switch skill {
        case .darkAura:
            let financesBefore = playerStats.mapValues(\.finances)
            if let result = PowerPathEngine.tryDarkAuraTheft(
                actorID: playerID,
                players: players,
                positions: playerBoardPositions,
                stats: &playerStats,
                progress: &playerPowerPathProgress,
                lapUsage: &playerLapAbilityUsage
            ) {
                if shouldAnimateFinancesChangesAutomatically {
                    for (id, afterStats) in playerStats {
                        guard let before = financesBefore[id] else { continue }
                        queueFinancesChangeAnimation(delta: afterStats.finances - before)
                    }
                }
                turnState.logCustomEvent(playerName: caster.className, message: result.message)
                let victim = players.first(where: { $0.id == result.victimID })
                powerPathSkillUsePresentation = PowerPathSkillUsePresentation(
                    skill: skill,
                    casterName: caster.displayTitle,
                    targetPlayer: victim,
                    targetGlow: glowColor(for: victim),
                    targetInstruction: "Straciłeś monety!",
                    effectDetail: result.message
                )
            } else {
                powerPathSkillUsePresentation = PowerPathSkillUsePresentation(
                    skill: skill,
                    casterName: caster.displayTitle,
                    targetPlayer: caster,
                    targetGlow: turnGlowColor,
                    targetInstruction: "Brak skutku",
                    effectDetail: "Mroczna Aura: brak celu na tym polu lub niepowodzenie."
                )
            }

        case .healing:
            guard var stats = playerStats[playerID], stats.health < 100 else { return }
            guard let message = PowerPathEngine.offerPostFightHealing(
                playerID: playerID,
                progress: playerPowerPathProgress,
                stats: &stats,
                accept: true
            ) else { return }
            _ = LapAbilityUsageEngine.markUsedPowerPath(.healing, playerID: playerID, usage: &playerLapAbilityUsage)
            setPlayerStats(stats, for: playerID)
            turnState.logCustomEvent(playerName: caster.className, message: message)
            powerPathSkillUsePresentation = PowerPathSkillUsePresentation(
                skill: skill,
                casterName: caster.displayTitle,
                targetPlayer: caster,
                targetGlow: turnGlowColor,
                targetInstruction: "Pełne zdrowie!",
                effectDetail: message
            )

        case .curse, .shadow, .benevolent, .protection:
            break
        }
    }

    private func presentPowerPathCurseUse(casterID: UUID, targetID: UUID) {
        guard let caster = players.first(where: { $0.id == casterID }) else { return }
        guard let target = players.first(where: { $0.id == targetID }) else { return }
        guard playerPowerPathProgress[casterID]?.hasUnlocked(.curse) == true else { return }
        guard !LapAbilityUsageEngine.hasUsedPowerPath(.curse, playerID: casterID, in: playerLapAbilityUsage) else { return }
        guard let message = applyPowerPathCurse(casterID: casterID, targetID: targetID) else { return }

        _ = LapAbilityUsageEngine.markUsedPowerPath(.curse, playerID: casterID, usage: &playerLapAbilityUsage)
        turnState.logCustomEvent(playerName: caster.className, message: message)
        powerPathSkillUsePresentation = PowerPathSkillUsePresentation(
            skill: .curse,
            casterName: caster.displayTitle,
            targetPlayer: target,
            targetGlow: glowColor(for: target),
            targetInstruction: "Klątwa nałożona!",
            effectDetail: "Twoja następna nagroda monet będzie o połowę mniejsza."
        )
    }

    private func confirmSessionAbilityUse(
        ability: GameplaySessionAbility,
        casterID: UUID,
        targetID: UUID,
        boardSpaces: Int
    ) {
        pendingAbilityUse = nil
        guard let caster = players.first(where: { $0.id == casterID }) else { return }

        guard canUseSessionAbility(ability) else {
            lastAbilityOutcome = "„\(ability.name)” działa tylko w: \(ability.scope.label)."
            turnState.logCustomEvent(
                playerName: caster.className,
                message: lastAbilityOutcome,
                turnMessage: "Zdolność niedostępna w tym momencie."
            )
            return
        }

        var outcomeParts: [String] = []

        switch ability.kind {
        case .turnDamage:
            let message = SessionAbilityExecutor.applyTurnDamageActivation(
                ability: ability,
                targetPlayerID: targetID,
                stats: &playerStats,
                activeEffects: &activeTurnDamageEffects
            )
            outcomeParts.append(message)
            if let targetStats = playerStats[targetID] {
                setPlayerStats(targetStats, for: targetID)
            }

        case .boardMove:
            let message = SessionAbilityExecutor.applyBoardMove(
                targetPlayerID: targetID,
                spaces: boardSpaces,
                positions: &playerBoardPositions
            )
            outcomeParts.append(message)

        case .temporaryStatBoost:
            var boosts = activeTemporaryBoosts[targetID] ?? []
            let message = SessionAbilityExecutor.applyTemporaryBoost(
                ability: ability,
                targetPlayerID: targetID,
                stats: &playerStats,
                boosts: &boosts
            )
            activeTemporaryBoosts[targetID] = boosts
            outcomeParts.append(message)
            if let targetStats = playerStats[targetID] {
                setPlayerStats(targetStats, for: targetID)
            }
        }

        sessionAbilityPool.consume(abilityID: ability.id, from: casterID)
        var owned = playerGrantedAbilityIDs[casterID] ?? []
        owned.removeAll { $0 == ability.id }
        playerGrantedAbilityIDs[casterID] = owned.isEmpty ? nil : owned
        syncAbilityStatCount(for: casterID)

        lastAbilityOutcome = outcomeParts.joined(separator: " ")
        turnState.logCustomEvent(
            playerName: caster.className,
            message: "Użyto „\(ability.name)” — \(lastAbilityOutcome) (jednorazowo)."
        )
    }

    private func processTurnStartEffects(for playerID: UUID) {
        var boosts = activeTemporaryBoosts[playerID] ?? []
        let messages = SessionAbilityExecutor.processTurnStart(
            for: playerID,
            stats: &playerStats,
            turnDamageEffects: &activeTurnDamageEffects,
            temporaryBoosts: &boosts
        )
        activeTemporaryBoosts[playerID] = boosts.isEmpty ? nil : boosts

        if let stats = playerStats[playerID] {
            setPlayerStats(stats, for: playerID)
        }

        for message in messages {
            if let player = players.first(where: { $0.id == playerID }) {
                turnState.logCustomEvent(playerName: player.className, message: message)
            }
        }
    }

    private func grantedAbilities(for playerID: UUID) -> [CreatedAbility] {
        grantedSessionAbilities(for: playerID).map(\.asCreatedAbility)
    }

    private func finishChoiceEffectsReveal() {
        settings.playTapSound()
        guard let activePlayer else {
            startFieldPhase = .hidden
            return
        }

        let choice = pendingPassChoiceText
        startFieldPhase = .hidden
        lastEventResult = nil
        pendingPassChoiceText = ""

        if registerStartFieldVisit(for: activePlayer) {
            powerPathPendingAction = .completeStartPass(playerID: activePlayer.id, choice: choice)
            recommendations = [:]
            return
        }

        completeStartFieldPassAfterCampaign(player: activePlayer, choice: choice)
        recommendations = [:]
    }

    private func allPlayersCompletedCurrentDecision() -> Bool {
        let idx = resolvedDecisionIndex
        for slot in 0..<players.count {
            if thinkingService.playthroughStore.memory.choiceIndex(
                decisionIndex: idx,
                playerSlot: slot
            ) == nil {
                return false
            }
        }
        return !players.isEmpty
    }

    @discardableResult
    private func advanceCampaignStepAfterDecision() -> Bool {
        interpretation = ""

        if decisionIndex < campaign.decisions.count - 1 {
            decisionIndex += 1
            sceneIndex = activePlayerSceneIndex()
            if let activePlayer,
               let ability = sessionAbilityPool.grantRandom(to: activePlayer.id) {
                var ids = playerGrantedAbilityIDs[activePlayer.id] ?? []
                if !ids.contains(ability.id) {
                    ids.append(ability.id)
                    playerGrantedAbilityIDs[activePlayer.id] = ids
                    syncAbilityStatCount(for: activePlayer.id)
                }
                turnState.logCustomEvent(
                    playerName: activePlayer.className,
                    message: "Zebrano zdolność sesji: \(ability.name)."
                )
            }
            return false
        }
        return campaign.isAtFinalStoryStep(decisionRound: decisionIndex)
    }

    private func markCampaignStoryFinished() {
        guard campaignsEnabled else { return }
        markSessionGameOver(showWinnerReveal: sessionWinnerPlayerID != nil)
        turnState.logCustomEvent(
            playerName: "Kampania",
            message: "Fabuła kampanii „\(campaign.title)” zakończona.",
            turnMessage: "Kampania fabularna dobiegła końca — zobacz podsumowanie w zakładce Koniec gry."
        )
    }

    private func markSessionGameOver(showWinnerReveal: Bool) {
        guard !campaignStoryFinished else { return }
        campaignStoryFinished = true
        inGameScreen = .campaignEnd
        sessionEndPhase = showWinnerReveal ? .winnerReveal : .rankings
        startFieldPhase = .hidden
        xpShopPhase = .hidden
        pendingXpShopRoll = nil
        pendingFinalTurn = false
        finalTurnRoundActive = false
        showFinalTurnIntro = false

        if let winnerID = sessionWinnerPlayerID,
           let winner = players.first(where: { $0.id == winnerID }) {
            turnState.logCustomEvent(
                playerName: winner.className,
                message: "\(winner.displayTitle) wygrał rozgrywkę.",
                turnMessage: "Koniec gry — zwycięzca: \(winner.displayTitle)."
            )
        }

        if !showWinnerReveal {
            settings.playStatsRevealSound()
        }
    }

    private func finishCampaignSession() {
        savedGameStore.clearSave()
        thinkingService.playthroughStore.reset(for: campaign)
        dismiss()
    }

    private func applyQueueBlockFromCampaignEffects(
        _ effects: CampaignChoiceEffects,
        playerID: UUID,
        playerName: String
    ) {
        let block = max(0, effects.blockRounds)
        guard block > 0 else { return }

        let total = (playerQueueBlockRounds[playerID] ?? 0) + block
        playerQueueBlockRounds[playerID] = total
        turnState.logCustomEvent(
            playerName: playerName,
            message: "Blokada kolejki na \(block) tur (łącznie \(total))."
        )
    }

    private func removeRandomOwnedItem(for playerID: UUID, playerName: String) {
        var owned = playerGrantedItemIDs[playerID] ?? []
        guard !owned.isEmpty else { return }
        let index = Int.random(in: 0..<owned.count)
        let removedID = owned.remove(at: index)
        playerGrantedItemIDs[playerID] = owned
        unequipIfNeeded(itemID: removedID, for: playerID)
        PlayerOwnedItemValues.removeItem(
            playerID: playerID,
            itemID: removedID,
            values: &playerOwnedItemValues
        )
        let itemName = creatorStore.catalog.items.first { $0.id == removedID }?.name ?? "przedmiot"
        turnState.logCustomEvent(
            playerName: playerName,
            message: "Utracono przedmiot: \(itemName)."
        )
    }

    private func applyRecommendation(for player: PlayerCharacter, playerSlot: Int) {
        guard let rec = thinkingService.recommendChoice(
            for: player,
            playerSlot: playerSlot,
            campaign: campaign,
            sceneIndex: sceneIndex(for: player),
            decisionIndex: decisionIndex
        ) else { return }

        recommendations[player.id] = rec
        thinkingService.applyRecommendedChoice(
            campaign: campaign,
            playerSlot: playerSlot,
            playerID: player.id,
            decisionIndex: decisionIndex,
            recommendation: rec
        )

        if startFieldPhase == .passingDecisions {
            let label = campaign.choiceLabels(
                forPlayerIndex: activePlayerIndex,
                decisionIndex: decisionIndex
            )[safe: rec.choiceIndex] ?? rec.choiceText
            selectChoice(label, choiceIndex: rec.choiceIndex, activePlayer: player)
        } else {
            selectedChoices[player.id] = rec.choiceText
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    NavigationStack {
        GameView()
            .environment(AppSettings())
            .environment(CampaignStore())
            .environment(SavedGameStore())
            .environment(CampaignLLMService())
            .environment(GameplayThinkingService(
                preferences: ThinkingModelPreferences(),
                gameplayLLM: GameplayLLMService(),
                analysisLLM: CampaignLLMService(),
                masterEngine: MasterAlgorithmEngine(),
                playthroughStore: PlaythroughMemoryStore()
            ))
            .environment(ThinkingModelPreferences())
            .environment(MasterAlgorithmEngine())
            .environment(PlaythroughMemoryStore())
    }
}
