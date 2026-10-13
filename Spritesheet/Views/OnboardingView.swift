//
//  OnboardingView.swift
//  Spritesheet
//
//  Created by Tufan Cakir on 13.10.26.
//

import SwiftUI

struct OnboardingView: View {
    static let currentVersion = 1

    let completion: () -> Void
    @State private var page = 0

    private let pages = [
        OnboardingPage(
            title: "Welcome to Spritesheet",
            description:
                "Create spritesheets from individual images or existing sprite animations.",
            symbol: "rectangle.grid.2x2"
        ),
        OnboardingPage(
            title: "Import Images",
            description:
                "Import PNG images from Files or Photos and extract frames from existing spritesheets.",
            symbol: "photo.on.rectangle.angled"
        ),
        OnboardingPage(
            title: "Combine Frames",
            description:
                "Sort your frames and flexibly adjust columns, spacing, and alignment.",
            symbol: "square.grid.3x3"
        ),
        OnboardingPage(
            title: "Preview and Export",
            description:
                "Check frame playback and export your spritesheet as a PNG at the desired resolution.",
            symbol: "arrow.up.doc"
        ),
    ]

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button("Skip", action: completion)
                    .opacity(page == pages.count - 1 ? 0 : 1)
            }

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    OnboardingPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            HStack {
                Button("Back") {
                    page = max(0, page - 1)
                }
                .disabled(page == 0)

                Spacer()

                Button(page == pages.count - 1 ? "Get Started" : "Next") {
                    if page == pages.count - 1 {
                        completion()
                    } else {
                        page += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let symbol: String
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: page.symbol)
                    .font(.system(size: 72, weight: .medium))
                    .foregroundStyle(.tint)
                    .accessibilityLabel(Text(page.title))
                Text(page.title)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(page.description)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                Spacer()
            }
            .accessibilityHidden(true)

            Color.clear
                .accessibilityElement()
                .accessibilityLabel(Text(page.title))
                .accessibilityValue(Text(page.description))
        }
        .padding(.horizontal)
    }
}
