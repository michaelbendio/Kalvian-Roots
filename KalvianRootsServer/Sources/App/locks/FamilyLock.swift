import Vapor

struct FamilyLock: Content {
    var leaseId: UUID
    var familyId: String
    var owner: String?
    var purpose: String?
    var expiresAt: Date
}
