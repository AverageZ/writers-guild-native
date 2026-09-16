import { test, expect, type Page } from '@playwright/test';
import type { Commands, Manuscript, TextAnchor, EditorEvent } from '../src/contracts';

declare global { interface Window { testEvents: EditorEvent[] } }

async function command<M extends keyof Commands>(page: Page, method: M, payload: Commands[M]) {
  const response = await page.evaluate(({ method, payload }) => window.guildEditor.dispatch({ version: 1, id: crypto.randomUUID(), method, payload }), { method, payload });
  if (!response.ok) throw new Error(response.error);
  return response.value;
}
async function exported(page: Page) { return await command(page, 'export', null) as Manuscript; }
async function load(page: Page, html: string, sceneID = 'scene', revision = 4) {
  return command(page, 'load', { sceneID, html, text: '', revision });
}
test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await page.waitForFunction(() => !!window.guildEditor);
});

test('import normalization advances revision once, unchanged export never advances it', async ({ page }) => {
  await command(page, 'load', { sceneID: 'normalization', html: '<p><b>Rowan</b></p>', text: 'outdated cache', revision: 20 });
  const canonical = await exported(page);
  expect(canonical).toEqual({ sceneID: 'normalization', html: '<p><strong>Rowan</strong></p>', text: 'Rowan', revision: 21 });
  expect(await exported(page)).toEqual(canonical);
  await command(page, 'load', { ...canonical, sceneID: 'reopened' });
  expect((await exported(page)).revision).toBe(21);
});

test('real typing, semantic formatting, portable export/reload and same-scene echo preserve undo', async ({ page }) => {
  await load(page, '<p>Rowan waits.</p>');
  await command(page, 'setSelection', { start: 12, length: 0 });
  await page.keyboard.type(' Still.');
  let draft = await exported(page);
  expect(draft.text).toBe('Rowan waits. Still.');
  expect(draft.revision).toBeGreaterThan(4);
  await command(page, 'setSelection', { start: 0, length: 5 });
  await command(page, 'applyFormatting', 'strong');
  draft = await exported(page);
  expect(draft.html).toContain('<strong>Rowan</strong>');
  const revision = draft.revision;
  await command(page, 'load', draft);
  expect((await exported(page)).revision).toBe(revision);
  await command(page, 'applyFormatting', 'undo');
  expect((await exported(page)).html).not.toContain('<strong>');
  await command(page, 'load', { ...draft, sceneID: 'reloaded' });
  const reloaded = await exported(page);
  expect(reloaded.html).toBe(draft.html);
  expect(reloaded.text).toBe(draft.text);
  expect(reloaded.revision).toBe(draft.revision);
});

test('UTF16 projection handles emoji, combining marks, nested blocks, empty blocks and line breaks', async ({ page }) => {
  await load(page, '<h1>Arrival</h1><p>🦊 café</p><p></p><blockquote><p>North<br>gate</p></blockquote><ul><li><p>One</p></li><li><p>Two</p></li></ul>');
  const draft = await exported(page);
  expect(draft.text).toBe('Arrival\n🦊 café\n\nNorth\ngate\nOne\nTwo');
  const start = draft.text.indexOf('🦊');
  const anchor: TextAnchor = { sceneID: 'scene', revision: draft.revision, start, length: '🦊 café'.length, quote: '🦊 café', prefix: 'Arrival\n', suffix: '\n\nNorth' };
  expect(await command(page, 'getTextForAnchor', anchor)).toBe('🦊 café');
  await command(page, 'setSelection', { start, length: 2 });
  expect(await command(page, 'getSelection', null)).toEqual({ start, length: 2, text: '🦊' });
  await command(page, 'applyFormatting', 'emphasis');
  expect((await exported(page)).html).toContain('<em>🦊</em>');
});

test('decorations map through edits, click navigates, removal does not serialize, changed quotes disappear', async ({ page }) => {
  await load(page, '<p>A 🦊 waits at the gate.</p>');
  const draft = await exported(page);
  const anchor: TextAnchor = { sceneID: 'scene', revision: draft.revision, start: 5, length: 5, quote: 'waits', prefix: 'A 🦊 ', suffix: ' at the gate.' };
  await command(page, 'annotate', [{ id: 'observation', anchor }]);
  const annotation = page.locator('[data-annotation-id="observation"]');
  await expect(annotation).toHaveText('waits');
  await page.evaluate(() => {
    const events: EditorEvent[] = [];
    window.testEvents = events;
    window.addEventListener('guild-editor-event', event => events.push((event as CustomEvent<EditorEvent>).detail));
  });
  await annotation.click();
  expect(await page.evaluate(() => window.testEvents.some(e => e.type === 'annotationClick' && e.payload === 'observation'))).toBe(true);
  await command(page, 'setSelection', { start: 0, length: 0 });
  await page.keyboard.type('Today ');
  await expect(annotation).toHaveText('waits');
  await command(page, 'scrollTo', 'observation');
  expect(await command(page, 'getSelection', null)).toEqual({ start: 11, length: 5, text: 'waits' });
  expect(await page.evaluate(() => window.testEvents.some(e => e.type === 'selectionChange' && e.payload.start === 11 && e.payload.length === 5 && e.payload.text === 'waits'))).toBe(true);
  const mapped = await exported(page);
  expect(mapped.html).not.toContain('guild-annotation');
  expect(mapped.html).not.toContain('observation');
  expect(await command(page, 'getTextForAnchor', anchor)).toBe('waits');
  await command(page, 'removeAnnotation', 'observation');
  await expect(annotation).toHaveCount(0);
  expect((await exported(page)).revision).toBe(mapped.revision);
  await command(page, 'annotate', [{ id: 'observation', anchor }]);
  await command(page, 'setSelection', { start: 11, length: 5 });
  await page.keyboard.type('runs');
  await expect(annotation).toHaveCount(0);
  const failure = await page.evaluate(anchor => window.guildEditor.dispatch({ version: 1, id: 'stale', method: 'getTextForAnchor', payload: anchor }), anchor);
  expect(failure.ok).toBe(false);
});

test('overlapping and unsorted observations remain independently navigable without changing prose', async ({ page }) => {
  await load(page, '<p>Private Rowan seemed almost ready.</p>');
  const original = await exported(page);
  const anchor = (start: number, quote: string): TextAnchor => ({
    sceneID: 'scene', revision: original.revision, start, length: quote.length, quote, prefix: '', suffix: '',
  });
  await command(page, 'annotate', [
    { id: 'style', anchor: anchor(14, 'seemed almost') },
    { id: 'passage', anchor: anchor(0, original.text) },
    { id: 'rank', anchor: anchor(0, 'Private Rowan') },
  ]);
  await expect(page.locator('[data-annotation-id]')).not.toHaveCount(0);
  await command(page, 'scrollTo', 'rank');
  expect((await command(page, 'getSelection', null) as { text: string }).text).toBe('Private Rowan');
  await command(page, 'scrollTo', 'style');
  expect((await command(page, 'getSelection', null) as { text: string }).text).toBe('seemed almost');
  await command(page, 'removeAnnotation', 'passage');
  await command(page, 'scrollTo', 'rank');
  expect((await command(page, 'getSelection', null) as { text: string }).text).toBe('Private Rowan');
  expect(await exported(page)).toEqual(original);
});

test('ambiguous stale anchors never select a coincidental quote', async ({ page }) => {
  await load(page, '<p>waits waits</p>', 'scene', 8);
  await command(page, 'annotate', [{ id: 'ambiguous', anchor: { sceneID: 'scene', revision: 1, start: 0, length: 5, quote: 'waits', prefix: '', suffix: '' } }]);
  await expect(page.locator('[data-annotation-id]')).toHaveCount(0);
});

test('offline surface rejects unsafe imports and malformed commands without destroying the manuscript', async ({ page }) => {
  const remote: string[] = [];
  page.on('request', request => { if (!request.url().startsWith('http://127.0.0.1:4178/')) remote.push(request.url()); });
  await load(page, '<p>Safe prose.</p>');
  for (const html of ['<p><img src="https://example.com/pixel.png"></p>', '<iframe src="https://example.com"></iframe>', '<p onclick="alert(1)">Bad</p>']) {
    const result = await page.evaluate(html => window.guildEditor.dispatch({ version: 1, id: 'unsafe', method: 'load', payload: { sceneID: 'unsafe', revision: 0, html, text: '' } }), html);
    expect(result.ok).toBe(false);
    expect((await exported(page)).text).toBe('Safe prose.');
  }
  const invalid = await page.evaluate(() => [
    window.guildEditor.dispatch({ version: 2, id: 'bad', method: 'export', payload: null }),
    window.guildEditor.dispatch({ version: 1, id: 'bad', method: 'invented', payload: null }),
    window.guildEditor.dispatch({ version: 1, id: 'bad', method: 'setSelection', payload: { start: -1, length: 2 } }),
  ]);
  expect(invalid.every(reply => !reply.ok)).toBe(true);
  expect((await exported(page)).text).toBe('Safe prose.');
  expect(await page.evaluate(async () => { try { await fetch('https://example.com/forbidden'); return false; } catch { return true; } })).toBe(true);
  expect(remote).toEqual([]);
});
