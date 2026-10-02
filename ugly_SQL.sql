--     b. Which specialty had the most total number of claims for opioids?

-- original code
SELECT 
	specialty_description
	,SUM(total_claim_count) AS claim_count
FROM prescription INNER JOIN drug USING (drug_name) -- the join that should have caused duplicates
				  INNER JOIN prescriber USING(npi)
WHERE opioid_drug_flag = 'Y' -- the filter that avoided the duplicates
GROUP BY specialty_description
ORDER BY claim_count DESC;


SELECT * 
FROM prescription INNER JOIN drug USING (drug_name) -- the query that revealed the poor relationship

SELECT 
	drug_name
	,COUNT(drug_name) AS duplicates
FROM drug
GROUP BY drug_name
HAVING COUNT(generic_name) > 1 -- this line demonstrates that there are duplicates because the drug table has multiple generic names for every drug
ORDER BY duplicates DESC 


-- the CTE that fixed the join issue (reuse for coding session)
WITH drug_deduped AS(
	SELECT DISTINCT drug_name
	,opioid_drug_flag
	FROM drug
	WHERE opioid_drug_flag = 'Y'
)
SELECT 
	specialty_description
	,SUM(total_claim_count) AS claim_count
FROM prescription INNER JOIN drug_deduped USING (drug_name)
				  INNER JOIN prescriber USING(npi)
WHERE opioid_drug_flag = 'Y'
GROUP BY specialty_description
ORDER BY claim_count DESC; -- the numbers were the same, which prompted me to find that the WHERE clauses avoided the problem drugs

SELECT DISTINCT drug_name
FROM drug
WHERE opioid_drug_flag = 'Y' -- guessing the WHERE clause was why the numbers weren't skewed in the original
	
SELECT drug_name
FROM drug
WHERE opioid_drug_flag = 'Y' 

-- next two queries prove the WHERE clause is why the numbers weren't skewed in the original
SELECT 
	drug_name
	, COUNT (DISTINCT generic_name)
FROM drug
WHERE opioid_drug_flag = 'Y'
GROUP BY drug_name
HAVING COUNT (DISTINCT generic_name) > 1;

SELECT drug_name, COUNT(DISTINCT generic_name) AS regular
FROM drug
GROUP BY drug_name
HAVING COUNT(DISTINCT generic_name) > 1;

-- just a list of the duplicated drugs: 'SODIUM CHLORIDE', 'INSULIN SYRINGE', 'ULTICARE', 'DEXTROSE IN WATER', 'ULTRA COMFORT', 'CLINIMIX E', 'SURE COMFORT', 'ULTICARE INSULIN SYRINGE', 'LITE TOUCH', 'COMFORT EZ', 'ULTRA-THIN II', 'EASY TOUCH', 'FENOFIBRATE', 'SURE COMFORT INSULIN SYRINGE', 'EASY TOUCH INSULIN SYRINGE', 'BD INSULIN SYRINGE ULT-FINE II', 'ADVOCATE SYRINGES', 'PRODIGY INSULIN SYRINGE', 'TOPCARE ULTRA COMFORT', 'MONOJECT INSULIN SYRINGE', 'LITETOUCH INSULIN SYRINGE', 'CLINIMIX', 'EASY COMFORT INSULIN SYRINGE', 'BD INSULIN SYRINGE MICRO-FINE', 'POTASSIUM CHLORIDE', 'CICLOPIROX', 'PRECISION', 'TRUEPLUS INSULIN SYRINGE', 'SURE-JECT INSULIN SYRINGE', 'FAMOTIDINE', 'ULTILET INSULIN SYRINGE', 'DESMOPRESSIN ACETATE', 'CYTARABINE', 'DERMA-SMOOTHE-FS', 'CIMETIDINE', 'EMEND', 'SE-NATAL 19', 'CIPROFLOXACIN', 'MULTIVITAMINS WITH FLUORIDE', 'MAKENA', 'ONDANSETRON HCL', 'TOBRAMYCIN', 'PROGESTERONE', 'MARCAINE', 'GAMMAPLEX', 'VALPROIC ACID', 'LEVOCARNITINE', 'MULTIVITAMINS W-FLUORIDE-IRON', 'FENTANYL CITRATE', 'VIBRAMYCIN', 'HYDROCORTISONE', 'KIONEX', 'DDAVP', 'SOLU-MEDROL', 'PRENATE DHA', 'ZOMETA', 'MIDAZOLAM HCL', 'ZOLEDRONIC ACID', 'LOFIBRA', 'MUPIROCIN', 'ERYTHROMYCIN', 'GEODON', 'CORTISPORIN', 'PEG 3350-ELECTROLYTE', 'DILANTIN', 'EASY TOUCH INSULIN SAFETY', 'ORENCIA', 'METRONIDAZOLE', 'CEFTAZIDIME', 'WATER', 'MULTIVITAMIN WITH FLUORIDE', 'HEPARIN SODIUM', 'MOXIFLOXACIN', 'MEPERIDINE HCL', 'CEFTRIAXONE', 'NITROFURANTOIN', 'HYDROMORPHONE HCL', 'MAGNESIUM SULFATE', 'CELLCEPT', 'MESALAMINE', 'BUPIVACAINE HCL', 'BETAMETHASONE DIPROPIONATE', 'EXELON', 'DEXAMETHASONE SODIUM PHOSPHATE', 'NECON', 'DEPAKENE', 'AVONEX', 'NORETHIN-ETH ESTRA-FERROUS FUM', 'LIDOCAINE HCL', 'PRENATE ELITE', 'MAGELLAN INSULIN SYRINGE', 'CICLODAN', 'TETRACAINE HCL', 'TERUMO INSULIN SYRINGE', 'IMITREX', 'VANCOMYCIN HCL', 'SODIUM SULFACETAMIDE-SULFUR', 'GRANISETRON HCL', 'HYDROCORTISONE BUTYRATE', 'FLUOCINOLONE ACETONIDE', 'CARNITOR', 'SAFETYGLIDE INSULIN SYRINGE', 'MORPHINE SULFATE', 'ZOSYN', 'RIVASTIGMINE', 'MAGELLAN INSULIN SAFETY SYRNG', 'DEMEROL', 'MAXI-COMFORT', 'CIPRO', 'PRENATE MINI', 'GENTAMICIN SULFATE', 'FENOFIBRIC ACID', 'SOLU-CORTEF', 'LEVAQUIN', 'LOPROX', 'HALOPERIDOL', 'BD INSULIN SYRINGE ULTRA-FINE', 'VANISHPOINT', 'INTEGRA SYRINGE', 'PRENATAL PLUS')

-- a backup table so that my long-term fix doesn't delete NSS data
CREATE TABLE drug_backup AS SELECT * FROM drug;

SELECT * 
FROM drug_backup; -- it works!

-- before I work on creating a fixed table, I want to know how to handle this problem:
SELECT DISTINCT drug_name
,opioid_drug_flag
FROM drug
-- the number of distinct drugs is 3258, but this query returns 3258 because it's asking for distinct instances of drug_name and opioid drug flags?

WITH almost_deduped AS(
	SELECT DISTINCT drug_name
	,opioid_drug_flag
	FROM drug
)
SELECT 
	drug_name
	,COUNT(drug_name)
FROM almost_deduped
GROUP BY drug_name
HAVING COUNT(drug_name) > 1; -- these five drugs definitely seem like opioids

SELECT *
FROM drug
WHERE drug_name IN (
	WITH almost_deduped AS(
	SELECT DISTINCT drug_name
	,opioid_drug_flag
	FROM drug
)
	SELECT 
		drug_name
	FROM almost_deduped
	GROUP BY drug_name
	HAVING COUNT(drug_name) > 1
)
ORDER BY drug_name, opioid_drug_flag; -- generic names with different opioid_drug_flags. probably just a problem with how the flags were assigned because these are definitely opioids.
-- so these extra rows can just be ignored then, they aren't meaningful

DELETE FROM drug_backup
WHERE ctid NOT IN (
    SELECT MIN(ctid)
    FROM drug
    GROUP BY drug_name
); -- this query essentially finds the first instance of a drug_name and drops all the rest from the "drug" table

SELECT *
FROM drug_backup -- numbers now back to 3253 like they should be

ALTER TABLE drug_backup
ADD CONSTRAINT drug_name UNIQUE (drug_name); -- these adds constraints to the drug_names so that there can not be duplicates in this table in the future

SELECT * FROM drug_backup


"SODIUM CHLORIDE"
"INSULIN SYRINGE"
"ULTICARE"
"DEXTROSE IN WATER"
"ULTRA COMFORT"
"CLINIMIX E"
"SURE COMFORT"
"ULTICARE INSULIN SYRINGE"
"LITE TOUCH"
"COMFORT EZ"
"ULTRA-THIN II"
"EASY TOUCH"
"FENOFIBRATE"
"SURE COMFORT INSULIN SYRINGE"
"EASY TOUCH INSULIN SYRINGE"
"BD INSULIN SYRINGE ULT-FINE II"
"ADVOCATE SYRINGES"
"PRODIGY INSULIN SYRINGE"
"TOPCARE ULTRA COMFORT"
"MONOJECT INSULIN SYRINGE"
"LITETOUCH INSULIN SYRINGE"
"CLINIMIX"
"EASY COMFORT INSULIN SYRINGE"
"BD INSULIN SYRINGE MICRO-FINE"
"POTASSIUM CHLORIDE"
"CICLOPIROX"
"PRECISION"
"TRUEPLUS INSULIN SYRINGE"
"SURE-JECT INSULIN SYRINGE"
"FAMOTIDINE"
"ULTILET INSULIN SYRINGE"
"DESMOPRESSIN ACETATE"
"CYTARABINE"
"DERMA-SMOOTHE-FS"
"CIMETIDINE"
"EMEND"
"SE-NATAL 19"
"CIPROFLOXACIN"
"MULTIVITAMINS WITH FLUORIDE"
"MAKENA"
"ONDANSETRON HCL"
"TOBRAMYCIN"
"PROGESTERONE"
"MARCAINE"
"GAMMAPLEX"
"VALPROIC ACID"
"LEVOCARNITINE"
"MULTIVITAMINS W-FLUORIDE-IRON"
"FENTANYL CITRATE"
"VIBRAMYCIN"
"HYDROCORTISONE"
"KIONEX"
"DDAVP"
"SOLU-MEDROL"
"PRENATE DHA"
"ZOMETA"
"MIDAZOLAM HCL"
"ZOLEDRONIC ACID"
"LOFIBRA"
"MUPIROCIN"
"ERYTHROMYCIN"
"GEODON"
"CORTISPORIN"
"PEG 3350-ELECTROLYTE"
"DILANTIN"
"EASY TOUCH INSULIN SAFETY"
"ORENCIA"
"METRONIDAZOLE"
"CEFTAZIDIME"
"WATER"
"MULTIVITAMIN WITH FLUORIDE"
"HEPARIN SODIUM"
"MOXIFLOXACIN"
"MEPERIDINE HCL"
"CEFTRIAXONE"
"NITROFURANTOIN"
"HYDROMORPHONE HCL"
"MAGNESIUM SULFATE"
"CELLCEPT"
"MESALAMINE"
"BUPIVACAINE HCL"
"BETAMETHASONE DIPROPIONATE"
"EXELON"
"DEXAMETHASONE SODIUM PHOSPHATE"
"NECON"
"DEPAKENE"
"AVONEX"
"NORETHIN-ETH ESTRA-FERROUS FUM"
"LIDOCAINE HCL"
"PRENATE ELITE"
"MAGELLAN INSULIN SYRINGE"
"CICLODAN"
"TETRACAINE HCL"
"TERUMO INSULIN SYRINGE"
"IMITREX"
"VANCOMYCIN HCL"
"SODIUM SULFACETAMIDE-SULFUR"
"GRANISETRON HCL"
"HYDROCORTISONE BUTYRATE"
"FLUOCINOLONE ACETONIDE"
"CARNITOR"
"SAFETYGLIDE INSULIN SYRINGE"
"MORPHINE SULFATE"
"ZOSYN"
"RIVASTIGMINE"
"MAGELLAN INSULIN SAFETY SYRNG"
"DEMEROL"
"MAXI-COMFORT"
"CIPRO"
"PRENATE MINI"
"GENTAMICIN SULFATE"
"FENOFIBRIC ACID"
"SOLU-CORTEF"
"LEVAQUIN"
"LOPROX"
"HALOPERIDOL"
"BD INSULIN SYRINGE ULTRA-FINE"
"VANISHPOINT"
"INTEGRA SYRINGE"
"PRENATAL PLUS"