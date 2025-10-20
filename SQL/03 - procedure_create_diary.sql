-- Criamos uma PROCEDURE. É o ideal para ações que não retornam valores.
CREATE OR REPLACE PROCEDURE criar_agenda_semanal()
LANGUAGE plpgsql
AS $$
BEGIN
    -- Inserimos na tabela 'diary' selecionando uma combinação de dados.
    -- O client_id começa como NULL, pois o horário está vago.
    INSERT INTO diary (data, hora, employe_id, client_id)
    
    -- O SELECT abaixo gera todas as combinações que precisamos
    SELECT
        dias.dia AS data,
        horas.hora AS hora,
        empregados.id AS employe_id,
        NULL AS client_id
    
    -- Fonte 1: Nossos empregados ativos
    FROM (
        SELECT id FROM employer WHERE active = true
    ) AS empregados
    
    -- Fonte 2: As datas da próxima semana (de Segunda a Sábado)
    -- CROSS JOIN combina cada empregado com cada data.
    CROSS JOIN (
        -- generate_series é uma função poderosa para criar sequências.
        -- Se hoje é Domingo, ele gera as datas de amanhã (Segunda) até Sábado.
        SELECT generate_series(
            date_trunc('week', current_date + interval '1 day'), 
            date_trunc('week', current_date + interval '6 days'),
            '1 day'
        )::date AS dia
    ) AS dias
    
    -- Fonte 3: As horas de trabalho
    -- CROSS JOIN combina cada (empregado+data) com cada hora.
    CROSS JOIN (
        SELECT generate_series(9, 12) AS hora -- Manhã
        UNION ALL
        SELECT generate_series(13, 19) AS hora -- Tarde
    ) AS horas

    -- Condição de segurança para evitar duplicatas!
    -- Só insere se não existir um registro para o mesmo empregado, no mesmo dia e hora.
    WHERE NOT EXISTS (
        SELECT 1
        FROM diary d2
        WHERE d2.employe_id = empregados.id
          AND d2.data = dias.dia
          AND d2.hora = horas.hora
    );

END;
$$;