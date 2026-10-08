-- DBX-21 (08/10/2026), respostas do dono: "Embaixador é o nome do barco, Caju também; Ribas é
-- o marinheiro do barco de nome Comandante Zepi". O telefone dos cadastros não identifica o dono
-- (Embaixador nunca escreveu; Ribas, 2 mensagens sem nome). Idempotente.

-- Comandante Zepi é o barco (Azimut 30 Metri); Ribas é o marinheiro e o contato que temos.
update public.vessels
   set name = 'Comandante Zepi'
 where client_id = 'defa89f2-97d1-499c-bcc6-3fcfaf759b44' and name = 'Azimut 30 Metri';

update public.clients
   set name = 'Ribas',
       notes = concat_ws(E'\n', nullif(notes, ''),
         'Nome anterior: RIBAS AZ 30 METRI - COMANDANTE ZEPI (08/10/2026). Ribas é o marinheiro do barco Comandante Zepi (Azimut 30 Metri); dono do barco não informado.')
 where id = 'defa89f2-97d1-499c-bcc6-3fcfaf759b44' and name = 'RIBAS AZ 30 METRI - COMANDANTE ZEPI';

insert into public.vessel_contacts (vessel_id, full_name, role, phone, notes)
select v.id, 'Ribas', 'Marinheiro', c.phone, 'Contato do barco; o dono não foi informado.'
  from public.vessels v join public.clients c on c.id = v.client_id
 where v.client_id = 'defa89f2-97d1-499c-bcc6-3fcfaf759b44' and v.name = 'Comandante Zepi'
   and not exists (select 1 from public.vessel_contacts vc where vc.vessel_id = v.id and vc.full_name = 'Ribas');

update public.pastas_dropbox
   set observacao = 'Barco Comandante Zepi (Azimut 30 Metri); Ribas é o marinheiro. Mesmo barco da 0005.002.25_AZIMUT 30 METRI.'
 where dropbox_id = 'id:sZCHZmtLl2AAAAAAAABvoA';
update public.pastas_dropbox
   set observacao = 'Barco Comandante Zepi (Azimut 30 Metri); Ribas é o marinheiro.'
 where dropbox_id = 'id:sZCHZmtLl2AAAAAAAAB-pw';

-- Embaixador e Caju são os barcos; o dono de cada um ainda não é conhecido.
update public.clients
   set name = 'Embaixador (dono a identificar)',
       notes = concat_ws(E'\n', nullif(notes, ''),
         'Nome anterior: FALCON 115 - EMBAIXADOR (08/10/2026). Embaixador é o barco (Falcon 115); o dono não foi informado.')
 where id = 'b9155385-3b8c-440d-b727-026632a00dbd' and name = 'FALCON 115 - EMBAIXADOR';

update public.clients
   set name = 'Caju (dono a identificar)',
       notes = concat_ws(E'\n', nullif(notes, ''),
         'Nome anterior: Porto Fino 35 - Caju (08/10/2026). Caju é o barco (Porto Fino Fly 35); o dono não foi informado.')
 where id = '43ef220e-a34c-4fd1-92a6-96ac9dfcb4d0' and name = 'Porto Fino 35 - Caju';
