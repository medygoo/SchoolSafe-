// SchoolSafe — politique documents officiels PDF (Le Sage)
(function () {
  'use strict';
  if (window.__SS_DOCUMENTS_PDF_POLICY__) return;
  window.__SS_DOCUMENTS_PDF_POLICY__ = { version:'2026-08-12.1', installed:false };

  const OFFICIAL = Object.freeze({
    name: 'Complexe Scolaire Le Sage',
    subtitle: 'The Wise School International',
    motto: 'Former, Réformer, Exceller'
  });
  window.SCHOOL_OFFICIAL_IDENTITY = OFFICIAL;

  // Identité unique de cette installation : une seule école.
  window._ecoleDocIdentite = () => {
    const sc = (window.DB && DB.settings && DB.settings.school) || {};
    return {
      name: OFFICIAL.name,
      subtitle: OFFICIAL.subtitle,
      motto: OFFICIAL.motto,
      year: (window.DB && DB.settings && DB.settings.year) || (window.S && S.year) || '',
      address: sc.address || '', phone: sc.phone || '', email: sc.email || ''
    };
  };

  const install = () => {
    if (window.__SS_DOCUMENTS_PDF_POLICY__.installed) return true;
    if (typeof window.openM !== 'function' || typeof window.printListeTuteurs !== 'function') return false;

    // La liste officielle Élèves + tuteurs est proposée en PDF uniquement.
    // L'export CSV peut rester disponible comme donnée technique dans le code,
    // mais n'est plus présenté comme une seconde version du document officiel.
    window.ouvrirListeTuteurs = () => {
      if (typeof window._denyRole === 'function' && _denyRole('direction','direction2')) return;
      const opts = ((window.DB && DB.classes) || [])
        .filter(c => ((DB.students)||[]).some(s => s.cid === c.id && !s.archived))
        .map(c => `<option value="${c.id}">${typeof esc === 'function' ? esc(c.name) : c.name}</option>`).join('');
      openM('👨‍👩‍👧 Élèves et tuteurs — PDF', `
        <div class="form-group">
          <label class="form-label">Portée</label>
          <select class="form-input" id="lt_cid">
            <option value="">🏫 Toute l’école</option>${opts}
          </select>
        </div>
        <div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:10px;padding:11px 13px;font-size:12px;line-height:1.55">
          Le document officiel est généré en <strong>PDF</strong> avec le logo du <strong>Complexe Scolaire Le Sage</strong>.
          Il reprend, pour chaque élève, les parents/tuteurs et les personnes autorisées enregistrées.
        </div>`,
        `<button class="btn btn-outline" onclick="closeModal()">Annuler</button>
         <button class="btn btn-primary" onclick="printListeTuteurs($('lt_cid').value||null)">📄 Télécharger le PDF</button>`);
    };

    // Les CSV existants sont clairement identifiés comme exports de DONNÉES,
    // pas comme documents officiels. On ne supprime pas les outils d'import/export
    // utiles à l'administration.
    const relabelDataExports = root => {
      (root || document).querySelectorAll?.('button[onclick*="exportCSV("]').forEach(btn => {
        if (!/Données/i.test(btn.textContent || '')) btn.textContent = '📊 Données CSV — export technique';
        btn.title = 'Export technique de données — le document officiel est en PDF';
      });
    };
    relabelDataExports(document);
    if (document.body && window.MutationObserver) {
      new MutationObserver(() => relabelDataExports(document)).observe(document.body, { childList:true, subtree:true });
    }

    window.__SS_DOCUMENTS_PDF_POLICY__.installed = true;
    return true;
  };

  if (install()) return;
  const started = Date.now();
  const timer = setInterval(() => {
    if (install() || Date.now() - started > 15000) clearInterval(timer);
  }, 100);
})();
