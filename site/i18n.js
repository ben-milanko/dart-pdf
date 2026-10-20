/*
 * DartPDF site i18n — lightweight client-side localization.
 *
 * English is the source of truth and lives natively in the HTML, so the page
 * renders fully without JavaScript and without any fetch. Other locales are
 * lazy-loaded from /i18n/<locale>.json and applied over the DOM via data-i18n
 * attributes. The chosen locale is persisted in localStorage; the first visit
 * falls back to the browser's preferred language.
 *
 * Markup contract:
 *   data-i18n="key"            -> element.textContent = t(key)
 *   data-i18n-html="key"       -> element.innerHTML  = t(key)   (trusted, our JSON)
 *   data-i18n-attr="a:key;b:k" -> element.setAttribute(a, t(key)) ...
 *   data-i18n-switcher         -> the language <select> is injected here
 */
(function () {
  'use strict';

  // locale code -> native display name. Order defines the dropdown order.
  var LOCALES = [
    ['en', 'English'],
    ['ar', 'العربية'],
    ['de', 'Deutsch'],
    ['es', 'Español'],
    ['fr', 'Français'],
    ['hi', 'हिन्दी'],
    ['id', 'Bahasa Indonesia'],
    ['it', 'Italiano'],
    ['ja', '日本語'],
    ['ko', '한국어'],
    ['nl', 'Nederlands'],
    ['pl', 'Polski'],
    ['pt', 'Português'],
    ['ru', 'Русский'],
    ['th', 'ไทย'],
    ['tr', 'Türkçe'],
    ['uk', 'Українська'],
    ['vi', 'Tiếng Việt'],
    ['zh', '简体中文'],
    ['zh-Hant', '繁體中文']
  ];
  var SUPPORTED = LOCALES.map(function (l) { return l[0]; });
  var RTL = { ar: true };
  var STORE_KEY = 'dartpdf_lang';

  var cache = {};                       // locale -> dictionary
  var scriptBase = currentScriptDir();  // dir this script was loaded from

  function currentScriptDir() {
    var s = document.currentScript;
    var src = s && s.src ? s.src : '';
    return src.replace(/[^/]*$/, '');    // strip filename, keep trailing slash
  }

  // Map an arbitrary BCP-47 tag (e.g. "pt-BR", "zh-TW") to a supported code.
  function normalize(tag) {
    if (!tag) return null;
    tag = tag.toLowerCase();
    if (tag.indexOf('zh') === 0) {
      if (/hant|tw|hk|mo/.test(tag)) return 'zh-Hant';
      return 'zh';
    }
    var base = tag.split('-')[0];
    return SUPPORTED.indexOf(base) !== -1 ? base : null;
  }

  function detect() {
    // Explicit ?lang= override wins and is remembered (shareable localized links).
    try {
      var q = new URLSearchParams(location.search).get('lang');
      if (q) {
        var nq = SUPPORTED.indexOf(q) !== -1 ? q : normalize(q);
        if (nq) { persist(nq); return nq; }
      }
    } catch (e) {}
    var saved = null;
    try { saved = localStorage.getItem(STORE_KEY); } catch (e) {}
    if (saved && SUPPORTED.indexOf(saved) !== -1) return saved;
    var prefs = navigator.languages || [navigator.language];
    for (var i = 0; i < prefs.length; i++) {
      var n = normalize(prefs[i]);
      if (n) return n;
    }
    return 'en';
  }

  function persist(loc) {
    try { localStorage.setItem(STORE_KEY, loc); } catch (e) {}
  }

  function fetchDict(loc) {
    // English is native in the HTML, but switching *back* to English from
    // another locale must actively restore the English strings, so en.json is
    // fetched and applied like any other locale (it holds every key).
    if (cache[loc]) return Promise.resolve(cache[loc]);
    return fetch(scriptBase + 'i18n/' + loc + '.json', { cache: 'no-cache' })
      .then(function (r) { return r.ok ? r.json() : {}; })
      .then(function (d) { cache[loc] = d; return d; })
      .catch(function () { return {}; });
  }

  function applyDict(dict) {
    var i, el, nodes;

    nodes = document.querySelectorAll('[data-i18n]');
    for (i = 0; i < nodes.length; i++) {
      el = nodes[i];
      var v = dict[el.getAttribute('data-i18n')];
      if (v != null) el.textContent = v;
    }

    nodes = document.querySelectorAll('[data-i18n-html]');
    for (i = 0; i < nodes.length; i++) {
      el = nodes[i];
      var h = dict[el.getAttribute('data-i18n-html')];
      if (h != null) el.innerHTML = h;
    }

    nodes = document.querySelectorAll('[data-i18n-attr]');
    for (i = 0; i < nodes.length; i++) {
      el = nodes[i];
      var spec = el.getAttribute('data-i18n-attr').split(';');
      for (var j = 0; j < spec.length; j++) {
        var pair = spec[j].split(':');
        if (pair.length !== 2) continue;
        var av = dict[pair[1].trim()];
        if (av != null) el.setAttribute(pair[0].trim(), av);
      }
    }
  }

  function apply(loc, dict) {
    var root = document.documentElement;
    root.setAttribute('lang', loc);
    root.setAttribute('dir', RTL[loc] ? 'rtl' : 'ltr');
    applyDict(dict);
    var sel = document.getElementById('langSelect');
    if (sel) sel.value = loc;
  }

  function setLocale(loc) {
    persist(loc);
    fetchDict(loc).then(function (dict) { apply(loc, dict); });
  }

  function buildSwitcher() {
    var holders = document.querySelectorAll('[data-i18n-switcher]');
    if (!holders.length) return;

    for (var h = 0; h < holders.length; h++) {
      var holder = holders[h];
      if (holder.querySelector('.lang-switch')) continue;

      var wrap = document.createElement('label');
      wrap.className = 'lang-switch';
      wrap.setAttribute('aria-label', 'Language');

      var icon = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      icon.setAttribute('viewBox', '0 0 24 24');
      icon.setAttribute('width', '17');
      icon.setAttribute('height', '17');
      icon.setAttribute('fill', 'none');
      icon.setAttribute('stroke', 'currentColor');
      icon.setAttribute('stroke-width', '1.8');
      icon.innerHTML = '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.6 2.5 15.4 0 18M12 3c-2.5 2.6-2.5 15.4 0 18" stroke-linecap="round"/>';

      var sel = document.createElement('select');
      sel.id = 'langSelect';
      sel.className = 'lang-select';
      for (var i = 0; i < LOCALES.length; i++) {
        var opt = document.createElement('option');
        opt.value = LOCALES[i][0];
        opt.textContent = LOCALES[i][1];
        sel.appendChild(opt);
      }
      sel.addEventListener('change', function (e) { setLocale(e.target.value); });

      wrap.appendChild(icon);
      wrap.appendChild(sel);
      holder.appendChild(wrap);
    }
  }

  function injectStyles() {
    var css =
      '.lang-switch{position:relative;display:inline-flex;align-items:center;gap:6px;' +
      'color:var(--ink-soft,#3c4043);border:1px solid var(--line,#e7ebee);border-radius:999px;' +
      'padding:0 8px 0 12px;height:38px;background:rgba(255,255,255,.6);cursor:pointer;font-family:inherit}' +
      '.lang-switch:hover{border-color:var(--tint,#c6e3f8)}' +
      '.lang-switch>svg{flex:none;opacity:.75;pointer-events:none}' +
      '.lang-select{appearance:none;-webkit-appearance:none;border:0;background:transparent;' +
      'font:inherit;font-weight:600;font-size:14px;color:inherit;padding:0 18px 0 2px;height:100%;' +
      'cursor:pointer;outline:none;max-width:9.5rem;text-overflow:ellipsis}' +
      '.lang-switch::after{content:"";position:absolute;right:11px;top:50%;width:7px;height:7px;' +
      'border-right:2px solid currentColor;border-bottom:2px solid currentColor;opacity:.55;' +
      'transform:translateY(-70%) rotate(45deg);pointer-events:none}' +
      '.lang-select option{color:#202124}' +
      '[dir="rtl"] .lang-switch{padding:0 12px 0 8px}' +
      '[dir="rtl"] .lang-switch::after{right:auto;left:11px}' +
      '[dir="rtl"] body{text-align:right}' +
      '@media (max-width:720px){.lang-select{max-width:7.5rem}}';
    var st = document.createElement('style');
    st.textContent = css;
    document.head.appendChild(st);
  }

  function init() {
    injectStyles();
    buildSwitcher();
    setLocale(detect());
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
