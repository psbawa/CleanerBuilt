import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.ageDaysKey) private var ageDays = 7

    var body: some View {
        Form {
            Section("Age Threshold") {
                Stepper(value: $ageDays, in: 1...365) {
                    Text("Only include items untouched for \(ageDays) days")
                    Text("Applies to caches, logs, temporary files and DerivedData.")
                }
            }
            ForEach(CleanupCategory.allCases) { category in
                Section {
                    ForEach(CleanupRules.rules.filter { $0.category == category }) { RuleToggle(rule: $0) }
                } header: {
                    Label(category.title, systemImage: category.symbol)
                } footer: {
                    Text(category.explanation).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

private struct RuleToggle: View {
    let rule: Rule
    @AppStorage private var isOn: Bool

    init(rule: Rule) {
        self.rule = rule
        _isOn = AppStorage(wrappedValue: rule.defaultOn, Prefs.ruleKey(rule.id))
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            if rule.defaultOn {
                Text(rule.title)
            } else {
                Label(rule.title, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Text(rule.explanation)
        }
    }
}
