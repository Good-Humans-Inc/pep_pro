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
    @State private var isGeneratingPDF = false
    @State private var pdfGenerated = false
    @State private var pdfError: String? = nil
    @State private var showingShareSheet = false
    @State private var pdfURL: URL? = nil
    @EnvironmentObject private var voiceManager: VoiceManager
    
    var body: some View {
        VStack(spacing: 10) {
            Button(action: {
                showingPTReportAlert = true
            }) {
                HStack {
                    Image(systemName: "doc.text.fill")
                    Text("Export PT Report as PDF")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
                .foregroundColor(.blue)
            }
            .disabled(isGeneratingPDF)
            
            if isGeneratingPDF {
                ProgressView("Generating PDF...")
                    .padding(.top, 5)
            }
            
            if pdfGenerated {
                Text("PDF generated successfully!")
                    .foregroundColor(.green)
                    .font(.caption)
                    .padding(.top, 5)
            }
            
            if let error = pdfError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.top, 5)
                    .multilineTextAlignment(.center)
            }
        }
        .alert(isPresented: $showingPTReportAlert) {
            Alert(
                title: Text("Export PT Report"),
                message: Text("This will generate a PDF report that you can share with your physical therapist. Would you like to proceed?"),
                primaryButton: .default(Text("Generate PDF")) {
                    generatePTReportPDF()
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = pdfURL {
                ShareSheet(activityItems: [url])
            }
        }
    }
    
    private func generatePTReportPDF() {
        isGeneratingPDF = true
        pdfGenerated = false
        pdfError = nil
        
        // Get the current feedback data
        guard let storedFeedback = UserDefaults.standard.data(forKey: "LastExerciseFeedback"),
              let feedbackData = try? JSONDecoder().decode(ExerciseFeedbackData.self, from: storedFeedback) else {
            pdfError = "No exercise feedback data available"
            isGeneratingPDF = false
            return
        }
        
        // Create PDF content
        let pdfContent = createPDFContent(feedbackData: feedbackData)
        
        // Generate PDF
        let pdfData = createPDF(from: pdfContent)
        
        // Save PDF to documents directory
        do {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileName = "PT_Report_\(Date().timeIntervalSince1970).pdf"
            let fileURL = documentsDirectory.appendingPathComponent(fileName)
            
            try pdfData.write(to: fileURL)
            
            // Update state and show share sheet
            DispatchQueue.main.async {
                self.pdfURL = fileURL
                self.isGeneratingPDF = false
                self.pdfGenerated = true
                self.showingShareSheet = true
            }
        } catch {
            DispatchQueue.main.async {
                self.pdfError = "Failed to save PDF: \(error.localizedDescription)"
                self.isGeneratingPDF = false
            }
        }
    }
    
    private func createPDFContent(feedbackData: ExerciseFeedbackData) -> NSAttributedString {
        let content = NSMutableAttributedString()
        
        // Title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 24),
            .foregroundColor: UIColor.black
        ]
        content.append(NSAttributedString(string: "Physical Therapy Exercise Report\n\n", attributes: titleAttributes))
        
        // Date
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor.gray
        ]
        content.append(NSAttributedString(string: "Date: \(Date().formatted())\n\n", attributes: dateAttributes))
        
        // Patient ID
        content.append(NSAttributedString(string: "Patient ID: \(patientId)\n", attributes: dateAttributes))
        content.append(NSAttributedString(string: "Exercise ID: \(exerciseId)\n\n", attributes: dateAttributes))
        
        // General Feeling
        let sectionAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: UIColor.black
        ]
        content.append(NSAttributedString(string: "General Feeling\n", attributes: sectionAttributes))
        content.append(NSAttributedString(string: "\(feedbackData.generalFeeling)\n\n", attributes: dateAttributes))
        
        // Performance Quality
        content.append(NSAttributedString(string: "Performance Quality\n", attributes: sectionAttributes))
        content.append(NSAttributedString(string: "\(feedbackData.performanceQuality)\n\n", attributes: dateAttributes))
        
        // Pain Report
        content.append(NSAttributedString(string: "Pain Report\n", attributes: sectionAttributes))
        content.append(NSAttributedString(string: "\(feedbackData.painReport)\n\n", attributes: dateAttributes))
        
        // Exercise Statistics
        content.append(NSAttributedString(string: "Exercise Statistics\n", attributes: sectionAttributes))
        content.append(NSAttributedString(string: "Sets Completed: \(feedbackData.setsCompleted)\n", attributes: dateAttributes))
        content.append(NSAttributedString(string: "Reps Completed: \(feedbackData.repsCompleted)\n", attributes: dateAttributes))
        content.append(NSAttributedString(string: "Day Streak: \(feedbackData.dayStreak)\n\n", attributes: dateAttributes))
        
        // Motivational Message
        content.append(NSAttributedString(string: "Motivational Message\n", attributes: sectionAttributes))
        content.append(NSAttributedString(string: "\(feedbackData.motivationalMessage)\n", attributes: dateAttributes))
        
        return content
    }
    
    private func createPDF(from content: NSAttributedString) -> Data {
        let pdfMetaData = [
            kCGPDFContextCreator: "PEP Pro App",
            kCGPDFContextAuthor: "PEP Pro System"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageWidth: CGFloat = 8.5 * 72.0
        let pageHeight: CGFloat = 11 * 72.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let data = renderer.pdfData { context in
            context.beginPage()
            
            // Draw content
            content.draw(in: pageRect.insetBy(dx: 50, dy: 50))
        }
        
        return data
    }
}

// ShareSheet view for sharing the PDF
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
