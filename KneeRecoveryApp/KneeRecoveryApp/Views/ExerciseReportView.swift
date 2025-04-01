import SwiftUI
import ElevenLabsSDK

struct ExerciseReportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var voiceManager: VoiceManager
    
    @State private var showingCongrats = true
    @State private var feedbackData: ExerciseFeedbackData
    @State private var isLoadingReport = false
    @State private var reportError: String? = nil
    
    // Exercise data
    let exercise: Exercise
    let duration: TimeInterval
    let date: Date
    let conversationContent: String?
    
    init(exercise: Exercise, duration: TimeInterval, conversationContent: String? = nil, feedbackData: ExerciseFeedbackData? = nil, date: Date = Date()) {
        self.exercise = exercise
        self.duration = duration
        self.date = date
        self.conversationContent = conversationContent
        self._feedbackData = State(initialValue: feedbackData ?? ExerciseFeedbackData.defaultData)
    }
    
    var body: some View {
        ZStack {
            Color.white.edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Close button
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .font(.title2)
                        }
                    }
                    .padding(.bottom)
                    
                    HeaderSection(exerciseName: exercise.name, date: date)
                    
                    FeedbackSection(title: "General Feeling",
                                  content: feedbackData.generalFeeling)
                    
                    FeedbackSection(title: "Performance Quality",
                                  content: feedbackData.performanceQuality)
                    
                    FeedbackSection(title: "Pain Report",
                                  content: feedbackData.painReport)
                    
                    ExerciseStats(duration: duration,
                                exercise: exercise,
                                completed: feedbackData.completed,
                                setsCompleted: feedbackData.setsCompleted,
                                repsCompleted: feedbackData.repsCompleted)
                    
                    ProgressBoardSection(dayStreak: feedbackData.dayStreak)
                    
                    MotivationalMessageSection(message: feedbackData.motivationalMessage)
                    
                    GeneratePTReportButton(patientId: voiceManager.patientId ?? "", exerciseId: exercise.firestoreId ?? exercise.id.uuidString)
                }
                .padding()
            }
            
            if showingCongrats {
                CongratulationsOverlay {
                    withAnimation {
                        showingCongrats = false
                    }
                }
            }
            
            if isLoadingReport {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                VStack {
                    ProgressView("Generating report...")
                        .padding()
                        .background(Color.white)
                        .cornerRadius(10)
                }
            }
        }
        .onAppear {
            if let content = conversationContent {
                generateReportFromConversation(content)
            } else {
                loadFeedbackData()
            }
        }
        .alert(item: Binding(
            get: { reportError.map { ReportError(message: $0) } },
            set: { reportError = $0?.message }
        )) { error in
            Alert(
                title: Text("Report Generation Error"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private func loadFeedbackData() {
        // Check if we have exercise feedback stored for this session
        if let storedFeedback = UserDefaults.standard.data(forKey: "LastExerciseFeedback"),
           let decodedFeedback = try? JSONDecoder().decode(ExerciseFeedbackData.self, from: storedFeedback) {
            
            feedbackData = decodedFeedback
        }
    }
    
    private func generateReportFromConversation(_ content: String) {
        guard let patientId = voiceManager.patientId else {
            reportError = "No patient ID available"
            return
        }
        
        isLoadingReport = true
        
        // API endpoint
        let urlString = "https://us-central1-pep-pro.cloudfunctions.net/generate_exercise_report"
        guard let url = URL(string: urlString) else {
            reportError = "Invalid API URL"
            isLoadingReport = false
            return
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Request body
        let requestBody: [String: Any] = [
            "conversation_content": content,
            "patient_id": patientId,
            "exercise_id": exercise.firestoreId ?? exercise.id.uuidString
        ]
        
        // Convert data to JSON
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            reportError = "Failed to create request: \(error.localizedDescription)"
            isLoadingReport = false
            return
        }
        
        // Make API call
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoadingReport = false
                
                if let error = error {
                    reportError = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    reportError = "No data received"
                    return
                }
                
                do {
                    // Parse response
                    let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    
                    if let status = jsonResponse?["status"] as? String,
                       status == "success",
                       let reportData = jsonResponse?["report"] as? [String: Any] {
                        
                        // Convert report data to ExerciseFeedbackData
                        let newFeedback = ExerciseFeedbackData(
                            generalFeeling: reportData["general_feeling"] as? String ?? "No data available",
                            performanceQuality: reportData["performance_quality"] as? String ?? "No data available",
                            painReport: reportData["pain_report"] as? String ?? "No pain reported",
                            completed: reportData["completed"] as? Bool ?? true,
                            setsCompleted: reportData["sets_completed"] as? Int ?? 0,
                            repsCompleted: reportData["reps_completed"] as? Int ?? 0,
                            dayStreak: reportData["day_streak"] as? Int ?? 1,
                            motivationalMessage: reportData["motivational_message"] as? String ?? "Great job with your exercise!"
                        )
                        
                        // Update the view's feedback data
                        feedbackData = newFeedback
                        
                        // Save to UserDefaults for persistence
                        if let encodedData = try? JSONEncoder().encode(newFeedback) {
                            UserDefaults.standard.set(encodedData, forKey: "LastExerciseFeedback")
                        }
                        
                    } else if let errorMsg = jsonResponse?["error"] as? String {
                        reportError = errorMsg
                    } else {
                        reportError = "Invalid server response"
                    }
                } catch {
                    reportError = "Failed to parse response: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}

// Exercise Feedback Data Model
struct ExerciseFeedbackData: Codable, Equatable {
    var generalFeeling: String
    var performanceQuality: String
    var painReport: String
    var completed: Bool
    var setsCompleted: Int
    var repsCompleted: Int
    var dayStreak: Int
    var motivationalMessage: String
    
    static let defaultData = ExerciseFeedbackData(
        generalFeeling: "No data collected for this session.",
        performanceQuality: "No quality assessment for this session.",
        painReport: "No pain report for this session.",
        completed: true,
        setsCompleted: 0,
        repsCompleted: 0,
        dayStreak: 1,
        motivationalMessage: "Great job completing your exercise! Keep up the good work to continue your recovery progress."
    )
}

// MARK: - Supporting Views
struct HeaderSection: View {
    let exerciseName: String
    let date: Date
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("\(exerciseName) Report")
                .font(.title)
                .bold()
            Text(date.formatted())
                .foregroundColor(.secondary)
        }
    }
}

struct FeedbackSection: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
            Text(content)
                .padding(.vertical, 5)
            Divider()
        }
    }
}

struct ExerciseStats: View {
    let duration: TimeInterval
    let exercise: Exercise
    let completed: Bool
    let setsCompleted: Int
    let repsCompleted: Int
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)m \(seconds)s"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exercise Statistics")
                .font(.headline)
            
            HStack(spacing: 20) {
                StatItem(title: "Duration", value: formattedDuration)
                StatItem(title: "Sets", value: "\(setsCompleted)")
                StatItem(title: "Reps", value: "\(repsCompleted)")
            }
            
            HStack {
                Text("Completion:")
                Text(completed ? "Completed" : "Partial")
                    .foregroundColor(completed ? .green : .orange)
                    .fontWeight(.semibold)
            }
            .padding(.top, 4)
            
            Divider()
        }
    }
}

struct StatItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
        }
    }
}

struct ProgressBoardSection: View {
    let dayStreak: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Progress Board")
                .font(.headline)
            
            HStack {
                VStack {
                    Text("\(dayStreak)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("Day Streak")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                VStack {
                    Image(systemName: "flame.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .foregroundColor(.orange)
                    Text("Consistency")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                VStack {
                    Text("🏔️")
                        .font(.largeTitle)
                    Text("Goal Tracking")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            Divider()
        }
    }
}

struct MotivationalMessageSection: View {
    let message: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's Motivation")
                .font(.headline)
            Text(message)
                .foregroundColor(.secondary)
                .italic()
            Divider()
        }
    }
}

struct GeneratePTReportButton: View {
    let patientId: String
    let exerciseId: String
    @State private var showingPTReportAlert = false
    @State private var isGenerating = false
    @State private var reportGenerated = false
    @State private var reportError: String? = nil
    
    var body: some View {
        VStack(spacing: 10) {
            Button(action: {
                showingPTReportAlert = true
            }) {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("Generate PT Visit Report")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
                .foregroundColor(.blue)
            }
            
            if isGenerating {
                ProgressView("Generating report...")
                    .padding(.top, 5)
            }
            
            if reportGenerated {
                Text("Report generated successfully! Check your email.")
                    .foregroundColor(.green)
                    .font(.caption)
                    .padding(.top, 5)
            }
            
            if let error = reportError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.top, 5)
            }
        }
        .alert(isPresented: $showingPTReportAlert) {
            Alert(
                title: Text("Generate PT Report"),
                message: Text("This feature will generate a comprehensive report for your Physical Therapist. Would you like to proceed?"),
                primaryButton: .default(Text("Generate")) {
                    generatePTReport()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private func generatePTReport() {
        isGenerating = true
        reportGenerated = false
        reportError = nil
        
        // API endpoint
        let urlString = "https://us-central1-pep-pro.cloudfunctions.net/generate_pt_report"
        guard let url = URL(string: urlString) else {
            reportError = "Invalid API URL"
            isGenerating = false
            return
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Request body
        let requestBody: [String: Any] = [
            "patient_id": patientId,
            "exercise_id": exerciseId,
            "generate_pdf": true,
            "send_email": true
        ]
        
        // Convert data to JSON
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            reportError = "Failed to create request: \(error.localizedDescription)"
            isGenerating = false
            return
        }
        
        // Make API call
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isGenerating = false
                
                if let error = error {
                    reportError = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    reportError = "No data received"
                    return
                }
                
                do {
                    // Parse response
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = json["status"] as? String {
                        
                        if status == "success" {
                            reportGenerated = true
                        } else if let errorMsg = json["error"] as? String {
                            reportError = errorMsg
                        } else {
                            reportError = "Unknown error occurred"
                        }
                    } else {
                        reportError = "Invalid server response"
                    }
                } catch {
                    reportError = "Failed to parse response: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}

struct CongratulationsOverlay: View {
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                // You can implement a simple animation here
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.green)
                    .scaleEffect(1.5)
                    .opacity(0.9)
                
                Text("Fantastic Work!")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
                
                Text("Your exercise is complete!")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                onComplete()
            }
        }
    }
}

// MARK: - Integration with Exercise Coach Agent
extension VoiceManager {
    // Function to receive exercise feedback from the coach agent
    func recordExerciseFeedback(feedbackData: [String: Any]) {
        print("🏋️‍♀️ Recording exercise feedback: \(feedbackData)")
        
        // Convert the raw feedback data to our ExerciseFeedbackData model
        let feedback = ExerciseFeedbackData(
            generalFeeling: feedbackData["general_feeling"] as? String ?? "No feeling data provided",
            performanceQuality: feedbackData["performance_quality"] as? String ?? "No quality data provided",
            painReport: feedbackData["pain_report"] as? String ?? "No pain data provided",
            completed: feedbackData["completed"] as? Bool ?? true,
            setsCompleted: feedbackData["sets_completed"] as? Int ?? 0,
            repsCompleted: feedbackData["reps_completed"] as? Int ?? 0,
            dayStreak: feedbackData["day_streak"] as? Int ?? 1,
            motivationalMessage: feedbackData["motivational_message"] as? String ?? "Great job with your exercise today!"
        )
        
        // Save the feedback data for use in the report view
        if let encodedData = try? JSONEncoder().encode(feedback) {
            UserDefaults.standard.set(encodedData, forKey: "LastExerciseFeedback")
        }
        
        // Post notification that feedback is available
        NotificationCenter.default.post(
            name: Notification.Name("ExerciseFeedbackAvailable"),
            object: nil,
            userInfo: ["feedback": feedback]
        )
    }
}

// Add this client tool to your exercise coach agent
extension VoiceManager {
    func registerAdditionalExerciseCoachTools(clientTools: inout ElevenLabsSDK.ClientTools) {
        // Tool to record exercise feedback
        clientTools.register("recordExerciseFeedback") { [weak self] parameters in
            guard let self = self else { return "Manager not available" }
            
            print("🔵 recordExerciseFeedback tool called with parameters: \(parameters)")
            
            // Record the feedback
            self.recordExerciseFeedback(feedbackData: parameters)
            
            return "Exercise feedback recorded successfully"
        }
    }
}

// Add ReportError type for alert handling
struct ReportError: Identifiable {
    let id = UUID()
    let message: String
}

// Update VoiceManager extension
extension VoiceManager {
    func captureExerciseConversation() -> String {
        // Return the stored conversation messages
        var conversationText = ""
        
        // Access the stored messages from conversation history
        for message in conversationHistory { 
            conversationText += "\(message.role.rawValue): \(message.content)\n"
        }
        
        return conversationText
    }
}

// Update ExerciseDetailView extension
extension ExerciseDetailView {
    func presentExerciseReport(duration: TimeInterval) {
        // Get conversation content from voice manager
        let conversationContent = voiceManager.captureExerciseConversation()
        
        // Create and configure the report view
        let reportView = ExerciseReportView(
            exercise: exercise,
            duration: duration,
            conversationContent: conversationContent
        )
        .environmentObject(voiceManager)
        
        // Present using UIKit
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            
            let hostingController = UIHostingController(rootView: reportView)
            hostingController.modalPresentationStyle = .fullScreen
            hostingController.view.backgroundColor = .clear
            rootViewController.present(hostingController, animated: true)
        }
    }
}

// Helper extension for UIColor
extension UIColor {
    static var clear: UIColor {
        UIColor(red: 0, green: 0, blue: 0, alpha: 0)
    }
}
