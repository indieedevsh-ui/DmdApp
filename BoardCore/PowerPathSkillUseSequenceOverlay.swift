//
//  PowerPathSkillUseSequenceOverlay.swift
//  BoardCore
//

import SwiftUI
import UIKit

struct PowerPathSkillUsePresentation: Identifiable, Equatable {
    let id = UUID()
    let skill: PowerPathSkillID
    let casterName: String
    let targetPlayer: PlayerCharacter?
    let targetGlow: PlayerGlowColor
    let targetInstruction: String
    let effectDetail: String
}

struct PowerPathSkillUseSequenceOverlay: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerSlotStore.self) private var playerSlotStore
    @Environment(CreatorStore.self) private var creatorStore

    let presentation: PowerPathSkillUsePresentation
    let onComplete: () -> Void

    @State private var phase: Phase = .skill
    @State private var backdropOpacity: Double = 0
    @State private var iconScale: CGFloat = 0.45
    @State private var iconOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.35
    @State private var ringOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var profileScale: CGFloat = 0.55
    @State private var profileOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var dismissTask: Task<Void, Never>?

    private enum Phase {
        case skill
        case target
    }

    private var side: PowerPathSide { presentation.skill.side }

    private var accent: Color { side.auraAccent }

    private var profileImage: UIImage? {
        guard let target = presentation.targetPlayer else { return nil }
        if let slot = target.lobbySlotNumber,
           let image = playerSlotStore.appearanceImage(for: slot) {
            return image
        }
        if let qrCode = target.qrCode,
           let character = creatorStore.character(withNumericId: qrCode)
            ?? creatorStore.character(matching: qrCode) {
            return creatorStore.loadImage(fileName: character.imageFileName)
        }
        return nil
    }

    var body: some View {
        ZStack {
            Color.black.opacity(backdropOpacity * 0.72)
                .ignoresSafeArea()

            PowerPathAuraBackground(side: side)
                .opacity(backdropOpacity * 0.82)
                .allowsHitTesting(false)

            switch phase {
            case .skill:
                skillPhaseContent
            case .target:
                targetPhaseContent
            }
        }
        .onAppear { runSkillPhase() }
        .onDisappear { dismissTask?.cancel() }
    }

    private var skillPhaseContent: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .strokeBorder(accent.opacity(0.55), lineWidth: 2)
                    .frame(width: 220, height: 220)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)

                Image(systemName: skillIcon(for: presentation.skill))
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)
                    .shadow(color: accent.opacity(0.65), radius: 22)
            }

            Text("Użyto umiejętności")
                .font(.title.bold())
                .opacity(titleOpacity)

            Text(presentation.skill.title)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .opacity(titleOpacity)

            Text(presentation.effectDetail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .opacity(titleOpacity)

            Spacer()
        }
    }

    private var targetPhaseContent: some View {
        VStack(spacing: 24) {
            Spacer()

            if let target = presentation.targetPlayer {
                ZStack {
                    Circle()
                        .fill(presentation.targetGlow.swiftUIColor.opacity(profileOpacity * 0.35))
                        .frame(width: 148, height: 148)
                        .blur(radius: 18)

                    Circle()
                        .strokeBorder(presentation.targetGlow.accentColor.opacity(0.65), lineWidth: 3)
                        .frame(width: 118, height: 118)
                        .scaleEffect(profileScale)
                        .opacity(profileOpacity)

                    profileAvatar
                        .frame(width: 104, height: 104)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 2))
                        .scaleEffect(profileScale)
                        .opacity(profileOpacity)
                }

                Text(target.displayTitle)
                    .font(.title2.bold())
                    .opacity(subtitleOpacity)

                Text(presentation.targetInstruction)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(presentation.targetGlow.accentColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .opacity(subtitleOpacity)

                Text(presentation.effectDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(subtitleOpacity)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let profileImage {
            Image(uiImage: profileImage)
                .resizable()
                .scaledToFill()
        } else if let icon = PlayerProfileIcon.from(id: presentation.targetPlayer?.profileIconID) {
            PlayerProfileIconBadge(icon: icon, size: 104)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func runSkillPhase() {
        HapticManager.playStatReveal(intensity: settings.hapticIntensity * 0.85)
        settings.playStatsRevealSound()

        withAnimation(.easeOut(duration: 0.4)) {
            backdropOpacity = 1
        }
        withAnimation(.spring(response: 0.62, dampingFraction: 0.68)) {
            iconScale = 1.08
            iconOpacity = 1
            ringScale = 1.12
            ringOpacity = 1
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82).delay(0.08)) {
            iconScale = 1
            ringScale = 1
        }
        withAnimation(.easeOut(duration: 0.45).delay(0.14)) {
            titleOpacity = 1
        }

        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.1))
            guard !Task.isCancelled else { return }
            if presentation.targetPlayer != nil {
                transitionToTargetPhase()
            } else {
                dismissAnimated()
            }
        }
    }

    private func transitionToTargetPhase() {
        withAnimation(.easeInOut(duration: 0.28)) {
            titleOpacity = 0
            iconOpacity = 0
            ringOpacity = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            phase = .target
            runTargetPhase()
        }
    }

    private func runTargetPhase() {
        HapticManager.playStatReveal(intensity: settings.hapticIntensity * 0.7)

        withAnimation(.spring(response: 0.58, dampingFraction: 0.64)) {
            profileScale = 1.06
            profileOpacity = 1
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82).delay(0.08)) {
            profileScale = 1
        }
        withAnimation(.easeOut(duration: 0.45).delay(0.16)) {
            subtitleOpacity = 1
        }

        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            dismissAnimated()
        }
    }

    private func dismissAnimated() {
        withAnimation(.easeInOut(duration: 0.32)) {
            backdropOpacity = 0
            iconOpacity = 0
            titleOpacity = 0
            profileOpacity = 0
            subtitleOpacity = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(340))
            onComplete()
        }
    }

    private func skillIcon(for skill: PowerPathSkillID) -> String {
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
