# BENCHMARK LAB: the five locked scenes

Every candidate video model runs the same five scenes before it is allowed on the router. Scores land in system.ai_models.scores. Same seed policy, same references, same prompt text. Boss picks winners by looking, the numbers break ties.

Reference inputs come from canon once Phase 02 locks faces: front and 3/4 references per character, wardrobe list, location plates.

## A. Uncle Cred in his office (single, hero, dialogue closeup)
9:16, 8 seconds, desk to camera. Uncle Cred leans in and says "Bro. Before you apply for that Charger, come here." Office: Financial District, warm lamp, file cabinet, a framed 30 day rule poster. Tests: identity, lip sync, wardrobe, prop stability.

## B. Cred and Auntie APR (two shot, dialogue)
9:16, 8 seconds, over the shoulder on APR, then reverse on Cred. APR holds a printed offer letter, reads "twenty nine percent of what?" Cred rubs his forehead. Tests: two identities in one scene, hand and paper stability, cut coverage rule (never two mouths in frame).

## C. Repo Reggie and the tow (action, motion, stakes)
9:16, 8 seconds, exterior, 3 a.m. Reggie runs out of a house toward a tow truck lifting his car, the tow beep sting on the audio. Tests: motion quality, body consistency under motion, environment, native audio.

## D. Four in frame (the stress test)
9:16, 8 seconds, the office. Cred at the desk, APR standing, Reggie in the doorway, Mr. Denied's stamp arm entering from off frame. Nobody speaks; a stamp lands. Tests: character count, no merging, prop correctness. Expected to fail on most models; the score tells the router when a four shot must be built from singles.

## E. Closeup emotion (Reggie, the approval)
9:16, 6 seconds, extreme closeup. Reggie reads an approval on his phone; face goes from braced to disbelief to a laugh. No dialogue. Tests: expression range on a stylized face, temporal identity, eyes.

## Scoring (0 to 1 each, stored per model per scene)
identity, wardrobe, anatomy, motion, lip_sync (A and B only), prompt_adherence, artifact_free, cost_usd, latency_s, boss_pick (1 or 0).

## Router rules that come out of this
- dialogue_closeup -> best A score with lip_sync >= 0.9
- two_shot -> best B score, always singles coverage
- action -> best C score
- establishing -> best of C and E on environment, cheapest that clears 0.85
- four_or_more -> never one generation; composite from singles unless D clears 0.9
