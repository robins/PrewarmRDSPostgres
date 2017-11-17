# PrewarmRDSPostgres
AWS RDS PostgreSQL uses EBS which has an interesting feature called Lazy Loading that allows it to instantiate a disk (of *any* size) at almost constant time. Although a fantastic feature, this however, can lead to unexpected outcomes when high-end production load is thrown at a newly launched RDS Postgres instance immediately after Restoring from a Snapshot.

This project tries to use various methods available to allow RDS Postgres Users to force 'Initialization' of Disk Blocks, using pg_prewarm PostgreSQL extension (which is supported in RDS PostgreSQL). This is useful for instance when you restore an RDS Postgres instance and cannot afford high Latencies for initial workload thrown at it.

Although pg_prewarm was originally meant for populating buffer-cache (and not for this purpose), the idea is common and (in this specific use-case) heaven-sent to Initialize (almost) the entire snapshot from S3 on to the RDS EBS volume in question.

For those who understand the working of pg_prewarm (and are concerned about Instance Memory / Cache sizes), do note that even if pg_prewarm runs through all tables etc., thereby effectively evicting the disk-blocks pushed to cache in a recent run for the previous table, it still does the job of initializing all disk-blocks with respect to the EBS volume, and thus still recommended.

Notably, the only exception here is that RDS Postgres doesn't allow direct access to TOAST tables / (& Indexes to TOAST Tables) and so those are not possible to be accessed via this method.


### SingleDB.SQL ###
When this SQL is run against each Database in an RDS Postgres Instance, it forces the Disk-Block Initialization for all (possible) Database Objects owned by the User that it is run as.

On a sample run (run on a pgbench database), my RDS Postgres instance returns this:

|        clock_timestamp        | table_size | freespace_map_size | visibility_map_size | blocks_prefetched | current_database | schema_name |      table_name       |
|-------------------------------|------------|--------------------|---------------------|-------------------|------------------|-------------|-----------------------|
| 2017-11-16 23:24:07.197221-05 | 13 GB      | 3240 kB            | 408 kB              |           1639801 | pgbench          | public      | pgbench_accounts      |
| 2017-11-16 23:27:36.333857-05 | 2142 MB    | 0 bytes            | 0 bytes             |            274194 | pgbench          | public      | pgbench_accounts_pkey |
| 2017-11-16 23:28:11.488585-05 | 440 kB     | 24 kB              | 8192 bytes          |                59 | pgbench          | public      | pgbench_tellers       |
| 2017-11-16 23:28:11.490687-05 | 240 kB     | 0 bytes            | 0 bytes             |                30 | pgbench          | public      | pgbench_tellers_pkey  |
| 2017-11-16 23:28:11.494527-05 | 40 kB      | 0 bytes            | 0 bytes             |                 5 | pgbench          | public      | pgbench_branches_pkey |
| 2017-11-16 23:28:11.496651-05 | 40 kB      | 24 kB              | 8192 bytes          |                 9 | pgbench          | public      | pgbench_branches      |
| 2017-11-16 23:28:11.496708-05 | 0 bytes    | 0 bytes            | 0 bytes             |                 0 | pgbench          | public      | pgbench_history       |
(7 rows)
