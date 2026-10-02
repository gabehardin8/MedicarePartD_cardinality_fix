# MedicarePartD_cardinality_fix
Creating temporary and permanent fixes for the cardinality of table relationships in a database built off the Medicare Part D Public Use File

**Dataset:** Medicare Part D Prescribers Public Use File: https://data.cms.gov/provider-summary-by-type-of-service/medicare-part-d-prescribers

**Please Note:**
This README walks through the cleaned-up version of the investigation. If you want to see the real, unedited session — every query I ran along the way, including dead ends and in-progress comments to myself — it's included in this repo as [`ugly_SQL.sql`](ugly_SQL.sql).

## Question I was answering: 
*Which prescriber specialty had the highest total number of opioid claims?*

## Database Schema

<img width="938" height="611" alt="ERD" src="https://github.com/user-attachments/assets/4d23d91f-2031-4bd4-8a63-29eb637e8beb" />


The bug in this writeup lives in the `drug` table's relationship to `prescription` — it looks like a simple one-to-many connection on `drug_name`, but turned out to have a hidden second grain (`generic_name`) underneath it.




## The query that started this

```sql
SELECT
    specialty_description,
    SUM(total_claim_count) AS claim_count
FROM prescription
    INNER JOIN drug USING (drug_name)          -- the join that should have caused duplicates
    INNER JOIN prescriber USING (npi)
WHERE opioid_drug_flag = 'Y'                   -- the filter that (I'd later learn) avoided the duplicates
GROUP BY specialty_description
ORDER BY claim_count DESC;
```

This query ran fine and returned a plausible-looking answer. But I noticed that the JOIN numbers were inflating when I did INNER JOIN from a smaller table to a larger one. One-Many cardinalities shouldn't allow that.

## Finding the actual grain of the table

```sql
SELECT 
	drug_name
	,COUNT(drug_name) AS duplicates
FROM drug
GROUP BY drug_name
HAVING COUNT(generic_name) > 1 -- this line demonstrates that there are duplicates because the drug table has multiple generic names for every drug
ORDER BY duplicates DESC
```

This counted how many times the rows appeared for the same "drug_name" and different "generic_names". This confirmed that the the `drug` table's real grain is `(drug_name, generic_name)`, not `drug_name` alone

## Testing a fix — and getting suspicious when nothing changed

My first instinct was to deduplicate `drug_name` before joining:

```sql
WITH drug_deduped AS (
    SELECT DISTINCT drug_name, opioid_drug_flag
    FROM drug
    WHERE opioid_drug_flag = 'Y'
)
SELECT
    specialty_description,
    SUM(total_claim_count) AS claim_count
FROM prescription
    INNER JOIN drug_deduped USING (drug_name)
    INNER JOIN prescriber USING (npi)
WHERE opioid_drug_flag = 'Y'
GROUP BY specialty_description
ORDER BY claim_count DESC;
```

The totals came back **identical** to the original query. That was the real signal — if deduplication changes nothing, either there's no duplication problem in this slice of the data, or something else already filtered it out. I didn't assume it was a coincidence; I went to prove it.

## Testing my hypothesis

I checked the whole table, not just the filtered slice:

```sql
-- opioids only: any drug_name tied to more than one generic_name?
SELECT drug_name, COUNT(DISTINCT generic_name)
FROM drug
WHERE opioid_drug_flag = 'Y'
GROUP BY drug_name
HAVING COUNT(DISTINCT generic_name) > 1;        -- zero rows

-- the whole table: same check, no filter
SELECT drug_name, COUNT(DISTINCT generic_name) AS regular
FROM drug
GROUP BY drug_name
HAVING COUNT(DISTINCT generic_name) > 1;        -- 125 drug_names affected
```

125 drug names — mostly combination products like multivitamins, electrolyte solutions, and insulin syringe brands — have more than one `generic_name` row. None of the affected drugs happened to be opioids, which is exactly why my opioid-only query was never actually wrong — the `WHERE opioid_drug_flag = 'Y'` filter was accidentally protecting it the whole time.

## A second, separate bug: conflicting flags on the same drug

While checking for duplicate `drug_name`s another way, I found something different — the same `drug_name` appearing with *both* `Y` and `N` for `opioid_drug_flag`:

```sql
WITH almost_deduped AS (
    SELECT DISTINCT drug_name, opioid_drug_flag FROM drug
)
SELECT drug_name, COUNT(drug_name)
FROM almost_deduped
GROUP BY drug_name
HAVING COUNT(drug_name) > 1;
```

Five drug names came back, including **DEMEROL**, **MEPERIDINE HCL**, and **HYDROMORPHONE HCL** — all unambiguously opioids. There's no clinical reason any of these should ever be flagged `N`. This wasn't a modeling problem like the first issue; it was a data-entry/labeling inconsistency in the source flag itself. Since all five are legitimately opioids regardless of which row's flag you trust, I treated these as safe to collapse during cleanup rather than something requiring a judgment call.

## Short-term fix

Reusable at query time, no changes to the underlying table:

```sql
WITH drug_deduped AS (
    SELECT DISTINCT drug_name, opioid_drug_flag
    FROM drug
    WHERE opioid_drug_flag = 'Y'
)
SELECT ...
FROM prescription INNER JOIN drug_deduped USING (drug_name) ...
```

This is safe to drop into any report, but it has to be remembered and reapplied every time someone writes a new query against `drug`.

## Long-term fix

To actually close the hole, I worked on a copy of the table first — not the original — so the fix couldn't damage the shared class dataset if something went wrong:

```sql
CREATE TABLE drug_backup AS SELECT * FROM drug;
```

Then removed the duplicate rows, keeping one row per `drug_name`:

```sql
DELETE FROM drug_backup
WHERE ctid NOT IN (
    SELECT MIN(ctid)
    FROM drug
    GROUP BY drug_name
);
```

Row count dropped from 3,258 to 3,253 — exactly the 5 conflicting-flag rows identified above, confirming the cleanup removed precisely the rows it should have and nothing else.

Finally, locked in the fix so it can't silently reappear:

```sql
ALTER TABLE drug_backup
ADD CONSTRAINT drug_name UNIQUE (drug_name);
```

Any future insert or update that tries to create a duplicate `drug_name` will now be rejected outright by the database itself, rather than relying on every analyst remembering to write a `DISTINCT` clause.

## Reproducing this

The full dataset is public — this project uses CMS's [Medicare Part D Prescribers by Provider and Drug](https://data.cms.gov/provider-summary-by-type-of-service/medicare-part-d-prescribers/medicare-part-d-prescribers-by-provider-and-drug) data, free to download directly from data.cms.gov. The table structure above (`prescriber` / `drug` / `prescription`) is a normalized schema built for coursework, not the raw file layout, so rebuilding it from scratch isn't necessary just to see the bug in action.

This small, self-contained sample reproduces both issues — the combination-product row fan-out and the conflicting opioid flags — in any Postgres instance, no download required:

```sql
CREATE TABLE drug (
    drug_name TEXT,
    generic_name TEXT,
    opioid_drug_flag CHAR(1)
);

INSERT INTO drug (drug_name, generic_name, opioid_drug_flag) VALUES
    ('FENTANYL CITRATE',   'FENTANYL',       'Y'),
    ('MORPHINE SULFATE',   'MORPHINE',       'Y'),
    ('DEMEROL',            'MEPERIDINE HCL', 'Y'),
    ('DEMEROL',            'MEPERIDINE HCL', 'N'),  -- conflicting-flag bug
    ('HYDROMORPHONE HCL',  'HYDROMORPHONE',  'Y'),
    ('HYDROMORPHONE HCL',  'HYDROMORPHONE',  'N'),  -- conflicting-flag bug
    ('CLINIMIX E',         'DEXTROSE',       'N'),
    ('CLINIMIX E',         'SODIUM CHLORIDE','N'),  -- combination product: 1 drug_name, 2 generic_names
    ('CICLOPIROX',         'CICLOPIROX',     'N');

CREATE TABLE prescription (
    npi BIGINT,
    drug_name TEXT,
    total_claim_count INT
);

INSERT INTO prescription VALUES
    (1111111111, 'CLINIMIX E',       50),   -- will fan out to 2 rows on join
    (1111111111, 'FENTANYL CITRATE', 20);   -- stays 1-to-1

-- see the fan-out:
SELECT * FROM prescription INNER JOIN drug USING (drug_name);

-- see the hidden grain problem:
SELECT drug_name, COUNT(DISTINCT generic_name)
FROM drug
GROUP BY drug_name
HAVING COUNT(DISTINCT generic_name) > 1;

-- see the conflicting flags:
SELECT drug_name, opioid_drug_flag, COUNT(*)
FROM drug
GROUP BY drug_name, opioid_drug_flag
HAVING COUNT(*) > 0
ORDER BY drug_name;
```

Running the first query here shows `CLINIMIX E`'s 50 claims duplicated into two rows, while `FENTANYL CITRATE` stays clean — the exact same failure mode.

## Why this mattered

The scariest bugs aren't the ones that throw an error — they're the ones that return a plausible number that happens to be right for the wrong reason. My opioid query wasn't wrong, but it was only correct by accident, because a `WHERE` clause happened to filter out every drug affected by the underlying join problem. A slightly different question — total claims for *all* drugs, or a specialty breakdown for a non-opioid category — would have hit the same duplication and quietly inflated the results with no warning at all.

**Tools:** PostgreSQL, pgAdmin
