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

func main() {
	if err := godotenv.Load(); err != nil {
		fmt.Println("[INFO] 未找到 .env 檔，使用系統環境變數")
	}

	sepEndpoint := getEnv("SEP_ENDPOINT", "http://sep-engine-svc.ns-sep-stg.svc.cluster.local:8080/api/run")
	systemID := getEnv("SYSTEM_ID", "demo-go")
	batchImage := getEnv("BATCH_IMAGE", "")
	// Job 要建在哪個 namespace，留空則由 SEP 決定（會落在 SEP 自己的 namespace）
	jobNamespace := getEnv("JOB_NAMESPACE", "")

	r := gin.Default()

	api := r.Group("/api")
	{
		api.POST("/callsep", func(c *gin.Context) {
			req := RunRequest{
				SystemID:  systemID,
				TaskID:    fmt.Sprintf("%s-%d", systemID, time.Now().Unix()),
				Namespace: jobNamespace,
				Image:     batchImage,
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

	r.Run(":8080")
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
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
