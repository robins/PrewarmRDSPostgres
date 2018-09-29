/*
 * Brief: This Script is an extension of the singledb.sql and focusses on 
 * prefetch of only TOAST data.
 *
 * Importantly, do note that owing to how pg_toast schema permission works,
 * it'd be simplest to run the SQL that is generated as output of the SQL
 * given below.
 */
 
SELECT 
  'VACUUM FULL ' || (SELECT nspname from pg_namespace n where n.oid = c.relnamespace) || '.' || relname || ';' 
FROM pg_class c
WHERE reltoastrelid > 0
ORDER BY 1;
