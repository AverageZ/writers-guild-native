import Foundation
import GuildCore

@MainActor
extension WorkspaceModel {
    @discardableResult
    func createEntity(name: String, kind: String, aliases: String) -> ID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let worldID, !name.isEmpty else { return nil }
        let entity = Entity(worldID: worldID, name: name, kind: kind,
                            aliases: aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        library.entities.append(entity)
        save()
        return entity.id
    }

    func setSceneTime(_ time: Int, sceneID: ID) {
        guard let index = library.scenes.firstIndex(where: { $0.id == sceneID }) else { return }
        library.scenes[index].time = time
        for eventIndex in library.events.indices where library.events[eventIndex].sceneID == sceneID {
            library.events[eventIndex].time = time
        }
        save(); review(deliberate: false)
    }

    func establishCanonicalFact(entityID: ID, property: String, value: String, quote: String, loreID: ID) {
        guard let worldID, !property.isEmpty, !value.isEmpty, !quote.isEmpty,
              library.entities.contains(where: { $0.id == entityID && $0.worldID == worldID }),
              let lore = library.lore.first(where: { $0.id == loreID && $0.worldID == worldID }), lore.markdown.contains(quote) else {
            error = "Canon evidence must quote the selected world's lore exactly and identify a world entity."; return
        }
        let source = EvidenceReference(kind: "lore", sourceID: lore.id, label: lore.title, quote: quote)
        library.facts.removeAll { $0.worldID == worldID && $0.entityID == entityID && $0.property == property && $0.validFrom == nil }
        library.facts.append(CanonicalFact(worldID: worldID, entityID: entityID, property: property, value: value, evidence: source))
        save(); review(deliberate: false)
    }

    func establishEvent(entityID: ID, property: String, value: String, quote: String, time: Int) {
        guard let event = makeEvent(entityID: entityID, property: property, value: value, quote: quote, time: time) else { return }
        library.events.append(event)
        save(); review(deliberate: false)
    }

    func acceptClaim(_ claim: NarrativeClaim) {
        guard let scene, let index = library.claims.firstIndex(where: { $0.id == claim.id }),
              library.claims[index].status != .accepted,
              claim.sceneID == scene.id, claim.anchor.revision == manuscript?.revision else {
            error = "This claim is stale or already established. Review the current scene first."; return
        }
        guard let event = makeEvent(entityID: claim.entityID, property: claim.property, value: claim.value,
                                    quote: claim.anchor.quote, time: scene.time, anchor: claim.anchor) else { return }
        library.events.append(event)
        library.claims[index].status = .accepted
        save(); review(deliberate: false)
    }

    func rejectClaim(_ claim: NarrativeClaim) {
        guard let index = library.claims.firstIndex(where: { $0.id == claim.id }) else { return }
        library.claims[index].status = .rejected
        save()
    }

    private func makeEvent(entityID: ID, property: String, value: String, quote: String, time: Int, anchor supplied: TextAnchor? = nil) -> StoryEvent? {
        guard let scene, let manuscript, !property.isEmpty, !value.isEmpty, !quote.isEmpty,
              library.entities.contains(where: { $0.id == entityID && $0.worldID == worldID }) else {
            error = "A story event needs an entity, property, value and current-scene evidence."; return nil
        }
        let anchor: TextAnchor
        if let supplied, let relocated = AnchorResolver.relocate(supplied, in: manuscript) {
            anchor = relocated
        } else if supplied == nil, let range = manuscript.text.range(of: quote),
                  manuscript.text.range(of: quote, range: range.upperBound..<manuscript.text.endIndex) == nil {
            anchor = AnchorResolver.make(manuscript: manuscript, range: NSRange(range, in: manuscript.text))
        } else {
            error = "Evidence must uniquely quote this scene. Include more context if the same passage appears twice."; return nil
        }
        let evidence = EvidenceReference(kind: "scene", sourceID: scene.id, label: "\(scene.chapter) · \(scene.title)", quote: quote, anchor: anchor)
        let sequence = (library.events.filter { $0.storyID == scene.storyID && $0.time == time }.map(\.sequence).max() ?? -1) + 1
        return StoryEvent(storyID: scene.storyID, sceneID: scene.id, time: time, sequence: sequence,
                          entityID: entityID, property: property, value: value, evidence: evidence)
    }
}
