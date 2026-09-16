import Foundation

public typealias ID = String
public func newID() -> ID { UUID().uuidString.lowercased() }

public struct World: Codable, Identifiable, Sendable, Equatable {
    public var id: ID
    public var name: String
    public init(id: ID = newID(), name: String) { self.id = id; self.name = name }
}
public struct Story: Codable, Identifiable, Sendable, Equatable {
    public var id: ID
    public var worldID: ID
    public var title: String
    /// Offset in the world's arbitrary chronology units; stories never inherit other stories' events.
    public var worldOffset: Int
    public init(id: ID = newID(), worldID: ID, title: String, worldOffset: Int = 0) {
        self.id = id; self.worldID = worldID; self.title = title; self.worldOffset = worldOffset
    }
}
public struct Scene: Codable, Identifiable, Sendable, Equatable {
    public var id: ID
    public var storyID: ID
    public var title: String
    public var chapter: String
    public var order: Int
    /// Chronological time independent of presentation order, permitting flashbacks.
    public var time: Int
    public var expectedTense: String
    public init(id: ID = newID(), storyID: ID, title: String, chapter: String = "Chapter 1", order: Int, time: Int, expectedTense: String = "past") {
        self.id = id; self.storyID = storyID; self.title = title; self.chapter = chapter
        self.order = order; self.time = time; self.expectedTense = expectedTense
    }
}
public struct Manuscript: Codable, Sendable, Equatable {
    public var sceneID: ID
    public var html: String
    /// UTF-16 offsets into block-separated editor text, never Wordgard token positions.
    public var text: String
    public var revision: Int
    public init(sceneID: ID, html: String = "<p></p>", text: String = "", revision: Int = 0) {
        self.sceneID = sceneID; self.html = html; self.text = text; self.revision = revision
    }
}
public struct Lore: Codable, Identifiable, Sendable, Equatable {
    public var id: ID
    public var worldID: ID
    public var title: String
    public var markdown: String
    public init(id: ID = newID(), worldID: ID, title: String, markdown: String = "") {
        self.id = id; self.worldID = worldID; self.title = title; self.markdown = markdown
    }
}
public struct Entity: Codable, Identifiable, Sendable, Equatable {
    public var id: ID
    public var worldID: ID
    public var name: String
    public var kind: String
    public var aliases: [String]
    public init(id: ID = newID(), worldID: ID, name: String, kind: String = "character", aliases: [String] = []) {
        self.id = id; self.worldID = worldID; self.name = name; self.kind = kind; self.aliases = aliases
    }
}
public struct TextAnchor: Codable, Sendable, Equatable {
    public var sceneID: ID
    public var revision: Int
    public var start: Int
    public var length: Int
    public var quote: String
    public var prefix: String
    public var suffix: String
    public init(sceneID: ID, revision: Int, start: Int, length: Int, quote: String, prefix: String = "", suffix: String = "") {
        self.sceneID = sceneID; self.revision = revision; self.start = start; self.length = length
        self.quote = quote; self.prefix = prefix; self.suffix = suffix
    }
}
public struct EvidenceReference: Codable, Identifiable, Sendable, Equatable {
    public var id: ID
    public var kind: String
    public var sourceID: ID
    public var label: String
    public var quote: String
    public var anchor: TextAnchor?
    public init(id: ID = newID(), kind: String, sourceID: ID, label: String, quote: String, anchor: TextAnchor? = nil) {
        self.id = id; self.kind = kind; self.sourceID = sourceID; self.label = label; self.quote = quote; self.anchor = anchor
    }
}
public struct CanonicalFact: Codable, Identifiable, Sendable, Equatable {
    public var id: ID
    public var worldID: ID
    public var entityID: ID
    public var property: String
    public var value: String
    public var validFrom: Int?
    public var evidence: EvidenceReference
    public init(id: ID = newID(), worldID: ID, entityID: ID, property: String, value: String, validFrom: Int? = nil, evidence: EvidenceReference) {
        self.id = id; self.worldID = worldID; self.entityID = entityID; self.property = property
        self.value = value; self.validFrom = validFrom; self.evidence = evidence
    }
}
public struct StoryEvent: Codable, Identifiable, Sendable, Equatable {
    public var id: ID
    public var storyID: ID
    public var sceneID: ID
    public var time: Int
    public var sequence: Int
    public var entityID: ID
    public var property: String
    public var value: String
    public var previousValue: String?
    public var evidence: EvidenceReference
    public init(id: ID = newID(), storyID: ID, sceneID: ID, time: Int, sequence: Int = 0, entityID: ID, property: String, value: String, previousValue: String? = nil, evidence: EvidenceReference) {
        self.id = id; self.storyID = storyID; self.sceneID = sceneID; self.time = time; self.sequence = sequence
        self.entityID = entityID; self.property = property; self.value = value; self.previousValue = previousValue; self.evidence = evidence
    }
}
public enum ClaimStatus: String, Codable, Sendable { case pending, accepted, rejected, conflict, ambiguous }
public struct NarrativeClaim: Codable, Identifiable, Sendable, Equatable {
    public var id: ID
    public var storyID: ID
    public var sceneID: ID
    public var entityID: ID
    public var property: String
    public var value: String
    public var isTransition: Bool
    public var anchor: TextAnchor
    public var status: ClaimStatus
    public init(id: ID = newID(), storyID: ID, sceneID: ID, entityID: ID, property: String, value: String, isTransition: Bool, anchor: TextAnchor, status: ClaimStatus = .pending) {
        self.id = id; self.storyID = storyID; self.sceneID = sceneID; self.entityID = entityID
        self.property = property; self.value = value; self.isTransition = isTransition; self.anchor = anchor; self.status = status
    }
}
public struct AgentDefinition: Codable, Identifiable, Sendable, Equatable {
    public var id: ID
    public var name: String
    public var role: String
    public var categories: [String]
    public var traits: [String]
    public var enabled: Bool
    public var confidenceThreshold: Double
    public var frequencySeconds: Double
    public var patternThreshold: Int
    public init(id: ID, name: String, role: String, categories: [String], traits: [String], enabled: Bool = true, confidenceThreshold: Double = 0.65, frequencySeconds: Double = 2, patternThreshold: Int = 3) {
        self.id = id; self.name = name; self.role = role; self.categories = categories; self.traits = traits
        self.enabled = enabled; self.confidenceThreshold = confidenceThreshold; self.frequencySeconds = frequencySeconds; self.patternThreshold = patternThreshold
    }
}
public enum ObservationStatus: String, Codable, CaseIterable, Sendable { case unread, read, accepted, dismissed, markedIntentional, obsolete }
public struct AgentObservation: Codable, Identifiable, Sendable, Equatable {
    public var id: ID
    public var agentID: ID
    public var category: String
    public var severity: String
    public var confidence: Double
    public var anchor: TextAnchor
    public var message: String
    public var question: String?
    public var evidence: [EvidenceReference]
    public var createdAt: Date
    public var status: ObservationStatus
    public init(id: ID = newID(), agentID: ID, category: String, severity: String = "concern", confidence: Double, anchor: TextAnchor, message: String, question: String? = nil, evidence: [EvidenceReference], createdAt: Date = Date(), status: ObservationStatus = .unread) {
        self.id = id; self.agentID = agentID; self.category = category; self.severity = severity; self.confidence = confidence
        self.anchor = anchor; self.message = message; self.question = question; self.evidence = evidence; self.createdAt = createdAt; self.status = status
    }
}
public struct FeedbackEvent: Codable, Identifiable, Sendable, Equatable {
    public var id: ID
    public var observationID: ID
    public var agentID: ID
    public var worldID: ID
    public var category: String
    public var action: ObservationStatus
    public var createdAt: Date
    public init(id: ID = newID(), observationID: ID, agentID: ID, worldID: ID, category: String, action: ObservationStatus, createdAt: Date = Date()) {
        self.id = id; self.observationID = observationID; self.agentID = agentID; self.worldID = worldID
        self.category = category; self.action = action; self.createdAt = createdAt
    }
}
public struct AgentMemory: Codable, Identifiable, Sendable, Equatable {
    public var id: ID
    public var agentID: ID
    public var worldID: ID
    public var layer: String
    public var category: String
    public var belief: String
    public var salience: Double
    public var strength: Double
    public var confidence: Double
    public var decayRate: Double
    public var createdAt: Date
    public var lastRecalledAt: Date
    public var recallCount: Int
    public var sourceFeedbackIDs: [ID]
    public init(id: ID = newID(), agentID: ID, worldID: ID, layer: String, category: String, belief: String, salience: Double = 0.5, strength: Double = 1, confidence: Double = 0.7, decayRate: Double = 0.02, createdAt: Date = Date(), lastRecalledAt: Date = Date(), recallCount: Int = 0, sourceFeedbackIDs: [ID] = []) {
        self.id = id; self.agentID = agentID; self.worldID = worldID; self.layer = layer; self.category = category; self.belief = belief
        self.salience = salience; self.strength = strength; self.confidence = confidence; self.decayRate = decayRate
        self.createdAt = createdAt; self.lastRecalledAt = lastRecalledAt; self.recallCount = recallCount; self.sourceFeedbackIDs = sourceFeedbackIDs
    }
}
public struct ReviewRun: Codable, Identifiable, Sendable, Equatable {
    public var id: ID
    public var sceneID: ID
    public var revision: Int
    public var startedAt: Date
    public var status: String
    public init(id: ID = newID(), sceneID: ID, revision: Int, startedAt: Date = Date(), status: String) {
        self.id = id; self.sceneID = sceneID; self.revision = revision; self.startedAt = startedAt; self.status = status
    }
}
/// Value snapshot passed to analyzers. Manuscript and lore payloads live in portable source files on disk.
public struct Library: Codable, Sendable, Equatable {
    public var worlds: [World] = []
    public var stories: [Story] = []
    public var scenes: [Scene] = []
    public var manuscripts: [Manuscript] = []
    public var lore: [Lore] = []
    public var entities: [Entity] = []
    public var facts: [CanonicalFact] = []
    public var events: [StoryEvent] = []
    public var claims: [NarrativeClaim] = []
    public var agents: [AgentDefinition] = []
    public var observations: [AgentObservation] = []
    public var feedback: [FeedbackEvent] = []
    public var memories: [AgentMemory] = []
    public var reviewRuns: [ReviewRun] = []
    public init() {}
}
public struct ReviewContext: Sendable {
    public var library: Library
    public var scene: Scene
    public var manuscript: Manuscript
    public init(library: Library, scene: Scene, manuscript: Manuscript) { self.library = library; self.scene = scene; self.manuscript = manuscript }
}
public struct ReviewResult: Sendable {
    public var observations: [AgentObservation]
    public var claims: [NarrativeClaim]
    public init(observations: [AgentObservation] = [], claims: [NarrativeClaim] = []) { self.observations = observations; self.claims = claims }
}
public protocol Analyzer: Sendable { func analyze(_ context: ReviewContext) async throws -> ReviewResult }
public protocol ModelProvider: Sendable {
    var availabilityDescription: String { get }
    var isAvailable: Bool { get }
    func review(_ context: ReviewContext) async throws -> ReviewResult
}
