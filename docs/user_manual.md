# User manual

###### Prerequisits:
- A Databricks workspace with Unity Catalog enabled, including a suitable Free Edition workspace.
- Permission to deploy/run jobs and access to compute capable of running the notebooks.
- An existing catalog where you can create a schema, Delta tables and a volume. The default catalog is workspace.

##### Step-by-step instruction:

1. Create `Git Folder` within your Workspace using this GitHub repo link: https://github.com/Piotr-Barnas/pb-threat-protection.git
2. Go to: `./pb-threat-protection/pb_threat_protection_daily_job`
3. Click `open in editor` button
4. Deploy the bundle by clicking:
    1. Deployments section on side-bar (rocket sign)
    2. Deploy sign (leave source and target as `prod` -  it's fine for this task without real code life-cycle principles)
    3. Deploy

    ![deployment instruction screenshot](deployment_instruction.png)
5. Go to `Jobs & Pipelines` section
6. Open `pb_threat_protection_config` job
7. (optional) Setup job parameters before executing, by clicngin `Run now with different settings`. The parameters will determine target location for volume and tables used in main pipeline:
    - catalog (by default workspace)
    - schema (by default pb_threat_intelligence)
**Important:** if parameters changed, please remember to setup accordingly on further processing steps (step 10. and testing queries)
8. Click `Run now`. Wait for the job to finish with `Succeeded` status. It should take around 1 minute
9. Afterwards, go back to `Jobs & Pipelines` section.
10. Choose depending on preferences / run purpose. If you want to run:
    - **full daily pipeline** on the actuall feeds' data sources - go to `pb_threat_protection_daily_job` and run it
    - **test pipeline** on saved input snapshots - go to `pb_threat_protection_replay` and run it

### Replay and safe retries

- The replay job points to the included `stored_inputs/20261011/194013Z_0de50b39` snapshot. If you want to rerun both of the stored inputs, for the second run change the parameter to `stored_inputs/20261011/200837Z_dfd4f58a`
- In case you already run daily pipeline with up-to-date sources and you want to run a historical replay:
    - choose a separate schema (for example `pb_threat_intelligence_replay`),
    - run the config job with that schema,
    - then run replay with the same catalog/schema.
- Do not run daily and replay concurrently against one schema: their concurrency limits are per job.
- An older snapshot is rejected if a newer current state/history already exists.
If the history task fails, repair the same run before starting a new snapshot.

After a successful run, execute `docs/verification.sql` with the same catalog/schema
and the run_id (`194013Z_0de50b39` / `200837Z_dfd4f58a`). The expected differences are zero.
