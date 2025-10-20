CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule(
    'particao-mensal-agenda',      -- Um nome único para o job
    '0 4 15 * *',                  -- "Às 04:00 do dia 15 de cada mês"
    'CALL criar_particao_agenda_proximo_mes();' -- O comando a ser executado
);