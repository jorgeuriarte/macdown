/*
 * MacDown Remix — Inspector de edición inline (M1, EXPERIMENTAL)
 *
 * Modelo de interacción "fondo de sección" (espacial, Opción D — ver
 * docs/EDICION-INLINE.md). El DOM real de cmark-gfm es HTML PLANO: hermanos sin
 * <section>, con `data-sourcepos` por bloque.
 *
 *   1. Deriva el "tipo" de bloque del tagName y el rango de líneas de `data-sourcepos`.
 *   2. Calcula las SECCIONES al vuelo (Opción D) desde los headings + sourcepos.
 *   3. Resuelve el objetivo por POSICIÓN (la Y elige el bloque; clic en la etiqueta del
 *      fondo sube al contenedor: ítem→lista→sección→documento).
 *   4. Reutiliza el puente: postea 'block'/'selection' (recuadro/cursor en el editor) y
 *      redefine `macdownHighlightLines` (editor→visor).
 *   5. Edición: ✏︎ / doble-clic (ya fijado) abre el FUENTE Markdown en un mini-editor.
 *
 * ───────────────────────────────────────────────────────────────────────────────────
 *  MÁQUINA DE ESTADOS  —  una sola variable `mode` (única fuente de verdad)
 * ───────────────────────────────────────────────────────────────────────────────────
 *  off      No estamos en sólo-visor: no hay inspector. Sólo CAPA A (sincronización
 *           fuente↔visor: esquinas según el cursor del editor / selección en el visor).
 *  reading  Sólo-visor, modo escritura OFF. FAB ✎ visible apagado. Sólo CAPA A.
 *  idle     Modo escritura ON, sin objetivo. Franja visible.
 *  hover    Modo escritura ON, apuntando un bloque (transitorio).
 *  pinned   Bloque FIJADO. Habilita ✏︎, doble-clic y promover por etiqueta.
 *  editing  Mini-editor abierto (sub-estado `previewing` local: textarea ↔ vista previa).
 *
 *  Precondiciones (las fija ObjC): available = mode!='off'; writing = mode∈{idle,hover,
 *  pinned,editing}. Toda transición pasa por setMode(), que es el ÚNICO mutador de `mode`
 *  y el único sitio que cierra el mini-editor → los estados ilegales (p. ej. apagar el
 *  modo escritura con el editor abierto) son imposibles por construcción.
 *
 *  Qué hace cada entrada según el estado:
 *    mousemove   sólo idle/hover/pinned (no editing, no overLabel)
 *    clic=fijar  idle/hover → pinned
 *    ✏︎/dbl-clic  sólo pinned → editing
 *    etiqueta    hover/pinned → promueve (pinned)
 *    Esc         pinned→idle ; editing→idle (cierra)
 *    FAB ✎       cualquiera salvo editing → postea 'inlineToggle' (ObjC alterna writing)
 *    set*        ObjC: availability/writingMode → setMode (cierra editor si procede)
 * ───────────────────────────────────────────────────────────────────────────────────
 */
(function () {
  if (window.__mdInspector) return;          // idempotente (re-inyección)
  window.__mdInspector = true;

  // ---------- puente JS→ObjC ----------
  function post(msg) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.macdown)
        window.webkit.messageHandlers.macdown.postMessage(msg);
    } catch (e) {}
  }

  // ---------- color de acento del tema (color de enlace) ----------
  function themeAccent() {
    var a = document.createElement('a');
    a.href = '#'; a.style.cssText = 'display:none';
    document.documentElement.appendChild(a);
    var c = getComputedStyle(a).color; a.remove();
    if (!c || c === 'rgba(0, 0, 0, 0)')
      c = (document.body && getComputedStyle(document.body).color) || '#4183C4';
    return c;
  }

  // ---------- modelo de bloques sobre el HTML plano de cmark ----------
  function isContent(el) {
    return el && el.nodeType === 1 && el.hasAttribute && el.hasAttribute('data-sourcepos');
  }
  function bodyBlocks() {
    var out = [], ch = document.body.children;
    for (var i = 0; i < ch.length; i++) if (isContent(ch[i])) out.push(ch[i]);
    return out;
  }
  function hlevel(el) { var m = /^H([1-6])$/i.exec(el.tagName); return m ? +m[1] : 0; }
  function lines(el) {
    var a = el.getAttribute('data-sourcepos');
    var m = a && a.match(/^(\d+):\d+-(\d+):\d+/);
    return m ? [+m[1], +m[2]] : [0, 0];
  }
  var KIND = {
    H1: 'Título', H2: 'Encabezado', H3: 'Encabezado', H4: 'Encabezado', H5: 'Encabezado', H6: 'Encabezado',
    P: 'Párrafo', UL: 'Lista', OL: 'Lista', LI: 'Ítem', BLOCKQUOTE: 'Cita',
    PRE: 'Código', TABLE: 'Tabla', HR: 'Separador'
  };
  var ICON = {
    Documento: '§', 'Sección': '▤', 'Subsección': '▤', Apartado: '▤', 'Título': 'H1',
    Encabezado: 'H', 'Párrafo': '¶', Lista: '•', 'Ítem': '–', Cita: '❝',
    'Código': '‹›', Tabla: '▦', Separador: '—'
  };
  function kindOf(el) { return KIND[el.tagName] || el.tagName.toLowerCase(); }
  function blockEntry(el) {
    var L = lines(el);
    return { first: el, last: el, kind: kindOf(el), name: '', s: L[0], e: L[1] };
  }

  // Sección (rango implícito) que contiene blocks[idx] a un nivel de heading dado.
  function sectionAt(blocks, idx, level) {
    var h = -1;
    for (var i = idx; i >= 0; i--) {
      var L = hlevel(blocks[i]);
      if (L && L <= level) { if (L === level) { h = i; break; } else return null; }
    }
    if (h < 0) return null;
    var end = blocks.length - 1;
    for (var j = h + 1; j < blocks.length; j++) {
      var Lj = hlevel(blocks[j]);
      if (Lj && Lj <= level) { end = j - 1; break; }
    }
    var name = (blocks[h].textContent || '').trim().replace(/\s+/g, ' ').slice(0, 34);
    var kn = level <= 2 ? 'Sección' : (level === 3 ? 'Subsección' : 'Apartado');
    return { first: blocks[h], last: blocks[end], kind: kn, name: name,
             s: lines(blocks[h])[0], e: lines(blocks[end])[1] };
  }
  // Sección más interna (mayor nivel de heading) que contiene el bloque, o null.
  function innerSection(blocks, el) {
    var idx = blocks.indexOf(el);
    if (idx < 0) return null;
    for (var lvl = 6; lvl >= 2; lvl--) { var s = sectionAt(blocks, idx, lvl); if (s) return s; }
    return null;
  }
  function allSections(blocks) {
    var out = [];
    for (var i = 0; i < blocks.length; i++) { var L = hlevel(blocks[i]); if (L >= 2) out.push(sectionAt(blocks, i, L)); }
    return out;
  }
  function docEntry(blocks) {
    var f = blocks[0], l = blocks[blocks.length - 1];
    return { first: f, last: l, kind: 'Documento', name: '', s: lines(f)[0], e: lines(l)[1] };
  }

  function boxOf(en) {
    var a = en.first.getBoundingClientRect(), b = en.last.getBoundingClientRect();
    return { left: Math.min(a.left, b.left), top: Math.min(a.top, b.top),
             right: Math.max(a.right, b.right), bottom: Math.max(a.bottom, b.bottom) };
  }

  // ---------- overlays inyectados ----------
  var AC = themeAccent();
  var CM = function (p) { return 'color-mix(in srgb,' + AC + ' ' + p + ',transparent)'; };
  var corner = 'linear-gradient(' + AC + ',' + AC + ')';
  var st = document.createElement('style');
  st.textContent =
    '#mdi-gutter{position:fixed;z-index:2147483600;pointer-events:none;top:0;height:100vh;transition:background .15s,border-color .15s;' +
      'background:linear-gradient(90deg,transparent 0%,' + CM('13%') + ' 42%,' + CM('13%') + ' 100%);border-left:1px dashed ' + CM('38%') + ';}' +
    '#mdi-gutter.hot{background:linear-gradient(90deg,transparent 0%,' + CM('26%') + ' 42%,' + CM('26%') + ' 100%);border-left-color:' + CM('72%') + ';}' +
    '#mdi-fondo{position:fixed;pointer-events:none;z-index:2147483601;border-radius:10px;opacity:0;transition:all .08s ease;' +
      'background:' + CM('6%') + ';box-shadow:inset 0 0 0 1px ' + CM('16%') + ';}' +
    '#mdi-fondolbl{position:fixed;pointer-events:auto;cursor:pointer;z-index:2147483602;opacity:0;transition:opacity .08s,background .1s,color .1s;' +
      'font:600 10px/1 system-ui,sans-serif;letter-spacing:.3px;text-transform:uppercase;color:' + AC + ';' +
      'background:color-mix(in srgb,' + AC + ' 12%,#fff);padding:4px 8px;border-radius:0 0 7px 0;white-space:nowrap;}' +
    '#mdi-fondolbl:hover{background:' + AC + ';color:#fff;}' +
    '#mdi-ov{position:fixed;pointer-events:none;z-index:2147483603;border-radius:5px;opacity:0;transition:all .07s ease;' +
      'background:' + CM('9%') + ';box-shadow:inset 0 0 0 1.5px ' + CM('48%') + ';}' +
    '#mdi-sel{position:fixed;pointer-events:none;z-index:2147483604;border-radius:5px;opacity:0;transition:all .07s ease;background-repeat:no-repeat;' +
      'background-image:' + (corner + ',') + (corner + ',') + (corner + ',') + corner + ',' + (corner + ',') + (corner + ',') + (corner + ',') + corner + ';' +
      'background-position:left top,left top,right top,right top,left bottom,left bottom,right bottom,right bottom;' +
      'background-size:26px 2px,2px 26px,26px 2px,2px 26px,26px 2px,2px 26px,26px 2px,2px 26px;}' +
    '#mdi-tip{position:fixed;pointer-events:none;z-index:2147483605;font:600 11px/1.4 ui-monospace,Menlo,monospace;' +
      'background:#2b2f36;color:#fff;padding:3px 8px;border-radius:5px;white-space:nowrap;opacity:0;}' +
    '#mdi-tip span{opacity:.6;font-weight:400;margin-left:6px;}' +
    '#mdi-edit{position:fixed;z-index:2147483606;opacity:0;transform:scale(.8);transition:opacity .1s,transform .1s;pointer-events:auto;cursor:pointer;' +
      'background:' + AC + ';color:#fff;border:none;border-radius:50%;width:26px;height:26px;font:13px/1 system-ui,sans-serif;' +
      'box-shadow:0 2px 6px rgba(0,0,0,.22);display:flex;align-items:center;justify-content:center;}' +
    '#mdi-edit.on{opacity:.92;transform:none;}#mdi-edit:hover{opacity:1;}' +
    // Botón flotante translúcido (esquina sup. derecha): activa el modo escritura. Sólo
    // aparece en sólo-visor, el hogar único de la edición inline.
    '#mdi-fab{position:fixed;top:14px;right:16px;z-index:2147483640;width:38px;height:38px;border-radius:50%;' +
      'border:1px solid ' + CM('30%') + ';background:color-mix(in srgb,' + AC + ' 14%,rgba(255,255,255,.55));' +
      '-webkit-backdrop-filter:saturate(1.3) blur(6px);backdrop-filter:saturate(1.3) blur(6px);color:' + AC + ';' +
      'font:16px/1 system-ui,sans-serif;display:none;align-items:center;justify-content:center;cursor:pointer;' +
      'box-shadow:0 2px 8px rgba(0,0,0,.16);opacity:.5;transition:opacity .12s,background .12s,transform .1s,color .12s;}' +
    '#mdi-fab:hover{opacity:1;transform:scale(1.06);}' +
    '#mdi-fab.on{background:' + AC + ';color:#fff;opacity:1;border-color:' + AC + ';}' +
    '.mdi-edid{margin:.4em 0;border:1.5px solid ' + AC + ';border-radius:7px;overflow:hidden;box-shadow:0 4px 14px rgba(0,0,0,.10);}' +
    '.mdi-edid textarea{display:block;width:100%;box-sizing:border-box;border:0;outline:0;resize:vertical;min-height:60px;' +
      'font:13.5px/1.55 ui-monospace,Menlo,monospace;padding:11px 13px;color:inherit;background:transparent;}' +
    '.mdi-edid .bar{display:flex;justify-content:space-between;align-items:center;background:' + CM('7%') + ';' +
      'border-top:1px solid ' + CM('22%') + ';padding:5px 8px 5px 11px;font:11px system-ui,sans-serif;color:#8a929c;}' +
    '.mdi-edid .bar button{font:600 12px system-ui,sans-serif;border:0;border-radius:5px;padding:5px 10px;cursor:pointer;}' +
    '.mdi-edid .done{background:' + AC + ';color:#fff;}.mdi-edid .cancel{background:' + CM('16%') + ';color:inherit;}' +
    '.mdi-edid .view{background:' + CM('10%') + ';color:inherit;}' +
    '.mdi-edid .bar button{margin-left:6px;}' +
    '.mdi-edid .mdi-edprev{padding:6px 13px 12px;min-height:60px;}';
  (document.head || document.documentElement).appendChild(st);

  function mk(id, tag) { var e = document.createElement(tag || 'div'); e.id = id; document.body.appendChild(e); return e; }
  var gutter = mk('mdi-gutter'), fondo = mk('mdi-fondo'), fondolbl = mk('mdi-fondolbl'),
      ov = mk('mdi-ov'), sel = mk('mdi-sel'), tip = mk('mdi-tip');
  var edit = mk('mdi-edit', 'button'); edit.title = 'Editar'; edit.textContent = '✏︎';
  var fab = mk('mdi-fab', 'button'); fab.title = 'Edición inline (modo escritura)'; fab.textContent = '✎';

  // ---------- ESTADO ----------
  var mode = 'off';                            // off | reading | idle | hover | pinned | editing
  var primary = null, primSection = null;      // objetivo resuelto y su contenedor (datos)
  var overLabel = false;                       // ratón sobre la etiqueta del fondo (congela la selección)
  var curChain = null, curLevel = 0;           // (reservado) cadena de contenedores y nivel
  var _inlinePreviewCb = null;                 // callback del resultado de "Vista previa"
  var _inlineCancel = null;                    // limpieza del mini-editor abierto (la usa setMode)
  var GUT = 0.16, lastSent = '';
  gutter.style.display = 'none';               // oculta hasta entrar en modo escritura

  function isAvailable() { return mode !== 'off'; }
  function isWriting() { return mode === 'idle' || mode === 'hover' || mode === 'pinned' || mode === 'editing'; }

  // ÚNICO mutador de `mode`. Cierra el mini-editor al salir de 'editing', limpia el
  // objetivo en los estados sin selección, y reconfigura el "chrome" (applyChrome).
  function setMode(next) {
    if (next === mode) return;
    var was = mode;
    mode = next;
    if (was === 'editing' && _inlineCancel) { var c = _inlineCancel; _inlineCancel = null; c(); }
    if (next === 'off' || next === 'reading' || next === 'idle') {
      primary = null; primSection = null; clearEditor();
    }
    applyChrome();
  }
  // Posiciona/oculta el chrome estático (FAB, franja) y limpia overlays en los estados
  // sin selección. Los overlays de selección los dibuja render() en hover/pinned.
  function applyChrome() {
    fab.style.display = isAvailable() ? 'flex' : 'none';
    fab.classList.toggle('on', isWriting());
    var spatial = isWriting() && mode !== 'editing';
    gutter.style.display = spatial ? '' : 'none';
    if (mode !== 'hover' && mode !== 'pinned') { gutter.classList.remove('hot'); clearAll(); }
    if (spatial) positionGutter();
  }

  // Rectángulo de contenido. `right` es la COLUMNA DEL TEXTO (mediana de los bordes
  // derechos de los bloques), no el máximo: así una tabla o un <pre> anchos no arrastran
  // la franja de activación lejos del texto.
  function contentRect() {
    var bs = bodyBlocks(), l = 1e9, t = 1e9, b = -1e9, rights = [];
    for (var i = 0; i < bs.length; i++) {
      var q = bs[i].getBoundingClientRect();
      if (q.width) { l = Math.min(l, q.left); t = Math.min(t, q.top); b = Math.max(b, q.bottom); rights.push(q.right); }
    }
    if (!rights.length) return { left: 0, right: window.innerWidth, top: 0, bottom: window.innerHeight };
    rights.sort(function (x, y) { return x - y; });
    var col = rights[Math.floor(rights.length / 2)];
    return { left: l, right: col, top: t, bottom: b };
  }
  // X de la "línea de activación" (borde izquierdo de la franja): a GUT del borde del texto.
  function activationX() { var c = contentRect(); return c.right - (c.right - c.left) * GUT; }

  function place(boxEl, en, padX, padY) {
    var r = boxOf(en);
    boxEl.style.left = (r.left - padX) + 'px'; boxEl.style.top = (r.top - padY) + 'px';
    boxEl.style.width = (r.right - r.left + 2 * padX) + 'px'; boxEl.style.height = (r.bottom - r.top + 2 * padY) + 'px';
    boxEl.style.opacity = 1;
  }
  function showTip(en) {
    tip.innerHTML = '<b>' + (ICON[en.kind] || '') + ' ' + en.kind + '</b><span>L' +
      en.s + (en.e !== en.s ? '–' + en.e : '') + (en.name ? ' · ' + en.name : '') + '</span>';
    var r = boxOf(en);
    tip.style.left = (r.left - 6) + 'px'; tip.style.top = Math.max(4, r.top - 26) + 'px'; tip.style.opacity = 1;
  }
  function showEdit(en) {
    // El ✏︎ sólo aparece con el bloque FIJADO (no en hover) y nunca en el documento.
    if (mode !== 'pinned' || en.kind === 'Documento') { edit.classList.remove('on'); return; }
    var r = boxOf(en);
    edit.style.left = (activationX() - 13) + 'px';     // junto a la línea de activación
    edit.style.top = Math.max(6, r.top - 13) + 'px';
    edit.classList.add('on');
  }
  function showFondo(s) {
    if (!s) { fondo.style.opacity = 0; fondolbl.style.opacity = 0; fondolbl.style.pointerEvents = 'none'; overLabel = false; return; }
    fondolbl.style.pointerEvents = 'auto';
    var r = boxOf(s);
    fondo.style.left = (r.left - 10) + 'px'; fondo.style.top = (r.top - 8) + 'px';
    fondo.style.width = (r.right - r.left + 20) + 'px'; fondo.style.height = (r.bottom - r.top + 16) + 'px'; fondo.style.opacity = 1;
    fondolbl.textContent = (ICON[s.kind] || '▤') + ' ' + (s.name || s.kind);
    fondolbl.style.left = (r.left - 10) + 'px'; fondolbl.style.top = (r.top - 8) + 'px'; fondolbl.style.opacity = 1;
  }
  function clearAll() {
    ov.style.opacity = 0; sel.style.opacity = 0; fondo.style.opacity = 0; fondolbl.style.opacity = 0;
    fondolbl.style.pointerEvents = 'none'; overLabel = false;   // no dejar la etiqueta capturando invisible
    tip.style.opacity = 0; edit.classList.remove('on');
  }

  // refleja el objetivo en el EDITOR (recuadro y, si type='selection', cursor). Documento no.
  function sendEditor(en, type) {
    if (!en || en.kind === 'Documento') { if (type === 'block') clearEditor(); return; }
    var key = type + ':' + en.s + ':' + en.e;
    if (type === 'block' && key === lastSent) return;
    lastSent = key;
    post({ type: type, startLine: en.s, endLine: en.e });
  }
  function clearEditor() { lastSent = ''; post({ type: 'block', startLine: 0, endLine: 0 }); }

  // ---------- resolución espacial del objetivo ----------
  // <li> hijo directo de una lista más cercano a la Y (para huecos entre ítems).
  function nearestChildLi(list, y) {
    var lis = list.querySelectorAll(':scope > li[data-sourcepos]'), best = null, bd = 1e9;
    for (var i = 0; i < lis.length; i++) {
      var r = lis[i].getBoundingClientRect();
      var d = (y < r.top) ? (r.top - y) : (y > r.bottom ? (y - r.bottom) : 0);
      if (d < bd) { bd = d; best = lis[i]; }
    }
    return best;
  }
  // Bloque MÁS PROFUNDO bajo esta Y (muestreando en la columna de texto). Tablas atómicas.
  function blockAtY(y) {
    var c = contentRect(), sx = c.left + (c.right - c.left) * 0.4;
    var el = document.elementFromPoint(sx, y);
    if (el && el.closest) {
      var tbl = el.closest('table[data-sourcepos]');
      if (tbl) return tbl;
      var blk = el.closest('[data-sourcepos]');
      if (blk && document.body.contains(blk)) return blk;
    }
    var bs = bodyBlocks();                              // respaldo geométrico (nivel superior)
    for (var i = 0; i < bs.length; i++) { var r = bs[i].getBoundingClientRect(); if (y >= r.top && y <= r.bottom) return bs[i]; }
    return null;
  }
  // Contenedor inmediato de un elemento: su ancestro con data-sourcepos (la <ul> de un
  // <li>), o, si es de nivel superior, su sección virtual. Se muestra como "fondo".
  function containerOf(el) {
    var p = el.parentElement;
    while (p && p !== document.body) { if (isContent(p)) return blockEntry(p); p = p.parentElement; }
    return innerSection(bodyBlocks(), el);
  }
  function deepestSectionAtY(blocks, y) {
    var best = null, span = 1e9, secs = allSections(blocks);
    for (var i = 0; i < secs.length; i++) {
      var s = secs[i]; if (!s) continue;
      var r = boxOf(s);
      if (y >= r.top && y <= r.bottom) { var sp = s.e - s.s; if (sp < span) { span = sp; best = s; } }
    }
    return best;
  }
  // Apuntas al TEXTO de un bloque → ese bloque (el más profundo); a un HUECO dentro de una
  // sección → la sección; fuera de toda sección → el documento.
  function resolve(y) {
    var blocks = bodyBlocks(); if (!blocks.length) return null;
    var b = blockAtY(y);
    if (b) return { prim: blockEntry(b), fondoSection: containerOf(b) };
    var s = deepestSectionAtY(blocks, y);
    if (s) return { prim: s, fondoSection: null };
    var c = contentRect();
    if (y >= c.top && y <= c.bottom) return { prim: docEntry(blocks), fondoSection: null };
    return null;
  }

  // Dibuja el objetivo. `sel` (esquinas) si pinned; `ov` (relleno) si hover.
  function render(box) {
    primary = box.prim; primSection = box.fondoSection || null;
    if (box.chain) { curChain = box.chain; curLevel = box.level; }
    showFondo(primSection);
    var isPinned = (mode === 'pinned');
    var target = isPinned ? sel : ov; (isPinned ? ov : sel).style.opacity = 0;
    place(target, primary, 5, 4); showTip(primary); showEdit(primary);
    sendEditor(primary, isPinned ? 'selection' : 'block');
  }

  function positionGutter() {
    var ax = activationX();
    gutter.style.left = ax + 'px';
    gutter.style.width = Math.max(0, window.innerWidth - ax) + 'px';   // hasta el borde de la ventana
  }
  positionGutter();

  // Subir al contenedor: clic en la etiqueta del fondo promueve la selección un nivel
  // (ítem→lista→sección→documento). overLabel congela la selección mientras la sobrevuelas.
  function parentOf(en) {
    if (!en || en.kind === 'Documento') return null;
    if (en.kind === 'Sección' || en.kind === 'Subsección' || en.kind === 'Apartado')
      return docEntry(bodyBlocks());
    return containerOf(en.first);
  }
  function promote() {
    if (!primSection) return;
    primary = primSection; primSection = parentOf(primary);
    setMode('pinned');
    ov.style.opacity = 0; place(sel, primary, 5, 4); showFondo(primSection); showTip(primary); showEdit(primary);
    sendEditor(primary, 'selection');
  }
  fondolbl.addEventListener('mouseenter', function () { overLabel = true; });
  fondolbl.addEventListener('mouseleave', function () { overLabel = false; });
  fondolbl.addEventListener('click', function (e) { e.stopPropagation(); if (mode === 'hover' || mode === 'pinned') promote(); });

  // ---------- entradas (gated por `mode`) ----------
  window.addEventListener('mousemove', function (e) {
    if (mode === 'editing' || !isWriting() || overLabel) return;
    if (mode === 'pinned') {                        // se mantiene fijado hasta salir del primario (con margen)
      var r = boxOf(primary);
      var safe = e.target === edit || edit.contains(e.target) || e.target === fondolbl ||
        (e.clientX > r.left - 12 && e.clientX < r.right + 60 && e.clientY > r.top - 16 && e.clientY < r.bottom + 14);
      if (!safe) setMode('idle');
      return;
    }
    var c = contentRect();
    var inZone = e.clientX > activationX() && e.clientX < window.innerWidth &&
                 e.clientY > c.top - 4 && e.clientY < c.bottom + 4;
    if (inZone) {
      var box = resolve(e.clientY);
      if (box) { render(box); gutter.classList.add('hot'); setMode('hover'); }
      else { setMode('idle'); }
    } else { setMode('idle'); }
  });

  // clic en la franja = fijar
  window.addEventListener('click', function (e) {
    if (mode === 'editing' || !isWriting() || e.target === edit || edit.contains(e.target) ||
        e.target === fondolbl || (e.target.closest && e.target.closest('.mdi-edid'))) return;
    var c = contentRect();
    var inZone = e.clientX > activationX() && e.clientY > c.top - 4 && e.clientY < c.bottom + 4;
    if (inZone && primary) { setMode('pinned'); render({ prim: primary, fondoSection: primSection }); }
  });

  // doble-clic (sólo ya fijado) o ✏︎ = editar
  window.addEventListener('dblclick', function (e) {
    if (mode === 'editing' || !isWriting() || (e.target.closest && e.target.closest('.mdi-edid'))) return;
    if (mode === 'pinned' && primary) { e.preventDefault(); requestEdit(primary); }
  });
  edit.addEventListener('click', function () { if (mode === 'pinned' && primary) requestEdit(primary); });
  fab.addEventListener('click', function (e) { e.stopPropagation(); if (mode === 'editing') return; post({ type: 'inlineToggle' }); });

  window.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    if (mode === 'editing') { e.preventDefault(); setMode('idle'); }   // cierra el mini-editor
    else if (mode === 'pinned') setMode('idle');                       // suelta la fijación
  });

  window.addEventListener('resize', positionGutter);
  window.addEventListener('scroll', function () {
    positionGutter();
    if (primary) { place(mode === 'pinned' ? sel : ov, primary, 5, 4); showTip(primary); showEdit(primary); if (primSection) showFondo(primSection); }
  }, { passive: true });

  // ---------- edición del fuente ----------
  function requestEdit(en) {
    if (!en || en.kind === 'Documento' || mode === 'editing') return;
    post({ type: 'inlineEdit', startLine: en.s, endLine: en.e });
  }
  // Hermanos de <body> de en.first..en.last (uno para bloques; varios para una Sección).
  function spanFromTo(first, last) {
    if (first === last) return [first];
    var out = [], n = first;
    while (n) { out.push(n); if (n === last) break; n = n.nextElementSibling; }
    return out;
  }
  // Llamado desde ObjC con el fuente del rango: abre el mini-editor in situ → mode 'editing'.
  window.macdownOpenInlineEditor = function (s, e, text) {
    if (mode === 'editing') return;
    var en = primary;
    if (!en || en.s !== s || en.e !== e) {
      var bs = bodyBlocks();
      for (var i = 0; i < bs.length; i++) {
        var L = lines(bs[i]);
        if (L[0] === s) { en = blockEntry(bs[i]); var sec = innerSection(bs, bs[i]); if (sec && sec.s === s && sec.e === e) en = sec; break; }
      }
    }
    if (!en) return;
    var hide = spanFromTo(en.first, en.last);
    var wrap = document.createElement('div'); wrap.className = 'mdi-edid';
    var ta = document.createElement('textarea'); ta.value = text != null ? text : '';
    var bar = document.createElement('div'); bar.className = 'bar';
    var lab = document.createElement('span');
    lab.textContent = 'editando ' + en.kind + ' · L' + en.s + (en.e !== en.s ? '–' + en.e : '') + ' (markdown fuente)';
    var prev = document.createElement('div'); prev.className = 'mdi-edprev'; prev.style.display = 'none';
    prev.setAttribute('tabindex', '-1');         // enfocable → el Esc global llega también en Vista previa
    var btns = document.createElement('span');
    var cancel = document.createElement('button'); cancel.className = 'cancel'; cancel.textContent = 'Cancelar';
    var view = document.createElement('button'); view.className = 'view'; view.textContent = 'Vista previa';
    var done = document.createElement('button'); done.className = 'done'; done.textContent = 'Hecho';
    btns.appendChild(cancel); btns.appendChild(view); btns.appendChild(done); bar.appendChild(lab); bar.appendChild(btns);
    wrap.appendChild(ta); wrap.appendChild(prev); wrap.appendChild(bar);
    hide[0].parentNode.insertBefore(wrap, hide[0]);
    for (var k = 0; k < hide.length; k++) hide[k].style.display = 'none';

    // Limpieza del DOM del editor (idempotente). NO toca `mode`: lo invoca setMode al salir.
    function cleanup() {
      _inlinePreviewCb = null;
      if (wrap.parentNode) wrap.remove();
      for (var k = 0; k < hide.length; k++) hide[k].style.display = '';
    }
    _inlineCancel = cleanup;
    setMode('editing');                          // entra en el estado (oculta franja/overlays)

    var previewing = false;
    function autosize() { ta.style.height = 'auto'; ta.style.height = Math.max(60, ta.scrollHeight) + 'px'; }
    ta.addEventListener('input', autosize);
    cancel.onclick = function () { setMode('idle'); };
    done.onclick = function () { post({ type: 'inlineEditCommit', startLine: en.s, endLine: en.e, text: ta.value }); setMode('idle'); };
    // Vista previa: renderiza el markdown editado con el MISMO motor (cmark, vía ObjC).
    view.onclick = function () {
      if (!previewing) {
        prev.innerHTML = '<div style="opacity:.5;font:13px system-ui,sans-serif">renderizando…</div>';
        ta.style.display = 'none'; prev.style.display = ''; previewing = true; view.textContent = 'Editar';
        _inlinePreviewCb = function (html) {
          prev.innerHTML = html;
          if (window.macdownRenderMermaid) window.macdownRenderMermaid(prev);   // diagramas en la Vista previa
        };
        post({ type: 'inlinePreview', text: ta.value });
        prev.focus();                            // mantiene el foco en el visor → Esc cancela
      } else {
        prev.style.display = 'none'; ta.style.display = ''; previewing = false; view.textContent = 'Vista previa'; ta.focus();
      }
    };
    ta.addEventListener('keydown', function (ev) {
      if (ev.key === 'Enter' && (ev.metaKey || ev.ctrlKey)) { ev.preventDefault(); done.onclick(); }
      else if (ev.key === 'Escape') { ev.preventDefault(); setMode('idle'); }
    });
    ta.focus(); autosize();
  };

  // ---------- editor → visor (CAPA A + pista en escritura) ----------
  window.macdownHighlightLines = function (start, end) {
    if (mode === 'pinned' || mode === 'editing') return;   // no pisar fijación/edición
    if (!start) { primary = null; primSection = null; clearAll(); return; }
    var els = document.querySelectorAll('[data-sourcepos]'), best = null, bestSpan = 1e9;
    for (var i = 0; i < els.length; i++) {
      if (!document.body.contains(els[i])) continue;
      var L = lines(els[i]);
      if (L[0] <= start && start <= L[1]) { var sp = L[1] - L[0]; if (sp < bestSpan) { bestSpan = sp; best = els[i]; } }
    }
    if (!best) return;
    var tbl = best.closest && best.closest('table[data-sourcepos]'); if (tbl) best = tbl;
    primary = blockEntry(best); primSection = containerOf(best);
    if (isWriting()) { showFondo(primSection); place(ov, primary, 5, 4); showTip(primary); showEdit(primary); }
    else { ov.style.opacity = 0; fondo.style.opacity = 0; fondolbl.style.opacity = 0; place(sel, primary, 5, 4); }  // CAPA A: esquinas
  };

  // Preview→editor (CAPA A, sólo cuando NO se escribe): seleccionar/clicar en el visor
  // lleva el cursor del editor al bloque y dibuja las esquinas.
  document.addEventListener('selectionchange', function () {
    if (isWriting()) return;                     // en escritura el clic fija (lo gestiona el handler de click)
    var s0 = window.getSelection(); if (!s0 || s0.rangeCount === 0) return;
    var node = s0.anchorNode; if (node && node.nodeType === 3) node = node.parentElement;
    var el = node && node.closest && node.closest('[data-sourcepos]');
    if (!el) return;
    var tbl = el.closest('table[data-sourcepos]'); if (tbl) el = tbl;
    var en = blockEntry(el); primary = en; primSection = null;
    place(sel, en, 5, 4);
    post({ type: 'selection', startLine: en.s, endLine: en.e });
  });

  // ---------- setters de ObjC (availability = sólo-visor; writingMode = FAB) ----------
  window.macdownSetInlineAvailable = function (on) {
    if (on) { if (mode === 'off') setMode('reading'); }
    else { setMode('off'); }                     // setMode cierra el editor si lo hubiera
  };
  window.macdownSetWritingMode = function (on) {
    if (on) { if (isAvailable() && !isWriting()) setMode('idle'); }
    else if (isWriting()) { setMode('reading'); }   // cierra el editor si lo hubiera
  };
  window.macdownInlineWritingMode = function () { return isWriting(); };
  window.macdownInlinePreviewResult = function (html) { if (_inlinePreviewCb) _inlinePreviewCb(html); };
})();
