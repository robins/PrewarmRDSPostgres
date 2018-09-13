/*
 * This Script allows an RDS User to avoid the negative side-effects of
 * the Lazy Loading feature of EBS (See Reference [1]).
 *
 * When an RDS Postgres instance is restored from an existing Snapshot,
 * the Lazy Loading feature of EBS allows one to launch a 16TB instance in
 * a matter of mintues. The flip-side to that feature, is that the first 
 * fetch (of each disk-block) requested by RDS Postgres, is going to be a
 * fetch from S3 which in-turn is a high-latency operation.
 *
 * This SQL Script prefetches all disk-blocks which although would experience
 * this issue too, however, once run an actual SQL Workload immediately 
 * thereafter should not see these high-latency side-effects.
 *
 * Additionally, it is possible that (for various reasons) the disk-blocks
 * asssociated to a datbase object being prefetched may get evicted 
 * (from memory) soon after, but this is still helpful, since the lazy-loading
 * side-effects can be guaranteed to have been resolved by then.
 *
 * Moreover, it doesn't prefetch Large-Object tables owing to an RDS 
 * limitation. There is "No workaround" for this (i.e. first fetch of a 
 * Large-Object would experience Lazy Load related side-effects)
 * 
 * Importantly, do note that owing to how database object permissions work, this
 * Script needs to be run once per DB User as well as per Database.
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
    current_database(),
    n.nspname AS schema_name,
    c.relname AS relation_name
  FROM pg_catalog.pg_class c
    LEFT JOIN y ON y.oid = c.oid
    LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind IN ('r', 'v', 'm', 'S', 'f')
    AND pg_catalog.pg_table_is_visible(c.oid)
    AND (y.oid IS NOT NULL OR EXISTS (select 1 from pg_roles where rolname = current_user and c.relowner = pg_roles.oid LIMIT 1))

UNION ALL

  SELECT 
    clock_timestamp(),
    pg_size_pretty(octet_length(string_agg(lo_get(lo.oid),''))::bigint) AS Table_Size,
    pg_size_pretty(0::BIGINT), 
    pg_size_pretty(0::BIGINT), 
    pg_size_pretty(0::BIGINT), 
    0,
    current_database(),
    NULL,
    'User''s large objects' AS relation_name
    FROM pg_largeobject_metadata lo
      JOIN pg_roles
        ON rolname = current_user
          AND lomowner = pg_roles.oid
ORDER BY 1, 6 DESC;

DROP EXTENSION IF EXISTS pg_prewarm;
SET statement_timeout TO DEFAULT;
