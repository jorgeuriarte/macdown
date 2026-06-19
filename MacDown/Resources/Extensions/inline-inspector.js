/*
 * MacDown Remix — Inspector de edición inline (M1, EXPERIMENTAL)
 *
 * Porta el modelo de interacción acordado en docs/EDICION-INLINE.md al visor real
 * (WKWebView). A diferencia de los prototipos (docs/prototypes/), aquí el DOM es el
 * HTML PLANO que produce cmark-gfm: hermanos sin <section>, con `data-sourcepos` por
 * bloque. Por eso este script:
 *
 *   1. Deriva el "tipo" de bloque del tagName y el rango de líneas de `data-sourcepos`.
 *   2. Construye las SECCIONES como niveles VIRTUALES (Opción D, ver §7 de la spec):
 *      no crea <section>, las calcula al vuelo desde los headings + sourcepos.
 *   3. Reutiliza el puente existente: postMessage 'block'/'selection' refleja el bloque
 *      en el editor (recuadro / cursor), y redefine `macdownHighlightLines` para que el
 *      editor→visor siga funcionando cuando este inspector sustituye a la selección
 *      conectada clásica.
 *
 * Sólo se inyecta con el flag `experimentalInlineEditing` activo. La EDICIÓN del fuente
 * (abrir el bloque en un mini-editor) es el siguiente hito; aquí el botón ✏︎ / doble-clic
 * sólo destellan el bloque (no editan todavía).
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

  // ---------- color de acento del tema (mismo truco que la selección conectada) ----------
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
  // Devuelve null si idx no cae bajo un heading de ESE nivel (Opción D, proto-secciones).
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

  // Cadena hoja→raíz: bloque + anidamiento DOM real (listas/citas) + secciones virtuales + Documento.
  function chainFor(target) {
    var blocks = bodyBlocks();
    var real = [], n = target;
    while (n && n !== document.body) { if (isContent(n)) real.push(n); n = n.parentElement; }
    if (!real.length) return null;
    var top = real[real.length - 1];           // hijo directo de <body>
    var idx = blocks.indexOf(top);
    var chain = real.map(blockEntry);          // hoja..top (anidamiento DOM real)
    if (idx >= 0) {
      for (var lvl = 6; lvl >= 1; lvl--) {
        var s = sectionAt(blocks, idx, lvl);
        if (s && (s.first !== top || s.last !== top) &&
            !chain.some(function (c) { return c.first === s.first && c.last === s.last; }))
          chain.push(s);
      }
    }
    if (blocks.length) {
      var f = blocks[0], l = blocks[blocks.length - 1];
      chain.push({ first: f, last: l, kind: 'Documento', name: '', s: lines(f)[0], e: lines(l)[1] });
    }
    return chain;
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
      'background:linear-gradient(90deg,transparent,' + CM('16%') + ');border-left:1px dashed ' + CM('40%') + ';opacity:0;}' +
    '#mdi-gutter.on{opacity:1;}' +
    '#mdi-gutter.hot{background:linear-gradient(90deg,transparent,' + CM('32%') + ');border-left-color:' + CM('75%') + ';}' +
    '#mdi-ov{position:fixed;pointer-events:none;z-index:2147483602;border-radius:4px;opacity:0;transition:all .07s ease;' +
      'background:' + CM('8%') + ';box-shadow:inset 0 0 0 1.5px ' + CM('45%') + ';}' +
    '#mdi-sel{position:fixed;pointer-events:none;z-index:2147483603;border-radius:4px;opacity:0;transition:all .07s ease;background-repeat:no-repeat;' +
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
    '#mdi-bc{position:fixed;bottom:0;left:0;right:0;min-height:42px;display:flex;align-items:center;flex-wrap:wrap;gap:2px;' +
      'padding:0 14px;background:#fafbfc;border-top:1px solid #e7e9ec;font:13px/1 system-ui,sans-serif;z-index:2147483607;opacity:0;transition:opacity .12s;' +
      'color:#57606a;}' +
    '#mdi-bc.on{opacity:1;}' +
    '#mdi-bc .mdi-crumb{padding:5px 9px;border-radius:6px;cursor:pointer;color:#57606a;white-space:nowrap;}' +
    '#mdi-bc .mdi-crumb:hover{background:' + CM('14%') + ';color:' + AC + ';}' +
    '#mdi-bc .mdi-crumb.cur{color:#1f2328;font-weight:600;}#mdi-bc .mdi-sep{color:#bbb;}' +
    '#mdi-bc .mdi-lbl{color:#9aa1aa;margin-right:6px;font-size:11px;text-transform:uppercase;letter-spacing:.4px;}' +
    '#mdi-bc .mdi-esc{margin-left:auto;color:#aaa;font-size:11px;}' +
    '.mdi-edid{margin:.4em 0;border:1.5px solid ' + AC + ';border-radius:7px;overflow:hidden;box-shadow:0 4px 14px rgba(0,0,0,.10);}' +
    '.mdi-edid textarea{display:block;width:100%;box-sizing:border-box;border:0;outline:0;resize:vertical;min-height:60px;' +
      'font:13.5px/1.55 ui-monospace,Menlo,monospace;padding:11px 13px;color:inherit;background:transparent;}' +
    '.mdi-edid .bar{display:flex;justify-content:space-between;align-items:center;background:' + CM('7%') + ';' +
      'border-top:1px solid ' + CM('22%') + ';padding:5px 8px 5px 11px;font:11px system-ui,sans-serif;color:#8a929c;}' +
    '.mdi-edid .bar button{font:600 12px system-ui,sans-serif;border:0;border-radius:5px;padding:5px 10px;cursor:pointer;}' +
    '.mdi-edid .done{background:' + AC + ';color:#fff;}.mdi-edid .cancel{background:' + CM('16%') + ';color:inherit;margin-right:6px;}';
  (document.head || document.documentElement).appendChild(st);

  function mk(id, tag) { var e = document.createElement(tag || 'div'); e.id = id; document.body.appendChild(e); return e; }
  var gutter = mk('mdi-gutter'), ov = mk('mdi-ov'), sel = mk('mdi-sel'), tip = mk('mdi-tip');
  var edit = mk('mdi-edit', 'button'); edit.title = 'Editar este bloque'; edit.textContent = '✏︎';
  var bc = mk('mdi-bc'); bc.innerHTML = '<span class="mdi-lbl">Bloque</span>';

  // ---------- estado ----------
  var chain = [], level = 0, pinned = false, current = null, GUT = 0.16, lastSent = '', editing = false;

  function contentRect() {
    var bs = bodyBlocks(), l = 1e9, r = -1e9, t = 1e9, b = -1e9;
    for (var i = 0; i < bs.length; i++) {
      var q = bs[i].getBoundingClientRect();
      if (q.width) { l = Math.min(l, q.left); r = Math.max(r, q.right); t = Math.min(t, q.top); b = Math.max(b, q.bottom); }
    }
    if (l > r) { l = 0; r = window.innerWidth; t = 0; b = window.innerHeight; }
    return { left: l, right: r, top: t, bottom: b };
  }

  function place(boxEl, en, pad) {
    var r = boxOf(en);
    boxEl.style.left = (r.left - pad) + 'px'; boxEl.style.top = (r.top - pad) + 'px';
    boxEl.style.width = (r.right - r.left + 2 * pad) + 'px'; boxEl.style.height = (r.bottom - r.top + 2 * pad) + 'px';
    boxEl.style.opacity = 1;
  }
  function showTip(en) {
    tip.innerHTML = '<b>' + (ICON[en.kind] || '') + ' ' + en.kind + '</b><span>L' +
      en.s + (en.e !== en.s ? '–' + en.e : '') + (en.name ? ' · ' + en.name : '') + '</span>';
    var r = boxOf(en);
    tip.style.left = (r.left - 6) + 'px'; tip.style.top = Math.max(4, r.top - 26) + 'px'; tip.style.opacity = 1;
  }
  function showEdit(en) {
    if (en.kind === 'Documento') { edit.classList.remove('on'); return; }  // no se edita el doc entero inline
    var r = boxOf(en);
    edit.style.left = (r.right - 4 - 26) + 'px'; edit.style.top = Math.max(6, r.top - 13) + 'px'; edit.classList.add('on');
  }
  // refleja el bloque/sección actual en el EDITOR (recuadro y, si type='selection', cursor)
  function sendEditor(en, type) {
    if (!en) return;
    var key = type + ':' + en.s + ':' + en.e;
    if (type === 'block' && key === lastSent) return;
    lastSent = key;
    post({ type: type, startLine: en.s, endLine: en.e });
  }
  function clearEditor() { lastSent = ''; post({ type: 'block', startLine: 0, endLine: 0 }); }

  function renderBC() {
    var old = bc.querySelectorAll('.mdi-crumb,.mdi-sep,.mdi-esc');
    for (var k = 0; k < old.length; k++) old[k].remove();
    var top = chain.slice().reverse();
    top.forEach(function (en, i) {
      var c = document.createElement('span');
      c.className = 'mdi-crumb' + ((chain.length - 1 - level) === i ? ' cur' : '');
      c.textContent = (ICON[en.kind] || '') + ' ' + en.kind + (en.name ? ' ' + en.name : '');
      c.onmouseenter = function () {
        level = chain.length - 1 - i; current = chain[level];
        place(pinned ? sel : ov, current, 6); showTip(current); showEdit(current);
        sendEditor(current, pinned ? 'selection' : 'block'); renderBC();
      };
      bc.appendChild(c);
      if (i < top.length - 1) { var s = document.createElement('span'); s.className = 'mdi-sep'; s.textContent = '›'; bc.appendChild(s); }
    });
    if (pinned) { var e = document.createElement('span'); e.className = 'mdi-esc'; e.textContent = 'Esc para soltar'; bc.appendChild(e); }
  }

  function hover(leaf) {
    var ch = chainFor(leaf); if (!ch) return;
    chain = ch; if (level >= chain.length) level = 0;
    current = chain[Math.min(level, chain.length - 1)];
    place(ov, current, 6); showTip(current); showEdit(current);
    bc.classList.add('on'); gutter.classList.add('hot'); renderBC();
    sendEditor(current, 'block');
  }
  function pin() {
    pinned = true; ov.style.opacity = 0; gutter.classList.add('hot'); bc.classList.add('on');
    place(sel, current, 6); showTip(current); showEdit(current); renderBC();
    sendEditor(current, 'selection');
  }
  function unpin() {
    pinned = false; sel.style.opacity = 0; ov.style.opacity = 0; tip.style.opacity = 0;
    edit.classList.remove('on'); gutter.classList.remove('hot'); bc.classList.remove('on');
    current = null; clearEditor();
  }
  function refresh() { place(sel, current, 6); showTip(current); showEdit(current); renderBC(); sendEditor(current, 'selection'); }

  function siblingBlock(en, dir) {
    var el = en.first, n = dir > 0 ? el.nextElementSibling : el.previousElementSibling;
    while (n) { if (isContent(n)) return n; n = dir > 0 ? n.nextElementSibling : n.previousElementSibling; }
    return null;
  }

  // ---------- gutter / hover ----------
  function positionGutter() {
    var c = contentRect(), w = (c.right - c.left) * GUT;
    gutter.style.left = (c.right - w) + 'px'; gutter.style.width = w + 'px';
  }
  positionGutter(); gutter.classList.add('on');

  var leaveTimer = null;
  function inSafeZone(x, y, t) {
    if (t === edit || edit.contains(t) || bc.contains(t)) return true;
    if (!current) return false;
    var r = boxOf(current);
    return x > r.left - 10 && x < r.right + 60 && y > r.top - 18 && y < r.bottom + 16;
  }
  window.addEventListener('mousemove', function (e) {
    if (editing) return;
    if (pinned) {
      if (inSafeZone(e.clientX, e.clientY, e.target)) { if (leaveTimer) { clearTimeout(leaveTimer); leaveTimer = null; } }
      else if (!leaveTimer) { leaveTimer = setTimeout(function () { unpin(); leaveTimer = null; }, 160); }
      return;
    }
    var c = contentRect();
    var inZone = e.clientX > c.right - (c.right - c.left) * GUT && e.clientX < window.innerWidth &&
                 e.clientY > c.top - 4 && e.clientY < c.bottom + 4;
    if (inZone) {
      var el = document.elementFromPoint(c.left + (c.right - c.left) * 0.4, e.clientY);
      var leaf = el && el.closest && el.closest('[data-sourcepos]');
      if (leaf) { if (!current || !chainHas(leaf, current)) level = 0; hover(leaf); }
    } else if (!pinned) {
      ov.style.opacity = 0; tip.style.opacity = 0; edit.classList.remove('on');
      gutter.classList.remove('hot'); bc.classList.remove('on'); clearEditor();
    }
  });
  function chainHas(leaf, en) {
    var ch = chainFor(leaf); if (!ch) return false;
    return ch.some(function (c) { return c.first === en.first && c.last === en.last; });
  }

  // clic en la franja = fijar
  window.addEventListener('click', function (e) {
    if (editing) return;
    if (e.target === edit || edit.contains(e.target) || bc.contains(e.target)) return;
    var c = contentRect();
    var inZone = e.clientX > c.right - (c.right - c.left) * GUT && e.clientY > c.top - 4 && e.clientY < c.bottom + 4;
    if (inZone && current) pin();
  });

  // doble-clic (sólo ya fijado) o ✏︎ = editar  [sub-step 2: aquí sólo destella]
  window.addEventListener('dblclick', function (e) {
    if (editing) return;
    if (e.target === edit || edit.contains(e.target) || bc.contains(e.target)) return;
    if (pinned && current) { e.preventDefault(); requestEdit(current); }
  });
  edit.addEventListener('click', function () { if (current) requestEdit(current); });
  function requestEdit(en) {
    if (!en || en.kind === 'Documento' || editing) return;
    // Pide a ObjC el fuente Markdown del rango; responde con macdownOpenInlineEditor(...).
    post({ type: 'inlineEdit', startLine: en.s, endLine: en.e });
  }

  // Hermanos de <body> de en.first..en.last (un solo elemento para bloques normales;
  // varios para una Sección virtual, que abarca hermanos planos consecutivos).
  function spanFromTo(first, last) {
    if (first === last) return [first];
    var out = [], n = first;
    while (n) { out.push(n); if (n === last) break; n = n.nextElementSibling; }
    return out;
  }

  // Llamado desde ObjC con el fuente del bloque: abre el mini-editor (textarea) in situ.
  window.macdownOpenInlineEditor = function (s, e, text) {
    if (editing) return;
    var en = current;
    if (!en || en.s !== s || en.e !== e) {            // localizar por rango si hiciera falta
      var bs = bodyBlocks();
      for (var i = 0; i < bs.length; i++) {
        var L = lines(bs[i]);
        if (L[0] === s) { var ch = chainFor(bs[i]); en = ch && ch[0]; break; }
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
    sel.style.opacity = 0; ov.style.opacity = 0; tip.style.opacity = 0;
    edit.classList.remove('on'); gutter.classList.remove('hot');

    function autosize() { ta.style.height = 'auto'; ta.style.height = Math.max(60, ta.scrollHeight) + 'px'; }
    function close() {
      wrap.remove();
      for (var k = 0; k < hide.length; k++) hide[k].style.display = '';
      editing = false;
    }
    ta.addEventListener('input', autosize);
    cancel.onclick = function () { close(); };
    done.onclick = function () {
      // El re-render reemplazará todo el DOM; cerramos igualmente por si no cambia nada.
      post({ type: 'inlineEditCommit', startLine: en.s, endLine: en.e, text: ta.value });
      close();
    };
    ta.addEventListener('keydown', function (ev) {
      if (ev.key === 'Enter' && (ev.metaKey || ev.ctrlKey)) { ev.preventDefault(); done.onclick(); }
      else if (ev.key === 'Escape') { ev.preventDefault(); cancel.onclick(); }
    });
    ta.focus(); autosize();
  };

  // teclado: flechas sólo una vez fijado
  window.addEventListener('keydown', function (e) {
    if (editing) return;                       // el mini-editor gestiona sus teclas
    if (e.key === 'Escape' && pinned) { unpin(); return; }
    if (!pinned || !current) return;
    if (e.key === 'ArrowLeft') { level = Math.min(level + 1, chain.length - 1); current = chain[level]; refresh(); e.preventDefault(); }
    else if (e.key === 'ArrowRight') { level = Math.max(level - 1, 0); current = chain[level]; refresh(); e.preventDefault(); }
    else if (e.key === 'ArrowUp') { var u = siblingBlock(current, -1); if (u) { chain = chainFor(u) || chain; level = Math.min(level, chain.length - 1); current = chain[0]; refresh(); } e.preventDefault(); }
    else if (e.key === 'ArrowDown') { var d = siblingBlock(current, 1); if (d) { chain = chainFor(d) || chain; level = Math.min(level, chain.length - 1); current = chain[0]; refresh(); } e.preventDefault(); }
  });

  window.addEventListener('resize', positionGutter);
  window.addEventListener('scroll', function () {
    positionGutter();
    if (current) { place(pinned ? sel : ov, current, 6); showTip(current); showEdit(current); }
  }, { passive: true });

  // ---------- editor → visor (reemplaza a la selección conectada cuando el flag está activo) ----------
  window.macdownHighlightLines = function (start, end) {
    if (pinned) return;                       // no pisar una fijación con el cursor del editor
    if (!start) { current = null; ov.style.opacity = 0; tip.style.opacity = 0; edit.classList.remove('on'); return; }
    var bs = bodyBlocks(), best = null, bestSpan = 1e9;
    for (var i = 0; i < bs.length; i++) {
      var L = lines(bs[i]);
      if (L[0] <= start && start <= L[1]) { var sp = L[1] - L[0]; if (sp < bestSpan) { bestSpan = sp; best = bs[i]; } }
    }
    if (best) {
      var ch = chainFor(best); if (!ch) return;
      chain = ch; level = 0; current = chain[0];
      place(ov, current, 6); showTip(current); showEdit(current);
    }
  };
})();
