export interface Manuscript { sceneID: string; html: string; text: string; revision: number }
export interface TextAnchor { sceneID: string; revision: number; start: number; length: number; quote: string; prefix: string; suffix: string }
export interface Annotation { id: string; anchor: TextAnchor }
export type Formatting = 'strong' | 'emphasis' | 'paragraph' | 'heading1' | 'heading2' | 'blockquote' | 'bulletList' | 'orderedList' | 'undo' | 'redo';
export interface Selection { start: number; length: number; text: string }
export interface Commands {
  load: Manuscript; export: null; getText: null; getSelection: null; getTextForAnchor: TextAnchor;
  applyFormatting: Formatting; annotate: Annotation[]; removeAnnotation: string; scrollTo: string;
  setSelection: { start: number; length: number }; insertText: string;
}
export type CommandEnvelope = { [M in keyof Commands]: { version: 1; id: string; method: M; payload: Commands[M] } }[keyof Commands];
export type Reply = { version: 1; id: string; ok: true; value: unknown } | { version: 1; id: string; ok: false; error: string };
export type EditorEvent = { version: 1; type: 'ready'; payload: null } | { version: 1; type: 'change'; payload: Manuscript } | { version: 1; type: 'selectionChange'; payload: Selection } | { version: 1; type: 'annotationClick'; payload: string } | { version: 1; type: 'error'; payload: string };
export interface EditorAPI { dispatch(envelope: unknown): Reply }
declare global { interface Window { guildEditor: EditorAPI; webkit?: { messageHandlers?: { guild?: { postMessage(event: EditorEvent): void } } } } }
