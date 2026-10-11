# Approach and trade-offs

The pipeline:
1. downloads four feeds,
2. keeps the original files and metadata,
3. parses them into `feed_observations`,
4. builds table with latest classification: one category per domain,
5. validates the counts,
6. and updates SCD2 history.

### Rules applied

- **All or nothing:** every feed must download and pass validation. Publishing a partial snapshot could incorrectly remove domains from the current state and close their history. I've considered partial processing, but it would require explicit rules for retaining missing feeds.
- **Reproducible inputs:** original snapshots, timestamps and SHA-256 hashes allow the same inputs to be processed again. Observations are replaced only for the selected snapshot run.
- **Domain-only output:** IP addresses (15483 out of 18253 feed_b's malware records) and invalid candidates are excluded. Comments, unsupported lines and system hostnames are filltered-out and counted separately.
- **Conservative www mapping:** a leading `www` or `www<number>` label is removed only if the resulting hostname exists in the same run. Other subdomains remain separate, because they serve differnet purposes.

    That means `[www.example.com, example.com]` -> `example.com`, but single `www.example.com` will stay untouched. Original host/category evidence remains in observations.

- **Classification and sources:** malware wins over ads/trackers. Source feeds are collected after www mapping and before deduplication/category selection.
    - `feeds` means all feeds supporting the normalized domain, not necessarily the winning category.
    - `feed_count` measures source coverage, not confidence;
- **Simple quality gates:** each feed needs parsed records and valid unique domains. Both counts are compared with its previous successfully stored parse -> a drop above 70% stops the run. The 70% drop threshold is a simple safeguard chosen for this assessment. In production, I would adjust it based on each feed’s normal variation that would determine a better threshold.
- **Publication and history:** domain uniqueness and the full count balance are checked before overwriting `current`, and checked again afterwards. History closes removed/changed rows and inserts new versions in one MERGE. It uses snapshot time. Older snapshots are rejected; historical replay should use a separate schema.

## Limits and next steps

All four sources are treated as trusted for this assessment: their domain classifications are accepted without independent verification. However, the saved feed_c declares Last modified: 2024-05-12, which raises concerns about its freshness. It is included for completeness, but a production version would need source-specific freshness expectations and a policy for handling stale feeds.

`current` and history are separate tables, so their updates are not one transaction. Run only one pipeline at a time per schema, including daily and replay jobs. If history fails, repair that run before processing another snapshot. A single publication boundary, stronger concurrency controls, retention, alerts and a schedule are deferred rather than added to this assessment.

The parser supports hosts entries and simple `||hostname^` rules, not the full adblock language. Its hostname pattern intentionally allows underscores.

### Open points:

* Full category priority order beyond "malware first"
* Stronger concurrency controls that would secure cases like multiple parallel jobs or replays overwritting current state with an old one
* Retention policy for old `feed_snapshots`
* Intended schedule + timezone for the daily job
* Alerts on failure/long processing time etc.
* IP indicators could be stored separately in a wider solution.

###### Audit queries are in `verification.sql`
###### An account of the gap between what went in and what came out
is verified in Validate_counts job step (`04_final_validation.ipynb file`)
