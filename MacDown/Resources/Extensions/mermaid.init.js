// init mermaid (v10/v11 async API)
//
// MacDown emits fenced ```mermaid blocks as <div><pre><code class="language-mermaid">…</code></pre></div>
// (see hoedown_html_patch.c). We read each block's source, render it to SVG with mermaid, and
// replace the wrapping <div> with the result. mermaid >= 10 made render() asynchronous
// (it returns a Promise resolving to { svg, bindFunctions }), so this is promise-based.

(function () {
  if (typeof mermaid === "undefined") {
    return;
  }

  // Pick a mermaid theme that contrasts with the current preview background.
  // The HTML style's CSS is embedded in <head> and applied by the time this
  // end-of-body script runs, so we can read the real rendered background color.
  // This works for any dark style (Solarized Dark, Clearness Dark, custom) with
  // no theme-name lists to maintain.
  function prefersDarkDiagram() {
    function bgOf(el) {
      return el ? window.getComputedStyle(el).backgroundColor : null;
    }
    var bg = bgOf(document.body);
    if (!bg || bg === "transparent" || bg === "rgba(0, 0, 0, 0)") {
      bg = bgOf(document.documentElement);
    }
    var m = bg && bg.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
    if (!m) {
      return false;                                 // unknown → treat as light
    }
    var r = +m[1], g = +m[2], b = +m[3];
    var luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return luminance < 0.5;
  }

  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "loose",
    theme: prefersDarkDiagram() ? "dark" : "forest",
    flowchart: { useMaxWidth: true }
  });

  var renderAll = function () {
    var nodes = document.querySelectorAll("code.language-mermaid");
    Array.prototype.forEach.call(nodes, function (code, i) {
      var graphSource = code.textContent || code.innerText;

      var container = code.parentElement;            // <pre>
      // container es el <pre>. Sustituimos SOLO ese bloque por el diagrama, o el
      // <div> que lo envuelve si existe y contiene únicamente el <pre> (estructura
      // de hoedown). Con cmark-gfm NO hay <div> envolvente, así que subir al padre
      // a ciegas y reescribir su innerHTML borraría el resto del preview.
      var target = container;
      if (container && container.tagName === "PRE" &&
          container.parentElement &&
          container.parentElement.tagName === "DIV" &&
          container.parentElement.childElementCount === 1) {
        target = container.parentElement;            // <div> envolvente (hoedown)
      }
      if (!target || !target.parentNode) {
        return;
      }

      mermaid.render("mmdGraph" + i, graphSource).then(function (result) {
        var tmp = document.createElement("div");
        tmp.innerHTML = result.svg;
        var svgNode = tmp.firstElementChild || tmp.firstChild;
        if (!svgNode) {
          return;
        }
        target.parentNode.replaceChild(svgNode, target);
        if (typeof result.bindFunctions === "function") {
          result.bindFunctions(svgNode);
        }
      }).catch(function (error) {
        console.error("mermaid render error:", error);
      });
    });
  };

  if (document.readyState === "complete") {
    renderAll();
  } else {
    window.addEventListener("load", renderAll, false);
  }
})();
