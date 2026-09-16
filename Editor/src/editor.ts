import { Wordgard, Decoration, RangeSet } from 'wordgard/editor';
import { GardState, GardSelection, Transaction } from 'wordgard/state';
import { serialize, type Plot } from 'wordgard/doc';
import { Command, insertText, undo, redo } from 'wordgard/command';
import { history } from 'wordgard/history';
import { blockDoc, paragraph, heading, strong, emphasis, lineBreak, blockquote, bulletList, orderedList } from 'wordgard/schema';
import type { Manuscript, TextAnchor, Formatting, EditorEvent, Reply } from './contracts';

const emit = (event: EditorEvent) => {
  window.webkit?.messageHandlers?.guild?.postMessage(event);
  window.dispatchEvent(new CustomEvent('guild-editor-event', { detail: event }));
};
const record = (x: unknown): x is Record<string, unknown> => typeof x === 'object' && x !== null && !Array.isArray(x);
const integer = (x: unknown): x is number => typeof x === 'number' && Number.isSafeInteger(x) && x >= 0;
function requireString(x: unknown): asserts x is string { if (typeof x !== 'string') throw new Error('Expected a string'); }
function requireAnchor(x: unknown): asserts x is TextAnchor {
  if (!record(x) || typeof x.sceneID !== 'string' || !integer(x.revision) || !integer(x.start) || !integer(x.length) || typeof x.quote !== 'string' || typeof x.prefix !== 'string' || typeof x.suffix !== 'string') throw new Error('Invalid text anchor');
}
function requireManuscript(x: unknown): asserts x is Manuscript {
  if (!record(x) || typeof x.sceneID !== 'string' || !x.sceneID || typeof x.html !== 'string' || typeof x.text !== 'string' || !integer(x.revision)) throw new Error('Invalid manuscript');
}

// Only portable prose semantics enter the document. A template is inert: import validation
// never attaches source elements to the page, even briefly.
function portableHTML(html: string): string {
  const template = document.createElement('template');
  template.innerHTML = html;
  const allowed: Record<string, true> = { P: true, H1: true, H2: true, H3: true, H4: true, H5: true, H6: true, STRONG: true, B: true, EM: true, I: true, UL: true, OL: true, LI: true, BLOCKQUOTE: true, BR: true };
  for (const element of template.content.querySelectorAll('*')) {
    if (!Object.hasOwn(allowed, element.tagName)) throw new Error(`Unsupported manuscript element: ${element.tagName.toLowerCase()}`);
    for (const attribute of [...element.attributes]) {
      if (element.tagName === 'OL' && attribute.name === 'start' && /^\d+$/.test(attribute.value)) continue;
      throw new Error(`Unsupported manuscript attribute: ${attribute.name}`);
    }
    // Wordgard's prose schema parses semantic marks, not the presentational aliases.
    if (element.tagName === 'B' || element.tagName === 'I') {
      const semantic = document.createElement(element.tagName === 'B' ? 'strong' : 'em');
      semantic.append(...element.childNodes);
      element.replaceWith(semantic);
    }
  }
  return template.innerHTML || '<p></p>';
}

interface Segment { plain: number; token: number; length: number }
interface TextProjection { text: string; toToken(offset: number, end?: boolean): number; toPlain(token: number): number }
// Wordgard positions count structural tokens. Build an explicit UTF-16 projection;
// adjacent textblocks (including empty ones and nested list items) have one newline.
function projection(doc: Plot.Doc): TextProjection {
  let text = '';
  const segments: Segment[] = [];
  let blocks = 0;
  const walk = (plot: Plot, start: number) => {
    if (plot.isTextblock) {
      if (blocks++) text += '\n';
      segments.push({ plain: text.length, token: start, length: 0 });
    }
    let pos = start;
    for (const node of plot.content) {
      if (node.isPlot) walk(node, pos + 1);
      else {
        const value = node.isText ? String(node.param) : '\n';
        segments.push({ plain: text.length, token: pos, length: value.length });
        text += value;
      }
      pos += node.length;
    }
  };
  walk(doc, 0);
  const toToken = (offset: number, end = false) => {
    if (!integer(offset) || offset > text.length) throw new Error('Text offset outside manuscript');
    let segment: Segment | undefined;
    for (const candidate of segments) {
      if (offset >= candidate.plain && offset <= candidate.plain + candidate.length) {
        segment = candidate;
        if (end) break;
      }
    }
    if (!segment) throw new Error('Text offset has no editable position');
    return segment.token + offset - segment.plain;
  };
  const toPlain = (token: number) => {
    let result = 0;
    for (const s of segments) {
      if (token < s.token) break;
      result = s.plain + Math.min(s.length, token - s.token);
    }
    return result;
  };
  return { text, toToken, toPlain };
}
interface Tracked { id: string; quote: string; from: number; to: number }
interface Marks { items: Tracked[]; ranges: RangeSet<Decoration.Range> }
function marks(items: Tracked[]): Marks {
  // Wordgard RangeSet requires sorted, non-overlapping ranges. Sweep annotation
  // boundaries into disjoint visual spans while retaining every logical anchor.
  const edges = items.flatMap(item => [{ at: item.from, id: item.id, enter: true }, { at: item.to, id: item.id, enter: false }])
    .sort((a, b) => a.at - b.at);
  const active = new Set<string>();
  const ranges = RangeSet.create<Decoration.Range>(add => {
    let previous = 0;
    for (const edge of edges) {
      if (edge.at > previous && active.size) {
        const ids = [...active].sort();
        add(previous, edge.at, Decoration.Range.wrapper('span', {
          attributes: { class: 'guild-annotation', 'data-annotation-id': ids[0], 'data-annotation-ids': JSON.stringify(ids),
            title: ids.length > 1 ? `${ids.length} Guild observations; select each in the inspector` : 'Open Guild observation' },
          scope: 'inlineatom', inclusive: false,
        }));
      }
      if (edge.enter) active.add(edge.id); else active.delete(edge.id);
      previous = edge.at;
    }
  });
  return { items, ranges };
}
const replaceMarks = Transaction.Effect.define<Tracked[]>();
const annotationField = GardState.Field.define<Marks>({
  create: () => marks([]),
  update(value, tr) {
    for (const effect of tr.effects) if (effect.is(replaceMarks)) return marks(effect.value);
    if (!tr.docChanged || value.items.length === 0) return value;
    const mappedRanges = value.ranges.map(tr.changes);
    const projected = projection(tr.newDoc);
    const mapped = value.items.flatMap(item => {
      const from = tr.changes.mapPos(item.from, 1, 'after');
      const to = tr.changes.mapPos(item.to, -1, 'before');
      if (from === null || to === null || from >= to || projected.text.slice(projected.toPlain(from), projected.toPlain(to)) !== item.quote) return [];
      return [{ ...item, from, to }];
    });
    // RangeSet maps the visual source; changed/deleted quotes lose their decorations.
    return mapped.length === value.items.length ? { items: mapped, ranges: mappedRanges } : marks(mapped);
  },
  provide: field => Decoration.Range.source.of(state => state.field(field).ranges),
});

let editor: Wordgard | undefined;
let manuscript: Manuscript | undefined;
let cachedDoc: Plot.Doc | undefined;
let cachedProjection: TextProjection | undefined;
function view() { if (!editor || !manuscript) throw new Error('No manuscript loaded'); return editor; }
function projected() {
  const doc = view().state.doc;
  if (doc !== cachedDoc) { cachedProjection = projection(doc); cachedDoc = doc; }
  return cachedProjection!;
}
function snapshot(): Manuscript {
  const wg = view();
  wg.flush();
  return { sceneID: manuscript!.sceneID, revision: manuscript!.revision, html: serialize(wg.state.doc).toHTML(), text: projected().text };
}
function selectionSnapshot() {
  const p = projected(), s = view().state.selection;
  const start = p.toPlain(s.from), end = p.toPlain(s.to);
  return { start, length: end - start, text: p.text.slice(start, end) };
}
function load(value: unknown) {
  requireManuscript(value);
  if (manuscript?.sceneID === value.sceneID && value.revision <= manuscript.revision) return snapshot();
  const html = portableHTML(value.html);
  if (editor) { editor.flush(); editor.dom.remove(); }
  manuscript = { ...value };
  cachedDoc = undefined;
  editor = Wordgard.create({ parent: document.querySelector('#editor')!, doc: html, config: [
    blockDoc(), paragraph(), heading(), strong(), emphasis(), lineBreak(), blockquote(), bulletList(), orderedList(),
    history(), annotationField, Wordgard.label('Manuscript'),
    Wordgard.updateListener.of(update => {
      if (update.docChanged && manuscript) {
        // One increment per document transaction, independent of display batching.
        manuscript.revision += update.transactions.filter(tr => tr.docChanged).length;
        emit({ version: 1, type: 'change', payload: snapshot() });
      }
      if (update.selectionSet) emit({ version: 1, type: 'selectionChange', payload: selectionSnapshot() });
    }),
  ] });
  editor.contentDOM.addEventListener('click', event => {
    const target = event.target instanceof Element ? event.target.closest('[data-annotation-id]') : null;
    const id = target?.getAttribute('data-annotation-id');
    if (id) emit({ version: 1, type: 'annotationClick', payload: id });
  });
  const loaded = snapshot();
  if (loaded.html !== value.html || loaded.text !== value.text) loaded.revision = ++manuscript.revision;
  return loaded;
}
function locate(anchor: TextAnchor): { start: number; length: number } | null {
  if (anchor.sceneID !== manuscript!.sceneID || anchor.revision > manuscript!.revision || !anchor.quote || anchor.quote.length !== anchor.length) return null;
  const text = projected().text;
  if (anchor.revision === manuscript!.revision) return text.slice(anchor.start, anchor.start + anchor.length) === anchor.quote ? anchor : null;
  const candidates: number[] = [];
  for (let at = text.indexOf(anchor.quote); at >= 0; at = text.indexOf(anchor.quote, at + 1)) {
    if (text.slice(Math.max(0, at - anchor.prefix.length), at) === anchor.prefix && text.slice(at + anchor.length, at + anchor.length + anchor.suffix.length) === anchor.suffix) candidates.push(at);
  }
  return candidates.length === 1 ? { start: candidates[0], length: anchor.length } : null;
}
const formats = {
  strong: strong.button.run, emphasis: emphasis.button.run, paragraph: paragraph.button.run,
  heading1: heading.button1.run, heading2: heading.button2.run, blockquote: blockquote.button.run,
  bulletList: bulletList.toggleButton.run, orderedList: orderedList.toggleButton.run, undo, redo,
};
function execute(method: string, payload: unknown): unknown {
  if ((method === 'export' || method === 'getText' || method === 'getSelection') && payload !== null) throw new Error('This command requires a null payload');
  if (method === 'load') return load(payload);
  const wg = view();
  wg.flush();
  switch (method) {
    case 'export': return snapshot();
    case 'getText': return projected().text;
    case 'getSelection': return selectionSnapshot();
    case 'getTextForAnchor': {
      requireAnchor(payload); const range = locate(payload);
      if (!range) throw new Error('Anchor is missing, changed, or ambiguous');
      return projected().text.slice(range.start, range.start + range.length);
    }
    case 'setSelection': {
      if (!record(payload) || !integer(payload.start) || !integer(payload.length)) throw new Error('Invalid selection');
      const p = projected();
      wg.dispatch({ selection: GardSelection.range(p.toToken(payload.start), p.toToken(payload.start + payload.length, payload.length > 0)) });
      wg.focus(); break;
    }
    case 'insertText': {
      requireString(payload);
      const { from, to } = wg.state.selection.replacementRange;
      if (!Command.dispatch(wg, insertText, { from, to, insert: payload, userEvent: 'input.type' })) throw new Error('Text insertion is unavailable at selection');
      break;
    }
    case 'applyFormatting': {
      if (typeof payload !== 'string' || !Object.hasOwn(formats, payload)) throw new Error('Unsupported formatting command');
      if (!Command.dispatch(wg, formats[payload as Formatting])) throw new Error('Formatting command is unavailable at selection');
      wg.focus(); break;
    }
    case 'annotate': {
      if (!Array.isArray(payload)) throw new Error('Invalid annotations');
      const items: Tracked[] = [], seen = new Set<string>(), p = projected();
      for (const annotation of payload) {
        if (!record(annotation) || typeof annotation.id !== 'string' || !annotation.id || seen.has(annotation.id)) throw new Error('Invalid or duplicate annotation ID');
        requireAnchor(annotation.anchor); seen.add(annotation.id);
        const range = locate(annotation.anchor);
        if (range) items.push({ id: annotation.id, quote: annotation.anchor.quote, from: p.toToken(range.start), to: p.toToken(range.start + range.length, true) });
      }
      wg.dispatch({ effects: replaceMarks.of(items) }); break;
    }
    case 'removeAnnotation': {
      requireString(payload);
      wg.dispatch({ effects: replaceMarks.of(wg.state.field(annotationField).items.filter(item => item.id !== payload)) }); break;
    }
    case 'scrollTo': {
      requireString(payload);
      const item = wg.state.field(annotationField).items.find(item => item.id === payload);
      if (!item) throw new Error('Annotation is missing or obsolete');
      wg.dispatch({ selection: GardSelection.range(item.from, item.to), effects: Wordgard.scrollIntoView(item.from, { y: 'center' }) });
      wg.focus(); break;
    }
    default: throw new Error(`Unknown editor command: ${method}`);
  }
  wg.flush();
  return null;
}
window.guildEditor = { dispatch(envelope: unknown): Reply {
  let id = '';
  try {
    if (!record(envelope) || envelope.version !== 1 || typeof envelope.id !== 'string' || !envelope.id || typeof envelope.method !== 'string' || !Object.hasOwn(envelope, 'payload')) throw new Error('Invalid bridge envelope');
    id = envelope.id;
    return { version: 1, id, ok: true, value: execute(envelope.method, envelope.payload) };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    emit({ version: 1, type: 'error', payload: message });
    return { version: 1, id, ok: false, error: message };
  }
} };
window.addEventListener('error', event => emit({ version: 1, type: 'error', payload: event.message }));
window.addEventListener('unhandledrejection', event => emit({ version: 1, type: 'error', payload: String(event.reason) }));
document.querySelector('#toolbar')!.addEventListener('mousedown', event => event.preventDefault());
document.querySelector('#toolbar')!.addEventListener('click', event => {
  const button = event.target instanceof Element ? event.target.closest<HTMLButtonElement>('button[data-format]') : null;
  if (button) window.guildEditor.dispatch({ version: 1, id: crypto.randomUUID(), method: 'applyFormatting', payload: button.dataset.format });
});
emit({ version: 1, type: 'ready', payload: null });
