# Battery-Aware Return-to-Home for a Delivery Drone — Project Guide

Last updated: 15 Oct 2026 · Live version: [Claude Docs](https://claude.ai/code/artifact/c45639fc-8cf5-4dd3-bf44-5ddc61a9f7c9)

## Contents

1. [The big picture](#1-the-big-picture)
2. [Battery basics you need](#2-battery-basics-you-need)
3. [How a Kalman filter thinks, and what "Extended" adds](#3-how-a-kalman-filter-thinks-and-what-extended-adds)
4. [Our model: what the filter tracks](#4-our-model-what-the-filter-tracks)
5. [The EKF for our battery, step by step](#5-the-ekf-for-our-battery-step-by-step)
6. [The return-to-home decision](#6-the-return-to-home-decision-our-creative-part)
7. [Experiments we will run](#7-experiments-we-will-run)
8. [MATLAB project structure](#8-matlab-project-structure)
9. [Figures the report will contain](#9-figures-the-report-will-contain)
10. [Report structure, mapped to the marking criteria](#10-report-structure-mapped-to-the-marking-criteria)
11. [Seven-day plan](#11-seven-day-plan)
12. [Glossary](#12-glossary)
13. [References and data sources](#13-references-and-data-sources)

## 1. The big picture

We are building a "battery brain" for a delivery drone. It estimates how much charge is left, how sure it is about that number, and uses both to decide when to fly home.

### The story

A drone flies a long multi-drop delivery route. It must turn back before the battery runs out, but nobody can measure the remaining charge directly.

- Turn back **too late** and the drone falls out of the sky.
- Turn back **too early** and you waste range and deliveries.

The drone has only two clues. A **current sensor** is noisy and slightly wrong. A **voltage sensor** is honest, but the voltage dips whenever the motors work hard. Our filter combines both clues into one best guess.

### The question we answer, every second of the flight

1. How much charge is left? (the estimate)
2. How sure are we? (the uncertainty)
3. Is it time to go home? (the decision)

### What we build

| Part | What it is | Why we need it |
| --- | --- | --- |
| Simulator | A pretend drone and battery in MATLAB that produce "true" values and noisy sensor readings | We know the truth, so we can measure the filter's errors exactly |
| EKF | The filter that estimates charge and its uncertainty from the noisy sensors | The core of the assignment |
| Decision rule | Turns estimate + uncertainty into "continue" or "return home" | Our creative contribution (criterion 5) |
| Baselines | Simpler methods the drone could use instead: charge counting and a voltage threshold | Proves the EKF is worth it (criterion 4) |

![System overview](figures/fig1_system_overview.png)

The simulator knows the truth, so it can score every policy. The EKF and the baselines see only the noisy sensors, just like a real drone.

### Why an EKF, and not a KF or PF

- A plain **KF** needs straight-line (linear) equations. The battery's voltage-vs-charge curve is bent, so a KF cannot use the voltage properly.
- An **EKF** handles gently curved equations by using the tangent line at the current guess. Our curve is smooth and gently bent, which is the EKF's sweet spot.
- A **PF** would also work, but it is slower and unnecessary when the curve is smooth and the noise is roughly bell-shaped. EKF-based estimators are the classic approach in battery management systems (Plett, 2004), which supports criterion 4.

### What you hand in at the end

- MATLAB code: about 10 short files
- About 12 figures
- A report with introduction, methodology, implementation, results, discussion and conclusion

## 2. Battery basics you need

You need six battery ideas, and each one appears directly in our equations. All numbers below are illustrative starting values; we fix the final ones on Day 2.

### State of Charge (SoC)

SoC is the fuel gauge: 100% is full, 0% is empty. No sensor can measure it directly, so it must be estimated. That is why we need a filter.

### Capacity (Cn)

Capacity is the size of the tank, in amp-hours (Ah). A 5 Ah battery supplies 5 A for one hour, or 20 A for 15 minutes. Capacity shrinks with age: an old battery may hold only 80% of its label value.

### Open-circuit voltage (OCV) curve

When a battery rests with no current, its voltage depends only on its SoC. The OCV curve maps SoC to that resting voltage. It is a bent curve, not a straight line, and that bend is the reason we need an EKF.

![OCV curve](figures/fig2_ocv_curve.png)

*Illustrative typical Li-ion values (approximate); the final table comes from published data on Day 2.*

The dashed tangent hugs the curve near 40% and drifts away far from it. The EKF only needs the tangent near its current guess, which is why the trick works well for batteries.

The curve is steep near empty and flatter in the middle. Where it is flat, a small voltage error means a big SoC error, so voltage is a weaker clue there. Our filter will show this as growing uncertainty.

### Internal resistance (R0) and voltage sag

A battery behaves as if it has a small resistor inside. When current flows, the voltage drops instantly by current × R0. At 30 A with R0 = 8 mΩ, that is 0.24 V per cell.

This "sag" fools simple voltage gauges. During takeoff the battery looks emptier than it really is.

### Polarisation (the R1-C1 pair)

On top of the instant drop, a slower extra drop builds up over tens of seconds of heavy load. It fades again when the load eases. We model it with a resistor R1 and capacitor C1 in parallel, and call its voltage V1. Nobody measures V1, so the filter must estimate it too.

### The equivalent circuit

Put together, the battery acts like an OCV source in series with R0 and the R1-C1 pair. The voltage the sensor sees is:

$$
V_{\text{terminal}} = \mathrm{OCV}(\mathrm{SoC}) - R_0\, I - V_1
$$

![Equivalent circuit](figures/fig3_equivalent_circuit.png)

Only V is measured. The filter has to work out SoC and V1 from it, given the current.

### Charge counting (Coulomb counting), and why it drifts

The obvious way to track SoC is to start from a known value and subtract the charge drawn. Each step, SoC drops by I × Δt / (3600 × Cn). It is simple, but it has three weaknesses:

- **Wrong start:** if the battery was not full at takeoff, the error stays forever.
- **Sensor bias:** a small constant current error adds up. A 0.5 A bias over 15 minutes is 0.125 Ah, which is 2.5% of a 5 Ah battery.
- **Wrong capacity:** an aged battery empties faster than the counter thinks.

The EKF fixes all three by using voltage as a second clue. Charge counting becomes one of our baselines.

## 3. How a Kalman filter thinks, and what "Extended" adds

A Kalman filter mixes a prediction with a measurement, weighted by how much it trusts each. The EKF does the same thing when the equations are curved.

### An everyday picture

You walk through a dark room counting your steps. Each step adds a little error, so your sense of position slowly drifts. Now and then you touch a wall you know, and you correct yourself.

If your step counting is sloppy, you trust the wall more. If the wall touch is vague, you trust your counting more. That balance is the whole idea of a Kalman filter.

In our drone, **counting charge = counting steps**, and **reading the voltage = touching the wall**.

### The two-step loop, once every second

1. **Predict.** Push the estimate forward with the model: "I drew 20 A for 1 s, so SoC fell by this much." Uncertainty grows, because the model and the current sensor are imperfect.
2. **Update.** Compare the measured voltage with the voltage the model expected. The difference is the **innovation**, the filter's "surprise". Nudge the estimate to explain the surprise; uncertainty shrinks.

![EKF loop](figures/fig4_ekf_loop.png)

Current drives the prediction and voltage drives the correction. The loop then repeats with the new estimate.

### Uncertainty: the covariance P

The filter holds a guess and also how unsure it is, for example SoC = 62% ± 2%. With several quantities, this becomes a matrix P. Its diagonal holds each quantity's variance; the off-diagonal numbers say how their errors are linked.

We will plot ±3σ bands around the estimate. If the filter is honest, the true value stays inside the band about 99.7% of the time.

### The Kalman gain K: the trust balance

K decides how far the estimate moves toward what the measurement suggests.

| Situation | K | What the filter does |
| --- | --- | --- |
| Prediction very uncertain (P large) | Large | Follows the measurement |
| Sensor very noisy | Small | Keeps its prediction |
| Measurement tells little about the state (flat OCV) | Small | Barely changes SoC |

### The two tuning knobs: Q and R

- **Q (process noise)** says how much you distrust the model each step. Large Q makes the filter react fast but jumpy.
- **R (measurement noise)** says how much you distrust the sensor. Large R makes the filter smooth but slow.

Tuning means finding the balance. We will turn each knob on purpose and watch what happens.

A note on letters: Q and R always mean these two filter knobs in this guide. Battery capacity is written **Cn**, and the resistors are **R0** and **R1**.

### What "Extended" adds: the tangent-line trick

A plain KF needs straight-line equations; only then does the bell-shaped uncertainty stay bell-shaped. Our voltage equation contains OCV(SoC), a bent curve.

The EKF's trick: at every step, replace the curve with its **tangent line** at the current guess. The slope of that line, dOCV/dSoC, goes into a matrix called the **Jacobian**. After that, the ordinary KF formulas apply.

This works well when the curve is smooth and the uncertainty is small, which is our case. It works badly with sharp bends or huge uncertainty; there a particle filter or an unscented KF does better. That contrast is a good discussion point for the report.

### The full EKF recipe

This is what the code will do every second:

$$
\begin{aligned}
&\textbf{Predict:} && \hat{x}^-_k = f(\hat{x}_{k-1}, u_k) \qquad P^-_k = F_k P_{k-1} F_k^{\top} + Q \\
&\textbf{Update:} && \tilde{y}_k = z_k - h(\hat{x}^-_k, u_k) \qquad S_k = H_k P^-_k H_k^{\top} + R \\
& && K_k = P^-_k H_k^{\top} S_k^{-1} \qquad \hat{x}_k = \hat{x}^-_k + K_k \tilde{y}_k \qquad P_k = (I - K_k H_k) P^-_k
\end{aligned}
$$

| Symbol | Meaning in our project |
| --- | --- |
| x̂ | The estimate of the hidden quantities (SoC and friends) |
| ⁻ (superscript minus) | "Before the measurement", i.e. after predict only |
| u | Input: the measured current |
| z | Measurement: the measured voltage |
| f, h | Process model (how things change) and measurement model (what the sensor sees) |
| F, H | Jacobians: the tangent-line slopes of f and h |
| ỹ | Innovation: measured minus expected voltage |
| S | How big the innovation is expected to be |
| K | Kalman gain |

## 4. Our model: what the filter tracks

The filter tracks four hidden numbers. One input drives it (measured current) and one measurement checks it (voltage). We build it up in three stages so each step stays easy to follow.

### Assumed setup

- A delivery drone with a 6-cell (6S) lithium pack of 5 Ah. We model one cell; pack voltage = 6 × cell voltage.
- Current profile: takeoff about 30 A, cruise about 15 A, hover at each drop-off about 20 A, landing about 18 A.
- The filter runs once per second (Δt = 1 s).
- Starting cell values: Cn = 5 Ah, R0 = 8 mΩ, R1 = 6 mΩ, C1 = 5000 F (so the RC time constant R1 × C1 = 30 s).

All of these are illustrative and get fixed on Day 2 from published data.

### The four states

| State | Symbol | Unit | Why it is there |
| --- | --- | --- | --- |
| State of charge | SoC | fraction, 0 to 1 | The thing we actually want |
| Polarisation voltage | V1 | V | Needed to explain the measured voltage correctly |
| Current-sensor bias | b | A | Lets the filter learn and remove the sensor's constant error |
| Capacity | Cn | Ah | Handles an aged battery and makes the prediction step truly nonlinear |

- **Input:** measured current Iₘ = true current + bias + noise.
- **Measurement:** terminal voltage V of one cell.

### The equations

$$
\begin{aligned}
\text{SoC}_{k+1} &= \text{SoC}_k - \frac{(I_{m,k} - b_k)\,\Delta t}{3600\, C_{n,k}} \\
V_{1,k+1} &= a\, V_{1,k} + R_1 (1 - a)(I_{m,k} - b_k), \qquad a = e^{-\Delta t / (R_1 C_1)} \\
b_{k+1} &= b_k + \text{(small random wander)} \\
C_{n,k+1} &= C_{n,k} + \text{(small random wander)} \\[4pt]
V_k &= \text{OCV}(\text{SoC}_k) - V_{1,k} - R_0 (I_{m,k} - b_k) + \text{noise}
\end{aligned}
$$

In plain words:

1. **SoC line:** charge counting, but with the corrected current (Iₘ − b) and the estimated capacity.
2. **V1 line:** the slow voltage drifts toward R1 × I. The factor a (about 0.967 here) is how much of the old value survives each second.
3. **Bias and capacity lines:** "these stay the same, apart from slow random wander". This is how a filter learns a constant it does not know.
4. **Voltage line:** the circuit equation from section 2. This is the only thing we compare against a sensor.

The nonlinear parts are OCV(SoC), a bent curve in the measurement, and (Iₘ − b) / Cn, a division by a state in the prediction.

### Build-up in three stages

| Stage | States | What you learn |
| --- | --- | --- |
| A | SoC, V1 | The basic EKF loop; only the measurement is nonlinear |
| B | + bias b | State augmentation: learning a hidden constant |
| C | + capacity Cn | A full EKF with a nonlinear prediction, plus observability limits |

Stage C has an honest catch. Bias and capacity both change how fast SoC falls: bias shifts it, capacity scales it. Only changes in current (takeoff vs cruise) let the filter tell them apart, so capacity may converge slowly within one 15-minute flight. If that happens, it is a finding to explain, not a failure.

### The simulator's battery is deliberately different from the filter's

A filter tested against its own model always looks perfect, and real filters never have the exact model. So the "true" battery in the simulator is built differently:

| Aspect | Simulator (truth) | Filter (what it assumes) |
| --- | --- | --- |
| Circuit | Two RC pairs | One RC pair |
| R0, R1, C1 | Each off by up to ±15% | Nominal values |
| OCV curve | Shifted by a few millivolts | Nominal table |
| Current sensor | Bias between −1 and +1 A, noise about 0.2 A | Estimates the bias |
| Voltage sensor | Noise about 10 mV per cell | R set from this noise |

This makes the results believable (criterion 1) and gives you real material for the discussion (criterion 3).

## 5. The EKF for our battery, step by step

For our battery, the whole EKF is two small Jacobian matrices plus the recipe from section 3. This section is everything you need to code it.

### Step 0: start values

- **State guess:** x̂₀ = [SoC, V1, b, Cn] = [1.0, 0, 0, 5.0]. In normal use the starting SoC comes from the resting voltage before takeoff; in the stress test we deliberately assume "full".
- **Starting uncertainty (1σ):** SoC ±20%, V1 ±10 mV, bias ±1 A, capacity ±0.5 Ah. P₀ is a diagonal matrix of these values squared.

### Step 1: predict

Apply the four process equations from section 4. Then build F by differentiating each equation with respect to each state:

$$
F_k = \begin{bmatrix}
1 & 0 & \dfrac{\Delta t}{3600\, C_n} & \dfrac{(I_m - b)\,\Delta t}{3600\, C_n^2} \\[6pt]
0 & a & -R_1(1-a) & 0 \\
0 & 0 & 1 & 0 \\
0 & 0 & 0 & 1
\end{bmatrix}
$$

Each entry has a plain meaning. Top row, third column: if the bias estimate is 1 A too high, the predicted SoC falls slightly too slowly. Top row, last column: a bigger capacity means SoC falls more slowly.

**Process noise Q has two sources.** The current sensor's noise enters through the input, so we push it through the model. Model error and the slow wander of b and Cn add small diagonal terms:

$$
Q = G\,\sigma_I^2\,G^{\top} + \mathrm{diag}(q_{\text{SoC}},\, q_{V_1},\, q_b,\, q_{C_n}), \qquad G = \begin{bmatrix} -\dfrac{\Delta t}{3600\, C_n} & R_1(1-a) & 0 & 0 \end{bmatrix}^{\top}
$$

This derivation of Q is a strong point for the report: most student projects just guess Q.

### Step 2: update

Compute the voltage the filter expects, h(x̂⁻) = OCV(SoC⁻) − V1⁻ − R0 (Iₘ − b⁻), and its Jacobian:

$$
H_k = \begin{bmatrix} \dfrac{d\,\mathrm{OCV}}{d\,\mathrm{SoC}} & -1 & R_0 & 0 \end{bmatrix}
$$

- **dOCV/dSoC** is the tangent slope of the OCV curve at the current guess, read from the table by finite differences.
- **+R0 for bias:** a higher bias means less true current, so less sag and a higher voltage.
- **0 for capacity:** capacity never shows up in the voltage directly. The filter learns it only from how SoC evolves, which is why it learns slowly.

We measure one voltage, so S is a single number and K = P⁻Hᵀ / S. No matrix inverse is needed.

### Safeguards that trip up beginners

- Clamp SoC to [0, 1] and keep Cn positive after each update.
- Keep P symmetric: P = (P + Pᵀ) / 2 after each update, or use the Joseph form.
- At the ends of the OCV table, use a one-sided slope.
- Keep SoC as a fraction inside the equations; convert to % only for plots. Time is in seconds and capacity in Ah, hence the 3600.

### Starting tuning values

| Knob | Start value | Meaning |
| --- | --- | --- |
| σ_I | 0.2 A | Current sensor noise |
| q_SoC | 1e-8 per step | Small model error in SoC |
| q_V1 | 1e-6 V² per step | Small model error in V1 |
| q_b | 1e-6 A² per step | Lets the bias wander slowly |
| q_Cn | 1e-7 Ah² per step | Capacity is almost constant |
| R | 1e-4 V² | Voltage noise of 10 mV |

These are only starting points; we adjust them on Day 4.

### How we check that the filter is honest

- **±3σ bands:** the true error should stay inside about 99.7% of the time.
- **Innovations:** should look like random noise around zero, with no trend.
- **NIS** (innovation² / S): should average about 1. Much bigger means the filter is overconfident; much smaller means it is too cautious.
- **NEES:** the state error weighted by P⁻¹ should average about 4, the number of states. We can compute it only in simulation, where the truth is known.

## 6. The return-to-home decision (our creative part)

Every second, the drone computes the probability that it can still get home with a safety reserve. When that probability drops below 95%, it turns back.

### What getting home costs

- **Time home:** distance home (from GPS) ÷ cruise speed, plus about 60 s to land.
- **Charge needed:** cruise current × time home ÷ (3600 × estimated capacity), as a fraction of SoC.
- **Reserve:** we always keep 10% SoC for landing safety.

Example: 3 km from home at 10 m/s is 300 s, plus 60 s to land, so 360 s. At 15 A that uses 1.5 Ah, or 30% of a 5 Ah battery.

### From margin to probability

$$
\begin{aligned}
m &= \widehat{\text{SoC}} - \Delta\text{SoC}_{\text{home}} - \text{SoC}_{\text{reserve}} \\
\sigma_{\text{total}} &= \sqrt{\sigma_{\text{SoC}}^2 + \sigma_{\text{trip}}^2} \\
P(\text{safe}) &= \Phi\!\left(\frac{m}{\sigma_{\text{total}}}\right), \qquad \text{return home when } P(\text{safe}) < 0.95
\end{aligned}
$$

- **σ_SoC** comes straight from the EKF's P matrix. This is where the filter's uncertainty earns its keep.
- **σ_trip** covers wind and other trip surprises.
- **Φ** is the standard bell-curve probability. In base MATLAB, Φ(z) = 0.5 × erfc(−z / √2).

In plain words, the rule keeps a safety buffer of 1.645 standard deviations. When the filter is sure, the buffer is small and the drone flies longer. When it is unsure, the buffer grows automatically and the drone turns back earlier.

### Same estimate, different confidence, different decision

| Quantity | Confident filter | Unsure filter |
| --- | --- | --- |
| SoC estimate | 45% | 45% |
| σ_SoC from the EKF | 1% | 3% |
| Trip home + reserve | 30% + 10% | 30% + 10% |
| Margin m | 5% | 5% |
| σ_total (with σ_trip = 2%) | 2.2% | 3.6% |
| P(safe return) | 98.7% | 91.7% |
| Decision | Continue | Return home |

A method that uses only the estimate would treat these two cases the same. Ours does not, and that is the whole point.

### The four policies we compare

| Policy | Rule | Expected weakness |
| --- | --- | --- |
| A. Voltage threshold | Return when cell voltage stays below 3.6 V for 5 s | Fooled by sag, and ignores distance from home |
| B. Charge counting | Margin rule with SoC from counting; assumes a full, new battery | Drifts with bias, a wrong start or an aged battery |
| C. EKF estimate only | Return when margin m < 0 | Turns back too late when the filter is unsure |
| D. EKF risk-aware | Return when P(safe) < 95% | Expected best: rarely fails, wastes little |

### How each mission is judged

After the turn-back moment, the simulator flies the drone home on the true battery.

- **Failure:** the true battery empties, or the cell voltage under load falls below 3.0 V, before landing.
- **Unused battery:** true SoC at landing minus the 10% reserve. Lower means the battery was used better.
- **Work done:** distance flown before turning back.

This rule is our own design, so the report must state its assumptions: a straight flight home, a constant cruise current, and bell-shaped errors.

## 7. Experiments we will run

Eight single-flight experiments build understanding. One 500-flight Monte Carlo study then proves the headline result.

### Single-flight experiments

| # | Experiment | What we change | What we expect to see | Criterion |
| --- | --- | --- | --- | --- |
| E1 | Nominal flight | Nothing | EKF and charge counting both track well; the EKF band is tight | 1 |
| E2 | Wrong start | True SoC 70%, filter assumes 100% | Counting stays 30% wrong forever; the EKF converges, and we measure how fast | 4 |
| E3 | Biased current sensor | Bias of +0.8 A | Counting drifts steadily; the EKF learns the bias | 4, 5 |
| E4 | Aged battery | True capacity 85% of rated | Counting runs out early; the EKF capacity estimate moves toward the truth, slowly | 3, 5 |
| E5 | Turn the knobs | Q and R scaled by 0.01, 1 and 100 | Too little Q: slow and overconfident; too much: jumpy | 3 |
| E6 | Model mismatch | Truth uses 2 RC pairs and parameters off by ±15% | Some error appears; NEES and NIS tell us whether the bands stay honest | 1, 3 |
| E7 | Flat OCV region | Look at the mid-SoC part of a flight | σ_SoC grows where the curve is flat, and the risk rule reacts | 3, 5 |
| E8 | Stage comparison | Stage A, B and C filters on the same biased, aged flight | Shows what each added state buys | 3, 4 |

### The Monte Carlo study: the headline result

We fly 500 random missions. All four policies fly the same 500 missions with the same random draws, so the comparison is fair.

| Random factor | Range per mission |
| --- | --- |
| Starting SoC | 60% to 100% |
| Current-sensor bias | −1 A to +1 A |
| Battery age (true capacity) | 80% to 100% of rated |
| Wind (change in cruise current) | ±20% |
| Truth-model parameters | ±15% |
| Sensor noise | Fresh every flight |

| Metric | What it tells us |
| --- | --- |
| Failure rate | % of missions where the battery died before landing |
| Mean unused battery | True SoC at landing minus the reserve |
| Mean distance flown | How much work the drone did |
| SoC RMSE | Accuracy of the estimate, EKF vs counting |
| Mean NEES and NIS | Whether the filter's uncertainty is honest |

**Our hypothesis:** policy D gives near-zero failures with little unused battery. C fails occasionally, B fails when the battery is not full or is aged, and A wastes battery yet still fails sometimes. If the results differ, we report what happened and explain why; that still makes a good report.

### Bonus: the risk-threshold sweep

We rerun policy D with the threshold at 80%, 90%, 95%, 99% and 99.9%. Plotting failure rate against unused battery gives a trade-off curve. It shows an operator exactly what each extra "9" of safety costs in range, which is a strong creativity point.

## 8. MATLAB project structure

The project is about 12 short files, each doing one job, so you can understand and test them one at a time. Base MATLAB is enough. Control System Toolbox's built-in `extendedKalmanFilter` is optional, as a cross-check only.

```
drone_battery_ekf/
├── main_single_flight.m     Runs one flight (experiments E1–E8) and plots it
├── main_monte_carlo.m       Runs 500 flights × 4 policies and plots the comparison
├── config/
│   ├── battery_params.m     Truth and filter battery values (R0, R1, C1, Cn, ...)
│   └── ocv_lookup.m         OCV-vs-SoC table; returns OCV and its slope at any SoC
├── sim/
│   ├── make_mission.m       Route, distance to home, current profile
│   └── simulate_truth.m     The "real" 2-RC battery plus noisy, biased sensors
├── estimators/
│   ├── ekf_init.m           Start values x0, P0 and the tuning knobs
│   ├── ekf_step.m           One predict + update: the heart of the project
│   └── coulomb_count.m      Charge-counting baseline
├── decision/
│   ├── p_safe_return.m      Margin → probability, using erfc
│   └── rth_policies.m       The four turn-back rules A–D
└── plots/
    └── make_figures.m       All report figures, saved as PNG
```

### One second of flight, in code

The main loop is short. This is a sketch; the final code may differ slightly.

```matlab
for k = 1:N
    % 1. Truth: the real battery and its noisy sensors
    [truth, Im(k), Vm(k)] = simulate_truth(truth, I_true(k), p_true, dt);

    % 2. Estimators
    [xhat, P] = ekf_step(xhat, P, Im(k), Vm(k), p_filt, dt);
    soc_cc    = coulomb_count(soc_cc, Im(k), p_filt, dt);

    % 3. Decision
    ps = p_safe_return(xhat, P, dist_home(k), p_mission);
    if ps < 0.95 && ~returning
        returning = true;   % turn back now
    end
end
```

### The heart: ekf_step.m

The whole filter fits in about 30 lines. Every line maps to an equation in sections 4 and 5.

```matlab
function [x, P] = ekf_step(x, P, Im, Vm, p, dt)
% x = [SoC; V1; b; Cn]
soc = x(1); v1 = x(2); b = x(3); Cn = x(4);
I = Im - b;                                % bias-corrected current
a = exp(-dt / (p.R1 * p.C1));

% ---- Predict ----
x_pred = [soc - I*dt/(3600*Cn);
          a*v1 + p.R1*(1-a)*I;
          b;
          Cn];
F = [1 0  dt/(3600*Cn)   I*dt/(3600*Cn^2);
     0 a -p.R1*(1-a)     0;
     0 0  1              0;
     0 0  0              1];
G = [-dt/(3600*Cn); p.R1*(1-a); 0; 0];     % how current noise enters
Q = G*p.sigI^2*G' + diag([p.qSoC p.qV1 p.qb p.qCn]);
P_pred = F*P*F' + Q;

% ---- Update ----
[ocv, docv] = ocv_lookup(x_pred(1));      % OCV value and slope
V_pred = ocv - x_pred(2) - p.R0*(Im - x_pred(3));
H = [docv, -1, p.R0, 0];
S = H*P_pred*H' + p.Rv;                   % a single number
K = P_pred*H' / S;
x = x_pred + K*(Vm - V_pred);
P = (eye(4) - K*H)*P_pred;
P = (P + P')/2;                           % keep P symmetric
x(1) = min(max(x(1), 0), 1);              % keep SoC in [0, 1]
end
```

In the code, the voltage noise is called `Rv` so it is never confused with the resistors R0 and R1.

## 9. Figures the report will contain

Twelve core figures carry the report, and three extras add polish if time allows. Each figure answers one question.

| # | Figure | Question it answers | Source | Core? |
| --- | --- | --- | --- | --- |
| 1 | System diagram | How do the parts connect? | Section 1 | Core |
| 2 | OCV curve with its slope | Why do we need an EKF? | Section 2 | Core |
| 3 | Mission map + current profile | What does the drone actually do? | Simulator | Core |
| 4 | Measured vs expected voltage | Does the model explain the sag? | E1 | Core |
| 5 | SoC: truth vs EKF vs counting, with ±3σ band | Does the EKF beat counting? | E1, E2 | Core |
| 6 | SoC error with ±3σ bounds | Is the error inside the bands? | E2, E3 | Core |
| 7 | Bias estimate vs true bias | Can the filter learn a sensor error? | E3 | Core |
| 8 | Capacity estimate vs truth | Can it detect an aged battery? | E4 | Core |
| 9 | SoC RMSE for different Q and R | What does tuning do? | E5 | Core |
| 10 | Innovation and NIS over time | Is the filter honest? | E6 | Extra |
| 11 | σ_SoC against SoC | Does uncertainty grow where OCV is flat? | E7 | Extra |
| 12 | P(safe return) over time, each policy's turn-back marked | How does each rule decide? | Single flight | Core |
| 13 | Map of where each policy turned back | Who turned back too early or too late? | Single flight | Core |
| 14 | Failure rate and unused battery per policy | Which rule is best overall? | Monte Carlo | Core |
| 15 | Failure rate vs unused battery across thresholds | What does extra safety cost? | Threshold sweep | Extra |

## 10. Report structure, mapped to the marking criteria

The report follows the six sections the brief asks for, plus background and an appendix. Each section is aimed at specific criteria.

| Report section | What goes in | Figures | Criteria |
| --- | --- | --- | --- |
| 1. Introduction | The problem, why it matters (safety and range), objectives, a short list of contributions | 1 | 2, 4 |
| 2. Background | Battery basics, KF to EKF, related work (Plett; UAV SoC papers) | 2 | 3 |
| 3. Methodology | Model, states, equations, Jacobian and Q derivations, the decision rule | 3 | 1, 3 |
| 4. Implementation | File structure, the `ekf_step` code, parameters, tuning | — | 1, 2 |
| 5. Results | Experiments E1–E8, the Monte Carlo study, the threshold sweep | 4–15 | 4 |
| 6. Discussion | Why the EKF works here, limitations, when a PF or UKF would be better | 10, 11 | 3, 5 |
| 7. Conclusion | The answers, in numbers | — | 2 |
| Appendix | Full code | — | 1 |

### How to score on each criterion

1. **Correctness:** derivations match the code line for line; NEES and NIS show the filter is consistent; the truth model differs from the filter model.
2. **Clarity:** one figure per question, the same symbols everywhere, and a symbol table.
3. **Depth:** explain *why* each result happens (observability, gain behaviour, model mismatch), not only what happened.
4. **Effectiveness:** hard numbers against the baselines: SoC RMSE, failure rate, unused battery.
5. **Creativity:** the risk-aware decision rule, bias and capacity states, honest model mismatch, and the safety-vs-range trade-off curve.

### Limitations to discuss openly

Naming these yourself shows understanding and earns marks rather than losing them:

- Temperature is not modelled; a cold battery has higher resistance and less usable capacity.
- Lithium cells show slight voltage hysteresis between charge and discharge, which we ignore.
- Capacity is only weakly observable within one flight.
- The probability rule assumes bell-shaped errors; heavy-tailed surprises (a gust, a motor fault) are not covered.
- Results come from simulation; real flight logs have no true SoC to compare against.

## 11. Seven-day plan

Days 1–5 build and test, day 6 writes, day 7 polishes. The deadline is assumed to be 22 Oct 2026, seven days from 15 Oct.

### Day 1: understand

- [ ] Read sections 1–6 of this guide
- [ ] Work through one predict + update step by hand with real numbers (SoC only); we do this together
- [ ] Fix the final pack size and starting parameters

By tonight you can explain predict, update and the Kalman gain in your own words.

### Day 2: build the simulator

- [ ] `battery_params.m` and `ocv_lookup.m`, with an OCV table taken from published data
- [ ] `make_mission.m`: route, distance to home and current profile
- [ ] `simulate_truth.m`: the 2-RC battery plus noisy, biased sensors
- [ ] Figures 2 and 3; check that the voltage sags realistically at takeoff

### Day 3: first filter and baseline

- [ ] `ekf_init.m` and `ekf_step.m` with two states (Stage A)
- [ ] `coulomb_count.m`
- [ ] Run E1 and E2; figures 4, 5 and 6

### Day 4: full filter and tuning

- [ ] Add the bias and capacity states (Stages B and C)
- [ ] Run E3, E4, E5 and E8; figures 7, 8 and 9
- [ ] Check NEES and NIS (E6, E7); figures 10 and 11 if time allows

### Day 5: decision rule and Monte Carlo

- [ ] `p_safe_return.m` and `rth_policies.m`
- [ ] One flight with all four policies; figures 12 and 13
- [ ] `main_monte_carlo.m` with 500 flights; figure 14
- [ ] Threshold sweep; figure 15 if time allows

### Day 6: write the report

- [ ] Draft every section from this guide's structure (section 10)
- [ ] Insert figures, code snippets and result tables

### Day 7: polish and submit

- [ ] Check that every derivation matches the code
- [ ] Proofread; keep symbols consistent; complete the references
- [ ] Submit

**If you fall behind,** drop the extras first: figures 10, 11 and 15, then Stage C. The core still meets every requirement in the brief.

## 12. Glossary

| Term | Plain meaning |
| --- | --- |
| SoC (state of charge) | Fuel gauge of the battery, 0% to 100% |
| Capacity (Cn) | Size of the tank, in amp-hours (Ah) |
| C-rate | Current relative to capacity; 1C on a 5 Ah battery is 5 A |
| OCV (open-circuit voltage) | Battery voltage at rest; depends only on SoC |
| Terminal voltage | Voltage the sensor actually reads while current flows |
| R0 (internal resistance) | Causes the instant voltage drop under load |
| R1, C1, V1 (polarisation) | Model the slow extra voltage drop under sustained load |
| Voltage sag | Temporary voltage drop under heavy load |
| Coulomb counting | Tracking SoC by adding up current over time |
| Bias | A constant error in a sensor reading |
| State | A hidden quantity the filter estimates |
| Input | A known signal that drives the model (measured current) |
| Measurement | A sensor reading compared against the model (voltage) |
| Process model (f) | How the states change from one second to the next |
| Measurement model (h) | What the sensor should read, given the states |
| Covariance (P) | The filter's uncertainty about its states |
| Kalman gain (K) | How much the filter trusts the measurement over its prediction |
| Innovation | Measured minus expected value; the filter's surprise |
| Q | Process noise: how much the filter distrusts its model |
| R | Measurement noise: how much it distrusts the sensor |
| Jacobian (F, H) | Matrix of slopes; the tangent-line approximation of a curved equation |
| Linearisation | Replacing a curve with its tangent line near the current guess |
| Observability | Whether the measurements contain enough information to pin down a state |
| State augmentation | Adding an unknown constant, like bias, as an extra state to learn it |
| NEES / NIS | Statistical checks that the filter's stated uncertainty matches its real errors |
| Monte Carlo | Repeating a random simulation many times to get reliable averages |
| RMSE | Root-mean-square error; a typical size of the error |
| RTH (return to home) | The drone abandoning the mission to fly back and land |
| Φ (normal CDF) | Turns "how many standard deviations of margin" into a probability |
| Model mismatch | The filter's model differing from the real system, as it always does in practice |

## 13. References and data sources

These were found by web search on 15 Oct 2026. Open each one and check the details before citing it in the report.

### Filter and battery theory

- G. L. Plett, [Extended Kalman filtering for battery management systems of LiPB-based HEV battery packs, Part 1: Background](https://www.doi.org/10.1016/J.JPOWSOUR.2004.02.031), Journal of Power Sources, 2004. Parts 2 and 3 cover modelling and state/parameter estimation.
- [Extended Kalman Filter with Battery Estimation Example](https://www.mathworks.com/matlabcentral/fileexchange/105855-extended-kalman-filter-with-battery-estimation-example), MATLAB File Exchange. Useful to compare against our code.

### Drone battery estimation (related work)

- [SoC estimation using an extended Kalman filter for UAV applications](https://hal.archives-ouvertes.fr/hal-01537730), HAL archive.
- [Verification of prognostic algorithms to predict remaining flying time for electric unmanned vehicles](https://papers.phmsociety.org/index.php/ijphm/article/view/2700), International Journal of Prognostics and Health Management. Also see the related [NASA report](https://ntrs.nasa.gov/api/citations/20190025952/downloads/20190025952.pdf).
- [EKF, UKF and Coulomb counting compared on delivery and inspection missions](https://docs.lib.purdue.edu/jate/vol12/iss2/4), Purdue Journal of Aviation Technology and Engineering.

### Datasets (optional real-data checks)

- [In-flight positional and energy use data set of a DJI Matrice 100 quadcopter for small package delivery](https://arxiv.org/pdf/2103.13313), Carnegie Mellon, Scientific Data 2021. 209 flights with voltage and current logged.
- [eVTOL Battery Dataset](https://kilthub.cmu.edu/articles/dataset/eVTOL_Battery_Dataset/14226830), Carnegie Mellon, with its paper [A battery dataset for electric vertical takeoff and landing aircraft](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10238407/). Takeoff, cruise and landing duty cycles.
- [LG 18650HG2 Li-ion Battery Data](https://data.mendeley.com/datasets/b5mj79w5w9/2), McMaster University. Built for testing Kalman-filter SoC algorithms.

### Textbooks (from memory; verify the editions)

- G. L. Plett, *Battery Management Systems, Volume II: Equivalent-Circuit Methods*, Artech House.
- D. Simon, *Optimal State Estimation: Kalman, H∞, and Nonlinear Approaches*, Wiley, 2006.
- G. Welch and G. Bishop, *An Introduction to the Kalman Filter*, UNC Chapel Hill technical report. A gentle first read.
