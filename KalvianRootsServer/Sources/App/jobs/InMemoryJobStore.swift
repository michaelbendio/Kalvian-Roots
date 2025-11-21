import Vapor

actor InMemoryJobStore {
    struct Key: StorageKey { typealias Value = InMemoryJobStore }

    private var jobs: [UUID: JobState] = [:]

    func create(type: String) -> JobState {
        let now = Date()
        let job = JobState(
            id: UUID(),
            type: type,
            status: .queued,
            createdAt: now,
            updatedAt: now
        )
        jobs[job.id] = job
        return job
    }

    func update(id: UUID, mutate: (inout JobState) -> Void) -> JobState? {
        guard var job = jobs[id] else { return nil }
        mutate(&job)
        job.updatedAt = Date()
        jobs[id] = job
        return job
    }

    func get(id: UUID) -> JobState? { jobs[id] }
}
