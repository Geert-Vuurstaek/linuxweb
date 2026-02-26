CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL
);

INSERT INTO users (id, name)
VALUES (1, 'Geert Vuurstaek')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
