### Applied approach

• A record of the decisions behind it: what you chose, what you seriously considered and rejected, and the
fact or measurement that would change your mind.

- all or nothing approach
- filtering 


• Evidence that you ran it. The numbers your runs produced, the queries behind them, what you expected
before each one, and what changed between the first run and the second. Commit the exact inputs each
run used, so we can reproduce your numbers instead of trusting them.


• An account of the gap between what went in and what came out. Somebody will ask how many harmful
domains we know about, and the answer will not match the line counts of the four files, or their sum.
Show every step in between that drops or merges a record, down to the last one. This part wants
arithmetic rather than prose.


• A short note on what you left out, and what you would do next. If you spotted something in the data and
chose not to handle

- feed_b contains big number of IPs that I decided to filter out as the **domain** where mentioned in task instructions. In more extensive solution the IPs can be handled separatle and stored in another target table
- for the puropse of this task I've used all 4 files assuming we trust these sources are accurate, but some of the files are not updated for quite a while (TODO: provide the date, I think it was feed_c that had last_update from 2024). In more extensive solution where we expect some update frequency on sources I would add contract/expectation on source freshness
- 