import Foundation

public struct StateValue: Sendable, Equatable {
    public var value: String
    public var evidence: [EvidenceReference]
    public init(value: String, evidence: [EvidenceReference]) {
        self.value = value
        self.evidence = evidence
    }
}

/// Canon uses absolute world time. Events use story-local time and never cross stories.
/// At the queried time, `beforeSequence` is an exclusive cutoff; earlier times are complete.
/// Equal-time canon precedes events; equal-time events order by sequence, then stable ID.
public struct WorldState: Sendable {
    private struct Key: Hashable { var entityID: ID; var property: String }
    private var values: [Key: StateValue] = [:]

    public init(library: Library, scene: Scene, beforeSequence: Int = Int.max) {
        guard let story = library.stories.first(where: { $0.id == scene.storyID }) else { return }
        let entities = Set(library.entities.filter { $0.worldID == story.worldID }.map(\.id))
        struct Change {
            var time: Int
            var kind: Int
            var sequence: Int
            var id: ID
            var entityID: ID
            var property: String
            var value: String
            var evidence: EvidenceReference
        }
        let (worldTime, overflow) = scene.time.addingReportingOverflow(story.worldOffset)
        guard !overflow else { return }
        var changes = library.facts.compactMap { fact -> Change? in
            guard fact.worldID == story.worldID, entities.contains(fact.entityID),
                  fact.validFrom == nil || fact.validFrom! <= worldTime else { return nil }
            return Change(time: fact.validFrom ?? Int.min, kind: 0, sequence: 0, id: fact.id,
                          entityID: fact.entityID, property: fact.property, value: fact.value, evidence: fact.evidence)
        }
        let storyScenes = Set(library.scenes.filter { $0.storyID == story.id }.map(\.id))
        for event in library.events {
            guard event.storyID == story.id, storyScenes.contains(event.sceneID), entities.contains(event.entityID),
                  event.time < scene.time || (event.time == scene.time && event.sequence < beforeSequence) else { continue }
            let (time, overflow) = event.time.addingReportingOverflow(story.worldOffset)
            guard !overflow else { continue }
            changes.append(Change(time: time, kind: 1, sequence: event.sequence, id: event.id,
                                  entityID: event.entityID, property: event.property, value: event.value, evidence: event.evidence))
        }
        changes.sort {
            if $0.time != $1.time { return $0.time < $1.time }
            if $0.kind != $1.kind { return $0.kind < $1.kind }
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.id < $1.id
        }
        for change in changes {
            let key = Key(entityID: change.entityID, property: change.property)
            // Preserve the transition trail, not just an unsupported latest scalar.
            var evidence = values[key]?.evidence ?? []
            if !evidence.contains(where: { $0.id == change.evidence.id }) { evidence.append(change.evidence) }
            values[key] = StateValue(value: change.value, evidence: evidence)
        }
    }

    public func value(entityID: ID, property: String) -> StateValue? {
        values[Key(entityID: entityID, property: property)]
    }
}
