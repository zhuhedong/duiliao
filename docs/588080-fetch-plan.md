# 588080 采集平台扩展方案

> 目标：把 588080 / 顶尖大师从「一个源一个脚本」升级为 **可发现 + 可调度 + 可补洞 + 可观测** 的采集平台。  
> 安全底线：不放开任意 host、不开放公开注册、生产默认关闭脚本写入/执行，HTTP 重定向逐跳校验继续生效。

## 现状摘要

| 能力 | 现状 |
|------|------|
| 入口解析 | `fetch_588080` / `dingjian.discover_api_hosts`：entry → jump → am.js → API 集群 |
| Host 缓存 | 文件缓存 `out/source-catalog/hosts.json`，无统一健康检查服务与 API |
| 异步采集 | `collect_job` + `/app/collect-jobs` + APP 进度轮询已落地 |
| 栏目巡检 | `source_catalog` / `site_catalog`：scan、diff、reconcile（干跑/停用） |
| 模板源 | `registry._render_dynamic_site_template` + `extra.upstream_id` + 已验收 parser |
| 全页 dump | `POST /collector/site-dump/588080`（员工），落盘到 `collector/html` |
| AI | 分析可 `fetch_fresh` 或读文件；APP「抓取上下文」此前为本地占位 |
| 缺期 | `confirm_missing` 把缺期记为挂；缺少「按缺期再采」的回填任务 |

## 三期目标

### 一期：稳定底座（本 PR 必交付）

1. **Host 池服务**  
   - 解析 entry → jump → am.js，健康检查 `/api/v1/index/website/config`  
   - 活跃 base 写入 Setting（`dingjian_host_pool`）+ 文件缓存  
   - API：`GET/POST /collector/host-pool`、`POST .../refresh`  
   - 源脚本 `dj_util.api_hosts()` 优先读池内主机  

2. **异步采集任务**（已有，本 PR 加固）  
   - 继续用 `collect_job`；同步 `POST /collector/collect` 保留为薄封装  
   - 任务进度按源更新；取消/中断语义不变  

3. **抓取观测日志**  
   - 表 `fetch_observation`：source / lottery / period / url / status / 耗时 / content_hash / error / job_id  
   - 采集完成回调写入；`GET /collector/fetch-observations` 查询  

4. **安全**  
   - site-dump 仍仅员工；host 须过 SSRF 校验  
   - 重定向逐跳 `assert_safe_url` 不变  

### 二期：目录驱动（本 PR 尽量交付）

1. **栏目同步与建议**  
   - `GET /collector/catalog/suggestions`：基于最近 scan 的 pending / missing / renamed  
   - 建议「接入新栏」与「停用已消失」；真正改配置仍走 reconcile / 人工确认  

2. **通用模板抓取**  
   - 同类玩法用 `upstream_id` + 已验收 `parser` 生成脚本（现有路径）  
   - 文档化配置约定；Host 池接入 `urls_for`  

3. **全页 dump TTL 缓存**  
   - 最新快照指针 + TTL（默认 30 分钟）  
   - `GET /collector/site-dump/588080/latest`；AI / APP 优先读缓存  

### 三期：智能补洞与产品化（本 PR 最小可用）

1. **缺期回填任务**  
   - `POST /collector/backfill-jobs`：扫描缺预测的源，提交异步 `collect_job`  
   - `GET .../backfill-jobs/preview`：只预览不提交  

2. **APP**  
   - 采集页继续走异步 job（已有）  
   - AI「抓取上下文」改为读取服务端 dump 缓存摘要  

3. **监控字段**  
   - Host 池记录连续失败次数、上次成功时间  
   - 观测日志支持按 content_hash 变化筛查  

## 验收标准

- [x] 入口挂掉后，刷新 Host 池可在数分钟内切到备用 base（不依赖发版）  
- [x] 新栏目：scan → suggestions 可见，不强制写脚本也能看见 pending  
- [x] 单期全量采集：有 job id + 实时进度，APP 不超时  
- [x] 缺期回填：preview + 提交 job，结果可对账  
- [x] AI / APP 可在 TTL 内复用 dump，而不必每次外连  
- [x] 相关 pytest 覆盖 Host 池、观测写入、SSRF、回填预览  

## 明确不做

- 不对普通用户开放任意 `host`  
- 生产不默认开放注册 / 脚本 RCE  
- 不以无头浏览器为默认采集路径  
- 不在客户端做重采集，一律走后端任务  

## 本 PR 范围说明

见 Pull Request 描述：**已交付 vs 后续跟进**。


## 跟进交付（PR #3）

1. **Host 池后台探测**  
   - `HostPoolScheduler`：默认每 15 分钟 `probe()`（最短 5 分钟）  
   - 全挂时才 `refresh()` 重新发现  
   - API：`GET /collector/host-pool/scheduler`、`POST /collector/host-pool/probe`

2. **目录批量启用**  
   - `POST /collector/catalog/batch-enable`（员工，需 `confirm=true`）  
   - `create_source` 必须 `upstream_id` + 已验收 `parser`；禁止盲开未知 parser  
   - 写脚本仍受 `WRITE_SCRIPT_ENABLED` 约束

3. **通知钩子**  
   - `fetch_hash_changed` / `fetch_fail_streak` 进入 `GET /app/events`  
   - APP `NotifyRule` / `AppEventType` 已同步

4. **APP 采集进度**  
   - 已走异步 `collect-jobs` + `jobProgressProvider` 轮询（本跟进确认完整）
