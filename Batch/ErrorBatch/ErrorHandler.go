package main

import (
	"log"
	"time"
)

func main() {

	log.Printf("開始進行模擬錯誤批次@")

	time.Sleep(2 * time.Second)

	log.Printf("錯誤批次準備失敗 #")
	log.Printf(" 確認有用新版")

	time.Sleep(3 * time.Second)

	log.Fatalf("批次錯誤了！")
}
