-- SchoolSafe VPS baseline - 11 non-sensitive configuration seed
-- No Auth user, password, QR secret, SMTP, R2 secret, FCM secret, JWT secret or service-role key is stored here.

BEGIN;

INSERT INTO public.administrative_document_types(id,code,label,group_code,is_financial,active,sort_order,created_at,updated_at) VALUES
('adt_2417f9bd9deb464c8ae4a04d35dd1cdd','water_bill','Facture ou reçu d’eau','utilities',true,true,10,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00'),
('adt_06550f52580a4992aaf1e516e53dbd4d','electricity_bill','Facture ou reçu d’électricité','utilities',true,true,20,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00'),
('adt_d658cabfa27b41b8a9bf34490fb8002d','school_insurance','Assurance de l’école','insurance',true,true,30,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00'),
('adt_351dcfc0086d411da24cf4cf1bf185ce','rent_payment','Loyer et preuve de paiement','rent',true,true,40,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00'),
('adt_22ede7ada08f4f468e5bbf60202830a7','tax_payment','Taxes et impôts','tax_social',true,true,50,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00'),
('adt_5123ee65b60f46ea86ca30495496c006','cnss_payment','Paiement CNSS','tax_social',true,true,60,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00'),
('adt_75a7ce81988e4f71b0c6be198200bd6f','supplier_invoice','Facture fournisseur','supplier',true,true,70,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00'),
('adt_3f4302d8c6474764b50c885594a4b211','purchase_receipt','Reçu d’achat de l’école','supplier',true,true,80,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00'),
('adt_c4204a13d835462c97ccb4c62129def1','bank_document','Document bancaire','banking',true,true,90,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00'),
('adt_c2b41fa1a0a240b0a4fab9b6be54cd9','maintenance_invoice','Entretien et réparation','maintenance',true,true,100,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00'),
('adt_2fc550a5dc7f422da731503609b18569','contract','Contrat ou convention','legal',false,true,200,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00'),
('adt_286eda0e6fcf4cc28d27943b07156275','authorization_license','Autorisation, agrément ou licence','legal',false,true,210,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00'),
('adt_743d2b1facc64b7f83b6685ec979a729','staff_administrative','Document administratif du personnel','human_resources',false,true,220,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00'),
('adt_b0391dcfab574522b61c41588df0dd20','inventory','Inventaire ou fiche de matériel','inventory',false,true,230,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00'),
('adt_7af6bcdd18004349824a001e5fbe6b42','official_correspondence','Correspondance officielle','correspondence',false,true,240,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00'),
('adt_4e8d4840b4c9431497d4274031cc50ef','meeting_minutes','Procès-verbal ou compte rendu','correspondence',false,true,250,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00'),
('adt_1a13f4410d6445569d22bce9f453df43','other_financial','Autre document financier','other',true,true,900,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00'),
('adt_5d404ebfdaa04fd3b7f443ea6db7919c','other_administrative','Autre document administratif','other',false,true,910,'2026-08-03T06:45:21.018267+00:00','2026-08-03T06:45:21.018267+00:00')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.fee_types(id,label,category,trimestre,montant_defaut,active) VALUES
('ft_activ','Activité / Sport','autre',NULL,0,true),
('ft_autre','Autre frais','autre',NULL,0,true),
('ft_cant','Cantine scolaire','cantine',NULL,0,true),
('ft_insc','Frais d''inscription','scolaire','inscription',0,true),
('ft_sort','Frais de sortie','sortie',NULL,0,true),
('ft_T1','Frais scolaires — T1','scolaire','T1',0,true),
('ft_T2','Frais scolaires — T2','scolaire','T2',0,true),
('ft_T3','Frais scolaires — T3','scolaire','T3',0,true),
('ft_unif','Uniforme','autre',NULL,0,true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.classes(id,name,cycle,teacher_id,teacher_id_en,titulaire_id,option,card_color,card_color_soft,card_color_dark)
VALUES('c_a00d54de-fa2f-4de4-98ec-f7a0cc21b910','Première primaire cp1','primaire','u_2cc5539a-14a0-475e-a0a5-98c6d2ecfad1',NULL,NULL,NULL,'#ffff00','#ffffad','#adad00')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.school_profile(id,legal_name,display_name,slogan,locale,timezone,updated_at)
VALUES(1,'Complexe Scolaire Le Sage','The Wise School International','Former, réformer, exceller','fr-CD','Africa/Kinshasa','2026-08-01T10:32:26.352875+00:00')
ON CONFLICT (id) DO UPDATE SET
  legal_name=excluded.legal_name,display_name=excluded.display_name,slogan=excluded.slogan,
  locale=excluded.locale,timezone=excluded.timezone,updated_at=excluded.updated_at;

INSERT INTO public.settings(
  id,currenttrimestre,feescontrol,fees,retention,toggles,trimlocks,school,year,horaires,
  session_timeout_min,lockdown,budget_depenses,school_type,rattrapage_threshold,rattrapage_rate,
  opening_cash,opening_bank,staff_postes,archived_years,year_locked,year_locked_by,year_locked_date,
  vapid_public_key,operator_wa
) VALUES (
  'main','T1','{"active":false,"trimestre":"T1"}'::jsonb,
  '{"T1":0,"T2":0,"T3":0,"inscription":0}'::jsonb,
  '{"notifs":30,"messages":30,"scan_log":90,"audit_log":90,"approbations":60,"convocations":90,"messages_unread":60}'::jsonb,
  '{}'::jsonb,'{"T1":false,"T2":false,"T3":false}'::jsonb,
  '{"name":"Le Sage / The Wise School International"}'::jsonb,
  '2025-2026','{}'::jsonb,30,false,0,NULL,NULL,NULL,0,0,'[]'::jsonb,'[]'::jsonb,NULL,NULL,NULL,NULL,NULL
)
ON CONFLICT (id) DO UPDATE SET
  currenttrimestre=excluded.currenttrimestre,feescontrol=excluded.feescontrol,fees=excluded.fees,
  retention=excluded.retention,toggles=excluded.toggles,trimlocks=excluded.trimlocks,school=excluded.school,
  year=excluded.year,horaires=excluded.horaires,session_timeout_min=excluded.session_timeout_min,
  lockdown=excluded.lockdown,budget_depenses=excluded.budget_depenses,school_type=excluded.school_type,
  rattrapage_threshold=excluded.rattrapage_threshold,rattrapage_rate=excluded.rattrapage_rate,
  opening_cash=excluded.opening_cash,opening_bank=excluded.opening_bank,staff_postes=excluded.staff_postes,
  archived_years=excluded.archived_years,year_locked=excluded.year_locked,year_locked_by=excluded.year_locked_by,
  year_locked_date=excluded.year_locked_date,vapid_public_key=excluded.vapid_public_key,operator_wa=excluded.operator_wa;
-- Deliberately leaves settings.qr_secret and settings.msg_enc_key untouched/NULL.

INSERT INTO public.site_content(
  id,school_name,school_name_en,tagline,about_text,mission,founded_year,address,city,phone,whatsapp,email,
  programs,pillars,stats,staff,gallery,hero_photos,hero_url,logo_url,theme,primary_color,published_at,updated_at
) VALUES (
  'main','Complexe Scolaire Le Sage','The Wise School International',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
  '[]'::jsonb,'[]'::jsonb,'{}'::jsonb,'[]'::jsonb,'[]'::jsonb,'[]'::jsonb,NULL,NULL,'dark','#c0962e',NULL,
  '2026-08-04T09:24:32.163816+00:00'
)
ON CONFLICT (id) DO UPDATE SET
  school_name=excluded.school_name,school_name_en=excluded.school_name_en,tagline=excluded.tagline,
  about_text=excluded.about_text,mission=excluded.mission,founded_year=excluded.founded_year,address=excluded.address,
  city=excluded.city,phone=excluded.phone,whatsapp=excluded.whatsapp,email=excluded.email,
  programs=excluded.programs,pillars=excluded.pillars,stats=excluded.stats,staff=excluded.staff,
  gallery=excluded.gallery,hero_photos=excluded.hero_photos,hero_url=excluded.hero_url,logo_url=excluded.logo_url,
  theme=excluded.theme,primary_color=excluded.primary_color,published_at=excluded.published_at,updated_at=excluded.updated_at;

COMMIT;
