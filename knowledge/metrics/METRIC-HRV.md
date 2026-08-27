---
card_id: METRIC-HRV
metric_zh: 心率变异性（HRV, SDNN）
metric_bindings: [HKQuantityTypeIdentifierHeartRateVariabilitySDNN]
what_it_is: 相邻心跳间隔（RR 间期）的波动程度，反映自主神经系统（交感/副交感）对心脏的动态调节能力。Apple Health 记录的是 SDNN（正常 RR 间期的标准差），单位毫秒，通常越"有弹性"的身体状态下数值越高。
what_it_is_not: >
  HRV 不是"压力值"，单次低值不等于"你压力大"——它同时受睡眠、运动、酒精、周期相位、测量时机等多因素影响。
  注意口径：Apple 用 SDNN，而多数睡眠/恢复研究和主流可穿戴（Oura/Whoop）用 RMSSD；
  两者相关但不可直接换算，短时 SDNN（Apple 约 1 分钟采样）也不能与文献中 24 小时 SDNN 的参考值比较。
safe_claim_style: 只对"个人基线的相对变化"下结论，如"过去 3 天你的 HRV 低于你自己的 7 天基线约 20%，这段时间恰好连续短睡，两者可能相关，建议观察"。永远与自身比、说相关不说因果、给观察建议而非诊断。
avoid_claims:
  - "HRV 低说明你压力大"（单因素归因，HRV 受多因素影响）
  - "你的 HRV 比平均值/别人低，说明身体差"（个体间差异极大，跨人比较无意义）
  - "HRV 下降 = 生病了 / 内分泌失调"（诊断性断言，需医疗检查）
  - "HRV 高就可以放心加大训练量"（把相关当决策依据的过度推断）
  - 用 Apple 的 SDNN 值直接对照以 RMSSD 或 24h SDNN 为口径的文献阈值
internal_priority_note: 本卡各假设按 P1(系统综述/荟萃) P2(叙述综述/观察/单RCT) P3(小样本) 标注
last_reviewed: 2026-08-28
---

# METRIC-HRV：心率变异性（SDNN）

## 1. 生理机制（人话版）

心脏不是节拍器：健康状态下每次心跳的间隔都在微小波动。这个波动主要由自主神经"油门"（交感）和"刹车"（副交感/迷走神经）的实时博弈产生。
副交感占优（放松、恢复良好）时波动大→HRV 高；交感占优（应激、疲劳、炎症、酒精代谢中）时心跳变"死板"→HRV 低。
所以 HRV 可粗略理解为"身体当下的恢复余量/调节弹性"，而不是某种单一情绪的读数。

## 2. 已知影响因素

| 因素 | 方向 | 优先级 | 出处 |
|---|---|---|---|
| 睡眠不足/质量差 | 降低当夜及次日 HRV | P2 | Bourdillon 2021 (PMID 33897355)；Corrigan 2023 (PMID 36371929) ✅ |
| 高训练负荷/高强度运动 | 次日短期降低，1–2 天恢复；长期规律运动提高基线 | P2 | Nuuttila 2022 (PMID 35894977)；Buchheit 2014 (PMID 24578692) ✅ |
| 月经周期相位 | 多数研究：黄体期（尤其后期）迷走指标下降，卵泡期较高；个体差异大 | P1 | de Jager 2026 系统综述 (PMID 41545627) ✅（16 项研究，黄体期偏低，可单独支撑本行） |
| 酒精 | 当晚夜间 HRV 明显下降，剂量相关，可延续到次日 | P2 | Pietilä 2018 (DOI 10.2196/mental.9519，4098 人真实世界数据) ✅ |
| 年龄 | 随年龄增长基线下降 | P2 | Task Force 1996 ✅；正常参考值综述（Heart Rhythm 2016）⚠️待核 |
| 急性疾病/感染/炎症 | 显著降低，常早于主观症状 | P2 | ⚠️待核 |
| 咖啡因（尤其午后） | 可能轻度降低夜间 HRV，证据不一致 | P3 | ⚠️待核 |

## 3. analysis_hypotheses（核心节）

### H1 周期相位与 HRV 【P1】
- **假设**：黄体后期（经前约 5–7 天）的 HRV 日均值低于卵泡中期。
- **预期方向**：黄体后期 ↓（幅度可能 5–15%，个体差异大）。
- **需要的数据**：`HeartRateVariabilitySDNN`（日均值）、`HKCategoryTypeIdentifierMenstrualFlow`（推算相位）。
- **最少样本量**：≥3 个完整周期（约 90 天），每相位 ≥5 个有 HRV 记录的天。
- **出处**：de Jager 2026 (PMID 41545627，已核实且方向一致)。

### H2 短睡后 HRV 【P2】
- **假设**：睡眠时长比个人均值短 ≥1 小时的次日，HRV 低于个人基线。
- **预期方向**：短睡次日 ↓。
- **需要的数据**：`SleepAnalysis`（asleep 时长）、HRV 日均值。
- **最少样本量**：≥10 个短睡日 + ≥20 个正常日（约 6–8 周）。
- **出处**：Bourdillon 2021 (PMID 33897355)、Corrigan 2023 (PMID 36371929)，已核实。

### H3 高强度日后 HRV 【P2】
- **假设**：高强度训练日的当晚/次日 HRV 下降，1–2 天内回归基线；不回归提示恢复不足。
- **预期方向**：次日 ↓，第 2–3 天回升。
- **需要的数据**：`HKWorkoutType` + 时长 + `ActiveEnergyBurned`（划分高/低强度日）、HRV 日均值。
- **最少样本量**：≥8 个高强度日（约 4–6 周规律训练）。
- **出处**：Nuuttila 2022 (PMID 35894977)、Buchheit 2014 (PMID 24578692)，已核实。

### H4 饮酒与 HRV 【P2】
- **假设**：饮酒日当晚夜间 HRV 显著低于不饮酒夜，且量越大降幅越大。
- **预期方向**：↓，可能延续至次日晨。
- **需要的数据**：主观记录"饮酒 + 大致杯数"（HealthKit 无原生字段，需 App 内打 tag）、夜间 HRV。
- **最少样本量**：≥5 个饮酒日 + ≥20 个基线日。
- **出处**：Pietilä 2018 (DOI 10.2196/mental.9519) ✅已核实；剂量相关抑制睡眠期自主恢复，方向一致。

### H5 连续低 HRV 作为累积负荷信号 【P2】
- **假设**：HRV 连续 ≥3 天低于"个人 7 天滚动均值 − 1SD"时，随后出现静息心率升高、主观疲劳/情绪低的概率上升（累积负荷/生病前兆信号）。
- **预期方向**：连续低 HRV → 后续负向状态概率 ↑。
- **需要的数据**：HRV 日均值（滚动基线）、`RestingHeartRate`、主观状态打分（App 内记录）。
- **最少样本量**：≥60 天连续数据，含 ≥3 次"连续低"事件。
- **出处**：Buchheit 2014 (PMID 24578692)、Lundstrom 2023 (PMID 35853460)，已核实。

### H6 午后咖啡因与夜间 HRV 【P3】
- **假设**：14:00 后摄入咖啡因的当晚 HRV 略低。预期方向 ↓（弱效应）。
- **需要的数据**：主观咖啡因记录（时间+量）、夜间 HRV。最少样本量：≥15 咖啡因日 + ≥15 对照日。
- **出处**：⚠️待核，证据不一致，仅作探索。

## 4. confounds（混杂与口径）

- **Apple 间歇测量**：Apple Watch 仅在静止时机会性采样（约每 2 小时一次，+呼吸/正念 App 主动触发），每天样本数少且不固定，单日均值噪声大。
- **测量时机不固定**：白天活动间隙测到的值与夜间睡眠中的值差异巨大；比较时应尽量固定窗口（如只取夜间/清晨样本），否则"HRV 变化"可能只是"测量时间变了"。
- **单次值 vs 日均值**：单次读数波动可达 ±30% 以上，分析一律用日均值或固定时段均值，趋势看 7 天滚动线。
- **SDNN vs RMSSD 口径差**：RMSSD 主要反映迷走活动、对呼吸敏感；SDNN 混合了更多成分。文献结论多基于 RMSSD 或 24h SDNN，迁移到 Apple 的超短时 SDNN 时只能借"方向"，不能借"阈值"。

## 5. 数据质量注意

- 剔除明显异常值（如 <5 ms 或 >250 ms 的单次读数）；心律不齐、期前收缩会严重污染 SDNN。
- 每日有效样本 <2 次的天在假设检验中降权或剔除；佩戴习惯改变（换手、夜间不戴）当作数据断层标记。
- 生病、旅行/时差、经期第 1–2 天等特殊日打 tag，供分析时分层或排除。
- 版本迁移：watchOS 更新可能改变采样策略，长期趋势分析需注意系统版本断点。

## 6. 参考文献

1. Task Force of ESC/NASPE. Heart rate variability: standards of measurement, physiological interpretation and clinical use. *Circulation* 1996. ✅在线核实
2. Ramesh S, et al. HRV as a function of menopausal status, menstrual cycle phase, and estradiol level. *Physiol Rep* 2022. PMID: 35608101 ✅在线核实【注：该文（41 人横断面研究）结论为基线 HRV 无月经周期相位差异，不支持相位差异结论，仅存档；卡内已不再引用】
3. de Jager E, et al. Wearable-derived HRV across the menstrual cycle, hormonal contraceptive use, and reproductive life stages (living systematic review). *Sports Med* 2026. PMID: 41545627 ✅在线核实
4. Bourdillon N, et al. Sleep deprivation deteriorates heart rate variability and photoplethysmography. *Front Neurosci* 2021. PMID: 33897355 ✅在线核实
5. Corrigan SL, et al. Overnight HRV responses to military combat engineer training（含睡眠时长与 HRV 关联）. *Appl Ergon* 2023. PMID: 36371929 ✅在线核实
6. Nuuttila OP, et al. Reliability and sensitivity of nocturnal HR/HRV in monitoring individual responses to training load. *Int J Sports Physiol Perform* 2022. PMID: 35894977 ✅在线核实
7. Buchheit M. Monitoring training status with HR measures: do all roads lead to Rome? *Front Physiol* 2014. PMID: 24578692 ✅在线核实
8. Lundstrom CJ, et al. Practices and applications of HRV monitoring in endurance athletes. *Int J Sports Med* 2023. PMID: 35853460 ✅在线核实
9. Pietilä J, et al. Acute effect of alcohol intake on cardiovascular autonomic regulation during the first hours of sleep in a large real-world sample of Finnish employees. *JMIR Ment Health* 2018. DOI: 10.2196/mental.9519（4098 名芬兰雇员，剂量相关抑制睡眠期自主恢复）✅在线核实
10. 年龄相关 HRV 正常参考值综述（Heart Rhythm 2016 前后）. ⚠️待核
11. 咖啡因与夜间 HRV. ⚠️待核
