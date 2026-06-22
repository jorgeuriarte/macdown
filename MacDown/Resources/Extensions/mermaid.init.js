// init mermaid (v10/v11 async API) con DEGRADACIÓN ELEGANTE.
//
// MacDown emite bloques ```mermaid como <pre><code class="language-mermaid">…</code></pre>
// (con cmark-gfm; hoedown los envolvía en un <div>). Renderizamos cada bloque a SVG y
// sustituimos SOLO ese bloque. mermaid >= 10 hizo render() asíncrono (Promise<{svg,
// bindFunctions}>).
//
// Robustez: si el motor no está disponible o un diagrama es inválido, NO se rompe el resto
// del documento — se sustituye ESE bloque por un aviso claro en su sitio. El mensaje sirve
// además de diagnóstico (script no cargado vs. error de render).

(function () {
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

  // Nodo a sustituir por bloque mermaid: el <pre>, o el <div> envolvente si lo hubiera
  // (estructura de hoedown). Con cmark-gfm no hay <div>, así que NO subimos a ciegas.
  function targetFor(code) {
    var container = code.parentElement;            // <pre>
    if (container && container.tagName === "PRE" && container.parentElement &&
        container.parentElement.tagName === "DIV" && container.parentElement.childElementCount === 1) {
      return container.parentElement;
    }
    return container;
  }

  // Sustituye `target` por una caja de aviso (no rompe el resto del documento).
  function notice(target, title, detail, warn) {
    if (!target || !target.parentNode) return;
    var box = document.createElement("div");
    box.setAttribute("style",
      "margin:.6em 0;padding:9px 12px;border-radius:6px;font:13px/1.5 system-ui,-apple-system,sans-serif;" +
      "border:1px solid " + (warn ? "rgba(212,167,44,.5)" : "rgba(248,81,73,.45)") + ";" +
      "background:" + (warn ? "rgba(255,212,0,.07)" : "rgba(248,81,73,.06)") + ";color:#6a737d;");
    var h = document.createElement("div");
    h.setAttribute("style", "font-weight:600;color:" + (warn ? "#9a6700" : "#cf222e") + ";");
    h.textContent = title;
    box.appendChild(h);
    if (detail) {
      var d = document.createElement("div");
      d.setAttribute("style", "margin-top:3px;font:12px/1.45 ui-monospace,Menlo,monospace;white-space:pre-wrap;opacity:.85;");
      d.textContent = String(detail).slice(0, 500);
      box.appendChild(d);
    }
    target.parentNode.replaceChild(box, target);
  }

  // Tema del diagrama según el fondo real del visor (oscuro/claro), sin listas de nombres.
  function prefersDarkDiagram() {
    function bgOf(el) { return el ? window.getComputedStyle(el).backgroundColor : null; }
    var bg = bgOf(document.body);
    if (!bg || bg === "transparent" || bg === "rgba(0, 0, 0, 0)") bg = bgOf(document.documentElement);
    var m = bg && bg.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
    if (!m) return false;
    var r = +m[1], g = +m[2], b = +m[3];
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255 < 0.5;
  }

  function renderAll() {
    var nodes = document.querySelectorAll("code.language-mermaid");
    if (!nodes.length) return;

    var mermaid = resolveMermaid();
    if (!mermaid) {                                 // el motor no se cargó en el visor
      Array.prototype.forEach.call(nodes, function (code) {
        notice(targetFor(code), "⚠ Diagrama Mermaid no disponible",
               "El motor de diagramas no se cargó en el visor.", true);
      });
      return;
    }

    try {
      mermaid.initialize({
        startOnLoad: false, securityLevel: "loose",
        theme: prefersDarkDiagram() ? "dark" : "forest",
        flowchart: { useMaxWidth: true }
      });
    } catch (e) { /* el error real aflorará en el render */ }

    Array.prototype.forEach.call(nodes, function (code, i) {
      var source = code.textContent || code.innerText;
      var target = targetFor(code);
      if (!target || !target.parentNode) return;
      var p;
      try { p = mermaid.render("mmdGraph" + i, source); }
      catch (e) { notice(target, "⚠ Diagrama Mermaid inválido", (e && (e.message || e.str)) || String(e)); return; }
      Promise.resolve(p).then(function (result) {
        var tmp = document.createElement("div");
        tmp.innerHTML = result.svg;
        var svgNode = tmp.firstElementChild || tmp.firstChild;
        if (!svgNode) { notice(target, "⚠ Mermaid no produjo diagrama", null); return; }
        target.parentNode.replaceChild(svgNode, target);
        if (typeof result.bindFunctions === "function") result.bindFunctions(svgNode);
      }).catch(function (error) {
        notice(target, "⚠ Diagrama Mermaid inválido", (error && (error.message || error.str)) || String(error));
      });
    });
  }

  if (document.readyState === "complete") renderAll();
  else window.addEventListener("load", renderAll, false);
})();
