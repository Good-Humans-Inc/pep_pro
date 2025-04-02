import SwiftUI

struct AddCustomExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var voiceManager: VoiceManager
    
    @State private var exerciseName = ""
    @State private var voiceInstructions = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Exercise Details")) {
                    TextField("Exercise Name", text: $exerciseName)
                    
                    TextEditor(text: $voiceInstructions)
                        .frame(height: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
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
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
        }
    }
    
    private func submitExercise() {
        guard let patientId = UserDefaults.standard.string(forKey: "PatientID") else {
            errorMessage = "No patient ID found"
            showingError = true
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
            DispatchQueue.main.async {
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