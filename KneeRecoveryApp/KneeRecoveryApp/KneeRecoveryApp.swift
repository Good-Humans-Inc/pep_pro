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
        
        // Request notification permission
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: { granted, error in
                if granted {
                    print("Notification permission granted")
                } else {
                    print("Notification permission denied: \(String(describing: error))")
                }
            }
        )
        
        // Register for remote notifications
        application.registerForRemoteNotifications()
        
        return true
    }
    
    // Handle registration for remote notifications
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Pass device token to Firebase
        Messaging.messaging().apnsToken = deviceToken
    }
    
    // Handle failed registration
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // MARK: - MessagingDelegate
    
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
        if let token = fcmToken {
            print("FCM registration token: \(token)")
            
            // Store the token locally
            UserDefaults.standard.set(token, forKey: "FCMToken")
            
            // Display the token in an alert for easy copying during development
            #if DEBUG
            DispatchQueue.main.async {
                let alertController = UIAlertController(
                    title: "FCM Token",
                    message: token,
                    preferredStyle: .alert
                )
                alertController.addAction(UIAlertAction(title: "Copy", style: .default) { _ in
                    UIPasteboard.general.string = token
                })
                alertController.addAction(UIAlertAction(title: "OK", style: .cancel))
                
                // Get the current top view controller to present the alert
                UIApplication.shared.windows.first?.rootViewController?.present(alertController, animated: true)
            }
            #endif
        } else {
            print("FCM token is nil")
        }
    }
}

// Main SwiftUI App
@main
struct KneeRecoveryApp: App {
    // Connect AppDelegate to SwiftUI lifecycle
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // State objects for managers
    @StateObject var cameraManager = CameraManager()
    @StateObject var visionManager = VisionManager()
    @StateObject var voiceManager = VoiceManager()
    @StateObject var speechRecognitionManager = SpeechRecognitionManager()
    @StateObject var resourceCoordinator = ResourceCoordinator()
    
    // State for onboarding
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    
    // Environment object to monitor app lifecycle
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                NavigationView {
                    LandingView()
                        .environmentObject(cameraManager)
                        .environmentObject(visionManager)
                        .environmentObject(voiceManager)
                        .environmentObject(speechRecognitionManager)
                        .environmentObject(resourceCoordinator)
                }
                .environmentObject(cameraManager)
                .environmentObject(visionManager)
                .environmentObject(voiceManager)
                .environmentObject(speechRecognitionManager)
                .environmentObject(resourceCoordinator)
                .onAppear {
                    
                    // Ensure any lingering sessions are terminated
                    if voiceManager.isSessionActive {
                        print("⚠️ Terminating lingering voice session in LandingView")
                        voiceManager.endElevenLabsSession()
                    }
                    
                    resourceCoordinator.configure(
                        cameraManager: cameraManager,
                        visionManager: visionManager,
                        voiceManager: voiceManager,
                        speechRecognitionManager: speechRecognitionManager
                    )
                    
                    // Debug environment objects
                    print("App initialized with environment objects:")
                    print("- Camera Manager: \(cameraManager)")
                    print("- Vision Manager: \(visionManager)")
                    print("- Voice Manager: \(voiceManager)")
                    print("- Speech Recognition Manager: \(speechRecognitionManager)")
                    print("- Resource Coordinator: \(resourceCoordinator)")
                }
            } else {
                NavigationStack {
                    OnboardingView()
                        .environmentObject(voiceManager)
                        .environmentObject(resourceCoordinator)
                        .environmentObject(cameraManager)
                        .environmentObject(visionManager)
                        .environmentObject(speechRecognitionManager)
                        .onDisappear {
                            // Terminate any active sessions when view disappears
                            if voiceManager.isSessionActive {
                                print("⚠️ Terminating voice session on OnboardingView disappear")
                                voiceManager.endElevenLabsSession()
                            }
                            
                            // Update navigation state
                            hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "HasCompletedOnboarding")
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
