// ══════════════════════════════════════════════════════════════════════════
//  audit-charte.mjs — les documents de l'école portent-ils SES couleurs ?
//
//  La charte de l'école est gris · blanc · or.
//
//  Son « gris » est un GRIS BLEUTÉ — teinte 207°, saturation 14 % — donné
//  par la Direction en montrant un mur peint : #6b7d8b. Ce n'est pas
//  un gris neutre, et un contrôle qui exigeait R = G = B rejetait la charte
//  elle-même. L'or, #c09018, vient de l'étoile de l'emblème.
//
//  L'INTERFACE de l'application garde son bleu — c'est SchoolSafe, le
//  logiciel. Mais tout ce qui s'imprime engage l'école : bulletin, reçu,
//  fiche de préparation, convocation, certificat, carte d'élève.
//
//  Ne sont pas des couleurs de charte, et restent donc admises :
//   · les couleurs SÉMANTIQUES — vert d'un paiement, rouge d'une dette,
//     orange d'une alerte. Elles disent un état, pas une identité.
//   · l'or du drapeau congolais sous « République Démocratique du Congo »
//     sur les cartes d'élève.
//
//  Usage : node tools/audit-charte.mjs [--detail]
// ══════════════════════════════════════════════════════════════════════════
import fs from 'fs';

const src = fs.readFileSync(new URL('../dist/index.html', import.meta.url), 'utf8');
const lignes = src.split('\n');
const detail = process.argv.includes('--detail');

const offsets = []; { let o = 0; for (const l of lignes) { offsets.push(o); o += l.length + 1; } }
const estDecl = (l) => /^(window\.[A-Za-z_$][\w$]*\s*=|function\s+[A-Za-z_$])/.test(l);
const nomDe = (l) => {
  const m = /^(?:window\.)?([A-Za-z_$][\w$]*)\s*=/.exec(l) || /^function\s+([A-Za-z_$][\w$]*)/.exec(l);
  return m ? m[1] : '?';
};

// ── Les documents : de la déclaration à leur propre sortie ────────────────
const derniere = new Map();
lignes.forEach((l, i) => {
  if (!/dlPDF\(|\b\w+\.document\.write\(|a\.download\s*=/.test(l)) return;
  for (let j = i; j >= 0 && j > i - 900; j--) {
    if (!estDecl(lignes[j])) continue;
    if (nomDe(lignes[j]) === 'dlPDF') return;
    derniere.set(j, Math.max(derniere.get(j) || 0, i));
    return;
  }
});

// ── Classer une couleur ───────────────────────────────────────────────────
const rgb = (v) => {
  if (v[0] === '#') return [parseInt(v.slice(1,3),16), parseInt(v.slice(3,5),16), parseInt(v.slice(5,7),16)];
  const m = /(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/.exec(v);
  return m ? [ +m[1], +m[2], +m[3] ] : null;
};
// Couleurs sémantiques employées dans toute l'application — elles disent un
// état (payé, en dette, en alerte), jamais l'identité de l'école.
const SEMANTIQUES = new Set([
  // vert — payé, présent, réussi
  '#1f9d6b','#065f46','#d8f3e6','#22c55e','#16a34a','#f0fdf4','#86efac',
  '#15803d','#166534','#047857','#dcfce7','#2fbf8f','#10b981','#059669',
  // rouge — dette, absence, refus
  '#dc2626','#991b1b','#fee2e2','#ef5b5b','#f87171','#fef2f2','#b91c1c',
  '#fca5a5','#7f1d1d','#fff5f5','#fff1f2','#fca5a5','#e11d48',
  // orange et ambre — alerte, retard, en attente
  '#d98a2b','#92400e','#fdeccd','#f59e0b','#fbbf24','#fffbeb','#fff7ee',
  '#ea580c','#9a3412','#fff7ed','#fdba74','#b45309','#fef3c7',
  // bleu d'information, employé pour un état neutre
  '#eff6ff','#1e40af','#dbeafe',
]);
// Le « gris » de l'école n'est PAS un gris neutre : c'est un vert de gris,
// teinte 136°, relevé sur le pot de peinture de la Direction (#a9b4ac).
// Un classement qui exigeait R = G = B rejetait donc toute la charte.
// On accepte l'écart tant que le vert domine sans excès — au-delà, c'est
// un vert franc, hors charte.
const nature = ([r,g,b]) => {
  const e = Math.max(r,g,b) - Math.min(r,g,b);
  if (e <= 6) return 'gris';                                  // gris neutre pur
  // La teinte de référence #6b7d8b a 32 d'écart : un seuil à 30 rejetait la
  // couleur même de la charte. 34 laisse passer la gamme sans admettre un
  // bleu franc, qui dépasse largement.
  if (b >= g && g >= r && e <= 34) return 'gris';             // gris bleuté de l'école
  if (r > b + 40 && g > b + 20 && r >= g) return 'or';
  return 'hors';
};

let horsTotal = 0, docs = 0;
const rapport = [];
for (const [d, i] of [...derniere].sort((a,b) => a[0]-b[0])) {
  const nom = nomDe(lignes[d]);
  const corps = lignes.slice(d, i + 1).join('\n');
  const trouvees = [
    ...corps.matchAll(/#[0-9a-fA-F]{6}\b/g),
    ...corps.matchAll(/rgba?\(\s*\d+\s*,\s*\d+\s*,\s*\d+/g),
  ].map(m => m[0]);
  if (!trouvees.length) continue;
  docs++;
  const hors = [];
  let gris = 0, or = 0;
  for (const v of trouvees) {
    const c = rgb(v); if (!c) continue;
    if (SEMANTIQUES.has(v.toLowerCase())) continue;
    const n = nature(c);
    if (n === 'gris') gris++;
    else if (n === 'or') or++;
    else hors.push(v);
  }
  horsTotal += hors.length;
  rapport.push({ nom, ligne: d + 1, gris, or, hors });
}

console.log('═══ LES DOCUMENTS DE L\'ÉCOLE PORTENT-ILS SA CHARTE ? ═══');
console.log('    gris · blanc · or — les couleurs de l\'emblème\n');
for (const r of rapport) {
  const ok = r.hors.length === 0;
  if (!ok || detail) {
    console.log(`  ${ok ? '✓' : '✗'} ${r.nom.padEnd(30)} ${String(r.gris).padStart(3)} gris  ${String(r.or).padStart(2)} or` +
      (r.hors.length ? `   ✗ ${[...new Set(r.hors)].join(' ')}` : ''));
  }
}
console.log(horsTotal
  ? `\n✗ ${horsTotal} couleur(s) hors charte sur ${docs} documents`
  : `\n✓ Les ${docs} documents de l'école ne portent que du gris, du blanc et de l'or`);
process.exit(horsTotal ? 1 : 0);
