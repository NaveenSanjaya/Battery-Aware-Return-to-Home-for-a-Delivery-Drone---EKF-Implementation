# Plain-language summary of the report

This is a study aid, not part of the report. It starts with a one-page summary of the whole project. Then, for each chapter, it says in simple words what the chapter says and why it matters, followed by questions an examiner might ask, with short answers.

## One-page summary: the project in 10 bullets

1. **Problem.** A delivery drone must decide when to fly home, but it cannot measure its remaining charge (SoC). It only has a noisy, biased current sensor and a voltage that dips under load.
2. **Tool.** An Extended Kalman Filter (EKF) combines the two: current drives the prediction, voltage corrects it. It gives an SoC estimate *and* how sure it is (σ).
3. **Honest test.** The simulated "true" battery is deliberately different from the filter's model: two RC pairs instead of one, resistances off by 10%, and the OCV curve 5 mV lower.
4. **Key design finding.** The biggest error came from a wrong internal resistance R0, not from sensor bias. So the filter learns R0 during flight (stage B). On a normal flight this gave **0.97% SoC error vs 4.36% for charge counting**, and from a wrong start, 1.32% vs 13.85%.
5. **Why it works.** The current steps (take-off → cruise) let the filter tell "less charge" apart from "more resistance". At that moment its error band shrinks from ±8.5% to ±2.5%.
6. **Most accurate ≠ safest.** Stage B is the most accurate on a healthy battery, but on an old battery it is confidently wrong (+8.3% too optimistic). Stage C (which also learns bias and capacity) stayed honest in every test: the truth was inside its band 100% of the time, with 1.0–1.8% error. **Stage C makes the decision.**
7. **Go-home rule.** Turn back when P(land with the 10% reserve) < 95%. The trip cost uses the filter's own drain rate (current − bias)/capacity, plus a 10% trip allowance.
8. **Headline result (500 random missions).** D (risk-aware): **0% died, reserve broken 2.8%**. C (same filter, ignores σ): 38% broken. B (charge counting): **30.4% died** (58% with old batteries). A (voltage 3.5 V): 9.2% died.
9. **Calibrated.** At every threshold (80–99.9%), D broke its reserve no more often than it promised (e.g. 2.0% vs ≤5%). To be as safe, a voltage rule needs 3.55 V and wastes 3× more battery (17.9% vs 6.1%).
10. **Limits and next steps.** Simulation only, a representative OCV curve, no temperature, one route. If the model is very wrong (E6), no filter stays honest. Next: calibrate the bias at rest, estimate capacity between flights, try a 2-RC model, a UKF, and real flight logs.

---

## Abstract

- One paragraph (~200 words) at the start of the report with the problem, the method and the headline numbers: 0.97% vs 4.36% error, and 0% died / 2.8% reserve broken for D vs 38.0% for C and 30.4% died for B.
- It must agree with the Introduction's contributions and the Conclusion; all three use the same numbers.

---

## Chapter 1: Introduction

**What it says**

- A delivery drone must decide by itself when to stop delivering and fly home.
- It cannot measure how much charge is left (the SoC). It can only guess it from two imperfect sensors.
- The current sensor is noisy and slightly wrong (it has a bias). The voltage sensor is accurate, but the voltage drops whenever the motors work hard.
- If the drone turns back too late, it crashes. If it turns back too early, it wastes battery and does fewer deliveries.
- The best safety margin is not a fixed one. It should be small when we are sure about the SoC and big when we are not. So we need an estimator that also says how sure it is.
- A Kalman filter gives both a best guess and its uncertainty. The battery's voltage curve is bent, so we use the **Extended** Kalman Filter (EKF), which handles gently bent equations.
- The project builds a simulator, an EKF, a risk-aware return-home rule, and compares them with simpler methods.
- The filter also **learns the battery's internal resistance R0** during the flight. Testing showed that a wrong R0 was the biggest cause of SoC error (see Chapter 3).
- The filter that makes the go-home decision is chosen for **honest uncertainty**, not just accuracy (see Chapter 3).

**Why it matters:** it explains the problem and why an EKF is the right tool. This sets up everything else.

**Examiner questions**

1. *Why not just use a big fixed safety margin?*
   A big margin is safe but wastes battery on every flight. A margin that follows the filter's uncertainty is only big when it needs to be.
2. *Why an EKF and not a normal Kalman filter?*
   A normal KF needs straight-line equations. The voltage-vs-SoC curve is bent. The EKF uses the tangent line at the current guess, which works well because the curve is smooth.
3. *Why not a particle filter?*
   It would work, but it is much slower. For a smooth curve and bell-shaped noise, the EKF is good enough. EKFs are also the standard method in battery management systems (Plett, 2004).

---

## Chapter 2: Background

**What it says**

- **SoC** is the fuel gauge (0 to 1). **Capacity Cn** is the size of the tank in Ah. Old batteries have a smaller Cn.
- The **OCV curve** gives the resting voltage for each SoC. It is steep near empty (about 25 mV per 1% SoC) and flat in the middle (about 5 mV per 1%). Where it is flat, voltage tells us little about SoC.
- When current flows, the voltage drops instantly by R0 × I (**sag**), and also slowly by V1 (**polarisation**, an R1–C1 pair). So: V = OCV(SoC) − R0·I − V1.
- **Charge counting** subtracts the charge used. It is simple but drifts: a wrong start stays forever, a sensor bias adds up over time, and a wrong capacity makes it run out early.
- A **Kalman filter** repeats two steps every second: **predict** with the model (uncertainty grows), then **update** with the measurement (uncertainty shrinks). The difference between measured and expected voltage is the **innovation**.
- The **Kalman gain K** decides how much to trust the measurement. K is big when our guess is unsure, and small when the sensor is noisy or the curve is flat.
- **Q** says how much we distrust the model; **R** says how much we distrust the sensor. The **EKF** replaces bent equations with their tangent lines (the **Jacobians F and H**).
- A worked example (Day 1): one step moved the SoC from 78.89% to 74.63% and cut the uncertainty from 5% to 1.37%. In a 10-minute test, the EKF ended 0.12% off while charge counting was 4.01% off.

**Why it matters:** every idea here appears in the equations later. The worked example shows the filter actually doing its job with real numbers.

**Examiner questions**

1. *In your example K = 1.321. Isn't a gain above 1 wrong?*
   No. Here K turns volts into SoC, so it has units (SoC per volt). The number without units is K × H = 0.925. It means the filter moved 92.5% of the way towards what the voltage suggested.
2. *Why does the gain get smaller when the sensor is noisier?*
   S = H²P + R gets bigger when R is bigger, and K = PH/S. A noisy sensor deserves less trust, so the filter keeps more of its prediction (K fell from 1.321 to 0.470 with a 50 mV sensor).
3. *Why did charge counting end +4.01% off in the 10-minute test?*
   It started 5% too high and never corrected it. The 0.3 A bias over 600 s removed 1% from the estimate. 5% − 1% ≈ 4%.

---

## Chapter 3: Methodology

**What it says**

- **System:** a simulator makes the "true" battery and noisy sensor readings. The EKF and the simple methods see only the sensors. Only the simulator knows the truth, so it can score everyone exactly.
- **Truth vs filter:** the simulated battery has **two** RC pairs, slightly different resistances (R0 is 10% higher) and a 5 mV lower OCV curve. The EKF assumes **one** RC pair and nominal values. This is on purpose: real filters never have the perfect model.
- **The slow RC pair was made milder.** At first it was R2 = 4 mΩ. A quick calculation showed this would make the voltage about 63 mV lower than the filter expects at 15 A. That is a very harsh test. The default is now R2 = 1.5 mΩ (same 400 s time constant). The harsh 4 mΩ version is kept as stress test E6.
- **Sensors:** measured current = true + bias (0.5 A) + noise (0.2 A). Measured voltage = true + noise (10 mV).
- **The EKF state now has five slots:** SoC, V1, bias b, capacity Cn, and resistance R0. Current drives the prediction; voltage corrects it.
- **Three stages:** A learns SoC and V1. **B also learns R0** and is the most accurate on a healthy battery. **C learns all five** and is the one that will make the go-home decision. A state that a stage does not learn is "frozen": zero uncertainty and zero process noise, so the filter never changes it.
- **Why R0? (the investigation)** Stage A read the SoC about 2.5% too low and was overconfident: the truth was inside its ±3σ band only about 16% of the time. Turning on one mismatch at a time showed the cause. The 10% higher R0 was the worst (1.85% error alone). The battery sags more than the filter expects, so the filter thinks the SoC is lower. Making R bigger did not help (2.49%), and neither did the 10 mV model allowance on its own (2.48%), because a systematic error is not random noise. Learning R0 fixed it.
- **Why not bias and capacity?** In one 14-minute flight, the filter cannot tell them apart from R0. When the current is steady, a bias error and a resistance error change the voltage in the same way. Capacity only shows as slow SoC drift. Stage C is kept as an "observability study", and learning b and Cn over many flights is future work.
- **Measurement noise R has three parts:** sensor noise (10 mV), current noise through R0 (1.6 mV), and a **10 mV model-error allowance**. With 10 mV, the truth was inside the band 98% of the time (NIS about 0.5: a little too cautious, but honest). Honest bands matter because the return-home rule uses σ.
- **Q is derived, not guessed:** the current-sensor noise is pushed through the model with a vector G. The covariance update uses the **Joseph form**, which keeps P symmetric and positive.
- **Return-home rule (Day 5 final version):**
  - *Cost of getting home:* (cruise current − bias) × time home, plus (landing current − bias) × 40 s, all divided by the capacity. This uses the same "drain rate" the filter learned, (current − bias)/capacity, because Day 4 showed that is the part the filter gets right. The cruise current is learned during the flight from the sensor (a slow average), so it includes wind.
  - *Margin:* m = SoC estimate − cost of getting home − 10% reserve.
  - *Uncertainty:* the SoC σ from the EKF, plus a trip allowance of 10% of the trip cost (for wind and load surprises). Longer trip, more allowance.
  - *Probability:* P(safe) = bell-curve probability that the margin is above zero. **Go home when P(safe) < 95%.** That is the same as keeping a buffer of 1.645 σ.
- **What 95% promises:** if the σ is honest, the drone should break its reserve in no more than about 5% of missions. The Monte Carlo study checks this. That makes it a test of the whole chain (filter + cost + probability).
- **Four policies:** A = turn back when voltage < 3.5 V for 5 s; B = charge counting margin (rated 5 Ah, no bias correction, same resting-voltage start); C = EKF margin < 0 (ignores σ); D = P(safe) < 95%. Decisions are only checked while cruising or hovering. When a policy fires, the drone flies straight home.
- **Why 3.5 V for A?** A Python check: 3.4 V killed 92% of drones, 3.5 V 10%, 3.6 V none but wasted 27% of the battery. No single voltage works, because the right moment depends on how far from home you are.
- **Monte Carlo:** 500 missions on the long route (6 drops, too far for one battery). Each mission draws random start SoC (60–100%), bias (±1 A), wind (±20%), battery age (80–100%) and battery parameters (±15%). All four policies fly *the same* missions with *the same* noise. Scores: died, reserve broken, unused battery, deliveries. Then a threshold sweep: D at 80–99.9%, A at 3.40–3.60 V.
- **Choosing the decision filter (Python design check, 20 flights each).** On a healthy battery, B is the most accurate (about 1.1% error). But on an **aged battery** (only 85% capacity), B is confidently wrong: it thinks the battery is about 8% fuller than it is, and its band holds the truth only 27% of the time. That is the dangerous direction, because the drone would turn back too late. B blames the missing voltage on a higher R0 instead of a lower SoC. Stage C stayed honest (truth inside its band 100% of the time) in E1–E4, with 1.0–1.8% error. So **stage C will drive the go-home decision.** Lesson: *the most accurate filter is not always the safest one to make decisions with.*
- **Stage C's bias and capacity are individually wrong, but the SoC is right.** In the aged-battery test it guessed capacity 4.49 Ah (true 4.25) and bias −0.80 A (true +0.5). These errors cancel: what matters for SoC is the discharge rate (Im − b)/Cn, and that was only about 3% off. The voltage can check the rate, but not the two parts separately, within one flight.
- **Better starting guess:** from Day 4, the drone averages 10 resting voltage readings before take-off. This cuts the noise by about 3×, which fixes the "unlucky 3% low start" from Day 3.
- **Day 4 experiments planned:** E3 bigger bias (0.8 A), E4 aged battery, E5 tuning (Q and R made 100× bigger or smaller), E6 a much bigger slow RC pair, E7 uncertainty vs the flat part of the curve, E8 all stages over 20 random flights.
- These Python numbers are **design-stage checks**, not the final results. The final results come from the MATLAB runs.

**Why it matters:** this is the heart of the project. It defines exactly what the filter and the decision rule do. The investigation story (find the error, test fixes, keep the one that works) shows real engineering judgement, which earns "depth" and "creativity" marks.

**Examiner questions**

1. *Why make the simulated battery different from the filter's model?*
   A filter tested on its own model always looks perfect. A different "true" battery shows how the filter copes with a real-world model error.
2. *Why did a wrong R0 make the SoC estimate low?*
   The real battery sags more than expected. The only way the filter could explain a lower voltage was a lower OCV, which means a lower SoC. In the flat middle of the curve, 12 mV of extra sag looks like 2.4% less SoC.
3. *Why didn't increasing R fix it?*
   R is for random noise. The R0 error is the same every second, so the voltage always points to the wrong SoC. A bigger R only makes the filter move there more slowly.
4. *Why can't the filter learn the bias in one flight?*
   A bias error changes the voltage by R0 × δb, and a resistance error by −I × δR0. When the current is steady, these look the same, so the filter cannot tell which one is wrong. Only current changes separate them.
5. *Isn't adding a 10 mV allowance just cheating?*
   No. The model really is imperfect, and the allowance tells the filter so. Without it the band missed the truth more often (90% inside). With it, 98% inside, which is what the safety rule needs.
6. *Why not use stage B for the decision, since it is the most accurate?*
   Because on an aged battery it is confidently wrong, and wrong in the dangerous direction (it overestimates SoC). The go-home rule trusts the filter's σ, so an honest σ matters more than the last half-percent of accuracy.
7. *Stage C's bias estimate was wrong. How can its SoC be right?*
   The SoC only depends on the bias and capacity through the rate (Im − b)/Cn. Stage C got the rate nearly right, even though it split it wrongly between bias and capacity. Calibrating the bias at rest before take-off would fix the split.
8. *Why does the trip cost use (current − bias)/capacity and not just the capacity estimate?*
   Because the filter only gets that combination right; its capacity alone can be off (4.45 vs 4.25 Ah in E4). Using the same combination the filter uses keeps the cost consistent with what the voltage has checked.
9. *Why is policy D called "calibrated"?*
   Its threshold is a promise: at 95%, it should break the reserve in at most about 5% of missions. If the Monte Carlo shows that, the filter's σ and the trip allowance are honest. Policy C ignores σ and aims exactly at the reserve, so it should break it much more often.

---

## Chapter 4: Implementation

**What it says**

- The code is base MATLAB, split into small files that each do one job. Random seeds are fixed, so runs can be repeated exactly. Runs that are compared use the same seed, so they see the same noise.
- `battery_params.m` holds every number in one place: what the filter believes (including the 10 mV model allowance), the true battery, and the sensor errors.
- `ocv_lookup.m` gives the OCV and its slope. `soc_from_ocv.m` does the reverse: it turns the resting voltage before take-off into a starting SoC guess.
- `battery_true_step.m`, `read_sensors.m` and `drone_step.m` are the simulator. Each line matches an equation in Chapter 3.
- `ekf_init.m` sets the starting guess, the uncertainty and the stage. Freezing a state is just two lines: its starting σ and its q are set to zero.
- `ekf_step.m` is the filter: predict (lines 11–30), then compare and update (lines 32–50). Each line maps to an equation. The same code works for all stages with no `if` statements.
- `coulomb_count.m` is the one-line baseline. `run_flight.m` flies one full mission with truth, sensors, EKF and baseline together. `main_day3_ekf.m` runs E1 and E2 with stages A and B.
- `run_flight.m` now has options: `n_rest` (how many resting readings to average) and `q_scale`/`r_scale` (to turn the Q and R knobs in E5).
- `flight_metrics.m` turns one flight into numbers: error (RMSE, final, max), how often the truth was inside the band, NIS, and NEES on SoC (should be about 1).
- `main_day4_experiments.m` runs E3–E8. E8 alone is 300 flights (5 scenarios × 20 seeds × 3 stages). `ocv_lookup.m` now builds its curve once and reuses it, which is much faster but gives exactly the same numbers.
- `trip_soc.m` (cost to get home), `p_safe_return.m` (margin → probability with `erfc`) and `rth_policy.m` (the four rules, each a few lines). Policy A counts seconds below the threshold, so one noisy dip cannot send the drone home.
- `run_mission_rth.m` flies one long mission: 10 resting readings for the start, stage C EKF and charge counting always running, the cruise current learned while cruising, and the decision every second. `draw_conditions.m` draws one mission's random conditions. `main_day5_rth.m` runs the demo mission, the 500-mission Monte Carlo and the threshold sweep.

**Why it matters:** it shows the equations really are what the code does. That is part of the "correctness" mark.

**Examiner questions**

1. *How do you know the code matches the equations?*
   Each code listing has the real file line numbers, and the text links each line to its equation number.
2. *How does a "frozen" state stay frozen?*
   Its row and column in P start at zero and get no process noise, so they stay zero. Then its entry in the gain K is zero, and the update never moves it.
3. *Why does the EKF start from the resting voltage?*
   Before take-off no current flows, so the voltage equals the OCV. Reading the OCV curve backwards gives a good first SoC guess (about ±3%).

---

## Chapter 5: Results — simulator verification

**What it says**

- One test flight on the short mission (3 drop-offs), with no filter, to check the simulator. It used the first, harsher slow RC pair (R2 = 4 mΩ), which is now only used in stress test E6.
- The drone landed safely after 14.2 min and 6.89 km. The true SoC fell from 95% to 18.5%.
- The lowest voltage was 3.297 V, safely above the 3.0 V cut-off.
- The biggest sag was 367 mV at take-off (30 A). R0 alone explains 264 mV of it; the rest is polarisation building up.
- The voltage steps **up** when take-off ends (less current) and **down** at each hover (more current), as the circuit predicts.
- The gap between OCV and terminal voltage slowly widens. This is the slow RC pair that only the true battery has, the planned model mismatch.
- Charge counting with the biased sensor ended 2.3% low. Theory predicts about 2.4% (0.5 A for 14.2 min), so it matches.
- The distance and time also match the route: the straight legs add up to 6.89 km, and the phase times add up to about 14.2 min.

**Why it matters:** if the simulator were wrong, every later result would be wrong too. This check shows it behaves like a real battery and drone.

**Examiner questions**

1. *Why is charge counting negative (too low)?*
   The sensor reads 0.5 A too high, so the counter thinks more charge was used than really was.
2. *Why does the voltage gap keep growing during cruise?*
   The slow RC pair (τ = 400 s) keeps charging for most of the flight. The filter does not have this pair, so it will have to cope with the extra drop.
3. *Is one run enough to prove anything?*
   It is enough to check that the simulator behaves sensibly. It does not give statistics. The 500-flight Monte Carlo study will do that.

---

## Chapter 5: Results — E1 and E2, the first EKF results

**What it says**

- Real MATLAB runs on the short mission, comparing charge counting, EKF stage A (SoC, V1) and **stage B** (also learns R0). All see exactly the same noisy sensors.
- **E1 (normal flight, true 95%):** the starting guess from the resting voltage was about 3% low (92%), because one noisy voltage reading near full charge is worth about 1% SoC per 10 mV.
  - Charge counting kept that error and added bias drift: **−5.5%** at landing (RMSE 4.36%).
  - Stage A drifted low to **−3.9%** and its band held the truth only 17% of the time: biased and overconfident, as predicted.
  - Stage B: RMSE **0.97%**, final −1.5%, truth inside its band **100%** of the time. Its R0 estimate ended at 8.85 mΩ (true 8.8, start 8.0).
- **The big moment is at 0.5 min**, when take-off ends and the current drops from 30 A to 15 A. Stage B's error jumps from −3% to +1%, its band shrinks from ±8.5% to ±2.5%, and R0 jumps to the right value. Before that, with a steady current, the filter could not tell "lower SoC" from "higher resistance". The current change is what separates them.
- **Innovations** look like random noise inside their expected size, so the filter is healthy. Mean NIS is 0.51, slightly below 1, because of the deliberate 10 mV safety allowance.
- **E2 (true 85%, everyone assumes 100%):** charge counting stayed about 13–15% too high. At landing the battery was really at about 9% (below the 10% reserve), but charge counting thought about 21%. Stage B sat 5–7% high during take-off, then snapped to the truth at the current step (error below 2% after 42 s) and ended at −0.4%.
- Stage B still ends E1 1.5% low. This is probably the slow RC pair the filter does not know about, but the error stays inside its band, so it is honest about it.
- The MATLAB numbers match the earlier Python checks in pattern (stage B about 1% RMSE in both).

**Why it matters:** this is the first proof that the EKF works. Learning R0 cut the error to about a quarter of charge counting's, and the uncertainty band is honest. E2 shows why the drone needs this: with charge counting, it would think it had a fifth of its battery left when it was nearly empty.

**Examiner questions**

1. *Why does stage B's error jump at 0.5 min?*
   During take-off the current is constant, so a low voltage could mean "less charge" or "more resistance", and the filter can't tell which. When the current halves, the resistance part of the voltage halves but the OCV part doesn't. That difference reveals R0, and then the SoC falls into place.
2. *Why is the mean NIS below 1? Isn't that a problem?*
   NIS below 1 means the filter is a bit more cautious than needed. That is on purpose: we added a 10 mV allowance for model error so the bands stay honest (100% of the time inside here). For a safety decision, a slightly too-wide band is much better than a too-narrow one.
3. *Stage A's NIS was also fine (0.54), yet it was wrong. How?*
   NIS only checks whether the voltage is explained. Stage A explains the voltage perfectly, but with the wrong SoC. Only comparing with the true SoC (possible in simulation) shows the error.

---

## Chapter 5: Results — E3 to E8, stress tests

**What it says**

- From Day 4 the drone averages 10 resting readings before take-off, so the starting guess is better. Single runs use seed 2. E8 repeats everything over 20 random flights.
- **E3 (sensor bias 0.8 A):** charge counting drifts to −4.8%. Both EKF stages stay within about 2.5%. Stage C's bias guess only got to about +0.5 A (true +0.8; ended +0.33), but it *knew* it was unsure (wide band). Stage B was a bit overconfident (88% inside).
- **E4 (old battery, 85% capacity) is the key result.** The battery really landed at 9.9%, below the reserve. Charge counting thought 20.1%. **Stage B also failed:** it thought the battery was 8.5% fuller than it was, and its band held the truth only 28% of the time. **Stage C was right** (error +0.2%, 100% inside its band).
- **How stage C did it:** its capacity guess fell from 5.0 to 4.45 Ah (true 4.25), and its bias guess was −0.42 A (true +0.5, wrong sign!). These two errors cancel. The SoC only depends on the rate (current − bias) / capacity, and stage C got that rate right to within about 1.5%.
- **E5 (tuning):** making R 100× smaller made the filter believe every voltage wiggle. It swung to −13% during take-off and its NIS was 32, which clearly flags the problem. Making R 100× bigger made the band far too wide. Making Q 100× smaller was slightly more accurate but less honest (94% inside). We kept the chosen tuning.
- **E6 (much bigger hidden slow RC pair):** every filter got worse, and none stayed honest. Stage B was only as good as charge counting. This is the honest limit: if the model is too wrong, the voltage misleads the filter.
- **E7 (flat part of the curve):** stage C's uncertainty grows from 1.5% to 2.2% as the curve flattens. It even dips briefly at 65–70% SoC, exactly where the curve has a small steep bump. So the uncertainty really follows the curve's slope. Stage B's uncertainty shrinks instead, because it keeps learning R0.
- **E8 (20 flights each):** stage C is the **only filter honest in all of E1–E4** (100% inside), with 1.0–1.8% error. Stage B is the most accurate on a healthy battery (1.03%) but fails on the old one. **So stage C will make the go-home decision.**

**Why it matters:** this is the evidence for the project's main design choice. A filter that is very accurate but sometimes confidently wrong is dangerous for a safety decision. Stage C is a little less accurate on a good battery, but you can trust its uncertainty.

**Examiner questions**

1. *Stage C got the bias wrong, even the sign. Why should we trust it?*
   Because we trust it for the SoC, not the bias. The voltage only checks the rate (current − bias)/capacity, and stage C got that right. It also says honestly that it is unsure about the bias (wide band). Calibrating the bias at rest before take-off would fix the split.
2. *Why did stage B fail on the old battery?*
   The voltage dropped faster than expected. Stage B could explain that either with a lower SoC or a higher resistance, and it chose higher resistance. So its SoC stayed too high, and it was confident about it.
3. *In E6 charge counting beat some filters. Doesn't that show the EKF is useless?*
   No. It shows the EKF's limit: it is only as good as its model. When the model is far off, the voltage pushes it the wrong way. In the other scenarios (wrong start, old battery) charge counting was far worse (13.8% and 6.2% error). Fixes for E6 would be a 2-RC filter model or adaptive noise.

---

## Chapter 5: Results — the go-home decision

**What it says**

- **Demo mission** (hard conditions: old battery, sensor reading 0.5 A low, headwind):
  - D turned back first (5.9 min) and landed with 17.8%.
  - A and C turned back at 6.4 min, while hovering at drop-off 2, and landed just above the 10% reserve (11.7% and 11.9%).
  - B trusted charge counting, which was 7–12% too optimistic. It tried a second delivery, turned back too late and **died 200 m from home**.
- **Monte Carlo, 500 random missions, all four policies on exactly the same missions:**
  - **D (risk-aware):** 0% died, reserve broken in only **2.8%** (it promised at most 5%), 6.1% battery left over, 1.16 deliveries.
  - **C (EKF, ignores σ):** 0% died, but reserve broken in **38%**. Same filter as D!
  - **B (charge counting):** **30% died** (58% with old batteries), reserve broken in 90%. Most deliveries (1.56), but only because it was reckless.
  - **A (voltage 3.5 V):** 9% died, reserve broken in 32%, *and* it wasted 8% of the battery.
- The EKF itself (stage C) had 1.3% error over these 500 missions, against 3.4% for charge counting, and the truth was inside its band 100% of the time.
- **Threshold sweep:** D kept its promise at every setting (80% → 9.5% broken, promise ≤20%; 95% → 2.0%, promise ≤5%; 99% → 0%). For A to be as safe as D, it needs 3.55 V, which wastes 17.9% of the battery (3× D) and does about half the deliveries. No voltage setting beats D.
- **Price of safety:** going from 90% to 99% costs about 3 points of battery and 0.07 deliveries per mission. The operator can pick; 95% is a good default.

**Why it matters:** this is the headline result. Same filter, but using its uncertainty (D) instead of ignoring it (C) cuts reserve breaches from 38% to 2.8%. That is the creative part of the project.

**Examiner questions**

1. *Why does C break the reserve ~40% of the time if its estimate is accurate?*
   Because it aims exactly at the reserve. Even a good estimate is sometimes a little high, and then the drone lands a little below 10%. If errors go up and down equally, that happens about half the time. D aims above the reserve by 1.645 σ, so it rarely falls below.
2. *What does "calibrated" mean?*
   That the probability means what it says. D promised "at most 5% of missions break the reserve" at 95%, and it was 2.8% (and within the promise at every threshold). So you can trust its numbers. It is slightly on the safe side, like the Day 4 NIS ≈ 0.5.
3. *Why not just pick a higher voltage threshold for A?*
   A higher voltage is safer but wastes battery, because voltage doesn't know how far home is. At 3.55 V, A is about as safe as D but wastes 3× more battery and does half the deliveries.

---

## Chapter 6: Discussion

**What it says (all sections)**

- **Why the EKF works:** the voltage gives an independent check every second, and the gain decides how much to trust it. With a perfect model the error was only 0.12%, so the tangent-line approximation is fine. The remaining errors come from model mismatch.
- **OCV slope and uncertainty:** where the curve is flat, the voltage says less, so stage C's σ grows (1.5% → 2.2%). That is where turn-back decisions happen, so the go-home buffer grows there too.
- **Observability:** R0 needs current *changes* to be learned (the take-off step). Bias and capacity can't be separated within one flight; only the drain rate (current − bias)/capacity can be learned. An unlearned bias does little harm because the voltage keeps correcting it.
- **Model mismatch:** a systematic error is not random noise, so making R bigger doesn't fix it; learning the cause (R0) does. Stage A had a normal-looking NIS (≈0.5) but NEES 83–404: you can't see this failure from the innovations alone. With a very wrong model (E6), no filter stays honest.
- **Tuning (E5):** NIS catches a wrongly set R (NIS = 32), but not a biased model. A slightly more accurate tuning (Q×0.01) was less honest, so the safer one was kept.
- **Choosing the filter** and **value of uncertainty:** see the bullets below.
- **Limitations:** simulation only, representative OCV curve, no temperature or hysteresis, Gaussian assumption, straight path and constant cruise current home, the landing-phase P(safe) artefact, one route.
- **Future work:** bias calibration at rest, capacity between flights, 2-RC filter, adaptive noise, UKF/PF comparison, real CMU flight logs.

**Choosing the filter and the value of uncertainty (details)**

- **Most accurate ≠ safest.** Stage B is the most accurate on a good battery, but on an old battery it is confidently wrong and too optimistic. Stage C is a bit less accurate but always honest, so it drives the decision.
- Stage C gets the SoC right even when its bias and capacity guesses are wrong, because the voltage only checks the drain rate (current − bias)/capacity, and it gets that rate right.
- **C vs D is the cleanest test:** same filter, same everything, only D uses σ. Breaches: 38% vs 2.8%. Using the uncertainty is what makes the decision safe.
- **Calibration** tests the whole chain (filter σ, trip cost, trip allowance, bell-curve assumption). D kept every promise, with room to spare.
- B fails because nothing in charge counting notices it is wrong. A fails because the right voltage depends on the distance home.
- The threshold sweep gives the operator a clear price list for safety.

**Examiner questions**

1. *Why is a slightly conservative filter acceptable?*
   For a safety decision, a promise kept with room to spare is better than one that is broken. The cost here is a few percent of battery.
2. *Could you make stage C more accurate?*
   Yes: measure the sensor bias at rest before take-off (the current is known to be zero), and estimate capacity between flights. Then bias and capacity could be learned separately.
3. *Why didn't a UKF get used, if Dibbern et al. found it more accurate?*
   Because here the errors came from model mismatch, not from linearisation (the perfect-model test gave 0.12% error). A UKF uses the same model, so it would not fix those errors. Comparing them is listed as future work.

---

## Chapter 7: Conclusion

**What it says**

- Simulator: realistic (367 mV take-off sag; charge-counting drift matched theory).
- EKF: learning R0 cut the error to 0.97% (vs 4.36% charge counting); from a wrong start 1.32% (vs 13.85%). Stage C was the only filter honest in all of E1–E4 (1.03–1.80% error).
- Go-home rule: in the demo it landed with 17.8% while charge counting led to a crash 200 m from home.
- Monte Carlo: D 0% died, 2.8% reserve broken; C 38%; B 30.4% died; A 9.2% died. Estimator 1.31% vs 3.35% error. D's promise held at every threshold.
- Main message: the uncertainty is as valuable as the estimate, if it is honest.

**Examiner question**

1. *What is the single most important result?*
   With the same filter, using its uncertainty (policy D) instead of ignoring it (policy C) cut reserve breaches from 38% to 2.8%, with no crashes, and the 95% promise was kept.

---

## Things to check before submitting (from the writer)

- Module name and code on the title page (it says EN3330 Introduction to Engineering Optimization, which may be from another template). This is the only TODO left in the LaTeX.
- Compile with pdfLaTeX + BibTeX (pdflatex, bibtex, pdflatex, pdflatex) and look through the PDF once: tables near the page width, figure placement, and that the appendix shows the code (it reads the files from `../drone_battery_ekf`).
- Read the report once yourself, especially the Discussion and Conclusion, so you can explain every claim in your own words.
