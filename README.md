# PrewarmRDSPostgres
AWS RDS PostgreSQL uses EBS which has an interesting feature called Lazy Loading that allows it to instantiate a disk (of *any* size) at almost constant time. Although a fantastic feature, this however, can lead to unexpected outcomes when high-end production load is thrown at a newly launched RDS Postgres instance immediately after Restoring from a Snapshot.

This project tries to use various methods available to allow RDS Postgres Users to force 'Initialization' of Disk Blocks, using pg_prewarm PostgreSQL extension (which is supported in RDS PostgreSQL). This is useful for instance when you restore an RDS Postgres instance and cannot afford high Latencies for initial workload thrown at it.

Although pg_prewarm was originally meant for populating buffer-cache (and not for this purpose), the idea is common and (in this specific use-case) heaven-sent to Initialize (almost) the entire snapshot from S3 on to the RDS EBS volume in question.

For those who understand the working of pg_prewarm (and are concerned about Instance Memory / Cache sizes), do note that even if pg_prewarm runs through all tables etc., thereby effectively evicting the disk-blocks pushed to cache in a recent run for the previous table, it still does the job of initializing all disk-blocks with respect to the EBS volume, and thus still recommended.

Notably, the only exception here is that RDS Postgres doesn't allow direct access to TOAST tables / (& Indexes to TOAST Tables) and so those are not possible to be accessed via this method.


### SingleDB.SQL ###
When this SQL is run against each Database in an RDS Postgres Instance, it forces the Disk-Block Initialization for all (possible) Database Objects owned by the User that it is run as.
