import SwiftUI
import GuildCore

struct WorldStateView: View {
    @ObservedObject var model: WorkspaceModel
    @State private var entityName = ""
    @State private var entityKind = "character"
    @State private var aliases = ""
    @State private var entityID = ""
    @State private var property = "rank"
    @State private var value = ""
    @State private var quote = ""
    @State private var loreID = ""
    @State private var isCanon = false

    private var entities: [Entity] { model.library.entities.filter { $0.worldID == model.worldID } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("World State").font(.largeTitle.weight(.medium))
                Text("Canon establishes the world. Events establish this story. Claims wait for your decision.").foregroundStyle(.secondary)
                chronology
                Divider()
                entitiesSection
                Divider()
                establishSection
                Divider()
                claimsSection
                Divider()
                stateSection
            }.padding(34).frame(maxWidth: 1000, alignment: .leading)
        }
        .onAppear { entityID = entities.first?.id ?? ""; loreID = model.library.lore.first { $0.worldID == model.worldID }?.id ?? "" }
    }

    @ViewBuilder private var chronology: some View {
        if let index = model.library.scenes.firstIndex(where: { $0.id == model.sceneID }) {
            Text("\(model.library.scenes[index].chapter) · \(model.library.scenes[index].title)").font(.headline)
            HStack {
                TextField("Title", text: Binding(get: { model.library.scenes[index].title }, set: { model.library.scenes[index].title = $0; model.save() }))
                TextField("Chapter", text: Binding(get: { model.library.scenes[index].chapter }, set: { model.library.scenes[index].chapter = $0; model.save() }))
            }
            HStack {
                Stepper("Presentation order \(model.library.scenes[index].order)", value: Binding(get: { model.library.scenes[index].order }, set: { model.library.scenes[index].order = $0; model.save() }))
                Spacer()
                Stepper("Story time \(model.library.scenes[index].time)", value: Binding(get: { model.library.scenes[index].time }, set: { newTime in
                    model.setSceneTime(newTime, sceneID: model.library.scenes[index].id)
                }))
            }
            if let storyIndex = model.library.stories.firstIndex(where: { $0.id == model.scene?.storyID }) {
                Stepper("Story's world-time offset \(model.library.stories[storyIndex].worldOffset)", value: Binding(get: { model.library.stories[storyIndex].worldOffset }, set: { model.library.stories[storyIndex].worldOffset = $0; model.save(); model.review(deliberate: false) }))
            }
            Text("Reordering presentation does not change chronology. Changing scene time moves its established events with it.").font(.caption).foregroundStyle(.secondary)
        } else { Text("Open a scene to inspect its point-in-time state.") }
    }

    private var entitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Entities & aliases").font(.title2)
            ForEach(entities) { entity in
                HStack(alignment: .top) {
                    Text(entity.name).frame(width: 160, alignment: .leading)
                    Text(entity.kind).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                    Text(entity.aliases.joined(separator: ", ")).foregroundStyle(.secondary)
                    Spacer()
                    Text(entity.id).font(.caption2.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
                }
            }
            HStack {
                TextField("Entity name", text: $entityName)
                Picker("Kind", selection: $entityKind) { ForEach(["character", "group", "location", "object", "faction"], id: \.self) { Text($0).tag($0) } }.frame(width: 170)
            }
            HStack {
                TextField("Aliases, comma separated", text: $aliases)
                Button("Add entity") {
                    if let id = model.createEntity(name: entityName, kind: entityKind, aliases: aliases) {
                        entityID = id; entityName = ""; aliases = ""
                    }
                }.disabled(entityName.trimmingCharacters(in: .whitespaces).isEmpty || model.worldID == nil)
            }
        }.textFieldStyle(.roundedBorder)
    }

    private var establishSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Establish a fact").font(.title2)
            Picker("Authority", selection: $isCanon) {
                Text("Story event — from this scene").tag(false)
                Text("Canon — from world lore").tag(true)
            }.pickerStyle(.segmented)
            Picker("Entity", selection: $entityID) { Text("Choose entity").tag(""); ForEach(entities) { Text($0.name).tag($0.id) } }
            HStack { TextField("Property, e.g. rank / owner / location", text: $property); TextField("Value (entity ID for relationships)", text: $value) }
            if isCanon {
                Picker("Lore source", selection: $loreID) { Text("Choose lore").tag(""); ForEach(model.library.lore.filter { $0.worldID == model.worldID }) { Text($0.title).tag($0.id) } }
            }
            TextField(isCanon ? "Exact quote from lore" : "Exact quote from current scene", text: $quote)
            Text("Open property names support rank, location, owner and knowledge.<secret>. Relationship values refer to entity IDs shown above. A fact is established only when you press the button.")
                .font(.caption).foregroundStyle(.secondary)
            Button(isCanon ? "Establish canonical fact" : "Establish story event") {
                if isCanon {
                    model.establishCanonicalFact(entityID: entityID, property: property, value: value, quote: quote, loreID: loreID)
                } else {
                    model.establishEvent(entityID: entityID, property: property, value: value, quote: quote, time: model.scene?.time ?? 0)
                }
            }.disabled(entityID.isEmpty || property.isEmpty || value.isEmpty || quote.isEmpty || (!isCanon && model.scene == nil))
        }.textFieldStyle(.roundedBorder)
    }

    private var claimsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unestablished claims").font(.title2)
            if model.pendingClaims.isEmpty { Text("A review may extract claims. Prose never silently changes accepted state.").foregroundStyle(.secondary) }
            ForEach(model.pendingClaims) { claim in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(entities.first { $0.id == claim.entityID }?.name ?? claim.entityID) · \(claim.property) → \(claim.value)").font(.headline)
                    Text(claim.anchor.quote).italic()
                    HStack {
                        Text(claim.status.rawValue).foregroundStyle(.secondary)
                        Spacer()
                        Button("Reject claim") { model.rejectClaim(claim) }
                        Button("Establish as event") { model.acceptClaim(claim) }
                    }.font(.caption)
                }.padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder private var stateSection: some View {
        if let scene = model.scene {
            let state = WorldState(library: model.library, scene: scene)
            Text("As of story time \(scene.time)").font(.title2)
            ForEach(entities) { entity in
                let properties = Set(model.library.facts.filter { $0.entityID == entity.id }.map(\.property) + model.library.events.filter { $0.entityID == entity.id && $0.storyID == scene.storyID }.map(\.property)).sorted()
                ForEach(properties, id: \.self) { property in
                    if let current = state.value(entityID: entity.id, property: property) {
                        HStack(alignment: .top) {
                            Text("\(entity.name).\(property)").frame(width: 240, alignment: .leading)
                            Text(entities.first { $0.id == current.value }?.name ?? current.value).fontWeight(.medium)
                            Spacer()
                            ForEach(current.evidence) { reference in Button(reference.label) { model.showEvidence(reference) }.buttonStyle(.link) }
                        }.font(.callout)
                    }
                }
            }
            Text("Established story events").font(.headline).padding(.top, 12)
            ForEach(model.library.events.filter { $0.storyID == scene.storyID }.sorted { ($0.time, $0.sequence) < ($1.time, $1.sequence) }) { event in
                HStack {
                    Text("t\(event.time).\(event.sequence)").font(.caption.monospaced())
                    Text("\(entities.first { $0.id == event.entityID }?.name ?? event.entityID) · \(event.property) → \(entities.first { $0.id == event.value }?.name ?? event.value)")
                    Spacer()
                    Button("Evidence") { model.showEvidence(event.evidence) }.buttonStyle(.link)
                }.foregroundStyle(event.time > scene.time ? .secondary : .primary)
            }
        }
    }
}
