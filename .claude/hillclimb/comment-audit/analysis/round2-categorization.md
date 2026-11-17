# Round 2: categorization instead of a content round

The round 2 analyzer read the v1 train split: 40 cases, 3 reps. It found no
single cause large enough to clear the noise floor. Test has 38 cases, one
case moves test gate_correct by about 2.6 points, and the floor is about
+/-14 points.

| bucket | train keep cases | cause | fix it would need | change cases at risk |
| --- | --- | --- | --- | --- |
| essay length | 4 (h20, h31, h51, h54) | `linesGoverned` stops at the first blank line, so a file header or long doc comment is measured against one paragraph. The rule emits `trim` though none of the four argues a design. | Make the essay ratio an `uncertain: length` hint, not an action. Predicted train 0.717 -> 0.808. | none on train |
| into-code noise | 3 (h53, part of h25, h37) | The intoCode Noul fires at 0.71-0.80 on keep cases. Change cases h22 and h36 sit at 0.73-0.76. | A sharper intoCode question. No threshold separates them. | h22, h36 under any threshold move |
| duplicate | 2 (h03, h10) | The duplicate question carries no criteria. | Criteria, or a dedupe flag near 0.85, which frees only h10. | none at 0.85 |
| value floor | 2 (h16, h52) | A low-confidence value score removes on value alone. | A confidence gate on value-only removal. | l03 (confidence 0) |
| history, no markers | 1 (h37) | The history Noul reads 0.93 on a keep case. | A sharper question. | not assessed |
| alternative borderline | 1 rep (h11) | alternative sits exactly at 0.70 in one rep. | none | none |

Change-case margins: h22 (+0.05 intoCode) and h36 (+0.03 intoCode) are blocked
thinly, and l03 sits 0.05 below the value floor with confidence 0. The other
change cases clear their thresholds by 0.14 or more.
