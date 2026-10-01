package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

// 支援的批次種類，key 要跟 scripts/common.sh 的 BATCH_TARGETS、
// 以及各 image 的 repo 名稱（emailbatch / linebatch / errorbatch）保持一致，
// 呼叫端送的 batch_kind 直接對應這裡的 key，才不會多一層翻譯造成誤解。
const (
	batchKindEmail = "emailbatch"
	batchKindLine  = "linebatch"
	batchKindError = "errorbatch"
)

func main() {
	if err := godotenv.Load(); err != nil {
		fmt.Println("[INFO] 未找到 .env 檔，使用系統環境變數")
	}

	// Service 自己監聽的 port。容器裡固定是 8080（k8s Service/Dockerfile 都寫死這個），
	// 不受影響；這裡可覆蓋純粹是因為本機 8080 可能被別的東西佔用
	// （例如 OrbStack 自己常駐在 127.0.0.1:8080），本機開發時用 .env 的 PORT 換一個就好。
	port := getEnv("PORT", "8080")

	sepEndpoint := getEnv("SEP_ENDPOINT", "http://sep-engine-svc.ns-sep-stg.svc.cluster.local:8080/api/run")
	systemID := getEnv("SYSTEM_ID", "demo-go")
	// Job 要建在哪個 namespace，留空則由 SEP 決定（會落在 SEP 自己的 namespace）
	jobNamespace := getEnv("JOB_NAMESPACE", "")

	// 三支 batch 的 image 各自一個環境變數，由 CD 在部署時同時灌入
	// （ci.sh 本來就每次都會把三支一起建好，tag 一致）。
	// 呼叫端用 batch_kind 選其中一支，Service 自己不組 image 字串，
	// 避免呼叫端能透過參數注入任意 registry/tag。
	batchImages := map[string]string{
		batchKindEmail: getEnv("BATCH_IMAGE_EMAILBATCH", ""),
		batchKindLine:  getEnv("BATCH_IMAGE_LINEBATCH", ""),
		batchKindError: getEnv("BATCH_IMAGE_ERRORBATCH", ""),
	}

	r := gin.Default()

	api := r.Group("/api")
	{
		api.POST("/callsep", func(c *gin.Context) {
			// body 本身可以用各種形式省略欄位，但 BatchKind 是必填（見下面的檢查），
			// 所以這裡故意忽略 ShouldBindJSON 的 error（空 body 會回傳 EOF，交給
			// 下面 in.BatchKind == "" 統一處理成看得懂的錯誤訊息）。
			var in CallSepRequest
			_ = c.ShouldBindJSON(&in)

			// batch_kind 沒有預設值，刻意不猜。沒帶就是呼叫端的錯，直接 400，
			// 不要讓「忘了帶」被悄悄當成「要跑 emailbatch」。
			if in.BatchKind == "" {
				c.JSON(http.StatusBadRequest, gin.H{
					"error":   "batch_kind 為必填，不會使用預設值",
					"allowed": []string{batchKindEmail, batchKindLine, batchKindError},
				})
				return
			}

			image, known := batchImages[in.BatchKind]
			if !known {
				c.JSON(http.StatusBadRequest, gin.H{
					"error":   "未知的 batch_kind: " + in.BatchKind,
					"allowed": []string{batchKindEmail, batchKindLine, batchKindError},
				})
				return
			}
			if image == "" {
				c.JSON(http.StatusInternalServerError, gin.H{
					"error": fmt.Sprintf("batch_kind=%s 對應的 image 尚未設定（環境變數 BATCH_IMAGE_%s 缺失）",
						in.BatchKind, in.BatchKind),
				})
				return
			}

			req := RunRequest{
				SystemID:  systemID,
				TaskID:    fmt.Sprintf("%s-%d", systemID, time.Now().Unix()),
				Namespace: jobNamespace,
				Image:     image,
			}

			// 物件轉換為 json []byte
			payload, err := json.Marshal(req)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}

			// NewReader:  將 json []byte -> io.Reader 轉為要求的介面
			resp, err := http.Post(sepEndpoint, "application/json", bytes.NewReader(payload))
			if err != nil {
				c.JSON(http.StatusBadGateway, gin.H{"error": "呼叫 SEP 失敗: " + err.Error()})
				return
			}

			// 強制 realse io
			defer resp.Body.Close()

			// io.Reader -> []bytes
			body, err := io.ReadAll(resp.Body)
			if err != nil {
				c.JSON(http.StatusBadGateway, gin.H{"error": "讀取 SEP 回應失敗: " + err.Error()})
				return
			}

			// 狀態碼要在解析之前檢查。SEP 失敗時回的是 {"status","error"}，
			// 跟成功的格式不同，硬塞進 RunResponse 會得到一個空殼並偽裝成成功。
			// 這裡直接把原始 body 往上拋，SEP 的錯誤訊息才不會在轉換過程中被吃掉。
			if resp.StatusCode != http.StatusOK {
				c.JSON(http.StatusBadGateway, gin.H{
					"error":      "SEP 回傳錯誤",
					"sep_status": resp.StatusCode,
					"sep_body":   string(body),
				})
				return
			}

			var sepResp RunResponse
			if err := json.Unmarshal(body, &sepResp); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "解析 SEP 回應失敗: " + err.Error()})
				return
			}

			c.JSON(http.StatusOK, sepResp)
		})
	}

	r.Run(":" + port)
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// CallSepRequest 是呼叫端打 /api/callsep 時要帶的 body。
type CallSepRequest struct {
	// 要觸發哪一種批次：emailbatch / linebatch / errorbatch，必填，
	// 沒有預設值，不帶或帶未知的值都會回 400。
	BatchKind string `json:"batch_kind"`
}

type RunRequest struct {
	SystemID  string   `json:"system_id"`
	TaskID    string   `json:"task_id"`
	Namespace string   `json:"namespace,omitempty"`
	Image     string   `json:"image"`
	Command   []string `json:"command,omitempty"`
}

type RunResponse struct {
	Status  string `json:"status"`
	Message string `json:"message"`
	JobName string `json:"job_name"`
}
