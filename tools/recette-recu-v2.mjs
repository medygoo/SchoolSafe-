import fs from 'node:fs';

const src = fs.readFileSync(new URL('../dist/recu-paiement-v2.js', import.meta.url), 'utf8');
let failed = 0;
const ok = (name, cond) => {
  console.log(`${cond ? '✓' : '✗'} ${name}`);
  if (!cond) failed++;
};

ok('devise officielle présente', src.includes('Former, Réformer, Exceller'));
ok('ancienne devise absente', !src.includes('Éducation d’Excellence, Discipline et Valeurs'));
ok('format demi-A4 / A5 paysage', /@page\{size:A5 landscape/.test(src));
ok('montant reçu fortement agrandi', /field\.amount \.value\{font-size:29px/.test(src));
ok('montants payés du tableau agrandis', /paid-money\{font-size:20px/.test(src));
ok('version mobile garde les montants payés visibles', /paid-money\{font-size:19px/.test(src));
ok('logo dynamique de l’école', src.includes("window.SCHOOL_LOGO || window.SCHOOL_LOGO_DOC || './logo.jpg'"));
ok('zones de signatures prévues', src.includes('LU ET APPROUVÉ') && src.includes('ÉTABLI PAR') && src.includes('VISA &amp; CACHET DE L’ÉCOLE'));
ok('aucune signature automatique', !src.includes('SCHOOL_SIGNATURE') && !src.includes('_officialFooter'));
ok('versement réel relié au gabarit', src.includes('schoolReceiptV2FromVersement') && src.includes('DB.versements'));
ok('reçu parent relié au même gabarit', src.includes('parentReceiptV2FromNotification') && src.includes('viewReceiptV2'));
ok('mode de paiement inclus', src.includes('payment_method'));
ok('référence externe incluse', src.includes('payment_reference'));
ok('duplicata prévu', src.includes('DUPLICATA'));
ok('contrepassation visible', src.includes('PAIEMENT ANNULÉ / CONTREPASSÉ'));
ok('aucune donnée élève exemple en dur', !/LOMELA|LS2024|6ème A/.test(src));

if (failed) {
  console.error(`\n${failed} contrôle(s) en échec.`);
  process.exit(1);
}
console.log('\n16/16 — reçu V2 prêt à brancher lors de la bascule Finance/RH finale.');
