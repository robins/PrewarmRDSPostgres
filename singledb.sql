/*
 * This Script allows an an RDS User to pre-fetch most of the Database
 * objects (owned by the user that triggers the SQL) to Cache, which 
 * effectively reduces the effect of Lazy Loading seen on AWS EBS.
 *
 * It doesn't pre-fetch the following:
 * 1. Toast tables [RDS limitation] - No workaround
 * 2. DB Objects owned by other users [RDS limitation, since SuperUser access is not available]
 * 2a. Workaround: Re-run SQL once for each Database User that owns any Database Object.
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
          CASE WHEN pg_relation_size(c.oid::regclass, 'vm') > 0 THEN pg_prewarm(c.oid::regclass, 'prefetch', 'vm') ELSE 0 END
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
        AND c.relname NOT ILIKE 'pg_toast%'
      ORDER BY c.relpages DESC;

DROP EXTENSION IF EXISTS pg_prewarm;
SET statement_timeout TO DEFAULT;
