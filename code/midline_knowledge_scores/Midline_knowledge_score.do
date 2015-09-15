loc name_do Midline_knowledge_score

cap log close
cap file close _all
log using "${NPL_Agri}/Analysis/logs/`name_do'.smcl", replace

set varabbrev on
set more off

/* PROGRAM DESCRIPTION
Program: Midline_knowledge_score.do
Task: Grades Midline questions (G22-G32)
Project: ICIMOD NEPAL AGRICULTURE
Edited: Seungmin Lee, 15 September 2015 */

/*
INPUTS/OUTPUTS
Inputs:
	"${NPL_Agri}/Analysis/data/Midline_knowledge.dta" - Midline dataset
	"${NPL_Agri}/Analysis/code/Midline_knowledge_scores/Knowledge_answers.do" - Answer keys for midline knowledge questions
	
Outputs:
	"${NPL_Agri}/Analysis/output/Midline_knowledge_graded.dta" - dataset including grades and incentive results
*/

/* Open a Midline dataset */
use "${NPL_Agri}/Analysis/data/knowledge_score/Midline_knowledge.dta", clear
notes drop _dta // Drop dataset notes for a new dataset

// Change baseline varibles temporarily to calculate answers
rename BL_G31* BL_G32*
rename BL_G30* BL_G31*
rename BL_G# BL_G#, renumber(22)
tempfile Midline_data
save `Midline_data'

// Define macros for answers 
** This task will be done by "Midline_knowledge_answers.do" file
include "${NPL_Agri}\Analysis\code\Midline_knowledge_scores\Knowledge_answers.do"

loc crop TOMATO GINGER FRENCH_BEANS
loc round BL MID
loc id_vars A02 A04 A06 A07 A08
local question_no G22 G23 G24 G25 G26 G27 G28 G29 G30 G31 G32
loc G31_fert UREA DAP POTAS
loc G32_fert SANDY_LOAM SANDY LOAM CLAY

/* Grading questions */
/* Correct answers are graded as 1, wrong answers (including missing obs) are graded as 0 */

foreach crops of local crop {
	di "`crops'"
	preserve
	keep if ("`crops'" == midline_crop)  // keeps villages with proper crop only
	foreach rd of local round {
		foreach q_no of local question_no {
			if (inlist("`q_no'","G31","G32")) {
				foreach fert of local `q_no'_fert {
					gen `rd'_`q_no'_`fert'_Correct = 0
					replace `rd'_`q_no'_`fert'_Correct = 1 if (`rd'_`q_no'_`fert' == ``q_no'_`crops'_`fert'')
					label var `rd'_`q_no'_`fert'_Correct "Did respondent answer ``rd'_`q_no'_`fert' correctly?"
					}
				}
			else {
				gen `rd'_`q_no'_Correct = 0
				replace `rd'_`q_no'_Correct = 1 if (`rd'_`q_no' >= ``q_no'_`crops'_LB' & `rd'_`q_no' <= ``q_no'_`crops'_UB')
				label var `rd'_`q_no'_Correct "Did respondent answer `rd'_`q_no' correctly?"
			}
		}
	}
	tempfile knowledge_score_`crops'
	save `knowledge_score_`crops''
	restore
}
use `knowledge_score_TOMATO', clear
append using `knowledge_score_GINGER' `knowledge_score_FRENCH_BEANS'

// Re-change some variables in baseline survey back to the original question numbers
rename BL_G# BL_G#, renumber(21)
rename BL_G31* BL_G30*
rename BL_G32* BL_G31*

/* Calculating average knowlege score at ward level per each round*/
foreach round in BL MID {
	quietly ds `round'*Correct
	loc `round'_Answers `r(varlist)'
	egen `round'_knowledge_score = rowtotal(``round'_Answers')
	bys A02 A04 A06 A07: egen Avg_`round'_knowledge_score = mean(`round'_knowledge_score)
	label var `round'_knowledge_score "HH's `round' knowledge score"
	label var Avg_`round'_knowledge_score "Ward-level average `round' knowledge score"
	sort `id_vars'
}
/* Incentive-decision */
gen incentive = 0
// Incentive threshold: 20% increase AND 0.8 point increase in village-average score
tempvar pct_criteria fixed_criteria
gen `pct_criteria' = 1.2
gen `fixed_criteria' = 0.8
replace incentive = 1 if (Avg_MID_knowledge_score >= Avg_BL_knowledge_score * `pct_criteria' & Avg_MID_knowledge_score >= Avg_BL_knowledge_score + `fixed_criteria')
label var incentive "Does communicator of this village get incentives?"

/* Data Label */
label define YesorNo 0 "No" 1 "Yes"
quietly ds *Correct
label val `r(varlist)' incentive YesorNo

// Dataset notes
notes: Midline_knowledge_graded/ created by `name_do' - `c(username)' - `c(current_date)' 
notes: Created by "Midline_knowledge_score.do"

/* Save */
compress
save "${NPL_Agri}\Analysis\data\knowledge_score\Midline_knowledge_graded_ver2.dta", replace

// Close log and exit
cap file close _all
cap log close
exit

/*
// Check the scores for each crop
// Distribution is bothering
// 1) Why are there so many '0's? 
  ex) Go through the questionnaire and understand skipping patterns (some responents might not answer the questions cuz they skipped it)
     It it because they are really missing? or they answered as "don't know" (actually went through the questions)
	  => There are skip codes (g01_t, G01_g, g01_f)
	  => Label the households who skipped the questions as "skipped" instead of giving "0" score.
   2) Gradiing criteria- Answers that slightly differ should also be correctd. (ex. answer is 50cm, but a person answered as 49cm)
   3) Differences in scores b/w Tomato, Ginger and French Beans
   4) Make the score interpretable (out of 100)
   
  *** Some households may know nothing at baseline (so their answers are missing ) but knew something at midline (so their answers are non-missing)
  => We should take this into consideration, since this is different from knowing something both at baseline and midline.
  
