-- Esta procedure verifica se a partição do próximo mês existe e, se não, a cria.
CREATE OR REPLACE PROCEDURE criar_particao_agenda_proximo_mes()
LANGUAGE plpgsql
AS $$
DECLARE
    proximo_mes_inicio DATE;
    mes_seguinte_inicio DATE;
    nome_particao TEXT;
BEGIN
    -- Calcula o primeiro dia do próximo mês
    proximo_mes_inicio := date_trunc('month', current_date + interval '1 month')::date;
    
    -- Calcula o primeiro dia do mês seguinte a esse (para o limite superior da partição)
    mes_seguinte_inicio := date_trunc('month', current_date + interval '2 months')::date;
    
    -- Cria um nome para a tabela de partição, ex: 'diary_2025_11'
    nome_particao := 'diary_' || to_char(proximo_mes_inicio, 'YYYY_MM');
    
    -- Verifica se a partição já existe
    IF NOT EXISTS (SELECT FROM pg_class WHERE relname = nome_particao) THEN
        -- Se não existir, cria a partição usando EXECUTE para SQL dinâmico
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF diary FOR VALUES FROM (%L) TO (%L);',
            nome_particao,
            proximo_mes_inicio,
            mes_seguinte_inicio
        );
        RAISE NOTICE 'Partição % criada com sucesso.', nome_particao;
    ELSE
        RAISE NOTICE 'Partição % já existe.', nome_particao;
    END IF;
END;
$$;