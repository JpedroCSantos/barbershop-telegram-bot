# Documentação

## 1. Visão Geral do Projeto

O projeto "Barbearia" consiste em um sistema de automação para uma barbearia, permitindo que clientes consultem, marquem e cancelem horários de forma simples e direta. A interação é realizada inteiramente através de um bot no Telegram, que é orquestrado por uma plataforma de automação (n8n) e suportado por um banco de dados (Supabase).

**Objetivos Principais:**

- **Agendamento:** Permitir que clientes marquem horários.
- **Consulta:** Permitir que clientes consultem seus horários já marcados ou a disponibilidade da agenda.
- **Cancelamento:** Permitir que clientes cancelem seus próprios agendamentos.

**Regras de Negócio:**

- Agendamentos são limitados à semana corrente.
- Clientes não podem desmarcar horários de outros clientes.

## 2. Arquitetura e Tecnologias

O projeto é construído sobre três pilares principais:

1. **Interface de Mensagens: Telegram**
    - **Motivo:** Escolhido pela facilidade e gratuidade na criação de bots, sem necessidade de aprovação comercial, acelerando o desenvolvimento.
    - **Função:** Serve como o *front-end* do sistema, recebendo mensagens do usuário (via `Telegram Trigger`) e enviando respostas e confirmações.
2. **Orquestração e Lógica: n8n**
    - **Motivo:** Plataforma de automação *low-code* que permite construir fluxos de trabalho complexos.
    - **Função:** Atua como o *backend* da aplicação. Ele recebe o gatilho do Telegram, processa a linguagem natural do usuário usando IA, interage com o banco de dados e executa a lógica de negócio (ver Seção 5).
3. **Banco de Dados: Supabase (PostgreSQL)**
    - **Motivo:** Oferece um banco de dados PostgreSQL com uma camada de API e um *free tier* generoso.
    - **Função:** Armazena de forma persistente os dados de clientes, funcionários e a agenda.

## 3. Estrutura do Banco de Dados (Schema)

O banco de dados foi modelado com três tabelas principais no schema `barbershop`:

- `barbershop.employee`: Armazena os dados dos barbeiros.
    - Campos: `ID` (PK), `NAME`, `ROLE`, `ACTIVE`, `CREATED_AT`.
- `barbershop.client`: Armazena os dados dos clientes.
    - Campos: `ID` (PK), `NAME`, `ID_TELEGRAM`, `PHONE_NUMBER`.
- `barbershop.diary`: Tabela fato central que registra os horários.
    - Campos: `code`, `data`, `hora`, `employe_id` (FK para `employee`), `client_id` (FK para `client`).
    - Esta tabela é particionada por `RANGE` na coluna `data` para otimizar consultas.

**Diagrama do Schema:**

## 4. Decisões Críticas de Design (O "Porquê")

Diversas decisões de arquitetura foram tomadas para garantir a eficiência, manutenibilidade e experiência do usuário:

1. **Abordagem Híbrida (IA + Botões):** Em vez de depender 100% de texto livre, o fluxo utiliza um Agente de IA (Gemini) para interpretar a intenção inicial. Se a IA não conseguir identificar uma intenção clara (`valid: false`), um menu com botões (`Service Classification`) é oferecido como *fallback*, melhorando a experiência do usuário.
2. **Autenticação no Supabase:** A tentativa inicial foi usar um usuário dedicado (`n8n_app`) com privilégios mínimos. No entanto, devido a restrições do *pooler* de conexão do Supabase, foi necessário reverter para o usuário padrão (`postgres`) para garantir a estabilidade da conexão com o n8n.
3. **Lógica no Banco de Dados (Procedures):** Em vez de sobrecarregar o n8n com lógica complexa de agendamento, duas *procedures* SQL foram criadas:
    - `criar_agenda_semanal()`: Popula a agenda da semana seguinte para todos os barbeiros ativos.
    - `criar_particao_agenda_proximo_mes()`: Garante a manutenção das partições da tabela `diary`, criando automaticamente a tabela para o próximo mês.
4. **Fluxos Modulares (Sub-Workflows):** Funções reutilizáveis, como "Buscar cliente pelo ID do Telegram" e "Consultar horários disponíveis", foram encapsuladas em sub-workflows separados no n8n (ex: `Call 'Get Client'2`, `Call 'Consultar Horários'`). Isso evita duplicação de código e facilita a manutenção.
5. **Centralização da Lógica no n8n:** A verificação de disponibilidade de horário é centralizada em nós de Código (`Code Node`) e IF, em vez de múltiplas ramificações, simplificando a manutenção do fluxo.

## 5. Fluxo da Automação (O "Como" - n8n)

O fluxo principal do n8n (`AI Agent.json`) orquestra toda a interação, desde a mensagem do usuário até a resposta final.

**Etapa 1: Gatilho e Interpretação (NLU)**

1. **Recebimento:** O `Telegram Trigger` inicia o fluxo quando um usuário envia uma mensagem.
2. **Análise de Intenção:** A mensagem é enviada ao `AI Agent1` (Google Gemini).
3. **Prompt do Sistema (System Prompt):** A IA é instruída a analisar o texto e retornar um JSON estruturado contendo:
    - `valid`: (true/false) Se a intenção é clara.
    - `intent`: "marcar", "consultar" ou "cancelar".
    - `subIntent`: (Para "consultar") "disponibilidade" ou "meus_horarios".
    - `barbeiro`: Nome do barbeiro, se mencionado.
    - `data`: Data no formato AAAA-MM-DD.
    - `hora`: Hora no formato HH.
4. **Validação:** O nó `Solicitação Valida?` (IF) verifica se `valid == true`.
    - **Se Inválido:** O fluxo desvia para o `Service Classification`, que envia um menu com botões (ex: "🗓️ Agendar ou Consultar") para o usuário.
    - **Se Válido:** O fluxo principal continua.

**Etapa 2: Coleta de Dados e Roteamento**

1. **Verificar Barbeiro:** O nó `Possui Barbeiro?` (IF) checa se a IA extraiu um nome de barbeiro.
    - **Se Não:** O nó `Seleciona Barbeiro` envia botões ("João", "Pedro") para o usuário escolher.
    - **Se Sim:** O nó `Get Employee` busca o ID do barbeiro no banco.
2. **Identificar Cliente:** Um sub-workflow (`Call 'Get Client'2`) é executado para buscar ou criar o cliente no banco de dados usando seu `ID_TELEGRAM`.
3. **Centralizar Dados:** Um nó `Code in JavaScript` consolida os dados da IA, da seleção manual do barbeiro (se houver) e do cliente.
4. **Roteamento Principal:** O nó `Switch` direciona o fluxo com base no `intent` ("marcar", "consultar", "cancelar").

**Etapa 3: Execução dos Fluxos de Intenção**

---

### **Fluxo A: `intent == "marcar"`**

1. O fluxo verifica se `data` e `hora` foram fornecidos (`Has date and hour?`).
2. **Se Sim (Data/Hora definidos):**
    - `Get diary`: O n8n consulta o banco para aquele `employe_id`, `data` e `hora`.
    - `Horario Indisponivel?` (IF):
        - **Disponível (`client_id IS NULL`):** O nó `Execute a SQL query2` (UPDATE) atribui o `client_id` ao horário. Uma mensagem de confirmação é enviada (`Send a text message1`).
        - **Indisponível (`client_id IS NOT NULL`):** Uma mensagem de erro (`Send a text message2`) é enviada. O sub-workflow `Call 'Consultar Horários'` é chamado para sugerir horários alternativos.
3. **Se Não (Data/Hora indefinidos):**
    - O sub-workflow `Call 'Consultar Horários'1` é chamado imediatamente para mostrar a agenda.

---

### **Fluxo B: `intent == "consultar"`**

1. Um IF (`Consultar disponibilidade?`) verifica o `subIntent`.
2. **Se `subIntent == "disponibilidade"`:**
    - O sub-workflow `Call 'Consultar Horários'1` é chamado para mostrar a agenda livre.
3. **Se `subIntent == "meus_horarios"` (Default/Else):**
    - `Execute a SQL query`: Busca na tabela `diary` todos os horários futuros onde `client_id` corresponde ao do usuário.
    - `Texto para usuario`: Um nó de código formata a lista de agendamentos.
    - `Mensagem para usuario`: Envia a lista formatada para o Telegram.

---

### **Fluxo C: `intent == "cancelar"`**

1. `Possui data e hora?` (IF): O fluxo tenta identificar qual agendamento cancelar.
    - **Se Sim (ex: "cancelar hoje 10h"):** `Get diary1` busca o agendamento específico daquele cliente.
    - **Se Não (ex: "cancelar meu horário"):** `Get Client diary` busca *todos* os agendamentos futuros do cliente (nos próximos 7 dias).
2. `Cliente possui agendamento?` (IF):
    - **Não Possui:** Envia uma mensagem informando que não há agendamentos (`Definir mensagem de não agendamentos`).
    - **Possui:** O nó `Confirmar horário a cancelar` envia uma mensagem com os dados do agendamento e botões de confirmação ("✅ Confirmar", "❌ Recusar").
3. `Confirmar cancelamento?` (IF):
    - **Confirmado:** `Execute a SQL query1` (UPDATE) define `client_id = NULL` no banco, liberando o horário. Uma mensagem de sucesso é enviada.
    - **Recusado:** O fluxo é encerrado com uma mensagem (`Canelamento recusado`).

## 6. Componentes Principais do Banco de Dados (Procedures SQL)

Duas procedures em `PL/pgSQL` são cruciais para a manutenção automatizada da agenda.

### Procedure 1: `criar_agenda_semanal()`

Esta procedure é invocada (provavelmente por um CRON) para popular a tabela `diary` com todos os horários vagos (Manhã: 9-12h; Tarde: 13-19h) para os dias úteis da semana seguinte (Segunda a Sábado), para todos os funcionários ativos.

```sql
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
```

### Procedure 2: `criar_particao_agenda_proximo_mes()`

Como a tabela `diary` é particionada por mês, esta procedure de manutenção verifica se a partição para o próximo mês já existe e, caso não, a cria. Isso evita falhas de inserção de dados quando o mês virar.

```sql
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
```