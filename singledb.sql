/*
 * Brief: This Script allows an RDS Postgres User to remove latency related
 * side-effects of the Lazy Loading feature of EBS when subjecting it
 * to actual Production Workload.
 *
 * You can read more about the Lazy Loading feature of EBS here[1].
 *
 * Background: When an RDS Postgres instance is restored from an existing
 * Snapshot, the Lazy Loading feature of EBS allows one to launch any instance
 * (even as large as 16 TB) in a matter of minutes. The flip-side to that 
 * feature, is the first fetch (of each disk-block) requested by RDS Postgres,
 * is going to be fetched from S3, which in-turn is a high-latency operation.
 *
 * This SQL Script can be used to prefetch all disk-blocks of a recently
 * restored RDS Postgres Instance, which although would also experience
 * lazy-loading related side-effects, however, production workload sent to the
 * RDS instance immediately thereafter can be guaranteed to not see these
 * side-effects.
 *
 * Notably, it tries to fetch all the following (associated to a DB User):
 * 1) Table / Materialized View etc.
 * 2) TOAST data related to the above relations (if any)
 * 3) Large Objects (if any)
 *
 * Importantly, do note that owing to how Postgres object permissions work,
 * this Script needs to be run once each per DB User / per Database. This can
 * be run in parallel (although the idea is to ensure that they all run
 * successfully, i.e. give an output at the end).
 *
 * [1] EBS Lazy Loading: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-restoring-volume.html
 */

SET statement_timeout TO 0;
CREATE EXTENSION IF NOT EXISTS pg_prewarm;

WITH y AS (
  SELECT oid, aclist
  FROM (
    SELECT oid, relowner, unnest(relacl)::TEXT as aclist
    FROM pg_class
    WHERE relacl IS NOT NULL
  ) a
  WHERE aclist ILIKE current_user || '%'
    OR EXISTS (select 1 from pg_roles where rolname = current_user and a.relowner = pg_roles.oid LIMIT 1)
)
 SELECT
    clock_timestamp(),
    pg_size_pretty(pg_relation_size(c.oid::regclass)) AS Table_Size,
    pg_size_pretty(pg_relation_size(c.oid::regclass, 'fsm')) AS FreeSpace_Map_Size,
    pg_size_pretty(pg_relation_size(c.oid::regclass, 'vm')) AS Visibility_Map_Size,
    pg_size_pretty(pg_relation_size(c.oid::regclass, 'init')) AS Init_Size,
    (SELECT 
      CASE WHEN pg_relation_size(c.oid::regclass, 'main') > 0 THEN pg_prewarm(c.oid::regclass, 'prefetch', 'main') ELSE 0 END +
      CASE WHEN pg_relation_size(c.oid::regclass, 'fsm') > 0  THEN pg_prewarm(c.oid::regclass, 'prefetch', 'fsm')  ELSE 0 END +
      CASE WHEN pg_relation_size(c.oid::regclass, 'vm') > 0   THEN pg_prewarm(c.oid::regclass, 'prefetch', 'vm')   ELSE 0 END + 
      CASE WHEN pg_relation_size(c.oid::regclass, 'init') > 0 THEN pg_prewarm(c.oid::regclass, 'prefetch', 'init') ELSE 0 END
     ) as Blocks_Prefetched,
    n.nspname AS schema_name,
    c.relname AS relation_name
  FROM pg_catalog.pg_class c
    INNER JOIN y ON y.oid = c.oid
    LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind IN ('r', 'v', 'm', 'S', 'f')
    AND pg_catalog.pg_table_is_visible(c.oid)

UNION ALL

  SELECT 
    clock_timestamp(),
    pg_size_pretty(SUM(octet_length(lo_get(lo.oid)))) AS Table_Size,
    pg_size_pretty(0::BIGINT), 
    pg_size_pretty(0::BIGINT), 
    pg_size_pretty(0::BIGINT), 
    0,
    NULL,
    'User''s large objects' AS relation_name
    FROM pg_largeobject_metadata lo
      JOIN pg_roles
        ON rolname = current_user
          AND lomowner = pg_roles.oid
ORDER BY 1, 6 DESC;

DROP EXTENSION IF EXISTS pg_prewarm;
SET statement_timeout TO DEFAULT;
