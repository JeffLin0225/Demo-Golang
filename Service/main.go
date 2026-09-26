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

	sepEndpoint := getEnv("SEP_ENDPOINT", "http://sep-engine-svc.ns-sep.svc.cluster.local:8080/api/run")
	systemID := getEnv("SYSTEM_ID", "demo-go")
	batchImage := getEnv("BATCH_IMAGE", "")

	r := gin.Default()

	api := r.Group("/api")
	{
		api.POST("/callsep", func(c *gin.Context) {
			req := RunRequest{
				SystemID: systemID,
				TaskID:   fmt.Sprintf("%s-%d", systemID, time.Now().Unix()),
				Image:    batchImage,
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
			body, _ := io.ReadAll(resp.Body)
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
