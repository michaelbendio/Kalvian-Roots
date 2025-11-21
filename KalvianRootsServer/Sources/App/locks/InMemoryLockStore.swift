import Vapor

actor InMemoryLockStore {
    struct Key: StorageKey { typealias Value = InMemoryLockStore }

    private var locks: [String: FamilyLock] = [:]

    func acquire(familyId: String, owner: String?, purpose: String?, ttl: TimeInterval) -> FamilyLock? {
        let now = Date()
        if let existing = locks[familyId], existing.expiresAt > now { return nil }
        let lock = FamilyLock(
            leaseId: UUID(),
            familyId: familyId,
            owner: owner,
            purpose: purpose,
            expiresAt: now.addingTimeInterval(ttl)
        )
        locks[familyId] = lock
        return lock
    }

    func heartbeat(leaseId: UUID, ttl: TimeInterval) -> FamilyLock? {
        let now = Date()
        guard let (fid, lock) = locks.first(where: { $0.value.leaseId == leaseId }) else { return nil }
        var updated = lock
        updated.expiresAt = now.addingTimeInterval(ttl)
        locks[fid] = updated
        return updated
    }

    func release(leaseId: UUID) {
        if let fid = locks.first(where: { $0.value.leaseId == leaseId })?.key {
            locks.removeValue(forKey: fid)
        }
    }
}
