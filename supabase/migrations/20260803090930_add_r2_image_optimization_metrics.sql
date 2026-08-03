alter table public.school_files
  add column if not exists source_original_name text,
  add column if not exists source_mime_type text,
  add column if not exists source_size_bytes bigint,
  add column if not exists source_width integer,
  add column if not exists source_height integer,
  add column if not exists processed_width integer,
  add column if not exists processed_height integer,
  add column if not exists compression_quality smallint,
  add column if not exists compression_profile text,
  add column if not exists optimized boolean not null default false,
  add column if not exists optimization_version smallint;

alter table public.school_files
  add column if not exists compression_saved_bytes bigint
    generated always as (
      case
        when source_size_bytes is null then 0
        else greatest(source_size_bytes - size_bytes, 0)
      end
    ) stored,
  add column if not exists compression_ratio_pct numeric(6,2)
    generated always as (
      case
        when source_size_bytes is null or source_size_bytes <= 0 then 0
        else round((greatest(source_size_bytes - size_bytes, 0)::numeric / source_size_bytes::numeric) * 100, 2)
      end
    ) stored;

alter table public.school_files
  add constraint school_files_source_mime_type_check
    check (source_mime_type is null or source_mime_type in ('image/jpeg','image/png','image/webp','application/pdf')),
  add constraint school_files_source_size_check
    check (source_size_bytes is null or (source_size_bytes > 0 and source_size_bytes <= 8388608)),
  add constraint school_files_source_dimensions_check
    check (
      (source_width is null and source_height is null)
      or (
        source_width between 1 and 12000
        and source_height between 1 and 12000
        and (source_width::bigint * source_height::bigint) <= 40000000
      )
    ),
  add constraint school_files_processed_dimensions_check
    check (
      (processed_width is null and processed_height is null)
      or (
        processed_width between 1 and 12000
        and processed_height between 1 and 12000
      )
    ),
  add constraint school_files_compression_quality_check
    check (compression_quality is null or compression_quality between 1 and 100),
  add constraint school_files_compression_profile_check
    check (compression_profile is null or compression_profile in ('photo','identity','card','document','passthrough')),
  add constraint school_files_optimization_version_check
    check (optimization_version is null or optimization_version between 1 and 100),
  add constraint school_files_optimization_consistency_check
    check (
      not optimized
      or (
        source_mime_type in ('image/jpeg','image/png','image/webp')
        and source_size_bytes is not null
        and source_width is not null
        and source_height is not null
        and processed_width is not null
        and processed_height is not null
        and compression_quality is not null
        and compression_profile is not null
        and optimization_version is not null
      )
    );

create index if not exists school_files_idx_optimization_year
  on public.school_files (academic_year, optimized)
  where deleted_at is null;
