-- P0-29: align invitation storage with the current canonical role matrix.

alter table private.account_invitations
  drop constraint if exists account_invitations_role_check;

alter table private.account_invitations
  add constraint account_invitations_role_check
  check (role in (
    'direction',
    'direction2',
    'direction3',
    'direction_pedagogique',
    'caisse',
    'enseignant',
    'gardien',
    'parent'
  ));

comment on constraint account_invitations_role_check on private.account_invitations is
  'Accepts canonical SchoolSafe roles plus legacy aliases while invitation functions enforce the actor/target permission matrix.';