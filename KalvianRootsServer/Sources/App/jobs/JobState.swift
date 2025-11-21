import Vapor

struct JobState: Content {
    enum Status: String, Codable { case queued, running, completed, failed }
    var id: UUID
    var type: String
    var status: Status
    var createdAt: Date
    var updatedAt: Date
    var progress: Double?
    var message: String?
    var resultJSON: String?
    var errorCode: String?
    var errorMessage: String?
}
