package main

import (
	"fmt"
	"net/http"
	"os"
	"time"
)

func main() {
	// 設定監聽 Port
	port := "8080"

	// 定義首頁路由
	version := os.Getenv("APP_VERSION")
	if version == "" {
		version = "v1"
	}

	bgColor := os.Getenv("BG_COLOR")
	if bgColor == "" {
		bgColor = "white"
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		fmt.Fprintf(w, `
            <body style="background-color: %s; font-family: sans-serif; text-align: center; padding-top: 50px;">
                <h1>ArgoCD Demo: %s</h1>
                <p>I am Pod: <span style="color: red; font-weight: bold;">%s</span></p>
                <p>Sync Time: %s</p>
            </body>
        `, bgColor, version, time.Now().Format("15:04:05"))
	})

	// 健康檢查路由 (ArgoCD 判斷 Pod 是否存活用)
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	fmt.Printf("🚀 Server is starting at http://localhost:%s\n", port)

	// 啟動 Server
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		fmt.Printf("Error starting server: %s\n", err)
		os.Exit(1)
	}
}
