-- ============================================================================
-- P0-8 — BOOTSTRAP CLÉ PERMANENTE DES CARTES
-- DRAFT — NE PAS APPLIQUER TEL QUEL EN PRODUCTION
-- ============================================================================
-- Règle importante : une carte physique déjà imprimée dépend de cette clé.
-- Si des cartes existent lors d'une migration Hosted Supabase -> VPS, NE PAS
-- générer une nouvelle clé : transférer la clé existante par canal secret.
-- Ce fichier ne retourne jamais la valeur du secret.
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_card_count bigint;
BEGIN
  IF to_regclass('public.student_cards') IS NULL THEN
    RAISE EXCEPTION 'student_cards must exist before card key bootstrap';
  END IF;

  IF EXISTS(SELECT 1 FROM private.qr_keys WHERE id='student_card_v1') THEN
    RAISE NOTICE 'student_card_v1 already exists — unchanged';
    RETURN;
  END IF;

  SELECT count(*) INTO v_card_count FROM public.student_cards;

  IF v_card_count > 0 THEN
    RAISE EXCEPTION
      'student_card_v1 is missing while % card(s) exist: import the existing signing key securely; do not rotate it',
      v_card_count;
  END IF;

  INSERT INTO private.qr_keys(id,secret)
  VALUES ('student_card_v1',extensions.gen_random_bytes(32));

  RAISE NOTICE 'student_card_v1 generated because no physical card exists yet';
END $$;

-- Vérification non sensible : présence + longueur seulement.
SELECT id, octet_length(secret) AS secret_bytes
FROM private.qr_keys
WHERE id='student_card_v1';

-- DRAFT : aucune clé conservée tant que Loms n'a pas validé l'application réelle.
ROLLBACK;
