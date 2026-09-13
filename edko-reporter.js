/*  edko-reporter.js
    Auto-scrapes quiz/worksheet results and saves to localStorage.
    Injected into every worksheet by sync-from-icloud.sh.
*/
(function () {
  'use strict';

  var STORAGE_KEY = 'edko_results';

  /* ---- scrape one question block ---- */
  function scrapeQuestion(qEl, idx) {
    var qtEl = qEl.querySelector('.qt');
    var qText = qtEl ? qtEl.textContent.trim() : 'Otazka ' + (idx + 1);

    var userAnswer = '', correctAnswer = '', isCorrect = false, type = 'unknown';

    /* MCQ buttons (.ob) */
    var allBtns = qEl.querySelectorAll('.ob');
    if (allBtns.length) {
      type = 'mcq';
      var wrongBtn = qEl.querySelector('.ob.incorrect');
      var rightBtn = qEl.querySelector('.ob.correct');

      if (wrongBtn) {
        userAnswer = wrongBtn.textContent.trim();
        correctAnswer = rightBtn ? rightBtn.textContent.trim() : '';
        isCorrect = false;
      } else if (rightBtn) {
        userAnswer = rightBtn.textContent.trim();
        correctAnswer = rightBtn.textContent.trim();
        isCorrect = true;
      }
    }

    /* Fill-in-blank inputs (.binp) */
    var blanks = qEl.querySelectorAll('.binp');
    if (blanks.length) {
      type = 'fill';
      var parts = [];
      var allCorrect = true;
      blanks.forEach(function (inp) {
        var val = inp.value || '';
        var ok = inp.classList.contains('correct');
        if (!ok) allCorrect = false;
        var rev = inp.parentElement && inp.parentElement.querySelector('.rev.show, .rev');
        var corr = (rev && rev.textContent) ? rev.textContent.replace(/^[\s→]+/, '').trim() : '';
        parts.push({ val: val, correct: ok ? val : corr, ok: ok });
      });
      userAnswer = parts.map(function (p) { return p.val; }).join('; ');
      correctAnswer = parts.map(function (p) { return p.correct || p.val; }).join('; ');
      isCorrect = allCorrect;
    }

    /* Ordering / drag-drop (.aob) */
    var aobs = qEl.querySelectorAll('.aob');
    if (aobs.length) {
      type = 'order';
      var orderParts = [];
      var orderOk = true;
      aobs.forEach(function (a) {
        var ok = a.classList.contains('correct');
        if (!ok) orderOk = false;
        orderParts.push(a.textContent.trim());
      });
      userAnswer = orderParts.join(', ');
      isCorrect = orderOk;
    }

    return {
      num: idx + 1,
      q: qText,
      type: type,
      userAnswer: userAnswer,
      correctAnswer: correctAnswer,
      isCorrect: isCorrect
    };
  }

  /* ---- scrape all results ---- */
  function scrapeResults() {
    var title = document.title || location.pathname;
    var scoreEl = document.getElementById('stP');
    var pctEl = document.getElementById('stPct');
    var score = scoreEl ? parseInt(scoreEl.textContent) || 0 : 0;
    var pct = pctEl ? parseInt(pctEl.textContent) || 0 : 0;

    var questions = [];
    document.querySelectorAll('.qb, .q').forEach(function (qEl, i) {
      questions.push(scrapeQuestion(qEl, i));
    });

    /* For drill-type with no visible question blocks, check for missed list */
    if (questions.length === 0) {
      var missedEl = document.getElementById('missedList');
      if (missedEl) {
        missedEl.querySelectorAll('li').forEach(function (li, i) {
          questions.push({
            num: i + 1,
            q: li.textContent.trim(),
            type: 'drill-missed',
            userAnswer: 'wrong',
            correctAnswer: '',
            isCorrect: false
          });
        });
      }
    }

    return {
      id: location.pathname.replace(/^\//, '').replace('.html', ''),
      title: title,
      date: new Date().toISOString(),
      score: score,
      pct: pct,
      totalQuestions: questions.length,
      correctCount: questions.filter(function (q) { return q.isCorrect; }).length,
      questions: questions
    };
  }

  /* ---- persist ---- */
  function saveResult(result) {
    if (!result) return;

    /* Save to localStorage as backup */
    try {
      var all = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]');
      all.push(result);
      localStorage.setItem(STORAGE_KEY, JSON.stringify(all));
    } catch (e) {}

    /* Send to server (Vercel Blob) so parents can see from any device */
    try {
      fetch('/api/results', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(result)
      }).then(function (r) {
        if (r.ok) console.log('[edko-reporter] Result saved to server.');
        else console.warn('[edko-reporter] Server save failed:', r.status);
      }).catch(function (e) {
        console.warn('[edko-reporter] Server save error:', e);
      });
    } catch (e) {}

    console.log('[edko-reporter] Saved result:', result.title, result.pct + '%');
  }

  /* ---- watch for results panel ---- */
  var saved = false;

  function trySave() {
    if (saved) return;
    var result = scrapeResults();
    if (result && (result.score > 0 || result.questions.length > 0)) {
      saved = true;
      saveResult(result);
    }
  }

  /* Method 1: MutationObserver on #rsd */
  var rsd = document.getElementById('rsd');
  if (rsd) {
    var obs = new MutationObserver(function () {
      if (rsd.classList.contains('show')) {
        /* Small delay to let scores update */
        setTimeout(trySave, 500);
      }
    });
    obs.observe(rsd, { attributes: true, attributeFilter: ['class'] });
  }

  /* Method 2: Hook into common submit buttons as backup */
  document.addEventListener('click', function (e) {
    var btn = e.target;
    if (btn.id === 'subb' || btn.classList.contains('subb')) {
      setTimeout(trySave, 1500);
    }
  });

  /* Method 3: For drill-type, watch for finish screen */
  var finEl = document.getElementById('fin');
  if (finEl) {
    var obs2 = new MutationObserver(function () {
      if (finEl.style.display !== 'none' && finEl.offsetParent !== null) {
        setTimeout(trySave, 500);
      }
    });
    obs2.observe(finEl, { attributes: true, childList: true });
  }
})();
