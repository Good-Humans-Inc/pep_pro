import SwiftUI
import Speech

// Add Field enum at the top level
enum Field {
    case name
    case instructions
}

struct AddCustomExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var voiceManager: VoiceManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var speechRecognitionManager: SpeechRecognitionManager
    
    @State private var exerciseName = ""
    @State private var voiceInstructions = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isRecordingName = false
    @State private var isRecordingInstructions = false
    @State private var temporaryRecognizedText = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Exercise Details")) {
                    // Exercise Name Field
                    VStack(alignment: .leading) {
                        TextField("Exercise Name", text: $exerciseName)
                        
                        // Voice input button for name
                        Button(action: {
                            toggleVoiceRecording(for: .name)
                        }) {
                            HStack {
                                Image(systemName: isRecordingName ? "stop.circle.fill" : "mic.circle.fill")
                                Text(isRecordingName ? "Stop Recording" : "Voice Input: Name")
                            }
                            .foregroundColor(isRecordingName ? .red : .blue)
                        }
                        
                        // Show recognized text while recording name
                        if isRecordingName {
                            Text(speechRecognitionManager.recognizedText)
                                .foregroundColor(.gray)
                                .italic()
                        }
                    }
                    
                    // Voice Instructions Field
                    VStack(alignment: .leading) {
                        TextEditor(text: $voiceInstructions)
                            .frame(height: 100)
                        
                        // Voice input button for instructions
                        Button(action: {
                            toggleVoiceRecording(for: .instructions)
                        }) {
                            HStack {
                                Image(systemName: isRecordingInstructions ? "stop.circle.fill" : "mic.circle.fill")
                                Text(isRecordingInstructions ? "Stop Recording" : "Voice Input: Instructions")
                            }
                            .foregroundColor(isRecordingInstructions ? .red : .blue)
                        }
                        
                        // Show recognized text while recording instructions
                        if isRecordingInstructions {
                            Text(speechRecognitionManager.recognizedText)
                                .foregroundColor(.gray)
                                .italic()
                        }
                    }
                }
                
                Section {
                    Button(action: submitExercise) {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Add Exercise")
                        }
                    }
                    .disabled(isSubmitting || exerciseName.isEmpty || voiceInstructions.isEmpty)
                }
            }
            .navigationTitle("Add Custom Exercise")
            .navigationBarItems(leading: Button("Cancel") {
                dismiss()
            })
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
            .onChange(of: speechRecognitionManager.recognizedText) { newText in
                temporaryRecognizedText = newText
                
                // If we have final text, update the appropriate field
                if !isRecordingName && !isRecordingInstructions {
                    if !newText.isEmpty {
                        if isRecordingName {
                            exerciseName = newText
                        } else if isRecordingInstructions {
                            voiceInstructions = newText
                        }
                        temporaryRecognizedText = ""
                    }
                }
            }
            .onDisappear {
                // Clean up speech recognition when view disappears
                if isRecordingName || isRecordingInstructions {
                    speechRecognitionManager.stopListening()
                }
            }
        }
    }
    
    private func toggleVoiceRecording(for field: Field) {
        if (field == .name && isRecordingName) || (field == .instructions && isRecordingInstructions) {
            // Stop recording
            speechRecognitionManager.stopListening()
            
            // Update state
            if field == .name {
                isRecordingName = false
                exerciseName = speechRecognitionManager.recognizedText
            } else {
                isRecordingInstructions = false
                voiceInstructions = speechRecognitionManager.recognizedText
            }
            
            // Clear temporary text
            temporaryRecognizedText = ""
            
        } else {
            // Stop any ongoing recording
            if isRecordingName || isRecordingInstructions {
                speechRecognitionManager.stopListening()
                isRecordingName = false
                isRecordingInstructions = false
            }
            
            // Clear recognized text for new recording
            speechRecognitionManager.recognizedText = ""
            temporaryRecognizedText = ""
            
            // Start new recording
            if field == .name {
                isRecordingName = true
            } else {
                isRecordingInstructions = true
            }
            
            speechRecognitionManager.startListening()
        }
    }
    
    private func submitExercise() {
        guard let patientId = UserDefaults.standard.string(forKey: "PatientID") else {
            errorMessage = "No patient ID found"
            showingError = true
            return
        }
        
        // Prevent duplicate submissions
        guard !isSubmitting else {
            print("⚠️ Exercise submission already in progress")
            return
        }
        
        // For demo purposes, using a fixed PT ID
        // In production, this should come from PT authentication
        let ptId = "pt-demo-id"
        
        let requestBody: [String: Any] = [
            "pt_id": ptId,
            "patient_id": patientId,
            "exercise_name": exerciseName,
            "llm_provider": "openai",
            "voice_instructions": voiceInstructions
        ]
        
        let url = URL(string: "\(ServerAPI.baseURL)/add_custom_exercise")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            print("📤 Custom exercise request body: \(String(data: request.httpBody!, encoding: .utf8) ?? "unable to decode")")
        } catch {
            errorMessage = "Failed to prepare request: \(error.localizedDescription)"
            showingError = true
            return
        }
        
        isSubmitting = true
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { [self] in
                isSubmitting = false
                
                if let error = error {
                    errorMessage = "Network error: \(error.localizedDescription)"
                    showingError = true
                    return
                }
                
                guard let data = data else {
                    errorMessage = "No data received from server"
                    showingError = true
                    return
                }
                
                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    print("📥 Custom exercise response: \(json ?? [:])")
                    
                    if let status = json?["status"] as? String, status == "success" {
                        // Post notification to refresh exercises
                        NotificationCenter.default.post(
                            name: Notification.Name("ExercisesUpdated"),
                            object: nil
                        )
                        
                        // Clean up speech recognition if active
                        if isRecordingName || isRecordingInstructions {
                            speechRecognitionManager.stopListening()
                        }
                        
                        // Dismiss the view
                        dismiss()
                    } else if let error = json?["error"] as? String {
                        errorMessage = "Server error: \(error)"
                        showingError = true
                    } else {
                        errorMessage = "Invalid response from server"
                        showingError = true
                    }
                } catch {
                    errorMessage = "Failed to parse response: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }.resume()
    }
} 

