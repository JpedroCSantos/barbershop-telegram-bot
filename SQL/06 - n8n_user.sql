CREATE ROLE n8n_app WITH LOGIN PASSWORD '';--'password';

GRANT USAGE ON SCHEMA barbershop TO n8n_app;

GRANT SELECT, INSERT, UPDATE ON barbershop.client TO postgres;
GRANT SELECT, UPDATE ON barbershop.diary TO postgres;
GRANT SELECT ON barbershop.employee TO postgres;

-- GRANT USAGE, SELECT ON SEQUENCE barbershop.client_id TO n8n_app;
-- GRANT USAGE, SELECT ON SEQUENCE barbershop.employee_id TO n8n_app;