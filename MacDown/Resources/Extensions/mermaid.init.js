// init mermaid (v10/v11 async API) con DEGRADACIÓN ELEGANTE y soporte de la edición inline.
//
// MacDown emite bloques ```mermaid como <pre data-sourcepos="…"><code class="language-mermaid">
// …</code></pre>. Renderizamos cada bloque a SVG y sustituimos SOLO ese bloque. mermaid>=10
// hizo render() asíncrono (Promise<{svg, bindFunctions}>).
//
//  - Robustez: si el motor no está o un diagrama es inválido, NO se rompe el resto del
//    documento; se sustituye ESE bloque por un aviso claro en su sitio.
//  - Edición inline: el diagrama renderizado CONSERVA el `data-sourcepos` del bloque
//    original (en un <div> contenedor), para que el inspector pueda seleccionarlo/editar
//    su fuente. Sin esto, el <svg> "no es un nodo" y no se puede editar.
//  - Vista previa: se expone `window.macdownRenderMermaid(root)` para renderizar también
//    los bloques mermaid del fragmento que muestra el mini-editor.

(function () {
  var engine = null, inited = false, seq = 0;

  // El bundle v11 (esbuild) hace globalThis.mermaid = …default. Por si acaso, resolvemos
  // también desde el namespace interno del bundle.
  function resolveMermaid() {
    try { if (typeof mermaid !== "undefined" && mermaid && typeof mermaid.initialize === "function") return mermaid; } catch (e) {}
    try {
      if (typeof __esbuild_esm_mermaid_nm !== "undefined" && __esbuild_esm_mermaid_nm) {
        var ns = __esbuild_esm_mermaid_nm.mermaid;
        if (ns) {
          if (typeof ns.initialize === "function") return ns;
          if (ns.default && typeof ns.default.initialize === "function") return ns.default;
        }
      }
    } catch (e) {}
    return null;
  }
  function prefersDarkDiagram() {
    function bgOf(el) { return el ? window.getComputedStyle(el).backgroundColor : null; }
    var bg = bgOf(document.body);
    if (!bg || bg === "transparent" || bg === "rgba(0, 0, 0, 0)") bg = bgOf(document.documentElement);
    var m = bg && bg.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
    if (!m) return false;
    var r = +m[1], g = +m[2], b = +m[3];
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255 < 0.5;
  }
  function ensureEngine() {
    if (!engine) engine = resolveMermaid();
    if (engine && !inited) {
      try {
        engine.initialize({ startOnLoad: false, securityLevel: "loose",
          theme: prefersDarkDiagram() ? "dark" : "forest", flowchart: { useMaxWidth: true } });
      } catch (e) {}
      inited = true;
    }
    return engine;
  }

  // Nodo a sustituir: el <pre>, o el <div> envolvente de hoedown si lo hubiera.
  function targetFor(code) {
    var c = code.parentElement;                    // <pre>
    if (c && c.tagName === "PRE" && c.parentElement && c.parentElement.tagName === "DIV" &&
        c.parentElement.childElementCount === 1) return c.parentElement;
    return c;
  }
  // Contenedor de bloque que CONSERVA el data-sourcepos del original (para la edición inline).
  function holderFor(target, child) {
    var holder = document.createElement("div");
    holder.className = "mdi-mermaid";
    var sp = target && target.getAttribute && target.getAttribute("data-sourcepos");
    if (sp) holder.setAttribute("data-sourcepos", sp);
    if (child) holder.appendChild(child);
    return holder;
  }
  function notice(target, title, detail, warn) {
    if (!target || !target.parentNode) return;
    var box = holderFor(target, null);
    box.setAttribute("style",
      "margin:.6em 0;padding:9px 12px;border-radius:6px;font:13px/1.5 system-ui,-apple-system,sans-serif;" +
      "border:1px solid " + (warn ? "rgba(212,167,44,.5)" : "rgba(248,81,73,.45)") + ";" +
      "background:" + (warn ? "rgba(255,212,0,.07)" : "rgba(248,81,73,.06)") + ";color:#6a737d;");
    var h = document.createElement("div");
    h.setAttribute("style", "font-weight:600;color:" + (warn ? "#9a6700" : "#cf222e") + ";");
    h.textContent = title; box.appendChild(h);
    if (detail) {
      var d = document.createElement("div");
      d.setAttribute("style", "margin-top:3px;font:12px/1.45 ui-monospace,Menlo,monospace;white-space:pre-wrap;opacity:.85;");
      d.textContent = String(detail).slice(0, 500); box.appendChild(d);
    }
    target.parentNode.replaceChild(box, target);
  }

  // Renderiza los bloques mermaid bajo `root` (document por defecto; el fragmento de la
  // Vista previa cuando lo llama el inspector).
  function renderAll(root) {
    var scope = root || document;
    var nodes = scope.querySelectorAll("code.language-mermaid");
    if (!nodes.length) return;
    var m = ensureEngine();
    if (!m) {
      Array.prototype.forEach.call(nodes, function (code) {
        notice(targetFor(code), "⚠ Diagrama Mermaid no disponible", "El motor de diagramas no se cargó en el visor.", true);
      });
      return;
    }
    Array.prototype.forEach.call(nodes, function (code) {
      var source = code.textContent || code.innerText;
      var target = targetFor(code);
      if (!target || !target.parentNode) return;
      var id = "mmdGraph" + (seq++);
      var p;
      try { p = m.render(id, source); }
      catch (e) { notice(target, "⚠ Diagrama Mermaid inválido", (e && (e.message || e.str)) || String(e)); return; }
      Promise.resolve(p).then(function (result) {
        var tmp = document.createElement("div"); tmp.innerHTML = result.svg;
        var svgNode = tmp.firstElementChild || tmp.firstChild;
        if (!svgNode) { notice(target, "⚠ Mermaid no produjo diagrama", null); return; }
        if (!target.parentNode) return;
        var holder = holderFor(target, svgNode);   // conserva data-sourcepos → editable
        target.parentNode.replaceChild(holder, target);
        if (typeof result.bindFunctions === "function") result.bindFunctions(svgNode);
      }).catch(function (error) {
        notice(target, "⚠ Diagrama Mermaid inválido", (error && (error.message || error.str)) || String(error));
      });
    });
  }

  // Hook para la Vista previa del mini-editor (renderiza mermaid del fragmento).
  window.macdownRenderMermaid = function (root) { try { renderAll(root); } catch (e) {} };

  if (document.readyState === "complete") renderAll(document);
  else window.addEventListener("load", function () { renderAll(document); }, false);
})();
