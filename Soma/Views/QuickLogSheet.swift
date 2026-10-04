import SwiftUI

// MARK: - Quick-log bottom sheet (mirrors the web ReadingForm fields:
// Date & Time of Day, Blood Pressure (mmHg), Pulse, Arm, Notes)

struct QuickLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: BPStore

    @State private var date = Date()
    @State private var timeOfDay: TimeOfDay = .morning
    @State private var systolic = ""
    @State private var diastolic = ""
    @State private var pulse = ""
    @State private var arm: Arm = .R
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?

    private var isValid: Bool {
        guard let s = Int(systolic), let d = Int(diastolic) else { return false }
        return (40...300).contains(s) && (30...200).contains(d)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Date & Time of Day
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Date & Time of Day")
                            .font(SomaFont.bold(13))
                            .foregroundColor(SomaTheme.text)
                        HStack(spacing: 10) {
                            DatePicker("", selection: $date, displayedComponents: .date)
                                .labelsHidden()
                                .tint(SomaTheme.rose)
                            Picker("", selection: $timeOfDay) {
                                ForEach(TimeOfDay.allCases) { t in
                                    Text(t.shortLabel).tag(t)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(SomaTheme.text)
                        }
                    }

                    // Blood Pressure (mmHg)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Blood Pressure (mmHg)")
                            .font(SomaFont.bold(13))
                            .foregroundColor(SomaTheme.text)
                        HStack(spacing: 10) {
                            TextField("Systolic", text: $systolic)
                                .keyboardType(.numberPad)
                                .textFieldStyle(SomaFieldStyle())
                            TextField("Diastolic", text: $diastolic)
                                .keyboardType(.numberPad)
                                .textFieldStyle(SomaFieldStyle())
                        }
                    }

                    HStack(spacing: 10) {
                        // Pulse
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pulse (bpm)")
                                .font(SomaFont.bold(13))
                                .foregroundColor(SomaTheme.text)
                            TextField("—", text: $pulse)
                                .keyboardType(.numberPad)
                                .textFieldStyle(SomaFieldStyle())
                        }
                        // Arm
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Arm")
                                .font(SomaFont.bold(13))
                                .foregroundColor(SomaTheme.text)
                            Picker("", selection: $arm) {
                                Text("L").tag(Arm.L)
                                Text("R").tag(Arm.R)
                            }
                            .pickerStyle(.segmented)
                            .tint(SomaTheme.rose)
                        }
                    }

                    // Notes (optional)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (optional)")
                            .font(SomaFont.bold(13))
                            .foregroundColor(SomaTheme.text)
                        TextField("e.g., Morning reading, after exercise...", text: $notes, axis: .vertical)
                            .lineLimit(3)
                            .textFieldStyle(SomaFieldStyle())
                    }

                    if let error {
                        Text(error)
                            .font(SomaFont.regular(13))
                            .foregroundColor(SomaTheme.categoryTreatText)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Save reading")
                                .font(SomaFont.bold(16))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isValid ? SomaTheme.rose : SomaTheme.rose.opacity(0.4))
                    .cornerRadius(12)
                    .disabled(!isValid || isSaving)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(SomaTheme.background)
            .navigationTitle("Log reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(SomaTheme.rose)
    }

    private func save() async {
        guard let sys = Int(systolic), let dia = Int(diastolic) else { return }
        let pulseVal = Int(pulse)
        isSaving = true
        error = nil
        let ok = await store.addSession(
            date: date,
            timeOfDay: timeOfDay,
            systolic: sys,
            diastolic: dia,
            pulse: pulseVal,
            arm: arm,
            notes: notes
        )
        isSaving = false
        if ok {
            dismiss()
        } else {
            error = store.errorMessage ?? "Could not save the reading."
        }
    }
}

struct SomaFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(SomaFont.regular(15))
            .foregroundColor(SomaTheme.text)
            .padding(11)
            .background(Color(hex: "1c1c22"))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(SomaTheme.border, lineWidth: 1)
            )
    }
}
