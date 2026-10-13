//
//  RootView.swift
//  Spritesheet
//
//  Created by Tufan Cakir on 13.10.26.
//

import SwiftUI

struct RootView: View {
    @State private var library = ProjectLibraryViewModel()
    @State private var path: [UUID] = []
    @AppStorage("onboardingVersion") private var onboardingVersion = 0
    @AppStorage("appLanguage") private var appLanguage = "system"
    @AppStorage("appAppearance") private var appAppearance = "system"
    @State private var showsOnboarding = false

    var body: some View {
        NavigationStack(path: $path) {
            ProjectsView(library: library) { id in
                path.append(id)
            }
            .navigationDestination(for: UUID.self) { id in
                if let editor = library.openProject(id: id) {
                    ContentView(model: editor) {
                        if await library.closeEditor() {
                            path.removeAll()
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Project Unavailable",
                        systemImage: "exclamationmark.folder"
                    )
                }
            }
        }
        .environment(\.locale, selectedLocale)
        .preferredColorScheme(selectedColorScheme)
        .fullScreenCover(isPresented: $showsOnboarding) {
            OnboardingView {
                onboardingVersion = OnboardingView.currentVersion
                showsOnboarding = false
            }
            .environment(\.locale, selectedLocale)
        }
        .task {
            library.loadProjects()
            showsOnboarding = onboardingVersion < OnboardingView.currentVersion
        }
    }

    private var selectedLocale: Locale {
        appLanguage == "system"
            ? .autoupdatingCurrent : Locale(identifier: appLanguage)
    }

    private var selectedColorScheme: ColorScheme? {
        switch appAppearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
