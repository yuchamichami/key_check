// Normalize only identifiable DOM keyboard events. Never treat IME Process/229
// or composition text as proof that a particular physical key was pressed.
(function (root) {
  const aliases = {
    Eisu: 'Lang2', Alphanumeric: 'Lang2', EisuToggle: 'Lang2',
    Hiragana: 'Lang4', Katakana: 'Lang3', HiraganaKatakana: 'KanaMode',
    KanaMode: 'KanaMode', Convert: 'Convert', NonConvert: 'NonConvert',
    ZenkakuHankaku: 'Lang5',
  };
  function resolve(event, knownCodes, isMac = false) {
    if (event.code && Object.prototype.hasOwnProperty.call(knownCodes, event.code)) return event.code;
    if (aliases[event.key]) return aliases[event.key];
    if (isMac && event.key === 'KanjiMode') return 'Lang1';
    // These legacy values identify conversion keys, unlike 229 (generic IME).
    if (!event.code || event.code === 'Unidentified') {
      if (event.keyCode === 28) return 'Convert';
      if (event.keyCode === 29) return 'NonConvert';
    }
    return event.code && event.code !== 'Unidentified' ? event.code : (event.key || 'Unidentified');
  }
  const api = { resolve };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.KeyCheckKeyboardInput = api;
})(typeof window !== 'undefined' ? window : globalThis);
