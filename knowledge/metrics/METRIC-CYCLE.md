---
card_id: METRIC-CYCLE
metric_zh: 月经周期（经期记录与推算周期相位）
metric_bindings: [HKCategoryTypeIdentifierMenstrualFlow]
what_it_is: >
  用户在 Apple Health / 手表上自记的经期出血记录（有无+流量分级），
  以及系统由"周期第一天"前向计数推算出的周期天数与相位估计
  （月经期/卵泡期/排卵窗附近/黄体期）。它是本产品所有"按周期看数据"
  分析的时间轴锚点。
what_it_is_not: >
  相位是由经期记录推算的"估计"，不是激素实测。未经排卵检测（LH试纸、
  确认的体温双相等）确认，不能断言"你现在处于X期"——只能说"按推算，
  你大约在X期"。它也不是排卵确认工具、不是生育力判断，更不是诊断依据。
safe_claim_style: >
  「按你记录的经期推算，你目前大约在黄体期。在你过去 N 个周期里，
  这个阶段你的 HRV 平均比卵泡期低 X%。这是常见生理现象，仅供你
  参考自己的规律，不构成医疗建议。」——始终带"推算/大约/你自己的
  历史数据"三要素，并区分"文献说常见"与"你的数据显示"。
avoid_claims:
  - 不做任何怀孕、生育力、避孕有效性的推断或暗示（哪怕用户漏经期也只提示"记录缺口"，不提示"可能怀孕"）。
  - 不说"女性都会如此/黄体期就是会睡不好"——只说文献中的比例与方向，且个体差异很大。
  - 未经排卵确认不断言相位（"你处于排卵期"是禁语；只能说"按推算接近排卵窗"）。
  - 经前情绪波动的观察不等于 PMS/PMDD 诊断，不使用诊断性措辞，不建议用药。
  - 不用周期数据评判用户（如"周期不规律说明你身体差"）；周期长度变异是信息，不是缺陷。
internal_priority_note: 本卡各假设按 P1(系统综述/荟萃) P2(叙述综述/观察/单RCT) P3(小样本) 标注
last_reviewed: 2026-08-28
---

# METRIC-CYCLE：月经周期与推算相位

## 1. 生理机制（人话版）

一个周期从月经第一天开始。前半段（卵泡期）雌激素逐步爬升，身体偏"低温、低心率"状态；
中段雌激素达峰后触发 LH 峰，随后进入后半段（黄体期），孕激素成为主导。
孕激素有轻微升温和交感偏移效应：核心/远端体温升高约 0.2–0.5°C，静息心率上升，
迷走神经张力（表现为 HRV）下降。若未受孕，周期末两种激素一起回落，
体温、心率回落，月经来潮，进入下一循环。经前几天（黄体晚期）激素快速撤退，
是主观睡眠、情绪、精力报告变化最集中的窗口。
关键点：**后半段（黄体期）长度相对稳定（约 12–14 天），周期长短的差异主要来自前半段**（Bull 2019）。

## 2. 已知影响因素与对其他指标的已知影响

证据分级（按卡片规范）：P1=系统综述/荟萃；P2=叙述综述/观察/单RCT（含大样本观察）；P3=小样本/初步证据。

| 结论 | 等级 | 出处 |
|---|---|---|
| 腕/指端皮温呈周期性双相：黄体期比卵泡期高约 0.3°C 量级，可用于回溯性标记相位 | P2 | Zhu 2021 (JMIR)；Alzueta 2024；Apple/Natural Cycles 算法研究 (Hum Reprod 2025)（均为观察性研究） |
| 静息心率：月经期最低，排卵前后开始上升，黄体中晚期最高（幅度约 1–4 bpm） | P2 | Alzueta 2024；Goodale 2019 (Ava 队列，待核)（均为观察性研究） |
| HRV（RMSSD 等迷走指标）：黄体晚期低于卵泡期/月经期，与孕激素水平相关；年轻人群更明显 | P2 | Alzueta 2024；Schmalenberger 2020 (部分核实)；Sports Med 2026 活系统综述 (部分核实) |
| 客观睡眠指标（效率、时长、入睡潜伏期）在周期各相位总体稳定，但主观睡眠质量在经前常变差——"主观差、客观稳"是常见解离 | P2 | Alzueta 2024（客观稳定的直接证据）；经前主观睡眠变差为综述共识（Baker & Driver 2007，已核实） |
| 情绪：排卵期附近积极情绪偏高，黄体晚期负面情绪与躯体症状报告增多；黄体期 HRV 下降与经前情绪变化相关 | P2 | Alzueta 2024；BMC Women's Health 2024 (已核实) |
| 食欲与能量摄入：黄体期能量摄入平均高约 100–300 kcal/天，对碳水/甜食渴求增加 | P2 | 经典代谢研究共识（如 Barr 1995 等，未能在线核实）——写入假设时以用户自记为准 |
| 周期长度本身有意义：均值约 29.3 天，个体内有天然波动；周期长度差异主要由卵泡期贡献；年龄每 +1 岁周期约缩短 0.18 天 | P2 | Bull 2019 (n=612,613 周期，大样本观察) |
| 激素避孕会抑制内源性周期，上述所有相位效应不再适用 | P1 | Sports Med 2026 活系统综述 (部分核实)；机制层面为共识 |

## 3. analysis_hypotheses（核心节）

样本量单位为**周期数**（非天数）；一个周期约提供 1 对"卵泡期 vs 黄体期"配对观察。

### H1（P1）黄体期 HRV 下降 + 静息心率升高
- 陈述：同一用户内，黄体期（尤其黄体中晚期）夜间 HRV 低于卵泡期，RHR 高于卵泡期。
- 方向：HRV ↓，RHR ↑（相对卵泡期基线）。
- 数据字段：HKQuantityTypeIdentifierHeartRateVariabilitySDNN、HKQuantityTypeIdentifierRestingHeartRate + 本卡相位推算。
- 最少样本：3 个完整周期起步，6 个周期可给出稳定的个人幅度。
- 出处：Alzueta 2024（已核实）；Schmalenberger 2020（部分核实）。

### H2（P2）经前睡眠变化：主观先于客观
- 陈述：经前 3–5 天主观睡眠质量/晨间恢复感下降，而客观睡眠时长与效率可能不变——两者的差值本身是该用户的特征。
- 方向：主观评分 ↓；客观指标预期变化小（若客观也变，是更强的个人信号）。
- 数据字段：HKCategoryTypeIdentifierSleepAnalysis（时长/效率/阶段）+ 用户主观晨间评分。
- 最少样本：4 个周期（主观数据噪声大）。
- 出处：Alzueta 2024（已核实）；Baker & Driver 2007（已核实，PMID 17383933）。

### H3（P2）经前主观精力与情绪低谷
- 陈述：黄体晚期主观精力与情绪评分出现该用户可重复的低谷，且低谷深度与当周期 HRV 降幅相关。
- 方向：精力/情绪评分 ↓，与 HRV 降幅正相关（HRV 掉得越多，主观越差）。
- 数据字段：用户主观情绪/精力打卡 + HRV + 相位。
- 最少样本：4–6 个周期。
- 出处：BMC Women's Health 2024（已核实）；Alzueta 2024（已核实）。

### H4（P2）周期与食欲
- 陈述：黄体期主观食欲/渴求（尤其甜食）高于卵泡期。
- 方向：食欲 ↑；如用户记录饮食，能量摄入 ↑。
- 数据字段：主观食欲打卡（本产品自记）+ 可选 HKQuantityTypeIdentifierDietaryEnergyConsumed。
- 最少样本：3 个周期（主观食欲信号通常较明显）。
- 出处：经典代谢研究共识（未能在线核实）——对用户表述降级为"很多研究提示"。

### H5（P1）腕温作为相位标记与推算校准
- 陈述：夜间腕温的双相上移可回溯性地标记黄体期起点，用它校准"前向计数"的相位推算，比纯日历法更贴近该用户实际。
- 方向：黄体期腕温相对基线 ↑（约 +0.1~0.5°C，个体化）。
- 数据字段：HKQuantityTypeIdentifierAppleSleepingWristTemperature + MenstrualFlow。
- 最少样本：2 个周期即可见双相；4 个周期可做个人化校准。
- 出处：Zhu 2021（已核实）；Hum Reprod 2025 Apple 算法研究（已核实）。

### H6（P2）周期长度变异性本身的信息量
- 陈述：个人周期长度的滚动标准差是独立信号：变异突然增大可能与压力、旅行、训练负荷、体重变化等生活事件同期出现（只报共现，不下因果）。
- 方向：生活扰动期 → 周期长度变异 ↑（主要通过卵泡期延长/缩短体现）。
- 数据字段：MenstrualFlow 推算的周期长度序列 + 用户生活事件标注。
- 最少样本：6 个周期起（变异性统计需要更长序列）。
- 出处：Bull 2019（已核实：变异主要来自卵泡期）。

## 4. 混杂因素（confounds）

- **激素避孕改变一切**：口服避孕药/激素环等抑制内源性周期，相位假设 H1–H5 全部失效。必须先问、并允许用户标注；未标注时发现"无双相腕温+无 HRV 相位差"应提示而非硬套结论。
- **周期不规律**：周期长度波动大时，"前向计数"推算的中后段相位误差可达一周以上；此时只有月经期本身可信，其余相位结论应降级或依赖腕温标记（H5）。
- **漏记与假性长周期**：漏记一次经期会被算成一个超长周期，污染 H6 的变异性统计。超过个人均值 1.5 倍的周期先当作疑似漏记处理。
- **前向 vs 倒数计数的方法差异**：卵泡期事件用"周期第 N 天"（前向）定位，黄体期事件更该用"距下次月经 -N 天"（倒数）定位——因为黄体期长度稳定而卵泡期长度多变（Bull 2019）。经前分析一律用倒数计数，否则不同长度的周期会把黄体晚期对不齐。
- **共享时间轴的其他因素**：疾病、饮酒、旅行、剧烈训练同样压低 HRV / 抬高 RHR / 升高夜温，会伪装成相位效应。跨多个周期重复出现的模式才可信，单周期不下结论。

## 5. 数据质量注意

- 一切相位推算依赖用户自记经期的**完整性**：起始日最关键，缺失一天起始记录 = 整个周期轴平移。
- 记录密度检查：若某"周期"仅有零星一天流量记录，视为不完整周期，排除出统计而非硬算。
- Apple Health 中 MenstrualFlow 可能来自多个来源（手动、Cycle Tracking 预测回填），需区分"用户确认的记录"与"预测值"，只用前者定锚。
- 腕温需要连续佩戴入睡才有值；断续佩戴的周期不参与 H5。
- 新用户冷启动：前 2 个周期只做记录鼓励与描述性反馈，不输出相位性结论。

## 6. 参考文献

| # | 文献 | 核实状态 |
|---|---|---|
| 1 | Bull JR, et al. Real-world menstrual cycle characteristics of more than 600,000 menstrual cycles. *npj Digit Med*. 2019;2:83. doi:10.1038/s41746-019-0152-7. PMID: 31482137 | ✅ 已在线核实（PubMed/Nature） |
| 2 | Alzueta E, Gombert-Labedens M, et al. Menstrual Cycle Variations in Wearable-detected Finger Temperature and Heart Rate, but not in Sleep Metrics, in Young and Midlife Individuals. *J Biol Rhythms*. 2024;39(5):395–412. doi:10.1177/07487304241265018. PMID: 39108015 | ✅ 已在线核实（PMC 全文） |
| 3 | Zhu TY, et al. The Accuracy of Wrist Skin Temperature in Detecting Ovulation Compared to Basal Body Temperature. *J Med Internet Res*. 2021;23(6):e20710 | ✅ 已在线核实（JMIR，193 周期/57 人） |
| 4 | Performance of algorithms using wrist temperature for retrospective ovulation day estimate and next menses start day prediction. *Hum Reprod*. 2025;40(3):469– | ✅ 已在线核实（OUP 页面） |
| 5 | Schmalenberger KM, et al. Menstrual Cycle Changes in Vagally-Mediated HRV Are Associated with Progesterone（两项个体内研究）. PMC7141121 | ⚠️ 部分核实（检索到 PMC 条目，全文抓取被拦截） |
| 6 | Wearable-Derived HRV Across the Menstrual Cycle… A Living Systematic Review. *Sports Med*. 2025. doi:10.1007/s40279-025-02388-y | ⚠️ 部分核实（检索到 Springer 条目，未读全文） |
| 7 | Schmalenberger KM, et al. Associations of luteal phase changes in vagally mediated HRV with premenstrual emotional changes. *BMC Women's Health*. 2024. doi:10.1186/s12905-024-03273-y | ✅ 已在线核实（审查补核成功） |
| 8 | Baker FC, Driver HS. Circadian rhythms, sleep, and the menstrual cycle（综述）. *Sleep Med*. 2007. PMID: 17383933 | ✅ 已在线核实（审查补核成功） |
| 9 | 黄体期能量摄入增加的经典代谢研究（如 Barr 1995 等） | ❌ 未能在线核实，卡内表述已降级为"多项研究提示" |
