// Throwaway issue #11: compare in-Scene page breaks, structural Enter, and explicit commands.
import { Wordgard } from 'wordgard/editor';
import { Command, enter, redo, splitTextblock, undo } from 'wordgard/command';
import { GardSelection, GardState } from 'wordgard/state';
import { history, undoDepth } from 'wordgard/history';
import { blockDoc, blockquote, bulletList, emphasis, heading, lineBreak, orderedList, paragraph, strong } from 'wordgard/schema';
import { ChangeSet, Elt, Leaf, Node as PlotNode } from 'wordgard/doc';
import { Paragraph } from 'wordgard/types';

type Scene = { kind: 'Scene'; title: string; time: number | null; state: GardState; createdBy?: Insertion };
type Level = { kind: 'Level'; title: string; time: number; intent: string; reference?: string };
type Block = Scene | Level;
type Chapter = { role: 'regular' | 'Prologue' | 'Epilogue'; blocks: Block[] };
type Insertion = { source: Scene; parent: Chapter; scene: Scene; chapter?: Chapter; before: GardState; count: 0 | 2 | 3 };

const PageBreak = Leaf.define('PageBreak', {
  group: PlotNode.Group.Content,
  shape: { structure: () => Elt.mk('div', { class: 'page-break', role: 'separator', 'aria-label': 'Page break' },
    [Elt.mk('span', { 'aria-hidden': 'true' })]) },
  parseRules: [{ selector: 'div.page-break' }],
  selectable: true,
});

// Presentation-only operations; no edit, conversion, or time assignment for existing blocks.
function canAppendChapter(parent: Chapter, after: Scene) {
  return parent.role !== 'Epilogue' && parent.blocks.at(-1) === after;
}
function exchangeChapter(chapters: Chapter[], item: Insertion, chapter: Chapter) {
  item.parent.blocks.splice(item.parent.blocks.indexOf(item.scene), 1);
  item.chapter = chapter;
  chapter.blocks.push(item.scene);
  chapters.splice(chapters.indexOf(item.parent) + 1, 0, chapter);
}
function add(chapters: Chapter[], item: Insertion) {
  if (item.chapter) chapters.splice(chapters.indexOf(item.parent) + 1, 0, item.chapter);
  else item.parent.blocks.splice(item.parent.blocks.indexOf(item.source) + 1, 0, item.scene);
}
function remove(chapters: Chapter[], item: Insertion) {
  if (item.chapter) chapters.splice(chapters.indexOf(item.chapter), 1);
  else item.parent.blocks.splice(item.parent.blocks.indexOf(item.scene), 1);
}

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id)! as T;
const button = (id: string) => $<HTMLButtonElement>(id);
const status = (text: string) => { $('status').textContent = text; };
const focus = () => { editor?.flush(); editor?.focus(); };
const timing = 850;
const modes = ['rhythm', 'explicit', 'hybrid'] as const;
let mode: (typeof modes)[number] = 'hybrid';
let chapters: Chapter[];
let active: Block;
let editor: Wordgard | undefined;
let serial: number;
let redos: Map<Scene, { item: Insertion; at: GardState }>;

type Run = { step: 1; before: GardState; at: GardState; changes: ChangeSet } | { step: 2; item: Insertion; at: GardState };
let pending: (Run & { deadline: number }) | undefined;
let timer: number | undefined;
function clearRun(message?: string) {
  if (!pending) return;
  const step = pending.step;
  pending = undefined;
  window.clearTimeout(timer);
  status(message ?? (step === 2 ? 'Section break created. ⌘Z removes it.' : ''));
}
function arm(run: Run) {
  pending = { ...run, deadline: performance.now() + timing };
  timer = window.setTimeout(() => clearRun(), timing);
}

const config = [
  blockDoc(), paragraph(), heading(), strong(), emphasis(), lineBreak(), blockquote(), bulletList(), orderedList(),
  history(), Wordgard.label('Manuscript'), GardState.schemaElement.of(PageBreak),
  Wordgard.updateListener.of(update => {
    if (update.editor !== editor || active.kind !== 'Scene') return;
    if (pending && (update.state.doc !== pending.at.doc || !update.state.selection.eq(pending.at.selection))) clearRun();
    if (update.docChanged) {
      if (update.transactions.some(tr => tr.docChanged && !tr.isUserEvent('undo') && !tr.isUserEvent('redo'))) redos.delete(active);
    }
    if (update.docChanged || update.selectionSet) {
      updateCorrection();
    }
  }),
];
const newScene = (title: string, time: number | null, doc = '<p></p>'): Scene => ({
  kind: 'Scene', title, time, state: GardState.create({ doc, config }),
});
const parentOf = (block: Block) => chapters.find(chapter => chapter.blocks.includes(block))!;
const blocks = () => chapters.flatMap(chapter => chapter.blocks);
function reset() {
  clearRun();
  closeEditor();
  redos = new Map();
  serial = 0;
  const gate = newScene('The tide gate', 4, '<p>Mara turned the <strong>brass key</strong> and listened for the lock.</p>'
    + '<h2>Lines on the map</h2><blockquote><p>Wait until the bell falls silent.</p></blockquote>'
    + '<ul><li><p>The western lantern</p></li><li><p>The lock house</p></li></ul>'
    + '<p>On the other side of the gate, someone had left a <em>lamp burning</em>. She stepped onto the causeway.</p>');
  chapters = [
    { role: 'regular', blocks: [gate, { kind: 'Level', title: 'Across the lock', time: 2, intent: 'Separate Mara from town before the tide turns.' },
      newScene('The note under the door', 6, '<p>The lock house smelled of rain and machine oil.</p><p>Mara left the note under the white stone.</p>')] },
    { role: 'regular', blocks: [{ kind: 'Level', title: 'Up the signal tower', time: 7, intent: 'Show Mara the distant lantern from above the flats.', reference: 'signal-tower-01' },
      newScene('A voice in the fog', 8, '<p>“Put the lamp out,” someone whispered on the stair.</p>')] },
    { role: 'Epilogue', blocks: [newScene('The far shore', 12, '<p>The lantern was not lit every night. They still looked for it.</p>')] },
  ];
  open(gate, true);
  status(mode === 'hybrid' ? 'Try two quick Enters here, or place the caret at the end of an earlier paragraph.'
    : 'Start at the end of this Scene. Try one, two, or three Enters.');
}
function closeEditor(save?: GardState) {
  if (!editor || active.kind !== 'Scene') return;
  editor.flush();
  active.state = save ?? editor.state;
  const dom = editor.dom;
  editor = undefined;
  dom.remove();
}
function open(block: Block, tail = false, save?: GardState) {
  clearRun();
  closeEditor(save);
  active = block;
  const prose = block.kind === 'Scene';
  $('toolbar').hidden = !prose;
  $('toolbar').style.display = prose ? '' : 'none';
  $('editor').hidden = !prose;
  $('level').hidden = prose;
  button('scene').disabled = button('chapter').disabled = !prose;
  if (prose) {
    const state = block.state;
    editor = Wordgard.create({ parent: $('editor'), state });
    if (tail) editor.dispatch({
      selection: GardSelection.near(state, state.doc.length, -1),
      scrollIntoView: true,
    });
    focus();
  } else {
    renderLevel(block);
    $('level').focus();
  }
  $('page').scrollTop = 0;
  renderOutline();
  updateCorrection();
}

const chapterTitle = (chapter: Chapter) => chapter.role !== 'regular' ? chapter.role
  : `Chapter ${chapters.slice(0, chapters.indexOf(chapter) + 1).filter(c => c.role === 'regular').length}`;
const referenceStatus = (block: Level) => block.reference ? 'Reference supplied—not verified' : 'Unbound';
function renderLevel(level: Level) {
  const title = document.createElement('h2');
  title.textContent = `Level · ${level.title}`;
  const info = document.createElement('p');
  info.textContent = `${referenceStatus(level)} · Nonplayable in this workspace`;
  const details = document.createElement('dl');
  for (const [term, value] of [['Intent note', level.intent], ['Story time (independent of manuscript order)', String(level.time)],
    ['Gameplay reference', level.reference ?? 'None']]) {
    const label = document.createElement('dt'), content = document.createElement('dd');
    label.textContent = term;
    content.textContent = value;
    details.append(label, content);
  }
  $('level').replaceChildren(title, info, details);
}
function renderOutline() {
  const list = $('outline');
  list.replaceChildren();
  for (const chapter of chapters) {
    const heading = document.createElement('h2');
    heading.textContent = chapterTitle(chapter);
    list.append(heading);
    for (const block of chapter.blocks) {
      const row = document.createElement('button'), detail = document.createElement('small');
      row.textContent = `${block.kind} · ${block.title}`;
      row.setAttribute('aria-current', String(block === active));
      row.addEventListener('click', () => navigate(block));
      detail.textContent = block.kind === 'Level' ? `${referenceStatus(block)} · Story time ${block.time}` :
        block.time === null ? 'New draft · story time not assigned' : `Story time ${block.time}`;
      row.append(detail);
      list.append(row);
    }
  }
  const all = blocks(), index = all.indexOf(active), chapter = parentOf(active);
  button('previous').disabled = index === 0;
  button('next').disabled = index === all.length - 1;
  const startsChapter = chapter.blocks[0] === active, previous = all[index - 1];
  const transition = previous && (previous.kind === 'Level' || active.kind === 'Level')
    ? `${previous.kind} → ${active.kind} · content transition` : '';
  const boundary = startsChapter ? [chapterTitle(chapter), transition].filter(Boolean).join(' · ')
    : transition || 'Section break · Scene → Scene';
  $('boundary').textContent = `${boundary} / ${active.title}`;
}
function navigate(block: Block) {
  open(block, true);
  status(block.kind === 'Level' ? 'Level details only. Use Previous or Next to navigate. Enter does not edit a Level.' : '');
}

function atEnd(state: GardState) {
  const { head } = state.sel;
  if (!state.selection.empty || !head.textblockParent) return false;
  let root = head.parent;
  while (root.parent) root = root.parent;
  return head.isAtEnd(root);
}
function eligible(state: GardState) {
  const { head } = state.sel;
  const paragraph = head.textblockParent;
  return state.selection.empty && paragraph?.depth === 1 && paragraph.node.type === Paragraph.type &&
    paragraph.node.contentLength > 0 && head.isAtEnd(paragraph) && (mode === 'hybrid' || atEnd(state));
}
function append(kind: 'scene' | 'chapter', before: GardState, count: 0 | 2) {
  if (active.kind !== 'Scene') return;
  const parent = parentOf(active);
  if (kind === 'chapter' && !canAppendChapter(parent, active)) {
    status(parent.role === 'Epilogue' ? 'The Epilogue must stay last.' : 'A new chapter can start only after the last block of this chapter. Nothing moved.');
    return;
  }
  const scene = newScene(`Untitled scene ${++serial}`, null);
  const item: Insertion = { source: active, parent, before, scene, count,
    chapter: kind === 'chapter' ? { role: 'regular', blocks: [scene] } : undefined };
  scene.createdBy = item;
  redos.delete(active);
  add(chapters, item);
  open(scene, false, before);
  const tripleEnabled = count === 2 && mode === 'rhythm';
  const upgrade = tripleEnabled && canUpgrade(item);
  if (tripleEnabled) arm({ step: 2, item, at: editor!.state });
  status(kind === 'chapter' ? 'New chapter with an opening Scene. ⌘Z removes both.' : upgrade
    ? 'Section break created. Enter again within 850 ms for a new chapter.' : 'Section break created. ⌘Z removes it.');
}
function canUpgrade(item: Insertion) {
  const blocks = item.parent.blocks;
  return item.parent.role !== 'Epilogue' && blocks.at(-1) === item.scene;
}
function explicitAppend(kind: 'scene' | 'chapter') {
  clearRun();
  if (!editor) return;
  editor.flush();
  const state = editor.state;
  if (!atEnd(state) || !state.doc.content.some(node => node.isPlot && node.contentLength)) {
    status('Place the caret at the end of a Scene with prose. Structural commands never split existing text.');
    focus();
    return;
  }
  append(kind, state, 0);
}

function canRemove(item: Insertion, state: GardState) {
  return undoDepth(state) === 0 && state.doc.content.length === 1 && state.doc.content[0].isPlot &&
    state.doc.content[0].contentLength === 0 &&
    (!item.chapter || item.chapter.blocks.length === 1) &&
    !blocks().some(block => block.kind === 'Scene' && block.createdBy?.source === item.scene);
}

function pageBreakBeforeCaret(state: GardState) {
  const { head } = state.sel, paragraph = head.textblockParent;
  if (!state.selection.empty || !paragraph || !head.isAtStart(paragraph)) return null;
  const preceding = state.doc.resolve(paragraph.before).nodeBefore;
  return preceding?.type === PageBreak.type ? { from: paragraph.before - preceding.length, to: paragraph.before } : null;
}
function insertPageBreak(run: Extract<Run, { step: 1 }>) {
  const wg = editor!;
  clearRun();
  const paragraph = run.at.sel.head.textblockParent!;
  const marker = ChangeSet.create(run.at.doc, { from: paragraph.before, insert: [PageBreak] });
  const changes = run.changes.compose(marker);
  if (!Command.dispatch(wg, undo)) return;
  wg.dispatch({ changes, selection: GardSelection.cursor(marker.mapPos(run.at.selection.head, 1)),
    annotations: history.isolate.of(true), scrollIntoView: true });
  focus();
  status('Page break inserted in this Scene. ⌘Z removes it.');
}
function correction() {
  if (!editor || active.kind !== 'Scene') return;
  const item = active.createdBy;
  if (item?.count && canRemove(item, editor.state) && item.source.state.doc.eq(item.before.doc)) return item;
}
function updateCorrection() {
  button('correct').hidden = !editor || (!pageBreakBeforeCaret(editor.state) && !correction());
}
function keepBlankParagraphs() {
  clearRun();
  const wg = editor;
  wg?.flush();
  const pageBreak = wg && pageBreakBeforeCaret(wg.state);
  if (wg && pageBreak) {
    wg.dispatch({ changes: { ...pageBreak, insert: [Paragraph.create([])] }, annotations: history.isolate.of(true) });
    focus();
    status('Replaced the page break with a blank paragraph. ⌘Z restores the page break.');
    return;
  }
  const item = correction();
  if (!item) return;
  const origin = item.source.state.update({ selection: item.before.selection }).state;
  let after = origin, changes: ChangeSet | undefined;
  for (let i = 0; i < item.count; i++) {
    const spec = splitTextblock(after);
    if (!spec) return;
    const tr = after.update(spec);
    changes = changes ? changes.compose(tr.changes) : tr.changes;
    after = tr.state;
  }
  item.source.state = origin.update({ changes, selection: after.selection, annotations: history.isolate.of(true) }).state;
  remove(chapters, item);
  open(item.source);
  status('Kept the Enter presses as ordinary paragraph breaks. ⌘Z undoes those breaks.');
}
function historyAction(forward: boolean) {
  clearRun();
  if (!editor || active.kind !== 'Scene') return false;
  editor.flush();
  if (forward) {
    const next = redos.get(active), state = editor.state;
    if (next && next.at.doc.eq(state.doc) && undoDepth(next.at) === undoDepth(state)) {
      redos.delete(active);
      add(chapters, next.item);
      open(next.item.scene);
      status(next.item.chapter ? 'Chapter restored.' : 'Section break restored.');
      return true;
    }
  }
  if (Command.dispatch(editor, forward ? redo : undo)) {
    focus();
    status(forward ? 'Prose edit redone.' : 'Prose edit undone.');
    return true;
  }
  const item = active.createdBy;
  if (!forward && item && canRemove(item, editor.state)) {
    remove(chapters, item);
    redos.set(item.source, { item, at: item.source.state });
    open(item.source);
    status(item.chapter ? 'New chapter and opening Scene undone.' : 'Section break undone.');
    return true;
  }
  status(item && !forward ? 'Undo dependent structure first; no prose or other blocks were removed.' : `Nothing to ${forward ? 'redo' : 'undo'} here.`);
  return true;
}

function consume(event: KeyboardEvent) { event.preventDefault(); event.stopImmediatePropagation(); }
function onKey(event: KeyboardEvent) {
  if (!editor || event.target !== editor.contentDOM) return;
  if (event.isComposing || event.keyCode === 229 || editor.compositionStarted) { clearRun(); return; }
  if (event.metaKey && !event.altKey && !event.ctrlKey && event.key.toLowerCase() === 'z') {
    consume(event); historyAction(event.shiftKey); return;
  }
  if (event.key !== 'Enter' || event.ctrlKey || event.repeat) { clearRun(); return; }
  if (event.metaKey && !event.altKey) { consume(event); explicitAppend(event.shiftKey ? 'chapter' : 'scene'); return; }
  if (event.altKey && !event.metaKey && !event.shiftKey) {
    clearRun(); consume(event); Command.dispatch(editor, enter); return;
  }
  if (event.altKey || event.metaKey || event.shiftKey || mode === 'explicit') { clearRun(); return; }
  editor.flush();
  const state = editor.state;
  if (pending && (performance.now() > pending.deadline || pending.at.doc !== state.doc || !state.selection.eq(pending.at.selection))) clearRun();
  const run = pending;
  if (run?.step === 1) {
    consume(event);
    if (mode === 'hybrid') insertPageBreak(run);
    else append('scene', run.before, 2);
    return;
  }
  if (run?.step === 2) {
    consume(event); clearRun();
    run.item.count = 3;
    if (canUpgrade(run.item)) {
      exchangeChapter(chapters, run.item, { role: 'regular', blocks: [] });
      renderOutline();
      status('New chapter with the same opening Scene. ⌘Z removes both.');
    } else {
      status('Kept the section break. A new chapter cannot cross later blocks or follow the Epilogue.');
    }
    return;
  }
  if (!eligible(state)) return;
  const spec = splitTextblock(state);
  if (!spec) return;
  consume(event);
  const tr = state.update({ ...spec, annotations: history.isolate.of(true) });
  editor.dispatch(tr);
  arm({ step: 1, before: state, at: editor.state, changes: tr.changes });
  status(`Paragraph created. Enter again within 850 ms for a ${mode === 'hybrid' ? 'page' : 'section'} break, or ⌥↵ to keep a blank.`);
}

document.addEventListener('keydown', onKey, true);
for (const type of ['pointerdown', 'focusout', 'compositionstart', 'paste', 'drop']) {
  document.addEventListener(type, () => clearRun(), true);
}
function switchMode(value: typeof mode) {
  clearRun(); mode = value;
  for (const key of modes) button(key).setAttribute('aria-pressed', String(mode === key));
  $('hint').textContent = mode === 'rhythm'
    ? 'At a Scene end: 1 Enter = paragraph; 2 = new Scene; 3 = new chapter when this Scene ends its chapter. ⌥↵ is literal Enter.'
    : mode === 'hybrid'
      ? 'At a paragraph end: 2 Enters within 850 ms insert a page break in this Scene. ⌥↵ keeps blanks. Chapters are explicit only.'
      : 'Enter never changes structure. Use the New Scene or New Chapter controls at the end of a Scene.';
  if (editor) focus();
}
for (const key of modes) button(key).onclick = () => switchMode(key);
button('reset').onclick = reset;
button('previous').onclick = () => navigate(blocks()[blocks().indexOf(active) - 1]);
button('next').onclick = () => navigate(blocks()[blocks().indexOf(active) + 1]);
button('scene').onclick = () => explicitAppend('scene');
button('chapter').onclick = () => explicitAppend('chapter');
button('correct').onclick = keepBlankParagraphs;
button('undo').onclick = () => historyAction(false);
button('redo').onclick = () => historyAction(true);
const formats = { strong: strong.button.run, emphasis: emphasis.button.run, heading: heading.button2.run,
  quote: blockquote.button.run, list: bulletList.toggleButton.run };
for (const control of document.querySelectorAll<HTMLButtonElement>('[data-format]')) {
  control.onclick = () => { if (editor) { Command.dispatch(editor, formats[control.dataset.format as keyof typeof formats]); focus(); } };
}
for (const id of ['toolbar', 'actions', ...modes]) {
  $(id).addEventListener('mousedown', event => { if (event.target instanceof Element && event.target.closest('button')) event.preventDefault(); });
}
switchMode('hybrid');
reset();
