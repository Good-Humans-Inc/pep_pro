import Foundation
import SwiftUI
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate, MessagingDelegate {
    @Published var isNotificationAuthorized = false
    @Published var fcmToken: String?
    @Published var notificationError: String?
    
    static let shared = NotificationManager()
    
    override init() {
        super.init()
        
        // Request notification permissions
        requestPermissions()
        
        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = self
    }
    
    // Should be called from AppDelegate
    func setupFirebase() {
        // Set up messaging delegate
        Messaging.messaging().delegate = self
    }
    
    func requestPermissions() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.isNotificationAuthorized = granted
                
                if let error = error {
                    self.notificationError = error.localizedDescription
                    print("Notification permission error: \(error.localizedDescription)")
                }
                
                if granted {
                    print("Notification permission granted")
                    
                    // Register for remote notifications
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                } else {
                    print("Notification permission denied")
                }
            }
        }
    }
    
    // Method to schedule a local notification (fallback if FCM isn't available)
    func scheduleLocalNotification(title: String, body: String, date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        // Create trigger
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        // Create request
        let identifier = UUID().uuidString
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        // Add to notification center
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            } else {
                print("Local notification scheduled for \(date)")
            }
        }
    }
    
    // Method to register exercise reminders with the backend
    func registerExerciseReminders(patientId: String, frequency: String, time: String, days: [String] = []) {
        guard let fcmToken = self.fcmToken else {
            self.notificationError = "FCM token not available"
            return
        }
        
        // Create request to backend
        let url = URL(string: "https://us-central1-duoligo-pt-app.cloudfunctions.net/schedule_notifications")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create request body
        let requestBody: [String: Any] = [
            "patient_id": patientId,
            "schedule": [
                "frequency": frequency,
                "time": time,
                "days": days
            ],
            "fcm_token": fcmToken
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            // Send request
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.notificationError = "Failed to register reminders: \(error.localizedDescription)"
                    }
                    return
                }
                
                guard let data = data else {
                    DispatchQueue.main.async {
                        self.notificationError = "No data received from server"
                    }
                    return
                }
                
                // Process response
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = json["status"] as? String,
                       status == "success" {
                        DispatchQueue.main.async {
                            print("Exercise reminders registered successfully")
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.notificationError = "Failed to register reminders: invalid response"
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.notificationError = "Failed to parse response: \(error.localizedDescription)"
                    }
                }
            }.resume()
            
        } catch {
            self.notificationError = "Failed to create request: \(error.localizedDescription)"
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate Methods
    
    // Handle foreground notifications
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification interactions
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        // Process notification data
        if let type = userInfo["type"] as? String, type == "exercise_reminder" {
            // In a real app, you would navigate to the exercise screen here
            print("User tapped on exercise reminder notification")
        }
        
        completionHandler()
    }
    
    // MARK: - MessagingDelegate Methods
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // Store the token
        self.fcmToken = fcmToken
        
        print("Firebase registration token: \(String(describing: fcmToken))")
        
        // Send the token to your server (in a real app, you'd do this when a user logs in)
        if let token = fcmToken, let patientId = UserDefaults.standard.string(forKey: "patient_id") {
            // Register with default settings
            registerExerciseReminders(patientId: patientId, frequency: "daily", time: "09:00")
        }
    }
    
    // Helper method to register tokens with Firebase
    func registerDeviceToken(_ deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
    
    // Method for setting up notification settings UI
    func createNotificationSettingsView() -> some View {
        NotificationSettingsView(manager: self)
    }
}

// Notification Settings View
struct NotificationSettingsView: View {
    @ObservedObject var manager: NotificationManager
    
    @State private var frequency = "daily"
    @State private var reminderTime = Date()
    @State private var selectedDays: Set<String> = ["monday", "wednesday", "friday"]
    
    var body: some View {
        Form {
            Section(header: Text("Notification Permissions")) {
                HStack {
                    Text("Notifications")
                    Spacer()
                    Text(manager.isNotificationAuthorized ? "Enabled" : "Disabled")
                        .foregroundColor(manager.isNotificationAuthorized ? .green : .red)
                }
                
                if !manager.isNotificationAuthorized {
                    Button("Enable Notifications") {
                        manager.requestPermissions()
                    }
                    .foregroundColor(.blue)
                }
            }
            
            Section(header: Text("Exercise Reminders")) {
                Picker("Frequency", selection: $frequency) {
                    Text("Daily").tag("daily")
                    Text("Every Other Day").tag("every-other-day")
                    Text("Weekly").tag("weekly")
                }
                
                DatePicker("Reminder Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                
                if frequency == "weekly" {
                    VStack(alignment: .leading) {
                        Text("Days of the Week")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        WeekdaySelectorView(selectedDays: $selectedDays)
                    }
                }
                
                Button("Save Reminder Settings") {
                    saveReminderSettings()
                }
                .foregroundColor(.blue)
            }
        }
        .navigationTitle("Notification Settings")
    }
    
    private func saveReminderSettings() {
        guard let patientId = UserDefaults.standard.string(forKey: "patient_id") else {
            return
        }
        
        // Format time
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeString = formatter.string(from: reminderTime)
        
        // Register with backend
        manager.registerExerciseReminders(
            patientId: patientId,
            frequency: frequency,
            time: timeString,
            days: Array(selectedDays)
        )
    }
}

// Weekday selector component
struct WeekdaySelectorView: View {
    @Binding var selectedDays: Set<String>
    
    private let weekdays = [
        ("S", "sunday"),
        ("M", "monday"),
        ("T", "tuesday"),
        ("W", "wednesday"),
        ("T", "thursday"),
        ("F", "friday"),
        ("S", "saturday")
    ]
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(weekdays, id: \.1) { day in
                Button(action: {
                    toggleDay(day.1)
                }) {
                    Text(day.0)
                        .frame(width: 35, height: 35)
                        .background(selectedDays.contains(day.1) ? Color.blue : Color.gray.opacity(0.3))
                        .foregroundColor(selectedDays.contains(day.1) ? .white : .black)
                        .cornerRadius(17.5)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func toggleDay(_ day: String) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }
}
