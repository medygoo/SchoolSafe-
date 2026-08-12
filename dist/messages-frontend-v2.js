/*
 * SchoolSafe — Messages frontend V2
 * Contrat validé par Loms, 12 août 2026.
 *
 * FRONT-END UNIQUEMENT : ce fichier ne crée aucune colonne, policy RLS ou RPC.
 * Les protections serveur et la persistance multi-appareil de lecture/archivage
 * restent un chantier backend distinct avant activation définitive.
 */
(function () {
  'use strict';

  if (window.__SS_MESSAGES_FRONTEND_V2__) return;
  window.__SS_MESSAGES_FRONTEND_V2__ = { version: '2026-08-12', installed: false };

  const INSTALL_EVERY_MS = 100;
  const INSTALL_TIMEOUT_MS = 20000;
  const startedAt = Date.now();

  const install = () => {
    if (window.__SS_MESSAGES_FRONTEND_V2__.installed) return true;
    if (typeof R === 'undefined' || !R || typeof R.messages !== 'function') return false;
    if (typeof window.openComposeMsg !== 'function' || typeof window.sendMsg !== 'function') return false;

    const original = {
      messages: R.messages,
      openComposeMsg: window.openComposeMsg,
      sendMsg: window.sendMsg,
      deleteMessage: window.deleteMessage,
      markMsgRead: window.markMsgRead,
      markAllMsgRead: window.markAllMsgRead,
    };
    window.__SS_MESSAGES_FRONTEND_V2__.original = original;

    const roleUI = r => (typeof window._roleUI === 'function' ? window._roleUI(r) : r);
    const isDirection = () => !!(S.user && ['direction', 'direction2'].includes(roleUI(S.user.role)));
    const currentUid = () => (S.user && S.user.id) || 'anonymous';
    const escHtml = value => (typeof esc === 'function'
      ? esc(String(value == null ? '' : value))
      : String(value == null ? '' : value).replace(/[&<>\"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[c])));

    const storageSet = key => {
      try { return new Set(JSON.parse(localStorage.getItem(key) || '[]')); }
      catch (_) { return new Set(); }
    };
    const saveSet = (key, set) => localStorage.setItem(key, JSON.stringify([...set]));
    const archiveKey = () => `ss_msg_archived_v2_${currentUid()}`;
    const readKey = () => `ss_msg_read_v2_${currentUid()}`;
    const routeKey = () => `ss_msg_routes_v2_${currentUid()}`;

    const routeMap = () => {
      try { return JSON.parse(localStorage.getItem(routeKey()) || '{}') || {}; }
      catch (_) { return {}; }
    };
    const saveRouteMap = map => localStorage.setItem(routeKey(), JSON.stringify(map || {}));

    const isArchived = mid => storageSet(archiveKey()).has(mid);
    const isCollective = m => !!(m && (
      m.to_role || m.to_class_cid || m.to_class ||
      String(m.to || '').startsWith('role:') || String(m.to || '').startsWith('class:')
    ));
    const isReadForMe = m => {
      if (!m) return true;
      const local = storageSet(readKey()).has(m.id);
      return isCollective(m) ? local : (local || !!m.read);
    };

    const messageForMe = m => {
      if (!m || !S.user) return false;
      const role = roleUI(S.user.role);
      const uid = S.user.id;
      const kidCids = role === 'parent'
        ? (DB.students || []).filter(s => s.pid === uid).map(s => s.cid)
        : [];
      if (typeof window._msgPourMoi === 'function' && window._msgPourMoi(m, uid, role, kidCids)) return true;
      return ['direction', 'direction2'].includes(role) && m.from_role === 'parent' && m.status === 'sent';
    };

    const explanation = () => {
      const role = roleUI(S.user && S.user.role);
      let text = 'Cette page centralise les messages internes de l’école et conserve leur historique.';
      if (role === 'parent') {
        text = 'Écrivez uniquement à la Direction 1 / Direction 2. La Direction transmettra votre demande à l’enseignant concerné si nécessaire : aucun échange direct Parent ↔ Enseignant.';
      } else if (role === 'enseignant') {
        text = 'Vous répondez aux messages transmis par la Direction. Pour les familles, vous pouvez préparer un seul message collectif destiné à tous les parents de votre classe ; la Direction doit l’approuver avant l’envoi.';
      } else if (['direction', 'direction2'].includes(role)) {
        text = 'La Direction centralise les échanges : elle reçoit les parents, transmet au seul enseignant concerné, reçoit sa réponse et la renvoie au parent. Elle approuve aussi les messages collectifs des enseignants.';
      }
      return `<div class="premium-section" style="border-left:4px solid var(--primary);padding:14px 16px;margin-bottom:14px">
        <div style="font-weight:800;font-size:14px;margin-bottom:4px">💬 À quoi sert cette page ?</div>
        <div style="font-size:12.5px;line-height:1.55;color:var(--text-secondary)">${escHtml(text)}</div>
      </div>`;
    };

    const routingPanel = () => {
      if (!isDirection()) return '';
      const active = (DB.messages || []).filter(m => !isArchived(m.id) && m.status === 'sent');
      const parentMsgs = active.filter(m => m.from_role === 'parent').slice().sort((a,b)=>(b.date||'').localeCompare(a.date||'')||(b.time||'').localeCompare(a.time||'')).slice(0,5);
      const teacherMsgs = active.filter(m => m.from_role === 'enseignant' && messageForMe(m)).slice().sort((a,b)=>(b.date||'').localeCompare(a.date||'')||(b.time||'').localeCompare(a.time||'')).slice(0,5);

      const parentRows = parentMsgs.map(m => {
        const p = (DB.users || []).find(u => u.id === m.from);
        return `<div style="display:flex;align-items:center;gap:9px;padding:8px 0;border-bottom:1px solid var(--border)">
          <div style="flex:1;min-width:0"><div style="font-size:12px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${escHtml(p?.name || 'Parent')} — ${escHtml(m.subject || 'Message')}</div>
          <div style="font-size:11px;color:var(--text-muted)">${escHtml(m.date || '')} ${escHtml(m.time || '')}</div></div>
          <button class="btn btn-outline btn-sm" onclick="openForwardParentMessage('${m.id}')">➡️ Enseignant</button>
        </div>`;
      }).join('');

      const teacherRows = teacherMsgs.map(m => {
        const t = (DB.users || []).find(u => u.id === m.from);
        return `<div style="display:flex;align-items:center;gap:9px;padding:8px 0;border-bottom:1px solid var(--border)">
          <div style="flex:1;min-width:0"><div style="font-size:12px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${escHtml(t?.name || 'Enseignant')} — ${escHtml(m.subject || 'Réponse')}</div>
          <div style="font-size:11px;color:var(--text-muted)">${escHtml(m.date || '')} ${escHtml(m.time || '')}</div></div>
          <button class="btn btn-outline btn-sm" onclick="openRelayTeacherMessage('${m.id}')">↪️ Parent</button>
        </div>`;
      }).join('');

      return `<div class="premium-section" style="margin-bottom:14px">
        <div style="display:flex;align-items:center;gap:8px;margin-bottom:10px;flex-wrap:wrap">
          <div style="font-weight:800;flex:1">🔀 Routage Direction</div>
          <button class="btn btn-outline btn-sm" onclick="openArchivedMessages()">🗃️ Archives</button>
        </div>
        <div style="font-size:11.5px;color:var(--text-muted);margin-bottom:8px">Parent → Direction → enseignant concerné → Direction → parent</div>
        ${parentRows ? `<div style="font-size:11px;font-weight:800;text-transform:uppercase;color:var(--text-muted);margin-top:8px">Parents à transmettre</div>${parentRows}` : ''}
        ${teacherRows ? `<div style="font-size:11px;font-weight:800;text-transform:uppercase;color:var(--text-muted);margin-top:12px">Réponses enseignants</div>${teacherRows}` : ''}
        ${!parentRows && !teacherRows ? '<div style="font-size:12px;color:var(--text-muted);padding:8px 0">Aucun message à router pour le moment.</div>' : ''}
      </div>`;
    };

    R.messages = () => {
      const realMessages = DB.messages || [];
      try {
        DB.messages = realMessages
          .filter(m => !isArchived(m.id))
          .map(m => ({ ...m, read: isReadForMe(m) }));
        let html = original.messages();
        html = String(html).replace(/(onclick=\"deleteMessage\('[^']+'\)\"[^>]*>)[^<]*(<\/button>)/g, '$1🗃️ Archiver$2');
        return explanation() + routingPanel() + html;
      } finally {
        DB.messages = realMessages;
      }
    };

    window.markMsgRead = mid => {
      const m = (DB.messages || []).find(x => x.id === mid);
      if (!m || !messageForMe(m)) return;
      const set = storageSet(readKey());
      set.add(mid); saveSet(readKey(), set);
      if (!isCollective(m)) {
        m.read = true;
        try { pushSync('messages', 'patch', { read:true }, 'id=eq.' + mid); } catch (_) {}
      }
      try { saveToCrypt(); } catch (_) {}
      render();
    };

    window.markAllMsgRead = () => {
      const set = storageSet(readKey());
      (DB.messages || []).forEach(m => {
        if (m.status !== 'sent' || !messageForMe(m)) return;
        set.add(m.id);
        if (!isCollective(m) && !m.read) {
          m.read = true;
          try { pushSync('messages', 'patch', { read:true }, 'id=eq.' + m.id); } catch (_) {}
        }
      });
      saveSet(readKey(), set);
      try { saveToCrypt(); } catch (_) {}
      render(); toast('Tous les messages visibles sont marqués comme lus', 'success');
    };

    window.deleteMessage = id => {
      const m = (DB.messages || []).find(x => x.id === id);
      if (!m || !S.user) return;
      const allowed = m.from === S.user.id || isDirection() || messageForMe(m);
      if (!allowed) { toast('Accès non autorisé', 'error'); return; }
      showC('Archiver ce message ?', 'Le message disparaîtra de votre boîte active mais ne sera pas supprimé de l’historique serveur.', () => {
        const set = storageSet(archiveKey());
        set.add(id); saveSet(archiveKey(), set);
        render(); toast('Message archivé', 'success');
      });
    };

    window.restoreArchivedMessage = id => {
      const set = storageSet(archiveKey());
      set.delete(id); saveSet(archiveKey(), set);
      closeModal(); render(); toast('Message restauré', 'success');
    };

    window.openArchivedMessages = () => {
      const ids = storageSet(archiveKey());
      const rows = (DB.messages || []).filter(m => ids.has(m.id));
      const body = rows.length ? rows.map(m => {
        const from = (DB.users || []).find(u => u.id === m.from);
        return `<div style="padding:10px 0;border-bottom:1px solid var(--border)">
          <div style="font-weight:700;font-size:13px">${escHtml(m.subject || 'Message')}</div>
          <div style="font-size:11px;color:var(--text-muted);margin:2px 0 7px">${escHtml(from?.name || '')} · ${escHtml(m.date || '')} ${escHtml(m.time || '')}</div>
          <button class="btn btn-outline btn-sm" onclick="restoreArchivedMessage('${m.id}')">↩️ Restaurer</button>
        </div>`;
      }).join('') : '<div style="text-align:center;padding:30px;color:var(--text-muted)">Aucun message archivé sur cet appareil.</div>';
      openM('🗃️ Messages archivés', body, '<button class="btn btn-outline" onclick="closeModal()">Fermer</button>');
    };

    const openParentCompose = () => {
      openM('✉️ Écrire à la Direction', `
        <div style="background:var(--info-bg);border:1px solid var(--info-border);padding:10px 12px;border-radius:10px;margin-bottom:12px;font-size:12px;color:var(--text-secondary)">
          Votre message est reçu par <strong>Direction 1 et Direction 2</strong>. Si un enseignant doit intervenir, la Direction lui transmettra le message.
        </div>
        <div class="form-group"><label class="form-label">Type de message</label>
          <select class="form-select" id="msg_type">
            <option value="question">❓ Question</option>
            <option value="rdv">📅 Demande de rendez-vous</option>
            <option value="reclamation">⚠️ Réclamation</option>
            <option value="normal">✉️ Autre</option>
          </select>
        </div>
        <div class="form-group"><label class="form-label">Objet *</label><input class="form-input" id="msg_subject" placeholder="Objet du message"></div>
        <div class="form-group"><label class="form-label">Message *</label><textarea class="form-input" id="msg_body" rows="5" style="resize:vertical" placeholder="Votre message à la Direction..."></textarea></div>`,
        '<button class="btn btn-outline" onclick="closeModal()">Annuler</button><button class="btn btn-primary" onclick="sendMsg(\'parent_to_dir\')">📤 Envoyer à la Direction</button>'
      );
    };

    const openDirectionCompose = () => {
      const parents = (DB.users || []).filter(u => roleUI(u.role) === 'parent');
      const teachers = (DB.users || []).filter(u => roleUI(u.role) === 'enseignant');
      const d2 = (DB.users || []).filter(u => roleUI(u.role) === 'direction2');
      const caisse = (DB.users || []).filter(u => roleUI(u.role) === 'direction3');
      const guards = (DB.users || []).filter(u => roleUI(u.role) === 'gardien');
      const classes = DB.classes || [];
      const options = arr => arr.map(u => `<option value="uid:${u.id}">👤 ${escHtml(u.name)}</option>`).join('');
      openM('Nouveau message', `
        <div class="form-group"><label class="form-label">Type de message</label>
          <select class="form-select" id="msg_type" onchange="if(typeof applyDirMsgTemplate==='function')applyDirMsgTemplate()">
            <option value="normal">✉️ Message standard</option><option value="convocation">📋 Convocation</option><option value="annonce">📣 Annonce générale</option><option value="info">ℹ️ Information</option>
          </select>
        </div>
        <div class="form-group"><label class="form-label">Destinataire *</label>
          <select class="form-select" id="msg_to">
            <option value="">— Choisir —</option>
            <optgroup label="👨‍👩‍👧 Parents"><option value="role:parent">📢 Tous les parents</option>${options(parents)}</optgroup>
            ${classes.length ? `<optgroup label="🏫 Classes">${classes.map(c => `<option value="class:${c.id}">Parents — ${escHtml(c.name)}</option>`).join('')}</optgroup>` : ''}
            ${teachers.length ? `<optgroup label="👨‍🏫 Enseignants"><option value="role:enseignant">📢 Tous les enseignants</option>${options(teachers)}</optgroup>` : ''}
            ${d2.length ? `<optgroup label="🏛️ Direction 2">${options(d2)}</optgroup>` : ''}
            ${caisse.length ? `<optgroup label="💵 Caisse">${options(caisse)}</optgroup>` : ''}
            ${guards.length ? `<optgroup label="🛡️ Gardien">${options(guards)}</optgroup>` : ''}
          </select>
        </div>
        <div class="form-group"><label class="form-label">Objet *</label><input class="form-input" id="msg_subject" placeholder="Objet du message"></div>
        <div class="form-group"><label class="form-label">Message *</label><textarea class="form-input" id="msg_body" rows="5" style="resize:vertical"></textarea></div>`,
        '<button class="btn btn-outline" onclick="closeModal()">Annuler</button><button class="btn btn-primary" onclick="sendMsg(\'dir_send_v2\')">📤 Envoyer</button>'
      );
    };

    window.openComposeMsg = () => {
      const role = roleUI(S.user && S.user.role);
      if (role === 'parent') return openParentCompose();
      if (['direction', 'direction2'].includes(role)) return openDirectionCompose();
      return original.openComposeMsg();
    };

    const pushEncryptedMessage = async (msg, targets) => {
      (DB.messages = DB.messages || []).push(msg);
      let encS, encB;
      try {
        encS = await _encryptMsgField(msg.subject);
        encB = await _encryptMsgField(msg.body);
      } catch (e) {
        DB.messages = DB.messages.filter(x => x.id !== msg.id);
        toast('Message non envoyé — le chiffrement a échoué', 'error');
        return false;
      }
      try { pushSync('messages', 'post', { ...msg, subject:encS, body:encB }); }
      catch (e) {
        DB.messages = DB.messages.filter(x => x.id !== msg.id);
        toast('Message non envoyé', 'error');
        return false;
      }
      (targets || []).filter(Boolean).forEach(u => {
        const n = { id:_uid('n_'), uid:u.id, msg:`✉️ ${S.user.name} : “${msg.subject}”`, time:nowTime(), date:today(), read:false, type:'info' };
        (DB.notifs = DB.notifs || []).unshift(n);
        try { pushSync('notifs', 'post', n); } catch (_) {}
      });
      try { saveToCrypt(); } catch (_) {}
      return true;
    };

    const sendParentToDirections = async () => {
      if (roleUI(S.user && S.user.role) !== 'parent') { toast('Accès non autorisé', 'error'); return; }
      const subject = (($('msg_subject') || {}).value || '').trim();
      const body = (($('msg_body') || {}).value || '').trim();
      const msgType = (($('msg_type') || {}).value || 'normal');
      if (!subject) { toast('Entrez un objet', 'error'); return; }
      if (!body) { toast('Entrez un message', 'error'); return; }
      const directions = (DB.users || []).filter(u => ['direction', 'direction2'].includes(roleUI(u.role)));
      if (!directions.length) { toast('Aucune Direction disponible', 'error'); return; }
      const msg = { id:_uid('msg_'), from:S.user.id, from_role:'parent', to:null, to_role:'direction', to_class_cid:null,
        subject, body, msg_type:msgType, date:today(), time:nowTime(), status:'sent', read:false };
      if (!(await pushEncryptedMessage(msg, []))) return;
      directions.forEach(u => {
        const n = { id:_uid('n_'), uid:u.id, msg:`📨 MESSAGE PARENT — ${S.user.name} : “${subject}”`, time:nowTime(), date:today(), read:false, type:'alert' };
        (DB.notifs = DB.notifs || []).unshift(n);
        try { pushSync('notifs', 'post', n); } catch (_) {}
      });
      closeModal(); render(); toast('Message envoyé à la Direction 1 / Direction 2', 'success');
    };

    const sendDirectionV2 = async () => {
      if (!isDirection()) { toast('Accès non autorisé', 'error'); return; }
      const subject = (($('msg_subject') || {}).value || '').trim();
      const body = (($('msg_body') || {}).value || '').trim();
      const msgType = (($('msg_type') || {}).value || 'normal');
      const toVal = (($('msg_to') || {}).value || '').trim();
      if (!toVal) { toast('Sélectionnez un destinataire', 'error'); return; }
      if (!subject) { toast('Entrez un objet', 'error'); return; }
      if (!body) { toast('Entrez un message', 'error'); return; }

      let to = null, toRole = null, toClassCid = null, targets = [];
      if (toVal.startsWith('uid:')) {
        const uid = toVal.slice(4); const u = (DB.users || []).find(x => x.id === uid);
        if (!u) { toast('Destinataire introuvable', 'error'); return; }
        to = uid; targets = [u];
      } else if (toVal.startsWith('role:')) {
        toRole = toVal.slice(5);
        targets = (DB.users || []).filter(u => roleUI(u.role) === toRole);
      } else if (toVal.startsWith('class:')) {
        toClassCid = toVal.slice(6); to = 'class:' + toClassCid;
        const pids = [...new Set((DB.students || []).filter(s => s.cid === toClassCid).map(s => s.pid).filter(Boolean))];
        targets = (DB.users || []).filter(u => pids.includes(u.id));
      } else { toast('Destinataire invalide', 'error'); return; }

      const msg = { id:_uid('msg_'), from:S.user.id, from_role:roleUI(S.user.role), to, to_role:toRole, to_class_cid:toClassCid,
        subject, body, msg_type:msgType, date:today(), time:nowTime(), status:'sent', read:false };
      if (!(await pushEncryptedMessage(msg, targets))) return;
      closeModal(); render(); toast(`Message envoyé à ${targets.length || 1} destinataire(s)`, 'success');
    };

    window.sendMsg = async mode => {
      const role = roleUI(S.user && S.user.role);
      if (role === 'parent' && (mode === 'parent_to_dir' || mode === 'parent_direct')) return sendParentToDirections();
      if (['direction', 'direction2'].includes(role) && mode === 'dir_send_v2') return sendDirectionV2();
      return original.sendMsg(mode);
    };

    const teachersForParentMessage = m => {
      const kids = (DB.students || []).filter(s => s.pid === m.from && !s.archived);
      const out = [];
      kids.forEach(st => {
        const cl = (DB.classes || []).find(c => c.id === st.cid);
        if (!cl) return;
        [cl.teacher_id, cl.teacher_id_en].filter(Boolean).forEach(tid => {
          const t = (DB.users || []).find(u => u.id === tid && roleUI(u.role) === 'enseignant');
          if (!t) return;
          const found = out.find(x => x.teacher.id === t.id);
          if (found) found.context.push(`${st.name} — ${cl.name}`);
          else out.push({ teacher:t, context:[`${st.name} — ${cl.name}`] });
        });
      });
      return out;
    };

    window.openForwardParentMessage = mid => {
      if (!isDirection()) { toast('Accès non autorisé', 'error'); return; }
      const m = (DB.messages || []).find(x => x.id === mid && x.from_role === 'parent');
      if (!m) { toast('Message parent introuvable', 'error'); return; }
      const parent = (DB.users || []).find(u => u.id === m.from);
      const candidates = teachersForParentMessage(m);
      if (!candidates.length) { toast('Aucun enseignant affecté aux enfants de ce parent', 'error'); return; }
      const options = candidates.map(x => `<option value="${x.teacher.id}">${escHtml(x.teacher.name)} — ${escHtml(x.context.join(', '))}</option>`).join('');
      openM('➡️ Transmettre à l’enseignant concerné', `
        <div style="padding:10px 12px;background:var(--bg);border-radius:10px;margin-bottom:12px;font-size:12px"><strong>${escHtml(parent?.name || 'Parent')}</strong><br>${escHtml(m.subject || '')}<div style="margin-top:6px;white-space:pre-wrap;color:var(--text-secondary)">${escHtml(m.body || '')}</div></div>
        <div class="form-group"><label class="form-label">Un seul enseignant *</label><select class="form-select" id="msg_forward_teacher">${options}</select></div>
        <div class="form-group"><label class="form-label">Note de la Direction <span style="font-weight:400;color:var(--text-muted)">(facultatif)</span></label><textarea class="form-input" id="msg_forward_note" rows="3" placeholder="Contexte ou consigne pour l’enseignant"></textarea></div>`,
        `<button class="btn btn-outline" onclick="closeModal()">Annuler</button><button class="btn btn-primary" onclick="sendForwardParentMessage('${m.id}')">➡️ Transmettre</button>`
      );
    };

    window.sendForwardParentMessage = async mid => {
      if (!isDirection()) return;
      const originalParentMsg = (DB.messages || []).find(x => x.id === mid && x.from_role === 'parent');
      const tid = (($('msg_forward_teacher') || {}).value || '').trim();
      const teacher = (DB.users || []).find(u => u.id === tid && roleUI(u.role) === 'enseignant');
      if (!originalParentMsg || !teacher) { toast('Transmission impossible', 'error'); return; }
      const parent = (DB.users || []).find(u => u.id === originalParentMsg.from);
      const note = (($('msg_forward_note') || {}).value || '').trim();
      const ref = 'R' + String(originalParentMsg.id || Date.now()).replace(/[^a-z0-9]/gi, '').slice(-8).toUpperCase();
      const kids = (DB.students || []).filter(s => s.pid === originalParentMsg.from && !s.archived);
      const context = kids.map(s => `${s.name}${((DB.classes||[]).find(c=>c.id===s.cid)?.name) ? ' — '+(DB.classes||[]).find(c=>c.id===s.cid).name : ''}`).join(', ');
      const subject = `Transmission Direction [${ref}] — ${originalParentMsg.subject || 'Message parent'}`;
      const body = `Message transmis par la Direction.\nParent : ${parent?.name || 'Parent'}${context ? `\nÉlève(s) : ${context}` : ''}${note ? `\n\nNote Direction :\n${note}` : ''}\n\nMessage original :\n${originalParentMsg.body || ''}`;
      const msg = { id:_uid('msg_'), from:S.user.id, from_role:roleUI(S.user.role), to:teacher.id, to_role:null, to_class_cid:null,
        subject, body, msg_type:'normal', date:today(), time:nowTime(), status:'sent', read:false };
      if (!(await pushEncryptedMessage(msg, [teacher]))) return;
      const routes = routeMap(); routes[ref] = { parent_id:originalParentMsg.from, source_message_id:mid, teacher_id:teacher.id, forwarded_message_id:msg.id }; saveRouteMap(routes);
      closeModal(); render(); toast(`Message transmis uniquement à ${teacher.name}`, 'success');
    };

    const routeRefFromSubject = subject => {
      const m = String(subject || '').match(/\[(R[A-Z0-9]{4,20})\]/i);
      return m ? m[1].toUpperCase() : null;
    };

    window.openRelayTeacherMessage = mid => {
      if (!isDirection()) { toast('Accès non autorisé', 'error'); return; }
      const m = (DB.messages || []).find(x => x.id === mid && x.from_role === 'enseignant');
      if (!m) { toast('Réponse enseignant introuvable', 'error'); return; }
      const teacher = (DB.users || []).find(u => u.id === m.from);
      const ref = routeRefFromSubject(m.subject);
      const routes = routeMap(); const preferred = ref && routes[ref] ? routes[ref].parent_id : '';
      const parents = (DB.users || []).filter(u => roleUI(u.role) === 'parent');
      const opts = parents.map(p => `<option value="${p.id}" ${p.id===preferred?'selected':''}>${escHtml(p.name)}</option>`).join('');
      openM('↪️ Transmettre la réponse au parent', `
        <div style="padding:10px 12px;background:var(--bg);border-radius:10px;margin-bottom:12px;font-size:12px"><strong>${escHtml(teacher?.name || 'Enseignant')}</strong><br>${escHtml(m.subject || '')}<div style="margin-top:6px;white-space:pre-wrap;color:var(--text-secondary)">${escHtml(m.body || '')}</div></div>
        <div class="form-group"><label class="form-label">Parent destinataire *</label><select class="form-select" id="msg_relay_parent"><option value="">— Choisir le parent —</option>${opts}</select></div>
        <div class="form-group"><label class="form-label">Message transmis *</label><textarea class="form-input" id="msg_relay_body" rows="5">${escHtml(m.body || '')}</textarea></div>`,
        `<button class="btn btn-outline" onclick="closeModal()">Annuler</button><button class="btn btn-primary" onclick="sendRelayTeacherMessage('${m.id}')">📤 Envoyer au parent</button>`
      );
    };

    window.sendRelayTeacherMessage = async mid => {
      if (!isDirection()) return;
      const source = (DB.messages || []).find(x => x.id === mid && x.from_role === 'enseignant');
      const pid = (($('msg_relay_parent') || {}).value || '').trim();
      const parent = (DB.users || []).find(u => u.id === pid && roleUI(u.role) === 'parent');
      const bodyText = (($('msg_relay_body') || {}).value || '').trim();
      if (!source || !parent) { toast('Choisissez le parent destinataire', 'error'); return; }
      if (!bodyText) { toast('Le message est vide', 'error'); return; }
      const ref = routeRefFromSubject(source.subject);
      const cleanSubject = String(source.subject || 'Réponse').replace(/^Re:\s*/i,'').replace(/^Transmission Direction\s*/i,'').trim();
      const subject = `Réponse de la Direction${ref ? ' ['+ref+']' : ''} — ${cleanSubject}`;
      const msg = { id:_uid('msg_'), from:S.user.id, from_role:roleUI(S.user.role), to:parent.id, to_role:null, to_class_cid:null,
        subject, body:bodyText, msg_type:'normal', date:today(), time:nowTime(), status:'sent', read:false };
      if (!(await pushEncryptedMessage(msg, [parent]))) return;
      closeModal(); render(); toast(`Réponse transmise à ${parent.name}`, 'success');
    };

    window.__SS_MESSAGES_FRONTEND_V2__.installed = true;
    console.info('[SchoolSafe] Messages frontend V2 installé');
    return true;
  };

  if (install()) return;
  const timer = setInterval(() => {
    if (install() || Date.now() - startedAt > INSTALL_TIMEOUT_MS) clearInterval(timer);
  }, INSTALL_EVERY_MS);
})();
