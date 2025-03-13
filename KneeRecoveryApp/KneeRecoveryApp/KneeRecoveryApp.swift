import SwiftUI
import AVFoundation
import Firebase
import UserNotifications
import FirebaseMessaging

// App Delegate to handle Firebase, notifications, etc.
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Configure Firebase
        FirebaseApp.configure()
        
        // Set Messaging delegate
        Messaging.messaging().delegate = self
        
        // Request permission for push notifications
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
        
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Pass device token to Firebase
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        print("Notification tapped: \(userInfo)")
        
        // Handle notification based on type
        if let type = userInfo["type"] as? String {
            // Navigate to appropriate screen based on notification type
            // In a real app, you'd use NotificationCenter to communicate with SwiftUI
            print("Notification type: \(type)")
        }
        
        completionHandler()
    }
    
    // MARK: - MessagingDelegate
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("Firebase registration token: \(String(describing: fcmToken))")
        
        // Store this token for sending notifications to this device
        if let token = fcmToken {
            UserDefaults.standard.set(token, forKey: "fcmToken")
            
            // In a real app, you'd send this token to your server
            // sendFCMTokenToServer(token)
        }
    }
}

// Main SwiftUI App
@main
struct KneeRecoveryApp: App {
    // Connect AppDelegate to SwiftUI lifecycle
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // State objects for managers
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var visionManager = VisionManager()
    @StateObject private var voiceManager = VoiceManager()
    @StateObject private var speechRecognitionManager = SpeechRecognitionManager()
    @StateObject private var resourceCoordinator = ResourceCoordinator()
    
    // State for onboarding
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    // Environment object to monitor app lifecycle
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                LandingView()
                    .environmentObject(cameraManager)
                    .environmentObject(visionManager)
                    .environmentObject(voiceManager)
                    .environmentObject(speechRecognitionManager)
                    .environmentObject(resourceCoordinator)
                    .onAppear {
                        resourceCoordinator.configure(
                            cameraManager: cameraManager,
                            visionManager: visionManager,
                            voiceManager: voiceManager,
                            speechRecognitionManager: speechRecognitionManager
                        )
                    }
            } else {
                NavigationStack {
                    OnboardingView()
                        .environmentObject(voiceManager)
                        .environmentObject(resourceCoordinator)
                        .onDisappear {
                            hasCompletedOnboarding = true
                        }
                }
            }
        }
        // Monitor app lifecycle and perform cleanup
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                // Clean up when app moves to background
                print("App moving to background - cleaning up resources")
                speechRecognitionManager.cleanUp()
                voiceManager.cleanUp()
                cameraManager.cleanUp()
                resourceCoordinator.stopExerciseSession()
                
                // Force deactivate audio session
                do {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                } catch {
                    print("Failed to deactivate audio session: \(error)")
                }
            }
        }
    }
}
