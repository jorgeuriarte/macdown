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

  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "loose",
    theme: "forest",
    flowchart: { useMaxWidth: true }
  });

  var renderAll = function () {
    var nodes = document.querySelectorAll("code.language-mermaid");
    Array.prototype.forEach.call(nodes, function (code, i) {
      var graphSource = code.textContent || code.innerText;

      var container = code.parentElement;            // <pre>
      if (container && container.tagName === "PRE") {
        container = container.parentElement;         // wrapping <div>
      }
      if (!container) {
        return;
      }

      mermaid.render("mmdGraph" + i, graphSource).then(function (result) {
        container.innerHTML = result.svg;
        if (typeof result.bindFunctions === "function") {
          result.bindFunctions(container);
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
