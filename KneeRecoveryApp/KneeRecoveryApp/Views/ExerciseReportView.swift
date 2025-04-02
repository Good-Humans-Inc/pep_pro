import SwiftUI
import ElevenLabsSDK

// MARK: - Exercise Feedback Data Model
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

struct ExerciseReportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var voiceManager: VoiceManager
    
    @State private var showingCongrats = true
    @State private var feedbackData: ExerciseFeedbackData
    
    // Exercise data
    let exercise: Exercise
    let duration: TimeInterval
    let date: Date
    
    init(exercise: Exercise, duration: TimeInterval, feedbackData: ExerciseFeedbackData? = nil, date: Date = Date()) {
        self.exercise = exercise
        self.duration = duration
        self.date = date
        // Initialize with provided feedback data or defaults
        self._feedbackData = State(initialValue: feedbackData ?? ExerciseFeedbackData.defaultData)
    }
    
    var body: some View {
        ZStack {
            Color.white.edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
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
        }
        .onAppear {
            // Load additional feedback data if needed
            if feedbackData == ExerciseFeedbackData.defaultData {
                loadFeedbackData()
            }
        }
    }
    
    private func loadFeedbackData() {
        // Check if we have exercise feedback stored for this session
        if let storedFeedback = UserDefaults.standard.data(forKey: "LastExerciseFeedback"),
           let decodedFeedback = try? JSONDecoder().decode(ExerciseFeedbackData.self, from: storedFeedback) {
            feedbackData = decodedFeedback
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

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.primary)
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .bold()
        }
    }
}

struct DetailRow: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(content)
                .frame(maxWidth: .infinity, alignment: .leading)
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
    @EnvironmentObject private var voiceManager: VoiceManager
    
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
            .disabled(isGenerating)
            
            if isGenerating {
                ProgressView("Generating report...")
                    .padding(.top, 5)
            }
            
            if reportGenerated {
                Text("Report generated successfully!")
                    .foregroundColor(.green)
                    .font(.caption)
                    .padding(.top, 5)
            }
            
            if let error = reportError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.top, 5)
                    .multilineTextAlignment(.center)
            }
        }
        .alert(isPresented: $showingPTReportAlert) {
            Alert(
                title: Text("Generate PT Report"),
                message: Text("This will generate a comprehensive report based on your exercise session. Would you like to proceed?"),
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
        
        // Get conversation history
        let conversationHistory = voiceManager.getConversationHistory()
        
        if conversationHistory.isEmpty {
            reportError = "No exercise session data available.\nPlease complete an exercise session first."
            isGenerating = false
            return
        }
        
        // Call the server API
        ServerAPI().generatePTReport(
            patientId: patientId,
            exerciseId: exerciseId,
            conversationHistory: conversationHistory
        ) { result in
            DispatchQueue.main.async {
                isGenerating = false
                
                switch result {
                case .success(let response):
                    if let status = response["status"] as? String,
                       status == "success",
                       let report = response["report"] as? [String: Any] {
                        
                        reportGenerated = true
                        
                        // Create feedback data
                        let feedbackData = ExerciseFeedbackData(
                            generalFeeling: report["general_feeling"] as? String ?? "No feeling data provided",
                            performanceQuality: report["performance_quality"] as? String ?? "No quality data provided",
                            painReport: report["pain_report"] as? String ?? "No pain data provided",
                            completed: report["completed"] as? Bool ?? true,
                            setsCompleted: report["sets_completed"] as? Int ?? 0,
                            repsCompleted: report["reps_completed"] as? Int ?? 0,
                            dayStreak: report["day_streak"] as? Int ?? 1,
                            motivationalMessage: report["motivational_message"] as? String ?? "Great job with your exercise today!"
                        )
                        
                        // Save the feedback data
                        if let encodedData = try? JSONEncoder().encode(feedbackData) {
                            UserDefaults.standard.set(encodedData, forKey: "LastExerciseFeedback")
                            
                            // Post notification to update UI
                            NotificationCenter.default.post(
                                name: Notification.Name("ExerciseFeedbackAvailable"),
                                object: nil,
                                userInfo: ["feedback": feedbackData]
                            )
                        }
                        
                    } else if let error = response["error"] as? String {
                        reportError = "Server error: \(error)"
                    } else {
                        reportError = "Unexpected server response"
                    }
                    
                case .failure(let error):
                    reportError = "Failed to generate report: \(error.localizedDescription)"
                }
            }
        }
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
    // Function to record exercise feedback from the coach agent
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

// Helper to present the ExerciseReportView
extension View {
    func showExerciseReport(exercise: Exercise, duration: TimeInterval, feedbackData: ExerciseFeedbackData? = nil) -> some View {
        self.sheet(isPresented: .constant(true)) {
            ExerciseReportView(
                exercise: exercise,
                duration: duration,
                feedbackData: feedbackData
            )
        }
    }
}

// Usage in your ExerciseDetailView
extension ExerciseDetailView {
    func presentExerciseReport(duration: TimeInterval) {
        // Check if feedback data is available
        var feedbackData: ExerciseFeedbackData? = nil
        
        if let storedFeedback = UserDefaults.standard.data(forKey: "LastExerciseFeedback"),
           let decodedFeedback = try? JSONDecoder().decode(ExerciseFeedbackData.self, from: storedFeedback) {
            feedbackData = decodedFeedback
        }
        
        // Present the report view
        let reportView = ExerciseReportView(
            exercise: exercise,
            duration: duration,
            feedbackData: feedbackData
        )
        
        // Use UIKit to present the view modally
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            
            let hostingController = UIHostingController(rootView: reportView)
            hostingController.modalPresentationStyle = UIModalPresentationStyle.fullScreen
            rootViewController.present(hostingController, animated: true)
        }
    }
}
