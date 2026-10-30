// Matching rules. Pure functions with no network access, so they can be tested alone.
// Version 1 uses transparent rules: every match comes with the reasons that produced it.
(function (root) {
  var STOP = ('the and for with that this have from your what about into want need looking build building ' +
    'make making work working some more very also like just who can will been were they them their there ' +
    'where when which would should could than then over under into onto our out any all one two get got ' +
    'someone people person team startup').split(' ');

  function words(text) {
    return String(text || '').toLowerCase().replace(/[^a-z0-9+# ]/g, ' ').split(/\s+/)
      .filter(function (w) { return w.length >= 4 && STOP.indexOf(w) === -1; });
  }
  function uniq(a) { return a.filter(function (x, i) { return a.indexOf(x) === i; }); }
  function listText(a) {
    a = a.slice();
    if (a.length <= 1) return a.join('');
    return a.slice(0, -1).join(', ') + ' and ' + a[a.length - 1];
  }
  function has(arr, x) { return (arr || []).indexOf(x) !== -1; }

  var EXPERIENCED = ['Mentor', 'Founder', 'Professional'];

  function score(me, o) {
    var s = 0, why = [];
    var give = (me.need_skills || []).filter(function (x) { return has(o.offer_skills, x); });
    if (give.length) { s += 3 * give.length; why.push('Can help with ' + listText(give) + ', which you are looking for'); }
    var take = (o.need_skills || []).filter(function (x) { return has(me.offer_skills, x); });
    if (take.length) { s += 2 * take.length; why.push('Is looking for ' + listText(take) + ', which you offer'); }

    if (has(me.intent, 'Find a mentor') && has(EXPERIENCED, o.role)) { s += 3; why.push('Is a ' + o.role.toLowerCase() + ' who could mentor you'); }
    if (has(me.intent, 'Find investors') && o.role === 'Investor') { s += 5; why.push('Is an investor'); }
    if (has(me.intent, 'Find clients / customers') && (o.role === 'Founder' || o.role === 'Professional')) { s += 2; why.push('Is a ' + o.role.toLowerCase() + ' who may need your work'); }
    if (has(me.intent, 'Find a co-founder') && has(o.intent, 'Find a co-founder')) { s += 3; why.push('Is also looking for a co-founder'); }
    if (has(me.intent, 'Find hackathon teammates') && has(o.intent, 'Find hackathon teammates')) { s += 3; why.push('Is also looking for hackathon teammates'); }
    if (has(me.intent, 'Find internship / job') && (o.role === 'Founder' || o.role === 'Professional') && (o.need_skills || []).length) { s += 2; why.push('Is a ' + o.role.toLowerCase() + ' hiring for skills'); }
    if (has(o.intent, 'Find a mentor') && has(EXPERIENCED, me.role)) { s += 1; why.push('Is looking for a mentor and you have experience'); }
    if (has(o.intent, 'Find investors') && me.role === 'Investor') { s += 3; why.push('Is looking for investors'); }

    var mine = uniq(words(me.looking_text));
    var theirs = uniq(words(o.offer_text + ' ' + o.project));
    var shared = mine.filter(function (w) { return theirs.indexOf(w) !== -1; }).slice(0, 3);
    if (shared.length) { s += shared.length; why.push('Mentions ' + listText(shared.map(function (w) { return '"' + w + '"'; })) + ', like your own note'); }

    return { score: s, why: why };
  }

  function rank(me, others, limit) {
    return others.map(function (o) { var r = score(me, o); return { person: o, score: r.score, why: r.why }; })
      .filter(function (r) { return r.score > 0; })
      .sort(function (a, b) { return b.score - a.score; })
      .slice(0, limit || 5);
  }

  var api = { score: score, rank: rank, words: words };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.EMS_MATCH = api;
})(typeof window !== 'undefined' ? window : this);
