// ════════════════════════════════════════════════════════════════════════════
//  Jeu d'essai — 350 élèves
//
//  Écrit un fichier JSON à charger dans l'application pour éprouver ce qui
//  n'a jamais été éprouvé : le volume. Rien ici n'est réel — noms, dates et
//  montants sont fabriqués. Aucune donnée d'élève, de parent ou de paiement
//  véritable n'entre dans ce dépôt.
//
//  Il est déterministe : le même appel rend le même jeu. Un défaut trouvé se
//  rejoue à l'identique, ce qu'un tirage au hasard ne permet pas.
//
//    node tools/jeu-350.mjs > /tmp/jeu-350.json
//    node tools/jeu-350.mjs --resume
// ════════════════════════════════════════════════════════════════════════════

// Générateur déterministe — mulberry32. Une graine, une suite reproductible.
function alea(graine) {
  let a = graine >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const r = alea(20260803);
const pick = t => t[Math.floor(r() * t.length)];
const entre = (a, b) => a + Math.floor(r() * (b - a + 1));

// Noms usuels à Kinshasa — assemblés, jamais recopiés d'un registre réel.
const PRENOMS = ['Grâce','Merveille','Bénédicte','Josué','Emmanuel','Divine','Christian','Espérance',
  'Gloire','Nathan','Sarah','Daniel','Rebecca','Samuel','Esther','Jonathan','Ruth','David','Naomi',
  'Isaac','Deborah','Elie','Miriam','Gédéon','Anne','Paul','Rachel','Michée','Judith','Abel'];
const NOMS = ['Kabongo','Mbuyi','Tshimanga','Ilunga','Mukendi','Kalala','Nsimba','Luyeye','Mbala',
  'Bakase','Manzambi','Ekombe','Bolingo','Mussaso','Bagata','Ngoma','Kasongo','Mputu','Lokombe',
  'Nkulu','Bofasa','Matondo','Kiese','Lelo','Mabiala','Nzuzi','Kambale','Bwanga','Diata','Mavinga'];

const CLASSES = [
  { id:'c_m1', name:'1ère Maternelle', cycle:'maternelle', eff:22 },
  { id:'c_m2', name:'2ème Maternelle', cycle:'maternelle', eff:24 },
  { id:'c_m3', name:'3ème Maternelle', cycle:'maternelle', eff:26 },
  { id:'c_p1a',name:'1ère Primaire A', cycle:'primaire',   eff:31 },
  { id:'c_p1b',name:'1ère Primaire B', cycle:'primaire',   eff:30 },
  { id:'c_p2a',name:'2ème Primaire A', cycle:'primaire',   eff:29 },
  { id:'c_p2b',name:'2ème Primaire B', cycle:'primaire',   eff:28 },
  { id:'c_p3', name:'3ème Primaire',   cycle:'primaire',   eff:32 },
  { id:'c_p4', name:'4ème Primaire',   cycle:'primaire',   eff:30 },
  { id:'c_p5', name:'5ème Primaire',   cycle:'primaire',   eff:27 },
  { id:'c_p6', name:'6ème Primaire',   cycle:'primaire',   eff:26 },
  { id:'c_s1', name:'7ème CTEB',       cycle:'secondaire', eff:25 },
];
// 350 exactement : le reste tombe dans la dernière classe.
const TOTAL = 350;

const MATIERES = ['Français','Mathématiques','Anglais','Éveil scientifique','Histoire',
  'Géographie','Éducation civique','Religion','Dessin','Chant','Éducation physique'];

const ANNEE = '2026-2027';           // format exigé par R2 : ^\d{4}-\d{4}$
const AUJ   = '2026-08-03';

const db = {
  _meta: { genere_le: AUJ, graine: 20260803, reel: false,
           avertissement: "Jeu d'essai. Aucune donnée réelle." },
  classes: [], users: [], students: [], payments: [], attendance: [],
  grades: [], devoirs: [], matieres: [], scan_log: [],
  settings: { id:'main', year: ANNEE, currentTrimestre:'T1',
              school:{ name:'Complexe Scolaire Le Sage', devise:'$' },
              fees:{ T1:150, T2:150, T3:150 } },
};

// ── Personnel ────────────────────────────────────────────────────────────────
db.users.push(
  { id:'u_dir1', name:'Direction Générale',   role:'direction',   status:'active', email:'direction@example.test' },
  { id:'u_dir2', name:'Direction Pédagogique',role:'direction2',  status:'active', email:'pedagogie@example.test' },
  { id:'u_cai',  name:'Caisse',               role:'direction3',  status:'active', email:'caisse@example.test' },
  { id:'u_gar',  name:'Gardien du portail',   role:'gardien',     status:'active', email:'portail@example.test' },
);
CLASSES.forEach((c, i) => {
  db.users.push({ id:'u_ens'+i, name:`${pick(PRENOMS)} ${pick(NOMS)}`,
                  role: c.cycle==='maternelle' ? 'enseignant_maternelle' : 'enseignant',
                  status:'active', email:`ens${i}@example.test` });
});

// ── Classes et matières ──────────────────────────────────────────────────────
CLASSES.forEach((c, i) => {
  db.classes.push({ id:c.id, name:c.name, cycle:c.cycle, teacher_id:'u_ens'+i });
  MATIERES.slice(0, c.cycle==='maternelle' ? 5 : MATIERES.length).forEach((m, j) => {
    db.matieres.push({ id:`m_${c.id}_${j}`, cid:c.id, name:m, maxima: m==='Français'||m==='Mathématiques' ? 40 : 20 });
  });
});

// ── Élèves, parents, paiements ───────────────────────────────────────────────
let n = 0;
for (const c of CLASSES) {
  const eff = c === CLASSES[CLASSES.length-1] ? TOTAL - n : c.eff;
  for (let k = 0; k < eff && n < TOTAL; k++, n++) {
    const nom = `${pick(PRENOMS)} ${pick(NOMS)}`;
    const sid = 's_' + String(n+1).padStart(4,'0');
    const pid = 'p_' + String(n+1).padStart(4,'0');

    // Une famille sur cinq a plusieurs enfants : c'est le cas qui casse le
    // sélecteur multi-enfants, et il doit donc être représenté.
    const fratrie = n > 0 && r() < 0.20;
    const parentId = fratrie ? 'p_' + String(entre(1, n)).padStart(4,'0') : pid;
    if (!fratrie) {
      db.users.push({ id:pid, name:`${pick(PRENOMS)} ${nom.split(' ')[1]}`, role:'parent',
                      status:'active', phone:'+24381'+entre(1000000,9999999),
                      email:`parent${n+1}@example.test` });
    }

    db.students.push({
      id:sid, name:nom, mat:'LS'+ANNEE.slice(2,4)+String(n+1).padStart(4,'0'),
      cid:c.id, pid:parentId,
      dob:`${2026 - (c.cycle==='maternelle'?4:c.cycle==='primaire'?9:13) - entre(0,2)}-${String(entre(1,12)).padStart(2,'0')}-${String(entre(1,28)).padStart(2,'0')}`,
      archived:false, access_parent: r() < 0.95, may_leave_alone: r() < 0.08,
      school_id:null,
    });

    // Paiements — la répartition qui compte : il DOIT y avoir des partiels,
    // puisque c'est exactement ce que le modèle actuel ne sait pas représenter.
    const situation = r();
    ['T1','T2','T3','inscription'].forEach(t => {
      const paye = situation < 0.55 ? true                    // 55 % à jour
                 : situation < 0.80 ? (t==='T1'||t==='inscription')  // 25 % partiels
                 : situation < 0.95 ? t==='inscription'       // 15 % à peine commencé
                 : false;                                     //  5 % rien
      db.payments.push({ id:`pay_${sid}_${t}`, sid, t, paid:paye,
                         date: paye ? `2026-09-${String(entre(1,28)).padStart(2,'0')}` : null });
    });
  }
}

// ── Une journée de présences et de scans ─────────────────────────────────────
db.students.forEach(s => {
  const d = r();
  const statut = d < 0.86 ? 'ontime' : d < 0.94 ? 'late' : d < 0.98 ? 'sick' : 'absent';
  const h = statut==='late' ? `0${entre(8,9)}:${String(entre(0,59)).padStart(2,'0')}`
                            : `0${entre(6,7)}:${String(entre(30,59)).padStart(2,'0')}`;
  if (statut !== 'absent') {
    db.attendance.push({ id:`att_${s.id}`, sid:s.id, date:AUJ, status:statut, arr_time:h });
    db.scan_log.push({ id:`sl_${s.id}`, sid:s.id, name:s.name, date:AUJ, time:h,
                       type:'entry', status:statut, by_role:'gardien' });
  }
});
// Cinq refus — le cas qui, aujourd'hui, s'affiche « Arrivé(e) » chez le parent.
db.students.slice(0, 5).forEach((s, i) => {
  db.scan_log.push({ id:`sl_ref_${i}`, sid:s.id, name:s.name, date:AUJ, time:'07:15',
                     type:'entry', status:'refused_fees', label:'Frais non réglés',
                     by_role:'gardien' });
});

// ── Notes et devoirs ─────────────────────────────────────────────────────────
db.classes.forEach(c => {
  const mats = db.matieres.filter(m => m.cid === c.id);
  const eleves = db.students.filter(s => s.cid === c.id);
  mats.forEach(m => {
    for (let d = 0; d < 3; d++) {
      const did = `dv_${m.id}_${d}`;
      db.devoirs.push({ id:did, cid:c.id, matiere:m.name,
                        title:`${m.name} — ${['devoir','interrogation','examen'][d]} T1`,
                        category:['devoir','interro','examen'][d], status:'published',
                        date:AUJ, deadline:`2026-08-${String(10+d*3).padStart(2,'0')}`,
                        teacher_id:c.teacher_id });
      eleves.forEach(s => {
        db.grades.push({ id:`g_${s.id}_${m.id}_${d}`, sid:s.id, cid:c.id, devoir_id:did,
                         matiere:m.name, trimestre:'T1', max:m.maxima,
                         note: Math.round(m.maxima * (0.35 + r() * 0.6)) });
      });
    }
  });
});

// ── Sortie ───────────────────────────────────────────────────────────────────
if (process.argv.includes('--resume')) {
  const par = t => db.students.filter(s => {
    const p = db.payments.filter(x => x.sid === s.id);
    const n = p.filter(x => x.paid).length;
    return t === 'total' ? n === 4 : t === 'partiel' ? (n > 0 && n < 4) : n === 0;
  }).length;
  const familles = new Set(db.students.map(s => s.pid)).size;
  console.log(`
  JEU D'ESSAI — aucune donnée réelle

    ${db.students.length} élèves · ${db.classes.length} classes · ${familles} familles
    ${db.users.filter(u=>u.role==='parent').length} parents · ${db.users.filter(u=>u.role.startsWith('enseignant')).length} enseignants · ${db.users.length} comptes
    ${db.grades.length} cotes · ${db.devoirs.length} devoirs · ${db.matieres.length} matières
    ${db.attendance.length} présences · ${db.scan_log.length} scans dont 5 REFUS
    ${db.payments.length} lignes de paiement

    à jour ${par('total')} · PARTIELS ${par('partiel')} · rien ${par('rien')}
    fratries : ${db.students.length - familles} élèves partagent un parent

  Ce que ce jeu doit faire apparaître :
    · les partiels — le modèle actuel les traite comme « rien payé »
    · les 5 refus — l'espace parent les annonce « Arrivé(e) à l'école »
    · les fratries — le sélecteur multi-enfants
    · le volume — ${db.grades.length} cotes tirées par chaque téléphone aujourd'hui
`);
} else {
  process.stdout.write(JSON.stringify(db));
}
