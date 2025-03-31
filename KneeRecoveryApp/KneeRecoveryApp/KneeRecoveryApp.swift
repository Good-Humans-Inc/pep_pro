import SwiftUI
import AVFoundation
import Firebase
import UserNotifications
import FirebaseMessaging

// App Delegate to handle Firebase, notifications, etc.
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    // Track if this is first launch of the app
    @AppStorage("isFirstAppLaunch") private var isFirstAppLaunch = true
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        print("📱 Application launching (first launch: \(isFirstAppLaunch))")
        
        // Special setup for first app launch
        if isFirstAppLaunch {
            setupForFirstLaunch()
        }
        
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
        
        // Only mark first launch as complete after setup is done
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.isFirstAppLaunch = false
            print("📱 First launch setup completed")
        }
        
        return true
    }
    
    // Setup specific configurations for first launch
    private func setupForFirstLaunch() {
        print("🔄 Setting up app for first launch")
        
        // Reset all UserDefaults flags related to initialization
        UserDefaults.standard.set(false, forKey: "cameraManagerInitialized")
        UserDefaults.standard.set(false, forKey: "hasStartedExerciseBefore")
        
        // Pre-initialize AVCaptureSession at app startup to reduce failures
        let captureSession = AVCaptureSession()
        let sessionQueue = DispatchQueue(label: "session queue")
        
        // Request camera permissions right away
        AVCaptureDevice.requestAccess(for: .video) { granted in
            print("📷 Camera permission pre-request result: \(granted)")
            
            // If granted, do an initial configuration
            if granted {
                sessionQueue.async {
                    captureSession.beginConfiguration()
                    
                    // Attempt to add an input
                    if let device = AVCaptureDevice.default(for: .video),
                       let input = try? AVCaptureDeviceInput(device: device),
                       captureSession.canAddInput(input) {
                        captureSession.addInput(input)
                    }
                    
                    captureSession.commitConfiguration()
                    
                    // Start and immediately stop the session
                    captureSession.startRunning()
                    Thread.sleep(forTimeInterval: 0.5)
                    captureSession.stopRunning()
                    
                    print("✅ Camera session pre-initialized")
                }
            }
        }
        
        // Pre-configure audio session to initialize the system
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // First make sure it's not active
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            
            // Configure with default settings
            try audioSession.setCategory(.playAndRecord,
                                      mode: .default,
                                      options: [.defaultToSpeaker])
            
            // Briefly activate and deactivate to initialize
            try audioSession.setActive(true)
            try audioSession.setActive(false)
            
            // Now configure with proper settings for our app
            try audioSession.setCategory(.playAndRecord,
                                      mode: .spokenAudio,
                                      options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
                                      
            try audioSession.setPreferredSampleRate(48000.0)
            try audioSession.setPreferredIOBufferDuration(0.005)
            
            try audioSession.setActive(true)
            try audioSession.setActive(false)
            
            print("✅ Audio session pre-initialized for first launch")
        } catch {
            print("❌ Error pre-initializing audio session: \(error)")
        }
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
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    // First time launch flag
    @AppStorage("isFirstAppLaunch") private var isFirstAppLaunch = true
    
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
                    print("📱 LandingView appeared - app launch state: \(isFirstAppLaunch ? "first launch" : "subsequent launch")")
                    
                    // Configure resource coordinator with all the managers
                    resourceCoordinator.configure(
                        cameraManager: cameraManager,
                        visionManager: visionManager,
                        voiceManager: voiceManager,
                        speechRecognitionManager: speechRecognitionManager
                    )
                    
                    // Ensure any lingering sessions are terminated
                    if voiceManager.isSessionActive {
                        print("⚠️ Terminating lingering voice session in LandingView")
                        voiceManager.endElevenLabsSession()
                    }
                    
                    // Pre-initialize camera on first app launch to reduce errors
                    if isFirstAppLaunch {
                        print("🔄 First app launch - pre-initializing camera and audio")
                        preInitializeResources()
                    }
                    
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
                        .onAppear {
                            // Configure resource coordinator with all the managers
                            resourceCoordinator.configure(
                                cameraManager: cameraManager,
                                visionManager: visionManager,
                                voiceManager: voiceManager,
                                speechRecognitionManager: speechRecognitionManager
                            )
                            
                            // Pre-initialize camera on first app launch to reduce errors
                            if isFirstAppLaunch {
                                print("🔄 First app launch - pre-initializing camera and audio")
                                preInitializeResources()
                            }
                        }
                }
            }
        }
        // Monitor app lifecycle and perform cleanup
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                print("App became active")
            case .inactive:
                print("App became inactive")
            case .background:
                // Clean up when app moves to background
                print("App moving to background - cleaning up resources")
                cleanupResources()
            @unknown default:
                print("Unknown scene phase")
            }
        }
    }
    
    // Pre-initialize resources to prevent first-run issues
    private func preInitializeResources() {
        // First reset the camera to ensure clean state
        cameraManager.resetSession()
        
        // Start and immediately stop a camera session to warm it up
        cameraManager.startSession {
            print("✅ Camera pre-initialization completed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                cameraManager.stopSession()
                
                // Reset first launch flag after initialization
                isFirstAppLaunch = false
            }
        }
        
        // Configure audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try audioSession.setActive(true)
            try audioSession.setActive(false)
            print("✅ Audio session pre-initialized")
        } catch {
            print("❌ Error pre-initializing audio session: \(error)")
        }
    }
    
    // Cleanup all resources when app moves to background
    private func cleanupResources() {
        speechRecognitionManager.cleanUp()
        voiceManager.cleanUp()
        cameraManager.cleanUp()
        resourceCoordinator.stopExerciseSession()
        
        // Force deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("✅ Audio session deactivated on app background")
        } catch {
            print("❌ Failed to deactivate audio session: \(error)")
        }
    }
}
