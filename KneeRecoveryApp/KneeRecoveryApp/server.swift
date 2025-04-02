import Foundation

class ServerAPI {
    private let baseURL = "https://us-central1-pep-pro.cloudfunctions.net"
    private var patientID: String?
    
    func processVoiceInput(audioData: Data, completion: @escaping (Result<[Exercise], Error>) -> Void) {
        let url = URL(string: "\(baseURL)/api/process_audio")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add patient ID if available
        if let patientID = patientID {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"patient_id\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(patientID)\r\n".data(using: .utf8)!)
        }
        
        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"recording.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "ServerAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
                
                // Save patient ID for future requests
                if let patientID = json["patient_id"] as? String {
                    self.patientID = patientID
                }
                
                // Parse exercises
                if let recommendedExercises = json["recommended_exercises"] as? [[String: Any]] {
                    let exercises = recommendedExercises.map { exerciseData -> Exercise in
                        let id = UUID()
                        let name = exerciseData["name"] as? String ?? "Unknown Exercise"
                        let description = exerciseData["description"] as? String ?? ""
                        
                        // Parse target joints
                        let jointStrings = exerciseData["target_joints"] as? [String] ?? []
                        let targetJoints = jointStrings.compactMap { jointString -> BodyJointType? in
                            if jointString == "knee" {
                                return .leftKnee // or both knees depending on your needs
                            } else if jointString == "hip" {
                                return .leftHip
                            } else if jointString == "ankle" {
                                return .leftAnkle
                            }
                            return nil
                        }
                        
                        // Parse instructions
                        let instructions = exerciseData["instructions"] as? [String] ?? []
                        
                        return Exercise(
                            id: id,
                            name: name,
                            description: description,
                            imageURLString: nil,
                            duration: 180,
                            targetJoints: targetJoints,
                            instructions: instructions
                        )
                    }
                    
                    completion(.success(exercises))
                } else {
                    completion(.failure(NSError(domain: "ServerAPI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse exercises"])))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func logExerciseSession(exerciseID: UUID, duration: TimeInterval, completed: Bool, notes: String = "") {
        guard let patientID = patientID else { return }
        
        let url = URL(string: "\(baseURL)/api/log_exercise")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "patient_id": patientID,
            "exercise_id": exerciseID.uuidString,
            "duration": Int(duration),
            "completed": completed,
            "notes": notes
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { _, _, _ in
            // Could add success/error handling here
        }.resume()
    }
    
    func generatePTReport(patientId: String, exerciseId: String, conversationHistory: [[String: Any]], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let url = URL(string: "\(baseURL)/generate_pt_report")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "patient_id": patientId,
            "exercise_id": exerciseId,
            "conversation_history": conversationHistory
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "ServerAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    completion(.success(json))
                } else {
                    completion(.failure(NSError(domain: "ServerAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"])))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
