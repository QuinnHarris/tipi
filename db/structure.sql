--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

--
-- Name: cycle_test(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION cycle_test() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      DECLARE
        cycle_path integer ARRAY;
      BEGIN
        IF (TG_OP = 'UPDATE' AND
            NEW.successor_id = OLD.successor_id AND
            NEW.predecessor_id = OLD.predecessor_id) THEN
          RETURN NULL;
        END IF;

        WITH RECURSIVE branch_decend AS (
            SELECT NEW.successor_id AS id,
                   ARRAY[NEW.predecessor_id, NEW.successor_id] AS path,
                   false AS cycle
          UNION
            SELECT branch_relations.successor_id,
                   branch_decend.path || branch_relations.successor_id,
             branch_relations.successor_id = ANY(branch_decend.path)
              FROM branch_relations
          INNER JOIN branch_decend
            ON branch_relations.predecessor_id = branch_decend.id
              WHERE NOT branch_decend.cycle
        ) SELECT path INTO cycle_path
            FROM branch_decend WHERE cycle LIMIT 1;

        IF FOUND THEN
          RAISE EXCEPTION 'cycle found %', cycle_path;
        END IF;

        RETURN NULL;
      END
      $$;


--
-- Name: nodes_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION nodes_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        NEW.tsv :=
          setweight(to_tsvector('pg_catalog.english', coalesce(NEW.name,'')), 'A') ||
          setweight(to_tsvector('pg_catalog.english', coalesce(NEW.doc,'')), 'B');
        RETURN NEW;
      END
      $$;


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: actions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE actions (
    instance_id integer NOT NULL,
    node_version integer NOT NULL,
    node_branch_path integer[] DEFAULT '{}'::integer[] NOT NULL,
    state text
);


--
-- Name: branch_relations; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE branch_relations (
    predecessor_id integer NOT NULL,
    successor_id integer NOT NULL,
    version bigint,
    CONSTRAINT branch_relations_check CHECK (true)
);


--
-- Name: branches; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE branches (
    id integer NOT NULL,
    type text NOT NULL,
    name text NOT NULL,
    description text,
    merge_point boolean,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone
);


--
-- Name: branches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE branches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: branches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE branches_id_seq OWNED BY branches.id;


--
-- Name: version_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE version_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: edge_inters; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE edge_inters (
    version bigint DEFAULT nextval('version_seq'::regclass) NOT NULL,
    created_at timestamp without time zone NOT NULL,
    from_record_id integer NOT NULL,
    from_branch_id integer NOT NULL,
    from_branch_path integer[] DEFAULT '{}'::integer[] NOT NULL,
    to_record_id integer NOT NULL,
    to_branch_id integer NOT NULL,
    to_branch_path integer[] DEFAULT '{}'::integer[] NOT NULL,
    deleted boolean DEFAULT false NOT NULL
);


--
-- Name: edges; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE edges (
    version bigint DEFAULT nextval('version_seq'::regclass) NOT NULL,
    branch_id integer NOT NULL,
    branch_path integer[] DEFAULT '{}'::integer[] NOT NULL,
    created_at timestamp without time zone NOT NULL,
    from_record_id integer NOT NULL,
    from_branch_path integer[] DEFAULT '{}'::integer[] NOT NULL,
    to_record_id integer NOT NULL,
    to_branch_path integer[] DEFAULT '{}'::integer[] NOT NULL,
    deleted boolean DEFAULT false NOT NULL
);


--
-- Name: instance_relations; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE instance_relations (
    predecessor_id integer NOT NULL,
    successor_id integer NOT NULL,
    CONSTRAINT instance_relations_check CHECK (true)
);


--
-- Name: instances; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE instances (
    id integer NOT NULL,
    node_version integer,
    node_branch_path integer[] DEFAULT '{}'::integer[] NOT NULL,
    state text,
    count integer DEFAULT 1 NOT NULL,
    data text,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: instances_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE instances_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: instances_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE instances_id_seq OWNED BY instances.id;


--
-- Name: nodes; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE nodes (
    version bigint DEFAULT nextval('version_seq'::regclass) NOT NULL,
    branch_id integer NOT NULL,
    branch_path integer[] DEFAULT '{}'::integer[] NOT NULL,
    record_id integer NOT NULL,
    created_at timestamp without time zone NOT NULL,
    type text NOT NULL,
    name text NOT NULL,
    doc text,
    tsv tsvector,
    deleted boolean DEFAULT false NOT NULL
);


--
-- Name: nodes_record_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE nodes_record_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: nodes_record_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE nodes_record_id_seq OWNED BY nodes.record_id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE schema_migrations (
    filename text NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE users (
    id integer NOT NULL,
    branch_id integer,
    email text DEFAULT ''::text NOT NULL,
    encrypted_password text DEFAULT ''::text NOT NULL,
    reset_password_token text,
    reset_password_sent_at timestamp without time zone,
    remember_created_at timestamp without time zone,
    sign_in_count integer DEFAULT 0 NOT NULL,
    current_sign_in_at timestamp without time zone,
    last_sign_in_at timestamp without time zone,
    current_sign_in_ip text,
    last_sign_in_ip text,
    confirmation_token text,
    confirmed_at timestamp without time zone,
    confirmation_sent_at timestamp without time zone,
    unconfirmed_email text,
    failed_attempts integer DEFAULT 0 NOT NULL,
    unlock_token text,
    locked_at timestamp without time zone,
    provider text,
    uid text,
    name text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE users_id_seq OWNED BY users.id;


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY branches ALTER COLUMN id SET DEFAULT nextval('branches_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY instances ALTER COLUMN id SET DEFAULT nextval('instances_id_seq'::regclass);


--
-- Name: record_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY nodes ALTER COLUMN record_id SET DEFAULT nextval('nodes_record_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY users ALTER COLUMN id SET DEFAULT nextval('users_id_seq'::regclass);


--
-- Name: actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY actions
    ADD CONSTRAINT actions_pkey PRIMARY KEY (instance_id, node_version, node_branch_path);


--
-- Name: branch_relations_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY branch_relations
    ADD CONSTRAINT branch_relations_pkey PRIMARY KEY (successor_id, predecessor_id);


--
-- Name: branches_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY branches
    ADD CONSTRAINT branches_pkey PRIMARY KEY (id);


--
-- Name: edge_inters_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY edge_inters
    ADD CONSTRAINT edge_inters_pkey PRIMARY KEY (version);


--
-- Name: edges_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY edges
    ADD CONSTRAINT edges_pkey PRIMARY KEY (version);


--
-- Name: instance_relations_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY instance_relations
    ADD CONSTRAINT instance_relations_pkey PRIMARY KEY (successor_id, predecessor_id);


--
-- Name: instances_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY instances
    ADD CONSTRAINT instances_pkey PRIMARY KEY (id);


--
-- Name: nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY nodes
    ADD CONSTRAINT nodes_pkey PRIMARY KEY (version);


--
-- Name: schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (filename);


--
-- Name: users_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: edge_inters_from_record_id_from_branch_path_from_branch_id_inde; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX edge_inters_from_record_id_from_branch_path_from_branch_id_inde ON edge_inters USING btree (from_record_id, from_branch_path, from_branch_id);


--
-- Name: edge_inters_to_record_id_to_branch_path_to_branch_id_index; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX edge_inters_to_record_id_to_branch_path_to_branch_id_index ON edge_inters USING btree (to_record_id, to_branch_path, to_branch_id);


--
-- Name: edges_from_record_id_from_branch_path_index; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX edges_from_record_id_from_branch_path_index ON edges USING btree (from_record_id, from_branch_path);


--
-- Name: edges_to_record_id_to_branch_path_index; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX edges_to_record_id_to_branch_path_index ON edges USING btree (to_record_id, to_branch_path);


--
-- Name: instances_node_version_node_branch_path_index; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX instances_node_version_node_branch_path_index ON instances USING btree (node_version, node_branch_path);


--
-- Name: nodes_record_id_index; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX nodes_record_id_index ON nodes USING btree (record_id);


--
-- Name: nodes_tsv_index; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX nodes_tsv_index ON nodes USING btree (tsv);


--
-- Name: users_confirmation_token_index; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX users_confirmation_token_index ON users USING btree (confirmation_token);


--
-- Name: users_email_index; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX users_email_index ON users USING btree (email);


--
-- Name: users_reset_password_token_index; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX users_reset_password_token_index ON users USING btree (reset_password_token);


--
-- Name: users_unlock_token_index; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX users_unlock_token_index ON users USING btree (unlock_token);


--
-- Name: cycle_test; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER cycle_test AFTER INSERT OR UPDATE ON branch_relations NOT DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE PROCEDURE cycle_test();


--
-- Name: nodes_tsvector_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER nodes_tsvector_update BEFORE INSERT ON nodes FOR EACH ROW EXECUTE PROCEDURE nodes_trigger();


--
-- Name: actions_instance_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY actions
    ADD CONSTRAINT actions_instance_id_fkey FOREIGN KEY (instance_id) REFERENCES instances(id);


--
-- Name: actions_node_version_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY actions
    ADD CONSTRAINT actions_node_version_fkey FOREIGN KEY (node_version) REFERENCES nodes(version);


--
-- Name: branch_relations_predecessor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY branch_relations
    ADD CONSTRAINT branch_relations_predecessor_id_fkey FOREIGN KEY (predecessor_id) REFERENCES branches(id);


--
-- Name: branch_relations_successor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY branch_relations
    ADD CONSTRAINT branch_relations_successor_id_fkey FOREIGN KEY (successor_id) REFERENCES branches(id);


--
-- Name: edge_inters_from_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY edge_inters
    ADD CONSTRAINT edge_inters_from_branch_id_fkey FOREIGN KEY (from_branch_id) REFERENCES branches(id);


--
-- Name: edge_inters_to_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY edge_inters
    ADD CONSTRAINT edge_inters_to_branch_id_fkey FOREIGN KEY (to_branch_id) REFERENCES branches(id);


--
-- Name: edges_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY edges
    ADD CONSTRAINT edges_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES branches(id);


--
-- Name: instance_relations_predecessor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY instance_relations
    ADD CONSTRAINT instance_relations_predecessor_id_fkey FOREIGN KEY (predecessor_id) REFERENCES branches(id);


--
-- Name: instance_relations_successor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY instance_relations
    ADD CONSTRAINT instance_relations_successor_id_fkey FOREIGN KEY (successor_id) REFERENCES branches(id);


--
-- Name: instances_node_version_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY instances
    ADD CONSTRAINT instances_node_version_fkey FOREIGN KEY (node_version) REFERENCES nodes(version);


--
-- Name: nodes_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY nodes
    ADD CONSTRAINT nodes_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES branches(id);


--
-- Name: users_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES branches(id);


--
-- PostgreSQL database dump complete
--

INSERT INTO "schema_migrations" ("filename") VALUES ('20140315161218_initial.rb');INSERT INTO "schema_migrations" ("filename") VALUES ('20140315161218_initial.rb');