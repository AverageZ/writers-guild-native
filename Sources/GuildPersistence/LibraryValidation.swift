import Foundation
import GuildCore

extension LibraryStore {
    static func validateID(_ id: ID) throws {
        // Database IDs are bound text, not paths: analyzer keys may contain prose
        // or Unicode. Only scene/lore source-directory components need a whitelist.
        guard !id.isEmpty, id.utf8.count <= 512,
              !id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw LibraryStoreError.invalidData("Unsafe identifier: \(id).")
        }
    }

    static func validate(_ library: Library) throws {
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw LibraryStoreError.invalidData(message) }
        }
        func indexed<T>(_ values: [T], id: (T) -> ID, kind: String) throws -> [ID: T] {
            var result: [ID: T] = [:]
            for value in values {
                let key = id(value)
                try validateID(key)
                try require(result.updateValue(value, forKey: key) == nil, "Duplicate \(kind) identifier \(key).")
            }
            return result
        }
        func sourceID(_ id: ID) throws {
            try require(!id.isEmpty && id != "." && id != ".." && id.utf8.count <= 128 &&
                        id.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) },
                        "Unsafe source identifier \(id).")
        }
        func anchor(_ anchor: TextAnchor) throws {
            try validateID(anchor.sceneID)
            try require(anchor.revision >= 0 && anchor.start >= 0 && anchor.length >= 0 && anchor.start <= Int.max - anchor.length, "Invalid text anchor range or revision.")
            // Historical anchors may outlive their text. Never require current text
            // to match a previous revision's offsets or quote.
        }
        func evidence(_ evidence: EvidenceReference) throws {
            try validateID(evidence.id)
            try validateID(evidence.sourceID)
            if let value = evidence.anchor { try anchor(value) }
        }
        let worlds = try indexed(library.worlds, id: { $0.id }, kind: "world")
        let stories = try indexed(library.stories, id: { $0.id }, kind: "story")
        let scenes = try indexed(library.scenes, id: { $0.id }, kind: "scene")
        let manuscripts = try indexed(library.manuscripts, id: { $0.sceneID }, kind: "manuscript")
        let lore = try indexed(library.lore, id: { $0.id }, kind: "lore")
        let entities = try indexed(library.entities, id: { $0.id }, kind: "entity")
        _ = try indexed(library.facts, id: { $0.id }, kind: "fact")
        _ = try indexed(library.events, id: { $0.id }, kind: "event")
        _ = try indexed(library.claims, id: { $0.id }, kind: "claim")
        let agents = try indexed(library.agents, id: { $0.id }, kind: "agent")
        let observations = try indexed(library.observations, id: { $0.id }, kind: "observation")
        let feedback = try indexed(library.feedback, id: { $0.id }, kind: "feedback")
        _ = try indexed(library.memories, id: { $0.id }, kind: "memory")
        _ = try indexed(library.reviewRuns, id: { $0.id }, kind: "review run")
        for value in library.stories { try require(worlds[value.worldID] != nil, "Story \(value.id) has no world.") }
        for value in library.scenes {
            try sourceID(value.id)
            try require(stories[value.storyID] != nil, "Scene \(value.id) has no story.")
        }
        for value in manuscripts.values {
            try require(scenes[value.sceneID] != nil && value.revision >= 0, "Manuscript has no scene or an invalid revision.")
        }
        for value in lore.values {
            try sourceID(value.id)
            try require(worlds[value.worldID] != nil, "Lore \(value.id) has no world.")
        }
        for value in entities.values { try require(worlds[value.worldID] != nil, "Entity \(value.id) has no world.") }
        for value in library.facts {
            try require(worlds[value.worldID] != nil && entities[value.entityID]?.worldID == value.worldID, "Canon fact \(value.id) has mismatched ownership.")
            try evidence(value.evidence)
        }
        func stateOwnership(story: ID, scene: ID, entity: ID) throws {
            guard let owner = stories[story] else { throw LibraryStoreError.invalidData("State record has no story.") }
            try require(scenes[scene]?.storyID == story && entities[entity]?.worldID == owner.worldID, "State record crosses story or world boundaries.")
        }
        for value in library.events {
            try stateOwnership(story: value.storyID, scene: value.sceneID, entity: value.entityID)
            try evidence(value.evidence)
        }
        for value in library.claims {
            try stateOwnership(story: value.storyID, scene: value.sceneID, entity: value.entityID)
            try require(value.anchor.sceneID == value.sceneID, "Claim anchor belongs to a different scene.")
            try anchor(value.anchor)
        }
        for value in observations.values {
            try require(agents[value.agentID] != nil && scenes[value.anchor.sceneID] != nil, "Observation has no agent or scene.")
            try anchor(value.anchor)
            for reference in value.evidence { try evidence(reference) }
        }
        for value in feedback.values {
            try validateID(value.observationID)
            try require(agents[value.agentID] != nil && worlds[value.worldID] != nil, "Feedback has no agent or world.")
            if let observation = observations[value.observationID] {
                let story = scenes[observation.anchor.sceneID].flatMap { stories[$0.storyID] }
                try require(observation.agentID == value.agentID && story?.worldID == value.worldID, "Feedback crosses agent or world boundaries.")
            }
        }
        for value in library.memories {
            try require(agents[value.agentID] != nil && worlds[value.worldID] != nil, "Memory has no agent or world.")
            for id in value.sourceFeedbackIDs {
                try validateID(id)
                if let source = feedback[id] {
                    try require(source.agentID == value.agentID && source.worldID == value.worldID, "Memory feedback crosses agent or world boundaries.")
                }
            }
        }
        for value in library.reviewRuns {
            try require(scenes[value.sceneID] != nil && value.revision >= 0, "Review run has no scene or invalid revision.")
        }
    }
}
