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
    // Initialize AppState first
    private let appState = AppState()
    
    // Initialize managers with AppState
    private let voiceManager: VoiceManager
    private let cameraManager: CameraManager
    private let speechRecognitionManager: SpeechRecognitionManager
    private let resourceCoordinator: ResourceCoordinator
    private let visionManager: VisionManager
    
    init() {
        // Initialize vision manager first since camera manager depends on it
        visionManager = VisionManager(appState: appState)
        
        // Initialize camera manager with vision manager
        cameraManager = CameraManager(appState: appState, visionManager: visionManager)
        
        // Initialize other managers
        voiceManager = VoiceManager(appState: appState)
        speechRecognitionManager = SpeechRecognitionManager(appState: appState)
        resourceCoordinator = ResourceCoordinator(appState: appState)


        
        // Start vision processing
        visionManager.isProcessing = true
        print("🚀 App initialization complete")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(voiceManager)
                .environmentObject(cameraManager)
                .environmentObject(speechRecognitionManager)
                .environmentObject(resourceCoordinator)
                .environmentObject(visionManager)
        }
    }
}
