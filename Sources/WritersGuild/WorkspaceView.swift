import EditorHost
import GuildCore
import SwiftUI

struct WorkspaceView: View {
  @ObservedObject var model: WorkspaceModel
  @State private var creation: String?
  @State private var title = ""
  @State private var chapter = "Chapter 1"
  @State private var storyID = ""
  @State private var time = 1

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 190, ideal: 225, max: 300)
    } detail: {
      VStack(spacing: 0) {
        if model.route == "writing" {
          writing
        } else if model.route == "lore" {
          LoreView(model: model)
        } else if model.route == "guild" {
          GuildHallView(model: model)
        } else {
          WorldStateView(model: model)
        }
        Divider()
        HStack {
          Text(model.status).lineLimit(2)
          Spacer()
          if model.quietTime { Text("Quiet Time").foregroundStyle(.secondary) }
          if let document = model.manuscript, model.route == "writing" {
            Text("\(document.text.split(whereSeparator: \.isWhitespace).count) words")
          }
        }
        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 8)
      }
      .navigationTitle(model.world?.name ?? "Writers Guild")
      .toolbar {
        ToolbarItemGroup {
          Toggle(isOn: $model.quietTime) { Label("Quiet Time", systemImage: "moon") }
            .toggleStyle(.button).help("Hide annotations and defer automatic reviews")
          Button {
            model.review(deliberate: true)
          } label: {
            Label(
              model.reviewing ? "Reading…" : "Let the Guild Read",
              systemImage: "text.magnifyingglass")
          }.disabled(model.scene == nil || model.reviewing).keyboardShortcut(
            "r", modifiers: [.command, .shift]
          ).help("Let the Guild Read")
          Button {
            model.endSession()
          } label: {
            Label("End Session", systemImage: "sunset")
          }
          .help("Save and consolidate the Guild's memories")
        }
      }
    }
    .frame(minWidth: 1000, minHeight: 680)
    .sheet(isPresented: Binding(get: { creation != nil }, set: { if !$0 { creation = nil } })) {
      creationForm
    }
    .sheet(item: $model.evidence) { reference in evidenceSheet(reference) }
    .alert(
      "Writers Guild needs attention",
      isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
    ) {
      Button("OK") { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
  }

  private var sidebar: some View {
    List {
      Section("Worlds") {
        ForEach(model.library.worlds) { world in
          Button {
            model.selectWorld(world.id)
          } label: {
            Label(
              world.name,
              systemImage: world.id == model.worldID ? "globe.americas.fill" : "globe.americas"
            )
            .fontWeight(world.id == model.worldID ? .semibold : .regular)
          }.buttonStyle(.plain)
        }
      }
      ForEach(model.library.stories.filter { $0.worldID == model.worldID }) { story in
        Section(story.title) {
          ForEach(
            model.library.scenes.filter { $0.storyID == story.id }.sorted { $0.order < $1.order }
          ) { scene in
            Button {
              model.switchScene(scene)
            } label: {
              VStack(alignment: .leading, spacing: 3) {
                Text(scene.title).fontWeight(
                  model.sceneID == scene.id && model.route == "writing" ? .semibold : .regular)
                Text(scene.chapter).font(.caption2).foregroundStyle(.secondary)
              }.padding(.vertical, 3)
            }.buttonStyle(.plain).disabled(model.switching)
          }
          Button {
            storyID = story.id
            begin("Scene")
          } label: {
            Label("New scene", systemImage: "plus")
          }
          .buttonStyle(.plain).foregroundStyle(.secondary)
        }
      }
      Section("World & Guild") {
        navigation("Lore", route: "lore", icon: "books.vertical")
        navigation("World State", route: "state", icon: "point.3.connected.trianglepath.dotted")
        navigation("Guild Hall", route: "guild", icon: "person.3")
      }
      Section {
        Menu {
          Button("New World…") { begin("World") }
          Button("New Story…") { begin("Story") }.disabled(model.worldID == nil)
          Button("New Lore…") { begin("Lore") }.disabled(model.worldID == nil)
          Divider()
          Button("Open Library Folder…") { model.chooseLibrary() }
        } label: {
          Label("Add / Open", systemImage: "plus.circle")
        }
        .menuStyle(.borderlessButton)
      }
    }.listStyle(.sidebar)
  }

  private func navigation(_ title: String, route: String, icon: String) -> some View {
    Button {
      model.route = route
    } label: {
      Label(title, systemImage: icon).fontWeight(model.route == route ? .semibold : .regular)
    }.buttonStyle(.plain)
  }

  private var writing: some View {
    HSplitView {
      VStack(spacing: 0) {
        if let scene = model.scene {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text(scene.chapter.uppercased()).font(.caption).tracking(1.5).foregroundStyle(
                .secondary)
              Text(scene.title).font(.title2.weight(.medium))
            }
            Spacer()
            Text("Story time \(scene.time)").font(.caption).foregroundStyle(.secondary)
          }.padding(24)
          Divider()
          ManuscriptEditor(controller: model.editor)
            .id(ObjectIdentifier(model.editor))
        } else {
          ContentUnavailableView(
            "A world holds many stories", systemImage: "book.closed",
            description: Text("Create a story to begin writing."))
        }
      }.frame(minWidth: 450)
      if !model.quietTime {
        observationInspector.frame(minWidth: 250, idealWidth: 295, maxWidth: 370)
      }
    }
  }

  private var observationInspector: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          HStack {
            Text("THE GUILD").font(.caption.weight(.semibold)).tracking(2)
            Spacer()
            Text("\(model.observations.count)").foregroundStyle(.secondary)
          }
          if model.observations.isEmpty {
            Text("Room to write.").font(.title3)
            Text("The Guild reads after a pause. Ask for a deliberate review when you are ready.")
              .foregroundStyle(.secondary)
          }
          ForEach(model.observations) { observation in
            VStack(alignment: .leading, spacing: 9) {
              HStack {
                Text(model.library.agents.first { $0.id == observation.agentID }?.name ?? "Guild")
                  .font(.headline)
                Spacer()
                Text(observation.category).font(.caption).foregroundStyle(.secondary)
              }
              Button {
                model.selectObservation(observation.id)
              } label: {
                Text(observation.message).multilineTextAlignment(.leading).foregroundStyle(.primary)
              }.buttonStyle(.plain)
              if let question = observation.question {
                VStack(alignment: .leading, spacing: 3) {
                  Text("WRITER DECISION").font(.caption2.weight(.semibold)).tracking(1)
                    .foregroundStyle(.secondary)
                  Text(question).font(.callout).foregroundStyle(.secondary)
                }
              }
              ForEach(observation.evidence) { reference in
                Button {
                  model.showEvidence(reference)
                } label: {
                  Label(reference.label, systemImage: "arrow.up.right.square").font(.caption)
                }
                .buttonStyle(.link)
              }
              HStack {
                Button("Useful") { model.feedback(observation, action: .accepted) }
                Button("Dismiss") { model.feedback(observation, action: .dismissed) }
                Button("Intentional") { model.feedback(observation, action: .markedIntentional) }
              }.font(.caption).buttonStyle(.borderless)
            }
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
              Rectangle().fill(
                model.selectedObservationID == observation.id
                  ? Color.accentColor : Color.secondary.opacity(0.25)
              ).frame(width: 2)
            }
            .id(observation.id)
          }
          Divider()
          Text(model.provider.availabilityDescription).font(.caption).foregroundStyle(.secondary)
        }.padding(20)
      }.onChange(of: model.selectedObservationID) { _, id in
        if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
      }
    }
  }

  private func begin(_ kind: String) {
    title = ""
    creation = kind
  }
  private var creationForm: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("New \(creation ?? "")").font(.title2)
      TextField("Name", text: $title).textFieldStyle(.roundedBorder)
      if creation == "Scene" {
        TextField("Chapter", text: $chapter)
        Stepper("Story time: \(time)", value: $time)
        Text("Chronology is independent of where the scene appears in the manuscript.").font(
          .caption
        ).foregroundStyle(.secondary)
      }
      HStack {
        Button("Cancel") { creation = nil }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Create") {
          switch creation {
          case "World": model.createWorld(name: title)
          case "Story": model.createStory(title: title)
          case "Lore": model.addLore(title: title)
          case "Scene":
            model.createScene(storyID: storyID, title: title, chapter: chapter, time: time)
          default: break
          }
          creation = nil
        }.keyboardShortcut(.defaultAction).disabled(
          title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(28).frame(width: 400)
  }

  private func evidenceSheet(_ reference: EvidenceReference) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Evidence").font(.caption).foregroundStyle(.secondary)
      Text(reference.label).font(.title2)
      Text(reference.quote).font(.system(.body, design: .serif)).textSelection(.enabled)
      if let anchor = reference.anchor,
        let source = model.library.manuscripts.first(where: { $0.sceneID == anchor.sceneID }),
        AnchorResolver.relocate(anchor, in: source) == nil
      {
        Text(
          "The cited passage has changed. This is the evidence captured when the fact was established."
        ).foregroundStyle(.orange)
      }
      Text("Source: \(reference.kind) · \(reference.sourceID)").font(.caption).foregroundStyle(
        .secondary
      ).textSelection(.enabled)
      HStack {
        Button("Open source") {
          model.navigateEvidence(reference)
          model.evidence = nil
        }
        Spacer()
        Button("Done") { model.evidence = nil }.keyboardShortcut(.defaultAction)
      }
    }.padding(30).frame(width: 540)
  }
}

struct LoreView: View {
  @ObservedObject var model: WorkspaceModel
  var body: some View {
    HSplitView {
      List(selection: $model.selectedLoreID) {
        ForEach(model.library.lore.filter { $0.worldID == model.worldID }) { lore in
          Text(lore.title).tag(lore.id)
        }
      }.frame(minWidth: 150, idealWidth: 200, maxWidth: 260)
      if let index = model.library.lore.firstIndex(where: {
        $0.id == model.selectedLoreID && $0.worldID == model.worldID
      }) {
        VStack(alignment: .leading, spacing: 12) {
          Text(model.library.lore[index].title).font(.title)
          Text("World lore · Markdown · only you can change this source").font(.caption)
            .foregroundStyle(.secondary)
          TextEditor(
            text: Binding(
              get: { model.library.lore[index].markdown },
              set: {
                model.library.lore[index].markdown = $0
                model.save()
              })
          )
          .font(.system(.body, design: .monospaced))
        }.padding(26)
      } else {
        ContentUnavailableView(
          "The world's reference shelf", systemImage: "books.vertical",
          description: Text("Select a lore document, or create one using Add / Open."))
      }
    }
    .onAppear {
      if !model.library.lore.contains(where: {
        $0.id == model.selectedLoreID && $0.worldID == model.worldID
      }) {
        model.selectedLoreID = model.library.lore.first { $0.worldID == model.worldID }?.id
      }
    }
    .onChange(of: model.worldID) { _, _ in
      model.selectedLoreID = model.library.lore.first { $0.worldID == model.worldID }?.id
    }
  }
}

struct GuildHallView: View {
  @ObservedObject var model: WorkspaceModel
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        Text("Guild Hall").font(.largeTitle.weight(.medium))
        Text("Attentive readers, not authors. Their memories are beliefs, never canon.")
          .foregroundStyle(.secondary)
        ForEach(model.library.agents.indices, id: \.self) { index in
          let agent = model.library.agents[index]
          let adjusted = AgentMemoryEngine.adjustedAgents(
            in: model.library, worldID: model.worldID ?? ""
          ).first { $0.id == agent.id }
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text(agent.name).font(.title2)
              Text(agent.role).foregroundStyle(.secondary)
              Spacer()
              Toggle(
                "Enabled",
                isOn: Binding(
                  get: { model.library.agents[index].enabled },
                  set: {
                    model.library.agents[index].enabled = $0
                    model.save()
                    model.review(deliberate: false)
                  }))
            }
            Text(agent.traits.joined(separator: " · ")).font(.callout).italic()
            Text("Lenses: \(agent.categories.joined(separator: ", "))").font(.caption)
            HStack {
              Text(
                "Confidence floor \(agent.confidenceThreshold, format: .percent.precision(.fractionLength(0)))"
              )
              Slider(
                value: Binding(
                  get: { model.library.agents[index].confidenceThreshold },
                  set: {
                    model.library.agents[index].confidenceThreshold = $0
                    model.save()
                  }), in: 0.4...0.99
              ).frame(width: 120)
              Spacer()
              Text(
                "Pattern threshold \(agent.patternThreshold) → \(adjusted?.patternThreshold ?? agent.patternThreshold)"
              )
            }.font(.caption)
            let memories = model.library.memories.filter {
              $0.agentID == agent.id && $0.worldID == model.worldID
            }.sorted { $0.createdAt > $1.createdAt }
            if memories.isEmpty {
              Text("No experiences yet. Your feedback gives this reader something to remember.")
                .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(memories.prefix(6))) { memory in
              VStack(alignment: .leading, spacing: 4) {
                Text(memory.belief)
                Text(
                  "\(memory.layer) · strength \(memory.strength, specifier: "%.2f") · recalled \(memory.recallCount) · \(memory.sourceFeedbackIDs.count) feedback sources"
                )
                .font(.caption).foregroundStyle(.secondary)
              }
            }
            let recent = model.library.observations.filter { observation in
              observation.agentID == agent.id
                && model.library.scenes.contains { scene in
                  scene.id == observation.anchor.sceneID
                    && model.library.stories.contains {
                      $0.id == scene.storyID && $0.worldID == model.worldID
                    }
                }
            }.suffix(3)
            ForEach(Array(recent)) { observation in
              Text("\(observation.status.rawValue): \(observation.message)").font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          Divider()
        }
      }.padding(34).frame(maxWidth: 950, alignment: .leading)
    }
  }
}
