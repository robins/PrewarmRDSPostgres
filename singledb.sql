/*
 * This Script allows an an RDS User to pre-fetch most of the Database
 * objects (owned by the user that triggers the SQL) to Cache.
 * 
 * Although large databases may get some objects evicted out of cache
 * this SQL is highly beneficial for RDS PostgreSQL users who have recently
 * Restored their RDS Instances from a Snapshot and need a way to touch all
 * disk-blocks to remove all Lazy Load related side-effects when the 
 * production workload is sent through.
 * 
 * However, it doesn't pre-fetch Large-Object tables owing to an RDS 
 * limitation. There is "No workaround" for this (i.e. first fetch of a 
 * Large-Object would experience Lazy Load related side-effects)
 * 
 * Importantly, do note that for best results, this Script needs to be run 
 * once per DB User, per Database, per RDS Instance. Further, it needs to be
 * run by the DB User that has SELECT permissions on all DB Objects.
 */

SET statement_timeout TO 0;
CREATE EXTENSION IF NOT EXISTS pg_prewarm;

      SELECT 
        clock_timestamp(),
        pg_size_pretty(pg_relation_size(c.oid::regclass)) AS Table_Size,
        pg_size_pretty(pg_relation_size(c.oid::regclass, 'fsm')) AS FreeSpace_Map_Size,
        pg_size_pretty(pg_relation_size(c.oid::regclass, 'vm')) AS Visibility_Map_Size,
        (SELECT 
          pg_prewarm(c.oid::regclass, 'prefetch', 'main') +
          CASE WHEN pg_relation_size(c.oid::regclass, 'fsm') > 0 THEN pg_prewarm(c.oid::regclass, 'prefetch', 'fsm') ELSE 0 END +
          CASE WHEN pg_relation_size(c.oid::regclass, 'vm') > 0 THEN pg_prewarm(c.oid::regclass, 'prefetch', 'vm') ELSE 0 END + 
          CASE WHEN c.relpersistence = 'u' THEN pg_prewarm(c.oid::regclass, 'prefetch', 'init') ELSE 0 END
         ) as Blocks_Prefetched,
        current_database(),
        n.nspname AS schema_name,
        c.relname AS table_name
      FROM pg_class c
        JOIN pg_namespace n
          ON n.oid = c.relnamespace
        JOIN pg_user u
          ON u.usesysid = c.relowner
      WHERE u.usename NOT IN ('rdsadmin', 'rdsrepladmin', ' pg_signal_backend', 'rds_superuser', 'rds_replication')
        AND c.relkind IN ('r', 'i')
      ORDER BY c.relpages DESC;

DROP EXTENSION IF EXISTS pg_prewarm;
SET statement_timeout TO DEFAULT;
