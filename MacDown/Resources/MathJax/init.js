(function () {

MathJax.Hub.Config({
	'showProcessingMessages': false,
	'messageStyle': 'none'
});

// WebView legacy: puente windowScriptObject.
if (typeof MathJaxListener !== 'undefined') {
	MathJax.Hub.Register.StartupHook('End', function () {
		MathJaxListener.invokeCallbackForKey_('End');
	});
}

// WKWebView: puente genérico macdown (enrutado por type).
if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.macdown) {
	MathJax.Hub.Register.StartupHook('End', function () {
		window.webkit.messageHandlers.macdown.postMessage({type: 'mathjaxDone'});
	});
}

})();
