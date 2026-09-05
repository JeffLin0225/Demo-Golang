# Demo-Golang

> 一個輕量、高內聚的雲原生 HTTP 服務示範專案，專為展示基於 ArgoCD、GitHub Actions 與 Kubernetes 的宣告式 GitOps 持續交付（Continuous Delivery）架構而設計。

---

## 系統架構

本專案採用成熟的雙倉庫（Two-Repository）GitOps 架構模式：應用程式開發庫（`Demo-Golang`）專注於程式碼迭代與自動化映像檔建置，環境宣告庫（`Kubernetes-ArgoCD`）專注於叢集期望狀態（Desired State）的管理。當 CI 流程通過時，自動透過短 SHA 版號回寫部署配置，並由 ArgoCD 自動調和至 Kubernetes 叢集。

```mermaid
flowchart TD
    %% 樣式定義
    classDef clientStyle fill:#E3F2FD,stroke:#1565C0,stroke-width:2px,color:#0D47A1;
    classDef ciStyle fill:#EDE7F6,stroke:#512DA8,stroke-width:2px,color:#311B92;
    classDef repoStyle fill:#FFF3E0,stroke:#E65100,stroke-width:2px,color:#BF360C;
    classDef argoStyle fill:#E0F2F1,stroke:#00695C,stroke-width:2px,color:#004D40;
    classDef k8sStyle fill:#E8F5E9,stroke:#2E7D32,stroke-width:2px,color:#1B5E20;
    classDef probeStyle fill:#FFFDE7,stroke:#F57F17,stroke-width:2px,stroke-dasharray: 5 5,color:#F57F17;

    subgraph TriggerLayer ["觸發與原始碼層 (Trigger & Source Layer)"]
        Dev["👤 開發者 (Developer)<br/>Git Commit & Push / Manual Dispatch"]
        SourceRepo["📦 應用原始碼庫 (App Repo)<br/>JeffLin0225/Demo-Golang"]
    end

    subgraph CIPipeline ["持續整合管線 (CI Pipeline - GitHub Actions)"]
        GHA["⚙️ GitHub Actions Runner<br/>.github/workflows/docker-publish.yml"]
        QEMU["🛠️ QEMU & Docker Buildx<br/>Multi-Arch: linux/amd64, linux/arm64"]
        Vars["🏷️ Short SHA 產生器<br/>git rev-parse --short HEAD"]
    end

    subgraph RegistryLayer ["製品庫與宣告庫 (Registry & GitOps Manifest)"]
        DockerHub["🐳 Docker Hub Image Registry<br/>${DOCKERHUB_USERNAME}/demo-golang:latest<br/>${DOCKERHUB_USERNAME}/demo-golang:${SHORT_SHA}"]
        GitOpsRepo["📄 GitOps 部署配置庫 (CD Repo)<br/>JeffLin0225/Kubernetes-ArgoCD<br/>deployment.yml"]
    end

    subgraph CDControlPlane ["持續部署控制面 (GitOps Control Plane)"]
        ArgoCD["🐙 ArgoCD 控制器 (GitOps Controller)<br/>Reconciliation Loop & State Diff"]
    end

    subgraph K8sCluster ["運作環境層 (Kubernetes Cluster: Production)"]
        Deploy["🚀 Deployment (Demo App Pods)<br/>Port: 8080 | ENV: APP_VERSION, BG_COLOR"]
        Kubelet["🛡️ K8s Kubelet Probes<br/>Liveness / Readiness Probe<br/>GET /health (HTTP 200 OK)"]
        User["🌐 終端使用者 / 瀏覽器<br/>HTTP GET / (HTML 渲染)"]
    end

    %% 主 CI/CD 流程
    Dev -->|1. 觸發 workflow_dispatch / push| SourceRepo
    SourceRepo -->|2. 觸發 CI 工作流| GHA
    GHA -->|3. 初始化多架構環境| QEMU
    GHA -->|4. 擷取 Git Commit 短版號| Vars
    QEMU & Vars -->|5. 建置並推送雙架構映像檔| DockerHub
    GHA -->|6. SSH Deploy Key 自動修改 deployment.yml 並 Commit Push| GitOpsRepo

    %% GitOps 同步與部署流程
    GitOpsRepo -.->|7. 輪詢偵測 / Webhook 差異偵測 (Git Diff)| ArgoCD
    ArgoCD -->|8. 發起宣告式同步 (Sync Application)| Deploy
    Deploy -->|9. 拉取指定版本映像檔 (${SHORT_SHA})| DockerHub

    %% 背景治理與終端流量流程
    Kubelet -.->|A. 定期存活與就緒探針檢查| Deploy
    User -->|B. 訪問 Web 首頁 (Port: 8080)| Deploy

    %% 套用樣式
    class Dev,User clientStyle;
    class GHA,QEMU,Vars ciStyle;
    class SourceRepo,GitOpsRepo,DockerHub repoStyle;
    class ArgoCD argoStyle;
    class Deploy k8sStyle;
    class Kubelet probeStyle;
```

---

## 專案結構

```
.
├── .github/
│   └── workflows/
│       └── docker-publish.yml  # GitHub Actions 自動化腳本：負責 Multi-Arch 編譯、Docker Hub 推送及回寫 CD 倉庫
├── Dockerfile                  # 多階段 (Multi-Stage) 建置配置：隔離 Golang 編譯與極簡 Alpine 執行環境
├── go.mod                      # Go 模組設定檔 (宣告 Go 1.25.5 版本規範)
├── main.go                     # HTTP 服務核心：註冊首頁動態 HTML 與 /health 健康檢查探針端點
└── README.md                   # 專案架構指南與操作手冊
```

---

## 事前準備

### 本機開發環境
- **Go 執行環境**：Go 1.25.5 或相容版本
- **容器建置工具**：Docker 20.10+ / Docker Buildx
- **Kubernetes 環境**（可選）：Minikube / k3s / Kind 或正式 K8s 叢集

### GitHub Secrets 配置需求
若要執行完整的 CI/CD 工作流，需於 GitHub Repository 設定以下 Secrets：
- `DOCKERHUB_USERNAME`：Docker Hub 帳號
- `DOCKERHUB_TOKEN`：Docker Hub Access Token
- `ARGOCD_GITOPS_KEY`：具備 `JeffLin0225/Kubernetes-ArgoCD` 倉庫寫入權限的 SSH 私鑰（Deploy Key）

---

## 啟動方式

### 1. 本機原生啟動
```bash
go run main.go
```
預設伺服器將在 `http://localhost:8080` 啟動。

### 2. Docker 容器化建置與執行
```bash
# 建置容器映像檔
docker build -t demo-golang:local .

# 啟動容器並注入環境變數
docker run -d -p 8080:8080 \
  -e APP_VERSION="v1.2.0" \
  -e BG_COLOR="#E8F5E9" \
  demo-golang:local
```

---

## API 規格

| 方法 | 路徑 | 狀態碼 | 回應類型 | 說明 |
| :--- | :--- | :--- | :--- | :--- |
| `GET` | `/` | `200 OK` | `text/html` | 動態渲染首頁，顯示版本號（`APP_VERSION`）、背景顏色（`BG_COLOR`）與伺服器當前同步時間 |
| `GET` | `/health` | `200 OK` | `text/plain` | 輕量健康檢查端點（回傳 `ok`），供 Kubernetes Liveness / Readiness Probes 探針調用 |

---

## 環境變數

應用程式完全依循 12-Factor App 原則，所有環境差異均由環境變數注入控制：

| 變數名稱 | 說明 | 預設值 | 容器 / 生產範例 |
| :--- | :--- | :--- | :--- |
| `APP_VERSION` | 網頁上呈現的應用程式版本標籤 | `v1` | `v2.0.1` 或短 Git SHA |
| `BG_COLOR` | 網頁視覺背景色彩（支援 CSS 顏色代碼或 Hex） | `white` | `#1A237E` / `lightblue` |

---

## CI/CD 與 GitOps 自動化流程

1. **多架構建置（Multi-Arch Build）**：
   - 透過 `docker/setup-qemu-action` 與 `docker/setup-buildx-action` 同時交叉編譯 `linux/amd64` 與 `linux/arm64` 映像檔，完美相容 x86 伺服器與 Apple Silicon / AWS Graviton 節點。
2. **不可變標籤（Immutable Tagging）**：
   - 每一次建置均以 `git rev-parse --short HEAD` 產出唯一短 SHA，並推送 `:latest` 與 `:${SHORT_SHA}` 至 Docker Hub。
3. **宣告式狀態回寫（Declarative Manifest Update）**：
   - 透過 SSH 私鑰自動 Clone 部署庫 `JeffLin0225/Kubernetes-ArgoCD`。
   - 使用 `sed` 自動替換 `deployment.yml` 內的映像檔版本為對應短 SHA，提交並推回主分支。
4. **ArgoCD 自動調和（Reconciliation Loop）**：
   - ArgoCD 偵測到部署倉庫變更後，觸發 Out-of-Sync 狀態偵測，執行 Automated Sync 將新 Pod Rolling Update 至叢集內。

---

## 常用維運指令

### Kubernetes 叢集狀態確認
```bash
# 查看 Pod 運行狀態與版本標籤
kubectl get pods -l app=demo-golang -o wide

# 即時檢視 Pod 存活探針與日誌輸出
kubectl logs -f -l app=demo-golang --tail=100

# 查看目前 Deployment 的映像檔版本
kubectl get deployment demo-golang -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### 手動觸發 CI/CD 工作流
至 GitHub 專案庫的 **Actions** 頁面 ➔ 選擇 **(Manual Trigger)Build and Push to Docker Hub** ➔ 點選 **Run workflow**。
