//
//  YourSkillsFullScreenView.swift
//  BoardCore
//

import SwiftUI

struct YourSkillsFullScreenView: View {
    @Environment(AppSettings.self) private var settings

    let player: PlayerCharacter
    let playerGlow: PlayerGlowColor
    let powerPathProgress: PlayerPowerPathProgress
    let lapUsage: PlayerLapAbilityUsage
    let currentHealth: Int
    let opponents: [PlayerCharacter]

    let onUsePowerPathSkill: (PowerPathSkillID) -> Void
    let onCurseTarget: (UUID) -> Void
    let onExit: () -> Void

    var trikiExitHighlighted: Bool = false
    var trikiHoldChargeProgress: Double = 0

    @State private var feedbackMessage = ""
    @State private var showCursePicker = false

    private var unlockedPowerSkills: [PowerPathSkillID] {
        PowerPathSkillID.allCases
            .filter { powerPathProgress.hasUnlocked($0) }
            .sorted { $0.tier < $1.tier }
    }

    var body: some View {
        ZStack {
            AppGradientBackground(glow: playerGlow)

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if unlockedPowerSkills.isEmpty {
                            emptyState
                        } else {
                            ForEach(unlockedPowerSkills) { skill in
                                powerPathCard(skill)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }

                exitButton
            }

            if !feedbackMessage.isEmpty {
                feedbackBanner
            }
        }
        .sheet(isPresented: $showCursePicker) {
            curseTargetPicker
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Twoje Umiejętności")
                .font(.largeTitle.bold())
            Text(player.displayTitle)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Każdą umiejętność możesz użyć raz na okrążenie. Odświeżenie po przejściu przez start.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        Text("Brak odblokowanych umiejętności. Rozwijaj Ścieżkę Mocy na polu start.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func powerPathCard(_ skill: PowerPathSkillID) -> some View {
        let used = lapUsage.usedPowerPathSkills.contains(skill)
        let canActivate = skill.isActivatablePerLap && !used && canActivatePowerSkill(skill)
        let cardOpacity: Double = used ? 0.5 : 1

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: powerPathIcon(for: skill))
                    .font(.title3.bold())
                    .foregroundStyle(settings.accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(skill.title)
                        .font(.headline)
                    Text(skill.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            statusChip(
                label: skill.isPassiveInGameplay
                    ? "Pasywna — zawsze aktywna"
                    : used
                        ? "Użyta w tym okrążeniu"
                        : "Dostępna",
                tone: skill.isPassiveInGameplay ? .passive : used ? .used : .ready
            )

            if skill.isActivatablePerLap {
                if skill == .curse {
                    Button("Nałóż klątwę") {
                        settings.playTapSound()
                        showCursePicker = true
                    }
                    .buttonStyle(.appProminent)
                    .disabled(!canActivate)
                } else {
                    Button(skill == .healing ? "Użyj uzdrowienia" : "Użyj umiejętności") {
                        settings.playTapSound()
                        onUsePowerPathSkill(skill)
                    }
                    .buttonStyle(.appProminent)
                    .disabled(!canActivate)
                }

                if !canActivate && !used && skill == .healing && currentHealth >= 100 {
                    Text("Wymaga utraty zdrowia.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(used ? 0.06 : 0.12), lineWidth: 1)
        )
        .opacity(cardOpacity)
    }

    private var curseTargetPicker: some View {
        NavigationStack {
            List(opponents) { opponent in
                Button(opponent.displayTitle) {
                    settings.playTapSound()
                    showCursePicker = false
                    onCurseTarget(opponent.id)
                }
            }
            .navigationTitle("Cel klątwy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") {
                        settings.playTapSound()
                        showCursePicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var exitButton: some View {
        Button {
            onExit()
        } label: {
            Text("Wyjdź")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.appProminent)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .trikiSelectableHighlight(
            isSelected: trikiExitHighlighted,
            chargeProgress: trikiExitHighlighted ? trikiHoldChargeProgress : 0
        )
    }

    private var feedbackBanner: some View {
        VStack {
            Spacer()
            Text(feedbackMessage)
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.8))
                feedbackMessage = ""
            }
        }
    }

    private func canActivatePowerSkill(_ skill: PowerPathSkillID) -> Bool {
        switch skill {
        case .healing:
            return currentHealth < 100
        case .darkAura, .curse:
            return true
        case .shadow, .benevolent, .protection:
            return false
        }
    }

    private enum StatusTone {
        case ready, used, passive
    }

    private func statusChip(label: String, tone: StatusTone) -> some View {
        let color: Color = switch tone {
        case .ready: .green
        case .used: .orange
        case .passive: settings.accentColor
        }
        return Text(label)
            .font(.caption.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func powerPathIcon(for skill: PowerPathSkillID) -> String {
        switch skill {
        case .darkAura: "moon.haze.fill"
        case .curse: "eye.trianglebadge.exclamationmark.fill"
        case .shadow: "figure.stand.line.dotted.figure.stand"
        case .benevolent: "hands.sparkles.fill"
        case .protection: "shield.lefthalf.filled"
        case .healing: "heart.circle.fill"
        }
    }
}
