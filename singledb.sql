/*
 * This Script allows an an RDS User to pre-fetch most of the Database
 * objects (owned by the user that triggers the SQL) to Cache, which 
 * effectively reduces the effect of Lazy Loading seen on AWS EBS.
 *
 * It doesn't pre-fetch the following:
 * 1. Toast tables [RDS limitation] - No workaround
 * ~~2. Indexes [pg_prewarm limitation] - No workaround~~ Evidently relkind expansion did the job
 * 3. DB Objects owned by other users [RDS limitation]
 * 3a. Workaround: Re-run SQL as other User
 */

CREATE EXTENSION IF NOT EXISTS pg_prewarm;

      SELECT clock_timestamp(), pg_prewarm(c.oid::regclass), 
      relkind, current_database(), n.nspname, c.relname
      FROM pg_class c
        JOIN pg_namespace n
          ON n.oid = c.relnamespace
        JOIN pg_user u
          ON u.usesysid = c.relowner
      WHERE u.usename NOT IN ('rdsadmin', 'rdsrepladmin', ' pg_signal_backend', 'rds_superuser', 'rds_replication')
      ORDER BY c.relpages DESC;
   
DROP EXTENSION IF EXISTS pg_prewarm;
