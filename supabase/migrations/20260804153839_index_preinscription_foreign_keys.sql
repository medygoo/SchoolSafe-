-- Indexes couvrant les clés étrangères de public.preinscriptions.
-- Version appliquée dans Supabase : 20260804153839.

create index if not exists preinscriptions_parent_id_idx
  on public.preinscriptions (parent_id)
  where parent_id is not null;

create index if not exists preinscriptions_student_id_idx
  on public.preinscriptions (student_id)
  where student_id is not null;

create index if not exists preinscriptions_traite_par_idx
  on public.preinscriptions (traite_par)
  where traite_par is not null;
