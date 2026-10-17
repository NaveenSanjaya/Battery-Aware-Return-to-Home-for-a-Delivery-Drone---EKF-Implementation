# Plain-language summary of the report

This is a study aid, not part of the report. For each chapter written so far, it says in simple words what the chapter says and why it matters. It then gives a few questions an examiner might ask, with short answers.

Chapters 5 (after the simulator check), 6 and 7 are still skeletons. They will be added here when they are written.

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
- **Truth vs filter:** the simulated battery has **two** RC pairs, slightly different resistances and a 5 mV lower OCV curve. The EKF assumes **one** RC pair and nominal values. This is on purpose: real filters never have the perfect model.
- The slow second RC pair (τ = 400 s) makes the voltage drift lower over a flight. The filter cannot model this, so it is a real test.
- **Sensors:** measured current = true + bias (0.5 A) + noise (0.2 A). Measured voltage = true + noise (10 mV).
- **Mission:** take-off 30 A, cruise 15 A at 10 m/s, hover 20 A at each drop-off, landing 18 A, plus a small random wobble in the current.
- **EKF:** four hidden states: SoC, V1, bias b, capacity Cn. Current drives the prediction; voltage corrects it. Learning b and Cn as states lets the filter fix a biased sensor and an aged battery.
- **Q is derived, not guessed:** the current-sensor noise is pushed through the model with a vector G, giving Q = G·σ_I²·Gᵀ + small extra terms.
- **Return-home rule:** compute the margin m = SoC estimate − SoC needed to get home − 10% reserve. Turn the margin into a probability of a safe return with the bell curve. Go home when that probability falls below 95%. Four policies (A–D) will be compared, plus 8 experiments and a 500-flight Monte Carlo study.

**Why it matters:** this is the heart of the project. It defines exactly what the filter and the decision rule do, so the results can be checked against it.

**Examiner questions**

1. *Why make the simulated battery different from the filter's model?*
   A filter tested on its own model always looks perfect. A different "true" battery shows how the filter copes with a real-world model error.
2. *Why is capacity hard to estimate?*
   Capacity does not appear in the voltage equation (its entry in H is 0). The filter only learns it from how fast the SoC falls. Bias also changes that speed, so the filter needs current changes (take-off vs cruise) to tell them apart.
3. *What does the risk-aware rule do that "SoC minus trip cost" does not?*
   It uses the filter's uncertainty. With the same SoC estimate, an unsure filter gets a bigger safety buffer and turns back earlier. A confident filter flies longer.

---

## Chapter 4: Implementation

**What it says**

- The code is base MATLAB, split into small files that each do one job. Random seeds are fixed, so runs can be repeated exactly.
- `battery_params.m` holds every number in one place: what the filter believes, the true battery, and the sensor errors.
- `ocv_lookup.m` returns the OCV and its slope using a smooth (`pchip`) curve and a finite difference.
- `battery_true_step.m` is the true 2-RC battery. Each line matches one equation in Chapter 3.
- `read_sensors.m` adds bias and noise. `drone_step.m` is a small state machine (take-off, cruise, hover, return, landing).
- A policy can send the drone home just by setting its mode to `'return'`.
- The EKF, charge-counting, decision-rule and Monte Carlo sections are marked TODO. They will be filled in as the code is written.

**Why it matters:** it shows the equations really are what the code does. That is part of the "correctness" mark.

**Examiner questions**

1. *How do you know the code matches the equations?*
   Each code listing has the real file line numbers, and the text links each line to its equation number.
2. *Why split the battery and the drone into separate files?*
   Each file can be tested alone. A decision policy can change the drone's mode without touching the battery code.

---

## Chapter 5 (part written): Simulator verification

**What it says**

- One test flight on the short mission (3 drop-offs), with no filter, to check the simulator.
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

## Things to check before submitting (from the writer)

- Module name and code on the title page (it says EN3330 Introduction to Engineering Optimization, which may be from another template).
- The source of the OCV table: cite it, or say clearly it is a representative curve.
- Every `TODO` note in the bibliography (authors, years, titles). They print on purpose so you cannot miss them.
- The policy-A remark in Section 5.1 (the voltage dropping below 3.6 V while SoC is still above half). Confirm it from `day2_log.mat`.
