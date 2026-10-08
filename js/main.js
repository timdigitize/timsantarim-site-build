document.addEventListener('DOMContentLoaded', function () {
  var toggle = document.querySelector('.nav-toggle');
  var links = document.querySelector('.navbar .nav-links');
  if (toggle && links) {
    toggle.addEventListener('click', function () {
      var open = links.classList.toggle('is-open');
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
  }
  var navCats = document.querySelector('.nav-cats');
  if (navCats && window.matchMedia('(max-width: 720px)').matches) {
    navCats.querySelector('.nav-cats-btn').addEventListener('click', function (e) {
      e.preventDefault();
      navCats.classList.toggle('is-open');
    });
  }
  var wa = document.querySelector('.wa-float');
  var waBtn = document.querySelector('.wa-btn');
  if (wa && waBtn) {
    waBtn.addEventListener('click', function () {
      var open = wa.classList.toggle('is-open');
      waBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
  }
  var mainImg = document.getElementById('pd-main-img');
  var thumbs = document.querySelectorAll('.pd-thumb');
  thumbs.forEach(function (btn) {
    btn.addEventListener('click', function () {
      thumbs.forEach(function (b) { b.classList.remove('is-active'); });
      btn.classList.add('is-active');
      if (mainImg) mainImg.src = btn.getAttribute('data-src');
    });
  });
  var searchBox = document.querySelector('.search');
  var input = document.getElementById('site-search');
  var resultsEl = document.getElementById('search-results');
  if (searchBox && input && resultsEl) {
    var locale = searchBox.getAttribute('data-locale') || 'tr';
    var index = null;
    var selected = -1;
    function trFold(s) {
      return (s || '').toLocaleLowerCase('tr')
        .replace(/ç/g, 'c').replace(/ğ/g, 'g').replace(/ı/g, 'i')
        .replace(/ö/g, 'o').replace(/ş/g, 's').replace(/ü/g, 'u');
    }
    function loadIndex() {
      if (index) return Promise.resolve(index);
      return fetch('/search-index.json')
        .then(function (r) { return r.json(); })
        .then(function (data) { index = data; return index; });
    }
    function render(items, q) {
      selected = -1;
      if (!items.length) {
        resultsEl.innerHTML = '<div class="sr-empty">' +
          (locale === 'tr' ? 'Sonuç bulunamadı' : 'No results found') + '</div>';
      } else {
        resultsEl.innerHTML = items.slice(0, 8).map(function (p) {
          var name = locale === 'en' ? p.en : p.tr;
          var kat = locale === 'en' ? p.ken : p.ktr;
          var url = locale === 'en' ? p.uen : p.utr;
          var meta = p.c + (p.b ? ' · ' + p.b : '') + ' · ' + kat;
          return '<a href="' + url + '">' +
            '<img src="' + p.img + '" alt="" loading="lazy">' +
            '<span><span class="sr-name">' + name + '</span><br>' +
            '<span class="sr-meta">' + meta + '</span></span></a>';
        }).join('');
      }
      resultsEl.hidden = false;
    }
    function search(q) {
      var fq = trFold(q);
      var words = fq.split(/\s+/).filter(Boolean);
      return index.filter(function (p) {
        var hay = trFold(p.c + ' ' + (p.b || '') + ' ' + p.tr + ' ' + p.en + ' ' + p.ktr + ' ' + p.ken);
        return words.every(function (w) { return hay.indexOf(w) !== -1; });
      });
    }
    var timer = null;
    input.addEventListener('input', function () {
      var q = input.value.trim();
      clearTimeout(timer);
      if (q.length < 2) { resultsEl.hidden = true; return; }
      timer = setTimeout(function () {
        loadIndex().then(function () { render(search(q), q); });
      }, 120);
    });
    input.addEventListener('keydown', function (e) {
      var links = resultsEl.querySelectorAll('a');
      if (resultsEl.hidden || !links.length) return;
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        selected += (e.key === 'ArrowDown' ? 1 : -1);
        if (selected < 0) selected = links.length - 1;
        if (selected >= links.length) selected = 0;
        links.forEach(function (a, i) { a.classList.toggle('is-selected', i === selected); });
      } else if (e.key === 'Enter' && selected >= 0) {
        e.preventDefault();
        window.location.href = links[selected].getAttribute('href');
      } else if (e.key === 'Escape') {
        resultsEl.hidden = true;
      }
    });
    document.addEventListener('click', function (e) {
      if (!searchBox.contains(e.target)) resultsEl.hidden = true;
    });
  }
});