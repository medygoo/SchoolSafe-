/* ══════════════════════════════════════════════════════════════════════════
   Préinscription en ligne — Complexe Scolaire Le Sage

   ÉTAPE 1 : elle ne dépend d'aucun serveur.

   Le parent remplit la fiche sur son téléphone, et repart avec deux choses :
     · un message WhatsApp prêt à envoyer à la Direction ;
     · une fiche imprimable, aux couleurs et à l'emblème de l'école.

   Pourquoi commencer ainsi. Le site est statique — déposé par FTP chez LWS.
   Attendre la base pour ouvrir la préinscription, c'est perdre la rentrée.
   Ici, la famille arrive à l'école avec ses renseignements déjà écrits, et la
   Direction n'a plus qu'à confirmer et encaisser.

   AUCUN PAIEMENT NE PASSE PAR CE SITE. Le versement se fait à la Caisse,
   contre un reçu. Un site scolaire qui demanderait de l'argent en ligne serait
   la première chose qu'un escroc imiterait.

   ÉTAPE 2, quand la base sera prête : le même formulaire écrira une demande
   dans le projet Supabase de l'école, et la Direction la verra tomber dans
   SchoolSafe. Les champs ci-dessous portent DÉJÀ les noms de l'application
   (nom, dob, lieu_naissance, adresse, nom_papa, nom_maman, blood_group,
   medical_notes) pour que ce passage ne demande aucune ressaisie.
   ══════════════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';
  var form = document.getElementById('fiche-preinscription');
  if (!form) return;

  // ── LE SERVEUR ──────────────────────────────────────────────────────────
  // La clé publique (« anon ») n'est pas un secret : elle ne donne accès qu'à
  // ce que les politiques RLS autorisent. ChatGPT l'a confirmé par écrit le
  // 4 août 2026, après vérification : le rôle anon peut appeler
  // submit_preinscription, mais ne peut ni lire la table des demandes, ni lire
  // public.users. Un parent ne verra donc jamais la fiche d'une autre famille.
  var SUPA_URL = 'https://lcnronymkccgyltttqry.supabase.co';
  var SUPA_KEY = 'sb_publishable_riSfIF1hT5-imh4uq4bUmQ_b5poe7hG';

  var TEL_DIRECTION = '243978444167';
  var ECOLE  = 'COMPLEXE SCOLAIRE LE SAGE';
  var ECOLE2 = 'The Wise School International';
  var ADRESSE = 'Kabambare 4367, Quartier Bon Marché, Commune de Barumbu — Kinshasa, RDC';

  var CHAMPS = [
    ['nom',              "Nom de l'élève"],
    ['sexe',             'Sexe'],
    ['dob',              'Date de naissance'],
    ['lieu_naissance',   'Lieu de naissance'],
    ['classe',           'Classe demandée'],
    ['ecole_provenance', 'École de provenance'],
    ['nom_papa',         'Nom du père'],
    ['nom_maman',        'Nom de la mère'],
    ['telephone',        'Téléphone'],
    ['telephone2',       'Second téléphone'],
    ['adresse',          'Adresse'],
    ['email',            'E-mail'],
    ['blood_group',      'Groupe sanguin'],
    ['urgence',          'À prévenir en urgence'],
    ['medical_notes',    'Santé'],
    // La tutelle et les trois personnes autorisées. Sans photo : elles se
    // prennent à l'école, à la validation. Un gardien doit reconnaître un
    // visage en trois secondes au portail — une photo de WhatsApp n'y suffit
    // pas, et un formulaire public n'est pas un endroit où déposer la photo
    // d'un enfant.
    ['tutelle',          'Tuteur principal'],
    ['a1_nom',           'Autorisée 1 — nom'],
    ['a1_relation',      'Autorisée 1 — lien'],
    ['a1_telephone',     'Autorisée 1 — téléphone'],
    ['a2_nom',           'Autorisée 2 — nom'],
    ['a2_relation',      'Autorisée 2 — lien'],
    ['a2_telephone',     'Autorisée 2 — téléphone'],
    ['a3_nom',           'Autorisée 3 — nom'],
    ['a3_relation',      'Autorisée 3 — lien'],
    ['a3_telephone',     'Autorisée 3 — téléphone']
  ];

  function valeurs() {
    var d = {};
    CHAMPS.forEach(function (c) {
      var el = form.elements[c[0]];
      d[c[0]] = el ? String(el.value || '').trim() : '';
    });
    return d;
  }

  function dire(texte, ok) {
    var m = document.getElementById('f_message');
    m.hidden = false;
    m.className = 'full msg ' + (ok ? 'msg-ok' : 'msg-non');
    m.textContent = texte;
    m.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }

  // Les champs obligatoires — vérifiés nous-mêmes pour pouvoir dire LEQUEL
  // manque. « Veuillez remplir ce champ » sur un formulaire de quinze lignes
  // ne dit pas où regarder.
  function manquant(d) {
    var requis = [['nom', "le nom de l'élève"], ['sexe', 'le sexe'],
                  ['dob', 'la date de naissance'], ['classe', 'la classe demandée'],
                  ['telephone', 'le téléphone du parent'],
                  ['tutelle', 'le tuteur principal']];
    for (var i = 0; i < requis.length; i++) {
      if (!d[requis[i][0]]) {
        var el = form.elements[requis[i][0]];
        if (el) { el.focus(); }
        return requis[i][1];
      }
    }
    return null;
  }

  function dateFr(iso) {
    if (!iso) return '';
    var p = iso.split('-');
    return p.length === 3 ? p[2] + '/' + p[1] + '/' + p[0] : iso;
  }

  // ── WhatsApp ────────────────────────────────────────────────────────────
  document.getElementById('f_whatsapp').addEventListener('click', function () {
    var d = valeurs();
    var quoi = manquant(d);
    if (quoi) { dire('Il manque ' + quoi + '.', false); return; }

    var l = ['*PRÉINSCRIPTION — ' + ECOLE + '*', 'Année scolaire 2026-2027', ''];
    CHAMPS.forEach(function (c) {
      var v = d[c[0]];
      if (!v) return;                                  // une ligne vide ne s'écrit pas
      l.push('*' + c[1] + ' :* ' + (c[0] === 'dob' ? dateFr(v) : v));
    });
    l.push('', 'Fiche remplie depuis cslesage.com');

    window.open('https://wa.me/' + TEL_DIRECTION + '?text=' +
      encodeURIComponent(l.join('\n')), '_blank');
    dire('WhatsApp s\'ouvre avec votre fiche. Envoyez le message à la Direction, ' +
         'puis passez à l\'école pour la confirmation et le paiement.', true);
  });

  // ── Impression ──────────────────────────────────────────────────────────
  // Le navigateur imprime : vraies polices, texte sélectionnable, « Enregistrer
  // au format PDF » offert partout. On ne photographie pas une page.
  document.getElementById('f_imprimer').addEventListener('click', function () {
    var d = valeurs();
    var quoi = manquant(d);
    if (quoi) { dire('Il manque ' + quoi + '.', false); return; }

    var lignes = CHAMPS.map(function (c) {
      var v = d[c[0]];
      // Ne rien afficher vaut mieux qu'afficher faux : une ligne sans valeur
      // s'imprime vide, à remplir à la main, plutôt que de disparaître.
      return '<tr><th>' + c[1] + '</th><td>' +
        (v ? esc(c[0] === 'dob' ? dateFr(v) : v) : '&nbsp;') + '</td></tr>';
    }).join('');

    var w = window.open('', '_blank');
    if (!w) { dire('Votre navigateur a bloqué la fenêtre d\'impression. Autorisez-la, puis réessayez.', false); return; }
    w.document.write(
'<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8"><title>Fiche de renseignements — ' + esc(d.nom) + '</title><style>' +
'@page{size:A4;margin:14mm}' +
'*{box-sizing:border-box}body{font-family:Arial,Helvetica,sans-serif;color:#1a2228;margin:0;font-size:13px;line-height:1.5}' +
'.min{text-align:center;font-size:10px;letter-spacing:.04em;color:#5e6c78;text-transform:uppercase;line-height:1.6;margin-bottom:12px}' +
'.hdr{display:flex;gap:14px;align-items:flex-start;border-bottom:3px solid #556777;padding-bottom:12px;margin-bottom:6px}' +
'.hdr img{width:64px;height:64px;border-radius:50%;object-fit:cover;border:2px solid #c09018;flex:none}' +
'.hdr .t{font-size:17px;font-weight:800;color:#556777;line-height:1.15}' +
'.hdr .s{font-size:11px;color:#5e6c78}' +
'h1{font-size:15px;color:#556777;margin:18px 0 2px;letter-spacing:.04em}' +
'.date{font-size:11px;color:#5e6c78;margin-bottom:12px}' +
'table{width:100%;border-collapse:collapse;margin-bottom:16px}' +
'th{width:38%;text-align:left;font-weight:600;color:#5e6c78;padding:7px 10px;border-bottom:1px solid #dadee2;font-size:12px;vertical-align:top}' +
'td{padding:7px 10px;border-bottom:1px solid #dadee2;font-weight:700;vertical-align:top}' +
'.avis{background:#f0f1f2;border-left:3px solid #c09018;padding:10px 14px;font-size:11.5px;color:#1a2228;margin-bottom:18px}' +
'.sig{margin-top:26px;padding-top:14px;border-top:2px dashed #c09018;page-break-inside:avoid;break-inside:avoid;display:flex;gap:16px}' +
'.sig>div{flex:1;text-align:center}' +
'.sig .l{height:44px}' +
'.sig .n{border-top:1.5px solid #1a2228;padding-top:7px;font-size:11px;color:#5e6c78}' +
'.sig .n strong{display:block;font-size:12px;color:#1a2228}' +
'.pied{text-align:center;font-size:10px;color:#5e6c78;margin-top:10px}' +
'@media print{.noprint{display:none}}' +
'.noprint{text-align:center;margin-bottom:16px}' +
'.noprint button{background:#556777;color:#fff;border:0;border-radius:6px;padding:11px 26px;font-size:14px;font-weight:700;cursor:pointer}' +
'</style></head><body>' +
'<div class="noprint"><button onclick="window.print()">🖨️ Imprimer / Enregistrer en PDF</button></div>' +
'<div class="min">République Démocratique du Congo<br>Ministère de l\'Éducation Nationale et Nouvelle Citoyenneté</div>' +
'<div class="hdr"><img src="logo.jpg" alt=""><div><div class="t">' + ECOLE + '</div>' +
'<div class="s">' + ECOLE2 + '</div><div class="s">' + ADRESSE + '</div></div></div>' +
'<h1>FICHE DE RENSEIGNEMENTS DE L\'ÉLÈVE</h1>' +
'<div class="date">Année scolaire 2026-2027 · Kinshasa, le ' +
  new Date().toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' }) + '</div>' +
'<table>' + lignes + '</table>' +
'<div class="avis"><strong>Préinscription.</strong> Cette fiche a été remplie en ligne par la famille. ' +
'Elle ne vaut pas inscription : l\'inscription est confirmée à la Direction, après paiement de la ' +
'première tranche du minerval, contre un reçu de l\'école.</div>' +
'<div class="sig">' +
'<div><div class="l"></div><div class="n">Lu et approuvé<br><strong>' + esc(d.nom_papa || d.nom_maman || '……………………………') + '</strong><br>Parent / Tuteur</div></div>' +
'<div><div class="l"></div><div class="n">Reçu par<br><strong>……………………………</strong><br>Secrétariat</div></div>' +
'<div><div class="l"></div><div class="n">Visa &amp; cachet<br><strong>……………………………</strong><br>Direction Générale</div></div>' +
'</div>' +
'<div class="pied">' + ECOLE + ' · Tél : +243 978 444 167 · +243 816 722 901 · cslesage.com</div>' +
'</body></html>');
    w.document.close();
    dire('La fiche s\'ouvre dans un nouvel onglet. Imprimez-la ou enregistrez-la en PDF, ' +
         'puis apportez-la à l\'école.', true);
  });

  // ── ENVOI À L'ÉCOLE ─────────────────────────────────────────────────────
  // La demande part vers submit_preinscription. Le RPC accepte les champs
  // plats a1_nom, a1_relation… tels qu'ils sont dans le formulaire : aucune
  // transformation, donc aucune occasion de se tromper.
  //
  // WhatsApp et l'impression RESTENT. Une famille sans réseau, ou un envoi
  // qui échoue, ne doit pas perdre cinq minutes de saisie.
  var TRADUC = {
    ALREADY_SUBMITTED : "Cette demande a déjà été envoyée. L'école l'a bien reçue — inutile de recommencer.",
    INVALID_SUBMISSION: "La demande n'a pas pu être envoyée. Vérifiez les champs et réessayez.",
    RATE_LIMITED      : "Trop de demandes envoyées depuis ce numéro aujourd'hui. Réessayez demain, ou appelez l'école.",
    FORBIDDEN         : "L'envoi en ligne n'est pas autorisé pour le moment. Utilisez WhatsApp ou imprimez la fiche."
  };

  document.getElementById('f_envoyer').addEventListener('click', async function () {
    var d = valeurs();
    var quoi = manquant(d);
    if (quoi) { dire('Il manque ' + quoi + '.', false); return; }

    // Le piège anti-robot : trois champs invisibles. Un humain ne les voit
    // pas, un robot les remplit. S'ils portent quoi que ce soit, le serveur
    // refuse — c'est lui qui décide, pas nous.
    ['website', 'company', 'url'].forEach(function (k) {
      var el = form.elements[k]; d[k] = el ? el.value : '';
    });

    var b = document.getElementById('f_envoyer');
    var libelle = b.textContent;
    b.disabled = true; b.textContent = '⏳ Envoi…';
    try {
      var r = await fetch(SUPA_URL + '/rest/v1/rpc/submit_preinscription', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', apikey: SUPA_KEY,
                   Authorization: 'Bearer ' + SUPA_KEY },
        body: JSON.stringify({ p_request: d })
      });
      var j = null; try { j = await r.json(); } catch (e) {}

      if (r.ok && j && j.ok) {
        dire("✅ Votre demande est arrivée à l'école. La Direction va l'examiner. "
           + "Passez ensuite à l'école pour la confirmation et le paiement de la "
           + "première tranche — apportez la fiche imprimée.", true);
        form.querySelectorAll('button').forEach(function (x) { if (x.id === 'f_envoyer') x.disabled = true; });
        return;
      }
      var code = (j && (j.code || j.message)) || ('HTTP ' + r.status);
      // On ne prétend pas avoir envoyé ce qui n'est pas parti. On dit ce qui
      // s'est passé, et on rappelle les deux autres chemins.
      dire((TRADUC[code] || "L'envoi n'a pas abouti (" + code + ").")
         + " Vous pouvez envoyer la fiche par WhatsApp ou l'imprimer — vos "
         + "renseignements sont toujours là.", false);
    } catch (e) {
      dire("L'envoi n'a pas abouti : pas de connexion. Envoyez la fiche par "
         + "WhatsApp, ou imprimez-la et apportez-la à l'école. Vos "
         + "renseignements sont toujours là.", false);
    } finally { b.disabled = false; b.textContent = libelle; }
  });

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  // ── Les affiches s'agrandissent ─────────────────────────────────────────
  var lb = document.getElementById('lb'), lbImg = document.getElementById('lb-img'),
      lbCap = document.getElementById('lb-cap');
  if (lb) {
    document.querySelectorAll('.billet img, .affiche img').forEach(function (im) {
      im.style.cursor = 'zoom-in';
      im.addEventListener('click', function () {
        lbImg.src = im.src; lbCap.textContent = im.alt || '';
        lb.classList.add('open');
      });
    });
    var fermer = function () { lb.classList.remove('open'); };
    lb.addEventListener('click', fermer);
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') fermer(); });
  }
})();
