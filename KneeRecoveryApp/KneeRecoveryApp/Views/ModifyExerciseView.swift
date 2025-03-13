import SwiftUI

struct ModifyExerciseView: View {
    let exercise: Exercise
    
    @Binding var frequency: String
    @Binding var sets: Int
    @Binding var reps: Int
    @Binding var notes: String
    
    let onSave: () -> Void
    
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject private var voiceManager: VoiceManager
    @EnvironmentObject private var speechRecognitionManager: SpeechRecognitionManager
    
    @State private var isEditingViaVoice = false
    @State private var currentField: Field? = nil
    
    enum Field {
        case frequency, sets, reps, notes
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Exercise Details")) {
                    Text(exercise.name)
                        .font(.headline)
                    
                    Text(exercise.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Customize Exercise")) {
                    Picker("Frequency", selection: $frequency) {
                        Text("Daily").tag("daily")
                        Text("Twice Daily").tag("twice-daily")
                        Text("Every Other Day").tag("every-other-day")
                        Text("3x Weekly").tag("3x-weekly")
                        Text("2x Weekly").tag("twice-weekly")
                        Text("Weekly").tag("weekly")
                    }
                    
                    Stepper("Sets: \(sets)", value: $sets, in: 1...10)
                    
                    Stepper("Reps: \(reps)", value: $reps, in: 1...30)
                    
                    VStack(alignment: .leading) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ZStack(alignment: .topLeading) {
                            if notes.isEmpty {
                                Text("Add specific instructions or reminders...")
                                    .foregroundColor(.gray)
                                    .padding(.top, 8)
                            }
                            
                            TextEditor(text: $notes)
                                .frame(minHeight: 100)
                                .padding(0)
                        }
                        
                        // Voice input button for notes
                        Button(action: {
                            toggleVoiceInput(.notes)
                        }) {
                            HStack {
                                Image(systemName: isEditingViaVoice && currentField == .notes ? "mic.fill" : "mic")
                                    .foregroundColor(isEditingViaVoice && currentField == .notes ? .red : .blue)
                                Text(isEditingViaVoice && currentField == .notes ? "Listening..." : "Add Notes by Voice")
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                Section {
                    Button(action: {
                        onSave()
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Save Changes")
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle("Customize Exercise")
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
            .onChange(of: speechRecognitionManager.recognizedText) { newValue in
                if isEditingViaVoice, let field = currentField {
                    // Process voice input based on current field
                    switch field {
                    case .notes:
                        notes = newValue
                    case .frequency:
                        processFrequencyInput(newValue)
                    case .sets:
                        processSetsInput(newValue)
                    case .reps:
                        processRepsInput(newValue)
                    }
                }
            }
        }
    }
    
    private func toggleVoiceInput(_ field: Field) {
        if isEditingViaVoice && currentField == field {
            // Stop listening
            speechRecognitionManager.stopListening()
            isEditingViaVoice = false
            currentField = nil
        } else {
            // Start listening for the selected field
            if isEditingViaVoice {
                // Stop previous listening session
                speechRecognitionManager.stopListening()
            }
            
            // Clear previous text and start listening
            speechRecognitionManager.recognizedText = ""
            currentField = field
            isEditingViaVoice = true
            speechRecognitionManager.startListening()
        }
    }
    
    private func processFrequencyInput(_ input: String) {
        let input = input.lowercased()
        
        if input.contains("daily") {
            frequency = "daily"
        } else if input.contains("twice") && input.contains("day") {
            frequency = "twice-daily"
        } else if input.contains("other day") || input.contains("every other") {
            frequency = "every-other-day"
        } else if input.contains("three") || input.contains("3") {
            frequency = "3x-weekly"
        } else if input.contains("twice") || input.contains("two") || input.contains("2") {
            frequency = "twice-weekly"
        } else if input.contains("week") {
            frequency = "weekly"
        }
    }
    
    private func processSetsInput(_ input: String) {
        // Extract numbers from input text
        let pattern = "\\b[0-9]+\\b"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) {
            let numberStr = (input as NSString).substring(with: match.range)
            if let number = Int(numberStr) {
                sets = min(max(number, 1), 10) // Constrain to 1-10
            }
        }
    }
    
    private func processRepsInput(_ input: String) {
        // Extract numbers from input text
        let pattern = "\\b[0-9]+\\b"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) {
            let numberStr = (input as NSString).substring(with: match.range)
            if let number = Int(numberStr) {
                reps = min(max(number, 1), 30) // Constrain to 1-30
            }
        }
    }
}
