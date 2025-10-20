CREATE SCHEMA IF NOT EXISTS barbershop

CREATE TABLE IF NOT EXISTS barbershop.employee (
  ID SERIAL PRIMARY KEY NOT NULL,
  NAME VARCHAR(100) NOT NULL,
  ROLE VARCHAR(50) DEFAULT 'Barbeiro',
  ACTIVE boolean NOT NULL default false,
  CREATED_AT DATE default current_timestamp
)

CREATE TABLE IF NOT EXISTS barbershop.client (
  ID SERIAL PRIMARY KEY NOT NULL,
  NAME VARCHAR(100) NOT NULL,
  ID_TELEGRAM INT,
  PHONE_NUMBER VARCHAR(11)
)

CREATE TABLE IF NOT EXISTS barbershop.diary (
    code        INT GENERATED ALWAYS AS IDENTITY,
    data        DATE NOT NULL,
    hora        INT NOT NULL,
    employe_id  INT REFERENCES employee(id),
    client_id   INT REFERENCES client(id),

    PRIMARY KEY (data, code)
) PARTITION BY RANGE (data);

CREATE INDEX ON diary (employe_id);
CREATE INDEX ON diary (client_id);