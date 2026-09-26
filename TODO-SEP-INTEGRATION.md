# demo-go 作為 SEP 來源系統 — 代辦流程

> 目的：把 demo-go 從「單純 ArgoCD 展示專案」擴充成一個能實際呼叫 SEP（Serverless Execution Platform）
> `/api/run` 的來源系統，用來測試 SEP 的批次任務建立、配額、Job 生命週期。
> 對照 `serverless/README.md`「來源系統接入規範」章節。

## 0. 先清掉上一版的權宜改法

- [ ] `main.go` 目前有一個直接塞進去的 `runBatch()` / `batch` 子命令 —— 這是「被 SEP Job 執行的 workload」，
      不是「呼叫 SEP 的來源系統」，角色反了，先保留但不當作最終方案，等下面決定觸發 Job 要跑什麼 image
      後再決定去留（可能拆成獨立 `cmd/`，也可能整支移除）。

## 1. 決定專案結構：獨立的 batch 觸發程式

- [ ] 把 demo-go 從單一 `main.go` 改成多入口結構，例如：
      ```
      cmd/
        server/   ← 原本的 ArgoCD demo HTTP server（不動）
        source/   ← 新增：呼叫 SEP /api/run 的來源系統觸發程式
      ```
- [ ] `cmd/source` 的職責：
      1. 從自己 namespace 的 ConfigMap 讀 `current_image`（見第 4 節）
      2. 組 `RunRequest`（`system_id` / `task_id` / `image` / `command`）
      3. POST 到 `http://sep-engine-svc.<sep-namespace>.svc.cluster.local:8080/api/run`
      4. 印出 SEP 回傳的 `job_name`，方便追蹤
- [ ] **待確認**：SEP 建的 Job 實際要跑的 image/command 是什麼？
      - 選項 A：沿用 demo-go 自己（延續上一版的 batch 模式邏輯，image 就是 demo-go）
      - 選項 B：另外給一個極簡 task image（例如 busybox/python，類似 `flow.py` 的角色）
      - 先選一個最省事的走展示範例，不用糾結

## 2. Dockerfile

- [ ] 決定 build 策略：一支 Dockerfile 用 `--target` 分別建 `server` / `source` 兩個 image，
      還是乾脆拆兩支 Dockerfile（`Dockerfile.server` / `Dockerfile.source`）
- [ ] `source` image 只需要能對外發 HTTP request，不需要 K8s Job 建立權限（那是 SEP 的職責）

## 3. CI/CD：建置並推送 image 給 SEP 拉取

- [ ] 比照 `serverless/.github/workflows/CI-Build.yaml` 的模式（demo-go 現有的 `docker-publish.yml` 也可參考）：
      - Git commit short SHA 當 immutable tag（禁止 `:latest` / `:main`，見 README 規範）
      - push 到 SEP 叢集拉得到的 registry（GHCR，或跟 SEP 同一個 registry 帳號，避免 private repo 認證問題）
- [ ] CI 完成後**不要**直接更新 ConfigMap（見下一節，版本閘門要 CD 才動）

## 4. 來源端 ConfigMap（版本閘門）

- [ ] 在 demo-go 自己的 namespace（例如 `ns-demo-source`，待命名）建立 ConfigMap，內容比照 README 範例：
      ```yaml
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: demo-go-app-config
        namespace: ns-demo-source
      data:
        current_image: "demo-golang:git-<sha>"
      ```
- [ ] CD 階段才 `kubectl patch configmap` 更新 `current_image`，CI 階段嚴禁碰這個欄位
      （避免 SEP 排程觸發時跑到還沒驗證過的版本）

## 5. SEP 端要配合的事

- [ ] `serverless/charts/values.yaml` 的 `quotas.systems` 新增 `demo-go`（或決定的 system_id）條目，
      補齊 4 個 key：`cpu_request` / `memory_request` / `cpu_limit` / `memory_limit`
- [ ] 重新套用（`helm upgrade` 或直接 `kubectl apply` ConfigMap），確認：
      ```bash
      kubectl get configmap sep-system-quotas -n ns-sep -o jsonpath='{.data}'
      ```
      能看到新系統的 4 個 key
- [ ] 確認 `system_id`（≤40 字元）、`task_id`（≤63 字元，K8s label 限制）符合命名規則

## 6. Namespace / RBAC / 網路

- [ ] 決定 demo-go 的來源系統要不要獨立 namespace（建議要，隔離配額與權限）
- [ ] `cmd/source` 如果部署在叢集內，只需要讀「自己 namespace 的 ConfigMap」的權限：
      ```bash
      kubectl create role demo-source-reader --verb=get,list --resource=configmaps -n ns-demo-source
      kubectl create rolebinding demo-source-reader-binding \
        --role=demo-source-reader --serviceaccount=ns-demo-source:default -n ns-demo-source
      ```
      **不需要**建立/操作 K8s Job 的權限 —— 那是 SEP Engine 的職責，職責分離要守住
- [ ] 確認跨 namespace 呼叫 `sep-engine-svc` 沒有被 NetworkPolicy 擋（多數本機 OrbStack/Kind 環境預設沒有，正式叢集要另外確認）
- [ ] `IMAGE_PULL_POLICY`：SEP charts 目前預設 `Never`（只吃本機 image）。demo-go image 若從遠端 registry
      拉，SEP 那邊部署設定要改成 `IfNotPresent` / `Always`，且如果是 private repo 需要 `imagePullSecret`

## 7. 觸發方式

- [ ] 決定 `cmd/source` 怎麼被觸發：
      - K8s `CronJob`（模擬排程批次，最貼近 SEP README 講的 Prefect 情境）
      - 還是先留手動 `kubectl create job --from=cronjob/...` / 本機直接 `go run` 測試就好（展示範例階段夠用）

## 8. Helm（暫緩，非本階段必要）

- [ ] 展示範例階段：純手寫 K8s manifest（Namespace / ConfigMap / CronJob）+ 手動 `kubectl apply` 即可
- [ ] 之後要正式接 stg/prod GitOps 時，再比照 `serverless/charts/` 的 dev/stg/prod 分層結構補 Helm chart

## 9. 驗收測試

- [ ] `cmd/source` 手動觸發一次，確認 SEP 收到請求、建立 Job、Job 正常 Complete（非卡在 Running）
- [ ] 驗證配額有沒有套用正確（`kubectl describe job` 看 resource requests/limits）
- [ ] 驗證 TTL 回收（`ttlSecondsAfterFinished: 300s`）
- [ ] 之前寫的 `serverless/test/sourceSystemBatchTest.sh`（bash 版批次觸發腳本）先留著當快速手動 smoke test，
      等 `cmd/source` 正式落地後再評估要不要取代掉
