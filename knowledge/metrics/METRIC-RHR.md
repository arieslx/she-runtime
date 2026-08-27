---
card_id: METRIC-RHR
metric_zh: 静息心率
metric_bindings: [HKQuantityTypeIdentifierRestingHeartRate]
what_it_is: 身体在清醒、安静、不活动状态下的每分钟心跳次数估计值,反映自主神经系统(交感/副交感)平衡与心血管基础负荷,是恢复状态、周期相位、疾病与生活方式(酒精/睡眠)的敏感慢变量。
what_it_is_not: 不是运动时心率,不是医学诊断指标,不是"越低越好"的绝对分数;单日数值波动不代表健康变化,与他人比较无意义——只有与本人基线的相对偏移才可解读。
safe_claim_style: 只做"与你自己近期基线相比的相对变化"陈述,如"过去3天你的RHR比近30天基线高X bpm,历史上这种模式常与你的黄体期/饮酒/睡眠不足记录同时出现",并始终标注样本量与不确定性。
avoid_claims:
  - 不得声称RHR升高"诊断"或"预测"任何疾病(包括感染、心脏病、怀孕),只能说"与你历史上的某类记录存在时间上的关联"。
  - 不得用RHR判定排卵日或作为避孕/备孕依据(个体误差远大于群体均值2-4 bpm的效应量)。
  - 不得与人群标准值或他人数据比较来评价用户"心脏好坏"或体能高低。
  - 不得在样本量不足(见各假设最少样本)时输出结论,不得把单日异常当作趋势。
internal_priority_note: 本卡各假设按 P1(系统综述/荟萃) P2(叙述综述/观察/单RCT) P3(小样本) 标注
last_reviewed: 2026-08-28
---

# 静息心率(RHR)指标知识卡

## 1. 生理机制

静息心率由窦房结自律性决定,受自主神经系统持续调制:副交感(迷走)张力压低心率,交感激活抬高心率。因此RHR是一个"自主神经天平"的读数:

- **副交感占优**(恢复良好、有氧体能高)→ RHR偏低且稳定。
- **交感占优**(应激、炎症、脱水、酒精代谢、发热、恢复不足)→ RHR升高。
- **激素调制**:黄体期孕酮升高伴随核心体温上升约0.3-0.5°C与轻度交感偏移,带动RHR上升;这是女性RHR天然周期性波动的主因。
- **发热/免疫激活**:体温每升高1°C,心率约增加8-10 bpm(经验规律),感染前驱期的炎症反应即可推高RHR。

关键解读原则:RHR是**慢变量**,有意义的信号是"多日相对本人基线的持续偏移",而非单日绝对值。

## 2. 已知影响因素

| 因素 | 方向 | 优先级 | 出处 |
|---|---|---|---|
| 体能水平(长期有氧训练) | 长期↓(数周-数月尺度) | P2 | 运动生理学共识,教科书级;未单独在线核实 |
| 月经周期(黄体期 vs 卵泡期/月经期) | ↑ 约2-4 bpm | P2 | Shilaih 2017 [R1](已核实);npj Digit Med 2026 [R4](均为观察性研究) |
| 睡眠不足/熬夜 | 次日↑ | P2 | 与恢复不足机制一致;具体效应量未能在线核实 |
| 酒精(前一晚饮酒) | 当夜及次日↑ 约3 bpm,剂量相关 | P2 | Strüven 2025 [R2](已核实);PLOS Digit Health 2026 [R5](均为观察性研究) |
| 疾病(感染前驱期/发热) | ↑,可早于症状数日 | P2 | Mishra 2020 [R3](已核实,单队列观察) |
| 脱水 | ↑(血容量下降→代偿性心率上升) | P3 | 生理机制明确;可穿戴场景效应量未能在线核实 |
| 高温/气温季节变化 | 热应激时↑;RHR有季节性波动 | P3 | 未能在线核实,标注为待验证 |

注:PLOS Digit Health 2026大样本研究显示,酒精对RHR/HRV的影响**在女性中比男性更大**、年轻人比年长者更大 [R5]——对本产品用户群尤其相关。

## 3. analysis_hypotheses(核心节)

### H1 周期相位与RHR 【P2】
- **陈述**:用户黄体期的夜间/晨间RHR高于卵泡期与月经期,差值约2-4 bpm;RHR在月经开始前后回落可作为相位佐证信号。
- **方向**:黄体期 ↑,月经期回落至周期最低。
- **数据字段**:HKQuantityTypeIdentifierRestingHeartRate(按日)、HKCategoryTypeIdentifierMenstrualFlow(定相位锚点)、可选HKQuantityTypeIdentifierBasalBodyTemperature 交叉验证。
- **最少样本**:≥3个完整记录周期(约90天),且每周期RHR覆盖率≥70%。
- **出处**:Shilaih 2017 [R1](已核实,黄体中期vs月经期+3.8 bpm);npj Digit Med 2026 [R4]。

### H2 RHR持续升高作为恢复不足信号 【P2】
- **陈述**:RHR连续≥3天高于个人30天滚动基线+1个标准差(且无法用周期相位解释)时,与用户主观疲劳/训练负荷记录正相关,提示恢复不足。
- **方向**:恢复不足 → RHR多日持续↑。
- **数据字段**:RestingHeartRate、HKQuantityTypeIdentifierAppleExerciseTime/Workout记录、主观疲劳打分(App内记录)、SleepAnalysis。
- **最少样本**:≥60天RHR基线 + ≥10次主观疲劳记录。
- **出处**:训练监控领域共识方向;本条主要依赖个人内部验证,群体文献效应量未能在线核实——输出时须降低置信措辞。

### H3 疾病来临前的RHR升高 【P2】
- **陈述**:感染性疾病症状出现前0-4天(个别可提前更多),RHR相对个人基线出现异常升高(Mishra研究摘要口径:81%病例可检出生理改变,22/25在症状当天或之前可检出);回溯用户"生病"标签可验证此模式。
- **方向**:症状前数日 ↑,病愈后回落。
- **数据字段**:RestingHeartRate、RespiratoryRate、主观"生病/症状"标签、体温(如有)。
- **最少样本**:≥90天基线 + ≥2次带标签的生病事件才可做回溯呈现;严禁前瞻式"你要生病了"预警。
- **出处**:Mishra 2020, Nat Biomed Eng [R3](已核实,摘要口径:81%病例有生理改变,22/25在症状当天或之前可检出,模拟告警63%在前驱期触发)。

### H4 饮酒次日RHR升高 【P2】
- **陈述**:饮酒当夜的夜间RHR较本人无酒精夜升高(中等剂量约+3 bpm),呈剂量相关,停饮后1-3天内回落;女性效应量更大。
- **方向**:饮酒当夜/次日 ↑。
- **数据字段**:RestingHeartRate、HeartRateVariabilitySDNN、App内饮酒记录(时间+量)、SleepAnalysis。
- **最少样本**:≥5个饮酒夜 + ≥20个无酒精对照夜(本人内部对照)。
- **出处**:Strüven 2025 [R2](已核实,63.6→66.6 bpm);PLOS Digit Health 2026 [R5]。

### H5 RHR与HRV联合解读比单看更稳 【P2】
- **陈述**:"RHR↑ 且 HRV↓"同时出现时,对应激/恢复不足/饮酒/前驱感染的指示一致性显著高于任一指标单独异常;两指标方向矛盾时应输出"信号不明"而非强行解释。
- **方向**:压力态 = RHR↑ + HRV↓ 同向共现。
- **数据字段**:RestingHeartRate + HKQuantityTypeIdentifierHeartRateVariabilitySDNN(注意Apple仅提供SDNN,非RMSSD)。
- **最少样本**:≥60天双指标共同覆盖。
- **出处**:PLOS Digit Health 2026中RHR↑与HRV↓同现于饮酒夜 [R5];Sports Med 2026 HRV周期综述 [R6]。方法论组合本身为领域惯例,未见单独验证文献——待核。

## 4. confounds(混杂因素)

- **Apple的RHR算法口径**:Apple Watch的RHR并非睡眠心率,而是从**全天清醒静止时段**的背景心率读数中估计的当日值(与WHOOP/Oura用睡眠期心率的口径不同,数值系统性偏高且更受白天行为影响)。跨设备数据不可混用比较。此口径描述基于Apple公开文档,细节算法未公开——标注待核。
- **测量条件差异**:佩戴松紧、纹身/肤色对PPG信号的影响、当天静止时段多少(久坐日vs奔波日采样条件不同)、咖啡因摄入时间、测量当天是否发热或服药(β受体阻滞剂显著压低心率,支气管扩张剂/减充血剂抬高)。
- **相位混杂**:H2-H4的所有"升高"都必须先扣除H1的周期相位效应,否则黄体期正常升高会被误报为恢复不足/前驱疾病。
- **群体效应量≠个体效应量**:2-4 bpm是均值,个体可能不显现或更大;所有假设必须在用户本人数据内重新验证。

## 5. 数据质量注意

- 检查每日RHR是否存在:未佩戴日、仅充电时佩戴日会缺失或严重失真;建议以"过去30天覆盖率≥70%"作为启用分析的门槛。
- 剔除明显异常值(如RHR<35或>110 bpm的孤立点),但**连续多日**的高值不是异常值而是信号,不可剔除。
- 基线用30天滚动中位数±MAD而非均值±SD,以抗离群点。
- 注意设备更换/watchOS大版本升级可能造成口径跳变,应在时间轴上标记断点,跨断点不做直接比较。
- 周期相位分析需月经记录作锚;无记录周期的数据只能进入"未定相"池。

## 6. 参考文献

- [R1] Shilaih M, et al. Pulse Rate Measurement During Sleep Using Wearable Sensors, and its Correlation with the Menstrual Cycle Phases. *Sci Rep*. 2017;7:1294. DOI: 10.1038/s41598-017-01433-9. PMID: 28465583. **【已在线核实】**
- [R2] Strüven A, et al. The Impact of Alcohol on Sleep Physiology: A Prospective Observational Study on Nocturnal Resting Heart Rate Using Smartwatch Technology. *Nutrients*. 2025;17(9):1470. DOI: 10.3390/nu17091470. **【已在线核实】**
- [R3] Mishra T, et al. Pre-symptomatic detection of COVID-19 from smartwatch data. *Nat Biomed Eng*. 2020;4:1208-1220. DOI: 10.1038/s41551-020-00640-6. **【已在线核实】**
- [R4] Gonzalez, et al. The menstrual cycle through the lens of a wearable device. *npj Digital Medicine*. 2026. (nature.com/articles/s41746-026-02799-9) **【已在线核实(Crossref确认题录)】**
- [R5] Grosicki, et al. Real-world effects of alcohol on heart rate, sleep, and physical activity by age and sex. *PLOS Digital Health*. 2026. DOI: 10.1371/journal.pdig.0001284. **【已在线核实(Crossref确认题录,2.1万人,女性/年轻人效应更大)】**
- [R6] Wearable-Derived Heart Rate Variability Across the Menstrual Cycle… A Living Systematic Review. *Sports Medicine*. 2026;56(5) (2026-01在线). DOI: 10.1007/s40279-025-02388-y. **【搜索结果确认存在,全文未核】**
- [R7] Apple RHR算法口径描述:基于Apple Health公开说明。**【未能在线核实,待验证】**
