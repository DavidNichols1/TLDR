//
//  PlanSettings.swift
//  Ketchup
//
//  Settings' "Plan" section (one marked line in People/SettingsView.swift):
//  "Your plan" with the plans behind it, and today's usage bar. It doesn't
//  show until the server has plans (migration 0010), so it can sit in
//  Settings before the backend is upgraded.
//

import SwiftUI

struct PlanSection: View {
    private var store: PlanStore { .shared }

    var body: some View {
        SettingsSection("Plan", footer: "Every plan uses Meta's Standard mode, which Meta doesn't train on.") {
            if store.available, let status = store.status {
                NavigationLink {
                    PaywallView()
                        .navigationTitle("Your plan")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    SettingsRow("Your plan", systemImage: "menucard", value: status.plan.name, chevron: true)
                }
                .buttonStyle(.pressable)
                UsageBar(used: status.used, limit: status.limit, resetsAt: status.resetsAt)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
        }
        .task { await PlanStore.shared.refresh() }
    }
}
