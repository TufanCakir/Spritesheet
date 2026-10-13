//
//  SettingsView.swift
//  Spritesheet
//
//  Created by Tufan Cakir on 13.10.26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var language = "system"
    @AppStorage("appAppearance") private var appearance = "system"
    @AppStorage("onboardingVersion") private var onboardingVersion = 0
    @State private var showsOnboarding = false

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    Picker("Language", selection: $language) {
                        Text("System").tag("system")
                        Text("German").tag("de")
                        Text("English").tag("en")
                    }
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }

                Section("Help") {
                    Button(
                        "Show Onboarding",
                        systemImage: "questionmark.circle"
                    ) {
                        showsOnboarding = true
                    }
                }

                Section("App") {
                    LabeledContent("Version", value: version)
                    LabeledContent("Build", value: build)
                    LabeledContent("Developer", value: "Tufan Cakir")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showsOnboarding) {
            OnboardingView {
                onboardingVersion = OnboardingView.currentVersion
                showsOnboarding = false
            }
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "—"
    }
}
