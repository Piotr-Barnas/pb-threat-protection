-- Run after the complete pipeline succeeds.
-- Change catalog/schema here and the snapshot run_id below to your actual values.
USE CATALOG workspace;
USE SCHEMA pb_threat_intelligence;

-- Latest audit entry per metric: do not sum repeated attempts.
-- Validation status is ranked together, so a successful retry replaces a failure.
CREATE OR REPLACE TEMP VIEW selected_audit AS
SELECT run_id, run_date, feed_name, stage, status, record_count, previous_count, ratio, logged_at
FROM (
  SELECT *, row_number() OVER (
    PARTITION BY feed_name, stage,
      CASE WHEN stage IN ('parsed', 'accepted domains') THEN '' ELSE status END
    ORDER BY logged_at DESC
  ) AS rn
  FROM feed_count_audit
  WHERE run_id = '200837Z_dfd4f58a' -- first run: '194013Z_0de50b39', second run: '200837Z_dfd4f58a'
)
WHERE rn = 1;

-- SELECT * FROM selected_audit;

-- 1. Expect eight passed checks: two per feed
SELECT feed_name, stage, status, record_count, previous_count, ratio
FROM selected_audit
WHERE stage IN ('parsed', 'accepted domains')
ORDER BY feed_name, stage;

-- results:
-- 194013Z_0de50b39 feed_b parsed: 18253
-- 200837Z_dfd4f58a 



-- 2. check parsing stage
-- file lines -> parsed observations
-- Extra aliases add records
-- skipped lines and system hosts remove records
------------------------------------------------
-- expect: four rows with difference and storage_difference = 0
WITH counts AS (
  SELECT feed_name,
    max(CASE WHEN stage = 'input lines' THEN record_count END) AS input_lines,
    max(CASE WHEN stage = 'skipped lines' THEN record_count END) AS skipped_lines,
    max(CASE WHEN stage = 'extra aliases' THEN record_count END) AS extra_aliases,
    max(CASE WHEN stage = 'system hosts' THEN record_count END) AS system_hosts,
    max(CASE WHEN stage = 'parsed' THEN record_count END) AS parsed
  FROM selected_audit WHERE feed_name <> 'all feeds' GROUP BY feed_name
), stored AS (
  SELECT feed_name, count(*) AS observations
  FROM feed_observations
  WHERE run_id = (SELECT max(run_id) FROM selected_audit)
  GROUP BY feed_name
)
SELECT c.*, coalesce(s.observations, 0) AS stored_observations,
  input_lines - skipped_lines + extra_aliases - system_hosts - parsed AS difference,
  parsed - coalesce(s.observations, 0) AS storage_difference
FROM counts c LEFT JOIN stored s USING (feed_name)
ORDER BY feed_name;

-- 3. every reason for removing/merging a parsed record.
SELECT feed_name, status AS reason, record_count
FROM selected_audit WHERE stage = 'filtered out'
ORDER BY feed_name, status;

-- results:
-- 194013Z_0de50b39 feed_b IPs: 15483
-- 200837Z_dfd4f58a 



-- 4. full balance
------------------------------------------------
-- expect: difference = 0, published_difference = 0, rows_from_other_runs = 0
-- published = output_count
-- NULL means missing audit evidence
WITH totals AS (
  SELECT
    sum(CASE WHEN stage = 'input lines' THEN record_count END) AS input_lines,
    sum(CASE WHEN stage = 'skipped lines' THEN record_count END) AS skipped_lines,
    sum(CASE WHEN stage = 'extra aliases' THEN record_count END) AS extra_aliases,
    sum(CASE WHEN stage = 'system hosts' THEN record_count END) AS system_hosts,
    sum(CASE WHEN stage = 'parsed' THEN record_count END) AS parsed,
    coalesce(sum(CASE WHEN stage = 'filtered out' THEN record_count END), 0) AS filtered,
    max(CASE WHEN stage = 'current domains' AND status = 'published' THEN record_count END) AS published
  FROM selected_audit
), output AS (
  SELECT count(*) AS output_count,
    count_if(NOT (c.run_id <=> chosen.run_id)) AS rows_from_other_runs
  FROM domains_classification_current c
  CROSS JOIN (SELECT max(run_id) AS run_id FROM selected_audit) chosen
)
SELECT *, input_lines - skipped_lines + extra_aliases - system_hosts
          - filtered - output_count AS difference,
          published - output_count AS published_difference
FROM totals CROSS JOIN output;

-- 5. Output summary
-- invalid_rows must be 0 and rows = unique_domains.
SELECT category, count(*) AS rows, count(DISTINCT domain) AS unique_domains,
  count_if(domain IS NULL OR category IS NULL OR feeds IS NULL OR feed_count IS NULL
           OR feed_count < 1 OR feed_count <> size(feeds)
           OR size(feeds) <> size(array_distinct(feeds))) AS invalid_rows
FROM domains_classification_current GROUP BY category;


-- after 194013Z_0de50b39: ads_and_trackers = 135977 | malware = 2770 (it's matching with parsed - IPs: 18253 - 15483)
-- after 200837Z_dfd4f58a:

-- check duplicated domains
------------------------------------------------
-- expect: no rows
SELECT domain, count(*) AS copies
FROM domains_classification_current
GROUP BY domain HAVING count(*) <> 1;

-- 6. check active history match current values AND multiplicity.
-- run_id is deliberately excluded: an unchanged history row retains its original run
------------------------------------------------
-- expect: no rows
WITH current_values AS (
  SELECT domain, category, sort_array(feeds) AS feeds, feed_count
  FROM domains_classification_current
), active_values AS (
  SELECT domain, category, sort_array(feeds) AS feeds, feed_count
  FROM domains_classification_history WHERE is_current
)
SELECT 'current_only' AS difference, * FROM (
  SELECT * FROM current_values EXCEPT ALL SELECT * FROM active_values
)
UNION ALL
SELECT 'history_only' AS difference, * FROM (
  SELECT * FROM active_values EXCEPT ALL SELECT * FROM current_values
);

-- 7. history intervals must be valid and must not overlap
------------------------------------------------
-- expect: no rows
WITH versions AS (
  SELECT *, lead(valid_from) OVER (PARTITION BY domain ORDER BY valid_from) AS next_from
  FROM domains_classification_history
)
SELECT * FROM versions
WHERE valid_from IS NULL OR is_current IS NULL
   OR (is_current AND valid_to IS NOT NULL)
   OR (NOT is_current AND valid_to IS NULL)
   OR valid_to < valid_from
   OR (next_from IS NOT NULL AND (valid_to IS NULL OR valid_to > next_from));

-- 8. changes introduced by the second run
------------------------------------------------
-- expect: no changes, as the two runs were executed close together
-- unchanged = 138747 (so all rows not changed and nothing new inserted)
WITH changes AS (
    SELECT
        domain,
        MAX(CASE
            WHEN run_id = '200837Z_dfd4f58a' -- second run_id
            THEN 1 ELSE 0
        END) AS opened,
        MAX(CASE
            WHEN closed_by_run_id = '200837Z_dfd4f58a'
            THEN 1 ELSE 0
        END) AS closed,
        MAX(CASE
            WHEN is_current THEN 1 ELSE 0
        END) AS active
    FROM domains_classification_history
    GROUP BY domain
),
classified AS (
    SELECT
        domain,
        CASE
            WHEN opened = 1 AND closed = 1 THEN 'changed'
            WHEN opened = 1 AND closed = 0 THEN 'added_or_returned'
            WHEN opened = 0 AND closed = 1 THEN 'removed'
            WHEN opened = 0 AND closed = 0 AND active = 1 THEN 'unchanged'
        END AS change_type
    FROM changes
)
SELECT change_type, COUNT(*) AS domains
FROM classified
WHERE change_type IS NOT NULL
GROUP BY change_type
ORDER BY change_type;