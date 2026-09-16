import Foundation

public enum Greyhaven {
    /// Stable fixture IDs support manual exploration and deterministic regressions.
    /// The intentional problem passage is `scene-5`; Chapter 8 is stored first to expose retrieval-order bugs.
    public static func make() -> Library {
        var library = Library()
        let world = World(id: "greyhaven", name: "Greyhaven")
        let story = Story(id: "story-homecoming", worldID: world.id, title: "The Homecoming")
        let otherStory = Story(id: "story-watch", worldID: world.id, title: "The Quiet Watch", worldOffset: 100)
        library.worlds = [world]
        library.stories = [story, otherStory]
        let future = Scene(id: "scene-8", storyID: story.id, title: "The confession", chapter: "Chapter 8", order: 8, time: 8)
        let beginning = Scene(id: "scene-1", storyID: story.id, title: "The south stair", chapter: "Chapter 1", order: 1, time: 1)
        let gift = Scene(id: "scene-2", storyID: story.id, title: "A key entrusted", chapter: "Chapter 2", order: 2, time: 2)
        let promotion = Scene(id: "scene-4", storyID: story.id, title: "The new insignia", chapter: "Chapter 4", order: 4, time: 4)
        let late = Scene(id: "scene-5", storyID: story.id, title: "The road to Old Town", chapter: "Chapter 5", order: 5, time: 5)
        let flashback = Scene(id: "scene-flashback", storyID: story.id, title: "Before the insignia", chapter: "Chapter 6 · Flashback", order: 6, time: 2)
        let watch = Scene(id: "scene-watch", storyID: otherStory.id, title: "Another telling", chapter: "Chapter 1", order: 1, time: 1)
        library.scenes = [future, beginning, gift, promotion, late, flashback, watch]
        library.entities = [
            Entity(id: "rowan", worldID: world.id, name: "Rowan", aliases: ["Rowan Ash"]),
            Entity(id: "mara", worldID: world.id, name: "Mara"),
            Entity(id: "elise", worldID: world.id, name: "Elise"),
            Entity(id: "jonas", worldID: world.id, name: "Jonas"),
            Entity(id: "maren", worldID: world.id, name: "Maren Vale", aliases: ["Maren"]),
            Entity(id: "party", worldID: world.id, name: "The party", kind: "party", aliases: ["the travelers"]),
            Entity(id: "old-town", worldID: world.id, name: "Old Town", kind: "location"),
            Entity(id: "south-exit", worldID: world.id, name: "the dungeon's southern exit", kind: "location", aliases: ["south stair", "southern exit"]),
            Entity(id: "brass-key", worldID: world.id, name: "the brass key", kind: "object", aliases: ["brass key"])
        ]
        library.lore = [
            Lore(id: "lore-geography", worldID: world.id, title: "Greyhaven · roads and ruins", markdown: "# Roads and ruins\n\nOld Town crowns the northern ridge. The dungeon's southern exit lies south of Old Town. Travelers leaving the southern exit must head north to reach Old Town.\n\nThe southern road leads away from the town, toward the marsh."),
            Lore(id: "lore-people", worldID: world.id, title: "People and possessions", markdown: "# People and possessions\n\nRowan begins as a Private. Maren Vale is the keeper of the town archives; Maren is her familiar name.\n\nMara initially owns the brass key. Jonas initially does not know who killed his brother. These starting facts do not establish later events: the writer approves those within each story.")
        ]
        func loreEvidence(_ id: String, _ quote: String, _ suffix: String) -> EvidenceReference {
            EvidenceReference(id: "evidence-\(suffix)", kind: "lore", sourceID: id, label: library.lore.first(where: { $0.id == id })!.title, quote: quote)
        }
        library.facts = [
            CanonicalFact(id: "fact-geography", worldID: world.id, entityID: "south-exit", property: "southOf", value: "old-town", evidence: loreEvidence("lore-geography", "The dungeon's southern exit lies south of Old Town.", "geography")),
            CanonicalFact(id: "fact-rank", worldID: world.id, entityID: "rowan", property: "rank", value: "Private", evidence: loreEvidence("lore-people", "Rowan begins as a Private.", "rank")),
            CanonicalFact(id: "fact-key", worldID: world.id, entityID: "brass-key", property: "owner", value: "mara", evidence: loreEvidence("lore-people", "Mara initially owns the brass key.", "key")),
            CanonicalFact(id: "fact-knowledge", worldID: world.id, entityID: "jonas", property: "knowledge.brothersKiller", value: "false", evidence: loreEvidence("lore-people", "Jonas initially does not know who killed his brother.", "knowledge"))
        ]
        func manuscript(_ scene: Scene, _ paragraphs: [String]) -> Manuscript {
            let html = paragraphs.map { paragraph in
                "<p>" + paragraph.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") + "</p>"
            }.joined()
            return Manuscript(sceneID: scene.id, html: html, text: paragraphs.joined(separator: "\n"), revision: 1)
        }
        library.manuscripts = [
            manuscript(future, ["Jonas learned who killed his brother. The confession changed everything he thought he knew."]),
            manuscript(beginning, ["Private Rowan counted the travelers at the foot of the stair.", "The party emerged through the dungeon's southern exit. Old Town waited beyond the northern ridge."]),
            manuscript(gift, ["Mara gave the brass key to Elise. Elise tied it beneath her collar, promising to keep it safe."]),
            manuscript(promotion, ["Rowan was promoted to Corporal. The captain pinned the new insignia to Rowan's coat before the assembled watch."]),
            manuscript(late, [
                "They headed south toward Old Town. Private Rowan stepped into the room.",
                "Rowan was promoted to Corporal. Mara unlocked the door with the brass key.",
                "Marenn Vale waited beside the cold hearth. Jonas wondered who killed his brother.",
                "The wind rises. Rowan opens the shutters. Mara steps into the light. Elise watches the road.",
                "Perhaps the room seemed almost welcoming, somewhat warmer than the road, maybe safe enough to rest.",
                "The bell sounded across the square. The bell answered from the tower. The bell faded into the mist."
            ]),
            manuscript(flashback, ["Private Rowan waited beside the south stair. The new insignia was still two days away."]),
            manuscript(watch, ["Private Rowan watched the dawn. Mara held the brass key. In this telling, neither promotion nor gift had happened."])
        ]
        func sceneEvidence(_ scene: Scene, _ quote: String, _ suffix: String) -> EvidenceReference {
            let source = library.manuscripts.first { $0.sceneID == scene.id }!
            let range = (source.text as NSString).range(of: quote)
            return EvidenceReference(id: "evidence-\(suffix)", kind: "manuscript", sourceID: scene.id,
                                     label: "\(scene.chapter) · \(scene.title)", quote: quote,
                                     anchor: AnchorResolver.make(manuscript: source, range: range))
        }
        library.events = [
            StoryEvent(id: "event-knowledge", storyID: story.id, sceneID: future.id, time: future.time, entityID: "jonas", property: "knowledge.brothersKiller", value: "true", previousValue: "false", evidence: sceneEvidence(future, "Jonas learned who killed his brother.", "confession")),
            StoryEvent(id: "event-exit", storyID: story.id, sceneID: beginning.id, time: beginning.time, entityID: "party", property: "location", value: "south-exit", evidence: sceneEvidence(beginning, "The party emerged through the dungeon's southern exit.", "exit")),
            StoryEvent(id: "event-key", storyID: story.id, sceneID: gift.id, time: gift.time, entityID: "brass-key", property: "owner", value: "elise", previousValue: "mara", evidence: sceneEvidence(gift, "Mara gave the brass key to Elise.", "gift")),
            StoryEvent(id: "event-promotion", storyID: story.id, sceneID: promotion.id, time: promotion.time, entityID: "rowan", property: "rank", value: "Corporal", previousValue: "Private", evidence: sceneEvidence(promotion, "Rowan was promoted to Corporal.", "promotion"))
        ]
        library.agents = DeterministicAnalyzer.defaultAgents
        return library
    }
}
