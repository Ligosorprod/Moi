-- ============================================================
-- Fiches de prospection - Schema SQL (PostgreSQL / Supabase)
-- ============================================================
-- ATTENTION SECURITE :
-- Ce schema stocke les mots de passe en texte clair et ne met
-- en place aucune protection avancee (hachage, RLS, etc.).
-- A n'utiliser que pour une phase de test, jamais en production
-- avec de vraies donnees clients. Pour passer en prod, il
-- faudra au minimum :
--   - hacher les mots de passe (bcrypt/argon2) cote application
--   - activer Row Level Security (RLS) si utilise sur Supabase
--   - stocker les photos dans un bucket de stockage plutot
--     qu'en base (colonne "photo" en base64)
-- ============================================================

-- Extension pour generer des UUID (disponible par defaut sur Supabase)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ------------------------------------------------------------
-- Table des commerciaux (comptes qui se connectent a l'appli)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS commerciaux (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(50)  NOT NULL UNIQUE,
    password      VARCHAR(255) NOT NULL,   -- en clair pour l'instant (periode de test)
    nom           VARCHAR(120) NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Compte de demonstration (equivalent du DEMO_COMMERCIAL cote JS)
INSERT INTO commerciaux (username, password, nom)
VALUES ('demo', 'demo123', 'Compte Démo')
ON CONFLICT (username) DO NOTHING;

-- ------------------------------------------------------------
-- Fonction : creation d'un compte commercial par l'admin
-- (equivalent du formulaire "Equipe" -> create-comm-form)
-- Renvoie le compte cree, ou leve une erreur si l'identifiant
-- existe deja (comme le message "Cet identifiant existe deja.")
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION creer_commercial(
    p_nom      VARCHAR,
    p_username VARCHAR,
    p_password VARCHAR
) RETURNS commerciaux AS $$
DECLARE
    nouveau commerciaux;
BEGIN
    IF EXISTS (SELECT 1 FROM commerciaux WHERE username = p_username) THEN
        RAISE EXCEPTION 'Cet identifiant existe deja.';
    END IF;

    INSERT INTO commerciaux (username, password, nom)
    VALUES (p_username, p_password, p_nom)
    RETURNING * INTO nouveau;

    RETURN nouveau;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- Fonction : suppression d'un compte commercial par l'admin
-- Les fiches liees sont supprimees automatiquement (ON DELETE
-- CASCADE sur fiches.commercial_id)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION supprimer_commercial(p_username VARCHAR)
RETURNS VOID AS $$
BEGIN
    DELETE FROM commerciaux WHERE username = p_username;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- Table des administrateurs (optionnelle : sinon mot de passe
-- admin unique gere cote application, comme dans le HTML actuel)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS administrateurs (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(50)  NOT NULL UNIQUE,
    password      VARCHAR(255) NOT NULL,   -- en clair pour l'instant
    nom           VARCHAR(120) NOT NULL DEFAULT 'Administrateur',
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

INSERT INTO administrateurs (username, password, nom)
VALUES ('admin', 'Admin2026!', 'Administrateur')
ON CONFLICT (username) DO NOTHING;

-- ------------------------------------------------------------
-- Table des fiches de prospection
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fiches (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    commercial_id     INTEGER NOT NULL REFERENCES commerciaux(id) ON DELETE CASCADE,

    -- infos du prospect
    nomprenom         VARCHAR(150) NOT NULL,
    produit           VARCHAR(80)  NOT NULL,
    contact1          VARCHAR(50)  NOT NULL,
    contact2          VARCHAR(50),
    echeance          DATE         NOT NULL,
    interet           VARCHAR(30),
    promesses         TEXT,

    -- statut du dossier
    statut            VARCHAR(20)  NOT NULL DEFAULT 'en_attente'
                        CHECK (statut IN ('en_attente', 'valide', 'refuse')),

    -- rempli seulement si valide
    montant           NUMERIC(12,2),
    photo             TEXT,               -- idealement une URL vers un fichier stocke a part
    nom_carte_grise   VARCHAR(150),
    date_validation   DATE,
    date_refus        DATE,

    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Liste des produits valides (equivalent du tableau PRODUITS cote JS)
-- Decommenter si tu veux forcer la liste au niveau base :
-- ALTER TABLE fiches ADD CONSTRAINT fiches_produit_check
--     CHECK (produit IN (
--         'Auto', 'Sante', 'Multirisque habitation', 'Tous risques chantier',
--         'Transport de marchandise', 'Seven Jolly', 'Assurance Vie', 'PME/PMI'
--     ));

-- ------------------------------------------------------------
-- Index utiles pour les listes/tris de l'appli
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_fiches_commercial_id ON fiches (commercial_id);
CREATE INDEX IF NOT EXISTS idx_fiches_echeance      ON fiches (echeance);
CREATE INDEX IF NOT EXISTS idx_fiches_statut        ON fiches (statut);
CREATE INDEX IF NOT EXISTS idx_fiches_created_at    ON fiches (created_at DESC);

-- ------------------------------------------------------------
-- Vue pratique : total des ventes validees par commercial
-- (equivalent de la fonction totalVentes() cote JS)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW ventes_par_commercial AS
SELECT
    c.id            AS commercial_id,
    c.username,
    c.nom,
    COUNT(f.id)                                             AS nb_fiches,
    COALESCE(SUM(f.montant) FILTER (WHERE f.statut = 'valide'), 0) AS total_ventes_fcfa
FROM commerciaux c
LEFT JOIN fiches f ON f.commercial_id = c.id
GROUP BY c.id, c.username, c.nom;
