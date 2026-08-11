// SchoolSafe — Reçu de paiement V2
// Construction Finance/RH préparée pour la bascule unique finale.
// Ce fichier est volontairement DORMANT tant qu'il n'est pas inclus dans index.html.
// Décisions validées : demi-A4 lisible téléphone, gris/blanc/or, montants très visibles,
// devise « Former, Réformer, Exceller », logo de l'école, zones de signature VIDES.
(function () {
  'use strict';

  const GOLD = '#b8860b';
  const GOLD_LINE = '#c09018';
  const DARK = '#3f4348';
  const MID = '#556777';
  const LIGHT = '#f0f1f2';
  const PALE = '#f7f8f9';
  const GREEN = '#167c32';

  const E = value => {
    if (typeof window.esc === 'function') return window.esc(value == null ? '' : String(value));
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#039;');
  };

  const school = () => (window.DB && DB.settings && DB.settings.school) || {};
  const currencySymbol = () => {
    if (typeof window._cur === 'function') return window._cur();
    const d = school().devise || '$';
    return d === 'USD' ? '$' : d;
  };
  const money = n => `${currencySymbol()}${Number(n || 0).toLocaleString('fr-FR', {minimumFractionDigits: 2, maximumFractionDigits: 2})}`;

  const numberWords = n => {
    const units = ['', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf', 'dix', 'onze', 'douze', 'treize', 'quatorze', 'quinze', 'seize', 'dix-sept', 'dix-huit', 'dix-neuf'];
    const tens = ['', '', 'vingt', 'trente', 'quarante', 'cinquante', 'soixante', 'soixante', 'quatre-vingt', 'quatre-vingt'];
    const x = Math.round(Number(n));
    if (!Number.isFinite(x) || x === 0) return 'zéro';
    if (x < 0) return 'moins ' + numberWords(-x);
    if (x < 20) return units[x];
    if (x < 100) {
      const t = Math.floor(x / 10), u = x % 10;
      if (t === 7 || t === 9) return tens[t] + (u === 1 && t === 7 ? '-et-' : '-') + units[10 + u];
      return tens[t] + (u ? (t === 8 ? '-' : u === 1 ? '-et-' : '-') + units[u] : (t === 8 ? 's' : ''));
    }
    if (x < 1000) {
      const c = Math.floor(x / 100), r = x % 100;
      return (c > 1 ? units[c] + '-' : '') + 'cent' + (r ? '-' + numberWords(r) : (c > 1 ? 's' : ''));
    }
    if (x < 1000000) {
      const m = Math.floor(x / 1000), r = x % 1000;
      return (m > 1 ? numberWords(m) + '-' : '') + 'mille' + (r ? '-' + numberWords(r) : '');
    }
    return String(x);
  };

  const currencyWords = () => {
    const d = school().devise || '$';
    return ({'$':'dollars américains', USD:'dollars américains', CDF:'francs congolais', FCFA:'francs CFA', XAF:'francs CFA', '€':'euros', '£':'livres sterling'})[d] || d;
  };

  const amountWords = amount => {
    const w = numberWords(amount);
    return (w.charAt(0).toUpperCase() + w.slice(1)) + ' ' + currencyWords();
  };

  const formatDate = raw => {
    if (!raw) return '—';
    const d = new Date(String(raw).slice(0, 10) + 'T00:00:00');
    if (Number.isNaN(d.getTime())) return E(raw);
    return d.toLocaleDateString('fr-FR', {day:'2-digit', month:'2-digit', year:'numeric'});
  };

  const statusBanner = input => {
    if (input.annulled || input.reversed) {
      return `<div class="status status-cancel"><strong>PAIEMENT ANNULÉ / CONTREPASSÉ</strong><span>${input.reversal_reason ? E(input.reversal_reason) : 'Le reçu reste conservé dans l’historique.'}</span></div>`;
    }
    return `<div class="status status-ok"><span class="check">✓</span><div><strong>PAIEMENT CONFIRMÉ</strong><span>Versement reçu et enregistré par l’école.</span></div></div>`;
  };

  const allocationRows = input => {
    const arr = Array.isArray(input.allocations) && input.allocations.length
      ? input.allocations
      : [{label: input.fee_label || input.type_label || input.motif || 'Frais scolaires', period: input.trimestre || '—', expected: input.expected_amount, paid: input.amount, remaining: input.remaining_amount}];

    return arr.map(a => {
      const expected = Number(a.expected == null ? a.amount_expected : a.expected) || 0;
      const paid = Number(a.paid == null ? a.amount_paid : a.paid) || 0;
      const remaining = Math.max(0, Number(a.remaining == null ? (expected - paid) : a.remaining) || 0);
      return `<tr><td class="designation">${E(a.label || a.designation || 'Frais')}</td><td>${E(a.period || a.trimestre || '—')}</td><td class="money">${money(expected)}</td><td class="money paid-money">${money(paid)}</td><td class="money">${money(remaining)}</td></tr>`;
    }).join('');
  };

  const totals = input => {
    const arr = Array.isArray(input.allocations) && input.allocations.length ? input.allocations : null;
    if (!arr) {
      const expected = Number(input.expected_amount) || Number(input.amount) || 0;
      const paid = Number(input.amount) || 0;
      const remaining = Math.max(0, Number(input.remaining_amount == null ? expected - paid : input.remaining_amount) || 0);
      return {expected, paid, remaining};
    }
    return arr.reduce((t, a) => {
      const expected = Number(a.expected == null ? a.amount_expected : a.expected) || 0;
      const paid = Number(a.paid == null ? a.amount_paid : a.paid) || 0;
      const remaining = Math.max(0, Number(a.remaining == null ? expected - paid : a.remaining) || 0);
      t.expected += expected; t.paid += paid; t.remaining += remaining; return t;
    }, {expected:0, paid:0, remaining:0});
  };

  window.buildSchoolReceiptV2 = input => {
    const sc = school();
    const yr = input.year || (window.DB && DB.settings && DB.settings.year) || '';
    const logo = input.logo || window.SCHOOL_LOGO || window.SCHOOL_LOGO_DOC || './logo.jpg';
    const schName = input.school_name || sc.name || 'Complexe Scolaire Le Sage';
    const schSub = input.school_sub || sc.sub || 'The Wise School International';
    const total = totals(input);
    const reference = input.payment_reference || input.reference || input.reference_externe || '—';
    const receiptTag = input.duplicata ? '<span class="duplicata">DUPLICATA</span>' : '';

    const CSS = `
*{box-sizing:border-box}html,body{margin:0;padding:0}body{font-family:'Segoe UI',Arial,sans-serif;background:#eef0f2;color:#191b1e;padding:10px}
.receipt{width:min(100%,1050px);margin:0 auto;background:#fff;border:1px solid #d6d8da;border-radius:10px;overflow:hidden;box-shadow:0 3px 16px rgba(0,0,0,.08)}
.header{display:grid;grid-template-columns:118px 1fr 315px;gap:18px;align-items:center;padding:14px 20px 10px;border-bottom:3px solid ${GOLD_LINE};position:relative}
.logo{width:108px;height:108px;border-radius:50%;object-fit:contain;background:#fff}.school h1{font-size:28px;line-height:1.03;margin:0;font-weight:900;letter-spacing:.1px}.school h2{font-size:19px;margin:7px 0;color:${GOLD};font-weight:900}.motto{font-size:17px;font-weight:800;margin-top:12px}.motto:before,.motto:after{content:'';display:inline-block;width:38px;height:2px;background:${GOLD_LINE};vertical-align:middle;margin:0 10px}
.receipt-meta{align-self:stretch;display:flex;flex-direction:column;gap:7px;justify-content:center}.official{background:${DARK};color:#fff;border-radius:7px;text-align:center;padding:6px;font-size:18px;font-weight:900}.receipt-no{border:1px solid #999;border-radius:7px;text-align:center;padding:7px 8px}.receipt-no small{display:block;font-size:12px;font-weight:800}.receipt-no b{display:block;font-size:23px;color:${GOLD};line-height:1.05;margin-top:2px}.datetime{text-align:center;font-size:14px;font-weight:800}.duplicata{display:inline-block;background:${GOLD};color:#fff;border-radius:4px;padding:3px 8px;font-size:11px;margin-top:3px}
.content{padding:10px 20px 12px}.top-grid{display:grid;grid-template-columns:1fr 1.13fr;gap:18px}.box{border:1px solid #909397;border-radius:8px;overflow:hidden}.box-title{background:${DARK};color:#fff;padding:7px 12px;font-size:16px;font-weight:900}.fields{padding:9px 13px}.field{display:grid;grid-template-columns:145px 1fr;gap:8px;padding:3px 0;font-size:15px}.field .label{font-weight:700}.field .value{font-weight:900}.field.amount .value{font-size:29px;line-height:1;color:#000}.field.words .value{font-size:15px}.field.reference .value{font-family:monospace}
.section-title{display:inline-block;background:${DARK};color:#fff;border-radius:7px 7px 0 0;padding:6px 14px;font-size:16px;font-weight:900;margin-top:10px}table{width:100%;border-collapse:collapse;border:1px solid #aeb1b4;font-size:14px}th{background:${DARK};color:#fff;padding:7px 8px;text-align:center;font-size:13px}td{border:1px solid #c8cbce;padding:6px 8px;text-align:center;font-weight:700}.designation{text-align:left}.money{font-size:17px;font-weight:900}.paid-money{font-size:20px;color:#050505}.total-row td{background:#fbf1d9;color:${GOLD};font-size:19px;font-weight:900}.total-row td:first-child{text-align:left}
.status{margin-top:9px;border:1px solid #bbb;border-radius:7px;min-height:48px;display:flex;align-items:center;padding:7px 14px}.status strong{display:block;font-size:17px}.status span{display:block;font-size:12px;margin-top:2px}.status-ok{color:${GREEN}}.status-ok .check{font-size:30px;font-weight:900;margin:0 14px 0 2px}.status-cancel{background:#f1f1f1;color:#8b1e1e;justify-content:center;text-align:center;flex-direction:column}
.signatures{display:grid;grid-template-columns:1fr 1fr 1.18fr;gap:12px;margin-top:9px}.sig{border:1px solid #aaa;border-radius:7px;min-height:98px;text-align:center;padding:8px}.sig h3{font-size:14px;margin:0 0 4px;color:${GOLD};font-weight:900}.sig p{font-size:12px;margin:0}.sig-line{height:48px;border-bottom:1.5px solid #303236;margin:0 18px 5px}.stamp-space{height:51px;border:1.5px solid ${GOLD_LINE};border-radius:6px;margin:5px 7px 0}
.footer{border-top:1px solid #ccc;margin-top:9px;padding:7px 12px 0;text-align:center;font-size:11px}.contacts{display:flex;justify-content:center;gap:22px;flex-wrap:wrap}.footer-motto{background:${DARK};color:${GOLD};font-size:15px;font-weight:900;margin:7px -12px -1px;padding:6px}
.print-btn{display:block;margin:10px auto 0;background:${DARK};color:#fff;border:0;border-radius:8px;padding:10px 24px;font-weight:800;font-size:14px;cursor:pointer}
@media(max-width:720px){body{padding:0;background:#fff}.receipt{border:0;border-radius:0;box-shadow:none;width:100%}.header{grid-template-columns:78px 1fr;gap:8px;padding:9px}.logo{width:72px;height:72px}.school h1{font-size:19px}.school h2{font-size:14px}.motto{font-size:13px;margin-top:5px}.motto:before,.motto:after{width:18px;margin:0 5px}.receipt-meta{grid-column:1/-1;display:grid;grid-template-columns:1fr 1.5fr;gap:5px}.official{font-size:14px}.receipt-no{padding:4px}.receipt-no b{font-size:19px}.datetime{grid-column:1/-1;font-size:12px}.content{padding:7px}.top-grid{grid-template-columns:1fr}.box-title,.section-title{font-size:14px}.field{font-size:14px;grid-template-columns:132px 1fr}.field.amount .value{font-size:30px}table{font-size:12px}th{font-size:10px;padding:5px 2px}td{padding:5px 2px}.money{font-size:15px}.paid-money{font-size:19px}.total-row td{font-size:16px}.signatures{grid-template-columns:1fr 1fr}.sig:last-child{grid-column:1/-1}.contacts{gap:5px 14px}}
@media print{body{background:#fff;padding:0}.receipt{width:100%;max-width:none;border:none;border-radius:0;box-shadow:none}.print-btn{display:none}@page{size:A5 landscape;margin:5mm}}
`;

    return `<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Reçu ${E(input.receipt_no || '')}</title><style>${CSS}</style></head><body><main class="receipt">
<header class="header"><img class="logo" src="${E(logo)}" alt="Logo de l'école"><div class="school"><h1>${E(schName)}</h1><h2>${E(schSub)}</h2><div class="motto">Former, Réformer, Exceller</div></div><div class="receipt-meta"><div class="official">REÇU OFFICIEL</div><div class="receipt-no"><small>N° REÇU</small><b>${E(input.receipt_no || '—')}</b>${receiptTag}</div><div class="datetime">Date : ${E(formatDate(input.date))} &nbsp; | &nbsp; Heure : ${E(input.time || '—')}</div></div></header>
<section class="content"><div class="top-grid"><section class="box"><div class="box-title">INFORMATIONS ÉLÈVE</div><div class="fields"><div class="field"><span class="label">Nom et prénom</span><span class="value">${E(input.student_name || '—')}</span></div><div class="field"><span class="label">Matricule</span><span class="value">${E(input.mat || '—')}</span></div><div class="field"><span class="label">Classe</span><span class="value">${E(input.class_name || '—')}</span></div><div class="field"><span class="label">Année scolaire</span><span class="value">${E(yr || '—')}</span></div></div></section>
<section class="box"><div class="box-title">INFORMATIONS PAIEMENT</div><div class="fields"><div class="field"><span class="label">Type de paiement</span><span class="value">${E(input.fee_label || input.type_label || input.motif || '—')}${input.trimestre ? ' · ' + E(input.trimestre) : ''}</span></div><div class="field amount"><span class="label">Montant reçu</span><span class="value">${money(input.amount)}</span></div><div class="field words"><span class="label">En toutes lettres</span><span class="value">${E(amountWords(input.amount))}</span></div><div class="field"><span class="label">Moyen de paiement</span><span class="value">${E(input.payment_method || 'Espèces')}</span></div><div class="field reference"><span class="label">Référence</span><span class="value">${E(reference)}</span></div>${input.note ? `<div class="field"><span class="label">Note</span><span class="value">${E(input.note)}</span></div>` : ''}</div></section></div>
<div class="section-title">DÉTAIL DES FRAIS COUVERTS</div><table><thead><tr><th>DÉSIGNATION</th><th>PÉRIODE / TRIMESTRE</th><th>MONTANT ATTENDU</th><th>MONTANT PAYÉ</th><th>SOLDE RESTANT</th></tr></thead><tbody>${allocationRows(input)}</tbody><tfoot><tr class="total-row"><td>TOTAL</td><td></td><td>${money(total.expected)}</td><td>${money(total.paid)}</td><td>${money(total.remaining)}</td></tr></tfoot></table>
${statusBanner(input)}
<section class="signatures"><div class="sig"><h3>LU ET APPROUVÉ</h3><p>Nom et signature</p><div class="sig-line"></div></div><div class="sig"><h3>ÉTABLI PAR</h3><p>Nom et signature</p><div class="sig-line"></div></div><div class="sig"><h3>VISA &amp; CACHET DE L’ÉCOLE</h3><p>Signature et cachet</p><div class="stamp-space"></div></div></section>
<footer class="footer"><div class="contacts">${sc.address ? `<span>Adresse : ${E(sc.address)}</span>` : ''}${sc.phone ? `<span>Téléphone : ${E(sc.phone)}</span>` : ''}${sc.email ? `<span>Email : ${E(sc.email)}</span>` : ''}${sc.website ? `<span>Site web : ${E(sc.website)}</span>` : ''}</div><div class="footer-motto">Former, Réformer, Exceller</div></footer></section><button class="print-btn" onclick="window.print()">Imprimer / PDF</button></main></body></html>`;
  };

  window.schoolReceiptV2FromVersement = vid => {
    const v = (window.DB && DB.versements || []).find(x => x.id === vid);
    if (!v) return null;
    const student = (DB.students || []).find(x => x.id === v.sid) || {name:v.student_name, mat:v.mat};
    const cl = typeof window.gc === 'function' ? window.gc(student.cid) : (DB.classes || []).find(x => x.id === student.cid);
    const ft = (DB.fee_types || []).find(x => x.id === v.fee_type_id);
    const expected = Number(ft && ft.montant_defaut) || Number(v.montant) || 0;
    const totalPaid = (DB.versements || []).filter(x => x.sid === v.sid && x.fee_type_id === v.fee_type_id && !x.annulled).reduce((sum, x) => sum + (Number(x.montant) || 0), 0);
    const remaining = Math.max(0, expected - totalPaid);
    return {
      receipt_no:v.recu_no,
      student_name:student.name || v.student_name,
      mat:student.mat || v.mat,
      class_name:cl && cl.name,
      year:DB.settings && DB.settings.year,
      fee_label:v.fee_label || (ft && ft.label) || v.motif,
      trimestre:v.trimestre || (ft && ft.trimestre),
      amount:Number(v.montant) || 0,
      expected_amount:expected,
      remaining_amount:remaining,
      payment_method:v.payment_method || 'Espèces',
      payment_reference:v.payment_reference || v.reference || v.reference_externe || '',
      note:v.note || '',
      date:v.date,
      time:v.time,
      annulled:!!v.annulled,
      reversal_reason:v.annulled_reason || '',
      duplicata:Number(v.print_count || 1) > 1
    };
  };

  // Fonction prête pour le branchement final. Elle ne remplace PAS encore la fonction live.
  window.printVersementRecuV2 = vid => {
    const data = window.schoolReceiptV2FromVersement(vid);
    if (!data) { if (typeof window.toast === 'function') toast('Versement introuvable', 'error'); return; }
    const html = window.buildSchoolReceiptV2(data);
    if (typeof window.dlPDF === 'function') window.dlPDF(html, `Recu-${String(data.receipt_no || '').replace(/[^a-z0-9]/gi, '_')}.pdf`);
    else {
      const w = window.open('', '_blank'); if (!w) return; w.document.write(html); w.document.close();
    }
  };

  window.parentReceiptV2FromNotification = nid => {
    const n = (window.DB && DB.notifs || []).find(x => x.id === nid);
    if (!n || !n.receipt) return null;
    const r = n.receipt;
    return {receipt_no:r.num, student_name:r.student, mat:r.mat, class_name:r.classe, year:DB.settings && DB.settings.year, fee_label:r.type_label, trimestre:r.trimestre, amount:Number(r.amount)||0, expected_amount:Number(r.expected_amount)||Number(r.amount)||0, remaining_amount:Number(r.remaining_amount)||0, payment_method:r.payment_method||'Espèces', payment_reference:r.payment_reference||r.reference||'', note:r.note||'', date:r.date, time:r.time, duplicata:!!r.duplicata, annulled:!!r.annulled, reversal_reason:r.reversal_reason||''};
  };

  window.viewReceiptV2 = nid => {
    const data = window.parentReceiptV2FromNotification(nid);
    if (!data) return;
    const html = window.buildSchoolReceiptV2(data);
    if (typeof window.dlPDF === 'function') window.dlPDF(html, `Recu-${String(data.receipt_no || '').replace(/[^a-z0-9]/gi, '_')}.pdf`);
    else { const w = window.open('', '_blank'); if (!w) return; w.document.write(html); w.document.close(); }
  };
})();
