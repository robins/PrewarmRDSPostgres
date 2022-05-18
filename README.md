# PrewarmRDSPostgres
AWS RDS PostgreSQL uses EBS which has an interesting feature called Lazy Loading that allows it to instantiate a disk (of *any* size) at almost constant time. Although a fantastic feature, this however, can lead to unexpected outcomes when high-end production load is thrown at a newly launched RDS Postgres instance immediately after Restoring from a Snapshot.

This project tries to use various methods available to allow RDS Postgres Users to force 'Initialization' of Disk Blocks, using pg_prewarm PostgreSQL extension (which is supported in RDS Postgres). This is useful for instance when you restore an RDS Postgres instance and cannot afford high Latencies for the initial workload thrown at it.

Although pg_prewarm was originally meant for populating buffer-cache (and not for this purpose), the idea is common and (in this specific use-case) heaven-sent to Initialize (almost) the entire snapshot from S3 on to the RDS EBS volume in question.

For those who understand the working of pg_prewarm (and are concerned about Instance Memory / Cache sizes), do note that even if pg_prewarm runs through all tables etc., thereby effectively evicting the disk-blocks pushed to cache in a previous run for a recent table, it still does the job of initializing all disk-blocks with respect to the EBS volume, and thus still recommended (for the above use-case).

Notably, TOAST tables are handled in a special way, owing to how Postgres treats them. For this, please refer to 'toast.sql' Script in this Repository.


### SingleDB.SQL ###
When this SQL is run against each Database in an RDS Postgres Instance, it forces the Disk-Block Initialization for all Database Objects owned by the User (or for which there are SELECT privileges).

On a sample run (run on a pgbench database), my RDS Postgres instance returns this:

|        clock_timestamp        | table_size | freespace_map_size | visibility_map_size | init_size | blocks_prefetched | schema_name |      table_name       |
|-------------------------------|------------|--------------------|---------------------|-----------|-------------------|-------------|-----------------------|
| 2018-09-29 07:11:33.688139+00 | 1281 MB    | 344 kB             | 48 kB               | 0 bytes   |            163984 | public      | pgbench_accounts     |
| 2018-09-29 07:11:57.970511+00 | 8192 bytes | 24 kB              | 8192 bytes          | 0 bytes   |                 5 | public      | pgbench_branches     |
| 2018-09-29 07:11:57.970735+00 | 0 bytes    | 0 bytes            | 0 bytes             | 0 bytes   |                 0 | public      | pgbench_history      |
| 2018-09-29 07:11:57.970804+00 | 48 kB      | 24 kB              | 8192 bytes          | 0 bytes   |                10 | public      | pgbench_tellers      |
| 2018-09-29 07:11:57.971753+00 | ¤          | 0 bytes            | 0 bytes             | 0 bytes   |                 0 | ¤           | User's large objects |
(5 rows)

### Toast.SQL ###
On a sample run (run on a pgbench database), my RDS Postgres instance returns this:

pg_user@pgbench=> 
SELECT
  'VACUUM FULL ' || c.relnamespace::regnamespace || '.' || relname || ';' AS vacuum_sql
FROM pg_class c
WHERE reltoastrelid > 0
ORDER BY 1;

|                       vacuum_sql        
|----------------------------------------------------------
| VACUUM FULL information_schema.sql_features;            |
| VACUUM FULL information_schema.sql_implementation_info; |
| VACUUM FULL information_schema.sql_languages;           |
| VACUUM FULL information_schema.sql_packages;            |
| VACUUM FULL information_schema.sql_parts;               |
| VACUUM FULL information_schema.sql_sizing;              |
| VACUUM FULL information_schema.sql_sizing_profiles;     |
| VACUUM FULL pg_catalog.pg_attrdef;                      |
| VACUUM FULL pg_catalog.pg_constraint;                   |
| VACUUM FULL pg_catalog.pg_db_role_setting;              |
| VACUUM FULL pg_catalog.pg_description;                  |
| VACUUM FULL pg_catalog.pg_proc;                         |
| VACUUM FULL pg_catalog.pg_rewrite;                      |
| VACUUM FULL pg_catalog.pg_seclabel;                     |
| VACUUM FULL pg_catalog.pg_shdescription;                |
| VACUUM FULL pg_catalog.pg_shseclabel;                   |
| VACUUM FULL pg_catalog.pg_statistic;                    |
| VACUUM FULL pg_catalog.pg_statistic_ext;                |
| VACUUM FULL pg_catalog.pg_trigger;                      |
(19 rows)
