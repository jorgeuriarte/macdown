/*
 * MacDown Remix — Inspector de edición inline (M1, EXPERIMENTAL)
 *
 * Modelo de interacción "fondo de sección" (espacial, Opción D — ver
 * docs/EDICION-INLINE.md). El DOM real de cmark-gfm es HTML PLANO: hermanos sin
 * <section>, con `data-sourcepos` por bloque. Este script:
 *
 *   1. Deriva el "tipo" de bloque del tagName y el rango de líneas de `data-sourcepos`.
 *   2. Calcula las SECCIONES al vuelo (Opción D) desde los headings + sourcepos, SIN
 *      crear <section> ni tocar el render de cmark.
 *   3. Resuelve el objetivo por POSICIÓN en la franja de activación (derecha):
 *        - sobre el TEXTO de un bloque (incl. la línea de un título) → ese bloque,
 *          con el "fondo" de su sección contenedora mostrado detrás;
 *        - sobre un HUECO/margen dentro de una sección → la sección entera;
 *        - sobre un hueco fuera de toda sección → el documento.
 *      Así, en cualquier encabezado, se alcanzan los dos niveles (título solo / sección)
 *      sin breadcrumb, flechas ni doble-clic mágico.
 *   4. Reutiliza el puente: postea 'block'/'selection' (recuadro/cursor en el editor) y
 *      redefine `macdownHighlightLines` (editor→visor), sustituyendo a la selección
 *      conectada clásica mientras vive en esta rama.
 *   5. Edición: ✏︎ / doble-clic (ya fijado) abre el FUENTE Markdown del objetivo en un
 *      mini-editor in situ; al confirmar, ObjC reescribe el rango exacto y re-renderiza.
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
      'background:linear-gradient(90deg,transparent,' + CM('14%') + ');border-left:1px dashed ' + CM('38%') + ';}' +
    '#mdi-gutter.hot{background:linear-gradient(90deg,transparent,' + CM('30%') + ');border-left-color:' + CM('70%') + ';}' +
    '#mdi-fondo{position:fixed;pointer-events:none;z-index:2147483601;border-radius:10px;opacity:0;transition:all .08s ease;' +
      'background:' + CM('6%') + ';box-shadow:inset 0 0 0 1px ' + CM('16%') + ';}' +
    '#mdi-fondolbl{position:fixed;pointer-events:none;z-index:2147483602;opacity:0;transition:all .08s;' +
      'font:600 10px/1 system-ui,sans-serif;letter-spacing:.3px;text-transform:uppercase;color:' + AC + ';' +
      'background:color-mix(in srgb,' + AC + ' 12%,#fff);padding:3px 7px;border-radius:0 0 7px 0;}' +
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
    '.mdi-edid{margin:.4em 0;border:1.5px solid ' + AC + ';border-radius:7px;overflow:hidden;box-shadow:0 4px 14px rgba(0,0,0,.10);}' +
    '.mdi-edid textarea{display:block;width:100%;box-sizing:border-box;border:0;outline:0;resize:vertical;min-height:60px;' +
      'font:13.5px/1.55 ui-monospace,Menlo,monospace;padding:11px 13px;color:inherit;background:transparent;}' +
    '.mdi-edid .bar{display:flex;justify-content:space-between;align-items:center;background:' + CM('7%') + ';' +
      'border-top:1px solid ' + CM('22%') + ';padding:5px 8px 5px 11px;font:11px system-ui,sans-serif;color:#8a929c;}' +
    '.mdi-edid .bar button{font:600 12px system-ui,sans-serif;border:0;border-radius:5px;padding:5px 10px;cursor:pointer;}' +
    '.mdi-edid .done{background:' + AC + ';color:#fff;}.mdi-edid .cancel{background:' + CM('16%') + ';color:inherit;margin-right:6px;}';
  (document.head || document.documentElement).appendChild(st);

  function mk(id, tag) { var e = document.createElement(tag || 'div'); e.id = id; document.body.appendChild(e); return e; }
  var gutter = mk('mdi-gutter'), fondo = mk('mdi-fondo'), fondolbl = mk('mdi-fondolbl'),
      ov = mk('mdi-ov'), sel = mk('mdi-sel'), tip = mk('mdi-tip');
  var edit = mk('mdi-edit', 'button'); edit.title = 'Editar'; edit.textContent = '✏︎';

  // ---------- estado ----------
  var primary = null, primSection = null, pinned = false, editing = false, GUT = 0.16, lastSent = '';

  function contentRect() {
    var bs = bodyBlocks(), l = 1e9, r = -1e9, t = 1e9, b = -1e9;
    for (var i = 0; i < bs.length; i++) {
      var q = bs[i].getBoundingClientRect();
      if (q.width) { l = Math.min(l, q.left); r = Math.max(r, q.right); t = Math.min(t, q.top); b = Math.max(b, q.bottom); }
    }
    if (l > r) { l = 0; r = window.innerWidth; t = 0; b = window.innerHeight; }
    return { left: l, right: r, top: t, bottom: b };
  }

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
    if (en.kind === 'Documento') { edit.classList.remove('on'); return; }  // el doc entero no se edita inline
    var r = boxOf(en);
    edit.style.left = (r.right - 4 - 26) + 'px'; edit.style.top = Math.max(6, r.top - 13) + 'px'; edit.classList.add('on');
  }
  function showFondo(s) {
    if (!s) { fondo.style.opacity = 0; fondolbl.style.opacity = 0; return; }
    var r = boxOf(s);
    fondo.style.left = (r.left - 10) + 'px'; fondo.style.top = (r.top - 8) + 'px';
    fondo.style.width = (r.right - r.left + 20) + 'px'; fondo.style.height = (r.bottom - r.top + 16) + 'px'; fondo.style.opacity = 1;
    fondolbl.textContent = '▤ ' + (s.name || s.kind);
    fondolbl.style.left = (r.left - 10) + 'px'; fondolbl.style.top = (r.top - 8) + 'px'; fondolbl.style.opacity = 1;
  }
  function clearAll() {
    ov.style.opacity = 0; sel.style.opacity = 0; fondo.style.opacity = 0; fondolbl.style.opacity = 0;
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
  // ¿qué bloque (hermano de body) ocupa esta Y, muestreando en la columna de contenido?
  function blockAtY(y) {
    var c = contentRect(), sx = c.left + (c.right - c.left) * 0.4;
    var el = document.elementFromPoint(sx, y);
    var leaf = el && el.closest && el.closest('[data-sourcepos]');
    if (leaf) { while (leaf && leaf.parentElement && leaf.parentElement !== document.body) leaf = leaf.parentElement; }
    if (leaf && leaf.parentElement === document.body && isContent(leaf)) return leaf;
    // respaldo geométrico
    var bs = bodyBlocks();
    for (var i = 0; i < bs.length; i++) { var r = bs[i].getBoundingClientRect(); if (y >= r.top && y <= r.bottom) return bs[i]; }
    return null;
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
  function resolve(y) {
    var blocks = bodyBlocks(); if (!blocks.length) return null;
    var b = blockAtY(y);
    if (b) return { prim: blockEntry(b), fondoSection: innerSection(blocks, b) };  // texto de bloque/título → el bloque
    var s = deepestSectionAtY(blocks, y);                                          // hueco dentro de una sección → la sección
    if (s) return { prim: s, fondoSection: null };
    var c = contentRect();                                                         // hueco fuera de toda sección → el documento
    if (y >= c.top && y <= c.bottom) return { prim: docEntry(blocks), fondoSection: null };
    return null;
  }

  function render(box) {
    primary = box.prim; primSection = box.fondoSection || null;
    showFondo(primSection);
    var target = pinned ? sel : ov; (pinned ? ov : sel).style.opacity = 0;
    place(target, primary, 5, 4); showTip(primary); showEdit(primary);
    sendEditor(primary, pinned ? 'selection' : 'block');
  }
  function unpin() { pinned = false; clearAll(); primary = null; primSection = null; clearEditor(); }

  // ---------- interacción base ----------
  function positionGutter() {
    var c = contentRect(), w = (c.right - c.left) * GUT;
    gutter.style.left = (c.right - w) + 'px'; gutter.style.width = w + 'px';
  }
  positionGutter();

  window.addEventListener('mousemove', function (e) {
    if (editing) return;
    if (pinned) {                                  // se mantiene fijado hasta salir del primario (con margen) o Esc
      var r = boxOf(primary);
      var safe = e.target === edit || edit.contains(e.target) ||
        (e.clientX > r.left - 12 && e.clientX < r.right + 60 && e.clientY > r.top - 16 && e.clientY < r.bottom + 14);
      if (!safe) unpin();
      return;
    }
    var c = contentRect();
    var inZone = e.clientX > c.right - (c.right - c.left) * GUT && e.clientX < window.innerWidth &&
                 e.clientY > c.top - 4 && e.clientY < c.bottom + 4;
    if (inZone) { gutter.classList.add('hot'); var box = resolve(e.clientY); if (box) render(box); else clearAll(); }
    else { gutter.classList.remove('hot'); clearAll(); primary = null; primSection = null; clearEditor(); }
  });

  // clic en la franja = fijar
  window.addEventListener('click', function (e) {
    if (editing || e.target === edit || edit.contains(e.target) || (e.target.closest && e.target.closest('.mdi-edid'))) return;
    var c = contentRect();
    var inZone = e.clientX > c.right - (c.right - c.left) * GUT && e.clientY > c.top - 4 && e.clientY < c.bottom + 4;
    if (inZone && primary) { pinned = true; render({ prim: primary, fondoSection: primSection }); }
  });

  // doble-clic (sólo ya fijado) o ✏︎ = editar
  window.addEventListener('dblclick', function (e) {
    if (editing || (e.target.closest && e.target.closest('.mdi-edid'))) return;
    if (pinned && primary) { e.preventDefault(); requestEdit(primary); }
  });
  edit.addEventListener('click', function () { if (primary) requestEdit(primary); });

  window.addEventListener('keydown', function (e) {
    if (editing) return;
    if (e.key === 'Escape' && pinned) unpin();
  });

  window.addEventListener('resize', positionGutter);
  window.addEventListener('scroll', function () {
    positionGutter();
    if (primary) { place(pinned ? sel : ov, primary, 5, 4); showTip(primary); showEdit(primary); if (primSection) showFondo(primSection); }
  }, { passive: true });

  // ---------- edición del fuente ----------
  function requestEdit(en) {
    if (!en || en.kind === 'Documento' || editing) return;
    post({ type: 'inlineEdit', startLine: en.s, endLine: en.e });
  }
  // Hermanos de <body> de en.first..en.last (uno para bloques; varios para una Sección virtual).
  function spanFromTo(first, last) {
    if (first === last) return [first];
    var out = [], n = first;
    while (n) { out.push(n); if (n === last) break; n = n.nextElementSibling; }
    return out;
  }
  // Llamado desde ObjC con el fuente del rango: abre el mini-editor in situ.
  window.macdownOpenInlineEditor = function (s, e, text) {
    if (editing) return;
    var en = primary;
    if (!en || en.s !== s || en.e !== e) {
      var bs = bodyBlocks();
      for (var i = 0; i < bs.length; i++) {
        var L = lines(bs[i]);
        if (L[0] === s) { en = blockEntry(bs[i]); var sec = innerSection(bs, bs[i]); if (sec && sec.s === s && sec.e === e) en = sec; break; }
      }
    }
    if (!en) return;
    editing = true;
    var hide = spanFromTo(en.first, en.last);
    var wrap = document.createElement('div'); wrap.className = 'mdi-edid';
    var ta = document.createElement('textarea'); ta.value = text != null ? text : '';
    var bar = document.createElement('div'); bar.className = 'bar';
    var lab = document.createElement('span');
    lab.textContent = 'editando ' + en.kind + ' · L' + en.s + (en.e !== en.s ? '–' + en.e : '') + ' (markdown fuente)';
    var btns = document.createElement('span');
    var cancel = document.createElement('button'); cancel.className = 'cancel'; cancel.textContent = 'Cancelar';
    var done = document.createElement('button'); done.className = 'done'; done.textContent = 'Hecho';
    btns.appendChild(cancel); btns.appendChild(done); bar.appendChild(lab); bar.appendChild(btns);
    wrap.appendChild(ta); wrap.appendChild(bar);
    hide[0].parentNode.insertBefore(wrap, hide[0]);
    for (var k = 0; k < hide.length; k++) hide[k].style.display = 'none';
    clearAll(); pinned = false;

    function autosize() { ta.style.height = 'auto'; ta.style.height = Math.max(60, ta.scrollHeight) + 'px'; }
    function close() {
      wrap.remove();
      for (var k = 0; k < hide.length; k++) hide[k].style.display = '';
      editing = false;
    }
    ta.addEventListener('input', autosize);
    cancel.onclick = function () { close(); };
    done.onclick = function () { post({ type: 'inlineEditCommit', startLine: en.s, endLine: en.e, text: ta.value }); close(); };
    ta.addEventListener('keydown', function (ev) {
      if (ev.key === 'Enter' && (ev.metaKey || ev.ctrlKey)) { ev.preventDefault(); done.onclick(); }
      else if (ev.key === 'Escape') { ev.preventDefault(); cancel.onclick(); }
    });
    ta.focus(); autosize();
  };

  // ---------- editor → visor ----------
  window.macdownHighlightLines = function (start, end) {
    if (pinned || editing) return;             // no pisar una fijación / edición con el cursor del editor
    if (!start) { primary = null; primSection = null; clearAll(); return; }
    var bs = bodyBlocks(), best = null, bestSpan = 1e9;
    for (var i = 0; i < bs.length; i++) {
      var L = lines(bs[i]);
      if (L[0] <= start && start <= L[1]) { var sp = L[1] - L[0]; if (sp < bestSpan) { bestSpan = sp; best = bs[i]; } }
    }
    if (best) {
      primary = blockEntry(best); primSection = innerSection(bs, best);
      showFondo(primSection); place(ov, primary, 5, 4); showTip(primary); showEdit(primary);
    }
  };
})();
